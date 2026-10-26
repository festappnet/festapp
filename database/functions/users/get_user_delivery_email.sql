CREATE OR REPLACE FUNCTION public.get_user_delivery_email(p_user uuid)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public, extensions
AS $$
    SELECT COALESCE(
        NULLIF(lower(btrim(ui.email_delivery)), ''),
        NULLIF(lower(btrim(ui.email_readonly)), '')
    )
      FROM public.user_info ui
     WHERE ui.id = p_user;
$$;

REVOKE ALL ON FUNCTION public.get_user_delivery_email(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_user_delivery_email(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.get_user_delivery_email(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_delivery_email(uuid) TO service_role;
