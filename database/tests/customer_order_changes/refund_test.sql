-- test-setup: database/tests/helpers/payment_lifecycle_fixture.sql
-- test-setup: database/tests/customer_order_changes/fixture.sql
DO $$
DECLARE x jsonb:=pg_temp.customer_fixture(); oid bigint:=(x->>'order')::bigint; payment bigint:=(x->>'payment')::bigint;
 conn uuid; attempt uuid; unit bigint; token text; payload jsonb:='{}'; preview jsonb; result jsonb; command uuid:=extensions.gen_random_uuid(); claim jsonb;
BEGIN
 SELECT o.unit INTO unit FROM public.occasions o WHERE id=(x->>'occasion')::bigint;
 INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state,model_verified)
 VALUES((x->>'organization')::bigint,unit,'acct_customerRefund',false,'connected',true) RETURNING id INTO conn;
 UPDATE eshop.payment_info SET payment_method='stripe',bank_account=NULL,variable_symbol=NULL,creditor_reference=NULL,deposit_amount=NULL,stripe_connection_id=conn WHERE id=payment;
 INSERT INTO eshop.stripe_checkout_attempts(order_id,payment_info_id,organization_id,unit_id,connection_id,livemode,amount_minor,currency,order_revision,idempotency_key,reservation_expires_at,state,payment_intent_id)
 VALUES(oid,payment,(x->>'organization')::bigint,unit,conn,false,100000,'CZK',1,'customer-refund:'||command,now()+interval '30 minutes','paid','pi_customerRefund') RETURNING id INTO attempt;
 INSERT INTO eshop.stripe_payment_movements(connection_id,provider_id,attempt_id,kind,amount_minor,currency,occurred_at)
 VALUES(conn,'pi_customerRefund',attempt,'payment',100000,'CZK',now());
 PERFORM public.refresh_payment_info_totals_internal(payment);
 result:=public.apply_provider_payment_effects_internal('stripe',attempt,'customer-paid',public.provider_order_payment_projection_internal(oid));
 UPDATE eshop.payment_providers SET refund_write_supported=true,refund_write_enabled=true WHERE provider_key='stripe';
 token:=pg_temp.customer_cap(x,'cancel',payload);
 PERFORM set_config('request.jwt.claim.sub','',true);PERFORM set_config('request.jwt.claim.role','service_role',true);
 SET LOCAL ROLE service_role;
 preview:=public.customer_order_change_gateway('preview',token,NULL,'cancel',payload,command);
 PERFORM assert_eq(preview->>'effect','cancel_refund','full supported original-source refund');
 result:=public.customer_order_change_gateway('command',token,NULL,'cancel',payload,command,preview->>'fingerprint');
 result:=public.customer_order_change_gateway('command',token,NULL,'cancel',payload,command,preview->>'fingerprint');
 RESET ROLE;
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'storno','admission canceled atomically with refund intent');
 PERFORM assert_eq((SELECT price FROM eshop.orders WHERE id=oid),1000::numeric,'online original price preserved');
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=payment),0::numeric,'accepted refund is not returned money');
 PERFORM assert_eq((SELECT count(*) FROM eshop.refund_requests WHERE order_id=oid),1::bigint,'retry reserves exactly once');
 PERFORM assert_eq((SELECT amount FROM eshop.refund_requests WHERE id=command),1000::numeric,'only actual available paid balance reserved');
 UPDATE public.occasions SET features='[]',customer_self_service_epoch=customer_self_service_epoch+1 WHERE id=(x->>'occasion')::bigint;
 SET LOCAL ROLE service_role;
 claim:=public.claim_payment_refund(command);
 PERFORM assert_true(claim->>'lease' IS NOT NULL,'accepted financial obligation remains dispatchable with self-service off');
 result:=public.complete_payment_refund(command,(claim->>'lease')::uuid,'{"status":"succeeded","refundId":"re_customerRefund"}');
 RESET ROLE;
 PERFORM assert_eq((SELECT returned FROM eshop.payment_info WHERE id=payment),0::numeric,'transport success is still not settlement');
 INSERT INTO eshop.stripe_payment_movements(connection_id,provider_id,attempt_id,kind,amount_minor,currency,occurred_at)
 VALUES(conn,'re_customerRefund',attempt,'refund',100000,'CZK',now());
 PERFORM public.refresh_payment_info_totals_internal(payment);
 result:=public.apply_provider_payment_effects_internal('stripe',attempt,'customer-refunded',public.provider_order_payment_projection_internal(oid));
 SET LOCAL ROLE service_role;
 claim:=public.claim_payment_refund(command);
 RESET ROLE;
 PERFORM assert_eq((SELECT status FROM eshop.refund_requests WHERE id=command),'succeeded','original provider fact confirms returned money');
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'storno','settlement cannot revive canceled admission');
 PERFORM assert_false(EXISTS(SELECT 1 FROM eshop.transactions WHERE payment_info=payment),'no shadow bank ledger');
END $$;
