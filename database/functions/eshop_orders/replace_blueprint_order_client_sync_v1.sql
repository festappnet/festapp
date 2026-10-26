CREATE OR REPLACE FUNCTION public.confirm_blueprint_order_change_client_sync_v1(
  p_spot_ids bigint[],p_input_data jsonb,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_begin jsonb; v_hash text;
  v_result jsonb; v_before_users uuid[];
BEGIN
  PERFORM public.lock_blueprint_scope_internal(ARRAY(SELECT DISTINCT occasion FROM eshop.spots WHERE id=ANY(p_spot_ids)));
  SELECT min(s.occasion) INTO v_occasion FROM eshop.spots s
    WHERE s.id=ANY(p_spot_ids);
  IF v_actor IS NULL OR v_occasion IS NULL OR cardinality(p_spot_ids)=0
    OR (SELECT count(*) FROM eshop.spots s
      WHERE s.id=ANY(p_spot_ids) AND s.occasion=v_occasion)
      <>cardinality(ARRAY(SELECT DISTINCT id FROM unnest(p_spot_ids) id))
    OR NOT public.can_write_orders(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  IF public.payment_reference_scope_enabled_internal((SELECT id FROM public.forms WHERE occasion=v_occasion ORDER BY id LIMIT 1)) THEN
    RETURN jsonb_build_object('status','rejected','code',409,'data',jsonb_build_object('errorCode','ATOMIC_REPLACEMENT_REQUIRED')); END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'spots',p_spot_ids,'input',p_input_data)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.order.prepare_replace',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN public.project_local_payment_reference_order_internal(v_begin->'response'); END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  v_result:=public.confirm_blueprint_order_change_internal_v1(
    p_spot_ids,p_input_data);
  IF COALESCE((v_result->>'success')::boolean,false) IS NOT TRUE THEN
    RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,'rejected',400,v_result); END IF;
  RETURN public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,v_occasion,'inventory.order.prepare_replace',
    jsonb_build_array(jsonb_build_object('entityType','order','entityId',NULL,
      'operation','update','safeLabel','Blueprint order replacement',
      'changedFields',jsonb_build_array('cancellations','allocations'))),
    v_before_users,v_result);
END; $$;
REVOKE ALL ON FUNCTION public.confirm_blueprint_order_change_client_sync_v1(
  bigint[],jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.confirm_blueprint_order_change_client_sync_v1(
  bigint[],jsonb,uuid) TO authenticated;

-- Released clients keep their exact original fingerprint and response projection.
CREATE OR REPLACE FUNCTION public.replace_blueprint_order_client_sync_v1(p_spot_ids bigint[],p_input_data jsonb,p_command_id uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.replace_blueprint_order_command_internal(p_spot_ids,p_input_data,p_command_id,NULL)
$$;
REVOKE ALL ON FUNCTION public.replace_blueprint_order_client_sync_v1(bigint[],jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.replace_blueprint_order_client_sync_v1(bigint[],jsonb,uuid) TO authenticated;
