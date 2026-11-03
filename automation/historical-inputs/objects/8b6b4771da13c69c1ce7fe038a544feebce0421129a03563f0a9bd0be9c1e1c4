CREATE OR REPLACE FUNCTION public.get_is_event_feedback_enabled_on_occasion(
    p_occasion bigint
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.occasions o
    CROSS JOIN LATERAL jsonb_array_elements(
      COALESCE(o.features, '[]'::jsonb)
    ) feature
    WHERE o.id = p_occasion
      AND feature->>'code' = 'event_feedback'
      AND LOWER(COALESCE(feature->>'is_enabled', 'false')) = 'true'
  );
$function$;

REVOKE ALL ON FUNCTION public.get_is_event_feedback_enabled_on_occasion(bigint)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_is_event_feedback_enabled_on_occasion(bigint)
  TO anon, authenticated, service_role;
