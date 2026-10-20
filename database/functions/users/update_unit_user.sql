CREATE OR REPLACE FUNCTION update_unit_user(
    input_data jsonb
) RETURNS jsonb
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    -- Variables extracted from input_data
    v_user uuid;
    v_unit bigint;
    v_is_manager boolean;
    v_is_editor boolean;
    v_is_editor_view boolean;
    v_data jsonb;

    -- Internal helper variables
    v_update_user_payload jsonb;
    v_update_user_result jsonb;
    v_final_user_uuid uuid;
BEGIN
    -- 1. Extract and validate fields from the input JSONB
    v_user := (input_data->>'user')::uuid;
    v_unit := (input_data->>'unit')::bigint;
    v_is_manager := (input_data->>'is_manager')::boolean;
    v_is_editor := (input_data->>'is_editor')::boolean;
    v_is_editor_view := (input_data->>'is_editor_view')::boolean;

    -- Default the 'data' field to an empty jsonb object if it's null or an empty string
    v_data := CASE
                WHEN input_data->>'data' IS NULL OR input_data->>'data' = ''
                THEN '{}'::jsonb
                ELSE input_data->'data'
              END;

    -- 2. Perform initial validation
    IF v_unit IS NULL THEN
        RETURN jsonb_build_object('code', 400, 'message', 'The "unit" field is required.');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.units WHERE id = v_unit) THEN
      RETURN jsonb_build_object('code', 404, 'message', 'Unit not found');
    END IF;

    -- 3. Authorization Check: Verify the calling user is a manager for the specified unit
    IF NOT EXISTS (
      SELECT 1 FROM public.unit_users
      WHERE "user" = auth.uid()
        AND unit = v_unit
        AND is_manager = true
    ) THEN
      RETURN jsonb_build_object('code', 403, 'message', 'Unauthorized: You must be a manager of this unit.');
    END IF;

    -- 4. Prepare payload to call the update_user function
    -- The `update_user` function expects email, name, surname etc., to be inside its 'data' payload.
    -- We will ensure these fields are present in v_data before making the call.
    IF input_data ? 'name' THEN v_data := v_data || jsonb_build_object('name', input_data->>'name'); END IF;
    IF input_data ? 'surname' THEN v_data := v_data || jsonb_build_object('surname', input_data->>'surname'); END IF;
    IF input_data ? 'sex' THEN v_data := v_data || jsonb_build_object('sex', input_data->>'sex'); END IF;
    IF v_user IS NULL AND input_data ? 'email' THEN
        v_data := v_data || jsonb_build_object('email', input_data->>'email');
    END IF;

    v_update_user_payload := jsonb_build_object(
        'user', v_user,
        'unit', v_unit,
        'data', v_data
    );

    -- 5. Call update_user and handle its response
    v_update_user_result := update_user(v_update_user_payload);

    -- If the sub-function did not return a success code (200 or 201), pass its error response through.
    IF (v_update_user_result->>'code')::int NOT IN (200, 201) THEN
        RETURN v_update_user_result;
    END IF;

    -- Extract the definitive user UUID returned from the update_user function
    v_final_user_uuid := (v_update_user_result->>'user')::uuid;

    -- Sanity check in case update_user succeeds but doesn't return a UUID
    IF v_final_user_uuid IS NULL THEN
      RETURN jsonb_build_object('code', 500, 'message', 'Failed to retrieve user UUID after profile update.', 'lol', (v_update_user_result));
    END IF;

    -- 6. Insert or Update the user's roles in the unit (UPSERT)
    INSERT INTO public.unit_users("user", unit, is_manager, is_editor, is_editor_view, data)
    VALUES (v_final_user_uuid, v_unit, v_is_manager, v_is_editor, v_is_editor_view, v_data)
    ON CONFLICT ("user", unit) DO UPDATE
    SET is_manager     = EXCLUDED.is_manager,
        is_editor      = EXCLUDED.is_editor,
        is_editor_view = EXCLUDED.is_editor_view,
        data           = EXCLUDED.data;

    -- 7. Return a final success response
    RETURN jsonb_build_object(
      'code', 200,
      'message', 'User role in unit updated successfully',
      'user', v_final_user_uuid::text
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'code', 500,
      'message', SQLERRM
    );
END;
$$ LANGUAGE plpgsql;