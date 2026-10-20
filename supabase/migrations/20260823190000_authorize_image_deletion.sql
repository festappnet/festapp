CREATE OR REPLACE FUNCTION public.authorize_image_deletion(p_links text[])
RETURNS TABLE(link text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_requested_count integer;
  v_found_count integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
  END IF;

  v_requested_count := cardinality(p_links);
  IF v_requested_count IS NULL OR v_requested_count < 1 OR v_requested_count > 50
     OR array_position(p_links, NULL) IS NOT NULL
     OR v_requested_count <> (SELECT count(DISTINCT requested) FROM unnest(p_links) AS requested) THEN
    RAISE EXCEPTION 'Image link batch must contain 1-50 unique non-null links.'
      USING ERRCODE = '22023';
  END IF;

  SELECT count(DISTINCT image.link) INTO v_found_count
  FROM public.images AS image
  WHERE image.link = ANY(p_links);

  IF v_found_count <> v_requested_count THEN
    RAISE EXCEPTION 'Every image link must exist.' USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.images AS image
    WHERE image.link = ANY(p_links)
      AND NOT (
        (image.unit IS NOT NULL AND public.get_is_editor_on_unit(image.unit))
        OR
        (image.occasion IS NOT NULL AND (
          public.get_is_editor_on_occasion(image.occasion)
          OR public.get_is_editor_order_on_occasion(image.occasion)
        ))
      )
  ) THEN
    RAISE EXCEPTION 'Permission denied for image deletion.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT DISTINCT image.link
  FROM public.images AS image
  WHERE image.link = ANY(p_links)
  ORDER BY image.link;
END;
$$;

REVOKE ALL ON FUNCTION public.authorize_image_deletion(text[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.authorize_image_deletion(text[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.authorize_image_deletion(text[]) TO authenticated;
