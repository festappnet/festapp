-- Scope/delegation adapters only. Existing waitlist command and encrypted email
-- delivery pipeline own mutation, receipt, ticket identity and notifications.
CREATE OR REPLACE FUNCTION public.get_form_waitlist_context(p_occasion bigint,p_organization bigint,p_unit bigint,p_form bigint,
 p_operation text,p_payload jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb; offer uuid; oid bigint;
BEGIN
 IF p_operation IS NULL OR p_operation NOT IN('proposal','detail','send','cancel','withdraw','accept','decline') OR jsonb_typeof(p_payload)<>'object' THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid waitlist intent'; END IF;
 PERFORM public.check_form_order_scope_internal(p_occasion,p_organization,p_unit,p_form,p_operation<>'detail');
 IF p_operation IN('detail','withdraw') THEN
  oid:=(p_payload->>'orderId')::bigint;
  IF NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=oid AND form=p_form AND occasion=p_occasion) THEN
   RAISE insufficient_privilege USING MESSAGE='foreign waiting order'; END IF;
 ELSIF p_operation IN('cancel','accept','decline') THEN
  offer:=(p_payload->>'offerId')::uuid;
  IF NOT EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE id=offer AND form_id=p_form) THEN
   RAISE insufficient_privilege USING MESSAGE='foreign offer'; END IF;
 ELSIF p_operation='send' THEN
  IF (p_payload->>'formId')::bigint IS DISTINCT FROM p_form OR
   jsonb_typeof(p_payload->'recipients') IS DISTINCT FROM 'array' OR jsonb_array_length(p_payload->'recipients') NOT BETWEEN 1 AND 100 OR
   EXISTS(SELECT 1 FROM jsonb_array_elements(p_payload->'recipients') r WHERE NOT EXISTS(
     SELECT 1 FROM eshop.orders o WHERE o.id=(r->>'orderId')::bigint AND o.form=p_form AND o.occasion=p_occasion)) THEN
   RAISE insufficient_privilege USING MESSAGE='foreign waitlist recipients'; END IF;
 END IF;
 IF p_operation='proposal' THEN
  IF coalesce((p_payload->>'limit')::int,50) NOT BETWEEN 1 AND 100 THEN RAISE invalid_parameter_value USING MESSAGE='invalid waitlist page'; END IF;
  result:=public.get_waitlist_offer_proposal_internal(p_form,(p_payload->>'after')::bigint,coalesce((p_payload->>'limit')::int,50));
 ELSIF p_operation='detail' THEN result:=public.get_waitlist_order_detail(oid);
 ELSE result:='{}'; END IF;
 IF octet_length(result::text)>1048576 THEN RAISE program_limit_exceeded USING MESSAGE='waitlist detail too large'; END IF;
 RETURN jsonb_build_object('occasionId',p_occasion,'formId',p_form,'result',result);
END $$;
REVOKE ALL ON FUNCTION public.get_form_waitlist_context(bigint,bigint,bigint,bigint,text,jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_form_waitlist_context(bigint,bigint,bigint,bigint,text,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.execute_admin_waitlist_command_client_sync_v1(p_administration jsonb,p_operation text,p_payload jsonb,
 p_command_id uuid,p_client_id uuid,p_actor uuid,p_deliveries jsonb DEFAULT '[]')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE previous_sub text:=current_setting('request.jwt.claim.sub',true); result jsonb; occ bigint; fid bigint;
 prior jsonb; preview jsonb; quote jsonb; receipt_status text;
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 IF p_actor IS NULL OR p_operation NOT IN('send','cancel','withdraw','accept','decline') THEN RAISE insufficient_privilege USING MESSAGE='administrative waitlist actor required'; END IF;
 occ:=(p_administration->>'occasionId')::bigint;fid:=(p_administration->>'formId')::bigint;
 PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
 PERFORM public.check_form_order_scope_internal(occ,(p_administration->>'organizationId')::bigint,(p_administration->>'unitId')::bigint,fid);
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 PERFORM 1 FROM public.forms WHERE id=fid FOR UPDATE;
 PERFORM public.get_form_waitlist_context(occ,(p_administration->>'organizationId')::bigint,(p_administration->>'unitId')::bigint,fid,p_operation,p_payload);
 IF p_operation='accept' THEN
  p_payload:=p_payload||jsonb_build_object('orderDetails',public.form_order_input_internal(fid,p_payload->'orderDetails'));
  IF p_payload->>'approvalHash' IS NULL OR p_payload->>'approvalHash' !~ '^[a-f0-9]{64}$' THEN
   RAISE invalid_parameter_value USING MESSAGE='waiting acceptance approval required'; END IF;
  SELECT response,status INTO prior,receipt_status FROM public.client_mutation_receipts WHERE command_id=p_command_id
   AND actor_id=p_actor AND occasion=occ AND command_name='inventory.waitlist.accept';
  IF receipt_status='expired' THEN
   PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
   RETURN jsonb_build_object('code',410,'errorCode','COMMAND_EXPIRED_DO_NOT_REPLAY'); END IF;
  IF prior IS NULL THEN
   preview:=public.preview_admin_waitlist_acceptance(p_administration,p_payload,p_actor);
   IF (preview->>'code')::int<>200 OR preview->>'confirmationHash' IS DISTINCT FROM p_payload->>'approvalHash' THEN
    PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
    RETURN jsonb_build_object('code',409,'errorCode','ORDER_CHANGED_REPREVIEW_REQUIRED'); END IF;
   quote:=preview->'quote';
  ELSE quote:=prior#>'{data,adminQuote}'; END IF;
  p_payload:=p_payload||jsonb_build_object('administrativeApproval',jsonb_build_object('quote',quote,
   'scope',jsonb_build_object('occasionId',occ,'formId',fid,'actorId',p_actor)));
 END IF;
 result:=public.execute_waitlist_command_client_sync_v1(p_operation,p_payload,p_command_id,p_client_id,p_actor,p_deliveries);
 IF p_operation='accept' AND (result->>'code')::int=200 THEN
  IF prior IS NULL AND public.form_order_quote_internal((result#>>'{data,order,id}')::bigint) IS DISTINCT FROM quote THEN
   RAISE serialization_failure USING MESSAGE='waiting acceptance quote changed'; END IF;
  result:=result||jsonb_build_object('data',(result->'data')||jsonb_build_object('quote',result#>'{data,adminQuote}'));
 END IF;

 PERFORM public.get_form_waitlist_context(occ,(p_administration->>'organizationId')::bigint,(p_administration->>'unitId')::bigint,fid,p_operation,p_payload);
 PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
 RETURN result;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true); RAISE;
END $$;
REVOKE ALL ON FUNCTION public.execute_admin_waitlist_command_client_sync_v1(jsonb,text,jsonb,uuid,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.execute_admin_waitlist_command_client_sync_v1(jsonb,text,jsonb,uuid,uuid,uuid,jsonb) TO service_role;
