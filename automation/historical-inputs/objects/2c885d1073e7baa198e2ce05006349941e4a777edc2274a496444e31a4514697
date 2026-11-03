CREATE OR REPLACE FUNCTION get_unit_edit_data(p_unit_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_unit_data jsonb;
    v_occasions_data jsonb;
BEGIN
    -- 1. Call get_unit_for_edit to get the unit details
    SELECT get_unit_for_edit(p_unit_id) INTO v_unit_data;

    -- Check if get_unit_for_edit returned an error (code != 200)
    IF (v_unit_data->>'code')::INT <> 200 THEN
          RAISE EXCEPTION 'get_unit_for_edit failed: %', v_unit_data->>'message';
    END IF;

    -- 2. Call get_all_occasions_for_edit_v212 to get the occasions
    -- Note: get_all_occasions_for_edit_v212 returns the array directly, not wrapped in code/data
    SELECT get_all_occasions_for_edit_v212(p_unit_id) INTO v_occasions_data;

    -- 3. Merge the results.
    -- v_unit_data has structure {code: 200, data: {...}}
    -- We want to return structure that includes both.
    -- Let's return { unit: ..., occasions: ... }
    
    RETURN jsonb_build_object(
        'unit', (v_unit_data->'data'),
        'occasions', v_occasions_data
    );
END;
$$;
