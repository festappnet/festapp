CREATE OR REPLACE FUNCTION public.save_user_group_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_group jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_actor uuid:=auth.uid(); v_id bigint; v_version bigint; v_begin jsonb;
  v_hash text; v_current jsonb; v_requested jsonb; v_entity jsonb;
  v_participants jsonb; v_current_participants jsonb;
  v_old_users uuid[]; v_new_users uuid[];
  v_old_place bigint; v_old_private boolean:=false; v_place_id bigint;
  v_private_place jsonb; v_place_version bigint; v_private_impacts jsonb;
  v_current_place jsonb; v_requested_place jsonb; v_place_changed boolean:=false;
  v_actor_replacements jsonb:='[]'::jsonb;
BEGIN
  v_id:=(p_group->>'id')::bigint;
  IF v_actor IS NULL OR NOT (public.get_is_editor_on_occasion(p_occasion)
    OR (v_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.user_groups ug
      JOIN public.user_group_info g ON g.id=ug."group"
      WHERE ug."group"=v_id AND ug."user"=v_actor AND ug.is_admin
        AND g.occasion=p_occasion))) THEN
    RAISE insufficient_privilege USING MESSAGE='group editor required';
  END IF;
  IF p_group IS NULL OR jsonb_typeof(p_group)<>'object'
    OR octet_length(p_group::text)>524288
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_group) key WHERE key NOT IN
      ('id','title','description','type','placeId','privatePlace','participants'))
    OR NOT (p_group ?& ARRAY['title','participants'])
    OR jsonb_typeof(p_group->'participants')<>'array'
    OR jsonb_array_length(p_group->'participants')>5000
    OR length(btrim(COALESCE(p_group->>'title',''))) NOT BETWEEN 1 AND 500
    OR octet_length(COALESCE(p_group->>'description',''))>262144 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid group aggregate';
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('userId',x.user_id,
    'isAdmin',COALESCE(x.is_admin,false)) ORDER BY x.user_id),'[]'::jsonb),
    COALESCE(array_agg(x.user_id ORDER BY x.user_id),'{}'::uuid[])
    INTO v_participants,v_new_users
  FROM jsonb_to_recordset(p_group->'participants') x(user_id uuid,is_admin boolean);
  IF jsonb_array_length(p_group->'participants')<>cardinality(v_new_users)
    OR cardinality(v_new_users)<>cardinality(ARRAY(SELECT DISTINCT unnest(v_new_users)))
    OR EXISTS (SELECT 1 FROM unnest(v_new_users) id LEFT JOIN public.occasion_users ou
      ON ou."user"=id AND ou.occasion=p_occasion WHERE ou."user" IS NULL) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid group participants';
  END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_group->'participants') x WHERE jsonb_typeof(x)<>'object' OR x->>'user_id' IS NULL OR EXISTS(SELECT 1 FROM jsonb_object_keys(x) k WHERE k NOT IN ('user_id','is_admin')))
    OR (p_group->>'placeId' IS NOT NULL AND p_group->'privatePlace' IS NOT NULL AND p_group->'privatePlace'<>'null'::jsonb) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid group participants or place choice'; END IF;
  v_private_place:=p_group->'privatePlace';
  IF v_private_place IS NOT NULL AND v_private_place<>'null'::jsonb AND (
    jsonb_typeof(v_private_place)<>'object'
    OR EXISTS (SELECT 1 FROM jsonb_object_keys(v_private_place) key WHERE key NOT IN
      ('id','title','description','coordinates','order','icon'))
    OR length(btrim(COALESCE(v_private_place->>'title',''))) NOT BETWEEN 1 AND 500
    OR jsonb_typeof(v_private_place->'coordinates')<>'object'
    OR octet_length(v_private_place::text)>131072) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid private group place';
  END IF;
  IF v_private_place IS NOT NULL AND v_private_place<>'null'::jsonb THEN
    IF jsonb_typeof(v_private_place#>'{coordinates,latLng,lat}') IS DISTINCT FROM 'number'
      OR jsonb_typeof(v_private_place#>'{coordinates,latLng,lng}') IS DISTINCT FROM 'number'
      OR (v_private_place#>>'{coordinates,latLng,lat}')::double precision NOT BETWEEN -90 AND 90
      OR (v_private_place#>>'{coordinates,latLng,lng}')::double precision NOT BETWEEN -180 AND 180
      OR (v_private_place->>'icon' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.icons i JOIN public.occasions o ON o.id=p_occasion AND i.organization=o.organization WHERE i.id=(v_private_place->>'icon')::bigint AND (i.unit=o.unit OR i.unit IS NULL))) THEN
      RAISE invalid_parameter_value USING MESSAGE='invalid private coordinates or icon'; END IF;
  END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'expectedVersion',p_expected_version,'group',p_group)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.group.save',
    p_occasion,v_actor,v_hash);
  PERFORM public.lock_group_occasion_internal_v1(p_occasion);
  IF v_actor IS NULL OR NOT (public.get_is_editor_on_occasion(p_occasion)
    OR (v_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.user_groups ug
      JOIN public.user_group_info g ON g.id=ug."group"
      WHERE ug."group"=v_id AND ug."user"=v_actor AND ug.is_admin
        AND g.occasion=p_occasion))) THEN
    RAISE insufficient_privilege USING MESSAGE='group editor required';
  END IF;
  IF EXISTS(SELECT 1 FROM unnest(v_new_users) id LEFT JOIN public.occasion_users ou ON ou.occasion=p_occasion AND ou."user"=id WHERE ou."user" IS NULL) THEN RAISE invalid_parameter_value USING MESSAGE='invalid group participants after lock'; END IF;
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF v_id IS NOT NULL THEN
    PERFORM 1 FROM public.user_group_info g WHERE g.id=v_id
      AND g.occasion=p_occasion FOR UPDATE;
    IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,'rejected',404,jsonb_build_object('version',0,'group',NULL)); END IF;
    SELECT g.place,COALESCE(p.is_hidden AND p.type='group',false),
      public.get_user_group_command_data_v1(g.id)
      INTO v_old_place,v_old_private,v_current
    FROM public.user_group_info g LEFT JOIN public.places p ON p.id=g.place
    WHERE g.id=v_id;
    SELECT COALESCE(array_agg(ug."user" ORDER BY ug."user"),'{}'::uuid[]),
      COALESCE(jsonb_agg(jsonb_build_object('userId',ug."user",
        'isAdmin',ug.is_admin) ORDER BY ug."user"),'[]'::jsonb)
      INTO v_old_users,v_current_participants FROM public.user_groups ug
      WHERE ug."group"=v_id;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('user_group','occasion',p_occasion,v_id::text,0) ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
      WHERE aggregate_type='user_group' AND scope_type='occasion'
      AND scope_id=p_occasion AND aggregate_id=v_id::text FOR UPDATE;
    IF p_expected_version IS DISTINCT FROM v_version THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
        jsonb_build_object('version',v_version,'group',v_current)); END IF;
  ELSIF p_expected_version IS NOT NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='new group must not have expected version';
  END IF;
  IF v_private_place IS NOT NULL AND v_private_place<>'null'::jsonb THEN
    v_place_id:=(v_private_place->>'id')::bigint;
    IF v_place_id IS NULL THEN
      INSERT INTO public.places(title,description,type,coordinates,is_hidden,"order",icon,occasion)
      VALUES (v_private_place->>'title',v_private_place->>'description','group',
        v_private_place->'coordinates',true,(v_private_place->>'order')::bigint,
        (v_private_place->>'icon')::bigint,p_occasion) RETURNING id INTO v_place_id;
      v_place_version:=1;
      v_place_changed:=true;
      INSERT INTO public.client_aggregate_versions
        (aggregate_type,scope_type,scope_id,aggregate_id,version)
      VALUES ('place','occasion',p_occasion,v_place_id::text,v_place_version);
    ELSE
      PERFORM 1 FROM public.places p WHERE p.id=v_place_id AND p.occasion=p_occasion
        AND p.type='group' AND p.is_hidden FOR UPDATE;
      IF NOT FOUND OR v_id IS NULL OR NOT v_old_private
        OR v_place_id IS DISTINCT FROM v_old_place THEN
        RAISE invalid_parameter_value USING MESSAGE='private place is not owned by group';
      END IF;
      PERFORM public.assert_group_place_owner_internal_v1(p_occasion,v_id,v_place_id,false);
      INSERT INTO public.client_aggregate_versions
        (aggregate_type,scope_type,scope_id,aggregate_id,version)
      VALUES ('place','occasion',p_occasion,v_place_id::text,0) ON CONFLICT DO NOTHING;
      SELECT jsonb_build_object('id',p.id,'title',p.title,
        'description',p.description,'coordinates',p.coordinates,
        'order',p."order",'icon',p.icon) INTO v_current_place
      FROM public.places p WHERE p.id=v_place_id;
      v_requested_place:=jsonb_build_object('id',v_place_id,
        'title',v_private_place->>'title','description',v_private_place->>'description',
        'coordinates',v_private_place->'coordinates',
        'order',(v_private_place->>'order')::bigint,
        'icon',(v_private_place->>'icon')::bigint);
      v_place_changed:=v_current_place IS DISTINCT FROM v_requested_place;
      IF v_place_changed THEN
        UPDATE public.places SET title=v_private_place->>'title',
          description=v_private_place->>'description',coordinates=v_private_place->'coordinates',
          "order"=(v_private_place->>'order')::bigint,icon=(v_private_place->>'icon')::bigint
          WHERE id=v_place_id;
        UPDATE public.client_aggregate_versions SET version=version+1,
          updated_at=clock_timestamp() WHERE aggregate_type='place'
          AND scope_type='occasion' AND scope_id=p_occasion
          AND aggregate_id=v_place_id::text RETURNING version INTO v_place_version;
      ELSE
        SELECT version INTO v_place_version FROM public.client_aggregate_versions
        WHERE aggregate_type='place' AND scope_type='occasion'
          AND scope_id=p_occasion AND aggregate_id=v_place_id::text;
      END IF;
    END IF;
  ELSE
    v_place_id:=(p_group->>'placeId')::bigint;
    IF v_place_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.places p
      WHERE p.id=v_place_id AND p.occasion=p_occasion AND NOT p.is_hidden) THEN
      RAISE invalid_parameter_value USING MESSAGE='invalid shared group place';
    END IF;
  END IF;
  v_requested:=jsonb_build_object('id',v_id,'title',p_group->>'title',
    'description',p_group->>'description','type',p_group->>'type',
    'place',v_place_id,'participants',v_participants);
  IF v_current IS NOT NULL AND jsonb_build_object('id',v_id,
      'title',v_current->>'title','description',v_current->>'description',
      'type',v_current->>'type','place',(v_current->>'place')::bigint,
      'participants',v_current_participants)=v_requested
      AND NOT v_place_changed THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      jsonb_build_object('version',v_version,'group',v_current));
  END IF;
  IF v_old_private AND v_old_place IS DISTINCT FROM v_place_id THEN
    PERFORM public.assert_group_place_owner_internal_v1(p_occasion,v_id,v_old_place,true);
  END IF;
  IF v_id IS NULL THEN
    INSERT INTO public.user_group_info(title,description,type,place,occasion)
    VALUES (p_group->>'title',p_group->>'description',p_group->>'type',v_place_id,p_occasion)
    RETURNING id INTO v_id;
    v_version:=1;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES ('user_group','occasion',p_occasion,v_id::text,v_version);
  ELSE
    UPDATE public.user_group_info SET title=p_group->>'title',
      description=p_group->>'description',type=p_group->>'type',place=v_place_id
      WHERE id=v_id;
    UPDATE public.client_aggregate_versions SET version=version+1,
      updated_at=clock_timestamp() WHERE aggregate_type='user_group'
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_id::text
      RETURNING version INTO v_version;
  END IF;
  DELETE FROM public.user_groups WHERE "group"=v_id;
  INSERT INTO public.user_groups("user","group",is_admin)
    SELECT x.user_id,v_id,COALESCE(x.is_admin,false)
    FROM jsonb_to_recordset(p_group->'participants') x(user_id uuid,is_admin boolean);
  IF v_old_private AND v_old_place IS DISTINCT FROM v_place_id THEN
    IF EXISTS (SELECT 1 FROM public.user_group_info g WHERE g.id<>v_id
      AND g.place=v_old_place) THEN
      RAISE foreign_key_violation USING MESSAGE='private group place has another owner';
    END IF;
    DELETE FROM public.places WHERE id=v_old_place;
    DELETE FROM public.client_aggregate_versions WHERE aggregate_type='place'
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_old_place::text;
  END IF;
  v_private_impacts:=public.group_profile_impacts_internal_v1(p_occasion,COALESCE(v_old_users,'{}'::uuid[])||v_new_users);
  v_entity:=public.get_user_group_command_data_v1(v_id)||
    jsonb_build_object('aggregate_version',v_version);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_private_impacts) x WHERE x->>'userId'=v_actor::text) THEN
    v_actor_replacements:=jsonb_build_array(jsonb_build_object(
      'component','private_profile','userId',v_actor,
      'payload',public.get_private_profile_payload_v1(p_occasion,v_actor)));
  END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.group.save','profile',jsonb_build_array(jsonb_build_object(
      'entityType','user_group','entityId',v_id,
      'operation',CASE WHEN v_current IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(p_group->>'title',240),'changedFields',jsonb_build_array('aggregate'))),
    '{}',v_private_impacts,'[]',jsonb_build_object('version',v_version,'group',v_entity),
    '{}','[]','user',NULL,v_actor_replacements);
END; $function$
;
REVOKE ALL ON FUNCTION public.save_user_group_client_sync_v1(bigint,uuid,bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_user_group_client_sync_v1(bigint,uuid,bigint,jsonb) TO authenticated;
