-- Runtime uses only portable layout and normalized bindings; legacy columns are migration archives.
BEGIN;
CREATE OR REPLACE FUNCTION public.update_blueprint_client_sync_v1(
  p_blueprint jsonb,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_blueprint bigint;
  v_begin jsonb; v_hash text; v_users uuid[]; v_result jsonb; v_reason text; v_detail text; v_issue jsonb;
BEGIN
  IF p_blueprint IS NULL OR jsonb_typeof(p_blueprint)<>'object'
    OR octet_length(p_blueprint::text)>8388608 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid blueprint aggregate'; END IF;
  v_occasion:=NULLIF(p_blueprint->>'occasion','')::bigint;
  v_blueprint:=NULLIF(p_blueprint->>'id','')::bigint;
  IF v_blueprint IS NOT NULL THEN SELECT occasion INTO v_occasion FROM eshop.blueprints WHERE id=v_blueprint; END IF;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR (coalesce(public.get_is_editor_on_occasion(v_occasion),false) OR coalesce(public.get_is_manager_on_occasion(v_occasion),false)) IS NOT TRUE
    OR (v_blueprint IS NOT NULL AND NOT EXISTS (SELECT 1 FROM eshop.blueprints b
      WHERE b.id=v_blueprint AND b.occasion=v_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE='blueprint editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',v_occasion,'blueprint',p_blueprint)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.blueprint.save',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM public.lock_blueprint_scope_internal(ARRAY[v_occasion]);
  SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_users
  FROM public.occasion_users ou JOIN eshop.order_product_ticket opt
    ON opt.ticket=ou.ticket JOIN eshop.spots s
    ON s.order_product_ticket=opt.id
  WHERE ou.occasion=v_occasion AND s.occasion=v_occasion;
  BEGIN
    IF p_blueprint->'layout' IS NULL OR p_blueprint->'layout'='null'::jsonb THEN RAISE check_violation USING MESSAGE='BLUEPRINT_LAYOUT_REQUIRED'; END IF;
    v_result:=public.save_blueprint_layout_internal_v1(p_blueprint);
  EXCEPTION WHEN check_violation OR raise_exception OR invalid_text_representation OR not_null_violation OR unique_violation OR foreign_key_violation THEN
    GET STACKED DIAGNOSTICS v_reason=MESSAGE_TEXT,v_detail=PG_EXCEPTION_DETAIL;
    v_issue:=jsonb_build_object('reason',v_reason);
    IF left(coalesce(v_detail,''),1)='{' THEN
      BEGIN v_issue:=v_issue||jsonb_strip_nulls(jsonb_build_object('nodeId',(v_detail::jsonb)->'nodeId','spotId',(v_detail::jsonb)->'spotId','groupNodeId',(v_detail::jsonb)->'groupNodeId'));
      EXCEPTION WHEN invalid_text_representation THEN NULL; END;
    END IF;
    v_result:=jsonb_build_object('code',409,'reason',CASE WHEN SQLSTATE IN ('23514','P0001') THEN v_reason ELSE 'BLUEPRINT_INVALID_INPUT' END,
      'issues',jsonb_build_array(v_issue),
      'layout_revision',(SELECT layout_revision FROM eshop.blueprints WHERE id=v_blueprint));
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,v_result);
  END;
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.blueprint.save',jsonb_build_array(jsonb_build_object(
      'entityType','blueprint','entityId',v_result->>'blueprint_id',
      'operation',CASE WHEN v_blueprint IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(p_blueprint->>'title',240),'changedFields',jsonb_build_array(
        'layout','bindings'))),v_users,v_result);
END; $$;
REVOKE ALL ON FUNCTION public.update_blueprint_client_sync_v1(jsonb,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_blueprint_client_sync_v1(jsonb,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION get_blueprint(
    my_secret UUID,
    form_key UUID,
    blueprint_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    blueprintData JSONB;
    spotsData JSONB;
    productsData JSONB;
    valid_spots JSONB;
    form_bundle JSONB;
BEGIN
    -- Validate the form and blueprint association
    IF NOT EXISTS (
        SELECT 1
        FROM public.forms f
        WHERE f.key = form_key
          AND (NOT public.is_demo_occasion(f.occasion) OR public.can_read_demo_occasion(f.occasion))
          AND (f.is_open = true OR public.get_is_editor_order_view_on_occasion(f.occasion))
          AND EXISTS (
              SELECT 1
              FROM eshop.blueprints b
              WHERE b.id = blueprint_id
                AND f.blueprint = blueprint_id
          )
    ) THEN
        RETURN jsonb_build_object(
            'code', 400,
            'message', 'Invalid form key or blueprint association.'
        );
    END IF;

    IF EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=blueprint_id AND layout IS NULL) THEN
      RETURN jsonb_build_object('code',409,'reason','BLUEPRINT_LAYOUT_MIGRATION_REQUIRED');
    END IF;

    -- Fetch blueprint details
    SELECT jsonb_build_object(
        'id', b.id,
        'occasion', b.occasion,
        'created_at', b.created_at,
        'data', b.data,
        'title', b.title,
        'layout', b.layout, 'layout_revision', b.layout_revision,
        'layoutResources', public.blueprint_layout_resources_internal(b.layout,b.occasion)
    )
    INTO blueprintData
    FROM eshop.blueprints b
    WHERE b.id = blueprint_id;

    -- Every runtime spot belongs to a canonical node binding.
    SELECT coalesce(jsonb_agg(spot),'[]'::jsonb) INTO valid_spots
      FROM eshop.blueprint_seat_bindings WHERE blueprint=blueprint_id;

    -- Fetch enriched spots data
    SELECT jsonb_agg(jsonb_build_object(
        'id', s.id,
        'title', s.title,
        'product', s.product,
        'state', CASE
            WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
            WHEN s.secret IS NOT NULL AND s.secret_expiration_time > now() THEN
                CASE
                    WHEN s.secret = my_secret THEN 'selected_by_me'
                    ELSE 'selected'
                END
            ELSE 'available'
        END
    ))
    INTO spotsData
    FROM eshop.spots s
    WHERE s.id = ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
      AND s.occasion = (
        SELECT occasion FROM public.forms WHERE key = form_key
      );

    -- Reuse the form's public catalog projection, including current wave-applied
    -- price, visible offers, product maximum and inventory availability.
    form_bundle:=public.get_form_bundle_internal((SELECT id FROM public.forms WHERE key=form_key),true)::jsonb;
    SELECT coalesce(jsonb_agg(product||jsonb_build_object('isAvailable',
        coalesce((product->>'is_dynamically_available')::boolean,true) AND
        (coalesce((product->>'maximum')::bigint,0)<=0 OR
         coalesce((product->>'ordered_count')::bigint,0)<(product->>'maximum')::bigint))),'[]')
    INTO productsData
    FROM (SELECT DISTINCT ON (offered_product.value->>'id') offered_product.value AS product
      FROM jsonb_array_elements(coalesce(form_bundle#>'{data,fields}','[]')) field
      CROSS JOIN LATERAL jsonb_array_elements(coalesce(field#>'{product_type_data,products}','[]')) AS offered_product(value)
      WHERE (field->>'is_ticket_field')::boolean AND field->>'type'='product_type'
        AND (offered_product.value->>'id')::bigint IN (
          SELECT s.product FROM eshop.spots s WHERE s.id=ANY(SELECT jsonb_array_elements_text(valid_spots)::bigint)
          UNION SELECT ab.product FROM eshop.blueprint_area_bindings ab WHERE ab.blueprint=blueprint_id)
      ORDER BY offered_product.value->>'id') offered;

    -- Add spots data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{spots}',
        COALESCE(spotsData, '[]'::jsonb)
    );

    -- Add products data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{products}',
        COALESCE(productsData, '[]'::jsonb)
    );

    blueprintData:=blueprintData||public.blueprint_public_binding_projection_internal(blueprint_id,my_secret);

    blueprintData:=blueprintData||jsonb_build_object('areaAvailability',public.blueprint_area_availability_internal(blueprint_id,(SELECT id FROM public.forms WHERE key=form_key)));

    -- Return combined data
    RETURN jsonb_build_object(
        'code', 200,
        'data', blueprintData
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_blueprint_for_edit(
    occasion_link TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    blueprint_id BIGINT;
    blueprintData JSONB;
    spotsData JSONB;
    productsData JSONB;
    ticketsData JSONB;
    ordersData JSONB;
    orderProductTicketsData JSONB;
    valid_spots JSONB;
    occasion_id BIGINT;
BEGIN
    -- Resolve occasion_id using occasion_link
    SELECT id
    INTO occasion_id
    FROM public.occasions
    WHERE id = public.resolve_occasion_link_internal(occasion_link);

    -- Check if occasion_link is valid
    IF occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Occasion link does not exist');
    END IF;

    -- Authorization check
    IF (SELECT get_is_editor_order_view_on_occasion(occasion_id)) <> TRUE THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to edit this occasion');
    END IF;

    -- Fetch the first blueprint_id for the occasion
    SELECT id
    INTO blueprint_id
    FROM eshop.blueprints
    WHERE occasion = occasion_id
    ORDER BY id
    LIMIT 1;

    -- Check if a blueprint exists for the occasion
    IF blueprint_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'No blueprint found for this occasion');
    END IF;

    IF EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=blueprint_id AND layout IS NULL) THEN
      RETURN jsonb_build_object('code',409,'reason','BLUEPRINT_LAYOUT_MIGRATION_REQUIRED');
    END IF;

    -- Fetch blueprint details
    SELECT jsonb_build_object(
        'id', b.id,
        'created_at', b.created_at,
        'data', b.data,
        'title', b.title,
        'occasion', b.occasion,
        'organization', b.organization,
        'layout', b.layout, 'layout_revision', b.layout_revision,
        'layoutResources', public.blueprint_layout_resources_internal(b.layout,b.occasion)
    )
    INTO blueprintData
    FROM eshop.blueprints b
    WHERE b.id = blueprint_id;

    -- Every runtime spot belongs to a canonical node binding.
    SELECT coalesce(jsonb_agg(spot),'[]'::jsonb) INTO valid_spots
      FROM eshop.blueprint_seat_bindings WHERE blueprint=blueprint_id;

    -- Fetch enriched spots data
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', s.id,
        'title', s.title,
        'product', s.product,
        'order_product_ticket', s.order_product_ticket,
        'state', CASE
          WHEN t.state = 'used' THEN 'used'
          WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
          WHEN s.secret IS NOT NULL AND s.secret_expiration_time > now() THEN 'selected'
          ELSE 'available'
        END
      )
    )
    INTO spotsData
    FROM eshop.spots s
    LEFT JOIN eshop.order_product_ticket opt ON s.order_product_ticket = opt.id
    LEFT JOIN eshop.tickets t ON opt.ticket = t.id
    WHERE s.id = ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
      AND s.occasion = occasion_id;

    -- Fetch all products of type "spot", "taxi", "food"
    SELECT jsonb_agg(jsonb_build_object(
        'id', p.id,
        'title', p.title,
        'price', p.price,
        'type', pt.type,
        'description', pt.description,
        'product_type', p.product_type,
        'currency_code', p.currency_code
    ))
    INTO productsData
    FROM eshop.products p
    JOIN eshop.product_types pt ON pt.id = p.product_type
    WHERE pt.occasion = occasion_id;

    -- Fetch relevant tickets associated with the order_product_ticket in spots
    SELECT jsonb_agg(jsonb_build_object(
        'id', t.id,
        'ticket_symbol', t.ticket_symbol,
        'state', t.state,
        'note', t.note,
        'note_hidden', t.note_hidden
    ))
    INTO ticketsData
    FROM eshop.tickets t
    JOIN eshop.order_product_ticket opt ON opt.ticket = t.id
    JOIN eshop.spots s ON s.order_product_ticket = opt.id
    WHERE s.id = ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
      AND t.occasion = occasion_id;

    -- Fetch relevant orders associated with the order_product_ticket in spots
    SELECT jsonb_agg(jsonb_build_object(
        'id', o.id,
        'order_symbol', o.order_symbol,
        'order_sequence', o.order_sequence,
        'created_at', o.created_at,
        'updated_at', o.updated_at,
        'price', o.price,
        'state', o.state,
        'currency_code', o.currency_code,
        'data', jsonb_build_object('name', o.data->>'name', 'surname', o.data->>'surname', 'email', o.data->>'email', 'note', o.data->>'note', 'note_hidden', coalesce(o.note_hidden,o.data->>'note_hidden'))
    ))
    INTO ordersData
    FROM eshop.orders o
    JOIN eshop.order_product_ticket opt ON opt."order" = o.id
    JOIN eshop.spots s ON s.order_product_ticket = opt.id
    WHERE s.id = ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
      AND o.occasion = occasion_id;

    -- Extract order IDs from ordersData JSONB
    WITH order_ids AS (
        SELECT (order_obj->>'id')::BIGINT AS id
        FROM jsonb_array_elements(ordersData) order_obj
    )
    -- Fetch relevant order-product-ticket data based on extracted order IDs
    SELECT jsonb_agg(jsonb_build_object(
            'id', opt.id,
            'order', opt."order",
            'product', opt.product,
            'ticket', opt.ticket,
            'created_at', opt.created_at
        ))
    INTO orderProductTicketsData
    FROM eshop.order_product_ticket opt
    WHERE opt."order" IN (SELECT id FROM order_ids);

    -- Add spots data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{spots}',
        COALESCE(spotsData, '[]'::jsonb)
    );

    -- Add products data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{products}',
        COALESCE(productsData, '[]'::jsonb)
    );

    -- Add relevant tickets data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{tickets}',
        COALESCE(ticketsData, '[]'::jsonb)
    );

    -- Add relevant orders data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{orders}',
        COALESCE(ordersData, '[]'::jsonb)
    );

    -- Add relevant order-product-ticket data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{order_product_ticket}',
        COALESCE(orderProductTicketsData, '[]'::jsonb)
    );

    blueprintData:=blueprintData||public.blueprint_binding_projection_internal(blueprint_id);

    blueprintData:=blueprintData||jsonb_build_object('areaAvailability',public.blueprint_area_availability_internal(blueprint_id,NULL));

    -- Return combined data
    RETURN jsonb_build_object(
        'code', 200,
        'data', blueprintData
    );
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
     v_form_link TEXT;
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
         PERFORM public.check_occasion_writable(occ_id);
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

         IF (input_data ? 'organization' AND (input_data->>'organization')::bigint IS DISTINCT FROM v_org_id)
           OR NOT EXISTS(SELECT 1 FROM public.units WHERE id=final_unit AND organization=v_org_id) THEN
           RAISE insufficient_privilege USING MESSAGE='Occasion tenant cannot change'; END IF;

         UPDATE public.occasions
            SET updated_at  = now,
                title       = COALESCE(input_data->>'title', title),
                description = COALESCE(input_data->>'description', description),
                link        = public.reserve_public_link_internal('occasion',occ_id,input_data->>'link',false),
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
             '',
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
         UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',occ_id,input_data->>'link',true) WHERE id=occ_id RETURNING * INTO updated_occ;
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
             INSERT INTO eshop.blueprints(occasion, organization, created_at, updated_at,layout)
             VALUES (occ_id, COALESCE(updated_occ.organization, 1), now, now,
              '{"schemaVersion":1,"symbolSetVersion":1,"canvas":{"x":0,"y":0,"width":1120,"height":2080,"fill":"#ffffffff"},"defaultTextStyle":{"fontId":"builtin:roboto-unpacked:24438383f80387edbbd3a199d7b257258db7003f5b291a7d3fb6fa89483ae57f","size":24,"color":"#222222FF"},"nodes":[]}'::jsonb)
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
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_occasion bigint; v_version bigint; v_response jsonb;
BEGIN
  v_occasion:=NULLIF(input_data->>'id','')::bigint;
  IF v_occasion IS NULL THEN
    PERFORM public.create_occasion_client_sync_v1(
      extensions.gen_random_uuid(),input_data);
    RETURN;
  END IF;
  SELECT COALESCE(v.version,0) INTO v_version
    FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
      ON v.aggregate_type='occasion' AND v.scope_type='occasion'
      AND v.scope_id=v_occasion AND v.aggregate_id=v_occasion::text;
  v_response:=public.save_occasion_client_sync_v1(v_occasion,
    extensions.gen_random_uuid(),v_version,input_data);
  IF v_response->>'status'='conflict' THEN
    RAISE serialization_failure USING MESSAGE='Occasion changed; reload before saving';
  ELSIF v_response->>'status' IS DISTINCT FROM 'applied' THEN
    RAISE invalid_parameter_value USING MESSAGE='Occasion save rejected';
  END IF;
END; $$;
REVOKE ALL ON FUNCTION public.update_occasion_203(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_occasion_203(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.duplicate_occasion_internal_v1(oc bigint, p_target_unit bigint, p_locale text)
RETURNS bigint
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  new_occ         bigint;
  rec             record;
  new_info_id     bigint;
  v_new_id        bigint;
  new_place_id    bigint;
  new_event_id    bigint;
  new_bp_id       bigint;
  new_pt_id       bigint;
  new_product_id  bigint;
  new_form_id     bigint;
  v_source_unit bigint;
  v_target_unit bigint;
  v_organization bigint;
  v_demo boolean;
  v_layout_ids jsonb; v_copied_layout jsonb; v_resource_copy jsonb;
BEGIN
  SELECT unit, organization INTO v_source_unit, v_organization
  FROM public.occasions WHERE id = oc;
  v_target_unit := COALESCE(p_target_unit, v_source_unit);
  v_demo := public.is_demo_occasion(oc);
  IF auth.uid() IS NULL OR v_source_unit IS NULL OR v_target_unit IS NULL
     OR NOT public.can_copy_occasion_source(oc)
     OR public.is_demo_unit(v_target_unit)
     OR NOT public.get_is_manager_on_unit(v_target_unit)
     OR NOT EXISTS (SELECT 1 FROM public.units
       WHERE id = v_target_unit AND organization = v_organization) THEN
    RAISE insufficient_privilege USING MESSAGE = 'source and target unit manager required within one organization';
  END IF;

  IF EXISTS(SELECT 1 FROM eshop.blueprints WHERE occasion=oc AND layout IS NULL) THEN
    RAISE check_violation USING MESSAGE='BLUEPRINT_LAYOUT_MIGRATION_REQUIRED';
  END IF;

  ------------------------------------------------------------------
  -- 1. Duplicate the main occasion record.
  --    Modify the link to ensure uniqueness by appending a unique suffix.
  ------------------------------------------------------------------
  INSERT INTO public.occasions
    (created_at, updated_at, data, is_hidden, is_open, is_promoted, start_time, end_time, link, title, organization, services, unit, features, occasion_hidden, description)
  SELECT now(), now(), data, CASE WHEN v_demo THEN true ELSE is_hidden END,
         CASE WHEN v_demo THEN false ELSE is_open END, CASE WHEN v_demo THEN false ELSE is_promoted END, start_time, end_time,
         '' AS link,
         public.copy_occasion_title_internal(title,p_locale), v_organization, services, v_target_unit, features, NULL, description
  FROM public.occasions
  WHERE id = oc
  RETURNING id INTO new_occ;

  UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',new_occ,NULL,true) WHERE id=new_occ;

  ------------------------------------------------------------------
  -- 2. Create temporary mapping tables (old id → new id)
  ------------------------------------------------------------------
  CREATE TEMP TABLE tmp_places (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_events (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_exclusive_groups (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_blueprints (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_blueprint_layout_ids (blueprint bigint,old_id uuid,new_id uuid,PRIMARY KEY(blueprint,old_id)) ON COMMIT DROP;
  PERFORM 1 FROM public.occasions WHERE id=oc FOR UPDATE;
  CREATE TEMP TABLE tmp_product_types (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_products (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_spots (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_inventory_pools (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_inventory_contexts (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_resources (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_resource_slots (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_scanner_fields (old_id bigint,new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_forms (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_information_hidden (old_id bigint, new_id bigint) ON COMMIT DROP;

  ------------------------------------------------------------------
  -- 3. Duplicate tables that reference the occasion directly
  ------------------------------------------------------------------

  -- 3a. Email Templates
  INSERT INTO public.email_templates (html, occasion, unit, subject, organization, code, title)
  SELECT DISTINCT ON (code) html, new_occ, v_target_unit, subject, v_organization, code, title
  FROM public.email_templates
  WHERE occasion = oc
  ORDER BY code, (unit IS NOT DISTINCT FROM v_source_unit) DESC,
    (organization IS NOT DISTINCT FROM v_organization) DESC, id DESC;

  -- 3b. Duplicate information_hidden rows using a loop and record mapping.
  FOR rec IN
    SELECT id, data
    FROM public.information_hidden
    WHERE occasion = oc AND NOT v_demo
  LOOP
    INSERT INTO public.information_hidden (created_at, data, occasion)
    VALUES (now(), rec.data, new_occ)
    RETURNING id INTO new_info_id;

    INSERT INTO tmp_information_hidden (old_id, new_id)
    VALUES (rec.id, new_info_id);
  END LOOP;

  -- 3c. Information – update its foreign key to information_hidden using the mapping.
  INSERT INTO public.information
    (created_at, title, description, is_hidden, "order", updated_at, type, occasion, data, information_hidden, unit)
  SELECT now(), title, description, is_hidden, "order", now(), type, new_occ, data,
         CASE WHEN information_hidden IS NOT NULL
              THEN (SELECT tih.new_id FROM tmp_information_hidden AS tih WHERE tih.old_id = information_hidden)
              ELSE NULL END,
         v_target_unit
  FROM public.information
  WHERE occasion = oc;

  -- 3d. Role Info
  INSERT INTO public.role_info (title, occasion)
  SELECT title, new_occ
  FROM public.role_info
  WHERE occasion = oc;

  ------------------------------------------------------------------
  -- 4. Duplicate tables with additional foreign keys (using loops)
  ------------------------------------------------------------------

  -- 4a. Places
  FOR rec IN
    SELECT id, title, description, type, created_at, coordinates, is_hidden, "order", icon, unit
    FROM public.places
    WHERE occasion = oc
  LOOP
    INSERT INTO public.places
      (title, description, type, created_at, coordinates, is_hidden, updated_at, occasion, "order", icon, unit)
    VALUES (rec.title, rec.description, rec.type, rec.created_at, rec.coordinates, rec.is_hidden, now(), new_occ, rec."order", rec.icon, v_target_unit)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_places (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 4b. Exclusive Groups
  FOR rec IN
    SELECT id, title
    FROM public.exclusive_groups
    WHERE occasion = oc
  LOOP
    INSERT INTO public.exclusive_groups (title, occasion)
    VALUES (rec.title, new_occ)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_exclusive_groups (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 4c. Events – adjust the "place" foreign key using tmp_places.
  FOR rec IN
    SELECT id, title, start_time, end_time, max_participants, description, place, split_for_men_women, is_group_event, is_hidden, type
    FROM public.events
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_place_id
      FROM tmp_places AS t
      WHERE t.old_id = rec.place;

    INSERT INTO public.events
      (created_at, title, start_time, end_time, max_participants, description, place, split_for_men_women, is_group_event, updated_at, is_hidden, occasion, type)
    VALUES (now(), rec.title, rec.start_time, rec.end_time, rec.max_participants, rec.description,
            COALESCE(new_place_id, rec.place), rec.split_for_men_women, rec.is_group_event, now(), rec.is_hidden, new_occ, rec.type)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_events (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 4d. Event Groups – update both parent and child using the event mapping.
  INSERT INTO public.event_groups (event_parent, event_child)
  SELECT
    (SELECT te.new_id FROM tmp_events AS te WHERE te.old_id = eg.event_parent),
    (SELECT te.new_id FROM tmp_events AS te WHERE te.old_id = eg.event_child)
  FROM public.event_groups eg
  WHERE eg.event_parent IN (SELECT old_id FROM tmp_events)
    AND eg.event_child IN (SELECT old_id FROM tmp_events);

  -- 4e. Event Roles – update event using mapping.
  INSERT INTO public.event_roles (event, role)
  SELECT (SELECT te.new_id FROM tmp_events AS te WHERE te.old_id = er.event), er.role
  FROM public.event_roles er
  WHERE er.event IN (SELECT old_id FROM tmp_events);

  -- 4f. Exclusive Events – update both event and group using mappings.
  INSERT INTO public.exclusive_events (event, "group")
  SELECT
    (SELECT te.new_id FROM tmp_events AS te WHERE te.old_id = ee.event),
    (SELECT teg.new_id FROM tmp_exclusive_groups AS teg WHERE teg.old_id = ee."group")
  FROM public.exclusive_events ee
  WHERE ee.event IN (SELECT old_id FROM tmp_events)
    AND ee."group" IN (SELECT old_id FROM tmp_exclusive_groups);

  ------------------------------------------------------------------
  -- 5. Duplicate ESHOP tables (using loops)
  ------------------------------------------------------------------

  -- 5a. Blueprints
  FOR rec IN
    SELECT id, data, title, organization, layout
    FROM eshop.blueprints
    WHERE occasion = oc
  LOOP
    PERFORM public.copy_blueprint_image_resources_internal(oc,new_occ,rec.layout);
    v_layout_ids:='{}';v_copied_layout:=rec.layout;
    IF rec.layout IS NOT NULL THEN
      -- Collect every declared record UUID, including nested preset documents.
      WITH RECURSIVE records(value) AS (
        SELECT rec.layout UNION ALL SELECT child.value FROM records CROSS JOIN LATERAL (
          SELECT item.value FROM jsonb_each(CASE WHEN jsonb_typeof(records.value)='object' THEN records.value ELSE '{}'::jsonb END) item
          UNION ALL SELECT item.value FROM jsonb_array_elements(CASE WHEN jsonb_typeof(records.value)='array' THEN records.value ELSE '[]'::jsonb END) item
        ) child
      )
      INSERT INTO tmp_blueprint_layout_ids(blueprint,old_id,new_id)
      SELECT rec.id,(value->>'id')::uuid,extensions.gen_random_uuid() FROM records WHERE jsonb_typeof(value)='object' AND value ? 'id'
      ON CONFLICT(blueprint,old_id) DO NOTHING;
      SELECT coalesce(jsonb_object_agg(old_id::text,new_id),'{}') INTO v_layout_ids FROM tmp_blueprint_layout_ids WHERE blueprint=rec.id;
      v_copied_layout:=public.remap_blueprint_layout_ids_internal(rec.layout,v_layout_ids);
      PERFORM public.validate_blueprint_layout_internal(v_copied_layout);
      PERFORM public.check_blueprint_image_resource_internal(v_copied_layout,new_occ);
    END IF;
    INSERT INTO eshop.blueprints
      (created_at, data, title, organization, occasion, updated_at,layout,layout_revision)
    VALUES (now(), rec.data, rec.title, v_organization, new_occ, now(),v_copied_layout,0)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_blueprints (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 5b. Product Types
  FOR rec IN
    SELECT id, title, description, type, data
    FROM eshop.product_types
    WHERE occasion = oc
  LOOP
    INSERT INTO eshop.product_types
      (created_at, updated_at, title, description, type, data, occasion)
    VALUES (now(), now(), rec.title, rec.description, rec.type, rec.data, new_occ)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_product_types (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 5c. Products – adjust product_type via mapping.
  FOR rec IN
    SELECT id, title, description, price, data, product_type, is_hidden, currency_code, "order", maximum
    FROM eshop.products
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_pt_id
      FROM tmp_product_types AS t
      WHERE t.old_id = rec.product_type;

    INSERT INTO eshop.products
      (created_at, updated_at, title, description, price, data, product_type, occasion, is_hidden, currency_code, "order", maximum)
    VALUES (now(), now(), rec.title, rec.description, rec.price, rec.data,
            COALESCE(new_pt_id, rec.product_type), new_occ, rec.is_hidden, rec.currency_code, rec."order", rec.maximum)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_products (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- Inventory configuration is copied, never its allocations or reservations.
  FOR rec IN SELECT * FROM public.inventory_pools WHERE occasion=oc LOOP
    INSERT INTO public.inventory_pools(title,description,type,data,sellable_capacity,occasion)
    VALUES(rec.title,rec.description,rec.type,rec.data,rec.sellable_capacity,new_occ)
    RETURNING id INTO v_new_id;
    INSERT INTO tmp_inventory_pools VALUES(rec.id,v_new_id);
  END LOOP;
  FOR rec IN SELECT c.* FROM public.inventory_contexts c
    JOIN tmp_inventory_pools m ON m.old_id=c.inventory_pool LOOP
    INSERT INTO public.inventory_contexts(inventory_pool,block_date,title,"order",data)
    VALUES((SELECT new_id FROM tmp_inventory_pools WHERE old_id=rec.inventory_pool),
      rec.block_date,rec.title,rec."order",rec.data) RETURNING id INTO v_new_id;
    INSERT INTO tmp_inventory_contexts VALUES(rec.id,v_new_id);
  END LOOP;
  FOR rec IN SELECT r.* FROM public.resources r
    JOIN tmp_inventory_pools m ON m.old_id=r.inventory_pool LOOP
    v_resource_copy:=public.copy_inventory_resource_configuration_internal(rec.id,
      (SELECT new_id FROM tmp_inventory_pools WHERE old_id=rec.inventory_pool),
      (SELECT new_id FROM tmp_places WHERE old_id=rec.place));
    INSERT INTO tmp_resources VALUES(rec.id,(v_resource_copy->>'resourceId')::bigint);
    INSERT INTO tmp_resource_slots(old_id,new_id)
      SELECT key::bigint,value::text::bigint FROM jsonb_each(v_resource_copy->'slotMap');
  END LOOP;
  INSERT INTO eshop.product_inventory_contexts(product,inventory_context,quantity)
    SELECT p.new_id,c.new_id,x.quantity FROM eshop.product_inventory_contexts x
    JOIN tmp_products p ON p.old_id=x.product
    JOIN tmp_inventory_contexts c ON c.old_id=x.inventory_context;

  -- 5d. Spots – adjust foreign keys for product and blueprint.
  FOR rec IN
    SELECT id, product, secret, secret_expiration_time, title, order_product_ticket, blueprint, inventory_context, resource, resource_slot
    FROM eshop.spots
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_product_id
      FROM tmp_products AS t
      WHERE t.old_id = rec.product;

    SELECT t.new_id INTO new_bp_id
      FROM tmp_blueprints AS t
      WHERE t.old_id = rec.blueprint;

    v_new_id:=public.copy_empty_inventory_spot_internal(rec.id,new_occ,COALESCE(new_product_id, rec.product),COALESCE(new_bp_id, rec.blueprint),
      (SELECT new_id FROM tmp_inventory_contexts WHERE old_id=rec.inventory_context),
      (SELECT new_id FROM tmp_resources WHERE old_id=rec.resource),
      (SELECT new_id FROM tmp_resource_slots WHERE old_id=rec.resource_slot));

    INSERT INTO tmp_spots (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  ------------------------------------------------------------------
  -- Copied geometry and commercial state share the same new UUID mapping.
  -- Holds/orders are deliberately absent and numeric spots/products remap too.
  INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot,selection_unit,group_node,blocked)
  SELECT bp.new_id,node_map.new_id,sp.new_id,unit_map.new_id,group_map.new_id,sb.blocked
  FROM eshop.blueprint_seat_bindings sb JOIN tmp_blueprints bp ON bp.old_id=sb.blueprint JOIN tmp_spots sp ON sp.old_id=sb.spot
  JOIN tmp_blueprint_layout_ids node_map ON node_map.blueprint=sb.blueprint AND node_map.old_id=sb.node_id
  LEFT JOIN tmp_blueprint_layout_ids unit_map ON unit_map.blueprint=sb.blueprint AND unit_map.old_id=sb.selection_unit
  LEFT JOIN tmp_blueprint_layout_ids group_map ON group_map.blueprint=sb.blueprint AND group_map.old_id=sb.group_node;
  INSERT INTO eshop.blueprint_group_products(blueprint,group_node,product)
  SELECT bp.new_id,node_map.new_id,p.new_id FROM eshop.blueprint_group_products gp
  JOIN tmp_blueprints bp ON bp.old_id=gp.blueprint JOIN tmp_products p ON p.old_id=gp.product
  JOIN tmp_blueprint_layout_ids node_map ON node_map.blueprint=gp.blueprint AND node_map.old_id=gp.group_node;
  INSERT INTO eshop.blueprint_area_bindings(blueprint,node_id,inventory_context,product)
  SELECT bp.new_id,node_map.new_id,c.new_id,p.new_id FROM eshop.blueprint_area_bindings ab JOIN tmp_blueprints bp ON bp.old_id=ab.blueprint
  JOIN tmp_inventory_contexts c ON c.old_id=ab.inventory_context JOIN tmp_products p ON p.old_id=ab.product
  JOIN tmp_blueprint_layout_ids node_map ON node_map.blueprint=ab.blueprint AND node_map.old_id=ab.node_id;

  -- 7. Duplicate Forms and Form Fields
  ------------------------------------------------------------------

  -- 7a. Forms – adjust the blueprint foreign key via mapping and update the link to be unique.
  FOR rec IN
    SELECT id, data, key, type, bank_account, deadline_duration_seconds, is_open, link, blueprint, header, header_off, title, participant_capacity, waitlist_enabled, show_remaining_capacity, waitlist_offer_duration_seconds
    FROM public.forms
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_bp_id
      FROM tmp_blueprints AS t
      WHERE t.old_id = rec.blueprint;

    INSERT INTO public.forms
      (created_at, data, key, occasion, type, bank_account, deadline_duration_seconds, is_open, link, blueprint, header, header_off, updated_at, title, participant_capacity, waitlist_enabled, show_remaining_capacity, waitlist_offer_duration_seconds)
    VALUES (now(), rec.data, uuid_generate_v4(), new_occ, rec.type,
            CASE WHEN v_demo THEN NULL WHEN v_source_unit = v_target_unit OR EXISTS (
              SELECT 1 FROM eshop.unit_bank_accounts uba
              WHERE uba.unit = v_target_unit AND uba.bank_account = rec.bank_account)
              THEN rec.bank_account ELSE NULL END,
            rec.deadline_duration_seconds,
            CASE WHEN v_demo THEN false WHEN v_source_unit <> v_target_unit AND rec.bank_account IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM eshop.unit_bank_accounts uba
                WHERE uba.unit = v_target_unit AND uba.bank_account = rec.bank_account)
              THEN false ELSE rec.is_open END,
            NULL,
            COALESCE(new_bp_id, rec.blueprint), rec.header, rec.header_off, now(), rec.title, rec.participant_capacity, rec.waitlist_enabled, rec.show_remaining_capacity, rec.waitlist_offer_duration_seconds)
    RETURNING id INTO v_new_id;

    UPDATE public.forms SET link=public.reserve_public_link_internal('form',v_new_id,NULL,true) WHERE id=v_new_id;

    INSERT INTO tmp_forms (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 7b. Form Fields – update the "form" foreign key and product_type via mapping tables.
  FOR rec IN SELECT * FROM public.form_fields WHERE form IN (SELECT old_id FROM tmp_forms) LOOP
    INSERT INTO public.form_fields(created_at,title,description,data,type,is_required,form,is_hidden,"order",product_type,is_ticket_field)
    VALUES(now(),rec.title,rec.description,rec.data,rec.type,rec.is_required,
      (SELECT new_id FROM tmp_forms WHERE old_id=rec.form),rec.is_hidden,rec."order",
      (SELECT new_id FROM tmp_product_types WHERE old_id=rec.product_type),rec.is_ticket_field) RETURNING id INTO v_new_id;
    INSERT INTO tmp_scanner_fields VALUES(rec.id,v_new_id);
  END LOOP;
  INSERT INTO public.scanner_settings(occasion_id,config)
  SELECT new_occ,jsonb_set(jsonb_set(config,'{products}',jsonb_build_object('mode',config#>>'{products,mode}',
    'ids',coalesce((SELECT jsonb_agg(m.new_id ORDER BY n) FROM jsonb_array_elements(config#>'{products,ids}') WITH ORDINALITY x(p,n) JOIN tmp_products m ON m.old_id=p::text::bigint),'[]'::jsonb),
    'order',coalesce((SELECT jsonb_agg(m.new_id ORDER BY n) FROM jsonb_array_elements(config#>'{products,order}') WITH ORDINALITY x(p,n) JOIN tmp_products m ON m.old_id=p::text::bigint),'[]'::jsonb))),
    '{fields}',coalesce((SELECT jsonb_agg(CASE WHEN f->>'source'='builtin' THEN f ELSE
      f||jsonb_build_object('form_id',fm.new_id,'field_id',ff.new_id,'key',(CASE WHEN f->>'source'='ticket_field' THEN 'ticket' ELSE 'order' END)||':'||fm.new_id||':'||ff.new_id) END ORDER BY n)
      FROM jsonb_array_elements(config->'fields') WITH ORDINALITY x(f,n)
      LEFT JOIN tmp_forms fm ON fm.old_id=(f->>'form_id')::bigint LEFT JOIN tmp_scanner_fields ff ON ff.old_id=(f->>'field_id')::bigint
      WHERE f->>'source'='builtin' OR (fm.new_id IS NOT NULL AND ff.new_id IS NOT NULL)),'[]'::jsonb))
  FROM public.scanner_settings WHERE occasion_id=oc;


  ------------------------------------------------------------------
  -- 8. Return the new occasion id
  ------------------------------------------------------------------
  -- References are remapped only after the complete type map exists.
  UPDATE public.occasions o SET features=(SELECT jsonb_agg(CASE WHEN f->>'code'='ticket' AND f ? 'layout'
    THEN jsonb_set(f,'{layout,templates}',(SELECT jsonb_object_agg(t.key,jsonb_set(t.value,'{elements}',
      (SELECT jsonb_agg(CASE WHEN e->>'binding'='productType' THEN jsonb_set(e,'{productTypeId}',
        to_jsonb((SELECT m.new_id FROM tmp_product_types m WHERE m.old_id=(e->>'productTypeId')::bigint))) ELSE e END ORDER BY n)
       FROM jsonb_array_elements(t.value->'elements') WITH ORDINALITY x(e,n)))) FROM jsonb_each(f->'layout'->'templates') t)) ELSE f END ORDER BY n)
    FROM jsonb_array_elements(o.features) WITH ORDINALITY x(f,n)) WHERE o.id=new_occ;
  PERFORM public.validate_ticket_layout_references(new_occ,f->'layout') FROM public.occasions o CROSS JOIN LATERAL jsonb_array_elements(o.features) f WHERE o.id=new_occ AND f->>'code'='ticket' AND f ? 'layout';
  DROP TABLE tmp_places, tmp_events, tmp_exclusive_groups, tmp_blueprints,tmp_blueprint_layout_ids,
    tmp_product_types, tmp_products, tmp_spots, tmp_forms, tmp_information_hidden,
    tmp_inventory_pools,tmp_inventory_contexts,tmp_resources,tmp_resource_slots,tmp_scanner_fields;
  RETURN new_occ;
END;
$$ LANGUAGE plpgsql;
REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint,bigint)
  FROM PUBLIC, anon, authenticated;

-- Existing internal callers retain same-unit semantics.
CREATE OR REPLACE FUNCTION public.duplicate_occasion_internal_v1(oc bigint)
RETURNS bigint LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT public.duplicate_occasion_internal_v1(oc, NULL);
$$;
REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint)
  FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint,bigint,text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.duplicate_occasion_internal_v1(oc bigint,p_target_unit bigint)
RETURNS bigint LANGUAGE sql SECURITY DEFINER SET search_path = public, extensions AS $$
 SELECT public.duplicate_occasion_internal_v1(oc,p_target_unit,'en');
$$;
REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Configuration only: no responses, orders, customers or reservation secrets.
CREATE OR REPLACE FUNCTION public.get_occasion_setup_sources(p_unit bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(p_unit) OR public.get_is_manager_on_unit(p_unit)) THEN
    RAISE EXCEPTION 'Source access denied' USING ERRCODE = '42501';
  END IF;
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object(
    'occasion', jsonb_build_object('id',o.id,'title',o.title,'link',o.link,
      'start_time',o.start_time,'end_time',o.end_time,'description',o.description,
      'data',o.data,'features',o.features,'is_open',false,'is_hidden',true),
    'forms', COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'title',f.title,'link',f.link,'type',f.type,'data',f.data,'header',f.header,
      'header_off',f.header_off,'deadline_duration_seconds',f.deadline_duration_seconds,
      'is_open',false,'blueprint',f.blueprint,
      'fields',COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'title',ff.title,'description',ff.description,'data',ff.data,'type',ff.type,
        'is_required',ff.is_required,'is_hidden',ff.is_hidden,'order',ff."order",
        'is_ticket_field',ff.is_ticket_field,
        'product_type_data',(SELECT jsonb_build_object('id',pt.id,'title',pt.title,
          'description',pt.description,'type',pt.type,'data',pt.data,
          'products',COALESCE((SELECT jsonb_agg(jsonb_build_object(
            'id',p.id,'title',p.title,'description',p.description,'price',p.price,
            'currency_code',p.currency_code,'maximum',p.maximum,'data',p.data,
            'is_hidden',p.is_hidden,'order',p."order") ORDER BY p."order",p.id)
            FROM eshop.products p WHERE p.product_type=pt.id),'[]'::jsonb))
          FROM eshop.product_types pt WHERE pt.id=ff.product_type)) ORDER BY ff."order",ff.id)
        FROM public.form_fields ff WHERE ff.form=f.id),'[]'::jsonb)) ORDER BY f.id)
      FROM public.forms f WHERE f.occasion=o.id),'[]'::jsonb),
    'blueprints',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'blueprintLayoutDraft',CASE WHEN b.layout IS NULL THEN NULL ELSE jsonb_build_object(
        'layout',b.layout,
        'seatBindings',coalesce((SELECT jsonb_agg(jsonb_build_object('nodeId',sb.node_id,'productId',spot.product,'title',spot.title,'groupNodeId',sb.group_node,'selectionUnitId',sb.selection_unit,'blocked',sb.blocked) ORDER BY sb.node_id)
          FROM eshop.blueprint_seat_bindings sb JOIN eshop.spots spot ON spot.id=sb.spot WHERE sb.blueprint=b.id),'[]'),
        'groupProducts',coalesce((SELECT jsonb_agg(jsonb_build_object('groupNodeId',gp.group_node,'productId',gp.product) ORDER BY gp.group_node) FROM eshop.blueprint_group_products gp WHERE gp.blueprint=b.id),'[]'),
        'areaBindings',coalesce((SELECT jsonb_agg(jsonb_build_object('nodeId',ab.node_id,'productId',ab.product,'inventoryContextId',ab.inventory_context) ORDER BY ab.node_id) FROM eshop.blueprint_area_bindings ab WHERE ab.blueprint=b.id),'[]')) END,
      'id',b.id,'title',b.title) ORDER BY b.id)
      FROM eshop.blueprints b WHERE b.occasion=o.id AND b.layout IS NOT NULL),'[]'::jsonb),
    'program',COALESCE((SELECT jsonb_agg(jsonb_build_object('title',e.title,
      'start_time',e.start_time,'end_time',e.end_time,'description',e.description))
      FROM public.events e WHERE e.occasion=o.id),'[]'::jsonb),
    'information',COALESCE((SELECT jsonb_agg(jsonb_build_object('title',i.title,
      'description',i.description,'type',i.type,'data',i.data) ORDER BY i."order",i.id)
      FROM public.information i WHERE i.occasion=o.id),'[]'::jsonb)
    ) ORDER BY o.start_time DESC,o.id DESC) FROM public.occasions o WHERE o.unit=p_unit),'[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_sources(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_sources(bigint) TO authenticated;

-- Materialize the private configuration exactly once. Provisional draft IDs and
-- source product IDs are never accepted as IDs in the new aggregate.
CREATE OR REPLACE FUNCTION public.finalize_occasion_setup_draft(p_id uuid,p_expected_revision bigint,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE policies jsonb; d public.occasion_setup_drafts; payload jsonb; config jsonb; features jsonb := '[]';
 started jsonb; receipt jsonb; new_id bigint; form_id bigint; form_data jsonb; fields jsonb := '[]';
 field jsonb; pt jsonb; products jsonb; product jsonb; result jsonb; source_id bigint;
 old_products jsonb := '[]'; old_types jsonb := '[]'; type_map jsonb := '{}'; final_features jsonb; new_products jsonb; product_map jsonb := '{}'; idx integer; j integer;
 intro_image text; form_link text; selected_bank bigint; bank_fingerprint text; bank_currencies text[]; required_currencies text[]; wave jsonb; target jsonb; saved_wave jsonb; wave_product bigint;
 has_tickets boolean;
 unit_defaults jsonb; communication_new boolean; reply_email text; form_meta jsonb; reminder_days numeric;
 blueprint_id bigint; v_commit public.client_commits%ROWTYPE;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_id FOR UPDATE;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(d.unit) OR public.get_is_manager_on_unit(d.unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 IF d.data ? 'finalizeResponse' THEN RETURN d.data->'finalizeResponse'; END IF;
 started := public.begin_unit_client_mutation_v1(p_command_id,'occasion.setup.finalize',d.unit,auth.uid(),
  encode(extensions.digest(convert_to(jsonb_build_object('draft',p_id,'revision',p_expected_revision)::text,'UTF8'),'sha256'),'hex'));
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 IF d.data ? 'finalizedOccasion' THEN RAISE invalid_parameter_value USING MESSAGE='Draft already finalized'; END IF;
 IF d.revision IS DISTINCT FROM p_expected_revision THEN RAISE serialization_failure USING MESSAGE='Draft changed in another session'; END IF;
 payload := d.data;
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
 IF source_id IS NOT NULL AND (NOT public.can_copy_occasion_source(source_id) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=source_id AND organization=d.organization)) THEN
  RAISE insufficient_privilege USING MESSAGE='Copy source denied'; END IF;
 IF nullif(btrim(payload->>'title'),'') IS NULL OR (payload->>'reviewConfirmed')::boolean IS DISTINCT FROM true THEN
  RAISE invalid_parameter_value USING MESSAGE='Draft review required'; END IF;
 IF (payload->>'end')::timestamptz < (payload->>'start')::timestamptz THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid event dates'; END IF;
 -- Draft uploads use the existing unit-scoped image writer. Never trust an
 -- arbitrary URL supplied by a client, or adopt another unit's image.
 IF intro_image IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.images WHERE link=intro_image AND unit=d.unit) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft image access denied'; END IF;
 IF coalesce((payload->>'isPromoted')::boolean,false) AND intro_image IS NULL THEN
  RAISE invalid_parameter_value USING MESSAGE='Promotion requires an intro image'; END IF;
 -- New setup clients explicitly confirm receiving instructions. Old drafts
 -- without this field retain the existing canonical automatic routing contract.
 SELECT array_agg(DISTINCT coalesce(nullif(p->>'currency_code',''),'CZK')) INTO required_currencies
 FROM jsonb_array_elements(coalesce(payload#>'{formDraft,fields}','[]')) f
 CROSS JOIN LATERAL jsonb_array_elements(coalesce(f#>'{product_type_data,products}','[]')) p
 WHERE coalesce((payload->>'formEnabled')::boolean,true) AND NOT coalesce((f->>'is_hidden')::boolean,false)
   AND NOT coalesce((p->>'is_hidden')::boolean,false) AND (p->>'price')::numeric>0;
 IF required_currencies IS NOT NULL AND payload ? 'bankAccountConfirmed' THEN
  IF (payload->>'bankAccountConfirmed')::boolean IS DISTINCT FROM true OR nullif(payload->>'bankAccountId','') IS NULL THEN
   RAISE invalid_parameter_value USING MESSAGE='Bank account confirmation required'; END IF;
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
   RAISE serialization_failure USING MESSAGE='Bank account details changed; confirm again'; END IF;
 END IF;
 -- Active form choices own enabled features, not whether an editor was visited.
 has_tickets:=coalesce((payload->>'formEnabled')::boolean,true) AND EXISTS(
  SELECT 1 FROM jsonb_array_elements(coalesce(payload#>'{formDraft,fields}','[]')) f
  WHERE f->>'type'='ticket' AND NOT coalesce((f->>'is_hidden')::boolean,false));
 IF has_tickets THEN
  features:=features||jsonb_build_array((coalesce(nullif(payload->'ticketDraft','null'::jsonb),'{}'::jsonb)-'layout')
    ||'{"code":"ticket","is_enabled":true}'::jsonb);
 END IF;
 IF coalesce((payload->>'formEnabled')::boolean,true) AND payload->>'blueprintMode' IN ('Nový','Převzít')
   AND jsonb_array_length(coalesce(payload#>'{blueprintLayoutDraft,seatBindings}','[]'))+
       jsonb_array_length(coalesce(payload#>'{blueprintLayoutDraft,areaBindings}','[]'))=0 THEN
  RAISE invalid_parameter_value USING MESSAGE='Selected blueprint has no places'; END IF;
 IF coalesce((payload->>'formEnabled')::boolean,true) THEN
  features := features || jsonb_build_array(jsonb_build_object('code','form','is_enabled',true) ||
    CASE WHEN communication_new THEN jsonb_build_object(
      'reminder_is_enabled',coalesce((unit_defaults->>'is_reminder_enabled')::boolean,true),
      'reminder_interval_seconds',coalesce((unit_defaults->>'reminder_interval_seconds')::bigint,86400)) ELSE '{}'::jsonb END);
 END IF;
 IF coalesce((payload->>'copyProgram')::boolean,false) THEN features := features || '[{"code":"schedule","is_enabled":true}]'; END IF;
 IF coalesce((payload->>'copyInformation')::boolean,false) THEN features := features || '[{"code":"information","is_enabled":true}]'; END IF;
 config := jsonb_build_object('unit',d.unit,'organization',d.organization,
  'title',payload->>'title','link',payload->>'link','description',coalesce(payload->>'description',''),
  'start_time',payload->>'start','end_time',payload->>'end','is_hidden',true,'is_open',false,
  'is_promoted',coalesce((payload->>'isPromoted')::boolean,false),
  'features',features,'data',jsonb_strip_nulls(jsonb_build_object('client_sync_v1',false,
   'image',intro_image,'place_name',nullif(btrim(payload->>'placeName'),''),'reply_to',reply_email)));
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
  result := public.update_form_internal_v1((form_data-'id'-'fields'-'blueprint'-'bank_account') || jsonb_build_object(
   'id',form_id,'occasion',new_id,'link',coalesce(form_link,(SELECT link FROM public.forms WHERE id=form_id)),
   'is_open',false,'bank_account',selected_bank,'form_fields',fields));
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
  IF coalesce(payload->>'blueprintMode','')<>'Bez plánku' AND
   (payload->>'blueprintMode' IN ('Nový','Převzít') OR
    (payload->'blueprintLayoutDraft' IS NOT NULL AND payload->'blueprintLayoutDraft'<>'null'::jsonb)) THEN
  IF payload->'blueprintLayoutDraft' IS NOT NULL AND payload->'blueprintLayoutDraft'<>'null'::jsonb THEN
   blueprint_id:=public.materialize_setup_blueprint_layout_internal(payload->'blueprintLayoutDraft',product_map,source_id,new_id,d.unit);
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
  INSERT INTO public.events(occasion,title,start_time,end_time,description)
  SELECT new_id,e->>'title',(e->>'start_time')::timestamptz,(e->>'end_time')::timestamptz,e->>'description'
  FROM jsonb_array_elements(coalesce(payload->'sourceProgram','[]')) e;
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
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
 VALUES('occasion','occasion',new_id,new_id::text,1);
 INSERT INTO public.client_commits(unit,actor_id,actor_kind,source,change_class)
 VALUES(d.unit,auth.uid(),'user','occasion.setup.finalize','configuration') RETURNING * INTO v_commit;
 INSERT INTO public.client_commit_items(commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
 SELECT v_commit.commit_id,0,'occasion',new_id::text,'insert',left(title,240),ARRAY['aggregate'] FROM public.occasions WHERE id=new_id;
 PERFORM public.fanout_unit_catalog_v1(v_commit.commit_id,d.unit);
 receipt := jsonb_build_object('status','applied','code',200,'data',
  jsonb_build_object('occasionId',new_id,'link',(SELECT link FROM public.occasions WHERE id=new_id)));
 receipt := public.finish_client_mutation_v1(p_command_id,receipt,v_commit.commit_id);
 UPDATE public.occasion_setup_drafts SET data=data || jsonb_build_object('finalizedOccasion',new_id,'finalizeResponse',receipt),revision=revision+1 WHERE id=p_id;
 RETURN receipt;
END $$;
REVOKE ALL ON FUNCTION public.finalize_occasion_setup_draft(uuid,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.finalize_occasion_setup_draft(uuid,bigint,uuid) TO authenticated;

DROP FUNCTION IF EXISTS public.update_blueprint(jsonb);
DROP FUNCTION IF EXISTS public.update_blueprint_internal_v1(jsonb);
COMMIT;
