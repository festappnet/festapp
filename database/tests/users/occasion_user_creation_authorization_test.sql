BEGIN;
DO $$
DECLARE
  actor uuid;
  org bigint;
  unit_id bigint;
  occasion_id bigint;
  response jsonb;
  command_id uuid := gen_random_uuid();
  profile jsonb;
  created_user uuid;
  second_occasion bigint;
BEGIN
  PERFORM public.create_user_for_test('user-create-admin', 'user-create-admin@example.invalid');
  actor := public.get_user_id('user-create-admin');
  INSERT INTO public.organizations(title) VALUES ('User creation') RETURNING id INTO org;
  UPDATE public.user_info SET organization = org WHERE id = actor;
  INSERT INTO public.units(title, organization) VALUES ('User creation', org) RETURNING id INTO unit_id;
  INSERT INTO public.occasions(title, organization, unit, link, start_time, end_time)
    VALUES ('User creation', org, unit_id, gen_random_uuid()::text, now(), now() + interval '1 day')
    RETURNING id INTO occasion_id;
  INSERT INTO public.organization_users(organization, "user", is_admin)
    VALUES (org, actor, true);
  PERFORM set_config('request.jwt.claim.sub', actor::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  SET LOCAL ROLE authenticated;
  ASSERT public.can_manage_occasion_participants(occasion_id), 'Administrator can manage participants';
  profile := jsonb_build_object(
      'occasion', occasion_id,
      'data', jsonb_build_object('email', 'new-admin-participant@example.invalid', 'name', 'Jana', 'surname', 'Nováková')
    );
  response := public.create_occasion_user_client_sync_v1(occasion_id, command_id, profile);
  ASSERT response->>'status' = 'applied', format('Administrator creation failed: %s', response);
  ASSERT public.create_occasion_user_client_sync_v1(occasion_id, command_id, profile) = response,
    'Retry must return the saved creation receipt';
  RESET ROLE;
  ASSERT EXISTS (SELECT 1 FROM public.occasion_users
    WHERE occasion = occasion_id AND "user" = (response#>>'{data,userId}')::uuid),
    'Created participant must be saved';
  ASSERT EXISTS (SELECT 1 FROM public.user_info
    WHERE id = (response#>>'{data,userId}')::uuid AND name = 'Jana' AND surname = 'Nováková'),
    'Created profile must retain the entered name';

  created_user := (response#>>'{data,userId}')::uuid;
  INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
    VALUES ('Existing account target',org,unit_id,gen_random_uuid()::text,now(),now()+interval '1 day')
    RETURNING id INTO second_occasion;
  SET LOCAL ROLE authenticated;
  response := public.create_occasion_user_client_sync_v1(second_occasion,gen_random_uuid(),
    jsonb_build_object('occasion',second_occasion,'data',jsonb_build_object(
      'email','  NEW-ADMIN-PARTICIPANT@EXAMPLE.INVALID  ', 'name','Jana','surname','Nováková')));
  ASSERT response->>'status'='applied', format('Existing mixed-case address failed: %s',response);
  ASSERT (response#>>'{data,userId}')::uuid=created_user,'Existing address must reuse its account';
  RESET ROLE;
  ASSERT (SELECT count(*) FROM public.occasion_users WHERE occasion=second_occasion AND "user"=created_user)=1,
    'Existing account must be added exactly once';
  SET LOCAL ROLE authenticated;

  -- The released grid includes every editable field, even an unset role.
  response := public.create_occasion_user_client_sync_v1(occasion_id, gen_random_uuid(),
    jsonb_build_object('occasion',occasion_id,'user',NULL,'role',NULL,
      'is_manager',true,'is_editor',true,'is_editor_view',true,
      'is_editor_order',true,'is_editor_order_view',true,
      'is_approved',false,'is_approver',false,'is_cleaning_crew',false,
      'is_cleaning_blocked',false,'is_receptionist',false,
      'services',jsonb_build_object('accommodation','{}'::jsonb),
      'data',jsonb_build_object('email','grid-participant@example.invalid',
        'name','Marek','surname','Novák','sex','unknown','phone',NULL,
        'birthDate',NULL,'is_volunteer',false,'app_links_sent',false)));
  ASSERT response->>'status' = 'applied', format('Complete grid creation failed: %s', response);

  RESET ROLE;

  -- Losing administrator rights must block both receipt replay and new writes.
  UPDATE public.organization_users SET is_admin = false WHERE organization = org AND "user" = actor;
  SET LOCAL ROLE authenticated;
  BEGIN
    PERFORM public.create_occasion_user_client_sync_v1(occasion_id, command_id, profile);
    RAISE EXCEPTION 'Revoked administrator replay accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.create_occasion_user_client_sync_v1(occasion_id, gen_random_uuid(), profile);
    RAISE EXCEPTION 'Unprivileged creation accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RESET ROLE;
  ASSERT NOT has_function_privilege('authenticated', 'public.update_user_internal_v1(jsonb)', 'EXECUTE'),
    'Internal writer must remain private';
END $$;
ROLLBACK;
