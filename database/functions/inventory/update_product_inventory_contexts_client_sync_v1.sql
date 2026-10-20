CREATE OR REPLACE FUNCTION public.update_product_inventory_contexts_client_sync_v1(p_product_id bigint, p_contexts jsonb, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_users uuid[]; v_expected bigint; v_version bigint; v_versioned boolean:=false;
BEGIN
  IF jsonb_typeof(p_contexts)='object' THEN
    IF jsonb_typeof(p_contexts->'contexts') IS DISTINCT FROM 'array'
      OR NOT p_contexts ? 'expected_aggregate_version'
      OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_contexts) k WHERE k NOT IN ('contexts','expected_aggregate_version')) THEN
      RAISE invalid_parameter_value USING MESSAGE='invalid context revision envelope'; END IF;
    v_versioned:=true;v_expected:=(p_contexts->>'expected_aggregate_version')::bigint;
    p_contexts:=p_contexts->'contexts';
  END IF;
  SELECT occasion INTO v_occasion FROM public.client_mutation_receipts WHERE command_id=p_command_id AND actor_id=v_actor AND command_name='inventory.product.contexts';
  IF NOT FOUND THEN
  SELECT p.occasion INTO v_occasion FROM eshop.products p WHERE p.id=p_product_id;
  END IF;
  IF v_actor IS NULL OR v_occasion IS NULL OR p_contexts IS NULL
    OR jsonb_typeof(p_contexts)<>'array' OR jsonb_array_length(p_contexts)>1000
    OR octet_length(p_contexts::text)>1048576
    OR NOT public.get_is_editor_order_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='inventory editor required'; END IF;
  SELECT coalesce(jsonb_agg(c ORDER BY (c->>'inventory_context_id')::bigint),'[]') INTO p_contexts FROM jsonb_array_elements(p_contexts) c;
  v_hash:=encode(extensions.digest(convert_to((jsonb_build_object(
    'productId',p_product_id,'contexts',p_contexts) || CASE WHEN v_versioned THEN jsonb_build_object('expectedVersion',v_expected) ELSE '{}'::jsonb END)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.product.contexts',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_contexts) c
      LEFT JOIN public.inventory_contexts ic
        ON ic.id=(c->>'inventory_context_id')::bigint
      LEFT JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool
      WHERE ip.occasion IS DISTINCT FROM v_occasion
        OR COALESCE((c->>'quantity')::integer,0)<0)
 THEN RAISE insufficient_privilege USING MESSAGE='foreign inventory context'; END IF;

  SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_users
  FROM eshop.order_product_ticket opt JOIN public.occasion_users ou
    ON ou.ticket=opt.ticket AND ou.occasion=v_occasion
  WHERE opt.product=p_product_id;
  PERFORM public.lock_product_order_dependencies_internal_v1(p_product_id);
  PERFORM 1 FROM eshop.products WHERE id=p_product_id AND occasion=v_occasion FOR UPDATE;
  SELECT coalesce(v.version,0) INTO v_version FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
    ON v.aggregate_type='product' AND v.scope_type='occasion' AND v.scope_id=v_occasion AND v.aggregate_id=p_product_id::text;
  IF v_versioned AND v_expected IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
      jsonb_build_object('productId',p_product_id,'aggregate_version',v_version)); END IF;
  PERFORM public.update_product_inventory_contexts_internal_v1(
    p_product_id,p_contexts);
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.product.contexts',jsonb_build_array(jsonb_build_object(
      'entityType','product_inventory_context','entityId',p_product_id,
      'operation','update','safeLabel','Product inventory contexts',
      'changedFields',jsonb_build_array('contexts'))),v_users,
    jsonb_build_object('productId',p_product_id,'aggregate_version',v_version+1));
END; $function$;
REVOKE ALL ON FUNCTION public.update_product_inventory_contexts_client_sync_v1(bigint,jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_product_inventory_contexts_client_sync_v1(bigint,jsonb,uuid) TO authenticated;
