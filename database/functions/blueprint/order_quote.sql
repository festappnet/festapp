-- Validate one final typed quote before retaining any confirmed write effects.
CREATE OR REPLACE FUNCTION public.blueprint_seat_order_quote_internal(p_effect jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE quote jsonb:=p_effect->'quote';money jsonb;products jsonb;
BEGIN
 IF coalesce(quote#>>'{newOrder,amount}','')!~'^-?[0-9]+(\.[0-9]+)?$'
  OR length(quote#>>'{newOrder,amount}')>40
  OR coalesce(btrim(quote#>>'{newOrder,currencyCode}'),'')!~'^[A-Za-z]{3}$'
  OR coalesce(length(quote#>>'{newOrder,state}'),0) NOT BETWEEN 1 AND 64
  OR quote#>>'{newOrder,paymentMethod}' IS DISTINCT FROM 'bank'
  OR (quote#>>'{newOrder,ticketCount}')::int IS DISTINCT FROM jsonb_array_length(quote->'spotIds')
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(quote#>'{newOrder,products}') p
    WHERE coalesce(p->>'amount','')!~'^-?[0-9]+(\.[0-9]+)?$' OR length(p->>'amount')>40
    OR coalesce(btrim(p->>'currencyCode'),'')!~'^[A-Za-z]{3}$')
  OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(quote->'spotIds') requested(id)
    WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements(quote#>'{newOrder,products}') p WHERE p->>'spotId'=requested.id)) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_ORDER_MONEY_UNAVAILABLE'; END IF;
 money:=public.project_order_amount_changes_internal(quote->'orders');
 SELECT coalesce(jsonb_agg(p||jsonb_build_object('currencyCode',upper(btrim(p->>'currencyCode')))),'[]') INTO products
 FROM jsonb_array_elements(quote#>'{newOrder,products}') p;
 RETURN jsonb_set(jsonb_set(jsonb_set(quote,'{orders}',money),'{newOrder,currencyCode}',to_jsonb(upper(btrim(quote#>>'{newOrder,currencyCode}')))),
  '{newOrder,products}',products);
END $$;
REVOKE ALL ON FUNCTION public.blueprint_seat_order_quote_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;
