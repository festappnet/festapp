CREATE OR REPLACE FUNCTION public.check_is_editor_order_on_occasion(oc bigint)
RETURNS void
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
BEGIN
    PERFORM public.check_occasion_writable(oc);
    IF (SELECT can_write_orders(oc)) <> TRUE THEN
        RAISE EXCEPTION 'User is not editor.';
    END IF;
END;
$$;
