-- Temporary fault injection is rolled back by the test runner.
ALTER TABLE public.email_messages ADD CONSTRAINT stripe_test_email_fault CHECK(message_kind<>'order_tickets') NOT VALID;
DO $$
DECLARE org bigint; u bigint; occ bigint; f bigint; pt bigint; p bigint; conn uuid; payload jsonb; result jsonb; replay jsonb;
 source jsonb:=jsonb_build_object('tokenHash',encode(extensions.digest(repeat('1',64),'sha256'),'hex'),'returnHash',encode(extensions.digest(repeat('2',64),'sha256'),'hex'),'contentHash',repeat('c',64),
  'sealed',jsonb_build_object('v','1','iv','fixture','ciphertext','fixture'));
 command uuid:=extensions.gen_random_uuid(); client uuid:=extensions.gen_random_uuid(); oid bigint; pi bigint; attempt eshop.stripe_checkout_attempts; claim jsonb; sync_claim jsonb; facts jsonb; event jsonb; response jsonb; count_before bigint;
 legacy_bank bigint; manager uuid; flow jsonb; original_attempts jsonb;
BEGIN
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM set_config('request.jwt.claim.sub','',true);
 INSERT INTO public.organizations(title,data) VALUES('Stripe create tenant','{"DEFAULT_URL":"https://tickets.example"}') RETURNING id INTO org;
 INSERT INTO public.units(title,organization) VALUES('Card receiver',org) RETURNING id INTO u;
 INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time)
 VALUES('Card order',org,u,'stripe-create-'||extensions.gen_random_uuid(),now(),now()+interval '2 days') RETURNING id INTO occ;
 INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state,paused,model_verified,charges_enabled,card_payments_active)
 VALUES(org,u,'acct_createFixture',false,'connected',false,true,true,true) RETURNING id INTO conn;
 INSERT INTO eshop.stripe_runtime_policy(organization_id,livemode,new_payments_enabled,online_admission_verified,reservation_policy_verified,dispute_policy_accepted,supported_surfaces)
 VALUES(org,false,true,true,true,true,ARRAY['web']);
 INSERT INTO public.forms(occasion,data,is_open,key) VALUES(occ,jsonb_build_object('payments',jsonb_build_object('bankEnabled',false,'stripeConnectionId',conn)),true,extensions.gen_random_uuid()) RETURNING id INTO f;
 INSERT INTO eshop.product_types(occasion,title,type) VALUES(occ,'Card tickets','spot') RETURNING id INTO pt;
 INSERT INTO eshop.products(product_type,occasion,title,price,currency_code,is_hidden) VALUES(pt,occ,'Card ticket',123.45,'CZK',false) RETURNING id INTO p;
 INSERT INTO public.form_fields(form,product_type,type) VALUES(f,pt,'product_type');
 payload:=jsonb_build_object('form',(SELECT key FROM public.forms WHERE id=f),'email','card@example.test','payment_method','stripe',
  'payment_type','full','expected_payment_amount_minor',12345,'expected_payment_currency','CZK','stripe_connection_id',conn,'payment_surface','web','stripePaymentSource',source,
  'ticket',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',p)))));
 result:=public.create_ticket_order_client_sync_v1(payload,command,client);
 PERFORM assert_eq(result#>>'{data,code}','200','canonical card create succeeds: '||result::text);
 oid:=(result#>>'{data,order,id}')::bigint;
 SELECT payment_info INTO pi FROM eshop.orders WHERE id=oid;
 SELECT * INTO STRICT attempt FROM eshop.stripe_checkout_attempts WHERE order_id=oid;
 PERFORM assert_eq(attempt.amount_minor,12345::bigint,'price originates from product catalog');
 PERFORM assert_true(attempt.reservation_expires_at=attempt.created_at+interval '31 minutes','fixed reservation and dispatch allowance');
 BEGIN
  PERFORM public.cancel_order_domain_internal_v1(oid,false);RAISE EXCEPTION 'ordinary cancellation changed a Stripe order';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'STRIPE_USE_REFUND_ADMISSION_DECISION' THEN RAISE; END IF; END;
 PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=oid),123.45::numeric,'rejected ordinary cancellation retains original amount');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'ordered','rejected ordinary cancellation retains reservation');

 PERFORM assert_true((SELECT bank_account IS NULL AND variable_symbol IS NULL AND creditor_reference IS NULL AND deposit_amount IS NULL FROM eshop.payment_info WHERE id=pi),'card needs no bank account or bank instructions');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'ordered','return/create is not proof of payment');
 PERFORM assert_eq((SELECT count(*) FROM eshop.stripe_payment_link_sources WHERE command_id=command),1::bigint,'source commits with order');
 PERFORM assert_true(NOT (SELECT data ? 'stripePaymentSource' FROM eshop.orders WHERE id=oid),'sealed capability excluded from order history and projection');
 PERFORM assert_eq(result#>>'{data,payment,method}','stripe','safe payment projection accompanies order');
 replay:=public.create_ticket_order_client_sync_v1(jsonb_set(payload,'{stripePaymentSource,tokenHash}',to_jsonb(repeat('d',64))),command,client);
 PERFORM assert_eq(replay#>>'{data,order,id}',oid::text,'same command retains original order and source');
 PERFORM assert_eq((SELECT count(*) FROM eshop.stripe_checkout_attempts WHERE order_id=oid),1::bigint,'replay cannot create another attempt');

 PERFORM public.attach_stripe_handoff_internal(oid,command,encode(extensions.digest(repeat('e',64),'sha256'),'hex'),false);
 response:=public.read_stripe_handoff_internal(repeat('e',64),false,false);
 PERFORM assert_true(NOT response ? 'source' AND NOT response::text LIKE '%@%','handoff status is minimal and never reveals its encrypted pay source');
 BEGIN
  PERFORM public.read_stripe_handoff_internal(repeat('1',64),false,true);RAISE EXCEPTION 'order pay accepted as handoff';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'INVALID_CAPABILITY' THEN RAISE; END IF; END;
 BEGIN
  PERFORM public.read_stripe_handoff_internal(repeat('e',64),true,true);RAISE EXCEPTION 'handoff crossed environments';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'INVALID_CAPABILITY' THEN RAISE; END IF; END;
 response:=public.read_stripe_handoff_internal(repeat('e',64),false,true);
 PERFORM assert_true(response ? 'source','single exchange authorizes the server to resume the original attempt');
 PERFORM public.attach_stripe_handoff_internal(oid,command,encode(extensions.digest(repeat('e',64),'sha256'),'hex'),false);
 BEGIN
  PERFORM public.read_stripe_handoff_internal(repeat('e',64),false,true);RAISE EXCEPTION 'handoff creation replay renewed consumed write scope';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'INVALID_CAPABILITY' THEN RAISE; END IF; END;
 PERFORM assert_eq(public.read_stripe_handoff_internal(repeat('e',64),false,false)#>'{payment,allowedActions}','["refresh"]'::jsonb,'consumed handoff may observe but cannot dispatch again');
 claim:=public.claim_stripe_checkout_internal(repeat('1',64),false);
 PERFORM assert_eq(claim->>'disposition','dispatch','pay capability claims durable attempt');
 PERFORM assert_eq(public.claim_stripe_checkout_internal(repeat('1',64),false)->>'disposition','busy','parallel tab cannot dispatch');
 BEGIN
  PERFORM public.claim_stripe_checkout_internal(repeat('2',64),false);RAISE EXCEPTION 'return handle obtained checkout';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'INVALID_CAPABILITY' THEN RAISE; END IF; END;
 response:=public.commit_stripe_checkout_session_internal(attempt.id,(claim->>'lease')::uuid,'cs_test_cardOrder',
  'https://checkout.stripe.com/c/pay/cs_test_cardOrder',extract(epoch FROM attempt.reservation_expires_at)::bigint);
 PERFORM assert_true((response->>'committed')::boolean,'provider Session receipt committed');
 sync_claim:=public.claim_stripe_sync_internal('acct_createFixture',false,attempt.id,'cs_test_cardOrder',NULL);
 facts:=jsonb_build_object('observedAt',clock_timestamp(),'sessionId','cs_test_cardOrder','paymentIntentId','pi_cardOrder','sessionStatus','complete',
  'movements',jsonb_build_array(jsonb_build_object('providerId','pi_cardOrder','kind','payment','amountMinor',12345,'currency','CZK','occurredAt',extract(epoch FROM attempt.created_at)::bigint)), 'disputes','[]'::jsonb);
 event:=jsonb_build_object('id','evt_cardPaid','bodyHash',repeat('a',64),'accountId','acct_createFixture','livemode',false,'type','checkout.session.completed','created',extract(epoch FROM now())::bigint);
 BEGIN
  PERFORM public.ingest_stripe_payment_internal(attempt.id,(sync_claim->>'lease')::uuid,event,facts);
  RAISE EXCEPTION 'email fault was swallowed';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'STRIPE_PAID_TRANSITION_FAILED' THEN RAISE; END IF; END;
 PERFORM assert_eq((SELECT count(*) FROM eshop.stripe_payment_movements WHERE attempt_id=attempt.id),0::bigint,'failed email effect rolls back money');
 PERFORM assert_eq((SELECT count(*) FROM eshop.stripe_event_inbox WHERE connection_id=conn),0::bigint,'failed effect cannot acknowledge webhook');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'ordered','failed effect rolls back domain transition');
 ALTER TABLE public.email_messages DROP CONSTRAINT stripe_test_email_fault;
 response:=public.ingest_stripe_payment_internal(attempt.id,(sync_claim->>'lease')::uuid,event,facts);
 PERFORM assert_true((response#>>'{data,committed}')::boolean,'atomic provider receipt');
 PERFORM assert_eq(response#>>'{data,payment,received}','123.45','wire projection keeps the exact supported-currency decimal contract');
 PERFORM assert_eq(response#>>'{data,payment,returned}','0.00','zero refund is also a normalized decimal string');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'paid','canonical paid transition');
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=pi),123.45::numeric,'gross amount exact');
 SELECT count(*) INTO count_before FROM public.email_messages WHERE order_id=oid AND message_kind='order_tickets';
 PERFORM assert_true(count_before>0,'paid transition creates existing ticket email intent');
 PERFORM public.ingest_stripe_payment_internal(attempt.id,NULL,event,facts);
 PERFORM assert_eq((SELECT count(*) FROM public.email_messages WHERE order_id=oid AND message_kind='order_tickets'),count_before,'webhook replay cannot enqueue duplicate tickets');
 PERFORM assert_eq((SELECT count(*) FROM eshop.stripe_payment_movements WHERE attempt_id=attempt.id),1::bigint,'webhook replay cannot duplicate money');
 -- A page with pending/failed refunds can advance its raw provider cursor
 -- without contributing a successful refund movement. Admission waits until
 -- the durable pass is complete, including across a worker failure.
 sync_claim:=public.claim_stripe_sync_internal('acct_createFixture',false,attempt.id,NULL,'pi_cardOrder');
 event:=event||jsonb_build_object('id','evt_refundPageOne','type','festapp.reconcile');
 response:=public.ingest_stripe_payment_internal(attempt.id,(sync_claim->>'lease')::uuid,event,facts||jsonb_build_object('refundCursor','re_recoveryCursor','observedAt',clock_timestamp()));
 PERFORM assert_eq(response#>>'{data,payment,status}','pending','incomplete provider pagination cannot look paid');
 PERFORM assert_eq(response#>>'{data,payment,admissionState}','pending','incomplete provider facts cannot authorize admission');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'paid','recovery preserves the paid domain history');
 UPDATE eshop.stripe_checkout_attempts SET next_reconcile_at=clock_timestamp()-interval '1 second' WHERE id=attempt.id;
 PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_recoverable_stripe_attempts_internal(false,10)) job WHERE job->>'attemptId'=attempt.id::text),'scheduler discovers a durable unfinished pass');
 sync_claim:=public.claim_stripe_sync_internal('acct_createFixture',false,attempt.id,NULL,'pi_cardOrder');
 PERFORM assert_eq(sync_claim#>>'{snapshot,refundCursor}','re_recoveryCursor','retry claim retains the committed provider cursor');
 PERFORM public.fail_stripe_reconciliation_internal(attempt.id,extensions.gen_random_uuid());
 PERFORM assert_true((SELECT lease_token=(sync_claim->>'lease')::uuid FROM eshop.stripe_checkout_attempts WHERE id=attempt.id),'stale worker cannot clear a newer lease');
 PERFORM public.fail_stripe_reconciliation_internal(attempt.id,(sync_claim->>'lease')::uuid);
 PERFORM assert_true((SELECT reconcile_failures=1 AND refund_cursor='re_recoveryCursor' AND next_reconcile_at>clock_timestamp() FROM eshop.stripe_checkout_attempts WHERE id=attempt.id),'failure backs off without losing progress');
 sync_claim:=public.claim_stripe_sync_internal('acct_createFixture',false,attempt.id,NULL,'pi_cardOrder');
 event:=event||jsonb_build_object('id','evt_refundPageTwo');
 response:=public.ingest_stripe_payment_internal(attempt.id,(sync_claim->>'lease')::uuid,event,facts||jsonb_build_object('observedAt',clock_timestamp()));
 PERFORM assert_eq(response#>>'{data,payment,admissionState}','valid','complete recovery restores verified admission');
 PERFORM assert_true((SELECT refund_cursor IS NULL AND reconcile_failures=0 FROM eshop.stripe_checkout_attempts WHERE id=attempt.id),'complete recovery clears cursor and failure count');
 sync_claim:=public.claim_stripe_sync_internal('acct_createFixture',false,attempt.id,NULL,'pi_cardOrder');
 facts:=facts||jsonb_build_object('observedAt',clock_timestamp(),'movements',facts->'movements'||jsonb_build_array(jsonb_build_object('providerId','re_cardPartial','kind','refund','amountMinor',2345,'currency','CZK','occurredAt',extract(epoch FROM now())::bigint)));
 event:=event||jsonb_build_object('id','evt_cardPartial','type','refund.updated');
 PERFORM public.ingest_stripe_payment_internal(attempt.id,(sync_claim->>'lease')::uuid,event,facts);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'paid','partial refund is not new debt');
 PERFORM assert_eq(public.stripe_order_payment_projection_internal(oid)->>'admissionState','valid','partial refund alone preserves group admission');
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=pi),23.45::numeric,'partial refund separate from gross');
 sync_claim:=public.claim_stripe_sync_internal('acct_createFixture',false,attempt.id,NULL,'pi_cardOrder');
 facts:=facts||jsonb_build_object('observedAt',clock_timestamp(),'disputes',jsonb_build_array(jsonb_build_object('providerId','dp_cardDispute','amountMinor',10000,'currency','CZK','status','needs_response')));
 event:=event||jsonb_build_object('id','evt_cardDispute','type','charge.dispute.created');
 PERFORM public.ingest_stripe_payment_internal(attempt.id,(sync_claim->>'lease')::uuid,event,facts);
 PERFORM assert_eq(public.stripe_order_payment_projection_internal(oid)->>'admissionState','hold','dispute hold is effective');
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=pi),23.45::numeric,'dispute is not a refund');
 sync_claim:=public.claim_stripe_sync_internal('acct_createFixture',false,attempt.id,NULL,'pi_cardOrder');
 facts:=jsonb_set(facts,'{disputes,0,status}','"won"')||jsonb_build_object('observedAt',clock_timestamp());
 event:=event||jsonb_build_object('id','evt_cardWon','type','charge.dispute.closed');
 PERFORM public.ingest_stripe_payment_internal(attempt.id,(sync_claim->>'lease')::uuid,event,facts);
 PERFORM assert_eq(public.stripe_order_payment_projection_internal(oid)->>'admissionState','valid','won dispute releases hold without resurrecting cancellations');
 sync_claim:=public.claim_stripe_sync_internal('acct_createFixture',false,attempt.id,NULL,'pi_cardOrder');
 facts:=facts||jsonb_build_object('observedAt',clock_timestamp(),'movements',facts->'movements'||jsonb_build_array(jsonb_build_object('providerId','re_cardRest','kind','refund','amountMinor',10000,'currency','CZK','occurredAt',extract(epoch FROM now())::bigint)));
 event:=event||jsonb_build_object('id','evt_cardFull','type','refund.updated');
 PERFORM public.ingest_stripe_payment_internal(attempt.id,(sync_claim->>'lease')::uuid,event,facts);
 PERFORM assert_eq(public.stripe_order_payment_projection_internal(oid)->>'status','refunded','full refund remains distinct from debt');
 PERFORM assert_eq((SELECT count(*) FROM public.get_order_tickets_internal(oid) WHERE state<>'storno'),0::bigint,'full refund cancels unused tickets');
 PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=oid),123.45::numeric,'refund preserves original sale amount');
 sync_claim:=public.claim_stripe_sync_internal('acct_createFixture',false,attempt.id,NULL,'pi_cardOrder');
 event:=event||jsonb_build_object('id','evt_cardFullRecovery','type','payment_intent.succeeded');
 PERFORM public.ingest_stripe_payment_internal(attempt.id,(sync_claim->>'lease')::uuid,event,
  facts||jsonb_build_object('observedAt',clock_timestamp()));
 PERFORM assert_eq(public.stripe_order_payment_projection_internal(oid)->>'status','refunded','a later provider observation never misclassifies completed refund as late payment');
 PERFORM assert_true(NOT EXISTS(SELECT 1 FROM eshop.stripe_admission_decisions WHERE attempt_id=attempt.id AND reason='late_payment'),'refund-induced cancellation is not evidence of late payment');
 PERFORM assert_eq((SELECT count(*) FROM eshop.stripe_admission_decisions WHERE attempt_id=attempt.id AND reason='full_refund'),1::bigint,'recovery preserves one full-refund decision');

 -- A paid fact after capacity release is money to resolve, never a new admission.
 payload:=jsonb_set(payload,'{stripePaymentSource,tokenHash}',to_jsonb(encode(extensions.digest(repeat('3',64),'sha256'),'hex')));
 payload:=jsonb_set(payload,'{stripePaymentSource,returnHash}',to_jsonb(encode(extensions.digest(repeat('4',64),'sha256'),'hex')));
 result:=public.create_ticket_order_client_sync_v1(payload,extensions.gen_random_uuid(),client);
 oid:=(result#>>'{data,order,id}')::bigint;
 SELECT * INTO STRICT attempt FROM eshop.stripe_checkout_attempts WHERE order_id=oid;
 UPDATE eshop.stripe_checkout_attempts SET created_at=clock_timestamp()-interval '1 hour',reservation_expires_at=clock_timestamp()-interval '30 minutes' WHERE id=attempt.id;
 PERFORM public.internal_storno_tickets_221(ARRAY(SELECT id FROM public.get_order_tickets_internal(oid)));
 UPDATE eshop.orders SET state='expired' WHERE id=oid;
 sync_claim:=public.claim_stripe_sync_internal('acct_createFixture',false,attempt.id,'cs_test_cardLate',NULL);
 facts:=jsonb_build_object('observedAt',clock_timestamp(),'sessionId','cs_test_cardLate','paymentIntentId','pi_cardLate','sessionStatus','complete',
  'movements',jsonb_build_array(jsonb_build_object('providerId','pi_cardLate','kind','payment','amountMinor',12345,'currency','CZK','occurredAt',extract(epoch FROM now())::bigint)),'disputes','[]'::jsonb);
 event:=event||jsonb_build_object('id','evt_cardLate','type','payment_intent.succeeded');
 BEGIN
  PERFORM public.ingest_stripe_payment_internal(attempt.id,NULL,event,facts);RAISE EXCEPTION 'null lease accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'STRIPE_SYNC_LEASE_INVALID' THEN RAISE; END IF; END;
 PERFORM public.ingest_stripe_payment_internal(attempt.id,(sync_claim->>'lease')::uuid,event,facts);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'expired','late money cannot resurrect released capacity');
 PERFORM assert_eq(public.stripe_order_payment_projection_internal(oid)->>'status','action_required','late money has explicit resolution state');
 PERFORM assert_eq((SELECT count(*) FROM eshop.stripe_payment_movements WHERE attempt_id=attempt.id),1::bigint,'late money is still recorded');
 PERFORM assert_eq(public.update_order_and_tickets_to_paid(oid)->>'code','409','legacy manual paid helper cannot reactivate Stripe');
 -- A price change rejects before an order/capability can commit.
 SELECT count(*) INTO count_before FROM eshop.orders WHERE form=f;
 result:=public.create_ticket_order_client_sync_v1(jsonb_set(payload,'{expected_payment_amount_minor}','1'),extensions.gen_random_uuid(),client);
 PERFORM assert_eq(result#>>'{data,errorCode}','STRIPE_PRICE_CHANGED','server guards the displayed quote');
 PERFORM assert_eq((SELECT count(*) FROM eshop.orders WHERE form=f),count_before,'price mismatch creates no order');
 result:=public.create_ticket_order_client_sync_v1(jsonb_set(payload,'{payment_method}','"bank"'),extensions.gen_random_uuid(),client);
 PERFORM assert_eq(result#>>'{data,message}','BANK_PAYMENT_NOT_CONFIGURED','Stripe-only cannot be bypassed with a bank payload');
 PERFORM assert_eq((SELECT count(*) FROM eshop.orders WHERE form=f),count_before,'disabled bank creates no order');
 -- Lost Session response: no synthetic Session or financial fact is needed
 -- to release an exhausted, overdue lookup. Later real money still survives.
 payload:=jsonb_set(payload,'{stripePaymentSource,tokenHash}',to_jsonb(encode(extensions.digest(repeat('5',64),'sha256'),'hex')));
 payload:=jsonb_set(payload,'{stripePaymentSource,returnHash}',to_jsonb(encode(extensions.digest(repeat('6',64),'sha256'),'hex')));
 result:=public.create_ticket_order_client_sync_v1(payload,extensions.gen_random_uuid(),client);
 oid:=(result#>>'{data,order,id}')::bigint;
 SELECT * INTO STRICT attempt FROM eshop.stripe_checkout_attempts WHERE order_id=oid;
 sync_claim:=public.claim_stripe_sync_internal('acct_createFixture',false,attempt.id,NULL,NULL);
 event:=event||jsonb_build_object('id','evt_absentSession','type','festapp.reconcile');
 facts:=jsonb_build_object('observedAt',clock_timestamp(),'sessionId',NULL,'paymentIntentId',NULL,'sessionStatus','expired','movements','[]'::jsonb,'disputes','[]'::jsonb,'noSessionVerified',true);
 BEGIN
  PERFORM public.ingest_stripe_payment_internal(attempt.id,(sync_claim->>'lease')::uuid,event,facts);RAISE EXCEPTION 'early absence expired capacity';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'STRIPE_FACT_IDENTITY_INVALID' THEN RAISE; END IF; END;
 UPDATE eshop.stripe_checkout_attempts SET created_at=clock_timestamp()-interval '1 hour',reservation_expires_at=clock_timestamp()-interval '29 minutes' WHERE id=attempt.id;
 PERFORM public.checkpoint_stripe_session_lookup_internal(attempt.id,(sync_claim->>'lease')::uuid,'cs_test_lookupCursor',NULL);
 sync_claim:=public.claim_stripe_sync_internal('acct_createFixture',false,attempt.id,NULL,NULL);
 PERFORM assert_eq(sync_claim#>>'{snapshot,sessionLookupCursor}','cs_test_lookupCursor','lost response lookup resumes its durable cursor');
 PERFORM public.ingest_stripe_payment_internal(attempt.id,(sync_claim->>'lease')::uuid,event,facts||jsonb_build_object('observedAt',clock_timestamp()));
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'expired','exhausted overdue lookup releases capacity');
 PERFORM assert_true((SELECT session_id IS NULL AND session_lookup_cursor IS NULL FROM eshop.stripe_checkout_attempts WHERE id=attempt.id),'absence creates no fake provider object');
 PERFORM assert_eq((SELECT count(*) FROM eshop.stripe_payment_movements WHERE attempt_id=attempt.id),0::bigint,'absence creates no economic movement');
 sync_claim:=public.claim_stripe_sync_internal('acct_createFixture',false,attempt.id,'cs_test_afterAbsence',NULL);
 facts:=jsonb_build_object('observedAt',clock_timestamp(),'sessionId','cs_test_afterAbsence','paymentIntentId','pi_afterAbsence','sessionStatus','complete',
  'movements',jsonb_build_array(jsonb_build_object('providerId','pi_afterAbsence','kind','payment','amountMinor',12345,'currency','CZK','occurredAt',extract(epoch FROM clock_timestamp())::bigint)),'disputes','[]'::jsonb);
 PERFORM public.ingest_stripe_payment_internal(attempt.id,(sync_claim->>'lease')::uuid,event||jsonb_build_object('id','evt_afterAbsence'),facts);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'expired','a later real Session never resurrects released capacity');
 PERFORM assert_eq((SELECT count(*) FROM eshop.stripe_payment_movements WHERE attempt_id=attempt.id),1::bigint,'later real money remains recoverable after an absence observation');
 -- Historical bank/manual facts must not cause actual provider money to be
 -- dropped or be mistaken for a full card refund.
 payload:=jsonb_set(payload,'{stripePaymentSource,tokenHash}',to_jsonb(encode(extensions.gen_random_bytes(32),'hex')));
 payload:=jsonb_set(payload,'{stripePaymentSource,returnHash}',to_jsonb(encode(extensions.gen_random_bytes(32),'hex')));
 result:=public.create_ticket_order_client_sync_v1(payload,extensions.gen_random_uuid(),client);
 PERFORM assert_eq(result#>>'{data,code}','200','mixed-history fixture order created');oid:=(result#>>'{data,order,id}')::bigint;
 SELECT * INTO STRICT attempt FROM eshop.stripe_checkout_attempts WHERE order_id=oid;
 INSERT INTO eshop.bank_accounts(title,type,supported_currencies) VALUES('Historical cash','CASH',ARRAY['CZK']) RETURNING id INTO legacy_bank;
 INSERT INTO eshop.transactions(bank_account_id,payment_info,amount,currency,date,transaction_type)
 VALUES(legacy_bank,attempt.payment_info_id,25,'CZK',now(),'manual'),(legacy_bank,attempt.payment_info_id,-123.45,'CZK',now(),'return');
 sync_claim:=public.claim_stripe_sync_internal('acct_createFixture',false,attempt.id,'cs_test_mixedHistory',NULL);
 facts:=jsonb_build_object('observedAt',clock_timestamp(),'sessionId','cs_test_mixedHistory','paymentIntentId','pi_mixedHistory','sessionStatus','complete',
  'movements',jsonb_build_array(jsonb_build_object('providerId','pi_mixedHistory','kind','payment','amountMinor',12345,'currency','CZK','occurredAt',extract(epoch FROM attempt.created_at)::bigint)),'disputes','[]'::jsonb);
 response:=public.ingest_stripe_payment_internal(attempt.id,(sync_claim->>'lease')::uuid,event||jsonb_build_object('id','evt_mixedHistory'),facts);
 PERFORM assert_true((response#>>'{data,committed}')::boolean,'actual provider money commits despite conflicting historical manual facts');
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=attempt.payment_info_id),148.45::numeric,'manual and provider gross are both preserved');
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=attempt.payment_info_id),123.45::numeric,'historical bank return remains a separate fact');
 PERFORM assert_eq(public.stripe_order_payment_projection_internal(oid)->>'status','action_required','manual return is not a full card refund');
 PERFORM assert_true((SELECT state<>'storno' FROM eshop.orders WHERE id=oid),'only actual full card refund cancels this admission group');
 UPDATE eshop.stripe_connections SET paused=true WHERE id=conn;
 result:=public.create_ticket_order_client_sync_v1(payload,extensions.gen_random_uuid(),client);
 PERFORM assert_true(result#>>'{data,code}'<>'200','submit rechecks pause under receiver lock');
 UPDATE eshop.products SET price=0 WHERE id=p;
 result:=public.create_ticket_order_client_sync_v1(payload,extensions.gen_random_uuid(),client);
 PERFORM assert_eq(result#>>'{data,code}','200','free order needs no bank or Stripe account');
 oid:=(result#>>'{data,order,id}')::bigint;
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'paid','free order completes through canonical transition');
 PERFORM assert_eq((SELECT count(*) FROM eshop.stripe_checkout_attempts WHERE order_id=oid),0::bigint,'free order never creates Checkout');

 -- Changing the recipient switches future orders but cannot rewrite any
 -- dispatched, paid, refunded or expired attempt's economic identity.
 SELECT jsonb_agg(jsonb_build_array(id,connection_id,amount_minor,currency,idempotency_key,session_id,payment_intent_id) ORDER BY id)
  INTO original_attempts FROM eshop.stripe_checkout_attempts WHERE unit_id=u;
 PERFORM public.create_user_for_test('stripe_replace_manager','stripe-replace-manager@example.test');manager:=get_user_id('stripe_replace_manager');
 UPDATE public.user_info SET organization=org WHERE id=manager;
 INSERT INTO public.unit_users(unit,"user",is_manager) VALUES(u,manager,true);
 PERFORM set_config('request.jwt.claim.sub',manager::text,true);
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 flow:=public.begin_stripe_connection_flow(u,false);
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 flow:=public.claim_stripe_connection_flow_internal(flow->>'state',manager,false);
 PERFORM set_config('request.jwt.claim.sub','',true);
 result:=public.complete_stripe_connection_flow_internal((flow->>'flowId')::uuid,(flow->>'lease')::uuid,
  jsonb_build_object('accountId','acct_createReplacement','modelVerified',true,'ready',true,'chargesEnabled',true,'cardPaymentsActive',true));
 PERFORM assert_eq((SELECT data#>>'{payments,stripeConnectionId}' FROM public.forms WHERE id=f),result->>'connectionId','future orders use the verified replacement');
 PERFORM assert_eq((SELECT jsonb_agg(jsonb_build_array(id,connection_id,amount_minor,currency,idempotency_key,session_id,payment_intent_id) ORDER BY id)
  FROM eshop.stripe_checkout_attempts WHERE unit_id=u),original_attempts,'replacement preserves every existing attempt identity');

 -- Expired bearer source retention cannot disable reconciliation of old money.
 UPDATE eshop.stripe_payment_link_sources SET expires_at=clock_timestamp()-interval '1 second'
  WHERE token_hash IN (SELECT token_hash FROM eshop.stripe_capabilities WHERE order_id IN (SELECT order_id FROM eshop.stripe_checkout_attempts WHERE unit_id=u));
 PERFORM assert_true(public.purge_expired_stripe_sources_internal(100)>0,'expired encrypted sources are purged in a bounded batch');
 SELECT * INTO STRICT attempt FROM eshop.stripe_checkout_attempts WHERE unit_id=u AND session_id IS NOT NULL ORDER BY created_at LIMIT 1;
 sync_claim:=public.claim_stripe_sync_internal('acct_createFixture',false,attempt.id,attempt.session_id,NULL);
 PERFORM assert_eq(sync_claim->>'disposition','dispatch','history sync works after source deletion and recipient replacement');
 PERFORM assert_true(sync_claim->'source'='null'::jsonb,'history sync does not fabricate a new pay source');
 PERFORM assert_eq(public.get_stripe_order_pay_source_internal(attempt.order_id,command)#>>'{payment,method}','stripe','delayed confirmation uses current safe projection without expired bearer');
END $$;
