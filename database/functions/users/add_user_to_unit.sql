CREATE OR REPLACE FUNCTION public.add_user_to_unit(
    unit_id BIGINT,
    usr uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    unit_org BIGINT;
    user_org BIGINT;
    user_exists BOOLEAN;
BEGIN
    IF NOT public.is_service_role() AND public.get_is_manager_on_unit(unit_id) IS NOT TRUE THEN
        RAISE insufficient_privilege USING MESSAGE = 'Unit manager required';
    END IF;

    -- Get the organization ID of the unit
    SELECT organization INTO unit_org
    FROM public.units
    WHERE id = unit_id;

    IF unit_org IS NULL THEN
      RAISE EXCEPTION 'Unit % not found', unit_id;
    END IF;

    -- Get the organization ID of the user
    SELECT organization INTO user_org
    FROM public.user_info
    WHERE id = usr;

    IF user_org IS NULL THEN
      RAISE EXCEPTION 'User % not found', usr;
    END IF;

    -- Check if the user and unit belong to the same organization
    IF user_org IS DISTINCT FROM unit_org THEN
        RAISE EXCEPTION 'User does not belong to the same organization as the unit';
    END IF;

    -- Check if the user already exists in the unit_users table
    SELECT EXISTS (
        SELECT 1
        FROM public.unit_users
        WHERE unit = unit_id AND "user" = usr
    ) INTO user_exists;

    -- If the user already exists, update the existing row; otherwise, insert a new one
    IF NOT user_exists THEN
        INSERT INTO public.unit_users (
                    unit,
                    "user",
                    created_at,
                    is_editor,
                    is_manager
                )
                VALUES (
                    unit_id,
                    usr,
                    now(),    -- Set created_at to current timestamp
                    FALSE,    -- Default value for is_editor
                    FALSE    -- Default value for is_manager
                );
    END IF;

    -- Return a successful JSON response
    RETURN jsonb_build_object('code', 200, 'message', 'User added/updated successfully');
EXCEPTION WHEN OTHERS THEN
    RAISE;
END;
$$;

REVOKE ALL ON FUNCTION public.add_user_to_unit(bigint, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_user_to_unit(bigint, uuid) TO authenticated, service_role;
