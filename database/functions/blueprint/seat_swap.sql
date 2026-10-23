CREATE OR REPLACE FUNCTION public.preview_blueprint_seat_swap(p_occasion bigint,p_organization bigint,p_unit bigint,
 p_blueprint bigint,p_first bigint,p_second bigint,p_editor boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE effect jsonb;rows jsonb;money jsonb;ids bigint[];
BEGIN
 IF p_editor IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='swap preview mode required'; END IF;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true,true);
 PERFORM public.lock_blueprint_scope_internal(ARRAY[p_occasion]);
 -- The shared occasion advisory scope stabilizes membership. Row locks are
 -- acquired by the financial owner after form/order parents, never before them.
 IF NOT EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=p_blueprint AND occasion=p_occasion AND layout IS NOT NULL) THEN
  RAISE insufficient_privilege USING MESSAGE='canonical blueprint unavailable'; END IF;
 ids:=public.blueprint_hold_selection_internal(p_occasion,p_blueprint,ARRAY[p_first,p_second],CASE WHEN p_editor THEN 20000 ELSE 1000 END);
 effect:=public.preview_blueprint_swap(p_first,p_second);
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true,true);
 IF (effect->>'code')::int<>200 THEN
  RETURN jsonb_build_object('code',409,'reason',CASE WHEN effect->>'reason'=ANY(ARRAY[
   'BLUEPRINT_UNIT_SIZE_MISMATCH','BLUEPRINT_SELECTION_UNIT_USED','BLUEPRINT_CURRENCY_MISMATCH',
   'STRIPE_ORDER_PRICE_IMMUTABLE','BLUEPRINT_SEAT_PROTECTED','SPOT_HELD'])
   THEN effect->>'reason' ELSE 'BLUEPRINT_SWAP_REJECTED' END);
 END IF;
 SELECT coalesce(jsonb_agg(CASE WHEN p_editor THEN s ELSE s-'customer' END ORDER BY (s->>'spotId')::bigint),'[]')
 INTO rows FROM jsonb_array_elements(effect->'sides') s;
 BEGIN
  money:=public.project_order_amount_changes_internal(effect->'orders');
 EXCEPTION WHEN check_violation THEN
  RETURN jsonb_build_object('code',409,'reason','BLUEPRINT_SWAP_MONEY_UNAVAILABLE');
 END;
 effect:=jsonb_build_object('code',200,'occasionId',p_occasion,'blueprintId',p_blueprint,
  'layoutRevision',effect#>'{blueprints,0,revision}','firstSpotId',p_first,'secondSpotId',p_second,
  'sourceSpotIds',effect->'sourceSpotIds','targetSpotIds',effect->'targetSpotIds',
  'confirmationHash',effect->>'confirmationHash','seats',rows,'orders',money);
 IF octet_length(effect::text)>(CASE WHEN p_editor THEN 8388608 ELSE 1048576 END) THEN
  RAISE program_limit_exceeded USING MESSAGE='swap preview exceeds payload limit'; END IF;
 RETURN effect;
END $$;
REVOKE ALL ON FUNCTION public.preview_blueprint_seat_swap(bigint,bigint,bigint,bigint,bigint,bigint,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.preview_blueprint_seat_swap(bigint,bigint,bigint,bigint,bigint,bigint,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.swap_blueprint_seats(p_occasion bigint,p_organization bigint,p_unit bigint,
 p_blueprint bigint,p_first bigint,p_second bigint,p_source_spots bigint[],p_target_spots bigint[],
 p_expected_revision bigint,p_confirmation_hash text,p_command_id uuid,p_editor boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF p_editor IS NULL OR p_command_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<0
  OR p_confirmation_hash IS NULL OR p_confirmation_hash!~'^[0-9a-f]{64}$'
  OR coalesce(cardinality(p_source_spots),0)=0 OR coalesce(cardinality(p_target_spots),0)=0
  OR cardinality(p_source_spots)+cardinality(p_target_spots)>(CASE WHEN p_editor THEN 20000 ELSE 1000 END) THEN
  RAISE invalid_parameter_value USING MESSAGE='confirmed swap required'; END IF;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true,true);
 IF NOT EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=p_blueprint AND occasion=p_occasion AND layout IS NOT NULL)
  OR (SELECT count(*) FROM eshop.spots WHERE id IN(p_first,p_second) AND occasion=p_occasion AND blueprint=p_blueprint)<>2 THEN
  RAISE insufficient_privilege USING MESSAGE='swap selection unavailable'; END IF;
 result:=public.swap_blueprint_seats_command_internal(p_first,p_second,p_command_id,
  jsonb_build_object('hash',p_confirmation_hash,'source',to_jsonb(p_source_spots),'target',to_jsonb(p_target_spots),
   'blueprint',p_blueprint,'revision',p_expected_revision));
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true,true);
 IF (SELECT count(*) FROM eshop.spots WHERE id IN(p_first,p_second) AND occasion=p_occasion AND blueprint=p_blueprint)<>2 THEN
  RAISE insufficient_privilege USING MESSAGE='swap selection unavailable'; END IF;
 IF NOT p_editor THEN result:=result-'sync'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.swap_blueprint_seats(bigint,bigint,bigint,bigint,bigint,bigint,bigint[],bigint[],bigint,text,uuid,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.swap_blueprint_seats(bigint,bigint,bigint,bigint,bigint,bigint,bigint[],bigint[],bigint,text,uuid,boolean) TO authenticated;
