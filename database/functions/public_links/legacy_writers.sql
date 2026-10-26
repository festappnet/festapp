CREATE OR REPLACE FUNCTION public.duplicate_form(p_old_form_id bigint)
RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE target text;
BEGIN
 SELECT o.link INTO target FROM public.forms f JOIN public.occasions o ON o.id=f.occasion WHERE f.id=p_old_form_id;
 RETURN public.duplicate_form_to_occasion(p_old_form_id,target);
END $$;
CREATE OR REPLACE FUNCTION public.copy_form_with_fields(p_source_form_id bigint)
RETURNS bigint LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.duplicate_form(p_source_form_id);
$$;
REVOKE ALL ON FUNCTION public.duplicate_form(bigint),public.copy_form_with_fields(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.duplicate_form(bigint),public.copy_form_with_fields(bigint) TO authenticated;
-- Abandoned implementations have no remaining callers after the cutover.
DROP FUNCTION IF EXISTS public.create_form_ws_obsolete_v1(jsonb);
DROP FUNCTION IF EXISTS public.sync_source_via_http_internal_v1(text);

DROP FUNCTION IF EXISTS public.duplicate_occasion_domain_command_internal_v1(bigint,uuid);
