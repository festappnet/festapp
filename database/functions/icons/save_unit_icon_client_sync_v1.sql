CREATE OR REPLACE FUNCTION public.save_unit_icon_client_sync_v1(p_unit bigint, p_command_id uuid, p_icon jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE
  v_actor uuid:=auth.uid();  v_organization bigint; v_id bigint;
  v_begin jsonb; v_hash text; v_commit jsonb; v_icon jsonb; v_response jsonb;
BEGIN
  SELECT u.organization INTO v_organization FROM public.units u WHERE u.id=p_unit;
  IF v_actor IS NULL OR p_unit IS NULL OR NOT public.can_write_unit_icons(p_unit) THEN
    RAISE insufficient_privilege USING MESSAGE='unit editor required';
  END IF;
  IF p_icon IS NULL OR jsonb_typeof(p_icon)<>'object'
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_icon) key WHERE key NOT IN ('link','svg'))
    OR NOT (p_icon ?& ARRAY['link','svg'])
    OR length(p_icon->>'link') NOT BETWEEN 1 AND 200
    OR octet_length(COALESCE(p_icon->>'svg','')) NOT BETWEEN 1 AND 51200 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid icon';
  END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('unit',p_unit,
    'icon',p_icon)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_unit_client_mutation_v1(p_command_id,'unit.icon.save',p_unit,
    v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  INSERT INTO public.icons(link,data,organization,unit,created_by)
  VALUES (p_icon->>'link',p_icon->>'svg',v_organization,p_unit,v_actor)
  RETURNING id INTO v_id;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('icon','unit',p_unit,v_id::text,1);
  SELECT to_jsonb(i)||jsonb_build_object('aggregate_version',1)
    INTO v_icon FROM public.icons i WHERE i.id=v_id;
  v_response:=public.complete_unit_mutation_internal_v1(p_command_id,p_unit,'unit.icon.save','icon',v_id,'insert',jsonb_build_object('icon',v_icon));
  PERFORM public.fanout_unit_map_catalog_internal_v1((v_response#>>'{mutation,commitId}')::uuid,p_unit);
  RETURN v_response;
END; $function$

;

REVOKE ALL ON FUNCTION public.save_unit_icon_client_sync_v1(bigint,uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_unit_icon_client_sync_v1(bigint,uuid,jsonb) TO authenticated;
