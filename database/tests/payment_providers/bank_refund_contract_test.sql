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

-- Read-only QR availability is independent of bank refund mutation readiness.
DO $$
DECLARE x jsonb:=pg_temp.refund_fixture(); context jsonb; bank jsonb; result jsonb;
 before_totals jsonb; before_requests bigint; before_transactions bigint;
 input jsonb;
BEGIN
 DELETE FROM eshop.payment_reference_reservations WHERE namespace_id=x->>'namespace';
 DELETE FROM eshop.payment_reference_scopes WHERE organization_id=(x->>'organization')::bigint;
 DELETE FROM eshop.payment_reference_accounts WHERE bank_account_id=(x->>'bank')::bigint;
 DELETE FROM eshop.payment_reference_namespaces WHERE id=x->>'namespace';
 DELETE FROM eshop.bank_account_users WHERE bank_account=(x->>'bank')::bigint AND "user"=(x->>'actor')::uuid;
 DELETE FROM eshop.bank_sync_connections WHERE id=(x->>'connection')::bigint;
 SELECT to_jsonb(t) INTO before_totals FROM public.payment_financial_totals_internal((x->>'payment')::bigint) t;
 SELECT count(*) INTO before_requests FROM eshop.refund_requests;
 SELECT count(*) INTO before_transactions FROM eshop.transactions;
 input:=jsonb_build_object('orderId',(x->>'order')::bigint,'currency','CZK','amount','200.00',
  'recipientIban','CZ6508000000192000145399','recipientName','Jana Nováková');
 SET LOCAL ROLE authenticated;
 context:=public.get_payment_operation_context((x->>'order')::bigint);
 result:=public.get_bank_refund_instructions(input);
 -- A repeat is another read, with no durable intent or reservation.
 PERFORM assert_true(result=public.get_bank_refund_instructions(input),'Identical QR inputs are repeatable reads');
 RESET ROLE;
 SELECT value INTO bank FROM jsonb_array_elements(context#>'{context,methods}') WHERE value->>'id'='bank';
 PERFORM assert_true(bank->'instructions'='true'::jsonb,'QR needs no allocator, sync connection or bank-admin role');
 PERFORM assert_true(bank->'refund'='false'::jsonb,'Read-only QR never grants bank refund write permission');
 PERFORM assert_eq(result#>>'{instructions,reference}',x->>'variableSymbol','Original VS is retained');
 PERFORM assert_eq(result#>>'{instructions,recipientIban}','CZ6508000000192000145399','Recipient is preserved');
 PERFORM assert_true((SELECT count(*)=before_requests FROM eshop.refund_requests),'No refund request or reservation');
 PERFORM assert_true((SELECT count(*)=before_transactions FROM eshop.transactions),'No transaction created');
 PERFORM assert_true((SELECT to_jsonb(t)=before_totals FROM public.payment_financial_totals_internal((x->>'payment')::bigint) t),'Financial totals unchanged');
 BEGIN
  PERFORM public.get_bank_refund_instructions(input||'{"amount":"1000.01"}'::jsonb);
  RAISE EXCEPTION 'Expected amount rejection';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'REFUND_AVAILABLE_EXCEEDED' THEN RAISE; END IF;
 END;
 -- An unrelated reader cannot see or render another occasion's instructions.
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 BEGIN
  PERFORM public.get_bank_refund_instructions(input);
  RAISE EXCEPTION 'Expected authorization rejection';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END $$;
