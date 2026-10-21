ALTER TABLE public.user_info
  ADD COLUMN IF NOT EXISTS email_delivery text;

-- Recover delivery overrides only for numeric sign-in aliases created by the
-- legacy ticket importer. Ordinary accounts keep NULL and resolve through
-- email_readonly; unrelated order contacts never become profile identity.
WITH latest_order_email AS (
    SELECT DISTINCT ON (ou."user")
           ou."user" AS user_id,
           lower(btrim(o.data->>'email')) AS email
      FROM public.occasion_users ou
      JOIN eshop.order_product_ticket opt ON opt.ticket = ou.ticket
      JOIN eshop.orders o ON o.id = opt."order"
     WHERE NULLIF(btrim(o.data->>'email'), '') IS NOT NULL
     ORDER BY ou."user", o.created_at DESC, o.id DESC
)
UPDATE public.user_info ui
   SET email_delivery = lo.email
  FROM latest_order_email lo
 WHERE lo.user_id = ui.id
   AND NULLIF(btrim(ui.email_delivery), '') IS NULL
   AND lower(btrim(ui.email_readonly)) <> lo.email
   AND regexp_replace(
           lower(btrim(ui.email_readonly)), '\+[0-9]+@', '@'
       ) = lo.email;

CREATE UNIQUE INDEX IF NOT EXISTS user_info_organization_sign_in_email_uidx
  ON public.user_info (organization, lower(btrim(email_readonly)))
  WHERE email_readonly IS NOT NULL;

COMMENT ON COLUMN public.user_info.email_readonly IS
  'Organization-unique canonical account email; shared mailboxes use +N aliases.';
COMMENT ON COLUMN public.user_info.email_delivery IS
  'Optional non-unique override used only for outbound account email.';

CREATE OR REPLACE FUNCTION public.allocate_user_sign_in_email(
    p_organization bigint,
    p_delivery_email text
)
RETURNS text
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_delivery_email text := lower(btrim(p_delivery_email));
    v_local_part text;
    v_domain_part text;
    v_candidate text;
    v_suffix integer := 0;
BEGIN
    IF v_delivery_email IS NULL OR v_delivery_email = ''
       OR position('@' IN v_delivery_email) <= 1 THEN
        RAISE EXCEPTION 'INVALID_DELIVERY_EMAIL';
    END IF;

    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'user-sign-in-email:' || p_organization::text, 0
        )
    );

    v_local_part := split_part(v_delivery_email, '@', 1);
    v_domain_part := substring(v_delivery_email FROM position('@' IN v_delivery_email) + 1);

    LOOP
        v_candidate := CASE WHEN v_suffix = 0 THEN v_delivery_email
            ELSE v_local_part || '+' || v_suffix::text || '@' || v_domain_part END;
        EXIT WHEN NOT EXISTS (
            SELECT 1 FROM public.user_info ui
             WHERE ui.organization = p_organization
               AND lower(btrim(ui.email_readonly)) = v_candidate
        );
        v_suffix := v_suffix + 1;
    END LOOP;

    RETURN v_candidate;
END;
$$;

REVOKE ALL ON FUNCTION public.allocate_user_sign_in_email(bigint, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.allocate_user_sign_in_email(bigint, text) FROM anon;
REVOKE ALL ON FUNCTION public.allocate_user_sign_in_email(bigint, text) FROM authenticated;
REVOKE ALL ON FUNCTION public.allocate_user_sign_in_email(bigint, text) FROM service_role;
CREATE OR REPLACE FUNCTION public.create_user_in_organization_with_data_pure(
    org bigint,
    email text,
    email_delivery text,
    password text,
    data jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    usr uuid;
    encrypted_pw text;
    user_meta_data jsonb := '{}';
    _key   text;
    _value text;
    trimmed_data jsonb := '{}';
    original_email text;
    normalized_delivery_email text;
BEGIN
    original_email := lower(trim(email));
    normalized_delivery_email := COALESCE(
        NULLIF(lower(trim(email_delivery)), ''), original_email
    );

    IF original_email IS NULL OR original_email = ''
       OR normalized_delivery_email IS NULL OR normalized_delivery_email = ''
       OR position('@' IN original_email) <= 1
       OR position('@' IN normalized_delivery_email) <= 1 THEN
        RAISE EXCEPTION 'INVALID_USER_EMAIL';
    END IF;

    -- All application writers serialize identity creation per organization.
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended('user-sign-in-email:' || org::text, 0)
    );

    IF EXISTS (
        SELECT 1 FROM public.user_info ui
         WHERE ui.organization = org
           AND lower(btrim(ui.email_readonly)) = original_email
    ) THEN
        RAISE EXCEPTION 'SIGN_IN_EMAIL_ALREADY_EXISTS';
    END IF;

    -- Add organization prefix to the email for auth tables
    email := format('%s+%s', org, original_email);

    -- Trim all values in the data JSONB object and build a new trimmed_data JSONB object
    FOR _key, _value IN
        SELECT key, value FROM jsonb_each_text(data)
    LOOP
        IF _value IS NOT NULL THEN
            trimmed_data := jsonb_set(trimmed_data, array[_key], to_jsonb(trim(_value)), true);
        ELSE
            trimmed_data := jsonb_set(trimmed_data, array[_key], 'null'::jsonb, true);
        END IF;
    END LOOP;

    usr := gen_random_uuid();
    encrypted_pw := crypt(password, gen_salt('bf'));

    -- Insert into auth.users with the email prefixed with organization
    INSERT INTO auth.users
      (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, recovery_sent_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token)
    VALUES
      ('00000000-0000-0000-0000-000000000000', usr, 'authenticated', 'authenticated', email, encrypted_pw, now(), NULL, NULL,
      '{"provider":"email","providers":["email"]}', user_meta_data, now(), now(), '', '', '', '');

    -- Insert into auth.identities with the email prefixed with organization
    INSERT INTO auth.identities (id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    VALUES
      (gen_random_uuid(), usr, usr, format('{"sub":"%s","email":"%s"}', usr::text, email)::jsonb, 'email', NULL, now(), now());

    -- The account email is canonical; store only a distinct delivery override.
    INSERT INTO user_info (
      id, email_readonly, email_delivery, name, surname, sex, phone, birth_date, data,
      organization
    )
    VALUES (
      usr,
      original_email,
      NULLIF(normalized_delivery_email, original_email),
      COALESCE(trimmed_data->>'name', ''),
      COALESCE(trimmed_data->>'surname', ''),
      COALESCE(trimmed_data->>'sex', ''),
      trimmed_data->>'phone',
      NULLIF(trimmed_data->>'birthDate', '')::date,
      trimmed_data,
      org
    );

    RETURN usr;
END;
$$;

-- Compatibility boundary for released callers. New code supplies the delivery
-- address explicitly; ordinary registrations use the sign-in email for both.
CREATE OR REPLACE FUNCTION public.create_user_in_organization_with_data_pure(
    org bigint,
    email text,
    password text,
    data jsonb
)
RETURNS uuid
LANGUAGE sql
SET search_path = public, extensions
AS $$
    SELECT public.create_user_in_organization_with_data_pure(
        org, email, email, password, data
    );
$$;
CREATE OR REPLACE FUNCTION public.import_occasion_users_from_csv_internal_v1(
    p_occasion_id bigint,
    p_rows jsonb,
    p_delete_user_ids jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_unit_id bigint;
    v_organization_id bigint;
    v_row jsonb;
    v_data_patch jsonb;
    v_services_patch jsonb;
    v_group_assignments jsonb := '[]'::jsonb;
    v_user_id uuid;
    v_email text;
    v_delivery_email text;
    v_existing_email text;
    v_has_delivery_email boolean;
    v_response jsonb;
    v_is_occasion_member boolean;
    v_created integer := 0;
    v_updated integer := 0;
    v_deleted integer := 0;
BEGIN
    SELECT o.unit, u.organization
      INTO v_unit_id, v_organization_id
      FROM public.occasions o
      JOIN public.units u ON u.id = o.unit
     WHERE o.id = p_occasion_id;

    IF v_unit_id IS NULL THEN
        RAISE EXCEPTION 'OCCASION_NOT_FOUND';
    END IF;

    IF NOT (
        public.get_is_manager_on_occasion(p_occasion_id)
        OR public.get_is_admin_on_occasion(p_occasion_id)
        OR public.get_is_editor_on_unit(v_unit_id)
    ) THEN
        RAISE EXCEPTION 'NOT_AUTHORIZED';
    END IF;

    IF COALESCE(jsonb_typeof(p_rows), 'null') <> 'array'
       OR COALESCE(jsonb_typeof(p_delete_user_ids), 'null') <> 'array' THEN
        RAISE EXCEPTION 'INVALID_IMPORT_PAYLOAD';
    END IF;
    IF jsonb_array_length(p_rows) > 10000
       OR jsonb_array_length(p_delete_user_ids) > 10000 THEN
        RAISE EXCEPTION 'IMPORT_PAYLOAD_TOO_LARGE';
    END IF;

    -- Serialize all CSV imports for one occasion. The group RPC uses the same
    -- lock, which is transaction-reentrant for this session.
    PERFORM pg_catalog.pg_advisory_xact_lock(p_occasion_id);
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'user-sign-in-email:' || v_organization_id::text, 0
        )
    );

    FOR v_row IN SELECT value FROM jsonb_array_elements(p_rows)
    LOOP
        IF COALESCE(jsonb_typeof(v_row), 'null') <> 'object'
           OR COALESCE(jsonb_typeof(v_row->'data'), 'null') <> 'object' THEN
            RAISE EXCEPTION 'INVALID_IMPORT_ROW';
        END IF;

        v_data_patch := v_row->'data';
        v_email := lower(btrim(v_data_patch->>'email'));
        v_has_delivery_email := v_row ? 'email_delivery';
        v_delivery_email := lower(btrim(COALESCE(
            v_row->>'email_delivery', v_data_patch->>'email'
        )));
        IF v_email IS NULL OR v_email = '' THEN
            RAISE EXCEPTION 'EMAIL_REQUIRED';
        END IF;
        IF v_delivery_email IS NULL OR v_delivery_email = '' THEN
            RAISE EXCEPTION 'DELIVERY_EMAIL_REQUIRED';
        END IF;

        v_user_id := NULLIF(v_row->>'user_id', '')::uuid;
        v_is_occasion_member := false;

        IF v_user_id IS NULL THEN
            -- Resolve against the occasion first. This makes a retry or a
            -- stale client safe: add_user_to_occasion must never replace an
            -- existing occasion row with profile data.
            SELECT ou."user"
              INTO v_user_id
              FROM public.occasion_users ou
              JOIN public.user_info ui ON ui.id = ou."user"
             WHERE ou.occasion = p_occasion_id
               AND lower(btrim(COALESCE(ui.email_readonly,
                                        ou.data->>'email'))) = v_email
             ORDER BY ou.created_at
             LIMIT 1;

            v_is_occasion_member := v_user_id IS NOT NULL;

            -- A CSV create may also refer to an organization user who simply
            -- is not on this occasion yet. Reuse that identity before creating
            -- a new Auth user.
            IF v_user_id IS NULL THEN
                SELECT ui.id
                  INTO v_user_id
                 FROM public.user_info ui
                 WHERE ui.organization = v_organization_id
                   AND lower(btrim(ui.email_readonly)) = v_email
                 ORDER BY ui.created_at
                 LIMIT 1;
            END IF;

            IF v_user_id IS NULL AND EXISTS (
                SELECT 1 FROM public.user_info ui
                 WHERE ui.organization = v_organization_id
                   AND lower(btrim(ui.email_readonly)) = v_email
            ) THEN
                -- The client assigns deterministic +N account emails for a
                -- CSV batch. Reassigning one here would make a later retry
                -- point at a different person. Without a stable external ID,
                -- reject the stale/colliding input instead of guessing identity.
                RAISE EXCEPTION 'ACCOUNT_EMAIL_ALREADY_EXISTS';
            END IF;

            IF v_user_id IS NULL THEN
                SELECT au.id
                  INTO v_user_id
                  FROM auth.users au
                 WHERE lower(au.email) = lower(v_organization_id::text || '+' || v_email)
                 ORDER BY au.created_at
                 LIMIT 1;
            END IF;

            IF v_user_id IS NULL THEN
                v_user_id := public.create_user_in_organization_with_data_pure(
                    v_organization_id,
                    v_email,
                    NULLIF(v_delivery_email, v_email),
                    encode(gen_random_bytes(16), 'hex'),
                    v_data_patch
                );
            ELSIF NOT EXISTS (
                SELECT 1 FROM public.user_info ui WHERE ui.id = v_user_id
            ) THEN
                INSERT INTO public.user_info (
                    id, organization, email_readonly, email_delivery, data,
                    name, surname, sex
                ) VALUES (
                    v_user_id,
                    v_organization_id,
                    v_email,
                    v_delivery_email,
                    v_data_patch,
                    v_data_patch->>'name',
                    v_data_patch->>'surname',
                    v_data_patch->>'sex'
                );
            END IF;

            IF v_is_occasion_member THEN
                v_updated := v_updated + 1;
            ELSE
                v_response := public.add_user_to_occasion_internal_v1(p_occasion_id, v_user_id);
                IF COALESCE((v_response->>'code')::integer, 500) <> 200 THEN
                    RAISE EXCEPTION 'ADD_USER_TO_OCCASION_FAILED: %',
                        COALESCE(v_response->>'message',
                                 'code ' || (v_response->>'code'));
                END IF;
                v_created := v_created + 1;
            END IF;
        ELSE
            SELECT lower(btrim(COALESCE(ui.email_readonly, ou.data->>'email')))
              INTO v_existing_email
              FROM public.occasion_users ou
              JOIN public.user_info ui ON ui.id = ou."user"
             WHERE ou.occasion = p_occasion_id
               AND ou."user" = v_user_id;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'USER_NOT_ON_OCCASION';
            END IF;
            IF v_existing_email IS DISTINCT FROM v_email THEN
                RAISE EXCEPTION 'USER_EMAIL_MISMATCH';
            END IF;
            v_updated := v_updated + 1;
        END IF;

        UPDATE public.user_info ui
           SET data = COALESCE(ui.data, '{}'::jsonb)
                      || public.get_user_profile_data_patch(v_data_patch),
               email_delivery = CASE
                   WHEN v_has_delivery_email
                       THEN NULLIF(v_delivery_email, v_email)
                   ELSE ui.email_delivery
               END,
               name = CASE WHEN v_data_patch ? 'name'
                           THEN v_data_patch->>'name' ELSE ui.name END,
               surname = CASE WHEN v_data_patch ? 'surname'
                              THEN v_data_patch->>'surname' ELSE ui.surname END,
               sex = CASE WHEN v_data_patch ? 'sex'
                          THEN v_data_patch->>'sex' ELSE ui.sex END,
               phone = CASE WHEN v_data_patch ? 'phone'
                            THEN v_data_patch->>'phone' ELSE ui.phone END,
               birth_date = CASE WHEN v_data_patch ? 'birthDate'
                                 THEN NULLIF(v_data_patch->>'birthDate', '')::date
                                 ELSE ui.birth_date END
         WHERE ui.id = v_user_id;

        IF v_row ? 'services' THEN
            IF COALESCE(jsonb_typeof(v_row->'services'), 'null') <> 'object' THEN
                RAISE EXCEPTION 'INVALID_SERVICES_PATCH';
            END IF;
            v_services_patch := v_row->'services';
        ELSE
            v_services_patch := NULL;
        END IF;

        UPDATE public.occasion_users ou
           SET data = COALESCE(ou.data, '{}'::jsonb) || v_data_patch,
               services = CASE
                   WHEN v_services_patch IS NULL THEN ou.services
                   ELSE COALESCE(ou.services, '{}'::jsonb) || v_services_patch
               END
         WHERE ou.occasion = p_occasion_id
           AND ou."user" = v_user_id;

        IF v_row ? 'group_title' THEN
            v_group_assignments := v_group_assignments || jsonb_build_array(
                jsonb_build_object(
                    'user_id', v_user_id,
                    'group_title', v_row->>'group_title'
                )
            );
        END IF;
    END LOOP;

    FOR v_user_id IN
        SELECT value::uuid FROM jsonb_array_elements_text(p_delete_user_ids)
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM public.occasion_users ou
             WHERE ou.occasion = p_occasion_id AND ou."user" = v_user_id
        ) THEN
            RAISE EXCEPTION 'DELETE_USER_NOT_ON_OCCASION';
        END IF;
        UPDATE public.news
           SET created_by = NULL
         WHERE created_by = v_user_id
           AND occasion = p_occasion_id;
        DELETE FROM public.user_groups
         WHERE "user" = v_user_id
           AND "group" IN (
               SELECT id FROM public.user_group_info
                WHERE occasion = p_occasion_id
           );
        DELETE FROM public.event_users
         WHERE "user" = v_user_id
           AND event IN (
               SELECT id FROM public.events WHERE occasion = p_occasion_id
           );
        DELETE FROM public.user_news
         WHERE "user" = v_user_id AND occasion = p_occasion_id;
        DELETE FROM public.event_users_saved
         WHERE "user" = v_user_id
           AND event IN (
               SELECT id FROM public.events WHERE occasion = p_occasion_id
           );
        DELETE FROM public.occasion_users
         WHERE "user" = v_user_id AND occasion = p_occasion_id;
        v_deleted := v_deleted + 1;
    END LOOP;

    IF jsonb_array_length(v_group_assignments) > 0 THEN
        PERFORM public.import_user_group_assignments(
            p_occasion_id,
            v_group_assignments
        );
    END IF;

    RETURN jsonb_build_object(
        'code', 200,
        'created', v_created,
        'updated', v_updated,
        'deleted', v_deleted,
        'groups', jsonb_array_length(v_group_assignments)
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.import_occasion_users_from_csv(
    p_occasion_id bigint,
    p_rows jsonb,
    p_delete_user_ids jsonb DEFAULT '[]'::jsonb
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.import_occasion_users_from_csv_internal_v1(
    p_occasion_id,p_rows,p_delete_user_ids);
$$;
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

        PERFORM public.delete_occasion_user(storno_record."user", p_occasion_id);

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
CREATE OR REPLACE FUNCTION public.get_user_delivery_email(p_user uuid)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public, extensions
AS $$
    SELECT COALESCE(
        NULLIF(lower(btrim(ui.email_delivery)), ''),
        NULLIF(lower(btrim(ui.email_readonly)), '')
    )
      FROM public.user_info ui
     WHERE ui.id = p_user;
$$;

REVOKE ALL ON FUNCTION public.get_user_delivery_email(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_user_delivery_email(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.get_user_delivery_email(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_delivery_email(uuid) TO service_role;


DROP FUNCTION IF EXISTS public.get_occasion_user_email(bigint, uuid);
