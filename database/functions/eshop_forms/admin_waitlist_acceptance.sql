-- Service-only rollback preview, used by the same administrative Edge channel.
CREATE OR REPLACE FUNCTION public.preview_admin_waitlist_acceptance(p_administration jsonb,p_payload jsonb,p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE previous_sub text:=current_setting('request.jwt.claim.sub',true); occ bigint;fid bigint;
 facts jsonb;result jsonb;quote jsonb;offer uuid;
BEGIN
 PERFORM public.require_client_sync_service_role_v1();
 IF p_actor IS NULL OR jsonb_typeof(p_payload)<>'object' OR p_payload ? 'token' OR octet_length(p_payload::text)>1048576 THEN
  RAISE insufficient_privilege USING MESSAGE='administrative acceptance actor required'; END IF;
 occ:=(p_administration->>'occasionId')::bigint;fid:=(p_administration->>'formId')::bigint;offer:=(p_payload->>'offerId')::uuid;
 PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
 PERFORM public.check_form_order_scope_internal(occ,(p_administration->>'organizationId')::bigint,(p_administration->>'unitId')::bigint,fid);
 PERFORM public.lock_form_order_internal(occ,fid);
 PERFORM public.get_form_waitlist_context(occ,(p_administration->>'organizationId')::bigint,(p_administration->>'unitId')::bigint,fid,'accept',p_payload);
 p_payload:=(p_payload-ARRAY['approvalHash','administrativeApproval'])||jsonb_build_object('orderDetails',public.form_order_input_internal(fid,p_payload->'orderDetails'));
 facts:=jsonb_build_object('form',public.form_order_facts_internal(fid),'offer',(SELECT to_jsonb(w) FROM eshop.waitlist_offers w WHERE id=offer),
  'slots',(SELECT jsonb_agg(to_jsonb(s) ORDER BY s.id) FROM eshop.waitlist_offer_slots s WHERE s.offer_id=offer));
 BEGIN
  result:=public.execute_waitlist_command_client_sync_v1('accept',p_payload,extensions.gen_random_uuid(),extensions.gen_random_uuid(),p_actor,'[]');
  IF (result->>'code')::int=200 THEN quote:=public.form_order_quote_internal((result#>>'{data,order,id}')::bigint); END IF;
  RAISE SQLSTATE 'P0F91' USING MESSAGE='rollback waiting acceptance quote';
 EXCEPTION WHEN SQLSTATE 'P0F91' THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);
 IF (result->>'code')::int<>200 THEN RETURN jsonb_build_object('code',422,'reason','ORDER_NOT_CREATABLE','occasionId',occ,'formId',fid,'actorId',p_actor); END IF;
 RETURN jsonb_build_object('code',200,'quote',quote,'occasionId',occ,'formId',fid,'actorId',p_actor,'confirmationHash',
  encode(extensions.digest(jsonb_build_object('actor',p_actor,'scope',p_administration,'payload',p_payload,'facts',facts,'quote',quote)::text,'sha256'),'hex'));
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('request.jwt.claim.sub',coalesce(previous_sub,''),true);RAISE;
END $$;
REVOKE ALL ON FUNCTION public.preview_admin_waitlist_acceptance(jsonb,jsonb,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.preview_admin_waitlist_acceptance(jsonb,jsonb,uuid) TO service_role;
