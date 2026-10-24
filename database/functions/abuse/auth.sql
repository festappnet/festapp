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
