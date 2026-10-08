BEGIN;
SELECT create_user_for_test('landing_admin', 'landing-admin@test.invalid');
SELECT create_user_for_test('landing_reader', 'landing-reader@test.invalid');
DO $$
DECLARE
  org bigint; other_org bigint; unit_id bigint; other_unit bigint;
  first_oc bigint; second_oc bigint; closed_oc bigint; foreign_oc bigint;
  result jsonb;
BEGIN
  INSERT INTO organizations(title, data) VALUES ('Landing test', '{"IS_APP_SUPPORTED":true,"APP_NAME":"Keep me"}') RETURNING id INTO org;
  INSERT INTO organizations(title, data) VALUES ('Other landing org', '{}') RETURNING id INTO other_org;
  INSERT INTO units(title, organization) VALUES ('Landing unit',org) RETURNING id INTO unit_id;
  INSERT INTO units(title, organization) VALUES ('Other unit',other_org) RETURNING id INTO other_unit;
  INSERT INTO organization_users("user",organization,is_admin) VALUES (get_user_id('landing_admin'),org,true);
  INSERT INTO unit_users("user",unit,is_editor_view,is_manager) VALUES (get_user_id('landing_reader'),unit_id,true,true);
  INSERT INTO occasions(title,link,organization,unit,start_time,end_time) VALUES ('First','landing-first',org,unit_id,now(),now()+interval '1 day') RETURNING id INTO first_oc;
  INSERT INTO occasions(title,link,organization,unit,start_time,end_time) VALUES ('Second','landing-second',org,unit_id,now(),now()+interval '1 day') RETURNING id INTO second_oc;
  INSERT INTO occasions(title,link,organization,unit,start_time,end_time,is_open) VALUES ('Closed','landing-closed',org,unit_id,now(),now()+interval '1 day',false) RETURNING id INTO closed_oc;
  INSERT INTO occasions(title,link,organization,unit,start_time,end_time) VALUES ('Foreign','landing-foreign',other_org,other_unit,now(),now()+interval '1 day') RETURNING id INTO foreign_oc;
  UPDATE organizations SET data=data||jsonb_build_object('DEFAULT_OCCASION',first_oc) WHERE id=org;
  PERFORM set_config('request.jwt.claim.sub',get_user_id('landing_admin')::text,true);
  result := get_unit_app_landing(unit_id);
  PERFORM assert_eq((result->>'occasion_id')::bigint,first_oc,'Legacy default is visible');
  result := set_unit_app_landing(unit_id,second_oc,first_oc);
  PERFORM assert_eq((result->>'occasion_id')::bigint,second_oc,'Switch to second occasion');
  BEGIN
    PERFORM set_unit_app_landing(unit_id,first_oc,first_oc);
    RAISE EXCEPTION 'Stale write accepted';
  EXCEPTION WHEN serialization_failure THEN NULL; END;
  BEGIN
    PERFORM set_unit_app_landing(unit_id,foreign_oc,second_oc);
    RAISE EXCEPTION 'Foreign occasion accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM set_unit_app_landing(unit_id,closed_oc,second_oc);
    RAISE EXCEPTION 'Closed occasion accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  result := set_unit_app_landing(unit_id,NULL,second_oc);
  PERFORM assert_true(result->>'occasion_id' IS NULL,'Clear opens overview');
  PERFORM assert_eq((SELECT data FROM organizations WHERE id=org),'{"IS_APP_SUPPORTED":true,"APP_NAME":"Keep me"}'::jsonb,'Clear removes both defaults and preserves unrelated data');
  result := set_unit_app_landing(unit_id,first_oc,NULL);
  PERFORM assert_eq((result->>'occasion_id')::bigint,first_oc,'Set from overview');
  PERFORM set_config('request.jwt.claim.sub',get_user_id('landing_reader')::text,true);
  result := get_unit_app_landing(unit_id);
  PERFORM assert_eq((result->>'can_manage')::boolean,false,'Unit manager does not gain organization admin rights');
  BEGIN
    PERFORM set_unit_app_landing(unit_id,NULL,first_oc);
    RAISE EXCEPTION 'Unauthorized write accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM get_unit_app_landing(other_unit);
    RAISE EXCEPTION 'Foreign read accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claim.sub','',true);
  BEGIN
    PERFORM get_unit_app_landing(unit_id);
    RAISE EXCEPTION 'Anonymous read accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
