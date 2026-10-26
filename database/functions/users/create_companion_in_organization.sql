-- Released self-create response adapter; the command owns account and relation effects.
CREATE OR REPLACE FUNCTION public.create_companion_in_organization(oc bigint,c_name text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_result jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS (SELECT 1 FROM public.occasion_users
  WHERE occasion=oc AND "user"=auth.uid()) THEN RETURN jsonb_build_object('code',403); END IF;
 v_result:=public.create_companion_client_sync_v1(oc,c_name,extensions.gen_random_uuid());
 RETURN jsonb_build_object('code',v_result->'code');
END $$;

REVOKE ALL ON FUNCTION public.create_companion_in_organization(bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_companion_in_organization(bigint,text) TO authenticated;
