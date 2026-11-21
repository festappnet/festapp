CREATE TABLE IF NOT EXISTS public.account_private_image_grants (
  code_hash bytea PRIMARY KEY,
  session_id uuid NOT NULL REFERENCES auth.sessions(id) ON DELETE CASCADE,
  project text NOT NULL,
  object_key text NOT NULL,
  expires_at timestamptz NOT NULL,
  claims jsonb NOT NULL
);
CREATE INDEX IF NOT EXISTS account_private_image_grants_expiry_idx
  ON public.account_private_image_grants(expires_at);
ALTER TABLE public.account_private_image_grants ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.account_private_image_grants FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.issue_account_private_image_grant_v1(
  p_project text, p_object_key text, p_expires_in integer
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_claims jsonb := auth.jwt();
  v_code text;
  v_expires_at timestamptz;
BEGIN
  IF public.get_account_assurance_v1() IS DISTINCT FROM 'allowed'
    OR public.get_image_project_access_v1(p_project) IS DISTINCT FROM true
    OR p_object_key IS NULL OR length(p_object_key) > 1024 OR p_object_key !~ '^private/.+'
    OR p_expires_in IS NULL OR p_expires_in NOT BETWEEN 1 AND 604800 THEN RETURN NULL; END IF;

  v_expires_at := least(statement_timestamp() + make_interval(secs => p_expires_in),
    to_timestamp((v_claims->>'exp')::bigint));
  v_code := translate(rtrim(encode(gen_random_bytes(32), 'base64'), '='), '+/', '-_');
  DELETE FROM public.account_private_image_grants WHERE code_hash IN (
    SELECT code_hash FROM public.account_private_image_grants
    WHERE expires_at <= statement_timestamp() ORDER BY expires_at LIMIT 32 FOR UPDATE SKIP LOCKED
  );
  -- Retain only the previously verified facts required by the access checks.
  INSERT INTO public.account_private_image_grants
    (code_hash, session_id, project, object_key, expires_at, claims)
  VALUES (digest(v_code, 'sha256'), (v_claims->>'session_id')::uuid, p_project, p_object_key, v_expires_at,
    jsonb_build_object('role', v_claims->'role', 'sub', v_claims->'sub',
      'session_id', v_claims->'session_id', 'exp', v_claims->'exp', 'aal', v_claims->'aal',
      'amr', v_claims->'amr', 'is_anonymous', v_claims->'is_anonymous'));
  RETURN jsonb_build_object('code', v_code,
    'expiresIn', floor(extract(epoch FROM (v_expires_at - statement_timestamp())))::integer);
END $$;

CREATE OR REPLACE FUNCTION public.redeem_account_private_image_grant_v1(
  p_project text, p_object_key text, p_code text
)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_previous text := current_setting('request.jwt.claims', true);
  v_claims jsonb;
  v_allowed boolean;
BEGIN
  IF p_code IS NULL OR p_code !~ '^[A-Za-z0-9_-]{43}$' THEN RETURN false; END IF;
  SELECT claims INTO v_claims FROM public.account_private_image_grants
  WHERE code_hash = digest(p_code, 'sha256') AND project = p_project AND object_key = p_object_key
    AND expires_at > statement_timestamp();
  IF NOT FOUND THEN RETURN false; END IF;

  -- These claims are read from an owner-only row created under a validated
  -- user JWT. Caller-supplied values never become request claims.
  PERFORM set_config('request.jwt.claims', v_claims::text, true);
  v_allowed := public.get_account_assurance_v1() = 'allowed'
    AND public.get_image_project_access_v1(p_project);
  PERFORM set_config('request.jwt.claims', coalesce(v_previous, ''), true);
  RETURN v_allowed IS TRUE;
END $$;

REVOKE ALL ON FUNCTION public.issue_account_private_image_grant_v1(text,text,integer),
  public.redeem_account_private_image_grant_v1(text,text,text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.issue_account_private_image_grant_v1(text,text,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.redeem_account_private_image_grant_v1(text,text,text) TO anon;
