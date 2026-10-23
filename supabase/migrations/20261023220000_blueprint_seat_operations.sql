-- Shared seat lifecycle, atomic block selection and canonical aggregate save.
CREATE OR REPLACE FUNCTION public.lock_blueprint_inventory_internal(p_occasion bigint,p_blueprint bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 -- Keep the existing financial resource lock ordering, before spot row locks.
 PERFORM 1 FROM eshop.products WHERE occasion=p_occasion ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_pools WHERE id IN(SELECT ic.inventory_pool FROM public.inventory_contexts ic
  JOIN eshop.product_inventory_contexts pic ON pic.inventory_context=ic.id JOIN eshop.products p ON p.id=pic.product WHERE p.occasion=p_occasion) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_contexts WHERE id IN(SELECT pic.inventory_context FROM eshop.product_inventory_contexts pic JOIN eshop.products p ON p.id=pic.product WHERE p.occasion=p_occasion) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.spots WHERE blueprint=p_blueprint ORDER BY id FOR UPDATE;
END $$;
REVOKE ALL ON FUNCTION public.lock_blueprint_inventory_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Lifecycle facts shared by the current UI reader and bounded operator views.
-- `blocked` is a binding setting, never a synonym for an order or temporary hold.
CREATE OR REPLACE FUNCTION public.blueprint_spot_facts_internal(p_occasion bigint,p_ids bigint[],p_at timestamptz DEFAULT statement_timestamp())
RETURNS TABLE(id bigint,title text,product bigint,order_product_ticket bigint,state text,is_protected boolean)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT s.id,s.title,s.product,s.order_product_ticket,CASE WHEN t.state='used' THEN 'used'
  WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
  WHEN s.secret IS NOT NULL AND s.secret_expiration_time>p_at THEN 'selected' ELSE 'available' END,
  s.order_product_ticket IS NOT NULL OR coalesce(s.secret IS NOT NULL AND s.secret_expiration_time>p_at,false)
 FROM eshop.spots s LEFT JOIN eshop.order_product_ticket opt ON opt.id=s.order_product_ticket
 LEFT JOIN eshop.tickets t ON t.id=opt.ticket WHERE s.occasion=p_occasion AND s.id=ANY(p_ids)
$$;
REVOKE ALL ON FUNCTION public.blueprint_spot_facts_internal(bigint,bigint[],timestamptz) FROM PUBLIC,anon,authenticated,service_role;

-- Enforce UI's atomic block-selection rule at the aggregate owner too. Other
-- geometry edits remain local until the ordinary Save/Cancel boundary is used.
CREATE OR REPLACE FUNCTION public.check_blueprint_block_changes_internal(p_blueprint bigint,p_layout jsonb,p_changes jsonb)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE incomplete boolean;protected_member boolean;
BEGIN
 -- Parse incoming changes and selection membership once, then join by identity.
 -- A whole-plan UI save must not scan every unit/JSON change for every member.
 WITH changes AS MATERIALIZED (
  SELECT (c->>'nodeId')::uuid node,(c->>'blocked')::boolean blocked,c->>'operation' operation
  FROM jsonb_array_elements(coalesce(p_changes,'[]'))c
 ), members AS MATERIALIZED (
  SELECT (u->>'id')::uuid unit,member::uuid node FROM jsonb_array_elements(coalesce(p_layout->'selectionUnits','[]'))u
  CROSS JOIN LATERAL jsonb_array_elements_text(u->'nodeIds')member
 ), targets AS MATERIALIZED (
  SELECT DISTINCT m.unit,c.blocked FROM changes c
  JOIN eshop.blueprint_seat_bindings old ON old.blueprint=p_blueprint AND old.node_id=c.node
  JOIN members m ON m.node=c.node
  WHERE c.operation='upsert' AND coalesce(old.blocked,false) IS DISTINCT FROM c.blocked
 )
 SELECT coalesce(bool_or(c.node IS NULL OR c.operation IS DISTINCT FROM 'upsert' OR c.blocked IS DISTINCT FROM t.blocked),false),
  coalesce(bool_or(s.order_product_ticket IS NOT NULL OR s.secret IS NOT NULL AND s.secret_expiration_time>clock_timestamp()),false)
 INTO incomplete,protected_member
 FROM targets t JOIN members m ON m.unit=t.unit LEFT JOIN changes c ON c.node=m.node
 LEFT JOIN eshop.blueprint_seat_bindings b ON b.blueprint=p_blueprint AND b.node_id=m.node
 LEFT JOIN eshop.spots s ON s.id=b.spot;
 IF incomplete THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INCOMPLETE_BLOCK_SELECTION_UNIT'; END IF;
 IF protected_member THEN RAISE check_violation USING MESSAGE='BLUEPRINT_SEAT_PROTECTED'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_blueprint_block_changes_internal(bigint,jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.check_blueprint_admin_scope_internal(p_occasion bigint,p_organization bigint,p_unit bigint,p_write boolean,p_lock boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,false,p_lock);
 IF p_write AND public.can_write_blueprints(p_occasion) IS DISTINCT FROM TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='blueprint editor required'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_blueprint_admin_scope_internal(bigint,bigint,bigint,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.blueprint_admin_seat_rows_internal(p_occasion bigint,p_blueprint bigint,p_ids bigint[])
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('spotId',f.id,'nodeId',b.node_id,'title',f.title,'productId',f.product,
  'productTitle',p.title,'selectionUnitId',b.selection_unit,'groupNodeId',b.group_node,'blocked',b.blocked,
  'state',f.state,'canBlock',NOT f.is_protected) ORDER BY f.id),'[]')
 FROM eshop.blueprint_seat_bindings b JOIN public.blueprint_spot_facts_internal(p_occasion,p_ids) f ON f.id=b.spot
 LEFT JOIN eshop.products p ON p.id=f.product AND p.occasion=p_occasion WHERE b.blueprint=p_blueprint
$$;
REVOKE ALL ON FUNCTION public.blueprint_admin_seat_rows_internal(bigint,bigint,bigint[]) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_blueprint_seats(p_occasion bigint,p_organization bigint,p_unit bigint,p_blueprint bigint DEFAULT NULL,p_after bigint DEFAULT NULL,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE bp bigint;meta jsonb;ids bigint[];next_id bigint;rows jsonb;
BEGIN
 IF p_limit IS NULL OR p_limit<1 OR p_limit>100 OR p_after IS NOT NULL AND p_after<1 THEN RAISE invalid_parameter_value USING MESSAGE='invalid seat page'; END IF;
 PERFORM public.check_blueprint_admin_scope_internal(p_occasion,p_organization,p_unit,false,true);
 SELECT id,jsonb_build_object('id',id,'title',title,'layoutRevision',layout_revision) INTO bp,meta
 FROM eshop.blueprints WHERE occasion=p_occasion AND (p_blueprint IS NULL OR id=p_blueprint) AND layout IS NOT NULL ORDER BY id LIMIT 1 FOR SHARE;
 IF bp IS NULL THEN RAISE insufficient_privilege USING MESSAGE='canonical blueprint unavailable'; END IF;
 SELECT coalesce(array_agg(spot ORDER BY spot),'{}'::bigint[]) INTO ids FROM (
  SELECT b.spot FROM eshop.blueprint_seat_bindings b JOIN eshop.spots s ON s.id=b.spot AND s.occasion=p_occasion
  WHERE b.blueprint=bp AND (p_after IS NULL OR b.spot>p_after) ORDER BY b.spot LIMIT p_limit+1) selected;
 IF cardinality(ids)>p_limit THEN ids:=ids[1:p_limit];next_id:=ids[p_limit]; END IF;
 rows:=public.blueprint_admin_seat_rows_internal(p_occasion,bp,ids);
 IF octet_length(rows::text)>1048576 THEN RAISE program_limit_exceeded USING MESSAGE='seat page exceeds payload limit'; END IF;
 PERFORM public.check_blueprint_admin_scope_internal(p_occasion,p_organization,p_unit,false,true);
 RETURN jsonb_build_object('occasionId',p_occasion,'blueprint',meta,'seats',rows,'nextCursor',next_id,'readAt',statement_timestamp());
END $$;
REVOKE ALL ON FUNCTION public.get_blueprint_seats(bigint,bigint,bigint,bigint,bigint,integer) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_blueprint_seats(bigint,bigint,bigint,bigint,bigint,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.blueprint_block_selection_internal(p_occasion bigint,p_blueprint bigint,p_spots bigint[])
RETURNS bigint[] LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE ids bigint[];
BEGIN
 IF coalesce(cardinality(p_spots),0)=0 OR cardinality(p_spots)>100 OR array_position(p_spots,NULL) IS NOT NULL
  OR (SELECT count(DISTINCT x) FROM unnest(p_spots)x)<>cardinality(p_spots) THEN RAISE invalid_parameter_value USING MESSAGE='invalid seat selection'; END IF;
 IF (SELECT count(*) FROM eshop.blueprint_seat_bindings b JOIN eshop.spots s ON s.id=b.spot AND s.occasion=p_occasion
  WHERE b.blueprint=p_blueprint AND b.spot=ANY(p_spots))<>cardinality(p_spots) THEN RAISE insufficient_privilege USING MESSAGE='seat selection unavailable'; END IF;
 SELECT array_agg(DISTINCT member ORDER BY member) INTO ids FROM unnest(p_spots) selected
 CROSS JOIN LATERAL unnest(public.blueprint_selection_unit_spots_internal(selected))member;
 IF cardinality(ids)>1000 THEN RAISE program_limit_exceeded USING MESSAGE='expanded selection exceeds operation limit'; END IF;
 IF (SELECT count(*) FROM eshop.blueprint_seat_bindings b JOIN eshop.spots s ON s.id=b.spot AND s.occasion=p_occasion
  WHERE b.blueprint=p_blueprint AND b.spot=ANY(ids))<>cardinality(ids) THEN RAISE insufficient_privilege USING MESSAGE='expanded selection unavailable'; END IF;
 RETURN ids;
END $$;
REVOKE ALL ON FUNCTION public.blueprint_block_selection_internal(bigint,bigint,bigint[]) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.preview_blueprint_seat_block(p_occasion bigint,p_organization bigint,p_unit bigint,p_blueprint bigint,p_spots bigint[],p_blocked boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ids bigint[];rev bigint;rows jsonb;
BEGIN
 IF p_blocked IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='block target required'; END IF;
 PERFORM public.check_blueprint_admin_scope_internal(p_occasion,p_organization,p_unit,true,true);
 SELECT layout_revision INTO rev FROM eshop.blueprints WHERE id=p_blueprint AND occasion=p_occasion AND layout IS NOT NULL FOR SHARE;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='canonical blueprint unavailable'; END IF;
 ids:=public.blueprint_block_selection_internal(p_occasion,p_blueprint,p_spots);
 rows:=public.blueprint_admin_seat_rows_internal(p_occasion,p_blueprint,ids);
 IF octet_length(rows::text)>1048576 THEN RAISE program_limit_exceeded USING MESSAGE='seat preview exceeds payload limit'; END IF;
 PERFORM public.check_blueprint_admin_scope_internal(p_occasion,p_organization,p_unit,true,true);
 RETURN jsonb_build_object('occasionId',p_occasion,'blueprintId',p_blueprint,'layoutRevision',rev,'requestedSpotIds',p_spots,
  'affectedSpotIds',ids,'blocked',p_blocked,'seats',rows,'canApply',NOT EXISTS(SELECT 1 FROM jsonb_array_elements(rows)r WHERE (r->>'canBlock')::boolean IS DISTINCT FROM true),'readAt',statement_timestamp());
END $$;
REVOKE ALL ON FUNCTION public.preview_blueprint_seat_block(bigint,bigint,bigint,bigint,bigint[],boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.preview_blueprint_seat_block(bigint,bigint,bigint,bigint,bigint[],boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.block_blueprint_seats(p_occasion bigint,p_organization bigint,p_unit bigint,p_blueprint bigint,p_spots bigint[],p_affected_spots bigint[],p_expected_revision bigint,p_blocked boolean,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE actor uuid:=auth.uid();started jsonb;fingerprint text;bp eshop.blueprints;ids bigint[];changes jsonb;request jsonb;result jsonb;users uuid[];reason text;
BEGIN
 PERFORM public.check_blueprint_admin_scope_internal(p_occasion,p_organization,p_unit,true);
 IF p_command_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<0 OR p_blocked IS NULL
  OR coalesce(cardinality(p_affected_spots),0)=0 OR cardinality(p_affected_spots)>1000 OR array_position(p_affected_spots,NULL) IS NOT NULL THEN RAISE invalid_parameter_value USING MESSAGE='confirmed block intention required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=p_blueprint AND occasion=p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='blueprint unavailable'; END IF;
 fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,'blueprint',p_blueprint,'spots',p_spots,
  'affected',p_affected_spots,'revision',p_expected_revision,'blocked',p_blocked)::text,'UTF8'),'sha256'),'hex');
 started:=public.begin_client_mutation_v1(p_command_id,'inventory.blueprint.block',p_occasion,actor,fingerprint);
 IF started->>'disposition'='replay' THEN result:=started->'response';
 ELSE
  PERFORM public.lock_blueprint_scope_internal(ARRAY[p_occasion]);
  -- Same product/blueprint lock order as the full aggregate owner.
  PERFORM 1 FROM eshop.products WHERE occasion=p_occasion ORDER BY id FOR UPDATE;
  SELECT * INTO bp FROM eshop.blueprints WHERE id=p_blueprint AND occasion=p_occasion FOR UPDATE;
  IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='blueprint unavailable'; END IF;
  BEGIN
   IF bp.layout_revision<>p_expected_revision OR bp.layout IS NULL THEN RAISE check_violation USING MESSAGE='BLUEPRINT_REVISION_CONFLICT'; END IF;
   ids:=public.blueprint_block_selection_internal(p_occasion,p_blueprint,p_spots);
   IF ids IS DISTINCT FROM ARRAY(SELECT x FROM unnest(p_affected_spots)x ORDER BY x) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_SELECTION_CHANGED'; END IF;
   PERFORM public.lock_blueprint_inventory_internal(p_occasion,p_blueprint);
   IF EXISTS(SELECT 1 FROM public.blueprint_spot_facts_internal(p_occasion,ids,clock_timestamp()) WHERE is_protected) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_SEAT_PROTECTED'; END IF;
   SELECT coalesce(jsonb_agg(jsonb_build_object('operation','upsert','blocked',p_blocked,'nodeId',b.node_id,
    'spotId',b.spot,'productId',s.product,'title',s.title,'groupNodeId',b.group_node,'selectionUnitId',b.selection_unit,
    'productAssignmentMode',b.product_assignment_mode) ORDER BY b.spot),'[]') INTO changes
   FROM eshop.blueprint_seat_bindings b JOIN eshop.spots s ON s.id=b.spot WHERE b.blueprint=p_blueprint AND b.spot=ANY(ids);
   request:=jsonb_build_object('id',bp.id,'occasion',bp.occasion,'organization',bp.organization,'title',bp.title,
    'expected_layout_revision',p_expected_revision,'layout',bp.layout,'textResourceIds',to_jsonb(public.blueprint_text_resource_ids_internal(bp.layout,bp.occasion)),
    'seatChanges',changes,'groupProductChanges','[]'::jsonb,'areaBindingChanges','[]'::jsonb);
   result:=public.save_blueprint_layout_internal_v1(request);
  EXCEPTION WHEN check_violation OR raise_exception OR invalid_text_representation OR not_null_violation OR unique_violation OR foreign_key_violation THEN
   GET STACKED DIAGNOSTICS reason=MESSAGE_TEXT;
   result:=public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,jsonb_build_object('reason',reason,'layoutRevision',bp.layout_revision));
  END;
  IF result->>'status' IS NULL THEN
   SELECT coalesce(array_agg(ou."user"),'{}'::uuid[]) INTO users FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
   result:=public.complete_private_inventory_mutation_v1(p_command_id,p_occasion,'inventory.blueprint.block',
    jsonb_build_array(jsonb_build_object('entityType','blueprint','entityId',bp.id,'operation','update','safeLabel',left(bp.title,240),'changedFields',jsonb_build_array('blocked'))),users,
    jsonb_build_object('blueprintId',bp.id,'layoutRevision',(result->>'layout_revision')::bigint,'affectedSpotIds',ids,'blocked',p_blocked));
  END IF;
 END IF;
 PERFORM public.check_blueprint_admin_scope_internal(p_occasion,p_organization,p_unit,true,true);
 IF NOT EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=p_blueprint AND occasion=p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='blueprint unavailable'; END IF;
 RETURN result-'sync';
END $$;
REVOKE ALL ON FUNCTION public.block_blueprint_seats(bigint,bigint,bigint,bigint,bigint[],bigint[],bigint,boolean,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.block_blueprint_seats(bigint,bigint,bigint,bigint,bigint[],bigint[],bigint,boolean,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.save_blueprint_layout_impl_internal(p_blueprint jsonb,p_reviewed_demo boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE b eshop.blueprints; c jsonb; binding eshop.blueprint_seat_bindings; s eshop.spots;
 node uuid; group_id uuid; unit_id uuid; product_id bigint; spot_id bigint; blocked_value boolean; assignment_mode text;
 pool public.inventory_pools; capacity_int bigint; physical_supply bigint;
 node_index jsonb; unit_index jsonb; seat_count bigint; text_ids text[]:='{}';
 doc jsonb:=p_blueprint->'layout'; result jsonb; expected bigint; issue text; all_seats uuid[]; supplied uuid[];
BEGIN
 IF nullif(p_blueprint->>'id','') IS NULL THEN
  IF public.can_write_blueprints((p_blueprint->>'occasion')::bigint) IS NOT TRUE THEN
   RAISE insufficient_privilege USING MESSAGE='blueprint editor required'; END IF;
  INSERT INTO eshop.blueprints(occasion,organization,title) SELECT id,organization,p_blueprint->>'title' FROM public.occasions WHERE id=(p_blueprint->>'occasion')::bigint RETURNING * INTO b;
 ELSE
  SELECT * INTO b FROM eshop.blueprints WHERE id=(p_blueprint->>'id')::bigint;
  PERFORM 1 FROM eshop.products WHERE occasion=b.occasion ORDER BY id FOR UPDATE;
  SELECT * INTO b FROM eshop.blueprints WHERE id=(p_blueprint->>'id')::bigint FOR UPDATE;
 END IF;
 IF b.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_NOT_FOUND'; END IF;
 IF p_reviewed_demo AND public.is_demo_occasion(b.occasion) THEN
  IF NOT public.can_migrate_reviewed_legacy_blueprint(b.occasion) THEN RAISE insufficient_privilege USING MESSAGE='blueprint migration reviewer required'; END IF;
 ELSE
 IF public.can_write_blueprints(b.occasion) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='blueprint editor required'; END IF;
 END IF;
 IF p_reviewed_demo AND public.is_demo_occasion(b.occasion) THEN
  IF b.layout IS NOT NULL THEN RAISE check_violation USING MESSAGE='BLUEPRINT_MIGRATION_INITIAL_LAYOUT_REQUIRED'; END IF;
 ELSE PERFORM public.check_occasion_writable(b.occasion); END IF;
 expected:=(p_blueprint->>'expected_layout_revision')::bigint;
 IF expected IS NULL OR expected<>b.layout_revision THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_REVISION_CONFLICT'; END IF;
 PERFORM public.validate_blueprint_layout_internal(doc);
  PERFORM public.check_blueprint_text_resources_internal(doc,b.occasion);
  text_ids:=public.blueprint_text_resource_ids_internal(doc,b.occasion);
  IF jsonb_typeof(p_blueprint->'textResourceIds') IS DISTINCT FROM 'array'
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_blueprint->'textResourceIds') id WHERE jsonb_typeof(id)<>'string')
    OR (SELECT coalesce(array_agg(id ORDER BY id),'{}'::text[]) FROM jsonb_array_elements_text(p_blueprint->'textResourceIds') id) IS DISTINCT FROM text_ids
    THEN RAISE check_violation USING MESSAGE='BLUEPRINT_TEXT_RESOURCE_REFS_MISMATCH'; END IF;

 PERFORM public.check_blueprint_image_resource_internal(doc,b.occasion);
 PERFORM public.check_blueprint_bitmap_resources_internal(doc,b.occasion);
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
 PERFORM public.lock_blueprint_inventory_internal(b.occasion,b.id);
 PERFORM public.check_blueprint_block_changes_internal(b.id,doc,p_blueprint->'seatChanges');
 IF EXISTS(SELECT change->>'nodeId' FROM jsonb_array_elements(coalesce(p_blueprint->'seatChanges','[]')) change GROUP BY change->>'nodeId' HAVING count(*)>1) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_DUPLICATE_SEAT_CHANGE'; END IF;
 FOR c IN SELECT * FROM jsonb_array_elements(coalesce(p_blueprint->'seatChanges','[]')) LOOP
  node:=(c->>'nodeId')::uuid;
  SELECT * INTO binding FROM eshop.blueprint_seat_bindings WHERE blueprint=b.id AND node_id=node;
  IF c->>'operation'='delete' THEN
   IF binding.node_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_BINDING_NOT_FOUND',DETAIL=c::text; END IF;
   SELECT * INTO s FROM eshop.spots WHERE id=binding.spot;
   IF s.order_product_ticket IS NOT NULL OR (s.secret IS NOT NULL AND s.secret_expiration_time>clock_timestamp()) THEN
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
  IF assignment_mode NOT IN ('inherit','override') OR NOT c ? 'productAssignmentMode' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_PRODUCT_ASSIGNMENT_MODE'; END IF;
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
   IF (s.order_product_ticket IS NOT NULL OR (s.secret IS NOT NULL AND s.secret_expiration_time>clock_timestamp()))
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
 IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings sb JOIN eshop.spots bound_spot ON bound_spot.id=sb.spot LEFT JOIN eshop.blueprint_group_products gp ON gp.blueprint=sb.blueprint AND gp.group_node=sb.group_node WHERE sb.blueprint=b.id AND sb.product_assignment_mode='inherit' AND (sb.group_node IS NULL OR gp.product IS NULL)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INHERITED_PRODUCT_MISMATCH'; END IF;
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
   PERFORM public.update_inventory_pool_bundle(jsonb_build_object('pool',jsonb_build_object(
    'id',pool.id,'occasion',pool.occasion,'title',pool.title,
    'description',pool.description,'type',pool.type,'data',pool.data,
    'sellable_capacity',capacity_int)));
   -- The standing count owns the complete setup: a higher count must also
   -- provide real supply. Preserve existing resources/allocations and add only
   -- the missing quantity through the canonical inventory resource command.
   SELECT coalesce(sum(r.capacity),0) INTO physical_supply
    FROM public.resources r WHERE r.inventory_pool=pool.id;
   IF physical_supply<capacity_int THEN
    PERFORM public.update_resource(jsonb_build_object('inventory_pool',pool.id,
     'title',coalesce(pool.title,b.title),'capacity',capacity_int-physical_supply));
   END IF;
  END IF;
  INSERT INTO eshop.blueprint_area_bindings VALUES(b.id,node,(c->>'inventoryContextId')::bigint,product_id);
 END LOOP;
 IF EXISTS(SELECT 1 FROM eshop.blueprint_area_bindings ab WHERE blueprint=b.id AND coalesce(node_index->ab.node_id::text->>'kind','')<>'capacityArea') THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_AREA_BINDING_SET_MISMATCH'; END IF;
 UPDATE eshop.blueprints SET layout=doc,layout_text_resource_ids=text_ids,layout_revision=layout_revision+1,updated_at=now(),title=coalesce(p_blueprint->>'title',title) WHERE id=b.id RETURNING * INTO b;
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

CREATE OR REPLACE FUNCTION public.get_blueprint_for_edit(
    occasion_link TEXT
)
RETURNS JSONB
LANGUAGE plpgsql STABLE
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
    IF (SELECT can_read_orders(occasion_id)) <> TRUE THEN
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
        'aggregate_version',coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='blueprint' AND scope_type='occasion' AND scope_id=b.occasion AND aggregate_id=b.id::text),0),
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

    -- Shared lifecycle interpretation; only this released/private UI view
    -- includes the order-product relationship ID needed by its order controls.
    SELECT jsonb_agg(jsonb_build_object('id',f.id,'title',f.title,'product',f.product,
      'order_product_ticket',f.order_product_ticket,'state',f.state) ORDER BY f.id) INTO spotsData
    FROM public.blueprint_spot_facts_internal(occasion_id,ARRAY(SELECT jsonb_array_elements_text(valid_spots)::bigint)) f;

    -- Fetch all products of type "spot", "taxi", "food"
    SELECT jsonb_agg(jsonb_build_object(
        'id', p.id,
            'aggregate_version',coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='product' AND scope_type='occasion' AND scope_id=p.occasion AND aggregate_id=p.id::text),0),
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
