CREATE OR REPLACE FUNCTION public.delete_resource_client_sync_v1(p_occasion bigint, p_resource bigint, p_command_id uuid, p_expected_version bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_pool bigint; v_version bigint; v_title text;
  v_begin jsonb; v_hash text; v_impacts jsonb; v_replacements jsonb:='[]'::jsonb;
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_order_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'resourceId',p_resource,'expectedVersion',p_expected_version)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'inventory.resource.delete',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  v_pool:=public.lock_resource_pools_internal_v1(p_resource);
  SELECT r.inventory_pool,r.title INTO v_pool,v_title FROM public.resources r
    WHERE r.id=p_resource AND r.occasion=p_occasion FOR UPDATE;
  IF v_pool IS NULL THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'unchanged',200,jsonb_build_object('version',0,'resource',NULL)); END IF;
  PERFORM 1 FROM public.inventory_pools ip WHERE ip.id=v_pool FOR UPDATE;
  PERFORM 1 FROM eshop.spots s WHERE s.resource=p_resource OR s.resource_slot IN(SELECT id FROM public.resource_slots WHERE resource=p_resource) ORDER BY s.id FOR UPDATE;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('resource','occasion',p_occasion,p_resource::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='resource' AND scope_type='occasion'
      AND scope_id=p_occasion AND aggregate_id=p_resource::text FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
      jsonb_build_object('version',v_version,'resourceId',p_resource)); END IF;
  IF EXISTS (SELECT 1 FROM eshop.spots s WHERE (s.resource=p_resource OR s.resource_slot IN(SELECT id FROM public.resource_slots WHERE resource=p_resource))
    AND (s.order_product_ticket IS NOT NULL OR (s.secret IS NOT NULL AND s.secret_expiration_time>clock_timestamp()))) THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,
      jsonb_build_object('version',v_version,'resourceId',p_resource,
        'message','resource has reserved spots')); END IF;
  DELETE FROM eshop.spots WHERE resource=p_resource OR resource_slot IN(SELECT id FROM public.resource_slots WHERE resource=p_resource);
  DELETE FROM public.resources WHERE id=p_resource;
  PERFORM public.adjust_spot_capacity_for_pool(v_pool);
  PERFORM public.advance_ticketing_authoring_version_internal_v1('inventory_pool',p_occasion,v_pool);
  DELETE FROM public.client_aggregate_versions WHERE aggregate_type='resource'
    AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_resource::text;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_inventory',
    'userId',ou."user")),'[]'::jsonb) INTO v_impacts
    FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
  IF EXISTS (SELECT 1 FROM public.occasion_users ou WHERE ou.occasion=p_occasion
    AND ou."user"=v_actor) THEN v_replacements:=jsonb_build_array(jsonb_build_object(
      'component','private_inventory','userId',v_actor,
      'payload',public.get_user_inventory_for_occasion_v1(p_occasion))); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'inventory.resource.delete','inventory',jsonb_build_array(jsonb_build_object(
      'entityType','resource','entityId',p_resource,'operation','delete',
      'safeLabel',left(v_title,240),'changedFields',jsonb_build_array('aggregate'))),
    '{}',v_impacts,'[]',jsonb_build_object('version',v_version,'resource',NULL),
    '{}','[]','user',NULL,v_replacements);
END; $function$;
REVOKE ALL ON FUNCTION public.delete_resource_client_sync_v1(bigint,bigint,uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_resource_client_sync_v1(bigint,bigint,uuid,bigint) TO authenticated;
