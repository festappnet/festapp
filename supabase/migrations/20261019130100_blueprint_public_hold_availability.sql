-- Canonical public catalog/hold admission and shared inventory configuration copy.
BEGIN;
-- Configuration-only extraction of the existing occasion-copy owner. Physical
-- inventory is copied exactly; capacity is never inferred from slot count.
CREATE OR REPLACE FUNCTION public.copy_inventory_resource_configuration_internal(p_source bigint,p_pool bigint,p_place bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE r public.resources; target public.inventory_pools; target_unit bigint; target_org bigint; new_id bigint; slot record; new_slot bigint; slots jsonb:='{}';
BEGIN
 SELECT * INTO r FROM public.resources WHERE id=p_source;
 SELECT * INTO target FROM public.inventory_pools WHERE id=p_pool;
 SELECT unit,organization INTO target_unit,target_org FROM public.occasions WHERE id=target.occasion;
 IF r.id IS NULL OR target.id IS NULL OR NOT public.can_copy_occasion_source(r.occasion)
  OR target_org IS DISTINCT FROM (SELECT organization FROM public.occasions WHERE id=r.occasion) THEN RAISE insufficient_privilege USING MESSAGE='Inventory copy source denied'; END IF;
 IF public.get_is_editor_order_on_occasion(target.occasion) IS NOT TRUE AND public.get_is_manager_on_unit(target_unit) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='Inventory copy target denied'; END IF;
 IF p_place IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.places WHERE id=p_place AND occasion=target.occasion) THEN RAISE check_violation USING MESSAGE='Inventory copy place denied'; END IF;
 INSERT INTO public.resources(title,description,capacity,booking_rules,inventory_pool,place,occasion,unit,data)
 VALUES(r.title,r.description,r.capacity,r.booking_rules,p_pool,p_place,target.occasion,target_unit,r.data) RETURNING id INTO new_id;
 FOR slot IN SELECT * FROM public.resource_slots WHERE resource=r.id ORDER BY id LOOP
  INSERT INTO public.resource_slots(resource,title,data) VALUES(new_id,slot.title,slot.data) RETURNING id INTO new_slot;
  slots:=slots||jsonb_build_object(slot.id::text,new_slot);
 END LOOP;
 RETURN jsonb_build_object('resourceId',new_id,'slotMap',slots);
END $$;
REVOKE ALL ON FUNCTION public.copy_inventory_resource_configuration_internal(bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.copy_empty_inventory_spot_internal(p_source bigint,p_occasion bigint,p_product bigint,p_blueprint bigint,p_context bigint,p_resource bigint,p_slot bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE source eshop.spots; new_id bigint;
BEGIN
 SELECT * INTO source FROM eshop.spots WHERE id=p_source;
 IF source.id IS NULL OR NOT public.can_copy_occasion_source(source.occasion)
  OR (SELECT organization FROM public.occasions WHERE id=p_occasion) IS DISTINCT FROM
     (SELECT organization FROM public.occasions WHERE id=source.occasion) THEN RAISE insufficient_privilege USING MESSAGE='Inventory copy source denied'; END IF;
 IF public.get_is_editor_order_on_occasion(p_occasion) IS NOT TRUE AND public.get_is_manager_on_unit((SELECT unit FROM public.occasions WHERE id=p_occasion)) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='Inventory copy target denied'; END IF;
 IF (p_product IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.products WHERE id=p_product AND occasion=p_occasion))
  OR (p_blueprint IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=p_blueprint AND occasion=p_occasion))
  OR (p_context IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.inventory_contexts c JOIN public.inventory_pools p ON p.id=c.inventory_pool WHERE c.id=p_context AND p.occasion=p_occasion))
  OR (p_resource IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.resources WHERE id=p_resource AND occasion=p_occasion))
  OR (p_slot IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.resource_slots WHERE id=p_slot AND resource=p_resource)) THEN RAISE check_violation USING MESSAGE='Inventory copy target denied'; END IF;
 INSERT INTO eshop.spots(created_at,occasion,product,updated_at,secret,secret_expiration_time,title,order_product_ticket,blueprint,inventory_context,resource,resource_slot)
 VALUES(now(),p_occasion,p_product,now(),NULL,NULL,source.title,NULL,p_blueprint,p_context,p_resource,p_slot) RETURNING id INTO new_id;
 RETURN new_id;
END $$;
REVOKE ALL ON FUNCTION public.copy_empty_inventory_spot_internal(bigint,bigint,bigint,bigint,bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.copy_setup_area_inventory_internal(p_areas jsonb,p_products jsonb,p_source bigint,p_target bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE area jsonb; pool public.inventory_pools; resource_row public.resources; bundle jsonb; mapped jsonb:='{}';
 old_ids bigint[]; new_ids bigint[]; new_pool bigint; index integer; old_product bigint; new_product bigint; links jsonb; copied jsonb; resource_map jsonb; slot_map jsonb; source_spot record;
BEGIN
 PERFORM public.check_is_editor_order_on_occasion(p_target);
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_areas) a WHERE a->>'inventoryContextId' IS NOT NULL) THEN
  IF p_source IS NULL OR NOT public.can_copy_occasion_source(p_source) THEN RAISE insufficient_privilege USING MESSAGE='Copy source denied'; END IF;
 END IF;
 FOR area IN SELECT value FROM jsonb_array_elements(p_areas) WHERE value->>'inventoryContextId' IS NOT NULL LOOP
  IF NOT EXISTS(SELECT 1 FROM eshop.product_inventory_contexts pic JOIN public.inventory_contexts ic ON ic.id=pic.inventory_context
   JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool JOIN eshop.products product ON product.id=pic.product
   WHERE pic.product=(area->>'productId')::bigint AND ic.id=(area->>'inventoryContextId')::bigint AND ip.occasion=p_source AND product.occasion=p_source) THEN
   RAISE check_violation USING MESSAGE='BLUEPRINT_SETUP_FOREIGN_CONTEXT'; END IF;
 END LOOP;
 FOR pool IN SELECT DISTINCT ip.* FROM public.inventory_pools ip JOIN public.inventory_contexts ic ON ic.inventory_pool=ip.id
  JOIN eshop.product_inventory_contexts pic ON pic.inventory_context=ic.id WHERE ip.occasion=p_source AND pic.product IN
   (SELECT (a->>'productId')::bigint FROM jsonb_array_elements(p_areas) a WHERE a->>'inventoryContextId' IS NOT NULL) ORDER BY ip.id LOOP
  bundle:=public.update_inventory_pool_bundle(jsonb_build_object('pool',(to_jsonb(pool)-'id'-'created_at'-'updated_at')||jsonb_build_object('occasion',p_target),
   'contexts',(SELECT jsonb_agg(to_jsonb(ic)-'id'-'inventory_pool' ORDER BY ic.id) FROM public.inventory_contexts ic WHERE ic.inventory_pool=pool.id)));
  new_pool:=(bundle#>>'{pool,id}')::bigint;
  SELECT array_agg(id ORDER BY id) INTO old_ids FROM public.inventory_contexts WHERE inventory_pool=pool.id;
  SELECT array_agg(id ORDER BY id) INTO new_ids FROM public.inventory_contexts WHERE inventory_pool=new_pool;
  FOR index IN 1..coalesce(array_length(old_ids,1),0) LOOP mapped:=mapped||jsonb_build_object(old_ids[index]::text,new_ids[index]); END LOOP;
  resource_map:='{}';slot_map:='{}';
  FOR resource_row IN SELECT * FROM public.resources WHERE inventory_pool=pool.id ORDER BY id LOOP
   copied:=public.copy_inventory_resource_configuration_internal(resource_row.id,new_pool,NULL);
   resource_map:=resource_map||jsonb_build_object(resource_row.id::text,copied->'resourceId');
   slot_map:=slot_map||(copied->'slotMap');
  END LOOP;
  FOR source_spot IN SELECT * FROM eshop.spots WHERE inventory_context=ANY(old_ids) ORDER BY id LOOP
   PERFORM public.copy_empty_inventory_spot_internal(source_spot.id,p_target,NULL,NULL,
     (mapped->>source_spot.inventory_context::text)::bigint,
     (resource_map->>source_spot.resource::text)::bigint,
     (slot_map->>source_spot.resource_slot::text)::bigint);
  END LOOP;
 END LOOP;
 FOR old_product IN SELECT DISTINCT (a->>'productId')::bigint FROM jsonb_array_elements(p_areas) a WHERE a->>'inventoryContextId' IS NOT NULL LOOP
  new_product:=(p_products->>old_product::text)::bigint;
  IF new_product IS NULL THEN RAISE check_violation USING MESSAGE='BLUEPRINT_SETUP_PRODUCT_NOT_IN_FORM'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('inventory_context_id',(mapped->>inventory_context::text)::bigint,'quantity',quantity)),'[]') INTO links
   FROM eshop.product_inventory_contexts WHERE product=old_product;
  PERFORM public.update_product_inventory_contexts_internal_v1(new_product,links);
 END LOOP;
 RETURN mapped;
END $$;



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
    SELECT id, data, title, organization, configuration, objects, groups, background_svg, layout
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
      (created_at, data, title, organization, configuration, objects, groups, occasion, updated_at, background_svg,layout,layout_revision)
    VALUES (now(), rec.data, rec.title, v_organization, rec.configuration, rec.objects, rec.groups, new_occ, now(), rec.background_svg,v_copied_layout,0)
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
  DROP TABLE tmp_places, tmp_events, tmp_exclusive_groups, tmp_blueprints,tmp_blueprint_layout_ids,
    tmp_product_types, tmp_products, tmp_spots, tmp_forms, tmp_information_hidden,
    tmp_inventory_pools,tmp_inventory_contexts,tmp_resources,tmp_resource_slots,tmp_scanner_fields;
  RETURN new_occ;
END;
$$ LANGUAGE plpgsql;


-- Existing internal callers retain same-unit semantics.







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

    -- Fetch blueprint details
    SELECT jsonb_build_object(
        'id', b.id,
        'occasion', b.occasion,
        'created_at', b.created_at,
        'data', b.data,
        'title', b.title,
        'configuration', b.configuration,
        'objects', b.objects,
        'groups', b.groups,
        'background_svg', b.background_svg,
        'layout', b.layout, 'layout_revision', b.layout_revision,
        'layoutResources', public.blueprint_layout_resources_internal(b.layout,b.occasion)
    )
    INTO blueprintData
    FROM eshop.blueprints b
    WHERE b.id = blueprint_id;

    -- Fetch valid spot IDs
    SELECT jsonb_agg((obj->>'id')::BIGINT)
    INTO valid_spots
    FROM jsonb_array_elements(
        (SELECT b.objects FROM eshop.blueprints b WHERE b.id = blueprint_id)
    ) obj
    WHERE obj->>'type' = 'spot'
      AND obj->>'id' IS NOT NULL;

    SELECT coalesce(valid_spots,'[]'::jsonb)||coalesce(jsonb_agg(spot),'[]'::jsonb) INTO valid_spots FROM eshop.blueprint_seat_bindings WHERE blueprint=blueprint_id;

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

-- One admission preflight for the complete atomic unit. These are the same
-- offered fields, maximum counts and physical/context quantities as checkout.
CREATE OR REPLACE FUNCTION public.blueprint_hold_admission_internal(p_form bigint,p_spots bigint[],p_secret uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE item record; counts jsonb; requested bigint; occupied bigint; physical bigint; cap bigint;
BEGIN
 -- Serialize all products and required inventory contexts in canonical ID order.
 PERFORM 1 FROM eshop.products WHERE id IN (SELECT product FROM eshop.spots WHERE id=ANY(p_spots)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_pools WHERE id IN (SELECT ic.inventory_pool FROM public.inventory_contexts ic
  JOIN eshop.product_inventory_contexts pic ON pic.inventory_context=ic.id JOIN eshop.spots s ON s.product=pic.product WHERE s.id=ANY(p_spots)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_contexts WHERE id IN (SELECT pic.inventory_context FROM eshop.product_inventory_contexts pic
  JOIN eshop.spots s ON s.product=pic.product WHERE s.id=ANY(p_spots)) ORDER BY id FOR UPDATE;
 FOR item IN SELECT p.*,count(*) AS requested FROM eshop.spots s JOIN eshop.products p ON p.id=s.product
  WHERE s.id=ANY(p_spots) AND NOT coalesce(s.secret=p_secret AND s.secret_expiration_time>statement_timestamp(),false)
  GROUP BY p.id ORDER BY p.id LOOP
  IF item.is_hidden THEN RETURN jsonb_build_object('code',409,'reason','PRODUCT_HIDDEN'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.form_fields ff WHERE ff.form=p_form AND ff.product_type=item.product_type
   AND ff.type='product_type' AND ff.is_ticket_field AND NOT ff.is_hidden) THEN
   RETURN jsonb_build_object('code',409,'reason','PRODUCT_NOT_IN_FORM'); END IF;
  IF coalesce(item.maximum,0)>0 THEN
   SELECT count(*) INTO occupied FROM eshop.order_product_ticket WHERE product=item.id;
   SELECT occupied+count(*) INTO occupied FROM eshop.spots WHERE product=item.id AND order_product_ticket IS NULL
    AND secret IS NOT NULL AND secret_expiration_time>statement_timestamp();
   IF occupied+item.requested>item.maximum THEN RETURN jsonb_build_object('code',409,'reason','PRODUCT_CAPACITY_EXCEEDED'); END IF;
  END IF;
  counts:=public.blueprint_product_availability_internal(item.id);
  IF (counts->>'available')::bigint<item.requested THEN RETURN jsonb_build_object('code',409,'reason',coalesce(counts->>'reason','PRODUCT_CAPACITY_EXCEEDED')); END IF;
 END LOOP;
 -- Two differently priced products can consume the same context. Sum their
 -- quantities before holding either member, rather than checking them alone.
 FOR item IN SELECT pic.inventory_context,ip.sellable_capacity,sum(pic.quantity)::bigint AS requested
  FROM eshop.spots s JOIN eshop.product_inventory_contexts pic ON pic.product=s.product
  JOIN public.inventory_contexts ic ON ic.id=pic.inventory_context JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool
  WHERE s.id=ANY(p_spots) AND NOT coalesce(s.secret=p_secret AND s.secret_expiration_time>statement_timestamp(),false)
  GROUP BY pic.inventory_context,ip.sellable_capacity ORDER BY pic.inventory_context LOOP
  SELECT count(*),count(*) FILTER(WHERE order_product_ticket IS NOT NULL OR
   (secret IS NOT NULL AND secret_expiration_time>statement_timestamp())) INTO physical,occupied
   FROM eshop.spots WHERE inventory_context=item.inventory_context;
  -- Addressed seats usually have no inventory_context. Their existing spot
  -- holds nevertheless promise all PIC quantities at checkout. Count that
  -- same hold record, subtracting any physical occupancy already counted.
  SELECT occupied+coalesce(sum(greatest(pic.quantity-CASE
    WHEN held.inventory_context=item.inventory_context THEN 1 ELSE 0 END,0)),0)
   INTO occupied FROM eshop.spots held JOIN eshop.product_inventory_contexts pic ON pic.product=held.product
   WHERE pic.inventory_context=item.inventory_context AND held.blueprint IS NOT NULL
    AND held.order_product_ticket IS NULL AND held.secret IS NOT NULL
    AND held.secret_expiration_time>statement_timestamp();
  cap:=least(physical,coalesce(item.sellable_capacity,physical));
  IF occupied+item.requested>cap THEN RETURN jsonb_build_object('code',409,'reason','PRODUCT_CAPACITY_EXCEEDED'); END IF;
 END LOOP;
 RETURN jsonb_build_object('code',200);
END $$;
REVOKE ALL ON FUNCTION public.blueprint_hold_admission_internal(bigint,bigint[],uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.select_spot_single_internal_v1(form_key uuid,secret_id uuid,spot_id bigint,selecting boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE bp bigint; occ bigint; org bigint; un bigint; s eshop.spots; policy jsonb; scopes jsonb; costs jsonb; r jsonb; held bigint; duration_seconds integer; form_data jsonb; form_open boolean; fid bigint;
BEGIN
 IF secret_id IS NULL OR selecting IS NULL THEN RETURN jsonb_build_object('code',400,'message','Invalid reservation'); END IF;
 SELECT f.blueprint,f.occasion,o.organization,o.unit,f.id,f.is_open INTO bp,occ,org,un,fid,form_open FROM public.forms f
 JOIN public.occasions o ON o.id=f.occasion WHERE f.key=form_key;
 IF bp IS NULL THEN RETURN jsonb_build_object('code',404,'message','Form blueprint not found'); END IF;
 PERFORM public.check_occasion_writable(occ);
 -- A buyer's active inventory is serialized before the individual spot lock.
 PERFORM pg_advisory_xact_lock(hashtextextended('hold:'||secret_id::text,0));
 SELECT * INTO s FROM eshop.spots WHERE id=spot_id AND blueprint=bp FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('code',404,'message','Spot not found'); END IF;
 IF s.order_product_ticket IS NOT NULL THEN RETURN jsonb_build_object('code',409,'message','Spot is already ordered'); END IF;
 IF s.secret_expiration_time<=statement_timestamp() THEN
  UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL WHERE id=spot_id;
  s.secret:=NULL; s.secret_expiration_time:=NULL;
 END IF;
 IF s.secret IS NOT NULL AND s.secret IS DISTINCT FROM secret_id THEN
  RETURN jsonb_build_object('code',403,'message','Spot is held by another buyer'); END IF;
 IF NOT selecting THEN
  UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL,updated_at=now() WHERE id=spot_id;
  RETURN jsonb_build_object('code',200,'message','Spot deselected');
 END IF;
 -- A retry cannot move the original expiration, including after another tab reload.
 IF s.secret=secret_id THEN RETURN jsonb_build_object('code',200,'message','Spot selected','expiresAt',s.secret_expiration_time); END IF;
 r:=public.blueprint_hold_admission_internal(fid,ARRAY[s.id],secret_id);
 IF (r->>'code')::integer<>200 THEN RETURN r; END IF;
 IF selecting AND public.get_is_editor_order_on_occasion(occ) IS NOT TRUE THEN
  form_data:=public.get_effective_form_data(fid);
  IF form_open IS NOT TRUE OR
   (coalesce(form_data#>>'{schedule,start_time}',form_data->>'start_time'))::timestamptz>statement_timestamp() OR
   (coalesce(form_data#>>'{schedule,end_time}',form_data->>'end_time'))::timestamptz<statement_timestamp() THEN
   RETURN jsonb_build_object('code',403,'message','Form is not open'); END IF;
 END IF;
 policy:=public.abuse_effective_rules_v1('spot.hold',un,org);
 scopes:=jsonb_build_object('recipient',secret_id,'unit',un,'organization',org);
 FOR r IN SELECT value FROM jsonb_array_elements(policy->'rules') ORDER BY value->>'rule_key' LOOP
  PERFORM pg_advisory_xact_lock(hashtextextended('abuse:'||(r->>'rule_key')||':'||(scopes->>(r->>'scope_kind')),0));
 END LOOP;
 SELECT count(*) INTO held FROM eshop.spots WHERE secret=secret_id AND secret_expiration_time>statement_timestamp() AND order_product_ticket IS NULL;
 costs:=jsonb_build_object('hold.active.buyer',held+1);
 PERFORM public.abuse_charge_v1(policy,scopes,costs);
 SELECT (x->>'base_limit')::integer INTO duration_seconds FROM jsonb_array_elements(public.abuse_effective_rules_v1('hold.duration',un,org)->'rules') x;
 IF duration_seconds IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
 UPDATE eshop.spots SET secret=secret_id,secret_expiration_time=statement_timestamp()+make_interval(secs=>duration_seconds),updated_at=now() WHERE id=spot_id RETURNING * INTO s;
 RETURN jsonb_build_object('code',200,'message','Spot selected','expiresAt',s.secret_expiration_time);
END $$;

CREATE OR REPLACE FUNCTION public.select_spot(form_key uuid,secret_id uuid,spot_id bigint,selecting boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ids bigint[]; member_id bigint; r jsonb; occ bigint; bp bigint; fid bigint;
BEGIN
 SELECT occasion,blueprint,id INTO occ,bp,fid FROM public.forms WHERE key=form_key;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 PERFORM pg_advisory_xact_lock(hashtextextended('hold:'||secret_id::text,0));
 ids:=public.blueprint_selection_unit_spots_internal(spot_id);
 PERFORM 1 FROM eshop.spots WHERE id=ANY(ids) ORDER BY id FOR UPDATE;
 BEGIN
  IF selecting AND EXISTS(SELECT 1 FROM eshop.spots s LEFT JOIN eshop.blueprint_seat_bindings b ON b.spot=s.id
   WHERE s.id=ANY(ids) AND (b.blocked OR s.product IS NULL)
    AND NOT coalesce(s.secret=secret_id AND s.secret_expiration_time>statement_timestamp(),false)) THEN
   RAISE check_violation USING MESSAGE='BLUEPRINT_SEAT_UNAVAILABLE'; END IF;
  IF selecting THEN
   r:=public.blueprint_hold_admission_internal(fid,ids,secret_id);
   IF (r->>'code')::integer<>200 THEN RETURN r; END IF;
  END IF;
  FOREACH member_id IN ARRAY ids LOOP
   r:=public.select_spot_single_internal_v1(form_key,secret_id,member_id,selecting);
   IF coalesce((r->>'code')::integer,500)<>200 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_HOLD_REJECTED'; END IF;
  END LOOP;
 EXCEPTION WHEN check_violation THEN
  RETURN coalesce(r,jsonb_build_object('code',409,'reason',SQLERRM,'message',SQLERRM));
 END;
 RETURN r||jsonb_build_object('spotIds',to_jsonb(ids));
END $$;



COMMIT;
