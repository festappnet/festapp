CREATE OR REPLACE FUNCTION public.storno_order_client_sync_v1(p_order bigint, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_before_users uuid[]; v_unchanged boolean:=false;
BEGIN
  PERFORM public.lock_blueprint_scope_internal(ARRAY[(SELECT occasion FROM eshop.orders WHERE id=p_order)]);
  SELECT o.occasion INTO v_occasion FROM eshop.orders o WHERE o.id=p_order;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR NOT public.can_write_orders(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'order',p_order)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.order.cancel',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  -- A committed cancellation needs only a receipt, without another admission.
  IF (SELECT state FROM eshop.orders WHERE id=p_order)='storno' THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      jsonb_build_object('orderId',p_order));
  END IF;
  BEGIN
    -- Preserve admission -> domain locks, also relative to deletion. If another
    -- cancellation wins while waiting, roll back this attempt's admission.
    PERFORM public.admit_order_mutation_v1(v_occasion,(SELECT count(*) FROM eshop.order_product_ticket WHERE "order"=p_order));
    PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]);
    IF (SELECT state FROM eshop.orders WHERE id=p_order)='storno' THEN
      RAISE SQLSTATE 'P0C01' USING MESSAGE='cancellation already committed'; END IF;
    SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
      FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
    PERFORM public.update_order_and_tickets_to_storno_ws_internal_v1(p_order);
  EXCEPTION WHEN SQLSTATE 'P0C01' THEN v_unchanged:=true;
  END;
  IF v_unchanged THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      jsonb_build_object('orderId',p_order));
  END IF;
  RETURN public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,v_occasion,'inventory.order.cancel',
    jsonb_build_array(jsonb_build_object('entityType','order','entityId',p_order,
      'operation','update','safeLabel','Order cancellation',
      'changedFields',jsonb_build_array('state','tickets','membership','allocations'))),
    v_before_users,jsonb_build_object('orderId',p_order));
END; $function$;

REVOKE ALL ON FUNCTION public.storno_order_client_sync_v1(bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.storno_order_client_sync_v1(bigint,uuid) TO authenticated;
