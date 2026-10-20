CREATE OR REPLACE FUNCTION delete_unit_user(usr uuid, unit_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    DELETE FROM unit_users
    WHERE "user" = usr AND unit = unit_id;

    UPDATE occasion_users
    SET is_editor = false,
        is_manager = false,
        is_editor_view = false
    WHERE "user" = usr
      AND occasion IN (SELECT id FROM occasions WHERE unit = unit_id);

    RETURN jsonb_build_object('code', 200);
END;
$$;
