CREATE OR REPLACE FUNCTION public.save_resource_client_sync_v1(p_occasion bigint,p_command_id uuid,p_expected_version bigint,p_resource jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE actor uuid:=auth.uid(); hash text; started jsonb; result jsonb; entity jsonb; impacts jsonb; replacements jsonb:='[]';
BEGIN
 IF actor IS NULL OR NOT public.can_write_orders(p_occasion) THEN
  RAISE insufficient_privilege USING MESSAGE='occasion order editor required'; END IF;
 IF p_resource->'booking_rules'='null'::jsonb THEN p_resource:=jsonb_set(p_resource,'{booking_rules}','{}'); END IF;
 hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,
  'expectedVersion',p_expected_version,'resource',p_resource)::text,'UTF8'),'sha256'),'hex');
 started:=public.begin_client_mutation_v1(p_command_id,'inventory.resource.save',p_occasion,actor,hash);
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 result:=public.save_inventory_resource_internal(p_occasion,p_expected_version,p_resource);
 IF result->>'status'<>'applied' THEN
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,result->>'status',(result->>'code')::integer,result->'data');
 END IF;
 entity:=result#>'{data,resource}';
 SELECT coalesce(jsonb_agg(jsonb_build_object('component','private_inventory','userId',ou."user")),'[]') INTO impacts
 FROM public.occasion_users ou WHERE ou.occasion=p_occasion;
 IF EXISTS(SELECT 1 FROM public.occasion_users ou WHERE ou.occasion=p_occasion AND ou."user"=actor) THEN
  replacements:=jsonb_build_array(jsonb_build_object('component','private_inventory','userId',actor,
   'payload',public.get_user_inventory_for_occasion_v1(p_occasion)));
 END IF;
 RETURN public.complete_client_mutation_applied_v1(p_command_id,p_occasion,'inventory.resource.save','inventory',
  jsonb_build_array(jsonb_build_object('entityType','resource','entityId',(entity->>'id')::bigint,
   'operation',CASE WHEN p_resource->>'id' IS NULL THEN 'insert' ELSE 'update' END,
   'safeLabel',left(entity->>'title',240),'changedFields',jsonb_build_array('aggregate'))),
  '{}',impacts,'[]',result->'data','{}','[]','user',NULL,replacements);
END $$;
REVOKE ALL ON FUNCTION public.save_resource_client_sync_v1(bigint,uuid,bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_resource_client_sync_v1(bigint,uuid,bigint,jsonb) TO authenticated;
