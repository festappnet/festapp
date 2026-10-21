-- Canonical owner recovered from the recorded effective main schema.
-- Public signatures, response envelopes and existing execution roles are preserved.

CREATE OR REPLACE FUNCTION public.get_event_editor_v1(p_occasion bigint, p_event bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_event jsonb; v_version bigint;
BEGIN
  IF NOT public.can_read_schedule_editor(p_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor view required';
  END IF;
  SELECT public.get_event_command_data_v1(e.id)||jsonb_build_object(
      'childEventIds',COALESCE((SELECT jsonb_agg(g.event_child ORDER BY g.event_child)
        FROM public.event_groups g WHERE g.event_parent=e.id),'[]'::jsonb)
    ),COALESCE(v.version,0)
    INTO v_event,v_version FROM public.events e
    LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='event'
      AND v.scope_type='occasion' AND v.scope_id=p_occasion
      AND v.aggregate_id=e.id::text
    WHERE e.id=p_event AND e.occasion=p_occasion;
  IF v_event IS NULL THEN RETURN jsonb_build_object('code',404,'data',NULL); END IF;
  RETURN jsonb_build_object('code',200,'data',jsonb_build_object(
    'version',v_version,'event',v_event));
END; $function$
;
REVOKE ALL ON FUNCTION public.get_event_editor_v1(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

GRANT EXECUTE ON FUNCTION public.get_event_editor_v1(bigint,bigint) TO postgres,authenticated,service_role;
