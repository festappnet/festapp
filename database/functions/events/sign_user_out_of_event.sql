CREATE OR REPLACE FUNCTION public.sign_user_out_of_event(ev bigint,usr uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE r jsonb;
BEGIN
 r:=public.set_event_attendance_client_sync_v1(ev,usr,'sign_out',extensions.gen_random_uuid());
 RETURN jsonb_build_object('code',r->'code','events_registration_start',r#>'{data,eventsRegistrationStart}');
EXCEPTION WHEN insufficient_privilege THEN RETURN jsonb_build_object('code',403);
END $$;

REVOKE ALL ON FUNCTION public.sign_user_out_of_event(bigint,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.sign_user_out_of_event(bigint,uuid) TO authenticated;
