DO $$
DECLARE actor uuid; org bigint; target bigint; other_unit bigint; cmd uuid:=gen_random_uuid(); conf jsonb;
 result jsonb; draft uuid:=gen_random_uuid(); before_usage bigint; before_count bigint; rev bigint; policy jsonb;
BEGIN
 SELECT ui.id,ui.organization INTO actor,org FROM public.user_info ui
 JOIN public.unit_users uu ON uu."user"=ui.id WHERE uu.is_manager LIMIT 1;
 SELECT unit INTO target FROM public.unit_users WHERE "user"=actor AND is_manager LIMIT 1;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 SELECT revision INTO rev FROM public.abuse_policy_revision;
 PERFORM public.set_abuse_policy_v1(rev,'Isolated admission behavior test','[{"rule_key":"occasion.create.actor.day","base_limit":1}]');
 conf:=jsonb_build_object('unit',target,'organization',org,'title','Admission test','start_time',now(),'end_time',now()+interval '1 day');
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 PERFORM assert_false(has_function_privilege('authenticated','public.admit_occasion_creation_v1(uuid,bigint,bigint)','EXECUTE'),'helper is private');
 PERFORM assert_false(has_table_privilege('authenticated','public.abuse_policy_rules','UPDATE'),'policy is protected');
 result:=public.create_occasion_client_sync_v1(cmd,conf);
 PERFORM assert_eq(public.create_occasion_client_sync_v1(cmd,conf)->'data',result->'data','receipt replay returns existing aggregate');
 EXECUTE 'RESET ROLE';
 SELECT sum(amount) INTO before_usage FROM public.abuse_budget_usage;
 SELECT count(*) INTO before_count FROM public.occasions;
 EXECUTE 'SET LOCAL ROLE authenticated';
 BEGIN
  PERFORM public.create_occasion_client_sync_v1(gen_random_uuid(),conf);
  RAISE EXCEPTION 'new UUID bypassed daily budget';
 EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 BEGIN
  PERFORM public.duplicate_occasion_client_sync_v1((result#>>'{data,occasionId}')::bigint,gen_random_uuid());
  RAISE EXCEPTION 'copy bypassed create budget';
 EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 -- A draft uses its own budget, never the exhausted creation budget.
 PERFORM public.create_occasion_setup_draft(draft,target);
 PERFORM public.create_occasion_setup_draft(draft,target);
 PERFORM public.save_occasion_setup_draft(draft,1,jsonb_build_object('title','Finalize under exhausted budget',
  'reviewConfirmed',true,'start',now(),'end',now()+interval '1 day','formEnabled',false),6);
 BEGIN PERFORM public.finalize_occasion_setup_draft(draft,2,gen_random_uuid()); RAISE EXCEPTION 'finalize bypassed shared create budget'; EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq((SELECT count(*) FROM public.occasions),before_count,'denied commands and bootstrap leave no occasions');
 PERFORM assert_eq((SELECT amount FROM public.abuse_budget_usage WHERE rule_key='occasion.create.actor.day' AND scope_id=actor::text),1::bigint,'replay and denial never charge creation twice');
 PERFORM assert_eq((SELECT sum(amount) FROM public.abuse_budget_usage WHERE rule_key='draft.create.actor.day' AND scope_id=actor::text),1::numeric,'draft retry charged once');
 -- Bootstrap defaults must obey a lowered payload policy too, not just saves.
 UPDATE public.abuse_policy_rules SET base_limit=1 WHERE rule_key='draft.payload.bytes';
 BEGIN PERFORM public.create_occasion_setup_draft(gen_random_uuid(),target); RAISE EXCEPTION 'bootstrap bypassed actual stored byte limit'; EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 PERFORM assert_eq((SELECT count(*) FROM public.occasion_setup_drafts WHERE author=actor),1::bigint,'oversized bootstrap leaves no partial draft');
 UPDATE public.abuse_policy_rules SET base_limit=262144 WHERE rule_key='draft.payload.bytes';
 -- Override cannot change actor capacity by switching target Unit.
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 SELECT revision INTO rev FROM public.abuse_policy_revision;
 BEGIN
  PERFORM public.set_abuse_policy_v1(rev,'Invalid actor scope override',jsonb_build_array(jsonb_build_object('rule_key','occasion.create.actor.day','target_kind','unit','target_id',target,'expires_at',now()+interval '1 day','base_limit',10)));
  RAISE EXCEPTION 'actor override accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 PERFORM public.set_abuse_policy_v1(rev,'Increase without resetting usage','[{"rule_key":"occasion.create.actor.day","base_limit":2}]');
 EXECUTE 'SET LOCAL ROLE authenticated';
 PERFORM public.create_occasion_client_sync_v1(gen_random_uuid(),conf);
 BEGIN PERFORM public.create_occasion_client_sync_v1(gen_random_uuid(),conf); RAISE EXCEPTION 'revision reset usage'; EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 EXECUTE 'RESET ROLE';
 PERFORM assert_eq((SELECT amount FROM public.abuse_budget_usage WHERE rule_key='occasion.create.actor.day' AND scope_id=actor::text),2::bigint,'policy revision preserves prior usage');
 -- Daily exhaustion survives an empty short window; final rule rejection changes no other budget.
 DELETE FROM public.abuse_budget_usage WHERE rule_key LIKE 'occasion.%.burst';
 SELECT sum(amount) INTO before_usage FROM public.abuse_budget_usage;
 BEGIN PERFORM public.admit_occasion_creation_v1(actor,target,org); RAISE EXCEPTION 'short window reset daily budget'; EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 PERFORM assert_eq((SELECT sum(amount) FROM public.abuse_budget_usage),before_usage::numeric,'all-rule rejection is atomic');
END $$;
