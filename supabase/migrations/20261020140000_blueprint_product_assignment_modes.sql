ALTER TABLE eshop.blueprint_seat_bindings ADD COLUMN IF NOT EXISTS product_assignment_mode text NOT NULL DEFAULT 'override' CHECK(product_assignment_mode IN ('inherit','override'));
-- Private host bindings only contain commercial identities; occupancy details
-- remain in the permission-checked admin reader's existing projection.
CREATE OR REPLACE FUNCTION public.blueprint_binding_projection_internal(p_blueprint bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object(
 'seatBindings',coalesce((SELECT jsonb_agg(jsonb_build_object('nodeId',b.node_id,'spotId',b.spot,'productId',s.product,'title',s.title,'selectionUnitId',b.selection_unit,'groupNodeId',b.group_node,'blocked',b.blocked,'productAssignmentMode',b.product_assignment_mode) ORDER BY b.node_id)
  FROM eshop.blueprint_seat_bindings b JOIN eshop.spots s ON s.id=b.spot WHERE b.blueprint=p_blueprint),'[]'),
 'groupProducts',coalesce((SELECT jsonb_agg(jsonb_build_object('groupNodeId',group_node,'productId',product) ORDER BY group_node) FROM eshop.blueprint_group_products WHERE blueprint=p_blueprint),'[]'),
 'areaBindings',coalesce((SELECT jsonb_agg(jsonb_build_object('nodeId',node_id,'inventoryContextId',inventory_context,'productId',product) ORDER BY node_id) FROM eshop.blueprint_area_bindings WHERE blueprint=p_blueprint),'[]'))
$$;
CREATE OR REPLACE FUNCTION public.blueprint_public_binding_projection_internal(p_blueprint bigint,p_secret uuid)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT public.blueprint_binding_projection_internal(p_blueprint)||jsonb_build_object('seatBindings',coalesce(
 (SELECT jsonb_agg(jsonb_build_object('nodeId',b.node_id,'spotId',b.spot,'productId',s.product,'title',s.title,'selectionUnitId',b.selection_unit,'groupNodeId',b.group_node,'blocked',b.blocked,'productAssignmentMode',b.product_assignment_mode,'status',CASE
 WHEN b.blocked OR s.product IS NULL THEN 'unavailable' WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
 WHEN s.secret IS NOT NULL AND s.secret_expiration_time>statement_timestamp() THEN CASE WHEN s.secret=p_secret THEN 'selected_by_me' ELSE 'selected' END
 ELSE 'available' END) ORDER BY b.node_id) FROM eshop.blueprint_seat_bindings b JOIN eshop.spots s ON s.id=b.spot WHERE b.blueprint=p_blueprint),'[]'))
$$;
REVOKE ALL ON FUNCTION public.blueprint_binding_projection_internal(bigint),public.blueprint_public_binding_projection_internal(bigint,uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.save_blueprint_layout_impl_internal(p_blueprint jsonb,p_reviewed_demo boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE b eshop.blueprints; c jsonb; binding eshop.blueprint_seat_bindings; s eshop.spots;
 node uuid; group_id uuid; unit_id uuid; product_id bigint; spot_id bigint; blocked_value boolean; assignment_mode text;
 pool public.inventory_pools; capacity_int bigint;
 node_index jsonb; unit_index jsonb; seat_count bigint;
 doc jsonb:=p_blueprint->'layout'; result jsonb; expected bigint; issue text; all_seats uuid[]; supplied uuid[];
BEGIN
 IF nullif(p_blueprint->>'id','') IS NULL THEN
  IF (coalesce(public.get_is_editor_on_occasion((p_blueprint->>'occasion')::bigint),false) OR coalesce(public.get_is_manager_on_occasion((p_blueprint->>'occasion')::bigint),false)) IS NOT TRUE THEN
   RAISE insufficient_privilege USING MESSAGE='blueprint editor required'; END IF;
  INSERT INTO eshop.blueprints(occasion,organization,title) SELECT id,organization,p_blueprint->>'title' FROM public.occasions WHERE id=(p_blueprint->>'occasion')::bigint RETURNING * INTO b;
 ELSE
  SELECT * INTO b FROM eshop.blueprints WHERE id=(p_blueprint->>'id')::bigint FOR UPDATE;
 END IF;
 IF b.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_NOT_FOUND'; END IF;
 IF p_reviewed_demo AND public.is_demo_occasion(b.occasion) THEN
  IF NOT EXISTS(SELECT 1 FROM public.occasion_users ou WHERE ou.occasion=b.occasion AND ou."user"=auth.uid() AND (ou.is_editor OR ou.is_manager)) THEN RAISE insufficient_privilege USING MESSAGE='blueprint migration reviewer required'; END IF;
 ELSE
 IF (coalesce(public.get_is_editor_on_occasion(b.occasion),false) OR coalesce(public.get_is_manager_on_occasion(b.occasion),false)) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='blueprint editor required'; END IF;
 END IF;
 IF p_reviewed_demo AND public.is_demo_occasion(b.occasion) THEN
  IF b.layout IS NOT NULL THEN RAISE check_violation USING MESSAGE='BLUEPRINT_MIGRATION_INITIAL_LAYOUT_REQUIRED'; END IF;
 ELSE PERFORM public.check_occasion_writable(b.occasion); END IF;
 expected:=(p_blueprint->>'expected_layout_revision')::bigint;
 IF expected IS NULL OR expected<>b.layout_revision THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_REVISION_CONFLICT'; END IF;
 PERFORM public.validate_blueprint_layout_internal(doc);
 PERFORM public.check_blueprint_image_resource_internal(doc,b.occasion);
 SELECT coalesce(jsonb_object_agg(x->>'id',x),'{}'),count(*) FILTER(WHERE x->>'kind'='seat') INTO node_index,seat_count FROM jsonb_array_elements(doc->'nodes') x;
 -- Membership is projected from the document, never trusted from an overlay.
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(doc->'selectionUnits','[]')) u WHERE
   (u->>'id')::uuid IS NULL OR jsonb_array_length(u->'nodeIds')=0 OR coalesce(u->>'kind','atomic')<>'atomic')
  OR EXISTS(SELECT member FROM jsonb_array_elements(coalesce(doc->'selectionUnits','[]')) u
   CROSS JOIN LATERAL jsonb_array_elements_text(u->'nodeIds') member GROUP BY member HAVING count(*)>1)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(doc->'selectionUnits','[]')) u
   CROSS JOIN LATERAL jsonb_array_elements_text(u->'nodeIds') member
   WHERE coalesce(node_index->member->>'kind','')<>'seat') THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_SELECTION_UNITS'; END IF;
 SELECT coalesce(jsonb_object_agg(member,u->>'id'),'{}') INTO unit_index
 FROM jsonb_array_elements(coalesce(doc->'selectionUnits','[]')) u CROSS JOIN LATERAL jsonb_array_elements_text(u->'nodeIds') member;
 -- Keep the existing financial resource lock ordering, before spot row locks.
 PERFORM 1 FROM eshop.products WHERE occasion=b.occasion ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_pools WHERE id IN(SELECT ic.inventory_pool FROM public.inventory_contexts ic
  JOIN eshop.product_inventory_contexts pic ON pic.inventory_context=ic.id JOIN eshop.products p ON p.id=pic.product WHERE p.occasion=b.occasion) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_contexts WHERE id IN(SELECT pic.inventory_context FROM eshop.product_inventory_contexts pic JOIN eshop.products p ON p.id=pic.product WHERE p.occasion=b.occasion) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.spots WHERE blueprint=b.id ORDER BY id FOR UPDATE;
 IF EXISTS(SELECT change->>'nodeId' FROM jsonb_array_elements(coalesce(p_blueprint->'seatChanges','[]')) change GROUP BY change->>'nodeId' HAVING count(*)>1) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_DUPLICATE_SEAT_CHANGE'; END IF;
 FOR c IN SELECT * FROM jsonb_array_elements(coalesce(p_blueprint->'seatChanges','[]')) LOOP
  node:=(c->>'nodeId')::uuid;
  SELECT * INTO binding FROM eshop.blueprint_seat_bindings WHERE blueprint=b.id AND node_id=node;
  IF c->>'operation'='delete' THEN
   IF binding.node_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_BINDING_NOT_FOUND',DETAIL=c::text; END IF;
   SELECT * INTO s FROM eshop.spots WHERE id=binding.spot;
   IF s.order_product_ticket IS NOT NULL OR (s.secret IS NOT NULL AND s.secret_expiration_time>statement_timestamp()) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_SEAT_PROTECTED',DETAIL=c::text; END IF;
   DELETE FROM eshop.blueprint_seat_bindings WHERE blueprint=b.id AND node_id=node;
   DELETE FROM eshop.spots WHERE id=s.id;
   CONTINUE;
  END IF;
  IF c->>'operation' IS DISTINCT FROM 'upsert' OR coalesce(node_index->node::text->>'kind','')<>'seat' THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_SEAT_CHANGE',DETAIL=c::text; END IF;
  IF NOT c ? 'productId' OR NOT c ? 'blocked' OR NOT c ? 'groupNodeId' OR NOT c ? 'selectionUnitId' THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INCOMPLETE_SEAT_CHANGE',DETAIL=c::text; END IF;
  assignment_mode:=coalesce(c->>'productAssignmentMode','override');
  IF assignment_mode NOT IN ('inherit','override') OR (doc->>'schemaVersion'='2' AND NOT c ? 'productAssignmentMode') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_PRODUCT_ASSIGNMENT_MODE'; END IF;
  product_id:=(c->>'productId')::bigint; group_id:=(c->>'groupNodeId')::uuid; unit_id:=(c->>'selectionUnitId')::uuid; blocked_value:=(c->>'blocked')::boolean;
  IF blocked_value IS NULL OR (product_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.products WHERE id=product_id AND occasion=b.occasion)) THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_PRODUCT',DETAIL=c::text; END IF;
  IF group_id IS NOT NULL AND coalesce(node_index->group_id::text->>'kind','') NOT IN ('group','table','furniture') THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_GROUP',DETAIL=c::text; END IF;
  IF unit_id IS DISTINCT FROM (unit_index->>node::text)::uuid THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_UNIT_MEMBERSHIP_MISMATCH',DETAIL=c::text; END IF;
  spot_id:=(c->>'spotId')::bigint;
  IF binding.node_id IS NOT NULL AND spot_id IS DISTINCT FROM binding.spot THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_SPOT_IDENTITY_CHANGED',DETAIL=c::text; END IF;
  IF spot_id IS NOT NULL THEN
   SELECT * INTO s FROM eshop.spots WHERE id=spot_id AND blueprint=b.id AND occasion=b.occasion;
   IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_SPOT_SCOPE_MISMATCH',DETAIL=c::text; END IF;
   IF (s.order_product_ticket IS NOT NULL OR (s.secret IS NOT NULL AND s.secret_expiration_time>statement_timestamp()))
    AND (s.product IS DISTINCT FROM product_id OR s.title IS DISTINCT FROM c->>'title'
     OR coalesce(binding.blocked,false) IS DISTINCT FROM blocked_value OR binding.selection_unit IS DISTINCT FROM unit_id OR binding.group_node IS DISTINCT FROM group_id OR binding.product_assignment_mode IS DISTINCT FROM assignment_mode) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_SEAT_PROTECTED',DETAIL=c::text; END IF;
   UPDATE eshop.spots SET product=product_id,title=c->>'title',updated_at=now() WHERE id=spot_id
    AND (product IS DISTINCT FROM product_id OR title IS DISTINCT FROM c->>'title');
  ELSE
   INSERT INTO eshop.spots(blueprint,occasion,product,title) VALUES(b.id,b.occasion,product_id,c->>'title') RETURNING id INTO spot_id;
  END IF;
  INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot,selection_unit,group_node,blocked,product_assignment_mode)
   VALUES(b.id,node,spot_id,unit_id,group_id,blocked_value,assignment_mode)
   ON CONFLICT(blueprint,node_id) DO UPDATE SET selection_unit=excluded.selection_unit,group_node=excluded.group_node,blocked=excluded.blocked,product_assignment_mode=excluded.product_assignment_mode;
 END LOOP;
 IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings sb WHERE sb.blueprint=b.id AND coalesce(node_index->sb.node_id::text->>'kind','')<>'seat')
  OR (SELECT count(*) FROM eshop.blueprint_seat_bindings sb WHERE sb.blueprint=b.id)<>seat_count
  OR EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings sb WHERE sb.blueprint=b.id AND sb.selection_unit IS DISTINCT FROM
   (unit_index->>sb.node_id::text)::uuid) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_BINDING_SET_MISMATCH'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings sb WHERE sb.blueprint=b.id AND sb.group_node IS NOT NULL AND coalesce(node_index->sb.group_node::text->>'kind','') NOT IN ('group','table','furniture')) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_GROUP'; END IF;
 FOR c IN SELECT * FROM jsonb_array_elements(coalesce(p_blueprint->'groupProductChanges','[]')) LOOP
  IF NOT c ? 'productId' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INCOMPLETE_GROUP_CHANGE',DETAIL=c::text; END IF;
  node:=(c->>'groupNodeId')::uuid; product_id:=(c->>'productId')::bigint;
  IF coalesce(node_index->node::text->>'kind','') NOT IN ('table','group','furniture')
   OR (product_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.products WHERE id=product_id AND occasion=b.occasion)) THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_GROUP_PRODUCT',DETAIL=c::text; END IF;
  DELETE FROM eshop.blueprint_group_products WHERE blueprint=b.id AND group_node=node;
  IF product_id IS NOT NULL THEN INSERT INTO eshop.blueprint_group_products VALUES(b.id,node,product_id); END IF;
 END LOOP;
 DELETE FROM eshop.blueprint_group_products gp WHERE blueprint=b.id AND NOT node_index ? gp.group_node::text;
 IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings sb JOIN eshop.spots s ON s.id=sb.spot LEFT JOIN eshop.blueprint_group_products gp ON gp.blueprint=sb.blueprint AND gp.group_node=sb.group_node WHERE sb.blueprint=b.id AND sb.product_assignment_mode='inherit' AND (sb.group_node IS NULL OR gp.product IS NULL OR s.product IS DISTINCT FROM gp.product)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INHERITED_PRODUCT_MISMATCH'; END IF;
 FOR c IN SELECT * FROM jsonb_array_elements(coalesce(p_blueprint->'areaBindingChanges','[]')) LOOP
  node:=(c->>'nodeId')::uuid; product_id:=(c->>'productId')::bigint;
  DELETE FROM eshop.blueprint_area_bindings WHERE blueprint=b.id AND node_id=node;
  IF c->>'operation'='delete' THEN CONTINUE; END IF;
  IF c->>'operation' IS DISTINCT FROM 'upsert' OR coalesce(node_index->node::text->>'kind','')<>'capacityArea'
   OR NOT EXISTS(SELECT 1 FROM eshop.product_inventory_contexts pic JOIN eshop.products p ON p.id=pic.product JOIN public.inventory_contexts ic ON ic.id=pic.inventory_context JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool WHERE pic.product=product_id AND pic.inventory_context=(c->>'inventoryContextId')::bigint AND p.occasion=b.occasion AND ip.occasion=b.occasion) THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_AREA_BINDING',DETAIL=c::text; END IF;
  IF c ? 'capacity' THEN
   capacity_int:=(c->>'capacity')::bigint;
   IF capacity_int IS NULL OR capacity_int<0 OR capacity_int>1000000 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_CAPACITY'; END IF;
   SELECT ip.* INTO pool FROM public.inventory_pools ip JOIN public.inventory_contexts ic ON ic.inventory_pool=ip.id WHERE ic.id=(c->>'inventoryContextId')::bigint;
   PERFORM public.update_inventory_pool_bundle(jsonb_build_object('pool',to_jsonb(pool)||jsonb_build_object('sellable_capacity',capacity_int)));
  END IF;
  INSERT INTO eshop.blueprint_area_bindings VALUES(b.id,node,(c->>'inventoryContextId')::bigint,product_id);
 END LOOP;
 IF EXISTS(SELECT 1 FROM eshop.blueprint_area_bindings ab WHERE blueprint=b.id AND coalesce(node_index->ab.node_id::text->>'kind','')<>'capacityArea') THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_AREA_BINDING_SET_MISMATCH'; END IF;
 UPDATE eshop.blueprints SET layout=doc,layout_revision=layout_revision+1,updated_at=now(),title=coalesce(p_blueprint->>'title',title) WHERE id=b.id RETURNING * INTO b;
 result:=public.blueprint_binding_projection_internal(b.id)||jsonb_build_object('code',200,'blueprint_id',b.id,'layout_revision',b.layout_revision,
  'document_hash',encode(extensions.digest(convert_to(doc::text,'UTF8'),'sha256'),'hex'));
 IF octet_length(result::text)>4194304 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_RESULT_TOO_LARGE'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.save_blueprint_layout_impl_internal(jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;

-- Runtime entry always enforces occasion writability, including demo read-only.
CREATE OR REPLACE FUNCTION public.save_blueprint_layout_internal_v1(p_blueprint jsonb)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.save_blueprint_layout_impl_internal(p_blueprint,false);
$$;
REVOKE ALL ON FUNCTION public.save_blueprint_layout_internal_v1(jsonb) FROM PUBLIC,anon,authenticated,service_role;

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
  INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot,selection_unit,group_node,blocked,product_assignment_mode)
  SELECT bp.new_id,node_map.new_id,sp.new_id,unit_map.new_id,group_map.new_id,sb.blocked,sb.product_assignment_mode
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

-- Unit-scoped preparation uses the existing ticket preview admission policy.
CREATE OR REPLACE FUNCTION public.admit_occasion_setup_blueprint_resources_v1(p_draft uuid,p_bytes bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE d public.occasion_setup_drafts;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_draft;
 IF d.id IS NULL OR auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(d.unit) OR public.get_is_manager_on_unit(d.unit)) THEN
  RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 IF d.data ? 'finalizedOccasion' OR p_bytes IS NULL OR p_bytes<=0 THEN RAISE invalid_parameter_value USING MESSAGE='Invalid draft preview'; END IF;
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('ticket.preview',d.unit,d.organization),
  jsonb_build_object('actor',auth.uid(),'unit',d.unit,'organization',d.organization),jsonb_build_object('ticket.preview.payload.bytes',p_bytes));
 RETURN public.bound_document_data_v1('{}');
END $$;
REVOKE ALL ON FUNCTION public.admit_occasion_setup_blueprint_resources_v1(uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.admit_occasion_setup_blueprint_resources_v1(uuid,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_occasion_setup_blueprint_resources(p_draft uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE d public.occasion_setup_drafts; doc jsonb; source_id bigint; resource_occasion bigint; resource_unit bigint;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_draft;
 IF d.id IS NULL OR auth.uid() IS NULL OR NOT (public.get_is_editor_on_unit(d.unit) OR public.get_is_manager_on_unit(d.unit)) THEN RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 source_id:=(d.data->>'sourceId')::bigint;
 IF source_id IS NOT NULL AND (NOT public.can_copy_occasion_source(source_id) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=source_id AND organization=d.organization)) THEN RAISE insufficient_privilege USING MESSAGE='Copy source denied'; END IF;
 doc:=coalesce(d.data#>'{blueprintLayoutDraft,layout}',jsonb_build_object('nodes','[]'::jsonb,'defaultTextStyle',jsonb_build_object('fontId',
  'builtin:futura-pt-book:571b3803a43928d59f695acb37e73c9dc89666f5d541183e2b53c19c8986ab44')));
 IF source_id IS NULL OR EXISTS(SELECT 1 FROM public.blueprint_image_assets WHERE unit=d.unit AND asset_ref=doc#>>'{background,assetRef}' AND state='ready') THEN
  resource_unit:=d.unit;
 ELSE resource_occasion:=source_id; END IF;
 RETURN public.bound_document_data_v1(jsonb_build_object('resources',public.blueprint_layout_resources_internal(doc,resource_occasion,resource_unit)));
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_setup_blueprint_resources(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_setup_blueprint_resources(uuid) TO authenticated;

-- Copy shared inventory configuration through its existing command owners.
-- Only empty target inventory is created; source holds/bookings never enter it.
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
REVOKE ALL ON FUNCTION public.copy_setup_area_inventory_internal(jsonb,jsonb,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.materialize_setup_area_inventory_internal(p_area jsonb,p_product bigint,p_target bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE bundle jsonb; pool_id bigint; context_id bigint; capacity_value bigint; linked jsonb;
BEGIN
 PERFORM public.check_is_editor_order_on_occasion(p_target);
 IF NOT EXISTS(SELECT 1 FROM eshop.products WHERE id=p_product AND occasion=p_target) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_SETUP_PRODUCT_NOT_IN_FORM'; END IF;
 capacity_value:=(p_area->>'capacity')::bigint;
 IF capacity_value IS NULL OR capacity_value<0 OR capacity_value>2147483647 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_SETUP_AREA_CAPACITY_REQUIRED'; END IF;
 bundle:=public.update_inventory_pool_bundle(jsonb_build_object('pool',jsonb_build_object('occasion',p_target,'title','Standing','type','generic','sellable_capacity',capacity_value,'data','{}'::jsonb),
  'contexts',jsonb_build_array(jsonb_build_object('title','Standing','order',0,'data','{}'::jsonb))));
 pool_id:=(bundle#>>'{pool,id}')::bigint;
 SELECT id INTO context_id FROM public.inventory_contexts WHERE inventory_pool=pool_id ORDER BY id LIMIT 1;
 PERFORM public.update_resource(jsonb_build_object('inventory_pool',pool_id,'title','Standing','capacity',capacity_value,'booking_rules','{}'::jsonb));
 SELECT coalesce(jsonb_agg(jsonb_build_object('inventory_context_id',inventory_context,'quantity',quantity)),'[]') INTO linked FROM eshop.product_inventory_contexts WHERE product=p_product;
 PERFORM public.update_product_inventory_contexts_internal_v1(p_product,linked||jsonb_build_array(jsonb_build_object('inventory_context_id',context_id,'quantity',1)));
 RETURN context_id;
END $$;
REVOKE ALL ON FUNCTION public.materialize_setup_area_inventory_internal(jsonb,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.materialize_setup_blueprint_layout_internal(p_draft jsonb,p_product_map jsonb,p_source bigint,p_target bigint,p_unit bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE doc jsonb:=p_draft->'layout'; ids jsonb:='{}'; seat jsonb; grp jsonb; area jsonb; product_id bigint; context_id bigint;
 seats jsonb:='[]'; groups jsonb:='[]'; areas jsonb:='[]'; result jsonb; context_map jsonb;
BEGIN
 PERFORM public.check_is_editor_on_occasion(p_target);
 IF p_source IS NOT NULL AND NOT public.can_copy_occasion_source(p_source) THEN RAISE insufficient_privilege USING MESSAGE='Copy source denied'; END IF;
 IF jsonb_typeof(doc)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_draft) k WHERE k NOT IN('layout','seatBindings','groupProducts','areaBindings')) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_SETUP_INVALID_DRAFT'; END IF;
 IF p_source IS NOT NULL THEN
  WITH RECURSIVE records(value) AS (SELECT doc UNION ALL SELECT child.value FROM records CROSS JOIN LATERAL (
   SELECT item.value FROM jsonb_each(CASE WHEN jsonb_typeof(records.value)='object' THEN records.value ELSE '{}' END) item
   UNION ALL SELECT item.value FROM jsonb_array_elements(CASE WHEN jsonb_typeof(records.value)='array' THEN records.value ELSE '[]' END) item) child)
  SELECT coalesce(jsonb_object_agg(value->>'id',extensions.gen_random_uuid()),'{}') INTO ids FROM records WHERE jsonb_typeof(value)='object' AND value ? 'id';
  doc:=public.remap_blueprint_layout_ids_internal(doc,ids);
 END IF;
 -- A new draft may use an authenticated unit-owned processed background.
 IF doc#>>'{background,assetRef}' LIKE 'image:%' THEN
  IF EXISTS(SELECT 1 FROM public.blueprint_image_assets WHERE unit=p_unit AND asset_ref=doc#>>'{background,assetRef}' AND state='ready') THEN
   PERFORM public.copy_blueprint_unit_image_resources_internal(p_unit,p_target,doc);
  ELSIF p_source IS NOT NULL THEN
   PERFORM public.copy_blueprint_image_resources_internal(p_source,p_target,doc);
  ELSE RAISE check_violation USING MESSAGE='BLUEPRINT_IMAGE_RESOURCE_NOT_READY'; END IF;
 END IF;
 FOR seat IN SELECT value FROM jsonb_array_elements(coalesce(p_draft->'seatBindings','[]')) LOOP
  IF seat ? 'spotId' OR EXISTS(SELECT 1 FROM jsonb_object_keys(seat) k WHERE k NOT IN('nodeId','productId','title','groupNodeId','selectionUnitId','blocked','productAssignmentMode')) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_SETUP_BINDING_IDENTITY'; END IF;
  product_id:=(p_product_map->>(seat->>'productId'))::bigint;
  IF seat->>'productId' IS NOT NULL AND product_id IS NULL THEN RAISE check_violation USING MESSAGE='BLUEPRINT_SETUP_PRODUCT_NOT_IN_FORM'; END IF;
  seats:=seats||jsonb_build_array(seat||jsonb_build_object('nodeId',coalesce(ids->> (seat->>'nodeId'),seat->>'nodeId'),
   'productAssignmentMode',coalesce(seat->>'productAssignmentMode','override'),'groupNodeId',coalesce(ids->>(seat->>'groupNodeId'),seat->>'groupNodeId'),'selectionUnitId',coalesce(ids->>(seat->>'selectionUnitId'),seat->>'selectionUnitId'),
   'spotId',NULL,'productId',product_id,'operation','upsert'));
 END LOOP;
 FOR grp IN SELECT value FROM jsonb_array_elements(coalesce(p_draft->'groupProducts','[]')) LOOP
  product_id:=(p_product_map->>(grp->>'productId'))::bigint;
  IF grp->>'productId' IS NOT NULL AND product_id IS NULL THEN RAISE check_violation USING MESSAGE='BLUEPRINT_SETUP_PRODUCT_NOT_IN_FORM'; END IF;
  groups:=groups||jsonb_build_array(jsonb_build_object('groupNodeId',coalesce(ids->>(grp->>'groupNodeId'),grp->>'groupNodeId'),'productId',product_id));
 END LOOP;
 context_map:=public.copy_setup_area_inventory_internal(coalesce(p_draft->'areaBindings','[]'),p_product_map,p_source,p_target);
 FOR area IN SELECT value FROM jsonb_array_elements(coalesce(p_draft->'areaBindings','[]')) LOOP
  product_id:=(p_product_map->>(area->>'productId'))::bigint;
  IF product_id IS NULL THEN RAISE check_violation USING MESSAGE='BLUEPRINT_SETUP_PRODUCT_NOT_IN_FORM'; END IF;
  IF area->>'inventoryContextId' IS NOT NULL THEN context_id:=(context_map->>(area->>'inventoryContextId'))::bigint;
  ELSE context_id:=public.materialize_setup_area_inventory_internal(area,product_id,p_target); END IF;
  areas:=areas||jsonb_build_array(jsonb_build_object('nodeId',coalesce(ids->>(area->>'nodeId'),area->>'nodeId'),'productId',product_id,'inventoryContextId',context_id,'operation','upsert'));
 END LOOP;
 result:=public.save_blueprint_layout_internal_v1(jsonb_build_object('occasion',p_target,'expected_layout_revision',0,'title','Blueprint','layout',doc,'seatChanges',seats,'groupProductChanges',groups,'areaBindingChanges',areas));
 RETURN (result->>'blueprint_id')::bigint;
END $$;
REVOKE ALL ON FUNCTION public.materialize_setup_blueprint_layout_internal(jsonb,jsonb,bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
