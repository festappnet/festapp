CREATE OR REPLACE FUNCTION public.get_inventory_pool_settings_data_internal(p_pool bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 SELECT jsonb_build_object('pool',jsonb_build_object('id',ip.id,'occasion',ip.occasion,'title',ip.title,
  'created_at',ip.created_at,'updated_at',ip.updated_at,'description',ip.description,'type',ip.type,'sellable_capacity',ip.sellable_capacity,'data',ip.data),
  'contexts',coalesce((SELECT jsonb_agg(jsonb_build_object('id',ic.id,'inventory_pool',ic.inventory_pool,
   'title',ic.title,'block_date',ic.block_date,'order',ic."order",'data',ic.data) ORDER BY ic."order" NULLS LAST,ic.id)
   FROM public.inventory_contexts ic WHERE ic.inventory_pool=ip.id),'[]'),
  'aggregate_version',coalesce(v.version,0)) INTO result
 FROM public.inventory_pools ip LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='inventory_pool'
  AND v.scope_type='occasion' AND v.scope_id=ip.occasion AND v.aggregate_id=ip.id::text WHERE ip.id=p_pool;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_inventory_pool_settings_data_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Settings needed to replace one pool aggregate; context omission in a save
-- preserves existing contexts. Complete replacement reads fail instead of truncating.
CREATE OR REPLACE FUNCTION public.get_inventory_pool_settings_internal(p_pool bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF (SELECT count(*) FROM public.inventory_contexts WHERE inventory_pool=p_pool)>2000 THEN
  RAISE program_limit_exceeded USING MESSAGE='pool exceeds context authoring limit'; END IF;
 result:=public.get_inventory_pool_settings_data_internal(p_pool);
 result:=jsonb_set(result,'{pool}',(result->'pool')-ARRAY['created_at','updated_at']);
 IF octet_length(result::text)>1048576 THEN RAISE program_limit_exceeded USING MESSAGE='pool exceeds authoring payload limit'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_inventory_pool_settings_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.inventory_pool_command_snapshot_internal(p_pool bigint,p_editor boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF p_editor THEN RETURN public.get_inventory_pool_bundle(p_pool); END IF;
 RETURN public.get_inventory_pool_settings_internal(p_pool);
END $$;
REVOKE ALL ON FUNCTION public.inventory_pool_command_snapshot_internal(bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_inventory_pool_settings(p_occasion bigint,p_organization bigint,p_unit bigint,p_pool bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,false,true);
 PERFORM 1 FROM public.inventory_pools WHERE id=p_pool AND occasion=p_occasion FOR SHARE;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='inventory pool unavailable'; END IF;
 result:=public.get_inventory_pool_settings_internal(p_pool);
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,false,true);
 RETURN jsonb_build_object('occasionId',p_occasion,'settings',result,'readAt',statement_timestamp());
END $$;
REVOKE ALL ON FUNCTION public.get_inventory_pool_settings(bigint,bigint,bigint,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_inventory_pool_settings(bigint,bigint,bigint,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_inventory_resource_rows_internal(p_occasion bigint,p_ids bigint[],p_editor boolean)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',r.id,'inventory_pool',r.inventory_pool,'occasion',r.occasion,
  'title',r.title,'capacity',r.capacity,'booking_rules',CASE WHEN p_editor THEN r.booking_rules ELSE coalesce(r.booking_rules,'{}') END,
  'aggregate_version',coalesce(v.version,0)) || CASE WHEN p_editor THEN jsonb_build_object(
   'created_at',r.created_at,'updated_at',r.updated_at,'description',r.description,'place',r.place,'unit',r.unit,'data',r.data,
   'slots',coalesce((SELECT jsonb_agg(jsonb_build_object('id',rs.id,'resource',rs.resource,'title',rs.title,'data',rs.data) ORDER BY rs.id)
    FROM public.resource_slots rs WHERE rs.resource=r.id),'[]')) ELSE '{}'::jsonb END
  ORDER BY CASE WHEN p_editor THEN r.title END,r.id),'[]')
 FROM public.resources r JOIN public.inventory_pools ip ON ip.id=r.inventory_pool AND ip.occasion=p_occasion
 LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='resource' AND v.scope_type='occasion'
  AND v.scope_id=p_occasion AND v.aggregate_id=r.id::text WHERE r.id=ANY(p_ids) AND r.occasion=p_occasion
$$;
REVOKE ALL ON FUNCTION public.get_inventory_resource_rows_internal(bigint,bigint[],boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_inventory_resources(p_occasion bigint,p_organization bigint,p_unit bigint,p_pool bigint,p_after bigint DEFAULT NULL,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ids bigint[];next_id bigint;rows jsonb;
BEGIN
 IF p_limit IS NULL OR p_limit<1 OR p_limit>100 OR p_after IS NOT NULL AND p_after<1 THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid resource page'; END IF;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,false,true);
 PERFORM 1 FROM public.inventory_pools WHERE id=p_pool AND occasion=p_occasion FOR SHARE;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='inventory pool unavailable'; END IF;
 SELECT coalesce(array_agg(id ORDER BY id),'{}'::bigint[]) INTO ids FROM (
  SELECT id FROM public.resources WHERE inventory_pool=p_pool AND occasion=p_occasion AND (p_after IS NULL OR id>p_after)
  ORDER BY id LIMIT p_limit+1) selected;
 IF cardinality(ids)>p_limit THEN ids:=ids[1:p_limit];next_id:=ids[p_limit]; END IF;
 rows:=public.get_inventory_resource_rows_internal(p_occasion,ids,false);
 IF octet_length(rows::text)>1048576 THEN RAISE program_limit_exceeded USING MESSAGE='resource page exceeds payload limit; use a smaller limit'; END IF;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,false,true);
 RETURN jsonb_build_object('occasionId',p_occasion,'poolId',p_pool,'resources',rows,'nextCursor',next_id,'readAt',statement_timestamp());
END $$;
REVOKE ALL ON FUNCTION public.get_inventory_resources(bigint,bigint,bigint,bigint,bigint,integer) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_inventory_resources(bigint,bigint,bigint,bigint,bigint,integer) TO authenticated;


-- The full current UI editor uses the same settings/resource projection owners
-- with an explicit tenant scope; the released bare-ID API remains available.
CREATE OR REPLACE FUNCTION public.get_inventory_pool_for_edit(p_occasion bigint,p_organization bigint,p_unit bigint,p_pool bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,false,true);
 PERFORM 1 FROM public.inventory_pools WHERE id=p_pool AND occasion=p_occasion FOR SHARE;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='inventory pool unavailable'; END IF;
 result:=public.get_inventory_pool_bundle(p_pool);
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,false,true);
 IF result ? 'code' AND (result->>'code')::integer<>200 THEN RAISE EXCEPTION 'inventory editor unavailable'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_inventory_pool_for_edit(bigint,bigint,bigint,bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_inventory_pool_for_edit(bigint,bigint,bigint,bigint) TO authenticated;
