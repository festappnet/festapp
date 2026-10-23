CREATE OR REPLACE FUNCTION public.get_information_editor_bundle_v1(p_occasion bigint, p_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE v_information jsonb;
BEGIN
  IF NOT public.can_read_information_editor_bundle(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor view required';
  END IF;
  SELECT COALESCE(jsonb_agg(public.get_information_command_data_v1(i.id)||
    jsonb_build_object('aggregate_version',COALESCE(v.version,0))
    ORDER BY i."order" NULLS LAST,i.id),'[]'::jsonb) INTO v_information
  FROM public.information i LEFT JOIN public.client_aggregate_versions v
    ON v.aggregate_type='information' AND v.scope_type='occasion'
    AND v.scope_id=p_occasion AND v.aggregate_id=i.id::text
  WHERE i.occasion=p_occasion AND (CASE WHEN p_type IS NULL
    THEN NULLIF(i.type,'') IS NULL ELSE i.type=p_type END);
  RETURN jsonb_build_object('code',200,'information',v_information);
END; $function$
;
REVOKE ALL ON FUNCTION public.get_information_editor_bundle_v1(p_occasion bigint, p_type text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_information_editor_bundle_v1(p_occasion bigint, p_type text) TO authenticated;
REVOKE ALL ON FUNCTION public.get_information_editor_bundle_v1(bigint,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_information_editor_bundle_v1(bigint,text) TO authenticated,service_role;
