CREATE OR REPLACE FUNCTION public.is_service_role()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_role text := NULLIF(current_setting('request.jwt.claim.role', true), '');
  v_claims text;
BEGIN
  IF v_role IS NULL THEN
    v_claims := NULLIF(current_setting('request.jwt.claims', true), '');
    IF v_claims IS NOT NULL THEN
      BEGIN
        v_role := v_claims::jsonb->>'role';
      EXCEPTION WHEN OTHERS THEN
        RETURN false;
      END;
    END IF;
  END IF;
  IF v_role IS NOT NULL THEN
    RETURN v_role = 'service_role';
  END IF;
  RETURN session_user = 'postgres';
END;
$$;

REVOKE ALL ON FUNCTION public.is_service_role() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.require_service_role()
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_service_role() THEN
    RAISE insufficient_privilege USING MESSAGE = 'service role required';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.require_service_role() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.require_service_role() TO service_role;
