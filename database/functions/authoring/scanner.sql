-- Reuse scanner projection, admission and operation receipts. Session credentials
-- remain inside this transaction; there is no second scan ledger or admission rule.
CREATE OR REPLACE FUNCTION public.manage_scanner_authoring(p_occasion bigint,p_organization bigint,p_unit bigint,p_action text,p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE cfg public.scanner_settings%ROWTYPE; projection jsonb; prior public.scanner_operations%ROWTYPE;
 session_data jsonb; session_id uuid; session_token text; op jsonb; expected jsonb; result jsonb; op_id uuid;
 ticket bigint:=(p_payload->>'ticketId')::bigint;
BEGIN
 PERFORM public.lock_people_scope_internal_v1(p_occasion,p_organization,p_unit);
 PERFORM public.scanner_require_settings_editor_internal(p_occasion);
 IF ticket IS NULL OR NOT EXISTS(SELECT 1 FROM eshop.tickets WHERE id=ticket AND occasion=p_occasion) THEN
  RAISE insufficient_privilege USING MESSAGE='ticket outside scanner scope'; END IF;
 SELECT * INTO cfg FROM public.scanner_settings WHERE occasion_id=p_occasion FOR SHARE;
 IF cfg.occasion_id IS NULL THEN cfg.config:=public.scanner_default_settings_internal(p_occasion);cfg.revision:=1; END IF;
 IF p_action='inspect' THEN
  SELECT dto INTO projection FROM public.scanner_ticket_projection_internal(p_occasion,cfg.config,ticket);
  IF projection IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='issued ticket required'; END IF;
  RETURN jsonb_build_object('ticketId',ticket,'state',projection->'state','settingsRevision',cfg.revision,
   'admissionAllowed',coalesce(projection->'admission_allowed','false'),'requiresUnpaidConfirmation',coalesce(projection->'requires_unpaid_confirmation','false'),
   'eligibilityFingerprint',projection->'eligibility_fingerprint');
 END IF;
 IF p_action<>'admit' OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object'
  OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN ('ticketId','operationId','eligibilityFingerprint','settingsRevision','confirmUnpaid','capturedAt'))
  OR (p_payload->>'eligibilityFingerprint') !~ '^[a-f0-9]{64}$'
  OR jsonb_typeof(p_payload->'confirmUnpaid') IS DISTINCT FROM 'boolean' THEN
  RAISE invalid_parameter_value USING MESSAGE='exact scanner intent required'; END IF;
 op_id:=(p_payload->>'operationId')::uuid;
 PERFORM (p_payload->>'capturedAt')::timestamptz;
 IF op_id IS NULL OR p_payload->>'capturedAt' IS NULL OR p_payload->>'settingsRevision' IS NULL THEN
  RAISE invalid_parameter_value USING MESSAGE='scanner identity/baseline required'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(op_id::text,5317));
 SELECT * INTO prior FROM public.scanner_operations WHERE operation_id=op_id;
 IF prior.operation_id IS NOT NULL THEN
  IF prior.occasion_id IS DISTINCT FROM p_occasion OR NOT EXISTS(SELECT 1 FROM public.scanner_sessions WHERE id=prior.session_id AND actor_user_id=auth.uid()) THEN
   RAISE insufficient_privilege USING MESSAGE='scanner receipt actor mismatch'; END IF;
  session_id:=prior.session_id;
 ELSE
  session_data:=public.open_scanner_session(NULL,p_occasion,'MCP confirmed admission');
  IF (session_data->>'code')::int<>200 THEN RETURN session_data; END IF;
  session_id:=(session_data#>>'{data,session_id}')::uuid;session_token:=session_data#>>'{data,token}';
 END IF;
 op:=jsonb_build_object('operation_id',op_id,'origin_session_id',session_id,'occasion_id',p_occasion,'ticket_id',ticket,'action','admit_ticket',
  'snapshot_id',NULL,'settings_revision',p_payload->'settingsRevision','eligibility_fingerprint',p_payload->'eligibilityFingerprint',
  'confirm_unpaid',p_payload->'confirmUnpaid','captured_at',p_payload->'capturedAt');
 IF prior.operation_id IS NOT NULL THEN
  IF prior.payload IS DISTINCT FROM op THEN RAISE invalid_parameter_value USING MESSAGE='scanner receipt payload mismatch'; END IF;
  RETURN jsonb_build_object('code',200,'data',jsonb_build_array(prior.receipt||jsonb_build_object('replayed',true)));
 END IF;
 result:=public.sync_scanner_operations(session_id,session_token,jsonb_build_array(op));
 PERFORM public.revoke_scanner_session(session_id,session_token);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.manage_scanner_authoring(bigint,bigint,bigint,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.manage_scanner_authoring(bigint,bigint,bigint,text,jsonb) TO authenticated,service_role;
