CREATE OR REPLACE FUNCTION public.delete_unit_icon_client_sync_v1(p_unit bigint, p_icon_id bigint, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE
  v_actor uuid:=auth.uid();  v_icon public.icons%ROWTYPE;
  v_begin jsonb; v_hash text; v_commit jsonb; v_response jsonb;
  v_places bigint; v_paths bigint; v_types bigint; v_refs jsonb;
BEGIN
  PERFORM 1 FROM public.units WHERE id=p_unit;
  IF v_actor IS NULL OR p_unit IS NULL OR NOT public.get_is_editor_on_unit(p_unit) THEN
    RAISE insufficient_privilege USING MESSAGE='unit editor required';
  END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('unit',p_unit,
    'iconId',p_icon_id)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_unit_client_mutation_v1(p_command_id,'unit.icon.delete',p_unit,
    v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT i.* INTO v_icon FROM public.icons i WHERE i.id=p_icon_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,
      'unchanged',200,jsonb_build_object('icon',NULL));
  END IF;
  IF v_icon.unit IS NULL OR v_icon.unit IS DISTINCT FROM p_unit THEN
    RAISE insufficient_privilege USING MESSAGE='icon belongs to another unit or is legacy';
  END IF;
  SELECT count(*) INTO v_places FROM public.places p WHERE p.icon=p_icon_id;
  SELECT count(*) INTO v_paths FROM public.path_groups pg WHERE pg.icon=p_icon_id;
  SELECT count(*) INTO v_types FROM public.place_types pt WHERE pt.icon=p_icon_id;
  IF v_places+v_paths+v_types>0 THEN
    v_refs:=jsonb_build_object('places',v_places,'path_groups',v_paths,
      'place_types',v_types);
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,
      'rejected',409,jsonb_build_object('icon',to_jsonb(v_icon),'refs',v_refs));
  END IF;
  DELETE FROM public.icons WHERE id=p_icon_id;
  DELETE FROM public.client_aggregate_versions WHERE aggregate_type='icon'
    AND scope_type='unit' AND scope_id=p_unit AND aggregate_id=p_icon_id::text;
  v_response:=public.complete_unit_mutation_internal_v1(p_command_id,p_unit,'unit.icon.delete','icon',p_icon_id,'delete',jsonb_build_object('icon',NULL));
  PERFORM public.fanout_unit_map_catalog_internal_v1((v_response#>>'{mutation,commitId}')::uuid,p_unit);
  RETURN v_response;
END; $function$

;

REVOKE ALL ON FUNCTION public.delete_unit_icon_client_sync_v1(bigint,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_unit_icon_client_sync_v1(bigint,bigint,uuid) TO authenticated;
