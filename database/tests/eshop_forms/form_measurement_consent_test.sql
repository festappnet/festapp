-- test-setup: database/tests/helpers/form_measurement_fixture.sql
DO $$
DECLARE role_name text;
BEGIN
 PERFORM assert_true(public.form_measurement_runtime_supported_internal('gtm-v1','https://unit-17.pages.dev',ARRAY['https://tickets.example']),'supported structure');
 PERFORM assert_false(public.form_measurement_runtime_supported_internal(NULL,NULL,NULL),'missing runtime fails closed');
 PERFORM assert_false(public.form_measurement_runtime_supported_internal('unknown','https://unit-17.pages.dev',ARRAY['https://tickets.example']),'unsupported profile');
 PERFORM assert_false(public.form_measurement_runtime_supported_internal('gtm-v1','https://api.festapp.net',ARRAY['https://tickets.example']),'unsupported origin');
 PERFORM assert_false(public.form_measurement_runtime_supported_internal('gtm-v1','https://unit-17.pages.dev','{}'),'empty parent list');
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  PERFORM assert_false(has_function_privilege(role_name,'public.form_measurement_runtime_supported_internal(text,text,text[])','EXECUTE'),'support expression remains private');
 END LOOP;
END $$;
DO $$
DECLARE x jsonb:=pg_temp.fixture(NULL); un bigint:=(x->>'unit')::bigint; fid bigint:=(x->>'form')::bigint;
 org bigint:=(x->>'organization')::bigint; before_policy jsonb; after_policy jsonb; receipt jsonb; version bigint:=0;
 legacy_revision text; value jsonb; rejected boolean; origin text:='https://unit-consent-test.pages.dev';
BEGIN
 INSERT INTO public.form_link_reservations(slug,form) VALUES(x->>'link',fid);
 UPDATE public.forms SET is_open=true,data='{"analytics":{"enabled":true}}' WHERE id=fid;
 INSERT INTO analytics.organization_policy(organization,enabled,revision,operator,reason) VALUES(org,true,1,'fixture','consent');
 INSERT INTO analytics.unit_runtime(unit,runtime_origin,runtime_profile,parent_origins,collector_origins,revision,operator,reason)
 VALUES(un,origin,'gtm-v1',ARRAY['https://tickets.example'],ARRAY['https://www.google-analytics.com'],1,'fixture','consent');
 before_policy:=public.form_measurement_runtime_internal(fid);
 PERFORM assert_eq(before_policy->'measurement_consent_bridge','false'::jsonb,'existing Units default to disabled consent bridge');
 -- Preserve the exact fingerprint used before the bridge setting existed.
 SELECT md5(jsonb_build_array(3,o.organization,u.id,u.data->'measurement_gtm_container',u.data->'measurement_scripts',
  u.data->'measurement_privacy_url',coalesce(u.data->'measurement_consent_version','1'::jsonb),r.runtime_profile,r.runtime_origin,
  r.parent_origins,r.collector_origins,r.revision,s->'policy_revision',u.data->'measurement_enabled',
  organization.data->'FORM_MEASUREMENT_ENABLED',s->'requested_enabled')::text)
 INTO legacy_revision
 FROM public.forms f JOIN public.occasions o ON o.id=f.occasion
 JOIN public.units u ON u.id=o.unit JOIN public.organizations organization ON organization.id=o.organization
 JOIN analytics.unit_runtime r ON r.unit=u.id
 CROSS JOIN LATERAL public.form_measurement_status_internal(f.id) AS status(s)
 WHERE f.id=fid;
 PERFORM assert_eq(before_policy->>'processing_revision',legacy_revision,'missing bridge preserves pre-bridge fingerprint');
 UPDATE public.units SET data=coalesce(data,'{}')||'{"measurement_consent_bridge":false}' WHERE id=un;
 PERFORM assert_eq(public.form_measurement_runtime_internal(fid)->>'processing_revision',legacy_revision,'false bridge preserves pre-bridge fingerprint');
 UPDATE public.units SET data=data||'{"measurement_consent_bridge":true}' WHERE id=un;
 PERFORM assert_true(public.form_measurement_runtime_internal(fid)->>'processing_revision'<>legacy_revision,'true bridge changes pre-bridge fingerprint');
 UPDATE public.units SET data=data-'measurement_consent_bridge' WHERE id=un;
 PERFORM assert_eq(before_policy->'measurement_protocol','3'::jsonb,'current behavior protocol is explicit');
 PERFORM assert_eq(before_policy->'required_purposes','["analytics","marketing"]'::jsonb,'mixed profile reports both purpose choices');
 PERFORM assert_eq(before_policy->'enhanced_conversions_unavailable','false'::jsonb,'enhanced conversions are available');
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
 UPDATE public.units SET data=data||'{"measurement_consent_layout":"modal"}' WHERE id=un;
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
 -- The normal manager aggregate owns the opt-in and its processing revision.
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 SELECT v.version INTO version FROM public.client_aggregate_versions v WHERE aggregate_type='unit' AND scope_type='unit' AND scope_id=un AND aggregate_id=un::text;
 before_policy:=public.form_measurement_runtime_internal(fid);
 receipt:=public.save_unit_client_sync_v1(un,gen_random_uuid(),version,jsonb_build_object('id',un,'settings',jsonb_build_object('measurement_consent_bridge',true)));
 PERFORM assert_eq(receipt->>'status','applied','manager can enable consent bridge');
 after_policy:=public.form_measurement_runtime_internal(fid);
 PERFORM assert_eq(after_policy->'measurement_consent_bridge','true'::jsonb,'policy carries consent bridge opt-in');
 PERFORM assert_true(after_policy->>'processing_revision'<>before_policy->>'processing_revision','enabling bridge changes processing revision');
 SELECT v.version INTO version FROM public.client_aggregate_versions v WHERE aggregate_type='unit' AND scope_type='unit' AND scope_id=un AND aggregate_id=un::text;
 receipt:=public.save_unit_client_sync_v1(un,gen_random_uuid(),version,jsonb_build_object('id',un,'settings',jsonb_build_object('measurement_consent_bridge',false)));
 PERFORM assert_eq(receipt->>'status','applied','manager can disable consent bridge');
 PERFORM assert_eq(public.form_measurement_runtime_internal(fid)->'measurement_consent_bridge','false'::jsonb,'policy carries disabled bridge');
 PERFORM assert_true(public.form_measurement_runtime_internal(fid)->>'processing_revision'<>after_policy->>'processing_revision','disabling bridge changes processing revision');
 PERFORM assert_eq(public.form_measurement_runtime_internal(fid)->>'processing_revision',before_policy->>'processing_revision','disabling bridge restores the fingerprint without the switch');
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 rejected:=false;
 BEGIN
  PERFORM public.save_unit_client_sync_v1(un,gen_random_uuid(),version,jsonb_build_object('id',un,'settings',jsonb_build_object('measurement_consent_version',3)));
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
 PERFORM assert_true(rejected,'nonmanager cannot increase consent version');
END $$;

-- Semantic coverage survives technical deployments but never processing changes.
DO $$
DECLARE x jsonb:=pg_temp.fixture(NULL); un bigint:=(x->>'unit')::bigint; fid bigint:=(x->>'form')::bigint;
 org bigint:=(x->>'organization')::bigint; before_policy jsonb; after_policy jsonb; previous_scope text;
BEGIN
 UPDATE public.forms SET is_open=true,data='{"analytics":{"enabled":true}}' WHERE id=fid;
 INSERT INTO analytics.organization_policy(organization,enabled,revision,operator,reason) VALUES(org,true,1,'fixture','scope');
 INSERT INTO analytics.unit_runtime(unit,runtime_origin,runtime_profile,parent_origins,collector_origins,revision,operator,reason)
 VALUES(un,'https://unit-scope.pages.dev','gtm-v1',ARRAY['https://tickets.example'],ARRAY['https://www.google-analytics.com'],1,'fixture','scope');
 before_policy:=public.form_measurement_runtime_internal(fid);
 PERFORM assert_true((before_policy->>'consent_revision') ~ '^[a-f0-9]{32}$','semantic revision exists');
 UPDATE analytics.unit_runtime SET revision=revision+1,runtime_origin='https://unit-scope-new.pages.dev',
  parent_origins=parent_origins||ARRAY['https://another.example'] WHERE unit=un;
 after_policy:=public.form_measurement_runtime_internal(fid);
 PERFORM assert_eq(after_policy->>'consent_revision',before_policy->>'consent_revision','runtime deploy and host additions preserve consent scope');
 PERFORM assert_true(after_policy->>'processing_revision'<>before_policy->>'processing_revision','technical lease still invalidates');
 UPDATE public.units SET data=data||'{"measurement_consent_text":"Updated purposes"}' WHERE id=un;
 after_policy:=public.form_measurement_runtime_internal(fid);
 PERFORM assert_true(after_policy->>'consent_revision'<>before_policy->>'consent_revision','notice text invalidates imported coverage');
 PERFORM assert_true(after_policy->>'processing_revision'<>before_policy->>'processing_revision','notice text also invalidates locally saved choices');
 previous_scope:=after_policy->>'consent_revision';
 UPDATE public.units SET data=data||'{"measurement_consent_version":2}' WHERE id=un;
 after_policy:=public.form_measurement_runtime_internal(fid);
 PERFORM assert_true(after_policy->>'consent_revision'<>previous_scope,'notice version invalidates saved coverage');
 previous_scope:=after_policy->>'consent_revision';
 UPDATE public.units SET data=data||'{"measurement_gtm_container":"GTM-NEW123"}' WHERE id=un;
 after_policy:=public.form_measurement_runtime_internal(fid);
 PERFORM assert_true(after_policy->>'consent_revision'<>previous_scope,'new destination invalidates saved coverage');
 previous_scope:=after_policy->>'consent_revision';
 UPDATE analytics.unit_runtime SET collector_origins=collector_origins||ARRAY['https://new-recipient.example'] WHERE unit=un;
 PERFORM assert_true(public.form_measurement_runtime_internal(fid)->>'consent_revision'<>previous_scope,'new collector invalidates saved coverage');
END $$;
