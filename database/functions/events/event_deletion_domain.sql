CREATE OR REPLACE FUNCTION public.lock_event_deletion_scope_internal_v1(p_occasion bigint,p_ids bigint[])
RETURNS bigint[] LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE children bigint[]; current_children bigint[];
BEGIN
 SELECT ARRAY(SELECT DISTINCT event_child FROM public.event_groups WHERE event_parent=ANY(p_ids) AND NOT event_child=ANY(p_ids) ORDER BY event_child) INTO children;
 IF EXISTS(SELECT 1 FROM public.events WHERE id=ANY(children) AND occasion<>p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='event child outside occasion'; END IF;
 PERFORM 1 FROM public.events WHERE occasion=p_occasion AND id=ANY(p_ids||children) ORDER BY id FOR UPDATE;
 SELECT ARRAY(SELECT DISTINCT event_child FROM public.event_groups WHERE event_parent=ANY(p_ids) AND NOT event_child=ANY(p_ids) ORDER BY event_child) INTO current_children;
 IF children IS DISTINCT FROM current_children THEN RAISE serialization_failure USING MESSAGE='event links changed; retry the same command'; END IF;
 RETURN children;
END $$;

-- Shared teardown for ordinary events and empty counseling slots. Callers own
-- admission/receipts; every removed link invalidates its surviving aggregate.
CREATE OR REPLACE FUNCTION public.delete_events_domain_internal_v1(p_occasion bigint,p_ids bigint[])
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE children bigint[]; groups bigint[]; had_speakers boolean; deleted integer;
BEGIN
 IF EXISTS(SELECT 1 FROM public.events WHERE id=ANY(p_ids) AND occasion<>p_occasion) THEN
  RAISE insufficient_privilege USING MESSAGE='event deletion outside occasion'; END IF;
 children:=public.lock_event_deletion_scope_internal_v1(p_occasion,p_ids);
 SELECT ARRAY(SELECT DISTINCT "group" FROM public.exclusive_events WHERE event=ANY(p_ids) ORDER BY "group") INTO groups;
 IF EXISTS(SELECT 1 FROM public.exclusive_groups WHERE id=ANY(groups) AND occasion<>p_occasion) THEN RAISE insufficient_privilege USING MESSAGE='exclusive group outside occasion'; END IF;
 PERFORM 1 FROM public.exclusive_groups WHERE id=ANY(groups) ORDER BY id FOR UPDATE;
 SELECT EXISTS(SELECT 1 FROM public.event_speakers WHERE event=ANY(p_ids)) INTO had_speakers;
 DELETE FROM public.event_users WHERE event=ANY(p_ids);
 DELETE FROM public.event_users_saved WHERE event=ANY(p_ids);
 DELETE FROM public.exclusive_events WHERE event=ANY(p_ids);
 DELETE FROM public.event_roles WHERE event=ANY(p_ids);
 DELETE FROM public.event_groups WHERE event_parent=ANY(p_ids) OR event_child=ANY(p_ids);
 DELETE FROM public.event_speakers WHERE event=ANY(p_ids);
 DELETE FROM public.events WHERE id=ANY(p_ids) AND occasion=p_occasion;
 GET DIAGNOSTICS deleted=ROW_COUNT;
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
 SELECT 'event','occasion',p_occasion,id::text,1 FROM unnest(children) id
 ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
 SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp();
 INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
 SELECT 'exclusive_group','occasion',p_occasion,id::text,1 FROM unnest(groups) id
 ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
 SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp();
 DELETE FROM public.client_aggregate_versions WHERE aggregate_type='event' AND scope_type='occasion' AND scope_id=p_occasion AND aggregate_id=ANY(ARRAY(SELECT id::text FROM unnest(p_ids) id));
 RETURN jsonb_build_object('deleted',deleted,'childIds',to_jsonb(children),'exclusiveGroupIds',to_jsonb(groups),'hadSpeakers',had_speakers);
END $$;
REVOKE ALL ON FUNCTION public.lock_event_deletion_scope_internal_v1(bigint,bigint[]),public.delete_events_domain_internal_v1(bigint,bigint[]) FROM PUBLIC,anon,authenticated,service_role;
