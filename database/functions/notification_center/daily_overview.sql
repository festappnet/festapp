-- One client RPC opens/acknowledges, pages or refreshes the daily overview.
-- Counts, historical place totals, bounded contact previews and badge state are
-- computed together. Calendar dates use one validated IANA display timezone.
CREATE OR REPLACE FUNCTION public.get_notification_center_daily_overview(
 p_organization bigint,p_current_occasion bigint,p_snapshot bigint DEFAULT NULL,
 p_snapshot_at timestamptz DEFAULT NULL,p_timezone text DEFAULT 'UTC',p_cursor jsonb DEFAULT NULL,
 p_limit integer DEFAULT 30,p_ids text[] DEFAULT NULL,p_open boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE snap bigint; context text; cursor jsonb; items jsonb; tail jsonb; more boolean;
 anchor timestamptz:=coalesce(p_snapshot_at,clock_timestamp()); previous_read bigint;
 choices jsonb; badge jsonb; lim integer:=greatest(1,least(p_limit,200));
BEGIN
 PERFORM public.notification_center_check_context(p_organization,p_current_occasion);
 IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=p_timezone) THEN
  RAISE invalid_parameter_value USING MESSAGE='notification_invalid_timezone'; END IF;
 IF cardinality(p_ids)>10000 OR (p_ids IS NOT NULL AND p_cursor IS NOT NULL AND p_cursor<>'null'::jsonb)
  OR (p_open AND (p_ids IS NOT NULL OR (p_cursor IS NOT NULL AND p_cursor<>'null'::jsonb))) THEN
  RAISE invalid_parameter_value USING MESSAGE='notification_update_limit'; END IF;
 IF p_ids IS NOT NULL THEN lim:=greatest(1,cardinality(p_ids)); END IF;
 IF p_open THEN
  INSERT INTO public.notification_center_user_state(organization,recipient) VALUES(p_organization,auth.uid()) ON CONFLICT DO NOTHING;
  SELECT last_delivery_sequence,read_through_sequence INTO snap,previous_read
   FROM public.notification_center_user_state WHERE organization=p_organization AND recipient=auth.uid() FOR UPDATE;
  anchor:=clock_timestamp();
 ELSE
  SELECT greatest(0,least(p_snapshot,last_delivery_sequence)) INTO snap
   FROM public.notification_center_user_state WHERE organization=p_organization AND recipient=auth.uid();
 END IF;
 snap:=coalesce(snap,0);
 context:=md5(jsonb_build_array('daily-overview',auth.uid(),p_organization,p_current_occasion,snap,extract(epoch FROM anchor),p_timezone)::text);
 cursor:=public.notification_center_time_cursor_internal(p_cursor,context);
 WITH visible AS MATERIALIZED (
  SELECT v.*,public.notification_center_order_activity_internal((event).kind) AND (event).occasion IS NOT NULL grouped
  FROM public.notification_center_visible_internal(p_organization,snap,p_current_occasion) v),
 classified AS MATERIALIZED (
  SELECT v.*,((event).occurred_at AT TIME ZONE p_timezone)::date calendar_day,
   CASE WHEN (event).data->>'count' ~ '^[0-9]{1,9}$'
    THEN nullif(greatest(((event).data->>'count')::bigint,0),0) END captured_places
  FROM visible v),
 ranked AS (
  SELECT *,row_number() OVER(bucket ORDER BY (event).occurred_at DESC,(event).id DESC) rank,
   count(*) OVER bucket n,count(captured_places) OVER bucket known_counts,sum(captured_places) OVER bucket total_places,
   bool_or(captured_places>1 OR (event).data#>'{formContext,allowsMultiple}'='true'::jsonb) OVER bucket has_multiple,
   max((delivery).sequence) OVER bucket latest FROM classified WHERE grouped
  WINDOW bucket AS(PARTITION BY (event).occasion,(event).kind,calendar_day)),
 combined AS (
  SELECT (event).id::text id,section,(event).occurred_at at,event,delivery,calendar_day,
   0::bigint activity_count,(delivery).sequence sequence,NULL::bigint place_count FROM classified WHERE NOT grouped
  UNION ALL
  SELECT 'order-day:'||(event).occasion||':'||(event).kind||':'||calendar_day,section,(event).occurred_at,event,delivery,
   calendar_day,n,latest,CASE WHEN has_multiple AND known_counts=n THEN total_places END FROM ranked WHERE rank=1),
 rows AS (
  SELECT *,row_number() OVER(ORDER BY section,at DESC,id DESC) position FROM combined
  WHERE (p_ids IS NULL OR id=ANY(p_ids)) AND (cursor IS NULL OR section>(cursor->>'section')::int
   OR (section=(cursor->>'section')::int AND (at,id)<((cursor->>'time')::timestamptz,cursor->>'id')))
  ORDER BY section,at DESC,id DESC LIMIT lim+1),
 page AS (SELECT *,public.notification_center_dto(event,delivery) dto FROM rows WHERE position<=lim)
 SELECT coalesce((SELECT jsonb_agg(CASE WHEN activity_count=0 THEN dto||jsonb_build_object('section',section,'day',calendar_day)
  ELSE dto||jsonb_build_object('id',id,'section',section,'day',calendar_day,'sequence',sequence,'data',
   (CASE WHEN activity_count=1 THEN dto->'data' ELSE jsonb_build_object('contact',dto#>'{data,contact}') END)-'orderId'-'orderSymbol'
   ||jsonb_build_object('activityCount',activity_count,'relatedOrders',true)
   ||jsonb_strip_nulls(jsonb_build_object('placeCount',place_count))
   ||jsonb_build_object('previewContacts',(SELECT jsonb_agg(
    public.notification_center_dto(r.event,r.delivery)#>'{data,contact}' ORDER BY r.rank)
    FROM ranked r WHERE (r.event).occasion=(page.event).occasion AND (r.event).kind=(page.event).kind
     AND r.calendar_day=page.calendar_day AND r.rank<=3))) END ORDER BY position) FROM page),'[]'),
  (SELECT jsonb_build_object('context',context,'section',section,'time',at,'id',id) FROM page ORDER BY position DESC LIMIT 1),
  (SELECT count(*)>lim FROM rows) INTO items,tail,more;
 IF p_open THEN
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',oc.id,'title',oc.title,'muted',coalesce(p.muted,false)) ORDER BY oc.title),'[]') INTO choices
  FROM public.occasions oc LEFT JOIN public.occasion_users ou ON ou.occasion=oc.id AND ou."user"=auth.uid()
  LEFT JOIN public.notification_center_preferences p ON p.organization=p_organization AND p.recipient=auth.uid() AND p.occasion=oc.id
  WHERE oc.organization=p_organization AND NOT public.is_demo_occasion(oc.id)
   AND (coalesce(ou.is_editor_order_view,false) OR public.notification_center_app_admin_internal(p_organization,oc.id,auth.uid()));
  -- A failed overview never acknowledges: data and watermark commit together.
  UPDATE public.notification_center_user_state SET read_through_sequence=greatest(read_through_sequence,snap)
  WHERE organization=p_organization AND recipient=auth.uid();
 END IF;
 badge:=public.get_notification_center_badge(p_organization);
 RETURN badge||jsonb_build_object('dailySupported',true,'snapshot',snap,'snapshotAt',anchor,
  'snapshotDay',(anchor AT TIME ZONE p_timezone)::date,'timezone',p_timezone,
  'previousReadThrough',previous_read,'occasions',choices,'items',items,
  'nextCursor',CASE WHEN more AND p_ids IS NULL THEN to_jsonb(encode(convert_to(tail::text,'UTF8'),'base64')) END);
END $$;
REVOKE ALL ON FUNCTION public.get_notification_center_daily_overview(bigint,bigint,bigint,timestamptz,text,jsonb,integer,text[],boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_notification_center_daily_overview(bigint,bigint,bigint,timestamptz,text,jsonb,integer,text[],boolean) TO authenticated;
