-- The email renderer reads inherited form settings as the service role.
-- Preserve the private client boundary while restoring that worker dependency.
REVOKE ALL ON FUNCTION public.get_effective_form_data(bigint)
FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_effective_form_data(bigint) TO service_role;
