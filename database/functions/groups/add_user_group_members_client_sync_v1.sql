CREATE OR REPLACE FUNCTION public.add_user_group_members_client_sync_v1(p_occasion bigint,p_group bigint,p_users uuid[],p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE actor uuid:=auth.uid(); begin_result jsonb; hash text; members jsonb; users uuid[]; v_version bigint; changed integer;
BEGIN
 IF cardinality(p_users)>5000 THEN RAISE invalid_parameter_value USING MESSAGE='too many members'; END IF;
 p_users:=ARRAY(SELECT DISTINCT id FROM unnest(p_users) id ORDER BY id);
 IF actor IS NULL OR cardinality(p_users) NOT BETWEEN 1 AND 5000 THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid selected members'; END IF;
 IF NOT public.get_is_editor_on_occasion(p_occasion) AND NOT EXISTS(SELECT 1 FROM public.user_groups m
  JOIN public.user_group_info g ON g.id=m."group" WHERE g.id=p_group AND g.occasion=p_occasion AND m."user"=actor AND m.is_admin) THEN
  RAISE insufficient_privilege USING MESSAGE='group editor required'; END IF;
 hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,'group',p_group,'users',p_users)::text,'UTF8'),'sha256'),'hex');
 begin_result:=public.begin_client_mutation_v1(p_command_id,'profile.group.members.add',p_occasion,actor,hash);
 IF begin_result->>'disposition'='replay' THEN RETURN begin_result->'response'; END IF;
 PERFORM 1 FROM public.user_group_info WHERE id=p_group AND occasion=p_occasion FOR UPDATE;
 IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='group unavailable'; END IF;
 IF NOT public.get_is_editor_on_occasion(p_occasion) AND NOT EXISTS(SELECT 1 FROM public.user_groups WHERE "group"=p_group AND "user"=actor AND is_admin) THEN
  RAISE insufficient_privilege USING MESSAGE='group editor required'; END IF;
 SELECT jsonb_agg(jsonb_build_object('user_id',id,'is_admin',false)) INTO members FROM unnest(p_users) id;
 changed:=public.write_user_group_members_internal_v1(p_occasion,p_group,members,false);
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
 VALUES('user_group','occasion',p_occasion,p_group::text,0) ON CONFLICT DO NOTHING;
 UPDATE public.client_aggregate_versions SET version=version+CASE WHEN changed>0 THEN 1 ELSE 0 END,updated_at=clock_timestamp()
 WHERE aggregate_type='user_group' AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_group::text RETURNING version INTO v_version;
 IF changed=0 THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,
  jsonb_build_object('version',v_version,'group',public.get_user_group_command_data_v1(p_group))); END IF;
 SELECT array_agg("user") INTO users FROM public.user_groups WHERE "group"=p_group;
 RETURN public.complete_private_profile_mutation_v1(p_command_id,p_occasion,'profile.group.members.add',
  jsonb_build_array(jsonb_build_object('entityType','user_group','entityId',p_group,'operation','update','safeLabel','Group members',
    'changedFields',jsonb_build_array('participants'))),users,'{}','[]',
  jsonb_build_object('version',v_version,'group',public.get_user_group_command_data_v1(p_group)));
END $$;
REVOKE ALL ON FUNCTION public.add_user_group_members_client_sync_v1(bigint,bigint,uuid[],uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.add_user_group_members_client_sync_v1(bigint,bigint,uuid[],uuid) TO authenticated;
