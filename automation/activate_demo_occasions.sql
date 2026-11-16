-- Explicit target and final catalogue publication, after backend/client verification.
-- psql -v demo_organization=3 -f automation/activate_demo_occasions.sql
\set ON_ERROR_STOP on
BEGIN;
\if :{?demo_locale}
\else
\set demo_locale cs
\endif
SELECT current_user='postgres' AND count(*)=3 AND count(DISTINCT d.demo_key)=3
 AND bool_and(public.resolve_occasion_link_internal(o.link,d.organization) IS NOT DISTINCT FROM o.id)
 AND bool_and(NOT EXISTS(SELECT 1 FROM public.forms f WHERE f.occasion=o.id
  AND public.resolve_form_link_internal(f.link) IS DISTINCT FROM f.id)) AS demo_ready
FROM public.demo_occasions d JOIN public.occasions o ON o.id=d.occasion
WHERE d.organization=:demo_organization AND d.fixture_version='2026-10-14.3'
 AND coalesce(o.data->>'demo_locale','cs')=:'demo_locale'
\gset
\if :demo_ready
UPDATE public.demo_occasions SET is_listed=false WHERE organization=:demo_organization;
UPDATE public.demo_occasions SET is_listed=true
WHERE organization=:demo_organization AND fixture_version='2026-10-14.3';
COMMIT;
\else
ROLLBACK;
DO $$ BEGIN RAISE EXCEPTION 'Expected three complete demo occasions, matching locale and maintenance role.'; END $$;
\endif
