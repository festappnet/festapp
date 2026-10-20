-- Runtime admits only the canonical document; archival geometry is an explicit
-- offline reviewed-import input. Restore both canonical readers before this file.
DROP FUNCTION IF EXISTS public.get_blueprint_legacy_rollout_internal(uuid,uuid,bigint);
DROP FUNCTION IF EXISTS public.get_blueprint_for_edit_legacy_rollout_internal(text);

DROP FUNCTION IF EXISTS public.update_blueprint(jsonb);
DROP FUNCTION IF EXISTS public.update_blueprint_internal_v1(jsonb);
DROP FUNCTION IF EXISTS public.storno_tickets_bulk_internal_v1(bigint[]);
