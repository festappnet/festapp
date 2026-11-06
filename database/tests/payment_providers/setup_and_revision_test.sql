DO $$
DECLARE fx jsonb:=public.scanner_test_fixture(1); oc bigint:=(fx->>'occasion')::bigint; f bigint:=(fx->>'form')::bigint;
 org bigint; u bigint; actor uuid:=extensions.gen_random_uuid(); draft uuid:=extensions.gen_random_uuid(); conn uuid; options jsonb; payload jsonb; result jsonb;
BEGIN
 SELECT organization,unit INTO org,u FROM public.occasions WHERE id=oc;
 INSERT INTO auth.users(id,email) VALUES(actor,actor||'@payment-test.invalid');
 INSERT INTO public.user_info(id,organization) VALUES(actor,org);
 INSERT INTO public.unit_users(unit,"user",is_editor,is_manager) VALUES(u,actor,true,false);
 INSERT INTO public.occasion_users(occasion,"user",is_editor) VALUES(oc,actor,true);
 INSERT INTO public.occasion_setup_drafts(id,unit,organization,author) VALUES(draft,u,org,actor);
 INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state,model_verified)
 VALUES(org,u,'acct_setupAuthor',false,'connected',true) RETURNING id INTO conn;
 PERFORM set_config('request.jwt.claim.sub','',true);
 BEGIN PERFORM public.get_setup_payment_options(draft);RAISE EXCEPTION 'anonymous setup options allowed';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 options:=public.get_setup_payment_options(draft);
 PERFORM assert_eq(options#>>'{providerRecipients,stripe,0,connectionId}',conn::text,'unit editor can choose recipient without management role');
 PERFORM assert_true(NOT options::text LIKE '%acct_setupAuthor%' AND NOT options::text LIKE '%dashboard%','setup options have no private management identity');
 payload:=jsonb_build_object('id',f,'occasion',oc,'settings',jsonb_build_object('payments',jsonb_build_object('bankEnabled',true,'providerConnections',jsonb_build_object('stripe',conn))));
 BEGIN PERFORM public.update_form_client_sync_v1(payload,extensions.gen_random_uuid());RAISE EXCEPTION 'revisionless modern snapshot accepted';
 EXCEPTION WHEN invalid_parameter_value THEN IF SQLERRM<>'modern payment snapshot requires original form revision' THEN RAISE; END IF; END;
 result:=public.update_form_client_sync_v1(payload||'{"expected_aggregate_version":1}'::jsonb,extensions.gen_random_uuid());
 PERFORM assert_eq(result->>'status','conflict','stale modern snapshot fails before replacing another provider');
 PERFORM assert_true(NOT coalesce((SELECT data ? 'payments' FROM public.forms WHERE id=f),false),'conflict never installs a binding');
END $$;
