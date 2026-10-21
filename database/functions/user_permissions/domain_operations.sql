-- Operation policies. Membership helpers are live facts, not cached decisions.
CREATE OR REPLACE FUNCTION public.can_read_orders(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
 SELECT public.order_read_rule(
   (SELECT ou.is_editor_order_view FROM public.occasion_users ou WHERE ou.occasion=p_occasion AND ou."user"=auth.uid()),
   public.is_demo_occasion(p_occasion),public.can_read_demo_occasion(p_occasion));
$$;
REVOKE ALL ON FUNCTION public.can_read_orders(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_read_orders(bigint) TO anon, authenticated, service_role;

-- Trusted service boundaries may carry a verified actor distinct from their
-- service JWT. The live membership fact stays in this one private SQL owner.
CREATE OR REPLACE FUNCTION public.order_editor_membership_as_actor_internal(p_actor uuid,p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER AS $$
 SELECT coalesce((SELECT m.is_editor_order FROM public.occasion_users m
   WHERE m.occasion=p_occasion AND m."user"=p_actor),false);
$$;
REVOKE ALL ON FUNCTION public.order_editor_membership_as_actor_internal(uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.order_editor_membership_as_actor_internal(uuid,bigint) TO postgres;

CREATE OR REPLACE FUNCTION public.can_write_orders_as_actor_internal(p_actor uuid,p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER AS $$
 SELECT public.order_write_rule(public.order_editor_membership_as_actor_internal(p_actor,p_occasion),
   public.is_demo_occasion(p_occasion));
$$;
REVOKE ALL ON FUNCTION public.can_write_orders_as_actor_internal(uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.can_write_orders_as_actor_internal(uuid,bigint) TO postgres;

CREATE OR REPLACE FUNCTION public.can_write_orders(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
 SELECT public.can_write_orders_as_actor_internal(auth.uid(),p_occasion);
$$;
REVOKE ALL ON FUNCTION public.can_write_orders(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_write_orders(bigint) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.can_delete_orders(p_occasion bigint)
RETURNS boolean LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
 -- The deletion writer calls this again after a resource lock. A STABLE SQL
 -- function would reuse the outer statement snapshot from before that wait.
 SELECT COALESCE((SELECT public.order_delete_rule(
   public.get_is_manager_on_unit(o.unit),public.get_is_editor_on_unit(o.unit),
   public.get_is_admin_on_occasion(o.id)) FROM public.occasions o WHERE o.id=p_occasion),false);
$$;
REVOKE ALL ON FUNCTION public.can_delete_orders(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_delete_orders(bigint) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.can_create_occasion(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
 SELECT public.occasion_create_rule(
   public.get_is_manager_on_unit(p_unit),public.get_is_editor_on_unit(p_unit));
$$;
REVOKE ALL ON FUNCTION public.can_create_occasion(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_create_occasion(bigint) TO anon, authenticated, service_role;

-- Configuration writes have always required the same unit-editor role on
-- both the current and requested unit. The UI projects the ordinary same-unit
-- case; the transactional writer supplies the actual requested target.
CREATE OR REPLACE FUNCTION public.can_edit_occasion(p_occasion bigint,p_target_unit bigint DEFAULT NULL)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
 SELECT coalesce((SELECT public.occasion_edit_rule(public.get_is_editor_on_unit(o.unit),
   public.get_is_editor_on_unit(coalesce(p_target_unit,o.unit)))
   AND target.organization=o.organization
   FROM public.occasions o JOIN public.units target ON target.id=coalesce(p_target_unit,o.unit)
   WHERE o.id=p_occasion),false);
$$;
REVOKE ALL ON FUNCTION public.can_edit_occasion(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_edit_occasion(bigint,bigint) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.can_read_map_editor_bundle(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
 -- Load this operation's two facts together, and inspect the demo registry
 -- once. A normal occasion never needs the tenant/demo-reader join.
 WITH facts AS MATERIALIZED (
   SELECT m.is_editor_view viewer,m.is_editor editor,public.is_demo_occasion(p_occasion) demo
   FROM (VALUES(1)) seed(dummy) LEFT JOIN public.occasion_users m
     ON m.occasion=p_occasion AND m."user"=auth.uid()
 )
 SELECT public.map_editor_read_rule(
   public.readable_membership(viewer,demo,CASE WHEN demo THEN public.can_read_demo_occasion(p_occasion) ELSE false END),
   public.active_membership(editor,demo)) FROM facts;
$$;
REVOKE ALL ON FUNCTION public.can_read_map_editor_bundle(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_read_map_editor_bundle(bigint) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.can_read_information_editor_bundle(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT COALESCE((public.get_is_editor_view_on_occasion(p_occasion)),false);
$$;
REVOKE ALL ON FUNCTION public.can_read_information_editor_bundle(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_read_information_editor_bundle(bigint) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.can_preview_ticket_readonly(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT COALESCE((auth.uid() IS NOT NULL AND (public.get_is_editor_on_occasion(p_occasion)
    OR public.get_is_editor_view_on_occasion(p_occasion)
    OR public.can_write_orders(p_occasion)
    OR public.can_read_orders(p_occasion))),false);
$$;
REVOKE ALL ON FUNCTION public.can_preview_ticket_readonly(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_preview_ticket_readonly(bigint) TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.can_read_unit_users(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT public.unit_users_read_rule(m.is_manager,m.is_editor,m.is_editor_view)
   FROM public.unit_users m WHERE m.unit=p_unit AND m."user"=auth.uid()),false);
$$;
CREATE OR REPLACE FUNCTION public.can_manage_unit_users(p_unit bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_is_manager_on_unit(p_unit);
$$;
CREATE OR REPLACE FUNCTION public.can_manage_occasion_participants(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.participant_manage_rule(public.get_is_manager_on_occasion(p_occasion),public.get_is_admin_on_occasion(p_occasion));
$$;
REVOKE ALL ON FUNCTION public.can_read_unit_users(bigint),public.can_manage_unit_users(bigint),public.can_manage_occasion_participants(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_read_unit_users(bigint),public.can_manage_unit_users(bigint),public.can_manage_occasion_participants(bigint) TO authenticated,service_role;
