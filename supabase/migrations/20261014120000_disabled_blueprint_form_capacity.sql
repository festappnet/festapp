-- Respect the occasion blueprint feature while preserving stored blueprints.
ALTER TABLE public.forms DROP CONSTRAINT IF EXISTS forms_capacity_configuration;
ALTER TABLE public.forms ADD CONSTRAINT forms_capacity_configuration CHECK (
 (participant_capacity IS NULL OR participant_capacity>0) AND
 (waitlist_offer_duration_seconds IS NULL OR waitlist_offer_duration_seconds>0) AND
 (NOT waitlist_enabled OR (participant_capacity IS NOT NULL AND waitlist_offer_duration_seconds IS NOT NULL AND waitlist_offer_duration_seconds>0)));

-- Source: database/functions/eshop_waitlist/form_capacity.sql
CREATE OR REPLACE FUNCTION public.get_form_capacity_snapshot_internal(p_form bigint,p_at timestamptz DEFAULT clock_timestamp())
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH counts AS (
 SELECT f.*, (SELECT count(DISTINCT t.id) FROM eshop.tickets t JOIN eshop.order_product_ticket x ON x.ticket=t.id JOIN eshop.orders o ON o.id=x."order"
  WHERE o.form=f.id AND t.state IS DISTINCT FROM 'storno' AND t.state IS DISTINCT FROM 'waitlisted' AND o.state IS DISTINCT FROM 'storno') occupied,
 (SELECT count(*) FROM eshop.waitlist_offer_slots s JOIN eshop.waitlist_offers w ON w.id=s.offer_id
  WHERE s.form_id=f.id AND s.outcome='pending' AND w.expires_at>p_at) reserved,
 (SELECT count(DISTINCT t.id) FROM eshop.tickets t JOIN eshop.order_product_ticket x ON x.ticket=t.id JOIN eshop.orders o ON o.id=x."order"
  WHERE o.form=f.id AND o.state='waitlisted' AND public.get_effective_waitlist_ticket_lifecycle_internal(t.id)='waiting') waiting
 FROM public.forms f WHERE f.id=p_form), free AS (
 SELECT *,greatest(participant_capacity-occupied-reserved,0) available FROM counts)
 SELECT jsonb_build_object('enabled',participant_capacity IS NOT NULL,'limit',participant_capacity,
 'remainingPublic',CASE WHEN participant_capacity IS NOT NULL THEN greatest(available-waiting,0) END,
 'showRemaining',show_remaining_capacity,'occupiedPeople',occupied,'offeredPlaces',reserved,'waitingPeople',waiting,
 'offerablePlaces',available,'heldForWaiting',least(available,waiting),'revision',capacity_revision,
 'canSendOffers',waitlist_enabled AND available>0,'blockedReason',CASE WHEN NOT waitlist_enabled THEN 'WAITLIST_NOT_AVAILABLE'
 WHEN available=0 THEN 'FORM_CAPACITY_EXCEEDED' END,'serverTime',p_at) FROM free;
$$;
CREATE OR REPLACE FUNCTION public.get_form_registration_mode_internal(p_form bigint,p_at timestamptz DEFAULT clock_timestamp())
RETURNS text LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; d jsonb; c jsonb;
BEGIN
 SELECT * INTO f FROM public.forms WHERE id=p_form; d:=public.get_effective_form_data(p_form);
 IF NOT f.is_open OR p_at < nullif(coalesce(d#>>'{schedule,start_time}',d->>'start_time'),'')::timestamptz
 OR p_at > nullif(coalesce(d#>>'{schedule,end_time}',d->>'end_time'),'')::timestamptz THEN RETURN 'closed'; END IF;
 IF f.blueprint IS NOT NULL AND EXISTS (
  SELECT 1 FROM public.occasions o WHERE o.id=f.occasion
  AND jsonb_path_exists(o.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)')
 ) THEN RETURN 'blueprint'; END IF;
 c:=public.get_form_capacity_snapshot_internal(p_form,p_at);
 IF f.participant_capacity IS NULL OR (c->>'remainingPublic')::bigint>0 THEN RETURN 'regular'; END IF;
 RETURN CASE WHEN f.waitlist_enabled THEN 'waitlist' ELSE 'full' END;
END $$;
CREATE OR REPLACE FUNCTION public.check_form_capacity_settings_internal(p_form bigint,p_input jsonb)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE f public.forms; c jsonb; n integer; enabled boolean; bp bigint;
BEGIN
 SELECT * INTO STRICT f FROM public.forms WHERE id=p_form FOR UPDATE;
 c:=public.get_form_capacity_snapshot_internal(p_form);
 n:=CASE WHEN p_input ? 'participant_capacity' THEN (p_input->>'participant_capacity')::integer ELSE f.participant_capacity END;
 enabled:=CASE WHEN p_input ? 'waitlist_enabled' THEN (p_input->>'waitlist_enabled')::boolean ELSE f.waitlist_enabled END;
 bp:=CASE WHEN p_input ? 'blueprint' THEN nullif(p_input->>'blueprint','')::bigint ELSE f.blueprint END;
 -- A retained blueprint is inactive when the occasion feature is disabled.
 IF NOT EXISTS (SELECT 1 FROM public.occasions o WHERE o.id=f.occasion
  AND jsonb_path_exists(o.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)')) THEN bp:=NULL; END IF;
 IF n IS NOT NULL AND n<(c->>'occupiedPeople')::bigint+(c->>'offeredPlaces')::bigint THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','CAPACITY_BELOW_COMMITTED','capacity',c)::text; END IF;
 IF ((NOT enabled) OR n IS NULL OR bp IS NOT NULL) AND
 ((c->>'waitingPeople')::bigint>0 OR (c->>'offeredPlaces')::bigint>0) THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','WAITLIST_HAS_ACTIVE_ENTRIES','capacity',c)::text; END IF;
 IF bp IS NOT NULL AND (n IS NOT NULL OR enabled) THEN
  RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','BLUEPRINT_CONFLICT')::text; END IF;
END $$;
REVOKE ALL ON FUNCTION public.get_form_capacity_snapshot_internal(bigint,timestamptz),
 public.get_form_registration_mode_internal(bigint,timestamptz),public.check_form_capacity_settings_internal(bigint,jsonb)
 FROM PUBLIC,anon,authenticated;

-- Source: database/functions/eshop_forms/get_form_by_link.sql
CREATE OR REPLACE FUNCTION public.get_form_bundle_internal(p_form_id bigint,p_allow_closed boolean DEFAULT false)
RETURNS JSON LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, extensions AS $$
DECLARE
    allData JSON;
    generated_secret UUID := gen_random_uuid();
    form_exists BOOLEAN;
    is_editor_view BOOLEAN := false;
    occ_id BIGINT;
BEGIN
    -- Check if the form exists
    SELECT EXISTS (
        SELECT 1
        FROM public.forms
        WHERE id = p_form_id
    ) INTO form_exists;

    IF NOT form_exists THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Form does not exist.'
        );
    END IF;

    SELECT occasion INTO occ_id FROM public.forms WHERE id = p_form_id;
    is_editor_view := public.get_is_editor_order_view_on_occasion(occ_id);


    IF NOT p_allow_closed AND NOT is_editor_view AND NOT EXISTS (
        SELECT 1
        FROM public.forms
        WHERE id = p_form_id AND is_open = true
    ) THEN
        -- If the form is closed, retrieve only the 'header_off' message
        SELECT jsonb_build_object(
            'code', 400,
            'data', jsonb_build_object(
                'header_off', f.header_off,
                'is_open', f.is_open
            )
        )
        INTO allData
        FROM public.forms f
        WHERE f.id = p_form_id;

        RETURN allData;
    END IF;

    -- If the form is open, retrieve the full form data including dynamic product availability
    SELECT jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'capacity', public.get_form_capacity_snapshot_internal(f.id),
            'registrationMode',public.get_form_registration_mode_internal(f.id),
            'participant_capacity',f.participant_capacity,'waitlist_enabled',f.waitlist_enabled,
            'show_remaining_capacity',f.show_remaining_capacity,'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
            'id', f.id,
            'link', f.link,
            'key', f.key,
            'created_at', f.created_at,
            'data', public.get_effective_form_data(f.id),
            'type', f.type,
            'title', f.title,
            'is_open', f.is_open,
            'header', f.header,
            'header_off', f.header_off,
            'occasion', jsonb_build_object(
                'id', o.id,
                'features', o.features,
                'start_time', o.start_time
            ),
            'blueprint', CASE WHEN EXISTS (SELECT 1 FROM public.occasions o WHERE o.id=f.occasion
                AND jsonb_path_exists(o.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)'))
                THEN f.blueprint END,
            'deadline_duration_seconds', f.deadline_duration_seconds,
            'account_number', ba.account_number,
            'secret', generated_secret,
            'fields', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', ff.id,
                        'title', ff.title,
                        'description', ff.description,
                        'data', ff.data,
                        'type', ff.type,
                        'is_required', ff.is_required,
                        'is_hidden', ff.is_hidden,
                        'is_ticket_field', ff.is_ticket_field,
                        'order', ff."order",
                        'product_type_data', (
                            CASE
                                WHEN ff.product_type IS NOT NULL THEN
                                    jsonb_build_object(
                                        'id', pt.id,
                                        'title', pt.title,
                                        'description', pt.description,
                                        'type', pt.type,
                                        'data', pt.data,
                                        'occasion', pt.occasion,
                                        'products', (
                                            SELECT jsonb_agg(
                                                jsonb_build_object(
                                                    'id', p.id,
                                                    'title', p.title,
                                                    'description', p.description,
                                                    'price', p.price,
                                                    'currency_code', p.currency_code,
                                                    'data', p.data,
                                                    'order', p."order",
                                                    'ordered_count', (
                                                        SELECT count(*)
                                                        FROM eshop.order_product_ticket opt
                                                        WHERE opt.product = p.id
                                                    ),
                                                    'maximum', p.maximum,
                                                    'is_dynamically_available', is_product_dynamically_available(p.id)
                                                ) ORDER BY COALESCE(p."order", 0)
                                            )
                                            FROM eshop.products p
                                            WHERE p.product_type = pt.id
                                              AND NOT p.is_hidden
                                        )
                                    )
                                ELSE NULL
                            END
                        )
                    ) ORDER BY COALESCE(ff."order", 0)
                )
                FROM public.form_fields ff
                LEFT JOIN eshop.product_types pt ON ff.product_type = pt.id
                WHERE ff.form = f.id AND ff.is_hidden = false
            )
        )
    )
    INTO allData
    FROM public.forms f
    LEFT JOIN eshop.bank_accounts ba ON f.bank_account = ba.id
    LEFT JOIN public.occasions o ON f.occasion = o.id
    WHERE f.id = p_form_id;

    RETURN allData;
END;
$$;

REVOKE ALL ON FUNCTION public.get_form_bundle_internal(bigint,boolean) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_form_by_link(form_link text)
RETURNS json LANGUAGE sql SECURITY DEFINER
SET search_path=public,extensions AS $$
 SELECT public.get_form_bundle_internal((SELECT id FROM public.forms WHERE link=form_link),false);
$$;

-- Source: database/functions/others/update_occasion.sql
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
     v_form_link TEXT;
     v_form_link_base TEXT;
     v_form_link_suffix INTEGER;
     v_reminder_interval_seconds BIGINT;
     v_email_order record;

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
         PERFORM public.validate_ticket_layout_references(occ_id, f->'layout') FROM jsonb_array_elements(processed_features) f WHERE f->>'code'='ticket' AND f ? 'layout';

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
                is_order_synchronization_enabled=COALESCE((input_data->>'is_order_synchronization_enabled')::boolean,is_order_synchronization_enabled),
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

     -- Enabling the blueprint feature must not bypass form capacity/waitlist guards,
     -- including when the stored blueprint already exists.
     IF jsonb_path_exists(updated_occ.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)') THEN
       FOR v_form_id IN SELECT id FROM public.forms WHERE occasion=occ_id ORDER BY id LOOP
         PERFORM public.check_form_capacity_settings_internal(v_form_id, '{"blueprint":1}'::jsonb);
       END LOOP;
     END IF;

     PERFORM public.validate_ticket_layout_references(occ_id, f->'layout') FROM jsonb_array_elements(processed_features) f WHERE f->>'code'='ticket' AND f ? 'layout';
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
             v_form_link := NULLIF(btrim(input_data->>'form_link'), '');
             IF v_form_link IS NULL THEN
                 -- Occasion slugs and form slugs are separate namespaces.
                 -- An automatic default must not block an unrelated settings save.
                 v_form_link_base := COALESCE(NULLIF(updated_occ.link, ''), 'registration');
                 v_form_link := v_form_link_base;
                 v_form_link_suffix := 0;
                 LOOP
                     -- Serialize automatic allocation for each candidate, including
                     -- candidates that are another occasion's unsuffixed slug.
                     PERFORM pg_advisory_xact_lock(hashtextextended('default-form:' || v_form_link, 0));
                     EXIT WHEN NOT EXISTS (SELECT 1 FROM public.forms WHERE link = v_form_link);
                     v_form_link_suffix := v_form_link_suffix + 1;
                     v_form_link := v_form_link_base || '-' || occ_id::text ||
                         CASE WHEN v_form_link_suffix = 1 THEN '' ELSE '-' || v_form_link_suffix::text END;
                 END LOOP;
             END IF;
             -- Explicit links still use create_form's collision validation.
             PERFORM create_form(occ_id, v_form_link, 'Registration');
         END IF;

         -- Check if reminders are enabled within the form feature
         IF (v_form_settings->>'reminder_is_enabled')::boolean IS TRUE THEN
             -- Get the reminder interval, defaulting to 1 day (86400 seconds) if not specified
             v_reminder_interval_seconds := COALESCE(
                 (v_form_settings->>'reminder_interval_seconds')::bigint,
                 86400
             );
             -- Call the function to queue payment reminders for all relevant orders

         END IF;
     END IF;

     -- Revalidate in-flight reminders after every relevant occasion update.
     PERFORM public.queue_payment_reminders(occ_id,coalesce(v_reminder_interval_seconds,86400));
     IF updated_occ.is_order_synchronization_enabled THEN
       FOR v_email_order IN SELECT id FROM eshop.orders WHERE occasion=occ_id AND state='paid' LOOP
         PERFORM public.enqueue_paid_order_tickets(v_email_order.id);
       END LOOP;
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
