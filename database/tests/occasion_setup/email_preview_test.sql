-- test-setup: database/functions/occasion_setup/email_preview.sql
-- The test harness wraps this fixture in a rollback-only transaction.
GRANT EXECUTE ON FUNCTION public.assert_false(boolean,text), public.assert_true(boolean,text), public.assert_eq(anyelement,anyelement,text) TO authenticated;
DO $$
DECLARE actor uuid; org bigint; target bigint; source bigint; foreign_org bigint; foreign_unit bigint;
 draft uuid:=gen_random_uuid(); foreign_draft uuid:=gen_random_uuid(); result jsonb; template_id bigint;
BEGIN
 PERFORM public.create_user_for_test('email_preview_editor','email_preview_editor@test.local');
 actor:=public.get_user_id('email_preview_editor');
 INSERT INTO public.organizations(title) VALUES('Preview fixture') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization,data)
  VALUES('Preview unit',org,'{"reply_to":"unit@example.invalid","communication_tone":"informal"}') RETURNING id INTO target;
 INSERT INTO public.unit_users("user",unit,is_manager) VALUES(actor,target,true);
 INSERT INTO public.organizations(title) VALUES('Other preview tenant') RETURNING id INTO foreign_org;
 INSERT INTO public.units(title,organization) VALUES('Other preview unit',foreign_org) RETURNING id INTO foreign_unit;
 INSERT INTO public.occasion_setup_drafts(id,unit,organization,author,data)
  VALUES(draft,target,org,actor,'{"title":"Draft preview","communicationTone":"inherit"}'),(foreign_draft,foreign_unit,foreign_org,actor,'{}');
 INSERT INTO public.occasions(title,link,unit,organization,start_time,end_time)
  VALUES('Source',gen_random_uuid()::text,target,org,now(),now()+interval '1 day') RETURNING id INTO source;
 INSERT INTO public.email_templates(code,subject,html,unit,organization)
  VALUES('TICKET_ORDER_CONFIRMATION','Unit subject','Unit text {{balanceReasoning}}',target,org);
 INSERT INTO public.email_templates(code,subject,html,occasion,unit,organization)
  VALUES('TICKET_ORDER_CONFIRMATION','Source subject','Source static text',source,target,org) RETURNING id INTO template_id;
 INSERT INTO public.email_wrappers(unit,organization,html) VALUES(target,org,'<destination>{{content}}</destination>');
 INSERT INTO public.email_wrappers(occasion,unit,organization,html) VALUES(source,target,org,'<source>{{content}}</source>');
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 PERFORM assert_false(has_function_privilege('anon','public.get_occasion_setup_email_preview(uuid,bigint)','EXECUTE'),'Public preview is forbidden');
 PERFORM assert_false(has_function_privilege('service_role','public.get_occasion_setup_email_preview(uuid,bigint)','EXECUTE'),'Service role cannot replace user authorization');
 result:=public.get_occasion_setup_email_preview(draft,1);
 PERFORM assert_eq((result->>'ticketsEnabled')::boolean,false,'No ticket is invented for a draft without admission fields');
 PERFORM assert_eq(result->'sampleProducts','[]'::jsonb,'No sample product is invented');
 PERFORM assert_eq(result->>'tone','informal','Unit tone inherited');
 PERFORM assert_eq(result->>'replyTo','unit@example.invalid','Unit reply inherited');
 PERFORM assert_eq(result->'resolved'->'template'->>'subject','Unit subject','Destination template inherited');
 PERFORM assert_eq(result->'resolved'->'wrapper'->>'html','<destination>{{content}}</destination>','Destination wrapper inherited');
 BEGIN PERFORM public.get_occasion_setup_email_preview(foreign_draft,1); RAISE EXCEPTION 'Foreign draft accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.get_occasion_setup_email_preview(gen_random_uuid(),1); RAISE EXCEPTION 'Missing draft accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.get_occasion_setup_email_preview(draft,2); RAISE EXCEPTION 'Stale revision accepted'; EXCEPTION WHEN serialization_failure THEN NULL; END;
 EXECUTE 'RESET ROLE';
 UPDATE public.occasion_setup_drafts SET data=data||jsonb_build_object('sourceId',source,'copyEmails',true,'communicationTone','formal','replyToMode','custom','replyToEmail','draft@example.invalid') WHERE id=draft;
 EXECUTE 'SET LOCAL ROLE authenticated';
 result:=public.get_occasion_setup_email_preview(draft,1);
 PERFORM assert_eq(result->>'tone','formal','Saved tone wins over unit');
 PERFORM assert_eq(result->>'replyTo','draft@example.invalid','Saved reply wins over unit');
 PERFORM assert_eq(result->'resolved'->'template'->>'subject','Source subject','Copied source template selected');
 PERFORM assert_eq(result->'resolved'->'wrapper'->>'html','<destination>{{content}}</destination>','Source wrapper never copied');
 PERFORM assert_true((result->>'has_custom_template')::boolean,'UI can identify custom static text');
 EXECUTE 'RESET ROLE';
 DELETE FROM public.email_templates WHERE id=template_id;
 EXECUTE 'SET LOCAL ROLE authenticated';
 result:=public.get_occasion_setup_email_preview(draft,1);
 PERFORM assert_eq(result->'resolved'->'template'->>'subject','Unit subject','Source inheritance does not override destination');
 EXECUTE 'RESET ROLE';
 UPDATE public.occasion_setup_drafts SET data=data||'{"communicationTone":"bad"}'::jsonb WHERE id=draft;
 EXECUTE 'SET LOCAL ROLE authenticated';
 BEGIN PERFORM public.get_occasion_setup_email_preview(draft,1); RAISE EXCEPTION 'Bad tone accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 EXECUTE 'RESET ROLE';
 UPDATE public.occasion_setup_drafts SET data=data||jsonb_build_object('communicationTone','formal','replyToEmail',E'inject@example.invalid\r\nBcc: other@example.invalid') WHERE id=draft;
 EXECUTE 'SET LOCAL ROLE authenticated';
 BEGIN PERFORM public.get_occasion_setup_email_preview(draft,1); RAISE EXCEPTION 'Header injection accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 EXECUTE 'RESET ROLE';
 UPDATE public.occasion_setup_drafts SET data=data||'{"replyToMode":"inherit","finalizedOccasion":1}'::jsonb WHERE id=draft;
 EXECUTE 'SET LOCAL ROLE authenticated';
 BEGIN PERFORM public.get_occasion_setup_email_preview(draft,1); RAISE EXCEPTION 'Finalized preview accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 EXECUTE 'RESET ROLE';
 UPDATE public.occasion_setup_drafts SET data=data-'finalizedOccasion' WHERE id=draft;
 DELETE FROM public.unit_users WHERE "user"=actor AND unit=target;
 EXECUTE 'SET LOCAL ROLE authenticated';
 BEGIN PERFORM public.get_occasion_setup_email_preview(draft,1); RAISE EXCEPTION 'Revoked access accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 EXECUTE 'RESET ROLE';
END $$;
