-- Preserve the canonical authenticated bank writer across recreation; live two-role and payment-policy checks remain inside.

-- SOURCE: user_permissions/bank_operations.sql
-- Account management requires both account administration and management of a
-- linked unit. Unit administration never grants bank administration implicitly.
CREATE OR REPLACE FUNCTION public.bank_account_write_rule(p_admin boolean,p_unit_manager boolean,p_demo boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT public.active_membership(p_admin AND p_unit_manager,p_demo);
$$;
REVOKE ALL ON FUNCTION public.bank_account_write_rule(boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.bank_account_write_rule(boolean,boolean,boolean) TO postgres;

CREATE OR REPLACE FUNCTION public.get_is_admin_on_bank_account(p_bank_account bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM eshop.bank_account_users m
 WHERE m.bank_account=p_bank_account AND m."user"=auth.uid() AND m.is_admin);
$$;
REVOKE ALL ON FUNCTION public.get_is_admin_on_bank_account(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_is_admin_on_bank_account(bigint) TO authenticated,service_role;

-- Personal bank-statement read authority is independent of a live unit link.
-- Order read access alone never grants this operation.
CREATE OR REPLACE FUNCTION public.can_read_bank_transactions(p_bank_account bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_is_admin_on_bank_account(p_bank_account);
$$;
REVOKE ALL ON FUNCTION public.can_read_bank_transactions(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_bank_transactions(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_manage_bank_account(p_bank_account bigint)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 RETURN (
 SELECT public.bank_account_write_rule(public.get_is_admin_on_bank_account(p_bank_account),
 EXISTS(SELECT 1 FROM eshop.unit_bank_accounts link JOIN public.unit_users membership
   ON membership.unit=link.unit AND membership."user"=auth.uid() AND membership.is_manager
   WHERE link.bank_account=p_bank_account AND NOT EXISTS(
     SELECT 1 FROM public.demo_unit_ids_internal() demo WHERE demo.unit_id=membership.unit)),
 public.is_demo_bank_account(p_bank_account))
 );
END;
$$;
REVOKE ALL ON FUNCTION public.can_manage_bank_account(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_manage_bank_account(bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_link_bank_account_to_unit(p_bank_account bigint,p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.bank_account_write_rule(public.get_is_admin_on_bank_account(p_bank_account),
   public.get_is_manager_on_unit(p_unit),public.is_demo_bank_account(p_bank_account));
$$;
REVOKE ALL ON FUNCTION public.can_link_bank_account_to_unit(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_link_bank_account_to_unit(bigint,bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.bank_account_users_read_rule(p_admin boolean,p_support boolean,p_unit_manager boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT coalesce(p_admin,false) OR coalesce(p_support,false) OR coalesce(p_unit_manager,false);
$$;
REVOKE ALL ON FUNCTION public.bank_account_users_read_rule(boolean,boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.bank_account_users_read_rule(boolean,boolean,boolean) TO postgres;
CREATE OR REPLACE FUNCTION public.can_read_bank_account_users(p_bank_account bigint,p_unit bigint DEFAULT NULL)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT (p_unit IS NULL OR EXISTS(SELECT 1 FROM eshop.unit_bank_accounts link
   WHERE link.bank_account=p_bank_account AND link.unit=p_unit))
 AND public.bank_account_users_read_rule(
  EXISTS(SELECT 1 FROM eshop.bank_account_users m WHERE m.bank_account=p_bank_account AND m."user"=auth.uid() AND m.is_admin),
  EXISTS(SELECT 1 FROM eshop.bank_account_users m WHERE m.bank_account=p_bank_account AND m."user"=auth.uid() AND m.is_support),
  p_unit IS NOT NULL AND public.get_is_manager_on_unit(p_unit));
$$;
REVOKE ALL ON FUNCTION public.can_read_bank_account_users(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_bank_account_users(bigint,bigint) TO authenticated,service_role;

-- The demo migration recreated the details writer after the old grants. Keep
-- the supported application entry points explicit, with live policy inside.
REVOKE ALL ON FUNCTION public.update_bank_account_user(bigint,text,boolean,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_bank_account_user(bigint,text,boolean,boolean) TO authenticated,service_role;

-- Existing fetch-transactions compatibility endpoint: resolve the actual
-- occasion, require its unit manager, then return only bank-authorized data.
-- Each affected account uses the same live two-role owner as BankSync manage.
CREATE OR REPLACE FUNCTION public.get_bank_sync_connections_for_occasion(p_link text)
RETURNS TABLE(connection_id bigint,remote_bank_account_id text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE target_unit bigint; target_occasion bigint;
BEGIN
 SELECT o.id,o.unit INTO target_occasion,target_unit FROM public.occasions o WHERE o.link=p_link FOR SHARE;
 IF auth.uid() IS NULL OR target_occasion IS NULL OR public.is_demo_occasion(target_occasion)
   OR NOT public.can_manage_unit_bank_accounts(target_unit) THEN
   RAISE insufficient_privilege USING MESSAGE='bank account and unit administration required';
 END IF;
 RETURN QUERY SELECT DISTINCT c.id,c.remote_bank_account_id
 FROM eshop.bank_sync_connections c JOIN eshop.unit_bank_accounts link
   ON link.bank_account=c.bank_account_id OR link.bank_account IN
     (SELECT a.bank_account_id FROM eshop.bank_sync_account_aliases a WHERE a.connection_id=c.id)
 JOIN eshop.bank_account_users membership ON membership.bank_account=link.bank_account
   AND membership."user"=auth.uid()
 LEFT JOIN (SELECT DISTINCT d.bank_account FROM public.demo_occasions d) protected
   ON protected.bank_account=link.bank_account
 WHERE link.unit=target_unit AND c.state IN ('connected','degraded') AND c.mode='api'
   AND c.legacy_blocked_at IS NOT NULL
   -- The single unit admission above established the live manager fact for
   -- this actual link. Keep account facts set based, without per-row RPCs.
   AND public.bank_account_write_rule(membership.is_admin,true,protected.bank_account IS NOT NULL);
END $$;
REVOKE ALL ON FUNCTION public.get_bank_sync_connections_for_occasion(text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_bank_sync_connections_for_occasion(text) TO authenticated;

-- SOURCE: eshop_bank_accounts/update_bank_account.sql
DROP FUNCTION IF EXISTS public.update_bank_account(bigint,text,text,text,text[]);
DROP FUNCTION IF EXISTS public.update_bank_account(bigint,text,text,text,text[],text,bigint);
DROP FUNCTION IF EXISTS public.update_bank_account(bigint,text,text,text,text[],text,bigint,text);

CREATE OR REPLACE FUNCTION public.update_bank_account(
    p_id bigint,
    p_account_number text,
    p_title text,
    p_type text DEFAULT 'FIO',
    p_supported_currencies text[] DEFAULT NULL,
    p_account_number_human_readable text DEFAULT NULL,
    p_unit_id bigint DEFAULT NULL,
    p_creditor_name text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_id bigint;
    v_account_number text;
    v_operation_id uuid;
    v_request jsonb;
BEGIN
    PERFORM public.require_bank_authoring_scope_internal(p_id,p_unit_id);
    PERFORM public.check_bank_account_writable(p_id);
    -- Prevent manual manipulation of CASH accounts
    IF p_type = 'CASH' THEN
        RAISE EXCEPTION 'CASH_ACCOUNT_MANUAL_UPDATE_FORBIDDEN';
    END IF;

    IF char_length(p_title)>120 THEN RAISE EXCEPTION 'BANK_ACCOUNT_TITLE_TOO_LONG'; END IF;

    -- Input normalization
    v_account_number := TRIM(p_account_number);

    IF p_id IS NULL THEN
        -- A new account has no account admin yet: a managed target unit is
        -- mandatory, and creation grants the second role atomically below.
        IF p_unit_id IS NULL THEN
            RAISE EXCEPTION 'A managed unit is required to create a bank account.' USING ERRCODE='42501';
        END IF;
        IF NOT public.can_manage_unit_bank_accounts(p_unit_id) THEN
            RAISE insufficient_privilege USING MESSAGE='User is not manager.';
        END IF;

        -- Check for duplicate account number on insert
        IF EXISTS (SELECT 1 FROM eshop.bank_accounts WHERE account_number = v_account_number) THEN
             RAISE EXCEPTION 'ACCOUNT_NUMBER_EXISTS';
        END IF;

        INSERT INTO eshop.bank_accounts (account_number, title, type, supported_currencies, account_number_human_readable, creditor_name)
        VALUES (v_account_number, p_title, p_type, p_supported_currencies, p_account_number_human_readable, nullif(trim(p_creditor_name), ''))
        RETURNING id INTO v_id;

        -- Automatically make the creator an Admin
        INSERT INTO eshop.bank_account_users (bank_account, "user", is_admin)
        VALUES (v_id, auth.uid(), true);

        -- Automatically link to unit if provided
        IF p_unit_id IS NOT NULL THEN
             INSERT INTO eshop.unit_bank_accounts (unit, bank_account, priority)
             VALUES (p_unit_id, v_id, 0);
        END IF;
    ELSE
        -- Check for duplicate account number on update (exclude current id)
        IF EXISTS (SELECT 1 FROM eshop.bank_accounts WHERE account_number = v_account_number AND id != p_id) THEN
             RAISE EXCEPTION 'ACCOUNT_NUMBER_EXISTS';
        END IF;

        -- Security Check: Caller must be an Admin of the bank account
        IF NOT public.can_manage_bank_account(p_id) THEN
            RAISE EXCEPTION 'Permission denied: Only bank account admins can update details.' USING ERRCODE='42501';
        END IF;

        PERFORM 1 FROM eshop.bank_accounts WHERE id=p_id FOR UPDATE;
        IF EXISTS (SELECT 1 FROM eshop.bank_sync_connections WHERE bank_account_id=p_id)
          AND EXISTS (SELECT 1 FROM eshop.bank_accounts WHERE id=p_id
            AND (account_number IS DISTINCT FROM v_account_number OR type IS DISTINCT FROM p_type)) THEN
          RAISE EXCEPTION 'BANK_SYNC_ACCOUNT_IDENTITY_IMMUTABLE';
        END IF;
        IF EXISTS(SELECT 1 FROM eshop.payment_reference_accounts a JOIN eshop.payment_reference_namespaces n ON n.id=a.namespace_id
          WHERE a.bank_account_id=p_id AND (n.canonical_account IS DISTINCT FROM public.canonical_payment_reference_account_internal(v_account_number)
           OR p_type='CASH')) THEN RAISE EXCEPTION 'PAYMENT_REFERENCE_ACCOUNT_IDENTITY_IMMUTABLE'; END IF;
        UPDATE eshop.bank_accounts
        SET
            account_number = v_account_number,
            title = p_title,
            type = p_type,
            supported_currencies = p_supported_currencies,
            account_number_human_readable = p_account_number_human_readable,
            creditor_name = nullif(trim(p_creditor_name), ''),
            updated_at = NOW()
        WHERE id = p_id
        RETURNING id INTO v_id;
    END IF;
    -- Local details and the durable remote update intent commit together.
    IF p_id IS NOT NULL AND EXISTS(SELECT 1 FROM eshop.bank_sync_connections WHERE bank_account_id=v_id) THEN
      v_operation_id := gen_random_uuid();
      v_request := jsonb_build_object('operation','update_details','operation_id',v_operation_id,'account_id',v_id);
      INSERT INTO eshop.bank_sync_operations(id,bank_account_id,actor,operation,payload_sha256,state,request)
        VALUES(v_operation_id,v_id,auth.uid(),'update_details',encode(extensions.digest(v_request::text,'sha256'),'hex'),'pending',v_request);
    END IF;
    RETURN v_id;
END;
$$;

ALTER FUNCTION public.update_bank_account(bigint,text,text,text,text[],text,bigint,text) OWNER TO postgres;

-- Keep the supported writer ACL with its declaration across every recreation.
REVOKE ALL ON FUNCTION public.update_bank_account(bigint,text,text,text,text[],text,bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_bank_account(bigint,text,text,text,text[],text,bigint,text) TO authenticated,service_role;
