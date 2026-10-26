-- Projection of the same authoritative aggregate returned by reads and receipts.
CREATE OR REPLACE FUNCTION public.project_configuration_settings_internal_v1(kind text, row_data jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE settings jsonb; features jsonb; f jsonb; safe_f jsonb; k text; result jsonb;
 spec jsonb:=public.configuration_settings_contract_internal_v1();
BEGIN
 SELECT COALESCE(jsonb_object_agg(key,value),'{}') INTO settings FROM jsonb_each(COALESCE(NULLIF(row_data->'data','null'::jsonb),'{}')) WHERE spec->kind ? key;
 result:=jsonb_build_object('entityType',kind,'entityId',(row_data->>'id')::bigint,
  'aggregateVersion',COALESCE((row_data->>'aggregate_version')::bigint,0),'title',row_data->'title','settings',settings);
 IF kind='occasion' THEN
  features:='[]';
  FOR f IN SELECT * FROM jsonb_array_elements(COALESCE(row_data->'features','[]')) LOOP
   IF spec->'features' ? (f->>'code') THEN
    SELECT COALESCE(jsonb_object_agg(key,value),'{}') INTO safe_f FROM jsonb_each(f) WHERE key='code' OR spec->'features'->(f->>'code') ? key;
    features:=features||jsonb_build_array(safe_f);
   END IF;
  END LOOP;
  result:=result||jsonb_build_object('organizationId',row_data->'organization','unitId',row_data->'unit',
   'startTime',row_data->'start_time','endTime',row_data->'end_time','isOpen',row_data->'is_open',
   'isHidden',row_data->'is_hidden','isPromoted',row_data->'is_promoted','description',row_data->'description',
   'features',features);
 END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.project_configuration_settings_internal_v1(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.check_configuration_scope_internal_v1(kind text, entity_id bigint, organization_id bigint, unit_id bigint, writing boolean)
RETURNS void LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR organization_id IS DISTINCT FROM (SELECT organization FROM public.user_info WHERE id=auth.uid()) THEN
  RAISE insufficient_privilege USING MESSAGE='configuration tenant mismatch'; END IF;
 IF kind='occasion' THEN
  IF NOT EXISTS(SELECT FROM public.occasions WHERE id=entity_id AND organization=organization_id AND (unit_id IS NULL OR unit=unit_id))
   OR NOT (CASE WHEN writing THEN public.can_edit_occasion(entity_id) ELSE public.can_read_occasion_editor_data(entity_id) OR public.can_edit_occasion(entity_id) END) THEN
   RAISE insufficient_privilege USING MESSAGE='occasion configuration scope denied'; END IF;
 ELSIF kind='unit' THEN
  IF entity_id IS DISTINCT FROM unit_id OR NOT EXISTS(SELECT FROM public.units WHERE id=entity_id AND organization=organization_id)
   OR NOT public.can_manage_unit_configuration(entity_id) THEN
   RAISE insufficient_privilege USING MESSAGE='unit configuration scope denied'; END IF;
 ELSE RAISE invalid_parameter_value USING MESSAGE='unsupported configuration entity'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_configuration_scope_internal_v1(text,bigint,bigint,bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_configuration_settings(p_entity_type text,p_entity_id bigint,p_organization bigint,p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE snapshot jsonb; version bigint;
BEGIN
 IF p_entity_type='occasion' THEN PERFORM 1 FROM public.occasions WHERE id=p_entity_id FOR SHARE;
 ELSE PERFORM 1 FROM public.units WHERE id=p_entity_id FOR SHARE; END IF;
 PERFORM public.check_configuration_scope_internal_v1(p_entity_type,p_entity_id,p_organization,p_unit,false);
 IF p_entity_type='occasion' THEN SELECT to_jsonb(o) INTO snapshot FROM public.occasions o WHERE id=p_entity_id;
 ELSE SELECT to_jsonb(u) INTO snapshot FROM public.units u WHERE id=p_entity_id; END IF;
 SELECT COALESCE(v.version,0) INTO version FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
 ON v.aggregate_type=p_entity_type AND v.scope_type=p_entity_type AND v.scope_id=p_entity_id AND v.aggregate_id=p_entity_id::text;
 RETURN public.project_configuration_settings_internal_v1(p_entity_type,snapshot||jsonb_build_object('aggregate_version',version));
END $$;
REVOKE ALL ON FUNCTION public.get_configuration_settings(text,bigint,bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_configuration_settings(text,bigint,bigint,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.save_configuration_settings(p_entity_type text,p_entity_id bigint,p_organization bigint,p_unit bigint,p_expected_version bigint,p_command_id uuid,p_settings jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb; allowed text[]; key text; aggregate_key text;
BEGIN
 PERFORM public.check_configuration_scope_internal_v1(p_entity_type,p_entity_id,p_organization,p_unit,true);
 allowed:=CASE WHEN p_entity_type='occasion' THEN ARRAY['title','description','start_time','end_time','is_open','is_hidden','is_promoted','settings','feature_changes'] ELSE ARRAY['title','settings'] END;
 IF jsonb_typeof(p_settings)<>'object' OR p_settings IS NULL OR EXISTS(SELECT FROM jsonb_object_keys(p_settings) k WHERE NOT k=ANY(allowed)) THEN
  RAISE invalid_parameter_value USING MESSAGE='unsupported configuration edit'; END IF;
 IF p_settings ? 'title' AND (jsonb_typeof(p_settings->'title')<>'string' OR nullif(btrim(p_settings->>'title'),'') IS NULL OR length(p_settings->>'title')>(CASE WHEN p_entity_type='unit' THEN 30 ELSE 512 END)) THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid title'; END IF;
 FOREACH key IN ARRAY ARRAY['is_open','is_hidden','is_promoted'] LOOP
  IF p_settings ? key AND jsonb_typeof(p_settings->key)<>'boolean' THEN RAISE invalid_parameter_value USING MESSAGE='invalid visibility flag'; END IF;
 END LOOP;
 FOREACH key IN ARRAY ARRAY['start_time','end_time'] LOOP
  IF p_settings ? key THEN PERFORM public.validate_configuration_value_internal_v1(p_settings->key,'{"type":"datetime"}'); END IF;
 END LOOP;
 IF p_settings ? 'description' THEN PERFORM public.validate_configuration_value_internal_v1(p_settings->'description','{"type":"string","maxLength":500000}'); END IF;
 IF p_entity_type='occasion' THEN
  result:=public.save_occasion_client_sync_v1(p_entity_id,p_command_id,p_expected_version,p_settings||jsonb_build_object('id',p_entity_id));
 ELSE result:=public.save_unit_client_sync_v1(p_entity_id,p_command_id,p_expected_version,p_settings||jsonb_build_object('id',p_entity_id)); END IF;
 PERFORM public.check_configuration_scope_internal_v1(p_entity_type,p_entity_id,p_organization,p_unit,true);
 aggregate_key:=p_entity_type;
 IF result#>ARRAY['data',aggregate_key] IS NOT NULL THEN
  result:=jsonb_set(result,'{data}',jsonb_build_object('configuration',public.project_configuration_settings_internal_v1(p_entity_type,result#>ARRAY['data',aggregate_key])));
 END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.save_configuration_settings(text,bigint,bigint,bigint,bigint,uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_configuration_settings(text,bigint,bigint,bigint,bigint,uuid,jsonb) TO authenticated;

-- Public links are an explicit read/write action, rather than included in generic settings reads.
CREATE OR REPLACE FUNCTION public.manage_occasion_public_link(p_occasion bigint,p_organization bigint,p_unit bigint,p_command_id uuid DEFAULT NULL,p_expected_version bigint DEFAULT NULL,p_link text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.check_configuration_scope_internal_v1('occasion',p_occasion,p_organization,p_unit,p_command_id IS NOT NULL);
 IF p_command_id IS NULL THEN
  PERFORM 1 FROM public.occasions WHERE id=p_occasion FOR SHARE;
  PERFORM public.check_configuration_scope_internal_v1('occasion',p_occasion,p_organization,p_unit,false);
  RETURN (SELECT jsonb_build_object('occasionId',o.id,'link',o.link,'aggregateVersion',COALESCE(v.version,0)) FROM public.occasions o LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='occasion' AND v.scope_type='occasion' AND v.scope_id=o.id AND v.aggregate_id=o.id::text WHERE o.id=p_occasion);
 END IF;
 IF p_link IS NULL OR length(p_link)>128 OR p_link !~ '^[a-z0-9]+(-[a-z0-9]+)*$' THEN RAISE invalid_parameter_value USING MESSAGE='invalid public link'; END IF;
 result:=public.save_occasion_client_sync_v1(p_occasion,p_command_id,p_expected_version,jsonb_build_object('id',p_occasion,'link',p_link));
 PERFORM public.check_configuration_scope_internal_v1('occasion',p_occasion,p_organization,p_unit,true);
 IF result#>'{data,occasion}' IS NOT NULL THEN
  result:=jsonb_set(result,'{data}',jsonb_build_object('occasionId',p_occasion,'link',result#>'{data,occasion,link}','aggregateVersion',result#>'{data,occasion,aggregate_version}'));
 END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.manage_occasion_public_link(bigint,bigint,bigint,uuid,bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.manage_occasion_public_link(bigint,bigint,bigint,uuid,bigint,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.manage_game_settings(p_occasion bigint,p_organization bigint,p_unit bigint,p_command_id uuid DEFAULT NULL,p_expected_version bigint DEFAULT NULL,p_start timestamptz DEFAULT NULL,p_end timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF p_command_id IS NULL THEN PERFORM 1 FROM public.occasions WHERE id=p_occasion FOR SHARE;
 ELSE PERFORM 1 FROM public.occasions WHERE id=p_occasion FOR UPDATE; END IF;
 IF auth.uid() IS NULL OR NOT public.can_edit_game_settings(p_occasion)
 OR NOT EXISTS(SELECT FROM public.occasions o JOIN public.user_info ui ON ui.id=auth.uid() AND ui.organization=o.organization WHERE o.id=p_occasion AND o.organization=p_organization AND (p_unit IS NULL OR o.unit=p_unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='game settings scope denied'; END IF;
 IF p_command_id IS NULL THEN RETURN public.get_game_settings_for_authoring_v1(p_occasion); END IF;
 RETURN public.game_update_settings_client_sync_v1(p_occasion,p_start,p_end,p_command_id,p_expected_version);
END $$;
REVOKE ALL ON FUNCTION public.manage_game_settings(bigint,bigint,bigint,uuid,bigint,timestamptz,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.manage_game_settings(bigint,bigint,bigint,uuid,bigint,timestamptz,timestamptz) TO authenticated;
