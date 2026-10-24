DO $$
DECLARE
  v_key text := encode(digest(gen_random_uuid()::text,'sha256'),'hex');
BEGIN
  PERFORM set_config('request.jwt.claim.role','anon',true);
  PERFORM assert_false(
    public.consume_password_reset_rate_limit_v1(v_key,3,900),
    'anonymous callers cannot consume the privileged password reset limiter'
  );

  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM assert_true(public.consume_password_reset_rate_limit_v1(v_key,3,900),'first attempt passes');
  PERFORM assert_true(public.consume_password_reset_rate_limit_v1(v_key,3,900),'second attempt passes');
  PERFORM assert_true(public.consume_password_reset_rate_limit_v1(v_key,3,900),'third attempt passes');
  PERFORM assert_false(public.consume_password_reset_rate_limit_v1(v_key,3,900),'fourth attempt is limited');
  PERFORM assert_false(
    public.consume_password_reset_rate_limit_v1('invalid',3,900),
    'invalid limiter keys fail closed'
  );
  PERFORM assert_true(NOT has_function_privilege(
    'anon','public.consume_password_reset_rate_limit_v1(text,integer,integer)','EXECUTE'),
    'anon lacks limiter execute privilege'
  );
  PERFORM assert_true(has_function_privilege(
    'service_role','public.consume_password_reset_rate_limit_v1(text,integer,integer)','EXECUTE'),
    'service role can call the limiter'
  );
END
$$;
