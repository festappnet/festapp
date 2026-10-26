\set ON_ERROR_STOP on
BEGIN;
SELECT pg_advisory_xact_lock(hashtextextended('festapp-server-security-remediation',0));
DO $$
BEGIN
  IF current_database()<>'festapp_rehearsal_20260909220601' OR
    NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=1) THEN
    RAISE EXCEPTION 'Canonical target mismatch';
  END IF;
  IF EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20261016170000') THEN
    RAISE EXCEPTION 'Migration already recorded; use readback rather than replay';
  END IF;
END $$;
-- Embedded canonical migration 20261016170000_server_security_containment.sql
-- Canonical sources: database/functions/security/server_security_containment.sql

-- Standalone containment. No data writes, runtime dependency or history rewrite.
DO $$
DECLARE signature text;
BEGIN
  FOREACH signature IN ARRAY ARRAY['public.migrate_users_to_org(bigint)',
    'public.update_spot(jsonb)', 'public.apply_allocations_claim_only(bigint)'] LOOP
    IF to_regprocedure(signature) IS NOT NULL THEN
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', signature);
    END IF;
  END LOOP;
END $$;

-- End canonical migration
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20261016170000','server_security_containment',ARRAY['-- sha256:df60beef0a8dd773e554a3fe9c10f7ccabe7c2dc6883947dcffc871c75882649']);
NOTIFY pgrst,'reload schema';
COMMIT;
