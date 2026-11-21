-- Catalog type and persisted links own admission identity. Snapshot type is
-- also checked so a stale or damaged snapshot cannot silently lose an entry.
CREATE OR REPLACE FUNCTION public.ticket_admission_integrity_internal(
  p_order bigint, p_ticket bigint
)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH scope AS (
   SELECT o.id, o.occasion, o.data, t.occasion AS ticket_occasion
   FROM eshop.orders o CROSS JOIN eshop.tickets t WHERE o.id=p_order AND t.id=p_ticket
 ), links AS (
   SELECT x.id, x.product, x."order", p.occasion, pt.type, pt.occasion AS type_occasion
   FROM eshop.order_product_ticket x
   LEFT JOIN eshop.products p ON p.id=x.product
   LEFT JOIN eshop.product_types pt ON pt.id=p.product_type WHERE x.ticket=p_ticket
 ), linked AS (
   SELECT coalesce(array_agg(product ORDER BY product) FILTER (WHERE type='spot'),'{}') AS ids,
     coalesce(bool_or(l."order"<>s.id OR (l.type='spot' AND
       (l.occasion IS DISTINCT FROM s.occasion OR l.type_occasion IS DISTINCT FROM s.occasion))
       OR (l.type IS DISTINCT FROM 'spot' AND EXISTS (
         SELECT 1 FROM eshop.spots sp WHERE sp.order_product_ticket=l.id AND sp.blueprint IS NOT NULL))),false) AS invalid
   FROM links l CROSS JOIN scope s
 ), ticket_snapshot AS (
   SELECT t FROM scope s CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(s.data->'tickets')='array' THEN s.data->'tickets' ELSE '[]' END) t
   WHERE t->>'id'=p_ticket::text
 ), snapshot AS (
   SELECT coalesce(array_agg(p.id ORDER BY p.id),'{}') AS ids,
     coalesce(bool_or(pt.type IS DISTINCT FROM 'spot' OR
       (j ? 'order_product_ticket_id' AND NOT EXISTS (
         SELECT 1 FROM links l WHERE l.product=p.id AND l.id::text=j->>'order_product_ticket_id'))),false) AS invalid
   FROM ticket_snapshot ts CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(ts.t->'products')='array' THEN ts.t->'products' ELSE '[]' END) j
   LEFT JOIN eshop.products p ON p.id::text=j->>'id'
   LEFT JOIN eshop.product_types pt ON pt.id=p.product_type
   WHERE pt.type='spot' OR j->>'type'='spot'
 )
 SELECT jsonb_build_object('productIds',linked.ids,
   'spotCount',greatest(cardinality(linked.ids),cardinality(snapshot.ids)),
   'reason',CASE WHEN s.occasion IS DISTINCT FROM s.ticket_occasion
     OR linked.invalid OR snapshot.invalid OR (SELECT count(*) FROM ticket_snapshot)<>1
     OR cardinality(linked.ids)>1 OR linked.ids IS DISTINCT FROM snapshot.ids
     OR EXISTS(SELECT 1 FROM links l JOIN eshop.spots sp ON sp.order_product_ticket=l.id
       WHERE l.type='spot' AND sp.blueprint IS NOT NULL GROUP BY l.id
       HAVING count(*)>1 OR bool_or(sp.product IS DISTINCT FROM l.product OR sp.occasion IS DISTINCT FROM s.occasion))
     THEN 'ADMISSION_DATA_AMBIGUOUS' END)
 FROM scope s CROSS JOIN linked CROSS JOIN snapshot
$$;
REVOKE ALL ON FUNCTION public.ticket_admission_integrity_internal(bigint,bigint)
  FROM PUBLIC,anon,authenticated,service_role;

-- Visibility and execution use the same order/ticket eligibility rules.
CREATE OR REPLACE FUNCTION public.order_admission_blocker_internal(p_order bigint,p_ticket bigint)
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT CASE
   WHEN f.id IS NULL OR o.state NOT IN ('created','ordered','paid','sent') OR pi.id IS NULL
     OR o.price IS NULL OR pi.amount IS DISTINCT FROM o.price OR pi.currency_code IS DISTINCT FROM o.currency_code
     OR pi.payment_method IS DISTINCT FROM 'bank' AND
       (p_ticket IS NULL OR NOT public.payment_method_is_online_internal(pi.payment_method))
     THEN 'ORDER_ADMISSION_UNAVAILABLE'
   WHEN EXISTS(SELECT 1 FROM eshop.order_discounts d WHERE d.order_id=o.id)
     THEN 'DISCOUNTED_ORDER_PRICE_IMMUTABLE'
   WHEN EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) other
     WHERE other.state NOT IN ('storno','waitlisted')
       AND public.ticket_admission_integrity_internal(o.id,other.id)->>'reason' IS NOT NULL)
     THEN 'ADMISSION_DATA_AMBIGUOUS'
   WHEN p_ticket IS NULL THEN NULL
   WHEN t.id IS NULL OR t.state NOT IN ('ordered','paid','sent','used') THEN 'ORDER_ADMISSION_UNAVAILABLE'
   WHEN t.state='used' THEN 'USED_TICKET_PROTECTED'
   WHEN EXISTS(SELECT 1 FROM eshop.ticket_batch_items bi WHERE bi.ticket_id=p_ticket) THEN 'BATCH_TICKET_PRINT_IMMUTABLE'
   WHEN v.integrity->>'reason' IS NOT NULL THEN v.integrity->>'reason'
   WHEN v.integrity->>'spotCount' IS DISTINCT FROM '1' THEN 'ORDER_ADMISSION_UNAVAILABLE'
   WHEN EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.spots s ON s.order_product_ticket=x.id
       WHERE x.ticket=p_ticket AND x."order"=o.id AND s.blueprint IS NOT NULL
       AND (s.blueprint IS DISTINCT FROM f.blueprint OR EXISTS(
         SELECT 1
         FROM eshop.spots member LEFT JOIN eshop.order_product_ticket admission ON admission.id=member.order_product_ticket
         LEFT JOIN eshop.tickets holder ON holder.id=admission.ticket
         WHERE member.id=ANY(public.blueprint_selection_unit_spots_internal(s.id))
           AND member.id<>s.id AND (
             admission."order" IS DISTINCT FROM o.id OR holder.state NOT IN ('ordered','paid','sent')
             OR public.ticket_admission_integrity_internal(o.id,holder.id)->>'reason' IS NOT NULL
             OR EXISTS(SELECT 1 FROM eshop.ticket_batch_items bi WHERE bi.ticket_id=holder.id)
           )
       )))
     THEN 'BLUEPRINT_INCOMPLETE_SELECTION_UNIT'
 END
 FROM eshop.orders o
 LEFT JOIN public.forms f ON f.id=o.form AND f.occasion=o.occasion
 LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info
 LEFT JOIN eshop.tickets t ON t.id=p_ticket AND t.occasion=o.occasion
   AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x."order"=o.id AND x.ticket=t.id)
 CROSS JOIN LATERAL (SELECT CASE WHEN t.id IS NOT NULL THEN public.ticket_admission_integrity_internal(o.id,t.id) END AS integrity) v
 WHERE o.id=p_order
$$;
REVOKE ALL ON FUNCTION public.order_admission_blocker_internal(bigint,bigint)
  FROM PUBLIC,anon,authenticated,service_role;

-- Fill missing historical type metadata from the scoped catalog for both editors.
CREATE OR REPLACE FUNCTION public.order_ticket_admission_snapshot_internal(p_ticket jsonb,p_occasion bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT CASE WHEN p_ticket IS NULL THEN NULL ELSE p_ticket || jsonb_build_object('products',
   coalesce((SELECT jsonb_agg(CASE WHEN pt.id IS NULL THEN item ELSE item||jsonb_build_object('type',pt.type) END ORDER BY n)
   FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_ticket->'products')='array' THEN p_ticket->'products' ELSE '[]' END) WITH ORDINALITY x(item,n)
   LEFT JOIN eshop.products p ON p.id::text=item->>'id' AND p.occasion=p_occasion
   LEFT JOIN eshop.product_types pt ON pt.id=p.product_type AND pt.occasion=p_occasion),'[]')) END
$$;
REVOKE ALL ON FUNCTION public.order_ticket_admission_snapshot_internal(jsonb,bigint)
  FROM PUBLIC,anon,authenticated,service_role;
