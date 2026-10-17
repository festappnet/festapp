CREATE OR REPLACE FUNCTION public.canonical_payment_reference_account_internal(p_account text)
RETURNS text LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE account text:=upper(regexp_replace(coalesce(p_account,''),'[[:space:]]','','g'));
 parts text[]; bban text; digits text; checksum integer;
BEGIN
 parts:=regexp_match(account,'^(?:([0-9]{1,6})-)?([0-9]{1,10})/([0-9]{4})$');
 IF parts IS NOT NULL THEN
  bban:=parts[3]||lpad(coalesce(parts[1],'0'),6,'0')||lpad(parts[2],10,'0');
  checksum:=98-mod((bban||'123500')::numeric,97)::integer;
  account:='CZ'||lpad(checksum::text,2,'0')||bban;
 END IF;
 IF account='' OR NOT public.is_valid_iban(account) THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_ACCOUNT_INVALID'; END IF;
 RETURN account;
END $$;
CREATE OR REPLACE FUNCTION public.payment_reference_scope_enabled_internal(p_form bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM eshop.payment_reference_scopes s JOIN public.occasions o ON o.organization=s.organization_id
 JOIN public.forms f ON f.occasion=o.id WHERE f.id=p_form AND s.phase IN ('active','paused'));
$$;
CREATE OR REPLACE FUNCTION public.enroll_payment_reference_account(p_bank_account bigint)
RETURNS text LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE account text; namespace text; existing text;
BEGIN
 PERFORM public.require_service_role();
 PERFORM public.check_bank_account_writable(p_bank_account);
 SELECT account_number INTO STRICT account FROM eshop.bank_accounts WHERE id=p_bank_account AND type IS DISTINCT FROM 'CASH' FOR UPDATE;
 namespace:=encode(extensions.digest(public.canonical_payment_reference_account_internal(account),'sha256'),'hex');
 INSERT INTO eshop.payment_reference_namespaces(id,canonical_account)
 VALUES(namespace,public.canonical_payment_reference_account_internal(account)) ON CONFLICT DO NOTHING;
 INSERT INTO eshop.payment_reference_accounts(bank_account_id,namespace_id,account_number_snapshot)
 VALUES(p_bank_account,namespace,account) ON CONFLICT DO NOTHING;
 SELECT namespace_id INTO existing FROM eshop.payment_reference_accounts WHERE bank_account_id=p_bank_account;
 IF existing<>namespace THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_ACCOUNT_IDENTITY_IMMUTABLE'; END IF;
 RETURN namespace;
END $$;
REVOKE ALL ON FUNCTION public.canonical_payment_reference_account_internal(text),public.payment_reference_scope_enabled_internal(bigint)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.enroll_payment_reference_account(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.enroll_payment_reference_account(bigint) TO service_role;

-- Inventory only: malformed unrelated accounts must not break grouping. Issuing
-- always calls the strict validator above and never falls back to an ID/string.
CREATE OR REPLACE FUNCTION public.try_payment_reference_account_internal(p_account text)
RETURNS text LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN RETURN public.canonical_payment_reference_account_internal(p_account);
EXCEPTION WHEN OTHERS THEN RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION public.try_payment_reference_account_internal(text) FROM PUBLIC,anon,authenticated,service_role;
