CREATE OR REPLACE FUNCTION public.submit_event_feedback(p_event bigint,p_rating text,p_note text DEFAULT NULL,p_client_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE p_occasion bigint; r jsonb;
BEGIN
 SELECT occasion INTO p_occasion FROM public.events WHERE id=p_event;
 IF p_occasion IS NULL THEN RETURN jsonb_build_object('code',404); END IF;
 r:=public.submit_event_feedback_client_sync_v1(p_occasion,p_event,p_rating,p_note,p_client_id,extensions.gen_random_uuid());
 RETURN jsonb_build_object('code',r->'code','data',r#>'{data,feedback}','message',r#>'{data,message}');
END $$;

REVOKE ALL ON FUNCTION public.submit_event_feedback(bigint,text,text,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.submit_event_feedback(bigint,text,text,uuid) TO anon,authenticated,service_role;
