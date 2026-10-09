-- Public counts and caller-only attendance state. No participant identifiers.
CREATE OR REPLACE FUNCTION public.get_event_attendance_summary(p_events bigint[])
RETURNS TABLE(event bigint, participant_count bigint, is_signed_in boolean)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, extensions
AS $function$
  SELECT e.id, count(eu."user"),
         COALESCE(bool_or(eu."user" = auth.uid()), false)
  FROM public.events e
  LEFT JOIN public.event_users eu ON eu.event = e.id
  WHERE e.id = ANY(p_events)
    AND (
      public.get_is_event_allowed(e.id)
      OR public.get_is_editor_view_on_occasion(e.occasion)
    )
  GROUP BY e.id;
$function$;

REVOKE ALL ON FUNCTION public.get_event_attendance_summary(bigint[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_event_attendance_summary(bigint[])
  TO anon, authenticated, service_role;
