-- Forward-only MCP summary boundary; existing full admin signatures are retained.
BEGIN;
CREATE OR REPLACE FUNCTION public.operator_order_facts_internal_v1(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('id',o.id,'occasionId',o.occasion,'symbol',o.order_symbol,'state',o.state,
   'ticketCount',(SELECT count(DISTINCT i.ticket) FROM eshop.order_product_ticket i JOIN eshop.tickets t ON t.id=i.ticket WHERE i."order"=o.id AND o.state IS DISTINCT FROM 'storno' AND o.state IS DISTINCT FROM 'waitlisted' AND t.state IS DISTINCT FROM 'storno' AND t.state IS DISTINCT FROM 'waitlisted'),
   'price',o.price::text,'currency',o.currency_code,'allowedActions',public.get_order_allowed_actions_internal_v1(o.id),
   'payment',CASE WHEN p.id IS NULL THEN NULL ELSE jsonb_build_object('amount',p.amount::text,'paid',p.paid::text,'returned',p.returned::text) END)
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=p_order;
$$;

CREATE OR REPLACE FUNCTION public.operator_order_snapshot_internal_v1(p_order bigint,p_detail boolean DEFAULT false)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.operator_order_facts_internal_v1(o.id) || jsonb_build_object(
   'createdAt',o.created_at,'updatedAt',o.updated_at,'revision',public.operator_order_revision_internal_v1(o.id),
   'customer',jsonb_build_object('name',o.data->>'name','surname',o.data->>'surname','email',o.data->>'email'),
   'payment',CASE WHEN p.id IS NULL THEN NULL ELSE jsonb_build_object('method',p.payment_method,'amount',p.amount::text,'paid',p.paid::text,'returned',p.returned::text,'variableSymbol',p.variable_symbol::text,'deadline',p.deadline) END)
   || CASE WHEN p_detail THEN jsonb_build_object('note',o.note_hidden,'responses',coalesce(o.data->'fields','[]'),
     'formFields',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',f.id,'title',f.title,'type',f.type) ORDER BY f.id),'[]') FROM public.form_fields f WHERE f.form=o.form),
     'tickets',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'state',t.state,
        'products',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',pr.id,'title',pr.title,'price',jsonb_path_query_first(o.data,'$.tickets[*] ? (@.id == $ticket).products[*] ? (@.id == $product).price',jsonb_build_object('ticket',t.id,'product',pr.id))#>>'{}','currentPrice',pr.price::text) ORDER BY i.id),'[]') FROM eshop.order_product_ticket i JOIN eshop.products pr ON pr.id=i.product WHERE i."order"=o.id AND i.ticket=t.id)) ORDER BY t.id),'[]')
       FROM eshop.tickets t WHERE t.id IN(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=o.id))) ELSE '{}'::jsonb END
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=p_order;
$$;

CREATE OR REPLACE FUNCTION public.operator_order_summary_internal_v1(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT jsonb_set(facts,'{allowedActions}',
   CASE WHEN facts->'allowedActions' ? 'view' THEN '["view"]'::jsonb ELSE '[]'::jsonb END)
 FROM (SELECT public.operator_order_facts_internal_v1(p_order) facts) safe;
$$;

CREATE OR REPLACE FUNCTION public.get_operator_order_summaries_v1(p_occasion bigint,p_organization bigint,p_unit bigint DEFAULT NULL,
  p_limit integer DEFAULT 25,p_before bigint DEFAULT NULL,p_state text DEFAULT NULL,p_symbol text DEFAULT NULL,p_order bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE rows jsonb; v_next bigint;
BEGIN
 PERFORM public.check_operator_order_scope_internal_v1(p_occasion,p_organization,p_unit);
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 OR (p_symbol IS NOT NULL AND p_symbol !~ '^[A-Z0-9]{10}$')
   OR (p_state IS NOT NULL AND length(p_state)>40)
   OR (p_order IS NOT NULL AND (p_before IS NOT NULL OR p_state IS NOT NULL OR p_symbol IS NOT NULL OR p_limit<>25)) THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid order summary page'; END IF;
 IF p_order IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='order unavailable'; END IF;
   RETURN jsonb_build_object('occasionId',p_occasion,'orders',jsonb_build_array(public.operator_order_summary_internal_v1(p_order)),'nextCursor',NULL);
 END IF;
 WITH page AS MATERIALIZED(SELECT id FROM eshop.orders WHERE occasion=p_occasion AND (p_before IS NULL OR id<p_before)
   AND (p_state IS NULL OR state=p_state) AND (p_symbol IS NULL OR order_symbol=p_symbol)
   ORDER BY id DESC LIMIT p_limit+1), visible AS(SELECT id FROM page ORDER BY id DESC LIMIT p_limit)
 SELECT coalesce(jsonb_agg(public.operator_order_summary_internal_v1(id) ORDER BY id DESC),'[]'),
   CASE WHEN p_symbol IS NULL AND (SELECT count(*) FROM page)>p_limit THEN min(id) END INTO rows,v_next FROM visible;
 RETURN jsonb_build_object('occasionId',p_occasion,'orders',rows,'nextCursor',v_next);
END $$;

REVOKE ALL ON FUNCTION public.operator_order_facts_internal_v1(bigint),public.operator_order_summary_internal_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_operator_order_summaries_v1(bigint,bigint,bigint,integer,bigint,text,text,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_operator_order_summaries_v1(bigint,bigint,bigint,integer,bigint,text,text,bigint) TO authenticated;

COMMIT;
