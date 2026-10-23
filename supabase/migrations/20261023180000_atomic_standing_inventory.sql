-- One shared pool/resource owner and one standing preparation receipt.
-- Shared mutation owner; no editor bundle, receipt or sync publication.
CREATE OR REPLACE FUNCTION public.save_inventory_pool_internal(p_bundle_data jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_pool_data jsonb := p_bundle_data->'pool';
    v_pool_id bigint;
    v_occasion_id bigint;

    -- Context variables
    v_context_data jsonb;
    v_context_id bigint;
    v_context_ids_from_input bigint[] := ARRAY[]::bigint[];

    result jsonb;
BEGIN
    -- Resolve occasion ID from the input data. It's required for both create and update.
    v_occasion_id := (v_pool_data->>'occasion')::bigint;
    IF v_occasion_id IS NULL THEN
        RAISE EXCEPTION '%', jsonb_build_object('code', 'B001', 'message', 'Occasion ID is required.')::text;
    END IF;

    -- Permission check
    IF NOT can_write_orders(v_occasion_id) THEN
        RAISE EXCEPTION '%', jsonb_build_object('code', 403, 'message', 'User is not authorized to edit this occasion.')::text;
    END IF;

    -- 1. Upsert the main inventory_pool record
    v_pool_id := (v_pool_data->>'id')::bigint;

    IF v_pool_id IS NULL THEN
        -- Create a new pool if ID is not provided
        INSERT INTO public.inventory_pools (title, occasion, sellable_capacity, description, type, data, created_at, updated_at)
        VALUES (
            v_pool_data->>'title',
            v_occasion_id,
            (v_pool_data->>'sellable_capacity')::bigint,
            v_pool_data->>'description',
            v_pool_data->>'type',
            v_pool_data->'data',
            now(),
            now()
        ) RETURNING id INTO v_pool_id;
    ELSE
        PERFORM 1 FROM public.inventory_pools WHERE id=v_pool_id AND occasion=v_occasion_id FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'Inventory pool scope mismatch'; END IF;
        PERFORM 1 FROM public.inventory_contexts WHERE inventory_pool=v_pool_id ORDER BY id FOR UPDATE;
        IF (v_pool_data->>'sellable_capacity')::bigint < (SELECT count(*) FROM eshop.spots s JOIN public.inventory_contexts ic ON ic.id=s.inventory_context
          WHERE ic.inventory_pool=v_pool_id AND (s.order_product_ticket IS NOT NULL OR (s.secret IS NOT NULL AND s.secret_expiration_time>clock_timestamp()))) THEN
          RAISE EXCEPTION 'INVENTORY_CAPACITY_BELOW_COMMITTED'; END IF;
        -- Update the existing pool
        UPDATE public.inventory_pools
        SET
            title = v_pool_data->>'title',
            sellable_capacity = (v_pool_data->>'sellable_capacity')::bigint,
            description = v_pool_data->>'description',
            type = v_pool_data->>'type',
            data = v_pool_data->'data',
            updated_at = now()
        WHERE id = v_pool_id;
    END IF;

    -- NOTE: Resource and Slot management logic has been removed as requested.

    -- 2. Upsert/Delete Inventory Contexts
    IF jsonb_typeof(p_bundle_data->'contexts') = 'array' THEN
        FOR v_context_data IN SELECT * FROM jsonb_array_elements(p_bundle_data->'contexts')
        LOOP
            v_context_id := (v_context_data->>'id')::bigint;
            IF v_context_id IS NULL THEN
                -- Create new context, now including the 'data' field
                INSERT INTO public.inventory_contexts (inventory_pool, block_date, title, "order", data)
                VALUES (v_pool_id, (v_context_data->>'block_date')::date, v_context_data->>'title', (v_context_data->>'order')::bigint, v_context_data->'data')
                RETURNING id INTO v_context_id;
            ELSE
                -- Update existing context, now including the 'data' field
                UPDATE public.inventory_contexts
                SET
                    block_date = (v_context_data->>'block_date')::date,
                    title = v_context_data->>'title',
                    "order" = (v_context_data->>'order')::bigint,
                    data = v_context_data->'data' -- Added this line
                WHERE id = v_context_id;
            END IF;
            v_context_ids_from_input := array_append(v_context_ids_from_input, v_context_id);
        END LOOP;
        -- Deleting a context must not detach a sold or currently held spot.
        PERFORM 1 FROM eshop.spots WHERE inventory_context IN (SELECT id FROM public.inventory_contexts
          WHERE inventory_pool=v_pool_id AND id<>ALL(v_context_ids_from_input)) ORDER BY id FOR UPDATE;
        IF EXISTS(SELECT 1 FROM eshop.spots WHERE inventory_context IN (SELECT id FROM public.inventory_contexts
          WHERE inventory_pool=v_pool_id AND id<>ALL(v_context_ids_from_input))
          AND (order_product_ticket IS NOT NULL OR (secret IS NOT NULL AND secret_expiration_time>clock_timestamp()))) THEN
          RAISE check_violation USING MESSAGE='INVENTORY_CONTEXT_IN_USE'; END IF;
        -- Delete contexts that were removed in the UI for this pool
        DELETE FROM public.inventory_contexts WHERE inventory_pool = v_pool_id AND id <> ALL(v_context_ids_from_input);
    END IF;

    -- 3. Create or delete spots for the inventory pool based on its resources and contexts.
    -- The function is executed, and its integer return value is discarded.
    PERFORM adjust_spot_capacity_for_pool(v_pool_id);

    -- Callers select only the snapshot their intention needs.
    RETURN v_pool_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.save_inventory_pool_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Existing complete-editor snapshot boundary; mutation has one shared owner.
CREATE OR REPLACE FUNCTION public.update_inventory_pool_bundle_internal_v1(p_bundle_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE pool_id bigint;
BEGIN
 IF public.can_write_orders((p_bundle_data#>>'{pool,occasion}')::bigint) IS DISTINCT FROM TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='occasion order editor required'; END IF;
 pool_id:=public.save_inventory_pool_internal(p_bundle_data);
 RETURN public.get_inventory_pool_bundle(pool_id);
END $$;
REVOKE ALL ON FUNCTION public.update_inventory_pool_bundle_internal_v1(jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- Resource rules, versions, allocation/capacity and lock order have one owner.
-- No receipt or sync publication here: a caller owns the complete intention.
CREATE OR REPLACE FUNCTION public.save_inventory_resource_internal(p_occasion bigint,p_expected_version bigint,p_resource jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_id bigint:=(p_resource->>'id')::bigint;
 v_pool bigint:=(p_resource->>'inventory_pool')::bigint; v_version bigint; v_origin_pool bigint;
 v_current jsonb; v_entity jsonb;
BEGIN
  -- No booking rules and an empty rule document have the same domain meaning.
  IF p_resource->'booking_rules'='null'::jsonb THEN
    p_resource:=jsonb_set(p_resource,'{booking_rules}','{}'); END IF;
  IF v_actor IS NULL OR NOT public.can_write_orders(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion order editor required'; END IF;
  IF p_resource IS NULL OR jsonb_typeof(p_resource)<>'object'
    OR octet_length(p_resource::text)>131072
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_resource) key WHERE key NOT IN
      ('id','title','capacity','booking_rules','inventory_pool'))
    OR v_pool IS NULL OR length(btrim(COALESCE(p_resource->>'title',''))) NOT BETWEEN 1 AND 500
    OR coalesce((p_resource->>'capacity')::integer,-1) NOT BETWEEN 0 AND 1000000
    OR jsonb_typeof(COALESCE(p_resource->'booking_rules','{}'))<>'object' THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid resource aggregate'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.inventory_pools WHERE id=v_pool AND occasion=p_occasion) THEN
    RAISE invalid_parameter_value USING MESSAGE='inventory pool is outside occasion'; END IF;
  IF v_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.resources WHERE id=v_id AND occasion=p_occasion) THEN
    RETURN jsonb_build_object('status','rejected','code',404,'data',jsonb_build_object('version',0,'resource',NULL)); END IF;
  v_origin_pool:=public.lock_resource_pools_internal_v1(v_id,v_pool);
  PERFORM 1 FROM public.inventory_pools ip WHERE ip.id=v_pool
    AND ip.occasion=p_occasion FOR UPDATE;
  IF NOT FOUND THEN RAISE invalid_parameter_value USING MESSAGE='inventory pool is outside occasion'; END IF;
  IF v_id IS NOT NULL THEN
    SELECT to_jsonb(r) INTO v_current FROM public.resources r WHERE r.id=v_id
      AND r.occasion=p_occasion FOR UPDATE;
    IF v_current IS NULL THEN RETURN jsonb_build_object('status','rejected','code',404,'data',jsonb_build_object('version',0,'resource',NULL)); END IF;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('resource','occasion',p_occasion,v_id::text,0) ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
      WHERE aggregate_type='resource' AND scope_type='occasion'
        AND scope_id=p_occasion AND aggregate_id=v_id::text FOR UPDATE;
    IF p_expected_version IS DISTINCT FROM v_version THEN
      RETURN jsonb_build_object('status','conflict','code',409,'data',jsonb_build_object('version',v_version,'resource',v_current||
          jsonb_build_object('aggregate_version',v_version))); END IF;
    IF jsonb_build_object('title',v_current->>'title','capacity',(v_current->>'capacity')::integer,
      'booking_rules',COALESCE(v_current->'booking_rules','{}'),
      'inventory_pool',(v_current->>'inventory_pool')::bigint)=jsonb_build_object(
      'title',p_resource->>'title','capacity',(p_resource->>'capacity')::integer,
      'booking_rules',COALESCE(p_resource->'booking_rules','{}'),
      'inventory_pool',v_pool) THEN RETURN jsonb_build_object('status','unchanged','code',200,'data',jsonb_build_object('version',v_version,
          'resource',v_current||jsonb_build_object('aggregate_version',v_version))); END IF;
    PERFORM 1 FROM eshop.spots WHERE resource=v_id OR resource_slot IN(SELECT id FROM public.resource_slots WHERE resource=v_id) ORDER BY id FOR UPDATE;
    IF (v_origin_pool IS DISTINCT FROM v_pool AND EXISTS(SELECT 1 FROM eshop.spots
      WHERE (resource=v_id OR resource_slot IN(SELECT id FROM public.resource_slots WHERE resource=v_id))
      AND (order_product_ticket IS NOT NULL OR (secret IS NOT NULL AND secret_expiration_time>clock_timestamp()))))
      OR EXISTS(SELECT 1 FROM eshop.spots WHERE (resource=v_id OR resource_slot IN(SELECT id FROM public.resource_slots WHERE resource=v_id))
        AND (order_product_ticket IS NOT NULL OR (secret IS NOT NULL AND secret_expiration_time>clock_timestamp()))
        GROUP BY inventory_context HAVING count(*)>(p_resource->>'capacity')::integer) THEN
      RETURN jsonb_build_object('status','rejected','code',409,'data',jsonb_build_object('version',v_version,'resourceId',v_id,'message','resource capacity or move conflicts with reserved spots')); END IF;
    IF v_origin_pool IS DISTINCT FROM v_pool THEN
      DELETE FROM eshop.spots WHERE resource=v_id OR resource_slot IN(SELECT id FROM public.resource_slots WHERE resource=v_id);
    END IF;
    UPDATE public.resources SET title=p_resource->>'title',
      capacity=(p_resource->>'capacity')::integer,
      booking_rules=COALESCE(p_resource->'booking_rules','{}'),inventory_pool=v_pool,
      updated_at=clock_timestamp() WHERE id=v_id;
    UPDATE public.client_aggregate_versions SET version=version+1,
      updated_at=clock_timestamp() WHERE aggregate_type='resource'
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_id::text
      RETURNING version INTO v_version;
  ELSE
    IF p_expected_version IS NOT NULL THEN
      RAISE invalid_parameter_value USING MESSAGE='new resource must not have expected version'; END IF;
    INSERT INTO public.resources(occasion,inventory_pool,title,capacity,booking_rules)
    VALUES (p_occasion,v_pool,p_resource->>'title',(p_resource->>'capacity')::integer,
      COALESCE(p_resource->'booking_rules','{}')) RETURNING id INTO v_id;
    v_version:=1;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('resource','occasion',p_occasion,v_id::text,v_version);
  END IF;
  IF v_origin_pool IS NOT NULL AND v_origin_pool IS DISTINCT FROM v_pool THEN
    PERFORM public.adjust_spot_capacity_for_pool(v_origin_pool);
  END IF;
  PERFORM public.adjust_spot_capacity_for_pool(v_pool);
  PERFORM public.advance_ticketing_authoring_version_internal_v1('inventory_pool',p_occasion,v_pool);
  IF v_origin_pool IS NOT NULL AND v_origin_pool IS DISTINCT FROM v_pool THEN
    PERFORM public.advance_ticketing_authoring_version_internal_v1('inventory_pool',p_occasion,v_origin_pool);
  END IF;
  SELECT to_jsonb(r)||jsonb_build_object('aggregate_version',v_version)
    INTO v_entity FROM public.resources r WHERE r.id=v_id;
  RETURN jsonb_build_object('status','applied','code',200,'data',jsonb_build_object('version',v_version,'resource',v_entity));
END $$;
REVOKE ALL ON FUNCTION public.save_inventory_resource_internal(bigint,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.save_resource_client_sync_v1(p_occasion bigint,p_command_id uuid,p_expected_version bigint,p_resource jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE actor uuid:=auth.uid(); hash text; started jsonb; result jsonb; entity jsonb; impacts jsonb; replacements jsonb:='[]';
BEGIN
 IF actor IS NULL OR NOT public.can_write_orders(p_occasion) THEN
  RAISE insufficient_privilege USING MESSAGE='occasion order editor required'; END IF;
 IF p_resource->'booking_rules'='null'::jsonb THEN p_resource:=jsonb_set(p_resource,'{booking_rules}','{}'); END IF;
 hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
  'expectedVersion',p_expected_version,'resource',p_resource)::text,'UTF8'),'sha256'),'hex');
 started:=public.begin_client_mutation_v1(p_command_id,'inventory.resource.save',p_occasion,actor,hash);
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 result:=public.save_inventory_resource_internal(p_occasion,p_expected_version,p_resource);
 IF result->>'status'<>'applied' THEN
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,result->>'status',(result->>'code')::integer,result->'data');
 END IF;
 entity:=result#>'{data,resource}';
 SELECT coalesce(jsonb_agg(jsonb_build_object('component','private_inventory','userId',ou."user")),'[]') INTO impacts
 FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
 IF EXISTS(SELECT 1 FROM public.occasion_users ou WHERE ou.occasion=p_occasion AND ou."user"=actor) THEN
  replacements:=jsonb_build_array(jsonb_build_object('component','private_inventory','userId',actor,
   'payload',public.get_user_inventory_for_occasion_v1(p_occasion)));
 END IF;
 RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,'inventory.resource.save','inventory',
  jsonb_build_array(jsonb_build_object('entityType','resource','entityId',(entity->>'id')::bigint,
   'operation',CASE WHEN p_resource->>'id' IS NULL THEN 'insert' ELSE 'update' END,
   'safeLabel',left(entity->>'title',240),'changedFields',jsonb_build_array('aggregate'))),
  '{}',impacts,'[]',result->'data','{}','[]','user',NULL,replacements);
END $$;
REVOKE ALL ON FUNCTION public.save_resource_client_sync_v1(bigint,uuid,bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_resource_client_sync_v1(bigint,uuid,bigint,jsonb) TO authenticated;

-- A single admin intention: prepare supply for an existing admission product.
-- Existing pool/resource/assignment owners retain validation and allocation.
CREATE OR REPLACE FUNCTION public.prepare_standing_inventory(p_occasion bigint,p_organization bigint,p_unit bigint,
 p_product_id bigint,p_expected_version bigint,p_capacity integer,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE actor uuid:=auth.uid(); started jsonb; hash text; current_version bigint;
 product_row eshop.products%ROWTYPE; type_title text; pool_id bigint; context_id bigint;
 resource_result jsonb; result jsonb; rejection jsonb; catalog jsonb; snapshot jsonb; pool_snapshot jsonb; users uuid[];
BEGIN
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true);
 IF p_product_id IS NULL OR p_expected_version IS NULL OR p_expected_version<0 OR p_capacity IS NULL
   OR p_capacity NOT BETWEEN 0 AND 1000000 THEN RAISE invalid_parameter_value USING MESSAGE='invalid standing inventory'; END IF;
 -- Reject foreign IDs before acquiring their order/product locks. Retained
 -- receipts still pin replay even if the prepared product was later deleted.
 IF NOT EXISTS(SELECT 1 FROM public.client_mutation_receipts WHERE command_id=p_command_id
     AND actor_id=actor AND command_name='inventory.standing.prepare')
   AND NOT EXISTS(SELECT 1 FROM eshop.products p JOIN eshop.product_types pt ON pt.id=p.product_type
     WHERE p.id=p_product_id AND p.occasion=p_occasion AND pt.occasion=p_occasion AND pt.type='spot') THEN
  RAISE insufficient_privilege USING MESSAGE='standing product unavailable';
 END IF;
 hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,'productId',p_product_id,
  'expectedVersion',p_expected_version,'capacity',p_capacity)::text,'UTF8'),'sha256'),'hex');
 started:=public.begin_client_mutation_v1(p_command_id,'inventory.standing.prepare',p_occasion,actor,hash);
 IF started->>'disposition'='replay' THEN
  result:=started->'response';
 ELSE
  -- Checkout/assignment owners lock order parents before the product. New stock
  -- rows do not yet belong to another product, so no inverse pool dependency.
  PERFORM public.lock_product_order_dependencies_internal_v1(p_product_id);
  SELECT p.* INTO product_row FROM eshop.products p JOIN eshop.product_types pt ON pt.id=p.product_type
   WHERE p.id=p_product_id AND p.occasion=p_occasion AND pt.occasion=p_occasion AND pt.type='spot' FOR UPDATE OF p;
  IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='standing product unavailable'; END IF;
  SELECT coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='product'
   AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_product_id::text),0) INTO current_version;
  IF current_version IS DISTINCT FROM p_expected_version OR EXISTS(SELECT 1 FROM eshop.product_inventory_contexts WHERE product=p_product_id) THEN
   result:=public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
    jsonb_build_object('productId',p_product_id,'aggregate_version',current_version));
  ELSE
   BEGIN
   -- Child failures abort every new object and the product link together.
   pool_id:=public.save_inventory_pool_internal(jsonb_build_object('pool',
    jsonb_build_object('title',product_row.title,'occasion',p_occasion,'sellable_capacity',p_capacity,
     'data',jsonb_build_object('is_auto_resource_assignment',false)),
    'contexts',jsonb_build_array(jsonb_build_object('title',product_row.title))));
   SELECT id INTO STRICT context_id FROM public.inventory_contexts WHERE inventory_pool=pool_id;
   IF pool_id IS NULL OR context_id IS NULL THEN RAISE EXCEPTION 'standing pool creation failed'; END IF;
   PERFORM public.advance_ticketing_authoring_version_internal_v1('inventory_pool',p_occasion,pool_id);
   resource_result:=public.save_inventory_resource_internal(p_occasion,NULL,jsonb_build_object(
    'inventory_pool',pool_id,'title',product_row.title,'capacity',p_capacity,'booking_rules','{}'::jsonb));
   IF resource_result->>'status'<>'applied' THEN RAISE EXCEPTION 'standing resource creation failed'; END IF;
   PERFORM public.update_product_inventory_contexts_internal_v1(p_product_id,
    jsonb_build_array(jsonb_build_object('inventory_context_id',context_id,'quantity',1)));
   catalog:=public.get_product_catalog_data_internal(p_occasion,NULLIF(p_product_id-1,0),1)::jsonb;
   SELECT pt.title INTO type_title FROM eshop.product_types pt WHERE pt.id=product_row.product_type;
   snapshot:=catalog#>'{products,0}' || jsonb_build_object('occasion',p_occasion,'type','spot','type_title',type_title,
    'inventory_contexts',jsonb_build_array(jsonb_build_object('inventory_context_id',context_id,'quantity',1)));
   IF (snapshot->>'id')::bigint IS DISTINCT FROM p_product_id THEN RAISE EXCEPTION 'standing product snapshot unavailable'; END IF;
   SELECT to_jsonb(ip)||jsonb_build_object('aggregate_version',v.version) INTO pool_snapshot
    FROM public.inventory_pools ip JOIN public.client_aggregate_versions v ON v.aggregate_type='inventory_pool'
     AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=ip.id::text WHERE ip.id=pool_id;
   -- Union of the existing pool/resource and assignment sync audiences.
   SELECT coalesce(array_agg(DISTINCT ou."user"),'{}') INTO users FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
   result:=public.complete_private_inventory_mutation_v1(p_command_id,p_occasion,'inventory.standing.prepare',
    jsonb_build_array(
     jsonb_build_object('entityType','inventory_pool','entityId',pool_id,'operation','insert','safeLabel','Standing inventory','changedFields',jsonb_build_array('aggregate')),
     jsonb_build_object('entityType','resource','entityId',resource_result#>'{data,resource,id}','operation','insert','safeLabel','Standing supply','changedFields',jsonb_build_array('aggregate')),
     jsonb_build_object('entityType','product','entityId',p_product_id,'operation','update','safeLabel','Standing product','changedFields',jsonb_build_array('inventory_contexts'))),users,
    jsonb_build_object('product',snapshot,'pool',pool_snapshot,'context',catalog#>'{inventory_contexts,0}',
      'resource',resource_result#>'{data,resource}','forms',catalog->'forms','readAt',catalog->'server_time'));
   EXCEPTION WHEN invalid_parameter_value THEN
    result:=public.complete_client_mutation_outcome_v1(p_command_id,'rejected',422,jsonb_build_object('reason','INVALID_STANDING_INVENTORY'));
   WHEN raise_exception THEN
    IF left(SQLERRM,1)<>'{' THEN RAISE; END IF;
    rejection:=SQLERRM::jsonb;
    IF rejection->>'code'<>'1017' THEN RAISE; END IF;
    result:=public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,jsonb_build_object('reason','PRODUCT_CAPACITY_EXCEEDED'));
   END;
  END IF;
 END IF;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true,true);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.prepare_standing_inventory(bigint,bigint,bigint,bigint,bigint,integer,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.prepare_standing_inventory(bigint,bigint,bigint,bigint,bigint,integer,uuid) TO authenticated;

