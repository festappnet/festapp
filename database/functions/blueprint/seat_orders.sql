CREATE OR REPLACE FUNCTION public.preview_blueprint_seat_order(p_occasion bigint,p_organization bigint,p_unit bigint,
 p_blueprint bigint,p_spots bigint[],p_input jsonb DEFAULT NULL,p_editor boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ids bigint[];affected bigint[];analysis jsonb;effect jsonb;quote jsonb;result jsonb;conflicts jsonb;items jsonb;failure text;
BEGIN
 IF p_editor IS NULL OR (p_input IS NOT NULL AND (jsonb_typeof(p_input)<>'object'
  OR octet_length(p_input::text)>(CASE WHEN p_editor THEN 4194304 ELSE 1048576 END))) THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid order preview'; END IF;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true,true);
 PERFORM public.lock_blueprint_scope_internal(ARRAY[p_occasion]);
 IF NOT EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=p_blueprint AND occasion=p_occasion AND layout IS NOT NULL) THEN
  RAISE insufficient_privilege USING MESSAGE='canonical blueprint unavailable'; END IF;
 ids:=public.blueprint_seat_order_selection_internal(p_occasion,p_blueprint,p_spots,CASE WHEN p_editor THEN 20000 ELSE 1000 END);
 affected:=public.blueprint_order_affected_spots_internal(ids);
 IF cardinality(affected)>(CASE WHEN p_editor THEN 20000 ELSE 1000 END) THEN
  RAISE program_limit_exceeded USING MESSAGE='affected order seats exceed operation limit'; END IF;
 PERFORM public.check_blueprint_swap_scope_internal(p_occasion,affected);
 IF p_input IS NULL THEN
  BEGIN
   analysis:=public.analyze_new_order_spots(ids);
  EXCEPTION WHEN serialization_failure OR deadlock_detected OR insufficient_privilege THEN RAISE;
  WHEN OTHERS THEN
   PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true,true);
   GET STACKED DIAGNOSTICS failure=PG_EXCEPTION_DETAIL;
   RETURN public.blueprint_order_rejection_internal(SQLERRM,failure);
  END;
  conflicts:=public.blueprint_order_conflicts_internal(analysis);
  SELECT coalesce(jsonb_agg(jsonb_build_object('spotId',i->'spot_id','title',i->'spot_title','productTitle',i->'product_title',
   'amount',i->>'price','currencyCode',upper(btrim(i->>'currency'))) ORDER BY (i->>'spot_id')::bigint),'[]')
  INTO items FROM jsonb_array_elements(analysis->'new_order_items') i;
  result:=jsonb_build_object('code',200,'mode','requirements','actorId',auth.uid(),'occasionId',p_occasion,'blueprintId',p_blueprint,
   'requestedSpotIds',p_spots,'spotIds',ids,'affectedSpotIds',affected,'conflicts',conflicts,'items',items,
   'seatSubtotal',CASE WHEN EXISTS(SELECT 1 FROM jsonb_array_elements(analysis->'new_order_items') i WHERE i->>'price' IS NULL OR i->>'currency' IS NULL)
     THEN NULL ELSE analysis->>'total_price' END,'currencyCode',upper(btrim(analysis->>'currency')),
   'formKey',analysis#>'{order_form,key}','requiredFields',coalesce(analysis#>'{order_form,fields}','[]'),
   'phonePrefixes',analysis#>'{order_form,phone_prefixes}');
 ELSE
  -- The real creation/cancellation and queued side effects are all rolled back.
  -- Generated order/ticket IDs and email keys never enter the stable quote hash.
  BEGIN
   effect:=public.apply_blueprint_seat_order_internal(ids,p_input,extensions.gen_random_uuid());
   quote:=public.blueprint_seat_order_quote_internal(effect);
   RAISE SQLSTATE 'BP001' USING MESSAGE='rollback successful order quote';
  EXCEPTION WHEN SQLSTATE 'BP001' THEN NULL;
  WHEN serialization_failure OR deadlock_detected OR insufficient_privilege THEN RAISE;
  WHEN OTHERS THEN
   PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true,true);
   GET STACKED DIAGNOSTICS failure=PG_EXCEPTION_DETAIL;
   RETURN public.blueprint_order_rejection_internal(SQLERRM,failure);
  END;
  result:=jsonb_build_object('code',200,'mode','quote','actorId',auth.uid(),'occasionId',p_occasion,'blueprintId',p_blueprint,
   'requestedSpotIds',p_spots,'confirmationHash',effect->>'confirmationHash','quote',quote,
   'conflicts',public.blueprint_order_conflicts_internal(effect->'analysis',quote->'orders'));
 END IF;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true,true);
 IF octet_length(result::text)>(CASE WHEN p_editor THEN 8388608 ELSE 1048576 END) THEN
  RAISE program_limit_exceeded USING MESSAGE='order preview exceeds payload limit'; END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.preview_blueprint_seat_order(bigint,bigint,bigint,bigint,bigint[],jsonb,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.preview_blueprint_seat_order(bigint,bigint,bigint,bigint,bigint[],jsonb,boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_blueprint_seat_order(p_occasion bigint,p_organization bigint,p_unit bigint,
 p_blueprint bigint,p_spots bigint[],p_input jsonb,p_target_spots bigint[],p_affected_spots bigint[],p_blueprints jsonb,
 p_confirmation_hash text,p_command_id uuid,p_editor boolean DEFAULT false,p_expected_actor uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb;max_seats integer:=CASE WHEN p_editor THEN 20000 ELSE 1000 END;
BEGIN
 IF p_expected_actor IS DISTINCT FROM auth.uid() OR auth.uid() IS NULL THEN
  RAISE insufficient_privilege USING MESSAGE='confirmed order actor changed'; END IF;
 IF p_editor IS NULL OR p_command_id IS NULL OR p_confirmation_hash IS NULL OR p_confirmation_hash!~'^[0-9a-f]{64}$'
  OR jsonb_typeof(p_input) IS DISTINCT FROM 'object' OR octet_length(p_input::text)>(CASE WHEN p_editor THEN 4194304 ELSE 1048576 END)
  OR coalesce(cardinality(p_spots),0)=0 OR cardinality(p_spots)>max_seats
  OR coalesce(cardinality(p_target_spots),0)=0 OR cardinality(p_target_spots)>max_seats
  OR coalesce(cardinality(p_affected_spots),0)=0 OR cardinality(p_affected_spots)>max_seats
  OR jsonb_typeof(p_blueprints) IS DISTINCT FROM 'array' THEN
  RAISE invalid_parameter_value USING MESSAGE='confirmed seat order required'; END IF;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true,true);
 IF NOT EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=p_blueprint AND occasion=p_occasion AND layout IS NOT NULL)
  OR (SELECT count(*) FROM eshop.spots WHERE id=ANY(p_spots) AND occasion=p_occasion AND blueprint=p_blueprint)<>cardinality(p_spots) THEN
  RAISE insufficient_privilege USING MESSAGE='order seat selection unavailable'; END IF;
 result:=public.replace_blueprint_order_command_internal(p_spots,p_input,p_command_id,
  jsonb_build_object('hash',p_confirmation_hash,'blueprint',p_blueprint,'targets',p_target_spots,
   'affected',p_affected_spots,'blueprints',p_blueprints));
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true,true);
 IF (SELECT count(*) FROM eshop.spots WHERE id=ANY(p_spots) AND occasion=p_occasion AND blueprint=p_blueprint)<>cardinality(p_spots) THEN
  RAISE insufficient_privilege USING MESSAGE='order seat selection unavailable'; END IF;
 IF NOT p_editor THEN
  result:=result-'sync';
  IF result->>'status' IN('applied','unchanged') THEN
   result:=jsonb_set(result,'{data}',jsonb_build_object('code',result#>'{data,code}',
    'orderId',result#>'{data,order,id}','orderSymbol',result#>'{data,order,order_symbol}','quote',jsonb_set((result#>'{data,quote}')-'seats','{newOrder}',(result#>'{data,quote,newOrder}')-'products')));
  END IF;
 END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.create_blueprint_seat_order(bigint,bigint,bigint,bigint,bigint[],jsonb,bigint[],bigint[],jsonb,text,uuid,boolean,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.create_blueprint_seat_order(bigint,bigint,bigint,bigint,bigint[],jsonb,bigint[],bigint[],jsonb,text,uuid,boolean,uuid) TO authenticated;
