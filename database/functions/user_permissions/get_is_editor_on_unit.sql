CREATE OR REPLACE FUNCTION public.get_is_editor_on_unit(unit_id bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
 SELECT public.active_membership(
   (SELECT m.is_editor FROM public.unit_users m WHERE m."user"=auth.uid() AND m.unit=unit_id),
   public.is_demo_unit(unit_id));
$$;
