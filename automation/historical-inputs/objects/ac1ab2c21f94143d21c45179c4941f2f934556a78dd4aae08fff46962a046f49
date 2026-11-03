CREATE OR REPLACE FUNCTION get_all_form_fields(form_link TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_form_id BIGINT;
    v_occasion_id BIGINT;
    formFieldsData JSONB;
BEGIN
    -- Retrieve form ID and occasion ID
    SELECT id, occasion INTO v_form_id, v_occasion_id
    FROM public.forms
    WHERE id = public.resolve_form_link_internal(form_link);

    -- Check if form exists
    IF v_form_id IS NULL THEN
        RAISE EXCEPTION 'Form not found.';
    END IF;

    -- Check permissions
    IF NOT public.get_is_editor_order_view_on_occasion(v_occasion_id) THEN
        RAISE EXCEPTION 'Access Denied';
    END IF;

    -- Fetch form fields
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', ff.id,
            'created_at', ff.created_at,
            'title', ff.title,
            'description', ff.description,
            'data', ff.data,
            'type', ff.type,
            'is_required', ff.is_required,
            'form', ff.form,
            'is_hidden', ff.is_hidden,
            'order', ff."order",
            'product_type', ff.product_type,
            'is_ticket_field', ff.is_ticket_field
        ) ORDER BY COALESCE(ff."order", 0)
    ), '[]'::jsonb)
    INTO formFieldsData
    FROM public.form_fields ff
    WHERE ff.form = v_form_id
      AND ff.is_ticket_field = false
      AND ff.type <> 'ticket';

    RETURN formFieldsData;
END;
$$;
