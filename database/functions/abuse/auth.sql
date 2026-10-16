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

-- Preserve every live old window. Its class was not stored: conservatively adopt
-- it in every compatible class, with expiry bounded to the former window.
INSERT INTO public.abuse_budget_usage(rule_key,scope_id,bucket_at,amount,expires_at)
SELECT r.rule_key,public.abuse_recipient_key_v1(x.key_hash),
 to_timestamp(floor(extract(epoch FROM x.window_started_at)/r.bucket_seconds)*r.bucket_seconds),
 x.attempts,x.window_started_at+interval '20 minutes'
FROM public.password_reset_rate_limits x CROSS JOIN public.abuse_policy_rules r
WHERE r.rule_key IN ('reset.source','reset.account') AND x.window_started_at>now()-interval '15 minutes' AND x.attempts>0;
INSERT INTO public.abuse_budget_usage(rule_key,scope_id,bucket_at,amount,expires_at)
SELECT r.rule_key,public.abuse_recipient_key_v1(x.key_hash),
 to_timestamp(floor(extract(epoch FROM x.window_start)/r.bucket_seconds)*r.bucket_seconds),x.hits,x.window_start+interval '2 minutes'
FROM public.external_login_rate_limits x CROSS JOIN public.abuse_policy_rules r
WHERE r.rule_key LIKE 'google.%' AND x.window_start>now()-interval '1 minute' AND x.hits>0;
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
DROP TABLE public.password_reset_rate_limits;
DROP TABLE public.external_login_rate_limits;

-- GoTrue explicitly invokes this PostgreSQL hook in its own committed transaction
-- BEFORE session issuance. This is not a database trigger. Returning reject keeps
-- consumption even when GoTrue subsequently rejects credentials or session work.
CREATE OR REPLACE FUNCTION public.password_verification_attempt_v1(event jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE actor uuid; allowed boolean;
BEGIN
 actor:=(event->>'user_id')::uuid;
 IF actor IS NULL OR jsonb_typeof(event->'valid') IS DISTINCT FROM 'boolean'
  OR NOT EXISTS(SELECT 1 FROM auth.users WHERE id=actor) THEN
  RETURN jsonb_build_object('decision','reject','message','Invalid login attempt','should_logout_user',false);
 END IF;
 allowed:=public.abuse_charge_v1(public.abuse_effective_rules_v1('auth.password',NULL,NULL),
  jsonb_build_object('actor',actor::text),'{}',true);
 RETURN jsonb_build_object('decision',CASE WHEN allowed THEN 'continue' ELSE 'reject' END,
  'message',CASE WHEN allowed THEN '' ELSE 'Too many login attempts. Try again later.' END,
  'should_logout_user',false);
END $$;
REVOKE ALL ON FUNCTION public.password_verification_attempt_v1(jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.password_verification_attempt_v1(jsonb) TO supabase_auth_admin;
