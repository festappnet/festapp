CREATE TABLE IF NOT EXISTS public.account_mfa_registration_handoffs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id uuid NOT NULL REFERENCES auth.sessions(id) ON DELETE CASCADE,
  client_id text NOT NULL REFERENCES public.external_login_clients(client_id) ON DELETE CASCADE,
  organization bigint NOT NULL,
  origin text NOT NULL,
  redirect_uri text NOT NULL,
  method text NOT NULL CHECK (method IN ('totp', 'webauthn', 'passkey')),
  code_hash text NOT NULL UNIQUE CHECK (code_hash ~ '^[0-9a-f]{64}$'),
  registration_revision bigint NOT NULL,
  challenge text NOT NULL CHECK (challenge ~ '^[A-Za-z0-9_-]{43}$'),
  expires_at timestamptz NOT NULL,
  claimed_at timestamptz,
  enrollment_started_at timestamptz,
  factor_id uuid,
  provider_challenge_id uuid,
  recovery_case_id uuid,
  verifying boolean NOT NULL DEFAULT false,
  verified_at timestamptz,
  UNIQUE (session_id, method)
);
ALTER TABLE public.account_mfa_registration_handoffs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_mfa_registration_handoffs FROM PUBLIC, anon, authenticated, service_role;

-- Called with the original user token through PostgREST. Keep the identity
-- and session proof together so the broker never needs to read unsigned JWTs.
CREATE OR REPLACE FUNCTION public.get_mfa_registration_actor_v1(p_organization bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = public, extensions AS $$
DECLARE v_decision text;
BEGIN
  v_decision := public.get_account_assurance_v1(p_organization, true);
  IF v_decision IS DISTINCT FROM 'allowed' THEN
    RETURN jsonb_build_object('decision', v_decision);
  END IF;
  RETURN jsonb_build_object('decision', 'allowed', 'userId', auth.uid(), 'sessionId', auth.jwt()->>'session_id',
    'passwordProven', auth.jwt()->'amr' @> '[{"method":"password"}]'::jsonb);
END $$;

CREATE OR REPLACE FUNCTION public.issue_mfa_registration_handoff_v1(
  p_user uuid, p_session uuid, p_client_id text, p_organization bigint,
  p_origin text, p_redirect_uri text, p_method text, p_code_hash text, p_challenge text, p_recovery_hash text DEFAULT NULL
)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_policy jsonb; v_id uuid; v_recovery uuid;
BEGIN
  PERFORM public.require_service_role();
  IF p_method IS NULL OR p_method NOT IN ('totp', 'webauthn', 'passkey') THEN
    RETURN false;
  END IF;
  IF p_recovery_hash IS NOT NULL THEN
    IF p_method NOT IN ('totp', 'webauthn') THEN RETURN false; END IF;
    SELECT case_id INTO v_recovery FROM public.account_mfa_recovery_holds
    WHERE user_id = p_user AND organization = p_organization
      AND sessions_revoked_at IS NOT NULL AND replacement_session_id IS NULL
      AND replacement_code_hash = p_recovery_hash AND replacement_expires_at > clock_timestamp()
    FOR UPDATE;
    IF v_recovery IS NULL THEN RETURN false; END IF;
  ELSIF EXISTS (SELECT FROM public.account_mfa_recovery_holds WHERE user_id = p_user) THEN
    RETURN false;
  END IF;
  v_policy := public.resolve_mfa_channel_policy_v1(p_client_id, p_organization, p_origin, p_redirect_uri);
  IF v_policy->'methods'->p_method->'registration' IS DISTINCT FROM 'true'::jsonb
    OR NOT EXISTS (
      SELECT FROM auth.sessions session
      JOIN public.user_info profile ON profile.id = session.user_id
      WHERE session.id = p_session AND session.user_id = p_user
        AND profile.organization = p_organization
        AND (session.not_after IS NULL OR session.not_after > clock_timestamp())
    ) THEN
    RETURN false;
  END IF;
  INSERT INTO public.account_mfa_registration_handoffs (
    user_id, session_id, client_id, organization, origin, redirect_uri,
    method, code_hash, registration_revision, challenge, expires_at, recovery_case_id
  ) VALUES (
    p_user, p_session, p_client_id, p_organization, p_origin, p_redirect_uri,
    p_method, p_code_hash, (v_policy->'methods'->p_method->>'registrationRevision')::bigint,
    p_challenge, clock_timestamp() + interval '90 seconds', v_recovery
  )
  ON CONFLICT (session_id, method) DO UPDATE SET
    id = gen_random_uuid(),
    client_id = excluded.client_id,
    organization = excluded.organization,
    origin = excluded.origin,
    redirect_uri = excluded.redirect_uri,
    code_hash = excluded.code_hash,
    registration_revision = excluded.registration_revision,
    challenge = excluded.challenge,
    expires_at = excluded.expires_at,
    claimed_at = NULL,
    enrollment_started_at = NULL,
    factor_id = NULL,
    provider_challenge_id = NULL,
    recovery_case_id = excluded.recovery_case_id,
    verifying = false,
    verified_at = NULL
  WHERE account_mfa_registration_handoffs.expires_at <= clock_timestamp()
  RETURNING id INTO v_id;
  IF v_id IS NOT NULL AND v_recovery IS NOT NULL THEN
    UPDATE public.account_mfa_recovery_holds SET replacement_code_hash = NULL, replacement_session_id = p_session
    WHERE case_id = v_recovery;
  END IF;
  RETURN v_id IS NOT NULL;
END $$;

CREATE OR REPLACE FUNCTION public.claim_mfa_registration_handoff_v1(
  p_user uuid, p_session uuid, p_organization bigint, p_origin text,
  p_code_hash text, p_challenge text, p_recovery boolean DEFAULT false
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_id uuid; v_method text;
BEGIN
  PERFORM public.require_service_role();
  UPDATE public.account_mfa_registration_handoffs handoff
  SET claimed_at = clock_timestamp(), expires_at = clock_timestamp() + interval '5 minutes'
  WHERE handoff.code_hash = p_code_hash AND handoff.challenge = p_challenge
    AND handoff.user_id = p_user AND handoff.session_id = p_session
    AND handoff.organization = p_organization AND handoff.origin = p_origin
    AND handoff.claimed_at IS NULL AND handoff.expires_at > clock_timestamp()
    AND public.resolve_mfa_channel_policy_v1(handoff.client_id, handoff.organization, handoff.origin, handoff.redirect_uri)
          ->'methods'->handoff.method @> jsonb_build_object(
            'registration', true, 'registrationRevision', handoff.registration_revision)
    AND CASE WHEN p_recovery THEN EXISTS (
      SELECT FROM public.account_mfa_recovery_holds h
      WHERE h.user_id = p_user AND h.case_id = handoff.recovery_case_id
        AND h.replacement_session_id = p_session AND h.replacement_expires_at > clock_timestamp()
    ) ELSE handoff.recovery_case_id IS NULL
      AND NOT EXISTS (SELECT FROM public.account_mfa_recovery_holds WHERE user_id = p_user)
    END
  RETURNING id, method INTO v_id, v_method;
  IF v_id IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN jsonb_build_object('id', v_id, 'method', v_method);
END $$;

REVOKE ALL ON FUNCTION public.get_mfa_registration_actor_v1(bigint)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_mfa_registration_actor_v1(bigint) TO authenticated;
REVOKE ALL ON FUNCTION public.issue_mfa_registration_handoff_v1(uuid,uuid,text,bigint,text,text,text,text,text,text),
  public.claim_mfa_registration_handoff_v1(uuid,uuid,bigint,text,text,text,boolean)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.issue_mfa_registration_handoff_v1(uuid,uuid,text,bigint,text,text,text,text,text,text),
  public.claim_mfa_registration_handoff_v1(uuid,uuid,bigint,text,text,text,boolean) TO service_role;
