CREATE OR REPLACE FUNCTION public.stage_wix_billing_delivery(p_app uuid,p_event jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ident text:=p_event->>'receiptId'; delivery_kind text:=p_event#>>'{requestBody,event,billingType}';
 digest text:=encode(extensions.digest(p_event::text,'sha256'),'hex'); prior public.wix_billing_deliveries;
BEGIN
 PERFORM public.require_service_role();
 IF jsonb_typeof(p_event#>'{basis,refundSequence}') IS DISTINCT FROM 'string'
  OR coalesce(p_event#>>'{basis,refundSequence}','') !~ '^(0|[1-9][0-9]{0,18})$'
  OR (delivery_kind='CHARGE' AND p_event#>>'{basis,refundSequence}'<>'0')
  OR (delivery_kind='REFUND' AND p_event#>>'{basis,refundSequence}'='0') THEN
  RAISE invalid_parameter_value USING MESSAGE='WIX_REPORT_V2_REQUIRED'; END IF;
 IF ident IS NULL OR delivery_kind IS NULL OR p_event->>'instanceId' IS NULL OR jsonb_typeof(p_event#>'{requestBody,event}') IS DISTINCT FROM 'object'
  OR octet_length(p_event::text)>32768 THEN RAISE invalid_parameter_value USING MESSAGE='INVALID_WIX_DELIVERY'; END IF;
 INSERT INTO public.wix_billing_deliveries(app_id,receipt_id,kind,instance_id,payload,payload_digest)
 VALUES(p_app,ident,delivery_kind,(p_event->>'instanceId')::uuid,p_event,digest) ON CONFLICT DO NOTHING;
 SELECT * INTO STRICT prior FROM public.wix_billing_deliveries WHERE app_id=p_app AND receipt_id=ident AND wix_billing_deliveries.kind=delivery_kind FOR UPDATE;
 IF prior.payload_digest<>digest THEN RAISE check_violation USING MESSAGE='WIX_DELIVERY_DIGEST_CONFLICT'; END IF;
 RETURN jsonb_build_object('state',prior.state,'digest',prior.payload_digest);
END $$;

CREATE OR REPLACE FUNCTION public.claim_wix_billing_delivery(p_app uuid,p_receipt text,p_kind text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE row public.wix_billing_deliveries; token uuid:=extensions.gen_random_uuid();
BEGIN
 PERFORM public.require_service_role();
 -- Activation changes serialize with claims. There is intentionally no enable RPC.
 PERFORM 1 FROM public.wix_billing_activation WHERE app_id=p_app AND enabled FOR SHARE;
 IF NOT FOUND THEN RAISE check_violation USING MESSAGE='WIX_BILLING_NOT_ACTIVATED'; END IF;
 SELECT * INTO STRICT row FROM public.wix_billing_deliveries WHERE app_id=p_app AND receipt_id=p_receipt AND kind=p_kind FOR UPDATE;
 IF row.payload->>'agreementReference' IS DISTINCT FROM (SELECT signed_addendum_reference FROM public.wix_billing_activation WHERE app_id=p_app) THEN
  RAISE check_violation USING MESSAGE='WIX_ACTIVATED_TERMS_MISMATCH'; END IF;
 IF row.state='sending' AND row.lease_until<=clock_timestamp() THEN
  UPDATE public.wix_billing_deliveries SET state='unknown',lease_until=NULL WHERE app_id=p_app AND receipt_id=p_receipt AND kind=p_kind;
  UPDATE public.wix_billing_attempts SET outcome='unknown',finished_at=clock_timestamp(),evidence='{"reason":"expired-attempt"}' WHERE id=row.attempt_id;
  RETURN jsonb_build_object('state','unknown');
 END IF;
 IF row.state<>'prepared' THEN RETURN jsonb_build_object('state',row.state); END IF;
 IF p_kind='REFUND' AND NOT EXISTS(SELECT 1 FROM public.wix_billing_deliveries
  WHERE app_id=p_app AND receipt_id=row.payload#>>'{basis,chargeReceiptId}' AND kind='CHARGE'
   AND instance_id=row.instance_id AND state='confirmed') THEN
  RAISE check_violation USING MESSAGE='WIX_ORIGINAL_CHARGE_UNCONFIRMED'; END IF;
 INSERT INTO public.wix_billing_attempts(id,app_id,receipt_id,kind) VALUES(token,p_app,p_receipt,p_kind);
 UPDATE public.wix_billing_deliveries SET state='sending',attempt_id=token,lease_until=clock_timestamp()+interval '60 seconds'
  WHERE app_id=p_app AND receipt_id=p_receipt AND kind=p_kind;
 RETURN jsonb_build_object('state','claimed','attemptId',token,'payload',row.payload,'instanceId',row.instance_id,'digest',row.payload_digest);
END $$;

CREATE OR REPLACE FUNCTION public.finish_wix_billing_delivery(p_app uuid,p_receipt text,p_kind text,p_attempt uuid,p_outcome text,p_evidence jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 IF p_outcome IS NULL OR p_outcome NOT IN('confirmed','rejected','unknown') OR jsonb_typeof(p_evidence) IS DISTINCT FROM 'object' OR octet_length(p_evidence::text)>8192 THEN
  RAISE invalid_parameter_value USING MESSAGE='INVALID_WIX_OUTCOME'; END IF;
 UPDATE public.wix_billing_deliveries SET state=p_outcome,lease_until=NULL
  WHERE app_id=p_app AND receipt_id=p_receipt AND kind=p_kind AND state='sending' AND attempt_id=p_attempt;
 IF NOT FOUND THEN RAISE check_violation USING MESSAGE='WIX_ATTEMPT_FENCE'; END IF;
 UPDATE public.wix_billing_attempts SET outcome=p_outcome,evidence=p_evidence,finished_at=clock_timestamp() WHERE id=p_attempt;
END $$;

CREATE OR REPLACE FUNCTION public.inspect_wix_billing_delivery(p_app uuid,p_receipt text,p_kind text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE row public.wix_billing_deliveries;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO STRICT row FROM public.wix_billing_deliveries WHERE app_id=p_app AND receipt_id=p_receipt AND kind=p_kind FOR UPDATE;
 IF row.state='sending' AND row.lease_until<=clock_timestamp() THEN
  UPDATE public.wix_billing_deliveries SET state='unknown',lease_until=NULL WHERE app_id=p_app AND receipt_id=p_receipt AND kind=p_kind RETURNING * INTO row;
  UPDATE public.wix_billing_attempts SET outcome='unknown',finished_at=clock_timestamp(),evidence='{"reason":"expired-attempt"}' WHERE id=row.attempt_id;
 END IF;
 RETURN to_jsonb(row)||jsonb_build_object('attempts',(SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY started_at),'[]') FROM public.wix_billing_attempts a WHERE a.app_id=p_app AND a.receipt_id=p_receipt AND a.kind=p_kind));
END $$;

CREATE OR REPLACE FUNCTION public.reconcile_wix_billing_delivery(p_app uuid,p_receipt text,p_kind text,p_attempt uuid,p_digest text,p_resolution text,p_evidence_reference text,p_operator_reference text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE row public.wix_billing_deliveries;
BEGIN
 PERFORM public.require_service_role();
 IF p_resolution IS NULL OR p_resolution NOT IN('accepted','proven-not-accepted')
  OR coalesce(length(btrim(p_evidence_reference)),0) NOT BETWEEN 1 AND 1000
  OR coalesce(length(btrim(p_operator_reference)),0) NOT BETWEEN 1 AND 1000 THEN
  RAISE invalid_parameter_value USING MESSAGE='WIX_RECONCILIATION_EVIDENCE_REQUIRED'; END IF;
 SELECT * INTO STRICT row FROM public.wix_billing_deliveries WHERE app_id=p_app AND receipt_id=p_receipt AND kind=p_kind FOR UPDATE;
 IF row.state NOT IN('unknown','rejected') OR row.attempt_id IS DISTINCT FROM p_attempt OR row.payload_digest IS DISTINCT FROM p_digest THEN
  RAISE check_violation USING MESSAGE='WIX_RECONCILIATION_FENCE'; END IF;
 UPDATE public.wix_billing_deliveries SET state=CASE WHEN p_resolution='accepted' THEN 'confirmed' ELSE 'prepared' END,
  reconciliation=reconciliation||jsonb_build_array(jsonb_build_object('attemptId',p_attempt,'digest',p_digest,'resolution',p_resolution,
   'evidenceReference',p_evidence_reference,'operatorReference',p_operator_reference,'at',clock_timestamp()))
  WHERE app_id=p_app AND receipt_id=p_receipt AND kind=p_kind;
 RETURN jsonb_build_object('state',CASE WHEN p_resolution='accepted' THEN 'confirmed' ELSE 'prepared' END);
END $$;

REVOKE ALL ON FUNCTION public.stage_wix_billing_delivery(uuid,jsonb),public.claim_wix_billing_delivery(uuid,text,text),
 public.finish_wix_billing_delivery(uuid,text,text,uuid,text,jsonb),public.inspect_wix_billing_delivery(uuid,text,text),
 public.reconcile_wix_billing_delivery(uuid,text,text,uuid,text,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.stage_wix_billing_delivery(uuid,jsonb),public.claim_wix_billing_delivery(uuid,text,text),
 public.finish_wix_billing_delivery(uuid,text,text,uuid,text,jsonb),public.inspect_wix_billing_delivery(uuid,text,text),
 public.reconcile_wix_billing_delivery(uuid,text,text,uuid,text,text,text,text) TO service_role;
