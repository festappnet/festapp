-- Resolve the frozen, authorized group only when the orders page is opened.
-- No target ID arrays are added to the notification feed or badge polling.
CREATE OR REPLACE FUNCTION public.notification_center_order_selection(
 p_occasion bigint,p_group jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF p_group ? 'viewToken' THEN
  p_group:=public.notification_center_prepared_scope((p_group->>'organization')::bigint,p_group);
  IF (p_group->>'occasion')::bigint IS DISTINCT FROM p_occasion THEN RAISE insufficient_privilege USING MESSAGE='notification_context_mismatch'; END IF;
  IF NOT coalesce(public.can_read_orders(p_occasion),false) THEN RAISE insufficient_privilege USING MESSAGE='orders_read_denied'; END IF;
  -- Frozen envelopes select every captured member, independent of preview/page size.
  -- Live authorization/privacy and source eligibility still apply on this request.
  SELECT coalesce(jsonb_agg(DISTINCT (e.data->>'orderId')::bigint),'[]'::jsonb) INTO result
  FROM public.notification_center_view_members m
  JOIN public.notification_center_events e ON e.id=m.event_id
  JOIN public.notification_center_deliveries d ON d.event_id=e.id AND d.organization=m.organization AND d.recipient=m.recipient
  WHERE m.organization=(p_group->>'organization')::bigint AND m.recipient=auth.uid() AND m.eligible
   AND e.occasion=p_occasion AND d.sequence<=(p_group->>'snapshot')::bigint
   AND NOT EXISTS(SELECT 1 FROM public.notification_center_deliveries newer WHERE newer.event_id=d.event_id AND newer.recipient=d.recipient AND newer.sequence<=(p_group->>'snapshot')::bigint AND newer.sequence>d.sequence)
   AND public.notification_center_allowed(e,auth.uid())
   AND public.notification_center_in_center_internal(e,(p_group->>'capturedAt')::timestamptz)
   AND public.notification_center_order_activity_internal(e.kind)
   AND public.notification_center_prepared_scope_member(e,d,p_group->>'groupKey',p_group->>'id',
    (p_group->>'afterSequence')::bigint,(p_group->>'throughSequence')::bigint,
    (p_group->>'capturedAt')::timestamptz,(p_group->>'captureIsRead')::boolean)
   AND e.data->>'orderId' ~ '^[0-9]{1,18}$';
  RETURN result;
 END IF;
 RAISE invalid_parameter_value USING MESSAGE='notification_view_token_required';
END $$;
REVOKE ALL ON FUNCTION public.notification_center_order_selection(bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.notification_center_order_selection(bigint,jsonb) TO authenticated;
