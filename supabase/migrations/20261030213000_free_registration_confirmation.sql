-- One lifecycle owner for checkout confirmation validity, reporting and repair.
-- A free registration is paid immediately. It still needs its configured
-- confirmation unless automatic ticket delivery replaces that message.
CREATE OR REPLACE FUNCTION public.order_checkout_email_kind_internal(p_order bigint)
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT CASE WHEN o.state='ordered' OR (
   o.state='paid' AND o.price=0 AND NOT (o.data ? 'ticketBatchOrigin')
   AND NOT (coalesce(oc.is_order_synchronization_enabled,false) AND EXISTS(
     SELECT 1 FROM jsonb_array_elements(coalesce(oc.features,'[]'::jsonb)) feature
     WHERE feature->>'code'='ticket' AND (feature->>'is_enabled')::boolean IS TRUE))
 ) THEN 'order_confirmation' ELSE 'order_tickets' END
 FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion WHERE o.id=p_order;
$$;
REVOKE ALL ON FUNCTION public.order_checkout_email_kind_internal(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.order_checkout_email_kind_internal(bigint) TO service_role;


CREATE OR REPLACE FUNCTION public.email_intent_valid(p_message public.email_messages) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_occ public.occasions; v_form public.forms; v_feature jsonb; v_deposit jsonb;
BEGIN
 PERFORM public.require_service_role();
 IF public.is_demo_occasion(p_message.occasion) THEN RETURN false; END IF;
 IF p_message.expires_at<=now() THEN RETURN false; END IF;
 IF p_message.message_kind='sign_in' AND EXISTS(SELECT 1 FROM public.occasion_users ou
   WHERE ou.occasion=p_message.occasion AND ou."user"=p_message.recipient_user AND (ou.is_editor OR ou.is_editor_view OR ou.is_manager)) THEN
  RETURN false; END IF;
 IF p_message.message_kind='custom' AND p_message.code='TEAM_INVITATION' THEN
  RETURN EXISTS(SELECT 1 FROM public.occasion_team_invitations i
   JOIN public.occasions o ON o.id=i.occasion AND o.unit=i.unit AND o.organization=i.organization
   JOIN public.unit_users uu ON uu.unit=i.unit AND uu."user"=i.created_by AND uu.is_manager
   WHERE i.message_id=p_message.message_id AND i.accepted_at IS NULL AND i.expires_at>now()
    AND i.email=p_message.recipient AND i.occasion=p_message.occasion AND i.organization=p_message.organization);
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='UNIT_VERIFICATION_REQUEST' THEN
  RETURN EXISTS(SELECT 1 FROM public.unit_legal_profiles p JOIN public.units u ON u.id=p.unit_id
   JOIN public.organization_users ou ON ou.organization=u.organization AND ou."user"=p_message.recipient_user AND ou.is_admin
   WHERE p.unit_id=p_message.unit AND u.organization=p_message.organization AND p.status='pending'
    AND p.revision=p_message.source_version
    AND public.get_user_delivery_email(ou."user")=p_message.recipient);
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='BANK_SYNC_WARNING' THEN
  IF NOT EXISTS (SELECT 1 FROM eshop.bank_sync_health h JOIN eshop.bank_sync_connections c ON c.id=h.connection_id
    WHERE h.connection_id=(p_message.data->>'connection_id')::bigint
      AND h.incident_id::text=p_message.data->>'incident_id' AND h.warning_code IS NOT NULL
      AND c.state IN ('connected','degraded') AND public.bank_sync_problem(c.id) IS NOT NULL
      AND EXISTS(SELECT 1 FROM eshop.bank_account_users bau WHERE bau."user"=p_message.recipient_user AND bau.is_admin
        AND (bau.bank_account=c.bank_account_id OR bau.bank_account IN
          (SELECT x.bank_account_id FROM eshop.bank_sync_account_aliases x WHERE x.connection_id=c.id)))) THEN RETURN false; END IF;
 END IF;
 IF p_message.message_kind='custom' AND p_message.code='ORDER_OVERVIEW' THEN RETURN false; END IF;
 IF p_message.order_id IS NULL THEN
  IF p_message.recipient_user IS NOT NULL AND p_message.message_kind<>'deletion_complete' THEN
   IF p_message.message_kind<>'gotrue' AND public.get_user_delivery_email(p_message.recipient_user) IS DISTINCT FROM p_message.recipient THEN RETURN false; END IF;
   IF p_message.data ? 'sign_in_code_version' AND NOT EXISTS(SELECT 1 FROM public.sign_in_codes WHERE user_id=p_message.recipient_user AND version::text=p_message.data->>'sign_in_code_version' AND expires_at>now() AND consumed_at IS NULL AND attempts<5) THEN RETURN false; END IF;
   IF p_message.data ? 'password_version' AND NOT EXISTS(SELECT 1 FROM auth.users WHERE id=p_message.recipient_user AND encode(extensions.digest(encrypted_password,'sha256'),'hex')=p_message.data->>'password_version') THEN RETURN false; END IF;
   IF p_message.data ? 'reset_hash' AND NOT EXISTS(SELECT 1 FROM public.user_reset_token WHERE "user"=p_message.recipient_user AND encode(extensions.digest(token::text,'sha256'),'hex')=p_message.data->>'reset_hash') THEN RETURN false; END IF;
  END IF;
  IF p_message.data ? 'deletion_request' AND NOT EXISTS(SELECT 1 FROM public.account_deletion_requests WHERE id=(p_message.data->>'deletion_request')::uuid AND status IN ('email_pending','email_sent') AND expires_at>now()) THEN RETURN false; END IF;
  IF p_message.data ? 'google_attempt' AND NOT EXISTS(SELECT 1 FROM public.external_login_attempts WHERE id=(p_message.data->>'google_attempt')::uuid AND mailbox_hash=p_message.data->>'mailbox_hash' AND expires_at>now() AND NOT mailbox_verified) THEN RETURN false; END IF;
  RETURN true;
 END IF;
 SELECT * INTO v_order FROM eshop.orders WHERE id=p_message.order_id;
 IF v_order.id IS NULL OR v_order.occasion<>p_message.occasion THEN RETURN false; END IF;
 IF p_message.data->>'repair_payment_fingerprint' IS NOT NULL AND p_message.data->>'repair_payment_fingerprint' IS DISTINCT FROM public.order_email_payment_fingerprint(v_order.id) THEN RETURN false; END IF;
 IF p_message.message_kind='custom' AND p_message.code='ORDER_OVERVIEW' THEN
  RETURN v_order.data->>'email'=p_message.recipient AND EXISTS(
   SELECT 1 FROM eshop.order_overview_sources s JOIN eshop.waitlist_capabilities c USING(token_hash)
   WHERE s.command_id=(p_message.data->>'order_overview_command')::uuid AND c.kind='order_view'
   AND c.order_id=v_order.id AND c.form_id=v_order.form AND c.organization_id=p_message.organization
   AND c.revoked_at IS NULL AND c.expires_at>now() AND s.expires_at=c.expires_at);
 END IF;
 IF p_message.message_kind='waitlist_confirmation' THEN
  RETURN v_order.state='waitlisted' AND v_order.data->>'email'=p_message.recipient;
 END IF;
 IF p_message.message_kind='waitlist_offer' THEN
  RETURN v_order.state='waitlisted' AND v_order.data->>'email'=p_message.recipient AND EXISTS(
   SELECT 1 FROM eshop.waitlist_offers w JOIN eshop.waitlist_offer_slots s ON s.offer_id=w.id
   WHERE w.id=(p_message.data->>'offer_id')::uuid AND w.order_id=v_order.id AND w.expires_at>clock_timestamp() AND s.outcome='pending');
 END IF;
 IF p_message.message_kind='order_storno' THEN RETURN true; END IF;
 IF v_order.state IN ('storno','expired','preparing_payment') THEN RETURN false; END IF;
 IF p_message.message_kind IN ('order_payment_notice','order_tickets') THEN
  IF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=v_order.payment_info AND payment_method='stripe')
   AND public.stripe_order_payment_projection_internal(v_order.id)->>'admissionState' IS DISTINCT FROM 'valid' THEN RETURN false; END IF;
  RETURN v_order.state IN ('paid','sent') AND v_order.email_payment_version=p_message.source_version
   AND (p_message.data->>'manual'='true' OR v_order.data->>'email'=p_message.recipient);
 END IF;
 IF p_message.message_kind='order_confirmation' THEN
  RETURN public.order_checkout_email_kind_internal(v_order.id)='order_confirmation'
   AND v_order.state IN ('ordered','paid') AND v_order.email_payment_version=p_message.source_version
   AND v_order.data->>'email'=p_message.recipient;
 END IF;
 IF p_message.message_kind='order_reminder' THEN
  SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
  IF v_pi.payment_method='stripe' THEN RETURN false; END IF;
  SELECT * INTO v_occ FROM public.occasions WHERE id=v_order.occasion;
  SELECT * INTO v_form FROM public.forms WHERE id=v_order.form;
  SELECT x INTO v_feature FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='form';
  SELECT x INTO v_deposit FROM jsonb_array_elements(v_occ.features) x WHERE x->>'code'='deposit';
  IF p_message.target_time<now()-interval '7 days' OR p_message.source_version IS DISTINCT FROM v_pi.email_reminder_version
   OR coalesce((v_feature->>'is_enabled')::boolean,false)=false
   OR coalesce((v_form.data->>'is_reminder_enabled')::boolean,(v_feature->>'reminder_is_enabled')::boolean,true)=false THEN RETURN false; END IF;
  IF (p_message.data->>'is_deposit_reminder')::boolean IS TRUE THEN
   RETURN v_order.state IN ('paid','sent') AND v_pi.deposit_amount IS NOT NULL AND v_pi.paid<v_pi.amount
    AND (v_deposit->>'is_enabled')::boolean IS TRUE AND v_deposit->>'deposit_deadline' IS DISTINCT FROM 'on_site';
  END IF;
  RETURN v_order.state='ordered' AND v_pi.deadline IS NOT NULL AND coalesce((v_pi.data->>'current_version_reminded')::boolean,false)=false;
 END IF;
 RETURN true;
END $$;

-- Current issues are explicit provenance chains, independent of historical counts.
-- This invoker helper is only reachable through authorized reporting functions.
CREATE OR REPLACE FUNCTION public.order_email_current_issues(p_order bigint) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH RECURSIVE messages AS (
  SELECT m.*,CASE WHEN m.complained_at IS NULL AND m.last_error IS DISTINCT FROM 'post_action_failed'
   AND coalesce(m.provider_failure,'') NOT IN ('reject','rendering_failure')
   AND greatest(m.bounced_at,events.bounce) IS NOT NULL
   AND greatest(m.delivered_at,events.delivery)>greatest(m.bounced_at,events.bounce)
   THEN 'delivery' ELSE public.email_reporting_state(m) END rs FROM public.email_messages m
  LEFT JOIN LATERAL (SELECT max(provider_time) FILTER(WHERE event_type='bounce') bounce,
   max(provider_time) FILTER(WHERE event_type='delivery') delivery
   FROM public.email_delivery_events e WHERE e.message_id=m.message_id) events ON true
  JOIN eshop.orders o ON o.id=m.order_id AND o.occasion=m.occasion
  JOIN public.occasions oc ON oc.id=o.occasion AND oc.organization=m.organization
  WHERE m.order_id=p_order AND o.state<>'storno'),
 chain AS (
  SELECT m.message_id root,m.message_id leaf,ARRAY[m.message_id] path FROM messages m
  WHERE NOT EXISTS(SELECT 1 FROM messages parent WHERE parent.message_id::text=m.data->>'repair_source_message_id' AND parent.message_kind=m.message_kind)
  UNION ALL
  SELECT c.root,m.message_id,c.path||m.message_id FROM chain c JOIN messages parent ON parent.message_id=c.leaf
  JOIN messages m ON m.data->>'repair_source_message_id'=c.leaf::text AND m.message_kind=parent.message_kind
  WHERE NOT m.message_id=ANY(c.path)),
 leaves AS (SELECT DISTINCT ON (root) * FROM chain ORDER BY root,cardinality(path) DESC,leaf),
 issues AS (
  SELECT root.message_id source_message_id,leaf.message_id,root.message_kind kind,root.recipient original_recipient,
   leaf.recipient,leaf.rs state,
   coalesce(leaf.last_error,CASE WHEN leaf.workflow_state IN ('pending','preparing','blocked') THEN
    (SELECT CASE WHEN paused THEN 'queue_paused' WHEN daily_quota<=provider_sent_24h THEN 'queue_limit' END FROM public.email_capacity) END) reason,
   (SELECT reason FROM public.email_suppressions WHERE recipient=lower(leaf.recipient)) suppression_reason,
   CASE WHEN o.state='storno' THEN 'cancelled'
    WHEN leaf.rs IN ('delivery','open','click') AND leaf.delivered_at IS NOT NULL
     AND (leaf.recipient IS DISTINCT FROM o.data->>'email' OR leaf.source_version IS DISTINCT FROM o.email_payment_version
      OR (leaf.data->>'repair_payment_fingerprint' IS NOT NULL AND leaf.data->>'repair_payment_fingerprint' IS DISTINCT FROM public.order_email_payment_fingerprint(o.id))) THEN 'stale_delivery'
    WHEN leaf.message_id<>root.message_id AND leaf.rs IN ('pending','preparing','accepted','open','click','sending','blocked') THEN 'waiting_repair'
    ELSE leaf.rs END resolution,
   (root.message_kind<>public.order_checkout_email_kind_internal(o.id)) obsolete
  FROM leaves c JOIN messages root ON root.message_id=c.root JOIN messages leaf ON leaf.message_id=c.leaf
  JOIN eshop.orders o ON o.id=p_order
  WHERE (EXISTS(SELECT 1 FROM messages m WHERE m.message_id=ANY(c.path)
    AND (m.rs IN ('bounce','complaint','reject','rendering_failure','dead','suppressed','unknown','retry_wait','delay','blocked','sending','post_action_failed')
     OR (m.message_kind IN ('order_confirmation','order_tickets') AND m.workflow_state IN ('pending','preparing') AND m.target_time<=now()))))
   -- Delivered current tickets supersede the obsolete checkout confirmation,
   -- even though confirmation and ticket repairs intentionally have separate chains.
   -- Acceptance/open tracking alone, stale snapshots and unrelated message kinds
   -- must never clear an actionable delivery failure.
   AND NOT (root.message_kind='order_confirmation' AND o.state IN ('paid','sent')
    AND EXISTS(SELECT 1 FROM messages tickets WHERE tickets.message_kind='order_tickets'
     AND tickets.rs IN ('delivery','open','click') AND tickets.delivered_at IS NOT NULL
     AND tickets.recipient=o.data->>'email' AND tickets.source_version=o.email_payment_version
     AND (tickets.data->>'repair_payment_fingerprint' IS NULL
      OR tickets.data->>'repair_payment_fingerprint'=public.order_email_payment_fingerprint(o.id))
     AND tickets.delivered_at>greatest(leaf.created_at,leaf.bounced_at,leaf.complained_at,
      (SELECT max(provider_time) FROM public.email_delivery_events
       WHERE message_id=leaf.message_id AND event_type IN ('bounce','complaint','reject','rendering_failure')))))
   AND NOT (leaf.delivered_at IS NOT NULL AND leaf.rs IN ('delivery','open','click')
    AND leaf.recipient=o.data->>'email' AND leaf.source_version=o.email_payment_version
    AND (leaf.data->>'repair_payment_fingerprint' IS NULL OR leaf.data->>'repair_payment_fingerprint'=public.order_email_payment_fingerprint(o.id))))
 SELECT coalesce(jsonb_agg(to_jsonb(issues) ORDER BY source_message_id),'[]'::jsonb) FROM issues;
$$;

CREATE OR REPLACE FUNCTION public.repair_order_email_client_sync_v1(
 p_order bigint,p_expected_email text,p_expected_state text,p_expected_payment_version bigint,
 p_email text,p_source_message uuid,p_resend boolean,p_command_id uuid,p_expected_payment_fingerprint text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; oc public.occasions; src public.email_messages; active public.email_messages;
 v_begin jsonb; v_hash text; v_email text; v_form bigint; v_field bigint; v_fields jsonb;
 v_kind text; v_intent jsonb; v_users uuid[]; v_payload jsonb; v_details jsonb;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 SELECT * INTO oc FROM public.occasions WHERE id=o.occasion;
 IF auth.uid() IS NULL OR o.id IS NULL OR NOT coalesce(public.can_write_orders(o.occasion),false) THEN
  RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 -- Re-authorize the object relationship even on receipt replay.
 IF p_source_message IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.email_messages m
  WHERE m.message_id=p_source_message AND m.order_id=o.id AND m.occasion=o.occasion
   AND m.organization=oc.organization AND public.email_report_allowed(m.organization,m.occasion,m.recipient_user)) THEN
  RAISE insufficient_privilege USING MESSAGE='order email unavailable'; END IF;
 v_hash:=encode(extensions.digest(jsonb_build_object('order',p_order,'expectedEmail',p_expected_email,
  'expectedState',p_expected_state,'expectedVersion',p_expected_payment_version,'email',p_email,
  'source',p_source_message,'resend',p_resend,'paymentFingerprint',p_expected_payment_fingerprint)::text,'sha256'),'hex');
 v_begin:=public.begin_client_mutation_v1(p_command_id,'inventory.order.repair_email',o.occasion,auth.uid(),v_hash);
 IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
 v_form:=o.form;
 -- Same form -> order -> message order as response editing / send fencing.
 IF v_form IS NOT NULL THEN PERFORM 1 FROM public.forms WHERE id=v_form FOR SHARE; END IF;
 SELECT * INTO o FROM eshop.orders WHERE id=p_order FOR UPDATE;
 IF o.id IS NULL OR o.form IS DISTINCT FROM v_form OR o.data->>'email' IS DISTINCT FROM p_expected_email
  OR o.state IS DISTINCT FROM p_expected_state OR o.email_payment_version IS DISTINCT FROM p_expected_payment_version
  OR p_expected_payment_fingerprint IS DISTINCT FROM public.order_email_payment_fingerprint(o.id) THEN
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('reason','order_changed')); END IF;
 PERFORM public.check_occasion_writable(o.occasion);
 IF o.state NOT IN ('ordered','paid','sent') THEN RAISE EXCEPTION 'ORDER_ACTION_NOT_ALLOWED'; END IF;
 IF p_resend IS NULL OR p_email IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='invalid_email_contact'; END IF;
 v_email:=public.normalize_order_email_contact(p_email);
 v_kind:=public.order_checkout_email_kind_internal(o.id);
 PERFORM 1 FROM public.email_messages WHERE order_id=o.id ORDER BY id FOR UPDATE;
 SELECT * INTO src FROM public.email_messages WHERE message_id=p_source_message;
 IF p_resend AND src.id IS NOT NULL AND (src.message_kind<>v_kind OR src.last_error='post_action_failed') THEN
  RAISE EXCEPTION 'source_not_resendable'; END IF;
 -- An issued permit or unknown outcome cannot be bypassed by changing contact.
 IF p_resend AND EXISTS(SELECT 1 FROM public.email_messages WHERE order_id=o.id AND message_kind IN ('order_confirmation','order_tickets')
  AND workflow_state IN ('sending','unknown')) THEN RAISE EXCEPTION 'email_outcome_unresolved'; END IF;
 IF p_resend AND EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(v_email)) THEN
  RAISE EXCEPTION 'email_recipient_suppressed'; END IF;
 IF p_resend THEN
  SELECT * INTO active FROM public.email_messages WHERE order_id=o.id AND message_kind=v_kind
   AND workflow_state IN ('pending','preparing','retry_wait','blocked')
   AND recipient=o.data->>'email' AND source_version=o.email_payment_version
   AND (expires_at IS NULL OR expires_at>now())
   ORDER BY id DESC LIMIT 1;
  IF active.id IS NOT NULL THEN
   RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
    jsonb_build_object('reason','active_email_intent','messageId',active.message_id)); END IF;
 END IF;
 -- Repair chains have one successor per source. A stale source cannot fork
 -- around a newer failed/waiting attempt, even after its active lease ended.
 IF p_resend AND src.id IS NOT NULL AND EXISTS(SELECT 1 FROM public.email_messages
  WHERE order_id=o.id AND data->>'repair_source_message_id'=src.message_id::text) THEN
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
   jsonb_build_object('reason','source_replaced')); END IF;
 -- Update only the existing contact projection, without invoking pricing/stock.
 SELECT min(id) INTO v_field FROM public.form_fields WHERE form=v_form AND type='email';
 IF (SELECT count(*) FROM public.form_fields WHERE form=v_form AND type='email')>1 THEN
  RAISE EXCEPTION 'ambiguous_contact_field'; END IF;
 IF v_field IS NOT NULL THEN
  SELECT coalesce(jsonb_agg(e - v_field::text) FILTER (WHERE e - v_field::text<>'{}'::jsonb),'[]') INTO v_fields
   FROM jsonb_array_elements(coalesce(o.data->'fields','[]')) e;
  o.data:=jsonb_set(o.data,'{fields}',v_fields||jsonb_build_array(jsonb_build_object(v_field::text,v_email)));
 END IF;
 UPDATE eshop.orders SET data=jsonb_set(o.data,'{email}',to_jsonb(v_email)),updated_at=now()
  WHERE id=o.id RETURNING * INTO o;
 INSERT INTO eshop.orders_history("order",state,price,currency_code,data,created_by)
  VALUES(o.id,o.state,o.price,o.currency_code,o.data,auth.uid());
 -- A prepared payload is a snapshot of its recipient; retire pre-permit old
 -- contacts explicitly, including legacy manual ticket snapshots.
 UPDATE public.email_messages SET workflow_state='cancelled',last_error='contact_changed',lease_token=NULL,lease_until=NULL
  WHERE order_id=o.id AND recipient IS DISTINCT FROM v_email
   AND workflow_state IN ('pending','preparing','retry_wait','blocked');
 IF p_resend THEN
  v_payload:=jsonb_build_object('order_id',o.id,'requested_by',auth.uid(),'repair_source_message_id',p_source_message,'repair_payment_fingerprint',p_expected_payment_fingerprint);
  IF v_kind='order_confirmation' THEN
   -- The existing confirmation renderer consumes the canonical checkout shape,
   -- not an order ID. Rebuild it from current facts without a checkout mutation.
   v_details:=public.get_order_details_for_email(o.id)->'data';
   -- Each explicit resend owns its command identity. Reusing the checkout
   -- command collides with the unique confirmation-command index.
   v_payload:=v_payload||jsonb_build_object('command_id',p_command_id,
    'ticket_order',jsonb_build_object('order',v_details->'order'||jsonb_build_object(
     'occasion',v_details->'occasion','reply_to',v_details->'reply_to',
     'form',jsonb_build_object('id',o.form,'data',v_details->'form_data'),
     'payment_info',coalesce(v_details->'payment_info','{}')||jsonb_build_object(
      'account_number',v_details#>'{bank_account,account_number}',
      'account_number_human_readable',v_details#>'{bank_account,account_number_human_readable}',
      'creditor_name',v_details#>'{bank_account,creditor_name}'))));
  END IF;
  v_intent:=public.enqueue_order_email(CASE v_kind WHEN 'order_confirmation' THEN 'TICKET_ORDER_CONFIRMATION' ELSE 'ORDER_TICKETS' END,
   v_payload,
   oc.organization,oc.id,oc.unit,now(),'repair:'||p_command_id);
  IF v_intent->>'message_id' IS NULL OR coalesce((v_intent->>'replayed')::boolean,false) THEN
   RAISE EXCEPTION 'email_enqueue_rejected'; END IF;
 END IF;
 SELECT coalesce(array_agg("user"),'{}') INTO v_users FROM public.occasion_users WHERE occasion=o.occasion;
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,o.occasion,'inventory.order.repair_email',
  jsonb_build_array(jsonb_build_object('entityType','order','entityId',o.id,'operation','update',
    'safeLabel','Order contact','changedFields',jsonb_build_array('data'))),v_users,
  jsonb_build_object('order',to_jsonb(o)||jsonb_build_object('email_payment_fingerprint',public.order_email_payment_fingerprint(o.id)),'intent',v_intent,'sendingRequested',p_resend));
END $$;
