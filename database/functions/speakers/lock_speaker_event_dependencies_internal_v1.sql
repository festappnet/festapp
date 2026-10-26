CREATE OR REPLACE FUNCTION public.lock_speaker_event_dependencies_internal_v1(p_speaker bigint)
RETURNS bigint[] LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE ids bigint[]; current_ids bigint[];
BEGIN
 SELECT ARRAY(SELECT event FROM public.event_speakers WHERE speaker=p_speaker ORDER BY event) INTO ids;
 PERFORM 1 FROM public.events WHERE id=ANY(ids) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.speakers WHERE id=p_speaker FOR UPDATE;
 SELECT ARRAY(SELECT event FROM public.event_speakers WHERE speaker=p_speaker ORDER BY event) INTO current_ids;
 IF ids IS DISTINCT FROM current_ids THEN RAISE serialization_failure USING MESSAGE='speaker event links changed; retry the same command'; END IF;
 RETURN ids;
END $$;
REVOKE ALL ON FUNCTION public.lock_speaker_event_dependencies_internal_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
