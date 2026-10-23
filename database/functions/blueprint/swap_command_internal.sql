CREATE OR REPLACE FUNCTION public.swap_blueprint_seats_command_internal(
 p_first bigint,p_second bigint,p_command_id uuid,p_confirmation jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE actor uuid:=auth.uid();occ bigint;started jsonb;fingerprint text;users uuid[];
 effect jsonb;affected bigint[];result_data jsonb;money jsonb;
BEGIN
 SELECT occasion INTO occ FROM public.client_mutation_receipts
 WHERE command_id=p_command_id AND actor_id=actor AND command_name='inventory.spots.swap';
 IF NOT FOUND THEN SELECT min(occasion) INTO occ FROM eshop.spots WHERE id IN(p_first,p_second); END IF;
 IF actor IS NULL OR p_first IS NULL OR p_second IS NULL OR p_first=p_second OR occ IS NULL
  OR public.can_write_orders(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 fingerprint:=encode(extensions.digest(convert_to((jsonb_build_object('spot1',p_first,'spot2',p_second)
  ||CASE WHEN p_confirmation IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('confirmation',p_confirmation) END)::text,'UTF8'),'sha256'),'hex');
 started:=public.begin_client_mutation_v1(p_command_id,'inventory.spots.swap',occ,actor,fingerprint);
 IF started->>'disposition'='replay' THEN
  IF public.can_write_orders(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  RETURN started->'response';
 END IF;
 IF (SELECT count(*) FROM eshop.spots WHERE id IN(p_first,p_second) AND occasion=occ)<>2 THEN
  RAISE insufficient_privilege USING MESSAGE='foreign spot swap'; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 affected:=CASE WHEN p_confirmation IS NULL THEN ARRAY[p_first,p_second] ELSE
  public.blueprint_selection_unit_spots_internal(p_first)||public.blueprint_selection_unit_spots_internal(p_second) END;
 SELECT coalesce(array_agg(DISTINCT ou."user"),'{}') INTO users FROM eshop.spots s
 JOIN eshop.order_product_ticket i ON i.id=s.order_product_ticket
 JOIN public.occasion_users ou ON ou.ticket=i.ticket AND ou.occasion=occ WHERE s.id=ANY(affected);
 BEGIN
  effect:=public.apply_blueprint_seat_swap_internal(p_first,p_second);
  IF p_confirmation IS NOT NULL THEN money:=public.project_order_amount_changes_internal(effect->'orders'); END IF;
  IF p_confirmation IS NOT NULL AND
   (effect->>'confirmationHash' IS DISTINCT FROM p_confirmation->>'hash'
    OR effect->'sourceSpotIds' IS DISTINCT FROM p_confirmation->'source'
    OR effect->'targetSpotIds' IS DISTINCT FROM p_confirmation->'target'
    OR effect->'blueprints' IS DISTINCT FROM jsonb_build_array(jsonb_build_object(
     'id',(p_confirmation->>'blueprint')::bigint,'revision',(p_confirmation->>'revision')::bigint))) THEN
   RAISE SQLSTATE 'BP002' USING MESSAGE='confirmed swap changed'; END IF;
 EXCEPTION WHEN SQLSTATE 'BP002' THEN
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,jsonb_build_object('reason','BLUEPRINT_SWAP_CHANGED'));
 WHEN serialization_failure OR deadlock_detected OR insufficient_privilege THEN RAISE;
 WHEN OTHERS THEN
  IF p_confirmation IS NULL THEN RAISE; END IF;
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,jsonb_build_object('reason','BLUEPRINT_SWAP_REJECTED'));
 END;
 -- Legacy adapters share the same late guard, not just the scoped UI/MCP RPC.
 IF public.can_write_orders(occ) IS NOT TRUE OR
  (SELECT count(*) FROM eshop.spots WHERE id IN(p_first,p_second) AND occasion=occ)<>2 THEN
  RAISE insufficient_privilege USING MESSAGE='swap selection unavailable'; END IF;
 PERFORM public.check_occasion_writable(occ);
 result_data:=jsonb_build_object('spotIds',jsonb_build_array(p_first,p_second));
 IF p_confirmation IS NOT NULL THEN
  result_data:=result_data||jsonb_build_object('blueprintId',(p_confirmation->>'blueprint')::bigint,
   'layoutRevision',(p_confirmation->>'revision')::bigint,'sourceSpotIds',effect->'sourceSpotIds',
   'targetSpotIds',effect->'targetSpotIds','orders',money);
 END IF;
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,occ,'inventory.spots.swap',
  jsonb_build_array(jsonb_build_object('entityType','spot_assignment','entityId',NULL,'operation','update',
   'safeLabel','Spot ticket swap','changedFields',jsonb_build_array('order_product_ticket','product'))),users,result_data);
END $$;
REVOKE ALL ON FUNCTION public.swap_blueprint_seats_command_internal(bigint,bigint,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
