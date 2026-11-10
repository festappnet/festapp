-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
-- test-setup: database/tests/helpers/refund_operation_fixture.sql
DO $$
DECLARE x jsonb:=pg_temp.refund_fixture(); payload jsonb; r jsonb; first uuid; second uuid; original text:=x->>'variableSymbol';
 alias_id bigint; request_id uuid; refs bigint; before_count bigint;
BEGIN
 payload:=jsonb_build_object('operation','prepare_refund','orderId',x->'order','method','bank','amount','200',
  'recipientIban',public.canonical_payment_reference_account_internal('1234/2010'),'recipientName','Eva Nováková');
 SELECT count(*) INTO refs FROM eshop.payment_reference_reservations;
 SET LOCAL ROLE authenticated;
 r:=public.command_payment_operation(payload,gen_random_uuid());
 RESET ROLE;
 first:=(r#>>'{data,request,id}')::uuid;
 -- Invalid reference and currency stay truthful unpaired bank facts.
 r:=pg_temp.refund_bank_event(x,10,-20000,'9999999999');
 PERFORM assert_false((r#>>'{refund,matched}')::boolean,'wrong reference never chooses an order by amount');
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),0::numeric,'invalid facts do not change refund totals');
 PERFORM pg_temp.refund_bank_event(x,12,-20000);
 SET LOCAL ROLE authenticated;
 r:=public.command_payment_operation(payload||'{"amount":"100"}',gen_random_uuid());
 RESET ROLE;
 second:=(r#>>'{data,request,id}')::uuid;
 PERFORM assert_true(first<>second,'second partial request has distinct internal identity');
 PERFORM assert_eq(r#>>'{data,request,instructions,reference}',original,'partial refunds reuse original VS');
 PERFORM pg_temp.refund_bank_event(x,13,-10000);
 PERFORM assert_eq((SELECT status FROM eshop.refund_requests WHERE id=second),'succeeded','sole pending request settled');
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),300::numeric,'two real partial returns');
 SET LOCAL ROLE authenticated;
 r:=public.command_payment_operation(payload||'{"amount":"100"}',gen_random_uuid());
 request_id:=(r#>>'{data,request,id}')::uuid;
 PERFORM public.command_payment_operation(jsonb_build_object('operation','cancel_pending','orderId',x->'order','requestId',request_id,'transferNotSubmitted',true),gen_random_uuid());
 RESET ROLE;
 r:=pg_temp.refund_bank_event(x,14,-12000);
 PERFORM assert_true((r#>>'{refund,matched}')::boolean,'late debit after cancellation remains evidence');
 r:=pg_temp.refund_bank_event(x,11,-20000,NULL,'{"currency":"USD"}');
 PERFORM assert_false((r#>>'{refund,matched}')::boolean,'wrong currency is not a refund');
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),420::numeric,'actual deviation amount is not clipped');
 PERFORM assert_true((SELECT (result->>'deviation')::boolean FROM eshop.refund_requests WHERE id=request_id),'late differing debit flagged');
 PERFORM assert_eq((SELECT count(*) FROM eshop.payment_reference_reservations),refs,'refunds allocate no new reference');
END $$;
DO $$
DECLARE x jsonb:=pg_temp.refund_fixture(); payload jsonb; r jsonb; rf text; refs bigint; alias_id bigint; amount_before numeric;
BEGIN
 -- Synthetic EUR readiness evidence is local only; production proof remains off.
 UPDATE eshop.orders SET currency_code='EUR' WHERE id=(x->>'order')::bigint;
 UPDATE eshop.payment_info SET currency_code='EUR',creditor_reference=public.generate_creditor_reference(variable_symbol) WHERE id=(x->>'payment')::bigint RETURNING creditor_reference INTO rf;
 UPDATE eshop.transactions SET currency='EUR' WHERE payment_info=(x->>'payment')::bigint;
 payload:=jsonb_build_object('operation','prepare_refund','orderId',x->'order','method','bank','amount','50.25',
  'recipientIban','DE89370400440532013000','recipientName','Eva Nováková');
 BEGIN
  PERFORM public.command_payment_operation(payload,gen_random_uuid());
  RAISE EXCEPTION 'EUR without transmission proof accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_REFUND_UNAVAILABLE' THEN RAISE; END IF; END;
 UPDATE eshop.bank_sync_connections SET refund_rf_verified=true WHERE id=(x->>'connection')::bigint;
 -- Stored source alias retains the same physical namespace and reviewed connection.
 INSERT INTO eshop.bank_accounts(title,type,account_number,supported_currencies)
  SELECT 'Alias EUR','FIO',account_number,ARRAY['EUR'] FROM eshop.bank_accounts WHERE id=(x->>'bank')::bigint RETURNING id INTO alias_id;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) VALUES((x->>'unit')::bigint,alias_id);
 INSERT INTO eshop.bank_account_users(bank_account,"user",is_admin) VALUES(alias_id,(x->>'actor')::uuid,true);
 INSERT INTO eshop.bank_sync_account_aliases(bank_account_id,connection_id) VALUES(alias_id,(x->>'connection')::bigint);
 INSERT INTO eshop.payment_reference_accounts(bank_account_id,namespace_id,account_number_snapshot)
  SELECT alias_id,x->>'namespace',account_number FROM eshop.bank_accounts WHERE id=(x->>'bank')::bigint;
 UPDATE eshop.payment_info SET bank_account=alias_id WHERE id=(x->>'payment')::bigint;
 SELECT count(*) INTO refs FROM eshop.payment_reference_reservations;
 SET LOCAL ROLE authenticated;
 r:=public.command_payment_operation(payload,gen_random_uuid());
 RESET ROLE;
 PERFORM assert_eq(r#>>'{data,request,instructions,reference}',rf,'EUR uses stored original RF');
 r:=pg_temp.refund_bank_event(x,30,-5025,NULL,jsonb_build_object('currency','EUR','raw_vs',NULL,'payer_reference',rf,'counter_account','DE89370400440532013000'));
 PERFORM assert_true((r#>>'{refund,matched}')::boolean,'EUR original RF and source alias settle');
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),50.25::numeric,'exact EUR refund');
 PERFORM assert_eq((SELECT count(*) FROM eshop.payment_reference_reservations),refs,'EUR refund creates no reference');
END $$;
DO $$
DECLARE x jsonb:=pg_temp.refund_fixture(); r jsonb; payload jsonb;
BEGIN
 r:=pg_temp.refund_bank_event(x,40,-20000,NULL,'{"date":"2026-11-09T12:00:00Z"}');
 PERFORM assert_false((r#>>'{refund,matched}')::boolean,'prior fact is not mass classified without intent');
 payload:=jsonb_build_object('operation','prepare_refund','orderId',x->'order','method','bank','amount','200',
  'recipientIban',public.canonical_payment_reference_account_internal('1234/2010'),'recipientName','Eva Nováková');
 SET LOCAL ROLE authenticated;
 r:=public.command_payment_operation(payload,gen_random_uuid());
 RESET ROLE;
 PERFORM assert_eq(r#>>'{data,nextAction}','recorded','explicit preparation adopts an evidenced prior debit instead of issuing another QR');
 PERFORM assert_eq(r#>>'{data,request,status}','succeeded','prior real bank fact confirms request');
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),200::numeric,'prior actual debit once');
END $$;
