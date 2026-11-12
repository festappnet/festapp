-- Only the current incident for a connection remains actionable. Historical
-- episodes can retain deliveries/read receipts, but must not duplicate alerts.
CREATE OR REPLACE FUNCTION public.notification_center_bank_episode_current(e public.notification_center_events)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT e.kind<>'bank_problem' OR EXISTS(SELECT 1 FROM eshop.bank_sync_health h
  WHERE h.connection_id=CASE WHEN e.data->>'bankConnectionId' ~ '^[0-9]{1,18}$' THEN (e.data->>'bankConnectionId')::bigint END
   AND h.incident_id::text=e.data->>'incidentId' AND public.bank_sync_alert_ready(h.connection_id));
$$;
REVOKE ALL ON FUNCTION public.notification_center_bank_episode_current(public.notification_center_events) FROM PUBLIC,anon,authenticated,service_role;

-- New-order activity follows the current order state, including older panel snapshots.
-- Participant joins remain relevant only while that person belongs to the occasion.
-- Activity expires from the center, not from the order/email audit history.
CREATE OR REPLACE FUNCTION public.notification_center_event_relevant_internal(
 e public.notification_center_events,p_anchor timestamptz)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT CASE WHEN e.kind='provider_problem' THEN e.status NOT IN ('recovered','resolved') AND EXISTS(
  SELECT 1 FROM eshop.provider_connection_notification_incidents i WHERE i.organization=e.organization AND i.provider=e.data->>'provider'
   AND i.connection_id::text=e.data->>'connectionId' AND i.unit::text=e.data->>'unitId' AND i.active AND i.incident_id::text=e.data->>'incidentId')
 WHEN e.kind='payment_problem' THEN e.status NOT IN ('recovered','resolved') AND EXISTS(
  SELECT 1 FROM eshop.payment_notification_incidents i JOIN eshop.orders o ON o.payment_info=i.payment_id
   JOIN public.occasions oc ON oc.id=o.occasion AND oc.organization=e.organization
  WHERE i.active AND i.incident_id::text=e.data->>'incidentId' AND o.occasion=e.occasion
   AND o.id=CASE WHEN e.data->>'orderId' ~ '^[0-9]{1,18}$' THEN (e.data->>'orderId')::bigint END)
 WHEN e.kind IN ('email_problem','bank_problem')
  THEN e.status NOT IN ('recovered','resolved') AND public.notification_center_bank_episode_current(e)
  ELSE (e.kind<>'order_payment_received' OR e.status NOT IN ('resolved','recovered')) AND e.occurred_at>=p_anchor-interval '30 days'
   AND (e.kind<>'order_created' OR coalesce(
    (SELECT o.state FROM eshop.orders o
     WHERE o.id=CASE WHEN e.data->>'orderId' ~ '^[0-9]{1,18}$'
      THEN (e.data->>'orderId')::bigint END AND o.occasion=e.occasion),
    e.status,'')<>'storno')
   AND (e.kind<>'occasion_joined' OR EXISTS(
    SELECT 1 FROM public.occasion_users m
    JOIN public.user_info u ON u.id=m."user" AND u.organization=e.organization
    WHERE m.occasion=e.occasion AND m."user"::text=e.data->>'userId')) END;
$$;
REVOKE ALL ON FUNCTION public.notification_center_event_relevant_internal(public.notification_center_events,timestamptz) FROM PUBLIC,anon,authenticated,service_role;

-- Live reads and cached prepared privacy retain their respective adapters.
CREATE OR REPLACE FUNCTION public.notification_center_in_center_internal(
 e public.notification_center_events,p_anchor timestamptz)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.notification_center_subject_visible_internal(e.organization,e.kind,e.data)
  AND public.notification_center_event_relevant_internal(e,p_anchor);
$$;
REVOKE ALL ON FUNCTION public.notification_center_in_center_internal(public.notification_center_events,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
