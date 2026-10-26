-- The client supplies its local calendar as UTC intervals. This keeps native
-- and web day/week boundaries (including DST) consistent with device labels.
CREATE OR REPLACE FUNCTION public.notification_center_order_activity_internal(p_kind text)
RETURNS boolean LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT p_kind IN ('order_created','order_cancelled','waitlist_registered','offer_accepted','offer_declined','offer_expired');
$$;
CREATE OR REPLACE FUNCTION public.notification_center_periods_internal(p_periods jsonb,p_at timestamptz)
RETURNS TABLE(period jsonb,start_at timestamptz,end_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE previous_start timestamptz;
BEGIN
 IF p_at IS NULL OR jsonb_typeof(p_periods) IS DISTINCT FROM 'array' OR jsonb_array_length(p_periods)>1024 THEN
  RAISE invalid_parameter_value USING MESSAGE='notification_invalid_calendar'; END IF;
 FOR period IN SELECT value FROM jsonb_array_elements(p_periods) LOOP
  BEGIN
   start_at:=(period->>'startAt')::timestamptz; end_at:=(period->>'endAt')::timestamptz;
   IF start_at IS NULL OR end_at IS NULL OR start_at>=end_at OR end_at>p_at-interval '24 hours'
    OR period->>'unit' NOT IN ('day','week') OR period->>'unit' IS NULL
    OR (period->>'firstDay')::date IS NULL OR (period->>'lastDay')::date IS NULL
    OR end_at-start_at>interval '8 days' OR (previous_start IS NOT NULL AND end_at<>previous_start) THEN
    RAISE EXCEPTION 'invalid interval'; END IF;
  EXCEPTION WHEN OTHERS THEN RAISE invalid_parameter_value USING MESSAGE='notification_invalid_calendar'; END;
  previous_start:=start_at; RETURN NEXT;
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.notification_center_time_cursor_internal(p_cursor jsonb,p_context text)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF p_cursor IS NULL OR p_cursor='null'::jsonb THEN RETURN NULL; END IF;
 BEGIN
  IF jsonb_typeof(p_cursor)<>'string' THEN RAISE EXCEPTION 'invalid cursor'; END IF;
  result:=convert_from(decode(p_cursor#>>'{}','base64'),'UTF8')::jsonb;
  IF result->>'context' IS DISTINCT FROM p_context OR (result->>'time')::timestamptz IS NULL
   OR jsonb_typeof(result->'id') IS DISTINCT FROM 'string' OR length(result->>'id') NOT BETWEEN 1 AND 512
   OR (result->>'section')::int NOT BETWEEN 0 AND 2 OR result->>'section' IS NULL THEN RAISE EXCEPTION 'invalid cursor'; END IF;
 EXCEPTION WHEN OTHERS THEN RAISE invalid_parameter_value USING MESSAGE='notification_invalid_cursor'; END;
 RETURN result;
END $$;
CREATE OR REPLACE FUNCTION public.get_notification_center_timeline(p_organization bigint,p_current_occasion bigint,
 p_snapshot bigint,p_snapshot_at timestamptz,p_periods jsonb,p_cursor jsonb DEFAULT NULL,p_limit integer DEFAULT 30)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE snap bigint; context text; cursor jsonb; items jsonb; tail jsonb; more boolean; missing boolean;
 lim integer:=greatest(1,least(p_limit,100));
BEGIN
 PERFORM public.notification_center_check_context(p_organization,p_current_occasion);
 PERFORM 1 FROM public.notification_center_periods_internal(p_periods,p_snapshot_at);
 SELECT greatest(0,least(p_snapshot,last_delivery_sequence)) INTO snap FROM public.notification_center_user_state
 WHERE organization=p_organization AND recipient=auth.uid(); snap:=coalesce(snap,0);
 context:=md5(jsonb_build_array(auth.uid(),p_organization,p_current_occasion,snap,p_snapshot_at,p_periods)::text);
 cursor:=public.notification_center_time_cursor_internal(p_cursor,context);
 WITH periods AS MATERIALIZED (SELECT * FROM public.notification_center_periods_internal(p_periods,p_snapshot_at)),
 visible AS MATERIALIZED (SELECT * FROM public.notification_center_visible_internal(p_organization,snap,p_current_occasion)),
 classified AS MATERIALIZED (
  SELECT v.*,p.period FROM visible v LEFT JOIN periods p ON public.notification_center_order_activity_internal((event).kind)
   AND (event).occasion IS NOT NULL AND (event).occurred_at>=p.start_at AND (event).occurred_at<p.end_at),
 raw AS (
  SELECT section,(event).occurred_at at,(event).id::text id,NULL::jsonb payload,event,delivery
  FROM classified WHERE period IS NULL),
 buckets AS (
  SELECT section,(event).occasion occasion,period,count(*) n,max((event).occurred_at) at,
   'order-period:'||(event).occasion||':'||md5(period::text) id
  FROM classified WHERE period IS NOT NULL GROUP BY section,(event).occasion,period),
 combined AS (
  SELECT * FROM raw UNION ALL
  SELECT b.section,b.at,b.id,jsonb_build_object('id',b.id,'kind','order_activity_group','section',b.section,'occurredAt',b.at,
   'occasionId',b.occasion,'occasionTitle',oc.title,'occasionLink',oc.link,'data',jsonb_build_object('period',b.period,'count',b.n)),
   NULL::public.notification_center_events,NULL::public.notification_center_deliveries
  FROM buckets b JOIN public.occasions oc ON oc.id=b.occasion AND oc.organization=p_organization),
 rows AS (SELECT *,row_number() OVER(ORDER BY section,at DESC,id DESC) position FROM combined
  WHERE cursor IS NULL OR section>(cursor->>'section')::int OR (section=(cursor->>'section')::int AND (at,id)<((cursor->>'time')::timestamptz,cursor->>'id'))
  ORDER BY section,at DESC,id DESC LIMIT lim+1),page AS(SELECT * FROM rows WHERE position<=lim)
 SELECT coalesce((SELECT jsonb_agg(CASE WHEN payload IS NULL
   THEN public.notification_center_dto(event,delivery)||jsonb_build_object('section',section) ELSE payload END ORDER BY position) FROM page),'[]'),
  (SELECT jsonb_build_object('context',context,'section',section,'time',at,'id',id) FROM page ORDER BY position DESC LIMIT 1),
  (SELECT count(*)>lim FROM rows),
  EXISTS(SELECT 1 FROM classified WHERE period IS NULL AND public.notification_center_order_activity_internal((event).kind)
    AND (event).occasion IS NOT NULL AND (event).occurred_at<p_snapshot_at-interval '24 hours')
 INTO items,tail,more,missing;
 IF missing THEN RAISE invalid_parameter_value USING MESSAGE='notification_calendar_incomplete'; END IF;
 RETURN jsonb_build_object('snapshot',snap,'items',items,'nextCursor',CASE WHEN more THEN to_jsonb(encode(convert_to(tail::text,'UTF8'),'base64')) END);
END $$;
CREATE OR REPLACE FUNCTION public.get_notification_center_timeline_group(p_organization bigint,p_current_occasion bigint,
 p_snapshot bigint,p_snapshot_at timestamptz,p_occasion bigint,p_period jsonb,p_cursor jsonb DEFAULT NULL,p_limit integer DEFAULT 30)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE snap bigint; context text; cursor jsonb; items jsonb; tail jsonb; more boolean; bounds record;
 lim integer:=greatest(1,least(p_limit,100));
BEGIN
 PERFORM public.notification_center_check_context(p_organization,p_current_occasion);
 SELECT * INTO STRICT bounds FROM public.notification_center_periods_internal(jsonb_build_array(p_period),p_snapshot_at);
 SELECT greatest(0,least(p_snapshot,last_delivery_sequence)) INTO snap FROM public.notification_center_user_state
 WHERE organization=p_organization AND recipient=auth.uid(); snap:=coalesce(snap,0);
 context:=md5(jsonb_build_array(auth.uid(),p_organization,p_current_occasion,snap,p_snapshot_at,p_occasion,p_period)::text);
 cursor:=public.notification_center_time_cursor_internal(p_cursor,context);
 IF cursor IS NOT NULL THEN BEGIN PERFORM (cursor->>'id')::uuid; EXCEPTION WHEN OTHERS THEN RAISE invalid_parameter_value USING MESSAGE='notification_invalid_cursor'; END; END IF;
 WITH rows AS (
 SELECT v.*,row_number() OVER(ORDER BY (event).occurred_at DESC,(event).id DESC) position
 FROM public.notification_center_visible_internal(p_organization,snap,p_current_occasion) v
 WHERE (event).occasion=p_occasion AND public.notification_center_order_activity_internal((event).kind)
  AND (event).occurred_at>=bounds.start_at AND (event).occurred_at<bounds.end_at
  AND (cursor IS NULL OR ((event).occurred_at,(event).id)<((cursor->>'time')::timestamptz,(cursor->>'id')::uuid))
 ORDER BY (event).occurred_at DESC,(event).id DESC LIMIT lim+1),page AS(SELECT * FROM rows WHERE position<=lim)
 SELECT coalesce((SELECT jsonb_agg(public.notification_center_dto(event,delivery)||jsonb_build_object('section',section) ORDER BY position) FROM page),'[]'),
  (SELECT jsonb_build_object('context',context,'section',section,'time',(event).occurred_at,'id',(event).id) FROM page ORDER BY position DESC LIMIT 1),
  (SELECT count(*)>lim FROM rows) INTO items,tail,more;
 RETURN jsonb_build_object('items',items,'nextCursor',CASE WHEN more THEN to_jsonb(encode(convert_to(tail::text,'UTF8'),'base64')) END);
END $$;
CREATE OR REPLACE FUNCTION public.get_notification_center_timeline_group_updates(p_organization bigint,p_current_occasion bigint,
 p_snapshot bigint,p_snapshot_at timestamptz,p_groups jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb; snap bigint; entry jsonb;
BEGIN
 PERFORM public.notification_center_check_context(p_organization,p_current_occasion);
 IF jsonb_typeof(p_groups) IS DISTINCT FROM 'array' OR jsonb_array_length(p_groups)>200 THEN RAISE invalid_parameter_value USING MESSAGE='notification_update_limit'; END IF;
 FOR entry IN SELECT value FROM jsonb_array_elements(p_groups) LOOP
  PERFORM 1 FROM public.notification_center_periods_internal(jsonb_build_array(entry->'period'),p_snapshot_at);
 END LOOP;
 SELECT greatest(0,least(p_snapshot,last_delivery_sequence)) INTO snap FROM public.notification_center_user_state
 WHERE organization=p_organization AND recipient=auth.uid(); snap:=coalesce(snap,0);
 WITH requested AS (SELECT DISTINCT value->>'id' id,(value->>'occasionId')::bigint occasion,value->'period' period FROM jsonb_array_elements(p_groups)),
 visible AS MATERIALIZED(SELECT * FROM public.notification_center_visible_internal(p_organization,snap,p_current_occasion))
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'count',n,'occasionTitle',title)),'[]') INTO result FROM (
 SELECT r.id,count((v.event).id) n,max(oc.title) title FROM requested r
 LEFT JOIN visible v ON (v.event).occasion=r.occasion AND public.notification_center_order_activity_internal((v.event).kind)
  AND (v.event).occurred_at>=(r.period->>'startAt')::timestamptz AND (v.event).occurred_at<(r.period->>'endAt')::timestamptz
 LEFT JOIN public.occasions oc ON oc.id=(v.event).occasion AND oc.organization=p_organization GROUP BY r.id) counts;
 RETURN jsonb_build_object('groups',result);
END $$;
REVOKE ALL ON FUNCTION public.notification_center_order_activity_internal(text),
 public.notification_center_periods_internal(jsonb,timestamptz),public.notification_center_time_cursor_internal(jsonb,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_notification_center_timeline(bigint,bigint,bigint,timestamptz,jsonb,jsonb,integer),
 public.get_notification_center_timeline_group(bigint,bigint,bigint,timestamptz,bigint,jsonb,jsonb,integer),
 public.get_notification_center_timeline_group_updates(bigint,bigint,bigint,timestamptz,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_notification_center_timeline(bigint,bigint,bigint,timestamptz,jsonb,jsonb,integer),
 public.get_notification_center_timeline_group(bigint,bigint,bigint,timestamptz,bigint,jsonb,jsonb,integer),
 public.get_notification_center_timeline_group_updates(bigint,bigint,bigint,timestamptz,jsonb) TO authenticated;
