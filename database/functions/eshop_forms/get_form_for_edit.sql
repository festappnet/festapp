-- Fix get_form_for_edit: Remove bigint = uuid comparison and add can_delete
CREATE OR REPLACE FUNCTION public.get_form_for_edit(form_link text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
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
            'can_delete', usage.reason IS NULL,
            'delete_blocked_reason', usage.reason,
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
    CROSS JOIN LATERAL (SELECT CASE WHEN EXISTS (
          SELECT 1 FROM (
            SELECT current_order.id, current_order.form, current_order.data FROM eshop.orders current_order WHERE current_order.form = ff.form
            UNION ALL
            SELECT current_order.id, current_order.form, history.data FROM eshop.orders current_order
            JOIN eshop.orders_history history ON history."order" = current_order.id WHERE current_order.form = ff.form
          ) o
          WHERE o.form = ff.form AND (
            EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(o.data->'fields', '[]'::jsonb)) answer
              WHERE answer ? ff.id::text AND answer->(ff.id::text) NOT IN ('null'::jsonb, '""'::jsonb, '[]'::jsonb, '{}'::jsonb))
            OR (ff.type = 'ticket' AND jsonb_path_exists(o.data, '$.tickets[*]'))
            OR (ff.type = 'note' AND ff.is_ticket_field AND jsonb_path_exists(o.data, '$.tickets[*] ? (@.note != null && @.note != "")'))
            OR (ff.type = 'ticket' AND EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt."order" = o.id AND opt.ticket IS NOT NULL))
            OR (ff.type = 'note' AND ff.is_ticket_field AND EXISTS (
              SELECT 1 FROM eshop.order_product_ticket opt JOIN eshop.tickets t ON t.id = opt.ticket
              WHERE opt."order" = o.id AND NULLIF(t.note, '') IS NOT NULL))
          )) THEN 'responses'
        ELSE (
          SELECT reason FROM public.form_fields member
          JOIN eshop.products p ON p.product_type = member.product_type
          CROSS JOIN LATERAL (SELECT CASE
          WHEN EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt.product = p.id)
            OR EXISTS (SELECT 1 FROM eshop.orders o WHERE o.occasion = p.occasion
              AND jsonb_path_exists(o.data, '$.tickets[*].products[*] ? (@.id == $id)', jsonb_build_object('id', p.id))) OR EXISTS (SELECT 1 FROM eshop.orders_history h JOIN eshop.orders o ON o.id = h."order"
              WHERE o.occasion = p.occasion AND jsonb_path_exists(h.data,
                '$.tickets[*].products[*] ? (@.id == $id)', jsonb_build_object('id', p.id))) THEN 'orders'
          WHEN EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product = p.id) THEN 'blueprint'
          WHEN EXISTS (SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product = p.id) THEN 'inventory'
          WHEN (SELECT count(*) FROM public.form_fields ref WHERE ref.product_type = p.product_type) > 1 THEN 'shared'
        END AS reason) usage
          WHERE (member.id = ff.id OR (ff.type = 'ticket' AND member.form = ff.form AND member.is_ticket_field))
            AND reason IS NOT NULL
          ORDER BY p.id LIMIT 1
        ) END AS reason) usage
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
            'can_delete', usage.reason IS NULL,
            'delete_blocked_reason', usage.reason,
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
    CROSS JOIN LATERAL (SELECT CASE
          WHEN EXISTS (SELECT 1 FROM eshop.order_product_ticket opt WHERE opt.product = p.id)
            OR EXISTS (SELECT 1 FROM eshop.orders o WHERE o.occasion = p.occasion
              AND jsonb_path_exists(o.data, '$.tickets[*].products[*] ? (@.id == $id)', jsonb_build_object('id', p.id))) OR EXISTS (SELECT 1 FROM eshop.orders_history h JOIN eshop.orders o ON o.id = h."order"
              WHERE o.occasion = p.occasion AND jsonb_path_exists(h.data,
                '$.tickets[*].products[*] ? (@.id == $id)', jsonb_build_object('id', p.id))) THEN 'orders'
          WHEN EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product = p.id) THEN 'blueprint'
          WHEN EXISTS (SELECT 1 FROM eshop.product_inventory_contexts pic WHERE pic.product = p.id) THEN 'inventory'
          WHEN (SELECT count(*) FROM public.form_fields ref WHERE ref.product_type = p.product_type) > 1 THEN 'shared'
        END AS reason) usage
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
