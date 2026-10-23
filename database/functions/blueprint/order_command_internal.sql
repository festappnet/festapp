CREATE OR REPLACE FUNCTION public.replace_blueprint_order_command_internal(
 p_spot_ids bigint[],p_input_data jsonb,p_command_id uuid,p_confirmation jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE actor uuid:=auth.uid();occ bigint;started jsonb;fingerprint text;before_users uuid[];
 effect jsonb;result jsonb;quote jsonb;ids bigint[];failure text;
BEGIN
 SELECT min(occasion) INTO occ FROM eshop.spots WHERE id=ANY(p_spot_ids);
 IF actor IS NULL OR occ IS NULL OR coalesce(cardinality(p_spot_ids),0)=0
  OR (SELECT count(*) FROM eshop.spots WHERE id=ANY(p_spot_ids) AND occasion=occ)<>
    cardinality(ARRAY(SELECT DISTINCT id FROM unnest(p_spot_ids) id))
  OR public.can_write_orders(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 fingerprint:=encode(extensions.digest(convert_to((jsonb_build_object('spots',p_spot_ids,'input',p_input_data)
  ||CASE WHEN p_confirmation IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('confirmation',p_confirmation) END)::text,'UTF8'),'sha256'),'hex');
 started:=public.begin_client_mutation_v1(p_command_id,'inventory.order.replace',occ,actor,fingerprint);
 IF started->>'disposition'='replay' THEN
  IF public.can_write_orders(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  RETURN public.project_local_payment_reference_order_internal(started->'response'); END IF;
 SELECT coalesce(array_agg(ou."user"),'{}') INTO before_users FROM public.occasion_users ou WHERE ou.occasion=occ;
 BEGIN
  ids:=CASE WHEN p_confirmation IS NULL THEN p_spot_ids ELSE
   public.blueprint_seat_order_selection_internal(occ,(p_confirmation->>'blueprint')::bigint,p_spot_ids,20000) END;
  effect:=public.apply_blueprint_seat_order_internal(ids,p_input_data,p_command_id);
  result:=effect->'result'||jsonb_build_object('paymentPreparationPolicy','leased_keep_pending');
  IF p_confirmation IS NOT NULL THEN
   quote:=public.blueprint_seat_order_quote_internal(effect);
   IF effect->>'confirmationHash' IS DISTINCT FROM p_confirmation->>'hash'
    OR quote->'spotIds' IS DISTINCT FROM p_confirmation->'targets'
    OR quote->'affectedSpotIds' IS DISTINCT FROM p_confirmation->'affected'
    OR quote->'blueprints' IS DISTINCT FROM p_confirmation->'blueprints' THEN
    RAISE SQLSTATE 'BP002' USING MESSAGE='BLUEPRINT_ORDER_CHANGED'; END IF;
  END IF;
 EXCEPTION WHEN SQLSTATE 'BP002' THEN
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,jsonb_build_object('reason','BLUEPRINT_ORDER_CHANGED'));
 WHEN serialization_failure OR deadlock_detected OR insufficient_privilege THEN RAISE;
 WHEN check_violation THEN
  IF public.can_write_orders(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  GET STACKED DIAGNOSTICS failure=PG_EXCEPTION_DETAIL;
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',CASE WHEN p_confirmation IS NULL THEN 400 ELSE 409 END,
   CASE WHEN p_confirmation IS NULL AND left(failure,1)='{' THEN failure::jsonb
   ELSE public.blueprint_order_rejection_internal(SQLERRM,failure) END);
 WHEN OTHERS THEN
  IF p_confirmation IS NULL THEN RAISE; END IF;
  IF public.can_write_orders(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,public.blueprint_order_rejection_internal(SQLERRM,NULL));
 END;
 IF public.can_write_orders(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 PERFORM public.check_occasion_writable(occ);
 IF p_confirmation IS NOT NULL THEN result:=result||jsonb_build_object('quote',quote); END IF;
 RETURN public.complete_profile_inventory_membership_mutation_v1(p_command_id,occ,'inventory.order.replace',
  jsonb_build_array(jsonb_build_object('entityType','order','entityId',result#>>'{order,id}','operation','insert',
   'safeLabel','Blueprint order replacement','changedFields',jsonb_build_array('cancellations','tickets','products','allocations','membership'))),
  before_users,result);
END $$;
REVOKE ALL ON FUNCTION public.replace_blueprint_order_command_internal(bigint[],jsonb,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
