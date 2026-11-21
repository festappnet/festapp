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
