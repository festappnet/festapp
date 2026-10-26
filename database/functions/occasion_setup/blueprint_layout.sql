-- Unit-scoped preparation uses the existing ticket preview admission policy.
CREATE OR REPLACE FUNCTION public.admit_occasion_setup_blueprint_resources_v1(p_draft uuid,p_bytes bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE d public.occasion_setup_drafts;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_draft;
 IF d.id IS NULL OR auth.uid() IS NULL OR NOT public.can_create_occasion(d.unit) THEN
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
DECLARE d public.occasion_setup_drafts; doc jsonb; source_id bigint; resources jsonb; source_resources jsonb;
BEGIN
 SELECT * INTO d FROM public.occasion_setup_drafts WHERE id=p_draft;
 IF d.id IS NULL OR auth.uid() IS NULL OR NOT public.can_create_occasion(d.unit) THEN RAISE insufficient_privilege USING MESSAGE='Draft access denied'; END IF;
 source_id:=(d.data->>'sourceId')::bigint;
 IF source_id IS NOT NULL AND (NOT public.can_copy_occasion_source(source_id) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=source_id AND organization=d.organization)) THEN RAISE insufficient_privilege USING MESSAGE='Copy source denied'; END IF;
 doc:=coalesce(d.data#>'{blueprintLayoutDraft,layout}',jsonb_build_object(
  'schemaVersion',2,'symbolSetVersion',1,'canvas',jsonb_build_object('x',0,'y',0,'width',2400,'height',1600,'fill','#FFFFFFFF'),
  'styles','{}'::jsonb,'seatingDefaults','{}'::jsonb,'textPolicy',jsonb_build_object('language','und','direction','auto'),
  'nodes','[]'::jsonb,'sections','[]'::jsonb,'selectionUnits','[]'::jsonb,'attachments','[]'::jsonb,'presets','[]'::jsonb));
 IF doc->>'schemaVersion' IS DISTINCT FROM '2' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_LAYOUT_MIGRATION_REQUIRED';END IF;
  resources:=public.blueprint_canonical_text_resources_internal(doc,NULL,p_draft,true);
  source_resources:=CASE WHEN source_id IS NULL THEN '{}'::jsonb ELSE public.blueprint_canonical_text_resources_internal(doc,source_id,NULL,true) END;
  resources:=resources||jsonb_build_object(
   'fontFamilies',coalesce(source_resources->'fontFamilies','{}')||(resources->'fontFamilies'),
   'textLayouts',coalesce(source_resources->'textLayouts','{}')||(resources->'textLayouts'),
   'numberSymbols',coalesce(source_resources->'numberSymbols','{}')||(resources->'numberSymbols'),
   'assets',public.blueprint_canonical_asset_resources_internal(doc,source_id,NULL)||public.blueprint_canonical_asset_resources_internal(doc,NULL,d.unit));
  RETURN public.bound_document_data_v1(jsonb_build_object('resources',resources));
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
 PERFORM public.validate_blueprint_layout_internal(doc);
 IF p_source IS NOT NULL THEN PERFORM public.copy_blueprint_text_resources_internal(p_source,NULL,p_target,doc);END IF;
 PERFORM public.check_blueprint_text_resources_internal(doc,p_target);
 PERFORM public.copy_blueprint_canonical_bitmap_resources_internal(p_source,p_unit,p_target,doc);
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
 result:=public.save_blueprint_layout_internal_v1(jsonb_build_object('occasion',p_target,'expected_layout_revision',0,'title','Blueprint','layout',doc,'seatChanges',seats,'groupProductChanges',groups,'areaBindingChanges',areas)||jsonb_build_object('textResourceIds',to_jsonb(public.blueprint_text_resource_ids_internal(doc,p_target))));
 RETURN (result->>'blueprint_id')::bigint;
END $$;
REVOKE ALL ON FUNCTION public.materialize_setup_blueprint_layout_internal(jsonb,jsonb,bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;
