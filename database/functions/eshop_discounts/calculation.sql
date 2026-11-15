-- Pure decimal owner. The input order is the normalized ticket/product order.
CREATE OR REPLACE FUNCTION public.calculate_order_discount_internal(p_lines jsonb,p_kind text,p_value numeric,p_digits integer)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE eligible numeric; target numeric; scale numeric:=power(10,p_digits); result jsonb;
BEGIN
 IF p_digits NOT BETWEEN 0 AND 2 OR p_kind NOT IN ('percent','fixed') OR p_value IS NULL OR p_value<=0
  OR p_value::text IN ('NaN','Infinity','-Infinity') OR (p_kind='percent' AND (p_value>10000 OR p_value<>trunc(p_value)))
  OR (p_kind='fixed' AND p_value<>round(p_value,p_digits)) OR jsonb_typeof(p_lines) IS DISTINCT FROM 'array'
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_lines) l WHERE l->>'base' IS NULL OR (l->>'base')::numeric::text IN ('NaN','Infinity','-Infinity') OR (l->>'base')::numeric<0
   OR (l->>'base')::numeric<>round((l->>'base')::numeric,p_digits)) THEN RAISE EXCEPTION 'DISCOUNT_INVALID'; END IF;
 SELECT coalesce(sum((l->>'base')::numeric) FILTER(WHERE l->'eligible'='true'::jsonb),0) INTO eligible FROM jsonb_array_elements(p_lines) l;
 IF eligible<=0 THEN RAISE EXCEPTION 'DISCOUNT_PRODUCT_SCOPE'; END IF;
 target:=least(eligible,CASE WHEN p_kind='percent' THEN round(eligible*p_value/10000,p_digits) ELSE p_value END)*scale;
 IF target<=0 THEN RAISE EXCEPTION 'DISCOUNT_INVALID'; END IF;
 WITH source AS (SELECT l,n,(l->>'base')::numeric base,CASE WHEN l->'eligible'='true'::jsonb THEN (l->>'base')::numeric*target/eligible ELSE 0 END exact
  FROM jsonb_array_elements(p_lines) WITH ORDINALITY s(l,n)),
 ranked AS (SELECT *,floor(exact) units,row_number() OVER(ORDER BY exact-floor(exact) DESC,n) rank,
  target-sum(floor(exact)) OVER() remaining FROM source),
 allocated AS (SELECT *, (units+CASE WHEN rank<=remaining THEN 1 ELSE 0 END)/scale discount FROM ranked)
 SELECT jsonb_build_object('base',sum(base),'discount',sum(discount),'net',sum(base-discount),'lines',
  jsonb_agg(l||jsonb_build_object('discount',discount,'net',base-discount) ORDER BY n)) INTO result FROM allocated;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(result->'lines') l WHERE (l->>'deposit')::numeric>0 AND (l->>'net')::numeric<=(l->>'deposit')::numeric) THEN
  RAISE EXCEPTION 'DISCOUNT_DEPOSIT_CONFLICT'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.calculate_order_discount_internal(jsonb,text,numeric,integer) FROM PUBLIC,anon,authenticated,service_role;
