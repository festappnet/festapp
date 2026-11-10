-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
-- test-setup: database/tests/helpers/refund_operation_fixture.sql
-- Two actual SQL adapters share the command/lease/recovery protocol. Stripe
-- facts below are persisted fixtures, not remote API/refund execution.
CREATE TEMP TABLE alternate_refund_bindings(order_id bigint PRIMARY KEY,payment_id bigint NOT NULL,binding jsonb NOT NULL);
CREATE TEMP TABLE alternate_refund_movements(provider_id text PRIMARY KEY,order_id bigint NOT NULL,amount numeric NOT NULL,currency text NOT NULL);
CREATE FUNCTION public.test_refund_provider(p_operation text,p_args jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE b pg_temp.alternate_refund_bindings; refunded numeric;
BEGIN
 SELECT * INTO b FROM pg_temp.alternate_refund_bindings WHERE order_id=(p_args->>'orderId')::bigint
  OR payment_id=(p_args->>'paymentId')::bigint;
 IF p_operation='operation_capabilities' THEN RETURN jsonb_build_object('id','refund_gateway','displayName','Alternate gateway',
  'record',false,'refund',b.order_id IS NOT NULL,'verification','verified_provider_observation');
 ELSIF p_operation='refund_binding' THEN RETURN b.binding;
 ELSIF p_operation='refund_observed' THEN RETURN to_jsonb(EXISTS(
  SELECT 1 FROM pg_temp.alternate_refund_movements m JOIN eshop.refund_requests r ON r.order_id=m.order_id
  WHERE r.id=(p_args->>'requestId')::uuid AND r.method='refund_gateway' AND m.provider_id=p_args->>'refundId'
   AND m.order_id=b.order_id AND m.currency=r.currency AND m.amount=r.amount));
 ELSIF p_operation='totals' THEN
  SELECT coalesce(sum(amount),0) INTO refunded FROM pg_temp.alternate_refund_movements WHERE order_id=b.order_id;
  RETURN jsonb_build_object('received',1000,'returned',refunded,'held',0,'invalid',false);
 ELSIF p_operation='projection' THEN RETURN '{"method":"refund_gateway","status":"paid","admissionState":"valid"}';
 END IF;
 RAISE EXCEPTION 'TEST_OPERATION_UNSUPPORTED';
END $$;
REVOKE ALL ON FUNCTION public.test_refund_provider(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO eshop.payment_providers(provider_key,handler,source_field,hosted_checkout,operation_mode,verification)
 VALUES('refund_gateway','public.test_refund_provider(text,jsonb)'::regprocedure,'refundGatewaySource',true,'remote','verified_provider_observation');
CREATE FUNCTION pg_temp.record_refund_fixture(x jsonb,p_provider text,p_refund text,p_amount numeric)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 IF p_provider='stripe' THEN
  INSERT INTO eshop.stripe_payment_movements(connection_id,provider_id,attempt_id,kind,amount_minor,currency,occurred_at)
  VALUES((x->>'connection')::uuid,p_refund,(x->>'attempt')::uuid,'refund',p_amount*100,'CZK',now());
 ELSE
  INSERT INTO pg_temp.alternate_refund_movements VALUES(p_refund,(x->>'order')::bigint,p_amount,'CZK');
 END IF;
 PERFORM public.refresh_payment_info_totals_internal((x->>'payment')::bigint);
END $$;
CREATE FUNCTION pg_temp.exercise_refund_dispatch(x jsonb,p_provider text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE oid bigint:=(x->>'order')::bigint; pi bigint:=(x->>'payment')::bigint;
 command uuid:=extensions.gen_random_uuid(); request2 uuid:=extensions.gen_random_uuid(); r jsonb; c jsonb; c2 jsonb; payload jsonb; saved_binding jsonb;
BEGIN
 PERFORM assert_false((SELECT refund_write_enabled FROM eshop.payment_providers WHERE provider_key=p_provider),'installation does not activate refund writes');
 payload:=jsonb_build_object('operation','prepare_refund','orderId',oid,'method',p_provider,'amount','100.00');
 BEGIN
  PERFORM public.command_payment_operation(payload,command);RAISE EXCEPTION 'disabled provider write accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_REFUND_UNAVAILABLE' THEN RAISE; END IF; END;
 UPDATE eshop.payment_providers SET refund_write_enabled=true WHERE provider_key=p_provider;
 SET LOCAL ROLE authenticated;
 r:=public.command_payment_operation(payload,command);
 RESET ROLE;
 PERFORM assert_eq(r#>>'{data,nextAction}','processing','same command creates durable external intent');
 PERFORM assert_eq((SELECT status FROM eshop.refund_requests WHERE id=command),'pending','accepted intent is not confirmed expenditure');
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=pi),0::numeric,'intent cannot manufacture returned money');
 PERFORM assert_eq((public.payment_method_context_internal(oid)->>'pending')::numeric,100::numeric,'intent reserves exact amount');
 saved_binding:=(SELECT rr.payload->'binding' FROM eshop.refund_requests rr WHERE rr.id=command);
 PERFORM assert_eq(saved_binding->>'currency','CZK','binding preserves original currency');
 PERFORM assert_eq((saved_binding->>'livemode')::boolean,false,'binding preserves original test/live environment');
 FOR c IN SELECT jsonb_build_object('operation','prepare_refund','orderId',oid,'method',method,'amount','1.00','receivedAt',now()) FROM unnest(ARRAY['cash','bank']) method LOOP
  BEGIN PERFORM public.command_payment_operation(c,extensions.gen_random_uuid());RAISE EXCEPTION 'external payment bypassed through builtin';
  EXCEPTION WHEN insufficient_privilege THEN NULL; WHEN raise_exception THEN
   IF SQLERRM<>'PAYMENT_REFUND_UNAVAILABLE' THEN RAISE; END IF; END;
 END LOOP;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 BEGIN PERFORM public.complete_payment_refund(command,NULL,'{"status":"succeeded","refundId":"unleased"}');RAISE EXCEPTION 'missing lease accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'REFUND_LEASE_LOST' THEN RAISE; END IF; END;
 c:=public.claim_payment_refund(command);
 PERFORM assert_eq(c->>'providerId',p_provider,'one installed provider dispatch identity');
 PERFORM assert_false((c->>'priorDispatched')::boolean,'initial claim is new dispatch');
 PERFORM assert_eq(c#>>'{snapshot,paymentId}',saved_binding->>'paymentId','original provider payment identity retained');
 PERFORM assert_eq(c#>>'{snapshot,accountId}',saved_binding->>'accountId','original account retained');
 PERFORM assert_eq((c#>>'{snapshot,amountMinor}')::numeric,10000::numeric,'exact refund minor units');
 PERFORM assert_eq(public.claim_payment_refund(command)->>'disposition','busy','live lease prevents duplicate remote dispatch');
 BEGIN PERFORM public.complete_payment_refund(command,extensions.gen_random_uuid(),'{"status":"succeeded"}');RAISE EXCEPTION 'wrong lease accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'REFUND_LEASE_LOST' THEN RAISE; END IF; END;
 r:=public.complete_payment_refund(command,(c->>'lease')::uuid,'{"status":"succeeded","refundId":"refund_owned"}');
 PERFORM assert_eq(r->>'status','pending','successful transport response waits for verified ledger fact');
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=pi),0::numeric,'successful dispatch alone has no financial effect');
 BEGIN PERFORM public.complete_payment_refund(command,(c->>'lease')::uuid,'{"status":"succeeded"}');RAISE EXCEPTION 'completed lease replay accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'REFUND_LEASE_LOST' THEN RAISE; END IF; END;
 c2:=public.claim_payment_refund(command);
 PERFORM assert_true((c2->>'priorDispatched')::boolean,'recovery resumes known dispatch instead of creating another');
 PERFORM assert_eq(c2#>>'{snapshot,idempotencyKey}',c#>>'{snapshot,idempotencyKey}','recovery retains one stable idempotency identity');
 r:=public.complete_payment_refund(command,(c2->>'lease')::uuid,'{"status":"unknown","dispatchUncertain":true,"refundId":"refund_owned"}');
 PERFORM assert_eq(r->>'status','unknown','uncertain operation retains explicit unresolved state');
 PERFORM assert_eq((public.payment_method_context_internal(oid)->>'available')::numeric,900::numeric,'unknown dispatch keeps its reservation');
 -- Only the adapter-owned verified ledger can confirm a refund. No bank row.
 PERFORM pg_temp.record_refund_fixture(x,p_provider,'refund_owned',100);
 r:=public.claim_payment_refund(command);
 PERFORM assert_eq(r->>'disposition','read','verified fact resolves request before any redispatch');
 PERFORM assert_eq((SELECT status FROM eshop.refund_requests WHERE id=command),'succeeded','verified ledger confirms the request');
 PERFORM assert_eq((public.payment_method_context_internal(oid)->>'pending')::numeric,0::numeric,'confirmed request releases reservation');
 PERFORM assert_eq((public.payment_method_context_internal(oid)->>'net')::numeric,900::numeric,'financial projection counts provider refund once');
 PERFORM assert_eq((SELECT count(*) FROM eshop.transactions WHERE payment_info=pi),0::bigint,'provider never creates a bank/cash shadow transaction');
 -- An externally created provider refund remains visible without a local intent.
 PERFORM pg_temp.record_refund_fixture(x,p_provider,'refund_external',50);
 PERFORM assert_eq((public.payment_method_context_internal(oid)->>'net')::numeric,850::numeric,'external refund shares the same actual ledger projection');
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 PERFORM public.command_payment_operation(payload,request2);
 -- The recovery claim checks the currently stored original binding, not client inputs.
 IF p_provider='stripe' THEN UPDATE eshop.stripe_connections SET account_id='acct_changedBinding' WHERE id=(x->>'connection')::uuid;
 ELSE UPDATE pg_temp.alternate_refund_bindings SET binding=jsonb_set(binding,'{accountId}','"changed-merchant"') WHERE order_id=oid; END IF;
 PERFORM set_config('request.jwt.claim.role','service_role',true);
 BEGIN PERFORM public.claim_payment_refund(request2);RAISE EXCEPTION 'changed original binding accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'REFUND_BINDING_CHANGED' THEN RAISE; END IF; END;
 IF p_provider='stripe' THEN UPDATE eshop.stripe_connections SET account_id=saved_binding->>'accountId' WHERE id=(x->>'connection')::uuid;
 ELSE UPDATE pg_temp.alternate_refund_bindings SET binding=saved_binding WHERE order_id=oid; END IF;
 UPDATE eshop.payment_providers SET refund_write_enabled=false WHERE provider_key=p_provider;
 PERFORM assert_eq(public.claim_payment_refund(request2)->>'disposition','read','disabled write activation prevents remote dispatch');
 PERFORM set_config('request.jwt.claim.role','authenticated',true);
 DELETE FROM public.unit_users WHERE unit=(x->>'unit')::bigint AND "user"=(x->>'actor')::uuid;
 BEGIN PERFORM public.command_payment_operation(payload,command);RAISE EXCEPTION 'revoked manager replay accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
DO $$
DECLARE x jsonb:=pg_temp.payment_fixture(); conn uuid; attempt uuid; u bigint; binding jsonb;
BEGIN
 PERFORM set_config('festapp.email_wake','scheduled',true);
 PERFORM assert_false(has_function_privilege('authenticated','public.claim_payment_refund(uuid)','EXECUTE'),'user cannot claim provider dispatch');
 PERFORM assert_false(has_function_privilege('authenticated','public.complete_payment_refund(uuid,uuid,jsonb)','EXECUTE'),'user cannot manufacture provider completion');
 SELECT unit INTO u FROM public.occasions WHERE id=(x->>'occasion')::bigint;
 INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state,model_verified)
 VALUES((x->>'organization')::bigint,u,'acct_refundContract',false,'connected',true) RETURNING id INTO conn;
 UPDATE eshop.payment_info SET payment_method='stripe',bank_account=NULL,variable_symbol=NULL,creditor_reference=NULL,
  deposit_amount=NULL,stripe_connection_id=conn WHERE id=(x->>'payment')::bigint;
 INSERT INTO eshop.stripe_checkout_attempts(order_id,payment_info_id,organization_id,unit_id,connection_id,livemode,amount_minor,
 currency,order_revision,idempotency_key,reservation_expires_at,state,payment_intent_id)
 VALUES((x->>'order')::bigint,(x->>'payment')::bigint,(x->>'organization')::bigint,u,conn,false,100000,'CZK',1,
 'refund-contract:'||extensions.gen_random_uuid(),now()+interval '30 minutes','paid','pi_refundContract') RETURNING id INTO attempt;
 INSERT INTO eshop.stripe_payment_movements(connection_id,provider_id,attempt_id,kind,amount_minor,currency,occurred_at)
 VALUES(conn,'pi_refundContract',attempt,'payment',100000,'CZK',now());
 PERFORM public.refresh_payment_info_totals_internal((x->>'payment')::bigint);
 PERFORM pg_temp.exercise_refund_dispatch(x||jsonb_build_object('connection',conn,'attempt',attempt,'unit',u),'stripe');
 -- Same shared path, different storage and original-payment identity protocol.
 x:=pg_temp.payment_fixture();SELECT unit INTO u FROM public.occasions WHERE id=(x->>'occasion')::bigint;
 UPDATE eshop.payment_info SET payment_method='refund_gateway',bank_account=NULL,variable_symbol=NULL,creditor_reference=NULL,deposit_amount=NULL
 WHERE id=(x->>'payment')::bigint;
 binding:=jsonb_build_object('attemptId',extensions.gen_random_uuid(),'accountId','merchant-asset-17','livemode',false,
 'paymentId','original-remote-transfer','currency','CZK','amountMinor',100000);
 INSERT INTO pg_temp.alternate_refund_bindings VALUES((x->>'order')::bigint,(x->>'payment')::bigint,binding);
 PERFORM public.refresh_payment_info_totals_internal((x->>'payment')::bigint);
 PERFORM pg_temp.exercise_refund_dispatch(x||jsonb_build_object('unit',u),'refund_gateway');
END $$;

DO $$
DECLARE x jsonb:=pg_temp.refund_fixture(); r jsonb; request uuid:=extensions.gen_random_uuid(); facts_before bigint;
BEGIN
 SELECT (SELECT count(*) FROM eshop.stripe_payment_movements)+(SELECT count(*) FROM eshop.barion_movements) INTO facts_before;
 r:=public.command_payment_operation(jsonb_build_object('operation','prepare_refund','orderId',x->'order','method','bank','amount','100.00',
  'recipientIban',public.canonical_payment_reference_account_internal('1234/2010'),'recipientName','Bank refund recipient'),request);
 PERFORM assert_eq((SELECT status FROM eshop.refund_requests WHERE id=request),'pending','bank instruction waits for its actual owner');
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=(x->>'payment')::bigint),0::numeric,'bank preparation is not confirmed spending');
 PERFORM pg_temp.refund_bank_event(x,77,-10000);
 PERFORM assert_eq((SELECT status FROM eshop.refund_requests WHERE id=request),'succeeded','actual bank ledger settles bank request');
 PERFORM assert_eq((SELECT count(*) FROM eshop.refund_settlements WHERE request_id=request),1::bigint,'bank owns one actual settlement');
 PERFORM assert_eq((SELECT count(*) FROM eshop.stripe_payment_movements)+(SELECT count(*) FROM eshop.barion_movements),facts_before,
  'pending and confirmed bank refund never create provider shadow money');
END $$;
