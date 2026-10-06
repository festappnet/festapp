BEGIN;

-- On the canonical runtime, extensions belongs to supabase_admin; postgres is
-- not a superuser or member of that role. GRANT by postgres returns a warning
-- without changing the ACL. Apply this scoped migration as the verified schema
-- owner through the protected local SQL connection, without retrieving keys.
GRANT USAGE ON SCHEMA extensions TO service_role;
DO $$
BEGIN
  IF NOT has_schema_privilege('service_role', 'extensions', 'USAGE') THEN
    RAISE EXCEPTION 'email_extensions_grant_failed: apply schema privileges as the verified extensions owner';
  END IF;
END;
$$;

NOTIFY pgrst, 'reload schema';
COMMIT;
