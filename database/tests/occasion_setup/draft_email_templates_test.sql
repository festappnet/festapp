-- Exercise private draft edits through the real creator and finalizer.
DO $$
DECLARE actor uuid; org bigint; un bigint; draft uuid:=gen_random_uuid(); d jsonb;
 payload jsonb; result jsonb; overrides jsonb:='{}'; item_code text; occasion_id bigint; source_id bigint; command uuid:=gen_random_uuid();
BEGIN
 PERFORM create_user_for_test('draft-email-editor','draft-email-'||gen_random_uuid()||'@example.invalid');
 actor:=get_user_id('draft-email-editor');
 INSERT INTO public.organizations(title) VALUES('Draft email test') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization) VALUES('Draft email unit',org) RETURNING id INTO un;
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES(un,actor,true,true);
 INSERT INTO public.email_templates(unit,organization,code,subject,html)
 VALUES(un,org,'TICKET_ORDER_CONFIRMATION','Shared subject','<p>Shared body</p>');
 FOREACH item_code IN ARRAY ARRAY['TICKET_ORDER_CONFIRMATION','TICKET_ORDER_PAYMENT_DONE','TICKET_ORDER_REMINDER','TICKET_ORDER_STORNO','TICKET_ORDER_UPDATE'] LOOP
  overrides:=overrides||jsonb_build_object(item_code,jsonb_build_object('subject','Draft '||item_code,'html','<p>Draft '||item_code||'</p>'));
 END LOOP;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Source email event',org,un,'source-email-'||draft,now(),now()+interval '1 day') RETURNING id INTO source_id;
 INSERT INTO public.email_templates(occasion,unit,organization,code,subject,html)
 VALUES(source_id,un,org,'TICKET_ORDER_CONFIRMATION','Source subject','<p>Source body</p>');
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 d:=public.create_occasion_setup_draft(draft,un);
 payload:=jsonb_build_object('title','Draft email event','link','draft-email-'||draft,
  'start',now()+interval '30 days','end',now()+interval '31 days','formEnabled',false,
  'reviewConfirmed',true,'sourceId',source_id,'copyEmails',true,'emailTemplateOverrides',overrides);
 d:=public.save_occasion_setup_draft(draft,(d->>'revision')::bigint,payload,5);
 result:=public.get_occasion_setup_email_preview(draft,(d->>'revision')::bigint);
 PERFORM assert_eq(jsonb_array_length(result->'emailTemplates'),5,'All five edited templates are available before creation');
 PERFORM assert_eq(result#>>'{resolved,template,subject}','Draft TICKET_ORDER_CONFIRMATION','Preview uses the saved private override');
 result:=public.finalize_occasion_setup_draft(draft,(d->>'revision')::bigint,command);
 PERFORM assert_eq(result->>'status','applied','Creator materializes valid draft templates');
 occasion_id:=(result#>>'{data,occasionId}')::bigint;
 PERFORM assert_eq(public.finalize_occasion_setup_draft(draft,(d->>'revision')::bigint,command),result,'Retry retains the same creation receipt');
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq((SELECT count(*) FROM public.email_templates WHERE occasion=occasion_id),5::bigint,'Exactly five occasion-local templates are persisted');
 PERFORM assert_eq((SELECT subject FROM public.email_templates WHERE occasion=source_id AND code='TICKET_ORDER_CONFIRMATION'),'Source subject','Copied source template remains unchanged');
 PERFORM assert_eq((SELECT subject FROM public.email_templates WHERE occasion IS NULL AND unit=un AND code='TICKET_ORDER_CONFIRMATION'),'Shared subject','Shared unit template is untouched');
 PERFORM assert_true((SELECT bool_and(unit=un AND organization=org AND subject='Draft '||code) FROM public.email_templates WHERE occasion=occasion_id),'Every persisted template belongs to the new occasion hierarchy');
 BEGIN PERFORM public.validate_setup_email_templates_internal('{"AUTH_EMAIL":{"subject":"x","html":"x"}}'); RAISE EXCEPTION 'Unrelated code accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.validate_setup_email_templates_internal('{"TICKET_ORDER_CONFIRMATION":null}'); RAISE EXCEPTION 'Null template accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.validate_setup_email_templates_internal('{"TICKET_ORDER_CONFIRMATION":{"subject":"x","html":"x","occasion":999}}'); RAISE EXCEPTION 'Hierarchy injection accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
END $$;
