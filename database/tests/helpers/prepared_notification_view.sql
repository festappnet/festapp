-- Test-only readiness orchestration over the real worker and canonical API.
-- Return the actual response; do not translate it into a retired wire contract.
CREATE OR REPLACE FUNCTION pg_temp.prepared_notification_view(p_org bigint,p_occasion bigint DEFAULT NULL,p_mode text DEFAULT 'preview',p_view uuid DEFAULT NULL,p_cursor integer DEFAULT 0,p_limit integer DEFAULT 30,p_keep_view boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 FOR attempt IN 1..100 LOOP
  result:=public.get_notification_center_view(p_org,p_occasion,p_mode=>p_mode,p_view=>p_view,p_cursor=>p_cursor,p_limit=>p_limit);
  IF result->>'state'='denied' THEN RETURN result; END IF;
  IF result->>'state'='ready' THEN
   IF NOT p_keep_view THEN PERFORM public.get_notification_center_view(p_org,p_occasion,p_mode=>'close',p_view=>(result->>'viewToken')::uuid); END IF;
   RETURN result;
  END IF;
  IF result->>'state'<>'preparing' THEN RAISE EXCEPTION 'unexpected notification state: %',result->>'state'; END IF;
  PERFORM public.project_notification_center(500);
  PERFORM public.prepare_notification_center(100);
  PERFORM public.prepare_notification_center_views(100);
 END LOOP;
 RAISE EXCEPTION 'prepared notification readiness deadline';
END $$;
CREATE OR REPLACE FUNCTION pg_temp.prepared_notification_badge(p_org bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM pg_temp.prepared_notification_view(p_org);
 RETURN public.get_notification_center_prepared_badge(p_org);
END $$;

GRANT EXECUTE ON FUNCTION pg_temp.prepared_notification_view(bigint,bigint,text,uuid,integer,integer,boolean),pg_temp.prepared_notification_badge(bigint) TO authenticated;
