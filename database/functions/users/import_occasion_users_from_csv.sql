CREATE OR REPLACE FUNCTION public.import_occasion_users_from_csv_apply_v1(p_occasion_id bigint, p_rows jsonb, p_delete_user_ids jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
        PERFORM public.import_user_group_assignments_internal_v1(
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
$function$
;
CREATE OR REPLACE FUNCTION public.import_occasion_users_from_csv_internal_v1(p_occasion_id bigint, p_rows jsonb, p_delete_user_ids jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
    PERFORM public.validate_occasion_user_csv_import_v1(
        p_occasion_id, p_rows, p_delete_user_ids);
    RETURN public.import_occasion_users_from_csv_apply_v1(
        p_occasion_id, p_rows, p_delete_user_ids);
END;
$function$
;
REVOKE ALL ON FUNCTION public.import_occasion_users_from_csv_apply_v1(bigint,jsonb,jsonb),public.import_occasion_users_from_csv_internal_v1(bigint,jsonb,jsonb) FROM PUBLIC,anon,authenticated;
