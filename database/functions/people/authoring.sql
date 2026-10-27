-- Bounded people projections and transport adapters. Existing commands own writes,
-- immutable intent hashes, receipts, audit, versions and downstream invalidation.
CREATE OR REPLACE FUNCTION public.people_profile_projection_internal_v1(p_profile jsonb,p_version bigint)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('userId',p_profile->'user','aggregateVersion',p_version,
  'name',p_profile#>'{profile,name}','surname',p_profile#>'{profile,surname}',
  'profile',coalesce((SELECT jsonb_object_agg(key,value) FROM jsonb_each(coalesce(nullif(p_profile->'data','null'::jsonb),'{}'))
   WHERE key IN ('name','surname','sex','phone','birthDate','note','diet','text1','text2','text3')),'{}'::jsonb),
  'roles',jsonb_build_object('role',p_profile->'role','is_manager',coalesce(nullif(p_profile->'is_manager','null'::jsonb),'false'::jsonb),
   'is_editor',coalesce(nullif(p_profile->'is_editor','null'::jsonb),'false'::jsonb),'is_editor_view',coalesce(nullif(p_profile->'is_editor_view','null'::jsonb),'false'::jsonb),
   'is_editor_order',coalesce(nullif(p_profile->'is_editor_order','null'::jsonb),'false'::jsonb),'is_editor_order_view',coalesce(nullif(p_profile->'is_editor_order_view','null'::jsonb),'false'::jsonb),
   'is_receptionist',coalesce(nullif(p_profile->'is_receptionist','null'::jsonb),'false'::jsonb),'is_approver',coalesce(nullif(p_profile->'is_approver','null'::jsonb),'false'::jsonb),
   'is_approved',coalesce(nullif(p_profile->'is_approved','null'::jsonb),'false'::jsonb),'is_cleaning_crew',coalesce(nullif(p_profile->'is_cleaning_crew','null'::jsonb),'false'::jsonb),
   'is_cleaning_blocked',coalesce(nullif(p_profile->'is_cleaning_blocked','null'::jsonb),'false'::jsonb),'is_volunteer',coalesce(nullif(p_profile#>'{data,is_volunteer}','null'::jsonb),'false'::jsonb)));
$$;
REVOKE ALL ON FUNCTION public.people_profile_projection_internal_v1(jsonb,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.manage_people(p_occasion bigint,p_organization bigint,p_unit bigint,p_action text,p_payload jsonb,p_command_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb; payload jsonb:=coalesce(p_payload,'{}'); entity jsonb; usr uuid; gid bigint;
 lim int:=coalesce((p_payload->>'limit')::int,50); item jsonb;
BEGIN
 PERFORM public.lock_people_scope_internal_v1(p_occasion,p_organization,p_unit);
 IF jsonb_typeof(payload)<>'object' OR octet_length(payload::text)>2097152 OR lim NOT BETWEEN 1 AND 100 THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid people request'; END IF;
 IF p_action LIKE 'units.%' THEN
  IF p_occasion IS NOT NULL OR NOT public.can_manage_unit_users(p_unit) THEN
   RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
  IF p_action='units.list' THEN
   SELECT jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(page) ORDER BY page."userId"),'[]'::jsonb)) INTO result FROM (
    SELECT uu."user" AS "userId",ui.name,ui.surname,coalesce(uu.is_manager,false) AS "isManager",
      coalesce(uu.is_editor,false) AS "isEditor",coalesce(v.version,0) AS "aggregateVersion",coalesce(uu.is_editor_view,false) AS "isEditorView"
    FROM public.unit_users uu JOIN public.user_info ui ON ui.id=uu."user"
    LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='unit_user' AND v.scope_type='unit' AND v.scope_id=p_unit AND v.aggregate_id=uu."user"::text
    LEFT JOIN public.organization_users visibility ON visibility.organization=p_organization AND visibility."user"=uu."user"
    WHERE uu.unit=p_unit AND visibility.is_hidden IS NOT TRUE AND (payload->>'after' IS NULL OR uu."user">(payload->>'after')::uuid)
    ORDER BY uu."user" LIMIT lim) page;
   RETURN result;
  ELSIF p_action='units.create' THEN
   PERFORM public.prepare_profile_change_internal_v1('{}',jsonb_build_object('profileChange',(payload->'profile')-'email'));
   IF jsonb_typeof(payload#>'{profile,email}') IS DISTINCT FROM 'string' THEN RAISE invalid_parameter_value USING MESSAGE='email required'; END IF;
   RETURN public.save_unit_user_client_sync_v1(p_unit,NULL,p_command_id,NULL,jsonb_build_object('kind','editor','data',payload->'profile','is_manager',false,'is_editor',false,'is_editor_view',false));
  ELSIF p_action IN ('units.roles','units.profile') THEN
   RETURN public.save_unit_user_client_sync_v1(p_unit,(payload->>'userId')::uuid,p_command_id,(payload->>'expectedVersion')::bigint,
    (payload->'changes')||jsonb_build_object('kind',CASE WHEN p_action='units.roles' THEN 'roles' ELSE 'profile' END));
  ELSIF p_action='units.revoke' THEN
   RETURN public.delete_unit_user_client_sync_v1((payload->>'userId')::uuid,p_unit,p_command_id);
  END IF;
 ELSIF p_action LIKE 'profiles.%' THEN
  IF NOT public.can_manage_occasion_participants(p_occasion) THEN
   RAISE insufficient_privilege USING MESSAGE='participant manager required'; END IF;
  usr:=(payload->>'userId')::uuid;
  IF p_action='profiles.list' THEN
   SELECT jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(page) ORDER BY page."userId"),'[]'::jsonb)) INTO result FROM (
    SELECT ou."user" AS "userId",ui.name,ui.surname,coalesce(v.version,0) AS "aggregateVersion"
    FROM public.occasion_users ou JOIN public.user_info ui ON ui.id=ou."user"
    LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='occasion_user' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=ou."user"::text
    WHERE ou.occasion=p_occasion AND (payload->>'after' IS NULL OR ou."user">(payload->>'after')::uuid)
    ORDER BY ou."user" LIMIT lim) page;
   RETURN result;
  ELSIF p_action='profiles.inspect' THEN
   PERFORM 1 FROM public.user_info WHERE id=usr FOR SHARE;
   PERFORM 1 FROM public.occasion_users WHERE occasion=p_occasion AND "user"=usr FOR SHARE;
   IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='participant unavailable'; END IF;
   SELECT public.people_profile_projection_internal_v1(public.get_occasion_user_command_data_v1(p_occasion,usr),coalesce(v.version,0)) INTO result
    FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='occasion_user' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=usr::text;
   RETURN result;
  ELSIF p_action IN ('profiles.save','profiles.roles') THEN
   result:=public.save_profile_client_sync_v1(p_occasion,usr,p_command_id,(payload->>'expectedVersion')::bigint,
    jsonb_build_object('occasion',p_occasion,'user',usr,CASE WHEN p_action='profiles.roles' THEN 'roleChange' ELSE 'profileChange' END,payload->'changes'));
  ELSIF p_action='profiles.create' THEN
   PERFORM public.prepare_profile_change_internal_v1('{}',jsonb_build_object('profileChange',(payload->'profile')-'email'));
   IF jsonb_typeof(payload#>'{profile,email}') IS DISTINCT FROM 'string' THEN RAISE invalid_parameter_value USING MESSAGE='email required'; END IF;
   result:=public.create_occasion_user_client_sync_v1(p_occasion,p_command_id,jsonb_build_object('occasion',p_occasion,'data',payload->'profile'));
  ELSIF p_action='profiles.delete' THEN
   result:=public.delete_occasion_user_client_sync_v1(p_occasion,usr,p_command_id,(payload->>'expectedVersion')::bigint);
  ELSIF p_action='profiles.importTickets' THEN
   result:=public.import_users_from_tickets_client_sync_v1(p_occasion,p_command_id);
  ELSIF p_action='profiles.import' THEN
   IF jsonb_typeof(payload->'rows') IS DISTINCT FROM 'array' OR jsonb_array_length(payload->'rows')>100 THEN RAISE invalid_parameter_value USING MESSAGE='bounded import required'; END IF;
   FOR item IN SELECT * FROM jsonb_array_elements(payload->'rows') LOOP
    IF EXISTS(SELECT 1 FROM jsonb_object_keys(item) k WHERE k NOT IN ('user_id','data')) THEN RAISE invalid_parameter_value USING MESSAGE='ordinary import fields required'; END IF;
    PERFORM public.prepare_profile_change_internal_v1('{}',jsonb_build_object('profileChange',(item->'data')-'email'));
   END LOOP;
   result:=public.import_profiles_client_sync_v1(p_occasion,p_command_id,payload->'rows','[]');
  END IF;
  -- Project the immutable stored response, never reread the mutated entity after replay.
  IF result#>'{data,profile}' IS NOT NULL AND result#>'{data,profile}'<>'null'::jsonb THEN
   entity:=public.people_profile_projection_internal_v1(result#>'{data,profile}',(result#>>'{data,version}')::bigint);
   result:=jsonb_set(result,'{data}',jsonb_build_object('profile',entity,'version',result#>'{data,version}'));
  END IF;
  IF result IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='unsupported people operation'; END IF;
  RETURN result;
 ELSIF p_action LIKE 'groups.%' THEN
  gid:=(payload->>'groupId')::bigint;
  IF gid IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.user_group_info WHERE id=gid AND occasion=p_occasion) THEN
   RAISE insufficient_privilege USING MESSAGE='group unavailable'; END IF;
  IF p_action='groups.list' THEN
   IF NOT public.can_read_groups_editor(p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='group reader required'; END IF;
   SELECT jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(page) ORDER BY page."groupId"),'[]'::jsonb)) INTO result FROM (
    SELECT g.id AS "groupId",g.title,g.description,g.type,g.place AS "placeId",coalesce(v.version,0) AS "aggregateVersion"
    FROM public.user_group_info g LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='user_group' AND v.scope_type='occasion' AND v.scope_id=p_occasion AND v.aggregate_id=g.id::text
    WHERE g.occasion=p_occasion AND (payload->>'after' IS NULL OR g.id>(payload->>'after')::bigint)
    ORDER BY g.id LIMIT lim) page;
   RETURN result;
  ELSIF p_action='groups.inspect' THEN
   PERFORM 1 FROM public.user_group_info WHERE id=gid AND occasion=p_occasion FOR SHARE;
   IF NOT public.can_read_group_editor(p_occasion,gid) THEN RAISE insufficient_privilege USING MESSAGE='group reader required'; END IF;
   IF (SELECT count(*) FROM public.user_groups WHERE "group"=gid)>500 THEN RAISE invalid_parameter_value USING MESSAGE='group exceeds authoring limit'; END IF;
   result:=public.get_user_group_command_data_v1(gid);
   RETURN jsonb_build_object('groupId',gid,'title',result->'title','description',result->'description','type',result->'type','placeId',result->'place','aggregateVersion',result->'aggregate_version',
    'participants',(SELECT coalesce(jsonb_agg(jsonb_build_object('user_id',x->'userId','is_admin',x->'isAdmin')),'[]'::jsonb) FROM jsonb_array_elements(result->'participants') x));
  ELSIF p_action='groups.save' THEN
   IF jsonb_typeof(payload->'group') IS DISTINCT FROM 'object' OR (payload->'group') ?| ARRAY['id','privatePlace','data'] THEN RAISE invalid_parameter_value USING MESSAGE='explicit group fields required'; END IF;
   result:=public.save_user_group_client_sync_v1(p_occasion,p_command_id,(payload->>'expectedVersion')::bigint,(payload->'group')||CASE WHEN gid IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('id',gid) END);
  ELSIF p_action='groups.delete' THEN
   result:=public.delete_user_group_client_sync_v1(p_occasion,gid,p_command_id,(payload->>'expectedVersion')::bigint);
  ELSIF p_action='groups.addMembers' THEN
   result:=public.add_user_group_members_client_sync_v1(p_occasion,gid,ARRAY(SELECT value::uuid FROM jsonb_array_elements_text(payload->'userIds')),p_command_id);
  ELSIF p_action='groups.replaceAssignments' THEN
   result:=public.replace_group_assignments_client_sync_v1(p_occasion,p_command_id,payload->'assignments');
  END IF;
  -- Mutation summaries expose no editor bundle or unrelated member profile data.
  IF result IS NOT NULL THEN RETURN jsonb_set(result,'{data}',(coalesce(result->'data','{}')-'group')||CASE WHEN result#>>'{data,group,id}' IS NOT NULL THEN jsonb_build_object('groupId',result#>'{data,group,id}') ELSE '{}'::jsonb END); END IF;
 END IF;
 IF result IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='unsupported people operation'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.manage_people(bigint,bigint,bigint,text,jsonb,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.manage_people(bigint,bigint,bigint,text,jsonb,uuid) TO authenticated,service_role;
