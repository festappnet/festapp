-- pg_net publishes only after the surrounding domain transaction commits.
-- This is a coalesced synchronization hint, never a second business queue.
CREATE OR REPLACE FUNCTION public.notification_center_prepared_wake()
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE url text;
BEGIN
 IF current_setting('festapp.notification_wake',true)='scheduled' THEN RETURN; END IF;
 UPDATE public.notification_center_maintenance SET next_at=clock_timestamp()+interval '1 second',wake_error=NULL
 WHERE name='delivery-wake' AND worker_url IS NOT NULL AND next_at<=clock_timestamp()
  AND ctid IN(SELECT ctid FROM public.notification_center_maintenance WHERE name='delivery-wake' FOR UPDATE SKIP LOCKED)
 RETURNING worker_url INTO url;
 IF url IS NULL THEN RETURN; END IF;
 PERFORM set_config('festapp.notification_wake','scheduled',true);
 BEGIN
  PERFORM net.http_post(url:=url,body:=jsonb_build_object('requestSecret',public.generate_request_secret(120)),timeout_milliseconds:=5000);
 EXCEPTION WHEN OTHERS THEN
  UPDATE public.notification_center_maintenance SET wake_error='wake_failed' WHERE name='delivery-wake'
   AND ctid IN(SELECT ctid FROM public.notification_center_maintenance WHERE name='delivery-wake' FOR UPDATE SKIP LOCKED);
 END;
END $$;
REVOKE ALL ON FUNCTION public.notification_center_prepared_wake() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.wake_notification_center()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.notification_center_require_service();
 -- The one-second safety tick discovers durable work; it must not create an
 -- HTTP request when idle. Domain commits retain their unconditional fast wake.
 -- Keep existing views eligible so live privacy/read repair and expiry cleanup
 -- are never delayed by this scheduler optimization.
 IF EXISTS(SELECT 1 FROM public.notification_center_events WHERE projected_revision<attention_revision)
  OR EXISTS(SELECT 1 FROM public.notification_center_projection_scopes WHERE next_check_at<=clock_timestamp() AND NOT quarantined)
  OR EXISTS(SELECT 1 FROM public.notification_center_views)
  OR EXISTS(SELECT 1 FROM public.notification_center_user_state u
   JOIN public.notification_center_email_profiles p USING(recipient)
   JOIN public.notification_center_organizations a USING(organization)
   WHERE u.email_scanned_sequence<u.last_delivery_sequence AND a.email_collection_started_at IS NOT NULL)
  OR EXISTS(SELECT 1 FROM public.notification_center_user_state u
   JOIN public.notification_center_organizations a USING(organization)
   JOIN public.user_info ui ON ui.id=u.recipient
   JOIN public.notification_center_deliveries d ON d.organization=u.organization AND d.recipient=u.recipient AND d.sequence>u.email_scanned_sequence
   JOIN public.notification_center_events e ON e.id=d.event_id
   WHERE u.email_scanned_sequence<u.last_delivery_sequence AND a.email_collection_started_at IS NOT NULL
    AND e.occurred_at>=a.email_collection_started_at AND public.notification_center_email_required_kind_internal(e.kind)
    AND NOT EXISTS(SELECT 1 FROM public.notification_center_email_profiles p WHERE p.recipient=u.recipient))
  OR EXISTS(SELECT 1 FROM public.notification_center_email_dispatches d
   WHERE d.state='collecting' AND d.due_at<=clock_timestamp() AND d.next_attempt_at<=clock_timestamp()
    AND EXISTS(SELECT 1 FROM public.notification_center_email_profiles p WHERE p.recipient=d.recipient)
    AND NOT EXISTS(SELECT 1 FROM public.email_messages m WHERE m.recipient_user=d.recipient AND m.message_kind='admin_notification_digest'
      AND m.workflow_state IN ('blocked','pending','preparing','sending','retry_wait','unknown'))) THEN
  PERFORM public.notification_center_prepared_wake();
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.wake_notification_center() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.wake_notification_center() TO service_role;
CREATE OR REPLACE FUNCTION public.configure_notification_center_worker(p_project_url text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.notification_center_require_service();
 IF p_project_url IS NULL OR p_project_url !~ '^https?://[^/?#[:space:]]+/?$' THEN RAISE invalid_parameter_value USING MESSAGE='notification_worker_origin_required'; END IF;
 INSERT INTO public.notification_center_maintenance(name,worker_url) VALUES('delivery-wake',rtrim(p_project_url,'/')||'/functions/v1/process-notification-center')
 ON CONFLICT(name) DO UPDATE SET worker_url=excluded.worker_url,next_at='-infinity',wake_error=NULL;
END $$;
REVOKE ALL ON FUNCTION public.configure_notification_center_worker(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.configure_notification_center_worker(text) TO service_role;
