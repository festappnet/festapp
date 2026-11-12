-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
-- Current-main readonly QR remains available, but cannot bypass product/source policy.
DO $$
DECLARE x jsonb:=pg_temp.payment_fixture(); un bigint; input jsonb; result jsonb; policy_input jsonb; preview jsonb;
 before_requests bigint; before_movements bigint;
BEGIN
 SELECT unit INTO un FROM public.occasions WHERE id=(x->>'occasion')::bigint;
 PERFORM pg_temp.payment_pair(x,1000);
 input:=jsonb_build_object('orderId',x->'order','amount','100.00','currency','CZK','recipientIban','CZ6508000000192000145399','recipientName','Jana Nováková');
 SELECT count(*) INTO before_requests FROM eshop.refund_requests;
 SELECT count(*) INTO before_movements FROM eshop.transactions;
 SET LOCAL ROLE authenticated;
 result:=public.get_bank_refund_instructions(input);
 RESET ROLE;
 PERFORM assert_true(result#>'{instructions,allowed}'='true'::jsonb,'existing bank QR is still an authorized read');
 PERFORM assert_eq(result#>>'{instructions,purpose}','bank_refund_instruction','read has explicit purpose');
 PERFORM assert_eq(result#>>'{instructions,sourceOrderId}',x->>'order','read binds stored order');
 PERFORM assert_eq(result#>>'{instructions,sourceMethod}','bank','read binds bank source');
 policy_input:=jsonb_build_object('organizationId',x->'organization','unitId',un,'method','bank','mode','disabled');
 SET LOCAL ROLE authenticated;
 preview:=public.preview_payment_method_policy(policy_input);
 PERFORM public.command_payment_method_policy(policy_input,gen_random_uuid(),preview->>'confirmation');
 BEGIN
  PERFORM public.get_bank_refund_instructions(input); RAISE EXCEPTION 'disabled bank readonly QR accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_REFUND_UNAVAILABLE' THEN RAISE; END IF; END;
 policy_input:=policy_input||'{"mode":"enabled"}';preview:=public.preview_payment_method_policy(policy_input);
 PERFORM public.command_payment_method_policy(policy_input,gen_random_uuid(),preview->>'confirmation');
 RESET ROLE;
 UPDATE eshop.payment_info SET payment_method='cash',bank_account=NULL,variable_symbol=NULL,creditor_reference=NULL,deposit_amount=NULL WHERE id=(x->>'payment')::bigint;
 SET LOCAL ROLE authenticated;
 BEGIN
  PERFORM public.get_bank_refund_instructions(input); RAISE EXCEPTION 'cash source became a bank QR';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_REFUND_UNAVAILABLE' THEN RAISE; END IF; END;
 RESET ROLE;
 PERFORM assert_eq((SELECT count(*) FROM eshop.refund_requests),before_requests,'readonly instruction never reserves a refund');
 PERFORM assert_eq((SELECT count(*) FROM eshop.transactions),before_movements,'readonly instruction never writes money');
END $$;
