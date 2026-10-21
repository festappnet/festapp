CREATE OR REPLACE FUNCTION public.update_blueprint_client_sync_v1(
  p_blueprint jsonb,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_blueprint bigint;
  v_begin jsonb; v_hash text; v_users uuid[]; v_result jsonb; v_reason text; v_detail text; v_issue jsonb;
BEGIN
  IF p_blueprint IS NULL OR jsonb_typeof(p_blueprint)<>'object'
    OR octet_length(p_blueprint::text)>8388608 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid blueprint aggregate'; END IF;
  SELECT occasion INTO v_occasion FROM public.client_mutation_receipts WHERE command_id=p_command_id AND actor_id=v_actor AND command_name='inventory.blueprint.save';
  IF NOT FOUND THEN
  v_occasion:=NULLIF(p_blueprint->>'occasion','')::bigint;
  v_blueprint:=NULLIF(p_blueprint->>'id','')::bigint;
  IF v_blueprint IS NOT NULL THEN SELECT occasion INTO v_occasion FROM eshop.blueprints WHERE id=v_blueprint; END IF;
  ELSE v_blueprint:=NULLIF(p_blueprint->>'id','')::bigint; END IF;
  IF v_actor IS NULL OR v_occasion IS NULL
    OR public.can_write_blueprints(v_occasion) IS NOT TRUE THEN
    RAISE insufficient_privilege USING MESSAGE='blueprint editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',v_occasion,'blueprint',p_blueprint)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.blueprint.save',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF v_blueprint IS NOT NULL AND NOT EXISTS (SELECT 1 FROM eshop.blueprints b WHERE b.id=v_blueprint AND b.occasion=v_occasion) THEN RAISE insufficient_privilege USING MESSAGE='foreign blueprint'; END IF;
  PERFORM public.lock_blueprint_scope_internal(ARRAY[v_occasion]);
  SELECT COALESCE(array_agg(DISTINCT ou."user"),'{}'::uuid[]) INTO v_users
  FROM public.occasion_users ou JOIN eshop.order_product_ticket opt
    ON opt.ticket=ou.ticket JOIN eshop.spots s
    ON s.order_product_ticket=opt.id
  WHERE ou.occasion=v_occasion AND s.occasion=v_occasion;
  BEGIN
    IF p_blueprint->'layout' IS NULL OR p_blueprint->'layout'='null'::jsonb THEN RAISE check_violation USING MESSAGE='BLUEPRINT_LAYOUT_REQUIRED'; END IF;
    v_result:=public.save_blueprint_layout_internal_v1(p_blueprint);
  EXCEPTION WHEN check_violation OR raise_exception OR invalid_text_representation OR not_null_violation OR unique_violation OR foreign_key_violation THEN
    GET STACKED DIAGNOSTICS v_reason=MESSAGE_TEXT,v_detail=PG_EXCEPTION_DETAIL;
    v_issue:=jsonb_build_object('reason',v_reason);
    IF left(coalesce(v_detail,''),1)='{' THEN
      BEGIN v_issue:=v_issue||jsonb_strip_nulls(jsonb_build_object('nodeId',(v_detail::jsonb)->'nodeId','spotId',(v_detail::jsonb)->'spotId','groupNodeId',(v_detail::jsonb)->'groupNodeId'));
      EXCEPTION WHEN invalid_text_representation THEN NULL; END;
    END IF;
    v_result:=jsonb_build_object('code',409,'reason',CASE WHEN SQLSTATE IN ('23514','P0001') THEN v_reason ELSE 'BLUEPRINT_INVALID_INPUT' END,
      'issues',jsonb_build_array(v_issue),
      'layout_revision',(SELECT layout_revision FROM eshop.blueprints WHERE id=v_blueprint));
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,v_result);
  END;
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.blueprint.save',jsonb_build_array(jsonb_build_object(
      'entityType','blueprint','entityId',v_result->>'blueprint_id',
      'operation',CASE WHEN v_blueprint IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(p_blueprint->>'title',240),'changedFields',jsonb_build_array(
        'layout','bindings'))),v_users,v_result);
END; $$;
REVOKE ALL ON FUNCTION public.update_blueprint_client_sync_v1(jsonb,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_blueprint_client_sync_v1(jsonb,uuid)
  TO authenticated;
