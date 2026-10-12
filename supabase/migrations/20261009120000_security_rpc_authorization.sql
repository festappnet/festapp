-- Security remediation: preserve valid scanner and scoped administration flows.
-- The release runner owns the transaction, including its migration ledger row.

-- Source: database/functions/support/service_role.sql
CREATE OR REPLACE FUNCTION public.is_service_role()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_role text := NULLIF(current_setting('request.jwt.claim.role', true), '');
  v_claims text;
BEGIN
  IF v_role IS NULL THEN
    v_claims := NULLIF(current_setting('request.jwt.claims', true), '');
    IF v_claims IS NOT NULL THEN
      BEGIN
        v_role := v_claims::jsonb->>'role';
      EXCEPTION WHEN OTHERS THEN
        RETURN false;
      END;
    END IF;
  END IF;
  IF v_role IS NOT NULL THEN
    RETURN v_role = 'service_role';
  END IF;
  RETURN session_user = 'postgres';
END;
$$;

REVOKE ALL ON FUNCTION public.is_service_role() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.require_service_role()
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_service_role() THEN
    RAISE insufficient_privilege USING MESSAGE = 'service role required';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.require_service_role() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.require_service_role() TO service_role;


-- Source: database/functions/user_permissions/get_can_view_user_auth.sql
-- Auth metadata is visible only to the identity or an administrator of its real scope.
CREATE OR REPLACE FUNCTION public.get_can_view_user_auth(p_user_id uuid)
RETURNS boolean
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
    SELECT public.is_service_role() OR (
        auth.uid() IS NOT NULL AND (
            auth.uid() = p_user_id
            OR EXISTS (
                SELECT 1 FROM public.user_info target
                JOIN public.organization_users actor ON actor.organization = target.organization
                WHERE target.id = p_user_id AND actor."user" = auth.uid() AND actor.is_admin IS TRUE
            )
            OR EXISTS (
                SELECT 1 FROM public.unit_users target
                JOIN public.unit_users actor ON actor.unit = target.unit
                WHERE target."user" = p_user_id AND actor."user" = auth.uid()
                  AND (actor.is_manager IS TRUE OR actor.is_editor IS TRUE OR actor.is_editor_view IS TRUE)
            )
            OR EXISTS (
                SELECT 1 FROM public.occasion_users target
                JOIN public.occasion_users actor ON actor.occasion = target.occasion
                WHERE target."user" = p_user_id AND actor."user" = auth.uid()
                  AND (actor.is_manager IS TRUE OR actor.is_editor IS TRUE OR actor.is_editor_view IS TRUE)
            )
        )
    );
$$;
REVOKE ALL ON FUNCTION public.get_can_view_user_auth(uuid) FROM PUBLIC, anon, authenticated;


-- Source: database/functions/users/add_user_to_unit.sql
CREATE OR REPLACE FUNCTION public.add_user_to_unit(
    unit_id BIGINT,
    usr uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    unit_org BIGINT;
    user_org BIGINT;
    user_exists BOOLEAN;
BEGIN
    IF NOT public.is_service_role() AND public.get_is_manager_on_unit(unit_id) IS NOT TRUE THEN
        RAISE insufficient_privilege USING MESSAGE = 'Unit manager required';
    END IF;

    -- Get the organization ID of the unit
    SELECT organization INTO unit_org
    FROM public.units
    WHERE id = unit_id;

    IF unit_org IS NULL THEN
      RAISE EXCEPTION 'Unit % not found', unit_id;
    END IF;

    -- Get the organization ID of the user
    SELECT organization INTO user_org
    FROM public.user_info
    WHERE id = usr;

    IF user_org IS NULL THEN
      RAISE EXCEPTION 'User % not found', usr;
    END IF;

    -- Check if the user and unit belong to the same organization
    IF user_org IS DISTINCT FROM unit_org THEN
        RAISE EXCEPTION 'User does not belong to the same organization as the unit';
    END IF;

    -- Check if the user already exists in the unit_users table
    SELECT EXISTS (
        SELECT 1
        FROM public.unit_users
        WHERE unit = unit_id AND "user" = usr
    ) INTO user_exists;

    -- If the user already exists, update the existing row; otherwise, insert a new one
    IF NOT user_exists THEN
        INSERT INTO public.unit_users (
                    unit,
                    "user",
                    created_at,
                    is_editor,
                    is_manager
                )
                VALUES (
                    unit_id,
                    usr,
                    now(),    -- Set created_at to current timestamp
                    FALSE,    -- Default value for is_editor
                    FALSE    -- Default value for is_manager
                );
    END IF;

    -- Return a successful JSON response
    RETURN jsonb_build_object('code', 200, 'message', 'User added/updated successfully');
EXCEPTION WHEN OTHERS THEN
    RAISE;
END;
$$;

REVOKE ALL ON FUNCTION public.add_user_to_unit(bigint, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_user_to_unit(bigint, uuid) TO authenticated, service_role;


-- Source: database/functions/users/get_user_id_by_email.sql
CREATE OR REPLACE FUNCTION public.get_user_id_by_email(email text)
RETURNS TABLE (id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  RETURN QUERY SELECT au.id FROM auth.users au
  WHERE au.email = $1 AND public.get_can_view_user_auth(au.id) IS TRUE;
END;
$$;
REVOKE ALL ON FUNCTION public.get_user_id_by_email(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_user_id_by_email(text) TO authenticated, service_role;


-- Source: database/functions/users/process_token_register.sql
CREATE OR REPLACE FUNCTION public.process_token_register(data jsonb) RETURNS jsonb
SET search_path = public, extensions AS $$
DECLARE
    email_exists boolean;
    inserted_id uuid;
    token uuid;
    result jsonb;
BEGIN
    -- Legacy registration helper has no application caller; retained for trusted maintenance only.
    PERFORM public.require_service_role();

    -- Check if the data contains an email
    IF NOT (data ? 'email') THEN
        -- Construct the result JSONB object with code 400
        result := jsonb_build_object('code', 400, 'message', 'Email is required');
        RETURN result;
    END IF;

    -- Call the function to get the user_id by email
    email_exists := get_user_id_by_email(data ->> 'email') IS NOT NULL;

    -- If email exists, return error
    IF email_exists THEN
        -- Construct the result JSONB object with code 400
        result := jsonb_build_object('code', 400, 'message', 'Email already exists');
        RETURN result;
    END IF;

    -- Generate token
    token := gen_random_uuid();

    -- Insert data into the token_register_user table and capture the inserted ID
    INSERT INTO token_register_user (id, token, is_activated, data)
    VALUES (gen_random_uuid(), token, false, data)
    RETURNING id INTO inserted_id;

    -- Construct the result JSONB object with code 200, ID, and token
    result := jsonb_build_object('code', 200, 'id', inserted_id, 'token', token, 'message', 'Registration successful');
    RETURN result;
END;
$$ LANGUAGE plpgsql;


REVOKE ALL ON FUNCTION public.process_token_register(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_token_register(jsonb) TO service_role;


-- Source: database/functions/users/get_last_sign_in_at.sql
CREATE OR REPLACE FUNCTION public.get_last_sign_in_at(user_id uuid)
RETURNS timestamp with time zone
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF public.get_can_view_user_auth(user_id) IS NOT TRUE THEN
    RAISE insufficient_privilege USING MESSAGE = 'User auth metadata access denied';
  END IF;
  RETURN (SELECT au.last_sign_in_at FROM auth.users au WHERE au.id = user_id);
END;
$$;
REVOKE ALL ON FUNCTION public.get_last_sign_in_at(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_last_sign_in_at(uuid) TO authenticated, service_role;


-- Source: database/functions/eshop_bank_accounts/get_bank_account_users.sql
-- Removing the historical default requires recreation; preserve both exact signatures.
DROP FUNCTION IF EXISTS public.get_bank_account_users(bigint, bigint);

CREATE OR REPLACE FUNCTION public.get_bank_account_users(
    p_bank_account_id bigint,
    p_unit_id bigint
)
RETURNS TABLE (
    user_id uuid,
    email text,
    name text,
    surname text,
    is_admin boolean,
    is_support boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_org_id bigint;
BEGIN
    -- A unit context is meaningful only for an actual account link.
    IF p_unit_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM eshop.unit_bank_accounts link
        WHERE link.unit = p_unit_id AND link.bank_account = p_bank_account_id
    ) THEN
        RAISE insufficient_privilege USING MESSAGE = 'Bank account is not linked to this unit';
    END IF;
    IF NOT public.is_service_role() AND NOT (
        EXISTS (
            SELECT 1 FROM eshop.bank_account_users actor
            WHERE actor.bank_account = p_bank_account_id AND actor."user" = auth.uid()
              AND (actor.is_admin IS TRUE OR actor.is_support IS TRUE)
        ) OR (p_unit_id IS NOT NULL AND public.get_is_manager_on_unit(p_unit_id) IS TRUE)
    ) THEN
        RAISE insufficient_privilege USING MESSAGE = 'Bank account access denied';
    END IF;
    -- If unit context is provided, find the organization
    IF p_unit_id IS NOT NULL THEN
        SELECT organization INTO v_org_id FROM public.units WHERE id = p_unit_id;
    END IF;

    RETURN QUERY
    SELECT
        u.id,
        u.email_readonly,
        u.name,
        u.surname,
        bau.is_admin,
        bau.is_support
    FROM eshop.bank_account_users bau
    JOIN public.user_info u ON bau."user" = u.id
    LEFT JOIN public.organization_users ou ON u.id = ou."user" AND (v_org_id IS NULL OR ou.organization = v_org_id)
    WHERE bau.bank_account = p_bank_account_id
      AND (v_org_id IS NULL OR ou.is_hidden IS NOT TRUE);
END;
$$;

-- Preserve the historical overload without an ambiguous default argument.
CREATE OR REPLACE FUNCTION public.get_bank_account_users(p_bank_account_id bigint)
RETURNS TABLE (user_id uuid, email text, name text, surname text, is_admin boolean, is_support boolean)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
    SELECT * FROM public.get_bank_account_users(p_bank_account_id, NULL::bigint);
$$;
REVOKE ALL ON FUNCTION public.get_bank_account_users(bigint, bigint) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_bank_account_users(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_bank_account_users(bigint, bigint) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_bank_account_users(bigint) TO authenticated, service_role;


-- Source: database/functions/others/get_all_email_templates.sql
CREATE OR REPLACE FUNCTION public.get_all_email_templates(p_context jsonb)
RETURNS jsonb
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
  email_data jsonb;
  v_occ  bigint;
  v_unit bigint;
  v_org  bigint;

  v_effective_org bigint;
  v_actual_unit bigint;
  v_actual_org bigint;
  is_app_supported boolean := false;
BEGIN
  -- 1. Extract context values from the JSON parameter
  v_occ  := CASE
              WHEN p_context ? 'occasion' AND (p_context->>'occasion') IS NOT NULL
              THEN (p_context->>'occasion')::bigint
              ELSE NULL
            END;
  v_unit := CASE
              WHEN p_context ? 'unit' AND (p_context->>'unit') IS NOT NULL
              THEN (p_context->>'unit')::bigint
              ELSE NULL
            END;
  v_org  := CASE
              WHEN p_context ? 'organization' AND (p_context->>'organization') IS NOT NULL
              THEN (p_context->>'organization')::bigint
              ELSE NULL
            END;

  -- Resolve ancestors from the requested object; never trust mixed tenant IDs.
  IF v_occ IS NOT NULL THEN
    SELECT unit, organization INTO v_actual_unit, v_actual_org
    FROM public.occasions WHERE id = v_occ;
    IF NOT FOUND OR (v_unit IS NOT NULL AND v_unit IS DISTINCT FROM v_actual_unit)
        OR (v_org IS NOT NULL AND v_org IS DISTINCT FROM v_actual_org) THEN
      RAISE insufficient_privilege USING MESSAGE = 'Invalid email template hierarchy';
    END IF;
    IF NOT public.is_service_role()
       AND public.get_is_editor_view_on_occasion(v_occ) IS NOT TRUE
       AND public.get_is_editor_order_view_on_occasion(v_occ) IS NOT TRUE THEN
      RAISE insufficient_privilege USING MESSAGE = 'Occasion template access denied';
    END IF;
    v_unit := v_actual_unit;
    v_org := v_actual_org;
  ELSIF v_unit IS NOT NULL THEN
    SELECT organization INTO v_actual_org FROM public.units WHERE id = v_unit;
    IF NOT FOUND OR (v_org IS NOT NULL AND v_org IS DISTINCT FROM v_actual_org) THEN
      RAISE insufficient_privilege USING MESSAGE = 'Invalid email template hierarchy';
    END IF;
    IF NOT public.is_service_role()
       AND public.get_is_manager_on_unit(v_unit) IS NOT TRUE
       AND public.get_is_editor_on_unit(v_unit) IS NOT TRUE
       AND public.get_is_editor_view_on_unit(v_unit) IS NOT TRUE THEN
      RAISE insufficient_privilege USING MESSAGE = 'Unit template access denied';
    END IF;
    v_org := v_actual_org;
  ELSIF NOT public.is_service_role() THEN
    IF v_org IS NULL OR public.get_is_admin_on_organization(v_org) IS NOT TRUE THEN
      RAISE insufficient_privilege USING MESSAGE = 'Organization template access denied';
    END IF;
  END IF;
  v_effective_org := v_org;

  -- 3. Check if App is Supported for the effective organization
  IF v_effective_org IS NOT NULL THEN
    SELECT COALESCE((data->>'IS_APP_SUPPORTED')::BOOLEAN, false)
    INTO is_app_supported
    FROM public.organizations
    WHERE id = v_effective_org;
  END IF;

  -- 5. Retrieve email templates
  SELECT jsonb_agg(result)
    INTO email_data
  FROM (
    SELECT DISTINCT ON (et.code)
           et.id,
           et.html,
           et.occasion,
           et.subject,
           et.organization,
           et.code,
           et.unit,
           et.title
    FROM public.email_templates et
    WHERE
      -- A. Filter based on context (Scope)
      (
           (v_occ IS NOT NULL AND et.occasion = v_occ)
        OR (v_unit IS NOT NULL AND et.unit = v_unit AND et.occasion IS NULL)
        OR (v_org IS NOT NULL  AND et.organization = v_org AND et.unit IS NULL AND et.occasion IS NULL)
        OR (et.organization IS NULL AND et.unit IS NULL AND et.occasion IS NULL)
      )
      -- B. Filter based on App Support (New Logic)
      AND (
        is_app_supported IS TRUE
        OR
        et.code NOT IN ('SIGN_IN_CODE', 'RESET_PASSWORD', 'APP_LINKS',
                        'ACCOUNT_DELETION_CONFIRM', 'ACCOUNT_DELETION_COMPLETE')
      )
    ORDER BY et.code,
             CASE
               WHEN (v_occ IS NOT NULL AND et.occasion = v_occ) THEN 1
               WHEN (v_unit IS NOT NULL AND et.unit = v_unit AND et.occasion IS NULL) THEN 2
               WHEN (v_org IS NOT NULL  AND et.organization = v_org AND et.unit IS NULL AND et.occasion IS NULL) THEN 3
               WHEN (et.organization IS NULL AND et.unit IS NULL AND et.occasion IS NULL) THEN 4
               ELSE 5
             END,
             et.id
  ) result;

  IF email_data IS NULL THEN
    email_data := '[]'::jsonb;
  END IF;

  RETURN email_data;
END;
$$;

REVOKE ALL ON FUNCTION public.get_all_email_templates(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_all_email_templates(jsonb) TO authenticated, service_role;


-- Source: database/functions/others/get_entity_email_templates.sql
CREATE OR REPLACE FUNCTION public.get_entity_email_templates(p_entity_type text, p_entity_id bigint)
RETURNS jsonb
SECURITY DEFINER
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id bigint;
    v_unit_id     bigint;
    v_org_id      bigint;

    context       jsonb;
    email_data    jsonb;

    occasion_data jsonb;
    unit_data     jsonb;
    org_data      jsonb;

    final_result  jsonb;
BEGIN
    -- 1. Resolve Hierarchy based on Entity Type
    IF p_entity_type = 'occasion' THEN
        v_occasion_id := p_entity_id;

        -- Get Unit & Org from Occasion
        SELECT unit, organization INTO v_unit_id, v_org_id
        FROM public.occasions WHERE id = v_occasion_id;

        IF v_unit_id IS NULL THEN
            RAISE EXCEPTION 'Occasion not found: %', p_entity_id;
        END IF;

    ELSIF p_entity_type = 'unit' THEN
        v_unit_id := p_entity_id;
        v_occasion_id := NULL;

        -- Get Org from Unit
        SELECT organization INTO v_org_id
        FROM public.units WHERE id = v_unit_id;

        IF v_org_id IS NULL THEN
            RAISE EXCEPTION 'Unit not found: %', p_entity_id;
        END IF;
    ELSE
        RAISE EXCEPTION 'Invalid entity type: %', p_entity_type;
    END IF;

    -- 2. Build Context for Template Retrieval
    context := jsonb_build_object(
        'occasion', v_occasion_id,
        'unit', v_unit_id,
        'organization', v_org_id
    );

    -- 3. Retrieve Templates (using core logic)
    email_data := public.get_all_email_templates(context);

    -- 4. Retrieve Entity Details for Response

    -- Organization
    SELECT jsonb_build_object('id', id, 'title', title, 'data', data)
    INTO org_data
    FROM public.organizations WHERE id = v_org_id;

    -- Unit
    SELECT jsonb_build_object('id', id, 'title', title, 'data', COALESCE(data, '{}'::jsonb), 'email', data->>'reply_to')
    INTO unit_data
    FROM public.units WHERE id = v_unit_id;

    -- Occasion (if applicable)
    IF v_occasion_id IS NOT NULL THEN
        SELECT jsonb_build_object('id', id, 'title', title, 'data', COALESCE(data, '{}'::jsonb), 'email', data->>'reply_to')
        INTO occasion_data
        FROM public.occasions WHERE id = v_occasion_id;
    ELSE
        occasion_data := NULL;
    END IF;

    -- 5. Build Final Result
    final_result := jsonb_build_object(
        'occasion',     occasion_data,
        'unit',         unit_data,
        'organization', org_data,
        'templates',    email_data
    );

    RETURN final_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_entity_email_templates(text, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_entity_email_templates(text, bigint) TO authenticated, service_role;


-- Source: database/functions/eshop_orders/scan_ticket.sql
CREATE OR REPLACE FUNCTION public.scan_ticket(scanned_id TEXT, scanned_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    ticket_row RECORD;
    order_json JSONB;
    products_json JSONB;
    spot_json JSONB;
    groups_json JSONB; -- New variable for groups
    order_id BIGINT;
    occasion_id BIGINT;
    hide_price BOOLEAN := FALSE;
    target_user_id UUID; -- New variable to store the resolved User ID
    expected_scan_code TEXT;
    is_uuid BOOLEAN;
    -- Deposit info variables
    v_deposit_amount NUMERIC;
    v_paid NUMERIC;
    v_amount NUMERIC;
    v_deposit_deadline_days INT;
    v_deposit_deadline TEXT;
    v_occ_start_time TIMESTAMPTZ;
    v_occ_features JSONB;
    v_deposit_feature JSONB;
    v_deposit_info JSONB;
BEGIN
    -----------------------------------------------------
    -- 1. Attempt to find ticket by Ticket Symbol
    -----------------------------------------------------
    SELECT *
      INTO ticket_row
    FROM eshop.tickets
    WHERE ticket_symbol = scanned_id
    LIMIT 1;

    -----------------------------------------------------
    -- 1.a. Fallback: Scan by User ID if Ticket Symbol not found
    -----------------------------------------------------
    IF ticket_row IS NULL THEN
        -- Check if the scanned_id is a valid UUID format
        is_uuid := scanned_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';

        IF is_uuid THEN
            -- If scanned by UUID, we know the user immediately
            target_user_id := scanned_id::UUID;

            SELECT t.*
              INTO ticket_row
            FROM public.occasion_users ou
            JOIN public.occasions o ON ou.occasion = o.id
            JOIN public.occasions_hidden oh ON o.occasion_hidden = oh.id
            JOIN eshop.tickets t ON ou.ticket = t.id
            WHERE ou.user = target_user_id
              AND oh.secret = scanned_code
            LIMIT 1;
        END IF;
    END IF;

    -----------------------------------------------------
    -- 1.b. Final Check if Ticket is still missing
    -----------------------------------------------------
    IF ticket_row IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Ticket or User with valid ticket not found');
    END IF;

    -----------------------------------------------------
    -- 2. Retrieve the associated order ID
    -----------------------------------------------------
    SELECT opt."order" INTO order_id
    FROM eshop.order_product_ticket opt
    WHERE opt.ticket = ticket_row.id
    LIMIT 1;

    IF order_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Order for ticket not found');
    END IF;

    -----------------------------------------------------
    -- 3. Retrieve the occasion ID from the order
    -----------------------------------------------------
    SELECT o.occasion, occ.link = 'r48vetrkovice2026'
      INTO occasion_id, hide_price
    FROM eshop.orders o
    JOIN public.occasions occ ON occ.id = o.occasion
    WHERE o.id = order_id
    LIMIT 1;

    IF occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Occasion for order not found');
    END IF;

    -----------------------------------------------------
    -- 3.b. Resolve User ID if not already found via UUID scan
    -----------------------------------------------------
    -- If we found the ticket via Symbol (Step 1), we need to find who holds it
    IF target_user_id IS NULL THEN
        SELECT "user" INTO target_user_id
        FROM public.occasion_users
        WHERE ticket = ticket_row.id
          AND occasion = occasion_id
        LIMIT 1;
    END IF;

    -----------------------------------------------------
    -- 4. Retrieve the expected scan_code
    -----------------------------------------------------
    SELECT oh.secret
      INTO expected_scan_code
    FROM public.occasions_hidden oh
    JOIN public.occasions o ON o.occasion_hidden = oh.id
    WHERE o.id = occasion_id
    LIMIT 1;

    IF expected_scan_code IS NULL THEN
        RETURN jsonb_build_object('code', 400, 'message', 'Scan code not defined for this occasion');
    END IF;

    -----------------------------------------------------
    -- 5. Validate the scanned_code
    -----------------------------------------------------
    IF scanned_code IS DISTINCT FROM expected_scan_code THEN
        RETURN jsonb_build_object('code', 401, 'message', 'Scan code is not correct');
    END IF;

    -----------------------------------------------------
    -- 6. Fetch order, products, spot, AND GROUPS
    -----------------------------------------------------

    -- A. Fetch Order
    SELECT CASE
             WHEN hide_price THEN
               (to_jsonb(o) - 'price') || jsonb_build_object(
                 'data',
                 CASE
                   WHEN jsonb_typeof(o.data->'tickets') = 'array' THEN
                     jsonb_set(
                       o.data,
                       '{tickets}',
                       COALESCE(
                         (
                           SELECT jsonb_agg(
                             CASE
                               WHEN jsonb_typeof(ticket->'products') = 'array' THEN
                                 jsonb_set(
                                   ticket,
                                   '{products}',
                                   COALESCE(
                                     (
                                       SELECT jsonb_agg(product - 'price')
                                       FROM jsonb_array_elements(ticket->'products') AS product
                                     ),
                                     '[]'::jsonb
                                   ),
                                   FALSE
                                 )
                               ELSE ticket
                             END
                           )
                           FROM jsonb_array_elements(o.data->'tickets') AS ticket
                         ),
                         '[]'::jsonb
                       ),
                       FALSE
                     )
                   ELSE o.data
                 END
               )
             ELSE to_jsonb(o)
           END
      INTO order_json
    FROM eshop.orders o
    WHERE o.id = order_id;

    -- B. Fetch Products
    SELECT jsonb_agg(
             CASE
               WHEN hide_price THEN
                 jsonb_build_object(
                   'id', p.id,
                   'title', p.title,
                   'order', p."order",
                   'description', p.description,
                   'currency_code', p.currency_code
                 )
               ELSE
                 jsonb_build_object(
                   'id', p.id,
                   'title', p.title,
                   'price', p.price,
                   'order', p."order",
                   'description', p.description,
                   'currency_code', p.currency_code
                 )
             END
           )
      INTO products_json
    FROM eshop.products p
    WHERE p.id IN (
        SELECT opt.product
          FROM eshop.order_product_ticket opt
         WHERE opt.ticket = ticket_row.id
    );

    -- C. Fetch Spot
    SELECT row_to_json(s) INTO spot_json
    FROM eshop.spots s
    WHERE s.order_product_ticket IN (
        SELECT opt.id
          FROM eshop.order_product_ticket opt
         WHERE opt.ticket = ticket_row.id
    )
    LIMIT 1;

    -- D. Fetch User Groups (New Logic)
    IF target_user_id IS NOT NULL THEN
        -- We construct a JSON object compatible with UserGroupInfoModel
        -- We join user_groups -> user_group_info -> places to get full context
        SELECT jsonb_agg(
                 to_jsonb(ugi) ||
                 jsonb_build_object(
                    'place_object', row_to_json(p)
                 )
               )
        INTO groups_json
        FROM public.user_groups ug
        JOIN public.user_group_info ugi ON ug."group" = ugi.id
        LEFT JOIN public.places p ON ugi.place = p.id
        WHERE ug."user" = target_user_id
          AND ugi.occasion = occasion_id;
    END IF;

    -----------------------------------------------------
    -- 6E. Fetch deposit info for deposit orders
    -----------------------------------------------------
    SELECT pi.deposit_amount, pi.paid, pi.amount
    INTO v_deposit_amount, v_paid, v_amount
    FROM eshop.payment_info pi
    JOIN eshop.orders o ON o.payment_info = pi.id
    WHERE o.id = order_id;

    IF v_deposit_amount IS NOT NULL THEN
        -- Get occasion features and start_time for deposit deadline
        SELECT occ.features, occ.start_time
        INTO v_occ_features, v_occ_start_time
        FROM public.occasions occ
        WHERE occ.id = occasion_id;

        -- Read deposit deadline from deposit feature in features JSONB
        SELECT elem INTO v_deposit_feature
        FROM jsonb_array_elements(v_occ_features) elem
        WHERE elem->>'code' = 'deposit';

        v_deposit_deadline_days := (v_deposit_feature->>'deposit_deadline_days')::int;
        v_deposit_deadline := v_deposit_feature->>'deposit_deadline';

        v_deposit_info := jsonb_build_object(
            'remaining_amount', GREATEST(0, COALESCE(v_amount, 0) - COALESCE(v_paid, 0)),
            'is_fully_paid', COALESCE(v_paid, 0) >= COALESCE(v_amount, 0),
            'deadline_type', CASE
                WHEN v_deposit_deadline = 'on_site' THEN 'on_site'
                WHEN v_deposit_deadline_days IS NOT NULL THEN 'date'
                ELSE NULL
            END,
            'deadline_date', CASE
                WHEN v_deposit_deadline_days IS NOT NULL AND v_deposit_deadline IS DISTINCT FROM 'on_site'
                THEN (v_occ_start_time - make_interval(days => v_deposit_deadline_days))::text
                ELSE NULL
            END,
            'deposit_amount', v_deposit_amount,
            'total_amount', v_amount,
            'paid_amount', COALESCE(v_paid, 0)
        );
    END IF;

    -----------------------------------------------------
    -- 7. Return the compiled JSONB response
    -----------------------------------------------------
    RETURN jsonb_build_object(
        'code', 200,
        'ticket', row_to_json(ticket_row),
        'order', order_json,
        'products', products_json,
        'spot', spot_json,
        'groups', COALESCE(groups_json, '[]'::jsonb),
        'deposit_info', v_deposit_info
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'code', 500,
            'message', 'An unexpected error occurred: ' || SQLERRM
        );
END;
$$;


-- Source: database/functions/eshop_orders/update_ticket_to_used.sql
CREATE OR REPLACE FUNCTION public.update_ticket_to_used(
    ticket_id bigint,
    scan_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    occasion_id bigint;
    current_state text;
    expected_scan_code text;
BEGIN
    -- 1. Validate Ticket Existence
    IF NOT EXISTS (
        SELECT 1 FROM eshop.tickets WHERE id = ticket_id
    ) THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Ticket not found.'
        );
    END IF;

    -- 2. Retrieve Associated Occasion ID AND Current State
    SELECT occasion, state
    INTO occasion_id, current_state
    FROM eshop.tickets
    WHERE id = ticket_id;

    -- Check if occasion_id is present (Integrity check)
    IF occasion_id IS NULL THEN
        RETURN jsonb_build_object(
            'code', 404,
            'message', 'Occasion associated with ticket not found.'
        );
    END IF;

    -- 2a. Validate Ticket State (New Check)
    IF current_state = 'used' THEN
        RETURN jsonb_build_object(
            'code', 409,
            'message', 'Ticket has already been used.'
        );
    ELSIF current_state = 'storno' THEN
        RETURN jsonb_build_object(
            'code', 409,
            'message', 'Ticket is cancelled (storno).'
        );
    END IF;

    -- 3. Retrieve Expected Scan Code from occasions_hidden via foreign key
    SELECT oh.secret
    INTO expected_scan_code
    FROM public.occasions_hidden oh
    JOIN public.occasions o ON o.occasion_hidden = oh.id
    WHERE o.id = occasion_id
    LIMIT 1;

    -- Check if scan_code is defined
    IF expected_scan_code IS NULL THEN
        RETURN jsonb_build_object(
            'code', 400,
            'message', 'Scan code not defined for occasion.'
        );
    END IF;

    -- 4. Validate Provided Scan Code
    IF scan_code IS DISTINCT FROM expected_scan_code THEN
        RETURN jsonb_build_object(
            'code', 401,
            'message', 'Scan code is not correct.'
        );
    END IF;

    -- 5. Update Ticket State to 'used' AND update timestamp
    UPDATE eshop.tickets
    SET
        state = 'used',
        updated_at = now()
    WHERE id = ticket_id;

    -- 6. Return Success Message
    RETURN jsonb_build_object(
        'code', 200,
        'message', 'Ticket state updated to used successfully.'
    );

EXCEPTION
    WHEN OTHERS THEN
        -- Handle any unexpected exceptions
        RETURN jsonb_build_object(
            'code', 500,
            'message', 'An unexpected error occurred.',
            'detail', SQLERRM
        );
END;
$$;

-- Source: database/functions/events/sign_user_to_event.sql
create or replace function public.sign_user_to_event (ev bigint, usr uuid) returns jsonb
 language plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
 as $$
declare
  i_max_participants integer;
  current_participants integer;
  event_group_count integer;
  event_group integer;
  exclusive_event_count integer;
  already_in_count integer;
  current_men_participants integer;
  current_women_participants integer;
  b_split_for_men_women boolean;
  is_current_user_male boolean;

  registration_start timestamp;
  event_start_time timestamp;
  event_end_time timestamp;
  workshops_feature jsonb;
  e RECORD;

  v_occasion bigint;
  v_is_counseling boolean;
  counseling_feature jsonb;
  v_limit integer;
  v_active integer;

begin
  -- Authorize before any membership or attendance mutation.
  IF auth.uid() IS NULL OR usr IS NULL THEN
    RETURN jsonb_build_object('code', 403);
  END IF;
  IF auth.uid() IS DISTINCT FROM usr THEN
      IF NOT EXISTS (
        SELECT 1 FROM user_companions uc
        JOIN events ce ON ce.id=ev AND ce.occasion=uc.occasion
        WHERE uc."user" = auth.uid() AND uc.companion = usr
          AND (public.get_companion_feature_policy_v1(uc.occasion)->>'is_enabled')::boolean) THEN
          IF (SELECT get_is_editor_on_occasion((SELECT occasion FROM events WHERE id = ev))) IS NOT TRUE THEN
            RETURN json_build_object('code', 403);
          END IF;
      END IF;
  END IF;

  -- Check if the user already exists on the occasion
  IF (SELECT get_exists_on_occasion_user(usr, (SELECT occasion FROM events WHERE id = ev))) <> TRUE THEN

      -- Check if the occasion is open
      IF (SELECT is_open FROM occasions WHERE id = (SELECT occasion FROM events WHERE id = ev)) = TRUE THEN

          -- Add the user to the occasion
          PERFORM public.add_user_to_occasion_internal_v1(
            (SELECT occasion FROM events WHERE id = ev), usr);

          -- Recheck if the user now exists on the occasion
          IF (SELECT get_exists_on_occasion_user(usr, (SELECT occasion FROM events WHERE id = ev))) <> TRUE THEN
              -- If user still doesn't exist, return a 403 response
              RETURN json_build_object('code', 403, 'message', 'Failed to add user to occasion');
          END IF;
      ELSE
          -- If the occasion is not open, return a 403 response
          RETURN json_build_object('code', 403, 'message', 'Occasion is not open');
      END IF;
  END IF;


  -- Resolve the occasion and detect whether this event is a counseling slot.
  SELECT occasion, (data->>'is_counseling_slot')::boolean IS TRUE
    INTO v_occasion, v_is_counseling
  FROM events
  WHERE id = ev;

  IF v_is_counseling THEN
    -- Counseling slots use their own registration window from the "counseling"
    -- feature; the workshops gate (104/108) does not apply (decision R1).
    SELECT elem
      INTO counseling_feature
    FROM occasions,
         jsonb_array_elements(features) elem
    WHERE id = v_occasion
      AND elem->>'code' = 'counseling'
    LIMIT 1;

    -- (a) Feature must be present and enabled, else registration is closed.
    IF counseling_feature IS NULL
       OR (counseling_feature->>'is_enabled')::boolean IS NOT TRUE THEN
      RETURN json_build_object('code', 108);
    END IF;

    registration_start := (counseling_feature->>'registration_start_time')::timestamp;
    IF registration_start IS NOT NULL THEN
      IF CURRENT_TIMESTAMP AT TIME ZONE 'UTC' < registration_start THEN
        RETURN json_build_object('code', 104, 'events_registration_start', registration_start AT TIME ZONE 'UTC');
      END IF;
    END IF;

    -- (b) Limit of the user's future counseling bookings (0 = unlimited).
    v_limit := COALESCE((counseling_feature->>'max_active_bookings')::int, 1);
    IF v_limit > 0 THEN
      SELECT count(*)
        INTO v_active
      FROM event_users eu
      JOIN events e2 ON e2.id = eu.event
      WHERE eu."user" = usr
        AND e2.occasion = v_occasion
        AND (e2.data->>'is_counseling_slot')::boolean IS TRUE
        AND e2.end_time > CURRENT_TIMESTAMP AT TIME ZONE 'UTC';
      IF v_active >= v_limit THEN
        RETURN json_build_object('code', 109);
      END IF;
    END IF;
  ELSE
    -- Check registration start time from occasions.features for the "workshops" feature
    SELECT elem
    INTO workshops_feature
    FROM occasions,
         jsonb_array_elements(features) elem
    WHERE id = (SELECT occasion FROM events WHERE id = ev)
      AND elem->>'code' = 'workshops'
    LIMIT 1;

    IF workshops_feature IS NOT NULL THEN
      -- If the workshops feature is not enabled, do not allow sign in
      IF (workshops_feature->>'is_enabled')::boolean IS NOT TRUE THEN
        RETURN json_build_object('code', 108, 'message', 'Registration for workshops is not enabled');
      END IF;
      -- If start_time is provided, enforce registration start time
      registration_start := (workshops_feature->>'start_time')::timestamp;
      IF registration_start IS NOT NULL THEN
        IF CURRENT_TIMESTAMP AT TIME ZONE 'UTC' < registration_start THEN
          RETURN json_build_object('code', 104, 'events_registration_start', registration_start AT TIME ZONE 'UTC');
        END IF;
      END IF;
    END IF;
    -- If the workshops feature is not present or its start_time is null, sign in is enabled
  END IF;

  SELECT start_time, end_time INTO event_start_time, event_end_time
  FROM events
  WHERE id = ev;

  IF CURRENT_TIMESTAMP AT TIME ZONE 'UTC' > event_end_time THEN
    RETURN json_build_object('code', 100);
  END IF;

  SELECT count(*) FROM event_users eu WHERE eu.event = ev AND eu."user" = usr INTO already_in_count;
  IF already_in_count > 0 THEN
    RETURN json_build_object('code', 103);
  END IF;

  SELECT count(*) FROM exclusive_events WHERE event = ev INTO event_group_count;
  IF event_group_count > 0 THEN
    SELECT "group" FROM exclusive_events WHERE event = ev INTO event_group;
    SELECT count(*) FROM exclusive_events ee JOIN event_users eu ON ee.event = eu.event
      WHERE ee."group" = event_group AND eu."user" = usr INTO exclusive_event_count;
    IF exclusive_event_count > 0 THEN
      RETURN json_build_object('code', 102);
    END IF;
  END IF;

  -- Check if the event already has the maximum number of participants
  SELECT max_participants FROM events WHERE id = ev INTO i_max_participants;
  SELECT split_for_men_women FROM events WHERE id = ev INTO b_split_for_men_women;

  IF b_split_for_men_women THEN
    SELECT exists (SELECT sex FROM user_info WHERE id = usr AND sex = 'male') INTO is_current_user_male;
    SELECT count(*) FROM event_users eu JOIN user_info ei ON eu."user" = ei.id
      WHERE event = ev AND ei.sex = 'male' INTO current_men_participants;
    SELECT count(*) FROM event_users eu JOIN user_info ei ON eu."user" = ei.id
      WHERE event = ev AND ei.sex <> 'male' INTO current_women_participants;
    IF is_current_user_male AND current_men_participants >= (i_max_participants / 2) THEN
      RETURN json_build_object('code', 105);
    ELSIF NOT is_current_user_male AND current_women_participants >= (i_max_participants / 2) THEN
      RETURN json_build_object('code', 106);
    END IF;
  END IF;

  -- Loop through user_events to check for scheduling conflicts
  FOR e IN
      SELECT events.id, events.start_time, events.end_time
      FROM events
      JOIN event_users ON events.id = event_users.event
      WHERE event_users."user" = usr
  LOOP
      IF ((e.start_time < event_end_time AND e.start_time > event_start_time) OR
          (e.end_time < event_end_time AND e.end_time > event_start_time) OR
          (e.start_time = event_start_time) OR
          (e.end_time = event_end_time)) THEN
          RETURN json_build_object('code', 107);
      END IF;
  END LOOP;

  SELECT count(*) FROM event_users WHERE event = ev INTO current_participants;
  IF current_participants >= i_max_participants THEN
    RETURN json_build_object('code', 101);
  ELSE
    INSERT INTO event_users (event, "user") VALUES (ev, usr);
    RETURN json_build_object('code', 200);
  END IF;
END;
$$;

-- Error Codes:
-- 200: OK
-- 100: Event is over
-- 101: Event is full
-- 102: Exclusive event already taken
-- 103: Already signed in
-- 104: Registration not started yet (events_registration_start in response);
--      for counseling slots the window comes from the "counseling" feature
--      (registration_start_time) instead of the workshops feature.
-- 105: Maximum male participants reached
-- 106: Maximum female participants reached
-- 107: Conflicting event schedule
-- 108: Registration is not enabled — workshops feature disabled, or, for a
--      counseling slot, the "counseling" feature is missing or not enabled.
-- 109: Counseling booking limit reached (max_active_bookings of the "counseling"
--      feature; counts the user's future counseling reservations on the occasion).


-- Source: database/functions/events/sign_user_out_of_event.sql
CREATE OR REPLACE FUNCTION public.sign_user_out_of_event(ev BIGINT, usr UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    event_end_time TIMESTAMP;
BEGIN
  -- Authorize before any membership or attendance mutation.
  IF auth.uid() IS NULL OR usr IS NULL THEN
    RETURN jsonb_build_object('code', 403);
  END IF;
    IF auth.uid() IS DISTINCT FROM usr THEN
        IF NOT EXISTS (
            SELECT 1 FROM user_companions uc
            JOIN events ce ON ce.id=ev AND ce.occasion=uc.occasion
            WHERE uc."user" = auth.uid() AND uc.companion = usr
              AND (public.get_companion_feature_policy_v1(uc.occasion)->>'is_enabled')::boolean ) THEN
            IF (SELECT get_is_editor_on_occasion((SELECT occasion FROM events WHERE id = ev))) IS NOT TRUE THEN
                    RETURN json_build_object('code', 403);
            END IF;
        END IF;
    END IF;
    -- Existing checks for occasion user and editor
    IF (SELECT get_exists_on_occasion_user(usr, (SELECT occasion FROM events WHERE id = ev))) <> TRUE THEN
        RETURN json_build_object('code', 403);
    END IF;


    -- Check if the user is signed in to the event
    IF (SELECT COUNT(*) FROM event_users WHERE event = ev AND "user" = usr) = 0 THEN
        RETURN json_build_object('code', 404, 'message', 'User is not signed into this event');
    END IF;

    -- Retrieve event end time
    SELECT end_time INTO event_end_time
    FROM events
    WHERE id = ev;

    -- Check if the event has already ended
    IF CURRENT_TIMESTAMP AT TIME ZONE 'UTC' > event_end_time THEN
        RETURN json_build_object('code', 201, 'message', 'Cannot sign out after the event has ended');
    END IF;

    -- Remove the user from the event
    DELETE FROM event_users WHERE event = ev AND "user" = usr;
    RETURN json_build_object('code', 200, 'message', 'User signed out successfully');
END;
$$;

NOTIFY pgrst, 'reload schema';
