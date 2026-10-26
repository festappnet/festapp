CREATE OR REPLACE FUNCTION public.check_request_secret(p_secret text)
RETURNS boolean
SET search_path = public, extensions AS $$
DECLARE
  v_count integer;
BEGIN
  -- Clean up expired secrets first
  DELETE FROM public.request_secrets
  WHERE created_at < (now() - (interval '1 second' * ttl_seconds));

  SELECT COUNT(*) INTO v_count
  FROM public.request_secrets
  WHERE secret = p_secret;

  RETURN v_count > 0;
END;
$$ LANGUAGE plpgsql;