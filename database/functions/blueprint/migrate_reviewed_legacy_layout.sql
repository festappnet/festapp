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
