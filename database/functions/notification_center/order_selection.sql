-- Resolve the frozen, authorized group only when the orders page is opened.
-- No target ID arrays are added to the notification feed or badge polling.
CREATE OR REPLACE FUNCTION public.notification_center_order_selection(
 p_occasion bigint,p_group jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,extensions AS $$
DECLARE org bigint; snap bigint; zone text; anchor timestamptz; result jsonb;
BEGIN
 IF NOT coalesce(public.can_read_orders(p_occasion),false) THEN
  RAISE insufficient_privilege USING MESSAGE='orders_read_denied'; END IF;
 SELECT organization INTO org FROM public.occasions WHERE id=p_occasion;
 IF org IS DISTINCT FROM (p_group->>'organization')::bigint THEN
  RAISE insufficient_privilege USING MESSAGE='notification_context_mismatch'; END IF;
 PERFORM public.notification_center_check_context(org,p_occasion);
 IF coalesce(p_group->>'snapshot','') !~ '^[0-9]{1,18}$' THEN
  RAISE invalid_parameter_value USING MESSAGE='notification_invalid_snapshot'; END IF;
 anchor:=least(coalesce((p_group->>'snapshotAt')::timestamptz,clock_timestamp()),clock_timestamp());
 zone:=p_group->>'timezone';
 IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=zone) THEN
  RAISE invalid_parameter_value USING MESSAGE='notification_invalid_timezone'; END IF;
 SELECT greatest(0,least((p_group->>'snapshot')::bigint,last_delivery_sequence)) INTO snap
 FROM public.notification_center_user_state WHERE organization=org AND recipient=auth.uid();
 SELECT coalesce(jsonb_agg(DISTINCT ((v.event).data->>'orderId')::bigint),'[]'::jsonb) INTO result
 FROM public.notification_center_visible_internal(org,coalesce(snap,0),p_occasion) v
 WHERE (v.event).occasion=p_occasion
  AND public.notification_center_in_center_internal(v.event,anchor)
  AND public.notification_center_order_activity_internal((v.event).kind)
  AND 'occasion-kind:'||p_occasion||':'||(v.event).kind=
    public.notification_center_rollup_id_internal(p_group->>'id')
  AND (v.event).data->>'orderId' ~ '^[0-9]{1,18}$';
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_order_selection(bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.notification_center_order_selection(bigint,jsonb) TO authenticated;
