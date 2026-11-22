-- Identify the account, registered origin and method in account security enrollment notices.

-- SOURCE: user_permissions/account_mfa_factor_registration.sql
CREATE OR REPLACE FUNCTION public.queue_account_security_enrollment_notice_v1(
  p_receipt uuid, p_user uuid, p_organization bigint
)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, extensions AS $$
DECLARE
  v_recipient text;
  v_context jsonb;
  v_message jsonb;
BEGIN
  SELECT public.get_user_delivery_email(u.id), jsonb_strip_nulls(jsonb_build_object(
    'lang', coalesce(o.data->>'DEFAULT_LANGUAGE', 'cs'),
    'account_email', NULLIF(btrim(u.email_readonly), ''),
    'origin', h.origin,
    'method', h.method
  ))
  INTO v_recipient, v_context
  FROM public.account_mfa_registration_handoffs h
  JOIN public.user_info u ON u.id = h.user_id AND u.organization = h.organization
  JOIN public.organizations o ON o.id = h.organization
  WHERE h.id = p_receipt AND h.user_id = p_user AND h.organization = p_organization
    AND h.verified_at IS NOT NULL;

  IF v_recipient IS NULL THEN RETURN; END IF;
  v_message := public.enqueue_email('custom', jsonb_build_object('organization', p_organization),
    v_recipient, v_context, 'mfa-enrollment:' || p_receipt::text, 'ACCOUNT_MFA_METHOD_ADDED');
  UPDATE public.email_messages SET tracking_policy = 'disabled'
  WHERE message_id = (v_message->>'message_id')::uuid;
END $$;
