CREATE OR REPLACE FUNCTION public.update_resource(p_input jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_id bigint:=(p_input->>'id')::bigint; pool bigint:=(p_input->>'inventory_pool')::bigint; oc bigint; v bigint; current_row jsonb:='{}'; normalized jsonb; result jsonb;
BEGIN
 SELECT occasion INTO oc FROM public.inventory_pools WHERE inventory_pools.id=pool;
 PERFORM public.check_is_editor_order_on_occasion(oc);
 PERFORM public.lock_resource_pools_internal_v1(v_id,pool);
 IF v_id IS NOT NULL THEN
  SELECT to_jsonb(r) INTO current_row FROM public.resources r WHERE r.id=v_id AND r.occasion=oc FOR UPDATE;
  IF current_row IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='resource unavailable'; END IF;
  SELECT coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='resource' AND scope_type='occasion' AND scope_id=oc AND aggregate_id=v_id::text),0) INTO v;
 END IF;
 normalized:=coalesce(current_row,'{}')||p_input;
 SELECT jsonb_object_agg(key,value) INTO normalized FROM jsonb_each(normalized)
 WHERE key IN ('id','title','capacity','booking_rules','inventory_pool');
 result:=public.save_resource_client_sync_v1(oc,extensions.gen_random_uuid(),v,normalized);
 IF result->>'code'<>'200' THEN RAISE serialization_failure USING MESSAGE='resource save rejected'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.update_resource(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_resource(jsonb) TO authenticated;
