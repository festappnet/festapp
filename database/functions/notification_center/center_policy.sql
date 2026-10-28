-- New-order activity follows the current order state, including older panel snapshots.
-- Activity expires from the center, not from the order/email audit history.
CREATE OR REPLACE FUNCTION public.notification_center_in_center_internal(
 e public.notification_center_events,p_anchor timestamptz)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT CASE WHEN e.kind IN ('email_problem','bank_problem')
  THEN e.status NOT IN ('recovered','resolved')
  ELSE e.occurred_at>=p_anchor-interval '30 days'
   AND (e.kind<>'order_created' OR coalesce(
    (SELECT o.state FROM eshop.orders o
     WHERE o.id=CASE WHEN e.data->>'orderId' ~ '^[0-9]{1,18}$'
      THEN (e.data->>'orderId')::bigint END AND o.occasion=e.occasion),
    e.status,'')<>'storno') END;
$$;
REVOKE ALL ON FUNCTION public.notification_center_in_center_internal(public.notification_center_events,timestamptz) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_notification_center_badge(p_organization bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.notification_center_user_state; anchor timestamptz:=clock_timestamp();
BEGIN
 PERFORM public.notification_center_check_context(p_organization);
 SELECT * INTO s FROM public.notification_center_user_state WHERE organization=p_organization AND recipient=auth.uid();
 RETURN jsonb_build_object('feedSupported',true,'timelineSupported',true,'enabled',true,'lastSequence',coalesce(s.last_delivery_sequence,0),'readThrough',coalesce(s.read_through_sequence,0),
 'unread',EXISTS(SELECT 1 FROM public.notification_center_deliveries d JOIN public.notification_center_events e ON e.id=d.event_id
 WHERE d.organization=p_organization AND d.recipient=auth.uid() AND d.sequence>greatest(coalesce(s.seen_through_sequence,0),coalesce(s.read_through_sequence,0))
 AND NOT (SELECT is_read FROM public.notification_center_batch_internal(e,d))
 AND public.notification_center_in_center_internal(e,anchor)
 AND public.notification_center_allowed(e,auth.uid()) AND public.notification_center_unmuted(e,auth.uid())));
END $$;

REVOKE ALL ON FUNCTION public.get_notification_center_badge(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_notification_center_badge(bigint) TO authenticated;
