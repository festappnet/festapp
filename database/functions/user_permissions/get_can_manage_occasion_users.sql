-- The same actor-bound policy serves ordinary SQL callers and trusted email
-- producers. Arbitrary-actor evaluation is private to the trusted SQL owner.
CREATE OR REPLACE FUNCTION public.can_manage_occasion_users_as_actor_internal_v1(p_actor uuid,p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT public.occasion_users_write_rule(
   public.active_membership(m.is_manager,public.is_demo_occasion(o.id)),
   public.active_membership(a.is_admin,public.is_demo_occasion(o.id)),
   public.active_membership(u.is_editor,public.is_demo_unit(o.unit)))
 FROM public.occasions o
 LEFT JOIN public.occasion_users m ON m.occasion=o.id AND m."user"=p_actor
 LEFT JOIN public.organization_users a ON a.organization=o.organization AND a."user"=p_actor
 LEFT JOIN public.unit_users u ON u.unit=o.unit AND u."user"=p_actor
 WHERE o.id=p_occasion AND p_actor IS NOT NULL),false);
$$;
REVOKE ALL ON FUNCTION public.can_manage_occasion_users_as_actor_internal_v1(uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.can_manage_occasion_users_as_actor_internal_v1(uuid,bigint) TO postgres;

CREATE OR REPLACE FUNCTION public.get_can_manage_occasion_users(p_occasion_id bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.can_manage_occasion_users_as_actor_internal_v1(auth.uid(),p_occasion_id);
$$;
REVOKE ALL ON FUNCTION public.get_can_manage_occasion_users(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_can_manage_occasion_users(bigint) TO authenticated;
