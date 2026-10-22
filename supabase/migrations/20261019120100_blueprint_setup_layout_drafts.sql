-- Blueprint V2 setup drafts materialize through the existing aggregate and inventory owners.
BEGIN;

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

GRANT EXECUTE ON FUNCTION public.get_occasion_setup_blueprint_resources(uuid) TO authenticated;

-- Copy shared inventory configuration through its existing command owners.
-- Only empty target inventory is created; source holds/bookings never enter it.
CREATE OR REPLACE FUNCTION public.copy_setup_area_inventory_internal(p_areas jsonb,p_products jsonb,p_source bigint,p_target bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE area jsonb; pool public.inventory_pools; resource_row public.resources; bundle jsonb; mapped jsonb:='{}';
 old_ids bigint[]; new_ids bigint[]; new_pool bigint; index integer; old_product bigint; new_product bigint; links jsonb;
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
  FOR resource_row IN SELECT * FROM public.resources WHERE inventory_pool=pool.id ORDER BY id LOOP
   IF resource_row.capacity IS NULL THEN RAISE check_violation USING MESSAGE='BLUEPRINT_SETUP_RESOURCE_CAPACITY_REQUIRED'; END IF;
   PERFORM public.update_resource(jsonb_build_object('inventory_pool',new_pool,'title',resource_row.title,'capacity',resource_row.capacity,'booking_rules',resource_row.booking_rules));
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
  IF seat ? 'spotId' OR EXISTS(SELECT 1 FROM jsonb_object_keys(seat) k WHERE k NOT IN('nodeId','productId','title','groupNodeId','selectionUnitId','blocked')) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_SETUP_BINDING_IDENTITY'; END IF;
  product_id:=(p_product_map->>(seat->>'productId'))::bigint;
  IF seat->>'productId' IS NOT NULL AND product_id IS NULL THEN RAISE check_violation USING MESSAGE='BLUEPRINT_SETUP_PRODUCT_NOT_IN_FORM'; END IF;
  seats:=seats||jsonb_build_array(seat||jsonb_build_object('nodeId',coalesce(ids->> (seat->>'nodeId'),seat->>'nodeId'),
   'groupNodeId',coalesce(ids->>(seat->>'groupNodeId'),seat->>'groupNodeId'),'selectionUnitId',coalesce(ids->>(seat->>'selectionUnitId'),seat->>'selectionUnitId'),
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
      'id',b.id,'title',b.title,'configuration',b.configuration,'groups',b.groups,
      'background_svg',b.background_svg,
      'objects',COALESCE((SELECT jsonb_agg((obj - 'state' - 'order_product_ticket' - 'secret') ||
        jsonb_build_object('state','available','product',s.product,'title',COALESCE(s.title,obj->>'title')))
        FROM jsonb_array_elements(COALESCE(b.objects,'[]'::jsonb)) obj
        LEFT JOIN eshop.spots s ON s.id=NULLIF(obj->>'id','')::bigint AND s.blueprint=b.id),'[]'::jsonb)) ORDER BY b.id)
      FROM eshop.blueprints b WHERE b.occasion=o.id),'[]'::jsonb),
    'program',COALESCE((SELECT jsonb_agg(jsonb_build_object('title',e.title,
      'start_time',e.start_time,'end_time',e.end_time,'description',e.description))
      FROM public.events e WHERE e.occasion=o.id),'[]'::jsonb),
    'information',COALESCE((SELECT jsonb_agg(jsonb_build_object('title',i.title,
      'description',i.description,'type',i.type,'data',i.data) ORDER BY i."order",i.id)
      FROM public.information i WHERE i.occasion=o.id),'[]'::jsonb)
    ) ORDER BY o.start_time DESC,o.id DESC) FROM public.occasions o WHERE o.unit=p_unit),'[]'::jsonb);
END $$;




-- Materialize the private configuration exactly once. Provisional draft IDs and
-- source product IDs are never accepted as IDs in the new aggregate.
CREATE OR REPLACE FUNCTION public.finalize_occasion_setup_draft(p_id uuid,p_expected_revision bigint,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE policies jsonb; d public.occasion_setup_drafts; payload jsonb; config jsonb; features jsonb := '[]';
 started jsonb; receipt jsonb; new_id bigint; form_id bigint; form_data jsonb; fields jsonb := '[]';
 field jsonb; pt jsonb; products jsonb; product jsonb; result jsonb; source_id bigint;
 old_products jsonb := '[]'; old_types jsonb := '[]'; type_map jsonb := '{}'; final_features jsonb; new_products jsonb; product_map jsonb := '{}'; idx integer; j integer;
 blueprint_id bigint; objects jsonb := '[]'; obj jsonb; v_commit public.client_commits%ROWTYPE;
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
 source_id := (payload->>'sourceId')::bigint;
 IF source_id IS NOT NULL AND (NOT public.can_copy_occasion_source(source_id) OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=source_id AND organization=d.organization)) THEN
  RAISE insufficient_privilege USING MESSAGE='Copy source denied'; END IF;
 IF nullif(btrim(payload->>'title'),'') IS NULL OR (payload->>'reviewConfirmed')::boolean IS DISTINCT FROM true THEN
  RAISE invalid_parameter_value USING MESSAGE='Draft review required'; END IF;
 IF (payload->>'end')::timestamptz < (payload->>'start')::timestamptz THEN
  RAISE invalid_parameter_value USING MESSAGE='Invalid event dates'; END IF;
 IF payload->'ticketDraft' IS NOT NULL AND payload->'ticketDraft'<>'null'::jsonb THEN features := features || jsonb_build_array((payload->'ticketDraft')-'layout'); END IF;
 IF coalesce((payload->>'formEnabled')::boolean,true) THEN features := features || '[{"code":"form","is_enabled":true}]'; END IF;
 IF coalesce((payload->>'copyProgram')::boolean,false) THEN features := features || '[{"code":"schedule","is_enabled":true}]'; END IF;
 IF coalesce((payload->>'copyInformation')::boolean,false) THEN features := features || '[{"code":"information","is_enabled":true}]'; END IF;
 config := jsonb_build_object('unit',d.unit,'organization',d.organization,
  'title',payload->>'title','link',payload->>'link','description',coalesce(payload->>'description',''),
  'start_time',payload->>'start','end_time',payload->>'end','is_hidden',true,'is_open',false,
  'features',features,'data',jsonb_build_object('client_sync_v1',false));
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
  SELECT id INTO form_id FROM public.forms WHERE occasion=new_id ORDER BY id LIMIT 1;
  IF form_id IS NULL THEN
   result := public.create_form_internal_v1(new_id,NULL,form_data->>'title'); form_id := (result->>'id')::bigint;
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
   'id',form_id,'occasion',new_id,'link',CASE WHEN source_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.forms source_form WHERE source_form.occasion=source_id AND source_form.link=form_data->>'link')
     THEN (SELECT link FROM public.forms WHERE id=form_id) ELSE coalesce(nullif(form_data->>'link',''),(SELECT link FROM public.forms WHERE id=form_id)) END,
   'is_open',false,'form_fields',fields));
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
  IF payload->'blueprintLayoutDraft' IS NOT NULL AND payload->'blueprintLayoutDraft'<>'null'::jsonb THEN
   blueprint_id:=public.materialize_setup_blueprint_layout_internal(payload->'blueprintLayoutDraft',product_map,source_id,new_id,d.unit);
   UPDATE public.forms SET blueprint=blueprint_id WHERE id=form_id;
   features:=features||'[{"code":"blueprint","is_enabled":true}]';
  ELSIF jsonb_array_length(coalesce(payload->'blueprintObjects','[]'))>0 THEN
   RAISE check_violation USING MESSAGE='BLUEPRINT_SETUP_LEGACY_DRAFT_REQUIRES_CONVERSION';
  END IF;
 END IF;
 -- Rebind ticket product-type references only after their new IDs exist.
 IF payload->'ticketDraft' ? 'layout' THEN
  pt := payload->'ticketDraft';
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




COMMIT;
