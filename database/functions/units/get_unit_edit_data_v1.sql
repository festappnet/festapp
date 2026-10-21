CREATE OR REPLACE FUNCTION public.get_unit_edit_data_v1(p_unit bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_result jsonb; v_version bigint;
BEGIN
  IF auth.uid() IS NULL OR NOT public.can_manage_unit_configuration(p_unit) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
  v_result:=public.get_unit_edit_data(p_unit);
  SELECT COALESCE(v.version,0) INTO v_version
    FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
      ON v.aggregate_type='unit' AND v.scope_type='unit'
      AND v.scope_id=p_unit AND v.aggregate_id=p_unit::text;
  RETURN jsonb_set(v_result,'{unit}',(v_result->'unit')||
    jsonb_build_object('aggregate_version',v_version));
END; $function$
;
REVOKE ALL ON FUNCTION public.get_unit_edit_data_v1(p_unit bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_unit_edit_data_v1(p_unit bigint) TO authenticated;
