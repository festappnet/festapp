-- Stripe is one connector. All Stripe storage/identity and price restrictions
-- remain here; the order lifecycle dispatches through the common registry.
CREATE OR REPLACE FUNCTION public.stripe_payment_provider_internal(p_operation text,p_args jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE input jsonb; connection uuid; payment_id bigint; attempt uuid; expires timestamptz;
 amount numeric; currency text; target bigint; result jsonb;
BEGIN
 target:=(p_args->>'orderId')::bigint;
 IF p_operation='projection' THEN RETURN public.stripe_order_payment_projection_internal(target);
 ELSIF p_operation='attach_source' THEN
  PERFORM public.attach_stripe_order_pay_source_internal(target,(p_args->>'commandId')::uuid,p_args->'source'); RETURN NULL;
 ELSIF p_operation='initialize_payment' THEN
  input:=p_args->'input';amount:=(p_args->>'amount')::numeric;currency:=p_args->>'currency';
  IF coalesce(input->>'payment_type','full')<>'full' OR (p_args->>'deposit')::numeric>0 THEN RAISE EXCEPTION 'STRIPE_DEPOSIT_UNSUPPORTED'; END IF;
  connection:=public.assert_stripe_form_payable_internal((p_args->>'formId')::bigint,(input->>'stripe_connection_id')::uuid,input->>'payment_surface');
  IF (input->>'expected_payment_amount_minor')::numeric IS DISTINCT FROM amount*100 OR input->>'expected_payment_currency' IS DISTINCT FROM currency THEN
   RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','STRIPE_PRICE_CHANGED','message','Order price changed. Review the order before paying.')::text; END IF;
  IF currency NOT IN ('CZK','EUR','PLN','USD','GBP') OR amount*100<>trunc(amount*100) THEN RAISE EXCEPTION 'STRIPE_AMOUNT_UNSUPPORTED'; END IF;
  INSERT INTO eshop.payment_info(amount,currency_code,created_at,payment_method,stripe_connection_id)
   VALUES(amount,currency,(p_args->>'createdAt')::timestamptz,'stripe',connection) RETURNING id INTO payment_id;
  RETURN jsonb_build_object('paymentInfoId',payment_id);
 ELSIF p_operation='create_attempt' THEN
  attempt:=public.create_stripe_order_attempt_internal(target);
  SELECT reservation_expires_at INTO STRICT expires FROM eshop.stripe_checkout_attempts WHERE id=attempt;
  RETURN jsonb_build_object('expiresAt',expires);
 ELSIF p_operation='paid_guard' THEN
  IF NOT EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info
   JOIN eshop.stripe_checkout_attempts a ON a.order_id=o.id JOIN eshop.stripe_payment_movements m ON m.attempt_id=a.id
   WHERE o.id=target AND m.kind='payment' AND m.amount_minor=a.amount_minor
    AND m.connection_id=pi.stripe_connection_id AND m.occurred_at<=a.reservation_expires_at) THEN
   RETURN jsonb_build_object('code',409,'message','STRIPE_PROVIDER_PAYMENT_REQUIRED'); END IF;
  IF (SELECT state FROM eshop.orders WHERE id=target)='expired' THEN RETURN jsonb_build_object('code',409,'message','Stripe reservation was released'); END IF;
  RETURN NULL;
 ELSIF p_operation='totals' THEN
  payment_id:=(p_args->>'paymentId')::bigint;
  WITH p AS (SELECT * FROM eshop.payment_info WHERE id=payment_id), money AS (
   SELECT coalesce(sum(m.amount_minor) FILTER(WHERE m.kind='payment'),0)/100 received,
    coalesce(sum(m.amount_minor) FILTER(WHERE m.kind='refund'),0)/100 returned,
    coalesce(bool_or(m.connection_id IS DISTINCT FROM p.stripe_connection_id OR m.currency IS DISTINCT FROM p.currency_code::text
     OR a.order_id NOT IN(SELECT id FROM eshop.orders WHERE payment_info=p.id)),false) invalid
   FROM p JOIN eshop.stripe_checkout_attempts a ON a.payment_info_id=p.id JOIN eshop.stripe_payment_movements m ON m.attempt_id=a.id),
  holds AS (SELECT coalesce(sum(d.amount_minor) FILTER(WHERE d.status IN ('needs_response','under_review','lost')),0)/100 held
   FROM eshop.stripe_checkout_attempts a JOIN eshop.stripe_disputes d ON d.attempt_id=a.id WHERE a.payment_info_id=payment_id)
  SELECT jsonb_build_object('received',received,'returned',returned,'invalid',invalid,'held',held) INTO result FROM money CROSS JOIN holds;
  RETURN result;
 ELSIF p_operation='effect_context' THEN
  SELECT jsonb_build_object('attemptId',a.id,'orderId',a.order_id,'paymentId',a.payment_info_id,'connectionId',a.connection_id,
   'organizationId',a.organization_id,'unitId',a.unit_id,'accountId',c.account_id,'livemode',a.livemode,
   'amountMinor',a.amount_minor,'currency',a.currency,'reservationExpiresAt',a.reservation_expires_at,
   'state',a.state,'incomplete',a.refund_cursor IS NOT NULL OR a.session_lookup_cursor IS NOT NULL,
   'receivedMinor',(SELECT coalesce(sum(amount_minor),0) FROM eshop.stripe_payment_movements WHERE attempt_id=a.id AND kind='payment'),
   'refundedMinor',(SELECT coalesce(sum(amount_minor),0) FROM eshop.stripe_payment_movements WHERE attempt_id=a.id AND kind='refund'),
   'paymentTime',(SELECT min(occurred_at) FROM eshop.stripe_payment_movements WHERE attempt_id=a.id AND kind='payment'),
   'decisions',coalesce((SELECT jsonb_agg(reason) FROM eshop.stripe_admission_decisions WHERE attempt_id=a.id),'[]'))
  INTO result FROM eshop.stripe_checkout_attempts a JOIN eshop.stripe_connections c ON c.id=a.connection_id
   JOIN eshop.payment_info pi ON pi.id=a.payment_info_id AND pi.stripe_connection_id=c.id
   WHERE a.id=(p_args->>'attemptId')::uuid AND c.organization_id=a.organization_id AND c.unit_id=a.unit_id AND c.livemode=a.livemode;
  RETURN result;
 ELSIF p_operation='effect_lock' THEN
  PERFORM 1 FROM eshop.stripe_checkout_attempts WHERE id=(p_args->>'attemptId')::uuid FOR UPDATE; RETURN NULL;
 ELSIF p_operation='effect_state' THEN
  IF p_args->>'state' NOT IN ('paid','expired','action_required') THEN RAISE EXCEPTION 'PAYMENT_EFFECT_STATE_INVALID'; END IF;
  UPDATE eshop.stripe_checkout_attempts SET state=p_args->>'state'
   WHERE id=(p_args->>'attemptId')::uuid; RETURN NULL;
 ELSIF p_operation='effect_decision' THEN
  INSERT INTO eshop.stripe_admission_decisions(attempt_id,reason,provider_revision,ticket_ids,actor)
   VALUES((p_args->>'attemptId')::uuid,p_args->>'reason',p_args->>'revision',
    ARRAY(SELECT jsonb_array_elements_text(coalesce(p_args->'tickets','[]'))::bigint),auth.uid()) RETURNING id INTO attempt;
  RETURN to_jsonb(attempt);
 ELSIF p_operation='setup_recipients' THEN
  SELECT coalesce(jsonb_agg(jsonb_build_object('connectionId',id,'name',business_name,'livemode',livemode) ORDER BY livemode,id),'[]') INTO result
   FROM eshop.stripe_connections WHERE unit_id=(p_args->>'unitId')::bigint AND model_verified AND state IN ('connected','restricted');
  RETURN result;
 ELSIF p_operation='unit_fields' THEN RETURN jsonb_build_object('stripe_preview_enabled',public.stripe_unit_feature_enabled_internal((p_args->>'unitId')::bigint));
 ELSIF p_operation='unit_feature' THEN RETURN to_jsonb(public.stripe_unit_feature_enabled_internal((p_args->>'unitId')::bigint));
 ELSIF p_operation='form_availability' THEN
  result:=public.stripe_form_payment_availability_internal((p_args->>'formId')::bigint);
  RETURN jsonb_build_object('providerId','stripe','configured',result#>'{configured,stripe}',
   'available',result->'available' ? 'stripe','recipient',result->'recipient','supportedSurfaces',result->'supportedSurfaces',
   'reason',jsonb_build_object('code',result->'stripeUnavailableReason'));
 ELSIF p_operation='validate_form' THEN
  PERFORM public.validate_stripe_form_payment_configuration_internal((p_args->>'formId')::bigint); RETURN NULL;
 ELSIF p_operation='form_editor_fields' THEN
  RETURN jsonb_build_object('stripeRecipient',public.get_form_stripe_recipient((p_args->>'unitId')::bigint,(p_args->>'occasionId')::bigint,(p_args->>'livemode')::boolean));
 ELSIF p_operation='movements' THEN
  SELECT coalesce(jsonb_agg(jsonb_build_object('kind',m.kind,'amount_minor',m.amount_minor,'currency',m.currency,'occurred_at',m.occurred_at)),'[]') INTO result
   FROM eshop.stripe_checkout_attempts a JOIN eshop.stripe_payment_movements m ON m.attempt_id=a.id WHERE a.payment_info_id=(p_args->>'paymentId')::bigint;
  RETURN result;
 END IF;
 RAISE EXCEPTION 'PAYMENT_PROVIDER_OPERATION_UNSUPPORTED';
END $$;
REVOKE ALL ON FUNCTION public.stripe_payment_provider_internal(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='eshop.payment_info'::regclass AND conname='payment_info_stripe_connection_identity') THEN
ALTER TABLE eshop.payment_info ADD CONSTRAINT payment_info_stripe_connection_identity CHECK(
 (payment_method='stripe')=(stripe_connection_id IS NOT NULL)); END IF; END $$;
INSERT INTO eshop.payment_providers(provider_key,handler,source_field,legacy_connection_field)
 VALUES('stripe','public.stripe_payment_provider_internal(text,jsonb)'::regprocedure,'stripePaymentSource','stripeConnectionId') ON CONFLICT(provider_key) DO UPDATE SET handler=excluded.handler,source_field=excluded.source_field,legacy_connection_field=excluded.legacy_connection_field;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='eshop.payment_info'::regclass AND conname='payment_info_registered_method') THEN
ALTER TABLE eshop.payment_info ADD CONSTRAINT payment_info_registered_method
 FOREIGN KEY(payment_method) REFERENCES eshop.payment_providers(provider_key); END IF; END $$;
