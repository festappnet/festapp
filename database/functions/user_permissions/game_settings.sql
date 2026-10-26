CREATE OR REPLACE FUNCTION public.can_edit_game_settings(p_occasion bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT auth.uid() IS NOT NULL AND public.get_is_editor_on_occasion(p_occasion)
 AND EXISTS(SELECT FROM public.occasions o JOIN public.user_info ui ON ui.id=auth.uid() AND ui.organization=o.organization WHERE o.id=p_occasion);
$$;
REVOKE ALL ON FUNCTION public.can_edit_game_settings(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_edit_game_settings(bigint) TO authenticated,service_role;
