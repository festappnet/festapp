BEGIN;
DO $$
DECLARE org bigint; usr uuid; reset uuid:=gen_random_uuid(); result jsonb; original text;
BEGIN
 INSERT INTO public.organizations(title) VALUES('Password reset retry validation fixture') RETURNING id INTO org;
 usr:=public.create_user_in_organization_with_data_pure(org,'retry@example.invalid','original-password','{}'::jsonb);
 SELECT encrypted_password INTO original FROM auth.users WHERE id=usr;
 INSERT INTO public.user_reset_token(token,"user") VALUES(reset,usr);
 FOREACH result IN ARRAY ARRAY[public.set_user_password_token(reset,'1234567'),public.set_user_password_token(reset,NULL)] LOOP
  IF (result->>'code')::int<>400 THEN RAISE EXCEPTION 'Weak/null password must return 400'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.user_reset_token WHERE token=reset) THEN RAISE EXCEPTION 'Invalid password consumed a valid reset token'; END IF;
  IF (SELECT encrypted_password FROM auth.users WHERE id=usr) IS DISTINCT FROM original THEN RAISE EXCEPTION 'Invalid password changed credentials'; END IF;
 END LOOP;
 result:=public.set_user_password_token(reset,'valid-replacement-password');
 IF (result->>'code')::int<>200 THEN RAISE EXCEPTION 'Corrected password could not use the preserved token'; END IF;
 IF EXISTS(SELECT 1 FROM public.user_reset_token WHERE token=reset) THEN RAISE EXCEPTION 'Successful reset did not consume token'; END IF;
 result:=public.set_user_password_token(reset,'another-valid-password');
 IF (result->>'code')::int<>403 THEN RAISE EXCEPTION 'Reset token could be reused after success'; END IF;
END $$;
ROLLBACK;
