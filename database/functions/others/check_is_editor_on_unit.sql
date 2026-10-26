CREATE OR REPLACE FUNCTION public.check_is_editor_on_unit(unit_id bigint)
RETURNS void
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
BEGIN
    IF (SELECT get_is_editor_on_unit(unit_id)) <> TRUE THEN
        RAISE EXCEPTION 'User is not editor.';
    END IF;
END;
$$;