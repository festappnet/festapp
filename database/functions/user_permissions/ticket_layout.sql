CREATE OR REPLACE FUNCTION public.can_edit_ticket_layout_as_actor_internal_v1(p_actor uuid,p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.ticket_layout_rule(p_actor IS NOT NULL,coalesce((SELECT NOT public.is_demo_unit(o.unit) AND m.is_editor FROM public.occasions o JOIN public.unit_users m ON m.unit=o.unit AND m."user"=p_actor WHERE o.id=p_occasion),false));
$$;
REVOKE ALL ON FUNCTION public.can_edit_ticket_layout_as_actor_internal_v1(uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
-- Layout writes are accepted only through the explicit occasion-save boundary.
CREATE OR REPLACE FUNCTION public.can_edit_ticket_layout(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT public.can_edit_ticket_layout_as_actor_internal_v1(auth.uid(),p_occasion);
$$;
REVOKE ALL ON FUNCTION public.can_edit_ticket_layout(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_edit_ticket_layout(bigint) TO authenticated;

-- Authoring currently has exactly the layout-write readership; this read
-- operation is separate so discovery never grants an unrelated domain write.
CREATE OR REPLACE FUNCTION public.can_read_ticket_layout(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT public.can_edit_ticket_layout(p_occasion);
$$;
REVOKE ALL ON FUNCTION public.can_read_ticket_layout(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_read_ticket_layout(bigint) TO authenticated;
