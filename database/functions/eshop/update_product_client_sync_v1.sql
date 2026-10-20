CREATE OR REPLACE FUNCTION public.update_product_client_sync_v1(p_product jsonb, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_product bigint; v_occasion bigint;
  v_begin jsonb; v_hash text; v_users uuid[]; v_version bigint; v_expected bigint;
BEGIN
  IF p_product IS NULL OR jsonb_typeof(p_product)<>'object'
    OR octet_length(p_product::text)>524288 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid product aggregate'; END IF;
  v_product:=NULLIF(p_product->>'id','')::bigint;
  SELECT occasion INTO v_occasion FROM public.client_mutation_receipts WHERE command_id=p_command_id AND actor_id=v_actor AND command_name='inventory.product.save';
  IF NOT FOUND THEN
  IF v_product IS NOT NULL THEN
    SELECT p.occasion INTO v_occasion FROM eshop.products p WHERE p.id=v_product;
  ELSE
    SELECT pt.occasion INTO v_occasion FROM eshop.product_types pt
      WHERE pt.id=NULLIF(p_product->>'product_type','')::bigint;
  END IF;
  END IF;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR NOT public.get_is_editor_order_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  IF jsonb_typeof(p_product->'inventory_contexts')='array' THEN
    p_product:=jsonb_set(p_product,'{inventory_contexts}',coalesce((SELECT jsonb_agg(c ORDER BY (c->>'inventory_context_id')::bigint)
      FROM jsonb_array_elements(p_product->'inventory_contexts') c),'[]')); END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',v_occasion,'product',p_product)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.product.save',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF v_product IS NOT NULL THEN
    SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_users
    FROM eshop.order_product_ticket opt JOIN public.occasion_users ou
      ON ou.ticket=opt.ticket AND ou.occasion=v_occasion
    WHERE opt.product=v_product;
  ELSE v_users:='{}'::uuid[]; END IF;
  -- Context replacement recalculates allocations: acquire the same outer order
  -- parents before saving a product, never product then order in this command.
  PERFORM public.lock_product_order_dependencies_internal_v1(v_product);
  IF v_product IS NOT NULL THEN
    PERFORM 1 FROM eshop.products WHERE id=v_product AND occasion=v_occasion FOR UPDATE;
    SELECT coalesce(v.version,0) INTO v_version FROM (SELECT 1) seed
    LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='product'
    AND v.scope_type='occasion' AND v.scope_id=v_occasion AND v.aggregate_id=v_product::text;
    -- Released scalar facades may omit this control until their explicit upgrade gate.
    v_expected:=CASE WHEN p_product ? 'expected_aggregate_version'
      THEN (p_product->>'expected_aggregate_version')::bigint ELSE v_version END;
    IF v_expected IS DISTINCT FROM v_version THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
        jsonb_build_object('productId',v_product,'aggregate_version',v_version)); END IF;
  ELSIF p_product->>'expected_aggregate_version' IS NOT NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='new product cannot have expected version';
  END IF;
  v_product:=public.update_product_internal_v1(p_product-'expected_aggregate_version');
  SELECT version INTO v_version FROM public.client_aggregate_versions WHERE aggregate_type='product'
    AND scope_type='occasion' AND scope_id=v_occasion AND aggregate_id=v_product::text;
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.product.save',jsonb_build_array(jsonb_build_object(
      'entityType','product','entityId',v_product,'operation',
      CASE WHEN p_product->>'id' IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(p_product->>'title',240),'changedFields',jsonb_build_array(
        'configuration','contexts'))),v_users,jsonb_build_object('productId',v_product,'aggregate_version',v_version));
END; $function$;
REVOKE ALL ON FUNCTION public.update_product_client_sync_v1(jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_product_client_sync_v1(jsonb,uuid) TO authenticated;
