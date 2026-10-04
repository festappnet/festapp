CREATE OR REPLACE FUNCTION public.get_order_details_for_email(p_order_id bigint)
RETURNS jsonb
SET search_path = public, extensions AS $$
DECLARE
    result_data jsonb;
    reference_history_data jsonb;
    form_fields_data jsonb;
    form_data jsonb;
    form_key uuid;
    latest_history_id bigint;
    v_reply_to_email TEXT;
BEGIN
    -- Retrieve the order, occasion, payment info, and bank account as separate objects
    SELECT jsonb_build_object(
        'order', to_jsonb(o.*),
        'occasion', to_jsonb(occ.*),
        'payment_info', to_jsonb(pi.*),
        'bank_account', CASE
            WHEN upper(o.currency_code) = 'EUR'
              AND ba.id IS NOT NULL
              AND nullif(trim(ba.creditor_name), '') IS NULL
            THEN jsonb_set(
              to_jsonb(ba.*),
              '{creditor_name}',
              to_jsonb(left(trim(regexp_replace(org.title, '[[:space:][:cntrl:]]+', ' ', 'g')), 70))
            )
            ELSE to_jsonb(ba.*)
        END
    )
    INTO result_data
    FROM eshop.orders AS o
    LEFT JOIN public.occasions AS occ ON o.occasion = occ.id
    LEFT JOIN public.organizations AS org ON occ.organization = org.id
    LEFT JOIN eshop.payment_info AS pi ON o.payment_info = pi.id
    LEFT JOIN eshop.bank_accounts AS ba ON pi.bank_account = ba.id
    WHERE o.id = p_order_id;

    -- Check if the order was found
    IF result_data IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Order not found.');
    END IF;

    -- Call the function you provided to get the email
    SELECT get_reply_to_email_for_order(p_order_id) INTO v_reply_to_email;

    -- Add the email to the result data. jsonb_build_object handles NULLs gracefully.
    result_data := result_data || jsonb_build_object('reply_to', v_reply_to_email);


    -- Find the latest order_history ID for the given order
    SELECT oh.id
    INTO latest_history_id
    FROM eshop.orders_history AS oh
    WHERE oh.order = p_order_id
    ORDER BY oh.created_at DESC
    LIMIT 1;

    IF latest_history_id IS NOT NULL THEN
        result_data := result_data || jsonb_build_object('latest_history_id', latest_history_id);
    END IF;

    -- Get the data of the latest SENT history entry
    SELECT data INTO reference_history_data
    FROM eshop.orders_history
    WHERE "order" = p_order_id AND (data->>'is_sent_to_customer')::boolean IS TRUE
    ORDER BY created_at DESC LIMIT 1;

    -- If no sent record was found, get the oldest record as the reference
    IF NOT FOUND THEN
        SELECT data INTO reference_history_data
        FROM eshop.orders_history
        WHERE "order" = p_order_id
        ORDER BY created_at ASC LIMIT 1;
    END IF;

    -- Add the reference data to the result
    IF reference_history_data IS NOT NULL THEN
        result_data := result_data || jsonb_build_object('reference_history', reference_history_data);
    END IF;

    -- Extract the form's unique key from the order's data
    form_key := (result_data->'order'->'data'->>'form')::uuid;

    -- If a form key exists, fetch all associated form fields
    IF form_key IS NOT NULL THEN
        -- 2. Modified query to fetch both form_fields and form_data at the same time
        SELECT
            jsonb_object_agg(ff.id, to_jsonb(ff.*)), -- All fields
            public.get_effective_form_data(f.id)     -- Form data with unit defaults
        INTO
            form_fields_data,
            form_data
        FROM
            public.form_fields AS ff
        JOIN
            public.forms AS f ON ff.form = f.id
        WHERE
            f.key = form_key
        GROUP BY
            f.id; -- Group by the form used for effective data

        -- If form fields were found, add them to the result data
        IF form_fields_data IS NOT NULL THEN
            result_data := result_data || jsonb_build_object('form_fields', form_fields_data);
        END IF;

        -- 3. Added this block to merge the form_data
        IF form_data IS NOT NULL THEN
            result_data := result_data || jsonb_build_object('form_data', form_data);
        END IF;
    END IF;

    -- Return a success response with the collected data
    RETURN jsonb_build_object('code', 200, 'data', result_data);

END;
$$ LANGUAGE plpgsql;
