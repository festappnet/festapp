-- Used by every server-side admission writer. Bank tickets retain their current
-- configured online/offline policy; card tickets require a current SQL decision.
CREATE OR REPLACE FUNCTION public.stripe_ticket_requires_online_internal(p_ticket bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders o ON o.id=x."order"
  JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE x.ticket=p_ticket AND pi.payment_method='stripe');
$$;
CREATE OR REPLACE FUNCTION public.stripe_ticket_admission_allowed_internal(p_ticket bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket x JOIN eshop.orders o ON o.id=x."order"
  JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE x.ticket=p_ticket AND pi.payment_method='stripe'
  AND public.stripe_order_payment_projection_internal(o.id)->>'admissionState' IS DISTINCT FROM 'valid');
$$;
REVOKE ALL ON FUNCTION public.stripe_ticket_requires_online_internal(bigint),public.stripe_ticket_admission_allowed_internal(bigint)
 FROM PUBLIC,anon,authenticated,service_role;
