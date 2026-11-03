-- Counseling feature gate. Reads the new "counseling" element in
-- occasions.features (decision R3). Speakers themselves are core and no longer
-- gated; only the counseling flow (areas catalog, slot generator, matcher,
-- booking window/limit) depends on this feature being enabled.
CREATE OR REPLACE FUNCTION public.get_is_counseling_enabled_on_occasion(p_occasion BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.occasions o
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(o.features, '[]'::jsonb)) feature
    WHERE o.id = p_occasion
      AND feature->>'code' = 'counseling'
      AND LOWER(COALESCE(feature->>'is_enabled', 'false')) = 'true'
  );
$$;
