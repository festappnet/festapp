CREATE OR REPLACE FUNCTION public.create_occasion_domain_command_internal_v1(p_command_id uuid, p_config jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_unit bigint; v_organization bigint;
  v_occasion bigint; v_begin jsonb; v_hash text; v_commit public.client_commits%ROWTYPE;
  v_entity jsonb;
BEGIN
  IF p_config IS NULL OR jsonb_typeof(p_config)<>'object'
    OR octet_length(p_config::text)>1048576
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_config) key WHERE key NOT IN
      ('id','start_time','end_time','is_open','is_hidden','is_promoted','link','title',
       'description','data','services','organization','unit','features','form_link',
       'has_orders','stats'))
    OR p_config->>'id' IS NOT NULL
    OR nullif(btrim(p_config->>'title'),'') IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid occasion aggregate'; END IF;
  v_unit:=NULLIF(p_config->>'unit','')::bigint;
  v_organization:=NULLIF(p_config->>'organization','')::bigint;
  IF v_actor IS NULL OR v_unit IS NULL OR v_organization IS NULL
    OR NOT EXISTS (SELECT 1 FROM public.units u
      WHERE u.id=v_unit AND u.organization=v_organization)
    OR NOT (public.get_is_manager_on_unit(v_unit)
      OR public.get_is_editor_on_unit(v_unit)) THEN
    RAISE insufficient_privilege USING MESSAGE='unit editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(p_config::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_unit_client_mutation_v1(p_command_id,
    'occasion.create',v_unit,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM public.update_occasion_internal_v1(p_config);
  SELECT o.id,to_jsonb(o)||jsonb_build_object('aggregate_version',1)
    INTO v_occasion,v_entity FROM public.occasions o
    WHERE o.id=currval(pg_get_serial_sequence('public.occasions','id'));
  IF v_occasion IS NULL THEN
    RAISE data_exception USING MESSAGE='occasion create returned no aggregate'; END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('occasion','occasion',v_occasion,v_occasion::text,1);
  INSERT INTO public.client_commits
    (unit,actor_id,actor_display,actor_kind,source,change_class)
  SELECT v_unit,v_actor,nullif(concat_ws(' ',ui.name,ui.surname),''),'user',
    'occasion.create','configuration' FROM public.user_info ui WHERE ui.id=v_actor
  RETURNING * INTO v_commit;
  INSERT INTO public.client_commit_items
    (commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
  VALUES (v_commit.commit_id,0,'occasion',v_occasion::text,'insert',
    left(v_entity->>'title',240),ARRAY['aggregate']);
  PERFORM public.fanout_unit_catalog_v1(v_commit.commit_id,v_unit);
  RETURN public.finish_client_mutation_v1(p_command_id,jsonb_build_object(
    'status','applied','code',200,'data',jsonb_build_object(
      'occasionId',v_occasion,'occasion',v_entity),
    'mutation',jsonb_build_object('commandId',p_command_id,
      'receiptId',p_command_id,'commitId',v_commit.commit_id,'replayed',false,
      'occurredAt',v_commit.occurred_at),
    'sync',jsonb_build_object('replacements','[]'::jsonb)),v_commit.commit_id);
END; $function$;
REVOKE ALL ON FUNCTION public.create_occasion_domain_command_internal_v1(uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
