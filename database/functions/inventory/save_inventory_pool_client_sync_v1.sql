CREATE OR REPLACE FUNCTION public.save_inventory_pool_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_bundle jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
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
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'expectedVersion',p_expected_version,'bundle',p_bundle)::text,'UTF8'),'sha256'),'hex');
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
          'bundle',public.get_inventory_pool_bundle(v_pool_id)),
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
          'bundle',public.get_inventory_pool_bundle(v_pool_id)),
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
  v_result:=public.update_inventory_pool_bundle_internal_v1(p_bundle);
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
  SELECT s.source_revision INTO STRICT v_actor_private_revision
  FROM public.client_sync_private_scopes s
  WHERE s.component='private_inventory' AND s.occasion=p_occasion
    AND s.user_id=v_actor;
  v_actor_private_payload:=public.get_user_inventory_for_occasion_v1(p_occasion);
  v_result:=v_result||jsonb_build_object('aggregate_version',v_version);
  v_response:=jsonb_build_object('status','applied','code',200,
    'data',jsonb_build_object('version',v_version,'bundle',v_result),
    'mutation',jsonb_build_object('commandId',p_command_id,'receiptId',p_command_id,
      'commitId',v_commit->>'commitId','replayed',false,'occurredAt',v_commit->>'occurredAt'),
    'sync',jsonb_build_object('replacements',jsonb_build_array(
      jsonb_build_object('component','private_inventory',
        'revision',v_actor_private_revision,'payload',v_actor_private_payload))));
  RETURN public.finish_client_mutation_v1(p_command_id,v_response,
    (v_commit->>'commitId')::uuid);
END; $function$;
REVOKE ALL ON FUNCTION public.save_inventory_pool_client_sync_v1(bigint,uuid,bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_inventory_pool_client_sync_v1(bigint,uuid,bigint,jsonb) TO authenticated;
