-- Operator surfaces never expose contacts, source payloads or recipient IDs.
CREATE OR REPLACE FUNCTION public.get_notification_center_delivery_health()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 PERFORM public.notification_center_require_service();
 SELECT coalesce(jsonb_agg(to_jsonb(s)),'[]') INTO result FROM (
  SELECT e.organization,count(*) pending,
   count(*) FILTER(WHERE r.retry_revision=r.eligible_revision AND r.quarantined) quarantined,
   count(*) FILTER(WHERE r.retry_revision=r.eligible_revision AND r.next_attempt_at>clock_timestamp()) backing_off,
   min(r.pending_since) oldest_pending_at,max(r.retry_count) maximum_attempts
  FROM public.notification_center_recipients r JOIN public.notification_center_events e ON e.id=r.event_id
  WHERE r.processed_revision<r.eligible_revision AND r.eligible_revision=e.attention_revision
  GROUP BY e.organization ORDER BY e.organization LIMIT 100) s;
 RETURN jsonb_build_object('organizations',result,'organizationLimit',100,'lastRun',
  (SELECT jsonb_build_object('scanned',last_scanned,'processed',last_processed,'deferred',last_deferred,
   'failed',last_failed,'elapsedMs',last_elapsed_ms,'at',last_run_at)
   FROM public.notification_center_maintenance WHERE name='delivery'));
END $$;
REVOKE ALL ON FUNCTION public.get_notification_center_delivery_health() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_notification_center_delivery_health() TO service_role;
CREATE OR REPLACE FUNCTION public.retry_notification_center_delivery(p_organization bigint,p_event uuid,p_recipient uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.notification_center_require_service();
 UPDATE public.notification_center_recipients r SET retry_count=0,next_attempt_at='-infinity',quarantined=false,last_error_code=NULL
 FROM public.notification_center_events e WHERE e.id=r.event_id AND e.organization=p_organization
  AND r.event_id=p_event AND r.recipient=p_recipient AND r.processed_revision<r.eligible_revision;
 RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.retry_notification_center_delivery(bigint,uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.retry_notification_center_delivery(bigint,uuid,uuid) TO service_role;
