-- Private quote and commit share scope, prices, normalization and allocation.
-- The existing occasion blueprint fence also fences every feature writer.
CREATE OR REPLACE FUNCTION public.order_discount_quote_internal(p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; c eshop.discount_codes; lines jsonb; result jsonb; currency text; digits integer; policy jsonb;
BEGIN
 IF p_input IS NULL OR octet_length(p_input::text)>1048576 OR jsonb_typeof(p_input->'ticket') IS DISTINCT FROM 'array'
  OR jsonb_array_length(p_input->'ticket') NOT BETWEEN 1 AND public.ticket_order_limit()
  OR coalesce(length(p_input#>>'{discount,code}'),0) NOT BETWEEN 4 AND 64
  OR coalesce(btrim(p_input#>>'{discount,code}'),'') COLLATE "C" !~ '^[A-Za-z0-9-]{4,32}$' THEN RAISE EXCEPTION 'DISCOUNT_INVALID'; END IF;
 SELECT * INTO f FROM public.forms WHERE key=(p_input->>'form')::uuid;
 IF f.id IS NULL THEN RAISE EXCEPTION 'DISCOUNT_INVALID'; END IF;
 p_input:=jsonb_set(p_input,'{ticket}',public.normalize_form_ticket_answers_internal(f.id,p_input->'ticket'));
 PERFORM public.lock_blueprint_scope_internal(ARRAY[f.occasion]);
 PERFORM public.payment_policy_fence_internal((SELECT organization FROM public.occasions WHERE id=f.occasion));
 SELECT jsonb_build_object('features',o.features,'updatedAt',o.updated_at,'aggregateVersion',(SELECT version FROM public.client_aggregate_versions v WHERE v.aggregate_type='occasion' AND v.scope_type='occasion' AND v.scope_id=o.id AND v.aggregate_id=o.id::text)) INTO policy FROM public.occasions o WHERE id=f.occasion;
 IF NOT coalesce(jsonb_path_exists(policy->'features','$[*] ? (@.code == "discount_codes" && @.is_enabled == true)'),false) THEN RAISE EXCEPTION 'DISCOUNT_FEATURE_OFF'; END IF;
 SELECT * INTO c FROM eshop.discount_codes WHERE occasion=f.occasion AND normalized_code=upper(btrim(p_input#>>'{discount,code}') COLLATE "C") FOR UPDATE;
 IF c.id IS NULL THEN RAISE EXCEPTION 'DISCOUNT_INVALID'; END IF;
 IF NOT c.is_active THEN RAISE EXCEPTION 'DISCOUNT_INACTIVE'; END IF;
 IF (c.valid_from IS NOT NULL AND clock_timestamp()<c.valid_from) OR (c.valid_until IS NOT NULL AND clock_timestamp()>=c.valid_until) THEN RAISE EXCEPTION 'DISCOUNT_OUTSIDE_VALIDITY'; END IF;
 IF cardinality(c.form_ids)>0 AND NOT f.id=ANY(c.form_ids) THEN RAISE EXCEPTION 'DISCOUNT_FORM_SCOPE'; END IF;
 IF c.usage_limit IS NOT NULL AND (SELECT count(*) FROM eshop.order_discounts WHERE code_id=c.id)>=c.usage_limit THEN RAISE EXCEPTION 'DISCOUNT_EXHAUSTED'; END IF;
 WITH tickets AS (SELECT t,n FROM jsonb_array_elements(public.normalize_form_ticket_answers_internal(f.id,p_input->'ticket')) WITH ORDINALITY s(t,n)),
 selection AS (
  SELECT n,m,p.id,p.title,p.price,p.currency_code,coalesce((p.data#>>'{deposit,amount}')::numeric,0) deposit,p.product_type,p.is_hidden
  FROM tickets CROSS JOIN LATERAL jsonb_array_elements(coalesce(t->'fields','[]')) WITH ORDINALITY a(answer,m)
   JOIN eshop.products p ON p.id=(answer->>'product_type')::bigint WHERE answer ? 'product_type'
  UNION ALL SELECT n,2147483647,p.id,p.title,p.price,p.currency_code,coalesce((p.data#>>'{deposit,amount}')::numeric,0),p.product_type,p.is_hidden
  FROM tickets JOIN eshop.spots s ON s.id=(t->>'spot')::bigint JOIN eshop.products p ON p.id=s.product
  WHERE s.blueprint=f.blueprint),
 scoped AS (SELECT s.*,p.occasion FROM selection s JOIN eshop.product_types p ON p.id=s.product_type)
 SELECT jsonb_agg(jsonb_build_object('productId',id,'title',title,'base',price,'currency',currency_code,'deposit',deposit,
  'eligible',price>0 AND (cardinality(c.product_ids)=0 OR id=ANY(c.product_ids))) ORDER BY n,m),min(currency_code)
 INTO lines,currency FROM scoped WHERE occasion=f.occasion AND NOT is_hidden AND
 (EXISTS(SELECT 1 FROM public.form_fields ff WHERE ff.form=f.id AND ff.product_type=scoped.product_type AND NOT ff.is_hidden)
  OR EXISTS(SELECT 1 FROM public.blueprint_form_products_internal(f.id) b WHERE b.product=scoped.id AND b.has_capacity));
 IF lines IS NULL OR currency IS NULL OR currency COLLATE "C" !~ '^[A-Z]{3}$' OR EXISTS(SELECT 1 FROM jsonb_array_elements(lines) l WHERE l->>'currency' IS DISTINCT FROM currency)
 THEN RAISE EXCEPTION 'DISCOUNT_INVALID'; END IF;
 IF c.kind='fixed' AND c.currency_code IS DISTINCT FROM currency THEN RAISE EXCEPTION 'DISCOUNT_CURRENCY_MISMATCH'; END IF;
 digits:=CASE WHEN currency IN ('JPY','KRW','VND','CLP','ISK','BIF','DJF','GNF','KMF','PYG','RWF','UGX','VUV','XAF','XOF','XPF') THEN 0 ELSE 2 END;
 result:=public.calculate_order_discount_internal(lines,c.kind,c.value,digits)||jsonb_build_object('currency',currency,'code',c.normalized_code,'codeId',c.id,'revision',c.revision);
 RETURN result||jsonb_build_object('fingerprint',encode(extensions.digest(convert_to(jsonb_build_object('quote',result,'policy',policy,'form',f.id,'selection',p_input->'ticket')::text,'UTF8'),'sha256'),'hex'));
END $$;
CREATE OR REPLACE FUNCTION public.quote_order_discount(p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE f public.forms; un bigint; org bigint; result jsonb;
BEGIN
 IF p_input IS NULL OR octet_length(p_input::text)>1048576 THEN RETURN jsonb_build_object('code',400,'errorCode','DISCOUNT_INVALID'); END IF;
 SELECT * INTO f FROM public.forms WHERE key=(p_input->>'form')::uuid;
 SELECT unit,organization INTO un,org FROM public.occasions WHERE id=f.occasion;
 IF f.id IS NULL THEN RETURN jsonb_build_object('code',400,'errorCode','DISCOUNT_INVALID'); END IF;
 IF NOT public.abuse_charge_v1(public.abuse_effective_rules_v1('discount.quote',un,org),jsonb_build_object('recipient',f.id,'organization',org),'{}',true) THEN
  RETURN jsonb_build_object('code',429,'errorCode','ABUSE_LIMIT_EXCEEDED'); END IF;
 BEGIN
  result:=public.order_discount_quote_internal(p_input);
  -- No IDs, availability, customers or definitions leave this boundary.
  RETURN jsonb_build_object('code',200,'quote',(result-ARRAY['codeId','lines'])||jsonb_build_object('lines',(
   SELECT jsonb_agg(jsonb_build_object('productId',l->'productId','base',l->'base','discount',l->'discount','net',l->'net','currency',l->'currency') ORDER BY n)
   FROM jsonb_array_elements(result->'lines') WITH ORDINALITY rows(l,n))));
 EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('code',400,'errorCode','DISCOUNT_INVALID')||CASE WHEN public.can_manage_discount_codes(f.occasion) AND SQLERRM ~ '^DISCOUNT_[A-Z_]+$' THEN jsonb_build_object('reason',SQLERRM) ELSE '{}'::jsonb END; END;
END $$;
REVOKE ALL ON FUNCTION public.order_discount_quote_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.quote_order_discount(jsonb) FROM PUBLIC,service_role;
GRANT EXECUTE ON FUNCTION public.quote_order_discount(jsonb) TO anon,authenticated;
