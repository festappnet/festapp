CREATE TABLE IF NOT EXISTS public.password_reset_rate_limits (
  key_hash text PRIMARY KEY CHECK (key_hash ~ '^[0-9a-f]{64}$'),
  window_started_at timestamptz NOT NULL DEFAULT now(),
  attempts integer NOT NULL DEFAULT 1 CHECK (attempts > 0)
);
ALTER TABLE public.password_reset_rate_limits ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS password_reset_rate_limits_window_idx
  ON public.password_reset_rate_limits(window_started_at);

CREATE OR REPLACE FUNCTION public.consume_password_reset_rate_limit_v1(
  p_key_hash text,
  p_limit integer,
  p_window_seconds integer
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_attempts integer;
  v_now timestamptz := clock_timestamp();
BEGIN
  IF auth.role() <> 'service_role' THEN RETURN false; END IF;
  IF p_key_hash !~ '^[0-9a-f]{64}$'
     OR p_limit < 1 OR p_limit > 1000
     OR p_window_seconds < 60 OR p_window_seconds > 86400 THEN
    RETURN false;
  END IF;
  DELETE FROM public.password_reset_rate_limits
  WHERE key_hash IN (
    SELECT key_hash FROM public.password_reset_rate_limits
    WHERE window_started_at < v_now-interval '1 day'
    ORDER BY window_started_at
    LIMIT 100
  );
  INSERT INTO public.password_reset_rate_limits(key_hash,window_started_at,attempts)
  VALUES(p_key_hash,v_now,1)
  ON CONFLICT(key_hash) DO UPDATE SET
    window_started_at=CASE
      WHEN public.password_reset_rate_limits.window_started_at <=
        v_now-make_interval(secs=>p_window_seconds) THEN v_now
      ELSE public.password_reset_rate_limits.window_started_at END,
    attempts=CASE
      WHEN public.password_reset_rate_limits.window_started_at <=
        v_now-make_interval(secs=>p_window_seconds) THEN 1
      ELSE public.password_reset_rate_limits.attempts+1 END
  RETURNING attempts INTO v_attempts;
  RETURN v_attempts <= p_limit;
END
$$;

REVOKE ALL ON TABLE public.password_reset_rate_limits FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.consume_password_reset_rate_limit_v1(text,integer,integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_password_reset_rate_limit_v1(text,integer,integer)
  TO service_role;

CREATE OR REPLACE FUNCTION public.set_user_password_token(token uuid,password text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id uuid;
  token_created_at timestamptz;
  email text;
  encrypted_pw text;
BEGIN
  DELETE FROM public.user_reset_token urt
  WHERE urt.token=$1
  RETURNING urt."user",urt.created_at INTO v_user_id,token_created_at;
  IF v_user_id IS NULL OR token_created_at < clock_timestamp()-interval '30 minutes' THEN
    RETURN jsonb_build_object('code',403);
  END IF;
  IF length(password)<8 THEN RETURN jsonb_build_object('code',400); END IF;

  encrypted_pw:=crypt(password,gen_salt('bf'));
  UPDATE auth.users SET encrypted_password=encrypted_pw WHERE id=v_user_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('code',404); END IF;

  UPDATE auth.refresh_tokens SET revoked=true WHERE auth.refresh_tokens.user_id=v_user_id::text;
  DELETE FROM auth.sessions WHERE auth.sessions.user_id=v_user_id;
  SELECT email_readonly INTO email FROM public.user_info WHERE id=v_user_id;
  IF email IS NULL THEN RETURN jsonb_build_object('code',404); END IF;
  RETURN jsonb_build_object('code',200,'email',email);
END
$$;
REVOKE ALL ON FUNCTION public.set_user_password_token(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_user_password_token(uuid,text)
  TO anon, authenticated, service_role;
