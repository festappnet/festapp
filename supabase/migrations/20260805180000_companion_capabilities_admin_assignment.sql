BEGIN;

ALTER TABLE public.user_companions ADD COLUMN IF NOT EXISTS occasion bigint;
ALTER TABLE public.user_companions ADD COLUMN IF NOT EXISTS origin text;
ALTER TABLE public.user_companions ADD COLUMN IF NOT EXISTS created_by uuid;

DO $$
DECLARE v_bad record;
BEGIN
  SELECT uc."user",uc.companion,classified.common_occasions
  INTO v_bad
  FROM public.user_companions uc
  CROSS JOIN LATERAL (SELECT count(*) AS common_occasions
    FROM public.occasion_users owner_membership
    JOIN public.occasion_users companion_membership
      ON companion_membership."user"=uc.companion
     AND companion_membership.occasion=owner_membership.occasion
    WHERE owner_membership."user"=uc."user") classified
  WHERE uc.occasion IS NULL
    AND classified.common_occasions<>1
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'Companion relation % -> % has % common occasions; classify it before migration',
      v_bad."user",v_bad.companion,v_bad.common_occasions;
  END IF;
END $$;

UPDATE public.user_companions uc
SET occasion=classified.occasion,
    origin=COALESCE(uc.origin,'self_created'),
    created_by=COALESCE(uc.created_by,uc."user")
FROM (
  SELECT uc2."user",uc2.companion,min(owner_membership.occasion) AS occasion
  FROM public.user_companions uc2
  JOIN public.occasion_users owner_membership
    ON owner_membership."user"=uc2."user"
  JOIN public.occasion_users companion_membership
    ON companion_membership."user"=uc2.companion
   AND companion_membership.occasion=owner_membership.occasion
  WHERE uc2.occasion IS NULL
  GROUP BY uc2."user",uc2.companion
) classified
WHERE uc."user"=classified."user" AND uc.companion=classified.companion;

ALTER TABLE public.user_companions
  ALTER COLUMN occasion SET NOT NULL,
  ALTER COLUMN origin SET NOT NULL;
ALTER TABLE public.user_companions DROP CONSTRAINT IF EXISTS user_companions_pkey;
ALTER TABLE public.user_companions DROP CONSTRAINT IF EXISTS user_companions_user_fkey;
ALTER TABLE public.user_companions DROP CONSTRAINT IF EXISTS user_companions_companion_fkey;
ALTER TABLE public.user_companions
  ADD CONSTRAINT user_companions_pkey PRIMARY KEY (occasion,"user",companion),
  ADD CONSTRAINT user_companions_one_owner UNIQUE (occasion,companion),
  ADD CONSTRAINT user_companions_not_self CHECK ("user"<>companion),
  ADD CONSTRAINT user_companions_origin_check
    CHECK (origin IN ('self_created','admin_assigned')),
  ADD CONSTRAINT user_companions_owner_fkey
    FOREIGN KEY (occasion,"user")
    REFERENCES public.occasion_users(occasion,"user") ON DELETE CASCADE,
  ADD CONSTRAINT user_companions_companion_fkey
    FOREIGN KEY (occasion,companion)
    REFERENCES public.occasion_users(occasion,"user") ON DELETE CASCADE,
  ADD CONSTRAINT user_companions_created_by_fkey
    FOREIGN KEY (created_by) REFERENCES public.user_info(id) ON DELETE SET NULL;
ALTER TABLE public.user_companions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.user_companions FROM PUBLIC,anon,authenticated;
DROP FUNCTION IF EXISTS public.create_companion(bigint,uuid,text);

CREATE OR REPLACE FUNCTION public.get_companion_feature_policy_v1(p_occasion bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT jsonb_build_object(
    'is_enabled',COALESCE((feature->>'is_enabled')::boolean,false),
    'allow_user_create',COALESCE((feature->>'allow_user_create')::boolean,true),
    'allow_admin_assign',COALESCE((feature->>'allow_admin_assign')::boolean,false),
    'max_companions',GREATEST(COALESCE((feature->>'max_companions')::integer,1),1))
  FROM public.occasions o
  LEFT JOIN LATERAL (
    SELECT item AS feature FROM jsonb_array_elements(COALESCE(o.features,'[]')) item
    WHERE item->>'code'='companions' LIMIT 1
  ) configured ON true
  WHERE o.id=p_occasion;
$$;
REVOKE ALL ON FUNCTION public.get_companion_feature_policy_v1(bigint)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_private_profile_payload_v1(
  p_occasion bigint,p_user uuid
) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT jsonb_build_object(
    'user',(SELECT jsonb_build_object('id',u.id,'email',u.email_readonly,
      'name',u.name,'surname',u.surname,'sex',u.sex,'phone',u.phone,
      'birthDate',u.birth_date,'data',u.data) FROM public.user_info u
      WHERE u.id=p_user),
    'occasion',(SELECT jsonb_build_object('role',ou.role,'services',ou.services,
      'data',ou.data,'isCleaningBlocked',ou.is_cleaning_blocked,
      'isCleaningCrew',ou.is_cleaning_crew) FROM public.occasion_users ou
      WHERE ou.occasion=p_occasion AND ou."user"=p_user),
    'companions',COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'id',ui.id,'name',ui.name,'surname',COALESCE(ui.surname,''),
      'group_title',COALESCE(groups.titles,''),'origin',uc.origin,
      'can_owner_delete',uc.origin='self_created',
      'event_ids',COALESCE((SELECT jsonb_agg(eu.event ORDER BY eu.event)
        FROM public.event_users eu JOIN public.events e ON e.id=eu.event
        WHERE eu."user"=ui.id AND e.occasion=p_occasion),'[]'::jsonb))
      ORDER BY ui.name,ui.surname,ui.id)
      FROM public.user_companions uc
      JOIN public.user_info ui ON ui.id=uc.companion
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
      'placeData',(SELECT to_jsonb(p) FROM public.places p WHERE p.id=g.place))
      ORDER BY g.id) FROM public.user_groups mine JOIN public.user_group_info g
        ON g.id=mine."group" WHERE mine."user"=p_user
        AND g.occasion=p_occasion),'[]'::jsonb));
$$;
REVOKE ALL ON FUNCTION public.get_private_profile_payload_v1(bigint,uuid)
  FROM PUBLIC,anon,authenticated;

DROP FUNCTION IF EXISTS public.get_user_companions_data();
CREATE OR REPLACE FUNCTION public.get_user_companions_data(p_occasion bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT jsonb_build_object('code',200,'data',payload->'companions')
  FROM (SELECT public.get_private_profile_payload_v1(
    p_occasion,auth.uid()) payload) projected
  WHERE EXISTS (SELECT 1 FROM public.occasion_users ou
    WHERE ou.occasion=p_occasion AND ou."user"=auth.uid());
$$;
REVOKE ALL ON FUNCTION public.get_user_companions_data(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_user_companions_data(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.check_companion_relation_invariants_v1(
  p_occasion bigint,p_owner uuid,p_companion uuid
) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_policy jsonb; v_count bigint;
BEGIN
  IF p_owner IS NULL OR p_companion IS NULL OR p_owner=p_companion THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid companion relation';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'companion-member:'||p_occasion::text||':'||least(p_owner::text,p_companion::text),0));
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'companion-member:'||p_occasion::text||':'||greatest(p_owner::text,p_companion::text),0));
  IF NOT EXISTS (SELECT 1 FROM public.occasion_users ou
      WHERE ou.occasion=p_occasion AND ou."user"=p_owner)
    OR NOT EXISTS (SELECT 1 FROM public.occasion_users ou
      WHERE ou.occasion=p_occasion AND ou."user"=p_companion) THEN
    RAISE invalid_parameter_value USING MESSAGE='both users must be occasion participants';
  END IF;
  IF EXISTS (SELECT 1 FROM public.user_companions uc WHERE uc.occasion=p_occasion
      AND (uc.companion=p_owner OR uc."user"=p_companion)) THEN
    RAISE check_violation USING MESSAGE='companion relations cannot be chained';
  END IF;
  IF EXISTS (SELECT 1 FROM public.user_companions uc WHERE uc.occasion=p_occasion
      AND uc.companion=p_companion AND uc."user"<>p_owner) THEN
    RAISE unique_violation USING MESSAGE='participant already has an owner';
  END IF;
  v_policy:=public.get_companion_feature_policy_v1(p_occasion);
  SELECT count(*) INTO v_count FROM public.user_companions uc
    WHERE uc.occasion=p_occasion AND uc."user"=p_owner;
  IF v_count >= (v_policy->>'max_companions')::integer
    AND NOT EXISTS (SELECT 1 FROM public.user_companions uc
      WHERE uc.occasion=p_occasion AND uc."user"=p_owner
        AND uc.companion=p_companion) THEN
    RAISE check_violation USING MESSAGE='maximum companions reached';
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_companion_relation_invariants_v1(bigint,uuid,uuid)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.create_companion_in_organization_internal_v1(
  org bigint,oc bigint,usr uuid,c_name text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE new_companion uuid:=gen_random_uuid(); user_email text;
  companion_email text; v_policy jsonb;
BEGIN
  v_policy:=public.get_companion_feature_policy_v1(oc);
  IF auth.uid() IS NULL OR auth.uid()<>usr
    OR NOT EXISTS (SELECT 1 FROM public.occasion_users ou
      WHERE ou.occasion=oc AND ou."user"=usr)
    OR NOT COALESCE((v_policy->>'is_enabled')::boolean,false)
    OR NOT COALESCE((v_policy->>'allow_user_create')::boolean,true) THEN
    RETURN jsonb_build_object('code',403);
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'companion-member:'||oc::text||':'||usr::text,0));
  IF (SELECT count(*) FROM public.user_companions uc
      WHERE uc.occasion=oc AND uc."user"=usr)
      >= (v_policy->>'max_companions')::integer THEN
    RETURN jsonb_build_object('code',403);
  END IF;
  SELECT ui.email_readonly INTO user_email FROM public.user_info ui WHERE ui.id=usr;
  companion_email:=user_email||'+'||btrim(c_name);
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,
    email_confirmed_at,raw_app_meta_data,created_at,updated_at,
    confirmation_token,email_change,email_change_token_new,recovery_token)
  VALUES('00000000-0000-0000-0000-000000000000',new_companion,
    'authenticated','authenticated',format('%s+%s',org,companion_email),'',now(),
    '{"provider":"email","providers":["email"]}',now(),now(),'','','','');
  INSERT INTO auth.identities(id,provider_id,user_id,identity_data,provider,
    created_at,updated_at)
  VALUES(gen_random_uuid(),new_companion,new_companion,
    jsonb_build_object('sub',new_companion,'email',format('%s+%s',org,companion_email)),
    'email',now(),now());
  INSERT INTO public.user_info(id,email_readonly,name,organization)
    VALUES(new_companion,companion_email,btrim(c_name),org);
  PERFORM public.add_user_to_occasion_internal_v1(oc,new_companion);
  -- The target membership now exists; serialize and recheck the complete graph.
  PERFORM public.check_companion_relation_invariants_v1(oc,usr,new_companion);
  INSERT INTO public.user_companions(occasion,"user",companion,origin,created_by)
    VALUES(oc,usr,new_companion,'self_created',usr);
  RETURN jsonb_build_object('code',200);
END $$;
REVOKE ALL ON FUNCTION public.create_companion_in_organization_internal_v1(bigint,bigint,uuid,text)
  FROM PUBLIC,anon,authenticated;
DROP FUNCTION IF EXISTS public.create_companion_in_organization(bigint,bigint,uuid,text);
CREATE FUNCTION public.create_companion_in_organization(oc bigint,c_name text)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
  SELECT public.create_companion_in_organization_internal_v1(
    o.organization,oc,auth.uid(),c_name)
  FROM public.occasions o WHERE o.id=oc;
$$;
REVOKE ALL ON FUNCTION public.create_companion_in_organization(bigint,text)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_companion_in_organization(bigint,text)
  TO authenticated;

-- Keep the released receipt/replacement protocol, but contract its relation
-- discovery to the target occasion. The definition is copied from the already
-- applied expansion migration so there is still one public command owner.
DO $$
DECLARE v_definition text;
BEGIN
  SELECT pg_get_functiondef(to_regprocedure(
    'public.create_companion_client_sync_v1(bigint,text,uuid)'))
    INTO STRICT v_definition;
  v_definition:=replace(v_definition,
    'FROM public.user_companions uc WHERE uc."user"=v_actor;',
    'FROM public.user_companions uc WHERE uc.occasion=p_occasion AND uc."user"=v_actor;');
  v_definition:=replace(v_definition,
    'WHERE uc."user"=v_actor AND NOT uc.companion=ANY(v_before)',
    'WHERE uc.occasion=p_occasion AND uc."user"=v_actor AND NOT uc.companion=ANY(v_before)');
  IF position('uc.occasion=p_occasion' IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not contract create_companion_client_sync_v1 to occasion scope';
  END IF;
  EXECUTE v_definition;
END $$;

ALTER FUNCTION public.get_occasion_users_for_edit(bigint)
  RENAME TO get_occasion_users_for_edit_internal_companion_v1;
REVOKE ALL ON FUNCTION public.get_occasion_users_for_edit_internal_companion_v1(bigint)
  FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.get_occasion_users_for_edit(p_occasion_id bigint)
RETURNS json LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_result jsonb; v_users jsonb;
BEGIN
  v_result:=public.get_occasion_users_for_edit_internal_companion_v1(p_occasion_id)::jsonb;
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN RETURN v_result::json; END IF;
  WITH companion_owners AS (
    SELECT uc.companion,uc."user" owner_id,uc.origin,
      concat_ws(' ',owner_info.name,owner_info.surname) owner_name
    FROM public.user_companions uc
    JOIN public.user_info owner_info ON owner_info.id=uc."user"
    WHERE uc.occasion=p_occasion_id
  )
  SELECT COALESCE(jsonb_agg(row.value||jsonb_strip_nulls(jsonb_build_object(
      'companion_owner_id',owners.owner_id,
      'companion_owner_name',owners.owner_name,
      'companion_origin',owners.origin))),'[]'::jsonb)
  INTO v_users
  FROM jsonb_array_elements(v_result#>'{data,occasion_users}') row
  LEFT JOIN companion_owners owners ON owners.companion=(row.value->>'user')::uuid;
  RETURN jsonb_set(v_result,'{data,occasion_users}',v_users)::json;
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_users_for_edit(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_users_for_edit(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_occasion_users_editor_bundle_v1(
  p_occasion bigint
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_result jsonb; v_users jsonb;
BEGIN
  v_result:=public.get_occasion_users_for_edit(p_occasion)::jsonb;
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN RETURN v_result; END IF;
  WITH companion_owners AS (
    SELECT uc.companion,uc."user" owner_id,uc.origin,
      concat_ws(' ',owner_info.name,owner_info.surname) owner_name
    FROM public.user_companions uc
    JOIN public.user_info owner_info ON owner_info.id=uc."user"
    WHERE uc.occasion=p_occasion
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
END $$;
REVOKE ALL ON FUNCTION public.get_occasion_users_editor_bundle_v1(bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_occasion_users_editor_bundle_v1(bigint)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.assign_existing_companion_client_sync_v1(
  p_occasion bigint,p_owner uuid,p_companion uuid,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_policy jsonb; v_begin jsonb; v_hash text;
BEGIN
  v_policy:=public.get_companion_feature_policy_v1(p_occasion);
  IF v_actor IS NULL OR NOT (public.get_is_manager_on_occasion(p_occasion)
      OR public.get_is_admin_on_occasion(p_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion manager required';
  END IF;
  IF NOT COALESCE((v_policy->>'is_enabled')::boolean,false)
      OR NOT COALESCE((v_policy->>'allow_admin_assign')::boolean,false) THEN
    RAISE insufficient_privilege USING MESSAGE='admin companion assignment disabled';
  END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'owner',p_owner,'companion',p_companion)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.companion.assign',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM public.check_companion_relation_invariants_v1(p_occasion,p_owner,p_companion);
  IF EXISTS (SELECT 1 FROM public.user_companions uc WHERE uc.occasion=p_occasion
      AND uc."user"=p_owner AND uc.companion=p_companion) THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      jsonb_build_object('owner',p_owner,'companion',p_companion));
  END IF;
  INSERT INTO public.user_companions(occasion,"user",companion,origin,created_by)
  VALUES(p_occasion,p_owner,p_companion,'admin_assigned',v_actor);
  RETURN public.complete_private_profile_mutation_v1(p_command_id,p_occasion,
    'profile.companion.assign',jsonb_build_array(jsonb_build_object(
      'entityType','companion_assignment','entityId',p_companion,'operation','insert',
      'safeLabel','Companion assignment','changedFields',jsonb_build_array('owner'))),
    ARRAY[p_owner],'{}','[]',jsonb_build_object('owner',p_owner,'companion',p_companion));
END $$;
REVOKE ALL ON FUNCTION public.assign_existing_companion_client_sync_v1(bigint,uuid,uuid,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.assign_existing_companion_client_sync_v1(bigint,uuid,uuid,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.unassign_existing_companion_client_sync_v1(
  p_occasion bigint,p_owner uuid,p_companion uuid,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_policy jsonb; v_begin jsonb; v_hash text;
BEGIN
  v_policy:=public.get_companion_feature_policy_v1(p_occasion);
  IF v_actor IS NULL OR NOT (public.get_is_manager_on_occasion(p_occasion)
      OR public.get_is_admin_on_occasion(p_occasion)) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion manager required';
  END IF;
  IF NOT COALESCE((v_policy->>'is_enabled')::boolean,false)
      OR NOT COALESCE((v_policy->>'allow_admin_assign')::boolean,false) THEN
    RAISE insufficient_privilege USING MESSAGE='admin companion assignment disabled';
  END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
    'owner',p_owner,'companion',p_companion)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,'profile.companion.unassign',
    p_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'companion-member:'||p_occasion::text||':'||least(p_owner::text,p_companion::text),0));
  DELETE FROM public.user_companions uc WHERE uc.occasion=p_occasion
    AND uc."user"=p_owner AND uc.companion=p_companion
    AND uc.origin='admin_assigned';
  IF NOT FOUND THEN
    RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
      jsonb_build_object('owner',p_owner,'companion',p_companion));
  END IF;
  RETURN public.complete_private_profile_mutation_v1(p_command_id,p_occasion,
    'profile.companion.unassign',jsonb_build_array(jsonb_build_object(
      'entityType','companion_assignment','entityId',p_companion,'operation','delete',
      'safeLabel','Companion assignment','changedFields',jsonb_build_array('owner'))),
    ARRAY[p_owner],'{}','[]',jsonb_build_object('owner',p_owner,'companion',p_companion));
END $$;
REVOKE ALL ON FUNCTION public.unassign_existing_companion_client_sync_v1(bigint,uuid,uuid,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.unassign_existing_companion_client_sync_v1(bigint,uuid,uuid,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.impact_companion_owners_v1(
  p_occasion bigint,p_companions uuid[],p_source text
) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_impacts jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_profile',
    'userId',owners."user") ORDER BY owners."user"),'[]'::jsonb)
  INTO v_impacts
  FROM (SELECT DISTINCT uc."user" FROM public.user_companions uc
    WHERE uc.occasion=p_occasion AND uc.companion=ANY(p_companions)) owners;
  IF jsonb_array_length(v_impacts)>0 THEN
    PERFORM public.record_client_sync_commit_v1(p_occasion,p_source,'profile',
      '[]','{}',v_impacts,'[]','user',NULL);
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.impact_companion_owners_v1(bigint,uuid[],text)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.impact_private_profile_users_v1(
  p_occasion bigint,p_users uuid[],p_source text
) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_impacts jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_profile',
    'userId',impacted.id) ORDER BY impacted.id),'[]'::jsonb)
  INTO v_impacts
  FROM (SELECT DISTINCT id FROM unnest(COALESCE(p_users,'{}'::uuid[])) id) impacted
  JOIN public.occasion_users ou
    ON ou.occasion=p_occasion AND ou."user"=impacted.id;
  IF jsonb_array_length(v_impacts)>0 THEN
    PERFORM public.record_client_sync_commit_v1(p_occasion,p_source,'profile',
      '[]','{}',v_impacts,'[]','user',NULL);
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.impact_private_profile_users_v1(bigint,uuid[],text)
  FROM PUBLIC,anon,authenticated;

ALTER FUNCTION public.save_profile_client_sync_v1(bigint,uuid,uuid,bigint,jsonb)
  RENAME TO save_profile_companion_internal_v1;
REVOKE ALL ON FUNCTION public.save_profile_companion_internal_v1(bigint,uuid,uuid,bigint,jsonb)
  FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.save_profile_client_sync_v1(
  p_occasion bigint,p_user uuid,p_command_id uuid,p_expected_version bigint,
  p_profile jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_result jsonb;
BEGIN
  v_result:=public.save_profile_companion_internal_v1(
    p_occasion,p_user,p_command_id,p_expected_version,p_profile);
  IF v_result->>'status'='applied' THEN
    PERFORM public.impact_companion_owners_v1(
      p_occasion,ARRAY[p_user],'profile.companion_identity.changed');
  END IF;
  RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.save_profile_client_sync_v1(bigint,uuid,uuid,bigint,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_profile_client_sync_v1(bigint,uuid,uuid,bigint,jsonb)
  TO authenticated;

ALTER FUNCTION public.import_profiles_client_sync_v1(bigint,uuid,jsonb,jsonb)
  RENAME TO import_profiles_companion_internal_v1;
REVOKE ALL ON FUNCTION public.import_profiles_companion_internal_v1(bigint,uuid,jsonb,jsonb)
  FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.import_profiles_client_sync_v1(
  p_occasion bigint,p_command_id uuid,p_rows jsonb,p_delete_user_ids jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_result jsonb; v_owners uuid[];
BEGIN
  SELECT COALESCE(array_agg(DISTINCT uc."user"),'{}'::uuid[]) INTO v_owners
  FROM public.user_companions uc WHERE uc.occasion=p_occasion;
  v_result:=public.import_profiles_companion_internal_v1(
    p_occasion,p_command_id,p_rows,p_delete_user_ids);
  IF v_result->>'status'='applied' THEN
    PERFORM public.impact_private_profile_users_v1(
      p_occasion,v_owners,'profile.companion_identity.imported');
  END IF;
  RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.import_profiles_client_sync_v1(bigint,uuid,jsonb,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.import_profiles_client_sync_v1(bigint,uuid,jsonb,jsonb)
  TO authenticated;

ALTER FUNCTION public.delete_occasion_user_client_sync_v1(bigint,uuid,uuid,bigint)
  RENAME TO delete_occasion_user_companion_internal_v1;
REVOKE ALL ON FUNCTION public.delete_occasion_user_companion_internal_v1(bigint,uuid,uuid,bigint)
  FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.delete_occasion_user_client_sync_v1(
  p_occasion bigint,p_user uuid,p_command_id uuid,p_expected_version bigint
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_result jsonb; v_owners uuid[];
BEGIN
  SELECT COALESCE(array_agg(DISTINCT uc."user"),'{}'::uuid[]) INTO v_owners
  FROM public.user_companions uc
  WHERE uc.occasion=p_occasion AND uc.companion=p_user;
  v_result:=public.delete_occasion_user_companion_internal_v1(
    p_occasion,p_user,p_command_id,p_expected_version);
  IF v_result->>'status'='applied' THEN
    PERFORM public.impact_private_profile_users_v1(
      p_occasion,v_owners,'profile.companion_membership.deleted');
  END IF;
  RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.delete_occasion_user_client_sync_v1(bigint,uuid,uuid,bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_occasion_user_client_sync_v1(bigint,uuid,uuid,bigint)
  TO authenticated;

ALTER FUNCTION public.replace_group_assignments_client_sync_v1(bigint,uuid,jsonb)
  RENAME TO replace_group_assignments_companion_internal_v1;
REVOKE ALL ON FUNCTION public.replace_group_assignments_companion_internal_v1(bigint,uuid,jsonb)
  FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.replace_group_assignments_client_sync_v1(
  p_occasion bigint,p_command_id uuid,p_assignments jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_result jsonb; v_companions uuid[];
BEGIN
  SELECT COALESCE(array_agg(uc.companion),'{}'::uuid[]) INTO v_companions
    FROM public.user_companions uc WHERE uc.occasion=p_occasion;
  v_result:=public.replace_group_assignments_companion_internal_v1(
    p_occasion,p_command_id,p_assignments);
  IF v_result->>'status'='applied' THEN
    PERFORM public.impact_companion_owners_v1(
      p_occasion,v_companions,'profile.companion_group.changed');
  END IF;
  RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.replace_group_assignments_client_sync_v1(bigint,uuid,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.replace_group_assignments_client_sync_v1(bigint,uuid,jsonb)
  TO authenticated;

ALTER FUNCTION public.delete_companion_client_sync_v1(bigint,uuid,uuid)
  RENAME TO delete_owned_companion_client_sync_v1;
CREATE OR REPLACE FUNCTION public.delete_owned_companion_guard_v1(
  p_occasion bigint,p_companion uuid
) RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_policy jsonb;
BEGIN
  v_policy:=public.get_companion_feature_policy_v1(p_occasion);
  IF NOT COALESCE((v_policy->>'is_enabled')::boolean,false)
      OR NOT COALESCE((v_policy->>'allow_user_create')::boolean,true) THEN
    RAISE insufficient_privilege USING MESSAGE='self-created companion lifecycle disabled';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.user_companions uc
    WHERE uc.occasion=p_occasion AND uc."user"=auth.uid()
      AND uc.companion=p_companion AND uc.origin='self_created') THEN
    RAISE insufficient_privilege USING MESSAGE='self-created companion ownership required';
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.delete_owned_companion_guard_v1(bigint,uuid)
  FROM PUBLIC,anon,authenticated;

-- The renamed released implementation retains its receipt/deletion machinery.
-- Inject the strict origin/capability guard through a private wrapper and expose
-- only the canonical name to clients.
ALTER FUNCTION public.delete_owned_companion_client_sync_v1(bigint,uuid,uuid)
  RENAME TO delete_owned_companion_internal_v1;
REVOKE ALL ON FUNCTION public.delete_owned_companion_internal_v1(bigint,uuid,uuid)
  FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.delete_owned_companion_client_sync_v1(
  p_occasion bigint,p_companion uuid,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
BEGIN
  PERFORM public.delete_owned_companion_guard_v1(p_occasion,p_companion);
  RETURN public.delete_owned_companion_internal_v1(p_occasion,p_companion,p_command_id);
END $$;
REVOKE ALL ON FUNCTION public.delete_owned_companion_client_sync_v1(bigint,uuid,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_owned_companion_client_sync_v1(bigint,uuid,uuid)
  TO authenticated;
DROP FUNCTION IF EXISTS public.delete_companion_client_sync_v1(bigint,uuid,uuid);
DROP FUNCTION IF EXISTS public.delete_user(uuid,bigint);
DROP FUNCTION IF EXISTS public.delete_user_obsolete_v1(uuid,bigint);
CREATE OR REPLACE FUNCTION public.delete_occasion_user_ws(
  usr_to_delete uuid,occasion_id bigint
) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
BEGIN
  IF NOT (public.get_is_manager_on_occasion(occasion_id)
      OR public.get_is_admin_on_occasion(occasion_id)) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion manager required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.occasion_users ou
      WHERE ou.occasion=occasion_id AND ou."user"=usr_to_delete) THEN
    RAISE invalid_parameter_value USING MESSAGE='target is not an occasion member';
  END IF;
  PERFORM public.delete_occasion_user(usr_to_delete,occasion_id);
END $$;
REVOKE ALL ON FUNCTION public.delete_occasion_user_ws(uuid,bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_occasion_user_ws(uuid,bigint)
  TO authenticated;

ALTER FUNCTION public.set_event_attendance_client_sync_v1(bigint,uuid,text,uuid)
  RENAME TO set_event_attendance_internal_v1;
REVOKE ALL ON FUNCTION public.set_event_attendance_internal_v1(bigint,uuid,text,uuid)
  FROM PUBLIC,anon,authenticated;
DO $$
DECLARE v_definition text;
BEGIN
  SELECT pg_get_functiondef(to_regprocedure(
    'public.set_event_attendance_internal_v1(bigint,uuid,text,uuid)'))
    INTO STRICT v_definition;
  v_definition:=replace(v_definition,
    'set_event_attendance_internal_v1','set_event_attendance_client_sync_v1');
  v_definition:=replace(v_definition,
    'WHERE c."user"=v_actor AND c.companion=p_participant_id)',
    'WHERE c.occasion=v_occasion AND c."user"=v_actor AND c.companion=p_participant_id AND COALESCE((public.get_companion_feature_policy_v1(v_occasion)->>''is_enabled'')::boolean,false))');
  v_definition:=replace(v_definition,
    'WHERE c.companion=p_participant_id ORDER BY c."user" LIMIT 1;',
    'WHERE c.occasion=v_occasion AND c.companion=p_participant_id ORDER BY c."user" LIMIT 1;');
  IF position('c.occasion=v_occasion' IN v_definition)=0
      OR position('get_companion_feature_policy_v1' IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not contract attendance command to occasion capability scope';
  END IF;
  EXECUTE v_definition;
END $$;
DROP FUNCTION public.set_event_attendance_internal_v1(bigint,uuid,text,uuid);
REVOKE ALL ON FUNCTION public.set_event_attendance_client_sync_v1(bigint,uuid,text,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_event_attendance_client_sync_v1(bigint,uuid,text,uuid)
  TO authenticated;

-- Contract the released legacy readers and attendance facades in place. These
-- functions remain for old clients, but every companion decision is scoped by
-- their explicit occasion/unit argument rather than a global relation lookup.
DO $$
DECLARE v_definition text;
BEGIN
  SELECT pg_get_functiondef(to_regprocedure(
    'public.get_all_user_basics_for_scan(text)')) INTO STRICT v_definition;
  v_definition:=replace(v_definition,
    'LEFT JOIN public.user_companions uc ON ui.id = uc.companion',
    'LEFT JOIN public.user_companions uc ON ui.id = uc.companion AND uc.occasion=oid');
  IF position('uc.occasion=oid' IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not scope get_all_user_basics_for_scan'; END IF;
  EXECUTE v_definition;

  SELECT pg_get_functiondef(to_regprocedure(
    'public.get_all_user_basics_from_occasion(bigint)')) INTO STRICT v_definition;
  v_definition:=replace(v_definition,
    'LEFT JOIN public.user_companions uc ON ui.id = uc.companion',
    'LEFT JOIN public.user_companions uc ON ui.id = uc.companion AND uc.occasion=oc');
  IF position('uc.occasion=oc' IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not scope get_all_user_basics_from_occasion'; END IF;
  EXECUTE v_definition;

  SELECT pg_get_functiondef(to_regprocedure(
    'public.get_all_user_basics_from_occasion_unit(bigint)')) INTO STRICT v_definition;
  v_definition:=replace(v_definition,
    'LEFT JOIN public.user_companions uc ON ui.id = uc.companion',
    'LEFT JOIN public.user_companions uc ON ui.id = uc.companion AND uc.occasion IN (SELECT id FROM public.occasions WHERE unit=p_unit_id)');
  IF position('unit=p_unit_id' IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not scope get_all_user_basics_from_occasion_unit'; END IF;
  EXECUTE v_definition;

  SELECT pg_get_functiondef(to_regprocedure(
    'public.get_user_info_for_users(uuid[],bigint)')) INTO STRICT v_definition;
  v_definition:=replace(v_definition,
    'LEFT JOIN public.user_companions uc ON ui.id = uc.companion',
    'LEFT JOIN public.user_companions uc ON ui.id = uc.companion AND uc.occasion=oc');
  IF position('uc.occasion=oc' IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not scope get_user_info_for_users'; END IF;
  EXECUTE v_definition;

  SELECT pg_get_functiondef(to_regprocedure(
    'public.get_users_from_occasion_with_orders(bigint)')) INTO STRICT v_definition;
  v_definition:=replace(v_definition,
    'WHERE uc."user" = ui.id',
    'WHERE uc."user" = ui.id AND uc.occasion=oc');
  IF position('uc.occasion=oc' IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not scope get_users_from_occasion_with_orders'; END IF;
  EXECUTE v_definition;

  SELECT pg_get_functiondef(to_regprocedure(
    'public.sign_user_to_event(bigint,uuid)')) INTO STRICT v_definition;
  v_definition:=replace(v_definition,
    'SELECT 1 FROM user_companions WHERE "user" = auth.uid() AND companion = usr',
    'SELECT 1 FROM public.user_companions uc JOIN public.events ce ON ce.id=ev AND ce.occasion=uc.occasion WHERE uc."user"=auth.uid() AND uc.companion=usr AND COALESCE((public.get_companion_feature_policy_v1(uc.occasion)->>''is_enabled'')::boolean,false)');
  IF position('ce.occasion=uc.occasion' IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not scope sign_user_to_event'; END IF;
  EXECUTE v_definition;

  SELECT pg_get_functiondef(to_regprocedure(
    'public.sign_user_out_of_event(bigint,uuid)')) INTO STRICT v_definition;
  v_definition:=replace(v_definition,
    'SELECT 1 FROM user_companions WHERE "user" = auth.uid() AND companion = usr ',
    'SELECT 1 FROM public.user_companions uc JOIN public.events ce ON ce.id=ev AND ce.occasion=uc.occasion WHERE uc."user"=auth.uid() AND uc.companion=usr AND COALESCE((public.get_companion_feature_policy_v1(uc.occasion)->>''is_enabled'')::boolean,false) ');
  IF position('ce.occasion=uc.occasion' IN v_definition)=0 THEN
    RAISE EXCEPTION 'Could not scope sign_user_out_of_event'; END IF;
  EXECUTE v_definition;
END $$;

UPDATE public.client_sync_component_sources
SET tracked_columns=ARRAY['occasion','user','companion','origin','created_by'],
    canonical_writers=ARRAY['create_companion_client_sync_v1',
      'delete_owned_companion_client_sync_v1',
      'assign_existing_companion_client_sync_v1',
      'unassign_existing_companion_client_sync_v1'],
    legacy_writers=ARRAY['create_companion_in_organization occasion facade']
WHERE component='private_profile'
  AND source_relation='public.user_companions'::regclass;

UPDATE public.client_sync_component_sources
SET canonical_writers=array_replace(canonical_writers,
  'delete_companion_client_sync_v1','delete_owned_companion_client_sync_v1')
WHERE 'delete_companion_client_sync_v1'=ANY(canonical_writers);

-- Released SECURITY DEFINER client-sync commands run with a locked-down
-- search_path. Their legacy permission/membership helpers must therefore own
-- an explicit trusted path rather than inheriting the caller's path. The
-- repository sources already declare this for the permission helpers; align
-- the live definitions and the renamed membership implementation as part of
-- this cutover.
ALTER FUNCTION public.add_user_to_occasion_internal_v1(bigint,uuid)
  SET search_path = public, extensions;
ALTER FUNCTION public.get_is_editor_on_unit(bigint)
  SET search_path = public, extensions;
ALTER FUNCTION public.get_is_editor_order_on_occasion(bigint)
  SET search_path = public, extensions;
ALTER FUNCTION public.update_ticket_products_internal_v1(bigint,jsonb)
  SET search_path = public, eshop, extensions;

COMMIT;
