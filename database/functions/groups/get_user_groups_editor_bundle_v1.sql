CREATE OR REPLACE FUNCTION public.get_user_groups_editor_bundle_v1(p_occasion bigint, p_type text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE v_groups jsonb; v_places jsonb; v_game_definitions jsonb;
BEGIN
  IF (public.get_is_editor_view_on_occasion(p_occasion) OR public.get_is_editor_on_occasion(p_occasion)) IS NOT TRUE THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor view required';
  END IF;
  SELECT COALESCE(jsonb_agg(public.get_user_group_command_data_v1(g.id)||
    jsonb_build_object('aggregate_version',COALESCE(v.version,0))
    ORDER BY g.title,g.id),'[]'::jsonb) INTO v_groups
  FROM public.user_group_info g LEFT JOIN public.client_aggregate_versions v
    ON v.aggregate_type='user_group' AND v.scope_type='occasion'
    AND v.scope_id=p_occasion AND v.aggregate_id=g.id::text
  WHERE g.occasion=p_occasion AND (p_type IS NULL AND g.type IS NULL OR g.type=p_type);
  SELECT COALESCE(jsonb_agg(to_jsonb(p)||jsonb_build_object(
    'aggregate_version',COALESCE(v.version,0)) ORDER BY p."order" NULLS LAST,p.title),
    '[]'::jsonb) INTO v_places FROM public.places p
  LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='place'
    AND v.scope_type='occasion' AND v.scope_id=p_occasion
    AND v.aggregate_id=p.id::text
  WHERE p.occasion=p_occasion AND NOT p.is_hidden
    AND p.coordinates->'latLng'->>'lat' IS NOT NULL
    AND p.coordinates->'latLng'->>'lng' IS NOT NULL;
  IF p_type='game' THEN
    SELECT jsonb_object_agg(i.id,i.title) INTO v_game_definitions
    FROM public.information i WHERE i.occasion=p_occasion AND i.type='game';
  END IF;
  RETURN jsonb_build_object('groups',v_groups,'places',v_places,
    'game_definitions',v_game_definitions);
END; $function$
;
REVOKE ALL ON FUNCTION public.get_user_groups_editor_bundle_v1(bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_user_groups_editor_bundle_v1(bigint,text) TO authenticated;
