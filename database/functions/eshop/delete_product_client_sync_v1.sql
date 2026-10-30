CREATE OR REPLACE FUNCTION public.delete_product_domain_command_internal_v1(p_product_id bigint,p_command_id uuid,p_expected_version bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE actor uuid:=auth.uid(); oc bigint; title text; begin_result jsonb; hash text; version bigint; used bigint; original_key uuid;
BEGIN
 SELECT occasion INTO oc FROM public.client_mutation_receipts WHERE command_id=p_command_id AND actor_id=actor AND command_name='inventory.product.delete';
 IF NOT FOUND THEN SELECT t.occasion INTO oc FROM eshop.products t WHERE id=p_product_id; END IF;
 IF actor IS NULL OR oc IS NULL OR public.can_write_orders(oc) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='product editor required'; END IF;
 hash:=encode(extensions.digest(convert_to((jsonb_build_object('productId',p_product_id)||CASE WHEN p_expected_version IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('expectedVersion',p_expected_version) END)::text,'UTF8'),'sha256'),'hex');
 begin_result:=public.begin_client_mutation_v1(p_command_id,'inventory.product.delete',oc,actor,hash);
 IF begin_result->>'disposition'='replay' THEN RETURN begin_result->'response'; END IF;
 PERFORM public.lock_primary_product_forms_internal(p_product_id);
 PERFORM public.lock_product_order_dependencies_internal_v1(p_product_id);
 SELECT t.title INTO title FROM eshop.products t WHERE id=p_product_id AND occasion=oc FOR UPDATE;
 IF NOT FOUND THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',404,jsonb_build_object('productId',p_product_id)); END IF;
 SELECT coalesce(v.version,0) INTO version FROM (SELECT 1) seed LEFT JOIN public.client_aggregate_versions v
 ON v.aggregate_type='product' AND v.scope_type='occasion' AND v.scope_id=oc AND v.aggregate_id=p_product_id::text;
 IF p_expected_version IS NOT NULL AND p_expected_version IS DISTINCT FROM version THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('aggregate_version',version)); END IF;
 SELECT count(*) INTO used FROM eshop.order_product_ticket WHERE product=p_product_id;
 IF used>0 THEN RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('message','product is in use')); END IF;
 PERFORM public.delete_product_internal_v1(p_product_id);
 DELETE FROM public.client_aggregate_versions WHERE aggregate_type='product' AND scope_type='occasion' AND scope_id=oc AND aggregate_id=p_product_id::text;
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,oc,'inventory.product.delete',jsonb_build_array(jsonb_build_object('entityType','product','entityId',p_product_id,'operation','delete','safeLabel',left(title,240),'changedFields',jsonb_build_array('aggregate'))),'{}'::uuid[],jsonb_build_object('productId',p_product_id));
END $$;
REVOKE ALL ON FUNCTION public.delete_product_domain_command_internal_v1(bigint,uuid,bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.delete_product_client_sync_v1(p_product_id bigint,p_command_id uuid,p_expected_version bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF p_expected_version IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='original product version required'; END IF;
 RETURN public.delete_product_domain_command_internal_v1(p_product_id,p_command_id,p_expected_version);
END $$;
REVOKE ALL ON FUNCTION public.delete_product_client_sync_v1(bigint,uuid,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_product_client_sync_v1(bigint,uuid,bigint) TO authenticated;
-- Published two-argument shape retains its original receipt hash. It cannot
-- reconstruct an editor baseline and remains subject to the client upgrade gate.
CREATE OR REPLACE FUNCTION public.delete_product_client_sync_v1(p_product_id bigint,p_command_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.delete_product_domain_command_internal_v1(p_product_id,p_command_id,NULL);
$$;
REVOKE ALL ON FUNCTION public.delete_product_client_sync_v1(bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_product_client_sync_v1(bigint,uuid) TO authenticated;
