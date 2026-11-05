-- Canonical presale content owners. No production conversion is automatic.

-- Source: database/functions/eshop_forms/form_settings.sql
-- Metadata patch owner for all administrative form settings. Private helpers;
-- authorization, locking, receipt and side effects stay in the form command.
CREATE OR REPLACE FUNCTION public.form_settings_keys_internal()
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT '{"is_reminder_enabled":null,"reminder_interval_seconds":null,"communication_tone":null,
 "variable_symbol":["type","starting_number"],"payment_message":["type"],
 "payments":["bankEnabled","stripeConnectionId"],
 "design":["is_card_design","primary_color","secondary_color","background_mode","theme_mode","font_family","countdown_style","presale_header"],
 "sale_opening_notifications":["enabled","collection_paused"],
 "schedule":["start_time","end_time","enable_countdown","countdown_title"]}'::jsonb;
$$;

CREATE OR REPLACE FUNCTION public.normalize_form_metadata_internal(p_data jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE result jsonb:='{}'; item jsonb; section jsonb; k text;
BEGIN
 IF p_data IS NULL OR p_data='null'::jsonb THEN RETURN result; END IF;
 IF jsonb_typeof(p_data)='object' THEN result:=p_data;
 ELSIF jsonb_typeof(p_data)='array' THEN
  -- Released readers already normalize historical [null,{metadata}] bundles.
  FOR item IN SELECT value FROM jsonb_array_elements(p_data) LOOP
   IF item='null'::jsonb THEN CONTINUE; END IF;
   IF jsonb_typeof(item)<>'object' THEN RAISE invalid_parameter_value USING MESSAGE='invalid form metadata'; END IF;
   result:=result||item;
  END LOOP;
 ELSE RAISE invalid_parameter_value USING MESSAGE='invalid form metadata';
 END IF;
 section:=coalesce(nullif(result->'schedule','null'::jsonb),'{}'::jsonb);
 IF jsonb_typeof(section)<>'object' THEN RAISE invalid_parameter_value USING MESSAGE='invalid form schedule'; END IF;
 FOREACH k IN ARRAY ARRAY['start_time','end_time'] LOOP
  -- Match the runtime reader's historical nested/root precedence, then retire
  -- the root alias. Otherwise clearing a nested override resurrects old dates.
  IF (NOT section ? k OR section->k='null'::jsonb) AND result ? k THEN
   section:=section||jsonb_build_object(k,result->k);
  END IF;
  result:=result-k;
  IF section->>k='' THEN section:=section-k;
  ELSIF section->>k IS NOT NULL AND (section->>k) !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$' THEN
   -- Interpret released timestamps exactly as the existing runtime did. Emit
   -- an explicit instant for current editors; new patches still require ISO.
   section:=section||jsonb_build_object(k,(section->>k)::timestamptz);
  END IF;
 END LOOP;
 IF section='{}'::jsonb THEN result:=result-'schedule';
 ELSE result:=result||jsonb_build_object('schedule',section); END IF;
 RETURN result;
END $$;

-- Full released-client metadata is translated to the same known-settings patch.
CREATE OR REPLACE FUNCTION public.form_settings_from_metadata_internal(p_data jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE result jsonb:='{}'; d jsonb:=public.normalize_form_metadata_internal(p_data); spec record; k text; section jsonb;
BEGIN
 FOR spec IN SELECT * FROM jsonb_each(public.form_settings_keys_internal()) LOOP
  IF spec.key='sale_opening_notifications' AND NOT d ? spec.key THEN CONTINUE; END IF;
  IF spec.value='null'::jsonb OR NOT d ? spec.key OR d->spec.key='null'::jsonb THEN
   result:=result||jsonb_build_object(spec.key,coalesce(d->spec.key,'null'::jsonb));
  ELSE
   IF jsonb_typeof(d->spec.key)<>'object' THEN RAISE invalid_parameter_value USING MESSAGE='invalid form settings section: '||spec.key; END IF;
   section:='{}';
   FOR k IN SELECT jsonb_array_elements_text(spec.value) LOOP
    section:=section||jsonb_build_object(k,coalesce(d->spec.key->k,'null'::jsonb));
   END LOOP;
   result:=result||jsonb_build_object(spec.key,section);
  END IF;
 END LOOP;
 RETURN result;
END $$;

CREATE OR REPLACE FUNCTION public.apply_form_settings_internal(p_data jsonb,p_patch jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE result jsonb:=public.normalize_form_metadata_internal(p_data); spec jsonb:=public.form_settings_keys_internal();
 entry record; field record; section jsonb; v jsonb; k text; path text; n numeric; starts timestamptz; ends timestamptz;
BEGIN
 IF p_patch IS NULL OR jsonb_typeof(p_patch)<>'object' OR octet_length(p_patch::text)>131072 THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid form settings patch'; END IF;
 FOR entry IN SELECT * FROM jsonb_each(p_patch) LOOP
  IF NOT spec ? entry.key THEN RAISE invalid_parameter_value USING MESSAGE='unsupported form setting: '||entry.key; END IF;
  IF spec->entry.key='null'::jsonb THEN
   IF entry.value='null'::jsonb THEN result:=result-entry.key; CONTINUE; END IF;
   IF entry.key='is_reminder_enabled' AND jsonb_typeof(entry.value)<>'boolean' THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid reminder mode'; END IF;
   IF entry.key='reminder_interval_seconds' THEN
    IF jsonb_typeof(entry.value)<>'number' THEN RAISE invalid_parameter_value USING MESSAGE='invalid reminder interval'; END IF;
    n:=(entry.value::text)::numeric;
    IF n<>trunc(n) OR n<0 OR n>9007199254740991 THEN RAISE invalid_parameter_value USING MESSAGE='invalid reminder interval'; END IF;
   END IF;
   IF entry.key='communication_tone' AND entry.value NOT IN ('"formal"'::jsonb,'"informal"'::jsonb) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid communication tone'; END IF;
   result:=result||jsonb_build_object(entry.key,entry.value);
   CONTINUE;
  END IF;
  IF entry.value<>'null'::jsonb AND jsonb_typeof(entry.value)<>'object' THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid form settings section: '||entry.key; END IF;
  section:=coalesce(nullif(result->entry.key,'null'::jsonb),'{}'::jsonb);
  IF jsonb_typeof(section)<>'object' THEN section:='{}'; END IF;
  FOR field IN
   SELECT * FROM jsonb_each(CASE WHEN entry.value='null'::jsonb THEN
    (SELECT jsonb_object_agg(value,'null'::jsonb) FROM jsonb_array_elements_text(spec->entry.key)) ELSE entry.value END)
  LOOP
   k:=field.key;v:=field.value;path:=entry.key||'.'||k;
   IF NOT (spec->entry.key) ? k THEN RAISE invalid_parameter_value USING MESSAGE='unsupported form setting: '||path; END IF;
   IF v='null'::jsonb THEN section:=section-k;CONTINUE; END IF;
   IF path IN ('payments.bankEnabled','design.is_card_design','schedule.enable_countdown','sale_opening_notifications.enabled','sale_opening_notifications.collection_paused') THEN
    IF jsonb_typeof(v)<>'boolean' THEN RAISE invalid_parameter_value USING MESSAGE='invalid boolean setting: '||path; END IF;
   ELSIF path='variable_symbol.starting_number' THEN
    IF jsonb_typeof(v)<>'number' OR v::text !~ '^[0-9]{1,10}$' OR (v::text)::bigint NOT BETWEEN 1 AND 9999999999 THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid sequence starting number'; END IF;
   ELSE
    IF jsonb_typeof(v)<>'string' THEN RAISE invalid_parameter_value USING MESSAGE='invalid string setting: '||path; END IF;
    IF length(v#>>'{}')>(CASE WHEN path IN ('schedule.countdown_title') THEN 65536 ELSE 128 END) THEN
     RAISE invalid_parameter_value USING MESSAGE='form setting too long: '||path; END IF;
    IF path='variable_symbol.type' AND v NOT IN ('"random"'::jsonb,'"sequence"'::jsonb) OR
       path='payment_message.type' AND v NOT IN ('"name_surname"'::jsonb,'"none"'::jsonb,'"occasion_title"'::jsonb) THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid setting mode: '||path; END IF;
    IF path='design.presale_header' AND v NOT IN ('"event_and_date"'::jsonb,'"date"'::jsonb,'"none"'::jsonb) THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid presale header'; END IF;
    IF path='design.theme_mode'  AND v NOT IN ('"system"'::jsonb,'"light"'::jsonb,'"dark"'::jsonb) THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid form theme mode'; END IF;
    IF path='design.background_mode' AND v NOT IN ('"solid"'::jsonb,'"gradient"'::jsonb) THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid background mode'; END IF;
    IF path IN ('design.primary_color','design.secondary_color') AND (v#>>'{}') !~ '^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$' THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid design color'; END IF;
    IF path IN ('design.font_family','design.countdown_style') AND length(btrim(v#>>'{}'))=0 THEN
     RAISE invalid_parameter_value USING MESSAGE='empty design setting'; END IF;
    IF path='payments.stripeConnectionId' THEN PERFORM (v#>>'{}')::uuid; END IF;
    IF path IN ('schedule.start_time','schedule.end_time') THEN
     IF (v#>>'{}') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$' THEN
      RAISE invalid_parameter_value USING MESSAGE='schedule requires an ISO instant with explicit timezone'; END IF;
     PERFORM (v#>>'{}')::timestamptz;
    END IF;
   END IF;
   section:=section||jsonb_build_object(k,v);
  END LOOP;
  -- Section reset removes only known authoring keys, preserving lifecycle flags
  -- (sale_preparation) and unrelated metadata owned by other contracts.
  IF section='{}'::jsonb THEN result:=result-entry.key;
  ELSE result:=result||jsonb_build_object(entry.key,section); END IF;
 END LOOP;
 IF p_patch ? 'variable_symbol' AND result#>>'{variable_symbol,type}'='sequence' AND
   (coalesce(result#>>'{variable_symbol,starting_number}','') !~ '^[0-9]{1,10}$' OR
    (result#>>'{variable_symbol,starting_number}')::bigint NOT BETWEEN 1 AND 9999999999) THEN
  RAISE invalid_parameter_value USING MESSAGE='sequence requires starting number'; END IF;
 IF p_patch ? 'schedule' THEN
  starts:=nullif(result#>>'{schedule,start_time}','')::timestamptz;
  ends:=nullif(result#>>'{schedule,end_time}','')::timestamptz;
  IF ends<starts THEN RAISE invalid_parameter_value USING MESSAGE='form sale end precedes start'; END IF;
 END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.form_settings_keys_internal(),public.normalize_form_metadata_internal(jsonb),
 public.form_settings_from_metadata_internal(jsonb),public.apply_form_settings_internal(jsonb,jsonb)
 FROM PUBLIC,anon,authenticated,service_role;

-- Source: database/functions/presale_content/archive.sql
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
DECLARE f public.forms%ROWTYPE; version_now bigint; saved public.form_presale_content_archive%ROWTYPE;
 d jsonb; html_hash text; snapshot jsonb;
BEGIN
 SELECT * INTO f FROM public.forms WHERE id=p_form;
 IF auth.uid() IS NULL OR NOT coalesce(public.can_author_forms(f.occasion),false) THEN
  RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[f.occasion]);
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

-- Source: database/functions/eshop_forms/form_creation_domain.sql
-- Shared form construction. Invoker-only, private to explicit checked owners.
CREATE OR REPLACE FUNCTION public.insert_form_for_occasion_internal_v1(p_occasion_id bigint, p_link text, p_title text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    new_form_id BIGINT;
    new_form JSONB;
    new_product_type_id BIGINT;
    now TIMESTAMPTZ := NOW();
    payment_default text;
    initial_data jsonb := '{"is_reminder_enabled": true,"design":{"presale_header":"event_and_date"}}'::jsonb;
BEGIN
    SELECT org.data->>'DEFAULT_FORM_PAYMENT_METHOD' INTO payment_default
    FROM public.occasions o JOIN public.organizations org ON org.id=o.organization
    WHERE o.id=p_occasion_id;
    IF payment_default = 'stripe' THEN
      -- A closed draft can await Connect without inventing a recipient or bank.
      initial_data := initial_data || '{"payments":{"bankEnabled":false}}'::jsonb;
    END IF;
    PERFORM public.notification_center_initialized_internal((SELECT organization FROM public.occasions WHERE id=p_occasion_id));
    -- Create the new form
    INSERT INTO public.forms(
        title,
        is_open,
        link,
        occasion,
        created_at,
        updated_at,
        deadline_duration_seconds,
        data
    )
    VALUES (
        p_title,
        false,
        NULL,
        p_occasion_id,
        now,
        now,
        604800, -- Default to 7 days
        initial_data
    )
    RETURNING to_jsonb(public.forms.*) INTO new_form;

    new_form_id := (new_form->>'id')::BIGINT;

    UPDATE public.forms SET link=public.reserve_public_link_internal('form',new_form_id,p_link,true) WHERE id=new_form_id;
    SELECT to_jsonb(f) INTO new_form FROM public.forms f WHERE id=new_form_id;

    -- Create default 'email' and 'ticket' fields
    INSERT INTO public.form_fields(title, type, is_required, form, "order")
    VALUES ('', 'email', true, new_form_id, 0),
           ('', 'ticket', true, new_form_id, 1);

    -- Ensure 'spot' product type exists for the occasion
    IF NOT EXISTS (SELECT 1 FROM eshop.product_types WHERE occasion = p_occasion_id AND type = 'spot') THEN
        INSERT INTO eshop.product_types(title, type, occasion)
        VALUES ('Spot', 'spot', p_occasion_id)
        RETURNING id INTO new_product_type_id;
    ELSE
        SELECT id INTO new_product_type_id FROM eshop.product_types WHERE occasion = p_occasion_id AND type = 'spot' LIMIT 1;
    END IF;

    -- Ensure the 'spot' product type has at least one product
    IF NOT EXISTS (SELECT 1 FROM eshop.products WHERE occasion = p_occasion_id AND product_type = new_product_type_id) THEN
        INSERT INTO eshop.products(title, price, product_type, occasion, currency_code, "order")
        VALUES ('Variant 1', 100, new_product_type_id, p_occasion_id, 'CZK', 0);
    END IF;

    -- Create the 'product_type' form field linked to 'spot'
    INSERT INTO public.form_fields(title, type, is_required, form, "order", product_type, is_ticket_field)
    VALUES ('Spot', 'product_type', false, new_form_id, 2, new_product_type_id, true);

    -- Return the raw data of the newly created form
    PERFORM public.notification_center_form_created_internal(new_form_id);
    RETURN new_form;
END;
$function$;
REVOKE ALL ON FUNCTION public.insert_form_for_occasion_internal_v1(bigint,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.insert_form_for_occasion_internal_v1(bigint,text,text) TO postgres;

-- Only the explicit occasion-create owner calls this initial-form boundary.
-- Manager-only creation uses its own domain right, not a fabricated editor role.
CREATE OR REPLACE FUNCTION public.create_initial_occasion_form_internal_v1(p_occasion_id bigint,p_link text,p_title text)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE v_unit bigint;
BEGIN
  SELECT unit INTO v_unit FROM public.occasions WHERE id=p_occasion_id FOR UPDATE;
  IF NOT FOUND OR auth.uid() IS NULL OR NOT public.can_create_occasion(v_unit)
    OR EXISTS(SELECT 1 FROM public.forms WHERE occasion=p_occasion_id) THEN
    RAISE insufficient_privilege USING MESSAGE='initial occasion form creation unavailable';
  END IF;
  PERFORM public.check_occasion_writable(p_occasion_id);
  RETURN public.insert_form_for_occasion_internal_v1(p_occasion_id,p_link,p_title);
END $$;
REVOKE ALL ON FUNCTION public.create_initial_occasion_form_internal_v1(bigint,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_initial_occasion_form_internal_v1(bigint,text,text) TO postgres;

-- Source: database/functions/eshop_forms/update_form.sql
CREATE OR REPLACE FUNCTION public.update_form_internal_v1(input_data JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    ----------------------------------------------------------------------------
    -- Declarations
    ----------------------------------------------------------------------------
    result JSONB;
    availability_at timestamptz;
    form_metadata jsonb;
    previous_form_metadata jsonb;
    availability_new boolean;
    deleted_fields BIGINT[];
    deleted_products BIGINT[];
    deletion_reason TEXT;
    deletion_row RECORD;
    protected_primary_types bigint[];

    form_id          BIGINT;               -- ID of the form being created/updated
    occasion_id      BIGINT;               -- ID of the occasion to which the form belongs
    now_ts           TIMESTAMPTZ := NOW(); -- Current timestamp for record updates

    link_param           TEXT;         -- Unique link for the form, must not conflict within the same org
    occasion_org         BIGINT;       -- Organization stored in the occasions table
    occasion_unit        BIGINT;       -- The 'unit' that must match for bank accounts
    conflict_check       INT;          -- Used for verifying uniqueness constraints
    deadline_val         BIGINT;       -- Field for validating form deadlines
    price_val            NUMERIC;      -- Field for validating product price

    bank_account_val     BIGINT;       -- Bank account from input_data
    bank_account_unit    BIGINT;       -- Unit of the bank account, must match occasion_unit

    v_seconds_before_deadline BIGINT; -- For calling the reminder queue function

    ----------------------------------------------------------------------------
    -- Since product_type data is now inside form_fields, we no longer read from
    -- a top-level product_types array. Instead, we will parse product_type objects
    -- directly from each form_field (if present).
    ----------------------------------------------------------------------------

    product_type_data    JSONB;        -- The JSONB data for product_type within a form_field
    product_type_id      BIGINT;       -- ID (new or existing) of the product_type
    product_type_occ     BIGINT;       -- For checking product_type's occasion

    products_data        JSONB;        -- JSONB array of products inside a product_type
    product_array_data   JSONB;        -- Rebuilt array of products
    product_data         JSONB;        -- Each product object from the products array
    product_id           BIGINT;       -- ID for a product (new or existing)
    product_occ          BIGINT;       -- Occasion check for an existing product

    ----------------------------------------------------------------------------
    -- form_fields data
    ----------------------------------------------------------------------------
    form_fields_data     JSONB := '[]'::JSONB; -- Final array of form_fields for the response
    field_data           JSONB;                -- Each form_field from input
    field_id             BIGINT;               -- ID for a form_field (new or existing)
    field_product_type   BIGINT;               -- Will store the final product_type.id for the form_field
    field_occ            BIGINT;               -- Verify product_type's occasion if referenced
BEGIN
    BEGIN
        /* All logic is inside this sub-block so we can catch exceptions similarly
           to how it's done in create_ticket_order, with a single EXCEPTION WHEN OTHERS THEN.
           We raise exceptions in JSON form, and if it's JSON, we return it as-is; otherwise,
           we build a default JSON error response. */

        ----------------------------------------------------------------------------
        -- Begin main logic


        ----------------------------------------------------------------------------

        -- Validate that input_data and essential fields exist
        IF input_data IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4001, 'message', 'Input data is missing')::TEXT;
        END IF;

        IF input_data->>'occasion' IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4002, 'message', 'Missing occasion ID in input data')::TEXT;
        END IF;

        occasion_id := (input_data->>'occasion')::BIGINT;
        IF occasion_id IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4002, 'message', 'Invalid or missing occasion ID')::TEXT;
        END IF;

        -- Retrieve the occasion's organization and unit
        SELECT o.organization, o.unit
          INTO occasion_org, occasion_unit
          FROM public.occasions o
         WHERE o.id = occasion_id
         LIMIT 1;

        IF occasion_org IS NULL OR occasion_unit IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4017, 'message', 'Occasion not found or missing required fields')::TEXT;
        END IF;

        IF NOT public.is_service_role() AND NOT public.can_author_forms(occasion_id) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
        PERFORM public.notification_center_initialized_internal(occasion_org);
        PERFORM public.lock_blueprint_scope_internal(ARRAY[occasion_id]);
        availability_at:=clock_timestamp();
        form_id := NULLIF(input_data->>'id','')::bigint;
        availability_new:=form_id IS NULL;
        IF form_id IS NOT NULL THEN
          IF NOT EXISTS(SELECT 1 FROM public.forms WHERE id=form_id AND occasion=occasion_id) THEN RAISE invalid_parameter_value USING MESSAGE='Form does not match occasion'; END IF;
          PERFORM 1 FROM public.forms WHERE id=form_id AND occasion=occasion_id FOR UPDATE;
          PERFORM public.notification_center_form_availability_internal(form_id,availability_at);
        END IF;
        IF form_id IS NULL THEN
          INSERT INTO public.forms(created_at,occasion) VALUES(now_ts,occasion_id) RETURNING id INTO form_id;
          link_param := public.reserve_public_link_internal('form',form_id,input_data->>'link',true);
        ELSE
          IF NOT EXISTS (SELECT 1 FROM public.forms WHERE id=form_id AND occasion=occasion_id) THEN
            RAISE invalid_parameter_value USING MESSAGE='Form does not match occasion'; END IF;
          link_param := public.reserve_public_link_internal('form',form_id,input_data->>'link',false);
        END IF;

        IF input_data ? 'settings' AND input_data ? 'data' THEN
          RAISE invalid_parameter_value USING MESSAGE='choose settings patch or released metadata, not both'; END IF;
        SELECT data INTO form_metadata FROM public.forms WHERE id=form_id;
        previous_form_metadata:=form_metadata;
        input_data:=public.guard_form_presale_write_internal(form_metadata,input_data);
        IF input_data ? 'settings' THEN
          form_metadata:=public.apply_form_settings_internal(form_metadata,input_data->'settings');
        ELSIF input_data ? 'data' THEN
          -- Released full-metadata boundary, same settings owner/validation.
          form_metadata:=public.normalize_form_metadata_internal(input_data->'data')
            ||CASE WHEN NOT public.normalize_form_metadata_internal(input_data->'data') ? 'sale_opening_notifications'
              AND public.normalize_form_metadata_internal(form_metadata) ? 'sale_opening_notifications'
              THEN jsonb_build_object('sale_opening_notifications',public.normalize_form_metadata_internal(form_metadata)->'sale_opening_notifications') ELSE '{}'::jsonb END;
          form_metadata:=public.apply_form_settings_internal(form_metadata,
            public.form_settings_from_metadata_internal(form_metadata));
        END IF;

        -- Explicit removals are part of this save transaction, never inferred from
        -- omitted fields in partial/older-client payloads. Exceptions roll back the save.
        SELECT coalesce(array_agg(DISTINCT pt.id),'{}'::bigint[]) INTO protected_primary_types
        FROM public.form_fields ff JOIN eshop.product_types pt ON pt.id=ff.product_type
        WHERE ff.form=form_id AND pt.type='spot';
        SELECT COALESCE(array_agg(value::bigint), '{}'::bigint[]) INTO deleted_fields
        FROM jsonb_array_elements_text(COALESCE(input_data->'deleted_field_ids', '[]'::jsonb));
        SELECT COALESCE(array_agg(value::bigint), '{}'::bigint[]) INTO deleted_products
        FROM jsonb_array_elements_text(COALESCE(input_data->'deleted_product_ids', '[]'::jsonb));

        IF EXISTS (SELECT 1 FROM unnest(deleted_fields) AS removed(id) WHERE NOT EXISTS (
            SELECT 1 FROM public.form_fields ff WHERE ff.id = removed.id AND ff.form = form_id))
          OR EXISTS (SELECT 1 FROM unnest(deleted_products) AS removed(id) WHERE NOT EXISTS (
            SELECT 1 FROM eshop.products p JOIN public.form_fields ff ON ff.product_type = p.product_type
            WHERE p.id = removed.id AND ff.form = form_id)) THEN
            RAISE EXCEPTION 'FORM_DELETE_changed';
        END IF;

        -- Removing the ticket container also removes its nested fields.
        IF EXISTS (SELECT 1 FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields) AND ff.type = 'ticket') THEN
            SELECT deleted_fields || COALESCE(array_agg(ff.id), '{}'::bigint[]) INTO deleted_fields
            FROM public.form_fields ff WHERE ff.form = form_id AND ff.is_ticket_field;
        END IF;

        -- Serialize product-type references and product FK insertions before checking
        -- usage, including ON DELETE CASCADE inventory links.
        PERFORM 1 FROM eshop.product_types pt WHERE pt.id IN (
            SELECT ff.product_type FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields)
            UNION SELECT p.product_type FROM eshop.products p WHERE p.id = ANY(deleted_products)
        ) ORDER BY pt.id FOR UPDATE;
        SELECT deleted_products || COALESCE(array_agg(p.id), '{}'::bigint[]) INTO deleted_products
        FROM eshop.products p JOIN public.form_fields ff ON ff.product_type = p.product_type
        WHERE ff.id = ANY(deleted_fields);
        PERFORM 1 FROM eshop.products p WHERE p.id = ANY(deleted_products) ORDER BY p.id FOR UPDATE;

        FOR deletion_row IN SELECT ff.* FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields)
        LOOP
            SELECT CASE WHEN EXISTS (
          SELECT 1 FROM (
            SELECT current_order.id, current_order.form, current_order.data FROM eshop.orders current_order WHERE current_order.form = ff.form
          ) o
          WHERE o.form = ff.form AND (
            EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(o.data->'fields') = 'array' THEN o.data->'fields' ELSE '[]'::jsonb END) answer
              WHERE answer ? ff.id::text AND answer->(ff.id::text) NOT IN ('null'::jsonb, '""'::jsonb, '[]'::jsonb, '{}'::jsonb))
            OR (ff.type = 'ticket' AND jsonb_path_exists(o.data, '$.tickets[*]'))
            OR (ff.type = 'note' AND ff.is_ticket_field AND jsonb_path_exists(o.data, '$.tickets[*] ? (@.note != null && @.note != "")'))
            OR (ff.type = 'ticket' AND EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt."order" = o.id AND opt.ticket IS NOT NULL))
            OR (ff.type = 'note' AND ff.is_ticket_field AND EXISTS (
              SELECT 1 FROM eshop.order_product_ticket opt JOIN eshop.tickets t ON t.id = opt.ticket
              WHERE opt."order" = o.id AND NULLIF(t.note, '') IS NOT NULL))
          )) OR EXISTS(SELECT 1 FROM eshop.tickets person CROSS JOIN LATERAL jsonb_array_elements(
            CASE WHEN jsonb_typeof(person.data->'fields')='array' THEN person.data->'fields' ELSE '[]' END) answer
            WHERE EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders q ON q.id=x."order" WHERE x.ticket=person.id AND q.form=ff.form) AND answer ? ff.id::text AND answer->(ff.id::text) NOT IN ('null'::jsonb,'""'::jsonb,'[]'::jsonb,'{}'::jsonb))
           OR (ff.type='ticket' AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders q ON q.id=x."order" WHERE x.ticket IS NOT NULL AND q.form=ff.form)) THEN 'responses'
        ELSE (
          SELECT reason FROM public.form_fields member
          JOIN eshop.products p ON p.product_type = member.product_type
          CROSS JOIN LATERAL (SELECT CASE
          WHEN EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt.product = p.id)
            OR EXISTS (SELECT 1 FROM eshop.orders o WHERE o.occasion = p.occasion
              AND jsonb_path_exists(o.data, '$.tickets[*].products[*] ? (@.id == $id)', jsonb_build_object('id', p.id))) THEN 'orders'
          WHEN EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product = p.id) THEN 'blueprint'
          WHEN EXISTS (SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product = p.id) THEN 'inventory'
          WHEN (SELECT count(*) FROM public.form_fields ref WHERE ref.product_type = p.product_type) > 1 THEN 'shared'
        END AS reason) usage
          WHERE (member.id = ff.id OR (ff.type = 'ticket' AND member.form = ff.form AND member.is_ticket_field))
            AND reason IS NOT NULL
          ORDER BY p.id LIMIT 1
        ) END INTO deletion_reason
            FROM public.form_fields ff WHERE ff.id = deletion_row.id;
            IF deletion_reason IS NOT NULL THEN
                RAISE EXCEPTION 'FORM_DELETE_%', deletion_reason;
            END IF;
        END LOOP;
        FOR deletion_row IN SELECT p.* FROM eshop.products p WHERE p.id = ANY(deleted_products)
        LOOP
            SELECT CASE
          WHEN EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt.product = p.id)
            OR EXISTS (SELECT 1 FROM eshop.orders o WHERE o.occasion = p.occasion
              AND jsonb_path_exists(o.data, '$.tickets[*].products[*] ? (@.id == $id)', jsonb_build_object('id', p.id))) THEN 'orders'
          WHEN EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product = p.id) THEN 'blueprint'
          WHEN EXISTS (SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product = p.id) THEN 'inventory'
          WHEN (SELECT count(*) FROM public.form_fields ref WHERE ref.product_type = p.product_type) > 1 THEN 'shared'
        END INTO deletion_reason
            FROM eshop.products p WHERE p.id = deletion_row.id;
            IF deletion_reason IS NOT NULL THEN
                RAISE EXCEPTION 'FORM_DELETE_%', deletion_reason;
            END IF;
        END LOOP;
        IF EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(input_data->'form_fields', '[]'::jsonb)) f
            WHERE (f->>'id')::bigint = ANY(deleted_fields))
          OR EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(input_data->'form_fields', '[]'::jsonb)) f,
            jsonb_array_elements(COALESCE(NULLIF(f->'product_type'->'products', 'null'::jsonb), '[]'::jsonb)) p
            WHERE (p->>'id')::bigint = ANY(deleted_products)) THEN
            RAISE EXCEPTION 'FORM_DELETE_changed';
        END IF;
        DELETE FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields);
        DELETE FROM eshop.planned_changes WHERE subject_id=ANY(deleted_products) AND change_type IN('products.price','products.is_hidden') AND NOT applied;
        DELETE FROM eshop.products p WHERE p.id = ANY(deleted_products);
        DELETE FROM public.client_aggregate_versions WHERE aggregate_type='product' AND scope_type='occasion'
          AND scope_id=occasion_id AND aggregate_id=ANY(ARRAY(SELECT id::text FROM unnest(deleted_products) id));

        ----------------------------------------------------------------------------
        -- Process form_fields array from input_data if present
        -- Each form_field may contain a product_type object. If so, we insert/update
        -- the product_type and its products, then set the resulting product_type.id
        -- in the form_field.
        ----------------------------------------------------------------------------
        IF (input_data->'form_fields') IS NOT NULL THEN
            form_fields_data := '[]'::JSONB;

            FOR field_data IN SELECT * FROM JSONB_ARRAY_ELEMENTS(input_data->'form_fields')
            LOOP
                IF field_data->>'type' IN ('select_one','select_many') THEN
                    IF jsonb_typeof(field_data#>'{data,options}') IS DISTINCT FROM 'array' THEN
                        RAISE EXCEPTION '%', jsonb_build_object('code', 422,
                            'message', 'FORM_SELECTION_OPTIONS_REQUIRED', 'fieldId', field_data->'id')::text;
                    END IF;
                    IF jsonb_array_length(field_data#>'{data,options}') = 0
                       OR EXISTS (SELECT 1 FROM jsonb_array_elements(field_data#>'{data,options}') option
                           WHERE jsonb_typeof(option->'value') IS DISTINCT FROM 'string'
                              OR btrim(option->>'value') = '') THEN
                        RAISE EXCEPTION '%', jsonb_build_object('code', 422,
                            'message', 'FORM_SELECTION_OPTIONS_REQUIRED', 'fieldId', field_data->'id')::text;
                    END IF;
                END IF;
                field_id := NULLIF(field_data->>'id', '')::BIGINT;
                IF field_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.form_fields WHERE id=field_id AND form=form_id) THEN
                  RAISE invalid_parameter_value USING MESSAGE='Foreign form field'; END IF;

                ----------------------------------------------------------------------------
                -- product_type logic now lives here, inside each form_field
                ----------------------------------------------------------------------------
                product_type_data := field_data->'product_type';  -- This is JSONB (could be null)
                IF field_data->>'type' = 'ticket' AND field_data#>>'{data,max_tickets}' IS NOT NULL THEN
                    IF (field_data#>>'{data,max_tickets}')::numeric < 1 OR
                       (field_data#>>'{data,max_tickets}')::numeric > public.ticket_order_limit() OR
                       trunc((field_data#>>'{data,max_tickets}')::numeric) <> (field_data#>>'{data,max_tickets}')::numeric THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 400,
                            'message', 'Invalid maximum tickets per order',
                            'limit', public.ticket_order_limit())::TEXT;
                    END IF;
                END IF;
                field_product_type := NULL;                        -- We'll store numeric ID here if we have a product_type

                IF field_data ? 'product_type_id' THEN
                    field_product_type := (field_data->>'product_type_id')::bigint;
                    IF field_product_type IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.product_types
                      WHERE id=field_product_type AND occasion=occasion_id) THEN
                      RAISE invalid_parameter_value USING MESSAGE='Foreign product type'; END IF;
                ELSIF product_type_data IS NOT NULL AND product_type_data::TEXT <> 'null' THEN
                    -- Attempt to parse the product_type.id if it exists
                    product_type_id := NULLIF(product_type_data->>'id', '')::BIGINT;

                    IF product_type_id IS NULL THEN
                        ----------------------------------------------------------------------------
                        -- New product_type
                        ----------------------------------------------------------------------------
                        INSERT INTO eshop.product_types (
                            created_at,
                            updated_at,
                            occasion,
                            title,
                            description,
                            type,
                            data
                        )
                        VALUES (
                            now_ts,
                            now_ts,
                            occasion_id,
                            product_type_data->>'title',
                            product_type_data->>'description',
                            product_type_data->>'type',
                            product_type_data->'data'
                        )
                        RETURNING id INTO product_type_id;

                        product_type_data := jsonb_set(
                            product_type_data,
                            '{id}',
                            TO_JSONB(product_type_id)
                        );
                    ELSE
                        ----------------------------------------------------------------------------
                        -- Existing product_type: check existence and occasion
                        ----------------------------------------------------------------------------
                        SELECT pt.occasion
                          INTO product_type_occ
                          FROM eshop.product_types pt
                         WHERE pt.id = product_type_id
                         LIMIT 1;

                        IF NOT FOUND THEN
                            RAISE EXCEPTION '%',
                                JSONB_BUILD_OBJECT(
                                    'code', 4006,
                                    'message', 'Product type not found',
                                    'details', product_type_data
                                )::TEXT;
                        END IF;

                        IF product_type_occ <> occasion_id THEN
                            RAISE EXCEPTION '%',
                                JSONB_BUILD_OBJECT(
                                    'code', 4007,
                                    'message', 'product_type occasion does not match form occasion',
                                    'product_type_occasion', product_type_occ,
                                    'form_occasion', occasion_id,
                                    'details', product_type_data
                                )::TEXT;
                        END IF;

                        PERFORM 1 FROM public.occasions WHERE id=occasion_id FOR UPDATE;
                        UPDATE eshop.product_types
                           SET
                               updated_at = now_ts,
                               title = product_type_data->>'title',
                               description = product_type_data->>'description',
                               type = product_type_data->>'type',
                               data = product_type_data->'data'
                         WHERE id = product_type_id;
                    END IF;

                    ----------------------------------------------------------------------------
                    -- Process products within this product_type, if any
                    ----------------------------------------------------------------------------
                    PERFORM public.advance_ticketing_authoring_version_internal_v1('product_type',occasion_id,product_type_id);
                    products_data := product_type_data->'products';
                    IF products_data IS NOT NULL AND products_data::TEXT <> 'null' THEN
                        product_array_data := '[]'::JSONB;

                        FOR product_data IN SELECT * FROM JSONB_ARRAY_ELEMENTS(products_data)
                        LOOP
                            product_id := NULLIF(product_data->>'id', '')::BIGINT;

                            -- Validate product price must be > 0
                            price_val := COALESCE(NULLIF(product_data->>'price',''), '0')::NUMERIC;
                            IF price_val < 0 THEN
                                RAISE EXCEPTION '%',
                                    JSONB_BUILD_OBJECT(
                                        'code', 4015,
                                        'message', 'Product price must be greater or equal to zero',
                                        'details', product_data
                                    )::TEXT;
                            END IF;

                            IF product_id IS NULL THEN
                                ----------------------------------------------------------------------------
                                -- New product
                                ----------------------------------------------------------------------------
                                PERFORM public.validate_product_price(price_val,product_data->'data',left(product_data->>'currency_code',3));
                                INSERT INTO eshop.products (
                                    created_at,
                                    updated_at,
                                    product_type,
                                    occasion,
                                    title,
                                    description,
                                    price,
                                    currency_code,
                                    data,
                                    is_hidden,
                                    "order",
                                    maximum
                                )
                                VALUES (
                                    now_ts,
                                    now_ts,
                                    product_type_id,
                                    occasion_id,
                                    product_data->>'title',
                                    product_data->>'description',
                                    price_val,
                                    left(product_data->>'currency_code', 3),
                                    product_data->'data',
                                    COALESCE((product_data->>'is_hidden')::BOOLEAN, false),
                                    NULLIF(product_data->>'order','')::BIGINT,
                                    NULLIF(product_data->>'maximum','')::BIGINT
                                )
                                RETURNING id INTO product_id;

                                product_data := jsonb_set(product_data, '{id}', TO_JSONB(product_id));
                            ELSE
                                ----------------------------------------------------------------------------
                                -- Existing product: must match the same occasion and product_type
                                ----------------------------------------------------------------------------
                                SELECT p.occasion
                                  INTO product_occ
                                  FROM eshop.products p
                                 WHERE p.id = product_id
                                   AND p.product_type = product_type_id
                                 LIMIT 1;

                                IF NOT FOUND THEN
                                    RAISE EXCEPTION '%',
                                        JSONB_BUILD_OBJECT(
                                            'code', 4008,
                                            'message', 'Product not found or does not match product_type',
                                            'details', product_data
                                        )::TEXT;
                                END IF;

                                IF product_occ <> occasion_id THEN
                                    RAISE EXCEPTION '%',
                                        JSONB_BUILD_OBJECT(
                                            'code', 4009,
                                            'message', 'Product occasion does not match form occasion',
                                            'product_occasion', product_occ,
                                            'form_occasion', occasion_id,
                                            'details', product_data
                                        )::TEXT;
                                END IF;

                                PERFORM public.validate_product_price_update(product_id,price_val,product_data->'data',left(product_data->>'currency_code',3));
                                UPDATE eshop.products
                                   SET
                                       updated_at = now_ts,
                                       title = product_data->>'title',
                                       description = product_data->>'description',
                                       price = price_val,
                                       currency_code = left(product_data->>'currency_code', 3),
                                       data = product_data->'data',
                                       is_hidden = COALESCE((product_data->>'is_hidden')::BOOLEAN, false),
                                       "order" = NULLIF(product_data->>'order','')::BIGINT,
                                       maximum = NULLIF(product_data->>'maximum','')::BIGINT
                                 WHERE id = product_id
                                   AND product_type = product_type_id;
                            END IF;

                            PERFORM public.advance_ticketing_authoring_version_internal_v1('product',occasion_id,product_id);
                            product_array_data := product_array_data || product_data;
                        END LOOP;

                        product_type_data := jsonb_set(
                            product_type_data,
                            '{products}',
                            product_array_data
                        );
                    END IF;

                    ----------------------------------------------------------------------------
                    -- Store product_type_id in field_product_type for the form_fields table
                    ----------------------------------------------------------------------------
                    field_product_type := product_type_id;

                    ----------------------------------------------------------------------------
                    -- Merge updated product_type_data back into the field_data
                    ----------------------------------------------------------------------------
                    field_data := jsonb_set(field_data, '{product_type}', product_type_data);
                END IF;

                ----------------------------------------------------------------------------
                -- Insert or update the form_field itself
                ----------------------------------------------------------------------------
                IF field_id IS NOT NULL THEN
                    -- Update existing form_field
                    UPDATE public.form_fields
                       SET
                           title = field_data->>'title',
                           description = field_data->>'description',
                           data = CASE WHEN field_data ? 'data' THEN field_data->'data' ELSE data END,
                           type = field_data->>'type',
                           is_required = COALESCE((field_data->>'is_required')::BOOLEAN, false),
                           is_hidden = COALESCE((field_data->>'is_hidden')::BOOLEAN, false),
                           "order" = NULLIF(field_data->>'order','')::BIGINT,
                           product_type = CASE WHEN field_data ? 'product_type' OR field_data ? 'product_type_id' THEN field_product_type ELSE product_type END,
                           is_ticket_field = COALESCE((field_data->>'is_ticket_field')::BOOLEAN, false),
                           form = form_id
                     WHERE id = field_id
                       AND form = form_id;

                    IF NOT FOUND THEN
                        RAISE EXCEPTION '%',
                            JSONB_BUILD_OBJECT(
                                'code', 4012,
                                'message', 'No matching form_field found to update (or does not belong to this form)',
                                'details', field_data
                            )::TEXT;
                    END IF;
                ELSE
                    -- Insert new form_field
                    INSERT INTO public.form_fields (
                        created_at,
                        title,
                        description,
                        data,
                        type,
                        is_required,
                        form,
                        is_hidden,
                        "order",
                        product_type,
                        is_ticket_field
                    )
                    VALUES (
                        now_ts,
                        field_data->>'title',
                        field_data->>'description',
                        field_data->'data',
                        field_data->>'type',
                        COALESCE((field_data->>'is_required')::BOOLEAN, false),
                        form_id,
                        COALESCE((field_data->>'is_hidden')::BOOLEAN, false),
                        NULLIF(field_data->>'order','')::BIGINT,
                        field_product_type,
                        COALESCE((field_data->>'is_ticket_field')::BOOLEAN, false)
                    )
                    RETURNING id INTO field_id;

                    field_data := jsonb_set(field_data, '{id}', TO_JSONB(field_id));
                END IF;

                form_fields_data := form_fields_data || field_data;
            END LOOP;
        END IF;

        ----------------------------------------------------------------------------
        -- Validate that deadline_duration_seconds is zero, positive, or null
        ----------------------------------------------------------------------------
        deadline_val := NULLIF(input_data->>'deadline_duration_seconds','')::BIGINT;
        IF deadline_val IS NOT NULL AND deadline_val < 0 THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT(
                    'code', 4016,
                    'message', 'deadline_duration_seconds must be zero or higher or null'
                )::TEXT;
        END IF;

        ----------------------------------------------------------------------------
        -- Validate bank_account belongs to the same unit as the occasion, if provided
        ----------------------------------------------------------------------------
        bank_account_val := NULLIF(input_data->>'bank_account','')::BIGINT;
        IF bank_account_val IS NOT NULL THEN
            SELECT ba.unit
              INTO bank_account_unit
              FROM eshop.unit_bank_accounts ba
             WHERE ba.bank_account = bank_account_val
               AND ba.unit = occasion_unit
             LIMIT 1;

            IF NOT FOUND THEN
                RAISE EXCEPTION '%',
                    JSONB_BUILD_OBJECT(
                        'code', 4020,
                        'message', 'Bank account not found',
                        'bank_account', bank_account_val
                    )::TEXT;
            END IF;

            IF bank_account_unit <> occasion_unit THEN
                RAISE EXCEPTION '%',
                    JSONB_BUILD_OBJECT(
                        'code', 4021,
                        'message', 'Bank account does not belong to the same unit as the occasion',
                        'bank_account_unit', bank_account_unit,
                        'occasion_unit', occasion_unit
                    )::TEXT;
            END IF;
        END IF;

        ----------------------------------------------------------------------------
        -- Update the main form record with all validated fields
        ----------------------------------------------------------------------------
        IF input_data->>'blueprint' IS NOT NULL AND NOT EXISTS(
          SELECT 1 FROM eshop.blueprints WHERE id=(input_data->>'blueprint')::bigint AND occasion=occasion_id) THEN
          RAISE EXCEPTION '%',jsonb_build_object('code',403,'message','Foreign blueprint')::text; END IF;
        PERFORM public.check_form_capacity_settings_internal(form_id,input_data);
        UPDATE public.forms
           SET
               participant_capacity = CASE WHEN input_data ? 'participant_capacity' THEN (input_data->>'participant_capacity')::integer ELSE participant_capacity END,
               waitlist_enabled = CASE WHEN input_data ? 'waitlist_enabled' THEN (input_data->>'waitlist_enabled')::boolean ELSE waitlist_enabled END,
               show_remaining_capacity = CASE WHEN input_data ? 'show_remaining_capacity' THEN (input_data->>'show_remaining_capacity')::boolean ELSE show_remaining_capacity END,
               waitlist_offer_duration_seconds = CASE WHEN input_data ? 'waitlist_offer_duration_seconds' THEN (input_data->>'waitlist_offer_duration_seconds')::integer ELSE waitlist_offer_duration_seconds END,
               capacity_revision = capacity_revision+1,
               title = CASE WHEN input_data ? 'title' THEN input_data->>'title' ELSE title END,
               -- Opening the real form ends its initial preparation phase.
               -- Later closing it is a pause, irrespective of test orders.
               data = CASE WHEN coalesce((input_data->>'is_open')::boolean,is_open) THEN
                 jsonb_set(coalesce(form_metadata,'{}'::jsonb),'{schedule}',
                  coalesce((form_metadata)->'schedule','{}'::jsonb)
                   ||'{"sale_preparation":false}'::jsonb)
                 ELSE form_metadata END,
               header = CASE WHEN input_data ? 'header' THEN input_data->>'header' ELSE header END,
               header_off = CASE WHEN input_data ? 'header_off' THEN input_data->>'header_off' ELSE header_off END,
               link = link_param,
               blueprint = CASE WHEN input_data ? 'blueprint' THEN NULLIF(input_data->>'blueprint','')::BIGINT ELSE blueprint END,
               bank_account = CASE WHEN input_data ? 'bank_account' THEN bank_account_val ELSE bank_account END,
               deadline_duration_seconds = CASE WHEN input_data ? 'deadline_duration_seconds' THEN deadline_val ELSE deadline_duration_seconds END,
               is_open = CASE WHEN input_data ? 'is_open' THEN (input_data->>'is_open')::boolean ELSE is_open END
         WHERE id = form_id;

        IF input_data ? 'form_fields' OR cardinality(deleted_fields)>0 OR cardinality(deleted_products)>0 THEN
          PERFORM public.assert_form_primary_products_internal(form_id,protected_primary_types);
        END IF;
        PERFORM public.validate_form_payment_configuration_internal(form_id);

        ----------------------------------------------------------------------------
        -- After updating the form, requeue payment reminders for the whole occasion
        -- as the form's settings (e.g., is_reminder_enabled) might have changed.
        ----------------------------------------------------------------------------
        -- First, find the 'seconds_before_deadline' setting from the occasion's 'form' feature.
        SELECT (elem->>'reminder_interval_seconds')::BIGINT
          INTO v_seconds_before_deadline
          FROM public.occasions, jsonb_array_elements(features) AS elem
         WHERE id = occasion_id
           AND elem->>'code' = 'form'
         LIMIT 1;

        -- If the setting is found, call the function to rebuild the reminder queue.
        PERFORM public.queue_payment_reminders(occasion_id, COALESCE(v_seconds_before_deadline,86400));

        ----------------------------------------------------------------------------
        -- Prepare a success response
        ----------------------------------------------------------------------------
        PERFORM public.assert_form_seating_source_internal(form_id);
        result := JSONB_BUILD_OBJECT(
            'code', 200,
            'message', 'Form updated successfully',
            'form_id', form_id,
            'link', link_param,
            'form_fields', form_fields_data
        );

        PERFORM public.sync_sale_opening_settings_internal(form_id,previous_form_metadata);

        IF availability_new THEN
          PERFORM public.notification_center_form_created_internal(form_id);
        ELSE
          PERFORM public.notification_center_form_availability_internal(form_id,availability_at);
        END IF;
        PERFORM public.notification_center_form_capacity_internal(form_id);
    EXCEPTION WHEN raise_exception THEN
        -- Catch any exception and attempt to parse it as JSON; if not JSON, wrap it in our own JSON.
        result := CASE
            WHEN left(SQLERRM, 1) = '{' THEN SQLERRM::JSONB
            ELSE JSONB_BUILD_OBJECT('code', 5001, 'message', SQLERRM)
        END;
    END;

    RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.update_form_internal_v1(jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Source: database/functions/eshop_forms/update_form_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.update_form_client_sync_v1(p_form jsonb, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_form bigint;
  v_begin jsonb; v_hash text; v_version bigint; v_expected bigint; v_users uuid[]; v_result jsonb; v_check record; v_current bigint;
BEGIN
  IF p_form IS NULL OR jsonb_typeof(p_form)<>'object'
    OR octet_length(p_form::text)>4194304 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid form aggregate'; END IF;
  v_occasion:=NULLIF(p_form->>'occasion','')::bigint;
  v_form:=NULLIF(p_form->>'id','')::bigint;
  IF v_actor IS NULL OR v_occasion IS NULL OR v_form IS NULL
    OR NOT public.can_author_forms(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
  PERFORM public.lock_blueprint_scope_internal(ARRAY[v_occasion]);
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',v_occasion,'form',p_form)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.form.save',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.forms WHERE id=v_form AND occasion=v_occasion) THEN RAISE insufficient_privilege USING MESSAGE='foreign form'; END IF;
  PERFORM public.notification_center_initialized_internal((SELECT organization FROM public.occasions WHERE id=v_occasion));
  -- Parent order matches checkout: form, product, blueprint, then seats.
  PERFORM 1 FROM public.forms WHERE id=v_form AND occasion=v_occasion FOR UPDATE;
  PERFORM 1 FROM eshop.product_types WHERE occasion=v_occasion ORDER BY id FOR UPDATE;
  PERFORM 1 FROM eshop.products WHERE occasion=v_occasion ORDER BY id FOR UPDATE;
  IF v_form IS NOT NULL THEN
    INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES('form','occasion',v_occasion,v_form::text,0) ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='form' AND scope_type='occasion' AND scope_id=v_occasion AND aggregate_id=v_form::text FOR UPDATE;
  ELSE v_version:=0; END IF;
  -- Missing baseline remains an installed-client adapter, explicitly not MCP-ready.
  v_expected:=CASE WHEN p_form ? 'expected_aggregate_version' THEN (p_form->>'expected_aggregate_version')::bigint ELSE v_version END;
  IF v_expected IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('aggregate_version',v_version)); END IF;
  -- These maps were frozen when the editor loaded. No read-before-write rebasing.
  -- Missing maps are the bounded released-client facade, not MCP-ready authoring.
  IF p_form ? 'expected_product_versions' OR p_form ? 'expected_product_type_versions' THEN
    IF jsonb_typeof(p_form->'expected_product_versions') IS DISTINCT FROM 'object'
      OR jsonb_typeof(p_form->'expected_product_type_versions') IS DISTINCT FROM 'object' THEN
      RAISE invalid_parameter_value USING MESSAGE='original product versions required'; END IF;
    FOR v_check IN
      SELECT DISTINCT 'product'::text kind, (p->>'id')::bigint id FROM jsonb_array_elements(coalesce(p_form->'form_fields','[]')) f
        CROSS JOIN LATERAL jsonb_array_elements(coalesce(nullif(f#>'{product_type,products}','null'),'[]')) p WHERE p->>'id' IS NOT NULL
      UNION SELECT 'product',value::bigint FROM jsonb_array_elements_text(coalesce(p_form->'deleted_product_ids','[]'))
      UNION SELECT DISTINCT 'product',p.id FROM eshop.products p JOIN public.form_fields ff ON ff.product_type=p.product_type
        WHERE ff.form=v_form AND ff.id IN (SELECT value::bigint FROM jsonb_array_elements_text(coalesce(p_form->'deleted_field_ids','[]')))
      UNION SELECT DISTINCT 'product_type',(f#>>'{product_type,id}')::bigint FROM jsonb_array_elements(coalesce(p_form->'form_fields','[]')) f
        WHERE f#>>'{product_type,id}' IS NOT NULL
      ORDER BY 1,2
    LOOP
      IF NOT (CASE v_check.kind WHEN 'product' THEN p_form->'expected_product_versions'
        ELSE p_form->'expected_product_type_versions' END) ? v_check.id::text THEN
        RAISE invalid_parameter_value USING MESSAGE='missing original product baseline'; END IF;
      IF (v_check.kind='product' AND NOT EXISTS(SELECT 1 FROM eshop.products WHERE id=v_check.id AND occasion=v_occasion))
        OR (v_check.kind='product_type' AND NOT EXISTS(SELECT 1 FROM eshop.product_types WHERE id=v_check.id AND occasion=v_occasion)) THEN
        RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('entity_type',v_check.kind,'entity_id',v_check.id,'deleted',true)); END IF;
      SELECT coalesce(v.version,0) INTO v_current FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
        ON v.aggregate_type=v_check.kind AND v.scope_type='occasion' AND v.scope_id=v_occasion AND v.aggregate_id=v_check.id::text;
      IF ((CASE v_check.kind WHEN 'product' THEN p_form->'expected_product_versions' ELSE p_form->'expected_product_type_versions' END)->>v_check.id::text)::bigint IS DISTINCT FROM v_current THEN
        RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
          jsonb_build_object('aggregate_version',v_version,'entity_type',v_check.kind,'entity_id',v_check.id,'entity_version',v_current));
      END IF;
    END LOOP;
  END IF;
  SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_users
  FROM public.occasion_users ou JOIN eshop.order_product_ticket opt
    ON opt.ticket=ou.ticket JOIN eshop.products p ON p.id=opt.product
  WHERE ou.occasion=v_occasion AND p.occasion=v_occasion;
  BEGIN
    v_result:=public.update_form_internal_v1(p_form-'expected_product_versions'-'expected_product_type_versions');
    IF coalesce((v_result->>'code')::integer,500)<>200 THEN
      RAISE SQLSTATE 'P0F01' USING MESSAGE='authoring domain rejected'; END IF;
  EXCEPTION WHEN SQLSTATE 'P0F01' THEN NULL;
  END;
  IF coalesce((v_result->>'code')::integer,500)<>200 THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',
      CASE WHEN (v_result->>'code')::integer BETWEEN 100 AND 599 THEN (v_result->>'code')::integer ELSE 400 END,v_result); END IF;
  v_form:=(v_result->>'form_id')::bigint;
  INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES('form','occasion',v_occasion,v_form::text,1)
    ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp()
    RETURNING version INTO v_version;
  v_result:=v_result||jsonb_build_object('aggregate_version',v_version,
    'product_versions',public.get_ticketing_product_versions_internal_v1(v_occasion,'product'),
    'product_type_versions',public.get_ticketing_product_versions_internal_v1(v_occasion,'product_type'),
    'authoring',public.get_form_authoring_snapshot_internal(v_form));
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.form.save',jsonb_build_array(jsonb_build_object(
      'entityType','form','entityId',v_form,'operation','update',
      'safeLabel',left(p_form->>'title',240),'changedFields',jsonb_build_array(
        'configuration','products'))),v_users,v_result);
END; $function$;

REVOKE ALL ON FUNCTION public.update_form_client_sync_v1(jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_form_client_sync_v1(jsonb,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.update_form(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 result:=public.update_form_client_sync_v1(input_data,extensions.gen_random_uuid());
 RETURN jsonb_build_object('code',result->'code')||result->'data';
END $$;
REVOKE ALL ON FUNCTION public.update_form(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_form(jsonb) TO authenticated;

-- Source: database/functions/occasion_setup/finalize.sql
-- Materialize the private configuration exactly once. Provisional draft IDs and
-- source product IDs are never accepted as IDs in the new aggregate.
CREATE OR REPLACE FUNCTION public.finalize_occasion_setup_draft(p_id uuid,p_expected_revision bigint,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE policies jsonb; d public.occasion_setup_drafts; payload jsonb; config jsonb; features jsonb := '[]';
 started jsonb; receipt jsonb; new_id bigint; form_id bigint; form_data jsonb; fields jsonb := '[]';
 field jsonb; pt jsonb; products jsonb; product jsonb; result jsonb; source_id bigint; configuration_source bigint;
 old_products jsonb := '[]'; old_types jsonb := '[]'; type_map jsonb := '{}'; final_features jsonb; new_products jsonb; product_map jsonb := '{}'; idx integer; j integer;
 email_banner text; intro_image text; form_link text; selected_bank bigint; bank_fingerprint text; bank_currencies text[]; required_currencies text[]; wave jsonb; target jsonb; saved_wave jsonb; wave_product bigint;
 has_tickets boolean;
 unit_defaults jsonb; communication_new boolean; reply_email text; form_meta jsonb; reminder_days numeric;
 payment_method text;
 publish_to_catalog boolean;
 sale_mode text; sale_start timestamptz; sale_end timestamptz;
 blueprint_mode text; blueprint_id bigint; blueprint_source bigint; v_commit public.client_commits%ROWTYPE;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id FOR UPDATE;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT public.can_create_occasion(d.unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 IF d.data ? 'finalizeResponse' THEN RETURN d.data->'finalizeResponse'; END IF;
 started := public.begin_unit_client_mutation_v1(p_command_id,'occasion.setup.finalize',d.unit,auth.uid(),
  encode(extensions.digest(convert_to(jsonb_build_object('draft',p_id,'revision',p_expected_revision)::text,'UTF8'),'sha256'),'hex'));
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 IF d.data ? 'finalizedOccasion' THEN RAISE invalid_parameter_value USING MESSAGE='Draft already finalized'; END IF;
 IF d.revision IS DISTINCT FROM p_expected_revision THEN RAISE SQLSTATE 'PT409' USING MESSAGE='Draft changed in another session'; END IF;
 payload := public.normalize_occasion_setup_appearance_internal(d.data);
 payment_method:=payload->>'paymentMethod';
 IF payment_method IS NOT NULL AND payment_method NOT IN ('stripe','bank','both') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid payment method'; END IF;
 blueprint_mode:=CASE payload->>'blueprintMode'
  WHEN 'Bez plánku' THEN 'none' WHEN 'Nový' THEN 'new' WHEN 'Převzít' THEN 'copy'
  ELSE payload->>'blueprintMode' END;
 IF blueprint_mode IS NULL THEN blueprint_mode:=CASE WHEN jsonb_typeof(payload->'blueprintLayoutDraft')='object' THEN 'copy' ELSE 'none' END; END IF;
 IF blueprint_mode NOT IN ('none','new','copy') THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid blueprint mode'; END IF;
 -- The form owns its sale window. Absent intent keeps historical drafts closed.
 sale_mode:=coalesce(payload->>'saleMode','preparation');
 IF coalesce((payload->>'formEnabled')::boolean,true) THEN
  IF sale_mode NOT IN ('preparation','scheduled','immediate') THEN
   RAISE invalid_parameter_value USING MESSAGE='Invalid sale mode'; END IF;
  sale_end:=coalesce(nullif(payload->>'saleEnd','')::timestamptz,(payload->>'end')::timestamptz);
  IF sale_end IS NULL THEN
   RAISE invalid_parameter_value USING MESSAGE='Sale end is required'; END IF;
  IF sale_mode='scheduled' THEN
   sale_start:=nullif(payload->>'saleStart','')::timestamptz;
   IF sale_start IS NULL OR sale_start<=clock_timestamp() OR sale_start>=sale_end THEN
    RAISE invalid_parameter_value USING MESSAGE='Invalid scheduled sale start'; END IF;
  ELSIF sale_mode='immediate' THEN
   IF sale_end<=clock_timestamp() THEN RAISE invalid_parameter_value USING MESSAGE='Sale has already ended'; END IF;
   sale_start:=clock_timestamp();
  END IF;
 END IF;
 PERFORM public.validate_setup_email_templates_internal(payload->'emailTemplateOverrides');
 communication_new:=payload ? 'communicationTone';
 IF communication_new THEN
  IF coalesce(payload->>'communicationTone','') NOT IN ('inherit','formal','informal')
    OR coalesce(payload->>'replyToMode','') NOT IN ('inherit','custom')
    OR coalesce(payload->>'remindersMode','') NOT IN ('inherit','enabled','disabled') THEN
   RAISE invalid_parameter_value USING MESSAGE='Invalid communication options'; END IF;
  IF payload->>'replyToMode'='custom' THEN
   reply_email:=btrim(payload->>'replyToEmail');
   IF reply_email IS NULL OR length(reply_email)>254 OR reply_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' THEN
    RAISE invalid_parameter_value USING MESSAGE='Invalid reply email'; END IF;
  END IF;
  SELECT coalesce(u.data,'{}'::jsonb) INTO unit_defaults FROM public.units u WHERE u.id=d.unit;
 END IF;
 source_id := (payload->>'sourceId')::bigint;
 intro_image:=nullif(payload->>'introImage','');
 email_banner:=payload->>'emailBanner';
 IF source_id IS NOT NULL AND (NOT public.can_copy_occasion_source(source_id) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=source_id AND organization=d.organization)) THEN
  RAISE insufficient_privilege USING MESSAGE='Copy source denied'; END IF;
 FOREACH configuration_source IN ARRAY ARRAY[nullif(payload->>'formSourceOccasionId','')::bigint,nullif(payload->>'blueprintSourceOccasionId','')::bigint] LOOP
  IF configuration_source IS NOT NULL AND (NOT public.can_copy_occasion_source(configuration_source) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=configuration_source AND organization=d.organization)) THEN
   RAISE insufficient_privilege USING MESSAGE='Configuration source denied'; END IF;
 END LOOP;
 -- A plan can be selected independently of the event/form copy. Resolve its
 -- resource scope from the stored plan, rather than the overall copy source.
 IF blueprint_mode='copy' THEN
  IF nullif(payload->>'blueprintSourceId','') IS NOT NULL THEN
   SELECT occasion INTO blueprint_source FROM eshop.blueprints WHERE id=(payload->>'blueprintSourceId')::bigint;
   IF NOT FOUND THEN RAISE invalid_parameter_value USING MESSAGE='Blueprint source missing'; END IF;
  ELSE
   blueprint_source:=coalesce(nullif(payload->>'blueprintSourceOccasionId','')::bigint,
     nullif(payload->>'formSourceOccasionId','')::bigint,source_id);
  END IF;
  IF blueprint_source IS NOT NULL AND (NOT public.can_copy_occasion_source(blueprint_source)
    OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=blueprint_source AND organization=d.organization)) THEN
   RAISE insufficient_privilege USING MESSAGE='Configuration source denied'; END IF;
 END IF;
 IF nullif(btrim(payload->>'title'),'') IS NULL OR (payload->>'reviewConfirmed')::boolean IS DISTINCT FROM true THEN
  RAISE invalid_parameter_value USING MESSAGE='Draft review required'; END IF;
 IF (payload->>'end')::timestamptz < (payload->>'start')::timestamptz THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid event dates'; END IF;
 -- Draft uploads use the existing unit-scoped image writer. Never trust an
 -- arbitrary URL supplied by a client, or adopt another unit's image.
 IF intro_image IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.images WHERE link=intro_image AND unit=d.unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft image access denied'; END IF;
 IF nullif(email_banner,'') IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.images WHERE link=email_banner AND unit=d.unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft email banner access denied'; END IF;
 IF coalesce((payload->>'isPromoted')::boolean,false) AND intro_image IS NULL THEN
  RAISE invalid_parameter_value USING MESSAGE='Promotion requires an intro image'; END IF;
 -- Selection is sufficient; current permissions, currencies and account
 -- fingerprint are still verified under locks before materialization.
 SELECT array_agg(DISTINCT coalesce(nullif(p->>'currency_code',''),'CZK')) INTO required_currencies
 FROM jsonb_array_elements(coalesce(payload#>'{formDraft,fields}','[]')) f
 CROSS JOIN LATERAL jsonb_array_elements(coalesce(f#>'{product_type_data,products}','[]')) p
 WHERE coalesce((payload->>'formEnabled')::boolean,true) AND NOT coalesce((f->>'is_hidden')::boolean,false)
   AND NOT coalesce((p->>'is_hidden')::boolean,false) AND (p->>'price')::numeric>0;
 IF required_currencies IS NOT NULL AND payment_method IS DISTINCT FROM 'stripe' AND (payload ? 'bankAccountId' OR payload ? 'bankAccountConfirmed' OR payment_method IN ('bank','both')) THEN
  IF nullif(payload->>'bankAccountId','') IS NULL THEN
   RAISE invalid_parameter_value USING MESSAGE='Bank account selection required'; END IF;
  selected_bank:=(payload->>'bankAccountId')::bigint;
  PERFORM 1 FROM eshop.bank_accounts ba JOIN eshop.unit_bank_accounts u ON u.bank_account=ba.id
   WHERE u.unit=d.unit AND ba.id=selected_bank AND ba.type<>'CASH' FOR SHARE OF ba,u;
  IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='Bank account access denied'; END IF;
  -- Take a fresh statement snapshot after acquiring locks: a concurrent account
  -- update may have committed while the locking statement was waiting.
  SELECT ba.supported_currencies,public.occasion_setup_bank_fingerprint_internal(ba.id)
   INTO bank_currencies,bank_fingerprint FROM eshop.bank_accounts ba WHERE ba.id=selected_bank;
  IF bank_currencies IS NULL OR NOT required_currencies <@ bank_currencies THEN
   RAISE invalid_parameter_value USING MESSAGE='Bank account currency mismatch'; END IF;
  IF bank_fingerprint IS DISTINCT FROM payload->>'bankAccountFingerprint' THEN
   RAISE SQLSTATE 'PT409' USING MESSAGE='Bank account details changed; select again'; END IF;
 END IF;
 -- Active form choices own enabled features, not whether an editor was visited.
 has_tickets:=coalesce((payload->>'formEnabled')::boolean,true) AND EXISTS(
  SELECT 1 FROM jsonb_array_elements(coalesce(payload#>'{formDraft,fields}','[]')) f
  WHERE f->>'type'='ticket' AND NOT coalesce((f->>'is_hidden')::boolean,false));
 IF has_tickets THEN
  features:=features||jsonb_build_array((coalesce(nullif(payload->'ticketDraft','null'::jsonb),'{}'::jsonb)-'layout')
    ||'{"code":"ticket","is_enabled":true}'::jsonb);
 END IF;
 IF blueprint_mode<>'none' AND (
  NOT coalesce((payload->>'formEnabled')::boolean,true) OR
  NOT EXISTS(
   SELECT 1 FROM jsonb_array_elements(coalesce(payload#>'{blueprintLayoutDraft,seatBindings}','[]')) binding
   JOIN jsonb_array_elements(coalesce(payload#>'{blueprintLayoutDraft,layout,nodes}','[]')) node ON node->>'id'=binding->>'nodeId'
   WHERE node->>'kind'='seat' AND binding->>'productId' IS NOT NULL AND NOT coalesce((binding->>'blocked')::boolean,false)
   UNION ALL
   SELECT 1 FROM jsonb_array_elements(coalesce(payload#>'{blueprintLayoutDraft,areaBindings}','[]')) binding
   JOIN jsonb_array_elements(coalesce(payload#>'{blueprintLayoutDraft,layout,nodes}','[]')) node ON node->>'id'=binding->>'nodeId'
   WHERE node->>'kind'='capacityArea' AND binding->>'productId' IS NOT NULL
    AND (binding->>'inventoryContextId' IS NOT NULL OR coalesce((binding->>'capacity')::numeric,0)>0)
  )) THEN RAISE invalid_parameter_value USING MESSAGE='Selected blueprint requires a form and sellable places'; END IF;
 IF coalesce((payload->>'formEnabled')::boolean,true) THEN
  features := features || jsonb_build_array(jsonb_build_object('code','form','is_enabled',true) ||
    CASE WHEN communication_new THEN jsonb_build_object(
      'reminder_is_enabled',coalesce((unit_defaults->>'is_reminder_enabled')::boolean,true),
      'reminder_interval_seconds',coalesce((unit_defaults->>'reminder_interval_seconds')::bigint,86400)) ELSE '{}'::jsonb END);
 END IF;
 IF coalesce((payload->>'copyProgram')::boolean,false) THEN features := features || '[{"code":"schedule","is_enabled":true}]'; END IF;
 IF coalesce((payload->>'copyInformation')::boolean,false) THEN features := features || '[{"code":"information","is_enabled":true}]'; END IF;
 publish_to_catalog:=coalesce((payload->>'formEnabled')::boolean,true) AND sale_mode<>'preparation' AND coalesce((payload->>'listPubliclyOnPublish')::boolean,true);
 config := jsonb_build_object('unit',d.unit,'organization',d.organization,
  'title',payload->>'title','link',payload->>'link','description',coalesce(payload->>'description',''),
  'start_time',payload->>'start','end_time',payload->>'end',
  'is_hidden',NOT publish_to_catalog,
  'is_open',publish_to_catalog,
  'is_promoted',coalesce((payload->>'isPromoted')::boolean,false),
  'features',features,'data',jsonb_strip_nulls(jsonb_build_object('client_sync_v1',false,
   'setup_listing_intent',coalesce((payload->>'listPubliclyOnPublish')::boolean,true),
   'email_banner',email_banner,'image',intro_image,'place_name',nullif(btrim(payload->>'placeName'),''),'reply_to',reply_email)));
 policies:=public.abuse_policy_bundle_v1(ARRAY['occasion.creation','occasion.copy'],d.unit,d.organization);
 IF source_id IS NOT NULL AND (coalesce((payload->>'copyProgram')::boolean,false) OR coalesce((payload->>'copyInformation')::boolean,false) OR coalesce((payload->>'copyEmails')::boolean,false)) THEN
  PERFORM public.admit_occasion_copy_v1(source_id,d.unit,d.organization,policies->'occasion.copy'); END IF;
 PERFORM public.admit_occasion_creation_v1(auth.uid(),d.unit,d.organization,NULL,policies->'occasion.creation');
 PERFORM public.update_occasion_internal_v1(config);
 new_id := currval(pg_get_serial_sequence('public.occasions','id'));
 SELECT o.features INTO features FROM public.occasions o WHERE o.id=new_id;
 INSERT INTO public.occasion_users(occasion,"user",is_manager,is_editor,is_editor_view,is_editor_order,is_editor_order_view)
 VALUES(new_id,auth.uid(),true,true,true,true,true);
 form_data := payload->'formDraft';
 IF form_data IS NOT NULL AND form_data<>'null'::jsonb AND coalesce((payload->>'formEnabled')::boolean,true) THEN
  IF communication_new THEN
   -- Semantic choices override legacy source metadata. Inherited values stay
   -- absent so reply/tone remain live unit defaults; reminder defaults above
   -- are a creation snapshot and never requeue existing events.
   form_meta:=coalesce(nullif(form_data->'data','null'::jsonb),'{}'::jsonb)
     -'communication_tone'-'is_reminder_enabled'-'reminder_interval_seconds';
   IF payload->>'communicationTone'<>'inherit' THEN
    form_meta:=form_meta||jsonb_build_object('communication_tone',payload->>'communicationTone'); END IF;
   IF required_currencies IS NOT NULL THEN
    IF payload->>'remindersMode'<>'inherit' THEN
     form_meta:=form_meta||jsonb_build_object('is_reminder_enabled',payload->>'remindersMode'='enabled'); END IF;
    IF nullif(btrim(payload->>'reminderLeadDays'),'') IS NOT NULL THEN
     reminder_days:=replace(payload->>'reminderLeadDays',',','.')::numeric;
     IF reminder_days<0 OR reminder_days::text IN ('NaN','Infinity','-Infinity') THEN
      RAISE invalid_parameter_value USING MESSAGE='Invalid reminder interval'; END IF;
     form_meta:=form_meta||jsonb_build_object('reminder_interval_seconds',round(reminder_days*86400)::bigint);
    END IF;
   END IF;
   form_data:=jsonb_set(form_data,'{data}',form_meta);
  END IF;
  -- Explicit values also clear dates inherited from a source/default form.
  form_meta:=coalesce(nullif(form_data->'data','null'::jsonb),'{}'::jsonb)
    -'start_time'-'end_time'-'enable_countdown';
  form_meta:=jsonb_set(form_meta,'{schedule}',coalesce(nullif(form_meta->'schedule','null'::jsonb),'{}'::jsonb)
   ||jsonb_build_object('start_time',sale_start,'end_time',sale_end,
     'enable_countdown',coalesce((payload->>'saleCountdown')::boolean,false),
     'sale_preparation',sale_mode='preparation'));
  form_meta:=form_meta-'sale_opening_notifications';
  form_meta:=jsonb_set(form_meta,'{design}',coalesce(nullif(form_meta->'design','null'),'{}')||
    jsonb_build_object('presale_header',coalesce(form_meta#>>'{design,presale_header}','event_and_date')));
  IF coalesce((payload->>'saleOpeningNotifications')::boolean,false) THEN
   IF sale_mode<>'scheduled' THEN RAISE invalid_parameter_value USING MESSAGE='sale_opening_requires_scheduled_sale'; END IF;
   form_meta:=form_meta||'{"sale_opening_notifications":{"enabled":true,"collection_paused":false}}'::jsonb;
   IF coalesce((payload->>'saleCountdown')::boolean,false) AND position('form-countdown' IN coalesce(form_meta#>>'{schedule,countdown_title}',''))=0 THEN
    form_meta:=jsonb_set(form_meta,'{schedule,countdown_title}',to_jsonb(coalesce(form_meta#>>'{schedule,countdown_title}','')||'<div class="html-editor-block form-countdown"></div>'));
   END IF;
   IF position('form-sale-opening-notification' IN coalesce(form_meta#>>'{schedule,countdown_title}',''))=0 THEN
    form_meta:=jsonb_set(form_meta,'{schedule,countdown_title}',to_jsonb(CASE
     WHEN position('<div class="html-editor-block form-countdown"></div>' IN coalesce(form_meta#>>'{schedule,countdown_title}',''))>0 THEN
      replace(form_meta#>>'{schedule,countdown_title}','<div class="html-editor-block form-countdown"></div>',
       '<div class="html-editor-block form-countdown"></div><div class="html-editor-block form-sale-opening-notification"></div>')
     ELSE coalesce(form_meta#>>'{schedule,countdown_title}','')||'<div class="html-editor-block form-sale-opening-notification"></div>' END));
   END IF;
  END IF;
  IF coalesce(nullif(payload->>'formSourceOccasionId','')::bigint,source_id) IS NOT NULL
     AND EXISTS(SELECT 1 FROM public.occasions src WHERE src.id=coalesce(nullif(payload->>'formSourceOccasionId','')::bigint,source_id) AND src.unit IS DISTINCT FROM d.unit) THEN
   form_meta:=form_meta #- '{payments,stripeConnectionId}';
  END IF;
  IF payment_method IS NOT NULL THEN
   form_meta:=jsonb_set(form_meta,'{payments}',coalesce(form_meta->'payments','{}'::jsonb)
      ||jsonb_build_object('bankEnabled',payment_method<>'stripe'));
   IF payment_method='bank' THEN form_meta:=form_meta #- '{payments,stripeConnectionId}'; END IF;
  END IF;
  form_data:=jsonb_set(form_data,'{data}',form_meta);
  SELECT id INTO form_id FROM public.forms WHERE occasion=new_id ORDER BY id LIMIT 1;
  IF form_id IS NULL THEN
   result := public.create_form_internal_v1(new_id,NULL,form_data->>'title'); form_id := (result->>'id')::bigint;
  END IF;
  form_link:=nullif(form_data->>'link','');
  IF source_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.forms source_form WHERE source_form.occasion=source_id AND source_form.link=form_link) THEN
   form_link:=(SELECT link FROM public.forms WHERE id=form_id);
  END IF;
  IF coalesce((payload->>'formLinkAutomatic')::boolean,false) THEN
   FOR j IN 1..20 LOOP
    -- Preserve the preview where still free; re-suggest if another writer won.
    IF form_link IS NULL OR EXISTS(SELECT 1 FROM public.form_link_reservations WHERE slug=form_link AND form IS DISTINCT FROM form_id) THEN
     form_link:=public.suggest_occasion_setup_form_link(p_id,payload->>'title',NULL)->>'suggestion';
    END IF;
    BEGIN
     form_link:=public.reserve_public_link_internal('form',form_id,form_link,false);
     EXIT;
    EXCEPTION WHEN unique_violation THEN
     IF j=20 THEN RAISE; END IF;
     form_link:=NULL;
    END;
   END LOOP;
  END IF;
  DELETE FROM public.form_fields WHERE form=form_id;
  DELETE FROM eshop.products WHERE occasion=new_id;
  DELETE FROM eshop.product_types WHERE occasion=new_id;
  -- Active plan owns the public seat selector. Catalog products remain available without it.
  form_data:=jsonb_set(form_data,'{fields}',coalesce((
   SELECT jsonb_agg(f) FROM jsonb_array_elements(coalesce(form_data->'fields','[]')) f
   WHERE f->>'type' IS DISTINCT FROM 'spot'),'[]'::jsonb)||
   CASE WHEN blueprint_mode<>'none' THEN jsonb_build_array('{"order":-1}'::jsonb ||
     coalesce((SELECT f FROM jsonb_array_elements(coalesce(form_data->'fields','[]')) f WHERE f->>'type'='spot' LIMIT 1),'{}'::jsonb) ||
     '{"type":"spot","is_ticket_field":true,"is_hidden":false,"is_required":true}'::jsonb) ELSE '[]'::jsonb END);
  -- Every field/product is newly owned by this occasion. Retain a local mapping
  -- for seats that referred to draft/source product IDs.
  FOR field IN SELECT value FROM jsonb_array_elements(coalesce(form_data->'fields','[]')) LOOP
   pt := coalesce(nullif(field->'product_type_data','null'::jsonb),field->'product_type');
   IF jsonb_typeof(pt)<>'object' THEN pt := NULL; END IF;
   field := field - 'id' - 'form' - 'product_type';
   IF pt IS NOT NULL AND pt<>'null'::jsonb THEN
    old_products := old_products || coalesce(pt->'products','[]');
    products := '[]';
    FOR product IN SELECT value FROM jsonb_array_elements(coalesce(pt->'products','[]')) LOOP
     products := products || jsonb_build_array(product-'id'-'occasion'-'product_type');
    END LOOP;
    field := (field-'product_type_data') || jsonb_build_object('product_type',(pt-'id'-'occasion') || jsonb_build_object('products',products));
   END IF;
   old_types := old_types || jsonb_build_array(pt->'id');
   fields := fields || jsonb_build_array(field);
  END LOOP;
  -- This form was born inside this same setup transaction. Its original form
  -- baseline is zero; the setup revision/command still owns materialization.
  result := public.update_form_internal_v1((form_data-'id'-'fields'-'blueprint'-'bank_account') || jsonb_build_object(
   'expected_aggregate_version',0,'id',form_id,'occasion',new_id,'link',coalesce(form_link,(SELECT link FROM public.forms WHERE id=form_id)),
   'is_open',sale_mode<>'preparation','bank_account',selected_bank,'form_fields',fields));
  IF result->>'code'<>'200' THEN RAISE EXCEPTION '%',result; END IF;
  IF jsonb_array_length(old_types)>0 THEN
   FOR idx IN 0..jsonb_array_length(old_types)-1 LOOP
    IF old_types->>idx IS NOT NULL THEN type_map := type_map || jsonb_build_object(old_types->>idx,result->'form_fields'->idx->'product_type'->'id'); END IF;
   END LOOP;
  END IF;
  SELECT coalesce(jsonb_agg(p ORDER BY field_order,product_order),'[]') INTO new_products
  FROM (SELECT p,ff.ordinality field_order,pp.ordinality product_order
   FROM jsonb_array_elements(result->'form_fields') WITH ORDINALITY ff(f,ordinality)
   CROSS JOIN LATERAL jsonb_array_elements(coalesce(ff.f->'product_type'->'products','[]')) WITH ORDINALITY pp(p,ordinality)) x;
  IF jsonb_array_length(old_products)>0 THEN
   FOR idx IN 0..jsonb_array_length(old_products)-1 LOOP
    IF old_products->idx->>'id' IS NOT NULL THEN product_map := product_map || jsonb_build_object(old_products->idx->>'id',new_products->idx->'id'); END IF;
   END LOOP;
  END IF;
  IF blueprint_mode<>'none' THEN
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(payload#>'{blueprintLayoutDraft,seatBindings}','[]')) binding
     WHERE binding->>'productId' IS NULL OR product_map->>(binding->>'productId') IS NULL) THEN
    RAISE invalid_parameter_value USING MESSAGE='Every blueprint seat requires a form product'; END IF;
  IF payload->'blueprintLayoutDraft' IS NOT NULL AND payload->'blueprintLayoutDraft'<>'null'::jsonb THEN
   IF payload#>>'{blueprintLayoutDraft,layout,schemaVersion}'='2' THEN
    PERFORM public.copy_blueprint_text_resources_internal(NULL,d.id,new_id,payload#>'{blueprintLayoutDraft,layout}');
   END IF;
   blueprint_id:=public.materialize_setup_blueprint_layout_internal(payload->'blueprintLayoutDraft',product_map,blueprint_source,new_id,d.unit);
   UPDATE public.forms SET blueprint=blueprint_id WHERE id=form_id;
   features:=features||'[{"code":"blueprint","is_enabled":true}]';
  ELSE
   RAISE check_violation USING MESSAGE='BLUEPRINT_LAYOUT_REQUIRED';
  END IF;
  END IF;
 END IF;
 -- Plans are materialized through the existing price-wave commands, using
 -- newly mapped product IDs. No source IDs or second scheduler escape.
 IF coalesce((payload->>'priceWavesEnabled')::boolean,false) AND coalesce((payload->>'formEnabled')::boolean,true)
   AND EXISTS(SELECT 1 FROM eshop.products p JOIN public.form_fields ff ON ff.product_type=p.product_type
     WHERE p.occasion=new_id AND ff.form=form_id AND NOT coalesce(ff.is_hidden,false)
       AND p.price>0 AND NOT coalesce(p.is_hidden,false)) THEN
  FOR wave IN SELECT value FROM jsonb_array_elements(coalesce(payload->'priceWaves','[]')) LOOP
   saved_wave:=public.create_product_price_wave((SELECT link FROM public.occasions WHERE id=new_id),(wave->>'change_time')::timestamptz);
   FOR target IN SELECT value FROM jsonb_array_elements(coalesce(wave->'targets','[]')) LOOP
    wave_product:=(product_map->>(target->>'product'))::bigint;
    IF wave_product IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='Price wave product missing'; END IF;
    PERFORM public.save_product_wave_target((saved_wave->>'id')::bigint,wave_product,(saved_wave->>'revision')::bigint,
      (target->>'price')::numeric,(target->>'is_hidden')::boolean,NULL,NULL);
   END LOOP;
  END LOOP;
 END IF;
 -- Rebind ticket product-type references only after their new IDs exist.
 IF has_tickets AND payload->'ticketDraft' ? 'layout' THEN
  pt := payload->'ticketDraft'||'{"code":"ticket","is_enabled":true}'::jsonb;
  SELECT jsonb_set(pt,'{layout,templates}',jsonb_object_agg(t.key,
    jsonb_set(t.value,'{elements}',coalesce((SELECT jsonb_agg(CASE WHEN e->>'binding'='productType'
      THEN jsonb_set(e,'{productTypeId}',coalesce(type_map->(e->>'productTypeId'),'null'::jsonb)) ELSE e END ORDER BY n)
      FROM jsonb_array_elements(t.value->'elements') WITH ORDINALITY x(e,n)),'[]'::jsonb))))
   INTO pt FROM jsonb_each(pt->'layout'->'templates') t;
  features := (SELECT jsonb_agg(CASE WHEN f->>'code'='ticket' THEN pt ELSE f END) FROM jsonb_array_elements(features) f);
 END IF;
 PERFORM public.validate_ticket_layout_references(new_id,f->'layout') FROM jsonb_array_elements(features) f WHERE f ? 'layout';
 final_features := features;
 UPDATE public.occasions SET features=final_features WHERE id=new_id;
 IF coalesce((payload->>'copyProgram')::boolean,false) THEN
  PERFORM public.materialize_occasion_setup_program_internal(coalesce(payload->'sourceProgram','[]'),new_id,d.unit);
 END IF;
 IF coalesce((payload->>'copyInformation')::boolean,false) THEN
  INSERT INTO public.information(occasion,unit,title,description,type,data)
  SELECT new_id,d.unit,i->>'title',i->>'description',i->>'type',i->'data'
  FROM jsonb_array_elements(coalesce(payload->'sourceInformation','[]')) i;
 END IF;
 IF coalesce((payload->>'copyEmails')::boolean,false) AND source_id IS NOT NULL THEN
  INSERT INTO public.email_templates(occasion,unit,organization,code,title,subject,html)
  SELECT new_id,d.unit,d.organization,code,title,subject,html FROM public.email_templates WHERE occasion=source_id;
 END IF;
 PERFORM public.admit_occasion_copy_v1(new_id,d.unit,d.organization,policies->'occasion.copy');
 IF email_banner IS NOT NULL THEN
  PERFORM public.update_entity_email_banner('occasion',new_id,email_banner);
 END IF;
 -- Draft edits override copied/inherited content only on the newly created occasion.
 FOR pt IN SELECT jsonb_build_object('code',key,'content',value)
  FROM jsonb_each(coalesce(payload->'emailTemplateOverrides','{}')) LOOP
  DELETE FROM public.email_templates WHERE occasion=new_id AND code=pt->>'code';
  INSERT INTO public.email_templates(occasion,unit,organization,code,subject,html)
  VALUES(new_id,d.unit,d.organization,pt->>'code',pt#>>'{content,subject}',pt#>>'{content,html}');
 END LOOP;
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
 VALUES('occasion','occasion',new_id,new_id::text,1);
 INSERT INTO public.client_commits(unit,actor_id,actor_kind,source,change_class)
 VALUES(d.unit,auth.uid(),'user','occasion.setup.finalize','configuration') RETURNING * INTO v_commit;
 INSERT INTO public.client_commit_items(commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
 SELECT v_commit.commit_id,0,'occasion',new_id::text,'insert',left(title,240),ARRAY['aggregate'] FROM public.occasions WHERE id=new_id;
 PERFORM public.fanout_unit_catalog_v1(v_commit.commit_id,d.unit);
 receipt := jsonb_build_object('status','applied','code',200,'data',
  jsonb_build_object('occasionId',new_id,'link',(SELECT link FROM public.occasions WHERE id=new_id),
   'formLink',(SELECT link FROM public.forms WHERE id=form_id),'saleMode',sale_mode,'isOpen',(SELECT is_open FROM public.occasions WHERE id=new_id),'isHidden',(SELECT is_hidden FROM public.occasions WHERE id=new_id),'isPromoted',(SELECT is_promoted FROM public.occasions WHERE id=new_id)));
 receipt := public.finish_client_mutation_v1(p_command_id,receipt,v_commit.commit_id);
 UPDATE public.occasion_setup_drafts SET data=data || jsonb_build_object('finalizedOccasion',new_id,'finalizeResponse',receipt),revision=revision+1 WHERE id=p_id;
 RETURN receipt;
END $$;
REVOKE ALL ON FUNCTION public.finalize_occasion_setup_draft(uuid,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.finalize_occasion_setup_draft(uuid,bigint,uuid) TO authenticated;
