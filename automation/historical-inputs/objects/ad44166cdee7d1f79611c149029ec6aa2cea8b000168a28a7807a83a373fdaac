CREATE OR REPLACE FUNCTION public.set_cleaning_notifications_muted_internal_v1(p_occasion bigint, p_muted boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_found boolean;
BEGIN
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('code', 401, 'message', 'Sign in is required');
  END IF;

  UPDATE public.occasion_users
  SET data = COALESCE(data, '{}'::jsonb)
             || jsonb_build_object('cleaning_notifications_off', COALESCE(p_muted, false))
  WHERE occasion = p_occasion AND "user" = v_user
  RETURNING true INTO v_found;

  IF NOT COALESCE(v_found, false) THEN
    RETURN jsonb_build_object('code', 404, 'message', 'Participant not found on this occasion');
  END IF;

  RETURN jsonb_build_object(
    'code', 200,
    'data', jsonb_build_object('muted', COALESCE(p_muted, false))
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.set_cleaning_notifications_muted_internal_v1(bigint,boolean) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.set_cleaning_notifications_muted(p_occasion bigint,p_muted boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 result:=public.set_cleaning_notifications_muted_client_sync_v1(p_occasion,p_muted,extensions.gen_random_uuid());
 RETURN jsonb_build_object('code',result->'code','message',result#>'{data,message}','data',result->'data');
END $$;
REVOKE ALL ON FUNCTION public.set_cleaning_notifications_muted(bigint,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_cleaning_notifications_muted(bigint,boolean) TO authenticated;
