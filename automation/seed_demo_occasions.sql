-- Operational demo seed. Supply the explicitly selected organization; never infer it.
\set ON_ERROR_STOP on
BEGIN;
\if :{?demo_locale}
\else
\set demo_locale cs
\endif
SELECT :'demo_locale' IN ('cs','en') AS supported_locale, :'demo_locale'='en' AS english_locale \gset
\if :supported_locale
\else
DO $$ BEGIN RAISE EXCEPTION 'Supported demo locales: cs, en'; END $$;
\endif
\ir ../database/fixtures/demo_occasions/layouts.sql
\ir ../database/fixtures/demo_occasions/reference.sql
\if :english_locale
\ir ../database/fixtures/demo_occasions/reference.en.sql
\endif
\ir ../database/fixtures/demo_occasions/artwork.sql
\ir ../database/fixtures/demo_occasions/titles.sql
\ir ../database/fixtures/demo_occasions/ball-prices.sql
\ir ../database/fixtures/demo_occasions/seed.sql
\ir ../database/fixtures/demo_occasions/locales.sql
\ir ../database/fixtures/demo_occasions/localization.sql
SELECT pg_temp.seed_demo_occasions_localized(:demo_organization,:'demo_locale');
COMMIT;
