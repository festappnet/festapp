-- Ticket layout editor: canonical definitions.
BEGIN;

-- Layout writes are accepted only through the explicit occasion-save boundary.
CREATE OR REPLACE FUNCTION public.can_edit_ticket_layout(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT auth.uid() IS NOT NULL AND COALESCE((SELECT public.get_is_editor_on_unit(o.unit)
    FROM public.occasions o WHERE o.id=p_occasion),false);
$$;
REVOKE ALL ON FUNCTION public.can_edit_ticket_layout(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_edit_ticket_layout(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.validate_ticket_layout(p_layout jsonb)
RETURNS void LANGUAGE plpgsql IMMUTABLE
SET search_path = public, extensions AS $$
DECLARE t jsonb; e jsonb; b jsonb; s jsonb; a jsonb; q jsonb; kind text; k text; ids text[]; bindings text[];
BEGIN
  IF p_layout IS NULL OR jsonb_typeof(p_layout) <> 'object' OR p_layout->'schemaVersion' IS DISTINCT FROM '1'::jsonb
    OR jsonb_typeof(p_layout->'templates') IS DISTINCT FROM 'object' OR p_layout->'templates'='{}'::jsonb OR octet_length(p_layout::text)>32768
  THEN RAISE EXCEPTION 'Invalid ticket layout'; END IF;
  FOR kind,t IN SELECT * FROM jsonb_each(p_layout->'templates') LOOP
    IF kind NOT IN ('wide','named') OR jsonb_typeof(t->'elements') IS DISTINCT FROM 'array'
      OR jsonb_array_length(t->'elements') NOT BETWEEN 2 AND 11
      OR (kind='wide' AND t->'page' IS DISTINCT FROM '{"width":595.28,"height":841.89}'::jsonb)
      OR (kind='named' AND t->'page' IS DISTINCT FROM '{"width":212.5,"height":387.5}'::jsonb)
    THEN RAISE EXCEPTION 'Invalid ticket template'; END IF;
    a:=t->'ticketArea'; ids:='{}'; bindings:='{}';
    FOR b IN SELECT a UNION ALL SELECT value->'box' FROM jsonb_array_elements(t->'elements') LOOP
      FOR k IN SELECT unnest(ARRAY['x','y','width','height']) LOOP
        IF jsonb_typeof(b->k) IS DISTINCT FROM 'number' OR (b->>k)::numeric<0 OR (b->>k)::numeric>842
        THEN RAISE EXCEPTION 'Invalid layout box'; END IF;
      END LOOP;
      IF (b->>'width')::numeric<1 OR (b->>'height')::numeric<1 THEN RAISE EXCEPTION 'Empty layout box'; END IF;
    END LOOP;
    IF (a->>'x')::numeric+(a->>'width')::numeric>(t->'page'->>'width')::numeric+.001
      OR (a->>'y')::numeric+(a->>'height')::numeric>(t->'page'->>'height')::numeric+.001
    THEN RAISE EXCEPTION 'Ticket outside page'; END IF;
    FOR e IN SELECT * FROM jsonb_array_elements(t->'elements') LOOP
      b:=e->'box'; s:=e->'style';
      IF e->>'binding' IS NULL OR e->>'binding' NOT IN ('qr','ticketSymbol','spotGroup','food','note','price','occasionTitle','occasionDatePlace','orderName','logo','footer')
        OR e->>'binding'=ANY(bindings) OR e->>'id'=ANY(ids) OR COALESCE(e->>'id','') !~ '^[a-zA-Z0-9_-]{1,40}$'
        OR jsonb_typeof(e->'visible') IS DISTINCT FROM 'boolean' OR jsonb_typeof(e->'locked') IS DISTINCT FROM 'boolean'
        OR (b->>'x')::numeric+(b->>'width')::numeric>(a->>'width')::numeric+.001
        OR (b->>'y')::numeric+(b->>'height')::numeric>(a->>'height')::numeric+.001
      THEN RAISE EXCEPTION 'Invalid layout element'; END IF;
      ids:=array_append(ids,e->>'id'); bindings:=array_append(bindings,e->>'binding');
      IF jsonb_typeof(s->'fontSize') IS DISTINCT FROM 'number' OR jsonb_typeof(s->'minFontSize') IS DISTINCT FROM 'number'
        OR jsonb_typeof(s->'maxLines') IS DISTINCT FROM 'number' OR COALESCE(s->>'color','') !~ '^[a-fA-F0-9]{6}$'
        OR COALESCE(s->>'align','') NOT IN ('left','center','right')
      THEN RAISE EXCEPTION 'Invalid layout style'; END IF;
      IF (s->>'fontSize')::numeric NOT BETWEEN 6 AND 72 OR (s->>'minFontSize')::numeric NOT BETWEEN 6 AND (s->>'fontSize')::numeric
        OR (s->>'maxLines')::numeric NOT BETWEEN 1 AND 12 OR (s->>'maxLines')::numeric<>trunc((s->>'maxLines')::numeric)
      THEN RAISE EXCEPTION 'Invalid text size'; END IF;
      IF e->>'binding' IN ('qr','ticketSymbol') AND e->'visible'<>'true'::jsonb THEN RAISE EXCEPTION 'Required ticket element hidden'; END IF;
      IF e->>'binding'='qr' THEN
        q:=b;
        IF b->'width'<>b->'height' OR (b->>'width')::numeric<60 OR upper(s->>'color') NOT IN ('000000','2A2A2A','17365D','123B20','401529') THEN RAISE EXCEPTION 'Invalid QR dimensions'; END IF;
      END IF;
    END LOOP;
    IF NOT bindings @> ARRAY['qr','ticketSymbol'] THEN RAISE EXCEPTION 'Missing required ticket elements'; END IF;
    FOR e IN SELECT * FROM jsonb_array_elements(t->'elements') LOOP
      b:=e->'box';
      IF e->'visible'='true'::jsonb AND e->>'binding' NOT IN ('qr','logo')
        AND (b->>'x')::numeric<(q->>'x')::numeric+(q->>'width')::numeric
        AND (b->>'x')::numeric+(b->>'width')::numeric>(q->>'x')::numeric
        AND (b->>'y')::numeric<(q->>'y')::numeric+(q->>'height')::numeric
        AND (b->>'y')::numeric+(b->>'height')::numeric>(q->>'y')::numeric
      THEN RAISE EXCEPTION 'Text overlaps QR quiet zone'; END IF;
    END LOOP;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.merge_ticket_layout_features(p_old jsonb,p_next jsonb,p_change jsonb DEFAULT NULL,p_create boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE
SET search_path = public, extensions AS $$
DECLARE old_layout jsonb; next_layout jsonb; f jsonb; result jsonb:='[]'; found_ticket boolean:=false;
BEGIN
  IF jsonb_typeof(p_next) IS DISTINCT FROM 'array' OR (SELECT count(*) FROM jsonb_array_elements(p_next) e WHERE e->>'code'='ticket')>1
  THEN RAISE EXCEPTION 'Invalid features'; END IF;
  SELECT value->'layout' INTO old_layout FROM jsonb_array_elements(COALESCE(p_old,'[]')) WHERE value->>'code'='ticket';
  next_layout:=old_layout;
  IF p_change IS NOT NULL THEN
    IF jsonb_typeof(p_change)<>'object' OR NOT (p_change ? 'expected' AND p_change ? 'next') THEN RAISE EXCEPTION 'Invalid ticket layout change'; END IF;
    IF COALESCE(old_layout,'null') IS DISTINCT FROM p_change->'expected' THEN
      RAISE EXCEPTION 'ticket_layout_conflict' USING ERRCODE='40001';
    END IF;
    -- A client must not downgrade a schema it does not understand.
    IF old_layout IS NOT NULL AND old_layout->'schemaVersion' IS DISTINCT FROM '1'::jsonb THEN RAISE EXCEPTION 'Unsupported ticket layout'; END IF;
    next_layout:=p_change->'next'; PERFORM public.validate_ticket_layout(next_layout);
  END IF;
  FOR f IN SELECT * FROM jsonb_array_elements(p_next) LOOP
    IF f->>'code'='ticket' THEN
      found_ticket:=true;
      IF p_create AND p_change IS NULL THEN next_layout:=f->'layout'; IF next_layout IS NOT NULL THEN PERFORM public.validate_ticket_layout(next_layout); END IF; END IF;
      f:=f-'layout'; IF next_layout IS NOT NULL THEN f:=f||jsonb_build_object('layout',next_layout); END IF;
    END IF;
    result:=result||jsonb_build_array(f);
  END LOOP;
  IF NOT found_ticket AND next_layout IS NOT NULL THEN result:=result||jsonb_build_array(jsonb_build_object('code','ticket','is_enabled',false,'layout',next_layout)); END IF;
  RETURN result;
END;
$$;


CREATE OR REPLACE FUNCTION public.update_occasion_internal_v1(input_data JSONB)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
 AS $$
 DECLARE
     updated_occ public.occasions;
     occ_id BIGINT;
     now TIMESTAMPTZ := NOW();
     final_unit BIGINT;

     -- Variable for the determined support flag
     is_app_supported BOOLEAN;

     -- Variable to help find the organization to check settings
     v_org_id BIGINT;

     -- Variables for feature handling
     new_blueprint_id BIGINT;
     v_form_id BIGINT;
     v_form_blueprint BIGINT;
     v_form_settings JSONB;
     v_reminder_interval_seconds BIGINT;

     input_features JSONB;
     old_features JSONB;
     processed_features JSONB;
     feature JSONB;
     form_feature_found BOOLEAN;
 BEGIN
     -- Validate input data. Raise an exception if it's missing or empty.
     IF input_data IS NULL OR input_data = '{}'::jsonb THEN
         RAISE EXCEPTION 'Input data is missing or empty';
     END IF;

     -- 1. Identify the Organization ID
     IF (input_data->>'id') IS NOT NULL THEN
         -- Case A: UPDATE - Get organization from the existing occasion
         SELECT organization INTO v_org_id
         FROM public.occasions
         WHERE id = (input_data->>'id')::BIGINT;
     ELSE
         -- Case B: INSERT - Try to get organization from input
         v_org_id := (input_data->>'organization')::BIGINT;

         -- Case C: INSERT fallback - If org is missing, try to get it via the Unit
         IF v_org_id IS NULL AND (input_data->>'unit') IS NOT NULL THEN
            SELECT organization INTO v_org_id
            FROM public.units
            WHERE id = (input_data->>'unit')::BIGINT;
         END IF;
     END IF;

     -- 2. Fetch the setting from public.organizations.data
     -- Defaults to TRUE if the organization or the key is not found to ensure backward compatibility
     IF v_org_id IS NOT NULL THEN
         SELECT COALESCE((data->>'IS_APP_SUPPORTED')::BOOLEAN, false)
         INTO is_app_supported
         FROM public.organizations
         WHERE id = v_org_id;
     ELSE
         is_app_supported := false;
     END IF;

     -- Ensure is_app_supported is not null (redundant safety check)
     is_app_supported := COALESCE(is_app_supported, false);

     --
     -- Prepare features based on is_app_supported flag
     --
     input_features := COALESCE(input_data->'features', '[]'::jsonb);
     processed_features := '[]'::jsonb;

     IF NOT is_app_supported THEN
         -- If the app is not supported, we must enable the 'form' feature.
         form_feature_found := false;
         -- Loop through existing features to find and enable the form feature
         FOR feature IN SELECT * FROM jsonb_array_elements(input_features)
         LOOP
             IF feature->>'code' = 'form' THEN
                 -- If form feature exists, ensure it is enabled
                 feature := feature || '{"is_enabled": true}';
                 form_feature_found := true;
             END IF;
             processed_features := processed_features || feature;
         END LOOP;

         -- If the form feature was not found in the original array, add it.
         IF NOT form_feature_found THEN
             processed_features := processed_features || '{"code": "form", "is_enabled": true}';
         END IF;
     ELSE
         -- If app is supported, use features as they were provided.
         processed_features := input_features;
     END IF;

     -- Determine if this is an UPDATE or INSERT based on the presence of an 'id'
     occ_id := (input_data->>'id')::BIGINT;

     IF occ_id IS NOT NULL THEN
         -- This is an UPDATE operation

         -- Check for the existence of the occasion and get its current unit
         SELECT unit, features INTO final_unit, old_features FROM public.occasions WHERE id = occ_id FOR UPDATE;
         IF NOT FOUND THEN
             RAISE EXCEPTION 'Occasion with ID % not found', occ_id;
         END IF;

         IF NOT public.get_is_editor_on_unit(final_unit) THEN
             RAISE insufficient_privilege USING MESSAGE = 'unit editor required';
         END IF;
         processed_features := public.merge_ticket_layout_features(old_features, processed_features, input_data->'ticket_layout_change');

         -- Determine the final unit, allowing it to be updated.
         final_unit := COALESCE((input_data->>'unit')::BIGINT, final_unit);

         -- Security check: ensure the current user has editor rights on the target unit.
         IF NOT public.get_is_editor_on_unit(final_unit) THEN
             RAISE insufficient_privilege USING MESSAGE = 'unit editor required';
         END IF;

         UPDATE public.occasions
            SET updated_at  = now,
                title       = COALESCE(input_data->>'title', title),
                description = COALESCE(input_data->>'description', description),
                link        = COALESCE(input_data->>'link', link),
                data        = COALESCE(input_data->'data', data),
                is_hidden   = COALESCE((input_data->>'is_hidden')::BOOLEAN, is_hidden),
                is_open     = COALESCE((input_data->>'is_open')::BOOLEAN, is_open),
                is_promoted = COALESCE((input_data->>'is_promoted')::BOOLEAN, is_promoted),
                start_time  = COALESCE((input_data->>'start_time')::TIMESTAMPTZ, start_time),
                end_time    = COALESCE((input_data->>'end_time')::TIMESTAMPTZ, end_time),
                organization = COALESCE((input_data->>'organization')::BIGINT, organization),
                services    = COALESCE(input_data->'services', services),
                unit        = final_unit,
                features    = processed_features -- Use the processed features
          WHERE id = occ_id
          RETURNING * INTO updated_occ;

     ELSE
         -- This is an INSERT operation

         -- For new occasions, the 'unit' field is mandatory.
         final_unit := (input_data->>'unit')::BIGINT;
         IF final_unit IS NULL THEN
             RAISE EXCEPTION 'The "unit" field is required for new occasions';
         END IF;

         -- Security check for the new occasion's unit.
         IF NOT public.get_is_editor_on_unit(final_unit) THEN
             RAISE insufficient_privilege USING MESSAGE = 'unit editor required';
         END IF;

         -- We still need to default 'reminder_is_enabled' for the 'form' feature if not specified.
         -- We do this on the already processed_features array.
         input_features := processed_features; -- Use the result from the is_app_supported logic
         processed_features := '[]'::jsonb;
         FOR feature IN SELECT * FROM jsonb_array_elements(input_features)
         LOOP
             -- If the current feature is the 'form' feature
             IF feature->>'code' = 'form' THEN
                 -- And if 'reminder_is_enabled' is NOT specified, default it to true.
                 IF NOT (feature ? 'reminder_is_enabled') THEN
                     feature := feature || '{"reminder_is_enabled": true}';
                 END IF;
             END IF;
             processed_features := processed_features || feature::jsonb;
         END LOOP;

         processed_features := public.merge_ticket_layout_features('[]', processed_features, input_data->'ticket_layout_change', true);

         INSERT INTO public.occasions(
             created_at, updated_at, title, description, link, data,
             is_hidden, is_open, is_promoted, start_time, end_time, organization,
             services, unit, features
         )
         VALUES(
             now, now,
             COALESCE(input_data->>'title', ''),
             COALESCE(input_data->>'description', ''),
             input_data->>'link',
             COALESCE(input_data->'data', '{}'::jsonb),
             COALESCE((input_data->>'is_hidden')::BOOLEAN, false),
             COALESCE((input_data->>'is_open')::BOOLEAN, true),
             COALESCE((input_data->>'is_promoted')::BOOLEAN, false),
             (input_data->>'start_time')::TIMESTAMPTZ,
             (input_data->>'end_time')::TIMESTAMPTZ,
             (input_data->>'organization')::BIGINT,
             COALESCE(input_data->'services', '{}'::jsonb),
             final_unit,
             processed_features
         )
         RETURNING * INTO updated_occ;

         -- Set the occ_id from the newly created record for subsequent logic
         occ_id := updated_occ.id;
     END IF;

     --
     -- Post-update/insert feature handling
     --

     -- Check if form feature is enabled and handle related logic.
     -- This will now be triggered if is_app_supported was false (based on organization settings).
     IF jsonb_path_exists(updated_occ.features, '$[*] ? (@.code == "form" && @.is_enabled == true)') THEN
         -- Extract the settings for the 'form' feature from the newly saved data
         SELECT elem INTO v_form_settings
         FROM jsonb_array_elements(updated_occ.features) AS elem
         WHERE elem->>'code' = 'form';

         -- Create a default form if one doesn't exist for the occasion
         IF NOT EXISTS (SELECT 1 FROM public.forms WHERE occasion = occ_id) THEN
             PERFORM create_form(
                 occ_id,
                 COALESCE(input_data->>'form_link', updated_occ.link),
                 'Registration'
             );
         END IF;

         -- Check if reminders are enabled within the form feature
         IF (v_form_settings->>'reminder_is_enabled')::boolean IS TRUE THEN
             -- Get the reminder interval, defaulting to 1 day (86400 seconds) if not specified
             v_reminder_interval_seconds := COALESCE(
                 (v_form_settings->>'reminder_interval_seconds')::bigint,
                 86400
             );
             -- Call the function to queue payment reminders for all relevant orders
             PERFORM public.queue_payment_reminders(occ_id, v_reminder_interval_seconds);
         END IF;
     END IF;

     -- Check if the blueprint feature is enabled in the final, saved state
     IF jsonb_path_exists(updated_occ.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)') THEN
         -- Find the associated form to attach the blueprint to
         SELECT id, blueprint INTO v_form_id, v_form_blueprint
           FROM public.forms
          WHERE occasion = occ_id
          LIMIT 1;

         -- If a form exists and it doesn't already have a blueprint, create one.
         IF FOUND AND v_form_blueprint IS NULL THEN
             INSERT INTO eshop.blueprints(configuration, occasion, organization, created_at, updated_at)
             VALUES ('{"dimensions": {"width": 28, "height": 52}}'::jsonb, occ_id, COALESCE(updated_occ.organization, 1), now, now)
             RETURNING id INTO new_blueprint_id;

             UPDATE public.forms
                SET blueprint = new_blueprint_id,
                    updated_at = now
              WHERE id = v_form_id;
         END IF;
     END IF;
 END;
 $$;

CREATE OR REPLACE FUNCTION public.update_occasion_203(input_data jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
BEGIN
  PERFORM public.update_occasion_internal_v1(input_data);
END;
$$;



-- Occasion settings are edited from the unit workspace. Keep the explicit
-- wrapper authorization aligned with both that UI contract and the trusted
-- update_occasion_internal_v1 implementation, which authorizes the target
-- unit editor before changing the aggregate.
CREATE OR REPLACE FUNCTION public.save_occasion_client_sync_v1(
  p_occasion bigint,
  p_command_id uuid,
  p_expected_version bigint,
  p_config jsonb
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_config jsonb;
  v_data jsonb;
  v_enabled boolean;
  v_hidden boolean;
  v_unit bigint;
BEGIN
  SELECT
    COALESCE((o.data->>'client_sync_v1')::boolean, false),
    o.is_hidden,
    o.unit
  INTO v_enabled, v_hidden, v_unit
  FROM public.occasions o
  WHERE o.id = p_occasion;

  IF auth.uid() IS NULL OR NOT (
    public.get_is_editor_on_occasion(p_occasion)
    OR public.get_is_admin_on_occasion(p_occasion)
    OR (v_unit IS NOT NULL AND public.get_is_editor_on_unit(v_unit))
  ) THEN
    RAISE insufficient_privilege USING MESSAGE = 'occasion editor required';
  END IF;

  IF v_enabled
    AND NOT v_hidden
    AND COALESCE((p_config->>'is_hidden')::boolean, false)
  THEN
    RAISE object_not_in_prerequisite_state
      USING MESSAGE = 'disable client_sync_v1 before hiding occasion';
  END IF;

  v_data := CASE
    WHEN jsonb_typeof(p_config->'data') = 'object' THEN p_config->'data'
    ELSE '{}'::jsonb
  END;
  v_config := jsonb_set(
    p_config,
    '{data}',
    jsonb_set(
      v_data,
      '{client_sync_v1}',
      to_jsonb(COALESCE(v_enabled, false)),
      true
    ),
    true
  );

  RETURN public.save_occasion_domain_command_internal_v1(
    p_occasion,
    p_command_id,
    p_expected_version,
    v_config
  );
END;
$$;

REVOKE ALL ON FUNCTION public.save_occasion_client_sync_v1(
  bigint,
  uuid,
  bigint,
  jsonb
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_occasion_client_sync_v1(
  bigint,
  uuid,
  bigint,
  jsonb
) TO authenticated;




-- The public save wrapper and the settings UI allow unit editors. The renamed
-- canonical domain command retained its older occasion-only guard, so it must
-- accept the same role before it reaches update_occasion_internal_v1.
CREATE OR REPLACE FUNCTION public.save_occasion_domain_command_internal_v1(
  p_occasion bigint,
  p_command_id uuid,
  p_expected_version bigint,
  p_config jsonb
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_version bigint;
  v_begin jsonb;
  v_hash text;
  v_entity jsonb;
  v_old_hidden boolean;
  v_new_hidden boolean;
  v_old_unit bigint;
  v_new_unit bigint;
  v_fanout_units bigint[] := '{}';
BEGIN
  SELECT o.unit INTO v_old_unit
  FROM public.occasions o
  WHERE o.id = p_occasion;

  IF v_actor IS NULL OR NOT (
    public.get_is_editor_on_occasion(p_occasion)
    OR public.get_is_admin_on_occasion(p_occasion)
    OR (v_old_unit IS NOT NULL AND public.get_is_editor_on_unit(v_old_unit))
  ) THEN
    RAISE insufficient_privilege USING MESSAGE = 'occasion editor required';
  END IF;

  IF p_config IS NULL OR jsonb_typeof(p_config) <> 'object'
    OR octet_length(p_config::text) > 1048576
    OR (p_config->>'id')::bigint IS DISTINCT FROM p_occasion
    OR EXISTS (
      SELECT 1
      FROM jsonb_object_keys(p_config) key
      WHERE key NOT IN (
        'id', 'start_time', 'end_time', 'is_open', 'is_hidden', 'is_promoted',
        'link', 'title', 'description', 'data', 'services', 'organization',
        'unit', 'features', 'form_link', 'has_orders', 'stats', 'ticket_layout_change'
      )
    )
  THEN
    RAISE invalid_parameter_value USING MESSAGE = 'invalid occasion aggregate';
  END IF;

  v_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion', p_occasion,
    'expectedVersion', p_expected_version,
    'config', p_config
  )::text, 'UTF8'), 'sha256'), 'hex');
  v_begin := public.begin_client_mutation_v1(
    p_command_id,
    'occasion.config.save',
    p_occasion,
    v_actor,
    v_hash
  );
  IF v_begin->>'disposition' = 'replay' THEN
    RETURN v_begin->'response';
  END IF;

  SELECT o.is_hidden, o.unit INTO v_old_hidden, v_old_unit
  FROM public.occasions o
  WHERE o.id = p_occasion
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,
      'rejected',
      404,
      jsonb_build_object('version', 0, 'occasion', NULL)
    );
  END IF;

  INSERT INTO public.client_aggregate_versions(
    aggregate_type, scope_type, scope_id, aggregate_id, version
  ) VALUES ('occasion', 'occasion', p_occasion, p_occasion::text, 0)
  ON CONFLICT DO NOTHING;
  SELECT version INTO v_version
  FROM public.client_aggregate_versions
  WHERE aggregate_type = 'occasion'
    AND scope_type = 'occasion'
    AND scope_id = p_occasion
    AND aggregate_id = p_occasion::text
  FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    SELECT to_jsonb(o) || jsonb_build_object('aggregate_version', v_version)
    INTO v_entity
    FROM public.occasions o
    WHERE o.id = p_occasion;
    RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,
      'conflict',
      409,
      jsonb_build_object('version', v_version, 'occasion', v_entity)
    );
  END IF;

  PERFORM public.update_occasion_internal_v1(p_config);
  UPDATE public.client_aggregate_versions
  SET version = version + 1, updated_at = clock_timestamp()
  WHERE aggregate_type = 'occasion'
    AND scope_type = 'occasion'
    AND scope_id = p_occasion
    AND aggregate_id = p_occasion::text
  RETURNING version INTO v_version;
  SELECT to_jsonb(o) || jsonb_build_object('aggregate_version', v_version)
  INTO v_entity
  FROM public.occasions o
  WHERE o.id = p_occasion;

  v_new_hidden := (v_entity->>'is_hidden')::boolean;
  v_new_unit := (v_entity->>'unit')::bigint;
  IF NOT v_old_hidden THEN
    v_fanout_units := array_append(v_fanout_units, v_old_unit);
  END IF;
  IF NOT v_new_hidden AND v_new_unit IS DISTINCT FROM v_old_unit THEN
    v_fanout_units := array_append(v_fanout_units, v_new_unit);
  ELSIF NOT v_new_hidden AND v_old_hidden THEN
    v_fanout_units := array_append(v_fanout_units, v_new_unit);
  END IF;

  RETURN public.complete_client_mutation_applied_v1(
    p_command_id,
    p_occasion,
    'occasion.config.save',
    'configuration',
    jsonb_build_array(jsonb_build_object(
      'entityType', 'occasion',
      'entityId', p_occasion,
      'operation', 'update',
      'safeLabel', left(v_entity->>'title', 240),
      'changedFields', jsonb_build_array('configuration')
    )),
    CASE WHEN v_old_hidden AND NOT v_new_hidden THEN ARRAY[
      'occasion_config', 'program_catalog', 'map_catalog', 'content_catalog',
      'live_public'
    ] ELSE ARRAY['occasion_config'] END,
    '[]',
    '[]',
    jsonb_build_object('version', v_version, 'occasion', v_entity),
    CASE WHEN NOT v_new_hidden THEN ARRAY['occasion_config'] ELSE '{}'::text[] END,
    '[]',
    'user',
    NULL,
    '[]',
    v_fanout_units
  );
END;
$$;

REVOKE ALL ON FUNCTION public.save_occasion_domain_command_internal_v1(
  bigint, uuid, bigint, jsonb
) FROM PUBLIC, anon, authenticated;



CREATE OR REPLACE FUNCTION public.get_ticket_details_for_generating(ticket_id_input BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    result JSONB;
BEGIN
    SELECT jsonb_build_object(
        -- 1. Build the 'ticket' key
        'ticket', (
            SELECT to_jsonb(t_detail)
            FROM (
                SELECT
                    t.id,
                    t.ticket_symbol,
                    t.occasion,
                    t.note,
                    t.state,
                    b.title AS table_title,
                    -- Subquery for Spot/Product details
                    (
                        SELECT jsonb_agg(ticket_prod ORDER BY ticket_prod.id)
                        FROM (
                            SELECT
                                opt2.id,
                                opt2.product,
                                s.title AS spot_title,
                                p.data->>'short_title' AS short_title,
                                p.title AS product_title, 
                                (
                                    SELECT g.value->>'title'
                                    FROM jsonb_array_elements(bp.groups) AS g(value)
                                    WHERE (g.value->>'id')::bigint = (
                                        SELECT (o2.value->>'group')::bigint
                                        FROM jsonb_array_elements(bp.objects) AS o2(value)
                                        WHERE (o2.value->>'id')::bigint = s.id
                                          AND o2.value->>'type' = 'spot'
                                        LIMIT 1
                                    )
                                    LIMIT 1
                                ) AS spot_group_title
                            FROM eshop.order_product_ticket opt2
                            LEFT JOIN eshop.spots s
                                ON s.order_product_ticket = opt2.id
                            LEFT JOIN eshop.products p
                                ON p.id = opt2.product
                            LEFT JOIN eshop.product_types pt 
                                ON pt.id = p.product_type
                            LEFT JOIN eshop.blueprints bp
                                ON bp.id = s.blueprint
                            WHERE opt2.ticket = t.id
                              AND NOT (pt.type = 'spot' AND s.title IS NULL)
                        ) ticket_prod
                    ) AS order_product_ticket,

                    -- Subquery for Price (extracting from ord.data)
                    (
                      SELECT COALESCE(SUM((prod->>'price')::numeric), 0)
                      FROM jsonb_array_elements(ord.data->'tickets') ticket_json,
                           jsonb_array_elements(ticket_json->'products') prod
                      WHERE (ticket_json->>'id')::bigint = t.id
                    ) AS price,

                    -- Subquery for Currency (extracting from ord.data)
                    (
                      SELECT (prod->>'currency_code')
                      FROM jsonb_array_elements(ord.data->'tickets') ticket_json,
                           jsonb_array_elements(ticket_json->'products') prod
                      WHERE (ticket_json->>'id')::bigint = t.id
                      LIMIT 1
                    ) AS currency_code
            ) t_detail
        ),

        -- 2. Build the 'occasion' key (dumps the whole occasion row including 'features')
        'occasion', to_jsonb(o),
        'order_data', jsonb_build_object('name', ord.data->'name', 'surname', ord.data->'surname')
    )
    INTO result
    FROM eshop.tickets t
    -- Join Occasion to get the occasion object
    JOIN public.occasions o
        ON o.id = t.occasion
    -- Join Blueprint for the table title
    LEFT JOIN eshop.blueprints b
        ON b.occasion = o.id
    -- Join Order Tables to expose 'ord.data' for the ticket sub-calculations above
    LEFT JOIN eshop.order_product_ticket opt
        ON opt.ticket = t.id
    LEFT JOIN eshop.orders ord
        ON ord.id = opt."order"
    WHERE t.id = ticket_id_input;

    RETURN result;
END;
$$;

-- Preserve existing column access, while reserving features for occasion save.
-- Do not grant direct writes to roles that did not already have them.
DO $$
DECLARE v_role text; v_columns text; v_update boolean; v_insert boolean;
BEGIN
  SELECT string_agg(quote_ident(attname), ',') INTO v_columns FROM pg_attribute
    WHERE attrelid='public.occasions'::regclass AND attnum>0 AND NOT attisdropped AND attname<>'features';
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
    v_update := has_table_privilege(v_role,'public.occasions','UPDATE');
    v_insert := has_table_privilege(v_role,'public.occasions','INSERT');
    EXECUTE format('REVOKE UPDATE, INSERT ON public.occasions FROM %I',v_role);
    EXECUTE format('REVOKE UPDATE(features), INSERT(features) ON public.occasions FROM %I',v_role);
    IF v_update THEN EXECUTE format('GRANT UPDATE (%s) ON public.occasions TO %I',v_columns,v_role); END IF;
    IF v_insert THEN EXECUTE format('GRANT INSERT (%s) ON public.occasions TO %I',v_columns,v_role); END IF;
  END LOOP;
END $$;


COMMIT;
