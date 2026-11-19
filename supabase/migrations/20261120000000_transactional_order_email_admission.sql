-- Separate verified system order delivery from user-triggered email limits.

-- SOURCE: abuse/order_delivery.sql
-- A separate allowance for checkout receipts and scheduled payment notices.
ALTER TABLE public.email_messages DROP CONSTRAINT email_messages_admission_class_check;
ALTER TABLE public.email_messages ADD CONSTRAINT email_messages_admission_class_check
 CHECK(admission_class IN ('ordinary','auth','commitment','notification','transactional')) NOT VALID;
ALTER TABLE public.email_messages VALIDATE CONSTRAINT email_messages_admission_class_check;

INSERT INTO public.abuse_policy_rules
 (rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap)
VALUES
 ('email.transactional.organization.day','email.transactional','organization','rolling',86400,3600,15000,30000),
 ('email.transactional.unit.day','email.transactional','unit','rolling',86400,3600,5000,10000),
 ('email.transactional.recipient.burst','email.transactional','recipient','rolling',60,60,12,20),
 ('email.transactional.recipient.day','email.transactional','recipient','rolling',86400,3600,60,120),
 ('email.send.transactional.recipient.burst','email.send.transactional','recipient','rolling',60,60,12,20),
 ('email.send.transactional.recipient.day','email.send.transactional','recipient','rolling',86400,3600,60,120);

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
  WHEN 'email.transactional' THEN 4 WHEN 'email.send.transactional' THEN 2
  WHEN 'email.ticket_resend' THEN 4 WHEN 'email.send.ticket_resend' THEN 4
  WHEN 'email.send.ordinary' THEN 2 WHEN 'email.send.auth' THEN 2 WHEN 'email.send.commitment' THEN 2
  ELSE -1 END;
$$;

-- SOURCE: abuse/email.sql
CREATE OR REPLACE FUNCTION public.email_admission_class_v1(m public.email_messages) RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; pi eshop.payment_info; commitment boolean:=false;
BEGIN
 IF m.message_kind='admin_notification_digest' AND m.organization IS NULL AND m.recipient_user IS NOT NULL
  AND EXISTS(SELECT 1 FROM public.notification_center_email_dispatches d WHERE d.id=m.notification_dispatch_id AND d.recipient=m.recipient_user) THEN RETURN 'notification'; END IF;

 IF m.message_kind IN ('order_tickets','order_payment_notice','order_storno') AND m.order_id IS NOT NULL THEN
  SELECT * INTO o FROM eshop.orders WHERE id=m.order_id;
  commitment:=((m.message_kind IN ('order_tickets','order_payment_notice') AND o.state IN ('paid','sent')) OR (m.message_kind='order_storno' AND o.state='storno')) AND o.occasion=m.occasion AND o.email_payment_version=m.source_version
   AND m.recipient IS NOT DISTINCT FROM o.data->>'email'
   AND m.dedupe_key=o.id||':'||o.email_payment_version||':'||coalesce(m.recipient,'')||CASE WHEN m.message_kind='order_storno' THEN ':storno' ELSE ':false' END
   AND NOT m.data ? 'requested_by';
 END IF;
 IF commitment THEN RETURN 'commitment'; END IF;
 -- A delivery orchestration marker is only issued by the private checkout and reminder producers.
 -- Bind it to the current order recipient, kind, and generation before assigning capacity.
 IF m.order_id IS NOT NULL AND m.data ? 'systemOrderDelivery'
    AND NOT m.data ?| ARRAY['requested_by','manual','recipient'] THEN
  SELECT * INTO o FROM eshop.orders WHERE id=m.order_id AND occasion=m.occasion;
  IF FOUND AND m.recipient IS NOT NULL AND m.recipient=o.data->>'email' THEN
   IF m.message_kind='order_confirmation' AND m.data->>'systemOrderDelivery'='checkout'
      AND m.data ? 'command_id' AND m.dedupe_key=public.order_email_automatic_key_internal(o.id,o.email_payment_version,m.recipient)
      AND m.source_version=o.email_payment_version AND o.state IN ('ordered','paid','preparing_payment')
   THEN RETURN 'transactional'; END IF;
   IF m.message_kind='order_reminder' AND m.data->>'systemOrderDelivery'='payment_reminder' THEN
    SELECT * INTO pi FROM eshop.payment_info WHERE id=o.payment_info;
    IF FOUND AND pi.payment_method='bank' AND m.source_version=pi.email_reminder_version
       AND m.dedupe_key=o.id||':'||pi.email_reminder_version||':'||m.recipient||':'||coalesce(m.data->>'is_deposit_reminder','false')
    THEN RETURN 'transactional'; END IF;
   END IF;
  END IF;
 END IF;
 RETURN CASE WHEN m.message_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue') THEN 'auth' ELSE 'ordinary' END;
END $$;
CREATE OR REPLACE FUNCTION public.admit_email_intent_v1(p_message bigint,p_recheck boolean DEFAULT false) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m public.email_messages; policy jsonb; scopes jsonb; costs jsonb; r jsonb;
 admission_group text; is_auth boolean; unit_count bigint; org_count bigint; unit_bytes bigint; org_bytes bigint; growth bigint:=0; policies jsonb; resend_scopes jsonb; limit_detail text;
BEGIN
 SELECT * INTO STRICT m FROM public.email_messages WHERE id=p_message;
 admission_group:=public.email_admission_class_v1(m);

 IF admission_group='notification' THEN
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
 policies:=public.abuse_policy_bundle_v1(ARRAY['email.payload','email.actor','email.backlog','email.auth.backlog','email.auth','email.ordinary','email.transactional'],m.unit,m.organization);
 IF m.unit IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.units WHERE id=m.unit AND organization=m.organization) THEN
  RAISE invalid_parameter_value USING MESSAGE='email_scope_mismatch'; END IF;
 scopes:=jsonb_build_object('unit',m.unit,'organization',m.organization,'global','all',
  'actor',m.producer_actor,'recipient',public.abuse_recipient_key_v1(coalesce(m.recipient,(SELECT email_readonly FROM public.user_info WHERE id=m.recipient_user))));
 PERFORM public.abuse_charge_v1(policies->'email.payload',scopes,
  jsonb_build_object('email.payload.bytes',octet_length(m.data::text)+coalesce(octet_length(m.prepared::text),0)));
 -- Neither caller priority nor request data can claim the reserved class.
 IF admission_group='commitment' THEN
  UPDATE public.email_messages SET admission_class='commitment',priority=5 WHERE id=m.id;
  RETURN;
 END IF;
 IF NOT p_recheck THEN
  resend_scopes:=public.ticket_resend_scopes_internal_v1(m);
  IF resend_scopes IS NOT NULL THEN scopes:=scopes||jsonb_build_object('actor',resend_scopes->'actor'); END IF;
  IF scopes->>'actor' IS NOT NULL THEN PERFORM public.abuse_charge_v1(policies->'email.actor',scopes); END IF;
 END IF;
 is_auth:=admission_group='auth';
 UPDATE public.email_messages SET admission_class=admission_group,
  priority=CASE WHEN admission_group='transactional' THEN least(priority,10) ELSE priority END WHERE id=m.id;
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
 WHERE organization=m.organization AND admission_class=admission_group AND workflow_state IN ('pending','blocked','preparing','sending','retry_wait','unknown');
 costs:=jsonb_build_object('email.auth.backlog.organization',org_count,'email.backlog.unit',unit_count,'email.backlog.organization',org_count,
  'email.backlog.unit.bytes',unit_bytes,'email.backlog.organization.bytes',org_bytes);
 PERFORM public.abuse_charge_v1(policy,scopes,costs);
 IF p_recheck THEN RETURN; END IF;
 policy:=policies->('email.'||admission_group);
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

-- SOURCE: abuse/health.sql
CREATE OR REPLACE FUNCTION public.abuse_health_internal_v1() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE queues jsonb; expired_at timestamptz; evidence_at timestamptz; capacity jsonb;
BEGIN
 SELECT jsonb_object_agg(class,stats) INTO queues FROM (
  SELECT class,jsonb_build_object(
   'pendingCount',least(5000,(SELECT count(*) FROM (
     SELECT 1 FROM public.email_messages WHERE admission_class=class
      AND workflow_state IN ('pending','blocked','preparing','sending','retry_wait','unknown') LIMIT 5001
    ) q)),
   'countCappedAt',5000,
   'oldestCreatedAt',(SELECT created_at FROM public.email_messages WHERE admission_class=class
     AND workflow_state IN ('pending','blocked','preparing','sending','retry_wait','unknown') ORDER BY created_at LIMIT 1),
   -- Historical uncertain sends and future schedules remain visible in counts,
   -- but only runnable work can age into a stalled-delivery alert.
   'oldestDueAt',(SELECT min(greatest(created_at,target_time)) FROM public.email_messages WHERE admission_class=class
     AND workflow_state IN ('pending','preparing','sending','retry_wait') AND target_time<=statement_timestamp())
  ) stats FROM unnest(ARRAY['ordinary','auth','commitment','transactional']) class
 ) q;
 SELECT expires_at INTO expired_at FROM public.abuse_budget_usage WHERE expires_at<statement_timestamp() ORDER BY expires_at LIMIT 1;
 SELECT measured_at INTO evidence_at FROM public.abuse_unit_evidence ORDER BY measured_at LIMIT 1;
 SELECT jsonb_build_object('paused',paused,'quotaMeasuredAt',quota_at,'circuitUntil',circuit_until,
   'nextSendAt',next_send_at,'providerOutageStreak',provider_outage_streak) INTO capacity FROM public.email_capacity LIMIT 1;
 RETURN jsonb_build_object('measuredAt',statement_timestamp(),
  'policyRevision',(SELECT revision FROM public.abuse_policy_revision WHERE singleton),
  'queue',queues,'oldestExpiredUsageAt',expired_at,'oldestGrowthEvidenceAt',evidence_at,'provider',capacity);
END $$;

-- SOURCE: emails/email_domain.sql
CREATE OR REPLACE FUNCTION public.enqueue_order_email(p_code text,p_data jsonb,p_org bigint,p_occ bigint,p_unit bigint,p_time timestamptz DEFAULT now(),p_request text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_kind text; v_version bigint; v_key text; v_recipient text; v_existing public.email_messages; v_base_key text;
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 -- Only private domain producers running as the canonical SQL owner can assign provenance.
 IF current_user<>'postgres' THEN p_data:=p_data-'systemOrderDelivery'; END IF;
 SELECT * INTO v_order FROM eshop.orders WHERE id=coalesce((p_data->>'order_id')::bigint,(p_data#>>'{ticket_order,order,id}')::bigint) FOR UPDATE;
 SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
 IF v_order.id IS NULL OR v_order.occasion<>p_occ THEN RAISE EXCEPTION 'invalid_order_email'; END IF;
 IF v_order.state='stock' THEN RAISE EXCEPTION 'ORDER_ACTION_NOT_ALLOWED'; END IF;
 IF v_order.data ? 'ticketBatchOrigin' AND nullif(trim(v_order.data->>'email'),'') IS NULL THEN
  RETURN jsonb_build_object('state','skipped','reason','no_recipient'); END IF;
 IF v_order.state='storno' AND p_code<>'TICKET_ORDER_STORNO' THEN
  RAISE EXCEPTION 'ORDER_CANCELLED: Cancelled orders are read-only' USING ERRCODE='55000';
 END IF;
 v_kind:=CASE p_code WHEN 'TICKET_ORDER_CONFIRMATION' THEN 'order_confirmation' WHEN 'TICKET_ORDER_PAYMENT_DONE' THEN 'order_payment_notice'
  WHEN 'TICKET_ORDER_REMINDER' THEN 'order_reminder' WHEN 'TICKET_ORDER_STORNO' THEN 'order_storno' WHEN 'TICKET_ORDER_UPDATE' THEN 'order_update'
  WHEN 'ORDER_TICKETS' THEN 'order_tickets' END;
 IF v_kind IS NULL THEN RAISE EXCEPTION 'unsupported_order_email'; END IF;
 v_version:=CASE WHEN v_kind='order_reminder' THEN v_pi.email_reminder_version ELSE v_order.email_payment_version END;
 v_recipient:=coalesce(p_data->>'recipient',v_order.data->>'email');
 v_key:=coalesce(p_request,p_data->>'command_id',v_order.id||':'||v_version||':'||coalesce(v_recipient,'')||':'||coalesce(p_data->>'is_deposit_reminder','false'));
 IF v_kind='order_storno' AND coalesce(p_request,'') NOT LIKE 'manual:%' THEN
  -- requested_by is audit metadata, never proof of an explicit resend.
  v_recipient:=v_order.data->>'email';
  p_data:=jsonb_build_object('order_id',v_order.id);
  v_key:=v_order.id||':'||v_version||':'||coalesce(v_recipient,'')||':storno';
  -- Older Edge follow-ups carried requested_by but no explicit resend ID and
  -- used the generic :false key. Reuse that committed identity rather than
  -- manufacture a second automatic message, including cancelled/expired rows.
  SELECT * INTO v_existing FROM public.email_messages
    WHERE organization=p_org AND order_id=v_order.id AND message_kind='order_storno'
      AND recipient=v_recipient AND source_version=v_version
      AND dedupe_key IN (v_key,v_order.id||':'||v_version||':'||coalesce(v_recipient,'')||':false')
    ORDER BY (dedupe_key=v_key) DESC,id LIMIT 1;
  IF v_existing.id IS NOT NULL THEN v_key:=v_existing.dedupe_key; END IF;
 END IF;
 IF v_kind IN ('order_tickets','order_confirmation') THEN
  SELECT * INTO v_existing FROM public.email_messages WHERE order_id=v_order.id AND message_kind=v_kind AND recipient=v_recipient AND source_version=v_version
    AND workflow_state IN ('pending','preparing','sending','retry_wait','unknown') ORDER BY id DESC LIMIT 1;
  IF v_existing.id IS NOT NULL THEN
   IF p_data->>'requested_by' IS NOT NULL THEN UPDATE public.email_messages SET post_action=post_action||jsonb_build_object('last_manual_request',jsonb_build_object('actor',p_data->>'requested_by','request',p_request,'at',now())) WHERE id=v_existing.id; END IF;
   RETURN jsonb_build_object('message_id',v_existing.message_id,'state',v_existing.workflow_state,'replayed',true);END IF;
  v_base_key:=public.order_email_automatic_key_internal(v_order.id,v_version,v_recipient);
  IF p_request IS NULL OR NOT EXISTS(SELECT 1 FROM public.email_messages WHERE order_id=v_order.id AND message_kind=v_kind AND recipient=v_recipient AND source_version=v_version) THEN v_key:=v_base_key;END IF;
 END IF;
 RETURN public.enqueue_email(v_kind,jsonb_build_object('organization',p_org,'occasion',p_occ,'unit',p_unit),v_recipient,p_data,v_key,
 CASE WHEN p_code='ORDER_TICKETS' THEN 'TICKET_ORDER_PAYMENT_DONE' ELSE p_code END,p_time,
 CASE WHEN v_kind='order_reminder' THEN p_time+interval '7 days' ELSE NULL END,v_order.id,v_version);
END $$;

-- SOURCE: emails/email_queue.sql
CREATE OR REPLACE FUNCTION public.enqueue_email(p_kind text,p_context jsonb,p_recipient text,p_data jsonb,p_dedupe text,
 p_code text DEFAULT '',p_not_before timestamptz DEFAULT now(),p_expires timestamptz DEFAULT NULL,
 p_order bigint DEFAULT NULL,p_version bigint DEFAULT NULL,p_post_action jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_hash text; v_row public.email_messages; v_org bigint:=(p_context->>'organization')::bigint; v_occ bigint:=(p_context->>'occasion')::bigint; v_unit bigint:=(p_context->>'unit')::bigint;
BEGIN
 IF p_code='BANK_SYNC_WARNING' THEN RAISE EXCEPTION 'bank_warning_producer_retired'; END IF;
 p_recipient:=public.normalize_order_email_contact(p_recipient);
 PERFORM public.check_occasion_writable(v_occ);
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 IF (v_org IS NULL AND p_kind<>'admin_notification_digest') OR p_kind NOT IN ('admin_notification_digest','order_confirmation','order_payment_notice','order_tickets','order_reminder','order_update','order_storno','custom','registration','sign_in','reset_password','app_links','deletion_confirm','deletion_complete','google_mailbox','gotrue','waitlist_confirmation','waitlist_offer','sale_opening_opened')
 OR p_dedupe IS NULL OR length(p_dedupe)>512 OR (p_recipient IS NOT NULL AND (length(p_recipient)>320 OR position('@' in p_recipient)=0)) THEN RAISE EXCEPTION 'invalid_email_intent'; END IF;
 IF (v_org IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=v_org)) OR
 (v_occ IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=v_occ AND organization=v_org AND (NOT p_context ? 'unit' OR unit IS NOT DISTINCT FROM v_unit))) THEN RAISE EXCEPTION 'email_scope_mismatch'; END IF;
 IF p_kind='admin_notification_digest' THEN
  IF v_org IS NOT NULL OR v_occ IS NOT NULL OR v_unit IS NOT NULL OR p_order IS NOT NULL OR
   p_recipient IS DISTINCT FROM public.get_user_delivery_email((p_context->>'recipient_user')::uuid) OR
   NOT EXISTS(SELECT 1 FROM public.notification_center_email_dispatches d
    WHERE d.id=(p_data->>'dispatchId')::uuid AND d.recipient=(p_context->>'recipient_user')::uuid AND d.state IN ('collecting','queued')) THEN
   RAISE EXCEPTION 'email_recipient_scope_mismatch';
  END IF;
 END IF;
 IF p_order IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=v_occ) THEN RAISE EXCEPTION 'email_order_scope_mismatch'; END IF;
 IF v_occ IS NOT NULL THEN SELECT unit INTO v_unit FROM public.occasions WHERE id=v_occ; END IF;
 IF p_order IS NOT NULL AND p_kind IN ('order_confirmation','order_update','order_reminder','order_payment_notice') THEN
  p_data:=coalesce(p_data,'{}')||jsonb_build_object('collectionAction',public.payment_collection_action_internal(p_order));
 END IF;
 IF p_order IS NOT NULL AND p_kind IN ('order_confirmation','order_update','order_reminder','order_payment_notice','order_storno','order_tickets') THEN
  p_data:=coalesce(p_data,'{}')||jsonb_build_object('paymentTemplateEpoch',coalesce((SELECT revision FROM eshop.payment_template_epochs WHERE occasion_id=v_occ),0));
 END IF;
 -- Snapshot the tenant default only for new unlocalized domain intents. Existing
 -- messages, explicit locales and prepared/encrypted Auth content are untouched.
 IF NOT coalesce(p_data,'{}'::jsonb) ? 'lang' AND
    (p_kind LIKE 'order_%' OR p_kind IN ('waitlist_confirmation','waitlist_offer','sale_opening_opened')) AND
    (SELECT data->>'DEFAULT_LANGUAGE' FROM public.organizations WHERE id=v_org)='en' THEN
   p_data:=coalesce(p_data,'{}'::jsonb)||'{"lang":"en"}'::jsonb;
 END IF;
 v_hash:=encode(extensions.digest(jsonb_build_object('context',p_context-'tracking_policy','recipient',p_recipient,'data',CASE WHEN p_order IS NOT NULL AND p_kind IN ('order_confirmation','order_update','order_reminder','order_payment_notice','order_storno','order_tickets') THEN p_data-'requested_by'-'collectionAction'-'paymentTemplateEpoch'-'systemOrderDelivery' ELSE p_data-'requested_by' END,'code',p_code,'version',p_version,'post',p_post_action)::text,'sha256'),'hex');
 IF p_kind='admin_notification_digest' THEN
 INSERT INTO public.email_messages(target_time,code,data,organization,occasion,unit,message_kind,dedupe_key,input_hash,recipient,recipient_user,order_id,source_version,expires_at,producer_actor,priority,workflow_state,post_action,tracking_policy,notification_dispatch_id)
 VALUES(p_not_before,p_code,p_data,v_org,v_occ,v_unit,p_kind,p_dedupe,v_hash,p_recipient,(p_context->>'recipient_user')::uuid,p_order,p_version,p_expires,coalesce((p_context->>'actor_id')::uuid,auth.uid()),
 CASE WHEN p_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue') THEN 0 WHEN p_kind='order_confirmation' THEN 10 ELSE 50 END,
 CASE WHEN p_not_before='infinity' THEN 'blocked' ELSE 'pending' END,p_post_action,CASE WHEN p_kind LIKE 'order_%' OR p_kind IN ('app_links','custom') THEN CASE WHEN p_context->>'tracking_policy'='engagement' THEN 'engagement' ELSE 'open' END ELSE 'disabled' END,CASE WHEN p_kind='admin_notification_digest' THEN (p_data->>'dispatchId')::uuid END)
 ON CONFLICT(recipient_user,message_kind,dedupe_key) WHERE message_kind='admin_notification_digest' DO NOTHING RETURNING * INTO v_row;
 ELSE
 INSERT INTO public.email_messages(target_time,code,data,organization,occasion,unit,message_kind,dedupe_key,input_hash,recipient,recipient_user,order_id,source_version,expires_at,producer_actor,priority,workflow_state,post_action,tracking_policy,notification_dispatch_id)
 VALUES(p_not_before,p_code,p_data,v_org,v_occ,v_unit,p_kind,p_dedupe,v_hash,p_recipient,(p_context->>'recipient_user')::uuid,p_order,p_version,p_expires,coalesce((p_context->>'actor_id')::uuid,auth.uid()),
 CASE WHEN p_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue') THEN 0 WHEN p_kind='order_confirmation' THEN 10 ELSE 50 END,
 CASE WHEN p_not_before='infinity' THEN 'blocked' ELSE 'pending' END,p_post_action,CASE WHEN p_kind LIKE 'order_%' OR p_kind IN ('app_links','custom') THEN CASE WHEN p_context->>'tracking_policy'='engagement' THEN 'engagement' ELSE 'open' END ELSE 'disabled' END,CASE WHEN p_kind='admin_notification_digest' THEN (p_data->>'dispatchId')::uuid END)
 ON CONFLICT(organization,message_kind,dedupe_key) DO NOTHING RETURNING * INTO v_row;
 END IF;
 IF v_row.id IS NULL THEN
  SELECT * INTO v_row FROM public.email_messages WHERE (organization=v_org OR (p_kind='admin_notification_digest' AND recipient_user=(p_context->>'recipient_user')::uuid)) AND message_kind=p_kind AND dedupe_key=p_dedupe;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'email_active_notification_conflict'; END IF;
  IF v_row.input_hash<>v_hash THEN RAISE EXCEPTION 'email_dedupe_conflict'; END IF;
  RETURN jsonb_build_object('message_id',v_row.message_id,'state',v_row.workflow_state,'replayed',true);
 END IF;
 PERFORM public.admit_email_intent_v1(v_row.id);
 PERFORM public.notification_center_email_internal(v_row.message_id);
 IF p_not_before<=now() THEN PERFORM public.wake_email_worker(); END IF;
 RETURN jsonb_build_object('message_id',v_row.message_id,'state',v_row.workflow_state,'replayed',false);
END $$;

-- SOURCE: emails/fakturoid_email_gate.sql
CREATE OR REPLACE FUNCTION public.enqueue_ticket_order_confirmation_v1(
  p_command_id uuid, p_occasion bigint, p_order_payload jsonb, p_language text
) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_organization bigint;
  v_unit bigint;
  v_order_id bigint := (p_order_payload#>>'{order,id}')::bigint;
  v_await_fakturoid boolean;
BEGIN
  SELECT o.organization, o.unit INTO v_organization, v_unit
  FROM public.occasions o WHERE o.id = p_occasion;
  IF v_organization IS NULL OR p_command_id IS NULL OR v_order_id IS NULL
     OR p_order_payload IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid ticket order effect';
  END IF;
  SELECT (coalesce((p_order_payload#>>'{order,payment_info,amount}')::numeric,0)>0)
    AND EXISTS (SELECT 1 FROM eshop.external_services es
                WHERE es.unit=v_unit AND es.type='FAKTUROID')
  INTO v_await_fakturoid;
  IF v_await_fakturoid THEN
    UPDATE eshop.orders SET state='preparing_payment', updated_at=now()
    WHERE id=v_order_id AND occasion=p_occasion AND state='ordered';
    IF NOT FOUND THEN
      RAISE check_violation USING MESSAGE='Fakturoid order is not ready for preparation';
    END IF;
  END IF;
  PERFORM public.enqueue_order_email('TICKET_ORDER_CONFIRMATION',jsonb_build_object(
    'systemOrderDelivery','checkout','command_id',p_command_id,'ticket_order',p_order_payload,'lang',coalesce(nullif(p_language,''),(SELECT CASE WHEN data->>'DEFAULT_LANGUAGE'='en' THEN 'en' ELSE 'cs' END FROM public.organizations WHERE id=v_organization),'cs'),
    'fakturoid_pending',v_await_fakturoid),v_organization,p_occasion,v_unit,
    CASE WHEN v_await_fakturoid THEN 'infinity'::timestamptz ELSE now() END);

END;
$$;

-- SOURCE: emails/queue_payment_reminders.sql
CREATE OR REPLACE FUNCTION public.queue_payment_reminders_internal(p_occasion_id BIGINT, p_payment_info_id BIGINT)
RETURNS VOID
SET search_path = public, extensions AS $$
-- NULL payment scope is reserved for explicit occasion-wide settings changes.
-- Checkout and deadline changes only replace reminders for their own payment.
BEGIN
  IF public.is_demo_occasion(p_occasion_id) THEN RETURN; END IF;

  UPDATE public.email_messages SET workflow_state='cancelled',last_error='reminder_superseded',lease_token=NULL,lease_until=NULL
  WHERE ((p_payment_info_id IS NULL AND occasion=p_occasion_id) OR order_id IN (SELECT id FROM eshop.orders WHERE payment_info IN (SELECT payment_info FROM eshop.orders WHERE occasion=p_occasion_id AND (p_payment_info_id IS NULL OR payment_info=p_payment_info_id)))) AND message_kind='order_reminder' AND workflow_state IN ('pending','retry_wait','blocked','preparing');
  UPDATE eshop.payment_info pi SET email_reminder_version=email_reminder_version+1
  WHERE EXISTS(SELECT 1 FROM eshop.orders o WHERE o.payment_info=pi.id AND o.occasion=p_occasion_id AND (p_payment_info_id IS NULL OR pi.id=p_payment_info_id));

  PERFORM public.enqueue_order_email('TICKET_ORDER_REMINDER',jsonb_build_object(
      'systemOrderDelivery', 'payment_reminder', 'order_id', o.id
    ),occ.organization,o.occasion,occ.unit,pi.deadline - make_interval(secs=>coalesce((f.data->>'reminder_interval_seconds')::bigint,(form_settings.feature->>'reminder_interval_seconds')::bigint,86400))) FROM eshop.payment_info pi
  JOIN
    eshop.orders o ON pi.id = o.payment_info
  JOIN
    public.occasions occ ON o.occasion = occ.id

  LEFT JOIN LATERAL (
      SELECT elem AS feature
      FROM jsonb_array_elements(occ.features) elem
      WHERE elem->>'code' = 'form'
  ) form_settings ON TRUE

  LEFT JOIN public.forms f ON f.id = o.form
  WHERE
    o.payment_info IN (SELECT payment_info FROM eshop.orders WHERE occasion=p_occasion_id AND (p_payment_info_id IS NULL OR payment_info=p_payment_info_id))
    AND o.state = 'ordered'
    AND pi.payment_method='bank' AND public.payment_collection_action_internal(o.id)->'allowed'='true'::jsonb
    AND pi.data#>>'{payment_policy,mode}' IS DISTINCT FROM 'none'
    AND pi.deadline IS NOT NULL

    AND (pi.data->>'current_version_reminded')::boolean IS NOT TRUE

    AND (form_settings.feature->>'is_enabled')::boolean IS TRUE

    AND COALESCE((f.data->>'is_reminder_enabled')::boolean, (form_settings.feature->>'reminder_is_enabled')::boolean, TRUE) IS TRUE;

  PERFORM public.enqueue_order_email('TICKET_ORDER_REMINDER',jsonb_build_object(
      'systemOrderDelivery', 'payment_reminder', 'order_id', o.id,
      'is_deposit_reminder', true
    ),occ.organization,o.occasion,occ.unit,(occ.start_time - make_interval(days => (deposit_settings.feature->>'deposit_deadline_days')::int)) - make_interval(secs=>coalesce((f.data->>'reminder_interval_seconds')::bigint,(form_settings.feature->>'reminder_interval_seconds')::bigint,86400))) FROM eshop.payment_info pi
  JOIN
    eshop.orders o ON pi.id = o.payment_info
  JOIN
    public.occasions occ ON o.occasion = occ.id

  LEFT JOIN LATERAL (
      SELECT elem AS feature
      FROM jsonb_array_elements(occ.features) elem
      WHERE elem->>'code' = 'deposit'
  ) deposit_settings ON TRUE

  LEFT JOIN LATERAL (
      SELECT elem AS feature
      FROM jsonb_array_elements(occ.features) elem
      WHERE elem->>'code' = 'form'
  ) form_settings ON TRUE
  LEFT JOIN public.forms f ON f.id = o.form
  WHERE
    o.payment_info IN (SELECT payment_info FROM eshop.orders WHERE occasion=p_occasion_id AND (p_payment_info_id IS NULL OR payment_info=p_payment_info_id))
    -- Schedule the balance reminder before deposit payment, as order creation always did.
    AND o.state IN ('ordered','paid')
    AND pi.payment_method='bank' AND public.payment_collection_action_internal(o.id)->'allowed'='true'::jsonb
    AND pi.data#>>'{payment_policy,mode}' IS DISTINCT FROM 'none'
    AND pi.deposit_amount IS NOT NULL
    AND coalesce(pi.paid,0)-coalesce(pi.returned,0) < pi.amount

    AND (deposit_settings.feature->>'is_enabled')::boolean IS TRUE

    AND (deposit_settings.feature->>'deposit_deadline') IS DISTINCT FROM 'on_site'

    AND (deposit_settings.feature->>'deposit_deadline_days') IS NOT NULL

    AND occ.start_time IS NOT NULL

    AND (form_settings.feature->>'is_enabled')::boolean IS TRUE
    AND COALESCE((f.data->>'is_reminder_enabled')::boolean, (form_settings.feature->>'reminder_is_enabled')::boolean, TRUE) IS TRUE;

END;
$$ LANGUAGE plpgsql;

REVOKE ALL ON FUNCTION public.queue_payment_reminders_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Preserve the published occasion-wide scheduling boundary and interval argument.
CREATE OR REPLACE FUNCTION public.queue_payment_reminders(p_occasion_id BIGINT,p_seconds_before_deadline BIGINT)
RETURNS void LANGUAGE sql SET search_path=public,extensions AS $$
 SELECT public.queue_payment_reminders_internal(p_occasion_id,NULL);
$$;
