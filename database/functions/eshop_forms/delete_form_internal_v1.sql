CREATE OR REPLACE FUNCTION public.delete_form_internal_v1(p_form_id bigint)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_response_count INT;
    v_form_key UUID;
    v_product_type_ids_to_check BIGINT[];
    v_deletable_product_type_ids BIGINT[];
BEGIN
    -- Step 1: Check if the form has any responses. If so, prevent deletion.
    -- This part of the logic remains unchanged.
    SELECT key INTO v_form_key FROM public.forms WHERE id = p_form_id;

    IF v_form_key IS NOT NULL THEN
        SELECT COUNT(*)
        INTO v_response_count
        FROM eshop.orders
        WHERE (data->>'form')::uuid = v_form_key;

        IF v_response_count > 0 THEN
            RAISE EXCEPTION 'This form cannot be deleted because it has responses.';
        END IF;
    END IF;

    -- Step 2: Collect all product_type IDs associated with this form's fields.
    -- We need this list to attempt a cleanup after deleting the fields.
    SELECT ARRAY_AGG(DISTINCT product_type)
    INTO v_product_type_ids_to_check
    FROM public.form_fields
    WHERE form = p_form_id AND product_type IS NOT NULL;

    PERFORM 1 FROM public.occasions WHERE id=(SELECT occasion FROM public.forms WHERE id=p_form_id) FOR UPDATE;
    IF EXISTS(SELECT 1 FROM eshop.product_types pt WHERE pt.id=ANY(v_product_type_ids_to_check) AND public.ticket_layout_uses_product_type(pt.occasion,pt.id) AND NOT EXISTS(SELECT 1 FROM eshop.products p WHERE p.product_type=pt.id) AND NOT EXISTS(SELECT 1 FROM public.form_fields ff WHERE ff.product_type=pt.id AND ff.form<>p_form_id))
    THEN RAISE EXCEPTION 'ticket_product_type_in_use'; END IF;
    -- Step 3: Delete the form fields unconditionally (after the response check).
    -- This severs the link from the form to the product types, fulfilling the
    -- requirement to "delete field anyway".
    DELETE FROM public.form_fields WHERE form = p_form_id;

    -- Step 4: Attempt to clean up the product types that were associated with the form.
    -- We will only delete product types that are not referenced by any existing products.
    IF v_product_type_ids_to_check IS NOT NULL AND array_length(v_product_type_ids_to_check, 1) > 0 THEN
        -- From our list of candidates, find which ones are NOT used by any products.
        SELECT ARRAY_AGG(pt.id)
        INTO v_deletable_product_type_ids
        FROM unnest(v_product_type_ids_to_check) AS pt(id)
        WHERE NOT EXISTS (
            SELECT 1
            FROM eshop.products p
            WHERE p.product_type = pt.id
        ) AND NOT EXISTS(SELECT 1 FROM public.form_fields ff WHERE ff.product_type=pt.id);

        -- If we found any deletable product types, delete them.
        IF v_deletable_product_type_ids IS NOT NULL AND array_length(v_deletable_product_type_ids, 1) > 0 THEN
            DELETE FROM eshop.product_types
            WHERE id = ANY(v_deletable_product_type_ids);
        END IF;
    END IF;

    -- Step 5: Finally, delete the form itself.
    DELETE FROM public.notification_center_source_state WHERE source_key='form-availability:'||p_form_id;
    DELETE FROM public.forms WHERE id = p_form_id;
END;
$$;
REVOKE ALL ON FUNCTION public.delete_form_internal_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
