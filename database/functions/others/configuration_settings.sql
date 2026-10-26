-- Narrow authoring intent, shared by UI and MCP. Never a caller-selected JSON path.
CREATE OR REPLACE FUNCTION public.validate_configuration_value_internal_v1(value jsonb, rule jsonb)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE k text; item jsonb; kind text:=rule->>'type';
BEGIN
 IF value='null'::jsonb AND COALESCE((rule->>'nullable')::boolean,false) THEN RETURN; END IF;
 IF kind IN ('string','datetime','email','timezone') THEN
  IF jsonb_typeof(value)<>'string' OR length(value#>>'{}')>COALESCE((rule->>'maxLength')::int,8192) THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid settings text'; END IF;
  IF kind='email' AND (value#>>'{}') !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid Reply-To'; END IF;
  IF kind='timezone' AND NOT EXISTS(SELECT FROM pg_timezone_names WHERE name=value#>>'{}') THEN
   RAISE invalid_parameter_value USING MESSAGE='unknown timezone'; END IF;
  IF kind='datetime' THEN
   IF (value#>>'{}') !~ '(Z|[+-][0-9]{2}:[0-9]{2})$' THEN RAISE invalid_parameter_value USING MESSAGE='explicit timestamp offset required'; END IF;
   PERFORM (value#>>'{}')::timestamptz;
  END IF;
 ELSIF kind IN ('integer','number') THEN
  IF jsonb_typeof(value)<>'number' THEN RAISE invalid_parameter_value USING MESSAGE='invalid settings number'; END IF;
  IF (kind='integer' AND (value#>>'{}')::numeric<>trunc((value#>>'{}')::numeric))
   OR (rule ? 'minimum' AND (value#>>'{}')::numeric<(rule->>'minimum')::numeric)
   OR (rule ? 'maximum' AND (value#>>'{}')::numeric>(rule->>'maximum')::numeric) THEN
   RAISE invalid_parameter_value USING MESSAGE='settings number out of range'; END IF;
 ELSIF kind='boolean' THEN
  IF jsonb_typeof(value)<>'boolean' THEN RAISE invalid_parameter_value USING MESSAGE='invalid settings boolean'; END IF;
 ELSIF kind='object' THEN
  IF jsonb_typeof(value)<>'object' THEN RAISE invalid_parameter_value USING MESSAGE='invalid settings object'; END IF;
  IF EXISTS(SELECT FROM jsonb_array_elements_text(COALESCE(rule->'required','[]')) AS required_keys(required_key) WHERE NOT value ? required_key) THEN
   RAISE invalid_parameter_value USING MESSAGE='incomplete settings object'; END IF;
  FOR k,item IN SELECT * FROM jsonb_each(value) LOOP
   IF NOT (rule->'properties' ? k) THEN RAISE invalid_parameter_value USING MESSAGE='unsupported settings field'; END IF;
   PERFORM public.validate_configuration_value_internal_v1(item,rule->'properties'->k);
  END LOOP;
 ELSIF kind='array' THEN
  IF jsonb_typeof(value)<>'array' OR jsonb_array_length(value)>COALESCE((rule->>'maxItems')::int,100) THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid settings array'; END IF;
  FOR item IN SELECT * FROM jsonb_array_elements(value) LOOP
   PERFORM public.validate_configuration_value_internal_v1(item,rule->'items');
  END LOOP;
 ELSE RAISE invalid_parameter_value USING MESSAGE='unsupported settings type'; END IF;
 IF rule ? 'enum' AND NOT (rule->'enum' @> jsonb_build_array(value)) THEN RAISE invalid_parameter_value USING MESSAGE='invalid settings choice'; END IF;
 IF rule ? 'pattern' AND (value#>>'{}') !~ (rule->>'pattern') THEN RAISE invalid_parameter_value USING MESSAGE='invalid settings format'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.validate_configuration_value_internal_v1(jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.merge_configuration_settings_internal_v1(current_data jsonb, settings jsonb, scope text)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE k text; value jsonb; result jsonb:=COALESCE(NULLIF(current_data,'null'::jsonb),'{}');
BEGIN
 PERFORM public.validate_configuration_value_internal_v1(settings,jsonb_build_object('type','object','properties',public.configuration_settings_contract_internal_v1()->scope));
 FOR k,value IN SELECT * FROM jsonb_each(settings) LOOP
  result:=CASE WHEN value='null'::jsonb THEN result-k ELSE jsonb_set(result,ARRAY[k],value,true) END;
 END LOOP;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.merge_configuration_settings_internal_v1(jsonb,jsonb,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.apply_occasion_settings_intent_internal_v1(p_occasion bigint, intent jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE current_row public.occasions%ROWTYPE; result jsonb:=intent; f jsonb; old_f jsonb;
 features jsonb; patch jsonb; code text; k text; rule jsonb; supported boolean;
 spec jsonb:=public.configuration_settings_contract_internal_v1();
BEGIN
 SELECT * INTO STRICT current_row FROM public.occasions WHERE id=p_occasion;
 SELECT COALESCE((data->>'IS_APP_SUPPORTED')::boolean,false) INTO supported FROM public.organizations WHERE id=current_row.organization;
 IF intent ? 'settings' THEN
  IF intent ? 'data' THEN RAISE invalid_parameter_value USING MESSAGE='choose settings intent or legacy data'; END IF;
  result:=(result-'settings')||jsonb_build_object('data',public.merge_configuration_settings_internal_v1(current_row.data,intent->'settings','occasion'));
 ELSIF intent ? 'data' THEN
  -- Released full-snapshot clients retain their boundary; known fields share validation.
  IF jsonb_typeof(intent->'data')<>'object' THEN RAISE invalid_parameter_value USING MESSAGE='invalid occasion metadata'; END IF;
  FOR k,rule IN SELECT * FROM jsonb_each(spec->'occasion') LOOP
   IF intent->'data' ? k THEN PERFORM public.validate_configuration_value_internal_v1(intent->'data'->k,rule); END IF;
  END LOOP;
 END IF;
 IF result#>>'{data,image}' IS DISTINCT FROM current_row.data->>'image' AND result#>>'{data,image}' IS NOT NULL
  AND NOT EXISTS(SELECT FROM public.images WHERE link=result#>>'{data,image}' AND (occasion=p_occasion OR unit=current_row.unit)) THEN
  RAISE invalid_parameter_value USING MESSAGE='image must belong to the occasion or its organizer'; END IF;
 IF result ? 'data' THEN result:=jsonb_set(result,'{data}',jsonb_set(result->'data','{client_sync_v1}',COALESCE(current_row.data->'client_sync_v1','false'),true)); END IF;
 IF intent ? 'feature_changes' THEN
  IF intent ? 'features' OR jsonb_typeof(intent->'feature_changes')<>'array' OR jsonb_array_length(intent->'feature_changes')>25 THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid feature settings intent'; END IF;
  features:=COALESCE(current_row.features,'[]');
  IF (SELECT count(*)<>count(DISTINCT x->>'code') FROM jsonb_array_elements(intent->'feature_changes') x) THEN
   RAISE invalid_parameter_value USING MESSAGE='duplicate feature'; END IF;
  FOR patch IN SELECT * FROM jsonb_array_elements(intent->'feature_changes') LOOP
   code:=patch->>'code';
   IF NOT (spec->'features' ? code) THEN RAISE invalid_parameter_value USING MESSAGE='unsupported feature'; END IF;
   PERFORM public.validate_configuration_value_internal_v1(patch-'code',jsonb_build_object('type','object','properties',spec->'features'->code));
   SELECT value INTO old_f FROM jsonb_array_elements(features) WHERE value->>'code'=code;
   f:=COALESCE(old_f,jsonb_build_object('code',code,'is_enabled',false))||patch;
   SELECT COALESCE(jsonb_agg(value),'[]') INTO features FROM jsonb_array_elements(features) WHERE value->>'code'<>code;
   features:=features||jsonb_build_array(f);
  END LOOP;
  result:=(result-'feature_changes')||jsonb_build_object('features',features);
 ELSIF NOT (intent ? 'features') THEN
  result:=result||jsonb_build_object('features',COALESCE(current_row.features,'[]'));
 END IF;
 -- Validate shared known settings on both current intent and released snapshots.
 IF jsonb_typeof(result->'features')<>'array' THEN RAISE invalid_parameter_value USING MESSAGE='invalid features'; END IF;
 FOR f IN SELECT * FROM jsonb_array_elements(result->'features') LOOP
  code:=f->>'code';
  SELECT value INTO old_f FROM jsonb_array_elements(COALESCE(current_row.features,'[]')) WHERE value->>'code'=code;
  IF f IS DISTINCT FROM old_f AND spec->'features' ? code THEN
   IF code='map' THEN
    FOR patch IN SELECT * FROM jsonb_array_elements(jsonb_build_array(f->'map_layer',f->'map_layer_offline')) LOOP
     IF COALESCE((patch->>'forceOfflineMap')::boolean,false) AND NULLIF(btrim(patch->>'offlineMapBundleManifestURL'),'') IS NULL THEN
      RAISE invalid_parameter_value USING MESSAGE='MapLibre requires a bundle manifest'; END IF;
    END LOOP;
   END IF;
   FOR k,rule IN SELECT * FROM jsonb_each(spec->'features'->code) LOOP
    IF f ? k THEN PERFORM public.validate_configuration_value_internal_v1(f->k,rule); END IF;
   END LOOP;
  END IF;
  IF code='program_notifications' AND COALESCE((f->>'is_enabled')::boolean,false) THEN RAISE invalid_parameter_value USING MESSAGE='program notifications delivery is not implemented'; END IF;
  IF NOT supported AND spec->'appOnly' ? code AND COALESCE((f->>'is_enabled')::boolean,false)
   AND NOT COALESCE((old_f->>'is_enabled')::boolean,false) THEN RAISE invalid_parameter_value USING MESSAGE='feature requires app-supported tenant'; END IF;
  IF NOT supported AND code='form' AND NOT COALESCE((f->>'is_enabled')::boolean,false) THEN
   RAISE invalid_parameter_value USING MESSAGE='form is required for this tenant'; END IF;
 END LOOP;
 IF intent ? 'title' AND intent->'title'<>'null'::jsonb AND (jsonb_typeof(intent->'title')<>'string' OR nullif(btrim(intent->>'title'),'') IS NULL OR length(intent->>'title')>512) THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid occasion title'; END IF;
 IF COALESCE((intent->>'start_time')::timestamptz,current_row.start_time)>COALESCE((intent->>'end_time')::timestamptz,current_row.end_time) THEN
  RAISE invalid_parameter_value USING MESSAGE='occasion start must precede end'; END IF;
 IF COALESCE((intent->>'is_promoted')::boolean,current_row.is_promoted) AND NULLIF(COALESCE(result->'data',current_row.data)->>'image','') IS NULL THEN
  RAISE invalid_parameter_value USING MESSAGE='promotion requires an occasion image'; END IF;
 IF COALESCE((current_row.data->>'client_sync_v1')::boolean,false) AND NOT current_row.is_hidden AND COALESCE((intent->>'is_hidden')::boolean,false) THEN
  RAISE object_not_in_prerequisite_state USING MESSAGE='disable client_sync_v1 before hiding occasion'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.apply_occasion_settings_intent_internal_v1(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
