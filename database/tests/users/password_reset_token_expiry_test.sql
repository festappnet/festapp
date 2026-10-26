DO $$
DECLARE
  v_org bigint;
  v_user uuid;
  v_token uuid;
  v_result jsonb;
  v_old_hash text;
BEGIN
  INSERT INTO public.organizations(title) VALUES('Password reset expiry test') RETURNING id INTO v_org;
  v_user:=public.create_user_in_organization_with_data_pure(
    v_org,'password-reset-expiry@test.local','password-reset-expiry@test.local',
    'original-password',jsonb_build_object('name','Reset','surname','Expiry','sex','unspecified')
  );
  SELECT encrypted_password INTO v_old_hash FROM auth.users WHERE id=v_user;

  v_token:=gen_random_uuid();
  INSERT INTO public.user_reset_token(token,created_at,"user")
  VALUES(v_token,now()-interval '31 minutes',v_user);
  v_result:=public.set_user_password_token(v_token,'replacement-password');
  PERFORM assert_eq((v_result->>'code')::int,403,'expired reset token is rejected');
  PERFORM assert_eq(
    (SELECT encrypted_password FROM auth.users WHERE id=v_user),v_old_hash,
    'expired reset token cannot change the password'
  );

  v_token:=gen_random_uuid();
  INSERT INTO public.user_reset_token(token,"user") VALUES(v_token,v_user);
  v_result:=public.set_user_password_token(v_token,'replacement-password');
  PERFORM assert_eq((v_result->>'code')::int,200,'fresh reset token succeeds');
  PERFORM assert_true(
    (SELECT encrypted_password FROM auth.users WHERE id=v_user)<>v_old_hash,
    'fresh reset token changes the password'
  );
  PERFORM assert_false(
    EXISTS(SELECT 1 FROM public.user_reset_token WHERE "user"=v_user),
    'reset token is consumed atomically'
  );
END
$$;
