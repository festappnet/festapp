-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
-- Projection-only fixture: actual dispatch and receipt authorization are covered
-- by the payment operation suite. Original bank facts are inserted unmodified.
DO $$
DECLARE x jsonb; oid bigint; pid bigint; receipt bigint; debit bigint; correction bigint;
 used_ticket bigint; request uuid; totals record; payment jsonb; report jsonb; money jsonb;
 original_type text:='bank_debit'; cash bigint; cash_refund bigint;
BEGIN
 x:=pg_temp.payment_fixture(700);oid:=(x->>'order')::bigint;pid:=(x->>'payment')::bigint;
 receipt:=pg_temp.payment_pair(x,1000);
 UPDATE eshop.transactions SET date='2026-11-09 12:00:00' WHERE id=receipt;
 INSERT INTO eshop.tickets(occasion,state) VALUES((x->>'occasion')::bigint,'used') RETURNING id INTO used_ticket;
 INSERT INTO eshop.order_product_ticket("order",ticket) VALUES(oid,used_ticket);
 INSERT INTO eshop.refund_requests(order_id,payment_info,method,amount,currency,status,source_account)
 VALUES(oid,pid,'bank',300,'CZK','pending',(x->>'bank')::bigint) RETURNING id INTO request;
 SELECT * INTO totals FROM public.payment_financial_totals_internal(pid);
 PERFORM assert_eq(totals.net_received,1000::numeric,'pending instructions do not spend money');
 PERFORM assert_eq((public.customer_order_payment_internal(oid)->>'pending')::numeric,300::numeric,'public pending remains separate');
 BEGIN
  PERFORM public.apply_transaction_pairing(receipt,NULL,'test','system');
  RAISE EXCEPTION 'reserved receipt could be removed';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'PAYMENT_REFUND_RESERVATION_CONFLICT' THEN RAISE; END IF;
 END;
 INSERT INTO eshop.transactions(bank_account_id,payment_info,amount,currency,date,transaction_type,ingest_source)
 VALUES((x->>'bank')::bigint,pid,-300,'CZK','2026-11-10 12:00:00',original_type,'bank_sync') RETURNING id INTO debit;
 INSERT INTO eshop.refund_settlements(transaction_id,request_id) VALUES(debit,request);
 UPDATE eshop.refund_requests SET status='succeeded' WHERE id=request;
 PERFORM public.refresh_payment_info_totals_internal(pid);
 PERFORM public.reconcile_order_payment_internal_v1(oid,'refund_fact');
 SELECT * INTO totals FROM public.payment_financial_totals_internal(pid);
 PERFORM assert_eq(totals.gross_received,1000::numeric,'classified debit does not reduce gross');
 PERFORM assert_eq(totals.refunded,300::numeric,'bank settlement returns once');
 PERFORM assert_eq(totals.net_received,700::numeric,'net subtracts actual bank debit');
 PERFORM assert_eq((SELECT transaction_type FROM eshop.transactions WHERE id=debit),original_type,'raw bank type is immutable');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'paid'::text,'exact net deposit retains eligibility');
 BEGIN
  INSERT INTO eshop.refund_settlements(transaction_id,request_id) VALUES(debit,request);
  RAISE EXCEPTION 'duplicate settlement accepted';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 -- A historical signed manual correction remains a receipt adjustment.
 INSERT INTO eshop.transactions(bank_account_id,payment_info,amount,currency,date,transaction_type)
 VALUES((x->>'bank')::bigint,pid,-50,'CZK','2026-11-10 13:00:00','manual') RETURNING id INTO correction;
 PERFORM public.refresh_payment_info_totals_internal(pid);
 PERFORM public.reconcile_order_payment_internal_v1(oid,'refund_fact');
 SELECT * INTO totals FROM public.payment_financial_totals_internal(pid);
 PERFORM assert_eq(totals.gross_received,950::numeric,'negative legacy correction adjusts gross');
 PERFORM assert_eq(totals.refunded,300::numeric,'negative legacy correction is not a second refund');
 PERFORM assert_eq(totals.net_received,650::numeric,'net preserves signed correction');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'ordered'::text,'net below deposit removes eligibility');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=used_ticket),'used'::text,'refund never rewrites consumed admission');
 payment:=public.customer_order_payment_internal(oid);
 PERFORM assert_eq((payment->>'received')::numeric,950::numeric,'customer received is gross');
 PERFORM assert_eq((payment->>'returned')::numeric,300::numeric,'customer returned is confirmed');
 PERFORM assert_eq((payment->>'net')::numeric,650::numeric,'customer sees net');
 PERFORM assert_eq((payment->>'dueNow')::numeric,50::numeric,'customer deposit due uses net');
 PERFORM assert_eq((payment->>'totalOutstanding')::numeric,350::numeric,'customer total outstanding uses net');
 PERFORM assert_true(payment->'transactions' @> '[{"kind":"refund","amount":-300}]'::jsonb,'raw bank debit is a refund in timeline');
 PERFORM public.reserve_public_link_internal('occasion',(x->>'occasion')::bigint,x->>'link',true);
 report:=public.get_report_ws(x->>'link');
 PERFORM assert_eq(report->>'code','200'::text,'report resolves same facts');
 money:=report#>'{report,money_by_currency,0}';
 PERFORM assert_eq((money->>'received')::numeric,950::numeric,'report gross agrees');
 PERFORM assert_eq((money->>'returned')::numeric,300::numeric,'report returned agrees');
 PERFORM assert_eq((money->>'deposit_received_net')::numeric,650::numeric,'report deposit uses net');
 PERFORM assert_true(report#>'{report,timeline,payments}' @> '[{"day":"2026-11-10","received":"-50.00","returned":"300.00"}]'::jsonb
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(report#>'{report,timeline,payments}') d
   WHERE d->>'day'='2026-11-10' AND (d->>'received')::numeric=-50 AND (d->>'returned')::numeric=300),
  'daily graph distinguishes negative correction from refund');
 BEGIN
  PERFORM public.get_order_deletion_context_v1(oid);
  RAISE EXCEPTION 'refund preflight allowed deletion';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'ORDER_HAS_REFUND_HISTORY' THEN RAISE; END IF; END;
 BEGIN
  PERFORM public.apply_transaction_pairing(debit,NULL,'manual_unlink','system');
  RAISE EXCEPTION 'generic refund unlink accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'REFUND_SETTLEMENT_REQUIRES_EXPLICIT_CORRECTION' THEN RAISE; END IF; END;
 -- Void only changes projection, preserving the original cash row.
 INSERT INTO eshop.bank_accounts(title,type,supported_currencies) VALUES('Refund cash','CASH',ARRAY['CZK']) RETURNING id INTO cash;
 INSERT INTO eshop.transactions(bank_account_id,payment_info,amount,currency,date,transaction_type,ingest_source)
 VALUES(cash,pid,-100,'CZK',now(),'return','manual') RETURNING id INTO cash_refund;
 INSERT INTO eshop.refund_settlements(transaction_id,voided_at,void_reason) VALUES(cash_refund,now(),'Incorrect cash entry');
 PERFORM public.refresh_payment_info_totals_internal(pid);
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=pid),300::numeric,'void excludes the cash refund once');
 PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.transactions WHERE id=cash_refund),'void preserves original audit fact');
 UPDATE eshop.orders SET state='expired' WHERE id=oid;
 UPDATE eshop.payment_info SET deposit_amount=1 WHERE id=pid;
 PERFORM public.reconcile_order_payment_internal_v1(oid,'refund_fact');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'expired'::text,'refund does not revive expired admission even above deposit');
END $$;
