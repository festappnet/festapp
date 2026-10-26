DO $$
DECLARE
  v_org bigint; v_other_org bigint; v_unit bigint; v_occasion bigint; v_actor uuid; v_receptionist uuid; v_created uuid;
  v_admin uuid; v_existing uuid;
  v_result jsonb; v_first_payload text; v_second_payload text;
  v_second_token text; v_first_manual_code text; v_second_manual_code text;
  v_duplicate_command uuid:=gen_random_uuid();
BEGIN
  INSERT INTO public.organizations(title) VALUES('Reception contract org') RETURNING id INTO v_org;
  INSERT INTO public.organizations(title) VALUES('Other reception contract org') RETURNING id INTO v_other_org;
  INSERT INTO public.units(organization,title) VALUES(v_org,'Reception unit') RETURNING id INTO v_unit;
  INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time,is_open,features,services)
  VALUES(v_org,v_unit,'Reception occasion','reception-'||gen_random_uuid(),now(),now()+interval '1 day',true,
    '[{"code":"reception","is_enabled":true}]'::jsonb,
    '{"accommodation":[{"code":"room-a","title":"Room A"}]}'::jsonb) RETURNING id INTO v_occasion;
  v_actor:=public.create_user_in_organization_with_data_pure(v_org,'actor@test.local','actor@test.local','password',jsonb_build_object('name','Actor','surname','Manager','sex','male'));
  v_receptionist:=public.create_user_in_organization_with_data_pure(v_org,'receptionist@test.local','receptionist@test.local','password',jsonb_build_object('name','Reception','surname','Staff','sex','female'));
  v_admin:=public.create_user_in_organization_with_data_pure(v_org,'admin@test.local','admin@test.local','password',jsonb_build_object('name','Occasion','surname','Admin','sex','female'));
  PERFORM public.create_user_in_organization_with_data_pure(v_other_org,'new@test.local','new@test.local','password',jsonb_build_object('name','Other','surname','Tenant','sex','unspecified'));
  INSERT INTO public.occasion_users(occasion,"user",is_manager,is_receptionist,data) VALUES(v_occasion,v_actor,true,true,'{}');
  INSERT INTO public.occasion_users(occasion,"user",is_receptionist,data) VALUES(v_occasion,v_receptionist,true,'{}');
  v_existing:=public.create_user_in_organization_with_data_pure(v_org,'existing@test.local','existing@test.local','password',jsonb_build_object('name','Existing','surname','Participant','sex','female'));
  INSERT INTO public.occasion_users(occasion,"user",data) VALUES(v_occasion,v_existing,'{}');
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);

  PERFORM assert_true(public.get_can_use_reception(v_occasion),'manager can use enabled reception');
  PERFORM assert_true(
    (public.get_private_profile_payload_v1(v_occasion,v_actor)->'occasion'->>'isReceptionist')::boolean,
    'client-sync private profile projects the same receptionist role as classic app config'
  );
  v_result:=public.create_reception_user_v1(v_occasion,gen_random_uuid(),jsonb_build_object('name','New','surname','Person','email','new@test.local','sex','unspecified'),NULL,'room-a',false);
  PERFORM assert_eq((v_result->>'code')::int,200,'creates an unprivileged reception user');
  PERFORM assert_eq(
    (SELECT organization FROM public.user_info WHERE id=(v_result->>'userId')::uuid),
    v_org,
    'same e-mail in another organization does not block tenant-local creation'
  );
  v_created:=(v_result->>'userId')::uuid;
  PERFORM assert_false((SELECT is_manager OR is_editor OR is_receptionist FROM public.occasion_users WHERE occasion=v_occasion AND "user"=v_created),'created membership has no elevated role');
  PERFORM assert_false(v_result ? 'payload','create receipt never contains the QR plaintext');

  v_result:=public.create_reception_user_v1(
    v_occasion,gen_random_uuid(),
    jsonb_build_object('name','Existing','surname','Participant','email','existing@test.local','sex','female'),
    NULL,NULL,false
  );
  PERFORM assert_eq((v_result->>'code')::int,200,'an occasion manager can resolve a current participant through the legacy create form');
  PERFORM assert_eq(v_result->>'userId',v_existing::text,'legacy create form returns the existing participant identity');
  PERFORM assert_true((v_result->>'existing')::boolean,'legacy create form marks the identity as existing');
  v_result:=public.issue_reception_login_qr_v1(v_occasion,(v_result->>'userId')::uuid);
  PERFORM assert_eq((v_result->>'code')::int,200,'an occasion manager can issue a login QR for a current participant');
  v_result:=public.get_reception_occasion_users_v1(v_occasion,'existing');
  PERFORM assert_eq(jsonb_array_length(v_result),1,'an occasion manager can search the current participant roster');
  PERFORM assert_eq(v_result->0->>'userId',v_existing::text,'manager roster search returns the matching participant identity');

  PERFORM set_config('request.jwt.claim.sub',v_receptionist::text,true);
  v_result:=public.create_reception_user_v1(
    v_occasion,gen_random_uuid(),
    jsonb_build_object('name','Existing','surname','Participant','email','existing@test.local','sex','female'),
    NULL,NULL,false
  );
  PERFORM assert_eq(v_result->>'message','email_already_exists','a receptionist cannot resolve an existing identity through the create form');
  v_result:=public.issue_reception_login_qr_v1(v_occasion,v_existing);
  PERFORM assert_eq(v_result->>'message','registration_unavailable','a receptionist cannot issue a login QR for an arbitrary participant');
  PERFORM assert_eq(public.get_reception_occasion_users_v1(v_occasion,'existing'),'[]'::jsonb,'a receptionist cannot search the participant roster');
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);

  INSERT INTO public.organization_users(organization,"user",is_admin) VALUES(v_org,v_admin,true);
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  v_result:=public.get_reception_occasion_users_v1(v_occasion,'existing');
  PERFORM assert_eq(jsonb_array_length(v_result),1,'an admin without a reception or manager role can search the participant roster');
  PERFORM assert_eq(v_result->0->>'userId',v_existing::text,'admin roster search returns the matching participant identity');
  v_result:=public.issue_reception_login_qr_v1(v_occasion,v_existing);
  PERFORM assert_eq((v_result->>'code')::int,200,'an admin without a reception or manager role can issue a login QR for any current participant');
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);

  v_result:=public.create_reception_user_v1(v_occasion,gen_random_uuid(),jsonb_build_object('name','Duplicate','surname','Account','email','admin@test.local','sex','unspecified'),NULL,NULL,false);
  PERFORM assert_eq(v_result->>'message','email_already_exists','an existing organization identity outside the occasion is not implicitly added');

  v_result:=public.create_reception_user_v1(
    v_occasion,v_duplicate_command,
    jsonb_build_object('name','New','surname','Person','email','other@test.local','sex','female'),
    NULL,NULL,false
  );
  PERFORM assert_eq(v_result->>'message','same_name_confirmation_required','exact name match requires explicit confirmation');
  PERFORM assert_true(jsonb_array_length(v_result->'candidates') BETWEEN 1 AND 10,'exact-name disclosure is bounded');
  PERFORM assert_false((v_result->'candidates'->0) ? 'userId','candidate does not disclose an identity UUID');
  PERFORM assert_true((v_result->'candidates'->0->>'email') LIKE '%***@%','candidate e-mail is masked');
  v_result:=public.create_reception_user_v1(
    v_occasion,v_duplicate_command,
    jsonb_build_object('name','New','surname','Person','email','other@test.local','sex','female'),
    NULL,NULL,true
  );
  PERFORM assert_eq((v_result->>'code')::int,200,'explicit confirmation creates the distinct identity');

  v_result:=public.issue_reception_login_qr_v1(v_occasion,v_created); v_first_payload:=v_result->>'payload';
  PERFORM assert_true(v_first_payload LIKE 'festapp-login:v1:'||v_occasion||':%','issue returns only typed opaque payload');
  v_first_manual_code:=v_result->>'manualCode';
  PERFORM assert_true(v_first_manual_code ~ '^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$','issue returns an unambiguous human-readable fallback code');
  PERFORM assert_eq((SELECT length(token_hash) FROM public.user_login_qr_credentials WHERE occasion=v_occasion AND "user"=v_created),64,'database stores a SHA-256 hash only');
  PERFORM assert_eq((SELECT length(manual_token_hash) FROM public.user_login_qr_credentials WHERE occasion=v_occasion AND "user"=v_created),64,'database stores only the fallback code hash');
  PERFORM assert_false((SELECT token_hash=v_first_payload FROM public.user_login_qr_credentials WHERE occasion=v_occasion AND "user"=v_created),'plaintext is not persisted');
  PERFORM assert_false((SELECT manual_token_hash=v_first_manual_code FROM public.user_login_qr_credentials WHERE occasion=v_occasion AND "user"=v_created),'fallback code plaintext is not persisted');
  v_result:=public.issue_reception_login_qr_v1(v_occasion,v_created); v_second_payload:=v_result->>'payload'; v_second_manual_code:=v_result->>'manualCode';
  PERFORM assert_true(v_first_payload<>v_second_payload,'rotation replaces the plaintext credential');
  PERFORM assert_true(v_first_manual_code<>v_second_manual_code,'rotation replaces the manual fallback code');

  v_second_token:=split_part(v_second_payload,':',4);
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  v_result:=public.resolve_reception_login_qr_v1(
    v_occasion,encode(digest(v_second_token,'sha256'),'hex')
  );
  PERFORM assert_eq(
    v_result->>'authEmail',
    (SELECT email FROM auth.users WHERE id=v_created),
    'issued QR resolves to the canonical Auth identity'
  );
  PERFORM assert_true(
    public.resolve_reception_login_qr_v1(
      v_occasion,encode(digest(replace(v_first_manual_code,'-',''),'sha256'),'hex')
    ) IS NULL,
    'rotation invalidates the previous manual fallback code'
  );
  v_result:=public.resolve_reception_login_qr_v1(
    v_occasion,encode(digest(replace(v_second_manual_code,'-',''),'sha256'),'hex')
  );
  PERFORM assert_eq(v_result->>'authEmail',(SELECT email FROM auth.users WHERE id=v_created),'current manual fallback code resolves to the same Auth identity');
  PERFORM public.mark_reception_login_qr_used_v1(
    v_occasion,encode(digest(replace(v_second_manual_code,'-',''),'sha256'),'hex')
  );
  PERFORM assert_true(
    public.resolve_reception_login_qr_v1(
      v_occasion,encode(digest(replace(v_second_manual_code,'-',''),'sha256'),'hex')
    ) IS NULL,
    'manual fallback code is single-use after a successful exchange'
  );
  PERFORM public.mark_reception_login_qr_used_v1(
    v_occasion,encode(digest(v_second_token,'sha256'),'hex')
  );
  PERFORM assert_eq(
    (SELECT use_count FROM public.user_login_qr_credentials
      WHERE occasion=v_occasion AND "user"=v_created),
    2::bigint,
    'successful QR and manual exchanges both record credential use'
  );
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  v_result:=public.revoke_reception_login_qr_v1(v_occasion,v_created);
  PERFORM assert_eq((v_result->>'code')::int,200,'owner can explicitly revoke the issued login QR');
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM assert_true(
    public.resolve_reception_login_qr_v1(
      v_occasion,encode(digest(v_second_token,'sha256'),'hex')
    ) IS NULL,
    'revoked QR cannot be resolved into a login identity'
  );
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  v_result:=public.issue_reception_login_qr_v1(v_occasion,v_created);
  PERFORM assert_eq((v_result->>'code')::int,200,'issuing after revoke creates a fresh active credential');

  v_result:=public.cancel_reception_registration_v1(v_occasion,v_created);
  PERFORM assert_eq(v_result->>'status','domain_blocked_auth_revocation_pending','domain is blocked before auth revocation');
  PERFORM assert_false(EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=v_occasion AND "user"=v_created),'cancel removes membership');
  PERFORM assert_false(EXISTS(SELECT 1 FROM public.user_login_qr_credentials WHERE occasion=v_occasion AND "user"=v_created),'membership cascade removes QR');

  UPDATE public.occasions SET features='[{"code":"reception","is_enabled":false}]' WHERE id=v_occasion;
  PERFORM assert_false(public.get_can_use_reception(v_occasion),'feature disable closes backend capability');
  PERFORM assert_false(has_table_privilege('authenticated','public.user_login_qr_credentials','SELECT'),'credential table has no client read access');
END $$;
