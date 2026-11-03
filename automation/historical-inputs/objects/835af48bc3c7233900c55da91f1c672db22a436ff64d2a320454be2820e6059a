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
