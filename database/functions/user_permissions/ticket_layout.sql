-- Layout writes are accepted only through the explicit occasion-save boundary.
CREATE OR REPLACE FUNCTION public.can_edit_ticket_layout(p_occasion bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT public.ticket_layout_rule(auth.uid() IS NOT NULL,
    (SELECT public.get_is_editor_on_unit(o.unit) FROM public.occasions o WHERE o.id=p_occasion));
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
