CREATE OR REPLACE FUNCTION public.get_all_occasions_for_edit_v212(unit_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  occasion_data jsonb;
  org_id bigint;
  unit_catalog_reader boolean;
BEGIN
  -- Step 1: Verify that the unit exists and retrieve its Organization ID.
  SELECT organization INTO org_id
  FROM public.units
  WHERE id = unit_id;

  -- If org_id is null, the unit does not exist.
  IF org_id IS NULL THEN
    RAISE EXCEPTION 'Unit not found' USING ERRCODE = 'PGRST001';
  END IF;

  -- Step 2: Check permissions
  IF NOT public.can_read_unit_occasion_catalog(unit_id) THEN
    RAISE EXCEPTION 'Insufficient permissions for this unit' USING ERRCODE = '42501';
  END IF;

  -- One actor/unit fact for the whole catalogue, not a permission query
  -- repeated for each occasion. Occasion membership remains row scoped.
  SELECT coalesce((SELECT public.unit_discovery_rule(m.is_editor,m.is_manager,m.is_editor_view)
    FROM public.unit_users m WHERE m.unit=unit_id AND m."user"=auth.uid()),false)
    INTO unit_catalog_reader;

  -- Step 3: Aggregate occasions
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', o.id,
      'title', o.title,
      'created_at', o.created_at,
      'updated_at', o.updated_at,
      'data', o.data #- '{heavy_field}', -- OPTIMIZATION: Remove heavy_field
      'is_hidden', o.is_hidden,
      'is_open', o.is_open,
      'start_time', o.start_time,
      'end_time', o.end_time,
      'link', o.link,
      'organization', o.organization,
      'services', o.services,
      'unit', o.unit,
      'features', (
          SELECT jsonb_agg(
              elem #- '{heavy_config}' -- OPTIMIZATION: Remove heavy_config from features
          )
          FROM jsonb_array_elements(o.features) elem
      ),
      'stats', jsonb_build_object(
          'total', COALESCE(ticket_stats.total, 0),
          'storno', COALESCE(ticket_stats.storno, 0),
          'paid_or_sent', COALESCE(ticket_stats.paid_or_sent, 0),
          'ordered', COALESCE(ticket_stats.ordered, 0),
          'used', COALESCE(ticket_stats.used, 0),
          'users', COALESCE(user_stats.user_count, 0)
      ),
      'sale_forms', public.get_occasion_sale_forms_internal(o.id),
      'form', (
         -- This subquery fetches the first associated form for the occasion.
         SELECT jsonb_build_object(
           'id', f.id,
           'created_at', f.created_at,
           'data', f.data,
           'key', f.key,
           'occasion', f.occasion,
           'type', f.type,
           'is_open', f.is_open,
           'link', f.link,
           'blueprint', NULL, -- OPTIMIZATION: Remove blueprint
           'header', NULL, -- OPTIMIZATION: Remove header
           'header_off', f.header_off,
           'updated_at', f.updated_at
         )
         FROM public.forms f
         WHERE f.occasion = o.id
         ORDER BY f.id
         LIMIT 1
      )
    )
    ORDER BY o.start_time DESC
  )
  INTO occasion_data
  FROM public.occasions o

  -- Ticket Stats
  LEFT JOIN (
      SELECT
          occasion,
          COUNT(*) AS total,
          COUNT(*) FILTER (WHERE state = 'storno') AS storno,
          COUNT(*) FILTER (WHERE state IN ('paid', 'sent')) AS paid_or_sent,
          COUNT(*) FILTER (WHERE state = 'ordered') AS ordered,
          COUNT(*) FILTER (WHERE state = 'used') AS used
      FROM eshop.tickets
      GROUP BY occasion
  ) AS ticket_stats ON o.id = ticket_stats.occasion

  -- User Stats
  LEFT JOIN (
      SELECT
          ou.occasion,
          COUNT(*) as user_count
      FROM public.occasion_users ou
      LEFT JOIN public.organization_users org_u
          ON ou."user" = org_u."user"
          AND org_u.organization = org_id
      WHERE (org_u.is_hidden IS NOT TRUE)
      GROUP BY ou.occasion
  ) AS user_stats ON o.id = user_stats.occasion

  WHERE o.unit = unit_id
  AND (
      unit_catalog_reader
      OR
      EXISTS (
          SELECT 1 FROM public.occasion_users ou
          WHERE ou.occasion = o.id
            AND ou."user" = auth.uid()
            AND public.occasion_staff_navigation_rule(ou.is_manager,ou.is_editor,ou.is_editor_view,ou.is_editor_order,ou.is_editor_order_view)
      )
  );

  IF occasion_data IS NULL THEN
    occasion_data := '[]'::jsonb;
  END IF;

  RETURN occasion_data;
END;
$function$
;
