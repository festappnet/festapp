CREATE OR REPLACE FUNCTION public.create_form_internal_v1(p_occasion_id bigint,p_link text,p_title text)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
    PERFORM public.check_occasion_writable(p_occasion_id);
    IF auth.uid() IS NULL OR NOT public.can_author_forms(p_occasion_id) THEN
      RAISE insufficient_privilege USING MESSAGE='form editor required'; END IF;
    RETURN public.insert_form_for_occasion_internal_v1(p_occasion_id,p_link,p_title);
END $$;
REVOKE ALL ON FUNCTION public.create_form_internal_v1(bigint,text,text) FROM PUBLIC,anon,authenticated,service_role;
