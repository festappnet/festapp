-- One aggregated RPC payload avoids PostgREST row caps and extra
-- service-catalog requests in the Users and Stay administration tabs.
CREATE OR REPLACE FUNCTION public.get_occasion_users_for_edit(
    p_occasion_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    users_data JSONB;
    forms_data JSONB;
    services_data JSONB;
    org_id BIGINT;
BEGIN
    SELECT organization INTO org_id
    FROM public.occasions
    WHERE id = p_occasion_id;

    IF (SELECT get_is_editor_view_on_occasion(p_occasion_id)) <> TRUE
       AND (SELECT get_is_editor_order_view_on_occasion(p_occasion_id)) <> TRUE THEN
        RETURN jsonb_build_object(
            'code', 403,
            'message', 'User is not authorized to view this occasion''s data'
        );
    END IF;

    SELECT jsonb_agg(
        to_jsonb(ui) || to_jsonb(ou) ||
        jsonb_build_object(
            'form_id', order_info.form_id,
            'order_created_at', order_info.created_at,
            'last_sign_in_at', au.last_sign_in_at,
            'group_title', standard_groups.titles
        )
    )
    INTO users_data
    FROM public.occasion_users ou
    JOIN public.user_info ui ON ou."user" = ui.id
    LEFT JOIN auth.users au ON au.id = ui.id
    LEFT JOIN eshop.tickets t ON ou.ticket = t.id
    LEFT JOIN public.organization_users org_u
      ON ui.id = org_u."user" AND org_u.organization = org_id
    LEFT JOIN LATERAL (
        SELECT o.data->>'form' AS form_id, o.created_at
        FROM eshop.order_product_ticket opt
        JOIN eshop.orders o ON opt."order" = o.id
        WHERE opt.ticket = t.id
        LIMIT 1
    ) AS order_info ON true
    LEFT JOIN LATERAL (
        SELECT string_agg(ugi.title, ', ' ORDER BY ugi.title) AS titles
        FROM public.user_groups ug
        JOIN public.user_group_info ugi ON ugi.id = ug."group"
        WHERE ug."user" = ou."user"
          AND ugi.occasion = p_occasion_id
          AND ugi.type IS NULL
    ) AS standard_groups ON true
    WHERE ou.occasion = p_occasion_id
      AND org_u.is_hidden IS NOT TRUE;

    SELECT jsonb_agg(
        jsonb_build_object(
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

    RETURN jsonb_build_object(
        'code', 200,
        'message', 'Occasion users and forms retrieved successfully.',
        'data', jsonb_build_object(
            'occasion_users', COALESCE(users_data, '[]'::jsonb),
            'forms', COALESCE(forms_data, '[]'::jsonb),
            'services', COALESCE(services_data, '{}'::jsonb)
        )
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.save_occasion_user_for_edit(input_data jsonb)
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
           sex = COALESCE(v_data->>'sex', user_info.sex)
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
