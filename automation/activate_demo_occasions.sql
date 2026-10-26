-- Explicit target and final catalogue publication, after backend/client verification.
-- psql -v demo_organization=3 -f automation/activate_demo_occasions.sql
\set ON_ERROR_STOP on
BEGIN;
SELECT current_user='postgres' AND count(*)=3 AND count(DISTINCT demo_key)=3 AS demo_ready
FROM public.demo_occasions
WHERE organization=:demo_organization AND fixture_version='2026-10-14.3'
\gset
\if :demo_ready
UPDATE public.demo_occasions SET is_listed=false WHERE organization=:demo_organization;
UPDATE public.demo_occasions SET is_listed=true
WHERE organization=:demo_organization AND fixture_version='2026-10-14.3';
COMMIT;
\else
ROLLBACK;
\echo 'Expected three complete demo occasions and the maintenance role.'
\quit 1
\endif
