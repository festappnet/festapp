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
  IF v_actor IS NULL OR NOT public.get_is_editor_order_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'poolId',p_pool,'expectedVersion',p_expected_version)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'inventory.pool.delete',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  v_product_ids:=public.lock_pool_product_dependencies_internal_v1(p_pool);
  SELECT ip.title INTO v_title FROM public.inventory_pools ip WHERE ip.id=p_pool
    AND ip.occasion=p_occasion FOR UPDATE;
  IF v_title IS NULL THEN RETURN public.complete_client_mutation_outcome_v1(
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
