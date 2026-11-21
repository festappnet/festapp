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
DECLARE handoff public.account_mfa_registration_handoffs%rowtype; method_policy jsonb;
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
  IF p_operation IN ('enroll', 'challenge', 'verify') THEN
    method_policy := public.resolve_mfa_channel_policy_v1(handoff.client_id, handoff.organization, handoff.origin, handoff.redirect_uri)
      ->'methods'->p_method;
    IF method_policy @> jsonb_build_object(
        'registration', true, 'registrationRevision', handoff.registration_revision) IS DISTINCT FROM true
      OR (NOT p_recovery AND NOT public.mfa_registration_actor_matches_v1(method_policy, p_user)) THEN
      RETURN false;
    END IF;
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
