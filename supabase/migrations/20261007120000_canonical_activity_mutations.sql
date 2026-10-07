-- Additive activities correction; legacy G3 boundaries retained.
-- Activity graph domain: one implementation shared by publish and G3 compatibility.
CREATE OR REPLACE FUNCTION public.activity_time_internal_v1(p_value text,p_occasion bigint,p_utc boolean)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE zone text; instant timestamptz;
BEGIN
 IF p_value IS NULL THEN RETURN NULL; END IF;
 SELECT COALESCE(data->>'timezone','Europe/Prague') INTO zone FROM public.occasions WHERE id=p_occasion;
 IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=zone) THEN zone:='Europe/Prague'; END IF;
 IF p_value ~ '(Z|[+-][0-9]{2}:[0-9]{2})$' THEN instant:=p_value::timestamptz;
 ELSE instant:=p_value::timestamp AT TIME ZONE CASE WHEN p_utc THEN 'UTC' ELSE zone END; END IF;
 RETURN to_char(instant AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"');
END $$;
CREATE OR REPLACE FUNCTION public.normalize_activity_graph_internal_v1(p_occasion bigint,p_graph jsonb,p_utc boolean DEFAULT true,p_validate boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE a jsonb; x jsonb; result jsonb:='[]'; assignments jsonb; seen uuid[]:='{}'; seen_assignments uuid[]:='{}'; aid uuid; xid uuid; places jsonb; events jsonb;
BEGIN
 IF p_graph IS NULL OR jsonb_typeof(p_graph)<>'array' OR jsonb_array_length(p_graph)>2000 OR octet_length(p_graph::text)>2097152 THEN RAISE invalid_parameter_value USING MESSAGE='invalid activity graph'; END IF;
 FOR a IN SELECT value FROM jsonb_array_elements(p_graph) ORDER BY value->>'id' LOOP
  IF jsonb_typeof(a)<>'object' OR NOT(a ?& ARRAY['id','title','is_hidden','order','assignments']) OR EXISTS(SELECT 1 FROM jsonb_object_keys(a) k WHERE k NOT IN('id','title','description','type','unit','is_hidden','order','data','assignments')) OR jsonb_typeof(a->'assignments')<>'array' THEN RAISE invalid_parameter_value USING MESSAGE='invalid activity'; END IF;
  aid:=(a->>'id')::uuid;
  IF aid IS NULL OR aid=ANY(seen) OR (p_validate AND EXISTS(SELECT 1 FROM public.activities WHERE id=aid AND occasion<>p_occasion)) OR (p_validate AND a->>'unit' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=p_occasion AND unit=(a->>'unit')::bigint)) THEN RAISE invalid_parameter_value USING MESSAGE='duplicate or foreign activity'; END IF;
  seen:=array_append(seen,aid); assignments:='[]';
  FOR x IN SELECT value FROM jsonb_array_elements(a->'assignments') ORDER BY value->>'id' LOOP
   IF jsonb_typeof(x)<>'object' OR NOT(x ?& ARRAY['id','linked_place_ids','linked_event_ids']) OR EXISTS(SELECT 1 FROM jsonb_object_keys(x) k WHERE k NOT IN('id','user','start_time','end_time','title','description','data','linked_place_ids','linked_event_ids')) OR jsonb_typeof(x->'linked_place_ids')<>'array' OR jsonb_typeof(x->'linked_event_ids')<>'array' THEN RAISE invalid_parameter_value USING MESSAGE='invalid assignment'; END IF;
   xid:=(x->>'id')::uuid;
   IF xid IS NULL OR xid=ANY(seen_assignments) OR (p_validate AND EXISTS(SELECT 1 FROM public.activity_assignments aa JOIN public.activities ac ON ac.id=aa.activity_id WHERE aa.id=xid AND ac.occasion<>p_occasion)) OR (p_validate AND x->>'user' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=p_occasion AND "user"=(x->>'user')::uuid)) THEN RAISE invalid_parameter_value USING MESSAGE='duplicate or foreign assignment'; END IF;
   IF p_validate AND (x->>'user' IS NULL OR x->>'start_time' IS NULL OR x->>'end_time' IS NULL OR public.activity_time_internal_v1(x->>'end_time',p_occasion,p_utc)::timestamptz < public.activity_time_internal_v1(x->>'start_time',p_occasion,p_utc)::timestamptz) THEN RAISE invalid_parameter_value USING MESSAGE='assignment user and ordered times required'; END IF;
   seen_assignments:=array_append(seen_assignments,xid);
   IF p_validate AND (EXISTS(SELECT 1 FROM jsonb_array_elements_text(x->'linked_place_ids') id WHERE NOT EXISTS(SELECT 1 FROM public.places WHERE public.places.id=id::bigint AND occasion=p_occasion)) OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(x->'linked_event_ids') id WHERE NOT EXISTS(SELECT 1 FROM public.events WHERE public.events.id=id::bigint AND occasion=p_occasion))) THEN RAISE invalid_parameter_value USING MESSAGE='foreign assignment reference'; END IF;
   SELECT COALESCE(jsonb_agg(id::bigint ORDER BY id::bigint),'[]') INTO places FROM jsonb_array_elements_text(x->'linked_place_ids') id;
   SELECT COALESCE(jsonb_agg(id::bigint ORDER BY id::bigint),'[]') INTO events FROM jsonb_array_elements_text(x->'linked_event_ids') id;
   IF jsonb_array_length(places)<>(SELECT count(DISTINCT v) FROM jsonb_array_elements(places) v) OR jsonb_array_length(events)<>(SELECT count(DISTINCT v) FROM jsonb_array_elements(events) v) THEN RAISE invalid_parameter_value USING MESSAGE='duplicate assignment links'; END IF;
   assignments:=assignments||jsonb_build_array(jsonb_build_object('id',xid,'user',(x->>'user')::uuid,'start_time',public.activity_time_internal_v1(x->>'start_time',p_occasion,p_utc),'end_time',public.activity_time_internal_v1(x->>'end_time',p_occasion,p_utc),'title',x->>'title','description',x->>'description','data',x->'data','linked_place_ids',places,'linked_event_ids',events));
  END LOOP;
  result:=result||jsonb_build_array(jsonb_build_object('id',aid,'title',a->>'title','description',a->>'description','type',a->>'type','unit',(a->>'unit')::bigint,'is_hidden',(a->>'is_hidden')::boolean,'order',(a->>'order')::bigint,'data',a->'data','assignments',assignments));
 END LOOP;
 RETURN result;
END $$;
CREATE OR REPLACE FUNCTION public.activity_history_graph_internal_v1(p_occasion bigint,p_history jsonb,p_validate boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE graph jsonb;
BEGIN
 IF p_history IS NULL OR jsonb_typeof(p_history)<>'object' OR octet_length(p_history::text)>2097152 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_history) k WHERE k NOT IN('id','parent_history_id','aggregate_version','activities','activity_assignments','assignmentPlaceLinks','assignmentEventLinks','schemaVersion','timeBasis')) OR (p_history ? 'schemaVersion' AND (p_history->>'schemaVersion'<>'1' OR p_history->>'timeBasis'<>'UTC')) THEN RAISE invalid_parameter_value USING MESSAGE='invalid activity history'; END IF;
 IF p_validate THEN
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(COALESCE(p_history->'activities','[]')) a,LATERAL jsonb_object_keys(a) k WHERE k NOT IN('id','created_at','updated_at','title','description','type','occasion','unit','is_hidden','order','data','activity_assignments')) OR EXISTS(SELECT 1 FROM jsonb_array_elements(COALESCE(p_history->'activity_assignments','[]')) x,LATERAL jsonb_object_keys(x) k WHERE k NOT IN('id','activity_id','user','start_time','end_time','title','description','data','user_info','activity_assignment_places','activity_assignment_events','created_at','updated_at')) THEN RAISE invalid_parameter_value USING MESSAGE='unknown activity history field'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(COALESCE(p_history->'activities','[]')) a WHERE jsonb_typeof(a->'activity_assignments')='array' AND (
    jsonb_array_length(a->'activity_assignments')<>(SELECT count(*) FROM jsonb_array_elements(COALESCE(p_history->'activity_assignments','[]')) x WHERE x->>'activity_id'=a->>'id') OR EXISTS(
      SELECT 1 FROM jsonb_array_elements(a->'activity_assignments') nx WHERE EXISTS(SELECT 1 FROM jsonb_object_keys(nx) k WHERE k NOT IN('id','activity_id','user','start_time','end_time','title','description','data','user_info','activity_assignment_places','activity_assignment_events','created_at','updated_at')) OR NOT EXISTS(
        SELECT 1 FROM jsonb_array_elements(COALESCE(p_history->'activity_assignments','[]')) x WHERE x->>'id'=nx->>'id' AND x->>'activity_id'=a->>'id' AND (x->'user',x->'title',x->'description',x->'data') IS NOT DISTINCT FROM (nx->'user',nx->'title',nx->'description',nx->'data') AND public.activity_time_internal_v1(x->>'start_time',p_occasion,p_history->>'timeBasis'='UTC') IS NOT DISTINCT FROM public.activity_time_internal_v1(nx->>'start_time',p_occasion,p_history->>'timeBasis'='UTC') AND public.activity_time_internal_v1(x->>'end_time',p_occasion,p_history->>'timeBasis'='UTC') IS NOT DISTINCT FROM public.activity_time_internal_v1(nx->>'end_time',p_occasion,p_history->>'timeBasis'='UTC'))))) THEN RAISE invalid_parameter_value USING MESSAGE='inconsistent nested history assignments'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(COALESCE(p_history->'assignmentPlaceLinks','[]')) l WHERE EXISTS(SELECT 1 FROM jsonb_object_keys(l) k WHERE k NOT IN('assignment_id','place_id')) OR l->>'place_id' IS NULL OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(COALESCE(p_history->'activity_assignments','[]')) x WHERE x->>'id'=l->>'assignment_id')) OR EXISTS(SELECT 1 FROM jsonb_array_elements(COALESCE(p_history->'assignmentEventLinks','[]')) l WHERE EXISTS(SELECT 1 FROM jsonb_object_keys(l) k WHERE k NOT IN('assignment_id','event_id')) OR l->>'event_id' IS NULL OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(COALESCE(p_history->'activity_assignments','[]')) x WHERE x->>'id'=l->>'assignment_id')) THEN RAISE invalid_parameter_value USING MESSAGE='orphan or invalid history link'; END IF;
 END IF;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',a->'id','title',a->'title','description',a->'description','type',a->'type','unit',a->'unit','is_hidden',a->'is_hidden','order',a->'order','data',a->'data','assignments',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',x->'id','user',x->'user','start_time',x->'start_time','end_time',x->'end_time','title',x->'title','description',x->'description','data',x->'data','linked_place_ids',COALESCE((SELECT jsonb_agg(l->'place_id') FROM jsonb_array_elements(COALESCE(p_history->'assignmentPlaceLinks','[]')) l WHERE l->>'assignment_id'=x->>'id'),'[]'),'linked_event_ids',COALESCE((SELECT jsonb_agg(l->'event_id') FROM jsonb_array_elements(COALESCE(p_history->'assignmentEventLinks','[]')) l WHERE l->>'assignment_id'=x->>'id'),'[]'))) FROM jsonb_array_elements(COALESCE(p_history->'activity_assignments','[]')) x WHERE x->>'activity_id'=a->>'id'),'[]'))),'[]') INTO graph FROM jsonb_array_elements(COALESCE(NULLIF(p_history->'activities','null'),'[]')) a;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(COALESCE(p_history->'activity_assignments','[]')) x WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements(COALESCE(p_history->'activities','[]')) a WHERE a->>'id'=x->>'activity_id')) THEN RAISE invalid_parameter_value USING MESSAGE='orphan history assignment'; END IF;
 RETURN public.normalize_activity_graph_internal_v1(p_occasion,graph,p_history->>'timeBasis'='UTC',p_validate);
END $$;
CREATE OR REPLACE FUNCTION public.activity_graph_history_internal_v1(p_graph jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('schemaVersion',1,'timeBasis','UTC','activities',COALESCE((SELECT jsonb_agg(a-'assignments') FROM jsonb_array_elements(p_graph) a),'[]'),'activity_assignments',COALESCE((SELECT jsonb_agg((x-'linked_place_ids'-'linked_event_ids')||jsonb_build_object('activity_id',a->'id')) FROM jsonb_array_elements(p_graph) a,LATERAL jsonb_array_elements(a->'assignments') x),'[]'),'assignmentPlaceLinks',COALESCE((SELECT jsonb_agg(jsonb_build_object('assignment_id',x->'id','place_id',p)) FROM jsonb_array_elements(p_graph) a,LATERAL jsonb_array_elements(a->'assignments') x,LATERAL jsonb_array_elements(x->'linked_place_ids') p),'[]'),'assignmentEventLinks',COALESCE((SELECT jsonb_agg(jsonb_build_object('assignment_id',x->'id','event_id',e)) FROM jsonb_array_elements(p_graph) a,LATERAL jsonb_array_elements(a->'assignments') x,LATERAL jsonb_array_elements(x->'linked_event_ids') e),'[]'));
$$;
CREATE OR REPLACE FUNCTION public.current_activity_graph_internal_v1(p_occasion bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.normalize_activity_graph_internal_v1(p_occasion,COALESCE(jsonb_agg(jsonb_build_object('id',a.id,'title',a.title,'description',a.description,'type',a.type,'unit',a.unit,'is_hidden',a.is_hidden,'order',a."order",'data',a.data,'assignments',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',x.id,'user',x."user",'start_time',x.start_time,'end_time',x.end_time,'title',x.title,'description',x.description,'data',x.data,'linked_place_ids',COALESCE((SELECT jsonb_agg(place_id) FROM public.activity_assignment_places WHERE assignment_id=x.id),'[]'),'linked_event_ids',COALESCE((SELECT jsonb_agg(event_id) FROM public.activity_assignment_events WHERE assignment_id=x.id),'[]'))) FROM public.activity_assignments x WHERE x.activity_id=a.id),'[]'))),'[]'),true) FROM public.activities a WHERE a.occasion=p_occasion;
$$;
CREATE OR REPLACE FUNCTION public.replace_activities_graph_internal_v1(p_occasion bigint,p_graph jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE a jsonb; x jsonb; graph jsonb; changed int;
BEGIN
 graph:=public.normalize_activity_graph_internal_v1(p_occasion,p_graph,true);
 DELETE FROM public.activity_assignments aa USING public.activities a WHERE aa.activity_id=a.id AND a.occasion=p_occasion AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(graph) g,LATERAL jsonb_array_elements(g->'assignments') assignment WHERE assignment->>'id'=aa.id::text);
 DELETE FROM public.activities WHERE occasion=p_occasion AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(graph) g WHERE g->>'id'=public.activities.id::text);
 FOR a IN SELECT value FROM jsonb_array_elements(graph) LOOP
  INSERT INTO public.activities(id,title,description,type,unit,occasion,is_hidden,"order",data) VALUES((a->>'id')::uuid,a->>'title',a->>'description',a->>'type',(a->>'unit')::bigint,p_occasion,(a->>'is_hidden')::boolean,(a->>'order')::bigint,a->'data') ON CONFLICT(id) DO UPDATE SET title=excluded.title,description=excluded.description,type=excluded.type,unit=excluded.unit,is_hidden=excluded.is_hidden,"order"=excluded."order",data=excluded.data WHERE public.activities.occasion=p_occasion;
  GET DIAGNOSTICS changed=ROW_COUNT; IF changed<>1 THEN RAISE invalid_parameter_value USING MESSAGE='global activity UUID collision'; END IF;
  FOR x IN SELECT value FROM jsonb_array_elements(a->'assignments') LOOP
   INSERT INTO public.activity_assignments(id,activity_id,"user",start_time,end_time,title,description,data) VALUES((x->>'id')::uuid,(a->>'id')::uuid,(x->>'user')::uuid,(x->>'start_time')::timestamptz,(x->>'end_time')::timestamptz,x->>'title',x->>'description',x->'data') ON CONFLICT(id) DO UPDATE SET activity_id=excluded.activity_id,"user"=excluded."user",start_time=excluded.start_time,end_time=excluded.end_time,title=excluded.title,description=excluded.description,data=excluded.data WHERE EXISTS(SELECT 1 FROM public.activities owner WHERE owner.id=public.activity_assignments.activity_id AND owner.occasion=p_occasion);
   GET DIAGNOSTICS changed=ROW_COUNT; IF changed<>1 THEN RAISE invalid_parameter_value USING MESSAGE='global assignment UUID collision'; END IF;
   DELETE FROM public.activity_assignment_places WHERE assignment_id=(x->>'id')::uuid;
   INSERT INTO public.activity_assignment_places(assignment_id,place_id) SELECT (x->>'id')::uuid,value::bigint FROM jsonb_array_elements_text(x->'linked_place_ids');
   DELETE FROM public.activity_assignment_events WHERE assignment_id=(x->>'id')::uuid;
   INSERT INTO public.activity_assignment_events(assignment_id,event_id) SELECT (x->>'id')::uuid,value::bigint FROM jsonb_array_elements_text(x->'linked_event_ids');
  END LOOP;
 END LOOP;
END $$;
-- G3 boundary: released raw graph writer remains a kernel bypass until contraction.
CREATE OR REPLACE FUNCTION public.update_activities(p_occasion_id bigint,p_activities_data jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.check_is_editor_on_occasion(p_occasion_id);
 PERFORM public.lock_group_occasion_internal_v1(p_occasion_id);
 PERFORM public.replace_activities_graph_internal_v1(p_occasion_id,p_activities_data);
 RETURN jsonb_build_object('code',200,'message','Activities saved successfully.');
END $$;
REVOKE ALL ON FUNCTION public.activity_time_internal_v1(text,bigint,boolean),public.normalize_activity_graph_internal_v1(bigint,jsonb,boolean,boolean),public.activity_history_graph_internal_v1(bigint,jsonb,boolean),public.activity_graph_history_internal_v1(jsonb),public.current_activity_graph_internal_v1(bigint),public.replace_activities_graph_internal_v1(bigint,jsonb) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.write_activity_history_internal_v1(p_occasion bigint,p_actor uuid,p_data jsonb,p_type text,p_parent bigint,p_note text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE hid bigint;
BEGIN
 IF p_type NOT IN ('AUTOSAVE','PUBLISH') OR (p_parent IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.activity_history WHERE id=p_parent AND occasion_id=p_occasion AND history_type='PUBLISH')) THEN RAISE invalid_parameter_value USING MESSAGE='invalid history parent or type'; END IF;
 IF p_type='AUTOSAVE' THEN PERFORM public.clear_activity_draft_internal_v1(p_occasion,p_actor,NULL,false); END IF;
 INSERT INTO public.activity_history(occasion_id,user_id,activities_data,history_type,note,parent_history_id) VALUES(p_occasion,p_actor,p_data,p_type,p_note,p_parent) RETURNING id INTO hid;
 RETURN hid;
END $$;
CREATE OR REPLACE FUNCTION public.clear_activity_draft_internal_v1(p_occasion bigint,p_actor uuid,p_parent bigint,p_check_parent boolean)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE n int;
BEGIN
 DELETE FROM public.activity_history WHERE occasion_id=p_occasion AND user_id=p_actor AND history_type='AUTOSAVE' AND (NOT p_check_parent OR parent_history_id IS NOT DISTINCT FROM p_parent);
 GET DIAGNOSTICS n=ROW_COUNT; RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.write_activity_history_internal_v1(bigint,uuid,jsonb,text,bigint,text),public.clear_activity_draft_internal_v1(bigint,uuid,bigint,boolean) FROM PUBLIC,anon,authenticated;
-- Exact released contracts remain callable until G3. Split legacy publish remains unsafe.
CREATE OR REPLACE FUNCTION public.save_activity_history(p_occasion_id bigint,p_activities_data jsonb,p_history_type text,p_parent_history_id bigint,p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE latest bigint; published_at timestamptz;
BEGIN
 IF NOT public.get_is_editor_on_occasion(p_occasion_id) THEN RETURN jsonb_build_object('code',403,'message','User is not authorized to edit this occasion'); END IF;
 PERFORM public.lock_activity_editor_internal_v1(p_occasion_id);
 SELECT id,created_at INTO latest,published_at FROM public.activity_history WHERE occasion_id=p_occasion_id AND history_type='PUBLISH' ORDER BY id DESC LIMIT 1;
 IF p_history_type='AUTOSAVE' AND p_parent_history_id IS DISTINCT FROM latest THEN RETURN jsonb_build_object('code',409,'message','A new version has been published. Please reload or rebase your changes.','data',jsonb_build_object('latest_publish_id',latest,'published_at',published_at)); END IF;
 PERFORM public.write_activity_history_internal_v1(p_occasion_id,auth.uid(),p_activities_data,p_history_type,p_parent_history_id,p_note);
 PERFORM public.retain_activity_history_internal_v1(p_occasion_id);
 RETURN jsonb_build_object('code',200,'message','History saved successfully.');
EXCEPTION WHEN others THEN RETURN jsonb_build_object('code',500,'message','Error saving history: '||SQLERRM);
END $$;
CREATE OR REPLACE FUNCTION public.delete_autosave_history(p_occasion_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF NOT public.get_is_editor_on_occasion(p_occasion_id) THEN RETURN jsonb_build_object('code',403,'message','User is not authorized'); END IF;
 PERFORM public.lock_activity_editor_internal_v1(p_occasion_id);
 PERFORM public.clear_activity_draft_internal_v1(p_occasion_id,auth.uid(),NULL,false);
 RETURN jsonb_build_object('code',200,'message','Autosave history has been cleared successfully.');
END $$;

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

CREATE OR REPLACE FUNCTION public.get_activity_editor_session_v1(p_occasion bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT CASE WHEN auth.uid() IS NULL OR NOT (public.get_is_editor_view_on_occasion(p_occasion) OR public.get_is_editor_on_occasion(p_occasion)) THEN jsonb_build_object('code',403) ELSE
 jsonb_build_object('code',200,'liveVersion',COALESCE((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='activities' AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_occasion::text),0),
 'latestPublishId',(SELECT id FROM public.activity_history WHERE occasion_id=p_occasion AND history_type='PUBLISH' ORDER BY id DESC LIMIT 1),
 'draftId',d.id,'draftParentHistoryId',d.parent_history_id,'draftData',CASE WHEN d.id IS NOT NULL THEN public.activity_graph_history_internal_v1(public.activity_history_graph_internal_v1(p_occasion,d.activities_data,false)) ELSE NULL END,
 'editBundle',jsonb_build_object(
 'events',COALESCE((SELECT jsonb_agg(to_jsonb(e) ORDER BY e.id) FROM public.events e WHERE e.occasion=p_occasion),'[]'),
 'places',COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p."order",p.id) FROM public.places p WHERE p.occasion=p_occasion),'[]'),
 'activities',COALESCE((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.id) FROM public.activities a WHERE a.occasion=p_occasion),'[]'),
 'activity_assignments',COALESCE((SELECT jsonb_agg(to_jsonb(x) ORDER BY x.id) FROM public.activity_assignments x JOIN public.activities a ON a.id=x.activity_id WHERE a.occasion=p_occasion),'[]'),
 'assignment_place_links',COALESCE((SELECT jsonb_agg(to_jsonb(l)) FROM public.activity_assignment_places l JOIN public.activity_assignments x ON x.id=l.assignment_id JOIN public.activities a ON a.id=x.activity_id WHERE a.occasion=p_occasion),'[]'),
 'assignment_event_links',COALESCE((SELECT jsonb_agg(to_jsonb(l)) FROM public.activity_assignment_events l JOIN public.activity_assignments x ON x.id=l.assignment_id JOIN public.activities a ON a.id=x.activity_id WHERE a.occasion=p_occasion),'[]'),
 'user_info',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',u.id,'name',u.name,'surname',u.surname,'sex',u.sex,'email',u.email_readonly)) FROM public.user_info u JOIN public.occasion_users ou ON ou."user"=u.id WHERE ou.occasion=p_occasion AND (ou.data->>'is_volunteer')::boolean),'[]'))) END
 FROM (SELECT 1) root LEFT JOIN LATERAL (SELECT id,parent_history_id,activities_data FROM public.activity_history WHERE occasion_id=p_occasion AND user_id=auth.uid() AND history_type='AUTOSAVE' ORDER BY id DESC LIMIT 1) d ON true;
$$;
REVOKE ALL ON FUNCTION public.get_activity_editor_session_v1(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_activity_editor_session_v1(bigint) TO authenticated;
CREATE OR REPLACE FUNCTION public.get_latest_autosave(p_occasion_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE
    autosave_record JSONB;
    v_latest_publish_id BIGINT;
BEGIN
 IF auth.uid() IS NULL OR NOT public.get_is_editor_view_on_occasion(p_occasion_id) THEN RETURN jsonb_build_object('code',403); END IF;
    -- Select the single latest autosave record for the current user
    SELECT jsonb_build_object(
        'id', id,
        'created_at', created_at,
        'activities_data', activities_data,
        'parent_history_id', parent_history_id
    )
    INTO autosave_record
    FROM public.activity_history
    WHERE occasion_id = p_occasion_id
      AND user_id = auth.uid()
      AND history_type = 'AUTOSAVE'
    ORDER BY created_at DESC
    LIMIT 1;

    -- Separately, find the ID of the absolute latest published version for the occasion
    SELECT id
    INTO v_latest_publish_id
    FROM public.activity_history
    WHERE occasion_id = p_occasion_id
      AND history_type = 'PUBLISH'
    ORDER BY created_at DESC
    LIMIT 1;

    -- Return an object containing both the autosave data (if found) and the latest publish ID (if found)
    RETURN jsonb_build_object(
        'code', 200,
        'message', 'Autosave and publish info retrieved.',
        'data', jsonb_build_object(
            'autosave', autosave_record,
            'latest_publish_id', v_latest_publish_id
        )
    );
END;
$function$
;
CREATE OR REPLACE FUNCTION public.get_activity_history_version(p_history_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE
    v_occasion_id BIGINT;
    history_data JSONB;
BEGIN
    SELECT occasion_id INTO v_occasion_id FROM public.activity_history WHERE id = p_history_id AND (history_type<>'AUTOSAVE' OR user_id=auth.uid());

    IF v_occasion_id IS NULL OR (SELECT get_is_editor_on_occasion(v_occasion_id)) <> TRUE THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to view this history version');
    END IF;

    -- Select the single history record into a JSON object
    SELECT jsonb_build_object(
        'id', id,
        'created_at', created_at,
        'activities_data', public.activity_graph_history_internal_v1(public.activity_history_graph_internal_v1(v_occasion_id,activities_data,false)),
        'parent_history_id', parent_history_id
    )
    INTO history_data
    FROM public.activity_history
    WHERE id = p_history_id AND (history_type<>'AUTOSAVE' OR user_id=auth.uid());

    -- Return the object wrapped in a standard response
    RETURN jsonb_build_object(
        'code', 200,
        'message', 'History version retrieved.',
        'data', history_data
    );
END;
$function$
;
CREATE OR REPLACE FUNCTION public.list_activity_history(p_occasion_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
DECLARE
    history_data JSONB;
BEGIN
    IF (SELECT get_is_editor_on_occasion(p_occasion_id)) <> TRUE THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to view history');
    END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', h.id,
        'created_at', h.created_at,
        'history_type', h.history_type,
        'note', h.note,
        'user_name', u.name,
        'user_surname', u.surname
    ) ORDER BY h.created_at DESC), '[]'::jsonb)
    INTO history_data
    FROM public.activity_history h
    LEFT JOIN public.user_info u ON h.user_id = u.id
    WHERE h.occasion_id = p_occasion_id AND (h.history_type <> 'AUTOSAVE' OR (h.history_type = 'AUTOSAVE' AND h.user_id = auth.uid()));

    RETURN jsonb_build_object(
        'code', 200,
        'message', 'History retrieved successfully',
        'data', history_data
    );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.remove_user_activity_internal_v1(p_occasion bigint,p_users uuid[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE impacted uuid[]; n int; impacts jsonb;
BEGIN
 PERFORM public.lock_activity_aggregate_internal_v1(p_occasion);
 SELECT ARRAY(SELECT DISTINCT aa."user" FROM public.activity_assignments aa JOIN public.activities a ON a.id=aa.activity_id WHERE a.occasion=p_occasion) INTO impacted;
 DELETE FROM public.activity_assignments aa USING public.activities a WHERE a.id=aa.activity_id AND a.occasion=p_occasion AND aa."user"=ANY(p_users);
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n=0 THEN RETURN '[]'; END IF;
 UPDATE public.client_aggregate_versions SET version=version+1,updated_at=clock_timestamp() WHERE aggregate_type='activities' AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_occasion::text;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_activity','userId',id) ORDER BY id),'[]') INTO impacts FROM unnest(impacted) id JOIN public.occasion_users ou ON ou.occasion=p_occasion AND ou."user"=id WHERE NOT id=ANY(p_users);
 RETURN impacts;
END $$;
REVOKE ALL ON FUNCTION public.remove_user_activity_internal_v1(bigint,uuid[]) FROM PUBLIC,anon,authenticated;

-- One occasion-user teardown handler. Authorization and receipt belong to its callers.
CREATE OR REPLACE FUNCTION public.remove_occasion_user_domain_internal_v1(p_occasion bigint,p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE groups bigint[]; impacts jsonb;
BEGIN
 PERFORM public.lock_activity_aggregate_internal_v1(p_occasion);
 SELECT COALESCE(array_agg(g.id),'{}') INTO groups FROM public.user_groups ug JOIN public.user_group_info g ON g.id=ug."group" WHERE ug."user"=p_user AND g.occasion=p_occasion;
 impacts:=public.group_profile_impacts_internal_v1(p_occasion,ARRAY(SELECT "user" FROM public.user_groups WHERE "group"=ANY(groups))||ARRAY[p_user]);
 impacts:=(SELECT COALESCE(jsonb_agg(x),'[]') FROM jsonb_array_elements(impacts) x WHERE x->>'userId'<>p_user::text)||public.remove_user_activity_internal_v1(p_occasion,ARRAY[p_user]);
 UPDATE public.news SET created_by=NULL WHERE created_by=p_user AND occasion=p_occasion;
 DELETE FROM public.user_groups WHERE "user"=p_user AND "group"=ANY(groups);
 UPDATE public.client_aggregate_versions SET version=version+1,updated_at=clock_timestamp() WHERE aggregate_type='user_group' AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=ANY(ARRAY(SELECT id::text FROM unnest(groups) id));
 DELETE FROM public.event_users WHERE "user"=p_user AND event IN(SELECT id FROM public.events WHERE occasion=p_occasion);
 DELETE FROM public.event_users_saved WHERE "user"=p_user AND event IN(SELECT id FROM public.events WHERE occasion=p_occasion);
 DELETE FROM public.user_news WHERE "user"=p_user AND occasion=p_occasion;
 DELETE FROM public.occasion_users WHERE "user"=p_user AND occasion=p_occasion;
 DELETE FROM public.client_sync_private_scopes WHERE occasion=p_occasion AND user_id=p_user;
 DELETE FROM public.client_aggregate_versions WHERE aggregate_type='occasion_user' AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=p_user::text;
 RETURN impacts;
END $$;
REVOKE ALL ON FUNCTION public.remove_occasion_user_domain_internal_v1(bigint,uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.import_user_group_assignments_internal_v1(
    p_occasion_id bigint,
    p_assignments jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_assignment record;
    v_group_id bigint;
    v_group_title text;
    v_keep_admin boolean;
    v_unit_id bigint;
BEGIN
    SELECT o.unit INTO v_unit_id
    FROM public.occasions o
    WHERE o.id = p_occasion_id;

    IF v_unit_id IS NULL THEN
        RAISE EXCEPTION 'OCCASION_NOT_FOUND';
    END IF;

    IF NOT (
        public.get_is_editor_on_occasion(p_occasion_id)
        OR public.get_is_manager_on_occasion(p_occasion_id)
        OR public.get_is_admin_on_occasion(p_occasion_id)
        OR public.get_is_editor_on_unit(v_unit_id)
    ) THEN
        RAISE EXCEPTION 'NOT_AUTHORIZED';
    END IF;

    IF COALESCE(jsonb_typeof(p_assignments), 'null') <> 'array' THEN
        RAISE EXCEPTION 'INVALID_ASSIGNMENTS';
    END IF;

    -- Serialize imports for one occasion so normalized group titles cannot be
    -- created twice by concurrent CSV imports.
    PERFORM pg_catalog.pg_advisory_xact_lock(p_occasion_id);

    FOR v_assignment IN
        SELECT assignment.user_id, assignment.group_title
        FROM jsonb_to_recordset(p_assignments)
            AS assignment(user_id uuid, group_title text)
    LOOP
        IF v_assignment.user_id IS NULL OR NOT EXISTS (
            SELECT 1
            FROM public.occasion_users ou
            WHERE ou.occasion = p_occasion_id
              AND ou."user" = v_assignment.user_id
        ) THEN
            RAISE EXCEPTION 'USER_NOT_ON_OCCASION';
        END IF;

        v_group_title := NULLIF(btrim(v_assignment.group_title), '');
        v_group_id := NULL;
        v_keep_admin := false;

        IF v_group_title IS NOT NULL THEN
            SELECT ugi.id
            INTO v_group_id
            FROM public.user_group_info ugi
            WHERE ugi.occasion = p_occasion_id
              AND ugi.type IS NULL
              AND lower(btrim(ugi.title)) = lower(v_group_title)
            ORDER BY ugi.id
            LIMIT 1;

            IF v_group_id IS NULL THEN
                INSERT INTO public.user_group_info (occasion, title)
                VALUES (p_occasion_id, v_group_title)
                RETURNING id INTO v_group_id;
            ELSE
                SELECT COALESCE(ug.is_admin, false)
                INTO v_keep_admin
                FROM public.user_groups ug
                WHERE ug."user" = v_assignment.user_id
                  AND ug."group" = v_group_id;

                v_keep_admin := COALESCE(v_keep_admin, false);
            END IF;
        END IF;

        DELETE FROM public.user_groups ug
        USING public.user_group_info ugi
        WHERE ug."group" = ugi.id
          AND ug."user" = v_assignment.user_id
          AND ugi.occasion = p_occasion_id
          AND ugi.type IS NULL;

        IF v_group_id IS NOT NULL THEN
            INSERT INTO public.user_groups ("user", "group", is_admin)
            VALUES (v_assignment.user_id, v_group_id, v_keep_admin);
        END IF;
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.import_user_group_assignments(
    p_occasion_id bigint,
    p_assignments jsonb
) RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public, extensions AS $$
  SELECT public.import_user_group_assignments_internal_v1(
    p_occasion_id,p_assignments);
$$;

REVOKE ALL ON FUNCTION public.import_user_group_assignments_internal_v1(bigint,jsonb) FROM PUBLIC,anon,authenticated;

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
CREATE OR REPLACE FUNCTION public.import_occasion_users_from_csv_internal_v1(p_occasion_id bigint, p_rows jsonb, p_delete_user_ids jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
    PERFORM public.validate_occasion_user_csv_import_v1(
        p_occasion_id, p_rows, p_delete_user_ids);
    RETURN public.import_occasion_users_from_csv_apply_v1(
        p_occasion_id, p_rows, p_delete_user_ids);
END;
$function$
;
REVOKE ALL ON FUNCTION public.import_occasion_users_from_csv_apply_v1(bigint,jsonb,jsonb),public.import_occasion_users_from_csv_internal_v1(bigint,jsonb,jsonb) FROM PUBLIC,anon,authenticated;
-- Released G3 compatibility facade; current callers use import_profiles_client_sync_v1.
CREATE OR REPLACE FUNCTION public.import_occasion_users_from_csv(p_occasion_id bigint,p_rows jsonb,p_delete_user_ids jsonb DEFAULT '[]'::jsonb)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
SELECT public.import_occasion_users_from_csv_internal_v1(p_occasion_id,p_rows,p_delete_user_ids);
$$;

CREATE OR REPLACE FUNCTION public.profile_group_import_state_internal_v1(p_occasion bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('profiles',COALESCE((SELECT jsonb_agg(jsonb_build_object('membership',to_jsonb(ou)-'created_at'-'updated_at','profile',to_jsonb(ui)-'created_at'-'updated_at') ORDER BY ou."user") FROM public.occasion_users ou JOIN public.user_info ui ON ui.id=ou."user" WHERE ou.occasion=p_occasion),'[]'),'groups',COALESCE((SELECT jsonb_object_agg(g.id,public.get_user_group_command_data_v1(g.id)-'aggregate_version') FROM public.user_group_info g WHERE g.occasion=p_occasion),'{}'));
$$;
REVOKE ALL ON FUNCTION public.profile_group_import_state_internal_v1(bigint) FROM PUBLIC,anon,authenticated;
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
  v_publishable boolean; v_actor_replacements jsonb:='[]'::jsonb; v_before_state jsonb; v_after_state jsonb; v_old_impacts jsonb;
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
  PERFORM public.lock_activity_aggregate_internal_v1(p_occasion);
  IF NOT (public.get_is_manager_on_occasion(p_occasion) OR public.get_is_admin_on_occasion(p_occasion) OR public.get_is_editor_on_unit(v_unit)) THEN RAISE insufficient_privilege USING MESSAGE='profile import permission required'; END IF;
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(p_occasion);
  PERFORM 1 FROM public.user_group_info g WHERE g.occasion=p_occasion
    ORDER BY g.id FOR UPDATE;
  v_before_state:=public.profile_group_import_state_internal_v1(p_occasion);
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
  v_old_impacts:=public.group_profile_impacts_internal_v1(p_occasion,ARRAY(
    SELECT DISTINCT id FROM (
      SELECT value::uuid id FROM jsonb_array_elements_text(p_delete_user_ids)
      UNION SELECT ug."user" FROM public.user_groups ug WHERE ug."group"=ANY(v_group_ids)
      UNION SELECT ou."user" FROM public.occasion_users ou JOIN public.user_info ui ON ui.id=ou."user" WHERE ou.occasion=p_occasion AND (ou."user"=ANY(ARRAY(SELECT (row->>'user_id')::uuid FROM jsonb_array_elements(p_rows) row WHERE NULLIF(row->>'user_id','') IS NOT NULL)) OR lower(btrim(ui.email_readonly))=ANY(ARRAY(SELECT lower(btrim(row#>>'{data,email}')) FROM jsonb_array_elements(p_rows) row)))
    ) impacted));
  v_private_impacts:=public.remove_user_activity_internal_v1(p_occasion,ARRAY(SELECT value::uuid FROM jsonb_array_elements_text(p_delete_user_ids)));
  v_result:=public.import_occasion_users_from_csv_internal_v1(
    p_occasion,p_rows,p_delete_user_ids);
  IF COALESCE((v_result->>'code')::integer,500)<>200 THEN
    RAISE data_exception USING MESSAGE=COALESCE(v_result->>'message','profile import failed');
  END IF;
  v_after_state:=public.profile_group_import_state_internal_v1(p_occasion);
  IF v_before_state=v_after_state THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'unchanged',200,v_result); END IF;
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
  SELECT 'user_group','occasion',p_occasion,key,1 FROM jsonb_each(v_after_state->'groups') WHERE value IS DISTINCT FROM v_before_state->'groups'->key
  ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,
      updated_at=clock_timestamp();
  DELETE FROM public.client_aggregate_versions v WHERE v.aggregate_type='occasion_user'
    AND v.scope_type='occasion' AND v.scope_id=p_occasion
    AND v.aggregate_id=ANY(ARRAY(SELECT value FROM jsonb_array_elements_text(
      p_delete_user_ids)));
  v_private_impacts:=v_private_impacts||v_old_impacts||public.group_profile_impacts_internal_v1(p_occasion,v_current_users);
  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'component',x->>'userId'),'[]') INTO v_private_impacts FROM (SELECT DISTINCT value x FROM jsonb_array_elements(v_private_impacts) WHERE EXISTS(SELECT 1 FROM public.occasion_users WHERE occasion=p_occasion AND "user"=(value->>'userId')::uuid)) current_impacts;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_private_impacts) x WHERE x->>'component'='private_profile' AND x->>'userId'=v_actor::text) THEN v_actor_replacements:=jsonb_build_array(
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
  PERFORM public.lock_activity_aggregate_internal_v1(p_occasion);
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
  v_private_impacts:=public.remove_occasion_user_domain_internal_v1(p_occasion,p_user);
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
  PERFORM public.lock_activity_aggregate_internal_v1(p_occasion);
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
  v_private_impacts:=v_private_impacts||public.remove_user_activity_internal_v1(p_occasion,ARRAY[p_companion]);
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
  FOR v_occasion IN SELECT DISTINCT dependency.occasion FROM (
 SELECT occasion FROM public.occasion_users WHERE "user"=p_user
 UNION SELECT gi.occasion FROM public.user_groups g JOIN public.user_group_info gi ON gi.id=g."group" WHERE g."user"=p_user
 UNION SELECT a.occasion FROM public.activity_assignments x JOIN public.activities a ON a.id=x.activity_id WHERE x."user"=p_user
 UNION SELECT occasion_id FROM public.activity_history WHERE user_id=p_user
) dependency JOIN public.occasions o ON o.id=dependency.occasion WHERE o.organization=p_organization ORDER BY dependency.occasion LOOP
    PERFORM public.lock_activity_aggregate_internal_v1(v_occasion);
  END LOOP;
  INSERT INTO public.client_commits
    (organization,actor_id,actor_display,actor_kind,source,change_class,reason)
  VALUES (p_organization,p_user,NULL,'service','account.delete','profile',
    'confirmed account deletion') RETURNING * INTO v_commit;
  INSERT INTO public.client_commit_items
    (commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields)
  VALUES (v_commit.commit_id,0,'user',p_user::text,'delete',NULL,
    ARRAY['membership','profile','private_data']);
  FOR v_occasion IN SELECT DISTINCT dependency.occasion FROM (
 SELECT occasion FROM public.occasion_users WHERE "user"=p_user
 UNION SELECT gi.occasion FROM public.user_groups g JOIN public.user_group_info gi ON gi.id=g."group" WHERE g."user"=p_user
 UNION SELECT a.occasion FROM public.activity_assignments x JOIN public.activities a ON a.id=x.activity_id WHERE x."user"=p_user
 UNION SELECT occasion_id FROM public.activity_history WHERE user_id=p_user
) dependency JOIN public.occasions o ON o.id=dependency.occasion WHERE o.organization=p_organization ORDER BY dependency.occasion LOOP
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
    IF EXISTS(SELECT 1 FROM public.activity_assignments aa JOIN public.activities a ON a.id=aa.activity_id WHERE a.occasion=v_occasion AND aa."user"=p_user) OR EXISTS(SELECT 1 FROM public.activity_history WHERE occasion_id=v_occasion AND user_id=p_user AND history_type='PUBLISH') THEN
      UPDATE public.client_aggregate_versions SET version=version+1,updated_at=clock_timestamp() WHERE aggregate_type='activities' AND scope_type='occasion' AND scope_id=v_occasion AND aggregate_id=v_occasion::text;
      FOR v_member IN SELECT "user" FROM public.occasion_users WHERE occasion=v_occasion AND "user"<>p_user ORDER BY "user" LOOP
        INSERT INTO public.client_sync_private_scopes(component,occasion,user_id,source_revision) VALUES('private_activity',v_occasion,v_member,1) ON CONFLICT(component,occasion,user_id) DO UPDATE SET source_revision=public.client_sync_private_scopes.source_revision+1,updated_at=clock_timestamp() RETURNING source_revision INTO v_revision;
        INSERT INTO public.client_commit_components(commit_id,component,scope_type,scope_id,user_id,resulting_revision) VALUES(v_commit.commit_id,'private_activity','occasion',v_occasion,v_member,v_revision);
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

-- Released G3 boundary. Current UI uses the version-bearing typed command.
CREATE OR REPLACE FUNCTION public.delete_occasion_user(usr uuid,oc bigint)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 IF NOT(public.get_is_manager_on_occasion(oc) OR public.get_is_admin_on_occasion(oc)) THEN RAISE insufficient_privilege USING MESSAGE='occasion manager required'; END IF;
 PERFORM public.remove_occasion_user_domain_internal_v1(oc,usr);
END $$;

CREATE OR REPLACE FUNCTION public.delete_occasion_user_ws(usr_to_delete uuid, occasion_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    IF NOT (public.get_is_manager_on_occasion(occasion_id)
        OR public.get_is_admin_on_occasion(occasion_id)) THEN
        RAISE insufficient_privilege USING MESSAGE='occasion manager required';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.occasion_users ou
        WHERE ou.occasion=occasion_id AND ou."user"=usr_to_delete) THEN
        RAISE invalid_parameter_value USING MESSAGE='target is not an occasion member';
    END IF;
    PERFORM public.remove_occasion_user_domain_internal_v1(occasion_id,usr_to_delete);
END;
$$;

REVOKE ALL ON FUNCTION public.delete_occasion_user_ws(uuid,bigint)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_occasion_user_ws(uuid,bigint)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.import_users_from_tickets(p_occasion_id bigint)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    ticket_record RECORD;
    order_data JSONB;
    user_email TEXT;
    v_sign_in_email TEXT;
    user_name TEXT;
    user_surname TEXT;
    user_sex TEXT;
    user_data JSONB;
    v_user_id UUID;
    v_organization_id BIGINT;
    field_element JSONB;
    field_key TEXT;

    field_info RECORD;
    field_value TEXT;
    v_text1 TEXT;
    v_text2 TEXT;
    v_birthDate TEXT;

    v_occasion_user_row public.occasion_users%ROWTYPE;
    new_email TEXT;

    -- Arrays to store results
    inserted_users JSONB[] := ARRAY[]::JSONB[];
    updated_users JSONB[] := ARRAY[]::JSONB[];
    deleted_users JSONB[] := ARRAY[]::JSONB[];

    storno_record RECORD;
    deleted_user_info RECORD;
    update_report_info RECORD;
BEGIN
    PERFORM public.lock_activity_aggregate_internal_v1(p_occasion_id);
    -- 1. Get the organization_id from the occasion
    SELECT organization INTO v_organization_id FROM public.occasions WHERE id = p_occasion_id;

    IF v_organization_id IS NULL THEN
        RAISE EXCEPTION 'Occasion with id % not found or has no organization.', p_occasion_id;
    END IF;

    -- 2. Handle Storno (Canceled) Tickets
    FOR storno_record IN
        SELECT ou."user", ou.ticket
        FROM public.occasion_users ou
        JOIN eshop.tickets t ON ou.ticket = t.id
        WHERE ou.occasion = p_occasion_id
          AND ou.ticket IS NOT NULL
          AND t.state = 'storno'
    LOOP
        SELECT ui.email_readonly, ui.name, ui.surname
        INTO deleted_user_info
        FROM public.user_info ui
        WHERE ui.id = storno_record."user";

        PERFORM public.remove_occasion_user_domain_internal_v1(p_occasion_id,storno_record."user");

        deleted_users := array_append(deleted_users,
            jsonb_build_object(
                'email', deleted_user_info.email_readonly,
                'name', deleted_user_info.name,
                'surname', deleted_user_info.surname,
                'ticket_id', storno_record.ticket
            )
        );
    END LOOP;

    -- 3. IMPORT & SYNC LOGIC
    FOR ticket_record IN
        SELECT DISTINCT ON (t.id)
            t.id as ticket_id,
            o.data as order_data,
            ou."user" as existing_occasion_user_id
        FROM eshop.tickets t
        JOIN eshop.order_product_ticket opt ON t.id = opt.ticket
        JOIN eshop.orders o ON opt."order" = o.id
        LEFT JOIN public.occasion_users ou ON t.id = ou.ticket
        WHERE t.occasion = p_occasion_id
          AND t.state IN ('ordered', 'sent', 'used', 'paid')
        ORDER BY t.id, o.id DESC
    LOOP
        order_data := ticket_record.order_data;
        user_email := lower(trim(order_data->>'email'));
        user_name := order_data->>'name';
        user_surname := order_data->>'surname';
        user_sex := NULL;

        v_text1 := NULL;
        v_text2 := NULL;
        v_birthDate := NULL;

        -- Extract Form Fields (Generic loop, checking specifically for known titles)
        IF jsonb_typeof(order_data->'fields') = 'array' THEN
            FOR field_element IN SELECT * FROM jsonb_array_elements(order_data->'fields')
            LOOP
                field_key := (SELECT * FROM jsonb_object_keys(field_element));
                field_value := field_element->>field_key;

                SELECT ff.type, ff.title
                INTO field_info
                FROM public.form_fields ff
                WHERE ff.id = field_key::bigint;

                -- Basic mappings
                IF field_info.type = 'sex' THEN
                    user_sex := field_value;
                END IF;

--                -- Custom mappings (removed IF ID=36 check to make it generic for the feature)
--                CASE field_info.title
--                    WHEN 'Typ účastníka' THEN
--                        v_text1 := field_value;
--                    WHEN 'Přípravný tým' THEN
--                        v_text2 := field_value;
--                    WHEN 'Datum narození' THEN
--                        v_birthDate := field_value;
--                    ELSE
--                        -- Do nothing
--                END CASE;
            END LOOP;
        END IF;

        -- ========================================================
        -- CASE A: EXISTING OCCASION USER -> UPDATE BY ID
        -- ========================================================
        IF ticket_record.existing_occasion_user_id IS NOT NULL THEN
            DECLARE
                current_ou_data JSONB;
                update_payload JSONB := '{}'::jsonb;
                target_uuid UUID := ticket_record.existing_occasion_user_id; -- STRICT ID DEPENDENCY
            BEGIN
                SELECT ui.email_readonly
                  INTO v_sign_in_email
                  FROM public.user_info ui
                 WHERE ui.id = target_uuid;

                -- Get current occasion data
                SELECT data INTO current_ou_data
                FROM public.occasion_users
                WHERE "user" = target_uuid AND occasion = p_occasion_id;

                -- Build payload comparing Order Data vs Current DB Data
                IF v_sign_in_email IS NOT NULL AND COALESCE(current_ou_data->>'email', 'NULL_FLAG') != v_sign_in_email THEN
                    update_payload := update_payload || jsonb_build_object('email', v_sign_in_email);
                END IF;
                IF user_name IS NOT NULL AND COALESCE(current_ou_data->>'name', 'NULL_FLAG') != user_name THEN
                    update_payload := update_payload || jsonb_build_object('name', user_name);
                END IF;
                IF user_surname IS NOT NULL AND COALESCE(current_ou_data->>'surname', 'NULL_FLAG') != user_surname THEN
                    update_payload := update_payload || jsonb_build_object('surname', user_surname);
                END IF;
                IF user_sex IS NOT NULL AND COALESCE(current_ou_data->>'sex', 'NULL_FLAG') != user_sex THEN
                    update_payload := update_payload || jsonb_build_object('sex', user_sex);
                END IF;
                -- Custom fields
--                IF v_text1 IS NOT NULL AND COALESCE(current_ou_data->>'text1', 'NULL_FLAG') != v_text1 THEN
--                    update_payload := update_payload || jsonb_build_object('text1', v_text1);
--                END IF;
--                IF v_text2 IS NOT NULL AND COALESCE(current_ou_data->>'text2', 'NULL_FLAG') != v_text2 THEN
--                    update_payload := update_payload || jsonb_build_object('text2', v_text2);
--                END IF;
--                IF v_birthDate IS NOT NULL AND COALESCE(current_ou_data->>'birthDate', 'NULL_FLAG') != v_birthDate THEN
--                    update_payload := update_payload || jsonb_build_object('birthDate', v_birthDate);
--                END IF;

                -- Perform Updates if needed
                IF update_payload != '{}'::jsonb THEN
                    -- 1. Update Occasion Specific Data
                    UPDATE public.occasion_users
                    SET data = data || update_payload
                    WHERE "user" = target_uuid
                      AND occasion = p_occasion_id;

                    -- 2. Update Global User Info (Sync core fields)
                    UPDATE public.user_info
                    SET
                        name = COALESCE(update_payload->>'name', name),
                        surname = COALESCE(update_payload->>'surname', surname),
                        sex = COALESCE(update_payload->>'sex', sex)
                    WHERE id = target_uuid;

                    -- Logging
                    SELECT ui.email_readonly, ui.name, ui.surname
                    INTO update_report_info
                    FROM public.user_info ui
                    WHERE ui.id = target_uuid;

                    updated_users := array_append(updated_users,
                        jsonb_build_object(
                            'id', target_uuid, -- Return ID for safety
                            'email', update_report_info.email_readonly,
                            'name', update_report_info.name,
                            'surname', update_report_info.surname,
                            'reason', 'data_sync',
                            'changes', update_payload
                        )
                    );
                END IF;
            END;

        -- ========================================================
        -- CASE B: NO LINKED USER -> CREATE OR LINK (FALLBACK TO EMAIL)
        -- ========================================================
        ELSE
            -- 1. Check if user exists globally by email
            SELECT id INTO v_user_id
            FROM public.user_info
            WHERE email_readonly = user_email AND organization = v_organization_id;

            IF v_user_id IS NOT NULL THEN
                -- USER EXISTS GLOBALLY
                SELECT * INTO v_occasion_user_row
                FROM public.occasion_users
                WHERE "user" = v_user_id AND occasion = p_occasion_id;

                IF v_occasion_user_row."user" IS NOT NULL AND v_occasion_user_row.ticket IS NOT NULL THEN
                    -- User exists on occasion AND has a ticket -> DUPLICATE EMAIL Conflict
                    -- Create new user with +suffix
                    new_email := public.allocate_user_sign_in_email(
                        v_organization_id, user_email
                    );

                    user_data := jsonb_build_object('name', user_name, 'surname', user_surname, 'email', new_email, 'sex', user_sex);
--                    IF v_text1 IS NOT NULL THEN user_data := user_data || jsonb_build_object('text1', v_text1); END IF;
--                    IF v_text2 IS NOT NULL THEN user_data := user_data || jsonb_build_object('text2', v_text2); END IF;
--                    IF v_birthDate IS NOT NULL THEN user_data := user_data || jsonb_build_object('birthDate', v_birthDate); END IF;

                    v_user_id := create_user_in_organization_with_data_pure(
                        v_organization_id, new_email, user_email,
                        gen_random_uuid()::text, user_data
                    );
                    PERFORM public.add_user_to_occasion_internal_v1(p_occasion_id, v_user_id);
                    UPDATE public.occasion_users SET ticket = ticket_record.ticket_id WHERE "user" = v_user_id AND occasion = p_occasion_id;

                    inserted_users := array_append(inserted_users, jsonb_build_object('id', v_user_id, 'email', new_email, 'name', user_name, 'surname', user_surname));
                ELSE
                    -- LINK EXISTING USER (User exists, but no ticket on this occasion)

                    user_data := jsonb_build_object('name', user_name, 'surname', user_surname, 'email', user_email, 'sex', user_sex);
--                    IF v_text1 IS NOT NULL THEN user_data := user_data || jsonb_build_object('text1', v_text1); END IF;
--                    IF v_text2 IS NOT NULL THEN user_data := user_data || jsonb_build_object('text2', v_text2); END IF;
--                    IF v_birthDate IS NOT NULL THEN user_data := user_data || jsonb_build_object('birthDate', v_birthDate); END IF;

                    -- Update Global Info
                    UPDATE public.user_info
                    SET
                        name = user_name,
                        surname = user_surname,
                        sex = user_sex,
                        data = COALESCE(user_info.data, '{}'::jsonb) || user_data
                    WHERE id = v_user_id;

                    IF v_occasion_user_row."user" IS NULL THEN
                        -- Link to occasion
                        PERFORM public.add_user_to_occasion_internal_v1(p_occasion_id, v_user_id);
                    END IF;

                    -- Update Occasion Data & Ticket
                    UPDATE public.occasion_users
                    SET
                        data = COALESCE(occasion_users.data, '{}'::jsonb) || user_data,
                        ticket = ticket_record.ticket_id
                    WHERE "user" = v_user_id AND occasion = p_occasion_id;

                    updated_users := array_append(updated_users, jsonb_build_object('id', v_user_id, 'email', user_email, 'name', user_name, 'surname', user_surname, 'reason', 'initial_import_link'));
                END IF;
            ELSE
                -- NEW USER CREATION
                user_data := jsonb_build_object('name', user_name, 'surname', user_surname, 'email', user_email, 'sex', user_sex);
--                IF v_text1 IS NOT NULL THEN user_data := user_data || jsonb_build_object('text1', v_text1); END IF;
--                IF v_text2 IS NOT NULL THEN user_data := user_data || jsonb_build_object('text2', v_text2); END IF;
--                IF v_birthDate IS NOT NULL THEN user_data := user_data || jsonb_build_object('birthDate', v_birthDate); END IF;

                v_user_id := create_user_in_organization_with_data_pure(
                    v_organization_id, user_email, user_email,
                    gen_random_uuid()::text, user_data
                );
                PERFORM public.add_user_to_occasion_internal_v1(p_occasion_id, v_user_id);
                UPDATE public.occasion_users SET ticket = ticket_record.ticket_id WHERE "user" = v_user_id AND occasion = p_occasion_id;

                inserted_users := array_append(inserted_users, jsonb_build_object('id', v_user_id, 'email', user_email, 'name', user_name, 'surname', user_surname));
            END IF;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'inserted', to_jsonb(inserted_users),
        'updated', to_jsonb(updated_users),
        'deleted', to_jsonb(deleted_users)
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.import_users_from_tickets_client_sync_v1(p_occasion bigint, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_begin jsonb; v_hash text; v_result jsonb;
  v_before_users uuid[];
BEGIN
  IF v_actor IS NULL OR NOT public.get_is_editor_on_occasion(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',p_occasion)::text,'UTF8'),'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'profile.tickets.import',p_occasion,v_actor,v_hash);
  PERFORM public.lock_activity_aggregate_internal_v1(p_occasion);
  IF NOT public.get_is_editor_on_occasion(p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
    FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
  v_result:=public.import_users_from_tickets_ws_internal_v1(p_occasion);
  RETURN public.complete_profile_inventory_membership_mutation_v1(
    p_command_id,p_occasion,'profile.tickets.import',jsonb_build_array(jsonb_build_object(
      'entityType','occasion_user','entityId',NULL,'operation','import',
      'safeLabel','Ticket profile import','changedFields',jsonb_build_array(
        'profile','ticket','membership'))),v_before_users,v_result);
END; $function$

;

CREATE OR REPLACE FUNCTION public.complete_profile_inventory_membership_mutation_v1(p_command_id uuid, p_occasion bigint, p_source text, p_items jsonb, p_before_users uuid[], p_data jsonb, p_actor_kind text DEFAULT 'user'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_actor uuid:=auth.uid(); v_after_users uuid[]; v_removed uuid[];
  v_impacts jsonb; v_replacements jsonb:='[]'::jsonb;
  v_public text[]:='{}'; v_dirty jsonb:='[]'::jsonb;
BEGIN
  SELECT COALESCE(array_agg(ou."user"),'{}'::uuid[]) INTO v_after_users
    FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
  SELECT ARRAY(SELECT id FROM unnest(COALESCE(p_before_users,'{}')) id
    WHERE NOT id=ANY(v_after_users)) INTO v_removed;
  DELETE FROM public.client_sync_private_scopes s WHERE s.occasion=p_occasion
    AND s.user_id=ANY(v_removed);
  DELETE FROM public.client_aggregate_versions v
    WHERE v.aggregate_type='occasion_user' AND v.scope_type='occasion'
      AND v.scope_id=p_occasion AND v.aggregate_id=ANY(
        ARRAY(SELECT id::text FROM unnest(v_removed) id));
  INSERT INTO public.client_aggregate_versions
    (aggregate_type,scope_type,scope_id,aggregate_id,version)
  SELECT 'occasion_user','occasion',p_occasion,id::text,1
    FROM unnest(v_after_users) id
  ON CONFLICT (aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
    SET version=public.client_aggregate_versions.version+1,
      updated_at=clock_timestamp();
  SELECT COALESCE(jsonb_agg(jsonb_build_object('component',component,
    'userId',id) ORDER BY id,component),'[]'::jsonb) INTO v_impacts
  FROM unnest(v_after_users) id CROSS JOIN unnest(
    ARRAY['private_profile','private_inventory']) component;
  IF cardinality(v_removed)>0 THEN
    v_public:=ARRAY['live_public'];
    SELECT COALESCE(jsonb_agg(jsonb_build_object('component','live_public',
      'entityId',e.id)),'[]'::jsonb) INTO v_dirty
      FROM public.events e WHERE e.occasion=p_occasion;
  END IF;
  IF v_actor IS NOT NULL AND v_actor=ANY(v_after_users) THEN
    v_replacements:=jsonb_build_array(
      jsonb_build_object('component','private_profile','userId',v_actor,
        'payload',public.get_private_profile_payload_v1(p_occasion,v_actor)),
      jsonb_build_object('component','private_inventory','userId',v_actor,
        'payload',public.get_user_inventory_for_occasion_v1(p_occasion)));
  END IF;
  IF p_source='profile.tickets.import' AND cardinality(v_removed)>0 THEN
    v_impacts:=v_impacts||COALESCE((SELECT jsonb_agg(jsonb_build_object('component','private_activity','userId',id) ORDER BY id) FROM unnest(v_after_users) id),'[]'::jsonb);
  END IF;
  RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,
    p_source,'inventory',p_items,v_public,v_impacts,v_dirty,p_data,
    '{}','[]',p_actor_kind,NULL,v_replacements);
END; $function$

;

-- Released G3 compatibility boundary. The typed move command owns the DML.
-- This facade generates its intent/token server-side and cannot protect stale edits.
CREATE OR REPLACE FUNCTION public.save_place_location(p_place_id bigint,p_lat double precision,p_lng double precision)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE occasion bigint; version bigint; result jsonb;
BEGIN
 IF auth.uid() IS NULL THEN RETURN jsonb_build_object('code',401,'message','Sign in is required to move a place'); END IF;
 SELECT p.occasion INTO occasion FROM public.places p WHERE id=p_place_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('code',404,'message','Place not found'); END IF;
 SELECT v.version INTO version FROM public.client_aggregate_versions v WHERE aggregate_type='place' AND scope_type='occasion' AND scope_id=occasion AND aggregate_id=p_place_id::text;
 result:=public.move_place_client_sync_v1(occasion,p_place_id,extensions.gen_random_uuid(),COALESCE(version,0),p_lat,p_lng);
 RETURN jsonb_build_object('code',(result->>'code')::int,'data',jsonb_build_object('id',p_place_id));
EXCEPTION WHEN insufficient_privilege THEN RETURN jsonb_build_object('code',403,'message','You cannot change this place');
END $$;

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
CREATE OR REPLACE FUNCTION public.cancel_reception_registration_v1(p_occasion bigint,p_user uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_r public.reception_registrations%rowtype; v_actor uuid:=auth.uid(); v_impacts jsonb;
BEGIN
  PERFORM public.lock_activity_aggregate_internal_v1(p_occasion);
  SELECT * INTO v_r FROM public.reception_registrations WHERE occasion=p_occasion AND "user"=p_user FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('code',404,'message','registration_unavailable'); END IF;
  IF NOT public.get_can_use_reception(p_occasion) OR NOT (public.get_is_manager_on_occasion(p_occasion) OR public.get_is_admin_on_occasion(p_occasion) OR (v_r.created_by=v_actor AND (v_r.status='cancelled' OR v_r.created_at>now()-interval '30 minutes'))) THEN
    RETURN jsonb_build_object('code',403,'message','registration_unavailable'); END IF;
  IF v_r.status='cancelled' THEN RETURN jsonb_build_object('code',200,'status',CASE WHEN v_r.auth_revoked_at IS NULL THEN 'domain_blocked_auth_revocation_pending' ELSE 'cancelled' END,'targetUser',p_user); END IF;
  UPDATE public.reception_registrations SET status='cancelled',cancelled_by=v_actor,cancelled_at=now() WHERE occasion=p_occasion AND "user"=p_user;
  v_impacts:=public.remove_occasion_user_domain_internal_v1(p_occasion,p_user);
  INSERT INTO public.client_sync_private_scopes(component,occasion,user_id,source_revision)
  SELECT x->>'component',p_occasion,(x->>'userId')::uuid,1 FROM jsonb_array_elements(v_impacts) x ORDER BY x->>'component',x->>'userId'
  ON CONFLICT(component,occasion,user_id) DO UPDATE SET source_revision=public.client_sync_private_scopes.source_revision+1,updated_at=clock_timestamp();
  RETURN jsonb_build_object('code',200,'status','domain_blocked_auth_revocation_pending','targetUser',p_user);
END $$;
