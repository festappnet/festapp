CREATE OR REPLACE FUNCTION public.get_is_editor_view_on_occasion(oc bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
 SELECT public.readable_membership(
   (SELECT m.is_editor_view FROM public.occasion_users m WHERE m."user"=auth.uid() AND m.occasion=oc),
   public.is_demo_occasion(oc),public.can_read_demo_occasion(oc));
$$;
