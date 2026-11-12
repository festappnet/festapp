-- Shared connection administration identity; connector commands retain their
-- established error messages and demo guards.
CREATE OR REPLACE FUNCTION public.payment_provider_unit_manager_internal(p_unit bigint,p_actor uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT p_actor IS NOT NULL AND EXISTS(SELECT 1 FROM public.units u JOIN public.unit_users uu ON uu.unit=u.id
 JOIN public.user_info i ON i.id=uu."user" AND i.organization=u.organization
 WHERE u.id=p_unit AND uu."user"=p_actor AND uu.is_manager);
$$;
REVOKE ALL ON FUNCTION public.payment_provider_unit_manager_internal(bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Consecutive transport failures, counted by the existing connector workers.
CREATE OR REPLACE FUNCTION public.payment_provider_connection_failure_threshold_internal()
RETURNS integer LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$ SELECT 3; $$;
REVOKE ALL ON FUNCTION public.payment_provider_connection_failure_threshold_internal() FROM PUBLIC,anon,authenticated,service_role;
