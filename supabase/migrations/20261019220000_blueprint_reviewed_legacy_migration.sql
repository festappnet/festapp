-- Explicit private reviewed migration; canonical runtime never reads legacy geometry.
BEGIN;
CREATE OR REPLACE FUNCTION public.begin_client_mutation_reviewed_impl_internal(p_command_id uuid, p_command_name text, p_occasion bigint, p_actor_id uuid, p_request_sha256 text, p_reviewed_demo boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_receipt public.client_mutation_receipts%ROWTYPE; v_inserted integer;
BEGIN
  IF p_reviewed_demo AND public.is_demo_occasion(p_occasion) THEN
    IF NOT EXISTS(SELECT 1 FROM public.occasion_users ou WHERE ou.occasion=p_occasion AND ou."user"=auth.uid() AND (ou.is_editor OR ou.is_manager)) THEN
      RAISE insufficient_privilege USING MESSAGE='blueprint migration reviewer required'; END IF;
  ELSE PERFORM public.check_occasion_writable(p_occasion); END IF;
  IF p_command_id IS NULL OR p_actor_id IS NULL OR p_actor_id IS DISTINCT FROM auth.uid() THEN
    RAISE insufficient_privilege USING MESSAGE='authenticated command actor required';
  END IF;
  IF p_command_name !~ '^[a-z][a-z0-9_.]{2,95}$'
     OR p_request_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid mutation receipt metadata';
  END IF;
  INSERT INTO public.client_mutation_receipts
    (command_id,command_name,occasion,actor_id,request_sha256)
  VALUES (p_command_id,p_command_name,p_occasion,p_actor_id,p_request_sha256)
  ON CONFLICT (command_id) DO NOTHING;
  GET DIAGNOSTICS v_inserted=ROW_COUNT;
  SELECT * INTO STRICT v_receipt FROM public.client_mutation_receipts
    WHERE command_id=p_command_id FOR UPDATE;
  IF v_receipt.command_name IS DISTINCT FROM p_command_name
     OR v_receipt.occasion IS DISTINCT FROM p_occasion
     OR v_receipt.actor_id IS DISTINCT FROM p_actor_id
     OR v_receipt.request_sha256 IS DISTINCT FROM p_request_sha256 THEN
    RAISE invalid_parameter_value USING MESSAGE='command id was already used with different request data';
  END IF;
  IF v_receipt.status='completed' THEN
    RETURN jsonb_build_object('disposition','replay','response',v_receipt.response);
  ELSIF v_receipt.status='expired' THEN
    RETURN jsonb_build_object('disposition','replay',
      'response',public.expired_client_mutation_response_v1(v_receipt));
  END IF;
  IF v_inserted<>1 THEN RAISE serialization_failure
    USING MESSAGE='incomplete mutation receipt cannot be resumed'; END IF;
  RETURN jsonb_build_object('disposition','claimed');
END; $function$;
REVOKE ALL ON FUNCTION public.begin_client_mutation_reviewed_impl_internal(uuid,text,bigint,uuid,text,boolean) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.begin_client_mutation_v1(p_command_id uuid,p_command_name text,p_occasion bigint,p_actor_id uuid,p_request_sha256 text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.begin_client_mutation_reviewed_impl_internal(p_command_id,p_command_name,p_occasion,p_actor_id,p_request_sha256,false);
$$;

CREATE OR REPLACE FUNCTION public.save_blueprint_layout_impl_internal(p_blueprint jsonb,p_reviewed_demo boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE b eshop.blueprints; c jsonb; binding eshop.blueprint_seat_bindings; s eshop.spots;
 node uuid; group_id uuid; unit_id uuid; product_id bigint; spot_id bigint; blocked_value boolean;
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
     OR coalesce(binding.blocked,false) IS DISTINCT FROM blocked_value OR binding.selection_unit IS DISTINCT FROM unit_id OR binding.group_node IS DISTINCT FROM group_id) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_SEAT_PROTECTED',DETAIL=c::text; END IF;
   UPDATE eshop.spots SET product=product_id,title=c->>'title',updated_at=now() WHERE id=spot_id
    AND (product IS DISTINCT FROM product_id OR title IS DISTINCT FROM c->>'title');
  ELSE
   INSERT INTO eshop.spots(blueprint,occasion,product,title) VALUES(b.id,b.occasion,product_id,c->>'title') RETURNING id INTO spot_id;
  END IF;
  INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot,selection_unit,group_node,blocked)
   VALUES(b.id,node,spot_id,unit_id,group_id,blocked_value)
   ON CONFLICT(blueprint,node_id) DO UPDATE SET selection_unit=excluded.selection_unit,group_node=excluded.group_node,blocked=excluded.blocked;
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

-- Explicit offline migration boundary. Never exposed through PostgREST roles.
CREATE OR REPLACE FUNCTION public.blueprint_legacy_migration_source_internal(p_blueprint bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions SET timezone='UTC' AS $$
SELECT jsonb_build_object('id',b.id,'organization',b.organization,'occasion',b.occasion,'title',b.title,'configuration',b.configuration,'objects',b.objects,'groups',b.groups,'background_svg',b.background_svg,'occasionMeta',(SELECT jsonb_build_object('id',o.id,'organization',o.organization,'unit',o.unit,'end_time',o.end_time,'is_hidden',o.is_hidden,'is_open',o.is_open,'occasion_hidden',o.occasion_hidden) FROM public.occasions o WHERE o.id=b.occasion),'forms',coalesce((SELECT jsonb_agg(jsonb_build_object('id',f.id,'occasion',f.occasion,'is_open',f.is_open,'type',f.type) ORDER BY f.id) FROM public.forms f WHERE f.blueprint=b.id),'[]'),'spots',coalesce((SELECT jsonb_agg(jsonb_build_object('id',s.id,'occasion',s.occasion,'title',s.title,'product',s.product,'state',s.state,'inventory_context',s.inventory_context,'resource',s.resource,'resource_slot',s.resource_slot) ORDER BY s.id) FROM eshop.spots s WHERE s.blueprint=b.id),'[]'),'products',coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.id,'occasion',p.occasion,'product_type',p.product_type,'title',p.title,'price',p.price,'currency_code',p.currency_code) ORDER BY p.id) FROM eshop.products p WHERE p.id IN (SELECT s.product FROM eshop.spots s WHERE s.blueprint=b.id)),'[]')) FROM eshop.blueprints b WHERE b.id=p_blueprint;
$$;
REVOKE ALL ON FUNCTION public.blueprint_legacy_migration_source_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.migrate_blueprint_layout_reviewed_internal(p_source text,p_source_sha text,p_blueprint jsonb,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE b eshop.blueprints; source jsonb; current_source jsonb; c jsonb; s eshop.spots; old_object jsonb; old_group text;
 effective_changes jsonb:='[]'; expected_node uuid; expected_group uuid; request_hash text; started jsonb; result jsonb; before_spots jsonb; after_spots jsonb; users uuid[];
BEGIN
 IF p_source_sha !~ '^[0-9a-f]{64}$' OR encode(extensions.digest(convert_to(p_source,'UTF8'),'sha256'),'hex') IS DISTINCT FROM p_source_sha THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_MIGRATION_SOURCE_HASH_MISMATCH'; END IF;
 source:=p_source::jsonb;
 SELECT * INTO b FROM eshop.blueprints WHERE id=(p_blueprint->>'id')::bigint;
 IF b.id IS NULL OR (source->>'id')::bigint IS DISTINCT FROM b.id OR (source->>'occasion')::bigint IS DISTINCT FROM b.occasion
  OR (p_blueprint->>'occasion')::bigint IS DISTINCT FROM b.occasion
  OR p_blueprint->>'title' IS DISTINCT FROM coalesce(b.title,'') THEN RAISE check_violation USING MESSAGE='BLUEPRINT_MIGRATION_SCOPE_MISMATCH'; END IF;
 IF auth.uid() IS NULL OR NOT (coalesce(public.get_is_editor_on_occasion(b.occasion),false) OR coalesce(public.get_is_manager_on_occasion(b.occasion),false) OR
  (public.is_demo_occasion(b.occasion) AND EXISTS(SELECT 1 FROM public.occasion_users ou WHERE ou.occasion=b.occasion AND ou."user"=auth.uid() AND (ou.is_editor OR ou.is_manager)))) THEN
  RAISE insufficient_privilege USING MESSAGE='blueprint migration reviewer required'; END IF;
 request_hash:=encode(extensions.digest(convert_to(jsonb_build_object('sourceSha',p_source_sha,'request',p_blueprint)::text,'UTF8'),'sha256'),'hex');
 started:=public.begin_client_mutation_reviewed_impl_internal(p_command_id,'inventory.blueprint.migrate',b.occasion,auth.uid(),request_hash,true);
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[b.occasion]);
 SELECT * INTO b FROM eshop.blueprints WHERE id=b.id FOR UPDATE;
 IF b.layout IS NOT NULL OR b.layout_revision<>0 OR (p_blueprint->>'expected_layout_revision')::bigint IS DISTINCT FROM 0
  OR EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings WHERE blueprint=b.id) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_MIGRATION_INITIAL_LAYOUT_REQUIRED'; END IF;
 -- Match canonical writer lock order and freeze only stable commercial facts.
 PERFORM 1 FROM eshop.products WHERE occasion=b.occasion ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_pools WHERE id IN(SELECT ic.inventory_pool FROM public.inventory_contexts ic
  JOIN eshop.product_inventory_contexts pic ON pic.inventory_context=ic.id JOIN eshop.products p ON p.id=pic.product WHERE p.occasion=b.occasion) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_contexts WHERE id IN(SELECT pic.inventory_context FROM eshop.product_inventory_contexts pic JOIN eshop.products p ON p.id=pic.product WHERE p.occasion=b.occasion) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.spots WHERE blueprint=b.id ORDER BY id FOR UPDATE;
 current_source:=public.blueprint_legacy_migration_source_internal(b.id);
 IF current_source IS DISTINCT FROM source THEN RAISE check_violation USING MESSAGE='BLUEPRINT_MIGRATION_REVIEW_STALE'; END IF;
 IF jsonb_array_length(coalesce(p_blueprint->'areaBindingChanges','[]'))<>0 OR
  jsonb_array_length(coalesce(p_blueprint#>'{layout,selectionUnits}','[]'))<>0 OR
  jsonb_array_length(coalesce(p_blueprint->'seatChanges','[]'))<>(SELECT count(*) FROM eshop.spots WHERE blueprint=b.id) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_MIGRATION_BINDING_SET_MISMATCH'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(spot) ORDER BY spot.id),'[]') INTO before_spots FROM eshop.spots spot WHERE spot.blueprint=b.id;
 FOR c IN SELECT value FROM jsonb_array_elements(coalesce(p_blueprint->'seatChanges','[]')) LOOP
  SELECT * INTO s FROM eshop.spots WHERE id=(c->>'spotId')::bigint AND blueprint=b.id AND occasion=b.occasion;
  IF s.id IS NULL OR c->>'operation' IS DISTINCT FROM 'upsert' OR c->>'selectionUnitId' IS NOT NULL OR
   (c->>'productId')::bigint IS DISTINCT FROM s.product OR c->>'title' IS DISTINCT FROM coalesce(s.title,'') OR
   (c->>'blocked')::boolean IS DISTINCT FROM coalesce(s.state='black',false) THEN
   RAISE check_violation USING MESSAGE='BLUEPRINT_MIGRATION_SPOT_FACTS_CHANGED'; END IF;
  expected_node:=extensions.uuid_generate_v5('6ba7b811-9dad-11d1-80b4-00c04fd430c8',format('festapp:occasion:%s:blueprint:%s:spot:%s',b.occasion,b.id,s.id));
  SELECT obj INTO old_object FROM jsonb_array_elements(coalesce(b.objects,'[]')) obj WHERE obj->>'type'='spot' AND (obj->>'id')::bigint=s.id;
  IF old_object IS NULL THEN RAISE check_violation USING MESSAGE='BLUEPRINT_MIGRATION_LEGACY_SPOT_MISSING'; END IF;
  old_group:=old_object->>'group';expected_group:=NULL;
  IF old_group IS NOT NULL AND EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(b.groups,'[]')) grp WHERE grp->>'id'=old_group) THEN
   expected_group:=extensions.uuid_generate_v5('6ba7b811-9dad-11d1-80b4-00c04fd430c8',format('festapp:occasion:%s:blueprint:%s:group:%s',b.occasion,b.id,old_group)); END IF;
  IF (c->>'nodeId')::uuid IS DISTINCT FROM expected_node OR (c->>'groupNodeId')::uuid IS DISTINCT FROM expected_group THEN
   RAISE check_violation USING MESSAGE='BLUEPRINT_MIGRATION_GROUP_MAPPING_CHANGED'; END IF;
  effective_changes:=effective_changes||jsonb_build_array(c||jsonb_build_object('title',s.title));
  INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot,selection_unit,group_node,blocked)
   VALUES(b.id,expected_node,s.id,NULL,expected_group,(c->>'blocked')::boolean);
 END LOOP;
 -- Seeded metadata permits the unchanged protected seats to pass the same
 -- canonical aggregate owner used by every runtime save.
 result:=public.save_blueprint_layout_impl_internal((p_blueprint-'title')||jsonb_build_object('seatChanges',effective_changes),true);
 SELECT coalesce(jsonb_agg(to_jsonb(spot) ORDER BY spot.id),'[]') INTO after_spots FROM eshop.spots spot WHERE spot.blueprint=b.id;
 IF before_spots IS DISTINCT FROM after_spots THEN RAISE check_violation USING MESSAGE='BLUEPRINT_MIGRATION_LIVE_FACTS_CHANGED'; END IF;
 SELECT coalesce(array_agg(DISTINCT ou."user"),'{}') INTO users FROM public.occasion_users ou WHERE ou.occasion=b.occasion;
 result:=result||jsonb_build_object('migrationSourceSha256',p_source_sha);
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,b.occasion,'inventory.blueprint.migrate',
  jsonb_build_array(jsonb_build_object('entityType','blueprint','entityId',b.id,'operation','update','safeLabel','Reviewed blueprint layout migration','changedFields',jsonb_build_array('layout','bindings'))),users,result);
END $$;
REVOKE ALL ON FUNCTION public.migrate_blueprint_layout_reviewed_internal(text,text,jsonb,uuid) FROM PUBLIC,anon,authenticated,service_role;

COMMIT;
