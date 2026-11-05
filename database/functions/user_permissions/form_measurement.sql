-- There is no platform-wide human role. The highest existing scoped role is
-- organization_users.is_admin; get_is_admin_on_occasion resolves that same fact.
CREATE OR REPLACE FUNCTION public.form_measurement_write_rule(p_admin boolean,p_demo boolean)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT coalesce(p_admin,false) AND NOT coalesce(p_demo,true);
$$;
REVOKE ALL ON FUNCTION public.form_measurement_write_rule(boolean,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_manage_form_measurement(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.form_measurement_write_rule(public.get_is_admin_on_occasion(p_occasion),public.is_demo_occasion(p_occasion));
$$;
REVOKE ALL ON FUNCTION public.can_manage_form_measurement(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_manage_form_measurement(bigint) TO authenticated,service_role;
