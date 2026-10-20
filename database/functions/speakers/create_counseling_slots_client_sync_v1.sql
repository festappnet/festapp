CREATE OR REPLACE FUNCTION public.create_counseling_slots_client_sync_v1(p_speaker bigint, p_start timestamp with time zone, p_end timestamp with time zone, p_slot_minutes integer, p_place bigint, p_capacity integer, p_title text, p_break_minutes integer, p_command_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $function$
DECLARE v_response jsonb; v_commit uuid; v_occasion bigint; v_ids bigint[];
BEGIN
  v_response:=public.create_counseling_slots_domain_command_internal_v1(
    p_speaker,p_start,p_end,p_slot_minutes,p_place,p_capacity,p_title,
    p_break_minutes,p_command_id);
  IF v_response->>'status'='applied' THEN
    v_commit:=NULLIF(v_response#>>'{mutation,commitId}','')::uuid;
    SELECT s.occasion INTO v_occasion FROM public.speakers s WHERE s.id=p_speaker;
    SELECT COALESCE(array_agg(value::bigint ORDER BY value::bigint),'{}') INTO v_ids
    FROM jsonb_array_elements_text(COALESCE(v_response#>'{data,event_ids}','[]'));
    IF v_commit IS NOT NULL AND cardinality(v_ids)>0
       AND EXISTS (SELECT 1 FROM public.occasions o WHERE o.id=v_occasion AND NOT o.is_hidden) THEN
      PERFORM public.attach_event_live_projection_v1(v_commit,v_occasion,v_ids);
    END IF;
  END IF;
  RETURN v_response;
END; $function$
;
REVOKE ALL ON FUNCTION public.create_counseling_slots_client_sync_v1(p_speaker bigint, p_start timestamp with time zone, p_end timestamp with time zone, p_slot_minutes integer, p_place bigint, p_capacity integer, p_title text, p_break_minutes integer, p_command_id uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_counseling_slots_client_sync_v1(p_speaker bigint, p_start timestamp with time zone, p_end timestamp with time zone, p_slot_minutes integer, p_place bigint, p_capacity integer, p_title text, p_break_minutes integer, p_command_id uuid) TO authenticated;
