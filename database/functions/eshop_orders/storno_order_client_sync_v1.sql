CREATE OR REPLACE FUNCTION public.storno_order_client_sync_v1(p_order bigint, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_before_users uuid[];
BEGIN
  SELECT o.occasion INTO v_occasion FROM eshop.orders o WHERE o.id=p_order;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR NOT public.get_is_editor_order_on_occasion(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'order',p_order)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.order.cancel',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM public.admit_order_mutation_v1(v_occasion,(SELECT count(*) FROM eshop.order_product_ticket WHERE "order"=p_order));
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  PERFORM public.update_order_and_tickets_to_storno_ws_internal_v1(p_order);
  RETURN public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,v_occasion,'inventory.order.cancel',
    jsonb_build_array(jsonb_build_object('entityType','order','entityId',p_order,
      'operation','update','safeLabel','Order cancellation',
      'changedFields',jsonb_build_array('state','tickets','membership','allocations'))),
    v_before_users,jsonb_build_object('orderId',p_order));
END; $function$;

REVOKE ALL ON FUNCTION public.storno_order_client_sync_v1(bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.storno_order_client_sync_v1(bigint,uuid) TO authenticated;
