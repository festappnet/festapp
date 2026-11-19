-- Pure shared metadata owner: email preparation must not depend on analytics policy tables.
CREATE OR REPLACE FUNCTION public.effective_form_metadata_internal(p_form_data jsonb,p_unit_data jsonb)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT (public.normalize_form_metadata_internal(p_form_data)-'analytics') || jsonb_build_object(
  'communication_tone',public.resolve_communication_tone(
   p_form_data->>'communication_tone',p_unit_data->>'communication_tone'));
$$;
REVOKE ALL ON FUNCTION public.effective_form_metadata_internal(jsonb,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.effective_form_metadata_internal(jsonb,jsonb) TO service_role;
-- Keep the underlying normalizer private. This definer only transforms caller-provided JSON;
-- it has no table access or data mutation and exposes no stored form/Unit records.
REVOKE ALL ON FUNCTION public.normalize_form_metadata_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_effective_form_data(p_form_id bigint)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = public, extensions
AS $$
    WITH form_metadata AS MATERIALIZED (
        SELECT public.effective_form_metadata_internal(f.data,u.data) AS metadata,
               o.end_time
        FROM public.forms f
        JOIN public.occasions o ON o.id = f.occasion
        JOIN public.units u ON u.id = o.unit
        WHERE f.id = p_form_id
    )
    SELECT metadata || jsonb_build_object(
        'schedule', coalesce(metadata->'schedule','{}'::jsonb) || jsonb_build_object(
            'end_time', coalesce(nullif(metadata#>'{schedule,end_time}','null'::jsonb),to_jsonb(end_time))
        ),
        'analytics', public.form_measurement_runtime_internal(p_form_id)
    )
    FROM form_metadata;
$$;

REVOKE ALL ON FUNCTION public.get_effective_form_data(bigint)
FROM PUBLIC, anon, authenticated, service_role;
