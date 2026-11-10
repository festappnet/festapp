-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
-- test-setup: database/tests/helpers/refund_operation_fixture.sql
DO $$
DECLARE x jsonb:=pg_temp.refund_fixture(); payload jsonb; result jsonb; replay jsonb; req uuid; tid bigint;
 c uuid:=gen_random_uuid(); original_vs bigint; original_rf text; count_before bigint;
BEGIN
 PERFORM assert_false(has_table_privilege('authenticated','eshop.refund_requests','INSERT'),'no direct request writer');
 PERFORM assert_false(has_table_privilege('authenticated','eshop.refund_settlements','INSERT'),'no direct settlement writer');
 PERFORM assert_false(has_function_privilege('authenticated','public.observe_bank_refund_internal(bigint)','EXECUTE'),'bank facts service boundary');
 PERFORM assert_false(has_function_privilege('authenticated','public.claim_payment_refund(uuid)','EXECUTE'),'no client dispatch claim');
 SELECT variable_symbol,creditor_reference INTO original_vs,original_rf FROM eshop.payment_info WHERE id=(x->>'payment')::bigint;
 payload:=jsonb_build_object('operation','prepare_refund','orderId',x->'order','method','cash','amount','300.25','receivedAt',now(),'note','Výdej');
 SET LOCAL ROLE authenticated;
 result:=public.command_payment_operation(payload,c);
 replay:=public.command_payment_operation(payload,c);
 RESET ROLE;
 PERFORM assert_eq(result->>'code','200','cash refund command commits');
 PERFORM assert_true((replay#>>'{mutation,replayed}')::boolean,'same payload receipt replay');
 PERFORM assert_eq(result#>>'{data,nextAction}','recorded','cash confirmed in transaction');
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),1000::numeric,'gross preserved');
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),300.25::numeric,'actual signed cash is return');
 PERFORM assert_eq(result#>>'{data,context,net}','699.75','net exact');
 req:=(result#>>'{data,request,id}')::uuid;
 tid:=(result#>>'{data,transactionId}')::bigint;
 PERFORM assert_eq((SELECT count(*) FROM eshop.refund_settlements WHERE request_id=req),1::bigint,'one settlement');
 BEGIN
  PERFORM public.command_payment_operation(payload||'{"amount":"301"}',c);
  RAISE EXCEPTION 'changed command accepted';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='changed command accepted' THEN RAISE; END IF; END;
 payload:=jsonb_build_object('operation','prepare_refund','orderId',x->'order','method','bank','amount','200',
  'recipientIban',public.canonical_payment_reference_account_internal('1234/2010'),'recipientName','Jan Novák');
 SET LOCAL ROLE authenticated;
 result:=public.command_payment_operation(payload,gen_random_uuid());
 RESET ROLE;
 PERFORM assert_eq(result#>>'{data,nextAction}','show_bank_instructions','bank only prepares');
 PERFORM assert_eq(result#>>'{data,context,net}','699.75','QR does not deduct');
 PERFORM assert_eq(result#>>'{data,context,pending}','200.00','pending reservation distinct');
 PERFORM assert_eq(result#>>'{data,request,instructions,reference}',original_vs::text,'original reference reused');
 req:=(result#>>'{data,request,id}')::uuid;
 BEGIN
  PERFORM public.command_payment_operation(payload||'{"method":"cash","amount":"500","receivedAt":"2026-11-10T12:00:00Z"}',gen_random_uuid());
  RAISE EXCEPTION 'reservation overspent';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'REFUND_AVAILABLE_EXCEEDED' THEN RAISE; END IF; END;
 BEGIN
  PERFORM public.insert_manual_transaction(-600,'CZK',(x->>'unit')::int,NULL,now()::text,NULL,(x->>'payment')::int);
  RAISE EXCEPTION 'legacy correction bypassed reservation';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_REFUND_RESERVATION_CONFLICT' THEN RAISE; END IF; END;
 result:=pg_temp.refund_bank_event(x,1,-20000);
 PERFORM assert_true((result#>>'{refund,matched}')::boolean,'verified BankSync debit settles');
 PERFORM assert_eq((SELECT status FROM eshop.refund_requests WHERE id=req),'succeeded','bank confirmation');
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),500.25::numeric,'both real refunds projected');
 PERFORM assert_eq((SELECT transaction_type FROM eshop.transactions WHERE id=(SELECT transaction_id FROM eshop.refund_settlements WHERE request_id=req)),'bank debit','raw bank type unchanged');
 replay:=pg_temp.refund_bank_event(x,1,-20000);
 PERFORM assert_eq(result,replay,'bank replay stable receipt');
 -- A second actual debit is a second fact even above intended amount.
 PERFORM pg_temp.refund_bank_event(x,2,-21000);
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),710.25::numeric,'second debit not hidden');
 PERFORM assert_eq((SELECT variable_symbol FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),original_vs,'no new VS');
 PERFORM assert_eq((SELECT creditor_reference FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),original_rf,'no new RF');
 -- Correction preserves immutable cash row and explicitly removes its projection.
 SET LOCAL ROLE authenticated;
 result:=public.command_payment_operation(jsonb_build_object('operation','correct_record','orderId',x->'order','requestId',c,'reason','Chybně zapsáno'),gen_random_uuid());
 RESET ROLE;
 PERFORM assert_eq((SELECT amount FROM eshop.transactions WHERE id=tid),-300.25::numeric,'cash row kept after audited void');
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),410::numeric,'void counted exactly once');
 -- An order reader without the actual bank role sees financial status only.
 UPDATE eshop.bank_account_users SET is_admin=false WHERE bank_account=(x->>'bank')::bigint AND "user"=(x->>'actor')::uuid;
 SET LOCAL ROLE authenticated;
 result:=public.get_payment_operation_context((x->>'order')::bigint);
 RESET ROLE;
 PERFORM assert_false(EXISTS(SELECT 1 FROM jsonb_array_elements(result#>'{context,requests}') r WHERE r->'instructions'<>'null'::jsonb),'no bank instruction PII for order-only reader');
 PERFORM assert_false(EXISTS(SELECT 1 FROM jsonb_array_elements(result#>'{context,requests}') r WHERE r->>'method'='bank' AND (r->'canReopen'='true'::jsonb OR r->'canCancel'='true'::jsonb)),'bank actions fail closed for order-only reader');
 DELETE FROM public.unit_users WHERE unit=(x->>'unit')::bigint AND "user"=(x->>'actor')::uuid;
 BEGIN
  PERFORM public.command_payment_operation(jsonb_build_object('operation','prepare_refund','orderId',x->'order','method','cash','amount','300.25','receivedAt',now(),'note','Výdej'),c);
  RAISE EXCEPTION 'revoked replay accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
