-- Mechanical compatibility for issued <=0.20.590 clients and their cached PWAs.
-- Remove once supported clients all send unit context. Ambiguity never picks a unit.
CREATE OR REPLACE FUNCTION public.released_bank_unit_internal(p_account bigint DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE units bigint[];
BEGIN
 SELECT array_agg(u.id ORDER BY u.id) INTO units FROM public.units u
 WHERE public.can_manage_unit_bank_accounts(u.id) AND NOT public.is_demo_unit(u.id)
 AND (p_account IS NULL OR EXISTS(SELECT 1 FROM eshop.unit_bank_accounts l WHERE l.unit=u.id AND l.bank_account=p_account));
 IF coalesce(cardinality(units),0)<>1 THEN
  RAISE insufficient_privilege USING MESSAGE='PAYMENT_BANK_SCOPE_REQUIRED'; END IF;
 RETURN units[1];
END $$;
REVOKE ALL ON FUNCTION public.released_bank_unit_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.get_my_admin_bank_accounts()
RETURNS TABLE (
    id bigint,
    account_number text,
    account_number_human_readable text,
    title text,
    creditor_name text,
    type text,
    token_masked text,
    token_expiry_date timestamptz,
    supported_currencies text[],
    linked_units text[],
    last_fetch_time timestamptz,
    last_fio_fetch_time timestamptz,
    bank_sync jsonb
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT * FROM public.get_linkable_bank_accounts(public.released_bank_unit_internal());
$$;
REVOKE ALL ON FUNCTION public.get_my_admin_bank_accounts() FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_my_admin_bank_accounts() TO authenticated;
CREATE OR REPLACE FUNCTION public.get_bank_transaction_history(p_bank_account_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF NOT public.can_read_bank_transactions(p_bank_account_id) THEN RAISE insufficient_privilege; END IF;
 RETURN public.get_bank_transaction_history(p_bank_account_id,public.released_bank_unit_internal(p_bank_account_id));
END $$;
REVOKE ALL ON FUNCTION public.get_bank_transaction_history(bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_bank_transaction_history(bigint) TO authenticated;
