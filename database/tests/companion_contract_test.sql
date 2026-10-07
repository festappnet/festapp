BEGIN;

DO $$
DECLARE
  v_signature regprocedure;
BEGIN
  FOREACH v_signature IN ARRAY ARRAY[
    'public.add_user_to_occasion_internal_v1(bigint,uuid)'::regprocedure,
    'public.get_is_editor_on_unit(bigint)'::regprocedure,
    'public.get_is_editor_order_on_occasion(bigint)'::regprocedure
  ] LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_proc
      WHERE oid=v_signature
        AND proconfig @> ARRAY['search_path=public, extensions']
    ) THEN
      RAISE EXCEPTION 'Companion dependency % lacks its trusted search_path',
        v_signature;
    END IF;
  END LOOP;
END $$;

DO $$
DECLARE v_privilege text;
  v_definition text;
BEGIN
  PERFORM assert_true(to_regprocedure('public.get_user_companions_data()') IS NULL,
    'occasion-less companion reader is absent');
  PERFORM assert_true(to_regprocedure('public.create_companion(bigint,uuid,text)') IS NULL,
    'drift-only create RPC is absent');
  PERFORM assert_true(to_regprocedure(
    'public.delete_companion_client_sync_v1(bigint,uuid,uuid)') IS NULL,
    'obsolete generic companion delete is absent');
  PERFORM assert_true(to_regprocedure('public.delete_user(uuid,bigint)') IS NULL,
    'generic account-delete facade is absent');
  PERFORM assert_true(to_regprocedure(
    'public.assign_existing_companion_client_sync_v1(bigint,uuid,uuid,uuid)') IS NOT NULL,
    'canonical admin assign exists');
  PERFORM assert_true(to_regprocedure(
    'public.unassign_existing_companion_client_sync_v1(bigint,uuid,uuid,uuid)') IS NOT NULL,
    'canonical admin unassign exists');
  PERFORM assert_true(to_regprocedure(
    'public.get_can_assign_companions_on_occasion(bigint)') IS NOT NULL,
    'canonical companion assignment permission exists');
  PERFORM assert_true((SELECT relrowsecurity FROM pg_class
      WHERE oid='public.user_companions'::regclass),
    'user_companions has RLS enabled');
  FOREACH v_privilege IN ARRAY ARRAY[
    'SELECT','INSERT','UPDATE','DELETE','TRUNCATE','TRIGGER','REFERENCES'
  ] LOOP
    PERFORM assert_true(NOT has_table_privilege(
      'anon','public.user_companions',v_privilege),
      'anon has no user_companions '||v_privilege);
    PERFORM assert_true(NOT has_table_privilege(
      'authenticated','public.user_companions',v_privilege),
      'authenticated has no user_companions '||v_privilege);
  END LOOP;
  PERFORM assert_true(EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='user_companions'
      AND column_name='occasion' AND is_nullable='NO'),
    'relation is occasion scoped');
  PERFORM assert_true(EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='user_companions'
      AND column_name='origin' AND is_nullable='NO'),
    'relation records origin');

  SELECT pg_get_functiondef(to_regprocedure(
    'public.set_event_attendance_client_sync_v1(bigint,uuid,text,uuid)'))
    INTO v_definition;
  PERFORM assert_true(v_definition LIKE '%c.occasion=v_occasion%',
    'attendance relation lookup is occasion scoped');
  PERFORM assert_true(v_definition LIKE '%get_companion_feature_policy_v1%',
    'attendance enforces the companion master gate');
  PERFORM assert_true(to_regprocedure(
    'public.set_event_attendance_internal_v1(bigint,uuid,text,uuid)') IS NULL,
    'attendance has one canonical implementation owner');

  SELECT pg_get_functiondef(to_regprocedure(
    'public.create_companion_client_sync_v1(bigint,text,uuid)'))
    INTO v_definition;
  PERFORM assert_true(v_definition LIKE '%uc.occasion=p_occasion%',
    'self-create detects the created relation inside the target occasion');

  SELECT pg_get_functiondef(to_regprocedure(
    'public.get_private_profile_payload_v1(bigint,uuid)'))
    INTO v_definition;
  PERFORM assert_true(v_definition LIKE '%companion_membership.services%',
    'private companion profile projects canonical participant services');

  SELECT pg_get_functiondef(to_regprocedure(
    'public.save_profile_client_sync_v1(bigint,uuid,uuid,bigint,jsonb)'))
    INTO v_definition;
  PERFORM assert_true(v_definition LIKE '%impact_companion_owners_v1%',
    'normal participant profile changes invalidate the companion owner');

  SELECT pg_get_functiondef(to_regprocedure(
    'public.import_profiles_client_sync_v1(bigint,uuid,jsonb,jsonb)'))
    INTO v_definition;
  PERFORM assert_true(v_definition LIKE '%group_profile_impacts_internal_v1%' AND v_definition LIKE '%v_old_impacts%',
    'profile import invalidates companion owners');

  SELECT pg_get_functiondef(to_regprocedure(
    'public.delete_occasion_user_client_sync_v1(bigint,uuid,uuid,bigint)'))
    INTO v_definition;
  PERFORM assert_true(v_definition LIKE '%remove_occasion_user_domain_internal_v1%',
    'occasion-member deletion invalidates companion owners before cascade');

  SELECT pg_get_functiondef(to_regprocedure(
    'public.get_all_user_basics_for_scan(text)')) INTO v_definition;
  PERFORM assert_true(v_definition LIKE '%uc.occasion=oid%',
    'scan reader does not apply a global companion relation');
  SELECT pg_get_functiondef(to_regprocedure(
    'public.get_all_user_basics_from_occasion(bigint)')) INTO v_definition;
  PERFORM assert_true(v_definition LIKE '%uc.occasion=oc%',
    'occasion reader scopes companion metadata');
  SELECT pg_get_functiondef(to_regprocedure(
    'public.get_user_info_for_users(uuid[],bigint)')) INTO v_definition;
  PERFORM assert_true(v_definition LIKE '%uc.occasion=oc%',
    'user-info reader scopes companion metadata');
  SELECT pg_get_functiondef(to_regprocedure(
    'public.get_users_from_occasion_with_orders(bigint)')) INTO v_definition;
  PERFORM assert_true(v_definition LIKE '%uc.occasion=oc%',
    'order reader scopes companions');
  SELECT pg_get_functiondef(to_regprocedure(
    'public.sign_user_to_event(bigint,uuid)')) INTO v_definition;
  PERFORM assert_true(v_definition LIKE '%ce.occasion=uc.occasion%'
      AND v_definition LIKE '%get_companion_feature_policy_v1%',
    'legacy sign-in enforces occasion scope and feature gate');
  SELECT pg_get_functiondef(to_regprocedure(
    'public.sign_user_out_of_event(bigint,uuid)')) INTO v_definition;
  PERFORM assert_true(v_definition LIKE '%ce.occasion=uc.occasion%'
      AND v_definition LIKE '%get_companion_feature_policy_v1%',
    'legacy sign-out enforces occasion scope and feature gate');
END $$;

INSERT INTO public.organizations(id,title)
VALUES (990001,'Companion contract organization');
INSERT INTO public.units(id,title,organization)
VALUES (990001,'Companion contract unit',990001);
INSERT INTO public.occasions(
  id,title,link,organization,unit,start_time,end_time,features
) VALUES
  (990001,'Companion contract A','companion-contract-a',990001,990001,
    now(),now()+interval '1 day',jsonb_build_array(jsonb_build_object(
      'code','companions','is_enabled',false,'max_companions',1,
      'allow_user_create',true,'allow_admin_assign',true))),
  (990002,'Companion contract B','companion-contract-b',990001,990001,
    now(),now()+interval '1 day',jsonb_build_array(jsonb_build_object(
      'code','companions','is_enabled',true,'max_companions',1,
      'allow_user_create',true,'allow_admin_assign',true)));

INSERT INTO auth.users(id,email) VALUES
  ('99000000-0000-0000-0000-000000000001','manager@companion.test'),
  ('99000000-0000-0000-0000-000000000002','owner@companion.test'),
  ('99000000-0000-0000-0000-000000000003','target@companion.test'),
  ('99000000-0000-0000-0000-000000000004','other@companion.test'),
  ('99000000-0000-0000-0000-000000000005','editor@companion.test'),
  ('99000000-0000-0000-0000-000000000006','unit-editor@companion.test');
INSERT INTO public.user_info(id,email_readonly,name,surname,organization) VALUES
  ('99000000-0000-0000-0000-000000000001','manager@companion.test','Manager','Test',990001),
  ('99000000-0000-0000-0000-000000000002','owner@companion.test','Owner','Test',990001),
  ('99000000-0000-0000-0000-000000000003','target@companion.test','Target','Test',990001),
  ('99000000-0000-0000-0000-000000000004','other@companion.test','Other','Test',990001),
  ('99000000-0000-0000-0000-000000000005','editor@companion.test','Editor','Test',990001),
  ('99000000-0000-0000-0000-000000000006','unit-editor@companion.test','Unit editor','Test',990001);
INSERT INTO public.occasion_users(occasion,"user",is_manager,is_editor) VALUES
  (990001,'99000000-0000-0000-0000-000000000001',true,true),
  (990001,'99000000-0000-0000-0000-000000000002',false,false),
  (990001,'99000000-0000-0000-0000-000000000003',false,false),
  (990001,'99000000-0000-0000-0000-000000000004',false,false),
  (990001,'99000000-0000-0000-0000-000000000005',false,true),
  (990001,'99000000-0000-0000-0000-000000000006',false,false),
  (990002,'99000000-0000-0000-0000-000000000002',false,false),
  (990002,'99000000-0000-0000-0000-000000000003',false,false);
INSERT INTO public.unit_users(unit,"user",is_editor)
VALUES (990001,'99000000-0000-0000-0000-000000000006',true);
UPDATE public.occasion_users
SET services='{"accommodation":{"room-a":"paid"}}'::jsonb
WHERE occasion=990001
  AND "user"='99000000-0000-0000-0000-000000000003';
INSERT INTO public.user_group_info(id,title,occasion)
VALUES (990001,'Fixture discussion group',990001);
INSERT INTO public.user_groups("user","group")
VALUES ('99000000-0000-0000-0000-000000000003',990001);
SELECT set_config('request.jwt.claim.sub',
  '99000000-0000-0000-0000-000000000001',true);

DO $$
BEGIN
  BEGIN
    PERFORM public.assign_existing_companion_client_sync_v1(
      990001,'99000000-0000-0000-0000-000000000002',
      '99000000-0000-0000-0000-000000000003',
      '99000000-0000-0000-0000-000000000101');
    PERFORM assert_fail('disabled feature accepted admin assignment');
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;

UPDATE public.occasions SET features=jsonb_build_array(jsonb_build_object(
  'code','companions','is_enabled',true,'max_companions',1,
  'allow_user_create',false,'allow_admin_assign',false)) WHERE id=990001;
DO $$
DECLARE v_result jsonb;
BEGIN
  BEGIN
    PERFORM public.assign_existing_companion_client_sync_v1(
      990001,'99000000-0000-0000-0000-000000000002',
      '99000000-0000-0000-0000-000000000003',
      '99000000-0000-0000-0000-000000000110');
    PERFORM assert_fail('disabled admin capability accepted assignment');
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  PERFORM set_config('request.jwt.claim.sub',
    '99000000-0000-0000-0000-000000000002',true);
  v_result:=public.create_companion_client_sync_v1(
    990001,'Blocked self create','99000000-0000-0000-0000-000000000111');
  PERFORM assert_eq(v_result->>'status','rejected',
    'disabled self-create capability rejects the command');
  PERFORM assert_eq((v_result->>'code')::integer,403,
    'disabled self-create capability returns forbidden');
  PERFORM set_config('request.jwt.claim.sub',
    '99000000-0000-0000-0000-000000000001',true);
END $$;

UPDATE public.occasions SET features=jsonb_build_array(jsonb_build_object(
  'code','companions','is_enabled',true,'max_companions',1,
  'allow_user_create',true,'allow_admin_assign',true)) WHERE id=990001;

DO $$
DECLARE v_result jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',
    '99000000-0000-0000-0000-000000000002',true);
  BEGIN
    PERFORM public.assign_existing_companion_client_sync_v1(
      990001,'99000000-0000-0000-0000-000000000002',
      '99000000-0000-0000-0000-000000000003',
      '99000000-0000-0000-0000-000000000120');
    PERFORM assert_fail('plain participant accepted companion assignment');
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  PERFORM set_config('request.jwt.claim.sub',
    '99000000-0000-0000-0000-000000000005',true);
  v_result:=public.assign_existing_companion_client_sync_v1(
    990001,'99000000-0000-0000-0000-000000000002',
    '99000000-0000-0000-0000-000000000003',
    '99000000-0000-0000-0000-000000000121');
  PERFORM assert_eq(v_result->>'status','applied',
    'occasion editor can assign a companion');
  v_result:=public.unassign_existing_companion_client_sync_v1(
    990001,'99000000-0000-0000-0000-000000000002',
    '99000000-0000-0000-0000-000000000003',
    '99000000-0000-0000-0000-000000000122');
  PERFORM assert_eq(v_result->>'status','applied',
    'occasion editor can unassign a companion');

  PERFORM set_config('request.jwt.claim.sub',
    '99000000-0000-0000-0000-000000000006',true);
  BEGIN
    PERFORM public.assign_existing_companion_client_sync_v1(
      990001,'99000000-0000-0000-0000-000000000002',
      '99000000-0000-0000-0000-000000000003',
      '99000000-0000-0000-0000-000000000123');
    PERFORM assert_fail('unit role bypassed canonical occasion editor permission');
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  UPDATE public.occasion_users SET is_editor=true
  WHERE occasion=990001
    AND "user"='99000000-0000-0000-0000-000000000006';
  v_result:=public.assign_existing_companion_client_sync_v1(
    990001,'99000000-0000-0000-0000-000000000002',
    '99000000-0000-0000-0000-000000000003',
    '99000000-0000-0000-0000-000000000125');
  PERFORM assert_eq(v_result->>'status','applied',
    'inherited occasion editor can assign a companion');
  v_result:=public.unassign_existing_companion_client_sync_v1(
    990001,'99000000-0000-0000-0000-000000000002',
    '99000000-0000-0000-0000-000000000003',
    '99000000-0000-0000-0000-000000000126');
  PERFORM assert_eq(v_result->>'status','applied',
    'inherited occasion editor can unassign a companion');

  PERFORM set_config('request.jwt.claim.sub',
    '99000000-0000-0000-0000-000000000001',true);
END $$;

DO $$
DECLARE v_result jsonb; v_profile jsonb; v_companion jsonb;
BEGIN
  v_result:=public.assign_existing_companion_client_sync_v1(
    990001,'99000000-0000-0000-0000-000000000002',
    '99000000-0000-0000-0000-000000000003',
    '99000000-0000-0000-0000-000000000102');
  PERFORM assert_eq(v_result->>'status','applied',
    'admin assignment is applied');
  PERFORM assert_true(EXISTS (SELECT 1 FROM public.user_companions uc
    WHERE uc.occasion=990001
      AND uc."user"='99000000-0000-0000-0000-000000000002'
      AND uc.companion='99000000-0000-0000-0000-000000000003'
      AND uc.origin='admin_assigned'),'assignment records occasion and origin');

  v_profile:=public.get_private_profile_payload_v1(
    990001,'99000000-0000-0000-0000-000000000002');
  v_companion:=v_profile->'companions'->0;
  PERFORM assert_eq(
    v_companion->'services'->'accommodation'->>'room-a','paid',
    'companion profile uses the normal participant accommodation assignment');
  PERFORM assert_eq(v_companion->>'group_title','Fixture discussion group',
    'companion profile includes the normal participant discussion group');

  v_result:=public.assign_existing_companion_client_sync_v1(
    990001,'99000000-0000-0000-0000-000000000002',
    '99000000-0000-0000-0000-000000000003',
    '99000000-0000-0000-0000-000000000103');
  PERFORM assert_eq(v_result->>'status','unchanged',
    'repeated assignment is idempotent');

  BEGIN
    PERFORM public.assign_existing_companion_client_sync_v1(
      990001,'99000000-0000-0000-0000-000000000002',
      '99000000-0000-0000-0000-000000000004',
      '99000000-0000-0000-0000-000000000104');
    PERFORM assert_fail('owner limit was not enforced');
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    PERFORM public.assign_existing_companion_client_sync_v1(
      990001,'99000000-0000-0000-0000-000000000003',
      '99000000-0000-0000-0000-000000000004',
      '99000000-0000-0000-0000-000000000105');
    PERFORM assert_fail('companion chain was not rejected');
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    PERFORM public.assign_existing_companion_client_sync_v1(
      990001,'99000000-0000-0000-0000-000000000004',
      '99000000-0000-0000-0000-000000000003',
      '99000000-0000-0000-0000-000000000106');
    PERFORM assert_fail('second owner was not rejected');
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  v_result:=public.unassign_existing_companion_client_sync_v1(
    990001,'99000000-0000-0000-0000-000000000002',
    '99000000-0000-0000-0000-000000000003',
    '99000000-0000-0000-0000-000000000107');
  PERFORM assert_eq(v_result->>'status','applied','admin unassignment is applied');
  PERFORM assert_true(EXISTS (SELECT 1 FROM public.user_info
    WHERE id='99000000-0000-0000-0000-000000000003'),
    'admin unassignment preserves the participant account');
  PERFORM assert_true(EXISTS (SELECT 1 FROM public.occasion_users
    WHERE occasion=990001
      AND "user"='99000000-0000-0000-0000-000000000003'),
    'admin unassignment preserves occasion membership');
END $$;

INSERT INTO public.user_companions(occasion,"user",companion,origin,created_by)
VALUES (990001,'99000000-0000-0000-0000-000000000002',
  '99000000-0000-0000-0000-000000000003','admin_assigned',
  '99000000-0000-0000-0000-000000000001');
SELECT set_config('request.jwt.claim.sub',
  '99000000-0000-0000-0000-000000000002',true);
INSERT INTO public.events(id,title,start_time,end_time,occasion)
VALUES (990001,'Companion attendance visibility',now()+interval '1 hour',
  now()+interval '2 hours',990001);
DO $$
DECLARE v_result jsonb; v_owner_profile jsonb; v_companion_sync jsonb;
  v_companion_program jsonb;
BEGIN
  v_result:=public.set_event_attendance_client_sync_v1(
    990001,'99000000-0000-0000-0000-000000000003','sign_in',
    '99000000-0000-0000-0000-000000000114');
  PERFORM assert_eq(v_result->>'status','applied',
    'owner can sign the assigned companion into an event');
  PERFORM assert_true(EXISTS (SELECT 1 FROM public.event_users
    WHERE event=990001
      AND "user"='99000000-0000-0000-0000-000000000003'),
    'companion attendance is stored under the companion identity');

  v_owner_profile:=public.get_private_profile_payload_v1(
    990001,'99000000-0000-0000-0000-000000000002');
  PERFORM assert_true((v_owner_profile->'companions'->0->'event_ids')
      @> '[990001]'::jsonb,
    'owner private profile immediately contains companion attendance');

  PERFORM set_config('request.jwt.claim.sub',
    '99000000-0000-0000-0000-000000000003',true);
  v_companion_sync:=public.get_private_client_sync_v1(
    jsonb_build_object('organizationId',990001,'occasionId',990001),'{}');
  SELECT component->'payload' INTO v_companion_program
  FROM jsonb_array_elements(v_companion_sync#>'{data,components}') component
  WHERE component->>'component'='private_program';
  PERFORM assert_true((v_companion_program->'signedIn') @> '[990001]'::jsonb,
    'companion self-login receives brother-created attendance');
  PERFORM set_config('request.jwt.claim.sub',
    '99000000-0000-0000-0000-000000000002',true);
END $$;
DO $$
BEGIN
  BEGIN
    PERFORM public.delete_owned_companion_client_sync_v1(
      990001,'99000000-0000-0000-0000-000000000003',
      '99000000-0000-0000-0000-000000000108');
    PERFORM assert_fail('admin-assigned account was accepted by self-delete');
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  PERFORM assert_true(EXISTS (SELECT 1 FROM public.user_info
    WHERE id='99000000-0000-0000-0000-000000000003'),
    'rejected old-client delete preserves account data');
END $$;

SELECT set_config('request.jwt.claim.sub',
  '99000000-0000-0000-0000-000000000001',true);
SELECT public.unassign_existing_companion_client_sync_v1(
  990001,'99000000-0000-0000-0000-000000000002',
  '99000000-0000-0000-0000-000000000003',
  '99000000-0000-0000-0000-000000000112');
INSERT INTO public.user_companions(occasion,"user",companion,origin,created_by)
VALUES (990001,'99000000-0000-0000-0000-000000000002',
  '99000000-0000-0000-0000-000000000004','self_created',
  '99000000-0000-0000-0000-000000000002');
SELECT set_config('request.jwt.claim.sub',
  '99000000-0000-0000-0000-000000000002',true);
DO $$
DECLARE v_result jsonb;
BEGIN
  v_result:=public.delete_owned_companion_client_sync_v1(
    990001,'99000000-0000-0000-0000-000000000004',
    '99000000-0000-0000-0000-000000000113');
  PERFORM assert_eq(v_result->>'status','applied',
    'self-created companion delete is applied');
  PERFORM assert_true(NOT EXISTS (SELECT 1 FROM public.user_info
    WHERE id='99000000-0000-0000-0000-000000000004'),
    'self-created delete removes its technical account');
END $$;

INSERT INTO public.events(id,title,start_time,end_time,occasion)
VALUES (990002,'Cross-occasion event',now(),now()+interval '1 hour',990002);
DO $$
BEGIN
  BEGIN
    PERFORM public.set_event_attendance_client_sync_v1(
      990002,'99000000-0000-0000-0000-000000000003','sign_in',
      '99000000-0000-0000-0000-000000000109');
    PERFORM assert_fail('cross-occasion companion attendance was accepted');
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;

ROLLBACK;
