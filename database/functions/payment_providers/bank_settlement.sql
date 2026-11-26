-- Called after verified BankSync fact persistence, never from an untrusted client.
CREATE OR REPLACE FUNCTION public.observe_bank_refund_internal(p_transaction bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE t eshop.transactions; pi eshop.payment_info; o eshop.orders; req eshop.refund_requests;
 candidates bigint[]; owner_id bigint; order_id bigint; candidate_count bigint; recipient text;
BEGIN
 SELECT * INTO STRICT t FROM eshop.transactions WHERE id=p_transaction FOR UPDATE;
 IF t.amount>=0 OR t.ingest_source NOT IN ('banksync_api','fio_api')
    OR public.is_demo_bank_account(t.bank_account_id) THEN RETURN jsonb_build_object('matched',false); END IF;
 IF EXISTS(SELECT 1 FROM eshop.refund_settlements WHERE transaction_id=t.id) THEN RETURN jsonb_build_object('matched',true,'replayed',true); END IF;
 IF t.payment_info IS NULL AND EXISTS(
  SELECT 1 FROM eshop.transaction_pairing_events WHERE transaction_snapshot_id=t.id AND method='manual_unlink'
 ) THEN RETURN jsonb_build_object('matched',false,'reason','manually_unlinked'); END IF;
 SELECT c.payment_ids INTO candidates FROM public.bank_transaction_reference_candidates_internal(t) c;
 IF coalesce(cardinality(candidates),0)<>1 THEN
  RETURN jsonb_build_object('matched',false,'reason','no_unique_reference');
 END IF;
 owner_id:=candidates[1];
 SELECT min(id),count(*) INTO order_id,candidate_count FROM eshop.orders WHERE payment_info=owner_id;
 IF candidate_count<>1 THEN RETURN jsonb_build_object('matched',false,'reason','no_unique_order'); END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[order_id]);
 SELECT * INTO o FROM eshop.orders WHERE id=order_id AND payment_info=owner_id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('matched',false); END IF;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=owner_id FOR UPDATE;
 IF pi.payment_method IS DISTINCT FROM 'bank' OR (t.payment_info IS NOT NULL AND t.payment_info<>pi.id)
    OR NOT EXISTS(SELECT 1 FROM public.bank_transaction_reference_candidates_internal(t) c WHERE c.payment_ids=candidates) THEN
  RETURN jsonb_build_object('matched',false,'reason','scope_or_reference_changed');
 END IF;
 IF t.ingest_source='banksync_api' AND EXISTS(
  SELECT 1 FROM public.bank_sync_api_review_row_internal(t.id) r WHERE r.delivery_id IS NOT NULL
   AND r.resolution->>'action' IS DISTINCT FROM 'api_distinct'
 ) THEN RETURN jsonb_build_object('matched',false,'reason','duplicate_review_required'); END IF;
 recipient:=public.try_payment_reference_account_internal(CASE WHEN t.counter_account LIKE '%/%' OR t.counter_account ~ '^[A-Za-z]{2}' THEN t.counter_account
  ELSE t.counter_account||'/'||t.bank_code END);
 -- Record a matching instruction if there is one. The movement identifies its order independently.
 SELECT * INTO req FROM eshop.refund_requests WHERE payment_info=pi.id AND method='bank'
  AND payload#>>'{instructions,recipientIban}'=recipient
  AND (t.date::date>=created_at::date OR payload->'existingDebits' @> jsonb_build_array(t.id)) ORDER BY (status IN ('pending','processing','unknown')) DESC,created_at DESC,id DESC LIMIT 1 FOR UPDATE;
 IF req.id IS NULL THEN
  IF t.date::date<(o.created_at AT TIME ZONE 'UTC')::date THEN
   RETURN jsonb_build_object('matched',false,'reason','movement_predates_order');
  END IF;
  IF t.payment_info=pi.id THEN RETURN jsonb_build_object('matched',true,'replayed',true); END IF;
  PERFORM public.apply_transaction_pairing(t.id,pi.id,'automatic_reference','service');
  RETURN jsonb_build_object('matched',true,'orderId',o.id,'requestId',NULL);
 END IF;
 UPDATE eshop.transactions SET payment_info=pi.id WHERE id=t.id;
 INSERT INTO eshop.refund_settlements(transaction_id,request_id) VALUES(t.id,req.id);
 UPDATE eshop.refund_requests SET status='succeeded',updated_at=now(),result=jsonb_build_object('transactionId',t.id,
  'actualAmount',(-t.amount)::text,'deviation',req.amount<>-t.amount OR req.status IN ('cancelled','succeeded')) WHERE id=req.id;
 INSERT INTO eshop.payment_operation_events(request_id,operation,details) VALUES(req.id,'bank_event',jsonb_build_object('transactionId',t.id,'amount',t.amount));
 INSERT INTO eshop.transaction_pairing_events(transaction_snapshot_id,transaction_id,new_payment_info_id,action,method,actor_kind,actor_id,details)
 VALUES(t.id,t.id,pi.id,'paired','refund_settlement',CASE WHEN auth.role()='service_role' THEN 'service' ELSE 'user' END,auth.uid(),jsonb_build_object('requestId',req.id));
 PERFORM public.refresh_payment_info_totals_internal(pi.id);
 PERFORM public.reconcile_order_payment_internal_v1(o.id,'refund_fact');
 PERFORM public.record_payment_fact_sync_internal(o.id);
 RETURN jsonb_build_object('matched',true,'orderId',o.id,'requestId',req.id);
END $$;
REVOKE ALL ON FUNCTION public.observe_bank_refund_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
