-- Preserve the private form-settings helper contract while allowing email metadata preparation.
-- Pure shared metadata owner: email preparation must not depend on analytics policy tables.
CREATE OR REPLACE FUNCTION public.effective_form_metadata_internal(p_form_data jsonb,p_unit_data jsonb)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT (public.normalize_form_metadata_internal(p_form_data)-'analytics') || jsonb_build_object(
  'communication_tone',CASE
   WHEN p_form_data->>'communication_tone' IN ('formal','informal') THEN p_form_data->>'communication_tone'
   WHEN p_unit_data->>'communication_tone' IN ('formal','informal') THEN p_unit_data->>'communication_tone'
   ELSE 'formal' END);
$$;
REVOKE ALL ON FUNCTION public.effective_form_metadata_internal(jsonb,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.effective_form_metadata_internal(jsonb,jsonb) TO service_role;
-- Keep the underlying normalizer private. This definer only transforms caller-provided JSON;
-- it has no table access or data mutation and exposes no stored form/Unit records.
REVOKE ALL ON FUNCTION public.normalize_form_metadata_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

