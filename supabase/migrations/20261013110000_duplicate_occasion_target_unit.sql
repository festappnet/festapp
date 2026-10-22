-- Canonical occasion copy with an authorized target Unit.
CREATE OR REPLACE FUNCTION public.duplicate_occasion_internal_v1(oc bigint, p_target_unit bigint)
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
BEGIN
  SELECT unit, organization INTO v_source_unit, v_organization
  FROM public.occasions WHERE id = oc;
  v_target_unit := COALESCE(p_target_unit, v_source_unit);
  IF auth.uid() IS NULL OR v_source_unit IS NULL OR v_target_unit IS NULL
     OR NOT public.get_is_manager_on_unit(v_source_unit)
     OR NOT public.get_is_manager_on_unit(v_target_unit)
     OR NOT EXISTS (SELECT 1 FROM public.units
       WHERE id = v_target_unit AND organization = v_organization) THEN
    RAISE insufficient_privilege USING MESSAGE = 'source and target unit manager required within one organization';
  END IF;

  ------------------------------------------------------------------
  -- 1. Duplicate the main occasion record.
  --    Modify the link to ensure uniqueness by appending a unique suffix.
  ------------------------------------------------------------------
  INSERT INTO public.occasions
    (created_at, updated_at, data, is_hidden, is_open, is_promoted, start_time, end_time, link, title, organization, services, unit, features, occasion_hidden, description)
  SELECT now(), now(), data, is_hidden, is_open, is_promoted, start_time, end_time,
         link || '-copy-' || substring(md5(random()::text) from 1 for 8) AS link,
         title || ' (Copy)', v_organization, services, v_target_unit, features, occasion_hidden, description
  FROM public.occasions
  WHERE id = oc
  RETURNING id INTO new_occ;

  RAISE NOTICE 'New occasion id: %', new_occ;

  ------------------------------------------------------------------
  -- 2. Create temporary mapping tables (old id → new id)
  ------------------------------------------------------------------
  CREATE TEMP TABLE tmp_places (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_events (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_exclusive_groups (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_blueprints (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_product_types (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_products (old_id bigint, new_id bigint) ON COMMIT DROP;
  CREATE TEMP TABLE tmp_spots (old_id bigint, new_id bigint) ON COMMIT DROP;
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
    WHERE occasion = oc
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
    SELECT id, data, title, organization, configuration, objects, groups, background_svg
    FROM eshop.blueprints
    WHERE occasion = oc
  LOOP
    INSERT INTO eshop.blueprints
      (created_at, data, title, organization, configuration, objects, groups, occasion, updated_at, background_svg)
    VALUES (now(), rec.data, rec.title, v_organization, rec.configuration, rec.objects, rec.groups, new_occ, now(), rec.background_svg)
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
    SELECT id, title, description, price, data, product_type, is_hidden, currency_code, "order"
    FROM eshop.products
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_pt_id
      FROM tmp_product_types AS t
      WHERE t.old_id = rec.product_type;

    INSERT INTO eshop.products
      (created_at, updated_at, title, description, price, data, product_type, occasion, is_hidden, currency_code, "order")
    VALUES (now(), now(), rec.title, rec.description, rec.price, rec.data,
            COALESCE(new_pt_id, rec.product_type), new_occ, rec.is_hidden, rec.currency_code, rec."order")
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_products (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 5d. Spots – adjust foreign keys for product and blueprint.
  FOR rec IN
    SELECT id, product, secret, secret_expiration_time, title, order_product_ticket, blueprint
    FROM eshop.spots
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_product_id
      FROM tmp_products AS t
      WHERE t.old_id = rec.product;

    SELECT t.new_id INTO new_bp_id
      FROM tmp_blueprints AS t
      WHERE t.old_id = rec.blueprint;

    INSERT INTO eshop.spots
      (created_at, occasion, product, updated_at, secret, secret_expiration_time, title, order_product_ticket, blueprint)
    VALUES (now(), new_occ, COALESCE(new_product_id, rec.product), now(), null, null, rec.title, null, COALESCE(new_bp_id, rec.blueprint))
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_spots (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  ------------------------------------------------------------------
  -- 6. Update blueprints “objects” JSON column if it contains spot objects.
  --    For each blueprint, if its "objects" JSON array contains an object with "type" = 'spot',
  --    replace its "id" with the corresponding new spot id.
  ------------------------------------------------------------------
  FOR rec IN
    SELECT tb.old_id AS old_bp, tb.new_id AS new_bp, b.objects
    FROM tmp_blueprints tb
    JOIN eshop.blueprints b ON b.id = tb.new_id
  LOOP
    IF rec.objects IS NOT NULL THEN
      UPDATE eshop.blueprints
      SET objects = (
        SELECT jsonb_agg(
          CASE
            WHEN obj->>'type' = 'spot' THEN
              obj || jsonb_build_object(
                'id',
                COALESCE(
                  (SELECT ts.new_id FROM tmp_spots ts WHERE ts.old_id = (obj->>'id')::bigint),
                  (obj->>'id')::int
                )
              )
            ELSE obj
          END
        )
        FROM jsonb_array_elements(rec.objects) AS obj
      )
      WHERE id = rec.new_bp;
    END IF;
  END LOOP;


  ------------------------------------------------------------------
  -- 7. Duplicate Forms and Form Fields
  ------------------------------------------------------------------

  -- 7a. Forms – adjust the blueprint foreign key via mapping and update the link to be unique.
  FOR rec IN
    SELECT id, data, key, type, bank_account, deadline_duration_seconds, is_open, link, blueprint, header, header_off, title
    FROM public.forms
    WHERE occasion = oc
  LOOP
    SELECT t.new_id INTO new_bp_id
      FROM tmp_blueprints AS t
      WHERE t.old_id = rec.blueprint;

    INSERT INTO public.forms
      (created_at, data, key, occasion, type, bank_account, deadline_duration_seconds, is_open, link, blueprint, header, header_off, updated_at, title)
    VALUES (now(), rec.data, uuid_generate_v4(), new_occ, rec.type,
            CASE WHEN v_source_unit = v_target_unit OR EXISTS (
              SELECT 1 FROM eshop.unit_bank_accounts uba
              WHERE uba.unit = v_target_unit AND uba.bank_account = rec.bank_account)
              THEN rec.bank_account ELSE NULL END,
            rec.deadline_duration_seconds,
            CASE WHEN v_source_unit <> v_target_unit AND rec.bank_account IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM eshop.unit_bank_accounts uba
                WHERE uba.unit = v_target_unit AND uba.bank_account = rec.bank_account)
              THEN false ELSE rec.is_open END,
            replace(uuid_generate_v4()::text, '-', ''),
            COALESCE(new_bp_id, rec.blueprint), rec.header, rec.header_off, now(), rec.title)
    RETURNING id INTO v_new_id;

    INSERT INTO tmp_forms (old_id, new_id)
    VALUES (rec.id, v_new_id);
  END LOOP;

  -- 7b. Form Fields – update the "form" foreign key and product_type via mapping tables.
  INSERT INTO public.form_fields
    (created_at, title, description, data, type, is_required, form, is_hidden, "order", product_type, is_ticket_field)
  SELECT now(), title, description, data, type, is_required,
         (SELECT tf.new_id FROM tmp_forms AS tf WHERE tf.old_id = form),
         is_hidden, "order",
         CASE WHEN product_type IS NOT NULL
              THEN (SELECT tp.new_id FROM tmp_product_types AS tp WHERE tp.old_id = product_type)
              ELSE NULL END,
         is_ticket_field
  FROM public.form_fields
  WHERE form IN (SELECT old_id FROM tmp_forms);

  ------------------------------------------------------------------
  -- 8. Return the new occasion id
  ------------------------------------------------------------------
  DROP TABLE tmp_places, tmp_events, tmp_exclusive_groups, tmp_blueprints,
    tmp_product_types, tmp_products, tmp_spots, tmp_forms, tmp_information_hidden;
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

-- The duplicate command must use the audit operation accepted by
-- client_commit_items_operation_check. The old value, 'create', rolled back
-- every attempted occasion copy before it returned an occasion ID.
CREATE OR REPLACE FUNCTION public.duplicate_occasion_client_sync_v1(
  p_occasion bigint, p_command_id uuid, p_target_unit bigint
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_unit bigint;
  v_title text;
  v_source_unit bigint;
  v_org bigint;
  v_new bigint;
  v_begin jsonb;
  v_hash text;
  v_commit public.client_commits%ROWTYPE;
BEGIN
  SELECT o.unit, o.title, o.organization INTO v_source_unit, v_title, v_org
  FROM public.occasions o WHERE o.id = p_occasion;
  v_unit := COALESCE(p_target_unit, v_source_unit);
  IF v_actor IS NULL OR v_source_unit IS NULL OR v_unit IS NULL
     OR NOT public.get_is_manager_on_unit(v_source_unit)
     OR NOT public.get_is_manager_on_unit(v_unit)
     OR NOT EXISTS (SELECT 1 FROM public.units WHERE id=v_unit AND organization=v_org) THEN
    RAISE insufficient_privilege USING MESSAGE = 'unit manager required';
  END IF;
  v_hash := encode(extensions.digest(convert_to((jsonb_build_object(
    'occasion', p_occasion) || CASE WHEN v_unit = v_source_unit THEN '{}'::jsonb
        ELSE jsonb_build_object('targetUnit', v_unit) END)::text, 'UTF8'), 'sha256'), 'hex');
  v_begin := public.begin_unit_client_mutation_v1(
    p_command_id, 'occasion.duplicate', v_unit, v_actor, v_hash);
  IF v_begin->>'disposition' = 'replay' THEN RETURN v_begin->'response'; END IF;

  v_new := public.duplicate_occasion_internal_v1(p_occasion, v_unit);
  INSERT INTO public.occasion_users
    (occasion, "user", is_manager, is_editor, is_editor_view, is_editor_order, is_editor_order_view)
  VALUES (v_new, v_actor, true, true, true, true, true);
  UPDATE public.occasions SET data = jsonb_set(COALESCE(data, '{}'::jsonb),
    '{client_sync_v1}', 'false'::jsonb, true) WHERE id = v_new;
  INSERT INTO public.client_commits
    (unit, actor_id, actor_display, actor_kind, source, change_class)
  SELECT v_unit, v_actor, nullif(concat_ws(' ', ui.name, ui.surname), ''),
    'user', 'occasion.duplicate', 'configuration'
  FROM public.user_info ui WHERE ui.id = v_actor
  RETURNING * INTO v_commit;
  INSERT INTO public.client_commit_items
    (commit_id, item_index, entity_type, entity_id, operation, safe_label,
     changed_fields)
  VALUES (v_commit.commit_id, 0, 'occasion', v_new::text, 'insert',
    left(COALESCE(v_title, '') || ' (Copy)', 240), ARRAY['aggregate']);
  PERFORM public.fanout_unit_catalog_v1(v_commit.commit_id, v_unit);
  RETURN public.finish_client_mutation_v1(p_command_id, jsonb_build_object(
    'status', 'applied', 'code', 200,
    'data', jsonb_build_object('occasionId', v_new),
    'mutation', jsonb_build_object('commandId', p_command_id,
      'receiptId', p_command_id, 'commitId', v_commit.commit_id,
      'replayed', false, 'occurredAt', v_commit.occurred_at),
    'sync', jsonb_build_object('replacements', '[]'::jsonb)),
    v_commit.commit_id);
END; $$;
REVOKE ALL ON FUNCTION public.duplicate_occasion_client_sync_v1(bigint, uuid, bigint)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.duplicate_occasion_client_sync_v1(bigint, uuid, bigint)
  TO authenticated;


-- Keep existing client signatures routed through the same canonical command.
CREATE OR REPLACE FUNCTION public.duplicate_occasion_client_sync_v1(
  p_occasion bigint, p_command_id uuid
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT public.duplicate_occasion_client_sync_v1(p_occasion, p_command_id, NULL);
$$;
REVOKE ALL ON FUNCTION public.duplicate_occasion_client_sync_v1(bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_occasion_client_sync_v1(bigint,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.duplicate_occasion(oc bigint, p_target_unit bigint)
RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_response jsonb;
BEGIN
  v_response := public.duplicate_occasion_client_sync_v1(oc, gen_random_uuid(), p_target_unit);
  RETURN (v_response #>> '{data,occasionId}')::bigint;
END; $$;
REVOKE ALL ON FUNCTION public.duplicate_occasion(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_occasion(bigint,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.duplicate_occasion(oc bigint)
RETURNS bigint LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT public.duplicate_occasion(oc, NULL);
$$;
REVOKE ALL ON FUNCTION public.duplicate_occasion(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_occasion(bigint) TO authenticated;

-- Return only authorized destinations. The navigation unit list does not carry
-- membership flags and may include units visible only through an occasion.
CREATE OR REPLACE FUNCTION public.get_occasion_copy_units(p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_org bigint; v_unit bigint;
BEGIN
  SELECT organization, unit INTO v_org, v_unit FROM public.occasions WHERE id=p_occasion;
  IF auth.uid() IS NULL OR v_unit IS NULL OR NOT public.get_is_manager_on_unit(v_unit) THEN
    RAISE insufficient_privilege USING MESSAGE='source unit manager required';
  END IF;
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object(
    'id', u.id, 'title', u.title, 'organization', u.organization) ORDER BY u.title,u.id)
    FROM public.units u WHERE u.organization=v_org AND public.get_is_manager_on_unit(u.id)), '[]'::jsonb);
END; $$;
REVOKE ALL ON FUNCTION public.get_occasion_copy_units(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_copy_units(bigint) TO authenticated;
