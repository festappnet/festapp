-- Canonical sources: eshop_bank_sync/schema.sql, bank_sync_health.sql, bank_sync_manage.sql.
-- Existing errors receive a fresh grace clock on their first observed failure.
ALTER TABLE eshop.bank_sync_connections ADD COLUMN IF NOT EXISTS failure_since timestamptz;
ALTER TABLE eshop.bank_sync_connections ADD COLUMN IF NOT EXISTS failure_observed_at timestamptz;

CREATE OR REPLACE FUNCTION public.bank_sync_warning_pending(p_connection_id bigint)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
  SELECT COALESCE(c.state IN ('connected','degraded') AND (c.last_error IS NOT NULL OR c.state='degraded') AND (
    c.failure_since IS NULL OR c.failure_observed_at IS NULL
    OR c.failure_observed_at<c.failure_since+interval '10 minutes'
    OR c.failure_observed_at<=now()-interval '10 minutes'),false)
  FROM eshop.bank_sync_connections c WHERE c.id=p_connection_id;
$$;
REVOKE ALL ON FUNCTION public.bank_sync_warning_pending(bigint) FROM PUBLIC,anon,authenticated,service_role;

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
  IF v_code IN ('token_invalid','account_mismatch','temporary_failure','unavailable','bank_error')
    AND public.bank_sync_warning_pending(v_connection) THEN RETURN NULL; END IF;
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

CREATE OR REPLACE FUNCTION public.get_bank_sync_connection(p_bank_account_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_result jsonb;
BEGIN
  PERFORM public.check_is_admin_for_bank_account(p_bank_account_id);
  SELECT jsonb_build_object('id',c.id,'remote_bank_account_id',c.remote_bank_account_id,'state',c.state,'mode',c.mode,
    'receiving_address',CASE WHEN c.pairing_code IS NOT NULL THEN c.pairing_code||'@banksync.festapp.net' END,
    'bank_pull_at',c.bank_pull_at,'receiver_commit_at',c.receiver_commit_at,'last_error',c.last_error,
    'warning_pending',public.bank_sync_warning_pending(c.id),'token_expiry_at',c.token_expiry_at) INTO v_result FROM eshop.bank_sync_connections c
    WHERE c.bank_account_id=p_bank_account_id OR c.id IN
      (SELECT connection_id FROM eshop.bank_sync_account_aliases WHERE bank_account_id=p_bank_account_id);
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.get_bank_sync_connection(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_bank_sync_connection(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.record_bank_sync_pull(p_id bigint,p_success_at timestamptz,p_error text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  UPDATE eshop.bank_sync_connections SET bank_pull_at=COALESCE(p_success_at,bank_pull_at),last_error=left(p_error,256),
    failure_since=CASE WHEN p_error IS NULL THEN NULL
      WHEN last_error IS NULL OR (p_success_at IS NOT NULL AND (bank_pull_at IS NULL OR p_success_at>bank_pull_at)) THEN now()
      ELSE COALESCE(failure_since,now()) END,
    failure_observed_at=CASE WHEN p_error IS NOT NULL THEN now() END,
    state=CASE WHEN state IN ('connected','degraded') THEN
      CASE WHEN p_error IS NOT NULL THEN 'degraded' WHEN p_success_at IS NOT NULL THEN 'connected' ELSE state END
      ELSE state END WHERE id=p_id;
END;
$$;
REVOKE ALL ON FUNCTION public.record_bank_sync_pull(bigint,timestamptz,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.record_bank_sync_pull(bigint,timestamptz,text) TO service_role;
