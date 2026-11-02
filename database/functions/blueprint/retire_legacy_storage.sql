-- The one-shot data cutover has completed. No runtime API reads or converts
-- the retired geometry columns; prepared migration artifacts stay off-server.
DROP FUNCTION IF EXISTS public.blueprint_legacy_migration_source_internal(bigint);
DROP FUNCTION IF EXISTS public.migrate_blueprint_layout_reviewed_internal(text,text,jsonb,uuid);
DROP FUNCTION IF EXISTS public.get_blueprint_editor(text);
