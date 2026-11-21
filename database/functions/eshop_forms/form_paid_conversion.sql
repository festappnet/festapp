CREATE OR REPLACE FUNCTION public.form_paid_conversion_eligible_internal(p_order bigint)
RETURNS boolean LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE
 o eshop.orders;
 payment eshop.payment_info;
 totals record;
 eligible_bank_received numeric;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 IF o.form IS NULL OR (o.state IN ('paid','sent')) IS NOT TRUE OR coalesce(o.price,0)<=0
  OR coalesce(trim(o.currency_code),'') !~ '^[A-Z]{3}$'
  OR NOT EXISTS(SELECT FROM public.form_measurement_decision_internal(o.form) d WHERE d.conversion_eligible)
 THEN RETURN false; END IF;

 SELECT * INTO payment FROM eshop.payment_info WHERE id=o.payment_info;
 IF payment.amount IS DISTINCT FROM o.price OR payment.currency_code IS DISTINCT FROM o.currency_code
  OR payment.payment_method IS NULL THEN RETURN false; END IF;

 SELECT * INTO totals FROM public.payment_financial_totals_internal(payment.id);
 IF totals.invalid_identity IS DISTINCT FROM false OR coalesce(totals.available,0)<o.price THEN RETURN false; END IF;

 IF payment.payment_method='bank' THEN
  -- Cash and administrative settlements cannot complete a qualifying purchase.
  SELECT coalesce(sum(m.amount),0) INTO eligible_bank_received
  FROM public.payment_transaction_movements_internal(payment.id) m
  JOIN eshop.transactions t ON t.id=m.transaction_id
  JOIN eshop.bank_accounts b ON b.id=t.bank_account_id
  WHERE NOT m.is_refund AND NOT m.voided AND upper(b.type)<>'CASH'
    AND t.transaction_type IS DISTINCT FROM 'manual' AND t.ingest_source IS DISTINCT FROM 'manual';
  IF eligible_bank_received-totals.refunded<o.price THEN RETURN false; END IF;
 ELSIF NOT public.payment_method_is_online_internal(payment.payment_method) THEN
  RETURN false;
 END IF;

 RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.form_paid_conversion_eligible_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
