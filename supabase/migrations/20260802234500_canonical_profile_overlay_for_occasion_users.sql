-- Canonical profile fields are shared across occasions; all other editor data
-- remains occasion-specific. This migration changes function definitions only
-- and does not rewrite user_info or occasion_users rows.

CREATE OR REPLACE FUNCTION public.get_occasion_users_for_edit(
    p_occasion_id BIGINT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    users_data JSON;
    forms_data JSON;
    services_data JSONB;
    org_id BIGINT;
BEGIN
    -- 0. Retrieve the Organization ID
    -- We need this to check against the organization_users table later
    SELECT organization INTO org_id
    FROM public.occasions
    WHERE id = p_occasion_id;

    -- Authorization check: Ensure the user has editor rights for the occasion.
    IF (SELECT get_is_editor_view_on_occasion(p_occasion_id)) <> TRUE AND (SELECT get_is_editor_order_view_on_occasion(p_occasion_id)) <> TRUE THEN
        RETURN json_build_object('code', 403, 'message', 'User is not authorized to view this occasion''s data');
    END IF;

    -- 1. Get all users associated with the occasion. Resolve order and group
    -- metadata once for the whole occasion instead of running correlated
    -- subqueries for every user.
    WITH visible_users AS MATERIALIZED (
        SELECT ou.*
        FROM public.occasion_users ou
        LEFT JOIN public.organization_users org_u
          ON org_u."user" = ou."user"
         AND org_u.organization = org_id
        WHERE ou.occasion = p_occasion_id
          AND org_u.is_hidden IS NOT TRUE
    ),
    order_info AS (
        SELECT DISTINCT ON (opt.ticket)
            opt.ticket,
            o.data->>'form' AS form_id,
            o.created_at
        FROM visible_users vu
        JOIN eshop.order_product_ticket opt ON opt.ticket = vu.ticket
        JOIN eshop.orders o ON o.id = opt."order"
        ORDER BY opt.ticket, opt.id
    ),
    standard_groups AS (
        SELECT
            ug."user",
            string_agg(ugi.title, ', ' ORDER BY ugi.title) AS titles
        FROM visible_users vu
        JOIN public.user_groups ug ON ug."user" = vu."user"
        JOIN public.user_group_info ugi ON ugi.id = ug."group"
        WHERE ugi.occasion = p_occasion_id
          AND ugi.type IS NULL
        GROUP BY ug."user"
    )
    SELECT json_agg(row_to_json(user_row))
    INTO users_data
    FROM (
        SELECT
            vu.occasion,
            vu.created_at,
            vu."user",
            vu.is_editor,
            vu.is_manager,
            vu.is_approved,
            vu.is_approver,
            -- Occasion data remains authoritative for event-specific fields.
            -- Overlay only the dedicated global profile columns; user_info.data
            -- also contains historical occasion fields and must not leak across
            -- events. A LEFT JOIN preserves legacy occasion rows without a
            -- matching user_info record.
            COALESCE(vu.data, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
                'email', ui.email_readonly,
                'name', ui.name,
                'surname', ui.surname,
                'sex', ui.sex,
                'phone', COALESCE(ui.phone, ui.data->>'phone'),
                'birthDate', COALESCE(
                    to_char(ui.birth_date, 'YYYY-MM-DD'),
                    ui.data->>'birthDate'
                )
            )) AS data,
            vu.role,
            vu.services,
            vu.is_editor_view,
            vu.is_editor_order,
            vu.is_editor_order_view,
            vu.is_cleaning_crew,
            vu.is_cleaning_blocked,
            vu.ticket,
            order_info.form_id,
            order_info.created_at AS order_created_at,
            au.last_sign_in_at,
            standard_groups.titles AS group_title
        FROM visible_users vu
        LEFT JOIN public.user_info ui ON ui.id = vu."user"
        LEFT JOIN auth.users au ON au.id = vu."user"
        LEFT JOIN order_info ON order_info.ticket = vu.ticket
        LEFT JOIN standard_groups ON standard_groups."user" = vu."user"
    ) user_row;

    -- 2. Get all forms associated with the occasion, selecting only the specified fields.
    SELECT json_agg(
        json_build_object(
            'key', f.key,
            'type', f.type,
            'id', f.id,
            'title', f.title,
            'link', f.link
        )
    )
    INTO forms_data
    FROM public.forms f
    WHERE f.occasion = p_occasion_id;

    -- 3. Return the service catalog in the same RPC response. Both the Users
    -- and Stay tabs need these options to render editable accommodation/food
    -- columns; keeping them here avoids extra requests and PostgREST's 1000-row
    -- cap on direct occasion_users queries.
    SELECT catalog.services || jsonb_build_object(
        'accommodation',
        COALESCE((
            SELECT jsonb_agg(
                service_item.item || jsonb_build_object('place_title', p.title)
                ORDER BY service_item.position
            )
            FROM jsonb_array_elements(
                CASE
                    WHEN jsonb_typeof(catalog.services->'accommodation') = 'array'
                        THEN catalog.services->'accommodation'
                    ELSE '[]'::jsonb
                END
            ) WITH ORDINALITY AS service_item(item, position)
            LEFT JOIN public.places p
              ON p.id = CASE
                  WHEN service_item.item->>'reference' ~ '^[0-9]+$'
                      THEN (service_item.item->>'reference')::bigint
                  ELSE NULL
              END
             AND p.occasion = p_occasion_id
        ), '[]'::jsonb)
    )
    INTO services_data
    FROM (
        SELECT CASE
            WHEN jsonb_typeof(o.services) = 'object' THEN o.services
            ELSE '{}'::jsonb
        END AS services
        FROM public.occasions o
        WHERE o.id = p_occasion_id
    ) catalog;

    -- Assemble the final JSON object without reparsing the complete roster as
    -- JSONB. Both the Users and Stay tabs consume this same bundle.
    RETURN json_build_object(
        'code', 200,
        'message', 'Occasion users and forms retrieved successfully.',
        'data', json_build_object(
            'occasion_users', COALESCE(users_data, '[]'::json),
            'forms',          COALESCE(forms_data, '[]'::json),
            'services',       COALESCE(services_data, '{}'::jsonb)
        )
    );
END;
$$;
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
       SET data = COALESCE(user_info.data, '{}'::jsonb) || v_data,
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
