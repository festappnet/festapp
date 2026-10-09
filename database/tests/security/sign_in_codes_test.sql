BEGIN;
DO $$
DECLARE org bigint; usr uuid:=gen_random_uuid(); r jsonb; pw text; i integer;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Code security') RETURNING id INTO org;
 INSERT INTO auth.users(id,email,encrypted_password) VALUES(usr,'code-security@test.invalid',extensions.crypt('existing-password',extensions.gen_salt('bf')));
 INSERT INTO public.user_info(id,organization,email_readonly) VALUES(usr,org,'code-security@test.invalid');
 SELECT encrypted_password INTO pw FROM auth.users WHERE id=usr;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM public.store_sign_in_code_v1(usr,'123456',now()+interval '1 hour');
 IF (SELECT expires_at>now()+interval '10 minutes' FROM public.sign_in_codes WHERE user_id=usr) THEN RAISE EXCEPTION 'expiry not bounded'; END IF;
 IF public.consume_sign_in_code_v1('code-security@test.invalid',org+1,'123456') IS NOT NULL THEN RAISE EXCEPTION 'cross tenant accepted'; END IF;
 FOR i IN 1..5 LOOP
  IF public.consume_sign_in_code_v1('code-security@test.invalid',org,'999999') IS NOT NULL THEN RAISE EXCEPTION 'wrong code accepted'; END IF;
 END LOOP;
 IF public.consume_sign_in_code_v1('code-security@test.invalid',org,'123456') IS NOT NULL THEN RAISE EXCEPTION 'attempt lock bypass'; END IF;
 PERFORM public.store_sign_in_code_v1(usr,'123456',now()+interval '10 minutes');
 r:=public.consume_sign_in_code_v1('code-security@test.invalid',org,'123456');
 IF r->>'userId' IS DISTINCT FROM usr::text THEN RAISE EXCEPTION 'valid code rejected'; END IF;
 IF public.consume_sign_in_code_v1('code-security@test.invalid',org,'123456') IS NOT NULL THEN RAISE EXCEPTION 'replay accepted'; END IF;
 PERFORM public.store_sign_in_code_v1(usr,'123456',now()+interval '10 minutes');
 UPDATE public.sign_in_codes SET expires_at=now()-interval '1 second' WHERE user_id=usr;
 IF public.consume_sign_in_code_v1('code-security@test.invalid',org,'123456') IS NOT NULL THEN RAISE EXCEPTION 'expired code accepted'; END IF;
 IF (SELECT encrypted_password FROM auth.users WHERE id=usr) IS DISTINCT FROM pw THEN RAISE EXCEPTION 'password changed'; END IF;
 IF has_table_privilege('anon','public.sign_in_codes','SELECT') OR has_function_privilege('authenticated','public.consume_sign_in_code_v1(text,bigint,text)','EXECUTE') THEN RAISE EXCEPTION 'public proof access'; END IF;
END $$;
ROLLBACK;
