CREATE OR REPLACE FUNCTION check_access_to_occasion(oc bigint)
RETURNS void
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    exists_on_occasion boolean;
BEGIN
    -- If the occasion is closed, check if the user exists on the occasion
    IF EXISTS (SELECT 1 FROM public.occasions WHERE id = oc AND NOT is_open) THEN
        -- Use the existing function to check if the user exists on the occasion
        SELECT get_exists_on_occasion(oc) INTO exists_on_occasion;

        -- If the user does not exist on the occasion, raise an exception
        IF NOT exists_on_occasion THEN
            RAISE EXCEPTION 'User is not allowed to access this occasion as it is closed.';
        END IF;
    END IF;
END;
$$;
