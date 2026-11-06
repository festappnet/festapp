-- One financial projection over actual ledgers. External/manual settlement is
-- retained as its own fact; disputes are an availability hold, never a refund.
CREATE OR REPLACE FUNCTION public.payment_financial_totals_internal(p_payment bigint)
RETURNS TABLE(gross_received numeric,refunded numeric,external_received numeric,
 disputed numeric,net_received numeric,available numeric,invalid_identity boolean)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 WITH p AS (SELECT * FROM eshop.payment_info WHERE id=p_payment),
 bank AS (SELECT
  coalesce(sum(t.amount) FILTER(WHERE t.transaction_type IS DISTINCT FROM 'return'),0) received,
  abs(coalesce(sum(t.amount) FILTER(WHERE t.transaction_type='return'),0)) returned,
  coalesce(bool_or(t.currency IS DISTINCT FROM p.currency_code),false) invalid
  FROM p JOIN eshop.transactions t ON t.payment_info=p.id),
 provider_raw AS (SELECT CASE WHEN payment_method='bank' THEN '{}'::jsonb
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
