CREATE OR REPLACE FUNCTION public.save_event_client_sync_v1(p_occasion bigint, p_command_id uuid, p_expected_version bigint, p_event jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_response jsonb; v_commit uuid; v_event bigint;
BEGIN
  v_response:=public.save_event_domain_command_internal_v1(
    p_occasion,p_command_id,p_expected_version,p_event);
  IF v_response->>'status'='applied' THEN
    v_commit:=NULLIF(v_response#>>'{mutation,commitId}','')::uuid;
    v_event:=NULLIF(v_response#>>'{data,event,id}','')::bigint;
    IF v_event IS NULL THEN v_event:=NULLIF(v_response#>>'{data,eventId}','')::bigint; END IF;
    IF v_commit IS NOT NULL AND v_event IS NOT NULL
       AND EXISTS (SELECT 1 FROM public.occasions o WHERE o.id=p_occasion AND NOT o.is_hidden) THEN
      PERFORM public.attach_event_live_projection_v1(v_commit,p_occasion,ARRAY[v_event]);
    END IF;
  END IF;
  RETURN v_response;
END; $function$
;
REVOKE ALL ON FUNCTION public.save_event_client_sync_v1(bigint,uuid,bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.save_event_client_sync_v1(bigint,uuid,bigint,jsonb) TO authenticated;
