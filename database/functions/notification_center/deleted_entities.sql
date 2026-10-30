-- Explicit operator repair for historical hard deletions. No domain rows change.
CREATE OR REPLACE FUNCTION public.notification_center_purge_deleted_internal(p_organization bigint)
RETURNS integer LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE removed integer;
BEGIN
 PERFORM public.notification_center_require_service();
 IF p_organization IS NULL OR NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=p_organization) THEN
  RAISE EXCEPTION 'notification_organization_required';
 END IF;
 DELETE FROM public.notification_center_events e
 WHERE e.organization=p_organization AND (
  (e.kind IN ('order_created','waitlist_registered','order_cancelled','offer_accepted')
   AND e.data->>'orderId' IS NOT NULL
   AND NOT EXISTS(SELECT 1 FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
    WHERE o.id::text=e.data->>'orderId' AND o.occasion=e.occasion AND oc.organization=e.organization))
  OR (e.kind='occasion_joined' AND e.data->>'userId' IS NOT NULL
   AND NOT EXISTS(SELECT 1 FROM public.occasion_users ou JOIN public.occasions oc ON oc.id=ou.occasion
    WHERE ou."user"::text=e.data->>'userId' AND ou.occasion=e.occasion AND oc.organization=e.organization))
  OR (e.kind='email_problem' AND e.data->>'messageId' IS NOT NULL
   AND NOT EXISTS(SELECT 1 FROM public.email_messages m
    WHERE m.message_id::text=e.data->>'messageId' AND m.organization=e.organization))
 );
 GET DIAGNOSTICS removed=ROW_COUNT;
 DELETE FROM public.notification_center_source_state s
 WHERE s.organization=p_organization AND s.source_key LIKE 'email:%'
 AND NOT EXISTS(SELECT 1 FROM public.email_messages m
  WHERE m.organization=s.organization AND s.source_key='email:'||m.message_id);
 RETURN removed;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_purge_deleted_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
