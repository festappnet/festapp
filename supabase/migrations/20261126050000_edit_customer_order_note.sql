-- Enable editing the customer note through scoped order form responses.

-- SOURCE: eshop_orders/update_order_responses.sql
CREATE OR REPLACE FUNCTION public.update_order_responses_domain_internal(
    p_order_id BIGINT,
    responses JSONB
)
RETURNS void
SECURITY INVOKER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id BIGINT;
    v_order_form_id BIGINT;
    v_current_state text;
    v_current_data JSONB;
    v_new_data JSONB;
    v_field_definitions JSONB;
    v_current_fields_map JSONB;
    v_merged_fields_map JSONB;
    v_new_fields_array JSONB;

    v_field_id_text TEXT;
    v_field_type TEXT;
    v_new_value JSONB;
    v_is_customer_note BOOLEAN;

    v_updated_order_state TEXT;
    v_updated_order_price NUMERIC(10, 2);
    v_updated_order_data JSONB;
BEGIN
    -- Fetch the order's current data, occasion, and form ID
    SELECT
        o.data,
        o.occasion,
        o.form,
        o.state
    INTO
        v_current_data,
        v_occasion_id,
        v_order_form_id,
        v_current_state
    FROM eshop.orders o
    WHERE o.id = p_order_id;

    -- Raise an exception if the SELECT INTO returned no row
    IF v_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Order not found: %', p_order_id;
    END IF;

    -- Reject the terminal state before form validation, without reversing
    -- the form -> order lock order used by form-field removal.
    IF v_current_state='storno' THEN
        RAISE EXCEPTION 'ORDER_CANCELLED: Cancelled orders are read-only' USING ERRCODE='55000';
    END IF;

    -- Raise an exception if the order is not linked to a form
    IF v_order_form_id IS NULL THEN
        RAISE EXCEPTION 'Order % has no associated form.', p_order_id;
    END IF;

    -- Coordinate response validation/writes with form saves and field removal.
    PERFORM 1 FROM public.forms WHERE id = v_order_form_id FOR SHARE;
    PERFORM public.check_order_is_mutable(p_order_id);
    PERFORM public.check_batch_ticket_print_immutable_internal(ARRAY(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=p_order_id));
    SELECT data INTO v_current_data FROM eshop.orders WHERE id=p_order_id;

    -- Fetch all field definitions for this form into a JSONB map { "field_id": "field_type" }
    SELECT jsonb_object_agg(ff.id::text, ff.type)
    INTO v_field_definitions
    FROM public.form_fields ff
    WHERE ff.form = v_order_form_id;

    -- Raise an exception if the form has no fields
    IF v_field_definitions IS NULL THEN
        RAISE EXCEPTION 'No form fields found for form %', v_order_form_id;
    END IF;

    -- FIX: Use a LATERAL join to explicitly reference the columns from jsonb_each,
    -- resolving the "ambiguous column 'value'" error.
    SELECT jsonb_object_agg(je.key, je.value)
    INTO v_current_fields_map
    FROM jsonb_array_elements(v_current_data -> 'fields') AS jae(field_object),
         LATERAL jsonb_each(jae.field_object) AS je(key, value);

    -- Start with the current order data
    v_new_data := v_current_data;

    -- Merge the existing fields map with the new responses. New responses overwrite old ones.
    v_merged_fields_map := COALESCE(v_current_fields_map, '{}'::jsonb) || responses;

    -- Iterate through only the *incoming* responses to handle updates and nulls
    FOR v_field_id_text, v_new_value IN SELECT * FROM jsonb_each(responses)
    LOOP
        -- Get the type of the field being updated
        v_field_type := v_field_definitions ->> v_field_id_text;

        -- Validate that the field ID exists on this order's form
        IF v_field_type IS NULL THEN
            RAISE EXCEPTION 'Field ID % not found on form %', v_field_id_text, v_order_form_id;
        END IF;

        -- Checkout also projects the visible order note to data.note.
        v_is_customer_note := v_field_type = 'note' AND EXISTS (
            SELECT 1 FROM public.form_fields ff
            WHERE ff.form = v_order_form_id AND ff.id::text = v_field_id_text
              AND ff.is_ticket_field IS NOT TRUE AND ff.is_hidden IS NOT TRUE
        );

        -- Handle null values: remove the key from the top level and from the merged map
        IF v_new_value IS NULL OR v_new_value = 'null'::jsonb THEN

            -- Remove from the map that will build the 'fields' array
            v_merged_fields_map := v_merged_fields_map - v_field_id_text;

            -- Remove top-level duplicated fields
            IF v_field_type = 'name' THEN
                v_new_data := v_new_data - 'name';
            ELSIF v_field_type = 'surname' THEN
                v_new_data := v_new_data - 'surname';
            ELSIF v_field_type = 'email' THEN
                v_new_data := v_new_data - 'email';
            ELSIF v_field_type = 'phone' THEN
                v_new_data := v_new_data - 'phone';
            ELSIF v_is_customer_note THEN
                v_new_data := v_new_data - 'note';
            END IF;

        -- Handle non-null values: update the top-level keys
        ELSE

            -- Update top-level duplicated fields
            IF v_field_type = 'name' THEN
                v_new_data := v_new_data || jsonb_build_object('name', v_new_value);
            ELSIF v_field_type = 'surname' THEN
                v_new_data := v_new_data || jsonb_build_object('surname', v_new_value);
            ELSIF v_field_type = 'email' THEN
                IF NOT public.email_address_is_valid(v_new_value #>> '{}') THEN
                    RAISE invalid_parameter_value USING MESSAGE='invalid_email_contact';
                END IF;
                v_new_data := v_new_data || jsonb_build_object('email', v_new_value);
            ELSIF v_field_type = 'phone' THEN
                v_new_data := v_new_data || jsonb_build_object('phone', v_new_value);
            ELSIF v_is_customer_note AND jsonb_typeof(v_new_value) = 'string' THEN
                v_new_data := v_new_data || jsonb_build_object('note', v_new_value);
            END IF;

        END IF;
    END LOOP;

    -- Rebuild the 'fields' array from the (now null-stripped) merged map
    -- It converts { "id": "val" } back to [ {"id": "val"} ]
    SELECT jsonb_agg(jsonb_build_object(key, value))
    INTO v_new_fields_array
    FROM jsonb_each(v_merged_fields_map);

    -- Set the new 'fields' array in the main data object
    v_new_data := jsonb_set(
        v_new_data,
        '{fields}',
        COALESCE(v_new_fields_array, '[]'::jsonb)
    );

    PERFORM public.notification_center_prepared_invalidate_order(p_order_id);
    -- Update the order in the database
    UPDATE eshop.orders
    SET
        data = v_new_data,
        updated_at = NOW()
    WHERE
        id = p_order_id
    RETURNING
        state, price, data
    INTO
        v_updated_order_state, v_updated_order_price, v_updated_order_data;

    -- Save the change to the orders_history table
    INSERT INTO eshop.orders_history (
        "order",
        state,
        price,
        data,
        created_at
    )
    VALUES (
        p_order_id,
        v_updated_order_state,
        v_updated_order_price,
        v_updated_order_data,
        NOW()
    );

END;
$$;

-- SOURCE: eshop_orders/update_order_detail_responses.sql
CREATE OR REPLACE FUNCTION public.update_order_detail_responses_domain_internal(
 p_order bigint,p_form bigint,p_expected_fields jsonb,p_responses jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; current_fields jsonb; entry record; ff public.form_fields;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 IF o.id IS NULL OR o.form IS DISTINCT FROM p_form
   OR NOT EXISTS(SELECT 1 FROM public.forms WHERE id=p_form AND occasion=o.occasion) THEN
   RETURN jsonb_build_object('code',404,'message','Responses unavailable'); END IF;
 IF p_responses IS NULL OR jsonb_typeof(p_responses)<>'object' OR octet_length(p_responses::text)>65536 THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid responses'; END IF;
 -- Use the same form -> order -> ticket lock order as response/grid owners.
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order]);
 PERFORM 1 FROM public.forms WHERE id=p_form FOR SHARE;
 PERFORM public.check_order_is_mutable(p_order);
 PERFORM public.check_batch_ticket_print_immutable_internal(ARRAY(SELECT ticket FROM eshop.order_product_ticket WHERE "order"=p_order));
 SELECT * INTO o FROM eshop.orders WHERE id=p_order FOR UPDATE;
 IF o.id IS NULL THEN RETURN jsonb_build_object('code',404); END IF;
 IF o.form IS DISTINCT FROM p_form OR NOT EXISTS(SELECT 1 FROM public.forms WHERE id=p_form AND occasion=o.occasion) THEN RETURN jsonb_build_object('code',409); END IF;
 current_fields:=coalesce(o.data->'fields','[]');
 IF current_fields IS DISTINCT FROM coalesce(p_expected_fields,'[]') THEN RETURN jsonb_build_object('code',409); END IF;
 FOR entry IN SELECT * FROM jsonb_each(p_responses) LOOP
   SELECT * INTO ff FROM public.form_fields WHERE form=p_form AND id::text=entry.key
     AND coalesce(is_ticket_field,false)=false;
   IF ff.id IS NULL OR ff.type IS NULL OR ff.type IN('sex','birth_year','birth_date','id_document','select_many','spot','product_type','ticket','email')
     OR (ff.type='note' AND ff.is_hidden IS TRUE)
     OR (entry.value<>'null'::jsonb AND jsonb_typeof(entry.value)<>'string') THEN
     RAISE invalid_parameter_value USING MESSAGE='response field not editable'; END IF;
   IF ff.type='select_one' AND entry.value NOT IN('null'::jsonb,'""'::jsonb)
     AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(ff.data->'options','[]')) opt WHERE opt->'value'=entry.value) THEN
     RAISE invalid_parameter_value USING MESSAGE='invalid response option'; END IF;
 END LOOP;
 IF p_responses='{}' THEN RETURN jsonb_build_object('code',200); END IF;
 PERFORM public.update_order_responses_domain_internal(p_order,p_responses);
 RETURN jsonb_build_object('code',200);
END $$;
