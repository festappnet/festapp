DO $$
DECLARE a uuid; b uuid; org bigint; un bigint; un2 bigint; config jsonb; before_amount numeric; policy jsonb;
BEGIN
 PERFORM create_user_for_test('abuse-a','abuse-a@example.invalid'); a:=get_user_id('abuse-a');
 PERFORM create_user_for_test('abuse-b','abuse-b@example.invalid'); b:=get_user_id('abuse-b');
 INSERT INTO public.organizations(title) VALUES('Scope fixture') RETURNING id INTO org;
 UPDATE public.user_info SET organization=org WHERE id IN (a,b);
 INSERT INTO public.units(title,organization) VALUES('First',org) RETURNING id INTO un;
 INSERT INTO public.units(title,organization) VALUES('Second',org) RETURNING id INTO un2;
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES(un,a,true,true),(un,b,true,true),(un2,a,true,true),(un2,b,true,true);
 UPDATE public.abuse_policy_rules SET base_limit=1 WHERE rule_key='occasion.create.unit.day';
 config:=jsonb_build_object('unit',un,'organization',org,'title','Scope test','start_time',now(),'end_time',now()+interval '1 day');
 PERFORM set_config('request.jwt.claim.sub',a::text,true); PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM public.create_occasion_client_sync_v1(gen_random_uuid(),config);
 PERFORM set_config('request.jwt.claim.sub',b::text,true);
 BEGIN PERFORM public.create_occasion_client_sync_v1(gen_random_uuid(),config); RAISE EXCEPTION 'second editor reset Unit quota'; EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 -- An independent Unit retains its capacity in the same tenant.
 config:=jsonb_set(config,'{unit}',to_jsonb(un2));
 PERFORM public.create_occasion_client_sync_v1(gen_random_uuid(),config);
 -- Actor quota follows the canonical UUID across target Units.
 UPDATE public.abuse_policy_rules SET base_limit=1 WHERE rule_key='occasion.create.actor.day';
 BEGIN PERFORM public.create_occasion_client_sync_v1(gen_random_uuid(),config); RAISE EXCEPTION 'Unit switch reset actor quota'; EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 -- Hiding does not free actual stored resources; rolling usage survives delete.
 UPDATE public.occasions SET is_hidden=true WHERE unit=un2;
 PERFORM public.delete_occasion_client_sync_v1((SELECT id FROM public.occasions WHERE unit=un2 LIMIT 1),gen_random_uuid());
 BEGIN PERFORM public.create_occasion_client_sync_v1(gen_random_uuid(),config); RAISE EXCEPTION 'delete reset rolling quota'; EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 -- Simulate a prior bucket, across a calendar day boundary. No midnight reset.
 DELETE FROM public.abuse_budget_usage WHERE rule_key='occasion.create.actor.day' AND scope_id=a::text;
 INSERT INTO public.abuse_budget_usage VALUES('occasion.create.actor.day',a::text,date_trunc('hour',statement_timestamp())-interval '24 hours',1,statement_timestamp()+interval '1 hour');
 PERFORM set_config('request.jwt.claim.sub',a::text,true);
 config:=jsonb_set(config,'{unit}',to_jsonb(un2));
 BEGIN PERFORM public.create_occasion_client_sync_v1(gen_random_uuid(),config); RAISE EXCEPTION 'leading rolling bucket ignored'; EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 -- A later rule denial rolls back all earlier prospective business charges.
 SELECT sum(amount) INTO before_amount FROM public.abuse_budget_usage;
 BEGIN PERFORM public.admit_occasion_creation_v1(a,un2,org); EXCEPTION WHEN SQLSTATE 'PT429' THEN NULL; END;
 PERFORM assert_eq((SELECT sum(amount) FROM public.abuse_budget_usage),before_amount,'no partial charges after last-rule refusal');
 -- Usage has no cascading dependency on Unit/occasion lifetime.
 PERFORM assert_false(EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.abuse_budget_usage'::regclass AND contype='f'),'usage cannot disappear via domain cascade');
END $$;
