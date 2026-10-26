CREATE OR REPLACE FUNCTION public.check_inventory_entity_scope_internal(p_occasion bigint,p_pool bigint,p_resource bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF p_pool IS NOT NULL AND EXISTS(SELECT 1 FROM public.inventory_pools WHERE id=p_pool AND occasion IS DISTINCT FROM p_occasion)
  OR p_resource IS NOT NULL AND EXISTS(SELECT 1 FROM public.resources WHERE id=p_resource AND occasion IS DISTINCT FROM p_occasion) THEN
  RAISE insufficient_privilege USING MESSAGE='inventory entity unavailable'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_inventory_entity_scope_internal(bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- A scope boundary over one existing receipt owner, never an outer receipt.
CREATE OR REPLACE FUNCTION public.manage_inventory(p_occasion bigint,p_organization bigint,p_unit bigint,
 p_action text,p_payload jsonb,p_command_id uuid,p_editor boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;entity_id bigint;pool_id bigint;expected bigint;entity jsonb;
BEGIN
 IF p_action IS NULL OR p_action NOT IN ('save_pool','delete_pool','save_resource','delete_resource')
  OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR p_editor IS NULL
  OR p_command_id IS NULL OR octet_length(p_payload::text)>1048576 THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid inventory intention'; END IF;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true);
 expected:=(p_payload->>'expectedVersion')::bigint;
 IF expected<0 THEN RAISE invalid_parameter_value USING MESSAGE='invalid inventory version'; END IF;
 IF p_action='save_pool' THEN
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN ('bundle','expectedVersion'))
   OR (p_payload#>>'{bundle,pool,occasion}')::bigint IS DISTINCT FROM p_occasion THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid pool intention'; END IF;
  pool_id:=(p_payload#>>'{bundle,pool,id}')::bigint;
 ELSIF p_action='save_resource' THEN
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN ('resource','expectedVersion')) THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid resource intention'; END IF;
  entity_id:=(p_payload#>>'{resource,id}')::bigint;pool_id:=(p_payload#>>'{resource,inventory_pool}')::bigint;
  IF NOT EXISTS(SELECT 1 FROM public.inventory_pools WHERE id=pool_id AND occasion=p_occasion) THEN
   RAISE insufficient_privilege USING MESSAGE='inventory pool unavailable'; END IF;
 ELSE
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE k NOT IN ('id','expectedVersion'))
   OR p_payload->>'id' IS NULL OR expected IS NULL THEN
   RAISE invalid_parameter_value USING MESSAGE='original inventory id/version required'; END IF;
  entity_id:=(p_payload->>'id')::bigint;
  IF p_action='delete_pool' THEN pool_id:=entity_id; END IF;
 END IF;
 -- Reject an existing foreign entity before the domain owner locks dependencies.
 -- Missing deletes still reach the owner for durable unchanged/replay outcomes.
 PERFORM public.check_inventory_entity_scope_internal(p_occasion,pool_id,CASE WHEN p_action IN ('save_resource','delete_resource') THEN entity_id END);
 IF p_action='save_pool' THEN
  result:=public.save_inventory_pool_command_internal(p_occasion,p_command_id,expected,p_payload->'bundle',p_editor);
 ELSIF p_action='delete_pool' THEN
  result:=public.delete_inventory_pool_client_sync_v1(p_occasion,entity_id,p_command_id,expected);
 ELSIF p_action='save_resource' THEN
  result:=public.save_resource_client_sync_v1(p_occasion,p_command_id,expected,p_payload->'resource');
 ELSE
  result:=public.delete_resource_client_sync_v1(p_occasion,entity_id,p_command_id,expected);
 END IF;
 IF p_action='save_pool' THEN pool_id:=coalesce((result#>>'{data,bundle,pool,id}')::bigint,pool_id);
 ELSIF p_action='save_resource' THEN entity_id:=coalesce((result#>>'{data,resource,id}')::bigint,entity_id); END IF;
 PERFORM public.check_inventory_entity_scope_internal(p_occasion,pool_id,CASE WHEN p_action IN ('save_resource','delete_resource') THEN entity_id END);
 -- Includes receipt replay. A late scope failure rolls the entire intention back.
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true,true);
 IF NOT p_editor THEN
  IF p_action='save_resource' AND jsonb_typeof(result#>'{data,resource}')='object' THEN
   entity:=result#>'{data,resource}';
   result:=jsonb_set(result,'{data,resource}',jsonb_build_object('id',entity->'id','occasion',entity->'occasion',
    'inventory_pool',entity->'inventory_pool','title',entity->'title','capacity',entity->'capacity',
    'booking_rules',entity->'booking_rules','aggregate_version',entity->'aggregate_version'));
  END IF;
  result:=result-'sync';
 END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.manage_inventory(bigint,bigint,bigint,text,jsonb,uuid,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.manage_inventory(bigint,bigint,bigint,text,jsonb,uuid,boolean) TO authenticated;
