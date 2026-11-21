CREATE TABLE IF NOT EXISTS public.account_passkey_sign_in_attempts (
  challenge_id uuid PRIMARY KEY,
  client_id text NOT NULL REFERENCES public.external_login_clients(client_id) ON DELETE CASCADE,
  organization bigint NOT NULL,
  origin text NOT NULL,
  redirect_uri text NOT NULL,
  sign_in_revision bigint NOT NULL,
  code_challenge text NOT NULL CHECK (code_challenge ~ '^[A-Za-z0-9_-]{43}$'),
  expires_at timestamptz NOT NULL,
  verifying boolean NOT NULL DEFAULT false,
  session_id uuid REFERENCES auth.sessions(id) ON DELETE CASCADE,
  code_hash text UNIQUE CHECK (code_hash ~ '^[0-9a-f]{64}$'),
  sealed_session text CHECK (length(sealed_session) <= 65536)
);
CREATE INDEX IF NOT EXISTS account_passkey_sign_in_expires_idx
  ON public.account_passkey_sign_in_attempts(expires_at);
ALTER TABLE public.account_passkey_sign_in_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_passkey_sign_in_attempts FROM PUBLIC, anon, authenticated, service_role;

-- The broker asks PostgREST to verify the provider token and resolve the
-- subject. A passkey is a primary proof, so MFA-required is a valid outcome.
CREATE OR REPLACE FUNCTION public.get_passkey_sign_in_actor_v1(p_organization bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = public, extensions AS $$
DECLARE v_decision text;
BEGIN
  v_decision := public.get_account_assurance_v1(p_organization);
  IF p_organization IS NULL OR v_decision NOT IN ('allowed', 'mfa_required')
    OR auth.jwt()->>'aal' IS DISTINCT FROM 'aal1'
    OR auth.jwt()->'amr' @> '[{"method":"passkey"}]'::jsonb IS DISTINCT FROM true THEN
    RETURN NULL;
  END IF;
  RETURN jsonb_build_object('sessionId', auth.jwt()->>'session_id', 'userId', auth.uid(),
    'requiresMfa', v_decision = 'mfa_required');
END $$;

CREATE OR REPLACE FUNCTION public.issue_passkey_sign_in_v1(
  p_id uuid, p_client_id text, p_organization bigint, p_origin text,
  p_redirect_uri text, p_revision bigint, p_code_challenge text
)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  IF public.resolve_mfa_channel_policy_v1(p_client_id, p_organization, p_origin, p_redirect_uri)
      ->'methods'->'passkey' @> jsonb_build_object(
        'signIn', true, 'signInRevision', p_revision) IS DISTINCT FROM true THEN
    RETURN false;
  END IF;
  DELETE FROM public.account_passkey_sign_in_attempts
  WHERE challenge_id IN (
    SELECT challenge_id FROM public.account_passkey_sign_in_attempts
    WHERE expires_at < clock_timestamp() ORDER BY expires_at LIMIT 32 FOR UPDATE SKIP LOCKED
  );
  INSERT INTO public.account_passkey_sign_in_attempts
    (challenge_id, client_id, organization, origin, redirect_uri, sign_in_revision, code_challenge, expires_at)
  VALUES (p_id, p_client_id, p_organization, p_origin, p_redirect_uri, p_revision,
          p_code_challenge, clock_timestamp() + interval '2 minutes');
  RETURN true;
END $$;

CREATE OR REPLACE FUNCTION public.reserve_passkey_sign_in_v1(p_id uuid, p_origin text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_scope jsonb;
BEGIN
  PERFORM public.require_service_role();
  UPDATE public.account_passkey_sign_in_attempts a
  SET verifying = true
  WHERE a.challenge_id = p_id AND a.origin = p_origin AND NOT a.verifying
    AND a.expires_at > clock_timestamp()
    AND public.resolve_mfa_channel_policy_v1(a.client_id, a.organization, a.origin, a.redirect_uri)
          ->'methods'->'passkey' @> jsonb_build_object('signIn', true, 'signInRevision', a.sign_in_revision)
  RETURNING jsonb_build_object('organization', a.organization, 'redirectUri', a.redirect_uri) INTO v_scope;
  RETURN v_scope;
END $$;

CREATE OR REPLACE FUNCTION public.complete_passkey_sign_in_v1(
  p_id uuid, p_origin text, p_user uuid, p_session uuid, p_code_hash text, p_sealed_session text
)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  UPDATE public.account_passkey_sign_in_attempts a
  SET session_id = p_session, code_hash = p_code_hash, sealed_session = p_sealed_session,
      expires_at = clock_timestamp() + interval '60 seconds'
  FROM auth.sessions s, public.user_info ui
  WHERE a.challenge_id = p_id AND a.origin = p_origin AND a.verifying AND a.session_id IS NULL
    AND a.expires_at > clock_timestamp()
    AND s.id = p_session AND s.user_id = p_user AND ui.id = p_user AND ui.organization = a.organization
    AND NOT EXISTS (SELECT FROM public.account_mfa_recovery_holds h WHERE h.user_id = p_user)
    AND public.resolve_mfa_channel_policy_v1(a.client_id, a.organization, a.origin, a.redirect_uri)
          ->'methods'->'passkey' @> jsonb_build_object('signIn', true, 'signInRevision', a.sign_in_revision);
  RETURN FOUND;
END $$;

CREATE OR REPLACE FUNCTION public.exchange_passkey_sign_in_v1(
  p_client_id text, p_organization bigint, p_origin text, p_code_hash text, p_code_challenge text
)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_sealed text; v_session uuid;
BEGIN
  PERFORM public.require_service_role();
  DELETE FROM public.account_passkey_sign_in_attempts a
  USING auth.sessions s, public.user_info ui
  WHERE a.client_id = p_client_id AND a.organization = p_organization AND a.origin = p_origin
    AND a.code_hash = p_code_hash AND a.code_challenge = p_code_challenge
    AND a.expires_at > clock_timestamp() AND a.session_id = s.id
    AND s.user_id = ui.id AND ui.organization = a.organization
    AND s.aal::text = 'aal1' AND s.oauth_client_id IS NULL
    AND (s.not_after IS NULL OR s.not_after > clock_timestamp())
    AND EXISTS (
      SELECT FROM auth.mfa_amr_claims amr WHERE amr.session_id = s.id
        AND amr.authentication_method = 'passkey'
    )
    AND NOT EXISTS (SELECT FROM public.account_mfa_recovery_holds h WHERE h.user_id = s.user_id)
    AND public.resolve_mfa_channel_policy_v1(a.client_id, a.organization, a.origin, a.redirect_uri)
          ->'methods'->'passkey' @> jsonb_build_object('signIn', true, 'signInRevision', a.sign_in_revision)
  RETURNING a.sealed_session, s.id INTO v_sealed, v_session;
  IF v_session IS NOT NULL THEN
    INSERT INTO public.account_passkey_primary_proofs(session_id, organization) VALUES (v_session, p_organization);
  END IF;
  RETURN v_sealed;
END $$;

REVOKE ALL ON FUNCTION public.get_passkey_sign_in_actor_v1(bigint)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_passkey_sign_in_actor_v1(bigint) TO authenticated;
REVOKE ALL ON FUNCTION
  public.issue_passkey_sign_in_v1(uuid,text,bigint,text,text,bigint,text),
  public.reserve_passkey_sign_in_v1(uuid,text),
  public.complete_passkey_sign_in_v1(uuid,text,uuid,uuid,text,text),
  public.exchange_passkey_sign_in_v1(text,bigint,text,text,text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION
  public.issue_passkey_sign_in_v1(uuid,text,bigint,text,text,bigint,text),
  public.reserve_passkey_sign_in_v1(uuid,text),
  public.complete_passkey_sign_in_v1(uuid,text,uuid,uuid,text,text),
  public.exchange_passkey_sign_in_v1(text,bigint,text,text,text)
  TO service_role;
