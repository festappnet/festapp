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
