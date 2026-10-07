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
