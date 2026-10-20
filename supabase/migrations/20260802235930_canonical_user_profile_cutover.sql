-- Establish one canonical current-profile write path while preserving every
-- historical occasion snapshot and every stay/service assignment. Existing
-- JSON data is not removed. Valid legacy birth dates are copied only into
-- currently empty dedicated profile columns.

CREATE OR REPLACE FUNCTION public.get_user_profile_data_patch(p_data jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = public, extensions
AS $$
  SELECT COALESCE(jsonb_object_agg(entry.key, entry.value), '{}'::jsonb)
  FROM jsonb_each(
    CASE WHEN jsonb_typeof(p_data) = 'object' THEN p_data ELSE '{}'::jsonb END
  ) AS entry
  WHERE entry.key = ANY (ARRAY[
    'name', 'surname', 'sex', 'phone', 'birthDate'
  ]::text[]);
$$;

REVOKE ALL ON FUNCTION public.get_user_profile_data_patch(jsonb) FROM PUBLIC;

UPDATE public.user_info
SET birth_date = left(data->>'birthDate', 10)::date
WHERE birth_date IS NULL
  AND data->>'birthDate' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T';

CREATE OR REPLACE FUNCTION public.save_occasion_user_for_edit_internal_v1(input_data jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion bigint := (input_data->>'occasion')::bigint;
    v_user uuid := (input_data->>'user')::uuid;
    v_unit bigint;
    v_data jsonb := CASE WHEN jsonb_typeof(input_data->'data') = 'object'
                         THEN input_data->'data' ELSE '{}'::jsonb END;
    v_services jsonb := CASE WHEN jsonb_typeof(input_data->'services') = 'object'
                             THEN input_data->'services' ELSE '{}'::jsonb END;
    v_catalog jsonb;
    v_existing_services jsonb;
    v_code text;
BEGIN
    SELECT o.unit,
           CASE WHEN jsonb_typeof(o.services) = 'object'
                THEN o.services ELSE '{}'::jsonb END
      INTO v_unit, v_catalog
      FROM public.occasions o
     WHERE o.id = v_occasion;

    IF v_unit IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Occasion not found');
    END IF;

    -- Keep the write boundary at occasion management level. In particular,
    -- a unit editor must not gain the ability to assign manager/editor flags
    -- through this SECURITY DEFINER function.
    IF NOT public.get_is_manager_on_occasion(v_occasion)
       AND NOT public.get_is_admin_on_occasion(v_occasion) THEN
        RETURN jsonb_build_object('code', 403, 'message', 'Not authorized to update occasion users');
    END IF;

    SELECT CASE WHEN jsonb_typeof(ou.services) = 'object'
                THEN ou.services ELSE '{}'::jsonb END
      INTO v_existing_services
      FROM public.occasion_users ou
     WHERE ou.occasion = v_occasion AND ou."user" = v_user;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Occasion user not found');
    END IF;

    -- Every assigned accommodation code must still exist in this occasion's
    -- catalog. This keeps the grid select and persisted service data aligned.
    FOR v_code IN
        SELECT key FROM jsonb_each(
            CASE WHEN jsonb_typeof(v_services->'accommodation') = 'object'
                 THEN v_services->'accommodation' ELSE '{}'::jsonb END
        )
    LOOP
        IF NOT EXISTS (
            SELECT 1
              FROM jsonb_array_elements(
                  CASE WHEN jsonb_typeof(v_catalog->'accommodation') = 'array'
                       THEN v_catalog->'accommodation' ELSE '[]'::jsonb END
              ) item
             WHERE item->>'code' = v_code
        ) AND NOT COALESCE((
            -- Historical assignments can outlive a removed catalog item.
            -- Preserve such a code on unrelated edits, but never allow a new
            -- unknown code to be introduced.
            jsonb_typeof(v_existing_services->'accommodation') = 'object'
            AND (v_existing_services->'accommodation') ? v_code
        ), false) THEN
            RETURN jsonb_build_object('code', 400, 'message', 'Unknown accommodation code: ' || v_code);
        END IF;
    END LOOP;

    UPDATE public.user_info
       SET data = COALESCE(user_info.data, '{}'::jsonb)
                  || public.get_user_profile_data_patch(v_data),
           name = COALESCE(v_data->>'name', user_info.name),
           surname = COALESCE(v_data->>'surname', user_info.surname),
           sex = COALESCE(v_data->>'sex', user_info.sex),
           phone = CASE
               WHEN v_data ? 'phone' THEN v_data->>'phone'
               ELSE user_info.phone
           END,
           birth_date = CASE
               WHEN v_data ? 'birthDate'
                   THEN NULLIF(v_data->>'birthDate', '')::date
               ELSE user_info.birth_date
           END
     WHERE id = v_user;

    UPDATE public.occasion_users
       SET data = v_data,
           -- A grid may edit only one service family. Merge top-level service
           -- keys so changing accommodation never erases food (and vice versa).
           -- An explicitly supplied empty object still clears that family.
           services = COALESCE(occasion_users.services, '{}'::jsonb) || v_services,
           role = CASE WHEN input_data ? 'role' THEN (input_data->>'role')::int ELSE role END,
           is_editor = COALESCE((input_data->>'is_editor')::boolean, is_editor),
           is_editor_view = COALESCE((input_data->>'is_editor_view')::boolean, is_editor_view),
           is_editor_order = COALESCE((input_data->>'is_editor_order')::boolean, is_editor_order),
           is_editor_order_view = COALESCE((input_data->>'is_editor_order_view')::boolean, is_editor_order_view),
           is_cleaning_crew = COALESCE((input_data->>'is_cleaning_crew')::boolean, is_cleaning_crew),
           is_cleaning_blocked = COALESCE((input_data->>'is_cleaning_blocked')::boolean, is_cleaning_blocked),
           is_approver = COALESCE((input_data->>'is_approver')::boolean, is_approver),
           is_approved = COALESCE((input_data->>'is_approved')::boolean, is_approved),
           is_manager = COALESCE((input_data->>'is_manager')::boolean, is_manager)
     WHERE occasion = v_occasion AND "user" = v_user;

    RETURN jsonb_build_object('code', 200, 'message', 'Occasion user updated');
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('code', 500, 'message', SQLERRM);
END;
$$;
CREATE OR REPLACE FUNCTION public.update_user_internal_v1(
  input_data jsonb
) RETURNS jsonb
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user uuid;
  v_occasion bigint;
  v_unit_input bigint;
  v_is_manager boolean;
  v_is_editor boolean;
  v_data jsonb;
  v_email text;
  v_password text;
  v_org bigint;
  v_unit bigint;
  new_user uuid;
  existing_user_id uuid;
  v_create_response jsonb;
BEGIN
  -- Extract main fields from the input_data jsonb object
  v_user := (input_data->>'user')::uuid;
  v_occasion := (input_data->>'occasion')::bigint;
  v_unit_input := (input_data->>'unit')::bigint;
  v_is_manager := COALESCE((input_data->>'is_manager')::boolean, false);
  v_is_editor := COALESCE((input_data->>'is_editor')::boolean, false);

  -- Ensure 'data' field is a valid jsonb
  v_data := CASE
        WHEN input_data->>'data' IS NULL OR input_data->>'data' = ''
        THEN '{}'::jsonb
        ELSE input_data->'data'
       END;

  -- Determine the unit
  IF v_occasion IS NOT NULL THEN
    SELECT unit INTO v_unit FROM public.occasions WHERE id = v_occasion;
    IF v_unit IS NULL THEN
     RETURN jsonb_build_object('code', 404, 'message', 'Occasion not found');
    END IF;
  ELSIF v_unit_input IS NOT NULL THEN
    v_unit := v_unit_input;
    IF NOT EXISTS (SELECT 1 FROM public.units WHERE id = v_unit) THEN
        RETURN jsonb_build_object('code', 404, 'message', 'Unit not found');
    END IF;
  ELSE
    RETURN jsonb_build_object('code', 400, 'message', 'Either an occasion or a unit must be provided');
  END IF;

  -- Get the organization
  SELECT organization INTO v_org FROM public.units WHERE id = v_unit;
  IF v_org IS NULL THEN
    RETURN jsonb_build_object('code', 404, 'message', 'Organization not found for the specified unit');
  END IF;

  -- Authorization check
  IF v_occasion IS NOT NULL THEN
    IF NOT EXISTS (
     SELECT 1 FROM public.occasion_users
     WHERE "user" = auth.uid()
      AND occasion = v_occasion
      AND is_manager = true
    ) THEN
     RETURN jsonb_build_object('code', 403, 'message', 'Unauthorized: Caller is not a manager for this occasion');
    END IF;
  ELSE
    IF NOT EXISTS (
        SELECT 1 FROM public.unit_users
        WHERE "user" = auth.uid()
        AND unit = v_unit
        AND is_manager = true
    ) THEN
        RETURN jsonb_build_object('code', 403, 'message', 'Unauthorized: Caller is not a manager for this unit');
    END IF;
  END IF;

  -- Logic for finding or creating user
  IF v_user IS NULL THEN
    v_email := input_data->'data'->>'email';

    IF v_email IS NULL OR v_email = '' THEN
      RETURN jsonb_build_object('code', 400, 'message', 'Email is required to find or create a user.');
    END IF;

    -- Check if user exists
    SELECT id INTO existing_user_id
    FROM auth.users
    WHERE email = v_org::text || '+' || v_email;

    IF existing_user_id IS NOT NULL THEN
      -- Create profile if missing
      IF NOT EXISTS (SELECT 1 FROM public.user_info WHERE id = existing_user_id) THEN
        INSERT INTO public.user_info (
          id, organization, email_readonly, data, name, surname, sex, phone,
          birth_date
        )
        VALUES (
            existing_user_id,
            v_org,
            v_email,
            v_data,
            v_data->>'name',
            v_data->>'surname',
            v_data->>'sex',
            v_data->>'phone',
            NULLIF(v_data->>'birthDate', '')::date
        );
      END IF;

      RETURN jsonb_build_object('code', 200, 'message', 'User found', 'user', existing_user_id::text);

    ELSE
      -- User does not exist, create new one
      v_password := encode(gen_random_bytes(16), 'hex');

      -- 1. Capture the JSONB response
      v_create_response := create_user_in_organization_with_data_ws(v_org, v_email, v_password, v_data);

      -- 2. Check if creation was successful (code 200)
      IF (v_create_response->>'code')::int != 200 THEN
          RETURN v_create_response; -- Return the error from the creation function
      END IF;

      -- 3. Extract the UUID string and cast it to UUID type
      new_user := (v_create_response->>'id')::uuid;

      RETURN jsonb_build_object(
       'code', 201,
       'message', 'User created successfully',
       'user', new_user::text
      );
    END IF;
  END IF;

  -- Update existing user logic
  UPDATE public.user_info
  SET
    data = COALESCE(user_info.data, '{}'::jsonb)
           || public.get_user_profile_data_patch(v_data),
    name = COALESCE(v_data->>'name', user_info.name),
    surname = COALESCE(v_data->>'surname', user_info.surname),
    sex = COALESCE(v_data->>'sex', user_info.sex),
    phone = CASE
      WHEN v_data ? 'phone' THEN v_data->>'phone'
      ELSE user_info.phone
    END,
    birth_date = CASE
      WHEN v_data ? 'birthDate'
        THEN NULLIF(v_data->>'birthDate', '')::date
      ELSE user_info.birth_date
    END
  WHERE id = v_user;

  RETURN jsonb_build_object(
   'code', 200,
   'message', 'User details updated successfully',
   'user', v_user
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('code', 500, 'message', SQLERRM);
END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION public.create_user_in_organization_with_data_pure(org bigint, email text, password text, data jsonb)
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
BEGIN
    -- Trim and lower the email input
    original_email := lower(trim(email));

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

    -- Insert into user_info with the original email (without prefix)
    INSERT INTO user_info (
      id, email_readonly, name, surname, sex, phone, birth_date, data,
      organization
    )
    VALUES (
      usr,
      original_email,
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
           SET data = COALESCE(ui.data, '{}'::jsonb)
                      || public.get_user_profile_data_patch(v_data_patch),
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
