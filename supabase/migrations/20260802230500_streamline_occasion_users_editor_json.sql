-- Stream the shared Users/Stay editor roster as JSON in one pass. This avoids
-- duplicating user_info and reparsing the complete response as JSONB.
DROP FUNCTION public.get_occasion_users_for_edit(BIGINT);

CREATE FUNCTION public.get_occasion_users_for_edit(
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
    SELECT organization INTO org_id
    FROM public.occasions
    WHERE id = p_occasion_id;

    IF (SELECT get_is_editor_view_on_occasion(p_occasion_id)) <> TRUE
       AND (SELECT get_is_editor_order_view_on_occasion(p_occasion_id)) <> TRUE THEN
        RETURN json_build_object(
            'code', 403,
            'message', 'User is not authorized to view this occasion''s data'
        );
    END IF;

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
            vu.*,
            order_info.form_id,
            order_info.created_at AS order_created_at,
            au.last_sign_in_at,
            standard_groups.titles AS group_title
        FROM visible_users vu
        LEFT JOIN auth.users au ON au.id = vu."user"
        LEFT JOIN order_info ON order_info.ticket = vu.ticket
        LEFT JOIN standard_groups ON standard_groups."user" = vu."user"
    ) user_row;

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

    RETURN json_build_object(
        'code', 200,
        'message', 'Occasion users and forms retrieved successfully.',
        'data', json_build_object(
            'occasion_users', COALESCE(users_data, '[]'::json),
            'forms', COALESCE(forms_data, '[]'::json),
            'services', COALESCE(services_data, '{}'::jsonb)
        )
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_occasion_users_for_edit(BIGINT)
TO PUBLIC, anon, authenticated, service_role;
