-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
CREATE FUNCTION public.policy_observed_gateway(p_operation text,p_args jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 IF p_operation='totals' AND current_setting('festapp.test.observed_refund',true)='yes' THEN RETURN '{"received":1000,"returned":100,"held":0,"invalid":false}';
 ELSIF p_operation='totals' THEN RETURN '{"received":1000,"returned":0,"held":0,"invalid":false}';
 ELSIF p_operation='operation_capabilities' THEN RETURN '{"id":"orchard","record":false,"refund":true,"verification":"verified_provider_observation"}';
 ELSIF p_operation='refund_binding' THEN RETURN '{"original":"verified-fixture","currency":"CZK"}';
 ELSIF p_operation='movements' AND current_setting('festapp.test.observed_refund',true)='yes' THEN RETURN '[{"sourceId":"orchard:payment-1","kind":"payment","amount_minor":100000,"currency":"CZK","occurred_at":"2026-11-12T10:00:00Z"},{"sourceId":"orchard:refund-observed","kind":"refund","amount_minor":10000,"currency":"CZK","occurred_at":"2026-11-12T11:00:00Z"}]';
 ELSIF p_operation='movements' THEN RETURN '[{"sourceId":"orchard:payment-1","kind":"payment","amount_minor":100000,"currency":"CZK","occurred_at":"2026-11-12T10:00:00Z"}]';
 END IF;
 RAISE EXCEPTION 'Unexpected connector operation';
END $$;
REVOKE ALL ON FUNCTION public.policy_observed_gateway(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO eshop.payment_providers(provider_key,handler,source_field,hosted_checkout,verification,refund_write_enabled,refund_observation_supported)
VALUES('orchard','public.policy_observed_gateway(text,jsonb)'::regprocedure,'orchardSource',true,'verified_provider_observation',true,true);
DO $$
DECLARE x jsonb:=pg_temp.payment_fixture(); c jsonb; payload jsonb; response jsonb; request_id uuid:=gen_random_uuid(); cash_account bigint; historical_cash bigint;
BEGIN
 UPDATE eshop.payment_info SET payment_method='orchard',bank_account=NULL,variable_symbol=NULL,creditor_reference=NULL WHERE id=(x->>'payment')::bigint;
 payload:=jsonb_build_object('operation','prepare_refund','orderId',x->'order','method','orchard','amount','100');
 SET LOCAL ROLE authenticated;
 c:=public.get_payment_operation_context((x->>'order')::bigint);
 response:=public.get_transactions_for_order((x->>'order')::bigint);
 RESET ROLE;
 PERFORM assert_eq(jsonb_array_length(c#>'{context,methods}'),1,'gateway has only its stored connector');
 PERFORM assert_eq(c#>>'{context,methods,0,reason}','unsupported_operation','technical support distinct from readiness');
 PERFORM assert_true((c#>>'{context,methods,0,refundObservationSupported}')::boolean,'observation remains supported');
 PERFORM assert_false((c#>>'{context,methods,0,refund}')::boolean,'observation is not write permission');
 PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(response->'transactions') m WHERE m->>'sourceId'='orchard:payment-1' AND m->>'source'='provider' AND (m->>'amount')::numeric=1000),'provider facts visible through order finance');
 PERFORM assert_false(response->'actions' ? 'historyAccounts','gateway has no statement discovery');
 PERFORM assert_true(response#>'{actions,pairingAccountId}'='null'::jsonb,'gateway has no bank pairing');
 SET LOCAL ROLE authenticated;
 BEGIN PERFORM public.preview_payment_operation(payload); RAISE EXCEPTION 'unsupported preview accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_REFUND_UNAVAILABLE' THEN RAISE; END IF; END;
 BEGIN PERFORM public.command_payment_operation(payload,request_id); RAISE EXCEPTION 'unsupported write accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_REFUND_UNAVAILABLE' THEN RAISE; END IF; END;
 BEGIN PERFORM public.command_payment_operation(payload||'{"method":"cash"}',gen_random_uuid()); RAISE EXCEPTION 'gateway cash fallback accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_SOURCE_MISMATCH' THEN RAISE; END IF; END;
 BEGIN PERFORM public.command_payment_operation(payload||'{"operation":"correct_record","method":"cash","reason":"spoof"}',gen_random_uuid()); RAISE EXCEPTION 'gateway correction accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_SOURCE_MISMATCH' THEN RAISE; END IF; END;
 RESET ROLE;
 PERFORM assert_eq((SELECT count(*) FROM eshop.refund_requests WHERE order_id=(x->>'order')::bigint),0::bigint,'unsupported preview/command reserve no money');
 -- Existing gateway history cannot be rewritten through the released cash RPC.
 INSERT INTO eshop.bank_accounts(title,type,supported_currencies) VALUES('Historická hotovost','CASH',ARRAY['CZK']) RETURNING id INTO cash_account;
 INSERT INTO eshop.unit_bank_accounts(unit,bank_account) SELECT unit,cash_account FROM public.occasions WHERE id=(x->>'occasion')::bigint;
 INSERT INTO eshop.transactions(bank_account_id,payment_info,amount,currency,date,transaction_type,ingest_source)
 VALUES(cash_account,(x->>'payment')::bigint,1,'CZK',now(),'manual','manual') RETURNING id INTO historical_cash;
 SET LOCAL ROLE authenticated;
 BEGIN PERFORM public.delete_manual_transaction_ws(historical_cash,(x->>'payment')::bigint); RAISE EXCEPTION 'legacy gateway cash correction accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_SOURCE_MISMATCH' THEN RAISE; END IF; END;
 RESET ROLE;
 PERFORM assert_true(EXISTS(SELECT 1 FROM eshop.transactions WHERE id=historical_cash),'rejected legacy correction preserves the historical fact');
 DELETE FROM eshop.transactions WHERE id=historical_cash; -- fixture-only cleanup before full-only amount checks
 PERFORM set_config('festapp.test.observed_refund','yes',true);
 SET LOCAL ROLE authenticated;
 response:=public.get_transactions_for_order((x->>'order')::bigint);
 RESET ROLE;
 PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(response->'transactions') t WHERE t->>'sourceId'='orchard:refund-observed' AND (t->>'amount')::numeric=-100),'observation-only connector exposes an actual external refund without write capability');
 PERFORM assert_eq((SELECT refunded FROM public.payment_financial_totals_internal((x->>'payment')::bigint)),100::numeric,'external observed refund enters original totals');
 PERFORM assert_eq((SELECT count(*) FROM eshop.refund_requests WHERE order_id=(x->>'order')::bigint),0::bigint,'observation does not fabricate a local request');
 PERFORM set_config('festapp.test.observed_refund','no',true);
 UPDATE eshop.payment_providers SET refund_write_supported=true,refund_write_enabled=false WHERE provider_key='orchard';
 c:=public.payment_method_context_internal((x->>'order')::bigint);
 PERFORM assert_eq(c#>>'{methods,0,reason}','connector_write_disabled','supported but unavailable has a distinct reason');
 UPDATE eshop.payment_providers SET refund_write_enabled=true WHERE provider_key='orchard';
 SET LOCAL ROLE authenticated;
 BEGIN PERFORM public.command_payment_operation(payload,request_id); RAISE EXCEPTION 'partial write accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_PARTIAL_REFUND_UNSUPPORTED' THEN RAISE; END IF; END;
 response:=public.command_payment_operation(payload||'{"amount":"1000"}',request_id);
 RESET ROLE;
 PERFORM assert_eq(response#>>'{data,nextAction}','processing','full-only connector can create a full refund intent');
 PERFORM assert_eq((SELECT amount FROM eshop.refund_requests WHERE id=request_id),1000::numeric,'amount is never silently changed');
 PERFORM assert_true(response#>'{data,request,instructions}' IS NULL OR response#>'{data,request,instructions}'='null'::jsonb,'gateway intent has no bank payload');
END $$;
