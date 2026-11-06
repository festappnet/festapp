CREATE SCHEMA IF NOT EXISTS analytics;
REVOKE ALL ON SCHEMA analytics FROM PUBLIC,anon,authenticated,service_role;

-- Forward-only relocation of earlier installations. Never dual-read/dual-write.
DO $$ BEGIN
 IF to_regclass('public.form_measurement_organization_policy') IS NOT NULL THEN
  IF to_regclass('analytics.organization_policy') IS NOT NULL THEN
   RAISE EXCEPTION 'Conflicting measurement policy tables; reconcile before migration';
  END IF;
  ALTER TABLE public.form_measurement_organization_policy SET SCHEMA analytics;
  ALTER TABLE analytics.form_measurement_organization_policy RENAME TO organization_policy;
 END IF;
 IF to_regclass('public.form_measurement_conversion_facts') IS NOT NULL THEN
  IF to_regclass('analytics.conversion_facts') IS NOT NULL THEN
   RAISE EXCEPTION 'Conflicting conversion tables; reconcile before migration';
  END IF;
  ALTER TABLE public.form_measurement_conversion_facts SET SCHEMA analytics;
  ALTER TABLE analytics.form_measurement_conversion_facts RENAME TO conversion_facts;
 END IF;
END $$;

-- Retire the unreleased organization-scoped runtime shape without discarding
-- any operator-provisioned deployment. Runtime trust now belongs to Unit.
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='analytics' AND table_name='organization_policy' AND column_name='runtime_origin') THEN
  IF EXISTS(SELECT 1 FROM analytics.organization_policy WHERE runtime_origin IS NOT NULL) THEN
   RAISE EXCEPTION 'Organization-scoped runtime deployment requires Unit reconciliation';
  END IF;
 END IF;
END $$;
ALTER TABLE IF EXISTS analytics.organization_policy DROP COLUMN IF EXISTS runtime_origin,
 DROP COLUMN IF EXISTS runtime_profile,DROP COLUMN IF EXISTS parent_origins,DROP COLUMN IF EXISTS collector_origins;

