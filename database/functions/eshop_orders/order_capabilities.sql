-- One capability projection for order readers. Domain writers still enforce
-- the same invariants under locks; clients never infer actions from a price.
CREATE OR REPLACE FUNCTION public.get_order_allowed_actions_internal(p_order bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT CASE
 WHEN o.state='waitlisted' THEN jsonb_build_array('view','note','offer','withdraw')
 WHEN o.state='stock' THEN jsonb_build_array('view')
 WHEN o.state IN ('storno','preparing_payment') THEN jsonb_build_array('view')
 WHEN EXISTS(SELECT 1 FROM eshop.ticket_batch_items i JOIN eshop.tickets t ON t.id=i.ticket_id
   WHERE i.sale_order_id=o.id AND t.state<>'storno') THEN jsonb_build_array('view','note','cancel','send')
 WHEN o.state='ordered' THEN jsonb_build_array('view','note','edit','cancel','paid')
 ELSE jsonb_build_array('view','note','edit','cancel','send') END
 FROM eshop.orders o WHERE o.id=p_order;
$$;
REVOKE ALL ON FUNCTION public.get_order_allowed_actions_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
