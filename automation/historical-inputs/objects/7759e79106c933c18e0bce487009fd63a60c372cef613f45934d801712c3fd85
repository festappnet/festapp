CREATE OR REPLACE FUNCTION get_all_service_items(oc BIGINT, type TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
  result JSONB;
BEGIN
  result := jsonb_build_object(
    'code', 200,
    'data', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'code', item->>'code',
          'title', item->>'title',
          'reference', (item->>'reference')::BIGINT
        )
      )
      FROM public.occasions,
           jsonb_array_elements(occasions.services->type) AS item
      WHERE occasions.id = oc
        AND occasions.services ? type
    ), '[]'::jsonb)  -- Use an empty JSON array if no items are found
  );

  RETURN result;
END;
$$;
