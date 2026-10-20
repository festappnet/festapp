CREATE OR REPLACE FUNCTION public.update_blueprint_client_sync_v1(p_blueprint jsonb, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_blueprint bigint;
  v_begin jsonb; v_hash text; v_version bigint; v_expected bigint; v_users uuid[]; v_result jsonb;
BEGIN
  IF p_blueprint IS NULL OR jsonb_typeof(p_blueprint)<>'object'
    OR octet_length(p_blueprint::text)>8388608 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid blueprint aggregate'; END IF;
  v_occasion:=NULLIF(p_blueprint->>'occasion','')::bigint;
  v_blueprint:=NULLIF(p_blueprint->>'id','')::bigint;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR NOT public.get_is_editor_order_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',v_occasion,'blueprint',p_blueprint)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.blueprint.save',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF v_blueprint IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=v_blueprint AND occasion=v_occasion) THEN RAISE insufficient_privilege USING MESSAGE='foreign blueprint'; END IF;
  -- Parent order matches checkout: form, product, blueprint, then seats.
  PERFORM 1 FROM public.forms WHERE occasion=v_occasion AND
    (blueprint=v_blueprint OR id=nullif(p_blueprint->>'form','')::bigint) ORDER BY id FOR UPDATE;
  IF p_blueprint->>'form' IS NOT NULL THEN
    IF NOT EXISTS(SELECT 1 FROM public.forms WHERE id=(p_blueprint->>'form')::bigint AND occasion=v_occasion) THEN
      RAISE insufficient_privilege USING MESSAGE='foreign form'; END IF;
    INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES('form','occasion',v_occasion,p_blueprint->>'form',0) ON CONFLICT DO NOTHING;
    SELECT version INTO v_expected FROM public.client_aggregate_versions WHERE aggregate_type='form'
      AND scope_type='occasion' AND scope_id=v_occasion AND aggregate_id=p_blueprint->>'form' FOR UPDATE;
    IF (p_blueprint->>'expected_form_version')::bigint IS DISTINCT FROM v_expected THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
        jsonb_build_object('form_version',v_expected)); END IF;
  END IF;
  PERFORM 1 FROM eshop.products WHERE occasion=v_occasion ORDER BY id FOR UPDATE;
  PERFORM 1 FROM eshop.blueprints WHERE id=v_blueprint AND occasion=v_occasion FOR UPDATE;
  IF v_blueprint IS NOT NULL THEN
    INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES('blueprint','occasion',v_occasion,v_blueprint::text,0) ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='blueprint' AND scope_type='occasion' AND scope_id=v_occasion AND aggregate_id=v_blueprint::text FOR UPDATE;
  ELSE v_version:=0; END IF;
  -- Missing baseline remains an installed-client adapter, explicitly not MCP-ready.
  v_expected:=CASE WHEN p_blueprint ? 'expected_aggregate_version' THEN (p_blueprint->>'expected_aggregate_version')::bigint ELSE v_version END;
  IF v_expected IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('aggregate_version',v_version)); END IF;
  SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_users
  FROM public.occasion_users ou JOIN eshop.order_product_ticket opt
    ON opt.ticket=ou.ticket JOIN eshop.spots s
    ON s.order_product_ticket=opt.id
  WHERE ou.occasion=v_occasion AND s.occasion=v_occasion;
  BEGIN
    v_result:=public.update_blueprint_internal_v1(p_blueprint-ARRAY['expected_aggregate_version','expected_form_version']);
    IF coalesce((v_result->>'code')::integer,500)<>200 THEN
      RAISE SQLSTATE 'P0F01' USING MESSAGE='authoring domain rejected'; END IF;
  EXCEPTION WHEN SQLSTATE 'P0F01' THEN NULL;
  END;
  IF coalesce((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      CASE WHEN (v_result->>'code')::integer BETWEEN 100 AND 599 THEN (v_result->>'code')::integer ELSE 400 END,v_result); END IF;
  v_blueprint:=(v_result->>'blueprint_id')::bigint;
  INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES('blueprint','occasion',v_occasion,v_blueprint::text,1)
    ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp()
    RETURNING version INTO v_version;
  v_result:=v_result||jsonb_build_object('aggregate_version',v_version);
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.blueprint.save',jsonb_build_array(jsonb_build_object(
      'entityType','blueprint','entityId',v_result->>'blueprint_id',
      'operation',CASE WHEN p_blueprint->>'id' IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(p_blueprint->>'title',240),'changedFields',jsonb_build_array(
        'spots','configuration'))),v_users,v_result);
END; $function$;

REVOKE ALL ON FUNCTION public.update_blueprint_client_sync_v1(jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_blueprint_client_sync_v1(jsonb,uuid) TO authenticated;
