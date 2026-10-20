DROP FUNCTION IF EXISTS public.import_user_group_assignments(bigint, jsonb);

CREATE OR REPLACE FUNCTION public.import_user_group_assignments(
    p_occasion_id bigint,
    p_assignments jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_assignment record;
    v_group_id bigint;
    v_group_title text;
    v_keep_admin boolean;
    v_unit_id bigint;
BEGIN
    SELECT o.unit INTO v_unit_id
    FROM public.occasions o
    WHERE o.id = p_occasion_id;

    IF v_unit_id IS NULL THEN
        RAISE EXCEPTION 'OCCASION_NOT_FOUND';
    END IF;

    IF NOT (
        public.get_is_editor_on_occasion(p_occasion_id)
        OR public.get_is_manager_on_occasion(p_occasion_id)
        OR public.get_is_admin_on_occasion(p_occasion_id)
        OR public.get_is_editor_on_unit(v_unit_id)
    ) THEN
        RAISE EXCEPTION 'NOT_AUTHORIZED';
    END IF;

    IF COALESCE(jsonb_typeof(p_assignments), 'null') <> 'array' THEN
        RAISE EXCEPTION 'INVALID_ASSIGNMENTS';
    END IF;

    -- Serialize imports for one occasion so normalized group titles cannot be
    -- created twice by concurrent CSV imports.
    PERFORM pg_catalog.pg_advisory_xact_lock(p_occasion_id);

    FOR v_assignment IN
        SELECT assignment.user_id, assignment.group_title
        FROM jsonb_to_recordset(p_assignments)
            AS assignment(user_id uuid, group_title text)
    LOOP
        IF v_assignment.user_id IS NULL OR NOT EXISTS (
            SELECT 1
            FROM public.occasion_users ou
            WHERE ou.occasion = p_occasion_id
              AND ou."user" = v_assignment.user_id
        ) THEN
            RAISE EXCEPTION 'USER_NOT_ON_OCCASION';
        END IF;

        v_group_title := NULLIF(btrim(v_assignment.group_title), '');
        v_group_id := NULL;
        v_keep_admin := false;

        IF v_group_title IS NOT NULL THEN
            SELECT ugi.id
            INTO v_group_id
            FROM public.user_group_info ugi
            WHERE ugi.occasion = p_occasion_id
              AND ugi.type IS NULL
              AND lower(btrim(ugi.title)) = lower(v_group_title)
            ORDER BY ugi.id
            LIMIT 1;

            IF v_group_id IS NULL THEN
                INSERT INTO public.user_group_info (occasion, title)
                VALUES (p_occasion_id, v_group_title)
                RETURNING id INTO v_group_id;
            ELSE
                SELECT COALESCE(ug.is_admin, false)
                INTO v_keep_admin
                FROM public.user_groups ug
                WHERE ug."user" = v_assignment.user_id
                  AND ug."group" = v_group_id;

                v_keep_admin := COALESCE(v_keep_admin, false);
            END IF;
        END IF;

        DELETE FROM public.user_groups ug
        USING public.user_group_info ugi
        WHERE ug."group" = ugi.id
          AND ug."user" = v_assignment.user_id
          AND ugi.occasion = p_occasion_id
          AND ugi.type IS NULL;

        IF v_group_id IS NOT NULL THEN
            INSERT INTO public.user_groups ("user", "group", is_admin)
            VALUES (v_assignment.user_id, v_group_id, v_keep_admin);
        END IF;
    END LOOP;
END;
$$;
DROP FUNCTION IF EXISTS public.import_occasion_users_from_csv(bigint, jsonb, jsonb);

CREATE OR REPLACE FUNCTION public.import_occasion_users_from_csv(
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
    v_existing_email text;
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

    FOR v_row IN SELECT value FROM jsonb_array_elements(p_rows)
    LOOP
        IF COALESCE(jsonb_typeof(v_row), 'null') <> 'object'
           OR COALESCE(jsonb_typeof(v_row->'data'), 'null') <> 'object' THEN
            RAISE EXCEPTION 'INVALID_IMPORT_ROW';
        END IF;

        v_data_patch := v_row->'data';
        v_email := lower(btrim(v_data_patch->>'email'));
        IF v_email IS NULL OR v_email = '' THEN
            RAISE EXCEPTION 'EMAIL_REQUIRED';
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
                    encode(gen_random_bytes(16), 'hex'),
                    v_data_patch
                );
            ELSIF NOT EXISTS (
                SELECT 1 FROM public.user_info ui WHERE ui.id = v_user_id
            ) THEN
                INSERT INTO public.user_info (
                    id, organization, email_readonly, data, name, surname, sex
                ) VALUES (
                    v_user_id,
                    v_organization_id,
                    v_email,
                    v_data_patch,
                    v_data_patch->>'name',
                    v_data_patch->>'surname',
                    v_data_patch->>'sex'
                );
            END IF;

            IF v_is_occasion_member THEN
                v_updated := v_updated + 1;
            ELSE
                v_response := public.add_user_to_occasion(p_occasion_id, v_user_id);
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
           SET data = COALESCE(ui.data, '{}'::jsonb) || v_data_patch,
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
        PERFORM public.delete_occasion_user(v_user_id, p_occasion_id);
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
