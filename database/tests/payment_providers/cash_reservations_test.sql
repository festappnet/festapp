-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
DO $$
DECLARE x jsonb:=pg_temp.payment_fixture(); f bigint:=(x->>'form')::bigint; result jsonb; oid bigint; pi eshop.payment_info;
 payload jsonb; command uuid:=gen_random_uuid(); session uuid:=gen_random_uuid(); original_deadline timestamptz;
BEGIN
 -- A timed snapshot retains its absolute deadline after changing the event policy.
 SELECT deadline INTO original_deadline FROM eshop.payment_info WHERE id=(x->>'payment')::bigint;
 UPDATE public.occasions SET features='[{"code":"form","is_enabled":true,"deadline_duration_seconds":100}]' WHERE id=(x->>'occasion')::bigint;
 PERFORM pg_temp.payment_edit(x,1100);
 PERFORM assert_eq((SELECT deadline FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),original_deadline,'new timed snapshot retains absolute deadline');
 UPDATE public.forms SET data='{"payments":{"bankEnabled":false,"cashEnabled":true,"cashInstructions":"Uhraďte u vstupu.","providerConnections":{}},"payment_deadline":{"mode":"none"}}',bank_account=NULL WHERE id=f;
 DELETE FROM eshop.unit_bank_accounts WHERE bank_account=(x->>'bank')::bigint;
 PERFORM public.validate_form_payment_configuration_internal(f);
 PERFORM assert_eq(public.form_payment_availability_internal(f)->'available','["cash"]'::jsonb,'cash without a bank');
 payload:=jsonb_build_object('form',(SELECT key FROM public.forms WHERE id=f),'email','reservation@example.invalid',
  'payment_method','cash','client_capabilities','["cash_reservations","no_payment_deadline"]'::jsonb,
  'ticket',jsonb_build_array(jsonb_build_object('fields',jsonb_build_array(jsonb_build_object('product_type',x->'product')))));
 SET LOCAL ROLE authenticated;
 result:=public.create_ticket_order_client_sync_v1(payload,command,session);
 RESET ROLE;
 PERFORM assert_eq(result->>'status','applied','cash checkout: '||result::text);
 oid:=(result#>>'{data,order,id}')::bigint;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=(SELECT payment_info FROM eshop.orders WHERE id=oid);
 PERFORM assert_eq(pi.payment_method,'cash','snapshot method');
 PERFORM assert_true(pi.deadline IS NULL AND pi.deposit_deadline IS NULL AND pi.bank_account IS NULL AND pi.variable_symbol IS NULL,'cash has no bank instructions or deadline');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'ordered','reservation is not paid');
 PERFORM assert_eq(public.customer_order_payment_internal(oid)->>'method','cash','public projection retains cash identity');
 PERFORM assert_true(public.customer_order_payment_internal(oid)->'qrPayment'='null'::jsonb,'cash has no payment QR');
 PERFORM public.insert_manual_transaction_internal_v1(250.50,'CZK',(SELECT unit FROM public.occasions WHERE id=(x->>'occasion')::bigint),NULL,now(),'cash',pi.id);
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=pi.id),250.50::numeric,'exact partial cash');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'ordered','partial remains unpaid');
 PERFORM public.insert_manual_transaction_internal_v1(749.50,'CZK',(SELECT unit FROM public.occasions WHERE id=(x->>'occasion')::bigint),NULL,now(),'balance',pi.id);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'paid','full actual cash promotes through ledger');
 BEGIN
  PERFORM public.check_payment_client_capabilities_internal(pi.data->'payment_policy','cash','[]');
  RAISE EXCEPTION 'old client accepted';
 EXCEPTION WHEN raise_exception THEN
  PERFORM assert_true(SQLERRM::jsonb->>'errorCode'='PAYMENT_CLIENT_UPDATE_REQUIRED','old client safely rejected');
 END;
END $$;
