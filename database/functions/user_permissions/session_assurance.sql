-- A hold survives removal of every factor and is independent of a session.
-- The database owner retains access until a scoped support workflow owns it.
CREATE TABLE IF NOT EXISTS public.account_mfa_recovery_holds (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  started_at timestamptz NOT NULL DEFAULT statement_timestamp()
);
ALTER TABLE public.account_mfa_recovery_holds ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_mfa_recovery_holds FROM PUBLIC, anon, authenticated, service_role;

-- Bound to the live Auth session and written only by a successful broker exchange.
CREATE TABLE IF NOT EXISTS public.account_passkey_primary_proofs (
  session_id uuid PRIMARY KEY REFERENCES auth.sessions(id) ON DELETE CASCADE,
  organization bigint NOT NULL
);
ALTER TABLE public.account_passkey_primary_proofs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_passkey_primary_proofs FROM PUBLIC, anon, authenticated, service_role;

-- Input claims come from the authenticated database request context.
-- p_organization optionally constrains the account tenant resolved from the
-- profile. Resource operations authorize their target scope independently.
CREATE OR REPLACE FUNCTION public.get_account_assurance_v1(
  p_organization bigint DEFAULT NULL,
  p_account_security boolean DEFAULT false
)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_jwt jsonb := auth.jwt();
  v_session auth.sessions%rowtype;
  v_aal text := v_jwt->>'aal';
  v_now timestamptz := statement_timestamp();
  v_epoch bigint := floor(extract(epoch FROM v_now));
  v_amr jsonb := v_jwt->'amr';
  v_method text;
  v_proof_at bigint;
  v_brokered_passkey boolean := false;
BEGIN
  IF p_account_security IS NULL
    OR v_jwt->>'role' IS DISTINCT FROM 'authenticated'
    OR v_jwt->'is_anonymous' = 'true'::jsonb
    OR coalesce(v_jwt->>'sub','') !~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
    OR coalesce(v_jwt->>'session_id','') !~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
    OR coalesce(v_jwt->>'exp','') !~ '^[0-9]{1,12}$'
    OR v_aal IS NULL OR v_aal NOT IN ('aal1','aal2') THEN
    RETURN 'invalid_session';
  END IF;
  IF (v_jwt->>'exp')::bigint <= v_epoch THEN
    RETURN 'invalid_session';
  END IF;

  SELECT s.* INTO v_session
  FROM auth.sessions s
  JOIN auth.users u ON u.id = s.user_id
  JOIN public.user_info ui ON ui.id = s.user_id
  WHERE s.id = (v_jwt->>'session_id')::uuid
    AND s.user_id = (v_jwt->>'sub')::uuid
    AND (p_organization IS NULL OR ui.organization = p_organization)
    AND u.deleted_at IS NULL AND NOT u.is_anonymous AND (u.banned_until IS NULL OR u.banned_until <= v_now)
    AND (s.not_after IS NULL OR s.not_after > v_now);
  IF NOT FOUND THEN
    RETURN 'invalid_session';
  END IF;
  IF EXISTS (SELECT FROM public.account_mfa_factor_removals WHERE user_id = v_session.user_id) THEN
    RETURN 'factor_change_pending';
  END IF;
  IF EXISTS (SELECT FROM public.account_mfa_recovery_holds h WHERE h.user_id = v_session.user_id) THEN
    RETURN 'account_recovery';
  END IF;

  IF (v_aal = 'aal1' OR p_account_security)
    AND v_amr @> '[{"method":"passkey"}]'::jsonb THEN
    SELECT EXISTS (
      SELECT FROM public.account_passkey_primary_proofs proof
      JOIN public.user_info profile ON profile.id = v_session.user_id AND profile.organization = proof.organization
      WHERE proof.session_id = v_session.id
    ) INTO v_brokered_passkey;
  END IF;

  -- The broker checks signed WebAuthn user verification and completes a bound
  -- exchange before recording this proof. GoTrue still labels this session AAL1.
  IF v_brokered_passkey AND v_aal = 'aal1' AND v_session.aal::text = 'aal1'
    AND v_session.oauth_client_id IS NULL THEN
    v_method := 'passkey';
  ELSIF NOT EXISTS (
    SELECT FROM auth.mfa_factors f WHERE f.user_id = v_session.user_id
      AND f.status = 'verified' AND f.factor_type IN ('totp','phone','webauthn')
  ) THEN
    -- Also closes recovery-code AAL2 and signed AAL2 left over after removal.
    IF v_aal <> 'aal1' OR v_session.aal::text IS DISTINCT FROM 'aal1' THEN
      RETURN 'invalid_session';
    END IF;
    IF NOT p_account_security THEN
      RETURN 'allowed';
    END IF;
    -- OTP also represents reset and internal session minting. The fallback
    -- for account security requires a recent password proof.
    v_method := 'password';
  ELSE
    IF v_aal <> 'aal2' OR v_session.aal::text IS DISTINCT FROM 'aal2' THEN
      RETURN 'mfa_required';
    END IF;
    SELECT CASE f.factor_type
      WHEN 'totp' THEN 'totp'
      WHEN 'phone' THEN 'mfa/phone'
      WHEN 'webauthn' THEN 'mfa/webauthn'
    END INTO v_method
    FROM auth.mfa_factors f
    WHERE f.id = v_session.factor_id AND f.user_id = v_session.user_id AND f.status = 'verified';
    IF v_method IS NULL THEN
      RETURN 'mfa_required';
    END IF;
  END IF;
  IF jsonb_typeof(v_amr) IS DISTINCT FROM 'array' THEN
    RETURN 'proof_required';
  END IF;

  SELECT max(least(
    CASE WHEN claim->>'timestamp' ~ '^[0-9]{1,12}$' THEN (claim->>'timestamp')::bigint END,
    floor(extract(epoch FROM live.updated_at))::bigint
  )) INTO v_proof_at
  FROM auth.mfa_amr_claims live
  CROSS JOIN jsonb_array_elements(v_amr) claim
  WHERE live.session_id = v_session.id
    AND live.authentication_method = v_method
    AND live.updated_at IS NOT NULL AND live.updated_at <= v_now
    AND claim->>'method' = v_method
    AND CASE WHEN claim->>'timestamp' ~ '^[0-9]{1,12}$'
      THEN (claim->>'timestamp')::bigint BETWEEN 1 AND v_epoch END;
  IF v_proof_at IS NULL THEN
    RETURN 'proof_required';
  END IF;
  IF p_account_security AND (v_epoch - v_proof_at > 300 OR v_session.oauth_client_id IS NOT NULL) THEN
    RETURN 'proof_required';
  END IF;
  -- A delegating issuer uses an OTP session with a second factor. The OTP
  -- alone cannot distinguish delegation, Google, QR or email recovery.
  -- Require an explicit identifiable primary method until a broker can write
  -- the session-purpose record for these flows.
  IF p_account_security AND NOT EXISTS (
    SELECT FROM jsonb_array_elements(v_amr) claim
    JOIN auth.mfa_amr_claims live ON live.session_id = v_session.id
      AND live.authentication_method = claim->>'method'
    WHERE claim->>'method' = 'password' OR (claim->>'method' = 'passkey' AND v_brokered_passkey)
  ) THEN
    RETURN 'proof_required';
  END IF;
  RETURN 'allowed';
END $$;

REVOKE ALL ON FUNCTION public.get_account_assurance_v1(bigint,boolean) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_account_assurance_v1(bigint,boolean) TO authenticated;

-- PostgREST evaluates this once as the verified request role before executing
-- a resource query, mutation or definer RPC. Auth itself has a separate ingress.
CREATE OR REPLACE FUNCTION public.enforce_account_assurance_request_v1()
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, extensions AS $$
DECLARE
  v_decision text;
  v_headers jsonb;
BEGIN
  IF current_user <> 'authenticated' THEN
    RETURN;
  END IF;
  IF current_setting('request.path',true) IN (
    '/rpc/get_account_assurance_v1', '/rpc/can_use_existing_mfa_factor_v1',
    '/rpc/get_passkey_sign_in_actor_v1', '/rpc/get_mfa_recovery_registration_actor_v1'
  ) THEN
    v_headers := nullif(current_setting('request.headers',true),'')::jsonb;
    IF coalesce(v_headers->>'content-profile','public') = 'public'
      AND coalesce(v_headers->>'accept-profile','public') = 'public' THEN
      RETURN;
    END IF;
  END IF;
  v_decision := public.get_account_assurance_v1();
  IF v_decision IS DISTINCT FROM 'allowed' THEN
    RAISE insufficient_privilege USING MESSAGE = v_decision;
  END IF;
END $$;

-- Keep the measurement hook available to installations already using it.
CREATE OR REPLACE FUNCTION public.enforce_account_assurance_and_observe_v1()
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, extensions AS $$
BEGIN
  PERFORM public.enforce_account_assurance_request_v1();
  PERFORM public.log_canonical_mutation_request_v1();
END $$;

REVOKE ALL ON FUNCTION public.enforce_account_assurance_request_v1(),
  public.enforce_account_assurance_and_observe_v1() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enforce_account_assurance_request_v1(),
  public.enforce_account_assurance_and_observe_v1() TO anon, authenticated, service_role;
