CREATE OR REPLACE FUNCTION public.swap_spot_tickets_client_sync_v1(p_spot_1 bigint, p_spot_2 bigint, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_users uuid[];
BEGIN
  SELECT occasion INTO v_occasion FROM public.client_mutation_receipts WHERE command_id=p_command_id AND actor_id=v_actor AND command_name='inventory.spots.swap';
  IF NOT FOUND THEN
  SELECT min(s.occasion) INTO v_occasion FROM eshop.spots s
    WHERE s.id IN (p_spot_1,p_spot_2);
  END IF;
  IF v_actor IS NULL OR p_spot_1 IS NULL OR p_spot_2 IS NULL
    OR p_spot_1=p_spot_2 OR v_occasion IS NULL
    OR NOT public.can_write_orders(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'spot1',p_spot_1,'spot2',p_spot_2)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.spots.swap',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF (SELECT count(*) FROM eshop.spots s
      WHERE s.id IN (p_spot_1,p_spot_2) AND s.occasion=v_occasion)<>2
 THEN RAISE insufficient_privilege USING MESSAGE='foreign spot swap'; END IF;

  PERFORM public.lock_blueprint_scope_internal(ARRAY[v_occasion]);
  PERFORM public.lock_spot_assignment_scope_internal_v1(ARRAY[p_spot_1,p_spot_2]);
  SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_users
  FROM eshop.spots s JOIN eshop.order_product_ticket opt
    ON opt.id=s.order_product_ticket JOIN public.occasion_users ou
    ON ou.ticket=opt.ticket AND ou.occasion=v_occasion
  WHERE s.id IN (p_spot_1,p_spot_2);
  PERFORM public.swap_spot_tickets_internal_v1(p_spot_1,p_spot_2);
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.spots.swap',jsonb_build_array(jsonb_build_object(
      'entityType','spot_assignment','entityId',NULL,'operation','update',
      'safeLabel','Spot ticket swap','changedFields',jsonb_build_array(
        'order_product_ticket','product'))),v_users,jsonb_build_object(
          'spotIds',jsonb_build_array(p_spot_1,p_spot_2)));
END; $function$;

REVOKE ALL ON FUNCTION public.swap_spot_tickets_client_sync_v1(bigint,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.swap_spot_tickets_client_sync_v1(bigint,bigint,uuid) TO authenticated;
