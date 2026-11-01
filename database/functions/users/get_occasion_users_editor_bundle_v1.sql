CREATE OR REPLACE FUNCTION public.get_occasion_users_editor_bundle_v1(p_occasion bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_result jsonb; v_users jsonb;
BEGIN
  v_result:=public.get_occasion_users_for_edit(p_occasion)::jsonb;
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN RETURN v_result; END IF;
  WITH companion_owners AS (
    SELECT uc.companion,uc."user" owner_id,uc.origin,
      concat_ws(' ',owner_info.name,owner_info.surname) owner_name
    FROM public.user_companions uc
    JOIN public.user_info owner_info ON owner_info.id=uc."user"
    WHERE uc.occasion=p_occasion AND public.occasion_member_visible_internal(p_occasion,owner_info.id)
  )
  SELECT COALESCE(jsonb_agg(row.value||jsonb_strip_nulls(jsonb_build_object(
      'aggregate_version',COALESCE(v.version,0),
      'companion_owner_id',owners.owner_id,
      'companion_owner_name',owners.owner_name,
      'companion_origin',owners.origin))),'[]'::jsonb)
  INTO v_users
  FROM jsonb_array_elements(v_result#>'{data,occasion_users}') row
  LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='occasion_user'
    AND v.scope_type='occasion' AND v.scope_id=p_occasion
    AND v.aggregate_id=row.value->>'user'
  LEFT JOIN companion_owners owners ON owners.companion=(row.value->>'user')::uuid;
  RETURN jsonb_set(v_result,'{data,occasion_users}',v_users);
END $function$
;
REVOKE ALL ON FUNCTION public.get_occasion_users_editor_bundle_v1(p_occasion bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_users_editor_bundle_v1(p_occasion bigint) TO authenticated;
REVOKE ALL ON FUNCTION public.get_occasion_users_editor_bundle_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_occasion_users_editor_bundle_v1(bigint) TO authenticated,service_role;
