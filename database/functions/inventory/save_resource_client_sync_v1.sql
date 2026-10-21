CREATE OR REPLACE FUNCTION public.save_resource_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_resource jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_id bigint:=(p_resource->>'id')::bigint;
  v_pool bigint:=(p_resource->>'inventory_pool')::bigint; v_version bigint; v_origin_pool bigint;
  v_begin jsonb; v_hash text; v_current jsonb; v_entity jsonb;
  v_impacts jsonb; v_replacements jsonb:='[]'::jsonb;
BEGIN
  -- No booking rules and an empty rule document have the same domain meaning.
  IF p_resource->'booking_rules'='null'::jsonb THEN
    p_resource:=jsonb_set(p_resource,'{booking_rules}','{}'); END IF;
  IF v_actor IS NULL OR NOT public.can_write_orders(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion order editor required'; END IF;
  IF p_resource IS NULL OR jsonb_typeof(p_resource)<>'object'
    OR octet_length(p_resource::text)>131072
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_resource) key WHERE key NOT IN
      ('id','title','capacity','booking_rules','inventory_pool'))
    OR v_pool IS NULL OR length(btrim(COALESCE(p_resource->>'title',''))) NOT BETWEEN 1 AND 500
    OR coalesce((p_resource->>'capacity')::integer,-1) NOT BETWEEN 0 AND 1000000
    OR jsonb_typeof(COALESCE(p_resource->'booking_rules','{}'))<>'object' THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid resource aggregate'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'expectedVersion',p_expected_version,'resource',p_resource)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'inventory.resource.save',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.inventory_pools WHERE id=v_pool AND occasion=p_occasion) THEN
    RAISE invalid_parameter_value USING MESSAGE='inventory pool is outside occasion'; END IF;
  IF v_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.resources WHERE id=v_id AND occasion=p_occasion) THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',404,jsonb_build_object('version',0,'resource',NULL)); END IF;
  v_origin_pool:=public.lock_resource_pools_internal_v1(v_id,v_pool);
  PERFORM 1 FROM public.inventory_pools ip WHERE ip.id=v_pool
    AND ip.occasion=p_occasion FOR UPDATE;
  IF NOT FOUND THEN RAISE invalid_parameter_value USING MESSAGE='inventory pool is outside occasion'; END IF;
  IF v_id IS NOT NULL THEN
    SELECT to_jsonb(r) INTO v_current FROM public.resources r WHERE r.id=v_id
      AND r.occasion=p_occasion FOR UPDATE;
    IF v_current IS NULL THEN RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,'rejected',404,jsonb_build_object('version',0,'resource',NULL)); END IF;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('resource','occasion',p_occasion,v_id::text,0) ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
      WHERE aggregate_type='resource' AND scope_type='occasion'
        AND scope_id=p_occasion AND aggregate_id=v_id::text FOR UPDATE;
    IF p_expected_version IS DISTINCT FROM v_version THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
        jsonb_build_object('version',v_version,'resource',v_current||
          jsonb_build_object('aggregate_version',v_version))); END IF;
    IF jsonb_build_object('title',v_current->>'title','capacity',(v_current->>'capacity')::integer,
      'booking_rules',COALESCE(v_current->'booking_rules','{}'),
      'inventory_pool',(v_current->>'inventory_pool')::bigint)=jsonb_build_object(
      'title',p_resource->>'title','capacity',(p_resource->>'capacity')::integer,
      'booking_rules',COALESCE(p_resource->'booking_rules','{}'),
      'inventory_pool',v_pool) THEN RETURN public.complete_client_mutation_outcome_v1(
        p_command_id,'unchanged',200,jsonb_build_object('version',v_version,
          'resource',v_current||jsonb_build_object('aggregate_version',v_version))); END IF;
    PERFORM 1 FROM eshop.spots WHERE resource=v_id OR resource_slot IN(SELECT id FROM public.resource_slots WHERE resource=v_id) ORDER BY id FOR UPDATE;
    IF (v_origin_pool IS DISTINCT FROM v_pool AND EXISTS(SELECT 1 FROM eshop.spots
      WHERE (resource=v_id OR resource_slot IN(SELECT id FROM public.resource_slots WHERE resource=v_id))
      AND (order_product_ticket IS NOT NULL OR (secret IS NOT NULL AND secret_expiration_time>clock_timestamp()))))
      OR EXISTS(SELECT 1 FROM eshop.spots WHERE (resource=v_id OR resource_slot IN(SELECT id FROM public.resource_slots WHERE resource=v_id))
        AND (order_product_ticket IS NOT NULL OR (secret IS NOT NULL AND secret_expiration_time>clock_timestamp()))
        GROUP BY inventory_context HAVING count(*)>(p_resource->>'capacity')::integer) THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,
        jsonb_build_object('version',v_version,'resourceId',v_id,'message','resource capacity or move conflicts with reserved spots')); END IF;
    IF v_origin_pool IS DISTINCT FROM v_pool THEN
      DELETE FROM eshop.spots WHERE resource=v_id OR resource_slot IN(SELECT id FROM public.resource_slots WHERE resource=v_id);
    END IF;
    UPDATE public.resources SET title=p_resource->>'title',
      capacity=(p_resource->>'capacity')::integer,
      booking_rules=COALESCE(p_resource->'booking_rules','{}'),inventory_pool=v_pool,
      updated_at=clock_timestamp() WHERE id=v_id;
    UPDATE public.client_aggregate_versions SET version=version+1,
      updated_at=clock_timestamp() WHERE aggregate_type='resource'
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_id::text
      RETURNING version INTO v_version;
  ELSE
    IF p_expected_version IS NOT NULL THEN
      RAISE invalid_parameter_value USING MESSAGE='new resource must not have expected version'; END IF;
    INSERT INTO public.resources(occasion,inventory_pool,title,capacity,booking_rules)
    VALUES (p_occasion,v_pool,p_resource->>'title',(p_resource->>'capacity')::integer,
      COALESCE(p_resource->'booking_rules','{}')) RETURNING id INTO v_id;
    v_version:=1;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('resource','occasion',p_occasion,v_id::text,v_version);
  END IF;
  IF v_origin_pool IS NOT NULL AND v_origin_pool IS DISTINCT FROM v_pool THEN
    PERFORM public.adjust_spot_capacity_for_pool(v_origin_pool);
  END IF;
  PERFORM public.adjust_spot_capacity_for_pool(v_pool);
  PERFORM public.advance_ticketing_authoring_version_internal_v1('inventory_pool',p_occasion,v_pool);
  IF v_origin_pool IS NOT NULL AND v_origin_pool IS DISTINCT FROM v_pool THEN
    PERFORM public.advance_ticketing_authoring_version_internal_v1('inventory_pool',p_occasion,v_origin_pool);
  END IF;
  SELECT to_jsonb(r)||jsonb_build_object('aggregate_version',v_version)
    INTO v_entity FROM public.resources r WHERE r.id=v_id;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_inventory',
    'userId',ou."user")),'[]'::jsonb) INTO v_impacts
    FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
  IF EXISTS (SELECT 1 FROM public.occasion_users ou WHERE ou.occasion=p_occasion
    AND ou."user"=v_actor) THEN v_replacements:=jsonb_build_array(jsonb_build_object(
      'component','private_inventory','userId',v_actor,
      'payload',public.get_user_inventory_for_occasion_v1(p_occasion))); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'inventory.resource.save','inventory',jsonb_build_array(jsonb_build_object(
      'entityType','resource','entityId',v_id,
      'operation',CASE WHEN v_current IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(p_resource->>'title',240),'changedFields',jsonb_build_array('aggregate'))),
    '{}',v_impacts,'[]',jsonb_build_object('version',v_version,'resource',v_entity),
    '{}','[]','user',NULL,v_replacements);
END; $function$;
REVOKE ALL ON FUNCTION public.save_resource_client_sync_v1(bigint,uuid,bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_resource_client_sync_v1(bigint,uuid,bigint,jsonb) TO authenticated;
