-- test-setup: database/tests/helpers/form_measurement_fixture.sql
DO $$
DECLARE x jsonb:=pg_temp.fixture(NULL); un bigint:=(x->>'unit')::bigint; fid bigint:=(x->>'form')::bigint;
 org bigint:=(x->>'organization')::bigint; before_policy jsonb; after_policy jsonb; receipt jsonb; version bigint:=0;
 value jsonb; rejected boolean; origin text:='https://unit-consent-test.pages.dev';
BEGIN
 INSERT INTO public.form_link_reservations(slug,form) VALUES(x->>'link',fid);
 UPDATE public.forms SET is_open=true,data='{"analytics":{"enabled":true}}' WHERE id=fid;
 INSERT INTO analytics.organization_policy(organization,enabled,revision,operator,reason) VALUES(org,true,1,'fixture','consent');
 INSERT INTO analytics.unit_runtime(unit,runtime_origin,runtime_profile,parent_origins,collector_origins,revision,operator,reason)
 VALUES(un,origin,'gtm-v1',ARRAY['https://tickets.example'],ARRAY['https://www.google-analytics.com'],1,'fixture','consent');
 before_policy:=public.form_measurement_runtime_internal(fid);
 PERFORM assert_eq(before_policy->'required_purposes','["analytics","marketing"]'::jsonb,'mixed profile requires both purposes');
 PERFORM assert_eq(before_policy->'enhanced_conversions_unavailable','true'::jsonb,'enhanced conversions are unavailable');
 PERFORM assert_eq(public.project_configuration_settings_internal_v1('unit',(SELECT to_jsonb(u) FROM public.units u WHERE u.id=un))#>'{settings,measurement_consent_version}','1'::jsonb,'historical aggregate projection defaults to version 1');
 PERFORM assert_eq(public.form_measurement_unit_data_internal(un,'{}')->'measurement_consent_version','1'::jsonb,'public Unit projection defaults to version 1');
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(un,(x->>'actor')::uuid,true)
 ON CONFLICT(unit,"user") DO UPDATE SET is_manager=true;
 PERFORM set_config('request.jwt.claim.sub',x->>'actor',true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 receipt:=public.save_unit_client_sync_v1(un,gen_random_uuid(),0,jsonb_build_object('id',un,'settings',jsonb_build_object('measurement_consent_version',2)));
 PERFORM assert_eq(receipt->>'status','applied','authorized aggregate accepts version increase');
 version:=(receipt#>>'{data,version}')::bigint;
 after_policy:=public.form_measurement_runtime_internal(fid);
 PERFORM assert_true(after_policy->>'processing_revision'<>before_policy->>'processing_revision','version invalidates the stored choice');
 before_policy:=after_policy;
 FOR value IN SELECT jsonb_array_elements('[null,0,-1,1,1.5,"3",2147483648]'::jsonb) LOOP
  rejected:=false;
  BEGIN
   PERFORM public.save_unit_client_sync_v1(un,gen_random_uuid(),version,jsonb_build_object('id',un,'settings',jsonb_build_object('measurement_consent_version',value)));
  EXCEPTION WHEN invalid_parameter_value THEN rejected:=true; END;
  PERFORM assert_true(rejected,'null, decrease, invalid type and out-of-range versions rejected');
 END LOOP;
 receipt:=public.save_unit_client_sync_v1(un,gen_random_uuid(),0,jsonb_build_object('id',un,'settings',jsonb_build_object('measurement_consent_version',3)));
 PERFORM assert_eq(receipt->>'status','conflict','aggregateVersion prevents lost update');
 receipt:=public.save_unit_client_sync_v1(un,gen_random_uuid(),version,jsonb_build_object('id',un,'data',(SELECT data-'measurement_consent_version' FROM public.units WHERE id=un)));
 PERFORM assert_eq((SELECT data->'measurement_consent_version' FROM public.units WHERE id=un),'2'::jsonb,'legacy whole-data omission cannot reset version');
 UPDATE public.units SET data=data||'{"measurement_consent_title":"New heading","measurement_consent_layout":"modal"}' WHERE id=un;
 PERFORM assert_eq(public.form_measurement_runtime_internal(fid)->>'processing_revision',before_policy->>'processing_revision','cosmetic changes preserve processing revision');
 UPDATE public.units SET data=data||'{"measurement_privacy_url":"https://organizer.example/new-policy"}' WHERE id=un;
 after_policy:=public.form_measurement_runtime_internal(fid);
 PERFORM assert_true(after_policy->>'processing_revision'<>before_policy->>'processing_revision','privacy URL invalidates consent');
 before_policy:=after_policy;
 UPDATE public.units SET data=data||'{"measurement_scripts":"window.tag=1"}' WHERE id=un;
 PERFORM assert_true(public.form_measurement_runtime_internal(fid)->>'processing_revision'<>before_policy->>'processing_revision','script bytes invalidate consent');
 before_policy:=public.form_measurement_runtime_internal(fid);
 UPDATE analytics.unit_runtime SET collector_origins=ARRAY['https://collect.example'] WHERE unit=un;
 PERFORM assert_true(public.form_measurement_runtime_internal(fid)->>'processing_revision'<>before_policy->>'processing_revision','collector destinations invalidate consent');
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 after_policy:=public.get_form_measurement_runtime_config(x->>'link',org,un,origin,'https://tickets.example')->'policy';
 PERFORM assert_eq(after_policy->>'processing_revision',public.form_measurement_runtime_internal(fid)->>'processing_revision','Worker RPC carries actual SQL processing snapshot');
 PERFORM assert_eq(after_policy->'required_purposes','["analytics","marketing"]'::jsonb,'Worker RPC carries required purposes');
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 rejected:=false;
 BEGIN
  PERFORM public.save_unit_client_sync_v1(un,gen_random_uuid(),version,jsonb_build_object('id',un,'settings',jsonb_build_object('measurement_consent_version',3)));
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
 PERFORM assert_true(rejected,'nonmanager cannot increase consent version');
END $$;
