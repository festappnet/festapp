CREATE OR REPLACE FUNCTION public.generate_request_secret(p_ttl_seconds integer)
RETURNS text
SET search_path = public, extensions AS $$
DECLARE
  v_secret text;
BEGIN
  -- Clean up expired secrets
  DELETE FROM public.request_secrets
  WHERE created_at < (now() - (interval '1 second' * ttl_seconds));

  -- Generate a new secret using a random UUID
  v_secret := gen_random_uuid()::text;

  INSERT INTO public.request_secrets(secret, ttl_seconds)
  VALUES (v_secret, p_ttl_seconds);

  RETURN v_secret;
END;
$$ LANGUAGE plpgsql;