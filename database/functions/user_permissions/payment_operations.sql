CREATE OR REPLACE FUNCTION public.payment_operation_permissions_internal(p_orders bigint[])
RETURNS TABLE(order_id bigint,can_record_cash boolean,can_refund_bank boolean,can_refund_provider boolean)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 RETURN QUERY
 WITH orders AS MATERIALIZED (
  SELECT o.id,o.occasion,oc.unit,pi.bank_account
  FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
  LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE o.id=ANY(p_orders)
 ), units AS MATERIALIZED (
  SELECT scope.unit,public.get_is_manager_on_unit(scope.unit) manager FROM (SELECT DISTINCT o.unit FROM orders o) scope
 ), occasions AS MATERIALIZED (
  SELECT scope.occasion,public.is_demo_occasion(scope.occasion) demo FROM (SELECT DISTINCT o.occasion FROM orders o) scope
 ), banks AS MATERIALIZED (
  SELECT scope.bank_account,public.can_manage_bank_account(scope.bank_account) manager
  FROM (SELECT DISTINCT o.bank_account FROM orders o WHERE o.bank_account IS NOT NULL) scope
 ), links AS MATERIALIZED (
  SELECT scope.unit,scope.bank_account,EXISTS(SELECT 1 FROM eshop.unit_bank_accounts link
   WHERE link.unit=scope.unit AND link.bank_account=scope.bank_account) linked
  FROM (SELECT DISTINCT o.unit,o.bank_account FROM orders o) scope
 )
 SELECT o.id::bigint,coalesce(u.manager AND NOT oc.demo,false),
  coalesce(b.manager AND u.manager AND link.linked AND NOT oc.demo,false),
  coalesce(u.manager AND NOT oc.demo,false)
 FROM orders o JOIN units u ON u.unit IS NOT DISTINCT FROM o.unit
 JOIN occasions oc ON oc.occasion=o.occasion
 LEFT JOIN banks b ON b.bank_account=o.bank_account
 JOIN links link ON link.unit IS NOT DISTINCT FROM o.unit AND link.bank_account IS NOT DISTINCT FROM o.bank_account;
END;
$$;
REVOKE ALL ON FUNCTION public.payment_operation_permissions_internal(bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- Typed operations bind scope from stored orders, never a caller-supplied unit.
CREATE OR REPLACE FUNCTION public.can_record_order_cash(p_order bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT p.can_record_cash FROM public.payment_operation_permissions_internal(ARRAY[p_order]) p),false);
$$;
CREATE OR REPLACE FUNCTION public.can_prepare_order_bank_refund(p_order bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT p.can_refund_bank FROM public.payment_operation_permissions_internal(ARRAY[p_order]) p),false);
$$;
CREATE OR REPLACE FUNCTION public.can_prepare_order_provider_refund(p_order bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT p.can_refund_provider FROM public.payment_operation_permissions_internal(ARRAY[p_order]) p),false);
$$;
REVOKE ALL ON FUNCTION public.can_record_order_cash(bigint),public.can_prepare_order_bank_refund(bigint),public.can_prepare_order_provider_refund(bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.can_record_order_cash(bigint),public.can_prepare_order_bank_refund(bigint),public.can_prepare_order_provider_refund(bigint) TO authenticated;
