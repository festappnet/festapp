-- Product scheduling adapters share the existing wave/plan owners. Target saves
-- retain their existing receipt; the remaining intentions get exactly one here.
CREATE OR REPLACE FUNCTION public.manage_product_schedule(p_occasion bigint,p_organization bigint,p_unit bigint,
 p_action text,p_payload jsonb,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb; started jsonb; hash text; command_name text; link text;
 wave jsonb; change jsonb; wave_id bigint; product_id bigint; allowed text[]; fields text[]; users uuid[]; constraint_name text;
BEGIN
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true);
 IF p_action IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object' OR octet_length(p_payload::text)>8192 THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid product schedule'; END IF;
 CASE p_action
 WHEN 'save_target' THEN
  allowed:=ARRAY['product_id','wave_id','change_time','expected_wave_revision','price','is_hidden','expected_price_revision','expected_visibility_revision'];
  fields:=ARRAY['product_id','price','is_hidden','expected_price_revision','expected_visibility_revision'];
 WHEN 'ensure_wave' THEN allowed:=ARRAY['change_time'];fields:=allowed;
 WHEN 'move_wave' THEN allowed:=ARRAY['wave_id','expected_wave_revision','change_time'];fields:=allowed;
 WHEN 'cancel_wave' THEN allowed:=ARRAY['wave_id','expected_wave_revision'];fields:=allowed;
 WHEN 'save_price_change' THEN allowed:=ARRAY['product_id','price','change_time','change_id','expected_revision'];fields:=ARRAY['product_id','price','change_time'];
 WHEN 'cancel_price_change' THEN allowed:=ARRAY['product_id','change_id','expected_revision'];fields:=allowed;
 ELSE RAISE invalid_parameter_value USING MESSAGE='invalid product schedule action';
 END CASE;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_payload) k WHERE NOT k=ANY(allowed)) OR NOT p_payload ?& fields THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid product schedule fields'; END IF;
 SELECT o.link INTO link FROM public.occasions o WHERE o.id=p_occasion;
 IF p_action='save_target' THEN
  result:=public.save_product_wave_target_client_sync_v1(p_payload||jsonb_build_object('occasion_link',link),p_command_id);
 ELSE
  command_name:='inventory.schedule.'||p_action;
  hash:=encode(extensions.digest(convert_to(jsonb_build_object('occasion',p_occasion,'action',p_action,'payload',p_payload)::text,'UTF8'),'sha256'),'hex');
  started:=public.begin_client_mutation_v1(p_command_id,command_name,p_occasion,auth.uid(),hash);
  IF started->>'disposition'='replay' THEN
   result:=started->'response';
  ELSE
   BEGIN
    wave_id:=(p_payload->>'wave_id')::bigint;
    product_id:=(p_payload->>'product_id')::bigint;
    -- Lock the actual aggregate after its receipt, in the owner's lock order.
    -- Scope is checked on the locked row, not an earlier Node lookup.
    IF wave_id IS NOT NULL THEN
     PERFORM 1 FROM eshop.product_price_waves WHERE id=wave_id AND occasion=p_occasion FOR UPDATE;
     IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='wave unavailable'; END IF;
    END IF;
    IF product_id IS NOT NULL THEN
     PERFORM 1 FROM eshop.products p JOIN eshop.product_types pt ON pt.id=p.product_type
      WHERE p.id=product_id AND p.occasion=p_occasion AND pt.occasion=p_occasion FOR UPDATE OF p;
     IF NOT FOUND THEN RAISE insufficient_privilege USING MESSAGE='product unavailable'; END IF;
    END IF;
    CASE p_action
    WHEN 'ensure_wave' THEN
     wave:=public.create_product_price_wave(link,(p_payload->>'change_time')::timestamptz);wave_id:=(wave->>'id')::bigint;
    WHEN 'move_wave' THEN
     wave:=public.move_product_price_wave(wave_id,(p_payload->>'expected_wave_revision')::bigint,(p_payload->>'change_time')::timestamptz);
    WHEN 'cancel_wave' THEN
     PERFORM public.cancel_product_price_wave(wave_id,(p_payload->>'expected_wave_revision')::bigint);
    WHEN 'save_price_change' THEN
     change:=public.save_product_price_change(product_id,(p_payload->>'price')::numeric,(p_payload->>'change_time')::timestamptz,
      (p_payload->>'change_id')::bigint,(p_payload->>'expected_revision')::bigint);
    WHEN 'cancel_price_change' THEN
     PERFORM public.cancel_product_price_change(product_id,(p_payload->>'change_id')::bigint,(p_payload->>'expected_revision')::bigint);
    END CASE;
    -- The existing complete owner publishes one sync/audit receipt. No provider,
    -- mail, historical order price or paid transition is performed here.
    result:=public.complete_private_inventory_mutation_v1(p_command_id,p_occasion,command_name,
     jsonb_build_array(jsonb_build_object('entityType',CASE WHEN wave_id IS NULL THEN 'product' ELSE 'product_price_wave' END,
      'entityId',coalesce(wave_id,product_id),'operation',CASE WHEN p_action LIKE 'cancel%' THEN 'delete' ELSE 'update' END,
      'safeLabel','Product schedule','changedFields',jsonb_build_array('planned_changes'))),'{}'::uuid[],
     jsonb_build_object('waveId',wave_id,'productId',product_id,'wave',wave,'change',change,'targets','[]'::jsonb));
   EXCEPTION WHEN serialization_failure THEN
    IF SQLERRM<>'PRICE_CHANGE_CONFLICT' THEN RAISE; END IF;
    result:=public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('reason','PRICE_CHANGE_CONFLICT'));
   WHEN invalid_parameter_value THEN
    IF SQLERRM NOT IN ('FUTURE_TIME_REQUIRED','INVALID_PRODUCT_PRICE','DEPOSIT_AMOUNT_TOO_HIGH','BLUEPRINT_PRODUCT_VISIBILITY_NOT_SUPPORTED','WAVE_ALREADY_APPLIED','INVALID_REVISION') THEN RAISE; END IF;
    result:=public.complete_client_mutation_outcome_v1(p_command_id,'rejected',422,jsonb_build_object('reason',SQLERRM));
   WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS constraint_name=CONSTRAINT_NAME;
    IF constraint_name<>'product_price_waves_occasion_change_time_key' THEN RAISE; END IF;
    result:=public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('reason','PRICE_CHANGE_CONFLICT'));
   END;
  END IF;
 END IF;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,true,true);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.manage_product_schedule(bigint,bigint,bigint,text,jsonb,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.manage_product_schedule(bigint,bigint,bigint,text,jsonb,uuid) TO authenticated;

-- The same term projection feeds the administration matrix and MCP wave list.
CREATE OR REPLACE FUNCTION public.get_product_price_waves_internal(p_occasion bigint,p_after bigint DEFAULT NULL,p_limit integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE ids bigint[]; next_id bigint; waves jsonb;
BEGIN
 IF p_limit IS NOT NULL AND (p_limit<1 OR p_limit>100) OR p_after IS NOT NULL AND p_after<1 THEN
  RAISE invalid_parameter_value USING MESSAGE='invalid wave page'; END IF;
 SELECT coalesce(array_agg(id ORDER BY id),'{}'::bigint[]) INTO ids FROM (
  SELECT w.id FROM eshop.product_price_waves w WHERE w.occasion=p_occasion AND (p_after IS NULL OR w.id>p_after)
   AND (w.change_time>statement_timestamp() OR EXISTS(SELECT 1 FROM eshop.planned_changes pc WHERE pc.wave_id=w.id AND NOT pc.applied))
   ORDER BY w.id LIMIT CASE WHEN p_limit IS NULL THEN NULL ELSE p_limit+1 END) selected;
 IF cardinality(ids)>p_limit THEN ids:=ids[1:p_limit];next_id:=ids[p_limit]; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',w.id,'occasion',w.occasion,'change_time',w.change_time,'revision',w.revision,
  'pending_product_count',counts.products,'pending_change_count',counts.pending,'applied_change_count',counts.applied) ORDER BY w.id),'[]') INTO waves
 FROM eshop.product_price_waves w CROSS JOIN LATERAL (
  SELECT count(DISTINCT subject_id) FILTER(WHERE NOT applied) products,
    count(*) FILTER(WHERE NOT applied) pending,count(*) FILTER(WHERE applied) applied
  FROM eshop.planned_changes WHERE wave_id=w.id) counts WHERE w.id=ANY(ids);
 RETURN jsonb_build_object('waves',waves,'nextCursor',next_id);
END $$;
REVOKE ALL ON FUNCTION public.get_product_price_waves_internal(bigint,bigint,integer) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_product_schedule(p_occasion bigint,p_organization bigint,p_unit bigint,
 p_after bigint DEFAULT NULL,p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 IF p_limit IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='bounded wave page required'; END IF;
 PERFORM public.check_product_catalog_scope_internal(p_occasion,p_organization,p_unit,false,true);
 RETURN jsonb_build_object('occasionId',p_occasion)||public.get_product_price_waves_internal(p_occasion,p_after,p_limit);
END $$;
REVOKE ALL ON FUNCTION public.get_product_schedule(bigint,bigint,bigint,bigint,integer) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_product_schedule(bigint,bigint,bigint,bigint,integer) TO authenticated;
