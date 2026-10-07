-- Released G3 boundary. Current UI uses the version-bearing typed command.
CREATE OR REPLACE FUNCTION public.delete_occasion_user(usr uuid,oc bigint)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 IF NOT(public.get_is_manager_on_occasion(oc) OR public.get_is_admin_on_occasion(oc)) THEN RAISE insufficient_privilege USING MESSAGE='occasion manager required'; END IF;
 PERFORM public.remove_occasion_user_domain_internal_v1(oc,usr);
END $$;
