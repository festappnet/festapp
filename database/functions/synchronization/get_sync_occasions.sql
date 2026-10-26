-- Public RPC: Returns occasions data for cross-instance synchronization.
-- Deployed on EVERY source instance that needs to be synced from.
-- Callable by anon role (uses only public data).
CREATE OR REPLACE FUNCTION public.get_sync_occasions(
    p_organization_id BIGINT DEFAULT NULL,
    p_unit_id BIGINT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    result jsonb;
BEGIN
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', o.id,
            'link', o.link,
            'title', o.title,
            'description', o.description,
            'data', o.data,
            'start_time', o.start_time,
            'end_time', o.end_time,
            'is_open', o.is_open,
            'is_hidden', o.is_hidden,
            'is_promoted', o.is_promoted,
            'features', o.features,
            'created_at', o.created_at,
            'form_link', (
                SELECT f.link
                FROM public.forms f
                WHERE f.occasion = o.id
                ORDER BY f.is_open DESC, f.id
                LIMIT 1
            )
        )
        ORDER BY o.start_time DESC
    ), '[]'::jsonb)
    INTO result
    FROM public.occasions o
    WHERE o.is_open = true
      AND o.is_hidden = false
      AND o.is_promoted = true
      AND (p_organization_id IS NULL OR o.organization = p_organization_id)
      AND (p_unit_id IS NULL OR o.unit = p_unit_id);

    RETURN result;
END;
$$;

-- Public access — this returns only publicly visible data
GRANT EXECUTE ON FUNCTION public.get_sync_occasions(bigint, bigint) TO anon;
GRANT EXECUTE ON FUNCTION public.get_sync_occasions(bigint, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_sync_occasions(bigint, bigint) TO service_role;
