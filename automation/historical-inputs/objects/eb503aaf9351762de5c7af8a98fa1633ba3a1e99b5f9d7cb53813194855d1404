CREATE OR REPLACE FUNCTION get_public_occasions(
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
  -- 1. First, check if the provided organization exists.
  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = p_organization_id) THEN
    RAISE EXCEPTION 'organization_not_found: Organization with id % does not exist.', p_organization_id
      USING ERRCODE = 'P0002'; -- P0002 = no_data_found
  END IF;

  -- 2. Handle the case where unit_id IS NULL.
  -- Fetch all occasions for the given organization.
  IF p_unit_id IS NULL THEN

    -- Query all non-hidden, open, and promoted occasions for the specified organization
    SELECT COALESCE(
      jsonb_agg(
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
             -- Sort by is_open DESC (True first), then by ID
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
    WHERE o.organization = p_organization_id
      AND o.is_hidden = false
      AND o.is_promoted = true;

    -- Build a "virtual" unit object to hold these occasions,
    -- matching the structure of the "ELSE" block.
    result_data := jsonb_build_object(
      'id', NULL,
      'created_at', NULL,
      'title', 'All Occasions', -- Placeholder title
      'organization', p_organization_id,
      'data', NULL,
      'features', NULL,
      'occasions', occasions_data
    );

  -- 3. Handle the case where unit_id IS NOT NULL.
  -- Fetch data for that specific unit.
  ELSE
    -- Check if the unit exists AND belongs to the specified organization
    IF NOT EXISTS (
      SELECT 1
      FROM public.units
      WHERE id = p_unit_id
        AND organization = p_organization_id
    ) THEN
      RAISE EXCEPTION 'unit_not_found: Unit with id % in organization % does not exist.', p_unit_id, p_organization_id
        USING ERRCODE = 'P0002'; -- P0002 = no_data_found
    END IF;

    -- If check passes, run the original query.
    SELECT jsonb_build_object(
      'id', u.id,
      'created_at', u.created_at,
      'title', u.title,
      'organization', u.organization,
      'data', u.data,
      'features', u.features,
      'occasions', (
         SELECT COALESCE(
           jsonb_agg(
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
                  -- Sort by is_open DESC (True first), then by ID
                  ORDER BY f.is_open DESC, f.id
                  LIMIT 1
               )
             )
             ORDER BY o.start_time DESC
           ),
           '[]'::jsonb
         )
         FROM public.occasions o
         WHERE o.unit = u.id
           AND o.is_hidden = false
      )
    )
    INTO result_data
    FROM public.units u
    WHERE u.id = p_unit_id;
  END IF;

  -- 4. Return the resulting JSON object directly.
  RETURN result_data;
END;
$$ LANGUAGE plpgsql;