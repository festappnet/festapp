-- Classify bank observations, separate response policy, and deduplicate bank-admin mailboxes.
-- Internal read helper. Only authorized domain RPCs may expose these details.
CREATE OR REPLACE FUNCTION public.bank_sync_problem(p_connection_id bigint)
RETURNS text LANGUAGE sql STABLE SET search_path=public,extensions AS $$
  SELECT CASE
    WHEN c.state='suspended' THEN 'suspended'
    WHEN c.state IN ('provisioning','shadow') THEN 'not_configured'
    WHEN c.mode='email' AND c.pairing_code IS NULL THEN 'email_missing'
    WHEN c.last_error='bank_sync_unavailable' THEN 'unavailable'
    WHEN c.mode='api' AND h.token_present IS FALSE THEN 'token_missing'
    WHEN c.last_error='fio_token_invalid_or_inactive' THEN 'token_invalid'
    WHEN c.last_error='fio_receiving_account_mismatch' THEN 'account_mismatch'
    WHEN c.last_error='fio_temporarily_unavailable' THEN 'temporary_failure'
    WHEN h.ingest_enabled IS FALSE OR (c.mode='api' AND h.polling_enabled IS FALSE) THEN 'connection_disabled'
    WHEN c.last_error IS NOT NULL OR c.state='degraded' THEN 'bank_error'
    -- bank_pull_at is a local copy of BankSync's successful pull timestamp.
    -- Only a fresh remote health observation can prove that polling stalled;
    -- an unmonitored or expired snapshot is not evidence of a bank failure.
    WHEN c.mode='api' AND h.checked_at>now()-interval '10 minutes'
      AND COALESCE(c.bank_pull_at,c.created_at)<now()-interval '30 minutes' THEN 'stale'
    ELSE NULL END
  FROM eshop.bank_sync_connections c LEFT JOIN eshop.bank_sync_health h ON h.connection_id=c.id
  WHERE c.id=p_connection_id;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_problem(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.bank_sync_warning(p_bank_account_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE v_title text; v_type text; v_connection bigint; v_code text; v_contacts jsonb;
BEGIN
  SELECT title,type INTO v_title,v_type FROM eshop.bank_accounts WHERE id=p_bank_account_id;
  IF NOT FOUND OR v_type='CASH' THEN RETURN NULL; END IF;
  SELECT c.id INTO v_connection FROM eshop.bank_sync_connections c WHERE c.bank_account_id=p_bank_account_id
    OR c.id IN (SELECT connection_id FROM eshop.bank_sync_account_aliases WHERE bank_account_id=p_bank_account_id);
  v_code:=CASE WHEN v_connection IS NULL THEN 'not_configured' ELSE public.bank_sync_problem(v_connection) END;
  IF v_code IS NULL THEN RETURN NULL; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('name',NULLIF(btrim(concat_ws(' ',ui.name,ui.surname)),''),
    'email',public.get_user_delivery_email(ui.id)) ORDER BY ui.name,ui.surname,ui.id),'[]'::jsonb)
    INTO v_contacts FROM eshop.bank_account_users bau JOIN public.user_info ui ON ui.id=bau."user"
    WHERE bau.bank_account=p_bank_account_id AND bau.is_admin;
  RETURN jsonb_build_object('code',v_code,'bank_account_title',v_title,'contacts',v_contacts,
    'bank_account_id',p_bank_account_id,'is_admin',EXISTS (
      SELECT 1 FROM eshop.bank_account_users bau WHERE bau.bank_account=p_bank_account_id
        AND bau."user"=auth.uid() AND bau.is_admin));
END;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_warning(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_bank_sync_health_targets(p_organization_id bigint)
RETURNS TABLE(connection_id bigint,remote_bank_account_id text,mode text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  RETURN QUERY SELECT c.id,c.remote_bank_account_id,c.mode FROM eshop.bank_sync_connections c
    WHERE c.legacy_blocked_at IS NOT NULL AND c.state IN ('connected','degraded','suspended')
      AND EXISTS (SELECT 1 FROM eshop.unit_bank_accounts ub JOIN public.units u ON u.id=ub.unit
        WHERE u.organization=p_organization_id AND (ub.bank_account=c.bank_account_id
          OR ub.bank_account IN (SELECT a.bank_account_id FROM eshop.bank_sync_account_aliases a WHERE a.connection_id=c.id)))
    ORDER BY (SELECT h.checked_at FROM eshop.bank_sync_health h WHERE h.connection_id=c.id) NULLS FIRST,c.id LIMIT 100;
END;
$$;
REVOKE ALL ON FUNCTION public.get_bank_sync_health_targets(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_bank_sync_health_targets(bigint) TO service_role;

-- Response policy belongs to Festapp, not to the bank transport adapter.
-- Unknown/temporary failures never ask an administrator to replace credentials.
CREATE OR REPLACE FUNCTION public.bank_sync_requires_action(p_code text)
RETURNS boolean LANGUAGE sql IMMUTABLE STRICT SET search_path=public,extensions AS $$
  SELECT p_code IN ('token_missing','token_invalid','account_mismatch','email_missing','connection_disabled');
$$;
REVOKE ALL ON FUNCTION public.bank_sync_requires_action(text) FROM PUBLIC,anon,authenticated,service_role;

-- Shared by admission and the final email validity check. Old observations and
-- recovered connections must not produce delayed, misleading notifications.
CREATE OR REPLACE FUNCTION public.bank_sync_alert_ready(p_connection_id bigint)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
  SELECT COALESCE((SELECT h.warning_code IS NOT NULL
    AND h.warning_since<=now()-CASE WHEN public.bank_sync_requires_action(h.warning_code)
      THEN interval '10 minutes' ELSE interval '60 minutes' END
    AND h.checked_at>now()-interval '10 minutes'
    AND c.state IN ('connected','degraded')
    AND public.bank_sync_problem(c.id)=h.warning_code
    FROM eshop.bank_sync_health h JOIN eshop.bank_sync_connections c ON c.id=h.connection_id
    WHERE c.id=p_connection_id),false);
$$;
REVOKE ALL ON FUNCTION public.bank_sync_alert_ready(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.record_bank_sync_health(p_organization_id bigint,p_connection_id bigint,
 p_success_at timestamptz,p_error text,p_ingest_enabled boolean,p_polling_enabled boolean,p_token_present boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_connection eshop.bank_sync_connections; v_code text; v_new_incident boolean;
BEGIN
  PERFORM public.require_service_role();
  SELECT c.* INTO STRICT v_connection FROM eshop.bank_sync_connections c
    WHERE c.id=p_connection_id AND EXISTS (SELECT 1 FROM eshop.unit_bank_accounts ub JOIN public.units u ON u.id=ub.unit
      WHERE u.organization=p_organization_id AND (ub.bank_account=c.bank_account_id OR ub.bank_account IN
        (SELECT a.bank_account_id FROM eshop.bank_sync_account_aliases a WHERE a.connection_id=c.id))) FOR UPDATE;
  IF p_error IS NOT NULL AND p_error NOT IN ('fio_token_invalid_or_inactive','fio_receiving_account_mismatch','bank_sync_retry_required',
    'fio_temporarily_unavailable','bank_sync_unavailable') THEN
    RAISE EXCEPTION 'BANK_SYNC_HEALTH_ERROR_INVALID';
  END IF;
  PERFORM public.record_bank_sync_pull(p_connection_id,p_success_at,p_error);
  INSERT INTO eshop.bank_sync_health(connection_id,checked_at,ingest_enabled,polling_enabled,token_present)
    VALUES(p_connection_id,now(),p_ingest_enabled,p_polling_enabled,p_token_present)
    ON CONFLICT(connection_id) DO UPDATE SET checked_at=now(),
      ingest_enabled=COALESCE(EXCLUDED.ingest_enabled,eshop.bank_sync_health.ingest_enabled),
      polling_enabled=COALESCE(EXCLUDED.polling_enabled,eshop.bank_sync_health.polling_enabled),
      token_present=COALESCE(EXCLUDED.token_present,eshop.bank_sync_health.token_present);
  IF v_connection.mode='email' AND v_connection.state='degraded' AND p_error IS NULL AND p_ingest_enabled IS TRUE THEN
    UPDATE eshop.bank_sync_connections SET state='connected' WHERE id=p_connection_id;
  END IF;
  v_code:=CASE WHEN v_connection.state IN ('connected','degraded') THEN public.bank_sync_problem(p_connection_id) END;
  -- Preserve the outage clock across changing retry symptoms. An actionable
  -- fault starts its own incident so a prior availability warning cannot hide it.
  SELECT (public.bank_sync_requires_action(v_code) IS DISTINCT FROM public.bank_sync_requires_action(warning_code))
    OR (public.bank_sync_requires_action(v_code) AND v_code IS DISTINCT FROM warning_code)
    INTO v_new_incident FROM eshop.bank_sync_health WHERE connection_id=p_connection_id;
  UPDATE eshop.bank_sync_health SET warning_code=v_code,
    warning_since=CASE WHEN v_code IS NULL THEN NULL WHEN v_new_incident THEN now() ELSE COALESCE(warning_since,now()) END,
    incident_id=CASE WHEN v_code IS NULL THEN NULL WHEN v_new_incident THEN gen_random_uuid() ELSE COALESCE(incident_id,gen_random_uuid()) END,
    notified_at=CASE WHEN v_code IS NULL OR v_new_incident THEN NULL ELSE notified_at END WHERE connection_id=p_connection_id;
END;
$$;
REVOKE ALL ON FUNCTION public.record_bank_sync_health(bigint,bigint,timestamptz,text,boolean,boolean,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.record_bank_sync_health(bigint,bigint,timestamptz,text,boolean,boolean,boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.enqueue_bank_sync_health_alerts(p_organization_id bigint)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE r record; a record; v_count integer:=0; v_sent integer; v_message jsonb;
BEGIN
  PERFORM public.require_service_role();
  FOR r IN SELECT h.*,c.bank_account_id,b.title FROM eshop.bank_sync_health h
    JOIN eshop.bank_sync_connections c ON c.id=h.connection_id JOIN eshop.bank_accounts b ON b.id=c.bank_account_id
    WHERE h.notified_at IS NULL AND public.bank_sync_alert_ready(c.id)
      AND EXISTS (SELECT 1 FROM eshop.unit_bank_accounts ub JOIN public.units u ON u.id=ub.unit
        WHERE u.organization=p_organization_id AND (ub.bank_account=c.bank_account_id OR ub.bank_account IN
          (SELECT x.bank_account_id FROM eshop.bank_sync_account_aliases x WHERE x.connection_id=c.id)))
    ORDER BY h.warning_since FOR UPDATE OF h SKIP LOCKED
  LOOP
    v_sent:=0;
    -- Different identities/aliases can share one mailbox. Pick one authorized
    -- recipient deterministically, retaining the delivery address for validity.
    FOR a IN SELECT DISTINCT ON (lower(btrim(x.email))) x.* FROM (
      SELECT ui.id,public.get_user_delivery_email(ui.id) AS email,
        COALESCE(ui.data->>'locale','cs') AS language
      FROM eshop.bank_account_users bau JOIN public.user_info ui ON ui.id=bau."user"
      WHERE bau.is_admin AND (bau.bank_account=r.bank_account_id OR bau.bank_account IN
        (SELECT x.bank_account_id FROM eshop.bank_sync_account_aliases x WHERE x.connection_id=r.connection_id))
      ) x WHERE NULLIF(btrim(x.email),'') IS NOT NULL ORDER BY lower(btrim(x.email)),x.id
    LOOP
      IF a.email IS NULL THEN CONTINUE; END IF;
      v_message:=public.enqueue_email('custom',jsonb_build_object('organization',p_organization_id,'recipient_user',a.id),a.email,
        jsonb_build_object('connection_id',r.connection_id,'incident_id',r.incident_id,'warning_code',r.warning_code,
          'account_title',r.title,'language',a.language,'warning_since',r.warning_since,
          'last_success_at',(SELECT bank_pull_at FROM eshop.bank_sync_connections WHERE id=r.connection_id)),
        'bank-sync:'||r.connection_id||':'||r.incident_id||':'||md5(lower(btrim(a.email))),'BANK_SYNC_WARNING',now(),now()+interval '1 day');
      UPDATE public.email_messages SET tracking_policy='disabled' WHERE message_id=(v_message->>'message_id')::uuid;
      v_sent:=v_sent+1;
    END LOOP;
    IF v_sent>0 THEN UPDATE eshop.bank_sync_health SET notified_at=now() WHERE connection_id=r.connection_id; END IF;
    v_count:=v_count+v_sent;
  END LOOP;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.enqueue_bank_sync_health_alerts(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_bank_sync_health_alerts(bigint) TO service_role;

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
      AND h.incident_id::text=p_message.data->>'incident_id'
      AND public.bank_sync_alert_ready(c.id)
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

