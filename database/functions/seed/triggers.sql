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
