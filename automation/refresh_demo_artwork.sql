-- Run only for an explicitly selected tenant after uploading verified assets.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
\ir ../database/fixtures/demo_occasions/layouts.sql
\ir ../database/fixtures/demo_occasions/artwork.sql
SELECT pg_temp.refresh_demo_artwork(:demo_organization);
COMMIT;
