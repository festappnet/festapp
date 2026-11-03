CREATE OR REPLACE FUNCTION public.get_users_from_occasion_with_orders(oc bigint)
RETURNS jsonb
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  users_data jsonb;
  tickets_data jsonb;
  order_product_tickets_data jsonb;
  orders_data jsonb;
  forms_data jsonb;
  form_fields_data jsonb;
  org_id bigint; -- Variable to store Organization ID
BEGIN
  -- 0. Retrieve Organization ID
  -- We need this to check the organization_users table
  SELECT organization INTO org_id
  FROM public.occasions
  WHERE id = oc;

  -- Security check: If the user lacks permission, raise an exception.
  IF (SELECT get_is_editor_view_on_occasion(oc)) <> TRUE THEN
      RAISE EXCEPTION 'User is not authorized to access this occasion' USING ERRCODE = '42501';
  END IF;

  -- 1. Fetch users as a JSON object, keyed by user ID.
  SELECT jsonb_object_agg(ui.id,
    jsonb_strip_nulls(jsonb_build_object(
      'id', ui.id,
      'name', ui.name,
      'surname', ui.surname,
      'sex', ui.sex,
      'email_readonly', ui.email_readonly,
      'phone', ui.phone,
      'birth_date', ui.birth_date,
      'data', ui.data,
      'ticket_id', ou.ticket,
      'companions', (
        SELECT COALESCE(jsonb_agg(
          jsonb_build_object(
            'id', comp_ui.id,
            'name', comp_ui.name,
            'surname', comp_ui.surname
          )
        ), '[]'::jsonb)
        FROM public.user_companions uc
        JOIN public.user_info comp_ui ON uc.companion = comp_ui.id
        WHERE uc."user" = ui.id AND uc.occasion=oc
      )
    ))
  ) INTO users_data
  FROM public.occasion_users ou
  JOIN public.user_info ui ON ou."user" = ui.id

  -- Join to check visibility
  LEFT JOIN public.organization_users org_u ON ui.id = org_u."user" AND org_u.organization = org_id

  WHERE ou.occasion = oc
  -- Filter hidden users
  AND (org_u.is_hidden IS NOT TRUE);

  -- 2. Use CTEs to gather the unique IDs of all related items, preventing duplicates.
  WITH relevant_tickets AS (
      -- Get unique ticket IDs directly linked to users on the occasion
      -- We MUST apply the same hidden filter here, otherwise we might fetch tickets for hidden users
      SELECT DISTINCT ou.ticket AS id
      FROM public.occasion_users ou
      LEFT JOIN public.organization_users org_u ON ou."user" = org_u."user" AND org_u.organization = org_id
      WHERE ou.occasion = oc
        AND ou.ticket IS NOT NULL
        AND (org_u.is_hidden IS NOT TRUE)
  ),
  relevant_orders AS (
      -- From those tickets, get unique order IDs via the join table
      -- (This automatically excludes orders from hidden users because relevant_tickets is filtered)
      SELECT DISTINCT "order" AS id
      FROM eshop.order_product_ticket
      WHERE ticket IN (SELECT id FROM relevant_tickets)
  ),
  relevant_forms AS (
      -- From those orders, get unique form IDs
      SELECT DISTINCT f.id
      FROM public.forms f
      JOIN eshop.orders o ON f.occasion = o.occasion AND f.key::text = o.data->>'form'
      WHERE o.id IN (SELECT id FROM relevant_orders)
  )
  -- 3. Fetch the data as dictionaries, using the de-duplicated ID sets from the CTEs.
  SELECT
    (SELECT jsonb_object_agg(t.id, to_jsonb(t)) FROM eshop.tickets t WHERE t.id IN (SELECT id FROM relevant_tickets)),
    (SELECT jsonb_object_agg(o.id, to_jsonb(o)) FROM eshop.orders o WHERE o.id IN (SELECT id FROM relevant_orders)),
    (SELECT jsonb_object_agg(opt.id, to_jsonb(opt)) FROM eshop.order_product_ticket opt WHERE opt.order IN (SELECT id FROM relevant_orders)),
    (SELECT jsonb_object_agg(f.id, to_jsonb(f)) FROM public.forms f WHERE f.id IN (SELECT id FROM relevant_forms)),
    (SELECT jsonb_object_agg(ff.id, to_jsonb(ff)) FROM public.form_fields ff WHERE ff.form IN (SELECT id FROM relevant_forms))
  INTO
    tickets_data,
    orders_data,
    order_product_tickets_data,
    forms_data,
    form_fields_data;

  -- 4. Return the data object directly.
  RETURN jsonb_build_object(
      'users', COALESCE(users_data, '{}'::jsonb),
      'tickets', COALESCE(tickets_data, '{}'::jsonb),
      'order_product_ticket', COALESCE(order_product_tickets_data, '{}'::jsonb),
      'orders', COALESCE(orders_data, '{}'::jsonb),
      'forms', COALESCE(forms_data, '{}'::jsonb),
      'form_fields', COALESCE(form_fields_data, '{}'::jsonb)
  );
END;
$$ LANGUAGE plpgsql;
