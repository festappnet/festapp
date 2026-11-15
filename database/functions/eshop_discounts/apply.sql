CREATE OR REPLACE FUNCTION public.apply_order_discount_internal(p_order bigint,p_input jsonb,p_tickets jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE q jsonb; tickets jsonb; snapshot jsonb; actual jsonb; item record; line jsonb; n integer:=0;
BEGIN
 -- This boundary runs after canonical admission/product locks and before payment.
 BEGIN
  q:=public.order_discount_quote_internal(p_input);
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM ~ '^DISCOUNT_[A-Z_]+$' THEN RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','DISCOUNT_QUOTE_CHANGED')::text; END IF;
  RAISE;
 END;
 IF p_input#>>'{discount,fingerprint}' IS DISTINCT FROM q->>'fingerprint' THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','DISCOUNT_QUOTE_CHANGED')::text; END IF;
 IF nullif(p_input->>'discount_command_id','') IS NULL THEN RAISE EXCEPTION 'DISCOUNT_COMMAND_REQUIRED'; END IF;
 SELECT jsonb_agg(jsonb_build_object('productId',p->'id','base',p->'price') ORDER BY tn,pn) INTO actual
  FROM jsonb_array_elements(p_tickets) WITH ORDINALITY ts(t,tn)
  CROSS JOIN LATERAL jsonb_array_elements(t->'products') WITH ORDINALITY ps(p,pn);
 IF actual IS DISTINCT FROM (SELECT jsonb_agg(jsonb_build_object('productId',l->'productId','base',l->'base') ORDER BY ls.n)
  FROM jsonb_array_elements(q->'lines') WITH ORDINALITY ls(l,n)) THEN RAISE EXCEPTION 'DISCOUNT_INVALID'; END IF;
 tickets:='[]';
 FOR item IN SELECT t FROM jsonb_array_elements(p_tickets) t LOOP
  DECLARE products jsonb:='[]'; p jsonb;
  BEGIN
   FOR p IN SELECT value FROM jsonb_array_elements(item.t->'products') LOOP
    line:=q->'lines'->n; n:=n+1;
    UPDATE eshop.order_product_ticket SET base_price=(line->>'base')::numeric,discount_amount=(line->>'discount')::numeric,net_price=(line->>'net')::numeric
     WHERE id=(p->>'order_product_ticket_id')::bigint AND "order"=p_order;
    IF NOT FOUND THEN RAISE EXCEPTION 'DISCOUNT_LINE_MISSING'; END IF;
    products:=products||jsonb_build_array(p||jsonb_build_object('base_price',line->'base','discount_amount',line->'discount','price',line->'net'));
   END LOOP;
   tickets:=tickets||jsonb_build_array(jsonb_set(item.t,'{products}',products));
  END;
 END LOOP;
 snapshot:=q||jsonb_build_object('tickets',tickets,'definition',(SELECT to_jsonb(c) FROM eshop.discount_codes c WHERE c.id=(q->>'codeId')::bigint));
 INSERT INTO eshop.order_discounts(order_id,code_id,command_id,snapshot,base_amount,discount_amount,net_amount,currency_code)
 VALUES(p_order,(q->>'codeId')::bigint,(p_input->>'discount_command_id')::uuid,snapshot,(q->>'base')::numeric,(q->>'discount')::numeric,(q->>'net')::numeric,q->>'currency');
 RETURN jsonb_build_object('tickets',tickets,'discount',q-ARRAY['lines','codeId'],'price',q->'net');
END $$;
CREATE OR REPLACE FUNCTION public.assert_order_discount_unchanged_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM eshop.order_discounts WHERE order_id=p_order) THEN RAISE EXCEPTION 'DISCOUNTED_ORDER_PRICE_IMMUTABLE'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.apply_order_discount_internal(bigint,jsonb,jsonb),public.assert_order_discount_unchanged_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
