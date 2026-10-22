-- Shared action projection for administration and delegated order tools.
CREATE OR REPLACE FUNCTION public.get_order_allowed_actions_internal_v1(p_order bigint,p_summary jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT (coalesce(p_summary,(CASE WHEN o.state='waitlisted' OR o.source_waitlist_order_id IS NOT NULL OR EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE order_id=o.id)
    THEN public.get_waitlist_summary_internal(o.id) ELSE public.get_order_action_summary_internal(o.state) END))->'allowedActions')
    - CASE WHEN p.payment_method='stripe' THEN ARRAY['cancel','paid']::text[] ELSE ARRAY[]::text[] END
 FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=p_order;
$$;

REVOKE ALL ON FUNCTION public.get_order_allowed_actions_internal_v1(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
