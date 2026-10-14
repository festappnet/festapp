-- Explicitly scoped, idempotent rename of registered demo fixtures only.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
\ir ../database/fixtures/demo_occasions/titles.sql
SELECT pg_temp.refresh_demo_titles(:demo_organization);
COMMIT;
