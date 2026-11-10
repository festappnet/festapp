-- Actual bank/cash movements have one classification owner. A bank refund
-- retains its raw type; only the settlement classifies it as a return. Historical
-- signed manual corrections remain signed receipts. A voided cash refund stays
-- auditable in the ledger and is excluded from every financial projection.
CREATE OR REPLACE FUNCTION public.payment_transaction_movements_internal(p_payment bigint DEFAULT NULL)
RETURNS TABLE(transaction_id bigint,payment_info bigint,amount numeric,currency text,
 occurred_at timestamptz,is_refund boolean,voided boolean)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT t.id,t.payment_info,t.amount,t.currency::text,t.date::timestamptz,
  coalesce(t.transaction_type='return',false) OR s.transaction_id IS NOT NULL,
  s.voided_at IS NOT NULL
 FROM eshop.transactions t LEFT JOIN eshop.refund_settlements s ON s.transaction_id=t.id
 WHERE p_payment IS NULL OR t.payment_info=p_payment;
$$;
REVOKE ALL ON FUNCTION public.payment_transaction_movements_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- One financial projection over actual ledgers. External/manual settlement is
-- retained as its own fact; disputes are an availability hold, never a refund.
CREATE OR REPLACE FUNCTION public.payment_financial_totals_internal(p_payment bigint)
RETURNS TABLE(gross_received numeric,refunded numeric,external_received numeric,
 disputed numeric,net_received numeric,available numeric,invalid_identity boolean)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH p AS (SELECT * FROM eshop.payment_info WHERE id=p_payment),
 bank AS (SELECT
  coalesce(sum(t.amount) FILTER(WHERE NOT t.is_refund AND NOT t.voided),0) received,
  abs(coalesce(sum(t.amount) FILTER(WHERE t.is_refund AND NOT t.voided),0)) returned,
  coalesce(bool_or(t.currency IS DISTINCT FROM p.currency_code),false) invalid
  FROM p JOIN LATERAL public.payment_transaction_movements_internal(p.id) t ON true),
 provider_raw AS (SELECT CASE WHEN NOT public.payment_method_is_online_internal(payment_method) THEN '{}'::jsonb
   ELSE public.provider_financial_totals_internal(payment_method,id) END facts FROM p),
 provider AS (SELECT coalesce((facts->>'received')::numeric,0) received,
  coalesce((facts->>'returned')::numeric,0) returned,coalesce((facts->>'invalid')::boolean,false) invalid FROM provider_raw),
 holds AS (SELECT coalesce((facts->>'held')::numeric,0) held FROM provider_raw),
 totals AS (SELECT bank.received+provider.received gross,bank.returned+provider.returned returned,
  coalesce(p.paid_externally,0) external,holds.held,bank.invalid OR provider.invalid invalid
  FROM p CROSS JOIN bank CROSS JOIN provider CROSS JOIN holds)
 -- The legacy external field has no attributable movement identity/date.
 -- Preserve it explicitly, without guessing whether it overlaps stored paid.
 SELECT gross,returned,external,held,gross-returned,
  greatest(gross-returned-held,0),invalid FROM totals;
$$;
REVOKE ALL ON FUNCTION public.payment_financial_totals_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.refresh_payment_info_totals_internal(p_payment bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE totals record;
BEGIN
 PERFORM 1 FROM eshop.payment_info WHERE id=p_payment FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'PAYMENT_INFO_NOT_FOUND'; END IF;
 SELECT * INTO STRICT totals FROM public.payment_financial_totals_internal(p_payment);
 IF totals.invalid_identity THEN RAISE EXCEPTION 'PAYMENT_FACT_IDENTITY_MISMATCH'; END IF;
 UPDATE eshop.payment_info SET paid=totals.gross_received,returned=totals.refunded WHERE id=p_payment;
 -- paid_externally is deliberately not rewritten or converted into a bank movement.
END $$;
REVOKE ALL ON FUNCTION public.refresh_payment_info_totals_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Call only while holding the canonical order/payment locks. Corrections and
-- unpairing may not consume funds already promised by an issued instruction.
CREATE OR REPLACE FUNCTION public.assert_payment_refund_reservations_internal(p_payment bigint,p_removed numeric DEFAULT 0)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE reserved numeric; facts record;
BEGIN
 SELECT coalesce(sum(amount),0) INTO reserved FROM eshop.refund_requests
 WHERE payment_info=p_payment AND status IN ('pending','processing','unknown');
 IF reserved=0 THEN RETURN; END IF;
 SELECT * INTO STRICT facts FROM public.payment_financial_totals_internal(p_payment);
 IF facts.invalid_identity OR facts.net_received-facts.disputed-p_removed<reserved THEN
  RAISE EXCEPTION 'PAYMENT_REFUND_RESERVATION_CONFLICT';
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.assert_payment_refund_reservations_internal(bigint,numeric) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.check_order_refund_delete_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM eshop.refund_requests WHERE order_id=p_order)
 OR EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.transactions t ON t.payment_info=o.payment_info
   JOIN eshop.refund_settlements s ON s.transaction_id=t.id WHERE o.id=p_order) THEN
  RAISE EXCEPTION 'ORDER_HAS_REFUND_HISTORY';
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_order_refund_delete_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
