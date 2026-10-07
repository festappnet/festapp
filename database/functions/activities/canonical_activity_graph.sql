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
