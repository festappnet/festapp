-- test-setup: database/tests/helpers/form_measurement_fixture.sql
DO $$
DECLARE x jsonb:=pg_temp.fixture(NULL); un bigint:=(x->>'unit')::bigint; org bigint:=(x->>'organization')::bigint;
 fid bigint:=(x->>'form')::bigint; scope jsonb; result jsonb; b jsonb; exported jsonb; before_policy jsonb; legacy_revision text; rejected boolean; signature text;
 config jsonb:='{"provider":"cookieconsent","revision":7,"categories":{"analytics":"statistika návštěv","marketing":"reklama"}}';
BEGIN
 PERFORM assert_eq(public.normalize_website_consent_provider_internal('{"provider":"complianz","policyId":"42"}'),'{"provider":"complianz","policyId":"42"}'::jsonb,'Complianz retains explicit policy coverage');
 rejected:=false;
 BEGIN PERFORM public.normalize_website_consent_provider_internal('{"provider":"complianz"}'); EXCEPTION WHEN invalid_parameter_value THEN rejected:=true; END;
 PERFORM assert_true(rejected,'Complianz without comparable timestamp needs a policy ID');
 PERFORM assert_eq(public.normalize_website_consent_provider_internal('{"provider":"cookiebot"}'),'{"provider":"cookiebot"}'::jsonb,'Cookiebot needs no mapping');
 PERFORM assert_eq(public.normalize_website_consent_provider_internal('{"provider":"wix"}'),'{"provider":"wix"}'::jsonb,'Wix needs no mapping');
 PERFORM assert_eq(public.normalize_website_consent_provider_internal('{"provider":"cookieconsent"}'),'{"provider":"cookieconsent"}'::jsonb,'CookieConsent categories optional');
 UPDATE public.organizations SET data=data||'{"DEFAULT_URL":"https://tickets.example"}' WHERE id=org;
 UPDATE public.units SET data=data||'{"measurement_consent_bridge":true,"measurement_websites":["https://organizer.example"]}' WHERE id=un;
 UPDATE public.forms SET is_open=true,data='{"analytics":{"enabled":true}}' WHERE id=fid;
 INSERT INTO analytics.organization_policy(organization,enabled,revision,operator,reason) VALUES(org,true,1,'fixture','consent');
 INSERT INTO analytics.unit_runtime(unit,runtime_origin,runtime_profile,parent_origins,collector_origins,revision,operator,reason)
 VALUES(un,'https://binding-test.pages.dev','gtm-v1',ARRAY['https://organizer.example'],ARRAY['https://www.google-analytics.com'],1,'fixture','consent');
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(un,(x->>'actor')::uuid,true) ON CONFLICT(unit,"user") DO UPDATE SET is_manager=true;
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 scope:=public.get_unit_website_consent_bindings(un);
 before_policy:=public.form_measurement_runtime_internal(fid);
 SELECT md5(jsonb_build_array(1,o.organization,u.id,u.data->'measurement_gtm_container',u.data->'measurement_scripts',u.data->'measurement_privacy_url',
  u.data->'measurement_consent_title',u.data->'measurement_consent_text',coalesce(u.data->'measurement_consent_version','1'::jsonb),
  r.runtime_profile,r.collector_origins,jsonb_build_array('analytics','marketing'))::text)
 INTO legacy_revision FROM public.units u JOIN public.occasions o ON o.unit=u.id JOIN analytics.unit_runtime r ON r.unit=u.id WHERE u.id=un;
 PERFORM assert_eq(scope->>'consentRevision',legacy_revision,'semantic revision preserved byte for byte');
 result:=public.save_unit_website_consent_binding(un,'https://organizer.example','wordpress',config,0,scope->>'consentRevision',false);
 b:=result#>'{bindings,0}';
 PERFORM assert_eq(b->>'state','draft','draft is not effective');
 rejected:=false;
 BEGIN PERFORM public.export_unit_website_consent_binding((b->>'id')::uuid,1); EXCEPTION WHEN invalid_parameter_value THEN rejected:=true; END;
 PERFORM assert_true(rejected,'draft cannot export');
 rejected:=false;
 BEGIN PERFORM public.save_unit_website_consent_binding(un,'https://organizer.example','joomla',config,0,scope->>'consentRevision',true); EXCEPTION WHEN serialization_failure THEN rejected:=true; END;
 PERFORM assert_true(rejected,'stale version cannot confirm or duplicate platform');
 result:=public.save_unit_website_consent_binding(un,'https://organizer.example','joomla',config,1,scope->>'consentRevision',true);
 exported:=public.export_unit_website_consent_binding((b->>'id')::uuid,2);
 PERFORM assert_eq(exported#>>'{providerConfig,categories,analytics}','statistika návštěv','Unicode categories preserved');
 PERFORM assert_eq(exported#>>'{providerConfig,consentRevision}',legacy_revision,'export confirmed server scope');
 PERFORM assert_eq(exported->>'serviceOrigin','https://tickets.example','service from organization');
 PERFORM assert_eq(exported#>>'{binding,version}','2','version advances');
 PERFORM assert_eq(exported#>>'{providerConfig,maxAgeSeconds}','31536000','server owns age ceiling');
 PERFORM assert_true((exported#>>'{providerConfig,consentValidFrom}')::timestamptz >= transaction_timestamp(),'new coverage cannot predate confirmation');
 PERFORM assert_false(exported->'providerConfig' ? 'revision','new CookieConsent exports use server coverage time');
 PERFORM assert_eq(public.form_measurement_runtime_internal(fid)#>>'{website_consent_bindings,0,effective}','true','policy advertises effective binding');
 PERFORM assert_false((public.form_measurement_runtime_internal(fid)->'website_consent_bindings')::text LIKE '%statistika%','public policy redacts provider config');
 PERFORM assert_true(public.form_measurement_runtime_internal(fid)->>'processing_revision'<>before_policy->>'processing_revision','managed binding changes technical revision');
 UPDATE analytics.unit_runtime SET revision=2 WHERE unit=un;
 PERFORM assert_eq(public.export_unit_website_consent_binding((b->>'id')::uuid,2)#>>'{providerConfig,consentRevision}',legacy_revision,'runtime deploy preserves confirmation');
 UPDATE public.units SET data=data||'{"measurement_privacy_url":"https://organizer.example/new"}' WHERE id=un;
 PERFORM assert_eq(public.get_unit_website_consent_bindings(un)#>>'{bindings,0,state}','confirmation_required','policy change retires export');
 rejected:=false;
 BEGIN PERFORM public.save_unit_website_consent_binding(un,'https://organizer.example','joomla',config,2,legacy_revision,true); EXCEPTION WHEN serialization_failure THEN rejected:=true; END;
 PERFORM assert_true(rejected,'stale semantic revision cannot confirm');
 scope:=public.get_unit_website_consent_bindings(un);
 result:=public.save_unit_website_consent_binding(un,'https://organizer.example','joomla',config,2,scope->>'consentRevision',true);
 result:=public.disable_unit_website_consent_binding((b->>'id')::uuid,3);
 PERFORM assert_eq(result#>>'{bindings,0,state}','disabled','disable retains tombstone');
 PERFORM assert_eq(public.form_measurement_runtime_internal(fid)#>>'{website_consent_bindings,0,version}','4','public policy advances disabled version');
 PERFORM assert_eq(public.form_measurement_runtime_internal(fid)#>>'{website_consent_bindings,0,effective}','false','disabled policy fails closed');
 rejected:=false;
 BEGIN PERFORM public.export_unit_website_consent_binding((b->>'id')::uuid,4); EXCEPTION WHEN invalid_parameter_value THEN rejected:=true; END;
 PERFORM assert_true(rejected,'disabled export denied');
 scope:=public.get_unit_website_consent_bindings(un);
 result:=public.save_unit_website_consent_binding(un,'https://organizer.example','wix',
  '{"provider":"wix","consentValidFrom":"2026-01-01T00:00:00.000Z","maxAgeSeconds":86400,"organization":999,"unit":999}',4,scope->>'consentRevision',true);
 exported:=public.export_unit_website_consent_binding((b->>'id')::uuid,5);
 PERFORM assert_eq(exported#>>'{providerConfig,provider}','wix','native Wix uses same server export');
 PERFORM assert_true((exported#>>'{providerConfig,consentValidFrom}')::timestamptz >= transaction_timestamp(),'caller cannot backdate coverage');
 PERFORM assert_eq(exported#>>'{providerConfig,maxAgeSeconds}','31536000','caller cannot choose validity ceiling');
 PERFORM assert_eq(exported#>>'{providerConfig,unit}',un::text,'client scope cannot override stored Unit');
 result:=public.save_unit_website_consent_binding(un,'https://organizer.example','html',config,5,scope->>'consentRevision',true);
 PERFORM assert_eq((SELECT count(*)::integer FROM analytics.website_consent_bindings WHERE unit=un),1,'four platform choices retain one binding');
 PERFORM assert_eq(result#>>'{bindings,0,id}',b->>'id','HTML reuses same stable binding');
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 rejected:=false;
 BEGIN PERFORM public.get_unit_website_consent_bindings(un); EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
 PERFORM assert_true(rejected,'foreign manager denied');
 rejected:=false;
 BEGIN PERFORM public.disable_unit_website_consent_binding((b->>'id')::uuid,4); EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
 PERFORM assert_true(rejected,'disable authorizes stored Unit');
 PERFORM assert_false(has_table_privilege('authenticated','analytics.website_consent_bindings','INSERT'),'direct writes denied');
 FOREACH signature IN ARRAY ARRAY[
  'public.get_unit_website_consent_bindings(bigint)',
  'public.save_unit_website_consent_binding(bigint,text,text,jsonb,bigint,text,boolean)',
  'public.disable_unit_website_consent_binding(uuid,bigint)',
  'public.export_unit_website_consent_binding(uuid,bigint)'
 ] LOOP
  PERFORM assert_false(has_function_privilege('anon',signature,'EXECUTE'),'anon admin RPC denied: '||signature);
  PERFORM assert_true(has_function_privilege('authenticated',signature,'EXECUTE'),'authenticated RPC declared: '||signature);
  PERFORM assert_false(has_function_privilege('service_role',signature,'EXECUTE'),'service role admin RPC denied: '||signature);
 END LOOP;
 -- UTF-16 boundary parity with JavaScript, including astral characters.
 PERFORM public.normalize_website_consent_provider_internal(jsonb_build_object('provider','cookieconsent','revision',1,'categories',jsonb_build_object('analytics',repeat('😀',64),'marketing','m')));
 rejected:=false;
 BEGIN PERFORM public.normalize_website_consent_provider_internal(jsonb_build_object('provider','cookieconsent','revision',1,'categories',jsonb_build_object('analytics',repeat('😀',65),'marketing','m'))); EXCEPTION WHEN invalid_parameter_value THEN rejected:=true; END;
 PERFORM assert_true(rejected,'129+ UTF16 units rejected');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.fixture(NULL); un bigint:=(x->>'unit')::bigint; org bigint:=(x->>'organization')::bigint;
 fid bigint:=(x->>'form')::bigint; scope jsonb; result jsonb; b jsonb; exported jsonb; policy jsonb; rejected boolean;
BEGIN
 UPDATE public.organizations SET data=data||'{"DEFAULT_URL":"https://tickets.example","FORM_MEASUREMENT_ENABLED":false}' WHERE id=org;
 UPDATE public.units SET data=data||'{"measurement_consent_bridge":true,"measurement_enabled":false,"measurement_websites":["https://self-service.example"]}' WHERE id=un;
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(un,(x->>'actor')::uuid,true) ON CONFLICT(unit,"user") DO UPDATE SET is_manager=true;
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 scope:=public.get_unit_website_consent_bindings(un);
 PERFORM assert_eq(scope->'saved_origins','["https://self-service.example"]'::jsonb,'manager scope owns saved probe origins');
 result:=public.save_unit_website_consent_binding(un,'https://self-service.example','wordpress','{"provider":"cookiebot"}',0,scope->>'consentRevision',true);
 b:=result#>'{bindings,0}';
 PERFORM assert_eq(b->>'state','ready','confirmed saved website needs no platform/runtime permission');
 exported:=public.export_unit_website_consent_binding((b->>'id')::uuid,1);
 PERFORM assert_eq(exported->>'websiteOrigin','https://self-service.example','self-service export succeeds');
 policy:=public.form_measurement_runtime_internal(fid);
 PERFORM assert_eq(policy#>>'{website_consent_bindings,0,effective}','true','consent policy is independent');
 PERFORM assert_eq(policy->'eligible','false'::jsonb,'consent does not enable measurement');
 PERFORM assert_eq(policy->'approved_hosts','[]'::jsonb,'consent does not widen runtime hosts');
 PERFORM assert_eq(policy->'runtime_origin','null'::jsonb,'consent cannot provision runtime');
 PERFORM assert_eq(policy->>'privacy_url','https://organizer.example/privacy','consent notice available with measurement off');
 PERFORM assert_true(NOT EXISTS(SELECT FROM analytics.unit_runtime WHERE unit=un),'no implicit runtime write');
 PERFORM assert_true(NOT EXISTS(SELECT FROM analytics.organization_policy WHERE organization=org),'no implicit platform permission');
 PERFORM assert_true(NOT EXISTS(SELECT FROM public.email_messages WHERE unit=un AND code='MEASUREMENT_APPROVAL_REQUEST'),'consent authoring sends no approval mail');
 rejected:=false;
 BEGIN PERFORM public.save_unit_website_consent_binding(un,'https://foreign.example','html','{"provider":"cookiebot"}',0,scope->>'consentRevision',true);
 EXCEPTION WHEN invalid_parameter_value THEN rejected:=true; END;
 PERFORM assert_true(rejected,'unsaved origin cannot pair');
 UPDATE public.units SET data=data||'{"measurement_websites":[]}' WHERE id=un;
 PERFORM assert_eq(public.get_unit_website_consent_bindings(un)#>>'{bindings,0,state}','unavailable','removing saved website revokes binding');
 rejected:=false;
 BEGIN PERFORM public.export_unit_website_consent_binding((b->>'id')::uuid,1); EXCEPTION WHEN invalid_parameter_value THEN rejected:=true; END;
 PERFORM assert_true(rejected,'removed website cannot export');
END $$;
