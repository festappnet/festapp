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

-- The imported/source trigger has unauthenticated ingress semantics. Leave
-- delivery disabled until setup_triggers() is called with the reviewed
-- canonical Function origin and the Vault token is present.
DROP TRIGGER IF EXISTS push_log_notifications ON public.log_notifications;

CREATE OR REPLACE FUNCTION public.setup_triggers(p_project_url text)
RETURNS void
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
  relation_name text;
BEGIN
  IF auth.role() <> 'service_role' AND session_user <> 'postgres' THEN
    RAISE EXCEPTION 'Access Denied: Service role required.';
  END IF;
  IF p_project_url !~ '^https://[^/]+$' THEN
    RAISE EXCEPTION 'Project URL must be an HTTPS origin';
  END IF;

  FOREACH relation_name IN ARRAY ARRAY[
    'events', 'icons', 'information', 'news', 'occasions', 'places',
    'user_info', 'speakers', 'speaker_topics', 'cleaning_reports'
  ] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS handle_updated_at ON public.%I', relation_name);
    EXECUTE format(
      'CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.%I '
      'FOR EACH ROW EXECUTE FUNCTION extensions.moddatetime(''updated_at'')',
      relation_name
    );
  END LOOP;

  DROP TRIGGER IF EXISTS push_log_notifications ON public.log_notifications;
  EXECUTE format(
    'CREATE TRIGGER push_log_notifications AFTER INSERT ON public.log_notifications '
    'FOR EACH ROW EXECUTE FUNCTION public.deliver_log_notification_v1(%L)',
    p_project_url || '/functions/v1/notify'
  );
END
$function$;
