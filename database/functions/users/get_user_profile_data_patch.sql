CREATE OR REPLACE FUNCTION public.get_user_profile_data_patch(p_data jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = public, extensions
AS $$
  SELECT COALESCE(jsonb_object_agg(entry.key, entry.value), '{}'::jsonb)
  FROM jsonb_each(
    CASE WHEN jsonb_typeof(p_data) = 'object' THEN p_data ELSE '{}'::jsonb END
  ) AS entry
  WHERE entry.key = ANY (ARRAY[
    'name', 'surname', 'sex', 'phone', 'birthDate'
  ]::text[]);
$$;

REVOKE ALL ON FUNCTION public.get_user_profile_data_patch(jsonb) FROM PUBLIC;
