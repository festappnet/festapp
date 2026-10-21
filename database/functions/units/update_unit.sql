-- Released legacy unit editor: locked compatibility baseline, one command owner.
CREATE OR REPLACE FUNCTION public.update_unit(p_unit_id bigint,p_title text,p_data jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_version bigint; v_result jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT public.can_manage_unit_configuration(p_unit_id) THEN
  RAISE insufficient_privilege USING MESSAGE='unit manager required'; END IF;
 PERFORM 1 FROM public.units WHERE id=p_unit_id FOR UPDATE;
 SELECT coalesce(v.version,0) INTO v_version FROM (SELECT 1) seed
 LEFT JOIN public.client_aggregate_versions v ON v.aggregate_type='unit'
 AND v.scope_type='unit' AND v.scope_id=p_unit_id AND v.aggregate_id=p_unit_id::text;
 v_result:=public.save_unit_client_sync_v1(p_unit_id,extensions.gen_random_uuid(),v_version,
  jsonb_build_object('id',p_unit_id,'title',p_title,'data',coalesce(p_data,'{}')));
 IF v_result->>'status' NOT IN ('applied','unchanged') THEN
  RAISE EXCEPTION 'unit save rejected: %',v_result->>'code'; END IF;
END $$;

REVOKE ALL ON FUNCTION public.update_unit(bigint,text,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_unit(bigint,text,jsonb) TO authenticated;
