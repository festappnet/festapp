CREATE OR REPLACE FUNCTION public.get_user_id_by_email(email text)
RETURNS TABLE (id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  RETURN QUERY SELECT au.id FROM auth.users au
  WHERE au.email = $1 AND public.get_can_view_user_auth(au.id) IS TRUE;
END;
$$;
REVOKE ALL ON FUNCTION public.get_user_id_by_email(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_user_id_by_email(text) TO authenticated, service_role;
