DO $$
DECLARE org bigint; u bigint; other_unit bigint; actor uuid; editor uuid;
 start jsonb; claim jsonb; result jsonb; replacement jsonb; replacement_claim jsonb; conn uuid; candidate uuid; occasion_id bigint; card_form bigint; bank_form bigint;
 account jsonb:=jsonb_build_object('accountId','acct_connectionFixture','businessName','Organizer fixture','country','CZ',
 'modelVerified',true,'chargesEnabled',true,'payoutsEnabled',false,'cardPaymentsActive',true,'ready',true);
BEGIN
 INSERT INTO public.organizations(title) VALUES('Stripe connection tenant') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Connection organizer',org) RETURNING id INTO u;
 INSERT INTO public.units(title,organization) VALUES('Other organizer',org) RETURNING id INTO other_unit;
 PERFORM public.create_user_for_test('stripe_manager','stripe-manager@example.test');actor:=get_user_id('stripe_manager');
 PERFORM public.create_user_for_test('stripe_editor','stripe-editor@example.test');editor:=get_user_id('stripe_editor');
 UPDATE public.user_info SET organization=org WHERE id IN(actor,editor);
 INSERT INTO public.unit_users(unit,"user",is_manager,is_editor) VALUES(u,actor,true,true),(u,editor,false,true),(other_unit,actor,true,true);
 PERFORM set_config('request.jwt.claim.sub',editor::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 BEGIN
  PERFORM public.begin_stripe_connection_flow(u,false);RAISE EXCEPTION 'editor connected Stripe';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 start:=public.begin_stripe_connection_flow(u,false);
 PERFORM assert_true(start->>'state' ~ '^[a-f0-9]{64}$','cryptographic server OAuth state');
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 BEGIN
  PERFORM public.claim_stripe_connection_flow_internal(start->>'state',editor,false);RAISE EXCEPTION 'changed actor accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'STRIPE_CONNECTION_FLOW_INVALID' THEN RAISE; END IF; END;
 BEGIN
  PERFORM public.claim_stripe_connection_flow_internal(start->>'state',actor,true);RAISE EXCEPTION 'changed environment accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'STRIPE_CONNECTION_FLOW_INVALID' THEN RAISE; END IF; END;
 claim:=public.claim_stripe_connection_flow_internal(start->>'state',actor,false);
 PERFORM assert_eq(claim->>'disposition','claimed','claim before external request');
 PERFORM assert_eq(public.claim_stripe_connection_flow_internal(start->>'state',actor,false)->>'disposition','uncertain','parallel callback cannot exchange twice');
 result:=public.complete_stripe_connection_flow_internal((claim->>'flowId')::uuid,(claim->>'lease')::uuid,account);
 conn:=(result->>'connectionId')::uuid;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
  VALUES('Recipient replacement',org,u,'stripe-replace-'||extensions.gen_random_uuid(),now(),now()+interval '1 day') RETURNING id INTO occasion_id;
 INSERT INTO public.forms(occasion,data,key) VALUES(occasion_id,jsonb_build_object('payments',jsonb_build_object('bankEnabled',false,'stripeConnectionId',conn)),extensions.gen_random_uuid()) RETURNING id INTO card_form;
 INSERT INTO public.forms(occasion,data,key) VALUES(occasion_id,'{}',extensions.gen_random_uuid()) RETURNING id INTO bank_form;
 PERFORM assert_true((SELECT paused AND charges_enabled AND NOT payouts_enabled FROM eshop.stripe_connections WHERE id=conn),'charges and payouts independent; linking does not unpause');
 PERFORM assert_eq(public.claim_stripe_connection_flow_internal(start->>'state',actor,false)->>'disposition','replay','callback replay returns saved completion');
 PERFORM assert_eq((SELECT count(*) FROM eshop.stripe_connection_audit WHERE connection_id=conn),1::bigint,'callback replay cannot duplicate audit');
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM public.set_stripe_unit_paused(u,false,false);
 PERFORM assert_true((public.get_stripe_unit_connection(u,false)->>'payoutsEnabled')::boolean=false,'safe status keeps payouts separate');
 replacement:=public.begin_stripe_connection_flow(u,false);
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 replacement_claim:=public.claim_stripe_connection_flow_internal(replacement->>'state',actor,false);
 PERFORM set_config('request.jwt.claim.sub','',true);
 BEGIN
  PERFORM public.complete_stripe_connection_flow_internal((replacement_claim->>'flowId')::uuid,(replacement_claim->>'lease')::uuid,
   account||jsonb_build_object('accountId','acct_replacement','modelVerified',false));RAISE EXCEPTION 'unverified model accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'STRIPE_ACCOUNT_MODEL_UNVERIFIED' THEN RAISE; END IF; END;
 PERFORM assert_eq((SELECT state FROM eshop.stripe_connections WHERE id=conn),'connected','failed replacement retains old recipient');
 PERFORM assert_eq((SELECT data#>>'{payments,stripeConnectionId}' FROM public.forms WHERE id=card_form),conn::text,'failed replacement preserves form binding');
 result:=public.complete_stripe_connection_flow_internal((replacement_claim->>'flowId')::uuid,(replacement_claim->>'lease')::uuid,
  account||jsonb_build_object('accountId','acct_replacement'));
 candidate:=(result->>'connectionId')::uuid;
 PERFORM assert_eq((SELECT state FROM eshop.stripe_connections WHERE id=conn),'retired','replacement retains old identity for history');
 PERFORM assert_true((SELECT paused FROM eshop.stripe_connections WHERE id=candidate),'replacement does not silently start accepting money');
 PERFORM assert_eq((SELECT data#>>'{payments,stripeConnectionId}' FROM public.forms WHERE id=card_form),candidate::text,'verified replacement atomically switches future card orders');
 PERFORM assert_eq((SELECT data#>>'{payments,bankEnabled}' FROM public.forms WHERE id=card_form),'false','replacement retains the chosen Stripe-only policy');
 PERFORM assert_true(NOT (SELECT data ? 'payments' FROM public.forms WHERE id=bank_form),'bank-only form is never enabled by connecting');
 PERFORM assert_eq((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='form' AND scope_id=occasion_id AND aggregate_id=card_form::text),1::bigint,'replacement fences stale editor drafts');
 PERFORM assert_eq((SELECT count(*) FROM public.client_mutation_receipts WHERE occasion=occasion_id AND command_name='inventory.form.stripe_recipient' AND status='completed'),1::bigint,'form replacement commits its Client Sync receipt');
 PERFORM assert_eq(public.claim_stripe_connection_flow_internal(replacement->>'state',actor,false)->>'disposition','replay','replacement replay returns its flow receipt');
 PERFORM assert_eq((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='form' AND scope_id=occasion_id AND aggregate_id=card_form::text),1::bigint,'replacement replay never changes a form twice');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.client_sync_component_sources WHERE source_relation='public.forms'::regclass
  AND canonical_writers @> ARRAY['complete_stripe_connection_flow_internal']),'replacement writer is registered for Client Sync');
 PERFORM assert_false(EXISTS(SELECT 1 FROM public.client_sync_component_sources WHERE source_relation IN
  ('eshop.stripe_capabilities'::regclass,'eshop.stripe_payment_link_sources'::regclass)),'private payment credentials have no client projection');
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM set_config('request.jwt.claim.sub',actor::text,true);
 start:=public.begin_stripe_connection_flow(other_unit,false);
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 claim:=public.claim_stripe_connection_flow_internal(start->>'state',actor,false);
 BEGIN
  PERFORM public.complete_stripe_connection_flow_internal((claim->>'flowId')::uuid,(claim->>'lease')::uuid,account);
  RAISE EXCEPTION 'account adopted across units';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'STRIPE_ACCOUNT_UNAVAILABLE' THEN RAISE; END IF; END;
 PERFORM assert_false(has_function_privilege('authenticated','public.complete_stripe_connection_flow_internal(uuid,uuid,jsonb)','EXECUTE'),'client cannot provide provider identity');
 PERFORM assert_false(has_function_privilege('anon','public.begin_stripe_connection_flow(bigint,boolean)','EXECUTE'),'anonymous connect denied');
END $$;
