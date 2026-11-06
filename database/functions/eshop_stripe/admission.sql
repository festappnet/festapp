-- Used by every server-side admission writer. Bank tickets retain their current
-- configured online/offline policy; card tickets require a current SQL decision.
CREATE OR REPLACE FUNCTION public.stripe_ticket_requires_online_internal(p_ticket bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.provider_ticket_requires_online_internal(p_ticket);
$$;
CREATE OR REPLACE FUNCTION public.stripe_ticket_admission_allowed_internal(p_ticket bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.provider_ticket_admission_allowed_internal(p_ticket);
$$;
REVOKE ALL ON FUNCTION public.stripe_ticket_requires_online_internal(bigint),public.stripe_ticket_admission_allowed_internal(bigint)
 FROM PUBLIC,anon,authenticated,service_role;
