CREATE OR REPLACE FUNCTION public.delete_unit(p_unit_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_manager_count integer;
BEGIN
    PERFORM public.check_is_manager_on_unit(p_unit_id);

    IF EXISTS (SELECT 1 FROM public.occasions WHERE unit = p_unit_id) THEN
        RAISE EXCEPTION 'UNIT_HAS_OCCASIONS';
    END IF;

    SELECT count(*)
      INTO v_manager_count
      FROM public.unit_users
     WHERE "user" = auth.uid()
       AND is_manager = true;

    IF v_manager_count <= 1 THEN
        RAISE EXCEPTION 'CANNOT_DELETE_LAST_UNIT';
    END IF;

    DELETE FROM public.unit_users WHERE unit = p_unit_id;
    DELETE FROM public.units WHERE id = p_unit_id;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_unit(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_unit(bigint) TO authenticated;
