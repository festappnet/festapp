UPDATE public.abuse_policy_rules SET base_limit=hard_cap WHERE budget_key IN ('occasion.creation','occasion.draft');
DO $$
DECLARE actor uuid; org bigint; unit_id bigint; draft uuid:=gen_random_uuid(); d jsonb; payload jsonb;
 response jsonb; context jsonb; event_id bigint; inherited_form bigint; custom_form bigint; form_feature jsonb;
 unit_data jsonb; bank_id bigint; bank_info jsonb; event_count bigint;
BEGIN
 PERFORM create_user_for_test('communication_setup_editor','communication_setup@test.local');
 actor:=get_user_id('communication_setup_editor');
 INSERT INTO public.organizations(title,data) VALUES('Communication setup','{"IS_APP_SUPPORTED":false}') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id=actor;
 INSERT INTO public.units(title,organization,data) VALUES('Communication unit',org,
  '{"reply_to":" unit@test.local ","communication_tone":"informal","is_reminder_enabled":true,"reminder_interval_seconds":86400,"private_fixture":"manager-only"}') RETURNING id INTO unit_id;
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES(unit_id,actor,true,true);
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES('unit','unit',unit_id,unit_id::text,7)
  ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE SET version=7;
 INSERT INTO eshop.bank_accounts(title,type,account_number,supported_currencies)
  VALUES('Communication fixture bank','OTHER','CZ6508000000192000145399',ARRAY['CZK']) RETURNING id INTO bank_id;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account,priority) VALUES(unit_id,bank_id,0);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 d:=public.create_occasion_setup_draft(draft,unit_id);
 context:=public.get_occasion_setup_communication(draft);
 PERFORM assert_true((context->>'canManage')::boolean,'Manager can edit unit communication defaults');
 PERFORM assert_true((context->>'firstEvent')::boolean,'A private draft is not an existing event');
 PERFORM assert_eq((context#>>'{unit,id}')::bigint,unit_id,'Manager receives the selected unit');
 PERFORM assert_eq((context#>>'{unit,aggregate_version}')::bigint,7::bigint,'Manager receives version for the existing unit editor');
 PERFORM assert_eq(context#>>'{unit,data,private_fixture}','manager-only','Manager receives full unit data');
 PERFORM assert_eq(context#>>'{defaults,replyTo}','unit@test.local','Reply address is trimmed');
 PERFORM assert_eq(context#>>'{defaults,tone}','informal','Unit tone is available');
 PERFORM assert_false(has_function_privilege('anon','public.get_occasion_setup_communication(uuid)','EXECUTE'),'Communication defaults are not public');
 BEGIN PERFORM public.get_occasion_setup_communication(gen_random_uuid()); RAISE EXCEPTION 'Unknown draft communication read accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 EXECUTE 'RESET ROLE';
 UPDATE public.unit_users SET is_manager=false WHERE unit=unit_id AND "user"=actor;
 EXECUTE 'SET LOCAL ROLE authenticated';
 context:=public.get_occasion_setup_communication(draft);
 PERFORM assert_false((context->>'canManage')::boolean,'Editor cannot manage unit defaults');
 PERFORM assert_true(context->'unit'='null'::jsonb,'Editor never receives full unit data or its edit version');
 PERFORM assert_eq(context->'defaults','{"replyTo":"unit@test.local","tone":"informal","remindersEnabled":true,"leadSeconds":86400}'::jsonb,'Editor receives only safe defaults');
 bank_info:=public.get_occasion_setup_bank_accounts(draft);
 payload:=d->'data'||jsonb_build_object('title','Inherited communication','start','2090-06-01T18:00:00Z','end','2090-06-02T02:00:00Z',
  'reviewConfirmed',true,'formEnabled',true,'formLinkAutomatic',true,
  'communicationTone','inherit','replyToMode','inherit','remindersMode','inherit','reminderLeadDays','',
  'bankAccountId',bank_id,'bankAccountConfirmed',true,'bankAccountFingerprint',bank_info->'accounts'->0->>'fingerprint');
 -- Copied form metadata must not silently defeat explicit inheritance.
 payload:=jsonb_set(payload,'{formDraft,data}','{"communication_tone":"informal","is_reminder_enabled":true,"reminder_interval_seconds":123,"fixture_retained":"yes"}');
 d:=public.save_occasion_setup_draft(draft,(d->>'revision')::bigint,payload,5);
 EXECUTE 'RESET ROLE';
 UPDATE public.unit_users SET is_editor=false WHERE unit=unit_id AND "user"=actor;
 EXECUTE 'SET LOCAL ROLE authenticated';
 BEGIN PERFORM public.finalize_occasion_setup_draft(draft,(d->>'revision')::bigint,gen_random_uuid()); RAISE EXCEPTION 'Revoked editor published draft'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 EXECUTE 'RESET ROLE';
 UPDATE public.unit_users SET is_editor=true WHERE unit=unit_id AND "user"=actor;
 UPDATE public.units SET data=data||'{"reply_to":"fresh@test.local","communication_tone":"formal","is_reminder_enabled":false,"reminder_interval_seconds":172800}' WHERE id=unit_id;
 SELECT data INTO unit_data FROM public.units WHERE id=unit_id;
 EXECUTE 'SET LOCAL ROLE authenticated';
 response:=public.finalize_occasion_setup_draft(draft,(d->>'revision')::bigint,gen_random_uuid());
 event_id:=(response#>>'{data,occasionId}')::bigint;
 PERFORM assert_false((public.get_occasion_setup_communication(draft)->>'firstEvent')::boolean,'Materialized event clears the first-event hint');
 EXECUTE 'RESET ROLE';
 SELECT id INTO inherited_form FROM public.forms WHERE occasion=event_id ORDER BY id LIMIT 1;
 SELECT f INTO form_feature FROM public.occasions o CROSS JOIN LATERAL jsonb_array_elements(o.features) f WHERE o.id=event_id AND f->>'code'='form';
 PERFORM assert_false((SELECT coalesce(data,'{}') ? 'reply_to' FROM public.occasions WHERE id=event_id),'Inherited reply address stays absent on event');
 PERFORM assert_false((SELECT coalesce(data,'{}') ?| ARRAY['communication_tone','is_reminder_enabled','reminder_interval_seconds'] FROM public.forms WHERE id=inherited_form),'Inherited choices remove copied form overrides');
 PERFORM assert_eq((SELECT data->>'fixture_retained' FROM public.forms WHERE id=inherited_form),'yes','Unrelated form metadata survives');
 PERFORM assert_false((form_feature->>'reminder_is_enabled')::boolean,'Reminder snapshot uses current unit default at finalization');
 PERFORM assert_eq((form_feature->>'reminder_interval_seconds')::bigint,172800::bigint,'Reminder interval snapshot uses current unit default');
 PERFORM assert_eq(public.get_effective_form_data(inherited_form)->>'communication_tone','formal','Inherited tone uses current unit default');
 PERFORM assert_eq((SELECT data FROM public.units WHERE id=unit_id),unit_data,'Finalization never changes unit defaults');
 UPDATE public.units SET data=data||'{"communication_tone":"informal","reminder_interval_seconds":259200}' WHERE id=unit_id;
 PERFORM assert_eq(public.get_effective_form_data(inherited_form)->>'communication_tone','informal','Inherited tone follows later unit changes');
 PERFORM assert_eq((SELECT f->>'reminder_interval_seconds' FROM public.occasions o CROSS JOIN LATERAL jsonb_array_elements(o.features) f WHERE o.id=event_id AND f->>'code'='form'),'172800','Reminder snapshot does not follow later unit changes');
 SELECT data INTO unit_data FROM public.units WHERE id=unit_id;
 UPDATE public.unit_users SET is_manager=true WHERE unit=unit_id AND "user"=actor;
 -- Event-specific overrides must not change the unit, even for a manager.
 draft:=gen_random_uuid();
 EXECUTE 'SET LOCAL ROLE authenticated';
 d:=public.create_occasion_setup_draft(draft,unit_id);
 payload:=d->'data'||jsonb_build_object('title','Custom communication','start','2090-07-01T18:00:00Z','end','2090-07-02T02:00:00Z',
  'reviewConfirmed',true,'formEnabled',true,'formLinkAutomatic',true,
  'communicationTone','formal','replyToMode','custom','replyToEmail',' event@test.local ',
  'remindersMode','enabled','reminderLeadDays','1,5',
  'bankAccountId',bank_id,'bankAccountConfirmed',true,'bankAccountFingerprint',bank_info->'accounts'->0->>'fingerprint');
 d:=public.save_occasion_setup_draft(draft,(d->>'revision')::bigint,payload,5);
 response:=public.finalize_occasion_setup_draft(draft,(d->>'revision')::bigint,gen_random_uuid());
 event_id:=(response#>>'{data,occasionId}')::bigint;
 EXECUTE 'RESET ROLE';
 SELECT id INTO custom_form FROM public.forms WHERE occasion=event_id ORDER BY id LIMIT 1;
 PERFORM assert_eq((SELECT data->>'reply_to' FROM public.occasions WHERE id=event_id),'event@test.local','Custom reply address belongs to this event');
 PERFORM assert_eq((SELECT data->>'communication_tone' FROM public.forms WHERE id=custom_form),'formal','Custom tone belongs to this form');
 PERFORM assert_true((SELECT (data->>'is_reminder_enabled')::boolean FROM public.forms WHERE id=custom_form),'Paid form can explicitly enable reminders');
 PERFORM assert_eq((SELECT (data->>'reminder_interval_seconds')::bigint FROM public.forms WHERE id=custom_form),129600::bigint,'Decimal day override is stored in canonical seconds');
 PERFORM assert_eq(public.get_effective_form_data(custom_form)->>'communication_tone','formal','Custom tone wins over unit default');
 PERFORM assert_eq((SELECT data FROM public.units WHERE id=unit_id),unit_data,'Custom event settings do not mutate unit');
 -- Invalid custom addresses must fail atomically, before any event is created.
 SELECT count(*) INTO event_count FROM public.occasions WHERE unit=unit_id;
 draft:=gen_random_uuid();
 EXECUTE 'SET LOCAL ROLE authenticated';
 d:=public.create_occasion_setup_draft(draft,unit_id);
 payload:=payload||'{"replyToEmail":"not an email"}';
 d:=public.save_occasion_setup_draft(draft,(d->>'revision')::bigint,payload,5);
 BEGIN PERFORM public.finalize_occasion_setup_draft(draft,(d->>'revision')::bigint,gen_random_uuid()); RAISE EXCEPTION 'Invalid custom reply accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq((SELECT count(*) FROM public.occasions WHERE unit=unit_id),event_count,'Rejected communication creates no event');
 DELETE FROM public.unit_users WHERE unit=unit_id AND "user"=actor;
 EXECUTE 'SET LOCAL ROLE authenticated';
 BEGIN PERFORM public.get_occasion_setup_communication(draft); RAISE EXCEPTION 'Revoked communication read accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 EXECUTE 'RESET ROLE';
END $$;
