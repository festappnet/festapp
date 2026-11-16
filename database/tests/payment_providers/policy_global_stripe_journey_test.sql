-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
-- Real canonical SQL checkout/settlement/delivery with deterministic verified provider facts.
-- No provider HTTP request, paid transaction or production identity is used.
DO $$
DECLARE x jsonb:=pg_temp.payment_fixture(); org bigint:=(x->>'organization')::bigint; un bigint; f bigint:=(x->>'form')::bigint;
 input jsonb; preview jsonb; r jsonb; audit jsonb; connection uuid; cmd uuid:=gen_random_uuid(); new_order bigint; pi bigint; tid bigint;
 attempt eshop.stripe_checkout_attempts; claim jsonb; sync_claim jsonb; facts jsonb; source jsonb; payload jsonb; free_order bigint; before_refs bigint;
BEGIN
 SELECT unit INTO un FROM public.occasions WHERE id=(x->>'occasion')::bigint;
 UPDATE public.organizations SET title='Festapp Tickets Global',data=coalesce(data,'{}')||'{"DEFAULT_URL":"https://tickets.example","DEFAULT_LANGUAGE":"en"}' WHERE id=org;
 INSERT INTO public.organization_users(organization,"user",is_admin) VALUES(org,(x->>'actor')::uuid,true);
 input:=jsonb_build_object('organizationId',org,'method','bank','mode','disabled','preferredMethod','stripe');
 SET LOCAL ROLE authenticated;
 preview:=public.preview_payment_method_policy(input); PERFORM public.command_payment_method_policy(input,gen_random_uuid(),preview->>'confirmation');
 RESET ROLE;
 UPDATE public.forms SET data='{"payments":{"bankEnabled":false,"providerConnections":{}}}',bank_account=NULL WHERE id=f;
 PERFORM assert_eq(public.form_payment_availability_internal(f)->'available','[]'::jsonb,'unconfigured Global has no bank fallback');
 SET LOCAL ROLE authenticated;
 r:=public.get_payment_method_policy(org,un);
 audit:=public.get_payment_template_audit(f); PERFORM public.review_payment_templates(f,audit->>'revision');
 RESET ROLE;
 PERFORM assert_true((r#>>'{methods,stripe,canConfigure}')::boolean,'authorized onboarding available before connection');
 PERFORM assert_false((r#>>'{methods,stripe,configured}')::boolean,'permission is not a ready connector');
 INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state,paused,model_verified,charges_enabled,card_payments_active)
 VALUES(org,un,'acct_policyGlobal',false,'connected',false,true,true,true) RETURNING id INTO connection;
 INSERT INTO eshop.stripe_runtime_policy(organization_id,livemode,new_payments_enabled,online_admission_verified,reservation_policy_verified,dispute_policy_accepted,supported_surfaces)
 VALUES(org,false,true,true,true,true,ARRAY['web']);
 UPDATE public.forms SET data=jsonb_build_object('payments',jsonb_build_object('bankEnabled',false,'providerConnections',jsonb_build_object('stripe',connection))) WHERE id=f;
 PERFORM assert_eq(public.form_payment_availability_internal(f)->'available','["stripe"]'::jsonb,'ready Global offers only Stripe');
 source:=jsonb_build_object('tokenHash',encode(extensions.digest(repeat('1',64),'sha256'),'hex'),'returnHash',encode(extensions.digest(repeat('2',64),'sha256'),'hex'),
  'contentHash',repeat('c',64),'sealed',jsonb_build_object('v','1','iv','fixture','ciphertext','fixture'));
 payload:=jsonb_build_object('form',(SELECT key FROM public.forms WHERE id=f),'email','global-journey@example.invalid','payment_method','stripe','payment_type','full',
  'expected_payment_amount_minor',100000,'expected_payment_currency','CZK','stripe_connection_id',connection,'payment_surface','web','stripePaymentSource',source,
  'ticket',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',x->'product')))));
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 r:=public.create_ticket_order_client_sync_v1(payload,cmd,gen_random_uuid());
 PERFORM assert_eq(r->>'status','applied','Global canonical checkout: '||r::text);
 new_order:=(r#>>'{data,order,id}')::bigint;
 SELECT payment_info INTO pi FROM eshop.orders WHERE id=new_order;
 SELECT DISTINCT ticket INTO tid FROM eshop.order_product_ticket WHERE "order"=new_order;
 SELECT * INTO STRICT attempt FROM eshop.stripe_checkout_attempts WHERE order_id=new_order;
 PERFORM assert_true((SELECT bank_account IS NULL AND variable_symbol IS NULL AND creditor_reference IS NULL FROM eshop.payment_info WHERE id=pi),'gateway creates no bank identity');
 claim:=public.claim_stripe_checkout_internal(repeat('1',64),false);
 PERFORM assert_eq(claim->>'disposition','dispatch','original private capability authorizes one checkout claim');
 PERFORM public.commit_stripe_checkout_session_internal(attempt.id,(claim->>'lease')::uuid,'cs_test_policyGlobal','https://checkout.stripe.com/c/pay/cs_test_policyGlobal',extract(epoch FROM attempt.reservation_expires_at)::bigint);
 sync_claim:=public.claim_stripe_sync_internal('acct_policyGlobal',false,attempt.id,'cs_test_policyGlobal',NULL);
 facts:=jsonb_build_object('observedAt',clock_timestamp(),'sessionId','cs_test_policyGlobal','paymentIntentId','pi_policyGlobal','sessionStatus','complete',
  'movements',jsonb_build_array(jsonb_build_object('providerId','pi_policyGlobal','kind','payment','amountMinor',100000,'currency','CZK','occurredAt',extract(epoch FROM attempt.created_at)::bigint)),'disputes','[]'::jsonb);
 PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM public.ingest_stripe_payment_internal(attempt.id,(sync_claim->>'lease')::uuid,jsonb_build_object('id','evt_policyGlobal','bodyHash',repeat('a',64),'accountId','acct_policyGlobal','livemode',false,'type','checkout.session.completed','created',extract(epoch FROM now())::bigint),facts);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=new_order),'paid','verified settlement grants paid state');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.email_messages WHERE order_id=new_order AND message_kind='order_tickets'),'same engine queues ticket delivery');
 PERFORM pg_temp.payment_accept_tickets(x||jsonb_build_object('order',new_order,'ticket',tid,'payment',pi));
 PERFORM assert_true(public.provider_ticket_admission_allowed_internal(tid),'verified settlement and accepted ticket delivery leave valid admission');
 -- Closing future sales does not block a supported original-connector refund.
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM set_config('request.jwt.claim.sub',x->>'actor',true);
 input:=jsonb_build_object('organizationId',org,'unitId',un,'method','stripe','mode','disabled');
 SET LOCAL ROLE authenticated;
 preview:=public.preview_payment_method_policy(input); PERFORM public.command_payment_method_policy(input,gen_random_uuid(),preview->>'confirmation');
 RESET ROLE;
 UPDATE eshop.payment_providers SET refund_write_enabled=true WHERE provider_key='stripe';
 SET LOCAL ROLE authenticated;
 r:=public.command_payment_operation(jsonb_build_object('operation','prepare_refund','orderId',new_order,'method','stripe','amount','100'),gen_random_uuid());
 RESET ROLE;
 PERFORM assert_eq(r#>>'{data,nextAction}','processing','original gateway servicing works after sales disable');
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=pi),0::numeric,'refund intent is not settlement');
 -- A free registration needs no gateway connection and still cannot issue bank instructions.
 UPDATE eshop.products SET price=0 WHERE id=(x->>'product')::bigint;
 UPDATE public.forms SET data='{"payments":{"bankEnabled":false,"providerConnections":{}}}' WHERE id=f;
 SELECT count(*) INTO before_refs FROM eshop.payment_reference_reservations;
 payload:=payload-'payment_method'-'stripePaymentSource'-'stripe_connection_id'-'expected_payment_amount_minor'-'expected_payment_currency';
 r:=public.create_ticket_order_client_sync_v1(payload,gen_random_uuid(),gen_random_uuid());
 PERFORM assert_eq(r->>'status','applied','free registration works with no ready payment method: '||r::text);
 free_order:=(r#>>'{data,order,id}')::bigint;
 PERFORM assert_true((SELECT p.amount=0 AND p.bank_account IS NULL AND p.variable_symbol IS NULL FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=free_order),'no-money storage boundary issues no bank account or reference');
 PERFORM assert_eq((SELECT count(*) FROM eshop.payment_reference_reservations),before_refs,'free registration allocates no new reference');
 PERFORM assert_true(public.customer_order_payment_internal(free_order)->'qrPayment' IS NULL OR public.customer_order_payment_internal(free_order)->'qrPayment'='null'::jsonb,'free registration has no payment QR');
END $$;
