-- One owner for issuing payment instructions, at checkout and on repricing.
-- The authorized caller owns its transaction; no provider charge is dispatched.
CREATE OR REPLACE FUNCTION public.ensure_order_payment_instructions_internal(p_order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, extensions
AS $$
DECLARE o eshop.orders; pi eshop.payment_info; f public.forms;
 account eshop.bank_accounts; receiving_account bigint; unit_id bigint; org_id bigint;
 form_data jsonb; symbol bigint; reference text; recipient text;
BEGIN
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order_id]);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order_id FOR UPDATE;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info FOR UPDATE;
 IF pi.payment_method NOT IN ('bank','stripe') OR pi.payment_method IS NULL THEN
   RAISE EXCEPTION 'PAYMENT_METHOD_INVALID'; END IF;
 IF pi.amount IS DISTINCT FROM o.price OR pi.currency_code IS DISTINCT FROM o.currency_code THEN
   RAISE EXCEPTION 'PAYMENT_ORDER_AMOUNT_MISMATCH'; END IF;
 IF pi.payment_method='stripe' AND (pi.bank_account IS NOT NULL
   OR pi.variable_symbol IS NOT NULL OR pi.creditor_reference IS NOT NULL) THEN
   RAISE EXCEPTION 'STRIPE_BANK_INSTRUCTIONS_FORBIDDEN'; END IF;
 -- Stripe creates references/attempts through its provider lifecycle. Bank
 -- instructions must never be fabricated for a card payment or a free order.
 IF pi.amount>0 AND pi.amount>coalesce(pi.paid,0) AND pi.payment_method='bank' THEN
   SELECT * INTO STRICT f FROM public.forms WHERE id=o.form;
   SELECT unit,organization INTO unit_id,org_id FROM public.occasions WHERE id=o.occasion;
   IF pi.bank_account IS NULL THEN
     IF pi.variable_symbol IS NOT NULL OR pi.creditor_reference IS NOT NULL THEN
       RAISE EXCEPTION 'PAYMENT_RECIPIENT_REQUIRED'; END IF;
     form_data:=public.get_effective_form_data(f.id);
     IF coalesce(form_data#>'{payments,bankEnabled}','true'::jsonb)<>'true'::jsonb THEN
       RAISE EXCEPTION 'BANK_PAYMENT_NOT_CONFIGURED'; END IF;
     SELECT b.id INTO receiving_account
     FROM eshop.unit_bank_accounts uba JOIN eshop.bank_accounts b ON b.id=uba.bank_account
     WHERE uba.unit=unit_id AND (f.bank_account IS NULL OR b.id=f.bank_account)
       AND b.supported_currencies @> ARRAY[trim(pi.currency_code)]
       AND b.type IS DISTINCT FROM 'CASH'
     ORDER BY uba.priority ASC,b.id ASC LIMIT 1;
     IF receiving_account IS NULL THEN
       RAISE EXCEPTION '%',jsonb_build_object('code',1018,
         'message','No available bank account supports the required currency',
         'required_currency',pi.currency_code)::text;
     END IF;
     UPDATE eshop.payment_info SET bank_account=receiving_account WHERE id=pi.id;
     pi.bank_account:=receiving_account;
   END IF;
   SELECT * INTO STRICT account FROM eshop.bank_accounts WHERE id=pi.bank_account FOR SHARE;
   -- Existing references retain their receiving account across price changes.
   IF pi.variable_symbol IS NULL THEN
     IF NOT EXISTS(SELECT 1 FROM eshop.unit_bank_accounts uba
       WHERE uba.unit=unit_id AND uba.bank_account=account.id)
       OR NOT account.supported_currencies @> ARRAY[trim(pi.currency_code)]
       OR account.type='CASH' THEN
       RAISE EXCEPTION 'BANK_PAYMENT_NOT_CONFIGURED'; END IF;
     IF public.payment_reference_scope_enabled_internal(f.id) THEN
       symbol:=public.reserve_order_payment_reference_internal(pi.id,f.id);
     ELSE
       symbol:=public.generate_payment_variable_symbol(account.id,f.id);
     END IF;
     UPDATE eshop.payment_info SET variable_symbol=symbol WHERE id=pi.id;
     pi.variable_symbol:=symbol;
   END IF;
   recipient:=nullif(trim(account.creditor_name),'');
   IF trim(pi.currency_code)='EUR' THEN
     IF recipient IS NULL THEN
       SELECT left(trim(regexp_replace(title,'[[:space:][:cntrl:]]+',' ','g')),70)
       INTO recipient FROM public.organizations WHERE id=org_id;
     END IF;
     IF recipient IS NULL OR length(recipient) NOT BETWEEN 1 AND 70 THEN
       RAISE EXCEPTION 'EUR_CREDITOR_NAME_REQUIRED'; END IF;
     IF account.account_number IS NULL OR NOT public.is_valid_iban(account.account_number) THEN
       RAISE EXCEPTION 'EUR_VALID_IBAN_REQUIRED'; END IF;
     IF pi.creditor_reference IS NULL THEN
       reference:=public.generate_creditor_reference(pi.variable_symbol);
       UPDATE eshop.payment_info SET creditor_reference=reference WHERE id=pi.id;
       pi.creditor_reference:=reference;
     END IF;
   END IF;
 ELSIF pi.bank_account IS NOT NULL THEN
   SELECT * INTO account FROM eshop.bank_accounts WHERE id=pi.bank_account;
   recipient:=account.creditor_name;
 END IF;
 RETURN jsonb_build_object('bank_account',pi.bank_account,
   'account_number',account.account_number,'account_number_human_readable',account.account_number_human_readable,
   'creditor_name',recipient,'variable_symbol',pi.variable_symbol,'creditor_reference',pi.creditor_reference);
END;
$$;
REVOKE ALL ON FUNCTION public.ensure_order_payment_instructions_internal(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_order_payment_instructions_internal(bigint) TO postgres,service_role;
