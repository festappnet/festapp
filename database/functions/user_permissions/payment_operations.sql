-- Typed operations bind scope from stored orders, never a caller-supplied unit.
CREATE OR REPLACE FUNCTION public.can_record_order_cash(p_order bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT public.get_is_manager_on_unit(oc.unit) AND NOT public.is_demo_occasion(o.occasion)
 FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion WHERE o.id=p_order),false);
$$;
CREATE OR REPLACE FUNCTION public.can_prepare_order_bank_refund(p_order bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT public.can_manage_bank_account(pi.bank_account) AND public.get_is_manager_on_unit(oc.unit)
 AND EXISTS(SELECT 1 FROM eshop.unit_bank_accounts link WHERE link.unit=oc.unit AND link.bank_account=pi.bank_account)
 AND NOT public.is_demo_occasion(o.occasion)
 FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE o.id=p_order),false);
$$;
CREATE OR REPLACE FUNCTION public.can_prepare_order_provider_refund(p_order bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.can_record_order_cash(p_order);
$$;
REVOKE ALL ON FUNCTION public.can_record_order_cash(bigint),public.can_prepare_order_bank_refund(bigint),public.can_prepare_order_provider_refund(bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.can_record_order_cash(bigint),public.can_prepare_order_bank_refund(bigint),public.can_prepare_order_provider_refund(bigint) TO authenticated;
