-- External catalogue versions retain their distinct original payloads.
-- Their unit-only admission has one typed owner, separate from V212.

CREATE OR REPLACE FUNCTION public.get_all_occasions_for_edit(unit_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  occasion_data jsonb;
BEGIN
  -- Step 1: Verify that the unit exists
  IF NOT EXISTS (SELECT 1 FROM public.units WHERE id = unit_id) THEN
    RETURN jsonb_build_object(
      'code', 404,
      'message', 'Unit not found'
    );
  END IF;

  -- Step 2: Check if the caller is a manager or editor of the unit
  IF NOT public.can_read_legacy_unit_occasion_catalog(unit_id) THEN
    RETURN jsonb_build_object('code', 403);
  END IF;

  -- Step 3: Aggregate occasions for the unit including the first form for each occasion.
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', o.id,
      'title', o.title,
      'created_at', o.created_at,
      'updated_at', o.updated_at,
      'data', o.data,
      'description', o.description,
      'is_hidden', o.is_hidden,
      'is_open', o.is_open,
      'start_time', o.start_time,
      'end_time', o.end_time,
      'link', o.link,
      'organization', o.organization,
      'services', o.services,
      'unit', o.unit,
      'features', o.features,
      'form', (
         SELECT jsonb_build_object(
           'id', f.id,
           'created_at', f.created_at,
           'data', f.data,
           'key', f.key,
           'occasion', f.occasion,
           'type', f.type,
           'is_open', f.is_open,
           'link', f.link,
           'blueprint', f.blueprint,
           'header', f.header,
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
  WHERE o.unit = unit_id;

  -- Step 4: If no occasions were found, return an empty array.
  IF occasion_data IS NULL THEN
    occasion_data := '[]'::jsonb;
  END IF;

  -- Step 5: Return the aggregated JSON response with a 200 code.
  RETURN jsonb_build_object(
    'code', 200,
    'data', occasion_data
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_all_occasions_for_edit_v182(unit_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  occasion_data jsonb;
BEGIN
  -- Step 1: Verify that the unit exists. If not, raise a 'not found' exception.
  IF NOT EXISTS (SELECT 1 FROM public.units WHERE id = unit_id) THEN
    RAISE EXCEPTION 'Unit not found' USING ERRCODE = 'PGRST001';
  END IF;

  -- Step 2: Check if the caller has sufficient permissions. If not, raise an 'insufficient privilege' exception.
  IF NOT public.can_read_legacy_unit_occasion_catalog(unit_id) THEN
    RAISE EXCEPTION 'Insufficient permissions for this unit' USING ERRCODE = '42501';
  END IF;

  -- Step 3: Aggregate occasions for the unit, including forms, order stats, and user data.
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', o.id,
      'title', o.title,
      'created_at', o.created_at,
      'updated_at', o.updated_at,
      'data', o.data,
      'is_hidden', o.is_hidden,
      'is_open', o.is_open,
      'start_time', o.start_time,
      'end_time', o.end_time,
      'link', o.link,
      'organization', o.organization,
      'services', o.services,
      'unit', o.unit,
      'features', o.features,
      'stats', jsonb_build_object(
          'total', COALESCE(order_stats.total, 0),
          'storno', COALESCE(order_stats.storno, 0),
          'paid_or_sent', COALESCE(order_stats.paid_or_sent, 0),
          'ordered', COALESCE(order_stats.ordered, 0),
          'used', COALESCE(order_stats.used, 0),
          'users', COALESCE(user_stats.user_count, 0)
      ),
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
           'blueprint', f.blueprint,
           'header', f.header,
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
  LEFT JOIN (
      -- This subquery calculates all required order counts in a single pass over the orders table.
      SELECT
          occasion,
          COUNT(*) AS total,
          COUNT(*) FILTER (WHERE state = 'storno') AS storno,
          COUNT(*) FILTER (WHERE state IN ('paid', 'sent')) AS paid_or_sent,
          COUNT(*) FILTER (WHERE state = 'ordered') AS ordered,
          COUNT(*) FILTER (WHERE state = 'used') AS used
      FROM eshop.orders
      WHERE occasion IS NOT NULL
      GROUP BY occasion
  ) AS order_stats ON o.id = order_stats.occasion
  LEFT JOIN (
      -- New: This subquery aggregates occasion users and provides their count.
      SELECT
          occasion,
          COUNT(*) as user_count
      FROM public.occasion_users
      GROUP BY occasion
  ) AS user_stats ON o.id = user_stats.occasion
  WHERE o.unit = unit_id;

  -- Step 4: If no occasions were found, return an empty JSON array.
  IF occasion_data IS NULL THEN
    occasion_data := '[]'::jsonb;
  END IF;

  -- Step 5: Return the aggregated JSON data directly.
  RETURN occasion_data;
END;
$function$
;
