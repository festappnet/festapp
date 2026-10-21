CREATE OR REPLACE FUNCTION get_form_for_edit(form_link TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_form_id BIGINT;
    v_occasion_id BIGINT;
    v_unit_id BIGINT;
    formData JSONB;
    formFieldsData JSONB;
    productTypesData JSONB;
    productsData JSONB;
    availableBankAccountsData JSONB;
BEGIN
    -- Step 1: Retrieve essential IDs for the form, occasion, and unit.
    -- This also serves as a check to ensure the form exists.
    SELECT
        f.id,
        f.occasion,
        o.unit
    INTO
        v_form_id,
        v_occasion_id,
        v_unit_id
    FROM public.forms f
    JOIN public.occasions o ON f.occasion = o.id
    WHERE f.link = form_link;

    -- If no form is found, return a 404 Not Found response.
    IF v_form_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Form not found for the provided link.');
    END IF;

    -- Step 2: Perform authorization check.
    -- The check_is_editor_order_view_via_form_link function is expected to raise an
    -- exception if the user is not authorized, which will terminate execution.
    PERFORM check_is_editor_order_view_via_form_link(form_link);

    -- Step 3: Fetch the main form data as a single JSON object.
    SELECT jsonb_build_object(
        'id', f.id,
        'key', f.key,
        'is_open', f.is_open,
        'created_at', f.created_at,
        'data', f.data,
        'type', f.type,
        'title', f.title,
        'header', f.header,
        'header_off', f.header_off,
        'occasion', f.occasion,
        'blueprint', f.blueprint,
        'link', f.link,
        'bank_account', f.bank_account, -- The ID of the selected bank account
        'deadline_duration_seconds', f.deadline_duration_seconds
    )
    INTO formData
    FROM public.forms f
    WHERE f.id = v_form_id;

    -- Step 4: Fetch all related form fields and aggregate them into a JSON array.
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', ff.id,
            'form', ff.form,
            'title', ff.title,
            'description', ff.description,
            'data', ff.data,
            'type', ff.type,
            'is_required', ff.is_required,
            'is_hidden', ff.is_hidden,
            'is_ticket_field', ff.is_ticket_field,
            'order', ff."order",
            'product_type', ff.product_type -- The ID of the related product type
        ) ORDER BY COALESCE(ff."order", 0)
    ), '[]'::jsonb)
    INTO formFieldsData
    FROM public.form_fields ff
    WHERE ff.form = v_form_id;

    -- Step 5: Fetch all product types for the occasion.
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', pt.id,
            'title', pt.title,
            'description', pt.description,
            'type', pt.type,
            'data', pt.data,
            'occasion', pt.occasion
        ) ORDER BY pt.title
    ), '[]'::jsonb)
    INTO productTypesData
    FROM eshop.product_types pt
    WHERE pt.occasion = v_occasion_id;

    -- Step 6: Fetch all products for the occasion, including their order count.
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', p.id,
            'occasion', p.occasion,
            'title', p.title,
            'description', p.description,
            'price', p.price,
            'currency_code', p.currency_code,
            'is_hidden', p.is_hidden,
            'order', p."order",
            'product_type', p.product_type,
            'ordered_count', (
                SELECT count(*)
                FROM eshop.order_product_ticket opt
                JOIN eshop.orders o ON opt."order" = o.id
                WHERE opt.product = p.id AND o.state <> 'storno' -- Exclude cancelled orders from the count
            ),
            'maximum', p.maximum,
            'data', p.data
        ) ORDER BY COALESCE(p."order", 0)
    ), '[]'::jsonb)
    INTO productsData
    FROM eshop.products p
    WHERE p.product_type IN (SELECT id FROM eshop.product_types WHERE occasion = v_occasion_id);

    -- Step 7: Fetch all bank accounts available for the occasion's unit.
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', ba.id,
            'account_number', ba.account_number,
            'account_number_human_readable', ba.account_number_human_readable,
            'title', ba.title,
            'supported_currencies', ba.supported_currencies
        )
    ), '[]'::jsonb)
    INTO availableBankAccountsData
    FROM eshop.unit_bank_accounts uba
    JOIN eshop.bank_accounts ba ON uba.bank_account = ba.id
    WHERE uba.unit = v_unit_id;

    -- Step 8: Assemble the final normalized JSON object and return it.
    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'form', formData,
            'form_fields', formFieldsData,
            'product_types', productTypesData,
            'products', productsData,
            'available_bank_accounts', availableBankAccountsData
        )
    );
END;
$$;

create or replace function delete_unit(p_unit_id bigint)
returns void
language plpgsql
security definer
as $$
declare
    v_manager_count int;
    v_occasion_count int;
begin
    -- 1. Check if user is manager
    perform check_is_manager_on_unit(p_unit_id);

    -- 2. Check if unit has no occasions
    select count(*) into v_occasion_count from occasions where unit = p_unit_id;
    if v_occasion_count > 0 then
        raise exception 'UNIT_HAS_OCCASIONS';
    end if;

    -- 3. Check if user has other managed units
    select count(*) into v_manager_count
    from unit_users
    where "user" = auth.uid() and is_manager = true;

    if v_manager_count <= 1 then
        raise exception 'CANNOT_DELETE_LAST_UNIT';
    end if;

    -- 4. Delete dependent unit_users (Cascade manually if not set on FK)
    delete from unit_users where unit = p_unit_id;

    -- 5. Delete the unit
    delete from units where id = p_unit_id;
end;
$$;
