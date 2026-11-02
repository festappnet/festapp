-- Exact-order read projection. This fingerprint is a read consistency token,
-- never authorization or a command fence. No registry, trigger, locks or writes.
CREATE OR REPLACE FUNCTION public.order_admin_places_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH own AS (
  SELECT x.id item_id,x.ticket,x.product,o.occasion,o.form,o.state order_state,t.state ticket_state,
   count(*) FILTER (WHERE pt.type='spot') OVER(PARTITION BY x.ticket) primary_count,
   pt.type product_type
  FROM eshop.orders o JOIN eshop.order_product_ticket x ON x."order"=o.id
  JOIN eshop.tickets t ON t.id=x.ticket AND t.occasion=o.occasion
  JOIN eshop.products p ON p.id=x.product AND p.occasion=o.occasion
  JOIN eshop.product_types pt ON pt.id=p.product_type WHERE o.id=p_order
 ), places AS (
 SELECT x.*,s.id spot_id,coalesce(s.blueprint,ab.blueprint) blueprint_id,
 coalesce(sb.node_id,ab.node_id) node_id,sb.group_node,sb.selection_unit,
 s.title,coalesce(sb.blocked,false) blocked,ab.node_id IS NOT NULL standing,
 (SELECT count(*) FROM eshop.spots sp WHERE sp.order_product_ticket=x.item_id AND sp.blueprint IS NOT NULL) addressed_count,
 EXISTS(SELECT 1 FROM eshop.order_product_ticket other WHERE other.ticket=x.ticket AND other."order"<>p_order) foreign_order,
 b.layout,
 EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(b.layout->'nodes','[]')) n WHERE n->>'id'=coalesce(sb.node_id,ab.node_id)::text) has_node,
 (SELECT n->>'label' FROM jsonb_array_elements(coalesce(b.layout->'nodes','[]')) n WHERE n->>'id'=sb.group_node::text) group_title,
 (SELECT n->>'label' FROM jsonb_array_elements(coalesce(b.layout->'nodes','[]')) n WHERE n->>'id'=coalesce(sb.node_id,ab.node_id)::text) node_title
 FROM own x JOIN eshop.spots s ON s.order_product_ticket=x.item_id AND s.occasion=x.occasion
 LEFT JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id AND sb.blueprint=s.blueprint
 LEFT JOIN public.forms f ON f.id=x.form AND f.occasion=x.occasion
 LEFT JOIN eshop.blueprint_area_bindings ab ON s.blueprint IS NULL AND ab.inventory_context=s.inventory_context AND ab.product=x.product
   AND (ab.blueprint=f.blueprint OR EXISTS(SELECT 1 FROM public.form_seating_transitions tr WHERE tr.form=f.id AND tr.blueprint=ab.blueprint AND tr.state='organizer_managed'))
 LEFT JOIN eshop.blueprints b ON b.id=coalesce(s.blueprint,ab.blueprint) AND b.occasion=x.occasion
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'spotId',spot_id,'ticketId',ticket,'admissionItemId',item_id,'productId',product,
  'blueprintId',blueprint_id,'nodeId',node_id,'groupNodeId',group_node,'selectionUnitId',selection_unit,
  'title',coalesce(node_title,title),'groupTitle',group_title,'standing',standing,
  'active',ticket_state NOT IN ('storno','waitlisted') AND order_state NOT IN ('storno','stock','waitlisted')
    AND primary_count=1 AND NOT foreign_order AND NOT blocked AND (standing OR addressed_count=1) AND has_node,
  'problem',CASE WHEN primary_count<>1 OR foreign_order OR addressed_count>1 THEN 'ADMISSION_DATA_AMBIGUOUS'
    WHEN ticket_state='storno' OR order_state='storno' THEN 'HISTORICAL'
    WHEN NOT has_node THEN 'PLACE_NOT_IN_CURRENT_PLAN' WHEN blocked THEN 'BLOCKED' END
 ) ORDER BY item_id,spot_id,node_id),'[]') FROM places;
$$;
REVOKE ALL ON FUNCTION public.order_admin_places_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_order_admin_detail(p_order bigint,p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; places jsonb; tickets jsonb; plans jsonb; actions jsonb; tr uuid;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 IF o.id IS NULL OR o.occasion IS DISTINCT FROM p_occasion OR public.can_read_orders(o.occasion) IS NOT TRUE THEN
  RETURN jsonb_build_object('code',404,'message','Order unavailable'); END IF;
 places:=public.order_admin_places_internal(o.id);
 actions:=public.get_order_allowed_actions_internal_v1(o.id);
 SELECT id INTO tr FROM public.form_seating_transitions WHERE form=o.form AND state='organizer_managed';
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'ticket_symbol',t.ticket_symbol,'state',t.state,
  'note',t.note,'note_hidden',t.note_hidden,'data',t.data,
  'snapshot',coalesce((SELECT v FROM jsonb_array_elements(coalesce(o.data->'tickets','[]')) v WHERE v->>'id'=t.id::text),
    (SELECT v FROM eshop.orders_history h CROSS JOIN LATERAL jsonb_array_elements(coalesce(h.data->'tickets','[]')) v
     WHERE h."order"=o.id AND v->>'id'=t.id::text ORDER BY h.created_at DESC,h.id DESC LIMIT 1)),
  'items',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',x.id,'productId',x.product) ORDER BY x.id),'[]') FROM eshop.order_product_ticket x WHERE x."order"=o.id AND x.ticket=t.id),
  'admission',CASE WHEN tr IS NOT NULL THEN (SELECT jsonb_build_object('category',a.category,'reason',a.reason) FROM public.seating_admissions_internal(tr) a WHERE a.order_id=o.id AND a.ticket_id=t.id) END,
  'batch',(SELECT jsonb_build_object('id',i.batch_id,'title',b.title,'ordinal',i.ordinal) FROM eshop.ticket_batch_items i JOIN eshop.ticket_batches b ON b.id=i.batch_id WHERE i.ticket_id=t.id)
 ) ORDER BY t.id),'[]') INTO tickets FROM eshop.tickets t
 WHERE t.occasion=o.occasion AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=t.id AND x."order"=o.id);
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'title',b.title,'layoutRevision',b.layout_revision) ORDER BY b.id),'[]') INTO plans
 FROM eshop.blueprints b WHERE b.occasion=o.occasion AND EXISTS(SELECT 1 FROM jsonb_array_elements(places) v WHERE v->>'blueprintId'=b.id::text);
 RETURN jsonb_build_object('code',200,'data',jsonb_build_object(
  'order',jsonb_build_object('id',o.id,'occasion',o.occasion,'form_id',o.form,'order_symbol',o.order_symbol,'order_sequence',o.order_sequence,
   'created_at',o.created_at,'updated_at',o.updated_at,'state',o.state,'price',o.price,'currency_code',o.currency_code,
   'data',o.data,'note_hidden',o.note_hidden,'allowedActions',actions,'email_payment_version',o.email_payment_version,
   'email_payment_fingerprint',public.order_email_payment_fingerprint(o.id),
   'payment_method',(SELECT payment_method FROM eshop.payment_info WHERE id=o.payment_info)),
  'capabilities',jsonb_build_object('write',coalesce(public.can_write_orders(o.occasion),false),'allowedActions',actions),
  'payment',public.customer_order_payment_internal(o.id)-'transactions',
  'waitlistSummary',CASE WHEN o.state='waitlisted' OR o.source_waitlist_order_id IS NOT NULL THEN public.get_waitlist_summary_internal(o.id) END,
  'tickets',tickets,'places',places,'placesComplete',true,'plans',plans,
  'placementFingerprint',md5(jsonb_build_object('order',o.id,'state',o.state,'form',o.form,'transition',tr,'places',places,'tickets',tickets)::text),
  'form',(SELECT jsonb_build_object('id',f.id,'title',f.title) FROM public.forms f WHERE f.id=o.form AND f.occasion=o.occasion),
  'fields',(SELECT coalesce(jsonb_agg(to_jsonb(ff)||jsonb_build_object('product_type_data',
    CASE WHEN pt.id IS NOT NULL THEN jsonb_build_object('id',pt.id,'title',pt.title,'description',pt.description,'type',pt.type) END)
    ORDER BY ff."order",ff.id),'[]') FROM public.form_fields ff
    LEFT JOIN eshop.product_types pt ON pt.id=ff.product_type AND pt.occasion=o.occasion WHERE ff.form=o.form),
  'productCategories',(SELECT coalesce(jsonb_object_agg(p.id::text,p.product_type),'{}') FROM eshop.products p
    WHERE p.occasion=o.occasion AND EXISTS(SELECT 1 FROM jsonb_array_elements(tickets) t
      CROSS JOIN LATERAL jsonb_array_elements(coalesce(t#>'{snapshot,products}','[]')) pr WHERE pr->>'id'=p.id::text)),
  'answers',coalesce(o.data->'fields','[]'),
  'emailSummary',public.get_order_email_summary(o.id)
 ));
END $$;
REVOKE ALL ON FUNCTION public.get_order_admin_detail(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_order_admin_detail(bigint,bigint) TO authenticated;
