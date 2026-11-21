-- Installed before provider mutation. This keeps pre-existing AAL1 grants
-- closed during the gap after removal of the last verified factor.
CREATE TABLE IF NOT EXISTS public.account_mfa_factor_removals (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  id uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  factor_id uuid NOT NULL,
  credential_kind text NOT NULL DEFAULT 'factor' CHECK (credential_kind IN ('factor', 'passkey')),
  organization bigint NOT NULL,
  last_factor boolean NOT NULL,
  recipient text NOT NULL,
  affected_sessions uuid[] NOT NULL,
  started_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.account_mfa_factor_removals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_mfa_factor_removals FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.begin_account_mfa_factor_removal_v1(
  p_user uuid, p_session uuid, p_factor uuid, p_confirm_disable boolean
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_organization bigint;
  v_count integer;
  v_id uuid;
  v_recipient text;
BEGIN
  PERFORM public.require_service_role();
  PERFORM 1 FROM public.user_info WHERE id = p_user FOR UPDATE;
  IF EXISTS (SELECT FROM public.account_mfa_factor_removals WHERE user_id = p_user) THEN
    RETURN jsonb_build_object('state', 'busy');
  END IF;
  SELECT profile.organization INTO v_organization
  FROM public.user_info profile
  JOIN auth.sessions s ON s.user_id = profile.id
  JOIN auth.mfa_factors f ON f.user_id = s.user_id AND f.id = s.factor_id AND f.status = 'verified'
  WHERE profile.id = p_user AND s.id = p_session AND s.aal::text = 'aal2'
    AND (s.not_after IS NULL OR s.not_after > clock_timestamp());
  IF v_organization IS NULL OR EXISTS (SELECT FROM public.account_mfa_recovery_holds WHERE user_id = p_user)
    OR NOT EXISTS (
      SELECT FROM auth.mfa_factors
      WHERE id = p_factor AND user_id = p_user AND status = 'verified'
        AND factor_type IN ('totp', 'phone', 'webauthn')
    ) THEN RETURN jsonb_build_object('state', 'refused'); END IF;

  SELECT count(*) INTO v_count FROM auth.mfa_factors
  WHERE user_id = p_user AND status = 'verified' AND factor_type IN ('totp', 'phone', 'webauthn');
  IF v_count = 1 AND p_confirm_disable IS DISTINCT FROM true THEN
    RETURN jsonb_build_object('state', 'confirm_disable');
  END IF;

  v_recipient := public.get_user_delivery_email(p_user);
  IF v_recipient IS NULL THEN RETURN jsonb_build_object('state', 'refused'); END IF;
  INSERT INTO public.account_mfa_factor_removals (user_id, factor_id, organization, last_factor, recipient, affected_sessions)
  VALUES (p_user, p_factor, v_organization, v_count = 1, v_recipient, ARRAY(
    SELECT id FROM auth.sessions WHERE user_id = p_user AND factor_id = p_factor
  ))
  ON CONFLICT (user_id) DO NOTHING RETURNING id INTO v_id;
  IF v_id IS NULL THEN RETURN jsonb_build_object('state', 'busy'); END IF;
  RETURN jsonb_build_object('state', 'reserved', 'id', v_id, 'lastFactor', v_count = 1,
    'revokesSession', v_count = 1 OR EXISTS (
      SELECT FROM auth.sessions WHERE id = p_session AND factor_id = p_factor
    ));
END $$;

CREATE OR REPLACE FUNCTION public.begin_account_passkey_removal_v1(
  p_user uuid, p_session uuid, p_credential uuid, p_password_proven boolean
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_profile public.user_info%rowtype;
  v_id uuid;
  v_recipient text;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO v_profile FROM public.user_info WHERE id = p_user FOR UPDATE;
  IF NOT FOUND OR EXISTS (SELECT FROM public.account_mfa_recovery_holds WHERE user_id = p_user)
    OR NOT EXISTS (SELECT FROM auth.webauthn_credentials WHERE id = p_credential AND user_id = p_user)
    OR NOT EXISTS (SELECT FROM auth.sessions WHERE id = p_session AND user_id = p_user
      AND (not_after IS NULL OR not_after > clock_timestamp())) THEN
    RETURN jsonb_build_object('state', 'refused');
  END IF;
  IF EXISTS (SELECT FROM public.account_mfa_factor_removals WHERE user_id = p_user) THEN
    RETURN jsonb_build_object('state', 'busy');
  END IF;
  IF NOT EXISTS (SELECT FROM auth.webauthn_credentials WHERE user_id = p_user AND id <> p_credential)
    AND (p_password_proven IS DISTINCT FROM true OR NOT EXISTS (
      SELECT FROM auth.mfa_amr_claims WHERE session_id = p_session AND authentication_method = 'password'
        AND updated_at >= clock_timestamp() - interval '5 minutes'
    )) THEN RETURN jsonb_build_object('state', 'password_required'); END IF;

  v_recipient := public.get_user_delivery_email(p_user);
  IF v_recipient IS NULL THEN RETURN jsonb_build_object('state', 'refused'); END IF;
  INSERT INTO public.account_mfa_factor_removals
    (user_id, factor_id, credential_kind, organization, last_factor, recipient, affected_sessions)
  VALUES (p_user, p_credential, 'passkey', v_profile.organization, false, v_recipient, '{}')
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('state', 'reserved', 'id', v_id, 'revokesSession', true);
END $$;

CREATE OR REPLACE FUNCTION public.finish_account_mfa_factor_removal_v1(p_operation uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_pending public.account_mfa_factor_removals%rowtype;
  v_message jsonb;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO v_pending FROM public.account_mfa_factor_removals WHERE id = p_operation FOR UPDATE;
  IF NOT FOUND OR (v_pending.credential_kind = 'factor' AND EXISTS (
    SELECT FROM auth.mfa_factors WHERE id = v_pending.factor_id
  )) OR (v_pending.credential_kind = 'passkey' AND EXISTS (
    SELECT FROM auth.webauthn_credentials WHERE id = v_pending.factor_id
  )) THEN RETURN false; END IF;

  IF v_pending.last_factor OR v_pending.credential_kind = 'passkey' THEN
    UPDATE auth.refresh_tokens SET revoked = true WHERE user_id = v_pending.user_id::text AND NOT revoked;
    DELETE FROM auth.sessions WHERE user_id = v_pending.user_id;
  ELSE
    UPDATE auth.refresh_tokens SET revoked = true
    WHERE session_id = ANY(v_pending.affected_sessions) AND NOT revoked;
    DELETE FROM auth.sessions WHERE user_id = v_pending.user_id AND id = ANY(v_pending.affected_sessions);
  END IF;
  UPDATE public.scanner_sessions SET revoked_at = clock_timestamp()
  WHERE actor_user_id = v_pending.user_id AND revoked_at IS NULL;

  v_message := public.enqueue_email('custom', jsonb_build_object('organization', v_pending.organization),
    v_pending.recipient, jsonb_build_object('lang', coalesce(
      (SELECT data->>'DEFAULT_LANGUAGE' FROM public.organizations WHERE id = v_pending.organization), 'cs')),
    'mfa-factor-removal:' || p_operation::text,
    CASE WHEN v_pending.credential_kind = 'passkey' THEN 'ACCOUNT_PASSKEY_REMOVED' ELSE 'ACCOUNT_MFA_FACTOR_REMOVED' END);
  UPDATE public.email_messages SET tracking_policy = 'disabled'
  WHERE message_id = (v_message->>'message_id')::uuid;
  DELETE FROM public.account_mfa_factor_removals WHERE id = p_operation;
  RETURN true;
END $$;

-- Only a definitive provider rejection can cancel. Uncertain transport and
-- post-commit failures leave the operation closed for reconciliation.
CREATE OR REPLACE FUNCTION public.cancel_account_mfa_factor_removal_v1(p_operation uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  DELETE FROM public.account_mfa_factor_removals op WHERE id = p_operation
    AND CASE WHEN op.credential_kind = 'passkey' THEN EXISTS (
      SELECT FROM auth.webauthn_credentials WHERE id = op.factor_id AND user_id = op.user_id
    ) ELSE EXISTS (
      SELECT FROM auth.mfa_factors WHERE id = op.factor_id AND user_id = op.user_id AND status = 'verified'
    ) END;
  RETURN FOUND;
END $$;

REVOKE ALL ON FUNCTION public.begin_account_mfa_factor_removal_v1(uuid,uuid,uuid,boolean),
  public.begin_account_passkey_removal_v1(uuid,uuid,uuid,boolean),
  public.finish_account_mfa_factor_removal_v1(uuid), public.cancel_account_mfa_factor_removal_v1(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.begin_account_mfa_factor_removal_v1(uuid,uuid,uuid,boolean),
  public.begin_account_passkey_removal_v1(uuid,uuid,uuid,boolean),
  public.finish_account_mfa_factor_removal_v1(uuid), public.cancel_account_mfa_factor_removal_v1(uuid)
  TO service_role;
