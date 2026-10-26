CREATE OR REPLACE FUNCTION get_unit_edit_data(p_unit_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_unit_data jsonb;
BEGIN
    -- 1. Call get_unit_for_edit to get the unit details
    SELECT get_unit_for_edit(p_unit_id) INTO v_unit_data;

    -- Check if get_unit_for_edit returned an error (code != 200)
    IF (v_unit_data->>'code')::INT <> 200 THEN
          RAISE EXCEPTION 'get_unit_for_edit failed: %', v_unit_data->>'message';
    END IF;

    RETURN public.get_unit_occasion_dashboard_internal(p_unit_id) ||
        jsonb_build_object('unit',v_unit_data->'data');
END;
$$;

REVOKE ALL ON FUNCTION public.get_unit_edit_data(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_unit_edit_data(bigint) TO authenticated;
