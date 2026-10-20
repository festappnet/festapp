CREATE OR REPLACE FUNCTION public.get_unit_for_edit(unit_id bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    unit_data jsonb;
BEGIN
    -- Check if the current user is authorized (editor or manager) for the provided unit
    IF NOT EXISTS (
        SELECT 1
        FROM unit_users
        WHERE "user" = auth.uid()
          AND unit = unit_id
          AND (is_editor = true OR is_manager = true OR is_editor_view = true)
    ) AND NOT EXISTS (
        SELECT 1
        FROM occasions o
        JOIN occasion_users ou ON ou.occasion = o.id
        WHERE o.unit = unit_id
          AND ou."user" = auth.uid()
          AND (
              ou.is_manager IS TRUE 
              OR ou.is_editor IS TRUE 
              OR ou.is_editor_view IS TRUE 
              OR ou.is_editor_order IS TRUE 
              OR ou.is_editor_order_view IS TRUE
          )
    ) THEN
        RETURN jsonb_build_object('code', 403);
    END IF;

    -- Retrieve the unit data as jsonb
    SELECT jsonb_build_object(
        'id', id,
        'title', title,
        'data', data,
        'features', features,
        'organization', organization,
        'aggregate_version', coalesce((SELECT v.version FROM public.client_aggregate_versions v
          WHERE v.aggregate_type='unit' AND v.scope_type='unit' AND v.scope_id=unit_id
          AND v.aggregate_id=unit_id::text),0)
    ) INTO unit_data
    FROM units
    WHERE id = unit_id;

    -- Return the unit data with a 200 code
    RETURN jsonb_build_object('code', 200, 'data', unit_data);
END;
$$;
