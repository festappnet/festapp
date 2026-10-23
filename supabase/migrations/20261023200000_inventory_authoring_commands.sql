-- Share scoped stock authoring and its existing receipt owners.
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

CREATE OR REPLACE FUNCTION public.get_inventory_pool_bundle(p_inventory_pool_id bigint)
RETURNS jsonb
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id bigint;
    v_pool_data jsonb;
    v_occasion_data jsonb;
    v_resources_data jsonb;
    v_contexts_data jsonb;
    v_places_data jsonb;
    v_products_data jsonb;
    v_product_inventory_contexts_data jsonb; -- New variable for the join table data
    result jsonb;
    settings jsonb;
BEGIN
    -- Get occasion for permission check from the inventory pool
    SELECT occasion INTO v_occasion_id
    FROM public.inventory_pools
    WHERE id = p_inventory_pool_id FOR SHARE;

    IF v_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Inventory Pool not found.';
    END IF;

    -- Permission check
    IF public.can_read_orders(v_occasion_id) IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION 'User is not authorized to view this occasion.';
    END IF;

    -- Current UI and MCP share the pool/context and resource projections.
    settings:=public.get_inventory_pool_settings_data_internal(p_inventory_pool_id);
    v_pool_data:=settings->'pool';
    v_contexts_data:=settings->'contexts';
    SELECT to_jsonb(o) INTO v_occasion_data FROM public.occasions o WHERE o.id=v_occasion_id;
    v_resources_data:=public.get_inventory_resource_rows_internal(v_occasion_id,
      ARRAY(SELECT id FROM public.resources WHERE inventory_pool=p_inventory_pool_id),true);

    -- Aggregate all places for the occasion
    SELECT COALESCE(jsonb_agg(to_jsonb(p) ORDER BY p.order), '[]'::jsonb)
    INTO v_places_data
    FROM public.places p
    WHERE p.occasion = v_occasion_id;

    -- MODIFICATION START
    -- Aggregate products that are linked to the inventory contexts of this specific pool.
    SELECT COALESCE(jsonb_agg(to_jsonb(pr)), '[]'::jsonb)
    INTO v_products_data
    FROM (
        SELECT DISTINCT pr.*
        FROM eshop.products pr
        JOIN eshop.product_inventory_contexts pic ON pr.id = pic.product
        JOIN public.inventory_contexts ic ON pic.inventory_context = ic.id
        WHERE ic.inventory_pool = p_inventory_pool_id
    ) pr;

    -- Aggregate the product <-> inventory_context join table entries for this pool's contexts.
    SELECT COALESCE(jsonb_agg(to_jsonb(pic)), '[]'::jsonb)
    INTO v_product_inventory_contexts_data
    FROM eshop.product_inventory_contexts pic
    JOIN public.inventory_contexts ic ON pic.inventory_context = ic.id
    WHERE ic.inventory_pool = p_inventory_pool_id;

    -- Construct the final bundle object, now including context-specific products and the join table data.
    result := jsonb_build_object(
        'pool', v_pool_data,
        'occasion', v_occasion_data,
        'resources', v_resources_data,
        'contexts', v_contexts_data,
        'places', v_places_data,
        'products', v_products_data,
        'product_inventory_contexts', v_product_inventory_contexts_data
        ,'aggregate_version', COALESCE((SELECT av.version
          FROM public.client_aggregate_versions av
          WHERE av.aggregate_type='inventory_pool' AND av.scope_type='occasion'
            AND av.scope_id=v_occasion_id
            AND av.aggregate_id=p_inventory_pool_id::text),0)
    );
    -- MODIFICATION END

    IF public.can_read_orders(v_occasion_id) IS DISTINCT FROM TRUE THEN
        RAISE insufficient_privilege USING MESSAGE='occasion order viewer required';
    END IF;
    RETURN result;
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object('code', 500, 'message', SQLERRM);
END;
$$ LANGUAGE plpgsql;

-- Single receipt owner; released/current UI select full editor snapshots.
CREATE OR REPLACE FUNCTION public.save_inventory_pool_command_internal(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_bundle jsonb, p_editor boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path=public,extensions
AS $function$
DECLARE
  v_actor uuid:=auth.uid(); v_pool_id bigint:=(p_bundle#>>'{pool,id}')::bigint;
  v_version bigint; v_begin jsonb; v_hash text; v_result jsonb;
  v_commit jsonb; v_response jsonb; v_private_impacts jsonb;
  v_current_command_data jsonb; v_requested_command_data jsonb;
  v_product_ids bigint[]; v_product_id bigint;
  v_actor_private_revision bigint; v_actor_private_payload jsonb;
BEGIN
  IF v_actor IS NULL OR NOT public.can_write_orders(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion order editor required';
  END IF;
  IF p_bundle IS NULL OR jsonb_typeof(p_bundle)<>'object'
    OR octet_length(p_bundle::text)>1048576
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_bundle) key
      WHERE key NOT IN ('pool','contexts'))
    OR jsonb_typeof(p_bundle->'pool')<>'object'
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_bundle->'pool') key
      WHERE key NOT IN ('id','title','sellable_capacity','occasion',
        'description','type','data'))
    OR (p_bundle ? 'contexts' AND p_bundle->'contexts'<>'null'::jsonb AND jsonb_typeof(p_bundle->'contexts')<>'array')
    OR jsonb_array_length(CASE WHEN jsonb_typeof(p_bundle->'contexts')='array' THEN p_bundle->'contexts' ELSE '[]'::jsonb END)>2000
    OR (p_bundle#>>'{pool,occasion}')::bigint IS DISTINCT FROM p_occasion
    OR (v_pool_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.inventory_pools ip
      WHERE ip.id=v_pool_id AND ip.occasion=p_occasion))
    OR EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_bundle->'contexts')='array' THEN p_bundle->'contexts' ELSE '[]'::jsonb END) c
      WHERE jsonb_typeof(c)<>'object' OR EXISTS (
        SELECT 1 FROM jsonb_object_keys(c) key
        WHERE key NOT IN ('id','inventory_pool','block_date','title','order','data'))
      OR ((c->>'id') IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.inventory_contexts ic
        WHERE ic.id=(c->>'id')::bigint AND ic.inventory_pool=v_pool_id))) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid or cross-scope inventory aggregate';
  END IF;
  v_hash:=encode(extensions.digest(convert_to((jsonb_build_object('occasion',p_occasion,
    'expectedVersion',p_expected_version,'bundle',p_bundle) || CASE WHEN p_editor THEN '{}'::jsonb ELSE jsonb_build_object('snapshot','settings') END)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'inventory.pool.save',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;

  IF v_pool_id IS NOT NULL THEN
    v_product_ids:=public.lock_pool_product_dependencies_internal_v1(v_pool_id);
    PERFORM 1 FROM public.inventory_pools ip WHERE ip.id=v_pool_id
      AND ip.occasion=p_occasion FOR UPDATE;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('inventory_pool','occasion',p_occasion,v_pool_id::text,0)
    ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
      WHERE aggregate_type='inventory_pool' AND scope_type='occasion'
        AND scope_id=p_occasion AND aggregate_id=v_pool_id::text FOR UPDATE;
    IF p_expected_version IS DISTINCT FROM v_version THEN
      v_response:=jsonb_build_object('status','conflict','code',409,
        'data',jsonb_build_object('version',v_version,
          'bundle',public.inventory_pool_command_snapshot_internal(v_pool_id,p_editor)),
        'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
          'commitId',NULL,'replayed',false,'occurredAt',clock_timestamp()),
        'sync',jsonb_build_object('replacements','[]'::jsonb));
      RETURN public.finish_client_mutation_v1(p_command_id,v_response,NULL);
    END IF;

    IF NOT p_bundle ? 'contexts' OR p_bundle->'contexts'='null'::jsonb THEN
      p_bundle:=jsonb_set(p_bundle,'{contexts}',coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id',ic.id,'inventory_pool',ic.inventory_pool,'block_date',ic.block_date,'title',ic.title,'order',ic."order",'data',ic.data)
        ORDER BY ic."order",ic.id) FROM public.inventory_contexts ic WHERE ic.inventory_pool=v_pool_id),'[]'));
    END IF;
    SELECT jsonb_build_object(
      'pool',jsonb_build_object('id',ip.id,'title',ip.title,
        'sellable_capacity',ip.sellable_capacity,'occasion',ip.occasion,
        'description',ip.description,'type',ip.type,'data',ip.data),
      'contexts',COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id',ic.id,'inventory_pool',ic.inventory_pool,
        'block_date',ic.block_date,'title',ic.title,'order',ic."order",
        'data',ic.data) ORDER BY ic."order",ic.id)
        FROM public.inventory_contexts ic
        WHERE ic.inventory_pool=ip.id),'[]'::jsonb))
      INTO v_current_command_data
    FROM public.inventory_pools ip WHERE ip.id=v_pool_id;
    SELECT jsonb_build_object(
      'pool',jsonb_build_object('id',(p_bundle#>>'{pool,id}')::bigint,
        'title',p_bundle#>>'{pool,title}',
        'sellable_capacity',(p_bundle#>>'{pool,sellable_capacity}')::bigint,
        'occasion',(p_bundle#>>'{pool,occasion}')::bigint,
        'description',p_bundle#>>'{pool,description}',
        'type',p_bundle#>>'{pool,type}','data',p_bundle#>'{pool,data}'),
      'contexts',COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id',(c->>'id')::bigint,'inventory_pool',v_pool_id,
        'block_date',(c->>'block_date')::date,'title',c->>'title',
        'order',(c->>'order')::bigint,'data',c->'data')
        ORDER BY (c->>'order')::bigint,(c->>'id')::bigint)
        FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_bundle->'contexts')='array' THEN p_bundle->'contexts' ELSE '[]'::jsonb END) c),'[]'::jsonb))
      INTO v_requested_command_data;
    IF v_current_command_data = v_requested_command_data THEN
      v_response:=jsonb_build_object('status','unchanged','code',200,
        'data',jsonb_build_object('version',v_version,
          'bundle',public.inventory_pool_command_snapshot_internal(v_pool_id,p_editor)),
        'mutation',jsonb_build_object('commandId',p_command_id,
          'receiptId',p_command_id,'commitId',NULL,'replayed',false,
          'occurredAt',clock_timestamp()),
        'sync',jsonb_build_object('replacements','[]'::jsonb));
      RETURN public.finish_client_mutation_v1(p_command_id,v_response,NULL);
    END IF;
  ELSIF p_expected_version IS NOT NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='new inventory pool must not have expected version';
  END IF;

  IF NOT p_bundle ? 'contexts' OR p_bundle->'contexts'='null'::jsonb THEN
    p_bundle:=jsonb_set(p_bundle,'{contexts}','[]'); END IF;
  v_pool_id:=public.save_inventory_pool_internal(p_bundle);
  v_result:=public.inventory_pool_command_snapshot_internal(v_pool_id,p_editor);
  FOREACH v_product_id IN ARRAY coalesce(v_product_ids,'{}'::bigint[]) LOOP
    PERFORM public.advance_ticketing_authoring_version_internal_v1('product',p_occasion,v_product_id);
  END LOOP;
  IF v_result ? 'code' AND COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RAISE EXCEPTION 'inventory aggregate handler failed: %',v_result->>'message';
  END IF;
  v_pool_id:=(v_result#>>'{pool,id}')::bigint;
  IF v_pool_id IS NULL THEN RAISE EXCEPTION 'inventory handler returned no pool id'; END IF;
  IF v_version IS NULL THEN
    v_version:=1;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('inventory_pool','occasion',p_occasion,v_pool_id::text,v_version);
  ELSE
    UPDATE public.client_aggregate_versions SET version=version+1,
      updated_at=clock_timestamp() WHERE aggregate_type='inventory_pool'
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_pool_id::text
      RETURNING version INTO v_version;
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_inventory',
    'userId',ou."user")),'[]'::jsonb) INTO v_private_impacts
    FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
  v_commit:=public.record_client_sync_commit_v1(p_occasion,'inventory.pool.save',
    'inventory',jsonb_build_array(jsonb_build_object('entityType','inventory_pool',
      'entityId',v_pool_id,'operation',CASE WHEN (p_bundle#>>'{pool,id}') IS NULL
        THEN 'insert' ELSE 'update' END,'safeLabel',left(v_result#>>'{pool,title}',240),
      'changedFields',jsonb_build_array('aggregate'))),'{}',v_private_impacts,
    '[]','user',NULL);
  IF p_editor THEN
  SELECT s.source_revision INTO STRICT v_actor_private_revision
  FROM public.client_sync_private_scopes s
  WHERE s.component='private_inventory' AND s.occasion=p_occasion
    AND s.user_id=v_actor;
  v_actor_private_payload:=public.get_user_inventory_for_occasion_v1(p_occasion);
  END IF;
  v_result:=v_result||jsonb_build_object('aggregate_version',v_version);
  v_response:=jsonb_build_object('status','applied','code',200,
    'data',jsonb_build_object('version',v_version,'bundle',v_result),
    'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
      'commitId',v_commit->>'commitId','replayed',false,'occurredAt',v_commit->>'occurredAt'),
    'sync',jsonb_build_object('replacements',CASE WHEN p_editor THEN jsonb_build_array(
      jsonb_build_object('component','private_inventory',
        'revision',v_actor_private_revision,'payload',v_actor_private_payload)) ELSE '[]'::jsonb END));
  RETURN public.finish_client_mutation_v1(p_command_id,v_response,
    (v_commit->>'commitId')::uuid);
END; $function$;
REVOKE ALL ON FUNCTION public.save_inventory_pool_command_internal(bigint,uuid,bigint,jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;

-- Released full-editor receipt API delegates to the same private command owner.
CREATE OR REPLACE FUNCTION public.save_inventory_pool_client_sync_v1(p_occasion bigint,p_command_id uuid,p_expected_version bigint,p_bundle jsonb)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.save_inventory_pool_command_internal(p_occasion,p_command_id,p_expected_version,p_bundle,true)
$$;
REVOKE ALL ON FUNCTION public.save_inventory_pool_client_sync_v1(bigint,uuid,bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_inventory_pool_client_sync_v1(bigint,uuid,bigint,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.delete_inventory_pool_client_sync_v1(p_occasion bigint, p_pool bigint, p_command_id uuid, p_expected_version bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_version bigint; v_title text; v_begin jsonb;
  v_hash text; v_reserved bigint; v_impacts jsonb;
  v_product_ids bigint[]; v_product_id bigint;
  v_replacements jsonb:='[]'::jsonb;
BEGIN
  IF v_actor IS NULL OR NOT public.can_write_orders(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'poolId',p_pool,'expectedVersion',p_expected_version)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'inventory.pool.delete',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  v_product_ids:=public.lock_pool_product_dependencies_internal_v1(p_pool);
  SELECT ip.title INTO v_title FROM public.inventory_pools ip WHERE ip.id=p_pool
    AND ip.occasion=p_occasion FOR UPDATE;
  IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'unchanged',200,jsonb_build_object('version',0,'pool',NULL)); END IF;
  PERFORM 1 FROM public.inventory_contexts ic WHERE ic.inventory_pool=p_pool
    ORDER BY ic.id FOR UPDATE;
  PERFORM 1 FROM public.resources r WHERE r.inventory_pool=p_pool
    ORDER BY r.id FOR UPDATE;
  PERFORM 1 FROM eshop.spots s WHERE s.inventory_context IN (
    SELECT ic.id FROM public.inventory_contexts ic WHERE ic.inventory_pool=p_pool)
    OR s.resource IN (SELECT r.id FROM public.resources r WHERE r.inventory_pool=p_pool) OR s.resource_slot IN (SELECT rs.id FROM public.resource_slots rs JOIN public.resources r ON r.id=rs.resource WHERE r.inventory_pool=p_pool)
    ORDER BY s.id FOR UPDATE;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('inventory_pool','occasion',p_occasion,p_pool::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='inventory_pool' AND scope_type='occasion'
      AND scope_id=p_occasion AND aggregate_id=p_pool::text FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
      jsonb_build_object('version',v_version,'poolId',p_pool)); END IF;
  SELECT count(*) INTO v_reserved FROM eshop.spots s
    WHERE (s.order_product_ticket IS NOT NULL OR (s.secret IS NOT NULL AND s.secret_expiration_time>clock_timestamp())) AND (s.inventory_context IN (
      SELECT ic.id FROM public.inventory_contexts ic WHERE ic.inventory_pool=p_pool)
      OR s.resource IN (SELECT r.id FROM public.resources r WHERE r.inventory_pool=p_pool) OR s.resource_slot IN (SELECT rs.id FROM public.resource_slots rs JOIN public.resources r ON r.id=rs.resource WHERE r.inventory_pool=p_pool));
  IF v_reserved>0 THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'rejected',409,jsonb_build_object('version',v_version,
      'poolId',p_pool,'message','inventory pool has reserved spots')); END IF;
  DELETE FROM eshop.spots s WHERE s.order_product_ticket IS NULL AND (
    s.inventory_context IN (SELECT ic.id FROM public.inventory_contexts ic
      WHERE ic.inventory_pool=p_pool) OR s.resource IN (
      SELECT r.id FROM public.resources r WHERE r.inventory_pool=p_pool) OR s.resource_slot IN (
      SELECT rs.id FROM public.resource_slots rs JOIN public.resources r ON r.id=rs.resource WHERE r.inventory_pool=p_pool));
  DELETE FROM public.client_aggregate_versions v WHERE v.scope_type='occasion'
    AND v.scope_id=p_occasion AND ((v.aggregate_type='resource' AND v.aggregate_id IN (
      SELECT r.id::text FROM public.resources r WHERE r.inventory_pool=p_pool))
      OR (v.aggregate_type='inventory_pool' AND v.aggregate_id=p_pool::text));
  DELETE FROM public.resources WHERE inventory_pool=p_pool;
  DELETE FROM public.inventory_contexts WHERE inventory_pool=p_pool;
  DELETE FROM public.inventory_pools WHERE id=p_pool;
  FOREACH v_product_id IN ARRAY v_product_ids LOOP
    PERFORM public.advance_ticketing_authoring_version_internal_v1('product',p_occasion,v_product_id);
  END LOOP;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_inventory',
    'userId',ou."user")),'[]'::jsonb) INTO v_impacts
    FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
  IF EXISTS (SELECT 1 FROM public.occasion_users ou WHERE ou.occasion=p_occasion
    AND ou."user"=v_actor) THEN v_replacements:=jsonb_build_array(jsonb_build_object(
      'component','private_inventory','userId',v_actor,
      'payload',public.get_user_inventory_for_occasion_v1(p_occasion))); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'inventory.pool.delete','inventory',jsonb_build_array(jsonb_build_object(
      'entityType','inventory_pool','entityId',p_pool,'operation','delete',
      'safeLabel',left(v_title,240),'changedFields',jsonb_build_array('aggregate'))),
    '{}',v_impacts,'[]',jsonb_build_object('version',v_version,'pool',NULL),
    '{}','[]','user',NULL,v_replacements);
END; $function$;
REVOKE ALL ON FUNCTION public.delete_inventory_pool_client_sync_v1(bigint,bigint,uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_inventory_pool_client_sync_v1(bigint,bigint,uuid,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.check_inventory_entity_scope_internal(p_occasion bigint,p_pool bigint,p_resource bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF p_pool IS NOT NULL AND EXISTS(SELECT 1 FROM public.inventory_pools WHERE id=p_pool AND occasion IS DISTINCT FROM p_occasion)
  OR p_resource IS NOT NULL AND EXISTS(SELECT 1 FROM public.resources WHERE id=p_resource AND occasion IS DISTINCT FROM p_occasion) THEN
  RAISE insufficient_privilege USING MESSAGE='inventory entity unavailable'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_inventory_entity_scope_internal(bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- A scope boundary over one existing receipt owner, never an outer receipt.
CREATE OR REPLACE FUNCTION public.manage_inventory(p_occasion bigint,p_organization bigint,p_unit bigint,
 p_action text,p_payload jsonb,p_command_id uuid,p_editor boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;entity_id bigint;pool_id bigint;expected bigint;entity jsonb;
BEGIN
 IF p_action IS NULL OR p_action NOT IN ('save_pool','delete_pool','save_resource','delete_resource')
  OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR p_editor IS NULL
  OR p_command_id IS NULL OR octet_length(p_payload::text)>1048576 THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid inventory intention'; END IF;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true);
 expected:=(p_payload->>'expectedVersion')::bigint;
 IF expected<0 THEN RAISE invalid_parameter_value USING MESSAGE='invalid inventory version'; END IF;
 IF p_action='save_pool' THEN
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN ('bundle','expectedVersion'))
   OR (p_payload#>>'{bundle,pool,occasion}')::bigint IS DISTINCT FROM p_occasion THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid pool intention'; END IF;
  pool_id:=(p_payload#>>'{bundle,pool,id}')::bigint;
 ELSIF p_action='save_resource' THEN
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN ('resource','expectedVersion')) THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid resource intention'; END IF;
  entity_id:=(p_payload#>>'{resource,id}')::bigint;pool_id:=(p_payload#>>'{resource,inventory_pool}')::bigint;
  IF NOT EXISTS(SELECT 1 FROM public.inventory_pools WHERE id=pool_id AND occasion=p_occasion) THEN
   RAISE insufficient_privilege USING MESSAGE='inventory pool unavailable'; END IF;
 ELSE
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN ('id','expectedVersion'))
   OR p_payload->>'id' IS NULL OR expected IS NULL THEN
   RAISE invalid_parameter_value USING MESSAGE='original inventory id/version required'; END IF;
  entity_id:=(p_payload->>'id')::bigint;
  IF p_action='delete_pool' THEN pool_id:=entity_id; END IF;
 END IF;
 -- Reject an existing foreign entity before the domain owner locks dependencies.
 -- Missing deletes still reach the owner for durable unchanged/replay outcomes.
 PERFORM public.check_inventory_entity_scope_internal(p_occasion,pool_id,CASE WHEN p_action IN ('save_resource','delete_resource') THEN entity_id END);
 IF p_action='save_pool' THEN
  result:=public.save_inventory_pool_command_internal(p_occasion,p_command_id,expected,p_payload->'bundle',p_editor);
 ELSIF p_action='delete_pool' THEN
  result:=public.delete_inventory_pool_client_sync_v1(p_occasion,entity_id,p_command_id,expected);
 ELSIF p_action='save_resource' THEN
  result:=public.save_resource_client_sync_v1(p_occasion,p_command_id,expected,p_payload->'resource');
 ELSE
  result:=public.delete_resource_client_sync_v1(p_occasion,entity_id,p_command_id,expected);
 END IF;
 IF p_action='save_pool' THEN pool_id:=coalesce((result#>>'{data,bundle,pool,id}')::bigint,pool_id);
 ELSIF p_action='save_resource' THEN entity_id:=coalesce((result#>>'{data,resource,id}')::bigint,entity_id); END IF;
 PERFORM public.check_inventory_entity_scope_internal(p_occasion,pool_id,CASE WHEN p_action IN ('save_resource','delete_resource') THEN entity_id END);
 -- Includes receipt replay. A late scope failure rolls the entire intention back.
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true,true);
 IF NOT p_editor THEN
  IF p_action='save_resource' AND jsonb_typeof(result#>'{data,resource}')='object' THEN
   entity:=result#>'{data,resource}';
   result:=jsonb_set(result,'{data,resource}',jsonb_build_object('id',entity->'id','occasion',entity->'occasion',
    'inventory_pool',entity->'inventory_pool','title',entity->'title','capacity',entity->'capacity',
    'booking_rules',entity->'booking_rules','aggregate_version',entity->'aggregate_version'));
  END IF;
  result:=result-'sync';
 END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.manage_inventory(bigint,bigint,bigint,text,jsonb,uuid,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.manage_inventory(bigint,bigint,bigint,text,jsonb,uuid,boolean) TO authenticated;
