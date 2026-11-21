CREATE OR REPLACE FUNCTION public.update_ticket_products_client_sync_v1(p_ticket bigint, p_products jsonb, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public,extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_users uuid[]; v_result jsonb;
BEGIN
  SELECT t.occasion INTO v_occasion FROM eshop.tickets t WHERE t.id=p_ticket;
  IF v_actor IS NULL OR v_occasion IS NULL OR p_products IS NULL
    OR jsonb_typeof(p_products)<>'array' OR jsonb_array_length(p_products)>1000
    OR octet_length(p_products::text)>1048576
    OR NOT public.can_write_orders(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'ticket',p_ticket,'products',p_products)::text,'UTF8'),'sha256'),'hex');
  PERFORM public.lock_blueprint_scope_internal(ARRAY[v_occasion]);
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.ticket.products',v_occasion,v_actor,v_hash);
  IF public.can_write_orders(v_occasion) IS NOT TRUE THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required';
  END IF;
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_users
    FROM public.occasion_users ou
    WHERE ou.occasion=v_occasion AND ou.ticket=p_ticket;
  BEGIN
    v_result:=public.update_ticket_products_internal_v1(p_ticket,p_products);
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT IN ('ADMISSION_CHANGE_REQUIRES_COMMAND','ADMISSION_DATA_AMBIGUOUS') THEN RAISE; END IF;
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('reason',SQLERRM));
  END;
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.ticket.products',jsonb_build_array(jsonb_build_object(
      'entityType','ticket_products','entityId',p_ticket,'operation','update',
      'safeLabel','Ticket products','changedFields',jsonb_build_array(
        'products','allocations'))),v_users,v_result);
END; $function$
;
REVOKE ALL ON FUNCTION public.update_ticket_products_client_sync_v1(bigint,jsonb,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.update_ticket_products_client_sync_v1(bigint,jsonb,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.update_ticket_products_client_sync_v1(bigint,jsonb,uuid) TO authenticated;
