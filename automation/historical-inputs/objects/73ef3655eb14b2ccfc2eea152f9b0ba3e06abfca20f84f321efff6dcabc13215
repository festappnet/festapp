CREATE OR REPLACE FUNCTION public.set_user_password_token(token uuid, password text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $$
  declare
  v_user_id uuid;
  token_created_at timestamptz;
  email text;
  encrypted_pw text;
BEGIN
    DELETE FROM public.user_reset_token urt
    WHERE urt.token=$1
    RETURNING urt."user",urt.created_at INTO v_user_id,token_created_at;
    IF v_user_id IS NULL OR token_created_at < clock_timestamp()-interval '30 minutes' THEN
        RETURN json_build_object('code', 403);
    END IF;

    IF length(password)<8 THEN RETURN json_build_object('code',400); END IF;

    encrypted_pw := crypt(password, gen_salt('bf'));

    UPDATE auth.users
    SET encrypted_password = encrypted_pw
    WHERE auth.users.id = v_user_id;
    IF NOT FOUND THEN RETURN json_build_object('code',404); END IF;

    UPDATE auth.refresh_tokens SET revoked=true WHERE auth.refresh_tokens.user_id=v_user_id::text;
    DELETE FROM auth.sessions WHERE auth.sessions.user_id=v_user_id;

    SELECT email_readonly INTO email FROM user_info WHERE user_info.id = v_user_id;
    IF email is NULL THEN
        RETURN json_build_object('code', 404);
    END IF;

    RETURN json_build_object('code', 200, 'email', email);
END;
$$;

REVOKE ALL ON FUNCTION public.set_user_password_token(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_user_password_token(uuid,text)
  TO anon, authenticated, service_role;
