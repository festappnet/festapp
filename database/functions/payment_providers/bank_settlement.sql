-- Called after verified BankSync fact persistence, never from an untrusted client.
CREATE OR REPLACE FUNCTION public.observe_bank_refund_internal(p_transaction bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE t eshop.transactions; pi eshop.payment_info; o eshop.orders; req eshop.refund_requests;
 ns text; owner_id bigint; recipient text; reference text; current_ns text;
BEGIN
 SELECT * INTO STRICT t FROM eshop.transactions WHERE id=p_transaction FOR UPDATE;
 IF t.amount>=0 OR t.ingest_source NOT IN ('banksync_api','fio_api') THEN RETURN jsonb_build_object('matched',false); END IF;
 IF EXISTS(SELECT 1 FROM eshop.refund_settlements WHERE transaction_id=t.id) THEN RETURN jsonb_build_object('matched',true,'replayed',true); END IF;
 SELECT a.namespace_id INTO ns FROM eshop.payment_reference_accounts a WHERE a.bank_account_id=t.bank_account_id;
 IF ns IS NULL THEN
  SELECT pa.namespace_id INTO ns FROM eshop.bank_sync_account_aliases a JOIN eshop.bank_sync_connections c ON c.id=a.connection_id
   JOIN eshop.payment_reference_accounts pa ON pa.bank_account_id=c.bank_account_id WHERE a.bank_account_id=t.bank_account_id;
 END IF;
 IF ns IS NULL THEN RETURN jsonb_build_object('matched',false); END IF;
 reference:=public.normalize_creditor_reference(t.payer_reference);
 IF t.currency='EUR' THEN
  SELECT p.id INTO owner_id FROM eshop.payment_reference_reservations r JOIN eshop.payment_info p ON p.id=r.payment_info_id
   WHERE r.namespace_id=ns AND r.original_payment_info_id=p.id AND r.variable_symbol=p.variable_symbol
    AND p.creditor_reference=reference;
 ELSE
  IF t.vs IS NULL OR trim(t.vs) !~ '^[0-9]{1,10}$' THEN RETURN jsonb_build_object('matched',false); END IF;
  SELECT r.payment_info_id INTO owner_id FROM eshop.payment_reference_reservations r
   WHERE r.namespace_id=ns AND r.variable_symbol=t.vs::bigint AND r.original_payment_info_id=r.payment_info_id;
 END IF;
 IF owner_id IS NULL THEN RETURN jsonb_build_object('matched',false); END IF;
 SELECT * INTO STRICT o FROM eshop.orders WHERE payment_info=owner_id;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[o.id]);
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=owner_id FOR UPDATE;
 IF NOT EXISTS(SELECT 1 FROM eshop.refund_requests WHERE payment_info=owner_id AND method='bank' AND reference_namespace=ns) THEN
  RETURN jsonb_build_object('matched',false); END IF;
 IF t.currency IS DISTINCT FROM trim(pi.currency_code) OR (t.payment_info IS NOT NULL AND t.payment_info<>pi.id) THEN
  RETURN jsonb_build_object('matched',false,'reason','scope_or_currency_mismatch'); END IF;
 recipient:=public.try_payment_reference_account_internal(CASE WHEN t.counter_account LIKE '%/%' OR t.counter_account ~ '^[A-Za-z]{2}' THEN t.counter_account
  ELSE t.counter_account||'/'||t.bank_code END);
 -- Destination verifies the immutable instruction; it never identifies the order.
 SELECT * INTO req FROM eshop.refund_requests WHERE payment_info=pi.id AND method='bank' AND reference_namespace=ns
  AND payload#>>'{instructions,recipientIban}'=recipient
  AND (t.date::date>=created_at::date OR payload->'existingDebits' @> jsonb_build_array(t.id)) ORDER BY (status IN ('pending','processing','unknown')) DESC,created_at DESC,id DESC LIMIT 1 FOR UPDATE;
 IF req.id IS NULL THEN RETURN jsonb_build_object('matched',false,'reason','recipient_or_date_mismatch'); END IF;
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
