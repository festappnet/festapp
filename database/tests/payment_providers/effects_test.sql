-- Deliberately different connector storage; no Stripe session or cursor model.
CREATE TEMP TABLE alternate_payment_facts(attempt uuid PRIMARY KEY, context jsonb NOT NULL);
CREATE TEMP TABLE alternate_payment_movements(attempt uuid,identity text,kind text,amount numeric,currency text,occurred_at timestamptz);
CREATE FUNCTION public.test_alternate_effects(p_operation text,p_args jsonb)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE c jsonb; result jsonb; o eshop.orders;
BEGIN
 SELECT context INTO c FROM pg_temp.alternate_payment_facts WHERE attempt=(p_args->>'attemptId')::uuid;
 IF p_operation='effect_context' THEN RETURN c;
 ELSIF p_operation='notification_facts' THEN
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('identity',identity,'amount',amount,'currency',currency,'occurredAt',occurred_at)),'[]') FROM pg_temp.alternate_payment_movements WHERE attempt=(p_args->>'attemptId')::uuid AND kind='payment');
 ELSIF p_operation='effect_lock' THEN PERFORM 1 FROM pg_temp.alternate_payment_facts WHERE attempt=(p_args->>'attemptId')::uuid FOR UPDATE; RETURN NULL;
 ELSIF p_operation='effect_state' THEN
  UPDATE pg_temp.alternate_payment_facts SET context=jsonb_set(context,'{state}',p_args->'state') WHERE attempt=(p_args->>'attemptId')::uuid;RETURN NULL;
 ELSIF p_operation='effect_decision' THEN
  UPDATE pg_temp.alternate_payment_facts SET context=jsonb_set(context,'{decisions}',context->'decisions'||jsonb_build_array(p_args->>'reason')) WHERE attempt=(p_args->>'attemptId')::uuid;RETURN to_jsonb(extensions.gen_random_uuid());
 ELSIF p_operation='totals' THEN
  SELECT context INTO c FROM pg_temp.alternate_payment_facts WHERE (context->>'paymentId')::bigint=(p_args->>'paymentId')::bigint;
  RETURN jsonb_build_object('received',(c->>'receivedMinor')::numeric/100,'returned',(c->>'refundedMinor')::numeric/100,'held',0,'invalid',false);
 ELSIF p_operation='projection' THEN
  SELECT * INTO o FROM eshop.orders WHERE id=(p_args->>'orderId')::bigint;
  SELECT context INTO c FROM pg_temp.alternate_payment_facts WHERE (context->>'orderId')::bigint=o.id;
  RETURN jsonb_build_object('method','different_gateway','status',CASE WHEN (c->>'refundedMinor')::numeric>=10000 THEN 'refunded' WHEN (c->>'receivedMinor')::numeric>=10000 THEN 'paid' ELSE 'pending' END,
   'admissionState',CASE WHEN (c->>'refundedMinor')::numeric>=10000 THEN 'hold' WHEN o.state IN ('paid','sent') THEN 'valid' ELSE 'pending' END,'reconciliationPending',false);
 ELSIF p_operation='paid_guard' THEN RETURN NULL;
 END IF;
 RAISE EXCEPTION 'unsupported test operation';
END $$;
INSERT INTO eshop.payment_providers(provider_key,handler,source_field,hosted_checkout) VALUES('different_gateway','public.test_alternate_effects(text,jsonb)'::regprocedure,'differentSource',true);
DO $$
DECLARE fx jsonb:=public.scanner_test_fixture(1); oc bigint:=(fx->>'occasion')::bigint; oid bigint; pi bigint; org bigint; u bigint;
 a uuid:=extensions.gen_random_uuid(); c jsonb; result jsonb; t bigint:=(fx#>>'{tickets,0}')::bigint; used bigint; emails bigint;
BEGIN
 PERFORM set_config('festapp.email_wake','scheduled',true);
 SELECT "order" INTO oid FROM eshop.order_product_ticket WHERE ticket=t;
 SELECT organization,unit INTO org,u FROM public.occasions WHERE id=oc;
 INSERT INTO eshop.ticket_wallet_objects(ticket_id,organization,occasion,issuer,environment,object_id,class_id) VALUES(t,org,oc,'1234','effects','1234.effects-'||t,'1234.effects-class-'||oc);
 PERFORM public.enqueue_ticket_wallet_internal(ARRAY[t]);
 INSERT INTO eshop.payment_info(amount,currency_code,payment_method) VALUES(100,'CZK','different_gateway') RETURNING id INTO pi;
 UPDATE eshop.orders SET payment_info=pi,price=100,currency_code='CZK' WHERE id=oid;
 c:=jsonb_build_object('attemptId',a,'orderId',oid,'paymentId',pi,'connectionId',extensions.gen_random_uuid(),
  'organizationId',org,'unitId',u,'accountId','merchant-owned-account','livemode',false,'amountMinor',10000,'currency','CZK',
  'reservationExpiresAt',now()+interval '20 minutes','state','paid','incomplete',false,'receivedMinor',10000,'refundedMinor',0,
  'paymentTime',now(),'decisions','[]'::jsonb);
 INSERT INTO pg_temp.alternate_payment_facts VALUES(a,c);
 INSERT INTO pg_temp.alternate_payment_movements VALUES(a,'connection:stored-payment:payment','payment',100,'CZK',now());
 INSERT INTO public.notification_center_organizations(organization,initialized_at) VALUES(org,now()-interval '1 day') ON CONFLICT DO NOTHING;
 result:=public.apply_provider_payment_effects_internal('different_gateway',a,'first',NULL);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'sent','another storage protocol runs the same owner');
 PERFORM assert_eq((SELECT paid FROM eshop.payment_info WHERE id=pi),100::numeric,'generic owner refreshes actual ledger totals');
 PERFORM assert_true(EXISTS(SELECT 1 FROM public.notification_center_events WHERE organization=org AND kind='order_payment_received' AND data->>'paymentFact'='different_gateway:connection:stored-payment:payment'),'notification identity comes from connector storage');
 UPDATE pg_temp.alternate_payment_facts SET context=context-'receivedMinor' WHERE attempt=a;
 BEGIN PERFORM public.apply_provider_payment_effects_internal('different_gateway',a,'missing',NULL);RAISE EXCEPTION 'missing financial field accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_EFFECT_CONTEXT_INVALID' THEN RAISE; END IF; END;
 UPDATE pg_temp.alternate_payment_facts SET context=jsonb_set(c,'{currency}','"EUR"') WHERE attempt=a;
 BEGIN PERFORM public.apply_provider_payment_effects_internal('different_gateway',a,'foreign',NULL);RAISE EXCEPTION 'foreign currency accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_EFFECT_SCOPE_INVALID' THEN RAISE; END IF; END;
 UPDATE pg_temp.alternate_payment_facts SET context=jsonb_set(c,'{organizationId}',to_jsonb(org+1)) WHERE attempt=a;
 BEGIN PERFORM public.apply_provider_payment_effects_internal('different_gateway',a,'foreign',NULL);RAISE EXCEPTION 'foreign account scope accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PAYMENT_EFFECT_SCOPE_INVALID' THEN RAISE; END IF; END;
 INSERT INTO eshop.tickets(occasion,ticket_symbol,state) VALUES(oc,'USED-'||a,'used') RETURNING id INTO used;
 INSERT INTO eshop.order_product_ticket("order",product,ticket) SELECT oid,product,used FROM eshop.order_product_ticket WHERE ticket=t;
 UPDATE pg_temp.alternate_payment_facts SET context=jsonb_set(c,'{refundedMinor}','10000') WHERE attempt=a;
 result:=public.apply_provider_payment_effects_internal('different_gateway',a,'full-refund',NULL);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'storno','full refund reaches canonical storno transition');
 PERFORM assert_true((SELECT requested>1 FROM eshop.ticket_wallet_work WHERE kind='object' AND ticket_id=t),'provider refund enqueues invalidation');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=t),'storno','eligible admission cancelled');
 PERFORM assert_eq((SELECT state FROM eshop.tickets WHERE id=used),'used','used ticket history preserved');
 SELECT email_payment_version INTO emails FROM eshop.orders WHERE id=oid;
 result:=public.apply_provider_payment_effects_internal('different_gateway',a,'replayed-refund',NULL);
 PERFORM assert_eq((SELECT email_payment_version FROM eshop.orders WHERE id=oid),emails,'duplicate full refund has no second email consequence');
 -- An uncertain create outlives the inventory reservation, never becoming absent.
 UPDATE eshop.orders SET state='ordered' WHERE id=oid;
 UPDATE pg_temp.alternate_payment_facts SET context=c||jsonb_build_object('state','uncertain','receivedMinor',0,'refundedMinor',0,'paymentTime',NULL,'reservationExpiresAt',now()-interval '1 minute') WHERE attempt=a;
 result:=public.apply_provider_payment_effects_internal('different_gateway',a,'uncertain-create',NULL,false,true);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'expired','elapsed inventory released while finance unresolved');
 PERFORM assert_eq((SELECT context->>'state' FROM pg_temp.alternate_payment_facts WHERE attempt=a),'uncertain','release does not assert absence');
 UPDATE pg_temp.alternate_payment_facts SET context=context||jsonb_build_object('receivedMinor',10000,'paymentTime',now()) WHERE attempt=a;
 result:=public.apply_provider_payment_effects_internal('different_gateway',a,'late-payment',NULL);
 PERFORM assert_eq((SELECT state FROM eshop.orders WHERE id=oid),'expired','late money never revives released seats');
 PERFORM assert_eq((SELECT context->>'state' FROM pg_temp.alternate_payment_facts WHERE attempt=a),'action_required','late payment remains held for resolution');
 PERFORM assert_true((SELECT context->'decisions' ? 'late_payment' FROM pg_temp.alternate_payment_facts WHERE attempt=a),'late payment has explicit resolution evidence');
END $$;
