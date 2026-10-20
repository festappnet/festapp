CREATE OR REPLACE FUNCTION public.add_user_to_occasion(oc bigint,usr uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE r jsonb;
BEGIN
 r:=public.add_user_to_occasion_client_sync_v1(oc,usr,extensions.gen_random_uuid());
 RETURN jsonb_build_object('code',r->'code');
END $$;
REVOKE ALL ON FUNCTION public.add_user_to_occasion(bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.add_user_to_occasion(bigint,uuid) TO authenticated;
