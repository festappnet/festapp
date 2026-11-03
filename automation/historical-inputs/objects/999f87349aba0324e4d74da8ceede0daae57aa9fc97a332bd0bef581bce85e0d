CREATE OR REPLACE FUNCTION get_available_occasions(
  p_organization_id bigint,
  p_unit_id bigint DEFAULT NULL
)
RETURNS jsonb
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  result_data jsonb;
  occasions_data jsonb;
BEGIN
  -- 1. Validation
  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = p_organization_id) THEN
    RAISE EXCEPTION 'organization_not_found: Organization % does not exist.', p_organization_id USING ERRCODE = 'P0002';
  END IF;

  IF p_unit_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.units WHERE id = p_unit_id AND organization = p_organization_id) THEN
      RAISE EXCEPTION 'unit_not_found: Unit % not found in Org %.', p_unit_id, p_organization_id USING ERRCODE = 'P0002';
    END IF;
  END IF;

  -- 2. Fetch Occasions with Source Integration
  -- We LEFT JOIN external_occasions_cache to get source metadata
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', o.id,
        'title', o.title,
        'description', o.description,
        'link', o.link,
        'start_time', o.start_time,
        'end_time', o.end_time,
        'is_open', o.is_open,
        'is_hidden', o.is_hidden,
        'is_promoted', o.is_promoted, -- Added for frontend filtering
        'features', o.features,
        'created_at', o.created_at,
        'updated_at', o.updated_at,
        'data', o.data,
        -- New Architectural Fields:
        'source_name', c.source_name,         -- "From Source X"
        'last_synced_at', c.last_synced_at,   -- "Synced 5m ago"
        'is_external', (c.source_name IS NOT NULL),
        -- Form Info (Preserved from original logic)
        'form', (
           SELECT jsonb_build_object(
              'id', f.id,
              'created_at', f.created_at,
              'data', f.data,
              'type', f.type,
              'is_open', f.is_open,
              'link', f.link,
              'header', f.header
           )
           FROM public.forms f
           WHERE f.occasion = o.id
           ORDER BY f.is_open DESC, f.id
           LIMIT 1
        )
      )
      ORDER BY o.start_time DESC
    ),
    '[]'::jsonb
  )
  INTO occasions_data
  FROM public.occasions o
  LEFT JOIN public.external_occasions_cache c ON o.link = c.link
  WHERE 
    -- Organization Filter
    -- Organization Filter: Match Org ID OR Include ALL External Occasions
    (o.organization = p_organization_id OR c.source_name IS NOT NULL)
    -- Unit Filter (Optional)
    AND (p_unit_id IS NULL OR o.unit = p_unit_id)
    -- Visibility Rules
    AND o.is_hidden = false
    -- Promotion Rule: STRICT - Must be promoted, even if external
    AND (p_unit_id IS NOT NULL OR o.is_promoted = true);

  -- 3. Construct Result Object
  IF p_unit_id IS NULL THEN
      result_data := jsonb_build_object(
        'title', 'All Occasions',
        'organization', p_organization_id,
        'occasions', occasions_data
      );
  ELSE
      SELECT jsonb_build_object(
        'id', u.id,
        'title', u.title,
        'organization', u.organization,
        'occasions', occasions_data
      )
      INTO result_data
      FROM public.units u
      WHERE u.id = p_unit_id;
  END IF;

  RETURN result_data;
END;
$$ LANGUAGE plpgsql;
