-- Sole provider-to-domain write boundary. Raw signature verification and current
-- account-scoped provider reads happen in Edge; every effect below commits once.
CREATE OR REPLACE FUNCTION public.ingest_stripe_payment_internal(
 p_attempt uuid,p_lease uuid,p_event jsonb,p_facts jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE a eshop.stripe_checkout_attempts; c eshop.stripe_connections; o eshop.orders; pi eshop.payment_info;
 existing eshop.stripe_event_inbox; movement eshop.stripe_payment_movements; d eshop.stripe_disputes;
 fact jsonb; totals record; before_projection jsonb; projection jsonb; v_receipt jsonb; transition jsonb;
 command uuid; input_hash text; mutation_claim jsonb; before_users uuid[]; cancelled bigint[]; payment_time timestamptz;
 card_received numeric; card_refunded numeric; financial_conflict boolean;
 changed boolean:=false; observed timestamptz:=(p_facts->>'observedAt')::timestamptz;
 no_session boolean:=coalesce(p_facts->'noSessionVerified'='true'::jsonb,false);
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE id=p_attempt;
 SELECT * INTO STRICT c FROM eshop.stripe_connections WHERE id=a.connection_id;
 IF p_event->>'id' IS NULL OR p_event->>'id' !~ '^evt_[A-Za-z0-9]+$'
  OR p_event->>'bodyHash' IS NULL OR p_event->>'bodyHash' !~ '^[a-f0-9]{64}$'
  OR p_event->>'accountId' IS DISTINCT FROM c.account_id OR (p_event->>'livemode')::boolean IS DISTINCT FROM a.livemode
  OR nullif(p_event->>'type','') IS NULL OR length(p_event->>'type')>100 THEN RAISE EXCEPTION 'STRIPE_EVENT_IDENTITY_INVALID'; END IF;
 SELECT * INTO existing FROM eshop.stripe_event_inbox WHERE connection_id=c.id AND event_id=p_event->>'id';
 IF FOUND THEN
  IF existing.body_sha256<>p_event->>'bodyHash' OR existing.receipt IS NULL THEN RAISE EXCEPTION 'STRIPE_EVENT_RECEIPT_INVALID'; END IF;
  RETURN existing.receipt;
 END IF;
 command:=(substr(encode(extensions.digest(c.id::text||':'||(p_event->>'id'),'sha256'),'hex'),1,32))::uuid;
 -- Event body identity is immutable; a replay may have newer provider reads.
 input_hash:=encode(extensions.digest(p_event::text,'sha256'),'hex');
 mutation_claim:=public.begin_anonymous_client_mutation_v1(command,'inventory.order.stripe_sync',
  (SELECT occasion FROM eshop.orders WHERE id=a.order_id),command,input_hash);
 IF mutation_claim->>'disposition'='replay' THEN RETURN mutation_claim->'response'; END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[a.order_id]);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=a.order_id FOR UPDATE;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=a.payment_info_id FOR UPDATE;
 SELECT * INTO STRICT a FROM eshop.stripe_checkout_attempts WHERE id=p_attempt FOR UPDATE;
 IF p_lease IS NULL OR a.lease_token IS NULL OR a.lease_expires_at IS NULL OR a.lease_token IS DISTINCT FROM p_lease OR a.lease_expires_at<=clock_timestamp()
  OR observed IS NULL OR observed>clock_timestamp()+interval '1 minute'
  OR observed<coalesce(a.last_synced_at,'-infinity') THEN RAISE EXCEPTION 'STRIPE_SYNC_LEASE_INVALID'; END IF;
 IF pi.id<>o.payment_info OR pi.payment_method<>'stripe' OR pi.stripe_connection_id<>c.id
  OR pi.amount*100<>a.amount_minor OR pi.currency_code<>a.currency
  OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=o.occasion AND organization=a.organization_id AND unit=a.unit_id)
  OR (NOT no_session AND (p_facts->>'sessionId' IS NULL OR p_facts->>'sessionId' !~ '^cs_[A-Za-z0-9_]+$'))
  OR (no_session AND (a.session_id IS NOT NULL OR a.session_lookup_found IS NOT NULL OR p_facts->>'sessionId' IS NOT NULL
   OR p_facts->>'paymentIntentId' IS NOT NULL OR p_facts->>'sessionStatus' IS DISTINCT FROM 'expired'
   OR a.reservation_expires_at>clock_timestamp()
   OR p_event->>'type' IS DISTINCT FROM 'festapp.reconcile' OR p_facts->'movements'<>'[]'::jsonb OR p_facts->'disputes'<>'[]'::jsonb))
  OR (a.session_id IS NOT NULL AND a.session_id<>p_facts->>'sessionId')
  OR (a.payment_intent_id IS NOT NULL AND a.payment_intent_id IS DISTINCT FROM p_facts->>'paymentIntentId')
  OR jsonb_typeof(p_facts->'movements') IS DISTINCT FROM 'array' OR jsonb_array_length(p_facts->'movements')>501
  OR jsonb_typeof(p_facts->'disputes') IS DISTINCT FROM 'array' OR jsonb_array_length(p_facts->'disputes')>100 THEN
  RAISE EXCEPTION 'STRIPE_FACT_IDENTITY_INVALID'; END IF;
 IF p_facts->>'refundCursor' IS NOT NULL AND (p_facts->>'refundCursor' !~ '^re_[A-Za-z0-9]+$'
  OR p_facts->>'refundCursor'=a.refund_cursor) THEN RAISE EXCEPTION 'STRIPE_REFUND_CURSOR_INVALID'; END IF;
 before_projection:=public.stripe_order_payment_projection_internal(o.id);
 SELECT coalesce(array_agg(ou."user"),'{}'::uuid[]) INTO before_users FROM public.occasion_users ou WHERE ou.occasion=o.occasion;
 INSERT INTO eshop.stripe_event_inbox(connection_id,event_id,body_sha256,event_type,provider_created_at)
 VALUES(c.id,p_event->>'id',p_event->>'bodyHash',p_event->>'type',to_timestamp((p_event->>'created')::bigint));
 FOR fact IN SELECT value FROM jsonb_array_elements(p_facts->'movements') LOOP
  IF fact->>'kind' IS NULL OR fact->>'kind' NOT IN ('payment','refund') OR fact->>'currency' IS DISTINCT FROM a.currency
   OR (fact->>'amountMinor')::numeric IS NULL OR (fact->>'amountMinor')::numeric<>trunc((fact->>'amountMinor')::numeric)
   OR (fact->>'amountMinor')::bigint NOT BETWEEN 1 AND a.amount_minor
   OR (fact->>'kind'='payment' AND (fact->>'providerId' IS DISTINCT FROM p_facts->>'paymentIntentId' OR fact->>'providerId' !~ '^pi_[A-Za-z0-9]+$' OR (fact->>'amountMinor')::bigint<>a.amount_minor))
   OR (fact->>'kind'='refund' AND (fact->>'providerId' IS NULL OR fact->>'providerId' !~ '^re_[A-Za-z0-9]+$'))
   OR (fact->>'occurredAt')::bigint IS NULL OR (fact->>'occurredAt')::bigint<0 THEN RAISE EXCEPTION 'STRIPE_MOVEMENT_INVALID'; END IF;
  SELECT * INTO movement FROM eshop.stripe_payment_movements WHERE connection_id=c.id AND provider_id=fact->>'providerId' AND kind=fact->>'kind';
  IF FOUND THEN
   IF movement.attempt_id<>a.id OR movement.amount_minor<>(fact->>'amountMinor')::bigint OR movement.currency<>a.currency
    OR movement.occurred_at<>to_timestamp((fact->>'occurredAt')::bigint) THEN RAISE EXCEPTION 'STRIPE_MOVEMENT_CHANGED'; END IF;
  ELSE
   INSERT INTO eshop.stripe_payment_movements(connection_id,provider_id,attempt_id,kind,amount_minor,currency,occurred_at)
   VALUES(c.id,fact->>'providerId',a.id,fact->>'kind',(fact->>'amountMinor')::bigint,a.currency,to_timestamp((fact->>'occurredAt')::bigint));
   changed:=true;
  END IF;
 END LOOP;
 FOR fact IN SELECT value FROM jsonb_array_elements(p_facts->'disputes') LOOP
  IF fact->>'providerId' IS NULL OR fact->>'providerId' !~ '^(dp|du)_[A-Za-z0-9]+$'
   OR (fact->>'amountMinor')::bigint NOT BETWEEN 1 AND a.amount_minor OR fact->>'currency' IS DISTINCT FROM a.currency
   OR fact->>'status' IS NULL OR fact->>'status' NOT IN ('warning_needs_response','warning_under_review','warning_closed','needs_response','under_review','won','lost') THEN
   RAISE EXCEPTION 'STRIPE_DISPUTE_INVALID'; END IF;
  SELECT * INTO d FROM eshop.stripe_disputes WHERE connection_id=c.id AND provider_id=fact->>'providerId';
  IF FOUND AND (d.attempt_id<>a.id OR d.amount_minor<>(fact->>'amountMinor')::bigint) THEN RAISE EXCEPTION 'STRIPE_DISPUTE_CHANGED'; END IF;
  IF d.status IS DISTINCT FROM fact->>'status' THEN changed:=true; END IF;
  INSERT INTO eshop.stripe_disputes(connection_id,provider_id,attempt_id,amount_minor,status,observed_at)
  VALUES(c.id,fact->>'providerId',a.id,(fact->>'amountMinor')::bigint,fact->>'status',observed)
  ON CONFLICT(connection_id,provider_id) DO UPDATE SET status=excluded.status,observed_at=excluded.observed_at;
 END LOOP;
 PERFORM public.refresh_payment_info_totals_internal(pi.id);
 SELECT * INTO STRICT totals FROM public.payment_financial_totals_internal(pi.id);
 SELECT coalesce(sum(amount_minor) FILTER(WHERE kind='payment'),0)/100.0,
  coalesce(sum(amount_minor) FILTER(WHERE kind='refund'),0)/100.0 INTO card_received,card_refunded
 FROM eshop.stripe_payment_movements WHERE attempt_id=a.id;
 IF card_received*100>a.amount_minor OR card_refunded>card_received THEN RAISE EXCEPTION 'STRIPE_TOTALS_INVALID'; END IF;
 -- Actual provider money must survive a historical/manual overpayment. Hold
 -- admission and delivery for explicit resolution instead of rejecting the fact.
 financial_conflict:=totals.gross_received>pi.amount OR totals.external_received<>0;
 IF financial_conflict AND NOT EXISTS(SELECT 1 FROM eshop.stripe_admission_decisions WHERE attempt_id=a.id AND reason='financial_conflict') THEN
  UPDATE eshop.stripe_checkout_attempts SET state='action_required' WHERE id=a.id;
  INSERT INTO eshop.stripe_admission_decisions(attempt_id,reason,provider_revision) VALUES(a.id,'financial_conflict',p_event->>'id');
  UPDATE eshop.orders SET email_payment_version=email_payment_version+1 WHERE id=o.id;
  PERFORM public.cancel_order_email_intents(o.id);
  changed:=true;
 END IF;
 UPDATE eshop.stripe_checkout_attempts SET session_id=p_facts->>'sessionId',payment_intent_id=p_facts->>'paymentIntentId',refund_cursor=p_facts->>'refundCursor',
  session_lookup_cursor=NULL,session_lookup_found=NULL
 WHERE id=a.id;
 SELECT min(occurred_at) INTO payment_time FROM eshop.stripe_payment_movements WHERE attempt_id=a.id AND kind='payment';
 IF card_received>=pi.amount AND card_refunded<pi.amount AND NOT financial_conflict AND p_facts->>'refundCursor' IS NULL THEN
  IF o.state IN ('ordered','created') AND payment_time<=a.reservation_expires_at THEN
   transition:=public.update_order_and_tickets_to_paid(o.id);
   IF transition->>'code' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'STRIPE_PAID_TRANSITION_FAILED'; END IF;
   changed:=true;
  ELSIF o.state NOT IN ('paid','sent') THEN
   UPDATE eshop.stripe_checkout_attempts SET state='action_required' WHERE id=a.id;
   IF NOT EXISTS(SELECT 1 FROM eshop.stripe_admission_decisions WHERE attempt_id=a.id AND reason='late_payment') THEN
    INSERT INTO eshop.stripe_admission_decisions(attempt_id,reason,provider_revision) VALUES(a.id,'late_payment',p_event->>'id');
   END IF;
  END IF;
  UPDATE eshop.stripe_checkout_attempts SET state=CASE WHEN state='action_required' THEN state ELSE 'paid' END WHERE id=a.id;
 END IF;
 IF card_refunded>=pi.amount AND card_received>0 THEN
  IF NOT EXISTS(SELECT 1 FROM eshop.stripe_admission_decisions WHERE attempt_id=a.id AND reason='full_refund') THEN
   SELECT array_agg(t.id) INTO cancelled FROM public.get_order_tickets_internal(o.id) person JOIN eshop.tickets t ON t.id=person.id
    WHERE coalesce(t.state,'') NOT IN ('used','storno');
   PERFORM public.internal_storno_tickets_221(cancelled);
   INSERT INTO eshop.stripe_admission_decisions(attempt_id,reason,ticket_ids,provider_revision) VALUES(a.id,'full_refund',coalesce(cancelled,'{}'),p_event->>'id');
   UPDATE eshop.orders SET state='storno',email_payment_version=email_payment_version+1,updated_at=clock_timestamp() WHERE id=o.id;
   PERFORM public.cancel_order_email_intents(o.id);
   changed:=true;
  END IF;
 ELSIF totals.gross_received=0 AND p_facts->>'sessionStatus'='expired' AND o.state='ordered' THEN
  SELECT array_agg(t.id) INTO cancelled FROM public.get_order_tickets_internal(o.id) person JOIN eshop.tickets t ON t.id=person.id WHERE coalesce(t.state,'') NOT IN ('used','storno');
  PERFORM public.internal_storno_tickets_221(cancelled);
  UPDATE eshop.orders SET state='expired',email_payment_version=email_payment_version+1,updated_at=clock_timestamp() WHERE id=o.id;
  UPDATE eshop.stripe_checkout_attempts SET state='expired' WHERE id=a.id;
  PERFORM public.cancel_order_email_intents(o.id);
  changed:=true;
 END IF;
 projection:=public.stripe_order_payment_projection_internal(o.id);
 IF projection->>'admissionState' IS DISTINCT FROM before_projection->>'admissionState' AND
  (projection->>'status'='disputed' OR before_projection->>'status'='disputed'
   OR projection->'reconciliationPending'='true'::jsonb OR before_projection->'reconciliationPending'='true'::jsonb) THEN
  UPDATE eshop.orders SET email_payment_version=email_payment_version+1 WHERE id=o.id;
  INSERT INTO eshop.stripe_admission_decisions(attempt_id,reason,provider_revision)
  VALUES(a.id,CASE WHEN projection->>'status'='disputed' THEN 'dispute_hold' WHEN before_projection->>'status'='disputed' THEN 'dispute_release'
   WHEN projection->'reconciliationPending'='true'::jsonb THEN 'reconciliation_hold' ELSE 'reconciliation_release' END,p_event->>'id');
  IF projection->>'admissionState'='valid' THEN PERFORM public.enqueue_paid_order_tickets(o.id); END IF;
  changed:=true;
 END IF;
 UPDATE eshop.stripe_checkout_attempts SET last_synced_at=observed,lease_token=NULL,lease_expires_at=NULL,reconcile_failures=0,
  next_reconcile_at=clock_timestamp()+CASE WHEN refund_cursor IS NOT NULL THEN interval '10 seconds' WHEN state IN ('paid','action_required') THEN interval '1 day' ELSE interval '2 minutes' END WHERE id=a.id;
 v_receipt:=public.complete_profile_inventory_membership_mutation_v1(command,o.occasion,'inventory.order.stripe_sync',
  CASE WHEN changed THEN jsonb_build_array(jsonb_build_object('entityType','order','entityId',o.id,'operation','update',
   'safeLabel','Card payment update','changedFields',jsonb_build_array('payment','state','tickets','admission','allocations'))) ELSE '[]'::jsonb END,
  before_users,jsonb_build_object('committed',true,'payment',projection),'service');
 UPDATE eshop.stripe_event_inbox SET committed_at=clock_timestamp(),receipt=v_receipt WHERE connection_id=c.id AND event_id=p_event->>'id';
 RETURN v_receipt;
END $$;
REVOKE ALL ON FUNCTION public.ingest_stripe_payment_internal(uuid,uuid,jsonb,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ingest_stripe_payment_internal(uuid,uuid,jsonb,jsonb) TO service_role;
