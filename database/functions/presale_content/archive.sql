-- Private recovery data, never part of forms.data or its public projection.
CREATE TABLE IF NOT EXISTS public.form_presale_content_archive (
 form bigint PRIMARY KEY REFERENCES public.forms(id) ON DELETE CASCADE,
 conversion_id uuid NOT NULL UNIQUE,
 original_version bigint NOT NULL,
 source_hash text NOT NULL,
 original_data jsonb,
 converted_html_hash text NOT NULL,
 result_version bigint NOT NULL,
 converted_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.form_presale_content_archive ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.form_presale_content_archive FROM PUBLIC,anon,authenticated,service_role;

-- All released/current writes pass this boundary under the existing form lock.
-- Null/empty retired fields are ignored; a meaningful old edit requires upgrade.
CREATE OR REPLACE FUNCTION public.guard_form_presale_write_internal(p_previous jsonb,p_input jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE result jsonb:=p_input; incoming jsonb; candidate jsonb; section text; k text;
 previous jsonb:=public.normalize_form_metadata_internal(p_previous); protected boolean; legacy_schedule jsonb; v jsonb;
BEGIN
 protected:=previous#>>'{design,presale_header}' IS NOT NULL;
 IF NOT (p_input ? 'data' OR p_input ? 'settings') THEN RETURN result; END IF;
 incoming:=CASE WHEN p_input ? 'data' THEN public.normalize_form_metadata_internal(p_input->'data') ELSE p_input->'settings' END;
 -- Only converted/new forms use the canonical contract. Other organizations
 -- retain their bounded installed-client ingress until their own authorized
 -- conversion; a shared backend migration must not cut them over implicitly.
 IF NOT protected THEN
  IF incoming#>>'{design,presale_header}' IS NOT NULL THEN
   RAISE invalid_parameter_value USING MESSAGE='PRESALE_MIGRATION_REQUIRED: convert the form before selecting a presale header';
  END IF;
  legacy_schedule:=incoming->'schedule';
  FOREACH k IN ARRAY ARRAY['before_start_message','show_before_start_message'] LOOP
   v:=legacy_schedule->k;
   IF v IS NULL OR v='null'::jsonb THEN CONTINUE; END IF;
   IF (k='before_start_message' AND (jsonb_typeof(v)<>'string' OR length(v#>>'{}')>65536)) OR
      (k='show_before_start_message' AND jsonb_typeof(v)<>'boolean') THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid legacy presale setting';
   END IF;
  END LOOP;
  IF p_input ? 'settings' THEN
   candidate:=public.apply_form_settings_internal(previous,
    incoming #- '{schedule,before_start_message}' #- '{schedule,show_before_start_message}');
   FOREACH k IN ARRAY ARRAY['before_start_message','show_before_start_message'] LOOP
    IF legacy_schedule='null'::jsonb OR legacy_schedule ? k THEN
     IF legacy_schedule='null'::jsonb OR legacy_schedule->k='null'::jsonb THEN
      candidate:=candidate #- ARRAY['schedule',k];
     ELSE
      candidate:=jsonb_set(candidate,'{schedule}',coalesce(candidate->'schedule','{}')||jsonb_build_object(k,legacy_schedule->k));
     END IF;
    END IF;
   END LOOP;
   RETURN jsonb_set(result-'settings','{data}',candidate);
  END IF;
  RETURN jsonb_set(result,'{data}',incoming);
 END IF;
 IF coalesce(incoming#>>'{schedule,before_start_message}','')<>'' OR
    incoming#>>'{schedule,show_before_start_message}'='true' THEN
  RAISE invalid_parameter_value USING MESSAGE='PRESALE_CLIENT_UPGRADE_REQUIRED: reload the form before editing retired content';
 END IF;
 incoming:=incoming #- '{schedule,before_start_message}' #- '{schedule,show_before_start_message}';
 IF protected THEN
  -- Missing/null headings in old full snapshots must never erase the new key.
  IF p_input ? 'settings' AND incoming->'design'='null'::jsonb THEN
   incoming:=jsonb_set(incoming,'{design}',
    (SELECT jsonb_object_agg(value,'null'::jsonb) FROM jsonb_array_elements_text(public.form_settings_keys_internal()->'design')));
  END IF;
  IF incoming#>>'{design,presale_header}' IS NULL THEN
   incoming:=jsonb_set(incoming,'{design}',coalesce(nullif(incoming->'design','null'),'{}') ||
    jsonb_build_object('presale_header',previous#>'{design,presale_header}'));
  END IF;
  IF p_input ? 'data' THEN
   candidate:=public.apply_form_settings_internal(previous,public.form_settings_from_metadata_internal(incoming));
  ELSE candidate:=public.apply_form_settings_internal(previous,incoming); END IF;
  IF p_input->>'expected_aggregate_version' IS NULL THEN
   FOREACH section IN ARRAY ARRAY['schedule','design','sale_opening_notifications'] LOOP
    FOREACH k IN ARRAY CASE section WHEN 'schedule' THEN ARRAY['countdown_title','enable_countdown']
     WHEN 'design' THEN ARRAY['presale_header'] ELSE ARRAY['enabled','collection_paused'] END LOOP
     IF candidate#>ARRAY[section,k] IS DISTINCT FROM previous#>ARRAY[section,k] THEN
      RAISE invalid_parameter_value USING MESSAGE='PRESALE_VERSION_REQUIRED: reload the form before editing the presale page';
     END IF;
    END LOOP;
   END LOOP;
  END IF;
 END IF;
 RETURN jsonb_set(result,ARRAY[CASE WHEN p_input ? 'data' THEN 'data' ELSE 'settings' END],incoming);
END $$;
REVOKE ALL ON FUNCTION public.guard_form_presale_write_internal(jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_form_presale_archive(p_form bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE occasion_id bigint; result jsonb;
BEGIN
 SELECT occasion INTO occasion_id FROM public.forms WHERE id=p_form;
 IF auth.uid() IS NULL OR NOT coalesce(public.can_author_forms(occasion_id),false) THEN
  RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
 SELECT jsonb_build_object('conversionId',conversion_id,'originalVersion',original_version,
  'secondaryHtml',CASE WHEN coalesce((legacy_data#>>'{schedule,show_before_start_message}')::boolean,false)
    AND (coalesce((legacy_data#>>'{schedule,enable_countdown}')::boolean,false)
      OR coalesce(legacy_data#>>'{schedule,countdown_title}','')<>''
      OR coalesce((legacy_data#>>'{sale_opening_notifications,enabled}')::boolean,false))
    THEN NULL ELSE legacy_data#>>'{schedule,before_start_message}' END) INTO result
 FROM (SELECT *,public.normalize_form_metadata_internal(original_data) legacy_data
  FROM public.form_presale_content_archive WHERE form=p_form) archived;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_form_presale_archive(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_form_presale_archive(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.presale_conversion_budgets_internal(p_data jsonb,p_html text,p_snapshot jsonb)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 WITH settings AS (SELECT public.form_settings_from_metadata_internal(p_data||jsonb_build_object(
  'schedule',coalesce(p_data->'schedule','{}')||jsonb_build_object('countdown_title',p_html))) patch),
 sizes AS (SELECT length(p_html) characters,
  octet_length(patch::text) settings_bytes,
  octet_length(jsonb_build_object('operation','forms.save','args',jsonb_build_object(
   'occasionId',coalesce(p_snapshot#>'{form,occasion}','1'::jsonb),
   'commandId','00000000-0000-4000-8000-000000000001',
   'form',jsonb_build_object('id',coalesce(p_snapshot#>'{form,id}','1'::jsonb),
    'expected_aggregate_version',coalesce(p_snapshot#>'{form,aggregate_version}','0'::jsonb),
    'expected_product_versions',coalesce(p_snapshot->'productVersions','{}'),
    'expected_product_type_versions',coalesce(p_snapshot->'productTypeVersions','{}'),
    'settings',patch)))::text)+1024 transport_bytes,
  octet_length(p_snapshot::text)+1024 snapshot_bytes FROM settings)
 SELECT jsonb_build_object('characters',characters,'settingsBytes',settings_bytes,
  'transportBytes',transport_bytes,'snapshotBytes',snapshot_bytes,
  'blocked',characters>65536 OR settings_bytes>131072 OR transport_bytes>48000 OR snapshot_bytes>1048576) FROM sizes;
$$;
REVOKE ALL ON FUNCTION public.presale_conversion_budgets_internal(jsonb,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Explicit operational conversion, not a read fallback or application trigger.
-- The pure converter supplies reviewed HTML; original hash and version bind it
-- to exactly the preflight input. No campaign/subscriber/queue writes occur.
CREATE OR REPLACE FUNCTION public.convert_form_presale_content(
 p_form bigint,p_expected_version bigint,p_source_hash text,p_html text,p_conversion_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE f public.forms%ROWTYPE; occasion_id bigint; version_now bigint; saved public.form_presale_content_archive%ROWTYPE;
 d jsonb; html_hash text; snapshot jsonb;
BEGIN
 SELECT occasion INTO occasion_id FROM public.forms WHERE id=p_form;
 IF auth.uid() IS NULL OR NOT coalesce(public.can_author_forms(occasion_id),false) THEN
  RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occasion_id]);
 SELECT * INTO f FROM public.forms WHERE id=p_form FOR UPDATE;
 html_hash:=encode(extensions.digest(convert_to(p_html,'UTF8'),'sha256'),'hex');
 SELECT * INTO saved FROM public.form_presale_content_archive WHERE form=p_form;
 IF FOUND THEN
  IF saved.conversion_id IS DISTINCT FROM p_conversion_id OR saved.source_hash IS DISTINCT FROM p_source_hash
    OR saved.converted_html_hash IS DISTINCT FROM html_hash THEN
   RAISE invalid_parameter_value USING MESSAGE='presale conversion identity mismatch'; END IF;
  RETURN jsonb_build_object('form',p_form,'version',saved.result_version,'replayed',true);
 END IF;
 IF p_html IS NULL OR p_conversion_id IS NULL OR p_expected_version IS NULL OR
    encode(extensions.digest(convert_to(coalesce(f.data,'{}')::text,'UTF8'),'sha256'),'hex') IS DISTINCT FROM p_source_hash THEN
  RAISE invalid_parameter_value USING MESSAGE='presale source changed'; END IF;
 IF f.data#>>'{design,presale_header}' IS NOT NULL THEN
  RAISE invalid_parameter_value USING MESSAGE='form already uses canonical presale content'; END IF;
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
 VALUES('form','occasion',f.occasion,p_form::text,0) ON CONFLICT DO NOTHING;
 SELECT version INTO version_now FROM public.client_aggregate_versions WHERE aggregate_type='form'
  AND scope_type='occasion' AND scope_id=f.occasion AND aggregate_id=p_form::text FOR UPDATE;
 IF version_now<>p_expected_version THEN RAISE serialization_failure USING MESSAGE='presale version conflict'; END IF;
 d:=public.normalize_form_metadata_internal(f.data);
 d:=jsonb_set(d,'{schedule}',coalesce(d->'schedule','{}')-'before_start_message'-'show_before_start_message'||jsonb_build_object('countdown_title',p_html));
 d:=jsonb_set(d,'{design}',coalesce(d->'design','{}')||jsonb_build_object('presale_header',
  CASE WHEN coalesce((d#>>'{schedule,enable_countdown}')::boolean,false) THEN 'date' ELSE 'none' END));
 -- Preflight uses the same byte budgets; recheck against the real saved
 -- snapshot before commit. A failed check rolls back archive and page together.
 PERFORM public.apply_form_settings_internal(d,jsonb_build_object('schedule',jsonb_build_object('countdown_title',p_html)));
 INSERT INTO public.form_presale_content_archive(form,conversion_id,original_version,source_hash,original_data,converted_html_hash,result_version)
 VALUES(p_form,p_conversion_id,version_now,p_source_hash,f.data,html_hash,version_now+1);
 UPDATE public.forms SET data=d,updated_at=clock_timestamp() WHERE id=p_form;
 UPDATE public.client_aggregate_versions SET version=version+1,updated_at=clock_timestamp()
 WHERE aggregate_type='form' AND scope_type='occasion' AND scope_id=f.occasion AND aggregate_id=p_form::text;
 snapshot:=public.get_form_authoring_snapshot_internal(p_form);
 IF (public.presale_conversion_budgets_internal(d,p_html,snapshot)->>'blocked')::boolean THEN
  RAISE program_limit_exceeded USING MESSAGE='PRESALE_SIZE_BLOCKED'; END IF;
 RETURN jsonb_build_object('form',p_form,'version',version_now+1,'replayed',false);
END $$;
REVOKE ALL ON FUNCTION public.convert_form_presale_content(bigint,bigint,text,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.convert_form_presale_content(bigint,bigint,text,text,uuid) TO authenticated;
