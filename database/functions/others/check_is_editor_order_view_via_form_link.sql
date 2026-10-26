CREATE OR REPLACE FUNCTION public.check_is_editor_order_view_via_form_link(form_link text)
RETURNS void
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    occasion_id bigint;
BEGIN
    -- Get occasion ID from form link
    SELECT f.occasion INTO occasion_id
    FROM public.forms f
    WHERE f.id = public.resolve_form_link_internal(form_link);

    -- Check if order/occasion exists
    IF occasion_id IS NULL THEN
        RAISE EXCEPTION 'Form not found or no associated occasion.';
    END IF;

    -- Verify editor permissions using existing helper function
    IF NOT public.can_read_orders(occasion_id) THEN
        RAISE EXCEPTION 'User is not authorized to edit this occasion.';
    END IF;
END;
$$;