-- Shared administration/MCP product scheduling with one receipt per intention.
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
 BEGIN
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
 EXCEPTION WHEN serialization_failure THEN
  IF SQLERRM<>'PRICE_CHANGE_CONFLICT' THEN RAISE; END IF;
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('reason','PRICE_CHANGE_CONFLICT'));
 WHEN invalid_parameter_value THEN
  IF SQLERRM NOT IN ('FUTURE_TIME_REQUIRED','INVALID_PRODUCT_PRICE','DEPOSIT_AMOUNT_TOO_HIGH','BLUEPRINT_PRODUCT_VISIBILITY_NOT_SUPPORTED','WAVE_ALREADY_APPLIED','INVALID_REVISION') THEN RAISE; END IF;
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',422,jsonb_build_object('reason',SQLERRM));
 END;
 SELECT coalesce(array_agg(DISTINCT ou."user"),'{}') INTO users FROM public.occasion_users ou
 JOIN eshop.order_product_ticket opt ON opt.ticket=ou.ticket WHERE ou.occasion=oc AND opt.product=(p_target->>'product_id')::bigint;
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,oc,'inventory.wave.target.save',
  jsonb_build_array(jsonb_build_object('entityType','product_price_wave','entityId',wave_id,'operation','update',
   'safeLabel','Product price wave','changedFields',jsonb_build_array('targets'))),users,jsonb_build_object('waveId',wave_id,'change',NULL,'wave',wave,'productId',p_target->'product_id','targets',
   (SELECT coalesce(jsonb_agg(to_jsonb(pc) ORDER BY pc.id),'[]') FROM eshop.planned_changes pc
    WHERE pc.wave_id=(wave->>'id')::bigint AND pc.subject_id=(p_target->>'product_id')::bigint AND NOT pc.applied)));
END $$;
REVOKE ALL ON FUNCTION public.save_product_wave_target_client_sync_v1(jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_product_wave_target_client_sync_v1(jsonb,uuid) TO authenticated;

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

-- The canonical entrypoint retains Client Sync v1 delivery.
CREATE OR REPLACE FUNCTION public.apply_planned_changes_client_sync_v1()
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_candidate record; v_change eshop.planned_changes%ROWTYPE;
  v_product eshop.products%ROWTYPE; v_occasion bigint; v_impacts jsonb; v_changed integer;
  v_failure text;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  -- Serializes workers, including backlog across multiple instants of one product.
  IF NOT pg_try_advisory_xact_lock(7310420261004::bigint) THEN RETURN; END IF;
  -- Hold all due products in ID order for the transaction. The former time/ID
  -- loop could lock product B then A while a wave move locked A then B.
  PERFORM 1 FROM eshop.products p WHERE EXISTS(SELECT 1 FROM eshop.planned_changes pc
    WHERE pc.subject_id=p.id AND pc.change_type IN ('products.price','products.is_hidden')
     AND NOT public.is_demo_occasion(pc.occasion) AND pc.change_time<=now() AND NOT pc.applied AND pc.failed_at IS NULL)
    ORDER BY p.id FOR UPDATE;
  FOR v_candidate IN SELECT id,subject_id,change_type FROM eshop.planned_changes
    WHERE NOT public.is_demo_occasion(occasion) AND change_time<=now() AND NOT applied AND failed_at IS NULL ORDER BY change_time,id
  LOOP
    -- Same lock order as editor commands: subject, then plan. Recheck after lock.
    IF v_candidate.change_type IN ('products.price','products.is_hidden') THEN
      PERFORM 1 FROM eshop.products WHERE id=v_candidate.subject_id FOR UPDATE;
    ELSIF v_candidate.change_type='forms.is_open' THEN
      PERFORM 1 FROM public.forms WHERE id=v_candidate.subject_id FOR UPDATE;
    END IF;
    SELECT * INTO v_change FROM eshop.planned_changes WHERE id=v_candidate.id FOR UPDATE;
    IF NOT FOUND OR v_change.applied OR v_change.failed_at IS NOT NULL OR v_change.change_time>now() THEN CONTINUE; END IF;
    BEGIN
      v_changed:=0; v_occasion:=NULL; v_impacts:='[]'::jsonb;
      IF v_change.change_type IN ('products.price','products.is_hidden') THEN
        SELECT * INTO v_product FROM eshop.products WHERE id=v_change.subject_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_SUBJECT'; END IF;
        SELECT occasion INTO v_occasion FROM eshop.product_types WHERE id=v_product.product_type;
        IF v_occasion IS NULL OR v_change.occasion IS DISTINCT FROM v_occasion
          OR v_product.occasion IS DISTINCT FROM v_occasion THEN RAISE EXCEPTION 'INVALID_OCCASION'; END IF;
        IF v_change.change_type='products.price' THEN
          PERFORM public.validate_product_price(v_change.new_value::numeric,v_product.data,v_product.currency_code);
          UPDATE eshop.products SET price=v_change.new_value::numeric,updated_at=now()
          WHERE id=v_change.subject_id AND price IS DISTINCT FROM v_change.new_value::numeric;
        ELSE
          UPDATE eshop.products SET is_hidden=v_change.new_value::boolean,updated_at=now()
          WHERE id=v_change.subject_id AND is_hidden IS DISTINCT FROM v_change.new_value::boolean;
        END IF;
        GET DIAGNOSTICS v_changed=ROW_COUNT;
      ELSIF v_change.change_type='forms.is_open' THEN
        SELECT occasion INTO v_occasion FROM public.forms WHERE id=v_change.subject_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_SUBJECT'; END IF;
        IF v_occasion IS NULL OR v_change.occasion IS DISTINCT FROM v_occasion THEN RAISE EXCEPTION 'INVALID_OCCASION'; END IF;
        UPDATE public.forms SET is_open=v_change.new_value::boolean,
          data=CASE WHEN v_change.new_value::boolean THEN jsonb_set(coalesce(data,'{}'::jsonb),'{schedule}',
            coalesce(data->'schedule','{}'::jsonb)||'{"sale_preparation":false}'::jsonb) ELSE data END
          WHERE id=v_change.subject_id AND is_open IS DISTINCT FROM v_change.new_value::boolean;
        GET DIAGNOSTICS v_changed=ROW_COUNT;
      ELSE RAISE EXCEPTION 'UNKNOWN_CHANGE_TYPE'; END IF;
      IF v_changed>0 THEN
        IF v_change.change_type='forms.is_open' THEN
          INSERT INTO public.client_aggregate_versions(aggregate_type,scope_type,scope_id,aggregate_id,version)
          VALUES('form','occasion',v_occasion,v_change.subject_id::text,1)
          ON CONFLICT(aggregate_type,scope_type,scope_id,aggregate_id) DO UPDATE
          SET version=public.client_aggregate_versions.version+1,updated_at=clock_timestamp();
          PERFORM public.record_client_sync_commit_v1(v_occasion,'inventory.form.planned','inventory',
            jsonb_build_array(jsonb_build_object('entityType','form','entityId',v_change.subject_id,
              'operation','update','safeLabel','Scheduled form change','changedFields',jsonb_build_array('is_open'))),
            '{}','[]','[]','service','planned_change:'||v_change.id::text);
        ELSE
        PERFORM public.advance_ticketing_authoring_version_internal_v1('product',v_occasion,v_change.subject_id);
        SELECT COALESCE(jsonb_agg(jsonb_build_object('component','private_inventory','userId',ou."user")),'[]'::jsonb)
          INTO v_impacts FROM eshop.order_product_ticket opt JOIN public.occasion_users ou
          ON ou.ticket=opt.ticket AND ou.occasion=v_occasion WHERE opt.product=v_change.subject_id;
        PERFORM public.record_client_sync_commit_v1(v_occasion,
          'inventory.product.planned','inventory',jsonb_build_array(jsonb_build_object(
          'entityType','product','entityId',v_change.subject_id,'operation','update',
          'safeLabel','Scheduled product change','changedFields',jsonb_build_array(split_part(v_change.change_type,'.',2)))),
          '{}',v_impacts,'[]','service','planned_change:'||v_change.id::text);
        END IF;
      END IF;
      UPDATE eshop.planned_changes SET applied=true,revision=revision+1 WHERE id=v_change.id;
    EXCEPTION WHEN OTHERS THEN
      -- This subtransaction rolls back price AND sync on any failure.
      v_failure := CASE WHEN SQLERRM IN ('INVALID_SUBJECT','INVALID_OCCASION','UNKNOWN_CHANGE_TYPE',
        'INVALID_PRODUCT_PRICE','DEPOSIT_AMOUNT_TOO_HIGH') THEN SQLERRM
        WHEN SQLSTATE IN ('22P02','22003') THEN 'INVALID_VALUE' ELSE 'APPLICATION_FAILED' END;
      UPDATE eshop.planned_changes SET failed_at=clock_timestamp(),failure_code=v_failure,revision=revision+1 WHERE id=v_change.id;
    END;
  END LOOP;
END; $$;
REVOKE ALL ON FUNCTION public.apply_planned_changes_client_sync_v1() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.apply_planned_changes_client_sync_v1() TO service_role;
CREATE OR REPLACE FUNCTION public.apply_planned_changes()
RETURNS void LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
  SELECT public.apply_planned_changes_client_sync_v1();
$$;
REVOKE ALL ON FUNCTION public.apply_planned_changes() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.apply_planned_changes() TO service_role;

-- One projection for the complete UI bundle and bounded product pages.
-- Internal only: callers own tenant/permission checks. NULL limit is the
-- explicit complete editor mode; pages use ID keysets, not a collection snapshot.
CREATE OR REPLACE FUNCTION public.get_product_catalog_data_internal(
 p_occasion bigint,p_after bigint DEFAULT NULL,p_limit integer DEFAULT NULL)
RETURNS json LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = public, extensions AS $$
DECLARE
  product_types json;
  products json;
  inventory_pools_data json;
  inventory_contexts_data json;
  product_inventory_contexts_data json;
  forms_data json;
  occ_id bigint := p_occasion;
  selected_ids bigint[];
  next_id bigint;
BEGIN
  IF p_limit IS NOT NULL AND (p_limit<1 OR p_limit>100) OR p_after IS NOT NULL AND p_after<1 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid catalog page';
  END IF;
  SELECT coalesce(array_agg(id ORDER BY id),'{}'::bigint[]) INTO selected_ids
  FROM (SELECT p.id FROM eshop.products p JOIN eshop.product_types pt ON pt.id=p.product_type
        WHERE pt.occasion=occ_id AND (p_after IS NULL OR p.id>p_after)
        ORDER BY p.id LIMIT CASE WHEN p_limit IS NULL THEN NULL ELSE p_limit+1 END) selected;
  IF cardinality(selected_ids)>p_limit THEN
    selected_ids:=selected_ids[1:p_limit];
    next_id:=selected_ids[p_limit];
  END IF;
  -- A page must never silently truncate inventory assignments. The existing
  -- product DTO supports up to 1000 assignments per product.
  IF p_limit IS NOT NULL AND EXISTS(SELECT 1 FROM eshop.product_inventory_contexts
       WHERE product=ANY(selected_ids) GROUP BY product HAVING count(*)>1000) THEN
    RAISE program_limit_exceeded USING MESSAGE='product inventory assignments exceed catalog page contract';
  END IF;

-- Fetch all product types for the given occasion
  SELECT json_agg(
           json_build_object(
             'id', pt.id,
             'type', pt.type,
             'title', pt.title
           )
         )
    INTO product_types
  FROM eshop.product_types pt
  WHERE pt.occasion = occ_id AND (p_limit IS NULL OR pt.id IN (SELECT product_type FROM eshop.products WHERE id=ANY(selected_ids)));

  -- Fetch all products for the given occasion, including form IDs
  SELECT json_agg(
           json_build_object(
             'id', p.id,
            'aggregate_version',coalesce((SELECT version FROM public.client_aggregate_versions WHERE aggregate_type='product' AND scope_type='occasion' AND scope_id=p.occasion AND aggregate_id=p.id::text),0),
             'title', p.title,
             'description', p.description,
             'short_title', p.data->>'short_title',
             'product_type', p.product_type,
             'data', p.data,
             'price', p.price,
             'price_changes', (SELECT COALESCE(json_agg(pc ORDER BY pc.change_time,pc.id),'[]'::json)
               FROM eshop.planned_changes pc WHERE pc.subject_id=p.id AND pc.change_type='products.price' AND NOT pc.applied),
             'visibility_changes', (SELECT COALESCE(json_agg(pc ORDER BY pc.change_time,pc.id),'[]'::json)
               FROM eshop.planned_changes pc WHERE pc.subject_id=p.id AND pc.change_type='products.is_hidden' AND NOT pc.applied),
             'currency_code', p.currency_code,
             'is_hidden', p.is_hidden,
             'is_used_in_blueprint', EXISTS (SELECT 1 FROM eshop.spots s WHERE s.product=p.id AND s.occasion=occ_id),
             'order', p."order",
             'maximum', p.maximum,
             'form_ids', (
               SELECT COALESCE(json_agg(DISTINCT ff.form ORDER BY ff.form), '[]'::json)
               FROM public.form_fields ff JOIN public.forms f ON f.id=ff.form
               WHERE ff.product_type = p.product_type AND f.occasion=occ_id
             ),
             -- These are product-ticket relationship rows, never unique people
             -- or order counts. Preserve historical all-state ordered_count.
             'ordered_count', sales.ordered_count,
             'paid_count', sales.paid_count,
             'sent_count', sales.sent_count,
             'purchased_count', sales.purchased_count
           ) ORDER BY p.id
         )
    INTO products
  FROM eshop.products p
  CROSS JOIN LATERAL (
    SELECT count(*) ordered_count,
      count(*) FILTER(WHERE o.state='paid') paid_count,
      count(*) FILTER(WHERE o.state='sent') sent_count,
      count(*) FILTER(WHERE o.state IN ('paid','sent')) purchased_count
    FROM eshop.order_product_ticket opt LEFT JOIN eshop.orders o ON o.id=opt."order"
    WHERE opt.product=p.id
  ) sales
  WHERE p.id=ANY(selected_ids);

  -- Fetch all inventory pools for the occasion
  SELECT json_agg(ip.*)
  INTO inventory_pools_data
  FROM public.inventory_pools ip
  WHERE ip.occasion = occ_id AND p_limit IS NULL;

  -- Fetch all inventory contexts for the occasion
  SELECT json_agg((CASE WHEN p_limit IS NULL THEN to_jsonb(ic) ELSE jsonb_build_object(
    'id',ic.id,'title',ic.title,'inventory_pool',ic.inventory_pool,'block_date',ic.block_date) END)
    ||jsonb_build_object('pool_title',ip.title,'pool_type',ip.type))
  INTO inventory_contexts_data
  FROM public.inventory_contexts ic
  JOIN public.inventory_pools ip ON ic.inventory_pool = ip.id
  WHERE ip.occasion = occ_id AND (p_limit IS NULL OR ic.id IN (
    SELECT inventory_context FROM eshop.product_inventory_contexts WHERE product=ANY(selected_ids)));

  -- Fetch all links between products and inventory contexts for the occasion
  SELECT json_agg(pic.*)
  INTO product_inventory_contexts_data
  FROM eshop.product_inventory_contexts pic
  JOIN eshop.products p ON pic.product = p.id
  JOIN eshop.product_types pt ON p.product_type = pt.id
  WHERE pt.occasion = occ_id AND p.id=ANY(selected_ids);

  -- Fetch only the id, title, and link for each form associated with the occasion
  SELECT json_agg(
           json_build_object(
             'id', f.id,
             'title', f.title
           )::jsonb || CASE WHEN p_limit IS NULL THEN jsonb_build_object('link',f.link) ELSE '{}'::jsonb END
         )
    INTO forms_data
  FROM public.forms f
  WHERE f.occasion = occ_id AND (p_limit IS NULL OR EXISTS(
    SELECT 1 FROM public.form_fields ff JOIN eshop.products p ON p.product_type=ff.product_type
    WHERE ff.form=f.id AND p.id=ANY(selected_ids)));
  IF p_limit IS NOT NULL AND json_array_length(coalesce(forms_data,'[]'::json))>1000 THEN
    RAISE program_limit_exceeded USING MESSAGE='form references exceed catalog page contract';
  END IF;

  RETURN json_build_object(
    'server_time', clock_timestamp(),
    'nextCursor',next_id,
    'price_waves', CASE WHEN p_limit IS NULL THEN public.get_product_price_waves_internal(occ_id)->'waves' ELSE '[]'::jsonb END,
    'product_types', COALESCE(product_types, '[]'::json),
    'products', COALESCE(products, '[]'::json),
    'inventory_pools', COALESCE(inventory_pools_data, '[]'::json),
    'inventory_contexts', COALESCE(inventory_contexts_data, '[]'::json),
    'product_inventory_contexts', COALESCE(product_inventory_contexts_data, '[]'::json),
    'forms', COALESCE(forms_data, '[]'::json)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_product_catalog_data_internal(bigint,bigint,integer) FROM PUBLIC,anon,authenticated,service_role;

-- Public compatibility entry used by released editor clients. Remove only once
-- supported clients use get_product_catalog exclusively. No second projection.
CREATE OR REPLACE FUNCTION public.get_products_and_types_for_edit(occasion_link text)
RETURNS json LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=public,extensions AS $$
DECLARE oc bigint;
BEGIN
 SELECT id INTO oc FROM public.occasions
 WHERE id=public.resolve_occasion_link_internal(occasion_link)
 AND organization=(SELECT ui.organization FROM public.user_info ui WHERE ui.id=auth.uid());
 IF oc IS NULL THEN RAISE EXCEPTION 'Occasion not found for link: %',occasion_link; END IF;
 IF public.can_read_orders(oc) IS DISTINCT FROM TRUE THEN
  RETURN json_build_object('code',403,'message','User is not authorized to view this.');
 END IF;
 RETURN public.get_product_catalog_data_internal(oc);
END $$;
REVOKE ALL ON FUNCTION public.get_products_and_types_for_edit(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_products_and_types_for_edit(text) TO authenticated;

