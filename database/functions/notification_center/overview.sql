-- Compact notification overview. Order actions share their existing orders
-- destination, so each occasion/kind has one complete authorized snapshot count.
CREATE OR REPLACE FUNCTION public.get_notification_center_overview(
 p_organization bigint,p_current_occasion bigint,p_snapshot bigint,
 p_cursor jsonb DEFAULT NULL,p_limit integer DEFAULT 30,p_ids text[] DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE snap bigint; context text; cursor jsonb; items jsonb; tail jsonb; more boolean;
 lim integer:=greatest(1,least(p_limit,200));
BEGIN
 PERFORM public.notification_center_check_context(p_organization,p_current_occasion);
 IF cardinality(p_ids)>200 OR (p_ids IS NOT NULL AND p_cursor IS NOT NULL AND p_cursor<>'null'::jsonb) THEN
  RAISE invalid_parameter_value USING MESSAGE='notification_update_limit'; END IF;
 SELECT greatest(0,least(p_snapshot,last_delivery_sequence)) INTO snap
 FROM public.notification_center_user_state WHERE organization=p_organization AND recipient=auth.uid();
 snap:=coalesce(snap,0);
 context:=md5(jsonb_build_array('overview',auth.uid(),p_organization,p_current_occasion,snap)::text);
 cursor:=public.notification_center_time_cursor_internal(p_cursor,context);
 WITH visible AS MATERIALIZED (
  SELECT v.*,public.notification_center_order_activity_internal((event).kind) AND (event).occasion IS NOT NULL grouped
  FROM public.notification_center_visible_internal(p_organization,snap,p_current_occasion) v),
 ranked AS (
  SELECT *,row_number() OVER(PARTITION BY (event).occasion,(event).kind ORDER BY (event).occurred_at DESC,(event).id DESC) rank,
   count(*) OVER(PARTITION BY (event).occasion,(event).kind) n,
   max((delivery).sequence) OVER(PARTITION BY (event).occasion,(event).kind) latest FROM visible WHERE grouped),
 combined AS (
  SELECT (event).id::text id,section,(event).occurred_at at,event,delivery,0::bigint activity_count,(delivery).sequence sequence
  FROM visible WHERE NOT grouped
  UNION ALL
  SELECT 'order-summary:'||(event).occasion||':'||(event).kind,section,(event).occurred_at,event,delivery,n,latest FROM ranked WHERE rank=1),
 rows AS (
  SELECT *,row_number() OVER(ORDER BY section,at DESC,id DESC) position FROM combined
  WHERE (p_ids IS NULL OR id=ANY(p_ids)) AND (cursor IS NULL OR section>(cursor->>'section')::int
   OR (section=(cursor->>'section')::int AND (at,id)<((cursor->>'time')::timestamptz,cursor->>'id')))
  ORDER BY section,at DESC,id DESC LIMIT lim+1),
 page AS (SELECT *,public.notification_center_dto(event,delivery) dto FROM rows WHERE position<=lim)
 SELECT coalesce((SELECT jsonb_agg(CASE WHEN activity_count=0 THEN dto||jsonb_build_object('section',section)
  ELSE dto||jsonb_build_object('id',id,'section',section,'sequence',sequence,'data',jsonb_build_object(
   'activityCount',activity_count,'relatedOrders',true)||
   (CASE WHEN activity_count=1 THEN dto->'data' ELSE jsonb_build_object('contact',dto#>'{data,contact}') END)-'orderId'-'orderSymbol') END ORDER BY position) FROM page),'[]'),
  (SELECT jsonb_build_object('context',context,'section',section,'time',at,'id',id) FROM page ORDER BY position DESC LIMIT 1),
  (SELECT count(*)>lim FROM rows) INTO items,tail,more;
 RETURN jsonb_build_object('items',items,'nextCursor',CASE WHEN more AND p_ids IS NULL THEN to_jsonb(encode(convert_to(tail::text,'UTF8'),'base64')) END);
END $$;
REVOKE ALL ON FUNCTION public.get_notification_center_overview(bigint,bigint,bigint,jsonb,integer,text[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_notification_center_overview(bigint,bigint,bigint,jsonb,integer,text[]) TO authenticated;
