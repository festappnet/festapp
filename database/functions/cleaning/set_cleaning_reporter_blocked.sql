CREATE OR REPLACE FUNCTION public.set_cleaning_reporter_blocked_internal_v1(p_occasion bigint, p_user uuid, p_blocked boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_found boolean;
BEGIN
  IF v_caller IS NULL THEN
    RETURN jsonb_build_object('code', 401, 'message', 'Sign in is required');
  END IF;

  IF p_user IS NULL THEN
    RETURN jsonb_build_object('code', 400, 'message', 'Target user is required');
  END IF;

  -- Blocking needs crew rights; unblocking needs the higher editor right.
  IF p_blocked THEN
    IF NOT public.get_is_cleaning_crew_on_occasion(p_occasion) THEN
      RETURN jsonb_build_object('code', 403, 'message', 'Cleaning crew access required');
    END IF;
  ELSE
    IF NOT public.get_is_editor_on_occasion(p_occasion) THEN
      RETURN jsonb_build_object('code', 403, 'message', 'Editor access required to unblock');
    END IF;
  END IF;

  IF p_blocked THEN
    UPDATE public.occasion_users
    SET is_cleaning_blocked = true,
        data = COALESCE(data, '{}'::jsonb) || jsonb_build_object(
          'cleaning_blocked_by', v_caller::text,
          'cleaning_blocked_at', to_char(now(), 'YYYY-MM-DD"T"HH24:MI:SSOF'))
    WHERE occasion = p_occasion AND "user" = p_user
    RETURNING true INTO v_found;
  ELSE
    UPDATE public.occasion_users
    SET is_cleaning_blocked = false,
        data = COALESCE(data, '{}'::jsonb) - 'cleaning_blocked_by' - 'cleaning_blocked_at'
    WHERE occasion = p_occasion AND "user" = p_user
    RETURNING true INTO v_found;
  END IF;

  IF NOT COALESCE(v_found, false) THEN
    RETURN jsonb_build_object('code', 404, 'message', 'Participant not found on this occasion');
  END IF;

  RETURN jsonb_build_object(
    'code', 200,
    'data', jsonb_build_object('blocked', p_blocked)
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.set_cleaning_reporter_blocked_internal_v1(bigint,uuid,boolean) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.set_cleaning_reporter_blocked(p_occasion bigint,p_user uuid,p_blocked boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 result:=public.set_cleaning_reporter_blocked_client_sync_v1(p_occasion,p_user,p_blocked,extensions.gen_random_uuid());
 RETURN jsonb_build_object('code',result->'code','message',result#>'{data,message}','data',result->'data');
END $$;
REVOKE ALL ON FUNCTION public.set_cleaning_reporter_blocked(bigint,uuid,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_cleaning_reporter_blocked(bigint,uuid,boolean) TO authenticated;
