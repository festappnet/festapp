-- test-setup: database/tests/helpers/form_measurement_fixture.sql
DO $$
DECLARE x jsonb:=pg_temp.fixture(NULL); fid bigint:=(x->>'form')::bigint; un bigint:=(x->>'unit')::bigint; org bigint:=(x->>'organization')::bigint;
 slug text:='measure-'||replace(gen_random_uuid()::text,'-',''); status jsonb; config jsonb; denied boolean:=false; origin text:='https://unit-test-measurement.pages.dev';
BEGIN
 UPDATE public.units SET data=data||'{"measurement_privacy_url":"https://organizer.example/privacy"}' WHERE id=un;
 UPDATE public.forms SET link=slug,is_open=true,data='{"analytics":{"enabled":true}}' WHERE id=fid;
 INSERT INTO public.form_link_reservations(slug,form) VALUES(slug,fid);
 INSERT INTO analytics.organization_policy(organization,enabled,revision,operator,reason) VALUES(org,true,1,'fixture','runtime gate');
 INSERT INTO analytics.unit_runtime(unit,runtime_origin,runtime_profile,parent_origins,collector_origins,revision,operator,reason)
 VALUES(un,origin,'gtm-v1',ARRAY['https://tickets.example'],ARRAY['https://www.google-analytics.com'],1,'fixture','compatibility tested');
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 status:=public.form_measurement_status_internal(fid);
 PERFORM assert_true((status->>'eligible')::boolean,'all stored ancestor gates + deployed Unit runtime permit measurement');
 UPDATE public.units SET data=data-'measurement_privacy_url' WHERE id=un;
 status:=public.form_measurement_status_internal(fid);
 PERFORM assert_false((status->>'eligible')::boolean,'missing privacy URL blocks every transport');
 PERFORM assert_true(status->'blocked_reasons' @> '["no_privacy_policy"]'::jsonb,'missing URL has canonical reason');
 PERFORM assert_true(public.get_form_measurement_policy(slug)->>'runtime_origin' IS NULL,'missing URL withholds frame origin');
 UPDATE public.units SET data=data||'{"measurement_privacy_url":"http://organizer.example/privacy"}' WHERE id=un;
 PERFORM assert_false((public.form_measurement_status_internal(fid)->>'eligible')::boolean,'non-HTTPS URL blocks measurement');
 UPDATE public.units SET data=data||'{"measurement_privacy_url":"https://organizer.example/privacy"}' WHERE id=un;
 PERFORM assert_true((public.form_measurement_status_internal(fid)->>'eligible')::boolean,'adding valid URL restores eligibility');
 PERFORM assert_eq(public.get_form_measurement_policy(slug)->>'privacy_url','https://organizer.example/privacy','eligible policy includes organizer URL');
 config:=public.get_form_measurement_runtime_config(slug,org,un,origin,'https://tickets.example');
 PERFORM assert_eq(config->>'gtm_container','GTM-AB12','service-only scoped reader gets Unit destination');
 PERFORM assert_false(config ? 'privacy_url' OR (config->'policy') ? 'privacy_url','runtime bootstrap omits privacy URL at every level');
 PERFORM assert_eq(config->>'unit',un::text,'Unit scope is projected from stored form');
 PERFORM assert_true(NOT (public.get_form_measurement_policy(slug) ? 'gtm_container'),'public policy never exposes destination');
 PERFORM assert_eq(public.get_form_measurement_policy(slug)->>'runtime_origin',origin,'runtime origin is platform owned');
 BEGIN
  PERFORM public.get_form_measurement_runtime_config(slug,org,un+1,origin,'https://tickets.example');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 PERFORM assert_true(denied,'forged Unit rejected');denied:=false;
 BEGIN
  PERFORM public.get_form_measurement_runtime_config(slug,org+1,un,origin,'https://tickets.example');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 PERFORM assert_true(denied,'forged organization rejected');denied:=false;
 BEGIN
  PERFORM public.get_form_measurement_runtime_config(slug,org,un,'https://other.pages.dev','https://tickets.example');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 PERFORM assert_true(denied,'forged runtime origin rejected');denied:=false;
 BEGIN
  PERFORM public.get_form_measurement_runtime_config(slug,org,un,origin,'https://unapproved.example');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 PERFORM assert_true(denied,'unapproved parent rejected');
 PERFORM set_config('request.jwt.claim.role','authenticated',true);denied:=false;
 BEGIN PERFORM public.get_form_measurement_runtime_config(slug,org,un,origin,'https://tickets.example');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 PERFORM assert_true(denied,'even direct definer owner with non-service claims cannot cross service predicate');
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 config:=public.form_measurement_runtime_internal(fid);
 UPDATE public.units SET data=data||'{"measurement_privacy_url":"https://organizer.example/updated"}' WHERE id=un;
 PERFORM assert_eq(public.form_measurement_runtime_internal(fid)->>'configuration_revision',config->>'configuration_revision','privacy change preserves frame revision');
 PERFORM assert_eq(public.form_measurement_status_internal(fid)->'enhanced_conversions_unavailable','true'::jsonb,'enhanced conversions are unavailable');
 PERFORM assert_eq(config->'approved_hosts','["https://tickets.example"]'::jsonb,'only approved origins may receive measurement events');
 PERFORM assert_eq(config#>>'{consent_notice,layout}','bar','bar is the default notice layout');
 PERFORM assert_true(config#>>'{consent_notice,title}' IS NULL AND config#>>'{consent_notice,text}' IS NULL,'empty notice text uses translations');
 UPDATE public.units SET data=data||'{"measurement_consent_layout":"modal","measurement_consent_title":" Vlastní ","measurement_consent_text":"  "}' WHERE id=un;
 PERFORM assert_eq(public.get_form_measurement_policy(slug)#>>'{consent_notice,layout}','modal','eligible policy carries the layout');
 PERFORM assert_eq(public.get_form_measurement_policy(slug)#>>'{consent_notice,title}','Vlastní','title is trimmed');
 PERFORM assert_true(public.get_form_measurement_policy(slug)#>>'{consent_notice,text}' IS NULL,'blank text is empty');
 PERFORM assert_eq(public.form_measurement_runtime_internal(fid)->>'configuration_revision',config->>'configuration_revision','notice change preserves frame revision');
 PERFORM assert_false((public.get_form_measurement_runtime_config(slug,org,un,origin,'https://tickets.example')->'policy') ?| ARRAY['consent_notice','approved_hosts','visitor_role'],'runtime bootstrap omits browser-only policy');
 PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM assert_eq(public.get_form_measurement_policy(slug)->>'visitor_role','anonymous','no JWT is anonymous');
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 PERFORM assert_eq(public.get_form_measurement_policy(slug)->>'visitor_role','visitor','signed-in ordinary visitor');
 PERFORM set_config('request.jwt.claim.sub',(x->>'actor'),true);
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(un,(x->>'actor')::uuid,true) ON CONFLICT(unit,"user") DO UPDATE SET is_manager=true;
 PERFORM assert_eq(public.get_form_measurement_policy(slug)->>'visitor_role','staff','Unit manager is not measured');
 UPDATE public.unit_users SET is_manager=false WHERE unit=un AND "user"=(x->>'actor')::uuid;
 PERFORM assert_eq(public.get_form_measurement_policy(slug)->>'visitor_role','visitor','a former manager is an ordinary visitor');
 UPDATE public.units SET data=data-'measurement_privacy_url' WHERE id=un;
 PERFORM assert_eq(public.form_measurement_runtime_internal(fid)->'approved_hosts','[]'::jsonb,'ineligible policy approves no host');
 PERFORM assert_true(public.form_measurement_runtime_internal(fid)->'consent_notice' = 'null'::jsonb,'ineligible policy redacts notice settings');
 UPDATE public.units SET data=data||'{"measurement_privacy_url":"https://organizer.example/updated"}' WHERE id=un;
 UPDATE public.organizations SET data=data||'{"FORM_MEASUREMENT_ENABLED":false}' WHERE id=org;
 PERFORM assert_false((public.form_measurement_status_internal(fid)->>'eligible')::boolean,'organization off dominates Unit + form');
 PERFORM assert_true(public.get_form_measurement_policy(slug)->>'privacy_url' IS NULL,'ineligible policy redacts URL');
 UPDATE public.organizations SET data=data||'{"FORM_MEASUREMENT_ENABLED":true}' WHERE id=org;
 UPDATE public.units SET data=data||'{"measurement_enabled":false}' WHERE id=un;
 PERFORM assert_false((public.form_measurement_status_internal(fid)->>'eligible')::boolean,'Unit off dominates form');
 UPDATE public.units SET data=data||'{"measurement_enabled":true}' WHERE id=un;
 UPDATE public.forms SET data='{"analytics":{"enabled":false}}' WHERE id=fid;
 PERFORM assert_false((public.form_measurement_status_internal(fid)->>'eligible')::boolean,'form remains separately off');
 UPDATE public.forms SET data='{"analytics":{"enabled":true}}' WHERE id=fid;
 UPDATE analytics.organization_policy SET enabled=false WHERE organization=org;
 PERFORM assert_false((public.form_measurement_status_internal(fid)->>'eligible')::boolean,'org admin cannot bypass platform');
 FOR slug IN SELECT unnest(ARRAY['anon','authenticated','service_role']) LOOP
  PERFORM assert_false(has_schema_privilege(slug,'analytics','USAGE'),'no direct schema access for '||slug);
  PERFORM assert_false(has_table_privilege(slug,'analytics.organization_policy','UPDATE'),'no policy writes for '||slug);
  PERFORM assert_false(has_table_privilege(slug,'analytics.unit_runtime','UPDATE'),'no deployment writes for '||slug);
 END LOOP;
 PERFORM assert_true(to_regclass('public.form_measurement_organization_policy') IS NULL,'old public policy table retired');
 PERFORM assert_true(to_regclass('public.form_measurement_conversion_facts') IS NULL,'old public facts table retired');
END $$;
