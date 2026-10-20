-- Fix get_form_for_edit: Remove bigint = uuid comparison and add can_delete
CREATE OR REPLACE FUNCTION public.get_form_for_edit(form_link text)
 RETURNS jsonb
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
    canDelete BOOLEAN;
BEGIN
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

    IF v_form_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Form not found for the provided link.');
    END IF;

    PERFORM check_is_editor_order_view_via_form_link(form_link);

    -- Calculate can_delete
    -- FIXED: Compare form (bigint) with v_form_id (bigint) directly
    SELECT NOT EXISTS (
        SELECT 1 FROM eshop.orders WHERE form = v_form_id
    ) INTO canDelete;

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
        'bank_account', f.bank_account,
        'deadline_duration_seconds', f.deadline_duration_seconds,
        'can_delete', canDelete -- Added field
    )
    INTO formData
    FROM public.forms f
    WHERE f.id = v_form_id;

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
            'product_type', ff.product_type
        ) ORDER BY COALESCE(ff."order", 0)
    ), '[]'::jsonb)
    INTO formFieldsData
    FROM public.form_fields ff
    WHERE ff.form = v_form_id;

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
                WHERE opt.product = p.id AND o.state <> 'storno'
            ),
            'maximum', p.maximum,
            'data', p.data
        ) ORDER BY COALESCE(p."order", 0)
    ), '[]'::jsonb)
    INTO productsData
    FROM eshop.products p
    WHERE p.product_type IN (SELECT id FROM eshop.product_types WHERE occasion = v_occasion_id);

    -- FIX: Exclude CASH accounts and ensure deterministic sorting by Priority
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', ba.id,
            'account_number', ba.account_number,
            'account_number_human_readable', ba.account_number_human_readable,
            'title', ba.title,
            'supported_currencies', ba.supported_currencies,
            'type', ba.type
        ) ORDER BY uba.priority ASC, ba.id ASC
    ), '[]'::jsonb)
    INTO availableBankAccountsData
    FROM eshop.unit_bank_accounts uba
    JOIN eshop.bank_accounts ba ON uba.bank_account = ba.id
    WHERE uba.unit = v_unit_id
      AND (ba.type IS DISTINCT FROM 'CASH'); -- EXCLUDE CASH ACCOUNTS

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

-- Fix get_bank_accounts_for_unit_management: Remove token_valid_until reference
DROP FUNCTION IF EXISTS public.get_bank_accounts_for_unit_management(bigint);

CREATE OR REPLACE FUNCTION public.get_bank_accounts_for_unit_management(p_unit_id bigint)
 RETURNS TABLE(id bigint, account_number text, title text, priority integer, type text, is_admin boolean, token_masked text, token_expiry_date timestamptz, supported_currencies text[], pairing_code text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        ba.id,
        ba.account_number,
        ba.title,
        uba.priority,
        ba.type,
        EXISTS(SELECT 1 FROM eshop.bank_account_users bau WHERE bau.bank_account = ba.id AND bau."user" = auth.uid() AND bau.is_admin = true) as is_admin,
        CASE WHEN s.secret IS NULL THEN NULL
             WHEN length(s.secret) <= 4 THEN '****'
             ELSE '****' || right(s.secret, 4)
        END as token_masked,
        s.expiry_date as token_expiry_date,
        ba.supported_currencies,
        ba.pairing_code
    FROM eshop.bank_accounts ba
    JOIN eshop.unit_bank_accounts uba ON ba.id = uba.bank_account
    LEFT JOIN eshop.secrets s ON ba.secret = s.id
    WHERE uba.unit = p_unit_id
      AND (ba.type IS DISTINCT FROM 'CASH') -- EXCLUDE CASH ACCOUNTS from management view
    ORDER BY uba.priority ASC, ba.id ASC;
END;
$$;

-- Fix delete_manual_transaction_ws: Ensure recalculate_order_payment_status is called
CREATE OR REPLACE FUNCTION public.delete_manual_transaction_ws(p_transaction_id bigint, p_payment_info_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $$
DECLARE
    transaction_amount numeric(12, 2);
    transaction_currency character(3);
    transaction_type text;
    payment_info_currency character(3);
    payment_info_record eshop.payment_info%ROWTYPE;
    associated_order_id bigint;
    bank_acc bigint;
    occasion_id bigint;
BEGIN
    --- Retrieve the associated order_id from payment_info
     SELECT pi.bank_account INTO bank_acc
     FROM eshop.payment_info pi
     WHERE pi.id = p_payment_info_id
     LIMIT 1;

     PERFORM public.check_is_admin_for_bank_account(bank_acc);

     -- FIX: Retrieve ID as well (stored in associated_order_id)
     SELECT o.occasion, o.id
     INTO occasion_id, associated_order_id
     FROM eshop.orders o
     WHERE o.payment_info = p_payment_info_id
     LIMIT 1;

     PERFORM public.check_is_editor_order_on_occasion(occasion_id);
    
    -- Check if the transaction is linked to the specified payment_info
    IF NOT EXISTS (
        SELECT 1
        FROM eshop.transactions
        WHERE id = p_transaction_id
          AND payment_info = p_payment_info_id
    ) THEN
        RAISE EXCEPTION 'Transaction % is not linked to Payment Info %.', p_transaction_id, p_payment_info_id;
    END IF;

    -- Retrieve the transaction amount, currency and TYPE
    SELECT t.amount, t.currency, t.transaction_type
    INTO transaction_amount, transaction_currency, transaction_type
    FROM eshop.transactions t
    WHERE t.id = p_transaction_id
      AND t.payment_info = p_payment_info_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Transaction % not found.', p_transaction_id;
    END IF;

    IF transaction_type != 'manual' THEN
         RAISE EXCEPTION 'Transaction % is not of type manual (cash). Cannot delete non-manual transactions via this operation.', p_transaction_id;
    END IF;

    -- Retrieve the payment_info currency_code
    SELECT pi.currency_code
    INTO payment_info_currency
    FROM eshop.payment_info pi
    WHERE pi.id = p_payment_info_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Payment Info % does not exist.', p_payment_info_id;
    END IF;

    -- Check if currencies match
    IF transaction_currency != payment_info_currency THEN
        RAISE EXCEPTION 'Currency mismatch: Transaction currency (%) does not match Payment Info currency (%)', transaction_currency, payment_info_currency;
    END IF;

    -- Adjust the paid or returned column based on the transaction amount
    IF transaction_amount > 0 THEN
        -- Ensure that the payment_info has enough 'paid' amount to deduct
        IF (SELECT COALESCE(paid, 0) FROM eshop.payment_info WHERE id = p_payment_info_id) < transaction_amount THEN
            RAISE EXCEPTION 'Insufficient paid amount in Payment Info % to remove Transaction %.', p_payment_info_id, p_transaction_id;
        END IF;

        UPDATE eshop.payment_info
        SET paid = COALESCE(paid, 0) - transaction_amount
        WHERE id = p_payment_info_id;
    ELSE
        -- Transaction was a return; ensure enough 'returned' amount to deduct
        IF (SELECT COALESCE(returned, 0) FROM eshop.payment_info WHERE id = p_payment_info_id) < transaction_amount THEN
            RAISE EXCEPTION 'Insufficient returned amount in Payment Info % to remove Transaction %.', p_payment_info_id, p_transaction_id;
        END IF;

        UPDATE eshop.payment_info
        SET returned = COALESCE(returned, 0) + transaction_amount
        WHERE id = p_payment_info_id;
    END IF;

    -- Fetch the updated payment_info record
    SELECT *
    INTO payment_info_record
    FROM eshop.payment_info
    WHERE id = p_payment_info_id;

    -- DELETE the transaction entirely
    DELETE FROM eshop.transactions
    WHERE id = p_transaction_id;

    -- FIX: Recalculate Order Status!
    IF associated_order_id IS NOT NULL THEN
        PERFORM public.recalculate_order_payment_status(associated_order_id);
    END IF;

    RAISE NOTICE 'Manual Transaction % successfully deleted from Payment Info %.', p_transaction_id, p_payment_info_id;
EXCEPTION
    WHEN others THEN
        RAISE EXCEPTION 'Failed to delete Transaction % from Payment Info %: %', p_transaction_id, p_payment_info_id, SQLERRM;
END;
$$;
