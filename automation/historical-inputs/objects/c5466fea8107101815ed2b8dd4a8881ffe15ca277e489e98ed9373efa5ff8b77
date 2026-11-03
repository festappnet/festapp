CREATE OR REPLACE FUNCTION public.get_all_occasions_for_edit_v212(unit_id bigint)
RETURNS jsonb
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  occasion_data jsonb;
  org_id bigint;
BEGIN
  -- Step 1: Verify that the unit exists and retrieve its Organization ID.
  -- We need the org_id to filter hidden users correctly in the subquery later.
  SELECT organization INTO org_id
  FROM public.units
  WHERE id = unit_id;

  -- If org_id is null, the unit does not exist.
  IF org_id IS NULL THEN
    RAISE EXCEPTION 'Unit not found' USING ERRCODE = 'PGRST001';
  END IF;

  -- Step 2: Check if the caller has sufficient permissions. If not, raise an 'insufficient privilege' exception.
  IF NOT EXISTS (
      SELECT 1 FROM public.unit_users
      WHERE "user" = auth.uid()
        AND unit = unit_id
        AND (is_manager = true OR is_editor = true OR is_editor_view = true)
  ) AND NOT EXISTS (
      SELECT 1 FROM public.occasion_users ou
      JOIN public.occasions o ON o.id = ou.occasion
      WHERE o.unit = unit_id
        AND ou."user" = auth.uid()
        AND (ou.is_manager IS TRUE OR ou.is_editor IS TRUE OR ou.is_editor_view IS TRUE OR ou.is_editor_order IS TRUE OR ou.is_editor_order_view IS TRUE)
  ) THEN
    RAISE EXCEPTION 'Insufficient permissions for this unit' USING ERRCODE = '42501';
  END IF;

  -- Step 3: Aggregate occasions for the unit, including forms, stats, and user data.
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', o.id,
      'title', o.title,
      'created_at', o.created_at,
      'updated_at', o.updated_at,
      -- 'data', o.data, -- OPTIMIZED: Removed heavy unused field
      'data', CASE 
        WHEN o.data ? 'data_timezone' THEN jsonb_build_object('data_timezone', o.data->'data_timezone')
        ELSE NULL 
      END,
      'is_hidden', o.is_hidden,
      'is_open', o.is_open,
      'start_time', o.start_time,
      'end_time', o.end_time,
      'link', o.link,
      'organization', o.organization,
      'services', o.services,
      'unit', o.unit,
      'aggregate_version', COALESCE((
        SELECT av.version FROM public.client_aggregate_versions av
        WHERE av.aggregate_type = 'occasion'
          AND av.scope_type = 'occasion'
          AND av.scope_id = o.id
          AND av.aggregate_id = o.id::text
      ), 0),
      -- 'features', o.features, -- OPTIMIZED: Return only essential fields
      'features', (
        SELECT jsonb_agg(
          jsonb_build_object(
            'code', elem->>'code',
            'is_enabled', (elem->>'is_enabled')::boolean
          )
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
      'form', (
         -- This subquery fetches the first associated form for the occasion.
         SELECT jsonb_build_object(
           'id', f.id,
           'created_at', f.created_at,
           -- 'data', f.data, -- OPTIMIZED: Removed heavy unused field
           'key', f.key,
           'occasion', f.occasion,
           'type', f.type,
           'is_open', f.is_open,
           'link', f.link,
           -- 'blueprint', f.blueprint, -- OPTIMIZED: Removed heavy unused field
           -- 'header', f.header, -- OPTIMIZED: Removed heavy unused field
           -- 'header_off', f.header_off, -- OPTIMIZED: Unused in list
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

  -- Ticket Stats (Unchanged: Financial/Ticket data usually remains even if user is hidden)
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

  -- User Stats (MODIFIED: Now filters out hidden users)
  LEFT JOIN (
      SELECT
          ou.occasion,
          COUNT(*) as user_count
      FROM public.occasion_users ou

      -- Join to Organization Users using the org_id fetched at the start
      LEFT JOIN public.organization_users org_u
          ON ou."user" = org_u."user"
          AND org_u.organization = org_id

      -- Filter: Only include users who are NOT hidden
      -- (IS NOT TRUE covers both FALSE and NULL)
      WHERE (org_u.is_hidden IS NOT TRUE)

      GROUP BY ou.occasion
  ) AS user_stats ON o.id = user_stats.occasion

  WHERE o.unit = unit_id
  AND (
      EXISTS (
          SELECT 1 FROM public.unit_users
          WHERE "user" = auth.uid()
            AND unit = unit_id
            AND (is_manager = true OR is_editor = true OR is_editor_view = true)
      )
      OR
      EXISTS (
          SELECT 1 FROM public.occasion_users ou
          WHERE ou.occasion = o.id
            AND ou."user" = auth.uid()
            AND (ou.is_manager IS TRUE OR ou.is_editor IS TRUE OR ou.is_editor_view IS TRUE OR ou.is_editor_order IS TRUE OR ou.is_editor_order_view IS TRUE)
      )
  );

  -- Step 4: If no occasions were found, return an empty JSON array.
  IF occasion_data IS NULL THEN
    occasion_data := '[]'::jsonb;
  END IF;

  -- Step 5: Return the aggregated JSON data directly.
  RETURN occasion_data;
END;
$$ LANGUAGE plpgsql;
