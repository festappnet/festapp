-- Only the current incident for a connection remains actionable. Historical
-- episodes can retain deliveries/read receipts, but must not duplicate alerts.
CREATE OR REPLACE FUNCTION public.notification_center_bank_episode_current(e public.notification_center_events)
RETURNS boolean LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT e.kind<>'bank_problem' OR NOT EXISTS(
  SELECT 1 FROM public.notification_center_source_state s
  WHERE s.organization=e.organization AND s.source_key='bank:'||(e.data->>'bankConnectionId')
   AND s.state->>'eventId' IS NOT NULL
   AND (s.state->>'eventId'<>e.id::text OR NOT coalesce((s.state->>'problem')::boolean,false)));
$$;
REVOKE ALL ON FUNCTION public.notification_center_bank_episode_current(public.notification_center_events) FROM PUBLIC,anon,authenticated,service_role;

-- New-order activity follows the current order state, including older panel snapshots.
-- Participant joins remain relevant only while that person belongs to the occasion.
-- Activity expires from the center, not from the order/email audit history.
CREATE OR REPLACE FUNCTION public.notification_center_in_center_internal(
 e public.notification_center_events,p_anchor timestamptz)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.notification_center_subject_visible_internal(e.organization,e.kind,e.data) AND CASE WHEN e.kind IN ('email_problem','bank_problem')
  THEN e.status NOT IN ('recovered','resolved') AND public.notification_center_bank_episode_current(e)
  ELSE e.occurred_at>=p_anchor-interval '30 days'
   AND (e.kind<>'order_created' OR coalesce(
    (SELECT o.state FROM eshop.orders o
     WHERE o.id=CASE WHEN e.data->>'orderId' ~ '^[0-9]{1,18}$'
      THEN (e.data->>'orderId')::bigint END AND o.occasion=e.occasion),
    e.status,'')<>'storno')
   AND (e.kind<>'occasion_joined' OR (EXISTS(SELECT 1 FROM public.organizations org
    WHERE org.id=e.organization AND org.data->>'IS_APP_SUPPORTED'='true') AND EXISTS(
    SELECT 1 FROM public.occasion_users m
    JOIN public.user_info u ON u.id=m."user" AND u.organization=e.organization
    WHERE m.occasion=e.occasion AND m."user"::text=e.data->>'userId'
     AND NOT EXISTS(SELECT 1 FROM public.organization_users hidden
      WHERE hidden.organization=e.organization AND hidden."user"=m."user" AND hidden.is_hidden)))) END;
$$;
REVOKE ALL ON FUNCTION public.notification_center_in_center_internal(public.notification_center_events,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
