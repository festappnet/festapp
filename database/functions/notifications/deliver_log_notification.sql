CREATE OR REPLACE FUNCTION public.deliver_log_notification_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  endpoint text := TG_ARGV[0];
  webhook_token text;
BEGIN
  IF TG_NARGS <> 1 OR endpoint !~ '^https://[^/]+/functions/v1/notify$' THEN
    RAISE EXCEPTION 'notification webhook endpoint is invalid';
  END IF;
  SELECT decrypted_secret INTO webhook_token
  FROM vault.decrypted_secrets
  WHERE name = 'festapp_notify_webhook_token_v1';
  IF webhook_token IS NULL OR length(webhook_token) < 32 THEN
    RAISE EXCEPTION 'notification webhook token is missing';
  END IF;
  PERFORM net.http_post(
    url := endpoint,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || webhook_token,
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object('record', to_jsonb(NEW)),
    timeout_milliseconds := 4000
  );
  RETURN NEW;
END
$function$;

REVOKE ALL ON FUNCTION public.deliver_log_notification_v1() FROM PUBLIC, anon, authenticated;
