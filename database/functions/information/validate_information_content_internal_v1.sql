-- Shared field validation. Unit games have no valid hidden-answer authority.
CREATE OR REPLACE FUNCTION public.validate_information_content_internal_v1(p_information jsonb,p_unit boolean)
RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path=public,extensions AS $$
BEGIN
 IF p_information IS NULL OR jsonb_typeof(p_information)<>'object' OR octet_length(p_information::text)>786432
 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_information) k WHERE k NOT IN
 ('id','title','description','type','isHidden','order','data','hiddenData'))
 OR jsonb_typeof(p_information->'isHidden') IS DISTINCT FROM 'boolean'
 OR length(coalesce(p_information->>'title',''))>500 OR length(coalesce(p_information->>'type',''))>100
 OR octet_length(coalesce(p_information->>'description',''))>524288
 OR octet_length(coalesce((p_information->'data')::text,''))>131072
 OR octet_length(coalesce((p_information->'hiddenData')::text,''))>65536
 OR ((p_information->>'type') IS DISTINCT FROM 'game' AND coalesce(p_information->'hiddenData','null')<>'null')
 OR (p_unit AND (p_information->>'type'='game' OR coalesce(p_information->'hiddenData','null')<>'null'))
 THEN RAISE invalid_parameter_value USING MESSAGE='invalid information aggregate or unsupported unit game'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.validate_information_content_internal_v1(jsonb,boolean) FROM PUBLIC,anon,authenticated;
