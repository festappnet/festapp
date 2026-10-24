DO $$
DECLARE u uuid:=gen_random_uuid(); result jsonb; original text; i integer;
BEGIN
 INSERT INTO auth.users(id,email,encrypted_password,created_at) VALUES(u,'permanent-password@test.invalid',extensions.crypt('123456',extensions.gen_salt('bf')),now()-interval '5 years');
 SELECT encrypted_password INTO original FROM auth.users WHERE id=u;
 FOR i IN 1..10 LOOP
  result:=public.password_verification_attempt_v1(jsonb_build_object('user_id',u,'valid',true));
  PERFORM assert_eq(result->>'decision','continue','permanent password supports repeated login');
 END LOOP;
 result:=public.password_verification_attempt_v1(jsonb_build_object('user_id',u,'valid',false));
 PERFORM assert_eq(result->>'decision','reject','correct and incorrect attempts share account budget');
 PERFORM assert_eq(result->>'should_logout_user','false','throttling never logs out existing sessions');
 result:=public.password_verification_attempt_v1(jsonb_build_object('user_id',u,'valid',true));
 PERFORM assert_eq(result->>'decision','reject','correct proof does not bypass exhausted attempt budget');
 PERFORM assert_eq((SELECT sum(amount) FROM public.abuse_budget_usage WHERE rule_key='password.verify.actor.burst' AND scope_id=u::text),12::numeric,'rejected attempts remain counted');
 PERFORM assert_eq((SELECT encrypted_password FROM auth.users WHERE id=u),original,'attempts never expire, consume or replace password');
 PERFORM assert_false(has_function_privilege('anon','public.password_verification_attempt_v1(jsonb)','EXECUTE'),'anonymous cannot spoof native hook');
 PERFORM assert_false(has_function_privilege('authenticated','public.password_verification_attempt_v1(jsonb)','EXECUTE'),'user cannot spoof native hook');
 PERFORM assert_false(has_function_privilege('service_role','public.password_verification_attempt_v1(jsonb)','EXECUTE'),'HTTP service role cannot impersonate native Auth');
 PERFORM assert_true(has_function_privilege('supabase_auth_admin','public.password_verification_attempt_v1(jsonb)','EXECUTE'),'native Auth owns hook');
END $$;
