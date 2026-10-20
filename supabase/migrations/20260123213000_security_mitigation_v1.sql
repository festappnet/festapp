-- Migration: Security Fixes for Critical Vulnerabilities
-- Date: 2026-01-23
-- Description: 
-- 1. Secure duplicate_occasion with explicit permission guard.
-- 2. Downgrade internal helpers to SECURITY INVOKER to prevent privilege escalation.
-- 3. Revoke public/authenticated access to internal helpers.

BEGIN;

--------------------------------------------------------------------------------
-- 1. Secure duplicate_occasion
--    Keeps SECURITY DEFINER (required for deep cloning)
--    Adds explicit `check_is_manager_on_unit` guard.
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION duplicate_occasion(oc bigint)
RETURNS bigint
SECURITY DEFINER
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
BEGIN
    -- [SECURITY FIX] Check permissions first
    -- Only managers of the unit can duplicate occasions
    PERFORM public.check_is_manager_on_unit((SELECT unit FROM public.occasions WHERE id = oc));

  ------------------------------------------------------------------
  -- 1. Duplicate the main occasion record.
  --    Modify the link to ensure uniqueness by appending a unique suffix.
  ------------------------------------------------------------------
  INSERT INTO public.occasions
    (created_at, updated_at, data, is_hidden, is_open, is_promoted, start_time, end_time, link, title, organization, services, unit, features, occasion_hidden, description)
  SELECT now(), now(), data, is_hidden, is_open, is_promoted, start_time, end_time,
         link || '-copy-' || substring(md5(random()::text) from 1 for 8) AS link,
         title || ' (Copy)', organization, services, unit, features, occasion_hidden, description
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
  INSERT INTO public.email_templates (html, occasion, unit, subject, organization, code)
  SELECT html, new_occ, unit, subject, organization, code
  FROM public.email_templates
  WHERE occasion = oc;

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
         unit
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
    VALUES (rec.title, rec.description, rec.type, rec.created_at, rec.coordinates, rec.is_hidden, now(), new_occ, rec."order", rec.icon, rec.unit)
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
    VALUES (now(), rec.data, rec.title, rec.organization, rec.configuration, rec.objects, rec.groups, new_occ, now(), rec.background_svg)
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
    VALUES (now(), rec.data, uuid_generate_v4(), new_occ, rec.type, rec.bank_account, rec.deadline_duration_seconds, rec.is_open,
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
  RETURN new_occ;
END;
$$ LANGUAGE plpgsql;


--------------------------------------------------------------------------------
-- 2. Downgrade internal helpers to SECURITY INVOKER
--    Removes the privilege escalation vector.
--------------------------------------------------------------------------------

ALTER FUNCTION public.recalculate_order_payment_status(bigint) SECURITY INVOKER;
ALTER FUNCTION public.update_order_and_tickets_to_paid(bigint) SECURITY INVOKER;
ALTER FUNCTION public.internal_storno_tickets_221(bigint[]) SECURITY INVOKER;


--------------------------------------------------------------------------------
-- 3. Revoke Public Access (Defense in Depth)
--    Even as INVOKER, these shouldn't be publicly callable.
--------------------------------------------------------------------------------

REVOKE EXECUTE ON FUNCTION public.recalculate_order_payment_status(bigint) FROM public, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_order_and_tickets_to_paid(bigint) FROM public, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.internal_storno_tickets_221(bigint[]) FROM public, anon, authenticated;


--------------------------------------------------------------------------------
-- 4. Secure System Tables
--    Prevent public manipulation of migration history.
--------------------------------------------------------------------------------

REVOKE ALL ON TABLE public.supabase_migrations FROM anon, authenticated;

COMMIT;
