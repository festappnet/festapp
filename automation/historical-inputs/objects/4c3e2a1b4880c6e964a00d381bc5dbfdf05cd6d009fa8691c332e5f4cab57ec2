-- Function: STOP SYNC
CREATE OR REPLACE FUNCTION public.stop_external_source_sync(p_source_name TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_job_name TEXT := 'sync_job_' || p_source_name;
BEGIN
    -- Security Check
    IF auth.role() <> 'service_role' AND session_user <> 'postgres' THEN
        RAISE EXCEPTION 'Access Denied: Service role required.';
    END IF;

    -- Unschedule
    PERFORM cron.unschedule(v_job_name);
    
    RETURN format('Sync job "%s" stopped successfully.', v_job_name);
EXCEPTION WHEN OTHERS THEN
    RETURN format('Error stopping sync: %s', SQLERRM);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.stop_external_source_sync(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.stop_external_source_sync(text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.stop_external_source_sync(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.stop_external_source_sync(text) TO service_role;
