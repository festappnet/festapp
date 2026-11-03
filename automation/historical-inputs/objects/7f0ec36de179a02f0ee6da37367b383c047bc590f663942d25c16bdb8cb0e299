CREATE OR REPLACE FUNCTION public.setup_triggers(p_project_url text)
RETURNS void
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
  relation_name text;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' AND session_user <> 'postgres' THEN
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

  -- Notification delivery is an explicit domain-command operation.
  UPDATE public.notification_runtime SET endpoint=p_project_url||'/functions/v1/notify' WHERE singleton;
END
$function$;

REVOKE ALL ON FUNCTION public.setup_triggers(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.setup_triggers(text) TO service_role;
