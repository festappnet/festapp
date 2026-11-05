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
BEGIN PERFORM public.notification_center_require_service();PERFORM public.notification_center_prepared_wake();END $$;
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
