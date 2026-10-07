CREATE OR REPLACE FUNCTION public.import_users_from_tickets(p_occasion_id bigint)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    ticket_record RECORD;
    order_data JSONB;
    user_email TEXT;
    v_sign_in_email TEXT;
    user_name TEXT;
    user_surname TEXT;
    user_sex TEXT;
    user_data JSONB;
    v_user_id UUID;
    v_organization_id BIGINT;
    field_element JSONB;
    field_key TEXT;

    field_info RECORD;
    field_value TEXT;
    v_text1 TEXT;
    v_text2 TEXT;
    v_birthDate TEXT;

    v_occasion_user_row public.occasion_users%ROWTYPE;
    new_email TEXT;

    -- Arrays to store results
    inserted_users JSONB[] := ARRAY[]::JSONB[];
    updated_users JSONB[] := ARRAY[]::JSONB[];
    deleted_users JSONB[] := ARRAY[]::JSONB[];

    storno_record RECORD;
    deleted_user_info RECORD;
    update_report_info RECORD;
BEGIN
    PERFORM public.lock_activity_aggregate_internal_v1(p_occasion_id);
    -- 1. Get the organization_id from the occasion
    SELECT organization INTO v_organization_id FROM public.occasions WHERE id = p_occasion_id;

    IF v_organization_id IS NULL THEN
        RAISE EXCEPTION 'Occasion with id % not found or has no organization.', p_occasion_id;
    END IF;

    -- 2. Handle Storno (Canceled) Tickets
    FOR storno_record IN
        SELECT ou."user", ou.ticket
        FROM public.occasion_users ou
        JOIN eshop.tickets t ON ou.ticket = t.id
        WHERE ou.occasion = p_occasion_id
          AND ou.ticket IS NOT NULL
          AND t.state = 'storno'
    LOOP
        SELECT ui.email_readonly, ui.name, ui.surname
        INTO deleted_user_info
        FROM public.user_info ui
        WHERE ui.id = storno_record."user";

        PERFORM public.remove_occasion_user_domain_internal_v1(p_occasion_id,storno_record."user");

        deleted_users := array_append(deleted_users,
            jsonb_build_object(
                'email', deleted_user_info.email_readonly,
                'name', deleted_user_info.name,
                'surname', deleted_user_info.surname,
                'ticket_id', storno_record.ticket
            )
        );
    END LOOP;

    -- 3. IMPORT & SYNC LOGIC
    FOR ticket_record IN
        SELECT DISTINCT ON (t.id)
            t.id as ticket_id,
            o.data as order_data,
            ou."user" as existing_occasion_user_id
        FROM eshop.tickets t
        JOIN eshop.order_product_ticket opt ON t.id = opt.ticket
        JOIN eshop.orders o ON opt."order" = o.id
        LEFT JOIN public.occasion_users ou ON t.id = ou.ticket
        WHERE t.occasion = p_occasion_id
          AND t.state IN ('ordered', 'sent', 'used', 'paid')
        ORDER BY t.id, o.id DESC
    LOOP
        order_data := ticket_record.order_data;
        user_email := lower(trim(order_data->>'email'));
        user_name := order_data->>'name';
        user_surname := order_data->>'surname';
        user_sex := NULL;

        v_text1 := NULL;
        v_text2 := NULL;
        v_birthDate := NULL;

        -- Extract Form Fields (Generic loop, checking specifically for known titles)
        IF jsonb_typeof(order_data->'fields') = 'array' THEN
            FOR field_element IN SELECT * FROM jsonb_array_elements(order_data->'fields')
            LOOP
                field_key := (SELECT * FROM jsonb_object_keys(field_element));
                field_value := field_element->>field_key;

                SELECT ff.type, ff.title
                INTO field_info
                FROM public.form_fields ff
                WHERE ff.id = field_key::bigint;

                -- Basic mappings
                IF field_info.type = 'sex' THEN
                    user_sex := field_value;
                END IF;

--                -- Custom mappings (removed IF ID=36 check to make it generic for the feature)
--                CASE field_info.title
--                    WHEN 'Typ účastníka' THEN
--                        v_text1 := field_value;
--                    WHEN 'Přípravný tým' THEN
--                        v_text2 := field_value;
--                    WHEN 'Datum narození' THEN
--                        v_birthDate := field_value;
--                    ELSE
--                        -- Do nothing
--                END CASE;
            END LOOP;
        END IF;

        -- ========================================================
        -- CASE A: EXISTING OCCASION USER -> UPDATE BY ID
        -- ========================================================
        IF ticket_record.existing_occasion_user_id IS NOT NULL THEN
            DECLARE
                current_ou_data JSONB;
                update_payload JSONB := '{}'::jsonb;
                target_uuid UUID := ticket_record.existing_occasion_user_id; -- STRICT ID DEPENDENCY
            BEGIN
                SELECT ui.email_readonly
                  INTO v_sign_in_email
                  FROM public.user_info ui
                 WHERE ui.id = target_uuid;

                -- Get current occasion data
                SELECT data INTO current_ou_data
                FROM public.occasion_users
                WHERE "user" = target_uuid AND occasion = p_occasion_id;

                -- Build payload comparing Order Data vs Current DB Data
                IF v_sign_in_email IS NOT NULL AND COALESCE(current_ou_data->>'email', 'NULL_FLAG') != v_sign_in_email THEN
                    update_payload := update_payload || jsonb_build_object('email', v_sign_in_email);
                END IF;
                IF user_name IS NOT NULL AND COALESCE(current_ou_data->>'name', 'NULL_FLAG') != user_name THEN
                    update_payload := update_payload || jsonb_build_object('name', user_name);
                END IF;
                IF user_surname IS NOT NULL AND COALESCE(current_ou_data->>'surname', 'NULL_FLAG') != user_surname THEN
                    update_payload := update_payload || jsonb_build_object('surname', user_surname);
                END IF;
                IF user_sex IS NOT NULL AND COALESCE(current_ou_data->>'sex', 'NULL_FLAG') != user_sex THEN
                    update_payload := update_payload || jsonb_build_object('sex', user_sex);
                END IF;
                -- Custom fields
--                IF v_text1 IS NOT NULL AND COALESCE(current_ou_data->>'text1', 'NULL_FLAG') != v_text1 THEN
--                    update_payload := update_payload || jsonb_build_object('text1', v_text1);
--                END IF;
--                IF v_text2 IS NOT NULL AND COALESCE(current_ou_data->>'text2', 'NULL_FLAG') != v_text2 THEN
--                    update_payload := update_payload || jsonb_build_object('text2', v_text2);
--                END IF;
--                IF v_birthDate IS NOT NULL AND COALESCE(current_ou_data->>'birthDate', 'NULL_FLAG') != v_birthDate THEN
--                    update_payload := update_payload || jsonb_build_object('birthDate', v_birthDate);
--                END IF;

                -- Perform Updates if needed
                IF update_payload != '{}'::jsonb THEN
                    -- 1. Update Occasion Specific Data
                    UPDATE public.occasion_users
                    SET data = data || update_payload
                    WHERE "user" = target_uuid
                      AND occasion = p_occasion_id;

                    -- 2. Update Global User Info (Sync core fields)
                    UPDATE public.user_info
                    SET
                        name = COALESCE(update_payload->>'name', name),
                        surname = COALESCE(update_payload->>'surname', surname),
                        sex = COALESCE(update_payload->>'sex', sex)
                    WHERE id = target_uuid;

                    -- Logging
                    SELECT ui.email_readonly, ui.name, ui.surname
                    INTO update_report_info
                    FROM public.user_info ui
                    WHERE ui.id = target_uuid;

                    updated_users := array_append(updated_users,
                        jsonb_build_object(
                            'id', target_uuid, -- Return ID for safety
                            'email', update_report_info.email_readonly,
                            'name', update_report_info.name,
                            'surname', update_report_info.surname,
                            'reason', 'data_sync',
                            'changes', update_payload
                        )
                    );
                END IF;
            END;

        -- ========================================================
        -- CASE B: NO LINKED USER -> CREATE OR LINK (FALLBACK TO EMAIL)
        -- ========================================================
        ELSE
            -- 1. Check if user exists globally by email
            SELECT id INTO v_user_id
            FROM public.user_info
            WHERE email_readonly = user_email AND organization = v_organization_id;

            IF v_user_id IS NOT NULL THEN
                -- USER EXISTS GLOBALLY
                SELECT * INTO v_occasion_user_row
                FROM public.occasion_users
                WHERE "user" = v_user_id AND occasion = p_occasion_id;

                IF v_occasion_user_row."user" IS NOT NULL AND v_occasion_user_row.ticket IS NOT NULL THEN
                    -- User exists on occasion AND has a ticket -> DUPLICATE EMAIL Conflict
                    -- Create new user with +suffix
                    new_email := public.allocate_user_sign_in_email(
                        v_organization_id, user_email
                    );

                    user_data := jsonb_build_object('name', user_name, 'surname', user_surname, 'email', new_email, 'sex', user_sex);
--                    IF v_text1 IS NOT NULL THEN user_data := user_data || jsonb_build_object('text1', v_text1); END IF;
--                    IF v_text2 IS NOT NULL THEN user_data := user_data || jsonb_build_object('text2', v_text2); END IF;
--                    IF v_birthDate IS NOT NULL THEN user_data := user_data || jsonb_build_object('birthDate', v_birthDate); END IF;

                    v_user_id := create_user_in_organization_with_data_pure(
                        v_organization_id, new_email, user_email,
                        gen_random_uuid()::text, user_data
                    );
                    PERFORM public.add_user_to_occasion_internal_v1(p_occasion_id, v_user_id);
                    UPDATE public.occasion_users SET ticket = ticket_record.ticket_id WHERE "user" = v_user_id AND occasion = p_occasion_id;

                    inserted_users := array_append(inserted_users, jsonb_build_object('id', v_user_id, 'email', new_email, 'name', user_name, 'surname', user_surname));
                ELSE
                    -- LINK EXISTING USER (User exists, but no ticket on this occasion)

                    user_data := jsonb_build_object('name', user_name, 'surname', user_surname, 'email', user_email, 'sex', user_sex);
--                    IF v_text1 IS NOT NULL THEN user_data := user_data || jsonb_build_object('text1', v_text1); END IF;
--                    IF v_text2 IS NOT NULL THEN user_data := user_data || jsonb_build_object('text2', v_text2); END IF;
--                    IF v_birthDate IS NOT NULL THEN user_data := user_data || jsonb_build_object('birthDate', v_birthDate); END IF;

                    -- Update Global Info
                    UPDATE public.user_info
                    SET
                        name = user_name,
                        surname = user_surname,
                        sex = user_sex,
                        data = COALESCE(user_info.data, '{}'::jsonb) || user_data
                    WHERE id = v_user_id;

                    IF v_occasion_user_row."user" IS NULL THEN
                        -- Link to occasion
                        PERFORM public.add_user_to_occasion_internal_v1(p_occasion_id, v_user_id);
                    END IF;

                    -- Update Occasion Data & Ticket
                    UPDATE public.occasion_users
                    SET
                        data = COALESCE(occasion_users.data, '{}'::jsonb) || user_data,
                        ticket = ticket_record.ticket_id
                    WHERE "user" = v_user_id AND occasion = p_occasion_id;

                    updated_users := array_append(updated_users, jsonb_build_object('id', v_user_id, 'email', user_email, 'name', user_name, 'surname', user_surname, 'reason', 'initial_import_link'));
                END IF;
            ELSE
                -- NEW USER CREATION
                user_data := jsonb_build_object('name', user_name, 'surname', user_surname, 'email', user_email, 'sex', user_sex);
--                IF v_text1 IS NOT NULL THEN user_data := user_data || jsonb_build_object('text1', v_text1); END IF;
--                IF v_text2 IS NOT NULL THEN user_data := user_data || jsonb_build_object('text2', v_text2); END IF;
--                IF v_birthDate IS NOT NULL THEN user_data := user_data || jsonb_build_object('birthDate', v_birthDate); END IF;

                v_user_id := create_user_in_organization_with_data_pure(
                    v_organization_id, user_email, user_email,
                    gen_random_uuid()::text, user_data
                );
                PERFORM public.add_user_to_occasion_internal_v1(p_occasion_id, v_user_id);
                UPDATE public.occasion_users SET ticket = ticket_record.ticket_id WHERE "user" = v_user_id AND occasion = p_occasion_id;

                inserted_users := array_append(inserted_users, jsonb_build_object('id', v_user_id, 'email', user_email, 'name', user_name, 'surname', user_surname));
            END IF;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'inserted', to_jsonb(inserted_users),
        'updated', to_jsonb(updated_users),
        'deleted', to_jsonb(deleted_users)
    );
END;
$$;
