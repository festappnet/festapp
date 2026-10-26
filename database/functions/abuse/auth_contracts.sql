-- Reusable Auth contracts. Historical budget adoption is immutable migration history.
-- Hash the former stable SHA identity with the protected key. This permits a
-- lossless migration of already consumed budgets without storing raw IP/email.
CREATE OR REPLACE FUNCTION public.consume_auth_abuse_v1(p_family text,p_key_hash text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 IF p_family IS NULL OR p_family NOT IN ('reset.source','reset.account','google.source','google.client','google.global','google.attempt','google.proof')
  OR p_key_hash IS NULL OR p_key_hash !~ '^[0-9a-f]{64}$' THEN RETURN false; END IF;
 RETURN public.abuse_charge_v1(public.abuse_effective_rules_v1('auth.'||p_family,NULL,NULL),
  jsonb_build_object('recipient',public.abuse_recipient_key_v1(p_key_hash),'global','all'),'{}',true);
END $$;
REVOKE ALL ON FUNCTION public.consume_auth_abuse_v1(text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.consume_auth_abuse_v1(text,text) TO service_role;

-- Compatibility signatures use the same canonical counters, never client limits.
CREATE OR REPLACE FUNCTION public.consume_password_reset_rate_limit_v1(p_key_hash text,p_limit integer,p_window_seconds integer)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF auth.role() IS DISTINCT FROM 'service_role' OR p_limit IS NULL OR p_limit NOT IN (3,20) OR p_window_seconds IS DISTINCT FROM 900 THEN RETURN false; END IF;
 RETURN public.consume_auth_abuse_v1(CASE p_limit WHEN 20 THEN 'reset.source' ELSE 'reset.account' END,p_key_hash);
END $$;
REVOKE ALL ON FUNCTION public.consume_password_reset_rate_limit_v1(text,integer,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.consume_password_reset_rate_limit_v1(text,integer,integer) TO service_role;
CREATE OR REPLACE FUNCTION public.google_auth_rate_limit_v1(p_key text,p_limit integer)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 RETURN public.consume_auth_abuse_v1(CASE p_limit WHEN 20 THEN 'google.source' WHEN 30 THEN 'google.client'
  WHEN 100 THEN 'google.global' WHEN 10 THEN 'google.attempt' WHEN 5 THEN 'google.proof' END,p_key);
END $$;
REVOKE ALL ON FUNCTION public.google_auth_rate_limit_v1(text,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.google_auth_rate_limit_v1(text,integer) TO service_role;

CREATE OR REPLACE FUNCTION public.cleanup_external_login_v1()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 DELETE FROM public.external_login_attempts WHERE expires_at<clock_timestamp();
 DELETE FROM public.existing_user_session_leases WHERE expires_at<clock_timestamp();
 PERFORM public.cleanup_abuse_usage_v1();
END $$;
REVOKE ALL ON FUNCTION public.cleanup_external_login_v1() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_external_login_v1() TO service_role;
