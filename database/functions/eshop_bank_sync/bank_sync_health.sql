-- BankSync observations and one durable notification incident per connection.
CREATE TABLE IF NOT EXISTS eshop.bank_sync_health (
  connection_id bigint PRIMARY KEY REFERENCES eshop.bank_sync_connections(id) ON DELETE CASCADE,
  checked_at timestamptz NOT NULL DEFAULT now(),
  ingest_enabled boolean,
  polling_enabled boolean,
  token_present boolean,
  warning_code text,
  warning_since timestamptz,
  incident_id uuid,
  notified_at timestamptz
);
ALTER TABLE eshop.bank_sync_health ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.bank_sync_health FROM PUBLIC,anon,authenticated,service_role;

-- Internal read helper. Only authorized domain RPCs may expose these details.
CREATE OR REPLACE FUNCTION public.bank_sync_problem(p_connection_id bigint)
RETURNS text LANGUAGE sql STABLE SET search_path=public,extensions AS $$
  SELECT CASE
    WHEN c.state='suspended' THEN 'suspended'
    WHEN c.state IN ('provisioning','shadow') THEN 'not_configured'
    WHEN c.mode='email' AND c.pairing_code IS NULL THEN 'email_missing'
    WHEN c.mode='api' AND h.token_present IS FALSE THEN 'token_missing'
    WHEN h.ingest_enabled IS FALSE OR (c.mode='api' AND h.polling_enabled IS FALSE) THEN 'bank_error'
    WHEN c.last_error IS NOT NULL OR c.state='degraded' THEN 'bank_error'
    WHEN c.mode='api' AND COALESCE(c.bank_pull_at,c.created_at)<now()-interval '30 minutes' THEN 'stale'
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
  RETURN jsonb_build_object('code',v_code,'bank_account_title',v_title,'contacts',v_contacts);
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

CREATE OR REPLACE FUNCTION public.record_bank_sync_health(p_organization_id bigint,p_connection_id bigint,
 p_success_at timestamptz,p_error text,p_ingest_enabled boolean,p_polling_enabled boolean,p_token_present boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_connection eshop.bank_sync_connections; v_code text;
BEGIN
  PERFORM public.require_service_role();
  SELECT c.* INTO STRICT v_connection FROM eshop.bank_sync_connections c
    WHERE c.id=p_connection_id AND EXISTS (SELECT 1 FROM eshop.unit_bank_accounts ub JOIN public.units u ON u.id=ub.unit
      WHERE u.organization=p_organization_id AND (ub.bank_account=c.bank_account_id OR ub.bank_account IN
        (SELECT a.bank_account_id FROM eshop.bank_sync_account_aliases a WHERE a.connection_id=c.id))) FOR UPDATE;
  IF p_error IS NOT NULL AND p_error NOT IN ('fio_token_invalid_or_inactive','fio_receiving_account_mismatch','bank_sync_retry_required') THEN
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
  UPDATE eshop.bank_sync_health SET warning_code=v_code,
    warning_since=CASE WHEN v_code IS NULL THEN NULL ELSE COALESCE(warning_since,now()) END,
    incident_id=CASE WHEN v_code IS NULL THEN NULL ELSE COALESCE(incident_id,gen_random_uuid()) END,
    notified_at=CASE WHEN v_code IS NULL THEN NULL ELSE notified_at END WHERE connection_id=p_connection_id;
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
    WHERE h.warning_code IS NOT NULL AND h.warning_since<=now()-interval '10 minutes' AND h.notified_at IS NULL
      AND h.checked_at>now()-interval '10 minutes' AND c.state IN ('connected','degraded')
      AND public.bank_sync_problem(c.id) IS NOT NULL
      AND EXISTS (SELECT 1 FROM eshop.unit_bank_accounts ub JOIN public.units u ON u.id=ub.unit
        WHERE u.organization=p_organization_id AND (ub.bank_account=c.bank_account_id OR ub.bank_account IN
          (SELECT x.bank_account_id FROM eshop.bank_sync_account_aliases x WHERE x.connection_id=c.id)))
    ORDER BY h.warning_since FOR UPDATE OF h SKIP LOCKED
  LOOP
    v_sent:=0;
    FOR a IN SELECT DISTINCT ui.id,public.get_user_delivery_email(ui.id) AS email,
      COALESCE(ui.data->>'locale','cs') AS language
      FROM eshop.bank_account_users bau JOIN public.user_info ui ON ui.id=bau."user"
      WHERE bau.is_admin AND (bau.bank_account=r.bank_account_id OR bau.bank_account IN
        (SELECT x.bank_account_id FROM eshop.bank_sync_account_aliases x WHERE x.connection_id=r.connection_id))
    LOOP
      IF a.email IS NULL THEN CONTINUE; END IF;
      v_message:=public.enqueue_email('custom',jsonb_build_object('organization',p_organization_id,'recipient_user',a.id),a.email,
        jsonb_build_object('connection_id',r.connection_id,'incident_id',r.incident_id,'warning_code',r.warning_code,
          'account_title',r.title,'language',a.language),
        'bank-sync:'||r.connection_id||':'||r.incident_id||':'||a.id,'BANK_SYNC_WARNING',now(),now()+interval '1 day');
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

CREATE OR REPLACE FUNCTION public.configure_bank_sync_health_monitor(p_organization_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_url text;
BEGIN
  PERFORM public.require_service_role();
  IF NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=p_organization_id) THEN RAISE EXCEPTION 'ORGANIZATION_NOT_FOUND'; END IF;
  SELECT regexp_replace(worker_url,'/process-email-queue$','/bank-sync-reconcile') INTO v_url FROM public.email_capacity;
  IF v_url IS NULL OR v_url !~ '^https://[^/]+/functions/v1/bank-sync-reconcile$' THEN RAISE EXCEPTION 'BANK_SYNC_MONITOR_URL_REQUIRED'; END IF;
  PERFORM cron.schedule('festapp_bank_sync_health_'||p_organization_id,'*/5 * * * *',
    format('SELECT net.http_post(url:=%L,body:=jsonb_build_object(''requestSecret'',public.generate_request_secret(3600),''monitor_organization_id'',%s),timeout_milliseconds:=360000)',v_url,p_organization_id));
END;
$$;
REVOKE ALL ON FUNCTION public.configure_bank_sync_health_monitor(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.configure_bank_sync_health_monitor(bigint) TO service_role;

-- Explicit administrator remediation starts a new observation window. Pending
-- incident mail becomes invalid immediately when synchronization is changed.
CREATE OR REPLACE FUNCTION public.reset_bank_sync_control_health(p_connection_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  DELETE FROM eshop.bank_sync_health WHERE connection_id=p_connection_id;
END;
$$;
REVOKE ALL ON FUNCTION public.reset_bank_sync_control_health(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.reset_bank_sync_control_health(bigint) TO service_role;
