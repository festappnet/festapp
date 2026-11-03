CREATE OR REPLACE FUNCTION public.process_occasion_auto_import(p_occasion_id bigint)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_features JSONB;
    v_is_auto_import_enabled BOOLEAN := false;
    v_import_res JSONB;
    v_inserted_user JSONB;
    v_target_user_id UUID;
    v_processed_count INT := 0;
BEGIN
    -- 1. Check if feature is enabled for this occasion
    SELECT features INTO v_occasion_features
    FROM public.occasions
    WHERE id = p_occasion_id;

    -- Since features is an Array, we expand it using jsonb_array_elements
    -- and filter for the object where 'code' is 'import'.
    SELECT COALESCE((feature_obj->>'auto_import')::boolean, false)
    INTO v_is_auto_import_enabled
    FROM jsonb_array_elements(v_occasion_features) AS feature_obj
    WHERE feature_obj->>'code' = 'import'
    LIMIT 1;

    -- 2. If enabled, run import and password reset
    IF v_is_auto_import_enabled THEN

        -- Run the import
        v_import_res := public.import_users_from_tickets(p_occasion_id);

        -- Check if we have inserted users
        IF v_import_res ? 'inserted' THEN
            FOR v_inserted_user IN SELECT * FROM jsonb_array_elements(v_import_res->'inserted')
            LOOP
                -- Extract ID directly from the updated function's return object
                v_target_user_id := (v_inserted_user->>'id')::UUID;

                IF v_target_user_id IS NOT NULL THEN
                    -- Reset password to '1'
                    UPDATE auth.users
                    SET encrypted_password = crypt('1', gen_salt('bf'))
                    WHERE id = v_target_user_id;

                    v_processed_count := v_processed_count + 1;
                END IF;
            END LOOP;
        END IF;

        -- Return result for debugging/logging
        RETURN jsonb_build_object(
            'success', true,
            'processed_users', v_processed_count,
            'import_details', v_import_res
        );
    END IF;

    -- Return skipped if feature disabled
    RETURN jsonb_build_object('success', false, 'reason', 'feature_disabled');
END;
$$;