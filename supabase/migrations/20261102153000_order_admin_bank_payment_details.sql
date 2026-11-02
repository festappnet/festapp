-- Read-only admin payment destination metadata; no payment or email writes.
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
  -- Authorized admin metadata stays readable after payment. Never issue or
  -- regenerate instructions as a side effect of viewing an order.
  'bankPaymentDetails',(SELECT jsonb_build_object(
    'account',coalesce(b.account_number_human_readable,b.account_number),
    'iban',b.account_number,'creditorName',b.creditor_name,
    'referenceKind',CASE WHEN o.currency_code='EUR' THEN 'RF' ELSE 'VS' END,
    'reference',CASE WHEN o.currency_code='EUR' THEN pi.creditor_reference ELSE pi.variable_symbol::text END)
    FROM eshop.payment_info pi JOIN eshop.bank_accounts b ON b.id=pi.bank_account
    WHERE pi.id=o.payment_info AND pi.payment_method='bank'
      AND pi.currency_code=o.currency_code),
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
