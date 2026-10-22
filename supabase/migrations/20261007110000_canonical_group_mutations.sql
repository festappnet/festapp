-- Forward additive group correction. Legacy public boundaries remain gated by G3.
-- Group domain lock/impact helpers. No client EXECUTE.
CREATE OR REPLACE FUNCTION public.lock_group_occasion_internal_v1(p_occasion bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
 PERFORM pg_catalog.pg_advisory_xact_lock(p_occasion);
 PERFORM 1 FROM public.user_group_info WHERE occasion=p_occasion ORDER BY id FOR UPDATE;
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
 SELECT 'user_group','occasion',p_occasion,id::text,0 FROM public.user_group_info WHERE occasion=p_occasion ORDER BY id ON CONFLICT DO NOTHING;
 PERFORM 1 FROM public.client_aggregate_versions WHERE aggregate_type='user_group' AND scope_type='occasion' AND scope_id=p_occasion ORDER BY aggregate_id::bigint FOR UPDATE;
END $$;
CREATE OR REPLACE FUNCTION public.group_profile_impacts_internal_v1(p_occasion bigint,p_users uuid[])
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
 SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_profile','userId',u.id) ORDER BY u.id),'[]'::jsonb)
 FROM (SELECT unnest(p_users) id UNION SELECT uc."user" FROM public.user_companions uc WHERE uc.occasion=p_occasion AND uc.companion=ANY(p_users)) u
 JOIN public.occasion_users ou ON ou.occasion=p_occasion AND ou."user"=u.id;
$$;
CREATE OR REPLACE FUNCTION public.assert_group_place_owner_internal_v1(p_occasion bigint,p_group bigint,p_place bigint,p_removing boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
 PERFORM 1 FROM public.places p WHERE p.id=p_place AND p.occasion=p_occasion AND p.type='group' AND p.is_hidden FOR UPDATE;
 IF NOT FOUND OR (SELECT count(*) FROM public.user_group_info WHERE place=p_place)<>1 OR NOT EXISTS(SELECT 1 FROM public.user_group_info WHERE id=p_group AND occasion=p_occasion AND place=p_place)
 OR EXISTS(SELECT 1 FROM public.activity_assignment_places WHERE place_id=p_place)
 OR EXISTS(SELECT 1 FROM public.activity_places WHERE place_id=p_place)
 OR EXISTS(SELECT 1 FROM public.events WHERE place=p_place)
 OR EXISTS(SELECT 1 FROM public.resources WHERE place=p_place)
 OR (p_removing AND (EXISTS(SELECT 1 FROM public.cleaning_reports WHERE place=p_place) OR EXISTS(SELECT 1 FROM public.cleaning_public_state WHERE place=p_place))) THEN
 RAISE invalid_parameter_value USING MESSAGE='private group place has ambiguous or external ownership'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.lock_group_occasion_internal_v1(bigint), public.group_profile_impacts_internal_v1(bigint,uuid[]), public.assert_group_place_owner_internal_v1(bigint,bigint,bigint,boolean) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_user_group_command_data_v1(p_group bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO public, extensions
AS $function$
  SELECT jsonb_build_object('id',g.id,'title',g.title,
    'description',g.description,'type',g.type,'data',g.data,'place',g.place,
    'is_admin',COALESCE((SELECT is_admin FROM public.user_groups WHERE "group"=g.id AND "user"=auth.uid()),false),
    'aggregate_version',COALESCE((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='user_group' AND scope_type='occasion' AND scope_id=g.occasion AND aggregate_id=g.id::text),0),
    'placeData',(SELECT to_jsonb(p)||jsonb_build_object('aggregate_version',COALESCE((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='place' AND scope_type='occasion' AND scope_id=g.occasion AND aggregate_id=p.id::text),0)) FROM public.places p WHERE p.id=g.place),
    'participants',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'userId',ug."user",'isAdmin',ug.is_admin,'is_admin',ug.is_admin,
      'user_info',jsonb_build_object('id',ui.id,'name',ui.name,'surname',ui.surname))
      ORDER BY ug."user") FROM public.user_groups ug JOIN public.user_info ui
      ON ui.id=ug."user" WHERE ug."group"=g.id),'[]'::jsonb))
  FROM public.user_group_info g WHERE g.id=p_group;
$function$
;
REVOKE ALL ON FUNCTION public.get_user_group_command_data_v1(bigint) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.get_user_group_editor_bundle_v1(p_occasion bigint,p_group_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT (public.get_is_editor_view_on_occasion(p_occasion) OR EXISTS(SELECT 1 FROM public.user_groups ug JOIN public.user_group_info g ON g.id=ug."group" WHERE g.id=p_group_id AND g.occasion=p_occasion AND ug."user"=auth.uid() AND ug.is_admin)) THEN
 RAISE insufficient_privilege USING MESSAGE='group editor required'; END IF;
 RETURN (SELECT public.get_user_group_command_data_v1(id) FROM public.user_group_info WHERE id=p_group_id AND occasion=p_occasion);
END $$;
REVOKE ALL ON FUNCTION public.get_user_group_editor_bundle_v1(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_user_group_editor_bundle_v1(bigint,bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_user_group_info_with_users(p_group_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE
    v_occasion_id bigint;
    v_is_member boolean;
    v_is_editor_view boolean;
    v_current_user_is_admin boolean;
    result_json jsonb;
BEGIN
    -- Check if the group exists and get its occasion for permission checks.
    SELECT occasion INTO v_occasion_id FROM public.user_group_info WHERE id = p_group_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'USER_GROUP_NOT_FOUND';
    END IF;

    -- Authorization Check: User must be a member or have editor view permissions on the occasion.
    SELECT EXISTS (SELECT 1 FROM public.user_groups WHERE "group" = p_group_id AND "user" = auth.uid()) INTO v_is_member;
    v_is_editor_view := get_is_editor_view_on_occasion(v_occasion_id);

    IF NOT v_is_member AND NOT v_is_editor_view THEN
        RAISE EXCEPTION 'NOT_AUTHORIZED';
    END IF;

    -- Get the current user's admin status for this specific group.
    SELECT is_admin INTO v_current_user_is_admin FROM public.user_groups WHERE "group" = p_group_id AND "user" = auth.uid();

    -- If authorized, build the final JSON object.
    SELECT
        jsonb_build_object(
            'id', ugi.id,
            'title', ugi.title,
            'description', ugi.description,
            'type', ugi.type,
            'data', ugi.data,
            'place', ugi.place, -- This is placeId
            'is_admin', COALESCE(v_current_user_is_admin, false),
            'places', (SELECT row_to_json(p)::jsonb||jsonb_build_object('aggregate_version',COALESCE((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='place' AND scope_type='occasion' AND scope_id=v_occasion_id AND aggregate_id=p.id::text),0)) FROM public.places p WHERE p.id = ugi.place),
            'user_groups', (
                SELECT COALESCE(jsonb_agg(
                    jsonb_build_object(
                        'is_admin', ug.is_admin,
                        'user_info', row_to_json(p_ui)::jsonb
                    )
                ), '[]'::jsonb)
                FROM public.user_groups ug
                JOIN public.user_info p_ui ON ug."user" = p_ui.id
                WHERE ug."group" = ugi.id
            )
        )
    INTO result_json
    FROM public.user_group_info ugi
    WHERE ugi.id = p_group_id;

    RETURN result_json;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_private_profile_payload_v1(p_occasion bigint, p_user uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  SELECT jsonb_build_object(
    'user',(SELECT jsonb_build_object('id',u.id,'email',u.email_readonly,
      'name',u.name,'surname',u.surname,'sex',u.sex,'phone',u.phone,
      'birthDate',u.birth_date,'data',u.data) FROM public.user_info u
      WHERE u.id=p_user),
    'occasion',(SELECT jsonb_build_object('role',ou.role,'services',ou.services,
      'data',ou.data,'isEditor',ou.is_editor,
      'isEditorView',ou.is_editor_view,
      'isEditorOrder',ou.is_editor_order,
      'isEditorOrderView',ou.is_editor_order_view,
      'isApproved',ou.is_approved,'isApprover',ou.is_approver,
      'isManager',ou.is_manager,
      'isCleaningBlocked',ou.is_cleaning_blocked,
      'isCleaningCrew',ou.is_cleaning_crew,
      'isReceptionist',ou.is_receptionist) FROM public.occasion_users ou
      WHERE ou.occasion=p_occasion AND ou."user"=p_user),
    'companions',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',ui.id,'name',ui.name,'surname',COALESCE(ui.surname,''),
      'group_title',COALESCE(groups.titles,''),'origin',uc.origin,
      'can_owner_delete',uc.origin='self_created',
      'services',COALESCE(companion_membership.services,'{}'::jsonb),
      'event_ids',COALESCE((SELECT jsonb_agg(eu.event ORDER BY eu.event)
        FROM public.event_users eu JOIN public.events e ON e.id=eu.event
        WHERE eu."user"=ui.id AND e.occasion=p_occasion),'[]'::jsonb))
      ORDER BY ui.name,ui.surname,ui.id)
      FROM public.user_companions uc
      JOIN public.user_info ui ON ui.id=uc.companion
      JOIN public.occasion_users companion_membership
        ON companion_membership.occasion=uc.occasion
       AND companion_membership."user"=uc.companion
      LEFT JOIN LATERAL (SELECT string_agg(ugi.title,', ' ORDER BY ugi.title) titles
        FROM public.user_groups ug JOIN public.user_group_info ugi ON ugi.id=ug."group"
        WHERE ug."user"=uc.companion AND ugi.occasion=p_occasion
          AND ugi.type IS NULL) groups ON true
      WHERE uc.occasion=p_occasion AND uc."user"=p_user),'[]'::jsonb),
    'groups',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',g.id,'title',g.title,'description',g.description,'type',g.type,
      'data',g.data,'place',g.place,'isAdmin',mine.is_admin,
      'participants',COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'userId',members."user",'isAdmin',members.is_admin,
        'name',ui.name,'surname',ui.surname) ORDER BY members."user")
        FROM public.user_groups members JOIN public.user_info ui
          ON ui.id=members."user" WHERE members."group"=g.id),'[]'::jsonb),
      'placeData',(SELECT to_jsonb(p)||jsonb_build_object('aggregate_version',COALESCE((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='place' AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p.id::text),0)) FROM public.places p WHERE p.id=g.place))
      ORDER BY g.id) FROM public.user_groups mine JOIN public.user_group_info g
        ON g.id=mine."group" WHERE mine."user"=p_user
        AND g.occasion=p_occasion),'[]'::jsonb));
$function$
;

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

CREATE OR REPLACE FUNCTION public.mutate_map_entity_internal_v1(p_kind text, p_action text, p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_entity_id bigint, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO public, extensions
AS $function$
DECLARE
  v_actor uuid:=auth.uid(); v_id bigint:=p_entity_id; v_version bigint;
  v_begin jsonb; v_hash text; v_current jsonb; v_requested jsonb;
  v_entity jsonb; v_commit jsonb; v_public jsonb; v_response jsonb;
  v_is_publishable boolean; v_old_hidden boolean; v_new_hidden boolean;
  v_impacts jsonb:='[]'; v_replacements jsonb:='[]';
  v_affects_public boolean:=false; v_label text; v_entity_key text;
BEGIN
  IF p_kind NOT IN ('place','place_type','path') OR p_action NOT IN ('save','delete')
    OR v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required';
  END IF;
  SELECT NOT o.is_hidden INTO v_is_publishable FROM public.occasions o
    WHERE o.id=p_occasion;
  IF v_is_publishable IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='occasion not found';
  END IF;

  IF p_action='save' THEN
    IF p_payload IS NULL OR jsonb_typeof(p_payload)<>'object'
      OR octet_length(p_payload::text)>262144 THEN
      RAISE invalid_parameter_value USING MESSAGE='invalid map aggregate';
    END IF;
    IF p_kind='place' THEN
      IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_payload) key WHERE key NOT IN
          ('id','title','description','type','coordinates','isHidden','order','icon'))
        OR NOT (p_payload ?& ARRAY['title','coordinates','isHidden'])
        OR length(p_payload->>'title') NOT BETWEEN 1 AND 500
        OR jsonb_typeof(p_payload->'coordinates')<>'object'
        OR jsonb_typeof(p_payload#>'{coordinates,latLng}')<>'object'
        OR jsonb_typeof(p_payload#>'{coordinates,latLng,lat}')<>'number'
        OR jsonb_typeof(p_payload#>'{coordinates,latLng,lng}')<>'number'
        OR (p_payload#>>'{coordinates,latLng,lat}')::double precision NOT BETWEEN -90 AND 90
        OR (p_payload#>>'{coordinates,latLng,lng}')::double precision NOT BETWEEN -180 AND 180 THEN
        RAISE invalid_parameter_value USING MESSAGE='invalid place aggregate';
      END IF;
      v_id:=(p_payload->>'id')::bigint;
      v_requested:=jsonb_build_object('id',v_id,'title',p_payload->>'title',
        'description',p_payload->>'description','type',p_payload->>'type',
        'coordinates',p_payload->'coordinates','isHidden',(p_payload->>'isHidden')::boolean,
        'order',(p_payload->>'order')::bigint,'icon',(p_payload->>'icon')::bigint);
      v_entity_key:='place';
    ELSIF p_kind='place_type' THEN
      IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_payload) key WHERE key NOT IN
          ('id','code','title','icon','order','isHidden','isDefault'))
        OR NOT (p_payload ?& ARRAY['code','title','isHidden','isDefault'])
        OR length(p_payload->>'code') NOT BETWEEN 1 AND 100
        OR (p_payload->>'code') !~ '^[A-Za-z0-9_-]+$'
        OR length(p_payload->>'title') NOT BETWEEN 1 AND 500 THEN
        RAISE invalid_parameter_value USING MESSAGE='invalid place type aggregate';
      END IF;
      v_id:=(p_payload->>'id')::bigint;
      v_requested:=jsonb_build_object('id',v_id,'code',p_payload->>'code',
        'title',p_payload->>'title','icon',(p_payload->>'icon')::bigint,
        'order',(p_payload->>'order')::bigint,
        'isHidden',(p_payload->>'isHidden')::boolean,
        'isDefault',(p_payload->>'isDefault')::boolean);
      v_entity_key:='placeType';
    ELSE
      IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_payload) key WHERE key NOT IN
          ('id','title','pathData','data','icon','isHidden','order'))
        OR NOT (p_payload ?& ARRAY['title','isHidden'])
        OR length(p_payload->>'title') NOT BETWEEN 1 AND 500
        OR (p_payload->'pathData' IS NOT NULL
          AND jsonb_typeof(p_payload->'pathData')<>'array')
        OR COALESCE(jsonb_array_length(p_payload->'pathData'),0)>500 THEN
        RAISE invalid_parameter_value USING MESSAGE='invalid path aggregate';
      END IF;
      v_id:=(p_payload->>'id')::bigint;
      v_requested:=jsonb_build_object('id',v_id,'title',p_payload->>'title',
        'pathData',p_payload->'pathData','data',p_payload->'data',
        'icon',(p_payload->>'icon')::bigint,
        'isHidden',(p_payload->>'isHidden')::boolean,
        'order',(p_payload->>'order')::bigint);
      v_entity_key:='path';
    END IF;
  ELSE
    IF v_id IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='entity id required'; END IF;
    v_entity_key:=CASE p_kind WHEN 'place_type' THEN 'placeType' ELSE p_kind END;
  END IF;

  IF (p_payload->>'icon') IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.icons i JOIN public.occasions o
      ON o.id=p_occasion AND i.organization=o.organization
    WHERE i.id=(p_payload->>'icon')::bigint AND (i.unit=o.unit OR i.unit IS NULL)
  ) THEN RAISE invalid_parameter_value USING MESSAGE='cross-scope map icon'; END IF;
  IF p_kind='path' AND p_action='save' AND EXISTS (
    SELECT 1 FROM jsonb_array_elements(COALESCE(p_payload->'pathData','[]')) segment,
      LATERAL jsonb_array_elements(segment) node
    WHERE (jsonb_typeof(node)='number' AND NOT EXISTS (
      SELECT 1 FROM public.places p WHERE p.id=(node#>>'{}')::bigint
        AND p.occasion=p_occasion))
      OR (jsonb_typeof(node)='object' AND NOT (
        jsonb_typeof(node->'lat')='number' AND jsonb_typeof(node->'lng')='number'))
      OR jsonb_typeof(node) NOT IN ('number','object')
  ) THEN RAISE invalid_parameter_value USING MESSAGE='invalid or cross-scope path node'; END IF;

  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'kind',p_kind,'action',p_action,'occasion',p_occasion,'entityId',v_id,
    'expectedVersion',p_expected_version,'payload',p_payload)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'map.'||p_kind||'.'||p_action,p_occasion,v_actor,v_hash);
  IF p_kind='place' THEN PERFORM public.lock_group_occasion_internal_v1(p_occasion); END IF;
  IF NOT public.get_is_editor_on_occasion(p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  IF p_kind='place' AND p_action='save' AND (
    ((p_payload->>'type')='group' AND (p_payload->>'isHidden')::boolean)
    OR EXISTS(SELECT 1 FROM public.places p WHERE p.id=v_id AND p.occasion=p_occasion AND p.type='group' AND p.is_hidden)) THEN
    RAISE invalid_parameter_value USING MESSAGE='private group place is owned by group save'; END IF;
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;

  IF v_id IS NOT NULL THEN
    IF p_kind='place' THEN
      PERFORM 1 FROM public.places p WHERE p.id=v_id AND p.occasion=p_occasion FOR UPDATE;
      IF FOUND THEN SELECT jsonb_build_object('id',p.id,'title',p.title,
        'description',p.description,'type',p.type,'coordinates',p.coordinates,
        'isHidden',p.is_hidden,'order',p."order",'icon',p.icon),p.is_hidden,p.title
        INTO v_current,v_old_hidden,v_label FROM public.places p WHERE p.id=v_id; END IF;
    ELSIF p_kind='place_type' THEN
      PERFORM 1 FROM public.place_types t WHERE t.id=v_id AND t.occasion=p_occasion FOR UPDATE;
      IF FOUND THEN SELECT jsonb_build_object('id',t.id,'code',t.code,'title',t.title,
        'icon',t.icon,'order',t."order",'isHidden',t.is_hidden,'isDefault',t.is_default),
        t.is_hidden,t.title INTO v_current,v_old_hidden,v_label
        FROM public.place_types t WHERE t.id=v_id; END IF;
    ELSE
      PERFORM 1 FROM public.path_groups pg WHERE pg.id=v_id AND pg.occasion=p_occasion FOR UPDATE;
      IF FOUND THEN SELECT jsonb_build_object('id',pg.id,'title',pg.title,
        'pathData',pg.path_data,'data',pg.data,'icon',pg.icon,
        'isHidden',pg.is_hidden,'order',pg."order"),pg.is_hidden,pg.title
        INTO v_current,v_old_hidden,v_label FROM public.path_groups pg WHERE pg.id=v_id; END IF;
    END IF;
    IF v_current IS NULL THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,
        CASE WHEN p_action='delete' THEN 'unchanged' ELSE 'rejected' END,
        CASE WHEN p_action='delete' THEN 200 ELSE 404 END,
        jsonb_build_object('version',0,v_entity_key,NULL));
    END IF;
    INSERT INTO public.client_aggregate_versions
      (aggregate_type,scope_type,scope_id,aggregate_id,version)
    VALUES (p_kind,'occasion',p_occasion,v_id::text,0) ON CONFLICT DO NOTHING;
    SELECT version INTO v_version FROM public.client_aggregate_versions
      WHERE aggregate_type=p_kind AND scope_type='occasion' AND scope_id=p_occasion
        AND aggregate_id=v_id::text FOR UPDATE;
    IF p_expected_version IS DISTINCT FROM v_version THEN
      IF p_kind='place' THEN SELECT to_jsonb(p)||jsonb_build_object('aggregate_version',v_version)
        INTO v_entity FROM public.places p WHERE p.id=v_id;
      ELSIF p_kind='place_type' THEN SELECT to_jsonb(t)||jsonb_build_object('aggregate_version',v_version)
        INTO v_entity FROM public.place_types t WHERE t.id=v_id;
      ELSE SELECT to_jsonb(pg)||jsonb_build_object('aggregate_version',v_version)
        INTO v_entity FROM public.path_groups pg WHERE pg.id=v_id; END IF;
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,
        'conflict',409,jsonb_build_object('version',v_version,
          v_entity_key,v_entity));
    END IF;
  ELSIF p_expected_version IS NOT NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='new map aggregate must not have expected version';
  END IF;

  IF p_action='save' AND v_current IS NOT DISTINCT FROM v_requested THEN
    IF p_kind='place' THEN SELECT to_jsonb(p)||jsonb_build_object('aggregate_version',v_version)
      INTO v_entity FROM public.places p WHERE p.id=v_id;
    ELSIF p_kind='place_type' THEN SELECT to_jsonb(t)||jsonb_build_object('aggregate_version',v_version)
      INTO v_entity FROM public.place_types t WHERE t.id=v_id;
    ELSE SELECT to_jsonb(pg)||jsonb_build_object('aggregate_version',v_version)
      INTO v_entity FROM public.path_groups pg WHERE pg.id=v_id; END IF;
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,
      'unchanged',200,jsonb_build_object('version',v_version,
        v_entity_key,v_entity));
  END IF;

  IF p_action='delete' THEN
    IF p_kind='place' AND (EXISTS (SELECT 1 FROM public.events e WHERE e.place=v_id)
      OR EXISTS(SELECT 1 FROM public.activity_assignment_places WHERE place_id=v_id)
      OR EXISTS(SELECT 1 FROM public.activity_places WHERE place_id=v_id)
      OR EXISTS (SELECT 1 FROM public.user_group_info g WHERE g.place=v_id)
      OR EXISTS (SELECT 1 FROM public.path_groups pg,
          LATERAL jsonb_array_elements(COALESCE(pg.path_data,'[]')) segment,
          LATERAL jsonb_array_elements(segment) node
        WHERE pg.occasion=p_occasion AND jsonb_typeof(node)='number'
          AND (node#>>'{}')::bigint=v_id)) THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,
        'rejected',409,jsonb_build_object('version',v_version,
          v_entity_key,NULL));
    END IF;
    IF p_kind='place_type' AND EXISTS (SELECT 1 FROM public.places p
      WHERE p.occasion=p_occasion AND p.type=v_current->>'code') THEN
      RETURN public.complete_client_mutation_outcome_v1(p_command_id,
        'rejected',409,jsonb_build_object('version',v_version,
          v_entity_key,NULL));
    END IF;
    IF p_kind='place' THEN DELETE FROM public.places WHERE id=v_id;
    ELSIF p_kind='place_type' THEN DELETE FROM public.place_types WHERE id=v_id;
    ELSE DELETE FROM public.path_groups WHERE id=v_id; END IF;
    DELETE FROM public.client_aggregate_versions WHERE aggregate_type=p_kind
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_id::text;
    v_entity:=NULL;
    v_affects_public:=NOT v_old_hidden;
  ELSE
    v_new_hidden:=(p_payload->>'isHidden')::boolean;
    v_affects_public:=NOT COALESCE(v_old_hidden,true) OR NOT v_new_hidden;
    IF p_kind='place' THEN
      IF v_id IS NULL THEN INSERT INTO public.places
        (title,description,type,coordinates,is_hidden,occasion,"order",icon)
        VALUES (p_payload->>'title',p_payload->>'description',p_payload->>'type',
          p_payload->'coordinates',v_new_hidden,p_occasion,(p_payload->>'order')::bigint,
          (p_payload->>'icon')::bigint) RETURNING id INTO v_id;
      ELSE UPDATE public.places SET title=p_payload->>'title',description=p_payload->>'description',
        type=p_payload->>'type',coordinates=p_payload->'coordinates',is_hidden=v_new_hidden,
        "order"=(p_payload->>'order')::bigint,icon=(p_payload->>'icon')::bigint,
        updated_at=clock_timestamp() WHERE id=v_id; END IF;
    ELSIF p_kind='place_type' THEN
      IF v_id IS NULL THEN INSERT INTO public.place_types
        (occasion,code,title,icon,"order",is_hidden,is_default)
        VALUES (p_occasion,p_payload->>'code',p_payload->>'title',(p_payload->>'icon')::bigint,
          (p_payload->>'order')::bigint,v_new_hidden,(p_payload->>'isDefault')::boolean)
        RETURNING id INTO v_id;
      ELSE UPDATE public.place_types SET code=p_payload->>'code',title=p_payload->>'title',
        icon=(p_payload->>'icon')::bigint,"order"=(p_payload->>'order')::bigint,
        is_hidden=v_new_hidden,is_default=(p_payload->>'isDefault')::boolean,
        updated_at=clock_timestamp() WHERE id=v_id; END IF;
    ELSE
      IF v_id IS NULL THEN INSERT INTO public.path_groups
        (title,path_data,data,icon,is_hidden,occasion,"order")
        VALUES (p_payload->>'title',p_payload->'pathData',p_payload->'data',
          (p_payload->>'icon')::bigint,v_new_hidden,p_occasion,
          (p_payload->>'order')::bigint) RETURNING id INTO v_id;
      ELSE UPDATE public.path_groups SET title=p_payload->>'title',
        path_data=p_payload->'pathData',data=p_payload->'data',
        icon=(p_payload->>'icon')::bigint,is_hidden=v_new_hidden,
        "order"=(p_payload->>'order')::bigint WHERE id=v_id; END IF;
    END IF;
    IF v_version IS NULL THEN v_version:=1;
      INSERT INTO public.client_aggregate_versions
        (aggregate_type,scope_type,scope_id,aggregate_id,version)
      VALUES (p_kind,'occasion',p_occasion,v_id::text,v_version);
    ELSE UPDATE public.client_aggregate_versions SET version=version+1,
      updated_at=clock_timestamp() WHERE aggregate_type=p_kind
      AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=v_id::text
      RETURNING version INTO v_version; END IF;
    IF p_kind='place' THEN SELECT to_jsonb(p)||jsonb_build_object('aggregate_version',v_version),p.title
      INTO v_entity,v_label FROM public.places p WHERE p.id=v_id;
    ELSIF p_kind='place_type' THEN SELECT to_jsonb(t)||jsonb_build_object('aggregate_version',v_version),t.title
      INTO v_entity,v_label FROM public.place_types t WHERE t.id=v_id;
    ELSE SELECT to_jsonb(pg)||jsonb_build_object('aggregate_version',v_version),pg.title
      INTO v_entity,v_label FROM public.path_groups pg WHERE pg.id=v_id; END IF;
  END IF;

  IF p_kind='place' THEN
    v_impacts:=public.group_profile_impacts_internal_v1(p_occasion,ARRAY(SELECT DISTINCT ug."user" FROM public.user_groups ug JOIN public.user_group_info g ON g.id=ug."group" WHERE g.occasion=p_occasion AND g.place=v_id));
    IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_impacts) x WHERE x->>'userId'=v_actor::text) THEN
      v_replacements:=jsonb_build_array(jsonb_build_object('component','private_profile','userId',v_actor,'payload',public.get_private_profile_payload_v1(p_occasion,v_actor)));
    END IF;
  END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'map.'||p_kind||'.'||p_action,'map',jsonb_build_array(jsonb_build_object(
      'entityType',p_kind,'entityId',v_id,'operation',CASE WHEN p_action='delete'
        THEN 'delete' WHEN v_current IS NULL THEN 'insert' ELSE 'update' END,
      'safeLabel',left(v_label,240),'changedFields',jsonb_build_array('aggregate'))),
    CASE WHEN v_is_publishable AND v_affects_public THEN ARRAY['map_catalog']
      ELSE '{}'::text[] END,v_impacts,'[]',
    jsonb_build_object('version',COALESCE(v_version,0),v_entity_key,v_entity),'{}','[]','user',NULL,v_replacements);
END; $function$
;
REVOKE ALL ON FUNCTION public.mutate_map_entity_internal_v1(text,text,bigint,uuid,bigint,bigint,jsonb) FROM PUBLIC,anon,authenticated;

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

CREATE OR REPLACE FUNCTION public.advance_group_profile_heads_internal_v1(p_occasion bigint,p_users uuid[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 INSERT INTO public.client_sync_private_scopes(component,occasion,user_id,source_revision)
 SELECT 'private_profile',p_occasion,(x->>'userId')::uuid,1 FROM jsonb_array_elements(public.group_profile_impacts_internal_v1(p_occasion,p_users)) x ORDER BY x->>'userId'
 ON CONFLICT(component,occasion,user_id) DO UPDATE SET source_revision=public.client_sync_private_scopes.source_revision+1,updated_at=clock_timestamp();
END $$;
REVOKE ALL ON FUNCTION public.advance_group_profile_heads_internal_v1(bigint,uuid[]) FROM PUBLIC,anon,authenticated;
-- Adjacent lifecycle owners: only group lock/version seam corrections.
CREATE OR REPLACE FUNCTION public.import_profiles_client_sync_v1(p_occasion bigint, p_command_id uuid, p_rows jsonb, p_delete_user_ids jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_unit bigint;
  v_result jsonb; v_before_users uuid[]; v_after_users uuid[]; v_current_users uuid[];
  v_event_ids bigint[]; v_group_ids bigint[]; v_private_impacts jsonb;
  v_publishable boolean; v_actor_replacements jsonb:='[]'::jsonb;
BEGIN
  SELECT o.unit,NOT o.is_hidden INTO v_unit,v_publishable
    FROM public.occasions o WHERE o.id=p_occasion;
  IF v_actor IS NULL OR NOT (public.get_is_manager_on_occasion(p_occasion)
    OR public.get_is_admin_on_occasion(p_occasion)
    OR public.get_is_editor_on_unit(v_unit)) THEN
    RAISE insufficient_privilege USING MESSAGE='profile import permission required'; END IF;
  IF p_rows IS NULL OR jsonb_typeof(p_rows)<>'array'
    OR p_delete_user_ids IS NULL OR jsonb_typeof(p_delete_user_ids)<>'array'
    OR jsonb_array_length(p_rows)>10000 OR jsonb_array_length(p_delete_user_ids)>10000
    OR octet_length(p_rows::text)+octet_length(p_delete_user_ids::text)>8388608 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid profile import'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'rows',p_rows,'deleteUserIds',p_delete_user_ids)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.users.import',
    p_occasion,v_actor,v_hash);
  PERFORM public.lock_group_occasion_internal_v1(p_occasion);
  IF NOT (public.get_is_manager_on_occasion(p_occasion) OR public.get_is_admin_on_occasion(p_occasion) OR public.get_is_editor_on_unit(v_unit)) THEN RAISE insufficient_privilege USING MESSAGE='profile import permission required'; END IF;
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(p_occasion);
  PERFORM 1 FROM public.user_group_info g WHERE g.occasion=p_occasion
    ORDER BY g.id FOR UPDATE;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
  SELECT COALESCE(array_agg(DISTINCT e.id),'{}'::bigint[]) INTO v_event_ids
    FROM public.events e LEFT JOIN public.event_users eu ON eu.event=e.id
    LEFT JOIN public.event_users_saved es ON es.event=e.id
    WHERE e.occasion=p_occasion AND (eu."user"=ANY(ARRAY(SELECT value::uuid
      FROM jsonb_array_elements_text(p_delete_user_ids))) OR
      es."user"=ANY(ARRAY(SELECT value::uuid
      FROM jsonb_array_elements_text(p_delete_user_ids))));
  SELECT COALESCE(array_agg(DISTINCT ug."group"),'{}'::bigint[]) INTO v_group_ids
    FROM public.user_groups ug JOIN public.user_group_info g ON g.id=ug."group"
    JOIN public.user_info ui ON ui.id=ug."user"
    WHERE g.occasion=p_occasion AND (ug."user"=ANY(ARRAY(SELECT value::uuid
      FROM jsonb_array_elements_text(p_delete_user_ids))) OR ug."user"=ANY(
      COALESCE((SELECT array_agg((row->>'user_id')::uuid)
        FROM jsonb_array_elements(p_rows) row
        WHERE NULLIF(row->>'user_id','') IS NOT NULL),'{}'::uuid[])) OR
      lower(btrim(ui.email_readonly))=ANY(COALESCE((SELECT array_agg(
        lower(btrim(row#>>'{data,email}'))) FROM jsonb_array_elements(p_rows) row),
        '{}'::text[])));
  v_result:=public.import_occasion_users_from_csv_internal_v1(
    p_occasion,p_rows,p_delete_user_ids);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RAISE data_exception USING MESSAGE=COALESCE(v_result->>'message','profile import failed');
  END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_after_users
    FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
  SELECT COALESCE(array_agg(DISTINCT ou."user" ORDER BY ou."user"),'{}'::uuid[])
    INTO v_current_users FROM public.occasion_users ou
    JOIN public.user_info ui ON ui.id=ou."user"
    WHERE ou.occasion=p_occasion AND (ou."user"=ANY(COALESCE((SELECT array_agg(
      (row->>'user_id')::uuid) FROM jsonb_array_elements(p_rows) row
      WHERE NULLIF(row->>'user_id','') IS NOT NULL),'{}'::uuid[])) OR
      lower(btrim(COALESCE(ui.email_readonly,ou.data->>'email')))=ANY(COALESCE((
        SELECT array_agg(lower(btrim(row#>>'{data,email}')))
        FROM jsonb_array_elements(p_rows) row),'{}'::text[])) OR
      NOT ou."user"=ANY(v_before_users));
  SELECT ARRAY(SELECT DISTINCT id FROM unnest(v_group_ids||COALESCE((
    SELECT array_agg(DISTINCT ug."group") FROM public.user_groups ug
    JOIN public.user_group_info g ON g.id=ug."group"
    WHERE g.occasion=p_occasion AND ug."user"=ANY(v_current_users)),
    '{}'::bigint[])) id ORDER BY id) INTO v_group_ids;
  SELECT ARRAY(SELECT DISTINCT id FROM unnest(v_current_users||COALESCE((
    SELECT array_agg(DISTINCT ug."user") FROM public.user_groups ug
    WHERE ug."group"=ANY(v_group_ids)),'{}'::uuid[])) id
    JOIN public.occasion_users ou ON ou.occasion=p_occasion AND ou."user"=id
    ORDER BY id) INTO v_current_users;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  SELECT 'occasion_user','occasion',p_occasion,id::text,1
    FROM unnest(v_current_users) id
  ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,
      updated_at=clock_timestamp();
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  SELECT 'user_group','occasion',p_occasion,id::text,1 FROM unnest(v_group_ids) id
  ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,
      updated_at=clock_timestamp();
  DELETE FROM public.client_aggregate_versions v WHERE v.aggregate_type='occasion_user'
    AND v.scope_type='occasion' AND v.scope_id=p_occasion
    AND v.aggregate_id=ANY(ARRAY(SELECT value FROM jsonb_array_elements_text(
      p_delete_user_ids)));
  v_private_impacts:=public.group_profile_impacts_internal_v1(p_occasion,v_current_users);
  IF v_actor=ANY(v_current_users) THEN v_actor_replacements:=jsonb_build_array(
    jsonb_build_object('component','private_profile','userId',v_actor,
      'payload',public.get_private_profile_payload_v1(p_occasion,v_actor))); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.users.import','profile',jsonb_build_array(jsonb_build_object(
      'entityType','occasion_user','entityId',NULL,'operation','import',
      'safeLabel','Profile CSV import','changedFields',jsonb_build_array('profiles','services','groups'))),
    CASE WHEN cardinality(v_event_ids)>0 AND v_publishable
      THEN ARRAY['live_public'] ELSE '{}'::text[] END,
    v_private_impacts,CASE WHEN cardinality(v_event_ids)>0 AND v_publishable
      THEN COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'component','live_public','entityId',id)) FROM unnest(v_event_ids) id),'[]'::jsonb)
      ELSE '[]'::jsonb END,v_result,'{}','[]','user',NULL,v_actor_replacements);
END; $function$
;
CREATE OR REPLACE FUNCTION public.delete_occasion_user_client_sync_v1(p_occasion bigint, p_user uuid, p_command_id uuid, p_expected_version bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_version bigint; v_begin jsonb; v_hash text;
  v_profile jsonb; v_event_ids bigint[]; v_group_ids bigint[];
  v_private_impacts jsonb; v_publishable boolean;
  v_actor_replacements jsonb:='[]'::jsonb;
BEGIN
  IF v_actor IS NULL OR NOT (public.get_is_manager_on_occasion(p_occasion)
    OR public.get_is_admin_on_occasion(p_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion manager required'; END IF;
  SELECT NOT o.is_hidden INTO v_publishable FROM public.occasions o WHERE o.id=p_occasion;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'userId',p_user,'expectedVersion',p_expected_version)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.user.delete',
    p_occasion,v_actor,v_hash);
  PERFORM public.lock_group_occasion_internal_v1(p_occasion);
  IF NOT (public.get_is_manager_on_occasion(p_occasion) OR public.get_is_admin_on_occasion(p_occasion)) THEN RAISE insufficient_privilege USING MESSAGE='occasion manager required'; END IF;
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM 1 FROM public.occasion_users ou WHERE ou.occasion=p_occasion
    AND ou."user"=p_user FOR UPDATE;
  IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,
    'unchanged',200,jsonb_build_object('version',0,'profile',NULL)); END IF;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('occasion_user','occasion',p_occasion,p_user::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='occasion_user' AND scope_type='occasion'
    AND scope_id=p_occasion AND aggregate_id=p_user::text FOR UPDATE;
  v_profile:=public.get_occasion_user_command_data_v1(p_occasion,p_user);
  IF p_expected_version IS DISTINCT FROM v_version THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,
      jsonb_build_object('version',v_version,'profile',v_profile)); END IF;
  SELECT COALESCE(array_agg(DISTINCT e.id),'{}'::bigint[]) INTO v_event_ids
  FROM public.events e LEFT JOIN public.event_users eu ON eu.event=e.id
  LEFT JOIN public.event_users_saved es ON es.event=e.id
  WHERE e.occasion=p_occasion AND (eu."user"=p_user OR es."user"=p_user);
  SELECT COALESCE(array_agg(ug."group"),'{}'::bigint[]) INTO v_group_ids
  FROM public.user_groups ug JOIN public.user_group_info g ON g.id=ug."group"
  WHERE ug."user"=p_user AND g.occasion=p_occasion;
  v_private_impacts:=public.group_profile_impacts_internal_v1(p_occasion,ARRAY(SELECT members."user" FROM public.user_groups members WHERE members."group"=ANY(v_group_ids) AND members."user"<>p_user)||ARRAY[p_user]);
  v_private_impacts:=(SELECT COALESCE(jsonb_agg(x ORDER BY x->>'userId'),'[]') FROM jsonb_array_elements(v_private_impacts) x WHERE x->>'userId'<>p_user::text);
  UPDATE public.news SET created_by=NULL WHERE created_by=p_user AND occasion=p_occasion;
  DELETE FROM public.user_groups WHERE "user"=p_user AND "group"=ANY(v_group_ids);
  UPDATE public.client_aggregate_versions SET version=version+1,
    updated_at=clock_timestamp() WHERE aggregate_type='user_group'
    AND scope_type='occasion' AND scope_id=p_occasion
    AND aggregate_id=ANY(ARRAY(SELECT id::text FROM unnest(v_group_ids) id));
  DELETE FROM public.event_users WHERE "user"=p_user AND event=ANY(v_event_ids);
  DELETE FROM public.event_users_saved WHERE "user"=p_user AND event=ANY(v_event_ids);
  DELETE FROM public.user_news WHERE "user"=p_user AND occasion=p_occasion;
  DELETE FROM public.occasion_users WHERE "user"=p_user AND occasion=p_occasion;
  DELETE FROM public.client_sync_private_scopes WHERE occasion=p_occasion
    AND user_id=p_user;
  DELETE FROM public.client_aggregate_versions WHERE aggregate_type='occasion_user'
    AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_user::text;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_private_impacts) impact
    WHERE impact->>'userId'=v_actor::text) THEN
    v_actor_replacements:=jsonb_build_array(jsonb_build_object(
      'component','private_profile','userId',v_actor,
      'payload',public.get_private_profile_payload_v1(p_occasion,v_actor))); END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.user.delete','profile',jsonb_build_array(jsonb_build_object(
      'entityType','occasion_user','entityId',p_user,'operation','delete',
      'safeLabel','Occasion user','changedFields',jsonb_build_array('membership'))),
    CASE WHEN v_publishable AND cardinality(v_event_ids)>0 THEN ARRAY['live_public']
      ELSE '{}'::text[] END,v_private_impacts,
    CASE WHEN v_publishable THEN COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'component','live_public','entityId',id)) FROM unnest(v_event_ids) id),'[]'::jsonb)
      ELSE '[]'::jsonb END,
    jsonb_build_object('version',v_version,'profile',NULL),
    '{}','[]','user',NULL,v_actor_replacements);
END; $function$
;
CREATE OR REPLACE FUNCTION public.delete_owned_companion_internal_v1(p_occasion bigint, p_companion uuid, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO public, extensions
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_event_ids bigint[];
  v_group_ids bigint[]; v_private_impacts jsonb; v_replacements jsonb;
  v_is_publishable boolean;
BEGIN
  IF v_actor IS NULL OR p_companion IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid companion delete'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.user_companions uc
    JOIN public.occasion_users ou ON ou."user"=uc.companion AND ou.occasion=p_occasion
    WHERE uc."user"=v_actor AND uc.companion=p_companion) THEN
    RAISE insufficient_privilege USING MESSAGE='companion owner required'; END IF;
  IF EXISTS (SELECT 1 FROM public.occasion_users ou
    WHERE ou."user"=p_companion AND ou.occasion<>p_occasion) THEN
    RAISE invalid_parameter_value USING MESSAGE='cross-occasion companion requires manual cleanup'; END IF;
  SELECT NOT o.is_hidden INTO v_is_publishable FROM public.occasions o
    WHERE o.id=p_occasion;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion,'companion',p_companion)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.companion.delete',
    p_occasion,v_actor,v_hash);
  PERFORM public.lock_group_occasion_internal_v1(p_occasion);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'companion-owner:'||v_actor::text||':'||p_occasion::text,0));
  PERFORM 1 FROM public.user_info ui WHERE ui.id=p_companion FOR UPDATE;
  IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'unchanged',200,jsonb_build_object('companion',NULL)); END IF;
  SELECT COALESCE(array_agg(DISTINCT event_id ORDER BY event_id),'{}'::bigint[])
    INTO v_event_ids FROM (
      SELECT eu.event event_id FROM public.event_users eu JOIN public.events e
        ON e.id=eu.event WHERE eu."user"=p_companion AND e.occasion=p_occasion
      UNION SELECT es.event FROM public.event_users_saved es JOIN public.events e
        ON e.id=es.event WHERE es."user"=p_companion AND e.occasion=p_occasion
    ) affected;
  SELECT COALESCE(array_agg(ug."group" ORDER BY ug."group"),'{}'::bigint[])
    INTO v_group_ids FROM public.user_groups ug JOIN public.user_group_info g
      ON g.id=ug."group" WHERE ug."user"=p_companion AND g.occasion=p_occasion;
  PERFORM 1 FROM public.events e WHERE e.id=ANY(v_event_ids) ORDER BY e.id FOR UPDATE;
  PERFORM 1 FROM public.user_group_info g WHERE g.id=ANY(v_group_ids) ORDER BY g.id FOR UPDATE;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_profile',
    'userId',impacted.user_id)),'[]'::jsonb) INTO v_private_impacts FROM (
      SELECT v_actor user_id UNION SELECT ug."user" FROM public.user_groups ug
        WHERE ug."group"=ANY(v_group_ids) AND ug."user"<>p_companion
    ) impacted JOIN public.occasion_users ou ON ou.occasion=p_occasion
      AND ou."user"=impacted.user_id;
  UPDATE public.news SET created_by=NULL WHERE created_by=p_companion;
  DELETE FROM public.user_groups WHERE "user"=p_companion;
  DELETE FROM public.event_users WHERE "user"=p_companion;
  DELETE FROM public.user_news WHERE "user"=p_companion;
  DELETE FROM public.event_users_saved WHERE "user"=p_companion;
  DELETE FROM public.occasion_users WHERE "user"=p_companion;
  DELETE FROM public.client_aggregate_versions WHERE aggregate_type='occasion_user'
    AND scope_type='occasion' AND scope_id=p_occasion
    AND aggregate_id=p_companion::text;
  DELETE FROM public.user_reset_token WHERE "user"=p_companion;
  DELETE FROM public.user_companions WHERE "user"=p_companion OR companion=p_companion;
  DELETE FROM public.user_info WHERE id=p_companion;
  DELETE FROM auth.identities WHERE user_id=p_companion;
  DELETE FROM auth.users WHERE id=p_companion;
  UPDATE public.client_aggregate_versions SET version=version+1,
    updated_at=clock_timestamp() WHERE aggregate_type='user_group'
    AND scope_type='occasion' AND scope_id=p_occasion
    AND aggregate_id=ANY(ARRAY(SELECT id::text FROM unnest(v_group_ids) id));
  v_replacements:=jsonb_build_array(jsonb_build_object(
    'component','private_profile','userId',v_actor,
    'payload',public.get_private_profile_payload_v1(p_occasion,v_actor)));
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    'profile.companion.delete','profile',jsonb_build_array(jsonb_build_object(
      'entityType','companion','entityId',p_companion,'operation','delete',
      'safeLabel','Companion','changedFields',jsonb_build_array('aggregate'))),
    CASE WHEN v_is_publishable AND cardinality(v_event_ids)>0
      THEN ARRAY['live_public'] ELSE '{}'::text[] END,v_private_impacts,
    CASE WHEN v_is_publishable THEN COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'component','live_public','entityId',event_id)) FROM unnest(v_event_ids) event_id),
      '[]'::jsonb) ELSE '[]'::jsonb END,
    jsonb_build_object('companion',NULL),'{}','[]','user',NULL,v_replacements);
END; $function$
;
CREATE OR REPLACE FUNCTION public.game_guess_client_sync_v1(p_checkpoint bigint, p_guess text, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_group bigint;
  v_begin jsonb; v_hash text; v_result jsonb; v_before jsonb; v_after jsonb;
  v_version bigint; v_impacts jsonb; v_replacements jsonb;
  v_domain_code integer;
BEGIN
  SELECT ih.occasion INTO v_occasion FROM public.information i
    JOIN public.information_hidden ih ON ih.id=i.information_hidden
    WHERE i.id=p_checkpoint;
  IF v_actor IS NULL OR v_occasion IS NULL THEN
    RAISE insufficient_privilege USING MESSAGE='occasion participant required'; END IF;
  SELECT ug."group" INTO v_group FROM public.user_groups ug
    JOIN public.user_group_info g ON g.id=ug."group"
    WHERE ug."user"=v_actor AND g.occasion=v_occasion AND g.type='game'
    ORDER BY g.id LIMIT 1;
  IF v_group IS NULL THEN RAISE insufficient_privilege USING MESSAGE='game group required'; END IF;
  IF p_guess IS NULL OR length(p_guess)>2000 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid game guess'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'checkpoint',p_checkpoint,'guess',p_guess)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.game.guess',
    v_occasion,v_actor,v_hash);
  PERFORM public.lock_group_occasion_internal_v1(v_occasion);
  IF NOT EXISTS(SELECT 1 FROM public.user_groups WHERE "group"=v_group AND "user"=v_actor) THEN RAISE insufficient_privilege USING MESSAGE='game group required'; END IF;
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.user_groups WHERE "group"=v_group AND "user"=v_actor) THEN RAISE insufficient_privilege USING MESSAGE='game group required'; END IF;
  SELECT g.data INTO v_before FROM public.user_group_info g WHERE g.id=v_group FOR UPDATE;
  v_result:=public.game_guess_internal_v1(p_checkpoint,p_guess);
  v_domain_code:=COALESCE((v_result->>'code')::integer,500);
  IF v_domain_code<>200 THEN RETURN public.complete_client_mutation_outcome_v1(
    p_command_id,'rejected',CASE WHEN v_domain_code BETWEEN 4030 AND 4039 THEN 403
      WHEN v_domain_code BETWEEN 4040 AND 4049 THEN 404 ELSE 400 END,
    jsonb_build_object('domainCode',v_domain_code,'message',v_result->>'message'));
  END IF;
  SELECT g.data INTO v_after FROM public.user_group_info g WHERE g.id=v_group;
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  VALUES ('user_group','occasion',v_occasion,v_group::text,0) ON CONFLICT DO NOTHING;
  SELECT version INTO v_version FROM public.client_aggregate_versions
    WHERE aggregate_type='user_group' AND scope_type='occasion'
      AND scope_id=v_occasion AND aggregate_id=v_group::text FOR UPDATE;
  IF v_before IS NOT DISTINCT FROM v_after THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      jsonb_build_object('domainCode',200,'correct',true,'version',v_version)); END IF;
  UPDATE public.client_aggregate_versions SET version=version+1,
    updated_at=clock_timestamp() WHERE aggregate_type='user_group'
    AND scope_type='occasion' AND scope_id=v_occasion AND aggregate_id=v_group::text
    RETURNING version INTO v_version;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_profile',
    'userId',ug."user")),'[]'::jsonb) INTO v_impacts FROM public.user_groups ug
    WHERE ug."group"=v_group;
  v_replacements:=jsonb_build_array(jsonb_build_object(
    'component','private_profile','userId',v_actor,
    'payload',public.get_private_profile_payload_v1(v_occasion,v_actor)));
  RETURN public.complete_client_mutation_applied_v1(p_command_id,v_occasion,
    'profile.game.guess','profile',jsonb_build_array(jsonb_build_object(
      'entityType','user_group','entityId',v_group,'operation','update',
      'safeLabel','Game checkpoint','changedFields',jsonb_build_array('game'))),
    '{}',v_impacts,'[]',jsonb_build_object('domainCode',200,'correct',true,
      'version',v_version),'{}','[]','user',NULL,v_replacements);
END; $function$
;
CREATE OR REPLACE FUNCTION public.import_occasion_users_from_csv_apply_v1(p_occasion_id bigint, p_rows jsonb, p_delete_user_ids jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_unit_id bigint;
    v_organization_id bigint;
    v_row jsonb;
    v_data_patch jsonb;
    v_services_patch jsonb;
    v_group_assignments jsonb := '[]'::jsonb;
    v_user_id uuid;
    v_email text;
    v_delivery_email text;
    v_existing_email text;
    v_has_delivery_email boolean;
    v_response jsonb;
    v_is_occasion_member boolean;
    v_created integer := 0;
    v_updated integer := 0;
    v_deleted integer := 0;
BEGIN
    SELECT o.unit, u.organization
      INTO v_unit_id, v_organization_id
      FROM public.occasions o
      JOIN public.units u ON u.id = o.unit
     WHERE o.id = p_occasion_id;

    IF v_unit_id IS NULL THEN
        RAISE EXCEPTION 'OCCASION_NOT_FOUND';
    END IF;

    IF NOT (
        public.get_is_manager_on_occasion(p_occasion_id)
        OR public.get_is_admin_on_occasion(p_occasion_id)
        OR public.get_is_editor_on_unit(v_unit_id)
    ) THEN
        RAISE EXCEPTION 'NOT_AUTHORIZED';
    END IF;

    IF COALESCE(jsonb_typeof(p_rows), 'null') <> 'array'
       OR COALESCE(jsonb_typeof(p_delete_user_ids), 'null') <> 'array' THEN
        RAISE EXCEPTION 'INVALID_IMPORT_PAYLOAD';
    END IF;
    IF jsonb_array_length(p_rows) > 10000
       OR jsonb_array_length(p_delete_user_ids) > 10000 THEN
        RAISE EXCEPTION 'IMPORT_PAYLOAD_TOO_LARGE';
    END IF;

    -- Serialize all CSV imports for one occasion. The group RPC uses the same
    -- lock, which is transaction-reentrant for this session.
    PERFORM pg_catalog.pg_advisory_xact_lock(p_occasion_id);
    PERFORM pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(
            'user-sign-in-email:' || v_organization_id::text, 0
        )
    );

    FOR v_row IN SELECT value FROM jsonb_array_elements(p_rows)
    LOOP
        IF COALESCE(jsonb_typeof(v_row), 'null') <> 'object'
           OR COALESCE(jsonb_typeof(v_row->'data'), 'null') <> 'object' THEN
            RAISE EXCEPTION 'INVALID_IMPORT_ROW';
        END IF;

        v_data_patch := v_row->'data';
        v_email := lower(btrim(v_data_patch->>'email'));
        v_has_delivery_email := v_row ? 'email_delivery';
        v_delivery_email := lower(btrim(COALESCE(
            v_row->>'email_delivery', v_data_patch->>'email'
        )));
        IF v_email IS NULL OR v_email = '' THEN
            RAISE EXCEPTION 'EMAIL_REQUIRED';
        END IF;
        IF v_delivery_email IS NULL OR v_delivery_email = '' THEN
            RAISE EXCEPTION 'DELIVERY_EMAIL_REQUIRED';
        END IF;

        v_user_id := NULLIF(v_row->>'user_id', '')::uuid;
        v_is_occasion_member := false;

        IF v_user_id IS NULL THEN
            -- Resolve against the occasion first. This makes a retry or a
            -- stale client safe: add_user_to_occasion must never replace an
            -- existing occasion row with profile data.
            SELECT ou."user"
              INTO v_user_id
              FROM public.occasion_users ou
              JOIN public.user_info ui ON ui.id = ou."user"
             WHERE ou.occasion = p_occasion_id
               AND lower(btrim(COALESCE(ui.email_readonly,
                                        ou.data->>'email'))) = v_email
             ORDER BY ou.created_at
             LIMIT 1;

            v_is_occasion_member := v_user_id IS NOT NULL;

            -- A CSV create may also refer to an organization user who simply
            -- is not on this occasion yet. Reuse that identity before creating
            -- a new Auth user.
            IF v_user_id IS NULL THEN
                SELECT ui.id
                  INTO v_user_id
                 FROM public.user_info ui
                 WHERE ui.organization = v_organization_id
                   AND lower(btrim(ui.email_readonly)) = v_email
                 ORDER BY ui.created_at
                 LIMIT 1;
            END IF;

            IF v_user_id IS NULL AND EXISTS (
                SELECT 1 FROM public.user_info ui
                 WHERE ui.organization = v_organization_id
                   AND lower(btrim(ui.email_readonly)) = v_email
            ) THEN
                -- The client assigns deterministic +N account emails for a
                -- CSV batch. Reassigning one here would make a later retry
                -- point at a different person. Without a stable external ID,
                -- reject the stale/colliding input instead of guessing identity.
                RAISE EXCEPTION 'ACCOUNT_EMAIL_ALREADY_EXISTS';
            END IF;

            IF v_user_id IS NULL THEN
                SELECT au.id
                  INTO v_user_id
                  FROM auth.users au
                 WHERE lower(au.email) = lower(v_organization_id::text || '+' || v_email)
                 ORDER BY au.created_at
                 LIMIT 1;
            END IF;

            IF v_user_id IS NULL THEN
                v_user_id := public.create_user_in_organization_with_data_pure(
                    v_organization_id,
                    v_email,
                    NULLIF(v_delivery_email, v_email),
                    encode(gen_random_bytes(16), 'hex'),
                    v_data_patch
                );
            ELSIF NOT EXISTS (
                SELECT 1 FROM public.user_info ui WHERE ui.id = v_user_id
            ) THEN
                INSERT INTO public.user_info (
                    id, organization, email_readonly, email_delivery, data,
                    name, surname, sex
                ) VALUES (
                    v_user_id,
                    v_organization_id,
                    v_email,
                    v_delivery_email,
                    v_data_patch,
                    v_data_patch->>'name',
                    v_data_patch->>'surname',
                    v_data_patch->>'sex'
                );
            END IF;

            IF v_is_occasion_member THEN
                v_updated := v_updated + 1;
            ELSE
                v_response := public.add_user_to_occasion_internal_v1(p_occasion_id, v_user_id);
                IF COALESCE((v_response->>'code')::integer, 500) <> 200 THEN
                    RAISE EXCEPTION 'ADD_USER_TO_OCCASION_FAILED: %',
                        COALESCE(v_response->>'message',
                                 'code ' || (v_response->>'code'));
                END IF;
                v_created := v_created + 1;
            END IF;
        ELSE
            SELECT lower(btrim(COALESCE(ui.email_readonly, ou.data->>'email')))
              INTO v_existing_email
              FROM public.occasion_users ou
              JOIN public.user_info ui ON ui.id = ou."user"
             WHERE ou.occasion = p_occasion_id
               AND ou."user" = v_user_id;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'USER_NOT_ON_OCCASION';
            END IF;
            IF v_existing_email IS DISTINCT FROM v_email THEN
                RAISE EXCEPTION 'USER_EMAIL_MISMATCH';
            END IF;
            v_updated := v_updated + 1;
        END IF;

        UPDATE public.user_info ui
           SET data = COALESCE(ui.data, '{}'::jsonb)
                      || public.get_user_profile_data_patch(v_data_patch),
               email_delivery = CASE
                   WHEN v_has_delivery_email
                       THEN NULLIF(v_delivery_email, v_email)
                   ELSE ui.email_delivery
               END,
               name = CASE WHEN v_data_patch ? 'name'
                           THEN v_data_patch->>'name' ELSE ui.name END,
               surname = CASE WHEN v_data_patch ? 'surname'
                              THEN v_data_patch->>'surname' ELSE ui.surname END,
               sex = CASE WHEN v_data_patch ? 'sex'
                          THEN v_data_patch->>'sex' ELSE ui.sex END,
               phone = CASE WHEN v_data_patch ? 'phone'
                            THEN v_data_patch->>'phone' ELSE ui.phone END,
               birth_date = CASE WHEN v_data_patch ? 'birthDate'
                                 THEN NULLIF(v_data_patch->>'birthDate', '')::date
                                 ELSE ui.birth_date END
         WHERE ui.id = v_user_id;

        IF v_row ? 'services' THEN
            IF COALESCE(jsonb_typeof(v_row->'services'), 'null') <> 'object' THEN
                RAISE EXCEPTION 'INVALID_SERVICES_PATCH';
            END IF;
            v_services_patch := v_row->'services';
        ELSE
            v_services_patch := NULL;
        END IF;

        UPDATE public.occasion_users ou
           SET data = COALESCE(ou.data, '{}'::jsonb) || v_data_patch,
               services = CASE
                   WHEN v_services_patch IS NULL THEN ou.services
                   ELSE COALESCE(ou.services, '{}'::jsonb) || v_services_patch
               END
         WHERE ou.occasion = p_occasion_id
           AND ou."user" = v_user_id;

        IF v_row ? 'group_title' THEN
            v_group_assignments := v_group_assignments || jsonb_build_array(
                jsonb_build_object(
                    'user_id', v_user_id,
                    'group_title', v_row->>'group_title'
                )
            );
        END IF;
    END LOOP;

    FOR v_user_id IN
        SELECT value::uuid FROM jsonb_array_elements_text(p_delete_user_ids)
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM public.occasion_users ou
             WHERE ou.occasion = p_occasion_id AND ou."user" = v_user_id
        ) THEN
            RAISE EXCEPTION 'DELETE_USER_NOT_ON_OCCASION';
        END IF;
        UPDATE public.news
           SET created_by = NULL
         WHERE created_by = v_user_id
           AND occasion = p_occasion_id;
        DELETE FROM public.user_groups
         WHERE "user" = v_user_id
           AND "group" IN (
               SELECT id FROM public.user_group_info
                WHERE occasion = p_occasion_id
           );
        DELETE FROM public.event_users
         WHERE "user" = v_user_id
           AND event IN (
               SELECT id FROM public.events WHERE occasion = p_occasion_id
           );
        DELETE FROM public.user_news
         WHERE "user" = v_user_id AND occasion = p_occasion_id;
        DELETE FROM public.event_users_saved
         WHERE "user" = v_user_id
           AND event IN (
               SELECT id FROM public.events WHERE occasion = p_occasion_id
           );
        DELETE FROM public.occasion_users
         WHERE "user" = v_user_id AND occasion = p_occasion_id;
        v_deleted := v_deleted + 1;
    END LOOP;

    IF jsonb_array_length(v_group_assignments) > 0 THEN
        PERFORM public.import_user_group_assignments_internal_v1(
            p_occasion_id,
            v_group_assignments
        );
    END IF;

    RETURN jsonb_build_object(
        'code', 200,
        'created', v_created,
        'updated', v_updated,
        'deleted', v_deleted,
        'groups', jsonb_array_length(v_group_assignments)
    );
END;
$function$
;
CREATE OR REPLACE FUNCTION public.create_reception_user_v1(p_occasion bigint, p_command_id uuid, p_profile jsonb, p_group_id bigint DEFAULT NULL::bigint, p_accommodation_code text DEFAULT NULL::text, p_confirm_same_name boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_org bigint; v_user uuid; v_hash text; v_existing public.reception_registrations%rowtype;
  v_name text:=btrim(p_profile->>'name'); v_surname text:=btrim(p_profile->>'surname'); v_email text:=lower(btrim(p_profile->>'email'));
  v_sex text:=p_profile->>'sex'; v_matches jsonb; v_services jsonb:='{}'::jsonb; v_catalog jsonb;
BEGIN
  IF NOT public.get_can_use_reception(p_occasion) THEN RETURN jsonb_build_object('code',403,'message','reception_unavailable'); END IF;
  IF NOT public.reception_rate_limit_v1('create',20) THEN RETURN jsonb_build_object('code',429,'message','rate_limited'); END IF;
  IF p_profile IS NULL OR jsonb_typeof(p_profile)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_profile) k WHERE k NOT IN('name','surname','email','sex','phone','birthDate'))
  THEN RETURN jsonb_build_object('code',400,'message','invalid_profile_fields'); END IF;
  IF COALESCE(v_name,'')='' OR COALESCE(v_surname,'')='' OR COALESCE(v_email,'')='' OR position('@' IN v_email)<=1 OR v_sex NOT IN('male','female','unspecified')
  THEN RETURN jsonb_build_object('code',400,'message','required_profile_fields'); END IF;
  v_hash:=encode(digest(jsonb_build_object('profile',p_profile,'group',p_group_id,'accommodation',p_accommodation_code)::text,'sha256'),'hex');
  SELECT * INTO v_existing FROM public.reception_registrations WHERE occasion=p_occasion AND created_by=v_actor AND command_id=p_command_id;
  IF FOUND THEN
    IF v_existing.request_hash<>v_hash THEN RETURN jsonb_build_object('code',409,'message','command_conflict'); END IF;
    SELECT ui.email_readonly INTO v_email FROM public.user_info ui WHERE ui.id=v_existing."user";
    RETURN jsonb_build_object('code',200,'userId',v_existing."user",'email',v_email,'replayed',true);
  END IF;
  PERFORM public.lock_group_occasion_internal_v1(p_occasion);
  IF NOT public.get_can_use_reception(p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='reception unavailable'; END IF;
  SELECT o.organization,COALESCE(o.services,'{}'::jsonb) INTO v_org,v_catalog FROM public.occasions o WHERE o.id=p_occasion FOR SHARE;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('reception-email:'||v_org::text||':'||v_email,0));
  SELECT ui.id INTO v_user
  FROM public.user_info ui
  WHERE ui.organization=v_org AND lower(btrim(ui.email_readonly))=v_email;
  IF v_user IS NOT NULL THEN
    IF (public.get_is_admin_on_occasion(p_occasion)
        OR public.get_is_manager_on_occasion(p_occasion))
      AND EXISTS(SELECT 1 FROM public.occasion_users ou
        WHERE ou.occasion=p_occasion AND ou."user"=v_user) THEN
      RETURN jsonb_build_object('code',200,'userId',v_user,'email',v_email,
        'existing',true,'replayed',false);
    END IF;
    RETURN jsonb_build_object('code',409,'message','email_already_exists');
  END IF;
  SELECT COALESCE(jsonb_agg(candidate),'[]'::jsonb) INTO v_matches FROM (
    SELECT jsonb_build_object('name',ui.name,'surname',ui.surname,'sex',ui.sex,
      'birthYear',CASE WHEN ui.birth_date IS NULL THEN NULL ELSE extract(year FROM ui.birth_date)::int END,
      'email',CASE WHEN position('@' IN ui.email_readonly)>2 THEN left(ui.email_readonly,1)||'***@'||split_part(ui.email_readonly,'@',2) ELSE '***' END,
      'onOccasion',EXISTS(SELECT 1 FROM public.occasion_users ou WHERE ou.occasion=p_occasion AND ou."user"=ui.id)) candidate
    FROM public.user_info ui WHERE ui.organization=v_org AND public.f_unaccent(btrim(ui.name))=public.f_unaccent(v_name)
      AND public.f_unaccent(btrim(ui.surname))=public.f_unaccent(v_surname) ORDER BY ui.created_at NULLS LAST LIMIT 10) q;
  IF jsonb_array_length(v_matches)>0 AND NOT p_confirm_same_name THEN RETURN jsonb_build_object('code',409,'message','same_name_confirmation_required','candidates',v_matches); END IF;
  IF p_group_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.user_group_info g WHERE g.id=p_group_id AND g.occasion=p_occasion AND g.type IS NULL FOR SHARE)
  THEN RETURN jsonb_build_object('code',400,'message','invalid_group'); END IF;
  IF p_accommodation_code IS NOT NULL AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(v_catalog->'accommodation')='array' THEN v_catalog->'accommodation' ELSE '[]'::jsonb END) x WHERE x->>'code'=p_accommodation_code)
  THEN RETURN jsonb_build_object('code',400,'message','invalid_accommodation'); END IF;
  v_user:=public.create_user_in_organization_with_data_pure(v_org,v_email,v_email,encode(gen_random_bytes(32),'hex'),p_profile-'email');
  IF p_accommodation_code IS NOT NULL THEN v_services:=jsonb_build_object('accommodation',jsonb_build_object(p_accommodation_code,'paid')); END IF;
  INSERT INTO public.occasion_users(occasion,"user",data,services) VALUES(p_occasion,v_user,p_profile,v_services);
  IF p_group_id IS NOT NULL THEN
    INSERT INTO public.user_groups("user","group",is_admin) VALUES(v_user,p_group_id,false);
    UPDATE public.client_aggregate_versions SET version=version+1,updated_at=clock_timestamp() WHERE aggregate_type='user_group' AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_group_id::text;
    PERFORM public.advance_group_profile_heads_internal_v1(p_occasion,ARRAY(SELECT "user" FROM public.user_groups WHERE "group"=p_group_id));
  END IF;
  INSERT INTO public.reception_registrations(occasion,"user",created_by,command_id,request_hash) VALUES(p_occasion,v_user,v_actor,p_command_id,v_hash);
  RETURN jsonb_build_object('code',200,'userId',v_user,'email',v_email,'replayed',false);
EXCEPTION WHEN unique_violation THEN RETURN jsonb_build_object('code',409,'message','email_or_command_conflict');
END $function$
;

-- Superseded ungranted wrapper implementations, now folded into receipt owners.
DROP FUNCTION IF EXISTS public.replace_group_assignments_companion_internal_v1(bigint,uuid,jsonb);
DROP FUNCTION IF EXISTS public.import_profiles_companion_internal_v1(bigint,uuid,jsonb,jsonb);
DROP FUNCTION IF EXISTS public.delete_occasion_user_companion_internal_v1(bigint,uuid,uuid,bigint);

CREATE OR REPLACE FUNCTION public.record_account_deletion_sync_v1(p_user uuid, p_organization bigint)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO public, extensions
AS $function$
DECLARE v_commit public.client_commits%ROWTYPE; v_occasion bigint;
  v_revision bigint; v_event bigint; v_member uuid;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  IF p_user IS NULL OR p_organization IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.user_info ui
    WHERE ui.id=p_user AND ui.organization=p_organization) THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid account deletion sync scope';
  END IF;
  FOR v_occasion IN SELECT occasion FROM public.occasion_users WHERE "user"=p_user ORDER BY occasion LOOP
    PERFORM public.lock_group_occasion_internal_v1(v_occasion);
  END LOOP;
  INSERT INTO public.client_commits
    (organization,actor_id,actor_display,actor_kind,source,change_class,reason)
  VALUES (p_organization,p_user,NULL,'service','account.delete','profile',
    'confirmed account deletion') RETURNING * INTO v_commit;
  INSERT INTO public.client_commit_items
    (commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
  VALUES (v_commit.commit_id,0,'user',p_user::text,'delete',NULL,
    ARRAY['membership','profile','private_data']);
  FOR v_occasion IN SELECT ou.occasion FROM public.occasion_users ou
    JOIN public.occasions o ON o.id=ou.occasion
    WHERE ou."user"=p_user AND o.organization=p_organization
    ORDER BY ou.occasion LOOP
    IF EXISTS (SELECT 1 FROM public.event_users eu JOIN public.events e
        ON e.id=eu.event WHERE eu."user"=p_user AND e.occasion=v_occasion)
      OR EXISTS (SELECT 1 FROM public.event_users_saved es JOIN public.events e
        ON e.id=es.event WHERE es."user"=p_user AND e.occasion=v_occasion) THEN
      INSERT INTO public.client_sync_scopes
        (component,scope_type,scope_id,source_revision)
      VALUES ('live_public','occasion',v_occasion,1)
      ON CONFLICT (component,scope_type,scope_id) DO UPDATE SET
        source_revision=public.client_sync_scopes.source_revision+1,
        updated_at=now() RETURNING source_revision INTO v_revision;
      INSERT INTO public.client_commit_components
        (commit_id,component,scope_type,scope_id,user_id,resulting_revision)
      VALUES (v_commit.commit_id,'live_public','occasion',v_occasion,NULL,v_revision);
      FOR v_event IN SELECT DISTINCT id FROM (
        SELECT eu.event id FROM public.event_users eu JOIN public.events e
          ON e.id=eu.event WHERE eu."user"=p_user AND e.occasion=v_occasion
        UNION SELECT es.event FROM public.event_users_saved es JOIN public.events e
          ON e.id=es.event WHERE es."user"=p_user AND e.occasion=v_occasion
      ) affected ORDER BY id LOOP
        INSERT INTO public.client_projection_dirty_keys
          (component,scope_type,scope_id,entity_id,source_revision)
        VALUES ('live_public','occasion',v_occasion,v_event,v_revision)
        ON CONFLICT (component,scope_type,scope_id,entity_id) DO UPDATE SET
          source_revision=EXCLUDED.source_revision,dirty_since=now(),
          claimed_at=NULL,claim_token=NULL;
      END LOOP;
    END IF;
    FOR v_member IN SELECT ou."user" FROM public.occasion_users ou
      WHERE ou.occasion=v_occasion AND ou."user"<>p_user ORDER BY ou."user" LOOP
      INSERT INTO public.client_sync_private_scopes
        (component,occasion,user_id,source_revision)
      VALUES ('private_profile',v_occasion,v_member,1)
      ON CONFLICT (component,occasion,user_id) DO UPDATE SET
        source_revision=public.client_sync_private_scopes.source_revision+1,
        updated_at=now() RETURNING source_revision INTO v_revision;
      INSERT INTO public.client_commit_components
        (commit_id,component,scope_type,scope_id,user_id,resulting_revision)
      VALUES (v_commit.commit_id,'private_profile','occasion',v_occasion,
        v_member,v_revision);
    END LOOP;
    UPDATE public.client_aggregate_versions SET version=version+1,
      updated_at=clock_timestamp() WHERE aggregate_type='user_group'
      AND scope_type='occasion' AND scope_id=v_occasion AND aggregate_id IN (
        SELECT ug."group"::text FROM public.user_groups ug
        WHERE ug."user"=p_user);
  END LOOP;
  RETURN v_commit.commit_id;
END; $function$
;

