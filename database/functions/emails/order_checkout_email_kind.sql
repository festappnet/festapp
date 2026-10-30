-- One lifecycle owner for checkout confirmation validity, reporting and repair.
-- A free registration is paid immediately. It still needs its configured
-- confirmation unless automatic ticket delivery replaces that message.
CREATE OR REPLACE FUNCTION public.order_checkout_email_kind_internal(p_order bigint)
RETURNS text LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT CASE WHEN o.state='ordered' OR (
   o.state='paid' AND o.price=0 AND NOT (o.data ? 'ticketBatchOrigin')
   AND NOT (coalesce(oc.is_order_synchronization_enabled,false) AND EXISTS(
     SELECT 1 FROM jsonb_array_elements(coalesce(oc.features,'[]'::jsonb)) feature
     WHERE feature->>'code'='ticket' AND (feature->>'is_enabled')::boolean IS TRUE))
 ) THEN 'order_confirmation' ELSE 'order_tickets' END
 FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion WHERE o.id=p_order;
$$;
REVOKE ALL ON FUNCTION public.order_checkout_email_kind_internal(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.order_checkout_email_kind_internal(bigint) TO service_role;
