CREATE OR REPLACE FUNCTION create_form(
    p_occasion_id BIGINT,
    p_link TEXT,
    p_title TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    new_form_id BIGINT;
    new_form JSONB;
    new_product_type_id BIGINT;
    v_communication_tone TEXT;
    now TIMESTAMPTZ := NOW();
BEGIN
    SELECT CASE WHEN u.data->>'communication_tone' = 'informal'
                THEN 'informal' ELSE 'formal' END
    INTO v_communication_tone
    FROM public.occasions o
    JOIN public.units u ON u.id = o.unit
    WHERE o.id = p_occasion_id;

    -- The definitive server-side uniqueness check for the form link
    IF EXISTS (SELECT 1 FROM public.forms WHERE link = p_link) THEN
        RAISE EXCEPTION '%',
            JSONB_BUILD_OBJECT('code', 4090, 'message', 'Form link is already in use')::TEXT;
    END IF;

    -- Create the new form
    INSERT INTO public.forms(
        title,
        link,
        occasion,
        created_at,
        updated_at,
        deadline_duration_seconds,
        data
    )
    VALUES (
        p_title,
        p_link,
        p_occasion_id,
        now,
        now,
        604800, -- Default to 7 days
        jsonb_build_object(
            'is_reminder_enabled', true,
            'communication_tone', COALESCE(v_communication_tone, 'formal')
        )
    )
    RETURNING to_jsonb(public.forms.*) INTO new_form;

    new_form_id := (new_form->>'id')::BIGINT;

    -- Create default 'email' and 'ticket' fields
    INSERT INTO public.form_fields(title, type, is_required, form, "order")
    VALUES ('', 'email', true, new_form_id, 0),
           ('', 'ticket', true, new_form_id, 1);

    -- Ensure 'spot' product type exists for the occasion
    IF NOT EXISTS (SELECT 1 FROM eshop.product_types WHERE occasion = p_occasion_id AND type = 'spot') THEN
        INSERT INTO eshop.product_types(title, type, occasion)
        VALUES ('Spot', 'spot', p_occasion_id)
        RETURNING id INTO new_product_type_id;
    ELSE
        SELECT id INTO new_product_type_id FROM eshop.product_types WHERE occasion = p_occasion_id AND type = 'spot' LIMIT 1;
    END IF;

    -- Ensure the 'spot' product type has at least one product
    IF NOT EXISTS (SELECT 1 FROM eshop.products WHERE occasion = p_occasion_id AND product_type = new_product_type_id) THEN
        INSERT INTO eshop.products(title, price, product_type, occasion, currency_code, "order")
        VALUES ('Variant 1', 100, new_product_type_id, p_occasion_id, 'CZK', 0);
    END IF;

    -- Create the 'product_type' form field linked to 'spot'
    INSERT INTO public.form_fields(title, type, is_required, form, "order", product_type, is_ticket_field)
    VALUES ('Spot', 'product_type', false, new_form_id, 2, new_product_type_id, true);

    -- Return the raw data of the newly created form
    RETURN new_form;
END;
$$;
