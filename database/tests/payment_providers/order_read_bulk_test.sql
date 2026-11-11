-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
-- test-setup: database/tests/helpers/refund_operation_fixture.sql
-- test-setup: database/tests/helpers/order_payment_context_reference.sql
-- An additional registered connector must keep working without a special bulk API.
CREATE FUNCTION public.test_order_read_gateway(p_operation text,p_args jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 IF p_operation='totals' THEN RETURN '{"received":1000.25,"returned":25.25,"held":100,"invalid":false}';
 ELSIF p_operation='operation_capabilities' THEN RETURN '{"id":"batch_gateway","record":false,"refund":true,"verification":"verified_provider_observation"}';
 END IF;
 RAISE EXCEPTION 'Unsupported test operation';
END $$;
REVOKE ALL ON FUNCTION public.test_order_read_gateway(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO eshop.payment_providers(provider_key,handler,source_field,hosted_checkout,verification,refund_write_enabled)
VALUES('batch_gateway','public.test_order_read_gateway(text,jsonb)'::regprocedure,'batchSource',true,'verified_provider_observation',true);
DO $$
DECLARE x jsonb:=pg_temp.refund_fixture(); y jsonb:=pg_temp.refund_fixture(); z jsonb:=pg_temp.refund_fixture();
 w jsonb:=pg_temp.payment_fixture(); ids bigint[]; row record; baseline jsonb; result jsonb; role_name text; signature text;
 request_id uuid:=gen_random_uuid(); null_payment_order bigint; sibling_order bigint; sibling_payment bigint;
BEGIN
 -- A bank reservation plus a confirmed cash refund exercise request history,
 -- instructions, decimal text and the difference between ledger and intent.
 PERFORM set_config('request.jwt.claim.sub',x->>'actor',true);
 result:=public.command_payment_operation(jsonb_build_object('operation','prepare_refund','orderId',x->'order','method','bank','amount','100.25',
  'recipientIban',public.canonical_payment_reference_account_internal('1234/2010'),'recipientName','Jan Novák'),request_id);
 result:=public.command_payment_operation(jsonb_build_object('operation','prepare_refund','orderId',x->'order','method','cash','amount','50.25',
  'receivedAt',now(),'note','Vrácení'),gen_random_uuid());
 -- Separate creation times: the production contract orders by created_at,
 -- with no ordering guarantee for two requests at the exact same timestamp.
 UPDATE eshop.refund_requests SET result='{"deviation":true}',created_at=now()-interval '1 second' WHERE id=request_id;
 -- Distinct stored scopes and unrelated ledger facts must never share decisions.
 UPDATE eshop.transactions SET currency='EUR',amount=-2000 WHERE payment_info=(y->>'payment')::bigint;
 UPDATE eshop.orders SET state='storno' WHERE id=(y->>'order')::bigint;
 INSERT INTO eshop.order_deletion_fences(order_id,command_id) VALUES((y->>'order')::bigint,gen_random_uuid());
 UPDATE eshop.payment_info SET payment_method='cash',bank_account=NULL,variable_symbol=NULL,creditor_reference=NULL
 WHERE id=(z->>'payment')::bigint;
 UPDATE eshop.payment_info SET payment_method='batch_gateway',bank_account=NULL,variable_symbol=NULL,creditor_reference=NULL
 WHERE id=(w->>'payment')::bigint;
 -- Same permission scope, different currency and financial facts.
 INSERT INTO eshop.payment_info(amount,currency_code,payment_method) VALUES(1000,'JPY','cash') RETURNING id INTO sibling_payment;
 INSERT INTO eshop.orders(occasion,form,price,state,currency_code,payment_info,order_symbol,order_sequence,data)
 SELECT occasion,form,1000,'ordered','JPY',sibling_payment,public.generate_order_symbol(),2,'{}'
 FROM eshop.orders WHERE id=(x->>'order')::bigint RETURNING id INTO sibling_order;
 INSERT INTO eshop.orders(occasion,form,state,order_symbol,order_sequence,data)
 SELECT occasion,form,'created',public.generate_order_symbol(),3,'{}' FROM eshop.orders WHERE id=(x->>'order')::bigint
 RETURNING id INTO null_payment_order;
 ids:=ARRAY[(x->>'order')::bigint,(y->>'order')::bigint,(z->>'order')::bigint,(w->>'order')::bigint,sibling_order,null_payment_order,-1,NULL,(x->>'order')::bigint];

 FOR row IN SELECT * FROM public.payment_method_contexts_internal(ids) LOOP
  baseline:=pg_temp.order_payment_context_reference(row.order_id);
  PERFORM assert_eq(row.context,baseline,'complete bulk/scalar parity: mixed scopes, ledger, methods and requests');
 END LOOP;
 PERFORM assert_eq((SELECT count(*) FROM public.payment_method_contexts_internal(ids)),5::bigint,'one context per distinct order with a payment');
 PERFORM assert_true(public.payment_method_context_internal(null_payment_order) IS NULL,'missing payment remains null');
 PERFORM assert_eq((SELECT count(*) FROM public.payment_method_contexts_internal('{}')),0::bigint,'empty selection');
 PERFORM assert_eq((SELECT count(*) FROM public.payment_method_contexts_internal(NULL)),0::bigint,'null selection');
 SELECT context INTO result FROM public.payment_method_contexts_internal(ids) WHERE order_id=(x->>'order')::bigint;
 PERFORM assert_eq(result->>'pending','100.25','bank reservation preserved');
 PERFORM assert_eq(result->>'refunded','50.25','actual cash refund preserved');
 PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(result->'requests') req WHERE req->>'instructions' IS NOT NULL),'authorized original bank instructions preserved');
 SELECT context INTO result FROM public.payment_method_contexts_internal(ids) WHERE order_id=(w->>'order')::bigint;
 PERFORM assert_eq(result->>'net','975.00','connector facts preserve exact decimals');
 PERFORM assert_eq(result->>'available','875.00','connector hold preserved');
 PERFORM assert_false(EXISTS(SELECT 1 FROM jsonb_array_elements(result->'methods') method WHERE method->'refund'='true'::jsonb),'foreign unit manager permission never leaks to provider');
 SELECT context INTO result FROM public.payment_method_contexts_internal(ids) WHERE order_id=sibling_order;
 PERFORM assert_true(EXISTS(SELECT 1 FROM jsonb_array_elements(result->'methods') method WHERE method->>'id'='cash' AND method->'record'='true'::jsonb AND method->'refund'='false'::jsonb),'shared permission scope retains per-order currency rules');

 -- Guard the real list entrypoint against reintroducing a per-order scalar
 -- read. Only this disposable transaction replaces the old scalar adapter.
 INSERT INTO public.occasion_link_reservations(slug,occasion) VALUES(x->>'link',(x->>'occasion')::bigint);
 EXECUTE $function$
  CREATE OR REPLACE FUNCTION public.payment_method_context_internal(p_order bigint)
  RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $body$
  BEGIN RAISE EXCEPTION 'SCALAR_PAYMENT_CONTEXT_IN_LIST'; END;
  $body$;
 $function$;
 EXECUTE $function$
  CREATE OR REPLACE FUNCTION public.order_tickets_with_seating_internal(p_order bigint,p_tickets jsonb)
  RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $body$
  BEGIN RAISE EXCEPTION 'SCALAR_SEATING_IN_LIST'; END;
  $body$;
 $function$;
 result:=public.get_orders(x->>'link',NULL,'{"include_full_order_data":true,"include_spots":true,"include_orders_history":true}');
 PERFORM assert_eq(result->>'code','200','real order list uses the bulk context boundary');

 -- Revocation must affect the very next read in the same session. The handler
 -- shortcut cannot be called by a client with forged prepared permissions.
 UPDATE eshop.bank_account_users SET is_admin=false WHERE bank_account=(x->>'bank')::bigint AND "user"=(x->>'actor')::uuid;
 SELECT context INTO result FROM public.payment_method_contexts_internal(ids) WHERE order_id=(x->>'order')::bigint;
 PERFORM assert_false(EXISTS(SELECT 1 FROM jsonb_array_elements(result->'requests') req WHERE req->>'instructions' IS NOT NULL),'revoked bank role hides instructions immediately');
 DELETE FROM public.unit_users WHERE unit=(x->>'unit')::bigint AND "user"=(x->>'actor')::uuid;
 SELECT context INTO result FROM public.payment_method_contexts_internal(ids) WHERE order_id=(x->>'order')::bigint;
 PERFORM assert_false(EXISTS(SELECT 1 FROM jsonb_array_elements(result->'methods') method WHERE method->'record'='true'::jsonb OR method->'refund'='true'::jsonb),'revoked manager role removes all money actions');
 SET LOCAL ROLE authenticated;
 BEGIN
  PERFORM public.command_payment_operation(jsonb_build_object('operation','record_payment','orderId',x->'order',
   'method','cash','amount','1','currency','CZK','receivedAt',now(),
   'permissions','{"can_record_cash":true,"can_refund_bank":true,"can_refund_provider":true}'::jsonb),gen_random_uuid());
  RAISE EXCEPTION 'Forged prepared permission accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 RESET ROLE;
 FOREACH signature IN ARRAY ARRAY[
  'public.payment_method_contexts_internal(bigint[])','public.payment_financial_totals_bulk_internal(bigint[])',
  'public.payment_transaction_movements_bulk_internal(bigint[])','public.payment_operation_permissions_internal(bigint[])',
  'public.cash_payment_provider_internal(text,jsonb)','public.bank_payment_provider_internal(text,jsonb)'
 ] LOOP
  FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
   PERFORM assert_false(has_function_privilege(role_name,signature,'EXECUTE'),'private prepared permission boundary: '||signature||' '||role_name);
  END LOOP;
 END LOOP;
END $$;
