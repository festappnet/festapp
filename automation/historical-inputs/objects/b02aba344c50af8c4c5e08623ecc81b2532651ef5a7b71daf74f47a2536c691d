-- The existing notification log is the durable intent; dispatch is explicit in
-- its domain command, after receipt/auth/admission. No row hook is installed.
CREATE TABLE public.notification_runtime (
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 endpoint text CHECK(endpoint ~ '^https://[^/]+/functions/v1/notify$')
);
INSERT INTO public.notification_runtime(singleton) VALUES(true);
ALTER TABLE public.notification_runtime ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.notification_runtime FROM PUBLIC,anon,authenticated;
GRANT SELECT,UPDATE ON public.notification_runtime TO service_role;
-- Adopt the existing server-owned destination, without sending anything.
UPDATE public.notification_runtime SET endpoint=(
 SELECT split_part(encode(tgargs,'escape'),E'\\000',1) FROM pg_trigger
 WHERE tgrelid='public.log_notifications'::regclass AND tgname='push_log_notifications' AND NOT tgisinternal
) WHERE singleton;
DROP TRIGGER IF EXISTS push_log_notifications ON public.log_notifications;
DROP FUNCTION IF EXISTS public.deliver_log_notification_v1();

CREATE OR REPLACE FUNCTION public.dispatch_log_notification_v1(p_notification uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE endpoint text; webhook_token text; message jsonb;
BEGIN
 SELECT r.endpoint INTO endpoint FROM public.notification_runtime r WHERE singleton;
 IF endpoint IS NULL THEN RETURN; END IF; -- Unconfigured local/rehearsal runtime.
 SELECT decrypted_secret INTO webhook_token FROM vault.decrypted_secrets WHERE name='festapp_notify_webhook_token_v1';
 IF webhook_token IS NULL OR length(webhook_token)<32 THEN RAISE configuration_limit_exceeded USING MESSAGE='notification webhook token missing'; END IF;
 SELECT to_jsonb(n) INTO message FROM public.log_notifications n WHERE id=p_notification;
 IF message IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='notification intent missing'; END IF;
 PERFORM net.http_post(url:=endpoint,headers:=jsonb_build_object('Authorization','Bearer '||webhook_token,'Content-Type','application/json'),
  body:=jsonb_build_object('record',message),timeout_milliseconds:=4000);
END $$;
REVOKE ALL ON FUNCTION public.dispatch_log_notification_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;
