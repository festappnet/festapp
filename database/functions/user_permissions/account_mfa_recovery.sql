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
