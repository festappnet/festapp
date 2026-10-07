CREATE OR REPLACE FUNCTION public.move_place_client_sync_v1(p_occasion bigint, p_place_id bigint, p_command_id uuid, p_expected_version bigint, p_lat double precision, p_lng double precision)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_actor uuid:=auth.uid(); v_version bigint; v_begin jsonb; v_hash text;
  v_place public.places%ROWTYPE; v_commit jsonb; v_public jsonb; v_response jsonb;
  v_is_publishable boolean; v_affects_public boolean; v_group bigint; v_impacts jsonb:='[]'; v_replacements jsonb:='[]';
BEGIN
 PERFORM public.assert_canonical_mutation_write_release_internal_v1(p_occasion);
  SELECT p.* INTO v_place FROM public.places p
    WHERE p.id=p_place_id AND p.occasion=p_occasion;
  IF NOT FOUND THEN RAISE invalid_parameter_value USING MESSAGE='place not found'; END IF;
  IF v_actor IS NULL OR p_lat IS NULL OR p_lng IS NULL OR p_lat NOT BETWEEN -90 AND 90 OR p_lng NOT BETWEEN -180 AND 180
    OR NOT (public.get_is_editor_on_occasion(p_occasion) OR EXISTS (
      SELECT 1 FROM public.user_groups ug JOIN public.user_group_info g
        ON g.id=ug."group" WHERE ug."user"=v_actor AND ug.is_admin
        AND g.occasion=p_occasion AND g.place=p_place_id
        AND v_place.type='group' AND v_place.is_hidden)) THEN
    RAISE insufficient_privilege USING MESSAGE='place move permission required';
  END IF;
  SELECT NOT o.is_hidden INTO v_is_publishable FROM public.occasions o WHERE o.id=p_occasion;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'placeId',p_place_id,'expectedVersion',p_expected_version,'lat',p_lat,'lng',p_lng)::text,
    'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'map.place.move',p_occasion,
    v_actor,v_hash);
  PERFORM public.lock_group_occasion_internal_v1(p_occasion);
  SELECT p.* INTO v_place FROM public.places p WHERE p.id=p_place_id AND p.occasion=p_occasion FOR UPDATE;
  IF NOT FOUND THEN RAISE invalid_parameter_value USING MESSAGE='place not found'; END IF;
  IF v_actor IS NULL OR p_lat IS NULL OR p_lng IS NULL OR p_lat NOT BETWEEN -90 AND 90 OR p_lng NOT BETWEEN -180 AND 180
    OR NOT (public.get_is_editor_on_occasion(p_occasion) OR EXISTS (
      SELECT 1 FROM public.user_groups ug JOIN public.user_group_info g
        ON g.id=ug."group" WHERE ug."user"=v_actor AND ug.is_admin
        AND g.occasion=p_occasion AND g.place=p_place_id
        AND v_place.type='group' AND v_place.is_hidden)) THEN
    RAISE insufficient_privilege USING MESSAGE='place move permission required';
  END IF;
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF v_place.type='group' AND v_place.is_hidden THEN
    SELECT id INTO v_group FROM public.user_group_info WHERE occasion=p_occasion AND place=p_place_id ORDER BY id LIMIT 1;
    PERFORM public.assert_group_place_owner_internal_v1(p_occasion,v_group,p_place_id,false);
  END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('place','occasion',p_occasion,p_place_id::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='place' AND scope_type='occasion' AND scope_id=p_occasion
      AND aggregate_id=p_place_id::text FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,
      'conflict',409,jsonb_build_object('version',v_version,'place',
        to_jsonb(v_place)||jsonb_build_object('aggregate_version',v_version)),'{}','[]','user',NULL,v_replacements);
  END IF;
  IF v_place.coordinates=jsonb_build_object('latLng',jsonb_build_object('lat',p_lat,'lng',p_lng)) THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,
      'unchanged',200,jsonb_build_object('version',v_version,'place',
        to_jsonb(v_place)||jsonb_build_object('aggregate_version',v_version)),'{}','[]','user',NULL,v_replacements);
  END IF;
  UPDATE public.places SET coordinates=jsonb_build_object('latLng',
    jsonb_build_object('lat',p_lat,'lng',p_lng)),updated_at=clock_timestamp()
    WHERE id=p_place_id RETURNING * INTO v_place;
  UPDATE public.client_aggregate_versions SET version=version+1,
    updated_at=clock_timestamp() WHERE aggregate_type='place'
    AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_place_id::text
    RETURNING version INTO v_version;
  IF v_group IS NOT NULL THEN
    UPDATE public.client_aggregate_versions SET version=version+1,updated_at=clock_timestamp()
      WHERE aggregate_type='user_group' AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_group::text;
  END IF;
  v_impacts:=public.group_profile_impacts_internal_v1(p_occasion,ARRAY(SELECT DISTINCT ug."user" FROM public.user_groups ug JOIN public.user_group_info g ON g.id=ug."group" WHERE g.occasion=p_occasion AND g.place=p_place_id));
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_impacts) x WHERE x->>'userId'=v_actor::text) THEN
    v_replacements:=jsonb_build_array(jsonb_build_object('component','private_profile','userId',v_actor,'payload',public.get_private_profile_payload_v1(p_occasion,v_actor)));
  END IF;
  v_affects_public:=NOT v_place.is_hidden;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'map.place.move','map',
    jsonb_build_array(jsonb_build_object('entityType','place','entityId',p_place_id,
      'operation','update','safeLabel',left(v_place.title,240),
      'changedFields',jsonb_build_array('coordinates'))),
    CASE WHEN v_is_publishable AND v_affects_public THEN ARRAY['map_catalog']
      ELSE '{}'::text[] END,v_impacts,'[]',
    jsonb_build_object('version',v_version,'place',to_jsonb(v_place)||
      jsonb_build_object('aggregate_version',v_version)),'{}','[]','user',NULL,v_replacements);
END; $function$
;
REVOKE ALL ON FUNCTION public.move_place_client_sync_v1(bigint,bigint,uuid,bigint,double precision,double precision) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.move_place_client_sync_v1(bigint,bigint,uuid,bigint,double precision,double precision) TO authenticated;
