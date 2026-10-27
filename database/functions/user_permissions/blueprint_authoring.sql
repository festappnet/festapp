-- The same private expression rules serve ordinary and trusted resource callers.
CREATE OR REPLACE FUNCTION public.can_write_blueprints_as_actor_internal_v1(p_actor uuid,p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT p_actor IS NOT NULL AND public.blueprint_write_rule(
  public.active_membership((SELECT is_editor FROM public.occasion_users WHERE occasion=p_occasion AND "user"=p_actor),public.is_demo_occasion(p_occasion)),
  public.active_membership((SELECT is_manager FROM public.occasion_users WHERE occasion=p_occasion AND "user"=p_actor),public.is_demo_occasion(p_occasion)));
$$;
REVOKE ALL ON FUNCTION public.can_write_blueprints_as_actor_internal_v1(uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.can_write_blueprints(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.can_write_blueprints_as_actor_internal_v1(auth.uid(),p_occasion);
$$;
REVOKE ALL ON FUNCTION public.can_write_blueprints(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_write_blueprints(bigint) TO authenticated,service_role;
