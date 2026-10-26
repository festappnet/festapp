-- Private aggregate metadata plumbing; callers own authorization and parent locks.
CREATE OR REPLACE FUNCTION public.advance_ticketing_authoring_version_internal_v1(p_kind text,p_occasion bigint,p_id bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE result bigint;
BEGIN
 IF p_kind NOT IN ('product','product_type','inventory_pool') OR p_occasion IS NULL OR p_id IS NULL THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid ticketing aggregate identity'; END IF;
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
 VALUES(p_kind,'occasion',p_occasion,p_id::text,1)
 ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
 SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp()
 RETURNING version INTO result;
 RETURN result;
END $$;
CREATE OR REPLACE FUNCTION public.get_ticketing_product_versions_internal_v1(p_occasion bigint,p_kind text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_object_agg(ids.id::text,coalesce(v.version,0)),'{}') FROM (
  SELECT id FROM eshop.products WHERE occasion=p_occasion AND p_kind='product'
  UNION ALL SELECT id FROM eshop.product_types WHERE occasion=p_occasion AND p_kind='product_type'
 ) ids LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type=p_kind
 AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=ids.id::text;
$$;
REVOKE ALL ON FUNCTION public.advance_ticketing_authoring_version_internal_v1(text,bigint,bigint),
 public.get_ticketing_product_versions_internal_v1(bigint,text) FROM PUBLIC,anon,authenticated,service_role;
