-- Add account-level assurance based on live GoTrue state and a durable recovery hold.

-- SOURCE: user_permissions/session_assurance.sql
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

  IF p_account_security THEN
    SELECT EXISTS (
      SELECT FROM public.account_passkey_primary_proofs proof
      JOIN public.user_info profile ON profile.id = v_session.user_id AND profile.organization = proof.organization
      WHERE proof.session_id = v_session.id
    ) INTO v_brokered_passkey;
  END IF;

  IF NOT EXISTS (
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
    -- OTP also represents reset and internal session minting. Only password and
    -- passkey sign-in with a completed broker exchange carry a known purpose.
    v_method := CASE WHEN v_brokered_passkey THEN 'passkey' ELSE 'password' END;
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

-- SOURCE: user_permissions/account_mfa_channel_policy.sql
-- Reuse the provisioned client/tenant/callback registry independently of
-- Google enablement. Platform labels describe the registered return channel.
CREATE TABLE IF NOT EXISTS public.account_mfa_channel_methods (
  client_id text NOT NULL REFERENCES public.external_login_clients(client_id) ON DELETE CASCADE,
  method text NOT NULL CHECK (method IN ('totp', 'webauthn', 'passkey')),
  offer_enabled boolean NOT NULL DEFAULT false,
  registration_enabled boolean NOT NULL DEFAULT false,
  sign_in_enabled boolean NOT NULL DEFAULT false,
  registration_revision bigint NOT NULL DEFAULT 1,
  sign_in_revision bigint NOT NULL DEFAULT 1,
  PRIMARY KEY (client_id, method),
  CHECK (method = 'passkey' OR NOT sign_in_enabled)
);
ALTER TABLE public.account_mfa_channel_methods ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_mfa_channel_methods FROM PUBLIC, anon, authenticated, service_role;

-- Only the broker reads the policy. A resolved row describes an exact return
-- channel. It does not attest the browser, installed app, or current actor.
CREATE OR REPLACE FUNCTION public.resolve_mfa_channel_policy_v1(
  p_client_id text,
  p_organization bigint,
  p_origin text,
  p_redirect_uri text
)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_policy jsonb;
BEGIN
  PERFORM public.require_service_role();
  SELECT jsonb_build_object(
    'clientId', client.client_id,
    'organization', client.organization,
    'platform', client.platform,
    'origin', client.origin,
    'redirectUri', client.redirect_uri,
    'methods', (
      SELECT jsonb_object_agg(method.key, jsonb_build_object(
        'offer', coalesce(policy.offer_enabled, false),
        'registration', coalesce(policy.registration_enabled, false),
        'signIn', coalesce(policy.sign_in_enabled, false),
        'registrationRevision', coalesce(policy.registration_revision, 0),
        'signInRevision', coalesce(policy.sign_in_revision, 0)))
      FROM (VALUES ('totp'), ('webauthn'), ('passkey')) method(key)
      LEFT JOIN public.account_mfa_channel_methods policy
        ON policy.client_id = client.client_id AND policy.method = method.key
    )
  ) INTO v_policy
  FROM public.external_login_clients client
  WHERE client.provisioned AND client.client_id = p_client_id
    AND client.organization = p_organization
    AND client.origin = p_origin AND client.redirect_uri = p_redirect_uri;
  RETURN v_policy;
END $$;

REVOKE ALL ON FUNCTION public.resolve_mfa_channel_policy_v1(text,bigint,text,text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.resolve_mfa_channel_policy_v1(text,bigint,text,text) TO service_role;


-- Operational owner for method toggles. A restart must never revive a receipt
-- issued before a disable/re-enable sequence.
CREATE OR REPLACE FUNCTION public.set_mfa_channel_method_v1(
  p_client_id text, p_method text, p_offer boolean, p_registration boolean, p_sign_in boolean
)
RETURNS void LANGUAGE sql SECURITY INVOKER
SET search_path = public, extensions AS $$
  INSERT INTO public.account_mfa_channel_methods (
    client_id, method, offer_enabled, registration_enabled, sign_in_enabled
  ) VALUES (p_client_id, p_method, p_offer, p_registration, p_sign_in)
  ON CONFLICT (client_id, method) DO UPDATE SET
    offer_enabled = excluded.offer_enabled,
    registration_enabled = excluded.registration_enabled,
    sign_in_enabled = excluded.sign_in_enabled,
    registration_revision = account_mfa_channel_methods.registration_revision
      + (account_mfa_channel_methods.registration_enabled IS DISTINCT FROM excluded.registration_enabled)::int,
    sign_in_revision = account_mfa_channel_methods.sign_in_revision
      + (account_mfa_channel_methods.sign_in_enabled IS DISTINCT FROM excluded.sign_in_enabled)::int;
$$;

REVOKE ALL ON FUNCTION public.set_mfa_channel_method_v1(text,text,boolean,boolean,boolean)
  FROM PUBLIC, anon, authenticated, service_role;

-- SOURCE: user_permissions/account_mfa_registration_handoff.sql
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

-- SOURCE: user_permissions/account_mfa_factor_registration.sql
CREATE OR REPLACE FUNCTION public.queue_account_security_enrollment_notice_v1(
  p_receipt uuid, p_user uuid, p_organization bigint
)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, extensions AS $$
DECLARE
  v_recipient text := public.get_user_delivery_email(p_user);
  v_message jsonb;
BEGIN
  IF v_recipient IS NULL THEN RETURN; END IF;
  v_message := public.enqueue_email('custom', jsonb_build_object('organization', p_organization),
    v_recipient, jsonb_build_object('lang', coalesce(
      (SELECT data->>'DEFAULT_LANGUAGE' FROM public.organizations WHERE id = p_organization), 'cs')),
    'mfa-enrollment:' || p_receipt::text, 'ACCOUNT_MFA_METHOD_ADDED');
  UPDATE public.email_messages SET tracking_policy = 'disabled'
  WHERE message_id = (v_message->>'message_id')::uuid;
END $$;

REVOKE ALL ON FUNCTION public.queue_account_security_enrollment_notice_v1(uuid,uuid,bigint)
  FROM PUBLIC, anon, authenticated, service_role;

-- Service-only state transition for a brokered enrollment. The broker gets
-- p_user and p_session from the original signed, fresh actor request.
CREATE OR REPLACE FUNCTION public.advance_mfa_factor_registration_v1(
  p_receipt uuid, p_user uuid, p_session uuid, p_origin text,
  p_method text, p_operation text, p_factor uuid DEFAULT NULL, p_recovery boolean DEFAULT false
)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE handoff public.account_mfa_registration_handoffs%rowtype;
BEGIN
  PERFORM public.require_service_role();
  IF p_method IS NULL OR p_method NOT IN ('totp', 'webauthn') THEN
    RETURN false;
  END IF;
  SELECT * INTO handoff FROM public.account_mfa_registration_handoffs
  WHERE id = p_receipt AND user_id = p_user AND session_id = p_session
    AND origin = p_origin AND method = p_method AND claimed_at IS NOT NULL
    AND expires_at > clock_timestamp() AND verified_at IS NULL
  FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  IF p_recovery THEN
    IF NOT EXISTS (
      SELECT FROM public.account_mfa_recovery_holds h
      WHERE h.user_id = p_user AND h.case_id = handoff.recovery_case_id
        AND h.replacement_session_id = p_session AND h.replacement_expires_at > clock_timestamp()
    ) THEN RETURN false; END IF;
  ELSIF handoff.recovery_case_id IS NOT NULL OR EXISTS (
    SELECT FROM public.account_mfa_recovery_holds WHERE user_id = p_user
  ) THEN RETURN false;
  END IF;
  IF p_operation IN ('enroll', 'challenge', 'verify')
    AND public.resolve_mfa_channel_policy_v1(handoff.client_id, handoff.organization, handoff.origin, handoff.redirect_uri)
          ->'methods'->p_method @> jsonb_build_object(
            'registration', true, 'registrationRevision', handoff.registration_revision) IS DISTINCT FROM true THEN
    RETURN false;
  END IF;

  CASE p_operation
    WHEN 'enroll' THEN
      IF handoff.enrollment_started_at IS NOT NULL THEN RETURN false; END IF;
      UPDATE public.account_mfa_registration_handoffs SET enrollment_started_at = clock_timestamp()
      WHERE id = handoff.id;
    WHEN 'bind' THEN
      IF handoff.enrollment_started_at IS NULL OR handoff.factor_id IS NOT NULL OR NOT EXISTS (
        SELECT FROM auth.mfa_factors WHERE id = p_factor AND user_id = p_user
          AND factor_type::text = p_method AND status = 'unverified'
      ) THEN RETURN false; END IF;
      UPDATE public.account_mfa_registration_handoffs SET factor_id = p_factor WHERE id = handoff.id;
    WHEN 'challenge', 'verify' THEN
      IF p_factor IS NULL OR handoff.factor_id IS DISTINCT FROM p_factor OR handoff.verifying OR NOT EXISTS (
        SELECT FROM auth.mfa_factors WHERE id = p_factor AND user_id = p_user
          AND factor_type::text = p_method AND status = 'unverified'
      ) THEN RETURN false; END IF;
      IF p_operation = 'verify' THEN
        UPDATE public.account_mfa_registration_handoffs SET verifying = true WHERE id = handoff.id;
      END IF;
    WHEN 'retry' THEN
      IF handoff.factor_id IS DISTINCT FROM p_factor OR NOT handoff.verifying OR NOT EXISTS (
        SELECT FROM auth.mfa_factors WHERE id = p_factor AND user_id = p_user
          AND factor_type::text = p_method AND status = 'unverified'
      ) THEN RETURN false; END IF;
      UPDATE public.account_mfa_registration_handoffs SET verifying = false WHERE id = handoff.id;
    WHEN 'finish' THEN
      IF handoff.factor_id IS DISTINCT FROM p_factor OR NOT handoff.verifying OR NOT EXISTS (
        SELECT FROM auth.mfa_factors WHERE id = p_factor AND user_id = p_user
          AND factor_type::text = p_method AND status = 'verified'
      ) THEN RETURN false; END IF;
      UPDATE public.account_mfa_registration_handoffs SET verifying = false, verified_at = clock_timestamp()
      WHERE id = handoff.id;
      PERFORM public.queue_account_security_enrollment_notice_v1(handoff.id, p_user, handoff.organization);
    ELSE
      RETURN false;
  END CASE;
  RETURN true;
END $$;

REVOKE ALL ON FUNCTION public.advance_mfa_factor_registration_v1(uuid,uuid,uuid,text,text,text,uuid,boolean)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.advance_mfa_factor_registration_v1(uuid,uuid,uuid,text,text,text,uuid,boolean) TO service_role;

-- SOURCE: user_permissions/account_mfa_factor_removal.sql
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

-- SOURCE: user_permissions/account_passkey_registration.sql
-- GoTrue owns challenge creation, consumption and credential storage. The
-- broker ties those operations to the signed actor and one registered channel.
CREATE OR REPLACE FUNCTION public.advance_passkey_registration_v1(
  p_receipt uuid, p_user uuid, p_session uuid, p_origin text,
  p_operation text, p_challenge uuid DEFAULT NULL, p_credential uuid DEFAULT NULL
)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE handoff public.account_mfa_registration_handoffs%rowtype;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO handoff FROM public.account_mfa_registration_handoffs
  WHERE id = p_receipt AND user_id = p_user AND session_id = p_session
    AND origin = p_origin AND method = 'passkey' AND claimed_at IS NOT NULL
    AND expires_at > clock_timestamp() AND verified_at IS NULL
  FOR UPDATE;
  IF NOT FOUND OR EXISTS (SELECT FROM public.account_mfa_recovery_holds WHERE user_id = p_user) THEN
    RETURN false;
  END IF;
  IF p_operation IN ('options', 'bind', 'verify')
    AND public.resolve_mfa_channel_policy_v1(handoff.client_id, handoff.organization, handoff.origin, handoff.redirect_uri)
          ->'methods'->'passkey' @> jsonb_build_object(
            'registration', true, 'registrationRevision', handoff.registration_revision) IS DISTINCT FROM true THEN
    RETURN false;
  END IF;

  CASE p_operation
    WHEN 'options' THEN
      IF handoff.enrollment_started_at IS NOT NULL THEN RETURN false; END IF;
      UPDATE public.account_mfa_registration_handoffs SET enrollment_started_at = clock_timestamp()
      WHERE id = handoff.id;
    WHEN 'bind' THEN
      IF p_challenge IS NULL OR handoff.enrollment_started_at IS NULL
        OR handoff.provider_challenge_id IS NOT NULL THEN RETURN false; END IF;
      UPDATE public.account_mfa_registration_handoffs SET provider_challenge_id = p_challenge
      WHERE id = handoff.id;
    WHEN 'verify' THEN
      IF p_challenge IS NULL OR handoff.provider_challenge_id IS DISTINCT FROM p_challenge
        OR handoff.verifying THEN RETURN false; END IF;
      UPDATE public.account_mfa_registration_handoffs SET verifying = true WHERE id = handoff.id;
    WHEN 'finish' THEN
      IF p_challenge IS NULL OR handoff.provider_challenge_id IS DISTINCT FROM p_challenge
        OR NOT handoff.verifying OR NOT EXISTS (
          SELECT FROM auth.webauthn_credentials WHERE id = p_credential AND user_id = p_user
        ) THEN RETURN false; END IF;
      UPDATE public.account_mfa_registration_handoffs SET verifying = false, verified_at = clock_timestamp()
      WHERE id = handoff.id;
      PERFORM public.queue_account_security_enrollment_notice_v1(handoff.id, p_user, handoff.organization);
    ELSE
      RETURN false;
  END CASE;
  RETURN true;
END $$;

REVOKE ALL ON FUNCTION public.advance_passkey_registration_v1(uuid,uuid,uuid,text,text,uuid,uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.advance_passkey_registration_v1(uuid,uuid,uuid,text,text,uuid,uuid) TO service_role;

-- SOURCE: user_permissions/account_passkey_sign_in.sql
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

-- SOURCE: user_permissions/account_mfa_recovery.sql
-- These commands are owned by the database operator. Approval IDs refer to
-- separately verified support evidence, never to documents or credentials.
ALTER TABLE public.account_mfa_recovery_holds
  ADD COLUMN IF NOT EXISTS case_id uuid UNIQUE,
  ADD COLUMN IF NOT EXISTS organization bigint,
  ADD COLUMN IF NOT EXISTS dual_approval boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS notice_id uuid,
  ADD COLUMN IF NOT EXISTS sessions_revoked_at timestamptz,
  ADD COLUMN IF NOT EXISTS replacement_code_hash text,
  ADD COLUMN IF NOT EXISTS replacement_expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS replacement_session_id uuid;

CREATE TABLE IF NOT EXISTS public.account_mfa_recovery_approvals (
  case_id uuid NOT NULL REFERENCES public.account_mfa_recovery_holds(case_id) ON DELETE CASCADE,
  reviewer uuid NOT NULL,
  evidence_id uuid NOT NULL,
  approved_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (case_id, reviewer),
  UNIQUE (case_id, evidence_id)
);
ALTER TABLE public.account_mfa_recovery_approvals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_mfa_recovery_approvals FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.account_recovery_needs_two_approvals_v1(p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, extensions AS $$
  SELECT EXISTS (SELECT FROM public.organization_users WHERE "user" = p_user AND is_admin)
    OR EXISTS (
      SELECT FROM public.unit_users m WHERE m."user" = p_user AND
        public.unit_discovery_rule(m.is_editor, m.is_manager, m.is_editor_view)
    ) OR EXISTS (
      SELECT FROM public.occasion_users m WHERE m."user" = p_user AND
        public.occasion_staff_navigation_rule(m.is_manager, m.is_editor, m.is_editor_view,
          m.is_editor_order, m.is_editor_order_view)
    );
$$;

CREATE OR REPLACE FUNCTION public.begin_account_mfa_recovery_v1(
  p_user uuid, p_organization bigint, p_case uuid
)
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, extensions AS $$
DECLARE
  v_hold public.account_mfa_recovery_holds%rowtype;
  v_recipient text;
  v_notice jsonb;
BEGIN
  IF p_case IS NULL OR NOT EXISTS (
    SELECT FROM public.user_info ui JOIN auth.users u ON u.id = ui.id
    WHERE ui.id = p_user AND ui.organization = p_organization AND u.deleted_at IS NULL AND NOT u.is_anonymous
  ) THEN RAISE EXCEPTION 'invalid_recovery_scope'; END IF;

  INSERT INTO public.account_mfa_recovery_holds (user_id, case_id, organization, dual_approval)
  VALUES (p_user, p_case, p_organization, public.account_recovery_needs_two_approvals_v1(p_user))
  ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO v_hold FROM public.account_mfa_recovery_holds WHERE user_id = p_user FOR UPDATE;
  IF v_hold.case_id IS DISTINCT FROM p_case OR v_hold.organization IS DISTINCT FROM p_organization THEN
    RAISE EXCEPTION 'recovery_already_open';
  END IF;
  IF EXISTS (SELECT FROM public.account_mfa_recovery_completions WHERE case_id = p_case) THEN
    RAISE EXCEPTION 'invalid_recovery_scope';
  END IF;
  IF v_hold.notice_id IS NOT NULL THEN RETURN v_hold.notice_id; END IF;

  v_recipient := public.get_user_delivery_email(p_user);
  IF v_recipient IS NULL THEN RAISE EXCEPTION 'recovery_contact_unavailable'; END IF;
  v_notice := public.enqueue_email('custom', jsonb_build_object('organization', p_organization),
    v_recipient, jsonb_build_object('lang', coalesce(
      (SELECT data->>'DEFAULT_LANGUAGE' FROM public.organizations WHERE id = p_organization), 'cs')),
    'mfa-recovery-start:' || p_case::text, 'ACCOUNT_MFA_RECOVERY_STARTED');
  UPDATE public.email_messages SET tracking_policy = 'disabled'
  WHERE message_id = (v_notice->>'message_id')::uuid;
  UPDATE public.account_mfa_recovery_holds SET notice_id = (v_notice->>'message_id')::uuid
  WHERE user_id = p_user RETURNING notice_id INTO v_hold.notice_id;
  RETURN v_hold.notice_id;
END $$;

CREATE OR REPLACE FUNCTION public.approve_account_mfa_recovery_v1(
  p_case uuid, p_reviewer uuid, p_evidence uuid
)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, extensions AS $$
DECLARE v_hold public.account_mfa_recovery_holds%rowtype;
BEGIN
  SELECT * INTO v_hold FROM public.account_mfa_recovery_holds
  WHERE case_id = p_case AND notice_id IS NOT NULL FOR UPDATE;
  IF NOT FOUND OR p_reviewer IS NULL OR p_evidence IS NULL OR p_reviewer = v_hold.user_id
    OR NOT EXISTS (SELECT FROM auth.users WHERE id = p_reviewer AND deleted_at IS NULL AND NOT is_anonymous) THEN
    RETURN false;
  END IF;
  INSERT INTO public.account_mfa_recovery_approvals(case_id, reviewer, evidence_id)
  VALUES (p_case, p_reviewer, p_evidence)
  ON CONFLICT DO NOTHING;
  RETURN EXISTS (SELECT FROM public.account_mfa_recovery_approvals
    WHERE case_id = p_case AND reviewer = p_reviewer AND evidence_id = p_evidence);
END $$;

-- This transaction starts only after the durable hold has committed. Retry
-- also removes sessions opened during the interruption and scanner grants
-- derived from this user. Secret-only and other users' grants are independent.
CREATE OR REPLACE FUNCTION public.revoke_account_mfa_recovery_sessions_v1(p_case uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, extensions AS $$
DECLARE
  v_hold public.account_mfa_recovery_holds%rowtype;
  v_required integer;

BEGIN
  SELECT * INTO v_hold FROM public.account_mfa_recovery_holds
  WHERE case_id = p_case AND notice_id IS NOT NULL FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;
  v_required := CASE WHEN v_hold.dual_approval OR public.account_recovery_needs_two_approvals_v1(v_hold.user_id)
    THEN 2 ELSE 1 END;
  IF (SELECT count(*) FROM public.account_mfa_recovery_approvals WHERE case_id = p_case) < v_required THEN
    RETURN false;
  END IF;
  UPDATE auth.refresh_tokens SET revoked = true WHERE user_id = v_hold.user_id::text AND NOT revoked;
  DELETE FROM auth.sessions WHERE user_id = v_hold.user_id;
  UPDATE public.scanner_sessions SET revoked_at = clock_timestamp()
  WHERE actor_user_id = v_hold.user_id AND revoked_at IS NULL;
  UPDATE public.account_mfa_recovery_holds SET sessions_revoked_at = clock_timestamp()
  WHERE case_id = p_case;
  RETURN true;
END $$;

-- The operator conveys the generated code via the independently verified
-- support channel. The ordinary security notice carries no enrollment code.
CREATE OR REPLACE FUNCTION public.issue_account_mfa_replacement_code_v1(p_case uuid)
RETURNS text LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, extensions AS $$
DECLARE
  v_hold public.account_mfa_recovery_holds%rowtype;
  v_code text;
BEGIN
  SELECT * INTO v_hold FROM public.account_mfa_recovery_holds
  WHERE case_id = p_case AND sessions_revoked_at IS NOT NULL FOR UPDATE;
  IF NOT FOUND OR EXISTS (
    SELECT FROM auth.mfa_factors WHERE user_id = v_hold.user_id AND status = 'verified'
  ) OR EXISTS (
    SELECT FROM public.account_mfa_registration_handoffs
    WHERE recovery_case_id = p_case AND verifying
  ) THEN RETURN NULL; END IF;

  v_code := translate(rtrim(encode(gen_random_bytes(32), 'base64'), '='), '+/', '-_');
  UPDATE public.account_mfa_recovery_holds
  SET replacement_code_hash = encode(digest(v_code, 'sha256'), 'hex'),
      replacement_expires_at = clock_timestamp() + interval '15 minutes',
      replacement_session_id = NULL
  WHERE case_id = p_case;
  RETURN v_code;
END $$;

CREATE TABLE IF NOT EXISTS public.account_mfa_recovery_completions (
  case_id uuid PRIMARY KEY,
  organization bigint NOT NULL,
  notice_id uuid NOT NULL,
  method text NOT NULL CHECK (method IN ('totp', 'webauthn')),
  approvals jsonb NOT NULL,
  external_revocation_evidence uuid NOT NULL,
  completed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.account_mfa_recovery_completions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_mfa_recovery_completions FROM PUBLIC, anon, authenticated, service_role;

-- The support operator attests completion of external revocation from the
-- inventory (including open Realtime subscriptions and pre-cutover links).
-- This reference cannot authorize recovery without a live, brokered factor.
CREATE OR REPLACE FUNCTION public.complete_account_mfa_recovery_v1(
  p_case uuid, p_external_revocation_evidence uuid
)
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, extensions AS $$
DECLARE
  v_hold public.account_mfa_recovery_holds%rowtype;
  v_method text;
  v_approvals jsonb;
BEGIN
  IF p_external_revocation_evidence IS NULL THEN RETURN false; END IF;
  SELECT * INTO v_hold FROM public.account_mfa_recovery_holds
  WHERE case_id = p_case AND sessions_revoked_at IS NOT NULL FOR UPDATE;
  IF NOT FOUND THEN
    RETURN EXISTS (
      SELECT FROM public.account_mfa_recovery_completions
      WHERE case_id = p_case AND external_revocation_evidence = p_external_revocation_evidence
    );
  END IF;

  SELECT handoff.method INTO v_method
  FROM public.account_mfa_registration_handoffs handoff
  JOIN auth.mfa_factors factor
    ON factor.id = handoff.factor_id AND factor.user_id = handoff.user_id
    AND factor.factor_type::text = handoff.method AND factor.status = 'verified'
  JOIN auth.sessions session
    ON session.id = handoff.session_id AND session.user_id = handoff.user_id
    AND session.factor_id = factor.id AND session.aal::text = 'aal2'
  JOIN public.user_info profile
    ON profile.id = handoff.user_id AND profile.organization = handoff.organization
  WHERE handoff.recovery_case_id = p_case AND handoff.user_id = v_hold.user_id
    AND handoff.organization = v_hold.organization AND handoff.session_id = v_hold.replacement_session_id
    AND handoff.verified_at >= v_hold.sessions_revoked_at
    AND factor.created_at >= v_hold.sessions_revoked_at
    AND (session.not_after IS NULL OR session.not_after > statement_timestamp())
  FOR SHARE OF factor;
  IF NOT FOUND THEN RETURN false; END IF;

  SELECT jsonb_agg(jsonb_build_object('reviewer', reviewer, 'evidenceId', evidence_id) ORDER BY reviewer)
  INTO v_approvals FROM public.account_mfa_recovery_approvals WHERE case_id = p_case;
  IF NOT public.revoke_account_mfa_recovery_sessions_v1(p_case) THEN RETURN false; END IF;
  INSERT INTO public.account_mfa_recovery_completions
    (case_id, organization, notice_id, method, approvals, external_revocation_evidence)
  VALUES (p_case, v_hold.organization, v_hold.notice_id, v_method, v_approvals, p_external_revocation_evidence);
  DELETE FROM public.account_mfa_recovery_holds WHERE case_id = p_case;
  RETURN true;
END $$;

-- The first proof is freshly authenticated after revocation. Subsequent
-- operations additionally require the exact recovery receipt and session.
CREATE OR REPLACE FUNCTION public.get_mfa_recovery_registration_actor_v1(p_organization bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_jwt jsonb := auth.jwt();
  v_hold public.account_mfa_recovery_holds%rowtype;
  v_session auth.sessions%rowtype;
BEGIN
  IF public.get_account_assurance_v1(p_organization) IS DISTINCT FROM 'account_recovery'
    OR v_jwt->>'aal' IS DISTINCT FROM 'aal1' THEN
    RETURN NULL;
  END IF;
  SELECT * INTO v_hold FROM public.account_mfa_recovery_holds WHERE user_id = auth.uid();
  SELECT * INTO v_session FROM auth.sessions WHERE id = (v_jwt->>'session_id')::uuid;
  IF v_hold.case_id IS NULL OR v_hold.sessions_revoked_at IS NULL
    OR v_hold.replacement_expires_at IS NULL OR v_hold.replacement_expires_at <= statement_timestamp()
    OR v_session.aal::text IS DISTINCT FROM 'aal1' OR v_session.created_at < v_hold.sessions_revoked_at
    OR (v_hold.replacement_session_id IS NOT NULL AND v_hold.replacement_session_id <> v_session.id)
    OR NOT EXISTS (
      SELECT FROM auth.mfa_amr_claims amr WHERE amr.session_id = v_session.id
        AND amr.authentication_method = 'password'
        AND amr.updated_at >= v_hold.sessions_revoked_at
        AND amr.updated_at >= statement_timestamp() - interval '5 minutes'
    ) OR v_jwt->'amr' @> '[{"method":"password"}]'::jsonb IS DISTINCT FROM true THEN
    RETURN NULL;
  END IF;
  RETURN jsonb_build_object('decision', 'allowed', 'userId', auth.uid(), 'sessionId', v_session.id);
END $$;

REVOKE ALL ON FUNCTION public.get_mfa_recovery_registration_actor_v1(bigint)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_mfa_recovery_registration_actor_v1(bigint) TO authenticated;

REVOKE ALL ON FUNCTION
  public.account_recovery_needs_two_approvals_v1(uuid),
  public.begin_account_mfa_recovery_v1(uuid,bigint,uuid),
  public.approve_account_mfa_recovery_v1(uuid,uuid,uuid),
  public.revoke_account_mfa_recovery_sessions_v1(uuid),
  public.issue_account_mfa_replacement_code_v1(uuid),
  public.complete_account_mfa_recovery_v1(uuid,uuid)
  FROM PUBLIC, anon, authenticated, service_role;

-- SOURCE: user_permissions/account_private_image_grants.sql
CREATE TABLE IF NOT EXISTS public.account_private_image_grants (
  code_hash bytea PRIMARY KEY,
  session_id uuid NOT NULL REFERENCES auth.sessions(id) ON DELETE CASCADE,
  project text NOT NULL,
  object_key text NOT NULL,
  expires_at timestamptz NOT NULL,
  claims jsonb NOT NULL
);
CREATE INDEX IF NOT EXISTS account_private_image_grants_expiry_idx
  ON public.account_private_image_grants(expires_at);
ALTER TABLE public.account_private_image_grants ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_private_image_grants FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.issue_account_private_image_grant_v1(
  p_project text, p_object_key text, p_expires_in integer
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_claims jsonb := auth.jwt();
  v_code text;
  v_expires_at timestamptz;
BEGIN
  IF public.get_account_assurance_v1() IS DISTINCT FROM 'allowed'
    OR public.get_image_project_access_v1(p_project) IS DISTINCT FROM true
    OR p_object_key IS NULL OR length(p_object_key) > 1024 OR p_object_key !~ '^private/.+'
    OR p_expires_in IS NULL OR p_expires_in NOT BETWEEN 1 AND 604800 THEN RETURN NULL; END IF;

  v_expires_at := least(statement_timestamp() + make_interval(secs => p_expires_in),
    to_timestamp((v_claims->>'exp')::bigint));
  v_code := translate(rtrim(encode(gen_random_bytes(32), 'base64'), '='), '+/', '-_');
  DELETE FROM public.account_private_image_grants WHERE code_hash IN (
    SELECT code_hash FROM public.account_private_image_grants
    WHERE expires_at <= statement_timestamp() ORDER BY expires_at LIMIT 32 FOR UPDATE SKIP LOCKED
  );
  -- Retain only the previously verified facts required by the access checks.
  INSERT INTO public.account_private_image_grants
    (code_hash, session_id, project, object_key, expires_at, claims)
  VALUES (digest(v_code, 'sha256'), (v_claims->>'session_id')::uuid, p_project, p_object_key, v_expires_at,
    jsonb_build_object('role', v_claims->'role', 'sub', v_claims->'sub',
      'session_id', v_claims->'session_id', 'exp', v_claims->'exp', 'aal', v_claims->'aal',
      'amr', v_claims->'amr', 'is_anonymous', v_claims->'is_anonymous'));
  RETURN jsonb_build_object('code', v_code,
    'expiresIn', floor(extract(epoch FROM (v_expires_at - statement_timestamp())))::integer);
END $$;

CREATE OR REPLACE FUNCTION public.redeem_account_private_image_grant_v1(
  p_project text, p_object_key text, p_code text
)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_previous text := current_setting('request.jwt.claims', true);
  v_claims jsonb;
  v_allowed boolean;
BEGIN
  IF p_code IS NULL OR p_code !~ '^[A-Za-z0-9_-]{43}$' THEN RETURN false; END IF;
  SELECT claims INTO v_claims FROM public.account_private_image_grants
  WHERE code_hash = digest(p_code, 'sha256') AND project = p_project AND object_key = p_object_key
    AND expires_at > statement_timestamp();
  IF NOT FOUND THEN RETURN false; END IF;

  -- These claims are read from an owner-only row created under a validated
  -- user JWT. Caller-supplied values never become request claims.
  PERFORM set_config('request.jwt.claims', v_claims::text, true);
  v_allowed := public.get_account_assurance_v1() = 'allowed'
    AND public.get_image_project_access_v1(p_project);
  PERFORM set_config('request.jwt.claims', coalesce(v_previous, ''), true);
  RETURN v_allowed IS TRUE;
END $$;

REVOKE ALL ON FUNCTION public.issue_account_private_image_grant_v1(text,text,integer),
  public.redeem_account_private_image_grant_v1(text,text,text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.issue_account_private_image_grant_v1(text,text,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.redeem_account_private_image_grant_v1(text,text,text) TO anon;

-- SOURCE: user_permissions/public_auth_operation_policy.sql
-- The public broker permits ordinary verification only for an existing
-- verified factor owned by the actor. GoTrue validates the actual challenge.
CREATE OR REPLACE FUNCTION public.can_use_existing_mfa_factor_v1(p_factor uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
BEGIN
  IF public.get_account_assurance_v1() NOT IN ('allowed', 'mfa_required', 'proof_required') THEN
    RETURN false;
  END IF;
  RETURN EXISTS (
    SELECT FROM auth.mfa_factors
    WHERE id = p_factor AND user_id = auth.uid() AND status = 'verified'
      AND factor_type IN ('totp', 'phone', 'webauthn')
  );
END $$;

-- Preserve ordinary password/account updates for accounts without an everyday
-- factor. An enrolled account requires fresh account security assurance.
CREATE OR REPLACE FUNCTION public.can_update_public_auth_account_v1()
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
BEGIN
  IF public.get_account_assurance_v1() IS DISTINCT FROM 'allowed' THEN
    RETURN false;
  END IF;
  IF EXISTS (SELECT FROM auth.mfa_factors WHERE user_id = auth.uid()
    AND status = 'verified' AND factor_type IN ('totp', 'phone', 'webauthn')) THEN
    RETURN public.get_account_assurance_v1(NULL, true) = 'allowed';
  END IF;
  RETURN true;
END $$;

REVOKE ALL ON FUNCTION public.can_use_existing_mfa_factor_v1(uuid),
  public.can_update_public_auth_account_v1() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_use_existing_mfa_factor_v1(uuid),
  public.can_update_public_auth_account_v1() TO authenticated;

-- SOURCE: users/existing_user_session.sql
-- Shared, distributed serialization for internal GoTrue recovery minting.
CREATE OR REPLACE FUNCTION public.format_auth_email(p_organization bigint, p_sign_in_email text)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path = public, extensions AS $$
DECLARE v_email text := lower(btrim(p_sign_in_email)); v_result text;
BEGIN
  IF p_organization IS NULL OR p_organization <= 0 OR v_email IS NULL
     OR v_email = '' OR position('@' IN v_email) <= 1 THEN
    RAISE EXCEPTION 'INVALID_USER_EMAIL';
  END IF;
  v_result := p_organization::text || '+' || v_email;
  IF octet_length(v_result) > 254 THEN RAISE EXCEPTION 'INVALID_USER_EMAIL'; END IF;
  RETURN v_result;
END $$;

CREATE TABLE IF NOT EXISTS public.existing_user_session_leases (
  user_id uuid PRIMARY KEY REFERENCES public.user_info(id) ON DELETE CASCADE,
  owner uuid NOT NULL,
  expires_at timestamptz NOT NULL
);
ALTER TABLE public.existing_user_session_leases ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.existing_user_session_leases FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.existing_user_session_leases TO service_role;

CREATE OR REPLACE FUNCTION public.resolve_existing_user_session_v1(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_profile public.user_info%rowtype; v_auth auth.users%rowtype;
BEGIN
  PERFORM public.require_service_role();
  SELECT * INTO v_profile FROM public.user_info WHERE id=p_user;
  SELECT * INTO v_auth FROM auth.users WHERE id=p_user;
  IF v_profile.id IS NULL OR v_auth.id IS NULL OR v_auth.deleted_at IS NOT NULL
    OR v_auth.banned_until > clock_timestamp()
    OR EXISTS (SELECT FROM public.account_mfa_recovery_holds h WHERE h.user_id = p_user)
    OR EXISTS (SELECT FROM public.account_mfa_factor_removals WHERE user_id = p_user)
    OR v_auth.email IS DISTINCT FROM public.format_auth_email(v_profile.organization,v_profile.email_readonly) THEN
    RETURN NULL;
  END IF;
  RETURN jsonb_build_object('userId',v_auth.id,'authEmail',v_auth.email,'organization',v_profile.organization,'requiresMfa',EXISTS(SELECT 1 FROM auth.mfa_factors WHERE user_id=p_user AND status='verified'));
END $$;

CREATE OR REPLACE FUNCTION public.acquire_existing_user_session_lease_v1(p_user uuid,p_owner uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_target jsonb; v_acquired uuid;
BEGIN
  PERFORM public.require_service_role();
  IF p_owner IS NULL THEN RAISE EXCEPTION 'invalid_lease_owner'; END IF;
  v_target := public.resolve_existing_user_session_v1(p_user);
  IF v_target IS NULL THEN RETURN NULL; END IF;
  INSERT INTO public.existing_user_session_leases(user_id,owner,expires_at)
    VALUES(p_user,p_owner,clock_timestamp()+interval '120 seconds')
  ON CONFLICT(user_id) DO UPDATE SET owner=excluded.owner,expires_at=excluded.expires_at
    WHERE existing_user_session_leases.expires_at <= clock_timestamp()
  RETURNING owner INTO v_acquired;
  IF v_acquired IS NULL THEN RETURN NULL; END IF;
  RETURN v_target;
END $$;

CREATE OR REPLACE FUNCTION public.check_existing_user_session_lease_v1(p_user uuid,p_owner uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  IF NOT EXISTS(SELECT 1 FROM public.existing_user_session_leases
      WHERE user_id=p_user AND owner=p_owner AND expires_at>clock_timestamp()) THEN RETURN NULL; END IF;
  RETURN public.resolve_existing_user_session_v1(p_user);
END $$;

CREATE OR REPLACE FUNCTION public.release_existing_user_session_lease_v1(p_user uuid,p_owner uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  PERFORM public.require_service_role();
  DELETE FROM public.existing_user_session_leases WHERE user_id=p_user AND owner=p_owner;
END $$;

REVOKE ALL ON FUNCTION public.resolve_existing_user_session_v1(uuid),
  public.acquire_existing_user_session_lease_v1(uuid,uuid),
  public.check_existing_user_session_lease_v1(uuid,uuid),
  public.release_existing_user_session_lease_v1(uuid,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_existing_user_session_v1(uuid),
  public.acquire_existing_user_session_lease_v1(uuid,uuid),
  public.check_existing_user_session_lease_v1(uuid,uuid),
  public.release_existing_user_session_lease_v1(uuid,uuid) TO service_role;
