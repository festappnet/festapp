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

CREATE OR REPLACE FUNCTION public.can_manage_bank_account(p_bank_account bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.bank_account_write_rule(public.get_is_admin_on_bank_account(p_bank_account),
 EXISTS(SELECT 1 FROM eshop.unit_bank_accounts link JOIN public.unit_users membership
   ON membership.unit=link.unit AND membership."user"=auth.uid() AND membership.is_manager
   WHERE link.bank_account=p_bank_account AND NOT EXISTS(
     SELECT 1 FROM public.demo_unit_ids_internal() demo WHERE demo.unit_id=membership.unit)),
 public.is_demo_bank_account(p_bank_account));
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
REVOKE ALL ON FUNCTION public.update_bank_account(bigint,text,text,text,text[],text,bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_bank_account(bigint,text,text,text,text[],text,bigint,text) TO authenticated,service_role;
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
