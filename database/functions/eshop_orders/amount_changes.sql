-- Stable financial state, aggregated once per actual order. Private callers
-- own authorization and acquire the canonical order/payment locks first.
CREATE OR REPLACE FUNCTION public.order_payment_snapshot_internal(p_orders bigint[])
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_object_agg(o.id::text,jsonb_build_object('amount',o.price,'state',o.state,
  'payment',CASE WHEN p.id IS NULL THEN NULL ELSE jsonb_build_object('id',p.id,'method',p.payment_method,
   'amount',p.amount,'paid',p.paid,'returned',p.returned,'currency',p.currency_code) END)),'{}')
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=ANY(p_orders)
$$;
REVOKE ALL ON FUNCTION public.order_payment_snapshot_internal(bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- One financial projection for preview and committed results. Never invent a
-- zero quote for missing data or let an unrepresentable result commit first.
CREATE OR REPLACE FUNCTION public.project_order_amount_changes_internal(p_orders jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF jsonb_typeof(p_orders) IS DISTINCT FROM 'array' OR EXISTS(
  SELECT 1 FROM jsonb_array_elements(p_orders) e WHERE
   jsonb_typeof(e->'beforeAmount') IS DISTINCT FROM 'number'
   OR jsonb_typeof(e->'afterAmount') IS DISTINCT FROM 'number'
   OR jsonb_typeof(e->'delta') IS DISTINCT FROM 'number'
   OR length(e->>'beforeAmount')>40 OR length(e->>'afterAmount')>40 OR length(e->>'delta')>40
   OR coalesce(btrim(e->>'currencyCode'),'')!~'^[A-Za-z]{3}$'
   OR coalesce(length(e->>'beforeState'),0) NOT BETWEEN 1 AND 64
   OR coalesce(length(e->>'afterState'),0) NOT BETWEEN 1 AND 64) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_SWAP_MONEY_UNAVAILABLE'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('orderId',e->'orderId','beforeAmount',e->>'beforeAmount',
  'afterAmount',e->>'afterAmount','delta',e->>'delta','currencyCode',upper(btrim(e->>'currencyCode')),
  'beforeState',e->>'beforeState','afterState',e->>'afterState') ORDER BY (e->>'orderId')::bigint),'[]')
 INTO result FROM jsonb_array_elements(p_orders) e;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.project_order_amount_changes_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;
