CREATE OR REPLACE FUNCTION public.save_discount_code(p_occasion bigint,p_definition jsonb,p_id bigint DEFAULT NULL,p_expected_revision bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c eshop.discount_codes; old eshop.discount_codes; forms bigint[]; products bigint[]; code text;
BEGIN
 IF public.can_manage_discount_codes(p_occasion) IS DISTINCT FROM TRUE THEN RAISE insufficient_privilege; END IF;
 IF p_definition IS NULL OR jsonb_typeof(p_definition)<>'object' OR octet_length(p_definition::text)>16384 THEN RAISE invalid_parameter_value; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[p_occasion]);
 PERFORM public.check_occasion_writable(p_occasion);
 IF public.can_manage_discount_codes(p_occasion) IS DISTINCT FROM TRUE THEN RAISE insufficient_privilege; END IF;
 IF coalesce(btrim(p_definition->>'code'),'') COLLATE "C" !~ '^[A-Za-z0-9-]{4,32}$' THEN RAISE EXCEPTION 'DISCOUNT_INVALID'; END IF;
 code:=upper(btrim(p_definition->>'code') COLLATE "C");
 SELECT coalesce(array_agg(DISTINCT value::bigint ORDER BY value::bigint),'{}') INTO forms FROM jsonb_array_elements_text(coalesce(p_definition->'formIds','[]'));
 SELECT coalesce(array_agg(DISTINCT value::bigint ORDER BY value::bigint),'{}') INTO products FROM jsonb_array_elements_text(coalesce(p_definition->'productIds','[]'));
 IF EXISTS(SELECT 1 FROM unnest(forms) id WHERE NOT EXISTS(SELECT 1 FROM public.forms f WHERE f.id=id AND f.occasion=p_occasion))
 OR EXISTS(SELECT 1 FROM unnest(products) id WHERE NOT EXISTS(SELECT 1 FROM eshop.products p WHERE p.id=id AND p.occasion=p_occasion)) THEN RAISE EXCEPTION 'DISCOUNT_SCOPE_INVALID'; END IF;
 IF p_id IS NOT NULL THEN
  SELECT * INTO old FROM eshop.discount_codes WHERE id=p_id AND occasion=p_occasion FOR UPDATE;
  IF NOT FOUND THEN RAISE insufficient_privilege; END IF;
  IF old.revision IS DISTINCT FROM p_expected_revision THEN RAISE EXCEPTION 'DISCOUNT_REVISION_CONFLICT'; END IF;
  IF code IS DISTINCT FROM old.normalized_code AND EXISTS(SELECT 1 FROM eshop.order_discounts WHERE code_id=p_id) THEN RAISE EXCEPTION 'DISCOUNT_IDENTITY_IMMUTABLE'; END IF;
 END IF;
 c.occasion:=p_occasion; c.normalized_code:=code; c.kind:=p_definition->>'kind'; c.value:=(p_definition->>'value')::numeric;
 c.currency_code:=CASE WHEN c.kind='fixed' THEN upper(p_definition->>'currency') END;
 IF c.kind='fixed' THEN PERFORM public.validate_product_price(c.value,'{}',c.currency_code); END IF;
 c.form_ids:=forms; c.product_ids:=products; c.valid_from:=nullif(p_definition->>'validFrom','')::timestamptz;
 c.valid_until:=nullif(p_definition->>'validUntil','')::timestamptz; c.usage_limit:=(p_definition->>'usageLimit')::bigint;
 c.is_active:=coalesce((p_definition->>'isActive')::boolean,false);
 IF p_id IS NULL THEN
  INSERT INTO eshop.discount_codes(occasion,normalized_code,kind,value,currency_code,form_ids,product_ids,valid_from,valid_until,usage_limit,is_active,created_by,updated_by)
   VALUES(c.occasion,c.normalized_code,c.kind,c.value,c.currency_code,c.form_ids,c.product_ids,c.valid_from,c.valid_until,c.usage_limit,c.is_active,auth.uid(),auth.uid()) RETURNING * INTO c;
 ELSE
  UPDATE eshop.discount_codes SET normalized_code=c.normalized_code,kind=c.kind,value=c.value,currency_code=c.currency_code,
   form_ids=c.form_ids,product_ids=c.product_ids,valid_from=c.valid_from,valid_until=c.valid_until,usage_limit=c.usage_limit,is_active=c.is_active,
   revision=old.revision+1,updated_by=auth.uid(),updated_at=clock_timestamp() WHERE id=p_id RETURNING * INTO c;
 END IF;
 INSERT INTO eshop.discount_code_audit(code_id,actor,revision,definition) VALUES(c.id,auth.uid(),c.revision,to_jsonb(c));
 RETURN to_jsonb(c);
END $$;
CREATE OR REPLACE FUNCTION public.list_discount_codes(p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF public.can_manage_discount_codes(p_occasion) IS DISTINCT FROM TRUE THEN RAISE insufficient_privilege; END IF;
 RETURN (SELECT coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('uses',CASE WHEN public.can_read_orders(p_occasion) THEN
  (SELECT count(*) FROM eshop.order_discounts d WHERE d.code_id=c.id) END,'discountTotals',CASE WHEN public.can_read_orders(p_occasion) THEN
  (SELECT coalesce(jsonb_object_agg(currency_code,amount),'{}') FROM (SELECT currency_code,sum(discount_amount) amount FROM eshop.order_discounts d WHERE d.code_id=c.id GROUP BY currency_code) totals) END) ORDER BY c.id),'[]') FROM eshop.discount_codes c WHERE c.occasion=p_occasion);
END $$;
REVOKE ALL ON FUNCTION public.save_discount_code(bigint,jsonb,bigint,bigint),public.list_discount_codes(bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.save_discount_code(bigint,jsonb,bigint,bigint),public.list_discount_codes(bigint) TO authenticated;
