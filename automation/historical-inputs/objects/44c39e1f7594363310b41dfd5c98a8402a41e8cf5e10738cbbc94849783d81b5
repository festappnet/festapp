CREATE OR REPLACE FUNCTION public.get_occasion_for_authoring_v1(p_occasion bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE slug text;
BEGIN
 SELECT link INTO slug FROM public.occasions WHERE id=p_occasion AND organization=(SELECT organization FROM public.user_info WHERE id=auth.uid());
 IF slug IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='occasion not found'; END IF;
 RETURN public.get_occasion_for_edit_v1(slug);
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_for_authoring_v1(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_for_authoring_v1(bigint) TO authenticated;
