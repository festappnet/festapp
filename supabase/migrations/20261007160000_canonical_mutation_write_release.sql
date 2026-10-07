-- Additive release guard; activation is a separately approved operation.
-- Operational release policy, writable only by its SQL owner. No client DML.
CREATE TABLE public.canonical_mutation_write_release_gate(
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 paused boolean NOT NULL,
 minimum_build bigint NOT NULL CHECK(minimum_build BETWEEN 1 AND 999999999),
 organization_ids bigint[] NOT NULL CHECK(cardinality(organization_ids)>0
  AND array_position(organization_ids,NULL) IS NULL AND 0<ALL(organization_ids))
);
REVOKE ALL ON TABLE public.canonical_mutation_write_release_gate FROM PUBLIC,anon,authenticated,service_role;

-- Header metadata never grants domain permissions. Absent policy preserves
-- additive compatibility until the explicitly authorized shared write fence.
CREATE OR REPLACE FUNCTION public.assert_canonical_mutation_write_release_internal_v1(p_occasion bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE gate public.canonical_mutation_write_release_gate%ROWTYPE;
 client_build text; headers jsonb; organization_id bigint;
BEGIN
 SELECT * INTO gate FROM public.canonical_mutation_write_release_gate WHERE singleton FOR SHARE;
 IF NOT FOUND THEN RETURN; END IF;
 -- Preserve existing SQL operator/cron and signed service lanes. This grants no
 -- actor permission: the typed command still performs its own auth checks.
 IF (nullif(current_setting('request.method',true),'') IS NULL
 AND session_user IN ('postgres','supabase_admin')) OR auth.role()='service_role' THEN RETURN; END IF;
 BEGIN
  headers:=COALESCE(nullif(current_setting('request.headers',true),''),'{}')::jsonb;
  client_build:=substring(headers->>'x-client-info' FROM '^festapp/[0-9]+\.[0-9]+\.[0-9]+\+([0-9]{1,9})/(?:web|android|ios|macos|windows|linux|fuchsia|js|service)$');
 EXCEPTION WHEN OTHERS THEN
  RAISE insufficient_privilege USING MESSAGE='canonical editor requires valid release metadata';
 END;
 SELECT organization INTO organization_id FROM public.occasions WHERE id=p_occasion;
 IF gate.paused OR client_build IS NULL OR client_build::bigint<gate.minimum_build
 OR organization_id IS NULL OR NOT organization_id=ANY(gate.organization_ids) THEN
  RAISE insufficient_privilege USING MESSAGE='canonical editor requires an enabled current release';
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.assert_canonical_mutation_write_release_internal_v1(bigint)
 FROM PUBLIC,anon,authenticated,service_role;

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
 PERFORM public.assert_canonical_mutation_write_release_internal_v1(p_occasion);
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

CREATE OR REPLACE FUNCTION public.delete_user_group_client_sync_v1(p_occasion bigint, p_group_id bigint, p_command_id uuid, p_expected_version bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_version bigint; v_begin jsonb; v_hash text;
  v_entity jsonb; v_users uuid[]; v_place bigint; v_private_place boolean;
  v_private_impacts jsonb; v_actor_replacements jsonb:='[]'::jsonb;
BEGIN
 PERFORM public.assert_canonical_mutation_write_release_internal_v1(p_occasion);
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'groupId',p_group_id,'expectedVersion',p_expected_version)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.group.delete',
    p_occasion,v_actor,v_hash);
  PERFORM public.lock_group_occasion_internal_v1(p_occasion);
  IF NOT public.get_is_editor_on_occasion(p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM 1 FROM public.user_group_info g WHERE g.id=p_group_id
    AND g.occasion=p_occasion FOR UPDATE;
  IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'unchanged',200,jsonb_build_object('version',0,'group',NULL)); END IF;
  SELECT public.get_user_group_command_data_v1(g.id),g.place,
    COALESCE(p.is_hidden AND p.type='group',false)
    INTO v_entity,v_place,v_private_place
  FROM public.user_group_info g LEFT JOIN public.places p ON p.id=g.place
  WHERE g.id=p_group_id;
  SELECT COALESCE(array_agg(ug."user" ORDER BY ug."user"),'{}'::uuid[])
    INTO v_users FROM public.user_groups ug WHERE ug."group"=p_group_id;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('user_group','occasion',p_occasion,p_group_id::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='user_group' AND scope_type='occasion'
    AND scope_id=p_occasion AND aggregate_id=p_group_id::text FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
      jsonb_build_object('version',v_version,'group',v_entity)); END IF;
  IF v_private_place THEN PERFORM public.assert_group_place_owner_internal_v1(p_occasion,p_group_id,v_place,true); END IF;
  DELETE FROM public.user_groups WHERE "group"=p_group_id;
  DELETE FROM public.user_group_info WHERE id=p_group_id;
  IF v_private_place THEN
    DELETE FROM public.places WHERE id=v_place;
    DELETE FROM public.client_aggregate_versions WHERE aggregate_type='place'
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_place::text;
  END IF;
  DELETE FROM public.client_aggregate_versions WHERE aggregate_type='user_group'
    AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_group_id::text;
  v_private_impacts:=public.group_profile_impacts_internal_v1(p_occasion,v_users);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_private_impacts) x WHERE x->>'userId'=v_actor::text) THEN v_actor_replacements:=jsonb_build_array(
    jsonb_build_object('component','private_profile','userId',v_actor,
      'payload',public.get_private_profile_payload_v1(p_occasion,v_actor))); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.group.delete','profile',jsonb_build_array(jsonb_build_object(
      'entityType','user_group','entityId',p_group_id,'operation','delete',
      'safeLabel',left(v_entity->>'title',240),'changedFields',jsonb_build_array('aggregate'))),
    '{}',v_private_impacts,'[]',jsonb_build_object('version',v_version,'group',NULL),
    '{}','[]','user',NULL,v_actor_replacements);
END; $function$
;
REVOKE ALL ON FUNCTION public.delete_user_group_client_sync_v1(bigint,bigint,uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_user_group_client_sync_v1(bigint,bigint,uuid,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.replace_group_assignments_client_sync_v1(p_occasion bigint, p_command_id uuid, p_assignments jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_unit bigint;
  v_before jsonb; v_after jsonb; v_changed bigint[];
  v_group_ids bigint[]; v_impacted_users uuid[]; v_private_impacts jsonb;
  v_actor_replacements jsonb:='[]'::jsonb;
BEGIN
 PERFORM public.assert_canonical_mutation_write_release_internal_v1(p_occasion);
  SELECT o.unit INTO v_unit FROM public.occasions o WHERE o.id=p_occasion;
  IF v_actor IS NULL OR NOT (public.get_is_editor_on_occasion(p_occasion)
    OR public.get_is_manager_on_occasion(p_occasion)
    OR public.get_is_admin_on_occasion(p_occasion)
    OR public.get_is_editor_on_unit(v_unit)) THEN
    RAISE insufficient_privilege USING MESSAGE='group import permission required'; END IF;
  IF p_assignments IS NULL OR jsonb_typeof(p_assignments)<>'array'
    OR jsonb_array_length(p_assignments)>10000
    OR octet_length(p_assignments::text)>2097152 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid group assignments'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'assignments',p_assignments)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.groups.import',
    p_occasion,v_actor,v_hash);
  PERFORM public.lock_group_occasion_internal_v1(p_occasion);
  IF NOT (public.get_is_editor_on_occasion(p_occasion) OR public.get_is_manager_on_occasion(p_occasion) OR public.get_is_admin_on_occasion(p_occasion) OR public.get_is_editor_on_unit(v_unit)) THEN RAISE insufficient_privilege USING MESSAGE='group import permission required'; END IF;
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(p_occasion);
  PERFORM 1 FROM public.user_group_info g WHERE g.occasion=p_occasion
    AND g.type IS NULL ORDER BY g.id FOR UPDATE;
  SELECT COALESCE(array_agg(DISTINCT ug."group"),'{}'::bigint[])
    INTO v_group_ids FROM public.user_groups ug JOIN public.user_group_info g
      ON g.id=ug."group" JOIN jsonb_to_recordset(p_assignments)
      x(user_id uuid,group_title text) ON x.user_id=ug."user"
    WHERE g.occasion=p_occasion AND g.type IS NULL;
  SELECT COALESCE(array_agg(DISTINCT members."user"),'{}'::uuid[])
    INTO v_impacted_users FROM public.user_groups members
    WHERE members."group"=ANY(v_group_ids);
  SELECT COALESCE(jsonb_object_agg(g.id,public.get_user_group_command_data_v1(g.id)-'aggregate_version'),'{}') INTO v_before FROM public.user_group_info g WHERE g.occasion=p_occasion AND g.type IS NULL;
  PERFORM public.import_user_group_assignments_internal_v1(
    p_occasion,p_assignments);
  SELECT COALESCE(jsonb_object_agg(g.id,public.get_user_group_command_data_v1(g.id)-'aggregate_version'),'{}') INTO v_after FROM public.user_group_info g WHERE g.occasion=p_occasion AND g.type IS NULL;
  IF v_before=v_after THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,jsonb_build_object('assignments',jsonb_array_length(p_assignments))); END IF;
  SELECT ARRAY(SELECT key::bigint FROM jsonb_each(v_after) WHERE value IS DISTINCT FROM v_before->key ORDER BY key::bigint) INTO v_changed;
  SELECT ARRAY(SELECT DISTINCT id FROM unnest(v_group_ids||COALESCE((
    SELECT array_agg(ug."group") FROM public.user_groups ug
    JOIN public.user_group_info g ON g.id=ug."group"
    JOIN jsonb_to_recordset(p_assignments) x(user_id uuid,group_title text)
      ON x.user_id=ug."user" WHERE g.occasion=p_occasion AND g.type IS NULL),
    '{}'::bigint[])) id ORDER BY id) INTO v_group_ids;
  SELECT ARRAY(SELECT DISTINCT id FROM unnest(v_impacted_users||COALESCE((
    SELECT array_agg(members."user") FROM public.user_groups members
    WHERE members."group"=ANY(v_group_ids)),'{}'::uuid[])) id ORDER BY id)
    INTO v_impacted_users;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  SELECT 'user_group','occasion',p_occasion,id::text,1 FROM unnest(v_changed) id
  ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,
      updated_at=clock_timestamp();
  v_private_impacts:=public.group_profile_impacts_internal_v1(p_occasion,v_impacted_users);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_private_impacts) x WHERE x->>'userId'=v_actor::text) THEN v_actor_replacements:=jsonb_build_array(
    jsonb_build_object('component','private_profile','userId',v_actor,
      'payload',public.get_private_profile_payload_v1(p_occasion,v_actor))); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.groups.import','profile',jsonb_build_array(jsonb_build_object(
      'entityType','user_group_membership','entityId',NULL,'operation','import',
      'safeLabel','Group assignment import','changedFields',jsonb_build_array('memberships'))),
    '{}',v_private_impacts,'[]',jsonb_build_object(
      'assignments',jsonb_array_length(p_assignments)),
    '{}','[]','user',NULL,v_actor_replacements);
END; $function$
;
REVOKE ALL ON FUNCTION public.replace_group_assignments_client_sync_v1(bigint,uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.replace_group_assignments_client_sync_v1(bigint,uuid,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.lock_activity_aggregate_internal_v1(p_occasion bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v bigint;
BEGIN
 PERFORM public.lock_group_occasion_internal_v1(p_occasion);
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version) VALUES('activities','occasion',p_occasion,p_occasion::text,0) ON CONFLICT DO NOTHING;
 SELECT version INTO v FROM public.client_aggregate_versions WHERE aggregate_type='activities' AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_occasion::text FOR UPDATE;
 RETURN v;
END $$;
CREATE OR REPLACE FUNCTION public.lock_activity_editor_internal_v1(p_occasion bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v bigint;
BEGIN
 v:=public.lock_activity_aggregate_internal_v1(p_occasion);
 IF auth.uid() IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
 RETURN v;
END $$;
REVOKE ALL ON FUNCTION public.lock_activity_aggregate_internal_v1(bigint) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.retain_activity_history_internal_v1(p_occasion bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE protected bigint[]; depth int;
BEGIN
 WITH RECURSIVE roots AS (
 SELECT id,parent_history_id FROM public.activity_history WHERE occasion_id=p_occasion AND history_type='AUTOSAVE'
 UNION SELECT id,parent_history_id FROM (SELECT id,parent_history_id FROM public.activity_history WHERE occasion_id=p_occasion AND history_type='PUBLISH' ORDER BY id DESC LIMIT 1) latest
 ), chain AS (
 SELECT id,parent_history_id,ARRAY[id] path,1 depth FROM roots
 UNION ALL SELECT h.id,h.parent_history_id,c.path||h.id,c.depth+1 FROM chain c JOIN public.activity_history h ON h.id=c.parent_history_id AND h.occasion_id=p_occasion WHERE NOT h.id=ANY(c.path) AND c.depth<10000
 ) SELECT array_agg(DISTINCT id),max(chain.depth) INTO protected,depth FROM chain;
 -- Fail closed on unbounded history: do not silently cut a protected chain.
 IF depth>=10000 THEN RETURN; END IF;
 DELETE FROM public.activity_history WHERE occasion_id=p_occasion AND created_at<now()-interval '30 days' AND NOT id=ANY(COALESCE(protected,'{}'::bigint[]));
END $$;
CREATE OR REPLACE FUNCTION public.save_activity_draft_client_sync_v1(p_occasion bigint,p_command_id uuid,p_expected_version bigint,p_history_data jsonb,p_parent_history_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE actor uuid:=auth.uid(); b jsonb; v bigint; latest bigint; draft public.activity_history%rowtype; graph jsonb; history jsonb; result jsonb; hid bigint;
BEGIN
 PERFORM public.assert_canonical_mutation_write_release_internal_v1(p_occasion);
 IF actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
 IF p_history_data IS NULL OR jsonb_typeof(p_history_data)<>'object' OR octet_length(p_history_data::text)>2097152 THEN RAISE invalid_parameter_value USING MESSAGE='invalid draft'; END IF;
 b:=public.begin_client_mutation_v1(p_command_id,'activities.draft.save',p_occasion,actor,encode(extensions.digest(jsonb_build_object('occasion',p_occasion,'expectedVersion',p_expected_version,'history',p_history_data,'parent',p_parent_history_id)::text,'sha256'),'hex'));
 v:=public.lock_activity_editor_internal_v1(p_occasion);
 IF b->>'disposition'='replay' THEN RETURN b->'response'; END IF;
 SELECT id INTO latest FROM public.activity_history WHERE occasion_id=p_occasion AND history_type='PUBLISH' ORDER BY id DESC LIMIT 1;
 IF p_expected_version IS DISTINCT FROM v OR p_parent_history_id IS DISTINCT FROM latest THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('version',v,'latestPublishId',latest)); END IF;
 graph:=public.activity_history_graph_internal_v1(p_occasion,p_history_data); history:=public.activity_graph_history_internal_v1(graph);
 SELECT * INTO draft FROM public.activity_history WHERE occasion_id=p_occasion AND user_id=actor AND history_type='AUTOSAVE' ORDER BY id DESC LIMIT 1;
 result:=jsonb_build_object('version',v,'latestPublishId',latest,'draftId',draft.id,'draftParentHistoryId',latest);
 IF draft.id IS NOT NULL AND draft.activities_data=history AND draft.parent_history_id IS NOT DISTINCT FROM latest THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,result); END IF;
 hid:=public.write_activity_history_internal_v1(p_occasion,actor,history,'AUTOSAVE',latest,NULL);
 PERFORM public.retain_activity_history_internal_v1(p_occasion);
 RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,'activities.draft.save','activities',jsonb_build_array(jsonb_build_object('entityType','activity_draft','entityId',hid,'operation',CASE WHEN draft.id IS NULL THEN 'insert' ELSE 'update' END,'changedFields',jsonb_build_array('draft'))),'{}','[]','[]',result||jsonb_build_object('draftId',hid));
END $$;
CREATE OR REPLACE FUNCTION public.discard_activity_draft_client_sync_v1(p_occasion bigint,p_command_id uuid,p_expected_draft_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE actor uuid:=auth.uid(); b jsonb; v bigint; draft bigint;
BEGIN
 PERFORM public.assert_canonical_mutation_write_release_internal_v1(p_occasion);
 IF actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
 b:=public.begin_client_mutation_v1(p_command_id,'activities.draft.discard',p_occasion,actor,encode(extensions.digest(jsonb_build_object('occasion',p_occasion,'draft',p_expected_draft_id)::text,'sha256'),'hex'));
 v:=public.lock_activity_editor_internal_v1(p_occasion);
 IF b->>'disposition'='replay' THEN RETURN b->'response'; END IF;
 SELECT id INTO draft FROM public.activity_history WHERE occasion_id=p_occasion AND user_id=actor AND history_type='AUTOSAVE' ORDER BY id DESC LIMIT 1;
 IF draft IS DISTINCT FROM p_expected_draft_id THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('version',v,'draftId',draft)); END IF;
 IF draft IS NULL THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,jsonb_build_object('version',v,'draftId',NULL)); END IF;
 PERFORM public.clear_activity_draft_internal_v1(p_occasion,actor,NULL,false);
 RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,'activities.draft.discard','activities',jsonb_build_array(jsonb_build_object('entityType','activity_draft','entityId',draft,'operation','delete','changedFields',jsonb_build_array('draft'))),'{}','[]','[]',jsonb_build_object('version',v,'draftId',NULL));
END $$;
CREATE OR REPLACE FUNCTION public.publish_activities_client_sync_v1(p_occasion bigint,p_command_id uuid,p_expected_version bigint,p_activities_data jsonb,p_history_data jsonb,p_parent_history_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE actor uuid:=auth.uid(); b jsonb; v bigint; latest bigint; graph jsonb; history jsonb; old_graph jsonb; previous_history jsonb; hid bigint; live_changed boolean; deleted int; impacts jsonb; replacements jsonb:='[]'; users uuid[];
BEGIN
 PERFORM public.assert_canonical_mutation_write_release_internal_v1(p_occasion);
 IF actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
 IF p_activities_data IS NULL OR jsonb_typeof(p_activities_data)<>'array' OR p_history_data IS NULL OR jsonb_typeof(p_history_data)<>'object' OR octet_length(p_activities_data::text)>2097152 OR octet_length(p_history_data::text)>2097152 THEN RAISE invalid_parameter_value USING MESSAGE='invalid activities aggregate'; END IF;
 b:=public.begin_client_mutation_v1(p_command_id,'activities.publish',p_occasion,actor,encode(extensions.digest(jsonb_build_object('occasion',p_occasion,'expectedVersion',p_expected_version,'activities',p_activities_data,'history',p_history_data,'parentHistoryId',p_parent_history_id)::text,'sha256'),'hex'));
 v:=public.lock_activity_editor_internal_v1(p_occasion);
 IF b->>'disposition'='replay' THEN RETURN b->'response'; END IF;
 SELECT id,activities_data INTO latest,previous_history FROM public.activity_history WHERE occasion_id=p_occasion AND history_type='PUBLISH' ORDER BY id DESC LIMIT 1;
 IF p_expected_version IS DISTINCT FROM v OR p_parent_history_id IS DISTINCT FROM latest THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('version',v,'latestPublishId',latest,'historyId',latest)); END IF;
 graph:=public.normalize_activity_graph_internal_v1(p_occasion,p_activities_data,true);
 IF graph IS DISTINCT FROM public.activity_history_graph_internal_v1(p_occasion,p_history_data) THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',400,jsonb_build_object('version',v,'latestPublishId',latest,'reason','graph_history_mismatch')); END IF;
 history:=public.activity_graph_history_internal_v1(graph); old_graph:=public.current_activity_graph_internal_v1(p_occasion);
 live_changed:=graph IS DISTINCT FROM old_graph OR latest IS NULL;
 IF NOT live_changed AND public.activity_history_graph_internal_v1(p_occasion,previous_history)=graph THEN
  deleted:=public.clear_activity_draft_internal_v1(p_occasion,actor,latest,true);
  IF deleted=0 THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,jsonb_build_object('version',v,'historyId',latest,'latestPublishId',latest,'draftId',NULL)); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,'activities.publish','activities',jsonb_build_array(jsonb_build_object('entityType','activity_draft','entityId',NULL,'operation','delete','changedFields',jsonb_build_array('draft'))),'{}','[]','[]',jsonb_build_object('version',v,'historyId',latest,'latestPublishId',latest,'draftId',NULL));
 END IF;
 SELECT ARRAY(SELECT DISTINCT (x->>'user')::uuid FROM jsonb_array_elements(old_graph||graph) a,LATERAL jsonb_array_elements(a->'assignments') x WHERE x->>'user' IS NOT NULL UNION SELECT actor) INTO users;
 PERFORM public.replace_activities_graph_internal_v1(p_occasion,graph);
 hid:=public.write_activity_history_internal_v1(p_occasion,actor,history,'PUBLISH',latest,'Published via application');
 PERFORM public.clear_activity_draft_internal_v1(p_occasion,actor,latest,true);
 UPDATE public.client_aggregate_versions SET version=version+1,updated_at=clock_timestamp() WHERE aggregate_type='activities' AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_occasion::text RETURNING version INTO v;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_activity','userId',u) ORDER BY u),'[]') INTO impacts FROM unnest(users) u JOIN public.occasion_users ou ON ou.occasion=p_occasion AND ou."user"=u;
 replacements:=jsonb_build_array(jsonb_build_object('component','private_activity','userId',actor,'payload',(public.get_my_events_and_activities(p_occasion,true)->'data')));
 PERFORM public.retain_activity_history_internal_v1(p_occasion);
 RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,'activities.publish','activities',jsonb_build_array(jsonb_build_object('entityType','activities','entityId',p_occasion,'operation','publish','changedFields',jsonb_build_array('graph','history'))),'{}',impacts,'[]',jsonb_build_object('version',v,'historyId',hid,'latestPublishId',hid,'draftId',NULL,'activities',graph),'{}','[]','user',NULL,replacements);
END $$;
REVOKE ALL ON FUNCTION public.lock_activity_editor_internal_v1(bigint),public.retain_activity_history_internal_v1(bigint) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.save_activity_draft_client_sync_v1(bigint,uuid,bigint,jsonb,bigint),public.discard_activity_draft_client_sync_v1(bigint,uuid,bigint),public.publish_activities_client_sync_v1(bigint,uuid,bigint,jsonb,jsonb,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_activity_draft_client_sync_v1(bigint,uuid,bigint,jsonb,bigint),public.discard_activity_draft_client_sync_v1(bigint,uuid,bigint),public.publish_activities_client_sync_v1(bigint,uuid,bigint,jsonb,jsonb,bigint) TO authenticated;

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

-- Existing map owner remains the only DML implementation.
CREATE OR REPLACE FUNCTION public.save_place_client_sync_v1(
 p_occasion bigint,p_command_id uuid,p_expected_version bigint,p_place jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.assert_canonical_mutation_write_release_internal_v1(p_occasion);
 RETURN public.mutate_map_entity_internal_v1('place','save',p_occasion,p_command_id,p_expected_version,NULL,p_place);
END $$;
CREATE OR REPLACE FUNCTION public.delete_place_client_sync_v1(
 p_occasion bigint,p_place_id bigint,p_command_id uuid,p_expected_version bigint
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.assert_canonical_mutation_write_release_internal_v1(p_occasion);
 RETURN public.mutate_map_entity_internal_v1('place','delete',p_occasion,p_command_id,p_expected_version,p_place_id,NULL);
END $$;
