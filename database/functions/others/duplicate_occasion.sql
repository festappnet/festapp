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
    INSERT INTO public.resources(title,description,capacity,booking_rules,inventory_pool,place,occasion,unit,data)
    VALUES(rec.title,rec.description,rec.capacity,rec.booking_rules,
      (SELECT new_id FROM tmp_inventory_pools WHERE old_id=rec.inventory_pool),
      (SELECT new_id FROM tmp_places WHERE old_id=rec.place),new_occ,v_target_unit,rec.data)
    RETURNING id INTO v_new_id;
    INSERT INTO tmp_resources VALUES(rec.id,v_new_id);
  END LOOP;
  FOR rec IN SELECT r.* FROM public.resource_slots r JOIN tmp_resources m ON m.old_id=r.resource LOOP
    INSERT INTO public.resource_slots(resource,title,data)
    VALUES((SELECT new_id FROM tmp_resources WHERE old_id=rec.resource),rec.title,rec.data)
    RETURNING id INTO v_new_id;
    INSERT INTO tmp_resource_slots VALUES(rec.id,v_new_id);
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

    INSERT INTO eshop.spots
      (created_at, occasion, product, updated_at, secret, secret_expiration_time, title, order_product_ticket, blueprint, inventory_context, resource, resource_slot)
    VALUES (now(), new_occ, COALESCE(new_product_id, rec.product), now(), null, null, rec.title, null, COALESCE(new_bp_id, rec.blueprint),
      (SELECT new_id FROM tmp_inventory_contexts WHERE old_id=rec.inventory_context),
      (SELECT new_id FROM tmp_resources WHERE old_id=rec.resource),
      (SELECT new_id FROM tmp_resource_slots WHERE old_id=rec.resource_slot))
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
  DROP TABLE tmp_places, tmp_events, tmp_exclusive_groups, tmp_blueprints,
    tmp_product_types, tmp_products, tmp_spots, tmp_forms, tmp_information_hidden,
    tmp_inventory_pools,tmp_inventory_contexts,tmp_resources,tmp_resource_slots,tmp_scanner_fields;
  RETURN new_occ;
END;
$$ LANGUAGE plpgsql;
REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint,bigint)
  FROM PUBLIC, anon, authenticated, service_role;

-- Existing internal callers retain same-unit semantics.
CREATE OR REPLACE FUNCTION public.duplicate_occasion_internal_v1(oc bigint)
RETURNS bigint LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT public.duplicate_occasion_internal_v1(oc, NULL);
$$;
REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint)
  FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint,bigint,text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.duplicate_occasion_internal_v1(oc bigint,p_target_unit bigint)
RETURNS bigint LANGUAGE sql SECURITY DEFINER SET search_path = public, extensions AS $$
 SELECT public.duplicate_occasion_internal_v1(oc,p_target_unit,'en');
$$;
REVOKE ALL ON FUNCTION public.duplicate_occasion_internal_v1(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
