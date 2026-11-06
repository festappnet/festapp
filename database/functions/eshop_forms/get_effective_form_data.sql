-- Pure shared metadata owner: email preparation must not depend on analytics policy tables.
CREATE OR REPLACE FUNCTION public.effective_form_metadata_internal(p_form_data jsonb,p_unit_data jsonb)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT (public.normalize_form_metadata_internal(p_form_data)-'analytics') || jsonb_build_object(
  'communication_tone',CASE
   WHEN p_form_data->>'communication_tone' IN ('formal','informal') THEN p_form_data->>'communication_tone'
   WHEN p_unit_data->>'communication_tone' IN ('formal','informal') THEN p_unit_data->>'communication_tone'
   ELSE 'formal' END);
$$;
REVOKE ALL ON FUNCTION public.effective_form_metadata_internal(jsonb,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.effective_form_metadata_internal(jsonb,jsonb) TO service_role;
-- The normalizer is a pure JSON transformation, with no table access.
GRANT EXECUTE ON FUNCTION public.normalize_form_metadata_internal(jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.get_effective_form_data(p_form_id bigint)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = public, extensions
AS $$
    SELECT public.effective_form_metadata_internal(f.data,u.data) || jsonb_build_object(
        'analytics',public.form_measurement_runtime_internal(f.id)
    )
    FROM public.forms f
    JOIN public.occasions o ON o.id = f.occasion
    JOIN public.units u ON u.id = o.unit
    WHERE f.id = p_form_id;
$$;

REVOKE ALL ON FUNCTION public.get_effective_form_data(bigint)
FROM PUBLIC, anon, authenticated, service_role;
