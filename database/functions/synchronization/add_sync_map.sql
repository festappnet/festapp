-- Function C: ADD MAP
CREATE OR REPLACE FUNCTION public.add_sync_map(
    p_source_name TEXT,
    p_target_org_id BIGINT,
    p_target_unit_id BIGINT,
    p_remote_link_base TEXT,
    p_remote_org_id BIGINT DEFAULT NULL,
    p_remote_unit_id BIGINT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    -- Security Check
    IF auth.role() <> 'service_role' AND session_user <> 'postgres' THEN
        RAISE EXCEPTION 'Access Denied: Service role required.';
    END IF;

    -- Soft Duplicate Check (No DB constraint required)
    IF EXISTS (
        SELECT 1 FROM public.external_sync_maps
        WHERE source_name = p_source_name
          AND target_org_id = p_target_org_id
          AND target_unit_id = p_target_unit_id
          AND remote_link_base = p_remote_link_base
          AND remote_org_id IS NOT DISTINCT FROM p_remote_org_id
          AND remote_unit_id IS NOT DISTINCT FROM p_remote_unit_id
    ) THEN
        RETURN 'Map already exists (skipped).';
    END IF;

    INSERT INTO public.external_sync_maps 
    (source_name, target_org_id, target_unit_id, remote_link_base, remote_org_id, remote_unit_id)
    VALUES 
    (p_source_name, p_target_org_id, p_target_unit_id, p_remote_link_base, p_remote_org_id, p_remote_unit_id);
    
    RETURN 'Map added.';
END;
$$;

-- Security Hardening: Revoke from Public, Allow only Service Role
REVOKE EXECUTE ON FUNCTION public.add_sync_map FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.add_sync_map FROM anon;
REVOKE EXECUTE ON FUNCTION public.add_sync_map FROM authenticated;
GRANT EXECUTE ON FUNCTION public.add_sync_map TO service_role;
