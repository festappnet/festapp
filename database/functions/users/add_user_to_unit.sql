-- Published RPC used by installed clients. Remove only after enforced upgrade.
-- Authenticated and receipt-backed; a bare service role cannot impersonate a manager.
CREATE OR REPLACE FUNCTION public.add_user_to_unit(unit_id bigint,usr uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 result:=public.add_user_to_unit_client_sync_v1(unit_id,usr,extensions.gen_random_uuid());
 RETURN jsonb_build_object('code',result->'code')||coalesce(result->'data','{}'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.add_user_to_unit(bigint,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.add_user_to_unit(bigint,uuid) TO authenticated,service_role;
