-- Operational demo seed. Supply the explicitly selected organization; never infer it.
\set ON_ERROR_STOP on
BEGIN;
\ir ../database/fixtures/demo_occasions/layouts.sql
\ir ../database/fixtures/demo_occasions/reference.sql
\ir ../database/fixtures/demo_occasions/artwork.sql
\ir ../database/fixtures/demo_occasions/titles.sql
\ir ../database/fixtures/demo_occasions/ball-prices.sql
\ir ../database/fixtures/demo_occasions/seed.sql
SELECT pg_temp.seed_demo_occasions(:demo_organization);
COMMIT;
