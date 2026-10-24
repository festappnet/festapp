-- Trusted teardown callers (reception/ticket import) keep their own admission.
CREATE OR REPLACE FUNCTION public.delete_occasion_user(usr uuid,oc bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN PERFORM public.remove_occasion_user_domain_internal_v1(oc,usr); END $$;
REVOKE ALL ON FUNCTION public.delete_occasion_user(uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
