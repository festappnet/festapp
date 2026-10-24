-- Form payment settings: explicit override > occasion default > application default.
BEGIN;
CREATE OR REPLACE FUNCTION public.queue_payment_reminders(p_occasion_id BIGINT, p_seconds_before_deadline BIGINT)
RETURNS VOID
SET search_path = public, extensions AS $$
-- The interval argument is retained for callers; persisted form/occasion settings own scheduling.
BEGIN


  UPDATE public.email_messages SET workflow_state='cancelled',last_error='reminder_superseded',lease_token=NULL,lease_until=NULL
  WHERE (occasion=p_occasion_id OR order_id IN (SELECT id FROM eshop.orders WHERE payment_info IN (SELECT payment_info FROM eshop.orders WHERE occasion=p_occasion_id))) AND message_kind='order_reminder' AND workflow_state IN ('pending','retry_wait','blocked','preparing');
  UPDATE eshop.payment_info pi SET email_reminder_version=email_reminder_version+1
  WHERE EXISTS(SELECT 1 FROM eshop.orders o WHERE o.payment_info=pi.id AND o.occasion=p_occasion_id);







  PERFORM public.enqueue_order_email('TICKET_ORDER_REMINDER',jsonb_build_object(
      'order_id', o.id
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
    (o.occasion=p_occasion_id OR o.payment_info IN (SELECT payment_info FROM eshop.orders WHERE occasion=p_occasion_id))
    AND o.state = 'ordered'
    AND pi.deadline IS NOT NULL



    AND (pi.data->>'current_version_reminded')::boolean IS NOT TRUE


    AND (form_settings.feature->>'is_enabled')::boolean IS TRUE



    AND COALESCE((f.data->>'is_reminder_enabled')::boolean, (form_settings.feature->>'reminder_is_enabled')::boolean, TRUE) IS TRUE;








  PERFORM public.enqueue_order_email('TICKET_ORDER_REMINDER',jsonb_build_object(
      'order_id', o.id,
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
    (o.occasion=p_occasion_id OR o.payment_info IN (SELECT payment_info FROM eshop.orders WHERE occasion=p_occasion_id))
    AND o.state = 'paid'
    AND pi.deposit_amount IS NOT NULL
    AND pi.paid < pi.amount

    AND (deposit_settings.feature->>'is_enabled')::boolean IS TRUE

    AND (deposit_settings.feature->>'deposit_deadline') IS DISTINCT FROM 'on_site'

    AND (deposit_settings.feature->>'deposit_deadline_days') IS NOT NULL

    AND occ.start_time IS NOT NULL

    AND (form_settings.feature->>'is_enabled')::boolean IS TRUE
    AND COALESCE((f.data->>'is_reminder_enabled')::boolean, (form_settings.feature->>'reminder_is_enabled')::boolean, TRUE) IS TRUE;

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.wake_email_worker() RETURNS void LANGUAGE plpgsql SECURITY INVOKER
SET search_path=public,extensions AS $$
DECLARE v_url text;
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 IF current_setting('festapp.email_wake',true)='scheduled' THEN RETURN; END IF;
 SELECT worker_url INTO v_url FROM public.email_capacity WHERE NOT paused;
 IF v_url IS NULL OR NOT (EXISTS(SELECT 1 FROM public.email_messages WHERE workflow_state IN ('pending','retry_wait') AND target_time<=now())
  OR EXISTS(SELECT 1 FROM public.email_capacity WHERE quota_at IS NULL OR quota_at<now()-interval '5 minutes')) THEN RETURN; END IF;
 PERFORM set_config('festapp.email_wake','scheduled',true);
 BEGIN
  PERFORM net.http_post(url:=v_url,body:=jsonb_build_object('requestSecret',public.generate_request_secret(120)),timeout_milliseconds:=5000);
 EXCEPTION WHEN OTHERS THEN
  -- Do not invert producer order/message locks against gateway capacity/order locks.
  UPDATE public.email_capacity SET wake_error='wake_failed' WHERE ctid IN (SELECT ctid FROM public.email_capacity FOR UPDATE SKIP LOCKED);
 END;
END $$;

-- Internal service boundary. Domain functions are the only caller for public commands.
CREATE OR REPLACE FUNCTION public.enqueue_email(p_kind text,p_context jsonb,p_recipient text,p_data jsonb,p_dedupe text,
 p_code text DEFAULT '',p_not_before timestamptz DEFAULT now(),p_expires timestamptz DEFAULT NULL,
 p_order bigint DEFAULT NULL,p_version bigint DEFAULT NULL,p_post_action jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE v_hash text; v_row public.email_messages; v_org bigint:=(p_context->>'organization')::bigint; v_occ bigint:=(p_context->>'occasion')::bigint; v_unit bigint:=(p_context->>'unit')::bigint;
BEGIN
 IF current_user NOT IN ('postgres','service_role') THEN PERFORM public.require_service_role(); END IF;
 IF v_org IS NULL OR p_kind NOT IN ('order_confirmation','order_payment_notice','order_tickets','order_reminder','order_update','order_storno','custom','registration','sign_in','reset_password','app_links','deletion_confirm','deletion_complete','google_mailbox','gotrue','waitlist_confirmation','waitlist_offer')
 OR p_dedupe IS NULL OR length(p_dedupe)>512 OR (p_recipient IS NOT NULL AND (length(p_recipient)>320 OR position('@' in p_recipient)=0)) THEN RAISE EXCEPTION 'invalid_email_intent'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=v_org) OR
 (v_occ IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=v_occ AND organization=v_org AND (NOT p_context ? 'unit' OR unit IS NOT DISTINCT FROM v_unit))) THEN RAISE EXCEPTION 'email_scope_mismatch'; END IF;
 IF p_order IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.orders WHERE id=p_order AND occasion=v_occ) THEN RAISE EXCEPTION 'email_order_scope_mismatch'; END IF;
 IF v_occ IS NOT NULL THEN SELECT unit INTO v_unit FROM public.occasions WHERE id=v_occ; END IF;
 v_hash:=encode(extensions.digest(jsonb_build_object('context',p_context-'tracking_policy','recipient',p_recipient,'data',p_data-'requested_by','code',p_code,'version',p_version,'post',p_post_action)::text,'sha256'),'hex');
 INSERT INTO public.email_messages(target_time,code,data,organization,occasion,unit,message_kind,dedupe_key,input_hash,recipient,recipient_user,order_id,source_version,expires_at,priority,workflow_state,post_action,tracking_policy)
 VALUES(p_not_before,p_code,p_data,v_org,v_occ,v_unit,p_kind,p_dedupe,v_hash,p_recipient,(p_context->>'recipient_user')::uuid,p_order,p_version,p_expires,
 CASE WHEN p_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue') THEN 0 WHEN p_kind='order_confirmation' THEN 10 ELSE 50 END,
 CASE WHEN p_not_before='infinity' THEN 'blocked' ELSE 'pending' END,p_post_action,CASE WHEN p_kind LIKE 'order_%' OR p_kind IN ('app_links','custom') THEN CASE WHEN p_context->>'tracking_policy'='engagement' THEN 'engagement' ELSE 'open' END ELSE 'disabled' END)
 ON CONFLICT(organization,message_kind,dedupe_key) DO NOTHING RETURNING * INTO v_row;
 IF v_row.id IS NULL THEN
  SELECT * INTO v_row FROM public.email_messages WHERE organization=v_org AND message_kind=p_kind AND dedupe_key=p_dedupe;
  IF v_row.input_hash<>v_hash THEN RAISE EXCEPTION 'email_dedupe_conflict'; END IF;
  RETURN jsonb_build_object('message_id',v_row.message_id,'state',v_row.workflow_state,'replayed',true);
 END IF;
 IF p_not_before<=now() THEN PERFORM public.wake_email_worker(); END IF;
 RETURN jsonb_build_object('message_id',v_row.message_id,'state',v_row.workflow_state,'replayed',false);
END $$;

CREATE OR REPLACE FUNCTION public.email_intent_valid(p_message public.email_messages) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_order eshop.orders; v_pi eshop.payment_info; v_occ public.occasions; v_form public.forms; v_feature jsonb; v_deposit jsonb;
BEGIN
 PERFORM public.require_service_role();
 IF p_message.expires_at<=now() THEN RETURN false; END IF;
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
  RETURN v_order.state IN ('paid','sent') AND v_order.email_payment_version=p_message.source_version
   AND (p_message.data->>'manual'='true' OR v_order.data->>'email'=p_message.recipient);
 END IF;
 IF p_message.message_kind='order_reminder' THEN
  SELECT * INTO v_pi FROM eshop.payment_info WHERE id=v_order.payment_info;
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

CREATE OR REPLACE FUNCTION public.recover_email_leases() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 -- Sending expiry is ambiguous, preparation expiry is safe to recover.
 UPDATE public.email_attempts a SET state='unknown',finished_at=now(),error_code='lease_expired'
 FROM public.email_messages m WHERE m.message_id=a.message_id AND m.workflow_state='sending' AND m.lease_until<now() AND a.state='sending';
 UPDATE public.email_messages SET workflow_state='unknown',last_error='lease_expired' WHERE workflow_state='sending' AND lease_until<now();
 UPDATE public.email_attempts a SET state='cancelled',finished_at=now() FROM public.email_messages m
 WHERE a.message_id=m.message_id AND a.lease_token=m.lease_token AND a.state='preparing' AND m.lease_until<now();
 UPDATE public.email_messages SET workflow_state='pending',lease_token=NULL,lease_until=NULL WHERE workflow_state='preparing' AND lease_until<now();

END $$;
REVOKE ALL ON FUNCTION public.recover_email_leases() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.recover_email_leases() TO service_role;

CREATE OR REPLACE FUNCTION public.claim_email() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_row public.email_messages; v_cap public.email_capacity; v_attempt uuid; v_token uuid:=extensions.gen_random_uuid();
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO v_cap FROM public.email_capacity FOR UPDATE;
 PERFORM public.recover_email_leases();
 UPDATE public.email_capacity SET heartbeat_at=now() WHERE singleton;
 IF v_cap.paused OR v_cap.quota_at IS NULL OR v_cap.quota_at<now()-interval '15 minutes' OR v_cap.circuit_until>now()
  OR (SELECT count(*) FROM public.email_messages WHERE workflow_state='preparing' AND lease_until>now())>=v_cap.max_preparing THEN RETURN NULL; END IF;
 SELECT * INTO v_row FROM public.email_messages m
 WHERE workflow_state IN ('pending','retry_wait') AND target_time<=now()
 AND (m.prepared IS NOT NULL OR m.message_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue','order_confirmation')
  OR (SELECT count(*) FROM public.email_messages heavy WHERE heavy.workflow_state='preparing' AND heavy.lease_until>now() AND heavy.prepared IS NULL
   AND heavy.message_kind NOT IN ('registration','sign_in','reset_password','google_mailbox','gotrue','order_confirmation'))<greatest(1,v_cap.max_preparing-1))
 AND NOT EXISTS(SELECT 1 FROM public.email_messages prior WHERE prior.order_id=m.order_id AND prior.message_kind='order_confirmation'
  AND m.message_kind<>'order_confirmation' AND prior.workflow_state NOT IN ('accepted','cancelled','expired'))
 ORDER BY priority-greatest(0,floor(extract(epoch FROM now()-created_at)/300))::integer,
 (SELECT max(a.created_at) FROM public.email_attempts a JOIN public.email_messages served ON served.message_id=a.message_id WHERE served.organization=m.organization) NULLS FIRST,target_time,id FOR UPDATE SKIP LOCKED LIMIT 1;
 IF v_row.id IS NULL THEN RETURN NULL; END IF;
 IF NOT public.email_intent_valid(v_row) THEN
  UPDATE public.email_messages SET workflow_state=CASE WHEN expires_at<=now() THEN 'expired' ELSE 'cancelled' END,last_error='intent_invalid' WHERE id=v_row.id;
  RETURN jsonb_build_object('skipped',true);
 END IF;
 UPDATE public.email_messages SET workflow_state='preparing',lease_token=v_token,lease_until=now()+interval '90 seconds' WHERE id=v_row.id RETURNING * INTO v_row;
 INSERT INTO public.email_attempts(message_id,lease_token,state) VALUES(v_row.message_id,v_token,'preparing') RETURNING attempt_id INTO v_attempt;
 RETURN to_jsonb(v_row)||jsonb_build_object('attempt_id',v_attempt);
END $$;

-- Keep the global preparation permit while rendering still runs; expired workers cannot renew.
CREATE OR REPLACE FUNCTION public.renew_email_preparation(p_message uuid,p_token uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE public.email_messages SET lease_until=now()+interval '90 seconds'
 WHERE message_id=p_message AND lease_token=p_token AND workflow_state='preparing' AND lease_until>now();
 IF NOT FOUND THEN RAISE EXCEPTION 'stale_email_preparation'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.renew_email_preparation(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.renew_email_preparation(uuid,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.prepare_email(p_message uuid,p_token uuid,p_prepared jsonb,p_post_action jsonb DEFAULT '{}') RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE public.email_messages SET prepared=coalesce(prepared,p_prepared),
 prepared_hash=coalesce(prepared_hash,encode(extensions.digest(p_prepared::text,'sha256'),'hex')),prepared_at=coalesce(prepared_at,now()),
 tracking_policy=CASE WHEN prepared IS NULL AND message_kind LIKE 'order_%' AND p_post_action->>'tracking_policy'='engagement' THEN 'engagement' ELSE tracking_policy END,
 post_action=CASE WHEN prepared IS NULL THEN post_action||p_post_action ELSE post_action END
 WHERE message_id=p_message AND lease_token=p_token AND lease_until>now() AND workflow_state='preparing'
 AND (prepared IS NULL OR prepared=p_prepared);
 IF NOT FOUND THEN RAISE EXCEPTION 'stale_email_preparation'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.begin_email_send(p_attempt uuid,p_token uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_attempt public.email_attempts; v_row public.email_messages; v_cap public.email_capacity; v_rate numeric; v_daily numeric; v_used numeric;
BEGIN
 PERFORM public.require_service_role();
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
  UPDATE public.email_messages SET workflow_state=CASE WHEN EXISTS(SELECT 1 FROM public.email_suppressions WHERE recipient=lower(v_row.recipient)) THEN 'suppressed' ELSE 'cancelled' END WHERE id=v_row.id;
  UPDATE public.email_attempts SET state='cancelled',finished_at=now() WHERE attempt_id=p_attempt;
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
 UPDATE public.email_capacity SET next_send_at=clock_timestamp()+make_interval(secs=>(1/v_rate)::double precision),
 probe_until=CASE WHEN provider_outage_streak>0 THEN now()+interval '90 seconds' ELSE NULL END,
 probe_attempt=CASE WHEN provider_outage_streak>0 THEN p_attempt ELSE NULL END WHERE singleton;
 UPDATE public.email_attempts SET state='sending',began_at=now() WHERE attempt_id=p_attempt;
 UPDATE public.email_messages SET workflow_state='sending',attempt_count=attempt_count+1 WHERE id=v_row.id;
 RETURN jsonb_build_object('disposition','send','message',to_jsonb(v_row));
END $$;

CREATE OR REPLACE FUNCTION public.finish_email_attempt(p_attempt uuid,p_token uuid,p_outcome text,p_provider_id text DEFAULT NULL,p_error text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_a public.email_attempts; v_m public.email_messages; v_delay integer;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 SELECT * INTO v_a FROM public.email_attempts WHERE attempt_id=p_attempt FOR UPDATE;
 SELECT * INTO v_m FROM public.email_messages WHERE message_id=v_a.message_id FOR UPDATE;
 IF v_a.lease_token IS DISTINCT FROM p_token OR v_m.lease_token IS DISTINCT FROM p_token THEN RAISE EXCEPTION 'stale_email_completion'; END IF;
 IF v_a.state='accepted' THEN RETURN; END IF;
 IF p_outcome NOT IN ('accepted','retry','dead','unknown','preparation_failed') THEN RAISE EXCEPTION 'invalid_email_outcome'; END IF;
 IF p_outcome='accepted' AND (p_provider_id IS NULL OR v_a.state NOT IN ('sending','unknown')) THEN RAISE EXCEPTION 'invalid_email_acceptance'; END IF;
 IF p_outcome IN ('retry','dead','unknown') AND v_a.state<>'sending' THEN RAISE EXCEPTION 'invalid_email_failure'; END IF;
 IF p_outcome='preparation_failed' AND v_a.state<>'preparing' THEN RAISE EXCEPTION 'invalid_email_preparation_failure'; END IF;
 IF p_outcome='accepted' THEN
  UPDATE public.email_capacity SET provider_outage_streak=0,probe_until=NULL,probe_attempt=NULL,circuit_until=NULL WHERE probe_attempt=p_attempt;
  UPDATE public.email_attempts SET state='accepted',provider_message_id=p_provider_id,finished_at=now() WHERE attempt_id=p_attempt;
  UPDATE public.email_messages SET workflow_state='accepted',provider_message_id=p_provider_id,accepted_at=coalesce(accepted_at,now()),last_error=NULL WHERE id=v_m.id;
 ELSE
  v_delay:=(ARRAY[15,60,300,1800,7200])[least(greatest(v_m.attempt_count,1),5)];
  UPDATE public.email_attempts SET state=CASE WHEN p_outcome='unknown' THEN 'unknown' ELSE 'not_accepted' END,error_code=p_error,finished_at=now() WHERE attempt_id=p_attempt;
  UPDATE public.email_messages SET workflow_state=CASE WHEN p_outcome='unknown' THEN 'unknown' WHEN p_outcome='dead' OR attempt_count+CASE WHEN p_outcome='preparation_failed' THEN 1 ELSE 0 END>=8 THEN 'dead' ELSE 'retry_wait' END,
   attempt_count=attempt_count+CASE WHEN p_outcome='preparation_failed' THEN 1 ELSE 0 END,
   target_time=now()+make_interval(secs=>v_delay*(0.8+random()*0.4)),last_error=left(p_error,100),lease_until=NULL WHERE id=v_m.id;
  IF p_outcome='unknown' THEN UPDATE public.email_capacity SET provider_outage_streak=least(provider_outage_streak+1,10),
   probe_until=NULL,probe_attempt=NULL,circuit_until=now()+make_interval(secs=>least(300,30*power(2,least(provider_outage_streak,4)))::double precision) WHERE singleton; END IF;
  IF p_error='throttled' THEN UPDATE public.email_capacity SET rate_factor=greatest(rate_factor/2,0.01),probe_until=NULL,probe_attempt=NULL,circuit_until=now()+interval '15 seconds' WHERE singleton; END IF;
 END IF;
 PERFORM public.reconcile_email_events();
END $$;

CREATE OR REPLACE FUNCTION public.reconcile_email_events() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_event record;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 WITH matched AS (UPDATE public.email_delivery_events e SET message_id=m.message_id FROM public.email_messages m
 WHERE e.message_id IS NULL AND lower(e.recipient)=lower(m.recipient)
 AND (m.provider_message_id=e.provider_message_id OR EXISTS(SELECT 1 FROM public.email_attempts a WHERE a.message_id=m.message_id AND a.attempt_id=e.attempt_id AND a.state IN ('sending','unknown','accepted'))) RETURNING e.message_id)
 UPDATE public.email_messages m SET feedback_pending=true WHERE m.message_id IN (SELECT message_id FROM matched);
 FOR v_event IN SELECT message_id,min(provider_time) FILTER(WHERE event_type='delivery') delivery,
 min(provider_time) FILTER(WHERE event_type='bounce') bounce,min(provider_time) FILTER(WHERE event_type='complaint') complaint,
 min(provider_time) FILTER(WHERE event_type='open') opened,min(provider_time) FILTER(WHERE event_type='click') clicked,
 min(provider_time) FILTER(WHERE event_type IN ('send','delivery','open','click','bounce','complaint','delay')) accepted,
 min(provider_message_id) provider_id,max(event_type) FILTER(WHERE event_type IN ('reject','rendering_failure','delay')) failure
 FROM public.email_delivery_events WHERE message_id IN (SELECT message_id FROM public.email_messages WHERE workflow_state IN ('sending','unknown') OR feedback_pending) GROUP BY message_id LOOP
  UPDATE public.email_messages SET delivered_at=least(delivered_at,v_event.delivery),bounced_at=least(bounced_at,v_event.bounce),complained_at=least(complained_at,v_event.complaint),
   opened_at=CASE WHEN tracking_policy<>'disabled' THEN least(opened_at,v_event.opened) ELSE NULL END,
   clicked_at=CASE WHEN tracking_policy='engagement' THEN least(clicked_at,v_event.clicked) ELSE NULL END,provider_failure=v_event.failure,
   accepted_at=coalesce(accepted_at,v_event.accepted),provider_message_id=coalesce(provider_message_id,v_event.provider_id),
   workflow_state=CASE WHEN v_event.accepted IS NOT NULL AND workflow_state IN ('sending','unknown') THEN 'accepted' ELSE workflow_state END,feedback_pending=false
  WHERE message_id=v_event.message_id;
  UPDATE public.email_attempts SET state='accepted',provider_message_id=v_event.provider_id,finished_at=coalesce(finished_at,now())
  WHERE message_id=v_event.message_id AND state IN ('sending','unknown') AND v_event.accepted IS NOT NULL;
 INSERT INTO public.email_suppressions(recipient,reason)
 SELECT lower(recipient),CASE WHEN bool_or(event_type='complaint') THEN 'complaint' ELSE 'hard_bounce' END
 FROM public.email_delivery_events WHERE message_id=v_event.message_id AND (event_type='complaint' OR (event_type='bounce' AND hard_bounce))
 GROUP BY lower(recipient)
 ON CONFLICT(recipient) DO UPDATE SET reason=CASE WHEN email_suppressions.reason='complaint' THEN 'complaint' ELSE excluded.reason END;
 END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.record_email_events(p_events jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 IF jsonb_typeof(p_events)<>'array' OR jsonb_array_length(p_events)>100 THEN RAISE EXCEPTION 'invalid_event_batch'; END IF;
 INSERT INTO public.email_delivery_events(event_key,provider_message_id,attempt_id,recipient,event_type,provider_time,hard_bounce,invalid_recipient)
 SELECT e->>'key',e->>'provider_id',(e->>'attempt_id')::uuid,e->>'recipient',e->>'type',(e->>'time')::timestamptz,coalesce((e->>'hard_bounce')::boolean,false),coalesce((e->>'invalid_recipient')::boolean,false)
 FROM jsonb_array_elements(p_events) e ON CONFLICT(event_key) DO NOTHING;
 PERFORM public.reconcile_email_events();
END $$;
REVOKE ALL ON FUNCTION public.record_email_events(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.record_email_events(jsonb) TO service_role;
CREATE OR REPLACE FUNCTION public.record_email_event(p_event jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM public.record_email_events(jsonb_build_array(p_event));
END $$;

CREATE OR REPLACE FUNCTION public.enqueue_prepared_email(p_kind text,p_context jsonb,p_recipient text,p_sealed jsonb,p_dedupe text,p_content_hash text,p_code text,p_expires timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_result jsonb; v_m public.email_messages;
BEGIN
 PERFORM public.require_service_role();
 -- Use stable digest as canonical data; nonce/ciphertext is not part of dedupe equality.
 v_result:=public.enqueue_email(p_kind,p_context,p_recipient,jsonb_build_object('content_hash',p_content_hash),p_dedupe,p_code,now(),p_expires);
 UPDATE public.email_messages SET prepared=coalesce(prepared,p_sealed),prepared_hash=coalesce(prepared_hash,encode(extensions.digest(p_sealed::text,'sha256'),'hex')),prepared_at=coalesce(prepared_at,now())
 WHERE message_id=(v_result->>'message_id')::uuid AND workflow_state IN ('pending','blocked','preparing','retry_wait');
 RETURN v_result;
END $$;

CREATE OR REPLACE FUNCTION public.get_internal_email_state(p_message uuid) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN (SELECT workflow_state FROM public.email_messages WHERE message_id=p_message);
END $$;

CREATE OR REPLACE FUNCTION public.refresh_email_quota(p_account text,p_region text,p_rate numeric,p_daily numeric,p_used numeric) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c public.email_capacity;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO c FROM public.email_capacity FOR UPDATE;
 IF c.account_id IS DISTINCT FROM p_account OR c.region IS DISTINCT FROM p_region OR p_rate IS NULL OR p_daily IS NULL OR p_used IS NULL OR p_rate<=0 OR p_daily<=0 OR p_used<0 THEN RAISE EXCEPTION 'email_quota_identity_mismatch'; END IF;
 UPDATE public.email_capacity SET max_rate=p_rate,daily_quota=p_daily,provider_sent_24h=p_used,quota_at=now(),wake_error=NULL,rate_factor=least(1,rate_factor+0.05) WHERE singleton;
END $$;

CREATE OR REPLACE FUNCTION public.invalidate_email_quota(p_reason text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN PERFORM public.require_service_role();UPDATE public.email_capacity SET quota_at=NULL,wake_error=left(p_reason,100) WHERE singleton;END $$;
REVOKE ALL ON FUNCTION public.invalidate_email_quota(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.invalidate_email_quota(text) TO service_role;

-- Explicit internal ACLs, including the invoker-only domain helpers.
DO $$ DECLARE p record; BEGIN
 FOR p IN SELECT oid::regprocedure signature FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
 ('wake_email_worker','enqueue_email','email_intent_valid','claim_email','prepare_email','begin_email_send','finish_email_attempt','reconcile_email_events','record_email_event',
  'enqueue_prepared_email','get_internal_email_state','refresh_email_quota','enqueue_order_email','enqueue_paid_order_tickets','cancel_order_email_intents','apply_email_post_actions') LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',p.signature);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',p.signature);
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.get_next_email_due() RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN PERFORM public.require_service_role();RETURN (SELECT min(target_time) FROM public.email_messages WHERE workflow_state IN ('pending','retry_wait'));END $$;
REVOKE ALL ON FUNCTION public.get_next_email_due() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_next_email_due() TO service_role;

CREATE OR REPLACE FUNCTION public.reserve_email_quota_refresh() RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 UPDATE public.email_capacity SET quota_refresh_until=now()+interval '30 seconds' WHERE (quota_at IS NULL OR quota_at<now()-interval '5 minutes') AND (quota_refresh_until IS NULL OR quota_refresh_until<now());
 RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.reserve_email_quota_refresh() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_email_quota_refresh() TO service_role;
CREATE OR REPLACE FUNCTION public.recover_email_delivery() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 PERFORM public.recover_email_leases();
 UPDATE public.email_messages SET workflow_state='expired',lease_token=NULL,lease_until=NULL
 WHERE expires_at<now() AND workflow_state IN ('pending','retry_wait','blocked','preparing');
 -- Erase sensitive body after terminal state/expiry; retain correlation and dedupe tombstones.
 UPDATE public.email_messages SET prepared=NULL,data=data-'ciphertext'
 WHERE message_kind IN ('registration','sign_in','reset_password','google_mailbox','gotrue','deletion_confirm','deletion_complete')
 AND (workflow_state IN ('accepted','dead','cancelled','suppressed','expired') OR expires_at<now()) AND prepared IS NOT NULL;
 UPDATE public.email_messages SET prepared=NULL,data=jsonb_build_object('command_id',data->'command_id')
 WHERE created_at<now()-interval '30 days' AND workflow_state IN ('accepted','dead','cancelled','suppressed','expired') AND prepared IS NOT NULL;
 DELETE FROM public.email_confirmation_receipts WHERE expires_at<now();
 DELETE FROM public.email_delivery_events WHERE received_at<now()-interval '90 days';
 PERFORM public.apply_email_post_actions();
 PERFORM public.reconcile_email_events();
 PERFORM public.wake_email_worker();
END $$;
REVOKE ALL ON FUNCTION public.recover_email_delivery() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.recover_email_delivery() TO service_role;

CREATE OR REPLACE FUNCTION public.reconcile_unknown_email(p_message uuid,p_decision text,p_evidence text,p_provider_id text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m public.email_messages;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.email_capacity FOR UPDATE;
 IF p_evidence IS NULL OR length(p_evidence)<10 OR p_decision NOT IN ('accepted','known_not_accepted','cancelled') THEN RAISE EXCEPTION 'reconciliation_evidence_required'; END IF;
 SELECT * INTO m FROM public.email_messages WHERE message_id=p_message FOR UPDATE;
 IF m.workflow_state<>'unknown' THEN RAISE EXCEPTION 'email_not_unknown'; END IF;
 IF p_decision='accepted' AND p_provider_id IS NULL THEN RAISE EXCEPTION 'provider_receipt_required'; END IF;
 UPDATE public.email_messages SET workflow_state=CASE p_decision WHEN 'accepted' THEN 'accepted' WHEN 'known_not_accepted' THEN 'pending' ELSE 'cancelled' END,
 accepted_at=CASE WHEN p_decision='accepted' THEN now() ELSE accepted_at END,provider_message_id=coalesce(p_provider_id,provider_message_id),
 target_time=now(),lease_token=NULL,lease_until=NULL,post_action=post_action||jsonb_build_object('reconciliation',jsonb_build_object('decision',p_decision,'evidence',left(p_evidence,256),'at',now()))
 WHERE message_id=p_message;
 PERFORM public.wake_email_worker();
END $$;
REVOKE ALL ON FUNCTION public.reconcile_unknown_email(uuid,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_unknown_email(uuid,text,text,text) TO service_role;

CREATE OR REPLACE FUNCTION public.finalize_ticket_order_internal_v1(p_target_order bigint,input_data JSONB,p_offer boolean DEFAULT false)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions
AS $$
DECLARE
    result JSONB;
    order_id BIGINT;
    assigned_order_symbol TEXT;
    assigned_order_sequence BIGINT;
    allocation_attempt INTEGER;
    ticket_data JSONB;
    spot_data RECORD;
    spot_id BIGINT;
    spot_product RECORD;
    now TIMESTAMPTZ := NOW();
    calculated_price NUMERIC(10,2) := 0;
    spot_secret UUID;
    product_id BIGINT;
    ordered_count BIGINT;
    used_spots JSONB := '[]'::JSONB;
    occasion_id BIGINT;
    organization_id BIGINT;
    unit_id BIGINT;
    occasion_title TEXT;
    occasion_features JSONB;
    account_number TEXT;
    account_number_human_readable TEXT;
    creditor_name TEXT;
    generated_creditor_reference TEXT;
    ticket_details JSONB := '[]'::JSONB;
    product_data RECORD;
    ticket_id BIGINT;
    order_product_ticket_id BIGINT;
    v_ticket_symbol TEXT;
    ticket_products JSONB := '[]'::JSONB;
    payment_info_id BIGINT;
    generated_variable_symbol BIGINT;
    bank_account_id BIGINT;
    form_key UUID;
    deadline TIMESTAMPTZ;
    form_deadline_duration BIGINT;
    form_data JSONB;
    currency_code TEXT;
    first_currency_code TEXT := NULL;
    field_item JSONB;
    products_array BIGINT[] := '{}';
    form_id BIGINT;
    field_type TEXT;
    key_val RECORD;
    order_data JSONB;
    order_note TEXT;
    ticket_note TEXT;
    reply_to TEXT;
    is_open_val BOOLEAN;
    is_editor BOOLEAN;
    v_product_deposit NUMERIC;
    v_total_deposit NUMERIC := 0;
BEGIN
    -- Wrap the entirelogic in a subtransaction block
    BEGIN
        -- Validate input_data and extract form key and email
        IF input_data IS NULL OR input_data->'form' IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1001, 'message', 'Missing form key in input data')::TEXT;
        END IF;

        IF input_data ?| ARRAY['order_symbol','orderSymbol','order_sequence','orderSequence']
            OR COALESCE(input_data->'data', '{}'::jsonb) ?| ARRAY['order_symbol','orderSymbol','order_sequence','orderSequence'] THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1001, 'message', 'Order symbol is server assigned')::TEXT;
        END IF;

        IF jsonb_typeof(input_data->'ticket') = 'array' AND
            jsonb_array_length(input_data->'ticket') > public.ticket_order_limit() THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1023,
                'message', 'Maximum number of tickets per order exceeded',
                'limit', public.ticket_order_limit())::TEXT;
        END IF;

        form_key := (input_data->>'form')::UUID;
        SELECT id, occasion, bank_account, deadline_duration_seconds, data, is_open
        INTO form_id, occasion_id, bank_account_id, form_deadline_duration, form_data, is_open_val
        FROM public.forms
        WHERE key = form_key FOR UPDATE;

        now:=clock_timestamp();
        IF occasion_id IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1003, 'message', 'Form is not linked to any occasion')::TEXT;
        END IF;


        -- The order payload captures the effective tone for its confirmation email.
        form_data := public.get_effective_form_data(form_id);

        is_editor := public.get_is_editor_order_on_occasion(occasion_id);

        IF NOT is_editor AND NOT p_offer THEN
            IF is_open_val IS FALSE THEN
                 RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1021, 'message', 'Form is closed')::TEXT;
            END IF;

            -- Check for start_time and end_time constraints only if not editor
            IF COALESCE(form_data->'schedule'->>'start_time', form_data->>'start_time') IS NOT NULL THEN
                IF now < (COALESCE(form_data->'schedule'->>'start_time', form_data->>'start_time'))::TIMESTAMPTZ THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1019, 'message', 'Form is not yet open')::TEXT;
                END IF;
            END IF;

            IF COALESCE(form_data->'schedule'->>'end_time', form_data->>'end_time') IS NOT NULL THEN
                IF now > (COALESCE(form_data->'schedule'->>'end_time', form_data->>'end_time'))::TIMESTAMPTZ THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1020, 'message', 'Form is closed')::TEXT;
                END IF;
            END IF;
        END IF;

        -- Fetch organization, unit, and occasion title from the occasion
        SELECT organization, unit, title, features
        INTO organization_id, unit_id, occasion_title, occasion_features
        FROM public.occasions
        WHERE id = occasion_id;

        form_deadline_duration := COALESCE(form_deadline_duration,
            (SELECT (elem->>'deadline_duration_seconds')::bigint
             FROM jsonb_array_elements(occasion_features) elem WHERE elem->>'code'='form'),604800);

        IF organization_id IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1005, 'message', 'No organization found for the occasion')::TEXT;
        END IF;

        IF input_data ? 'fields' THEN
            DECLARE
                valid_fields JSONB := '[]'::JSONB;
                elem JSONB;
                field_key TEXT;
            BEGIN
                FOR elem IN SELECT * FROM jsonb_array_elements(input_data->'fields')
                LOOP
                    field_key := (SELECT key FROM jsonb_object_keys(elem) AS key);

                    IF field_key IS NULL THEN
                        CONTINUE;
                    END IF;

                    -- Validate the field against the form_fields table
                    SELECT ff.type INTO field_type
                    FROM public.form_fields ff
                    WHERE ff.id = field_key::BIGINT AND ff.form = form_id AND ff.is_hidden = false;

                    IF FOUND THEN
                        valid_fields := valid_fields || elem;

                        IF field_type IN ('email', 'name', 'surname', 'phone', 'note') THEN
                            input_data := jsonb_set(input_data, ARRAY[field_type], elem->field_key, true);
                        END IF;
                    END IF;
                END LOOP;

                input_data := jsonb_set(input_data, '{fields}', valid_fields);
            END;
        END IF;

        IF input_data->>'email' IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1002, 'message', 'Missing email in input data')::TEXT;
        END IF;

        input_data:=jsonb_set(input_data,'{ticket}',public.normalize_form_ticket_answers_internal(form_id,input_data->'ticket'));

        SELECT id,order_symbol,order_sequence INTO order_id,assigned_order_symbol,assigned_order_sequence
        FROM eshop.orders WHERE id=p_target_order AND form=form_id FOR UPDATE;
        IF order_id IS NULL OR EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE "order"=order_id AND (NOT p_offer OR product IS NOT NULL)) THEN
          RAISE EXCEPTION 'Invalid finalization target'; END IF;
        IF NOT p_offer AND (SELECT participant_capacity IS NOT NULL FROM public.forms WHERE id=form_id)
           AND jsonb_array_length(input_data->'ticket') >
           (public.get_form_capacity_snapshot_internal(form_id)->>'remainingPublic')::bigint THEN
          RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','FORM_CAPACITY_EXCEEDED',
            'capacity',public.get_form_capacity_snapshot_internal(form_id))::text; END IF;
        PERFORM public.lock_ticket_order_products_internal(order_id,input_data);
        UPDATE eshop.orders SET state='ordered' WHERE id=order_id;

        PERFORM public.validate_waitlist_answers_internal(form_id,input_data,input_data->'ticket',false);
        -- Process each ticket
        FOR ticket_data IN SELECT * FROM JSONB_ARRAY_ELEMENTS(input_data->'ticket') LOOP

            spot_data := NULL;
            spot_product := NULL;
            spot_id := NULL;
            ticket_note := NULL;

            IF ticket_data->>'spot' IS NOT NULL THEN
                SELECT * INTO spot_data
                FROM eshop.spots
                WHERE id = (ticket_data->>'spot')::BIGINT
                  AND occasion = occasion_id;

                IF spot_data IS NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1007, 'message', 'Invalid or unrelated spot')::TEXT;
                END IF;

                IF spot_data.order_product_ticket IS NOT NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1008, 'message', 'Spot is already reserved or in use')::TEXT;
                END IF;

                spot_secret := (input_data->>'secret')::UUID;
                IF spot_data.secret IS DISTINCT FROM spot_secret THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1009, 'message', 'Invalid secret for spot')::TEXT;
                END IF;

                spot_id := spot_data.id;
                used_spots := used_spots || JSONB_BUILD_ARRAY(spot_id);

                SELECT i.*, it.type, it.title as type_title, spot_data.title as spot_title
                INTO spot_product
                FROM eshop.products i
                LEFT JOIN eshop.product_types it ON i.product_type = it.id
                WHERE i.id = spot_data.product;
            END IF;

            products_array := '{}';
            IF ticket_data ? 'fields' THEN
                FOR field_item IN SELECT * FROM JSONB_ARRAY_ELEMENTS(ticket_data->'fields')
                LOOP
                    IF field_item ? 'note' THEN
                        ticket_note := field_item->>'note';
                    END IF;
                    IF field_item ? 'product_type' THEN
                        products_array := products_array || ((field_item->>'product_type')::BIGINT);
                    END IF;
                END LOOP;
            END IF;

            v_ticket_symbol := generate_ticket_symbol(organization_id, occasion_id);
            IF p_offer THEN
              ticket_id:=(ticket_data->>'ticketId')::bigint;
              UPDATE eshop.tickets t SET state='ordered',ticket_symbol=v_ticket_symbol,
                note=ticket_note,data=public.extract_ticket_answers_internal(form_id,ticket_data),updated_at=now
              WHERE t.id=ticket_id AND t.state='waitlisted' AND t.ticket_symbol IS NULL
                AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=t.id AND x."order"=order_id AND x.product IS NULL)
                AND EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots x WHERE x.ticket_id=t.id AND x.outcome='accepted');
              IF NOT FOUND THEN RAISE EXCEPTION 'Invalid waiting ticket finalization'; END IF;
              DELETE FROM eshop.order_product_ticket WHERE "order"=order_id AND ticket=ticket_id AND product IS NULL;
            ELSE
              IF ticket_data ? 'ticketId' THEN RAISE EXCEPTION 'Ticket identity is server assigned'; END IF;
              INSERT INTO eshop.tickets (state,occasion,ticket_symbol,note,data,created_at,updated_at)
              VALUES('ordered',occasion_id,v_ticket_symbol,ticket_note,public.extract_ticket_answers_internal(form_id,ticket_data),now,now) RETURNING id INTO ticket_id;
            END IF;
            ticket_products := '[]'::JSONB;

            IF spot_id IS NOT NULL THEN
                products_array := products_array || spot_product.id;
            END IF;

            FOREACH product_id IN ARRAY products_array LOOP

                IF product_id IS NULL THEN
                    CONTINUE;
                END IF;

                SELECT i.*, it.type, it.title AS type_title, '' AS spot_title
                INTO product_data
                FROM eshop.products i
                LEFT JOIN eshop.product_types it ON i.product_type = it.id
                WHERE i.id = product_id
                  AND it.occasion = occasion_id;

                IF product_data.id IS NOT NULL AND spot_id IS NULL AND NOT EXISTS(SELECT 1 FROM public.form_fields ff
                  WHERE ff.form=form_id AND ff.product_type=product_data.product_type AND NOT ff.is_hidden) THEN
                  RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','PRODUCT_SCOPE_MISMATCH','productId',product_id)::text;
                END IF;
                IF product_data IS NULL THEN
                    RAISE EXCEPTION '%',
                        jsonb_build_object(
                            'code', 1011,
                            'message', 'Product not found or not part of occasion',
                            'details', product_id
                        )::text;
                END IF;

                IF COALESCE(product_data.maximum, 0) > 0 THEN
                    SELECT COUNT(*) INTO ordered_count
                    FROM eshop.order_product_ticket
                    WHERE product = product_id;
                    IF ordered_count + 1 > product_data.maximum THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                            'code', 1017,
                            'errorCode','PRODUCT_CAPACITY_EXCEEDED',
                            'message', 'Product is overbooked',
                            'product', jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                                'id', product_data.id,
                                'title', product_data.title,
                                'price', product_data.price,
                                'type', product_data.type,
                                'currency_code', product_data.currency_code
                            ))
                        )::TEXT;
                    END IF;
                END IF;

                IF product_data.type = 'spot' AND spot_product IS NULL THEN
                    spot_product := product_data;
                END IF;

                IF product_data.is_hidden THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1012,
                        'message', 'Selected product is hidden and cannot be ordered',
                        'id', product_id
                    )::TEXT;
                END IF;

                IF first_currency_code IS NULL THEN
                    first_currency_code := product_data.currency_code;
                ELSE
                    IF product_data.currency_code IS DISTINCT FROM first_currency_code THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                            'code', 1014,
                            'message', 'Products in the order must have the same currency',
                            'expected_currency', first_currency_code,
                            'actual_currency', product_data.currency_code
                        )::TEXT;
                    END IF;
                END IF;

                -- Build the product details for the ticket
                DECLARE
                    v_spot_title TEXT := NULL;
                    v_spot_description TEXT := NULL;
                BEGIN
                    -- Safe extraction of spot details
                    IF spot_id IS NOT NULL AND spot_product IS NOT NULL THEN
                         -- Only access fields if we have a spot_id (implies spot_product is fully set from spot lookup)
                         -- AND product_id matches.
                         IF product_id = spot_product.id THEN
                             v_spot_title := spot_product.spot_title;
                             v_spot_description := spot_product.description;
                         END IF;
                    END IF;

                    ticket_products := ticket_products || jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                        'id', product_id,
                        'title', product_data.title,
                        'type', product_data.type,
                        'type_title', product_data.type_title,
                        'price', product_data.price,
                        'currency_code', product_data.currency_code,
                        'spot_title', v_spot_title,
                        'description', v_spot_description,
                        'data', product_data.data
                    ));
                END;

                -- Accumulate the product price into the order total
                calculated_price := calculated_price + COALESCE(product_data.price, 0)::NUMERIC(10,2);

                -- Accumulate the product deposit into the order deposit total
                v_product_deposit := COALESCE((product_data.data->'deposit'->>'amount')::NUMERIC, 0);
                IF v_product_deposit > COALESCE(product_data.price, 0) THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1016,
                        'message', 'Deposit amount cannot exceed product price',
                        'product_id', product_id,
                        'deposit', v_product_deposit,
                        'price', product_data.price
                    )::TEXT;
                END IF;
                v_total_deposit := v_total_deposit + v_product_deposit;

                -- Link the ticket and product to the order
                INSERT INTO eshop.order_product_ticket ("order", product, ticket)
                VALUES (order_id, product_id, ticket_id)
                RETURNING id INTO order_product_ticket_id;

                -- For the spot product, link the generated order product ticket id to the spot record
                IF spot_id IS NOT NULL THEN
                    IF product_id = spot_product.id THEN
                        UPDATE eshop.spots
                        SET order_product_ticket = order_product_ticket_id, updated_at = now
                        WHERE id = spot_id;
                    END IF;
                END IF;
            END LOOP;

            -- If no explicit ticket->spot was provided, then at least one of the fields must be a spot product.
            IF spot_product IS NULL THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1015, 'message', 'Spot product is missing in ticket fields')::TEXT;
            END IF;

            -- Append the ticket details (with its products and the extracted ticket note) to the overall ticket_details array
            IF NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x."order"=order_id AND x.ticket=ticket_id) THEN
              INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(order_id,ticket_id,NULL);
            END IF;
            ticket_details := ticket_details || JSONB_BUILD_OBJECT(
                'id', ticket_id,
                'ticket_symbol', v_ticket_symbol,
                'note', ticket_note,
                'products', ticket_products
            );
        END LOOP;

        order_data := input_data - 'ticket' || JSONB_BUILD_OBJECT('tickets', ticket_details);

        -- Determine the bank account details based on the form and supported currency fallback using unit accounts only
        -- Modified Bank Account Selection: Exclude CASH Accounts
        IF bank_account_id IS NULL THEN
            SELECT uba.bank_account, ba.account_number, ba.account_number_human_readable, ba.creditor_name
            INTO bank_account_id, account_number, account_number_human_readable, creditor_name
            FROM eshop.unit_bank_accounts uba
            JOIN eshop.bank_accounts ba ON uba.bank_account = ba.id
            WHERE uba.unit = (SELECT unit FROM public.occasions WHERE id = occasion_id)
              AND ba.supported_currencies @> ARRAY[first_currency_code]
              AND (ba.type IS DISTINCT FROM 'CASH') -- EXCLUDE CASH ACCOUNTS
            ORDER BY uba.priority ASC, ba.id ASC
            LIMIT 1;

            IF bank_account_id IS NULL THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                    'code', 1018,
                    'message', 'No available bank account supports the required currency',
                    'required_currency', first_currency_code
                )::TEXT;
            END IF;
        ELSE
            -- Validate manually selected account: Exclude CASH Accounts
            PERFORM 1
            FROM eshop.unit_bank_accounts uba
            JOIN eshop.bank_accounts ba ON uba.bank_account = ba.id
            WHERE uba.unit = (SELECT unit FROM public.occasions WHERE id = occasion_id)
              AND ba.id = bank_account_id
              AND ba.supported_currencies @> ARRAY[first_currency_code]
              AND (ba.type IS DISTINCT FROM 'CASH'); -- EXCLUDE CASH ACCOUNTS

            IF NOT FOUND THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                    'code', 1018,
                    'message', 'The specified bank account does not support the required currency, is not linked, or is invalid (CASH type)',
                    'expected_currency', first_currency_code,
                    'provided_bank_account', bank_account_id
                )::TEXT;
            END IF;

            SELECT b.account_number, b.account_number_human_readable, b.creditor_name
            INTO account_number, account_number_human_readable, creditor_name
            FROM eshop.bank_accounts b
            WHERE b.id = bank_account_id;
        END IF;

        -- A configured account holder takes precedence. Otherwise use the
        -- occasion's organization name for EPC payment instructions.
        IF upper(trim(first_currency_code)) = 'EUR' AND NULLIF(trim(creditor_name), '') IS NULL THEN
          SELECT left(trim(regexp_replace(title, '[[:space:][:cntrl:]]+', ' ', 'g')), 70)
          INTO creditor_name
          FROM public.organizations
          WHERE id = organization_id;
        END IF;

        -- If user chose to pay full amount, skip deposit
        IF input_data->>'payment_type' = 'full' THEN
            v_total_deposit := 0;
        END IF;

        -- Generate a variable symbol and create the payment info record
        generated_variable_symbol := generate_payment_variable_symbol(bank_account_id, form_id);
        INSERT INTO eshop.payment_info (bank_account, variable_symbol, amount, deposit_amount, currency_code, created_at)
        VALUES (bank_account_id, generated_variable_symbol, calculated_price, NULLIF(v_total_deposit, 0), first_currency_code, now)
        RETURNING id INTO payment_info_id;

        IF upper(trim(first_currency_code)) = 'EUR' AND calculated_price > 0 THEN
          IF creditor_name IS NULL OR length(trim(creditor_name)) NOT BETWEEN 1 AND 70 THEN
            RAISE EXCEPTION 'EUR_CREDITOR_NAME_REQUIRED';
          END IF;
          IF account_number IS NULL OR NOT public.is_valid_iban(account_number) THEN
            RAISE EXCEPTION 'EUR_VALID_IBAN_REQUIRED';
          END IF;
          generated_creditor_reference := public.generate_creditor_reference(generated_variable_symbol);
          UPDATE eshop.payment_info
          SET creditor_reference = generated_creditor_reference
          WHERE id = payment_info_id AND creditor_reference IS NULL;
        END IF;

        -- persist all of the non‐state fields
        UPDATE eshop.orders
        SET
          price         = calculated_price,
          currency_code = first_currency_code,
          payment_info  = payment_info_id,
          data          = order_data,
          updated_at    = now
        WHERE id = order_id;

        -- Apply inventory allocations. This will raise an overbooking error if spots are unavailable.
        PERFORM apply_allocations(order_id);

        -- Always mark as 'ordered' initially to satisfy state requirements
        IF calculated_price = 0 THEN
          PERFORM update_order_and_tickets_to_paid(order_id);
        ELSE
          UPDATE eshop.orders
          SET state      = 'ordered'
          WHERE id = order_id;

          -- Calculate deadline if deadline duration is provided
          IF form_deadline_duration IS NOT NULL THEN
              deadline := now + make_interval(secs => form_deadline_duration);
              PERFORM public.set_payment_deadline(payment_info_id, deadline);
          ELSE
              deadline := NULL;
          END IF;
        END IF;

        -- Check via Unified Helper if order is already paid (e.g. price is 0)
        PERFORM public.recalculate_order_payment_status(order_id);

        -- Queue deposit reminder if deposit exists and deadline is days-based (not "on site")
        IF v_total_deposit > 0 THEN
            DECLARE
                v_occ_start_time TIMESTAMPTZ;
                v_deposit_deadline_days INT;
                v_deposit_deadline TEXT;
                v_reminder_interval BIGINT;
                v_reminder_is_enabled BOOLEAN;
                v_deposit_deadline_ts TIMESTAMPTZ;
                v_deposit_feature JSONB;
            BEGIN
                -- Read occasion start_time
                SELECT start_time INTO v_occ_start_time
                FROM public.occasions WHERE id = occasion_id;

                -- Get deposit feature config from features JSONB
                SELECT elem INTO v_deposit_feature
                FROM jsonb_array_elements(occasion_features) elem
                WHERE elem->>'code' = 'deposit';

                v_deposit_deadline_days := (v_deposit_feature->>'deposit_deadline_days')::int;
                v_deposit_deadline := v_deposit_feature->>'deposit_deadline';

                -- Store deposit deadline on payment_info and queue reminder
                IF v_deposit_deadline IS DISTINCT FROM 'on_site' AND v_deposit_deadline_days IS NOT NULL THEN
                    v_deposit_deadline_ts := v_occ_start_time - make_interval(days => v_deposit_deadline_days);

                    -- Store the calculated deposit deadline on the payment_info record
                    UPDATE eshop.payment_info
                    SET deposit_deadline = v_deposit_deadline_ts
                    WHERE id = payment_info_id;

                    -- Only queue reminder if deadline is in the future
                    IF v_deposit_deadline_ts > NOW() THEN
                        -- Get reminder interval from occasion form feature
                        SELECT COALESCE((form_data->>'reminder_interval_seconds')::bigint, (elem->>'reminder_interval_seconds')::bigint,86400)
                        INTO v_reminder_interval
                        FROM jsonb_array_elements(occasion_features) elem
                        WHERE elem->>'code' = 'form';

                        -- Check if reminder is enabled on the form feature
                        SELECT (elem->>'is_enabled')::boolean AND COALESCE((form_data->>'is_reminder_enabled')::boolean,(elem->>'reminder_is_enabled')::boolean,true)
                        INTO v_reminder_is_enabled
                        FROM jsonb_array_elements(occasion_features) elem
                        WHERE elem->>'code' = 'form';

                        IF COALESCE(v_reminder_is_enabled, FALSE) AND v_reminder_interval IS NOT NULL THEN
                            PERFORM public.enqueue_order_email('TICKET_ORDER_REMINDER',
                                jsonb_build_object('order_id',order_id,'is_deposit_reminder',true),organization_id,occasion_id,unit_id,
                                v_deposit_deadline_ts-make_interval(secs=>v_reminder_interval));
                        END IF;
                    END IF;
                END IF;
                -- Note: if deposit_deadline = 'on_site', deposit_deadline stays NULL → means "Na místě"
            END;
        END IF;

        -- Log the order to orders_history with details
        INSERT INTO eshop.orders_history (created_at, data, "order", state, price, currency_code)
        VALUES (
            now,
            JSONB_BUILD_OBJECT('input_data', input_data, 'tickets', ticket_details),
            order_id,
            'ordered',
            calculated_price,
            first_currency_code
        );

        UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id=form_id;
        -- Get the reply-to email for the order
        reply_to := get_reply_to_email_for_order(order_id);

        -- Check features and auto-import users if enabled
        PERFORM public.process_occasion_auto_import(occasion_id);

        -- Prepare the success response JSON
        result := JSONB_BUILD_OBJECT(
            'code', 200,
            'order', JSONB_BUILD_OBJECT(
                'id', order_id,
                'order_symbol', assigned_order_symbol,
                'data', order_data,
                'form', JSONB_BUILD_OBJECT(
                    'id', form_id,
                    'data', form_data
                ),
                'payment_info', JSONB_BUILD_OBJECT(
                    'id', payment_info_id,
                    'variable_symbol', generated_variable_symbol,
                    'creditor_reference', generated_creditor_reference,
                    'creditor_name', creditor_name,
                    'amount', calculated_price,
                    'deposit_amount', NULLIF(v_total_deposit, 0),
                    'deposit_deadline', (SELECT deposit_deadline FROM eshop.payment_info WHERE id = payment_info_id),
                    'deadline', deadline,
                    'account_number', account_number,
                    'account_number_human_readable', account_number_human_readable,
                    'currency_code', first_currency_code
                ),
                'occasion', JSONB_BUILD_OBJECT(
                    'id', occasion_id,
                    'organization', organization_id,
                    'unit', unit_id,
                    'title', occasion_title,
                    'features', occasion_features,
                    'data', (SELECT data FROM public.occasions WHERE id = occasion_id)
                ),
                'reply_to', reply_to
            )
        );

    EXCEPTION WHEN OTHERS THEN
        -- In case of any error, the inner block is rolled back and we capture the error message.
        result := CASE
            WHEN left(SQLERRM, 1) = '{' THEN SQLERRM::JSONB
            ELSE JSONB_BUILD_OBJECT('code', 1013, 'message', SQLERRM)
        END;
    END;

    RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.finalize_ticket_order_internal_v1(bigint,jsonb,boolean) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.update_form_internal_v1(input_data JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    ----------------------------------------------------------------------------
    -- Declarations
    ----------------------------------------------------------------------------
    result JSONB;
    deleted_fields BIGINT[];
    deleted_products BIGINT[];
    deletion_reason TEXT;
    deletion_row RECORD;

    form_id          BIGINT;               -- ID of the form being created/updated
    occasion_id      BIGINT;               -- ID of the occasion to which the form belongs
    now_ts           TIMESTAMPTZ := NOW(); -- Current timestamp for record updates

    link_param           TEXT;         -- Unique link for the form, must not conflict within the same org
    occasion_org         BIGINT;       -- Organization stored in the occasions table
    occasion_unit        BIGINT;       -- The 'unit' that must match for bank accounts
    conflict_check       INT;          -- Used for verifying uniqueness constraints
    deadline_val         BIGINT;       -- Field for validating form deadlines
    price_val            NUMERIC;      -- Field for validating product price

    bank_account_val     BIGINT;       -- Bank account from input_data
    bank_account_unit    BIGINT;       -- Unit of the bank account, must match occasion_unit

    v_seconds_before_deadline BIGINT; -- For calling the reminder queue function

    ----------------------------------------------------------------------------
    -- Since product_type data is now inside form_fields, we no longer read from
    -- a top-level product_types array. Instead, we will parse product_type objects
    -- directly from each form_field (if present).
    ----------------------------------------------------------------------------

    product_type_data    JSONB;        -- The JSONB data for product_type within a form_field
    product_type_id      BIGINT;       -- ID (new or existing) of the product_type
    product_type_occ     BIGINT;       -- For checking product_type's occasion

    products_data        JSONB;        -- JSONB array of products inside a product_type
    product_array_data   JSONB;        -- Rebuilt array of products
    product_data         JSONB;        -- Each product object from the products array
    product_id           BIGINT;       -- ID for a product (new or existing)
    product_occ          BIGINT;       -- Occasion check for an existing product

    ----------------------------------------------------------------------------
    -- form_fields data
    ----------------------------------------------------------------------------
    form_fields_data     JSONB := '[]'::JSONB; -- Final array of form_fields for the response
    field_data           JSONB;                -- Each form_field from input
    field_id             BIGINT;               -- ID for a form_field (new or existing)
    field_product_type   BIGINT;               -- Will store the final product_type.id for the form_field
    field_occ            BIGINT;               -- Verify product_type's occasion if referenced
BEGIN
    BEGIN
        /* All logic is inside this sub-block so we can catch exceptions similarly
           to how it's done in create_ticket_order, with a single EXCEPTION WHEN OTHERS THEN.
           We raise exceptions in JSON form, and if it's JSON, we return it as-is; otherwise,
           we build a default JSON error response. */

        ----------------------------------------------------------------------------
        -- Begin main logic
        ----------------------------------------------------------------------------

        -- Validate that input_data and essential fields exist
        IF input_data IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4001, 'message', 'Input data is missing')::TEXT;
        END IF;

        IF input_data->>'occasion' IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4002, 'message', 'Missing occasion ID in input data')::TEXT;
        END IF;

        occasion_id := (input_data->>'occasion')::BIGINT;
        IF occasion_id IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4002, 'message', 'Invalid or missing occasion ID')::TEXT;
        END IF;

        -- Ensure user is authorized to edit this occasion
        IF NOT COALESCE(get_is_editor_order_on_occasion(occasion_id), false) THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 403, 'message', 'User is not authorized to edit this occasion')::TEXT;
        END IF;

        -- Retrieve the occasion's organization and unit
        SELECT o.organization, o.unit
          INTO occasion_org, occasion_unit
          FROM public.occasions o
         WHERE o.id = occasion_id
         LIMIT 1;

        IF occasion_org IS NULL OR occasion_unit IS NULL THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4017, 'message', 'Occasion not found or missing required fields')::TEXT;
        END IF;

        IF NOT public.is_service_role() AND NOT (public.get_is_editor_on_unit(occasion_unit) OR public.get_is_editor_on_occasion(occasion_id)) THEN RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
        -- Validate the link field, which must be unique within the same organization
        link_param := input_data->>'link';
        IF link_param IS NULL OR link_param = '' THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT('code', 4013, 'message', 'Missing link in input data')::TEXT;
        END IF;

        -- Determine if we are creating a new form or updating an existing one
        form_id := NULLIF(input_data->>'id', '')::BIGINT;

        IF form_id IS NULL THEN
            -- New form: ensure link uniqueness via a join to occasions
            SELECT 1
              INTO conflict_check
              FROM public.forms f
              JOIN public.occasions o ON f.occasion = o.id
             WHERE o.organization = occasion_org
               AND f.link = link_param
             LIMIT 1;

            IF conflict_check IS NOT NULL THEN
                RAISE EXCEPTION '%',
                    JSONB_BUILD_OBJECT(
                        'code', 4014,
                        'message', 'Link is already used by another form in the same organization'
                    )::TEXT;
            END IF;

            INSERT INTO public.forms (
                created_at,
                occasion,
                link
            )
            VALUES (
                now_ts,
                occasion_id,
                link_param
            )
            RETURNING id INTO form_id;
        ELSE
            -- Existing form: ensure form belongs to the occasion and link is still unique
            IF NOT EXISTS (
                SELECT 1
                FROM public.forms
                WHERE id = form_id
                  AND occasion = occasion_id
            ) THEN
                RAISE EXCEPTION '%',
                    JSONB_BUILD_OBJECT(
                        'code', 4005,
                        'message', 'Form does not exist or does not match the given occasion',
                        'form_id', form_id
                    )::TEXT;
            END IF;

            PERFORM 1 FROM public.forms f WHERE f.id = form_id FOR UPDATE;

            SELECT 1
              INTO conflict_check
              FROM public.forms f
              JOIN public.occasions o ON f.occasion = o.id
             WHERE o.organization = occasion_org
               AND f.link = link_param
               AND f.id <> form_id
             LIMIT 1;

            IF conflict_check IS NOT NULL THEN
                RAISE EXCEPTION '%',
                    JSONB_BUILD_OBJECT(
                        'code', 4014,
                        'message', 'Link is already used by another form in the same organization'
                    )::TEXT;
            END IF;
        END IF;

        -- Explicit removals are part of this save transaction, never inferred from
        -- omitted fields in partial/older-client payloads. Exceptions roll back the save.
        SELECT COALESCE(array_agg(value::bigint), '{}'::bigint[]) INTO deleted_fields
        FROM jsonb_array_elements_text(COALESCE(input_data->'deleted_field_ids', '[]'::jsonb));
        SELECT COALESCE(array_agg(value::bigint), '{}'::bigint[]) INTO deleted_products
        FROM jsonb_array_elements_text(COALESCE(input_data->'deleted_product_ids', '[]'::jsonb));

        IF EXISTS (SELECT 1 FROM unnest(deleted_fields) AS removed(id) WHERE NOT EXISTS (
            SELECT 1 FROM public.form_fields ff WHERE ff.id = removed.id AND ff.form = form_id))
          OR EXISTS (SELECT 1 FROM unnest(deleted_products) AS removed(id) WHERE NOT EXISTS (
            SELECT 1 FROM eshop.products p JOIN public.form_fields ff ON ff.product_type = p.product_type
            WHERE p.id = removed.id AND ff.form = form_id)) THEN
            RAISE EXCEPTION 'FORM_DELETE_changed';
        END IF;

        -- Removing the ticket container also removes its nested fields.
        IF EXISTS (SELECT 1 FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields) AND ff.type = 'ticket') THEN
            SELECT deleted_fields || COALESCE(array_agg(ff.id), '{}'::bigint[]) INTO deleted_fields
            FROM public.form_fields ff WHERE ff.form = form_id AND ff.is_ticket_field;
        END IF;

        -- Serialize product-type references and product FK insertions before checking
        -- usage, including ON DELETE CASCADE inventory links.
        PERFORM 1 FROM eshop.product_types pt WHERE pt.id IN (
            SELECT ff.product_type FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields)
            UNION SELECT p.product_type FROM eshop.products p WHERE p.id = ANY(deleted_products)
        ) ORDER BY pt.id FOR UPDATE;
        SELECT deleted_products || COALESCE(array_agg(p.id), '{}'::bigint[]) INTO deleted_products
        FROM eshop.products p JOIN public.form_fields ff ON ff.product_type = p.product_type
        WHERE ff.id = ANY(deleted_fields);
        PERFORM 1 FROM eshop.products p WHERE p.id = ANY(deleted_products) ORDER BY p.id FOR UPDATE;

        FOR deletion_row IN SELECT ff.* FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields)
        LOOP
            SELECT CASE WHEN EXISTS (
          SELECT 1 FROM (
            SELECT current_order.id, current_order.form, current_order.data FROM eshop.orders current_order WHERE current_order.form = ff.form
          ) o
          WHERE o.form = ff.form AND (
            EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(o.data->'fields') = 'array' THEN o.data->'fields' ELSE '[]'::jsonb END) answer
              WHERE answer ? ff.id::text AND answer->(ff.id::text) NOT IN ('null'::jsonb, '""'::jsonb, '[]'::jsonb, '{}'::jsonb))
            OR (ff.type = 'ticket' AND jsonb_path_exists(o.data, '$.tickets[*]'))
            OR (ff.type = 'note' AND ff.is_ticket_field AND jsonb_path_exists(o.data, '$.tickets[*] ? (@.note != null && @.note != "")'))
            OR (ff.type = 'ticket' AND EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt."order" = o.id AND opt.ticket IS NOT NULL))
            OR (ff.type = 'note' AND ff.is_ticket_field AND EXISTS (
              SELECT 1 FROM eshop.order_product_ticket opt JOIN eshop.tickets t ON t.id = opt.ticket
              WHERE opt."order" = o.id AND NULLIF(t.note, '') IS NOT NULL))
          )) OR EXISTS(SELECT 1 FROM eshop.tickets person CROSS JOIN LATERAL jsonb_array_elements(
            CASE WHEN jsonb_typeof(person.data->'fields')='array' THEN person.data->'fields' ELSE '[]' END) answer
            WHERE EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders q ON q.id=x."order" WHERE x.ticket=person.id AND q.form=ff.form) AND answer ? ff.id::text AND answer->(ff.id::text) NOT IN ('null'::jsonb,'""'::jsonb,'[]'::jsonb,'{}'::jsonb))
           OR (ff.type='ticket' AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders q ON q.id=x."order" WHERE x.ticket IS NOT NULL AND q.form=ff.form)) THEN 'responses'
        ELSE (
          SELECT reason FROM public.form_fields member
          JOIN eshop.products p ON p.product_type = member.product_type
          CROSS JOIN LATERAL (SELECT CASE
          WHEN EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt.product = p.id)
            OR EXISTS (SELECT 1 FROM eshop.orders o WHERE o.occasion = p.occasion
              AND jsonb_path_exists(o.data, '$.tickets[*].products[*] ? (@.id == $id)', jsonb_build_object('id', p.id))) THEN 'orders'
          WHEN EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product = p.id) THEN 'blueprint'
          WHEN EXISTS (SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product = p.id) THEN 'inventory'
          WHEN (SELECT count(*) FROM public.form_fields ref WHERE ref.product_type = p.product_type) > 1 THEN 'shared'
        END AS reason) usage
          WHERE (member.id = ff.id OR (ff.type = 'ticket' AND member.form = ff.form AND member.is_ticket_field))
            AND reason IS NOT NULL
          ORDER BY p.id LIMIT 1
        ) END INTO deletion_reason
            FROM public.form_fields ff WHERE ff.id = deletion_row.id;
            IF deletion_reason IS NOT NULL THEN
                RAISE EXCEPTION 'FORM_DELETE_%', deletion_reason;
            END IF;
        END LOOP;
        FOR deletion_row IN SELECT p.* FROM eshop.products p WHERE p.id = ANY(deleted_products)
        LOOP
            SELECT CASE
          WHEN EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt.product = p.id)
            OR EXISTS (SELECT 1 FROM eshop.orders o WHERE o.occasion = p.occasion
              AND jsonb_path_exists(o.data, '$.tickets[*].products[*] ? (@.id == $id)', jsonb_build_object('id', p.id))) THEN 'orders'
          WHEN EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product = p.id) THEN 'blueprint'
          WHEN EXISTS (SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product = p.id) THEN 'inventory'
          WHEN (SELECT count(*) FROM public.form_fields ref WHERE ref.product_type = p.product_type) > 1 THEN 'shared'
        END INTO deletion_reason
            FROM eshop.products p WHERE p.id = deletion_row.id;
            IF deletion_reason IS NOT NULL THEN
                RAISE EXCEPTION 'FORM_DELETE_%', deletion_reason;
            END IF;
        END LOOP;
        IF EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(input_data->'form_fields', '[]'::jsonb)) f
            WHERE (f->>'id')::bigint = ANY(deleted_fields))
          OR EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(input_data->'form_fields', '[]'::jsonb)) f,
            jsonb_array_elements(COALESCE(NULLIF(f->'product_type'->'products', 'null'::jsonb), '[]'::jsonb)) p
            WHERE (p->>'id')::bigint = ANY(deleted_products)) THEN
            RAISE EXCEPTION 'FORM_DELETE_changed';
        END IF;
        DELETE FROM public.form_fields ff WHERE ff.id = ANY(deleted_fields);
        DELETE FROM eshop.planned_changes WHERE subject_id=ANY(deleted_products) AND change_type IN('products.price','products.is_hidden') AND NOT applied;
        DELETE FROM eshop.products p WHERE p.id = ANY(deleted_products);

        ----------------------------------------------------------------------------
        -- Process form_fields array from input_data if present
        -- Each form_field may contain a product_type object. If so, we insert/update
        -- the product_type and its products, then set the resulting product_type.id
        -- in the form_field.
        ----------------------------------------------------------------------------
        IF (input_data->'form_fields') IS NOT NULL THEN
            form_fields_data := '[]'::JSONB;

            FOR field_data IN SELECT * FROM JSONB_ARRAY_ELEMENTS(input_data->'form_fields')
            LOOP
                field_id := NULLIF(field_data->>'id', '')::BIGINT;

                ----------------------------------------------------------------------------
                -- product_type logic now lives here, inside each form_field
                ----------------------------------------------------------------------------
                product_type_data := field_data->'product_type';  -- This is JSONB (could be null)
                IF field_data->>'type' = 'ticket' AND field_data#>>'{data,max_tickets}' IS NOT NULL THEN
                    IF (field_data#>>'{data,max_tickets}')::numeric < 1 OR
                       (field_data#>>'{data,max_tickets}')::numeric > public.ticket_order_limit() OR
                       trunc((field_data#>>'{data,max_tickets}')::numeric) <> (field_data#>>'{data,max_tickets}')::numeric THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 400,
                            'message', 'Invalid maximum tickets per order',
                            'limit', public.ticket_order_limit())::TEXT;
                    END IF;
                END IF;
                field_product_type := NULL;                        -- We'll store numeric ID here if we have a product_type

                IF product_type_data IS NOT NULL AND product_type_data::TEXT <> 'null' THEN
                    -- Attempt to parse the product_type.id if it exists
                    product_type_id := NULLIF(product_type_data->>'id', '')::BIGINT;

                    IF product_type_id IS NULL THEN
                        ----------------------------------------------------------------------------
                        -- New product_type
                        ----------------------------------------------------------------------------
                        INSERT INTO eshop.product_types (
                            created_at,
                            updated_at,
                            occasion,
                            title,
                            description,
                            type,
                            data
                        )
                        VALUES (
                            now_ts,
                            now_ts,
                            occasion_id,
                            product_type_data->>'title',
                            product_type_data->>'description',
                            product_type_data->>'type',
                            product_type_data->'data'
                        )
                        RETURNING id INTO product_type_id;

                        product_type_data := jsonb_set(
                            product_type_data,
                            '{id}',
                            TO_JSONB(product_type_id)
                        );
                    ELSE
                        ----------------------------------------------------------------------------
                        -- Existing product_type: check existence and occasion
                        ----------------------------------------------------------------------------
                        SELECT pt.occasion
                          INTO product_type_occ
                          FROM eshop.product_types pt
                         WHERE pt.id = product_type_id
                         LIMIT 1;

                        IF NOT FOUND THEN
                            RAISE EXCEPTION '%',
                                JSONB_BUILD_OBJECT(
                                    'code', 4006,
                                    'message', 'Product type not found',
                                    'details', product_type_data
                                )::TEXT;
                        END IF;

                        IF product_type_occ <> occasion_id THEN
                            RAISE EXCEPTION '%',
                                JSONB_BUILD_OBJECT(
                                    'code', 4007,
                                    'message', 'product_type occasion does not match form occasion',
                                    'product_type_occasion', product_type_occ,
                                    'form_occasion', occasion_id,
                                    'details', product_type_data
                                )::TEXT;
                        END IF;

                        PERFORM 1 FROM public.occasions WHERE id=occasion_id FOR UPDATE;
                        UPDATE eshop.product_types
                           SET
                               updated_at = now_ts,
                               title = product_type_data->>'title',
                               description = product_type_data->>'description',
                               type = product_type_data->>'type',
                               data = product_type_data->'data'
                         WHERE id = product_type_id;
                    END IF;

                    ----------------------------------------------------------------------------
                    -- Process products within this product_type, if any
                    ----------------------------------------------------------------------------
                    products_data := product_type_data->'products';
                    IF products_data IS NOT NULL AND products_data::TEXT <> 'null' THEN
                        product_array_data := '[]'::JSONB;

                        FOR product_data IN SELECT * FROM JSONB_ARRAY_ELEMENTS(products_data)
                        LOOP
                            product_id := NULLIF(product_data->>'id', '')::BIGINT;

                            -- Validate product price must be > 0
                            price_val := COALESCE(NULLIF(product_data->>'price',''), '0')::NUMERIC;
                            IF price_val < 0 THEN
                                RAISE EXCEPTION '%',
                                    JSONB_BUILD_OBJECT(
                                        'code', 4015,
                                        'message', 'Product price must be greater or equal to zero',
                                        'details', product_data
                                    )::TEXT;
                            END IF;

                            IF product_id IS NULL THEN
                                ----------------------------------------------------------------------------
                                -- New product
                                ----------------------------------------------------------------------------
                                PERFORM public.validate_product_price(price_val,product_data->'data',left(product_data->>'currency_code',3));
                                INSERT INTO eshop.products (
                                    created_at,
                                    updated_at,
                                    product_type,
                                    occasion,
                                    title,
                                    description,
                                    price,
                                    currency_code,
                                    data,
                                    is_hidden,
                                    "order",
                                    maximum
                                )
                                VALUES (
                                    now_ts,
                                    now_ts,
                                    product_type_id,
                                    occasion_id,
                                    product_data->>'title',
                                    product_data->>'description',
                                    price_val,
                                    left(product_data->>'currency_code', 3),
                                    product_data->'data',
                                    COALESCE((product_data->>'is_hidden')::BOOLEAN, false),
                                    NULLIF(product_data->>'order','')::BIGINT,
                                    NULLIF(product_data->>'maximum','')::BIGINT
                                )
                                RETURNING id INTO product_id;

                                product_data := jsonb_set(product_data, '{id}', TO_JSONB(product_id));
                            ELSE
                                ----------------------------------------------------------------------------
                                -- Existing product: must match the same occasion and product_type
                                ----------------------------------------------------------------------------
                                SELECT p.occasion
                                  INTO product_occ
                                  FROM eshop.products p
                                 WHERE p.id = product_id
                                   AND p.product_type = product_type_id
                                 LIMIT 1;

                                IF NOT FOUND THEN
                                    RAISE EXCEPTION '%',
                                        JSONB_BUILD_OBJECT(
                                            'code', 4008,
                                            'message', 'Product not found or does not match product_type',
                                            'details', product_data
                                        )::TEXT;
                                END IF;

                                IF product_occ <> occasion_id THEN
                                    RAISE EXCEPTION '%',
                                        JSONB_BUILD_OBJECT(
                                            'code', 4009,
                                            'message', 'Product occasion does not match form occasion',
                                            'product_occasion', product_occ,
                                            'form_occasion', occasion_id,
                                            'details', product_data
                                        )::TEXT;
                                END IF;

                                PERFORM public.validate_product_price_update(product_id,price_val,product_data->'data',left(product_data->>'currency_code',3));
                                UPDATE eshop.products
                                   SET
                                       updated_at = now_ts,
                                       title = product_data->>'title',
                                       description = product_data->>'description',
                                       price = price_val,
                                       currency_code = left(product_data->>'currency_code', 3),
                                       data = product_data->'data',
                                       is_hidden = COALESCE((product_data->>'is_hidden')::BOOLEAN, false),
                                       "order" = NULLIF(product_data->>'order','')::BIGINT,
                                       maximum = NULLIF(product_data->>'maximum','')::BIGINT
                                 WHERE id = product_id
                                   AND product_type = product_type_id;
                            END IF;

                            product_array_data := product_array_data || product_data;
                        END LOOP;

                        product_type_data := jsonb_set(
                            product_type_data,
                            '{products}',
                            product_array_data
                        );
                    END IF;

                    ----------------------------------------------------------------------------
                    -- Store product_type_id in field_product_type for the form_fields table
                    ----------------------------------------------------------------------------
                    field_product_type := product_type_id;

                    ----------------------------------------------------------------------------
                    -- Merge updated product_type_data back into the field_data
                    ----------------------------------------------------------------------------
                    field_data := jsonb_set(field_data, '{product_type}', product_type_data);
                END IF;

                ----------------------------------------------------------------------------
                -- Insert or update the form_field itself
                ----------------------------------------------------------------------------
                IF field_id IS NOT NULL THEN
                    -- Update existing form_field
                    UPDATE public.form_fields
                       SET
                           title = field_data->>'title',
                           description = field_data->>'description',
                           data = field_data->'data',
                           type = field_data->>'type',
                           is_required = COALESCE((field_data->>'is_required')::BOOLEAN, false),
                           is_hidden = COALESCE((field_data->>'is_hidden')::BOOLEAN, false),
                           "order" = NULLIF(field_data->>'order','')::BIGINT,
                           product_type = field_product_type,
                           is_ticket_field = COALESCE((field_data->>'is_ticket_field')::BOOLEAN, false),
                           form = form_id
                     WHERE id = field_id
                       AND form = form_id;

                    IF NOT FOUND THEN
                        RAISE EXCEPTION '%',
                            JSONB_BUILD_OBJECT(
                                'code', 4012,
                                'message', 'No matching form_field found to update (or does not belong to this form)',
                                'details', field_data
                            )::TEXT;
                    END IF;
                ELSE
                    -- Insert new form_field
                    INSERT INTO public.form_fields (
                        created_at,
                        title,
                        description,
                        data,
                        type,
                        is_required,
                        form,
                        is_hidden,
                        "order",
                        product_type,
                        is_ticket_field
                    )
                    VALUES (
                        now_ts,
                        field_data->>'title',
                        field_data->>'description',
                        field_data->'data',
                        field_data->>'type',
                        COALESCE((field_data->>'is_required')::BOOLEAN, false),
                        form_id,
                        COALESCE((field_data->>'is_hidden')::BOOLEAN, false),
                        NULLIF(field_data->>'order','')::BIGINT,
                        field_product_type,
                        COALESCE((field_data->>'is_ticket_field')::BOOLEAN, false)
                    )
                    RETURNING id INTO field_id;

                    field_data := jsonb_set(field_data, '{id}', TO_JSONB(field_id));
                END IF;

                form_fields_data := form_fields_data || field_data;
            END LOOP;
        END IF;

        ----------------------------------------------------------------------------
        -- Validate that deadline_duration_seconds is zero, positive, or null
        ----------------------------------------------------------------------------
        IF (input_data->'data'->>'reminder_interval_seconds')::bigint < 0 THEN
            RAISE EXCEPTION 'reminder_interval_seconds must be zero or higher or null';
        END IF;
        deadline_val := NULLIF(input_data->>'deadline_duration_seconds','')::BIGINT;
        IF deadline_val IS NOT NULL AND deadline_val < 0 THEN
            RAISE EXCEPTION '%',
                JSONB_BUILD_OBJECT(
                    'code', 4016,
                    'message', 'deadline_duration_seconds must be zero or higher or null'
                )::TEXT;
        END IF;

        ----------------------------------------------------------------------------
        -- Validate bank_account belongs to the same unit as the occasion, if provided
        ----------------------------------------------------------------------------
        bank_account_val := NULLIF(input_data->>'bank_account','')::BIGINT;
        IF bank_account_val IS NOT NULL THEN
            SELECT ba.unit
              INTO bank_account_unit
              FROM eshop.unit_bank_accounts ba
             WHERE ba.bank_account = bank_account_val
               AND ba.unit = occasion_unit
             LIMIT 1;

            IF NOT FOUND THEN
                RAISE EXCEPTION '%',
                    JSONB_BUILD_OBJECT(
                        'code', 4020,
                        'message', 'Bank account not found',
                        'bank_account', bank_account_val
                    )::TEXT;
            END IF;

            IF bank_account_unit <> occasion_unit THEN
                RAISE EXCEPTION '%',
                    JSONB_BUILD_OBJECT(
                        'code', 4021,
                        'message', 'Bank account does not belong to the same unit as the occasion',
                        'bank_account_unit', bank_account_unit,
                        'occasion_unit', occasion_unit
                    )::TEXT;
            END IF;
        END IF;

        ----------------------------------------------------------------------------
        -- Update the main form record with all validated fields
        ----------------------------------------------------------------------------
        PERFORM public.check_form_capacity_settings_internal(form_id,input_data);
        UPDATE public.forms
           SET
               participant_capacity = CASE WHEN input_data ? 'participant_capacity' THEN (input_data->>'participant_capacity')::integer ELSE participant_capacity END,
               waitlist_enabled = CASE WHEN input_data ? 'waitlist_enabled' THEN (input_data->>'waitlist_enabled')::boolean ELSE waitlist_enabled END,
               show_remaining_capacity = CASE WHEN input_data ? 'show_remaining_capacity' THEN (input_data->>'show_remaining_capacity')::boolean ELSE show_remaining_capacity END,
               waitlist_offer_duration_seconds = CASE WHEN input_data ? 'waitlist_offer_duration_seconds' THEN (input_data->>'waitlist_offer_duration_seconds')::integer ELSE waitlist_offer_duration_seconds END,
               capacity_revision = capacity_revision+1,
               title = input_data->>'title',
               data = input_data->'data',
               header = input_data->>'header',
               header_off = input_data->>'header_off',
               link = link_param,
               blueprint = NULLIF(input_data->>'blueprint','')::BIGINT,
               bank_account = bank_account_val,
               deadline_duration_seconds = deadline_val,
               is_open = COALESCE((input_data->>'is_open')::BOOLEAN, true)
         WHERE id = form_id;

        ----------------------------------------------------------------------------
        -- After updating the form, requeue payment reminders for the whole occasion
        -- as the form's settings (e.g., is_reminder_enabled) might have changed.
        ----------------------------------------------------------------------------
        -- First, find the 'seconds_before_deadline' setting from the occasion's 'form' feature.
        SELECT (elem->>'reminder_interval_seconds')::BIGINT
          INTO v_seconds_before_deadline
          FROM public.occasions, jsonb_array_elements(features) AS elem
         WHERE id = occasion_id
           AND elem->>'code' = 'form'
         LIMIT 1;

        -- If the setting is found, call the function to rebuild the reminder queue.
        PERFORM public.queue_payment_reminders(occasion_id, COALESCE(v_seconds_before_deadline,86400));

        ----------------------------------------------------------------------------
        -- Prepare a success response
        ----------------------------------------------------------------------------
        result := JSONB_BUILD_OBJECT(
            'code', 200,
            'message', 'Form updated successfully',
            'form_id', form_id,
            'form_fields', form_fields_data
        );

    EXCEPTION WHEN OTHERS THEN
        -- Catch any exception and attempt to parse it as JSON; if not JSON, wrap it in our own JSON.
        result := CASE
            WHEN left(SQLERRM, 1) = '{' THEN SQLERRM::JSONB
            ELSE JSONB_BUILD_OBJECT('code', 5001, 'message', SQLERRM)
        END;
    END;

    RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_ticket_products_wsv2(
  p_ticket_id    bigint,
  p_products     jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions AS
$$
DECLARE
  v_order_id         bigint;
  v_occasion_id      bigint;
  v_payment_info_id  bigint;
  v_currency_code    char(3);
  v_state            text;
  v_old_data         jsonb;
  v_new_data         jsonb;
  v_sum_old          numeric := 0;
  v_sum_new          numeric := 0;
  v_diff             numeric;
  v_products_json    jsonb;
  v_old_products     jsonb;
  v_old_ids          bigint[];
  v_new_ids          bigint[];
  v_paid             numeric;
  v_price            numeric;
  v_new_state        text;
  v_occasion_features jsonb;
  v_form_settings     jsonb;
  v_deadline_duration_seconds bigint;
  v_new_deadline      timestamptz;
  v_current_products_for_compare jsonb;
BEGIN
  PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT "order" FROM eshop.order_product_ticket WHERE ticket=p_ticket_id));
  /* 0) Lookup & permission */
  SELECT opt."order", o.occasion, o.payment_info, o.currency_code, o.data, o.state, occ.features
    INTO v_order_id, v_occasion_id, v_payment_info_id, v_currency_code, v_old_data, v_state, v_occasion_features
  FROM eshop.order_product_ticket AS opt
  JOIN eshop.orders              AS o   ON o.id = opt."order"
  JOIN public.occasions          AS occ ON occ.id = o.occasion
  WHERE opt.ticket = p_ticket_id
  LIMIT 1 FOR UPDATE OF o;

  IF NOT FOUND THEN
    RAISE EXCEPTION '%', jsonb_build_object('code', 404, 'message', 'Ticket not linked to any order')::text;
  END IF;

  IF NOT get_is_editor_order_on_occasion(v_occasion_id) THEN
    RAISE EXCEPTION '%', jsonb_build_object('code', 403, 'message', 'Not authorized')::text;
  END IF;

  PERFORM public.check_ticket_is_mutable(p_ticket_id);

  /* Check for negative prices in the input */
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_products) AS p
    WHERE (p.value->>'price')::numeric < 0
  ) THEN
    RAISE EXCEPTION '%', jsonb_build_object('code', 400, 'message', 'Product prices cannot be negative.')::text;
  END IF;

  PERFORM public.lock_ticket_order_products_internal(v_order_id,jsonb_build_object('ticket',jsonb_build_array(jsonb_build_object('fields',
    (SELECT coalesce(jsonb_agg(jsonb_build_object('product_type',x->'id')),'[]') FROM jsonb_array_elements(p_products) x)))));
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_products) x JOIN eshop.products p ON p.id=(x->>'id')::bigint
    WHERE p.maximum>0 AND (SELECT count(*) FROM eshop.order_product_ticket WHERE product=p.id)+
      CASE WHEN EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE ticket=p_ticket_id AND product=p.id) THEN 0 ELSE 1 END>p.maximum) THEN
    RAISE EXCEPTION 'PRODUCT_CAPACITY_EXCEEDED'; END IF;
  /* get old products for the ticket */
  SELECT jsonb_path_query_first(v_old_data, '$.tickets[*] ? (@.id == $tid).products', jsonb_build_object('tid', p_ticket_id))
  INTO v_old_products;
  v_old_products := COALESCE(v_old_products, '[]'::jsonb);

  /* compute old/new ID arrays and check for changes */
  SELECT array_agg((p->>'id')::bigint) INTO v_old_ids FROM jsonb_array_elements(v_old_products) p;
  SELECT array_agg((p->>'id')::bigint) INTO v_new_ids FROM jsonb_array_elements(p_products) p;

  -- Create a comparable representation of products (id and price)
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', p->'id', 'price', p->'price') ORDER BY (p->>'id')::int), '[]'::jsonb)
  INTO v_current_products_for_compare
  FROM jsonb_array_elements(v_old_products) p;

  -- If product sets (ID and price) are identical, bail early.
  IF v_current_products_for_compare = (
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id', p->'id', 'price', p->'price') ORDER BY (p->>'id')::int), '[]'::jsonb)
    FROM jsonb_array_elements(p_products) p
  ) THEN
    RETURN jsonb_build_object('code',200,'data',v_old_data, 'message', 'No changes detected.');
  END IF;

  /* 1) old subtotal */
  SELECT COALESCE(SUM((p->>'price')::numeric), 0)
  INTO v_sum_old
  FROM jsonb_array_elements(v_old_products) AS p;

  /* 2) new products JSON + subtotal (FIXED HERE) */
  -- We now find the matching old product and merge it (||) with the new data.
  -- This preserves 'spot_title', 'spot_id' or any other extra fields.
  SELECT
    jsonb_agg(
      -- Start with the old product object if it exists (for this ID)
      COALESCE(
        (
           SELECT old_p
           FROM jsonb_array_elements(v_old_products) AS old_p
           WHERE (old_p->>'id')::bigint = p_info.id
           LIMIT 1
        ),
        '{}'::jsonb
      )
      ||
      -- Overwrite with refreshed/new standard fields
      jsonb_build_object(
        'id',            p_info.id,
        'type',          pt.type,
        'price',         (p_new.data->>'price')::numeric, -- Use price from input
        'title',         p_info.title,
        'type_title',    pt.title,
        'currency_code', p_info.currency_code
      )
    ),
    COALESCE(SUM((p_new.data->>'price')::numeric), 0)
  INTO v_products_json, v_sum_new
  FROM jsonb_array_elements(p_products) AS p_new(data)
  JOIN eshop.products           AS p_info ON p_info.id = (p_new.data->>'id')::bigint
  LEFT JOIN eshop.product_types AS pt     ON pt.id = p_info.product_type
  WHERE p_info.occasion = v_occasion_id;

  v_products_json := COALESCE(v_products_json, '[]'::jsonb);

  /* 3) rewrite just that ticket’s products array in orders.data */
  SELECT jsonb_set(
    v_old_data,
    '{tickets}',
    (
      SELECT jsonb_agg(
        CASE WHEN (tckt->>'id')::bigint = p_ticket_id
             THEN jsonb_set(tckt, '{products}', v_products_json)
             ELSE tckt
        END
      )
      FROM jsonb_array_elements(v_old_data->'tickets') AS tckt
    )
  ) INTO v_new_data;

  UPDATE eshop.orders
     SET data = v_new_data
   WHERE id = v_order_id;

  /* Update the ticket timestamp */
  UPDATE eshop.tickets
     SET updated_at = now()
   WHERE id = p_ticket_id;

  /* 4) granularly update the link‐table rows */
  v_old_ids := COALESCE(v_old_ids, ARRAY[]::bigint[]);
  v_new_ids := COALESCE(v_new_ids, ARRAY[]::bigint[]);

  -- Before deleting order_product_ticket rows, nullify the reference in eshop.spots
  UPDATE eshop.spots s
     SET order_product_ticket = NULL
  WHERE s.order_product_ticket IN (
      SELECT opt.id
      FROM eshop.order_product_ticket opt
      WHERE opt.ticket = p_ticket_id
        AND opt.product IN (SELECT unnest FROM unnest(v_old_ids) EXCEPT SELECT unnest FROM unnest(v_new_ids))
  );

  -- Delete link-table rows for products that were removed.
  DELETE FROM eshop.order_product_ticket
  WHERE ticket = p_ticket_id
    AND product IN (SELECT unnest FROM unnest(v_old_ids) EXCEPT SELECT unnest FROM unnest(v_new_ids));

  -- Insert new link-table rows for products that were added.
  INSERT INTO eshop.order_product_ticket ("order", ticket, product)
  SELECT v_order_id, p_ticket_id, new_pid
    FROM (SELECT unnest FROM unnest(v_new_ids) EXCEPT SELECT unnest FROM unnest(v_old_ids)) AS t(new_pid)
  ON CONFLICT DO NOTHING;

  /* 5) adjust payment_info.amount and order.price by the delta */
  v_diff := v_sum_new - v_sum_old;
  IF v_diff <> 0 THEN
      UPDATE eshop.payment_info
         SET amount = amount + v_diff
       WHERE id = v_payment_info_id;
      UPDATE eshop.orders
         SET price      = COALESCE(price,0) + v_diff,
             updated_at = now()
       WHERE id = v_order_id;
  END IF;

  /* 5a) decide new state based on money received */
  SELECT COALESCE(pi.paid,0), o.price
    INTO v_paid, v_price
    FROM eshop.orders o
    LEFT JOIN eshop.payment_info pi ON o.payment_info = pi.id
   WHERE o.id = v_order_id;

  v_new_state := CASE
                   WHEN v_paid >= v_price AND v_price > 0 THEN 'paid'
                   WHEN v_price <= 0 THEN 'paid'
                   ELSE 'ordered'
                 END;

  IF v_new_state = 'paid' THEN
    IF NOT EXISTS (
      SELECT 1 FROM eshop.tickets t
      JOIN eshop.order_product_ticket opt ON opt.ticket = t.id
      WHERE opt."order" = v_order_id AND t.state <> 'sent'
    ) THEN
      v_new_state := 'sent';
    END IF;
  END IF;

  PERFORM public.cancel_order_email_intents(v_order_id);
  UPDATE eshop.orders
     SET email_payment_version=email_payment_version+1, state      = v_new_state,
         updated_at = now()
   WHERE id = v_order_id;

  -- A price edit can pay off the order without the usual paid transition.
  -- Email acceptance only projects paid tickets to sent, so keep eligible
  -- tickets in step with the order before creating its delivery intent.
  IF v_new_state = 'paid' THEN
    UPDATE eshop.tickets t
       SET state = 'paid', updated_at = now()
      FROM eshop.order_product_ticket opt
     WHERE opt.ticket = t.id AND opt."order" = v_order_id
       AND t.state IN ('ordered', 'expired');
  END IF;

  IF v_price > 0 THEN
    -- If there's a balance due, set/update the payment deadline.
    SELECT elem INTO v_form_settings
    FROM jsonb_array_elements(v_occasion_features) AS elem
    WHERE elem->>'code' = 'form';

    v_deadline_duration_seconds := COALESCE(
        (SELECT f.deadline_duration_seconds FROM public.forms f
         JOIN eshop.orders o ON o.form=f.id WHERE o.id=v_order_id),
        (v_form_settings->>'deadline_duration_seconds')::bigint,
        604800 -- Default to 7 days (604800 seconds) if not specified
    );

    v_new_deadline := now() + make_interval(secs => v_deadline_duration_seconds);
    PERFORM public.set_payment_deadline(v_payment_info_id, v_new_deadline);
  ELSE
    -- If the order is free or paid off, clear the payment deadline.
    PERFORM public.set_payment_deadline(v_payment_info_id, NULL);
  END IF;

  PERFORM apply_allocations(v_order_id);
  PERFORM public.enqueue_paid_order_tickets(v_order_id);

  /* 6) append history */
  INSERT INTO eshop.orders_history("order", data, state, price, currency_code)
  VALUES (
    v_order_id,
    v_new_data,
    v_new_state,
    (SELECT price FROM eshop.orders WHERE id = v_order_id),
    v_currency_code
  );

  RETURN jsonb_build_object('code',200,'data',v_new_data);
END;
$$;

-- The receipted Client Sync command must use the same payment and email
-- transition as the legacy RPC, rather than its pre-email-cutover copy.
CREATE OR REPLACE FUNCTION public.update_ticket_products_internal_v1(
  p_ticket_id bigint, p_products jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions AS $$
BEGIN
  RETURN public.update_ticket_products_wsv2(p_ticket_id, p_products);
END;
$$;
REVOKE ALL ON FUNCTION public.update_ticket_products_internal_v1(bigint,jsonb)
  FROM PUBLIC, anon, authenticated;

COMMIT;
