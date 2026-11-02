-- Older public read contracts keep their response/access semantics and resolve
-- the same stable IDs. Do not restore link-column predicates here.

CREATE OR REPLACE FUNCTION public.check_occasion_link(link_txt text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    occasionId bigint;
    is_open_bool BOOLEAN;
    occasion_user occasion_users%rowtype;
    is_admin_bool BOOLEAN;
BEGIN
    -- If no link is provided, get the first open and non-hidden occasion's link
    IF link_txt = '' THEN
        SELECT link INTO link_txt FROM occasions WHERE occasions.is_open = true AND occasions.is_hidden = false LIMIT 1;
    END IF;

    -- Get the occasion ID for the provided link
    SELECT id INTO occasionId FROM occasions WHERE occasions.id = public.resolve_occasion_link_internal(link_txt) AND occasions.is_hidden = false;

    -- If the occasion ID is not found, return a 404 response
    IF occasionId IS NULL THEN
        RETURN json_build_object('code', 404);
    END IF;

    -- Get the is_open status for the occasion
    SELECT is_open INTO is_open_bool FROM occasions WHERE occasions.id = public.resolve_occasion_link_internal(link_txt);

    -- Get the occasion user record if it exists
    SELECT * INTO occasion_user FROM occasion_users WHERE occasion = occasionId AND "user" = auth.uid();

    -- Check if the current user is an admin on the occasion
    is_admin_bool := get_is_admin_on_occasion(occasionId);

    -- If the occasion is not open, enforce access restrictions
    IF is_open_bool = FALSE THEN
        IF auth.uid() IS NULL THEN
            RETURN json_build_object('code', 403);
        END IF;
        IF occasion_user IS NULL AND NOT is_admin_bool THEN
            RETURN json_build_object('code', 403);
        END IF;
        RETURN json_build_object(
            'code', 200,
            'is_admin', is_admin_bool,
            'occasion_user', COALESCE(row_to_json(occasion_user)::jsonb, NULL),
            'occasion', occasionId
        );
    END IF;

    -- If the occasion user record is not found and the user is not an admin, return basic occasion data
    IF occasion_user IS NULL THEN
        RETURN json_build_object(
            'code', 200,
            'is_admin', is_admin_bool,
            'link', link_txt,
            'occasion', occasionId
        );
    END IF;

    -- Return full occasion data including the user and admin status
    RETURN json_build_object(
        'code', 200,
        'is_admin', is_admin_bool,
        'occasion_user', row_to_json(occasion_user)::jsonb,
        'link', link_txt,
        'occasion', occasionId
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.check_is_editor_view_via_form_link(form_link text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $function$
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
    IF NOT public.get_is_editor_view_on_occasion(occasion_id) THEN
        RAISE EXCEPTION 'User is not authorized to edit this occasion.';
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_products_and_types_from_occasion(form_link text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
  product_types json;
  products json;
  occ_id bigint;
BEGIN
  PERFORM check_is_editor_order_view_via_form_link(form_link);

  SELECT f.occasion
    INTO occ_id
  FROM public.forms f
  WHERE f.id = public.resolve_form_link_internal(form_link);

  SELECT json_agg(
           json_build_object(
             'id', pt.id,
             'type', pt.type
           )
         )
    INTO product_types
  FROM eshop.product_types pt
  WHERE pt.occasion = occ_id;

  SELECT json_agg(
           json_build_object(
             'id', p.id,
             'title', p.title,
             'title_short', p.title_short,
             'product_type', p.product_type,
             'data', p.data,
             'price', p.price,
             'currency_code', p.currency_code,
             'is_hidden', p.is_hidden,
             'order', p."order",
             'maximum', p.maximum,
             'ordered_count', (
               SELECT count(*)
               FROM eshop.order_product_ticket opt
               WHERE opt.product = p.id
             ),
             'paid_count', (
               SELECT count(*)
               FROM eshop.order_product_ticket opt
               JOIN eshop.orders o ON o.id = opt.order
               WHERE opt.product = p.id
                 AND o.state = 'paid'
             ),
             'sent_count', (
               SELECT count(*)
               FROM eshop.order_product_ticket opt
               JOIN eshop.orders o ON o.id = opt.order
               WHERE opt.product = p.id
                 AND o.state = 'sent'
             )
           )
         )
    INTO products
  FROM eshop.products p
  WHERE p.product_type IN (
    SELECT pt.id
    FROM eshop.product_types pt
    WHERE pt.occasion = occ_id
  );

  RETURN json_build_object(
    'product_types', COALESCE(product_types, '[]'::json),
    'products', COALESCE(products, '[]'::json)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_reservations(p_occasion_link text, p_form_link text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    v_occasion_id BIGINT;
    v_form_key UUID;
    spotsData JSONB;
    productsData JSONB;
    productTypesData JSONB;
    ticketsData JSONB;
    ordersData JSONB;
    orderProductTicketsData JSONB;
    paymentInfoData JSONB;
    formsData JSONB;
BEGIN
    -- 1. Input Validation: Ensure at least one link is provided.
    IF p_occasion_link IS NULL AND p_form_link IS NULL THEN
        RETURN jsonb_build_object('code', 400, 'message', 'Either occasion_link or form_link must be provided');
    END IF;

    -- 2. Determine occasion_id based on the provided link.
    -- occasion_link has priority.
    IF p_occasion_link IS NOT NULL THEN
        SELECT id
        INTO v_occasion_id
        FROM public.occasions
        WHERE id = public.resolve_occasion_link_internal(p_occasion_link);
    ELSE -- If occasion_link is NULL, use form_link
        SELECT occasion, key
        INTO v_occasion_id, v_form_key
        FROM public.forms
        WHERE id = public.resolve_form_link_internal(p_form_link);
    END IF;

    -- 3. Check if a valid occasion was found.
    IF v_occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'The provided link is invalid or not linked to any occasion');
    END IF;

    -- 4. Authorization check.
    IF (SELECT can_read_orders(v_occasion_id)) <> TRUE THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to access this occasion');
    END IF;

    -- Fetch spots where order_product_ticket is not NULL
    SELECT jsonb_agg(jsonb_build_object(
        'id', s.id,
        'title', s.title,
        'product', s.product,
        'order_product_ticket', s.order_product_ticket,
        'state', CASE
            WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
            WHEN s.secret IS NOT NULL AND s.secret_expiration_time > now() THEN 'selected'
            ELSE 'available'
        END
    ))
    INTO spotsData
    FROM eshop.spots s
    WHERE s.occasion = v_occasion_id
      AND s.order_product_ticket IS NOT NULL;

    -- Fetch all products linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', p.id,
        'title', p.title,
        'price', p.price,
        'currency_code', p.currency_code,
        'type', pt.type,
        'description', pt.description
    ))
    INTO productsData
    FROM eshop.products p
    JOIN eshop.product_types pt ON pt.id = p.product_type
    WHERE pt.occasion = v_occasion_id;

    -- Fetch product types for the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', pt.id,
        'type', pt.type,
        'title', pt.title,
        'description', pt.description
    ))
    INTO productTypesData
    FROM eshop.product_types pt
    WHERE pt.occasion = v_occasion_id;

    -- Fetch tickets linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', t.id,
        'created_at', t.created_at,
        'ticket_symbol', t.ticket_symbol,
        'state', t.state,
        'note', t.note,
        'note_hidden', t.note_hidden
    ))
    INTO ticketsData
    FROM eshop.tickets t
    WHERE t.occasion = v_occasion_id;

    -- Fetch forms linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', f.id,
        'created_at', f.created_at,
        'data', f.data,
        'key', f.key,
        'occasion', f.occasion,
        'type', f.type,
        'deadline_duration_seconds', f.deadline_duration_seconds,
        'is_open', f.is_open,
        'link', f.link,
        'blueprint', f.blueprint,
        'title', f.title,
        'header', f.header,
        'header_off', f.header_off,
        'updated_at', f.updated_at
    ))
    INTO formsData
    FROM public.forms f
    WHERE f.occasion = v_occasion_id;

    -- Fetch orders - this is the conditional part.
    -- If v_form_key is not NULL, it means we are filtering by form.
    IF v_form_key IS NOT NULL THEN
        SELECT jsonb_agg(jsonb_build_object(
            'id', o.id,
            'created_at', o.created_at,
            'updated_at', o.updated_at,
            'price', o.price,
            'state', o.state,
            'currency_code', o.currency_code,
            'data', o.data,
            'payment_info', o.payment_info,
            'note_hidden', o.note_hidden
        ))
        INTO ordersData
        FROM eshop.orders o
        WHERE o.occasion = v_occasion_id
          AND o.data->>'form' = v_form_key::TEXT; -- Filter by the form's key
    ELSE
        -- Original query if not filtering by form
        SELECT jsonb_agg(jsonb_build_object(
            'id', o.id,
            'created_at', o.created_at,
            'updated_at', o.updated_at,
            'price', o.price,
            'state', o.state,
            'currency_code', o.currency_code,
            'data', o.data,
            'payment_info', o.payment_info,
            'note_hidden', o.note_hidden
        ))
        INTO ordersData
        FROM eshop.orders o
        WHERE o.occasion = v_occasion_id;
    END IF;

    -- Extract order IDs from the (potentially filtered) ordersData JSONB
    WITH order_ids AS (
        SELECT (order_obj->>'id')::BIGINT AS id
        FROM jsonb_array_elements(COALESCE(ordersData, '[]'::jsonb)) order_obj
    )
    -- Fetch relevant order-product-ticket data based on extracted order IDs
    SELECT jsonb_agg(jsonb_build_object(
        'id', opt.id,
        'order', opt."order",
        'product', opt.product,
        'ticket', opt.ticket,
        'created_at', opt.created_at
    ))
    INTO orderProductTicketsData
    FROM eshop.order_product_ticket opt
    WHERE opt."order" IN (SELECT id FROM order_ids);

    -- Fetch payment information linked to the orders
    SELECT jsonb_agg(jsonb_build_object(
        'id', pi.id,
        'created_at', pi.created_at,
        'bank_account', pi.bank_account,
        'variable_symbol', pi.variable_symbol,
        'amount', pi.amount,
        'paid', pi.paid,
        'returned', pi.returned,
        'deadline', pi.deadline,
        'currency_code', pi.currency_code,
        'data', pi.data
    ))
    INTO paymentInfoData
    FROM eshop.payment_info pi
    WHERE pi.id IN (
        SELECT DISTINCT (order_obj->>'payment_info')::BIGINT
        FROM jsonb_array_elements(COALESCE(ordersData, '[]'::jsonb)) order_obj
        WHERE order_obj->>'payment_info' IS NOT NULL
    );

    -- Return combined data
    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'spots', COALESCE(spotsData, '[]'::jsonb),
            'products', COALESCE(productsData, '[]'::jsonb),
            'product_types', COALESCE(productTypesData, '[]'::jsonb),
            'tickets', COALESCE(ticketsData, '[]'::jsonb),
            'orders', COALESCE(ordersData, '[]'::jsonb),
            'order_product_ticket', COALESCE(orderProductTicketsData, '[]'::jsonb),
            'payment_info', COALESCE(paymentInfoData, '[]'::jsonb),
            'forms', COALESCE(formsData, '[]'::jsonb)
        )
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_app_config_v203(data_in jsonb)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_app_config_v218(data_in)::jsonb;
$$;

CREATE OR REPLACE FUNCTION public.get_app_config_v216(data_in jsonb)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_app_config_v218(data_in)::jsonb;
$$;

CREATE OR REPLACE FUNCTION public.get_all_email_templates_via_form_link(form_link text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    occasion_id   bigint;
    v_unit        bigint;
    v_org         bigint;
    email_data    jsonb;
    context       jsonb;
    occasion_data jsonb;
    unit_data     jsonb;
    org_data      jsonb;
    final_result  jsonb;
BEGIN
    -- Retrieve the occasion ID from the forms table using the provided form link.
    SELECT f.occasion
      INTO occasion_id
      FROM public.forms f
      WHERE f.id = public.resolve_form_link_internal(form_link);

    IF occasion_id IS NULL THEN
        RAISE EXCEPTION 'Form not found or no associated occasion.';
    END IF;

    -- Retrieve unit and organization IDs from the occasion.
    SELECT o.unit, o.organization
      INTO v_unit, v_org
      FROM public.occasions o
      WHERE o.id = occasion_id;

    -- Build a JSON context with the occasion, unit, and organization.
    context := jsonb_build_object(
                  'occasion', occasion_id,
                  'unit', v_unit,
                  'organization', v_org
               );

    -- Call the updated function with the context parameter to retrieve templates.
    email_data := public.get_all_email_templates(context);

    -- Retrieve occasion details (id and title).
    SELECT jsonb_build_object('id', o.id, 'title', o.title)
      INTO occasion_data
      FROM public.occasions o
      WHERE o.id = occasion_id;

    -- Retrieve unit details (id and title).
    SELECT jsonb_build_object('id', u.id, 'title', u.title)
      INTO unit_data
      FROM public.units u
      WHERE u.id = v_unit;

    -- Retrieve organization details (id and title).
    SELECT jsonb_build_object('id', org.id, 'title', org.title)
      INTO org_data
      FROM public.organizations org
      WHERE org.id = v_org;

    -- Build final result JSON object containing the separate objects.
    final_result := jsonb_build_object(
                      'occasion',     occasion_data,
                      'unit',         unit_data,
                      'organization', org_data,
                      'templates',    email_data
                    );

    RETURN final_result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_app_config_v217(data_in jsonb)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_app_config_v218(data_in)::jsonb;
$$;

CREATE OR REPLACE FUNCTION public.get_app_config_v182(data_in jsonb)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_app_config_v218(data_in)::jsonb;
$$;

CREATE OR REPLACE FUNCTION public.get_app_config_v2(data_in jsonb)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_app_config_v218(data_in)::jsonb;
$$;

CREATE OR REPLACE FUNCTION public.get_inclusion_type_groups_by_link(p_occasion_link text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    v_occasion_id bigint;
    v_occasion_data jsonb;
    v_groups_data jsonb;
    result jsonb;
BEGIN
    -- Find the occasion ID from the provided link.
    SELECT id INTO v_occasion_id FROM public.occasions WHERE id = public.resolve_occasion_link_internal(p_occasion_link);
    IF v_occasion_id IS NULL THEN
        RAISE EXCEPTION 'Occasion with link % not found.', p_occasion_link;
    END IF;

    -- Permission check to ensure the user can view data for this occasion.
    IF NOT can_read_orders(v_occasion_id) THEN
        RAISE EXCEPTION 'User is not authorized to view this occasion.';
    END IF;

    -- Get the occasion details.
    SELECT to_jsonb(o) INTO v_occasion_data FROM public.occasions o WHERE id = v_occasion_id;

    -- Aggregate all groups for the occasion, and for each group, aggregate its inclusion types.
    SELECT COALESCE(jsonb_agg(groups_with_types), '[]'::jsonb)
    INTO v_groups_data
    FROM (
        SELECT
            jsonb_build_object(
                'id', g.id,
                'created_at', g.created_at,
                'updated_at', g.updated_at,
                'title', g.title,
                'type', g.type,
                'occasion', g.occasion,
                'inclusion_types', (
                    SELECT COALESCE(jsonb_agg(
                        jsonb_build_object(
                            'id', t.id,
                            'created_at', t.created_at,
                            'updated_at', t.updated_at,
                            'title', t.title,
                            'inclusion_type_group', t.inclusion_type_group,
                            'data', t.data
                        ) ORDER BY t.created_at
                    ), '[]'::jsonb)
                    FROM public.inclusion_types t
                    WHERE t.inclusion_type_group = g.id
                )
            ) AS groups_with_types
        FROM public.inclusion_type_groups g
        WHERE g.occasion = v_occasion_id
        ORDER BY g.created_at
    ) AS subquery;

    -- Construct the final bundle.
    result := jsonb_build_object(
        'occasion', v_occasion_data,
        'groups', v_groups_data
    );

    RETURN result;
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object('code', 500, 'message', SQLERRM);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_products_and_types_for_occasion(form_link text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
  product_types json;
  products json;
  occ_id bigint;
BEGIN
  PERFORM check_is_editor_order_view_via_form_link(form_link);

  SELECT f.occasion
    INTO occ_id
  FROM public.forms f
  WHERE f.id = public.resolve_form_link_internal(form_link);

  SELECT json_agg(
           json_build_object(
             'id', pt.id,
             'type', pt.type,
             'title', pt.title
           )
         )
    INTO product_types
  FROM eshop.product_types pt
  WHERE pt.occasion = occ_id;

  SELECT json_agg(
           json_build_object(
             'id', p.id,
             'title', p.title,
             'description', p.description,
             'title_short', p.title_short,
             'product_type', p.product_type,
             'data', p.data,
             'price', p.price,
             'currency_code', p.currency_code,
             'is_hidden', p.is_hidden,
             'order', p."order",
             'maximum', p.maximum,
             'ordered_count', (
               SELECT count(*)
               FROM eshop.order_product_ticket opt
               WHERE opt.product = p.id
             ),
             'paid_count', (
               SELECT count(*)
               FROM eshop.order_product_ticket opt
               JOIN eshop.orders o ON o.id = opt.order
               WHERE opt.product = p.id
                 AND o.state = 'paid'
             ),
             'sent_count', (
               SELECT count(*)
               FROM eshop.order_product_ticket opt
               JOIN eshop.orders o ON o.id = opt.order
               WHERE opt.product = p.id
                 AND o.state = 'sent'
             )
           )
         )
    INTO products
  FROM eshop.products p
  WHERE p.product_type IN (
    SELECT pt.id
    FROM eshop.product_types pt
    WHERE pt.occasion = occ_id
  );

  RETURN json_build_object(
    'product_types', COALESCE(product_types, '[]'::json),
    'products', COALESCE(products, '[]'::json)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_all_forms(occasion_link text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    v_occasion_id BIGINT;
    forms_data JSONB;
BEGIN
    -- Step 1: Resolve the occasion ID from the provided link.
    SELECT id
    INTO v_occasion_id
    FROM public.occasions
    WHERE id = public.resolve_occasion_link_internal(occasion_link);

    -- Step 2: If no occasion is found, return a 404 error.
    IF v_occasion_id IS NULL THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Occasion not found'
        );
    END IF;

    -- Step 3: Verify if the user has editor rights for this occasion.
    -- This assumes a function `get_is_editor_on_occasion` exists.
    IF NOT get_is_editor_view_on_occasion(v_occasion_id) THEN
        RETURN jsonb_build_object(
            'code', 403,
            'message', 'User is not authorized to view forms for this occasion.'
        );
    END IF;

    -- Step 4: Aggregate forms for the occasion into a JSONB array.
    -- The subquery for 'response_count' is now corrected to count responses from the 'eshop.orders' table.
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', f.id,
            'created_at', f.created_at,
            'title', f.title,
            'data', f.data,
            'key', f.key,
            'occasion', f.occasion,
            'type', f.type,
            'is_open', f.is_open,
            'link', f.link,
            'blueprint', f.blueprint,
            'updated_at', f.updated_at,
            'response_count', (
                SELECT COUNT(*)
                FROM eshop.orders o
                WHERE (o.data->>'form')::uuid = f.key -- Correctly join forms.key with the UUID in orders.data
            )
        ) ORDER BY f.created_at
    )
    INTO forms_data
    FROM public.forms f
    WHERE f.occasion = v_occasion_id;

    -- Step 5: If no forms were found, return an empty array.
    IF forms_data IS NULL THEN
        forms_data := '[]'::jsonb;
    END IF;

    -- Step 6: Return the aggregated JSON response with a 200 code.
    RETURN jsonb_build_object(
        'code', 200,
        'data', forms_data
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_app_config(data_in jsonb)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_app_config_v218(data_in)::jsonb;
$$;



CREATE OR REPLACE FUNCTION public.get_form_fields(p_form_link text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    form_id INT;
    fieldsData JSONB;
    productTypesData JSONB;
BEGIN
    PERFORM public.check_is_editor_order_view_via_form_link(p_form_link);
    -- Retrieve the form ID from the form link.
    SELECT id
    INTO form_id
    FROM public.forms
    WHERE id = public.resolve_form_link_internal(p_form_link);

    -- Validate that the form exists.
    IF form_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Form not found');
    END IF;

    -- Retrieve the form fields associated with the form.
    -- (Filtering out ticket fields by checking a Boolean column and a specific type value)
    SELECT jsonb_agg(
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
            'order', ff.order,
            'product_type', ff.product_type,
            'is_ticket_field', ff.is_ticket_field
         )
    )
    INTO fieldsData
    FROM public.form_fields ff
    WHERE ff.form = form_id
      AND ff.is_ticket_field = FALSE
      AND ff.type <> 'ticket';

    -- Retrieve product types for those fields.
    SELECT jsonb_agg(
         jsonb_build_object(
            'id', pt.id,
            'name', pt.title,
            'description', pt.description
         )
    )
    INTO productTypesData
    FROM eshop.product_types pt
    WHERE pt.id IN (
        SELECT DISTINCT ff.product_type
        FROM public.form_fields ff
        WHERE ff.form = form_id
    );

    -- Return combined data as JSON.
    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'fields', COALESCE(fieldsData, '[]'::jsonb),
            'product_types', COALESCE(productTypesData, '[]'::jsonb)
        )
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_form_from_link(form_link text)
RETURNS json LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.get_form_by_link(form_link);
$$;

CREATE OR REPLACE FUNCTION public.get_form_from_link_for_edit(form_link text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    allData JSON;
BEGIN

    PERFORM check_is_editor_order_view_via_form_link(form_link);

    SELECT jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'id', f.id,
            'key', f.key,
            'is_open', f.is_open,
            'created_at', f.created_at,
            'data', f.data,
            'type', f.type,
            'header', f.header,
            'header_off', f.header_off,
            'occasion', f.occasion,
            'blueprint', f.blueprint,
            'link', f.link,
            -- Return full bank_account details as JSON instead of just the id:
            'bank_account', jsonb_build_object(
                                'account_number', ba.account_number,
                                'account_number_human_readable', ba.account_number_human_readable,
                                'title', ba.title,
                                'supported_currencies', ba.supported_currencies
                            ),
            'deadline_duration_seconds', f.deadline_duration_seconds,
            -- Optionally, if you want to keep the account_number separately, you can leave it:
            'account_number', ba.account_number,
            'available_bank_accounts', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'account_number', ba_inner.account_number,
                        'account_number_human_readable', ba_inner.account_number_human_readable,
                        'title', ba_inner.title,
                        'supported_currencies', ba_inner.supported_currencies
                    )
                )
                FROM eshop.unit_bank_accounts uba
                JOIN eshop.bank_accounts ba_inner ON uba.bank_account = ba_inner.id
                WHERE uba.unit = (
                    SELECT o.unit
                    FROM public.occasions o
                    WHERE o.id = f.occasion
                )
            ),
            'fields', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', ff.id,
                        'title', ff.title,
                        'description', ff.description,
                        'data', ff.data,
                        'type', ff.type,
                        'is_required', ff.is_required,
                        'is_hidden', ff.is_hidden,
                        'is_ticket_field', ff.is_ticket_field,
                        'order', ff."order",
                        'product_type_data', (
                            CASE
                                WHEN ff.product_type IS NOT NULL THEN
                                    jsonb_build_object(
                                        'id', pt.id,
                                        'title', pt.title,
                                        'description', pt.description,
                                        'type', pt.type,
                                        'data', pt.data,
                                        'occasion', pt.occasion,
                                        'products', (
                                            SELECT jsonb_agg(
                                                jsonb_build_object(
                                                    'id', p.id,
                                                    'occasion', p.occasion,
                                                    'title', p.title,
                                                    'description', p.description,
                                                    'price', p.price,
                                                    'currency_code', p.currency_code,
                                                    'is_hidden', p.is_hidden,
                                                    'order', p."order",
                                                    'ordered_count', (
                                                        SELECT count(*)
                                                        FROM eshop.order_product_ticket opt
                                                        WHERE opt.product = p.id
                                                    ),
                                                    'maximum', p.maximum
                                                ) ORDER BY COALESCE(p."order", 0)
                                            )
                                            FROM eshop.products p
                                            WHERE p.product_type = pt.id
                                        )
                                    )
                                ELSE NULL
                            END
                        )
                    ) ORDER BY COALESCE(ff."order", 0)
                )
                FROM public.form_fields ff
                LEFT JOIN eshop.product_types pt ON ff.product_type = pt.id
                WHERE ff.form = f.id
            )
        )
    )
    INTO allData
    FROM public.forms f
    LEFT JOIN eshop.bank_accounts ba ON f.bank_account = ba.id
    WHERE f.id = public.resolve_form_link_internal(form_link);

    RETURN allData;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_occasion_from_link(org_id bigint, link_txt text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    occasionId bigint;
    is_open_bool BOOLEAN;
    occasion_user occasion_users%rowtype;
    is_admin_bool BOOLEAN;
    occasion_link text;
    version_recommended text;
BEGIN
    -- If no link is provided, get the default occasion from the organization
    IF link_txt = '' THEN
        -- Get the default occasion ID from the organization's data
        SELECT data->>'DEFAULT_OCCASION' INTO occasionId
        FROM organizations
        WHERE id = org_id;

        -- If no default occasion is set, get the first open and non-hidden occasion within the organization
        IF occasionId IS NULL THEN
            SELECT id, link INTO occasionId, occasion_link
            FROM occasions
            WHERE is_open = true
              AND is_hidden = false
              AND organization = org_id
            LIMIT 1;

            -- If no open occasion is found, return a 404 response
            IF occasionId IS NULL THEN
                RETURN json_build_object('code', 404, 'message', 'No open occasion found for the organization');
            END IF;
        ELSE
            -- Get the link for the default occasion
            SELECT link INTO occasion_link
            FROM occasions
            WHERE id = occasionId AND organization = org_id;
        END IF;
    ELSE
        -- Get the occasion ID and link for the provided link within the specified organization
        SELECT id, link INTO occasionId, occasion_link
        FROM occasions
        WHERE id = public.resolve_occasion_link_internal(link_txt,org_id)
          AND is_hidden = false
          AND organization = org_id;

        -- If the occasion ID is not found, return a 404 response
        IF occasionId IS NULL THEN
            RETURN json_build_object('code', 404, 'message', 'Occasion not found');
        END IF;
    END IF;

     -- Retrieve version_recommended from organization's data
    SELECT data->>'VERSION_RECOMMENDED' INTO version_recommended
    FROM organizations
    WHERE id = org_id;

    -- Get the is_open status for the occasion
    SELECT is_open INTO is_open_bool
    FROM occasions
    WHERE id = occasionId;

    -- Get the occasion user record if it exists
    SELECT * INTO occasion_user
    FROM occasion_users
    WHERE occasion = occasionId
      AND "user" = auth.uid();

    -- Check if the current user is an admin on the occasion
    is_admin_bool := get_is_admin_on_occasion(occasionId);

    -- If the occasion is not open, enforce access restrictions
    IF is_open_bool = FALSE THEN
        IF auth.uid() IS NULL THEN
            RETURN json_build_object('code', 403, 'message', 'Access forbidden', 'link', occasion_link, 'version_recommended', version_recommended);
        END IF;
        IF occasion_user IS NULL AND NOT is_admin_bool THEN
            RETURN json_build_object('code', 403, 'message', 'Access forbidden', 'link', occasion_link, 'version_recommended', version_recommended);
        END IF;
        RETURN json_build_object(
            'code', 200,
            'is_admin', is_admin_bool,
            'occasion_user', COALESCE(row_to_json(occasion_user)::jsonb, NULL),
            'link', occasion_link,
            'occasion', occasionId,
            'version_recommended', version_recommended
        );
    END IF;

    -- If the occasion user record is not found, the user is authenticated, and the occasion is open
    IF occasion_user IS NULL AND auth.uid() IS NOT NULL THEN
        -- Add the user to the occasion
        PERFORM add_user_to_occasion(occasionId, auth.uid());

        -- Fetch the updated occasion user record
        SELECT * INTO occasion_user
        FROM occasion_users
        WHERE occasion = occasionId
          AND "user" = auth.uid();
    END IF;

    -- If the occasion user record is still not found and the user is not an admin, return basic occasion data
    IF occasion_user IS NULL THEN
        RETURN json_build_object(
            'code', 200,
            'is_admin', is_admin_bool,
            'link', occasion_link,
            'occasion', occasionId,
            'version_recommended', version_recommended
        );
    END IF;

    -- Return full occasion data including the user and admin status
    RETURN json_build_object(
        'code', 200,
        'is_admin', is_admin_bool,
        'occasion_user', row_to_json(occasion_user)::jsonb,
        'link', occasion_link,
        'occasion', occasionId,
        'version_recommended', version_recommended
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_orders(form_link text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
AS $function$
DECLARE
    occasion_id BIGINT;
    spotsData JSONB;
    productsData JSONB;
    productTypesData JSONB;
    ticketsData JSONB;
    ordersData JSONB;
    orderProductTicketsData JSONB;
    paymentInfoData JSONB;
    formsData JSONB;
BEGIN
    -- Get the occasion_id based on the provided form_link
    SELECT occasion
    INTO occasion_id
    FROM public.forms
    WHERE id = public.resolve_form_link_internal(form_link);

    -- Check if form_link is valid
    IF occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Form key does not exist or is not linked to an occasion');
    END IF;

    -- Authorization check
    IF (SELECT can_read_orders(occasion_id)) <> TRUE THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to access this occasion');
    END IF;

    -- Fetch spots where order_product_ticket is not NULL
    SELECT jsonb_agg(jsonb_build_object(
        'id', s.id,
        'title', s.title,
        'product', s.product,
        'order_product_ticket', s.order_product_ticket,
        'state', CASE
            WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
            WHEN s.secret IS NOT NULL AND s.secret_expiration_time > now() THEN 'selected'
            ELSE 'available'
        END
    ))
    INTO spotsData
    FROM eshop.spots s
    WHERE s.occasion = occasion_id
      AND s.order_product_ticket IS NOT NULL;

    -- Fetch all products linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', p.id,
        'title', p.title,
        'price', p.price,
        'currency_code', p.currency_code,
        'type', pt.type,
        'description', pt.description
    ))
    INTO productsData
    FROM eshop.products p
    JOIN eshop.product_types pt ON pt.id = p.product_type
    WHERE pt.occasion = occasion_id;

    -- Fetch product types for the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', pt.id,
        'type', pt.type,
        'title', pt.title,
        'description', pt.description
    ))
    INTO productTypesData
    FROM eshop.product_types pt
    WHERE pt.occasion = occasion_id;

    -- Fetch tickets linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', t.id,
        'created_at', t.created_at,
        'ticket_symbol', t.ticket_symbol,
        'state', t.state,
        'note', t.note,
        'note_hidden', t.note_hidden
    ))
    INTO ticketsData
    FROM eshop.tickets t
    WHERE t.occasion = occasion_id;

    -- Fetch orders linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', o.id,
        'created_at', o.created_at,
        'updated_at', o.updated_at,
        'price', o.price,
        'state', o.state,
        'currency_code', o.currency_code,
        'data', o.data,
        'payment_info', o.payment_info,
        'note_hidden', o.note_hidden
    ))
    INTO ordersData
    FROM eshop.orders o
    WHERE o.occasion = occasion_id;

    -- Extract order IDs from ordersData JSONB
    WITH order_ids AS (
        SELECT (order_obj->>'id')::BIGINT AS id
        FROM jsonb_array_elements(ordersData) order_obj
    )
    -- Fetch relevant order-product-ticket data based on extracted order IDs
    SELECT jsonb_agg(jsonb_build_object(
        'id', opt.id,
        'order', opt."order",
        'product', opt.product,
        'ticket', opt.ticket,
        'created_at', opt.created_at
    ))
    INTO orderProductTicketsData
    FROM eshop.order_product_ticket opt
    WHERE opt."order" IN (SELECT id FROM order_ids);

    -- Fetch payment information linked to the orders
    SELECT jsonb_agg(jsonb_build_object(
        'id', pi.id,
        'created_at', pi.created_at,
        'bank_account', pi.bank_account,
        'variable_symbol', pi.variable_symbol,
        'amount', pi.amount,
        'paid', pi.paid,
        'returned', pi.returned,
        'deadline', pi.deadline,
        'currency_code', pi.currency_code
    ))
    INTO paymentInfoData
    FROM eshop.payment_info pi
    WHERE pi.id IN (
        SELECT DISTINCT (order_obj->>'payment_info')::BIGINT
        FROM jsonb_array_elements(ordersData) order_obj
    );

    -- Fetch forms linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', f.id,
        'created_at', f.created_at,
        'data', f.data,
        'key', f.key,
        'occasion', f.occasion,
        'type', f.type,
        'deadline_duration_seconds', f.deadline_duration_seconds,
        'is_open', f.is_open,
        'link', f.link,
        'blueprint', f.blueprint,
        'header', f.header,
        'header_off', f.header_off,
        'updated_at', f.updated_at
    ))
    INTO formsData
    FROM public.forms f
    WHERE f.occasion = occasion_id;

    -- Return combined data, including the new product_types key
    RETURN jsonb_build_object(
        'code', 200,
        'data', jsonb_build_object(
            'spots', COALESCE(spotsData, '[]'::jsonb),
            'products', COALESCE(productsData, '[]'::jsonb),
            'product_types', COALESCE(productTypesData, '[]'::jsonb),
            'tickets', COALESCE(ticketsData, '[]'::jsonb),
            'orders', COALESCE(ordersData, '[]'::jsonb),
            'order_product_ticket', COALESCE(orderProductTicketsData, '[]'::jsonb),
            'payment_info', COALESCE(paymentInfoData, '[]'::jsonb),
            'forms', COALESCE(formsData, '[]'::jsonb)
        )
    );
END;
$function$;
