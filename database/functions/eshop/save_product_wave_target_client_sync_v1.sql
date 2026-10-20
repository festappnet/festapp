-- One intention: resolve/create the wave and save its target, including adoption.
CREATE OR REPLACE FUNCTION public.save_product_wave_target_client_sync_v1(p_target jsonb,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE oc bigint; actor uuid:=auth.uid(); begin_result jsonb; hash text; wave jsonb; wave_id bigint; users uuid[];
BEGIN
 IF p_target IS NULL OR jsonb_typeof(p_target) IS DISTINCT FROM 'object' OR octet_length(p_target::text)>8192
  OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_target) k WHERE k NOT IN ('occasion_link','product_id','wave_id','change_time',
    'expected_wave_revision','price','is_hidden','expected_price_revision','expected_visibility_revision'))
  OR ((p_target->>'wave_id' IS NOT NULL)::integer+(p_target->>'change_time' IS NOT NULL)::integer)<>1
  OR NOT p_target ?& ARRAY['occasion_link','product_id','price','is_hidden','expected_price_revision','expected_visibility_revision']
 THEN RAISE invalid_parameter_value USING MESSAGE='invalid wave target'; END IF;
 oc:=public.resolve_occasion_link_internal(p_target->>'occasion_link');
 IF actor IS NULL OR oc IS NULL THEN RAISE insufficient_privilege USING MESSAGE='wave editor required'; END IF;
 PERFORM public.check_product_wave_editor(oc);
 IF NOT EXISTS(SELECT 1 FROM eshop.products WHERE id=(p_target->>'product_id')::bigint AND occasion=oc) THEN
  RAISE insufficient_privilege USING MESSAGE='PRODUCT_OCCASION_MISMATCH'; END IF;
 hash:=encode(extensions.digest(convert_to(p_target::text,'UTF8'),'sha256'),'hex');
 begin_result:=public.begin_client_mutation_v1(p_command_id,'inventory.wave.target.save',oc,actor,hash);
 IF begin_result->>'disposition'='replay' THEN RETURN begin_result->'response'; END IF;
 IF p_target->>'wave_id' IS NULL THEN
  wave:=public.create_product_price_wave(p_target->>'occasion_link',(p_target->>'change_time')::timestamptz);
  wave_id:=(wave->>'id')::bigint;
 ELSE
  wave_id:=(p_target->>'wave_id')::bigint;
  SELECT to_jsonb(w) INTO wave FROM eshop.product_price_waves w WHERE id=wave_id AND occasion=oc FOR UPDATE;
  IF wave IS NULL THEN RAISE insufficient_privilege USING MESSAGE='foreign wave'; END IF;
  IF p_target->>'expected_wave_revision' IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='wave revision required'; END IF;
 END IF;
 PERFORM public.save_product_wave_target(wave_id,(p_target->>'product_id')::bigint,
  CASE WHEN p_target->>'wave_id' IS NULL THEN (wave->>'revision')::bigint ELSE (p_target->>'expected_wave_revision')::bigint END,
  (p_target->>'price')::numeric,(p_target->>'is_hidden')::boolean,
  (p_target->>'expected_price_revision')::bigint,(p_target->>'expected_visibility_revision')::bigint);
 SELECT coalesce(array_agg(DISTINCT ou."user"),'{}') INTO users FROM public.occasion_users ou
 JOIN eshop.order_product_ticket opt ON opt.ticket=ou.ticket WHERE ou.occasion=oc AND opt.product=(p_target->>'product_id')::bigint;
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,oc,'inventory.wave.target.save',
  jsonb_build_array(jsonb_build_object('entityType','product_price_wave','entityId',wave_id,'operation','update',
   'safeLabel','Product price wave','changedFields',jsonb_build_array('targets'))),users,jsonb_build_object('wave',wave,'productId',p_target->'product_id'));
END $$;
REVOKE ALL ON FUNCTION public.save_product_wave_target_client_sync_v1(jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_product_wave_target_client_sync_v1(jsonb,uuid) TO authenticated;
