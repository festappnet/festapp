-- Explicitly selected tenant; source demo only, including synthetic financials.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
\ir ../database/fixtures/demo_occasions/reference.sql
\ir ../database/fixtures/demo_occasions/ball-prices.sql
\ir ../database/fixtures/demo_occasions/seed.sql
SELECT pg_temp.refresh_demo_ball_prices(:demo_organization);
SELECT public.record_client_sync_commit_v1(occasion,'demo.ball-prices','configuration',
 jsonb_build_array(jsonb_build_object('entityType','occasion','entityId',occasion::text,
  'operation','update','safeLabel','Demo ball: seat labels and prices','changedFields',
  jsonb_build_array('forms','blueprints','products','orders','payments','history'))),
 ARRAY['occasion_config'],'[]'::jsonb,'[]'::jsonb,'system','Apply reviewed demo ball pricing and Scout seat labels')
 FROM public.demo_occasions WHERE organization=:demo_organization AND demo_key='ball' AND fixture_version='2026-10-14.3';
COMMIT;
