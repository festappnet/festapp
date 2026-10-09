CREATE OR REPLACE FUNCTION public.get_last_sign_in_at(user_id uuid)
RETURNS timestamp with time zone
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF public.get_can_view_user_auth(user_id) IS NOT TRUE THEN
    RAISE insufficient_privilege USING MESSAGE = 'User auth metadata access denied';
  END IF;
  RETURN (SELECT au.last_sign_in_at FROM auth.users au WHERE au.id = user_id);
END;
$$;
REVOKE ALL ON FUNCTION public.get_last_sign_in_at(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_last_sign_in_at(uuid) TO authenticated, service_role;
