-- Meter authorized ticket resends per organizer and recipient at admission and send.

-- SOURCE: abuse/ticket_resend.sql
-- Admission and fenced sending use distinct counters with the same bounds.
INSERT INTO public.abuse_policy_rules
 (rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap)
SELECT budget||'.recipient.'||rule,s.budget,scope,'rolling',window_seconds,bucket_seconds,quota,quota
FROM (VALUES ('email.ticket_resend'),('email.send.ticket_resend')) s(budget)
CROSS JOIN (VALUES
 ('unit.burst','unit',60,60,2), ('unit.day','unit',86400,3600,5),
 ('global.burst','recipient',60,60,4), ('global.day','recipient',86400,3600,12)
) r(rule,scope,window_seconds,bucket_seconds,quota);

CREATE OR REPLACE FUNCTION public.ticket_resend_scopes_internal_v1(m public.email_messages)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE actor uuid; recipient_key text;
BEGIN
 IF m.message_kind IS DISTINCT FROM 'order_tickets' OR m.order_id IS NULL OR m.unit IS NULL OR m.recipient IS NULL
    OR COALESCE(m.data->>'requested_by','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
 THEN RETURN NULL; END IF;
 actor := (m.data->>'requested_by')::uuid;
 IF NOT EXISTS (
  SELECT 1 FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
  WHERE o.id=m.order_id AND o.occasion=m.occasion AND oc.organization=m.organization AND oc.unit=m.unit
   AND o.state IN ('paid','sent') AND o.email_payment_version=m.source_version
   AND lower(btrim(o.data->>'email'))=lower(btrim(m.recipient))
   AND (m.dedupe_key ~ '^(resend|repair|operator):'
        OR m.dedupe_key=public.order_email_automatic_key_internal(o.id,o.email_payment_version,o.data->>'email'))
 ) OR public.can_write_orders_as_actor_internal(actor,m.occasion) IS DISTINCT FROM TRUE
 THEN RETURN NULL; END IF;
 recipient_key := public.abuse_recipient_key_v1(m.recipient);
 RETURN jsonb_build_object('actor',actor,'unit',m.unit||':'||recipient_key,'recipient',recipient_key);
END $$;
REVOKE ALL ON FUNCTION public.ticket_resend_scopes_internal_v1(public.email_messages) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.charge_email_send_recipient_internal_v1(m public.email_messages)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE resend_scopes jsonb; limit_detail text;
BEGIN
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('email.send.'||m.admission_class,m.unit,m.organization),
  jsonb_build_object('recipient',CASE WHEN m.admission_class='notification' THEN m.recipient_user::text ELSE public.abuse_recipient_key_v1(m.recipient) END,'global','all'));
EXCEPTION WHEN SQLSTATE 'PT429' THEN
 GET STACKED DIAGNOSTICS limit_detail = PG_EXCEPTION_DETAIL;
 IF m.admission_class IS DISTINCT FROM 'ordinary' OR coalesce(limit_detail::jsonb->>'ruleKey','') NOT IN
  ('email.send.ordinary.recipient.burst','email.send.ordinary.recipient.day') THEN RAISE; END IF;
 resend_scopes:=public.ticket_resend_scopes_internal_v1(m);
 IF resend_scopes IS NULL THEN RAISE; END IF;
 PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('email.send.ticket_resend',m.unit,m.organization),resend_scopes);
END $$;
REVOKE ALL ON FUNCTION public.charge_email_send_recipient_internal_v1(public.email_messages) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: abuse/policy.sql
CREATE OR REPLACE FUNCTION public.abuse_effective_rules_v1(p_budget text,p_unit bigint,p_org bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('revision',v.revision,'rules',coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object(
 'base_limit',coalesce(u.base_limit,o.base_limit,r.base_limit)) ORDER BY r.rule_key),'[]'::jsonb))
 FROM public.abuse_policy_revision v CROSS JOIN public.abuse_policy_rules r
 LEFT JOIN public.abuse_policy_overrides o ON o.rule_key=r.rule_key AND o.target_kind='organization'
  AND o.target_id=p_org AND r.scope_kind IN ('unit','organization') AND o.expires_at>statement_timestamp()
 LEFT JOIN public.abuse_policy_overrides u ON u.rule_key=r.rule_key AND u.target_kind='unit'
  AND u.target_id=p_unit AND r.scope_kind='unit' AND u.expires_at>statement_timestamp()
 WHERE r.budget_key=p_budget GROUP BY v.revision
 HAVING count(*)=CASE p_budget WHEN 'occasion.creation' THEN 8 WHEN 'occasion.copy' THEN 2 WHEN 'occasion.draft' THEN 7
  WHEN 'unit.creation' THEN 3 WHEN 'email.ordinary' THEN 4 WHEN 'email.auth' THEN 4
  WHEN 'email.backlog' THEN 4 WHEN 'email.auth.backlog' THEN 1 WHEN 'email.payload' THEN 1
  WHEN 'email.prepare' THEN 2 WHEN 'email.actor' THEN 1 WHEN 'email.dispatch' THEN 1 WHEN 'ticket.document' THEN 4 WHEN 'ticket.preview' THEN 4 WHEN 'bank.operation' THEN 3 WHEN 'stripe.connect' THEN 3 WHEN 'stripe.checkout' THEN 3 WHEN 'barion.checkout' THEN 3 WHEN 'order.creation' THEN 4 WHEN 'qr.global' THEN 1 WHEN 'qr.proof' THEN 1 WHEN 'qr.payload' THEN 1 WHEN 'spot.hold' THEN 3 WHEN 'image.upload' THEN 5 WHEN 'image.fetch' THEN 5 WHEN 'sync.snapshot' THEN 2 WHEN 'sync.work' THEN 1 WHEN 'hold.duration' THEN 1 WHEN 'auth.reset.source' THEN 2 WHEN 'organization.creation' THEN 1 WHEN 'auth.reset.account' THEN 1
  WHEN 'auth.google.source' THEN 1 WHEN 'auth.google.client' THEN 1 WHEN 'auth.google.global' THEN 1 WHEN 'auth.google.attempt' THEN 1 WHEN 'auth.google.proof' THEN 1
  WHEN 'scan.operation' THEN 2 WHEN 'scan.invalid.global' THEN 1 WHEN 'scan.invalid.source' THEN 1 WHEN 'scan.password' THEN 2 WHEN 'scan.export' THEN 2
  WHEN 'reception.create' THEN 1 WHEN 'reception.issue' THEN 1 WHEN 'reception.revoke' THEN 1 WHEN 'reception.cancel' THEN 1
  WHEN 'discount.quote' THEN 2 WHEN 'order.mutation' THEN 4 WHEN 'batch-create' THEN 1 WHEN 'batch-document' THEN 2
  WHEN 'push.delivery' THEN 10
  WHEN 'cleaning.report' THEN 3
  WHEN 'push.dispatch' THEN 2
  WHEN 'image.records' THEN 9 WHEN 'auth.password' THEN 2 WHEN 'document.output' THEN 4 WHEN 'image.storage' THEN 3 WHEN 'monitor.thresholds' THEN 6 WHEN 'auth.password.change' THEN 3
  WHEN 'email.notification' THEN 3 WHEN 'email.notification.backlog' THEN 4 WHEN 'email.notification.prepare' THEN 2 WHEN 'email.send.notification' THEN 3
  WHEN 'email.ticket_resend' THEN 4 WHEN 'email.send.ticket_resend' THEN 4
  WHEN 'email.send.ordinary' THEN 2 WHEN 'email.send.auth' THEN 2 WHEN 'email.send.commitment' THEN 2
  ELSE -1 END;
$$;

-- SOURCE: abuse/email.sql
CREATE OR REPLACE FUNCTION public.admit_email_intent_v1(p_message bigint,p_recheck boolean DEFAULT false) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m public.email_messages; policy jsonb; scopes jsonb; costs jsonb; r jsonb;
 is_auth boolean; unit_count bigint; org_count bigint; unit_bytes bigint; org_bytes bigint; growth bigint:=0; policies jsonb; resend_scopes jsonb; limit_detail text;
BEGIN
 SELECT * INTO STRICT m FROM public.email_messages WHERE id=p_message;

 IF public.email_admission_class_v1(m)='notification' THEN
  scopes:=jsonb_build_object('global','all','recipient',m.recipient_user::text);
  PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('email.payload',NULL,NULL),scopes,
   jsonb_build_object('email.payload.bytes',octet_length(m.data::text)+coalesce(octet_length(m.prepared::text),0)));
  policy:=public.abuse_effective_rules_v1('email.notification.backlog',NULL,NULL);
  FOR r IN SELECT value FROM jsonb_array_elements(policy->'rules') ORDER BY value->>'rule_key' LOOP
   PERFORM pg_advisory_xact_lock(hashtextextended('abuse:'||(r->>'rule_key')||':'||(scopes->>(r->>'scope_kind')),0));
  END LOOP;
  SELECT count(*) FILTER(WHERE recipient_user=m.recipient_user),count(*),
   coalesce(sum(octet_length(data::text)+coalesce(octet_length(prepared::text),0)) FILTER(WHERE recipient_user=m.recipient_user),0),
   coalesce(sum(octet_length(data::text)+coalesce(octet_length(prepared::text),0)),0)
  INTO unit_count,org_count,unit_bytes,org_bytes FROM public.email_messages
  WHERE message_kind='admin_notification_digest' AND workflow_state IN ('pending','blocked','preparing','sending','retry_wait','unknown');
  PERFORM public.abuse_charge_v1(policy,scopes,jsonb_build_object(
   'email.notification.backlog.recipient',unit_count,'email.notification.backlog.global',org_count,
   'email.notification.backlog.recipient.bytes',unit_bytes,'email.notification.backlog.global.bytes',org_bytes));
  IF NOT p_recheck THEN
   PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('email.notification',NULL,NULL),scopes);

  END IF;
  UPDATE public.email_messages SET admission_class='notification',priority=80 WHERE id=m.id;
  RETURN;
 END IF;
 policies:=public.abuse_policy_bundle_v1(ARRAY['email.payload','email.actor','email.backlog','email.auth.backlog','email.auth','email.ordinary'],m.unit,m.organization);
 IF m.unit IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.units WHERE id=m.unit AND organization=m.organization) THEN
  RAISE invalid_parameter_value USING MESSAGE='email_scope_mismatch'; END IF;
 scopes:=jsonb_build_object('unit',m.unit,'organization',m.organization,'global','all',
  'actor',m.producer_actor,'recipient',public.abuse_recipient_key_v1(coalesce(m.recipient,(SELECT email_readonly FROM public.user_info WHERE id=m.recipient_user))));
 PERFORM public.abuse_charge_v1(policies->'email.payload',scopes,
  jsonb_build_object('email.payload.bytes',octet_length(m.data::text)+coalesce(octet_length(m.prepared::text),0)));
 -- Neither caller priority nor request data can claim the reserved class.
 IF public.email_admission_class_v1(m)='commitment' THEN
  UPDATE public.email_messages SET admission_class='commitment',priority=5 WHERE id=m.id;
  RETURN;
 END IF;
 IF NOT p_recheck THEN
  resend_scopes:=public.ticket_resend_scopes_internal_v1(m);
  IF resend_scopes IS NOT NULL THEN scopes:=scopes||jsonb_build_object('actor',resend_scopes->'actor'); END IF;
  IF scopes->>'actor' IS NOT NULL THEN PERFORM public.abuse_charge_v1(policies->'email.actor',scopes); END IF;
 END IF;
 is_auth:=public.email_admission_class_v1(m)='auth';
 UPDATE public.email_messages SET admission_class=CASE WHEN is_auth THEN 'auth' ELSE 'ordinary' END WHERE id=m.id;
 policy:=policies->(CASE WHEN is_auth THEN 'email.auth.backlog' ELSE 'email.backlog' END);
 -- Null Unit auth has an explicit tenant/global class, never a synthetic Unit.
 IF m.unit IS NULL THEN policy:=jsonb_set(policy,'{rules}',(SELECT jsonb_agg(value) FROM jsonb_array_elements(policy->'rules') WHERE value->>'scope_kind'<>'unit')); END IF;
 FOR r IN SELECT value FROM jsonb_array_elements(policy->'rules') ORDER BY value->>'rule_key' LOOP
  IF r->>'kind' IN ('bytes','duration') THEN CONTINUE; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('abuse:'||(r->>'rule_key')||':'||(scopes->>(r->>'scope_kind')),0));
 END LOOP;
 -- Pending partial indexes exclude delivery history. Include blocked/future/unknown.
 SELECT count(*) FILTER(WHERE unit=m.unit),count(*),
  coalesce(sum(octet_length(data::text)+coalesce(octet_length(prepared::text),0)) FILTER(WHERE unit=m.unit),0),
  coalesce(sum(octet_length(data::text)+coalesce(octet_length(prepared::text),0)),0)
 INTO unit_count,org_count,unit_bytes,org_bytes FROM public.email_messages
 WHERE organization=m.organization AND admission_class=CASE WHEN is_auth THEN 'auth' ELSE 'ordinary' END AND workflow_state IN ('pending','blocked','preparing','sending','retry_wait','unknown');
 costs:=jsonb_build_object('email.auth.backlog.organization',org_count,'email.backlog.unit',unit_count,'email.backlog.organization',org_count,
  'email.backlog.unit.bytes',unit_bytes,'email.backlog.organization.bytes',org_bytes);
 PERFORM public.abuse_charge_v1(policy,scopes,costs);
 IF p_recheck THEN RETURN; END IF;
 policy:=policies->(CASE WHEN is_auth THEN 'email.auth' ELSE 'email.ordinary' END);
 IF NOT is_auth AND m.unit IS NULL THEN
  -- System producers without a Unit retain tenant and recipient bounds.
  policy:=jsonb_set(policy,'{rules}',(SELECT jsonb_agg(value) FROM jsonb_array_elements(policy->'rules') WHERE value->>'scope_kind'<>'unit'));
 END IF;
 IF NOT is_auth AND m.unit IS NOT NULL THEN
  SELECT coalesce(verified_orders,0) INTO growth FROM public.abuse_unit_evidence
   WHERE unit=m.unit AND measured_at>statement_timestamp()-interval '15 minutes';
  growth:=coalesce(growth,0);
 END IF;
 BEGIN
  PERFORM public.abuse_charge_v1(policy,scopes,jsonb_build_object('growth',growth));
 EXCEPTION WHEN SQLSTATE 'PT429' THEN
  GET STACKED DIAGNOSTICS limit_detail = PG_EXCEPTION_DETAIL;
  IF resend_scopes IS NULL OR coalesce(limit_detail::jsonb->>'ruleKey','') NOT IN
   ('email.ordinary.recipient.burst','email.ordinary.recipient.day') THEN RAISE; END IF;
  -- An exhausted recipient budget can use the reserve. Tenant and Unit limits still apply.
  policy:=jsonb_set(policy,'{rules}',(SELECT jsonb_agg(value) FROM jsonb_array_elements(policy->'rules') WHERE value->>'scope_kind'<>'recipient'));
  PERFORM public.abuse_charge_v1(policy,scopes,jsonb_build_object('growth',growth));
  PERFORM public.abuse_charge_v1(public.abuse_effective_rules_v1('email.ticket_resend',m.unit,m.organization),resend_scopes);
 END;
END $$;

-- SOURCE: emails/email_queue.sql
CREATE OR REPLACE FUNCTION public.begin_email_send(p_attempt uuid,p_token uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_attempt public.email_attempts; v_row public.email_messages; v_cap public.email_capacity; v_rate numeric; v_daily numeric; v_used numeric; v_detail text; v_retry integer;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.notification_center_email_profiles p JOIN public.email_messages m ON m.recipient_user=p.recipient
 JOIN public.email_attempts a ON a.message_id=m.message_id WHERE a.attempt_id=p_attempt AND m.message_kind='admin_notification_digest' FOR UPDATE OF p;

 PERFORM public.payment_policy_fence_internal(m.organization) FROM public.email_messages m
 JOIN public.email_attempts a ON a.message_id=m.message_id WHERE a.attempt_id=p_attempt AND m.order_id IS NOT NULL;
 PERFORM 1 FROM public.forms f JOIN public.sale_opening_campaigns c ON c.form_id=f.id
  JOIN public.email_messages m ON m.data->>'campaign_id'=c.id::text
  JOIN public.email_attempts a ON a.message_id=m.message_id
  WHERE a.attempt_id=p_attempt AND m.message_kind IN ('sale_opening_opened') FOR UPDATE OF f;
 SELECT * INTO v_cap FROM public.email_capacity FOR UPDATE;
 SELECT * INTO v_attempt FROM public.email_attempts WHERE attempt_id=p_attempt;
 SELECT * INTO v_row FROM public.email_messages WHERE message_id=v_attempt.message_id;
 IF v_row.order_id IS NOT NULL THEN PERFORM 1 FROM eshop.orders WHERE id=v_row.order_id FOR UPDATE; END IF;
 SELECT * INTO v_attempt FROM public.email_attempts WHERE attempt_id=p_attempt FOR UPDATE;
 SELECT * INTO v_row FROM public.email_messages WHERE message_id=v_attempt.message_id FOR UPDATE;
 IF v_attempt.lease_token IS DISTINCT FROM p_token OR v_row.lease_token IS DISTINCT FROM p_token THEN RAISE EXCEPTION 'stale_email_attempt'; END IF;
 IF v_attempt.state<>'preparing' THEN RETURN jsonb_build_object('disposition','replay','state',v_attempt.state); END IF;
 IF v_row.workflow_state<>'preparing' OR v_row.lease_until<=now() OR v_row.prepared IS NULL THEN RAISE EXCEPTION 'stale_email_attempt'; END IF;
 IF NOT public.email_intent_valid(v_row) OR EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(v_row.recipient)) THEN
  UPDATE public.email_messages SET last_error=CASE WHEN v_row.message_kind='admin_notification_digest' AND v_row.recipient IS DISTINCT FROM public.get_user_delivery_email(v_row.recipient_user) THEN 'destination_changed' ELSE 'intent_invalid' END,workflow_state=CASE WHEN EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(v_row.recipient)) THEN 'suppressed' ELSE 'cancelled' END WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now() WHERE attempt_id=p_attempt;
  PERFORM public.notification_center_email_internal(v_row.message_id);
  RETURN jsonb_build_object('disposition','cancelled');
 END IF;
 -- A partial acceptance can change a queued offer after its rendered snapshot
 -- was cached. Re-render within this same queue before granting a send permit.
 IF v_row.message_kind='waitlist_offer' AND
  (v_row.post_action->>'waitlist_pending_count')::bigint IS DISTINCT FROM
  (SELECT count(*) FROM eshop.waitlist_offer_slots
   WHERE offer_id=(v_row.data->>'offer_id')::uuid AND outcome='pending') THEN
  UPDATE public.email_messages SET workflow_state='pending',target_time=now(),
   prepared=NULL,prepared_hash=NULL,prepared_at=NULL,
   post_action=post_action-'waitlist_pending_count',lease_token=NULL,lease_until=NULL,
   last_error='offer_snapshot_changed' WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),
   error_code='offer_snapshot_changed' WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','deferred');
 END IF;
 -- Only unstarted provider attempts can discard a stale Wallet snapshot.
 IF v_row.message_kind='order_tickets' AND v_row.post_action->>'wallet_fingerprint'
  IS DISTINCT FROM public.ticket_wallet_fingerprint(v_row.occasion) THEN
  UPDATE public.email_messages SET workflow_state='pending',target_time=now(),prepared=NULL,prepared_hash=NULL,prepared_at=NULL,
   post_action=post_action-'wallet_fingerprint',lease_token=NULL,lease_until=NULL,last_error='wallet_snapshot_changed' WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),error_code='wallet_snapshot_changed' WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','deferred');
 END IF;
 BEGIN
 v_rate:=CASE WHEN v_cap.shared_account THEN least(v_cap.max_rate*0.8,v_cap.allocated_rate) ELSE v_cap.max_rate*0.8 END*v_cap.rate_factor;
 v_daily:=CASE WHEN v_cap.shared_account THEN least(v_cap.daily_quota,v_cap.allocated_daily) ELSE v_cap.daily_quota END*0.9;
 -- Count all local starts since snapshot plus provider's rolling usage; conservative during drift.
 SELECT count(*) INTO v_used FROM public.email_attempts WHERE began_at>now()-interval '24 hours' AND (began_at>v_cap.quota_at OR state IN ('sending','unknown')) AND state IN ('sending','accepted','unknown');
 IF v_cap.paused OR v_cap.quota_at IS NULL OR v_cap.quota_at<now()-interval '15 minutes' OR v_rate IS NULL OR v_rate<=0 OR v_daily IS NULL
 OR (v_cap.shared_account AND (v_cap.allocated_rate IS NULL OR v_cap.allocated_daily IS NULL)) OR v_cap.provider_sent_24h+v_used>=v_daily
 OR v_cap.next_send_at>now() OR v_cap.circuit_until>now()
 OR (v_cap.provider_outage_streak>0 AND v_cap.probe_until>now())
 OR (SELECT count(*) FROM public.email_messages WHERE workflow_state='sending' AND lease_until>now())>=v_cap.max_sending THEN
  UPDATE public.email_messages SET workflow_state='pending',target_time=greatest(now()+interval '1 second',coalesce(v_cap.next_send_at,now()),coalesce(v_cap.circuit_until,now()),coalesce(v_cap.probe_until,now())),lease_token=NULL,lease_until=NULL,last_error='capacity_deferred' WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),error_code='capacity_deferred' WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','deferred');
 END IF;
 -- Recipient admission at enqueue does not protect against many future intents
 -- converging on one date. Meter the actual fenced send, with separate essential
 -- classes so ordinary bulk cannot consume Auth or accepted-order capacity.
 BEGIN
  PERFORM public.charge_email_send_recipient_internal_v1(v_row);
 EXCEPTION WHEN SQLSTATE 'PT429' THEN
  GET STACKED DIAGNOSTICS v_detail=PG_EXCEPTION_DETAIL;
  v_retry:=greatest(coalesce((v_detail::jsonb->>'retryAfterSeconds')::integer,60),1);
  UPDATE public.email_messages SET workflow_state='pending',target_time=now()+make_interval(secs=>v_retry),lease_token=NULL,lease_until=NULL,last_error='recipient_deferred' WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),error_code='recipient_deferred' WHERE attempt_id=p_attempt;
  RETURN jsonb_build_object('disposition','deferred');
 END;
 UPDATE public.email_capacity SET next_send_at=clock_timestamp()+make_interval(secs=>(1/v_rate)::double precision),
 probe_until=CASE WHEN provider_outage_streak>0 THEN now()+interval '90 seconds' ELSE NULL END,
 probe_attempt=CASE WHEN provider_outage_streak>0 THEN p_attempt ELSE NULL END WHERE singleton;
 IF v_row.message_kind='admin_notification_digest' THEN
  WITH context AS MATERIALIZED(SELECT public.notification_center_email_context_internal(v_row.notification_dispatch_id,v_row.recipient_user) value),
  decision AS MATERIALIZED(SELECT CASE
   WHEN value IS NULL OR jsonb_array_length(value->'items')=0 THEN 'cancelled'
   WHEN value->>'address' IS DISTINCT FROM v_row.recipient THEN 'destination_changed'
   WHEN value->>'fingerprint' IS DISTINCT FROM v_row.post_action->>'notification_fingerprint' THEN 'snapshot_changed'
   ELSE 'send' END action FROM context),
  attempt AS(UPDATE public.email_attempts SET state=CASE WHEN decision.action='send' THEN 'sending' ELSE 'cancelled' END,
   began_at=CASE WHEN decision.action='send' THEN now() END,
   error_code=CASE WHEN decision.action<>'send' THEN decision.action END FROM decision WHERE attempt_id=p_attempt)
  UPDATE public.email_messages SET workflow_state=CASE WHEN decision.action='send' THEN 'sending' WHEN decision.action='snapshot_changed' THEN 'pending' ELSE 'cancelled' END,
   prepared=CASE WHEN decision.action='snapshot_changed' THEN NULL ELSE prepared END,
   prepared_hash=CASE WHEN decision.action='snapshot_changed' THEN NULL ELSE prepared_hash END,
   prepared_at=CASE WHEN decision.action='snapshot_changed' THEN NULL ELSE prepared_at END,
   post_action=CASE WHEN decision.action='snapshot_changed' THEN post_action-'notification_fingerprint' ELSE post_action END,
   attempt_count=attempt_count+(decision.action='send')::integer,
   last_error=CASE WHEN decision.action<>'send' THEN decision.action END,
   lease_token=CASE WHEN decision.action='send' THEN lease_token END,
   lease_until=CASE WHEN decision.action='send' THEN lease_until END
   FROM decision WHERE id=v_row.id RETURNING last_error INTO v_detail;
  IF v_detail IS NOT NULL THEN
   RAISE SQLSTATE 'PN001' USING MESSAGE=v_detail;
  END IF;
 ELSE
  UPDATE public.email_attempts SET state='sending',began_at=now() WHERE attempt_id=p_attempt;
  UPDATE public.email_messages SET workflow_state='sending',attempt_count=attempt_count+1 WHERE id=v_row.id;
 END IF;
 RETURN jsonb_build_object('disposition','send','message',to_jsonb(v_row));
 EXCEPTION WHEN SQLSTATE 'PN001' THEN
  -- Metering, capacity reservation and final state changes roll back together.
  GET STACKED DIAGNOSTICS v_detail=MESSAGE_TEXT;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now(),error_code=v_detail WHERE attempt_id=p_attempt;
  UPDATE public.email_messages SET workflow_state=CASE WHEN v_detail='snapshot_changed' THEN 'pending' ELSE 'cancelled' END,
   target_time=now(),prepared=CASE WHEN v_detail='snapshot_changed' THEN NULL ELSE prepared END,
   prepared_hash=CASE WHEN v_detail='snapshot_changed' THEN NULL ELSE prepared_hash END,
   prepared_at=CASE WHEN v_detail='snapshot_changed' THEN NULL ELSE prepared_at END,
   post_action=post_action-'notification_fingerprint',lease_token=NULL,lease_until=NULL,last_error=v_detail WHERE id=v_row.id;
  RETURN jsonb_build_object('disposition',CASE WHEN v_detail='snapshot_changed' THEN 'deferred' ELSE 'cancelled' END);
 END;

END $$;
