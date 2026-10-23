-- One financial projection for preview and committed results. Never invent a
-- zero quote for missing data or let an unrepresentable result commit first.
CREATE OR REPLACE FUNCTION public.get_blueprint_swap_money_internal(p_orders jsonb)
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
REVOKE ALL ON FUNCTION public.get_blueprint_swap_money_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;
