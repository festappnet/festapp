-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
-- test-setup: database/tests/helpers/refund_operation_fixture.sql
DO $$
DECLARE x jsonb:=pg_temp.refund_fixture(); un bigint:=(x->>'unit')::bigint; org bigint:=(x->>'organization')::bigint;
 input jsonb; preview jsonb; response jsonb; bank_req uuid:=gen_random_uuid(); cash_tx bigint; q jsonb; msg public.email_messages;
 recipient text:=public.canonical_payment_reference_account_internal('1234/2010'); payload jsonb; enabled_revision jsonb; sibling bigint;
BEGIN
 SET LOCAL ROLE authenticated;
 response:=public.command_payment_operation(jsonb_build_object('operation','prepare_refund','orderId',x->'order','method','bank','amount','100',
  'recipientIban',recipient,'recipientName','Jan Novák'),bank_req);
 RESET ROLE;
 input:=jsonb_build_object('organizationId',org,'unitId',un,'method','bank','mode','disabled');
 SET LOCAL ROLE authenticated;
 preview:=public.preview_payment_method_policy(input);
 PERFORM public.command_payment_method_policy(input,gen_random_uuid(),preview->>'confirmation');
 BEGIN PERFORM public.command_payment_operation(jsonb_build_object('operation','cancel_pending','orderId',x->'order','requestId',bank_req,'transferNotSubmitted',false),gen_random_uuid());
 RAISE EXCEPTION 'unsafe cancellation accepted'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'REFUND_CANCELLATION_UNSAFE' THEN RAISE; END IF; END;
 response:=public.command_payment_operation(jsonb_build_object('operation','cancel_pending','orderId',x->'order','requestId',bank_req,'transferNotSubmitted',true),gen_random_uuid());
 RESET ROLE;
 PERFORM assert_eq((SELECT status FROM eshop.refund_requests WHERE id=bank_req),'cancelled','truthful no-transfer cancel remains available after disable');
 -- Actual cash on a bank order remains a separate, policy-controlled method.
 cash_tx:=public.write_cash_movement_internal(50,'CZK',un,NULL,now(),'U vstupu',(x->>'payment')::bigint,'correction',NULL);
 input:=input||'{"method":"cash"}';
 SET LOCAL ROLE authenticated;
 preview:=public.preview_payment_method_policy(input);
 PERFORM public.command_payment_method_policy(input,gen_random_uuid(),preview->>'confirmation');
 BEGIN PERFORM public.command_payment_operation(jsonb_build_object('operation','record_payment','orderId',x->'order','method','cash','amount','50','receivedAt',now()),gen_random_uuid());
 RAISE EXCEPTION 'disabled cash receipt accepted'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_RECORD_UNAVAILABLE' THEN RAISE; END IF; END;
 payload:=jsonb_build_object('operation','correct_record','orderId',x->'order','method','cash','transactionId',cash_tx,'amount','-50','reason','Chybně zapsaná částka','receivedAt',now());
 response:=public.command_payment_operation(payload,gen_random_uuid());
 BEGIN PERFORM public.command_payment_operation(payload,gen_random_uuid()); RAISE EXCEPTION 'same cash reversed twice';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_CORRECTION_ALREADY_APPLIED' THEN RAISE; END IF; END;
 RESET ROLE;
 PERFORM assert_eq((SELECT amount FROM eshop.transactions WHERE id=cash_tx),50::numeric,'original cash fact retained');
 PERFORM assert_eq((SELECT count(*) FROM eshop.transaction_pairing_events WHERE transaction_snapshot_id=cash_tx AND method='exact_cash_correction'),1::bigint,'one audited precise correction');
 -- A different unpaid order has a real collection snapshot in the same queue.
 q:=pg_temp.payment_fixture();
 UPDATE eshop.payment_info SET deadline=now()+interval '1 day' WHERE id=(q->>'payment')::bigint;
 SELECT * INTO msg FROM public.email_messages WHERE order_id=(q->>'order')::bigint AND message_kind='order_confirmation' LIMIT 1;
 PERFORM assert_true(msg.id IS NOT NULL,'checkout enqueues through the existing queue');
 UPDATE public.email_messages SET data=data||jsonb_build_object('collectionAction',public.payment_collection_action_internal((q->>'order')::bigint)) WHERE id=msg.id RETURNING * INTO msg;
 enabled_revision:=msg.data#>'{collectionAction,policyRevision}';
 PERFORM assert_true(msg.data#>'{collectionAction,allowed}'='true'::jsonb,'fixture has a currently executable collection');
 input:=jsonb_build_object('organizationId',q->'organization','unitId',(SELECT unit FROM public.occasions WHERE id=(q->>'occasion')::bigint),'method','bank','mode','disabled');
 SET LOCAL ROLE authenticated;
 preview:=public.preview_payment_method_policy(input); PERFORM public.command_payment_method_policy(input,gen_random_uuid(),preview->>'confirmation');
 RESET ROLE;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM assert_false(public.email_intent_valid(msg),'queued collection blocked after disable');
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 input:=input||'{"mode":"enabled"}';
 SET LOCAL ROLE authenticated;
 preview:=public.preview_payment_method_policy(input); PERFORM public.command_payment_method_policy(input,gen_random_uuid(),preview->>'confirmation');
 RESET ROLE;
 PERFORM assert_true(public.payment_collection_action_internal((q->>'order')::bigint)->'policyRevision' IS DISTINCT FROM enabled_revision,'re-enable advances the action epoch');
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 PERFORM assert_false(public.email_intent_valid(msg),'re-enable cannot resurrect old queued instructions');
 PERFORM assert_eq((SELECT data FROM public.email_messages WHERE id=msg.id),msg.data,'immutable queue snapshot was not rewritten');
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
END $$;
