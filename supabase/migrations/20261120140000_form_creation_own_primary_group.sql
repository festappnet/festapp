-- Form and product commands use a single locking order and shared plan bindings.

-- SOURCE: blueprint/availability.sql
-- Same counts and context quantities as finalize_ticket_order/apply_allocations.
-- This snapshot never reserves quantity; checkout remains authoritative.
CREATE OR REPLACE FUNCTION public.blueprint_product_availability_internal(p_product bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=public,extensions AS $$
DECLARE p eshop.products; c record; total bigint; occupied bigint; cap bigint; available bigint:=2147483647; capacity bigint:=2147483647;
BEGIN
 SELECT * INTO p FROM eshop.products WHERE id=p_product;
 IF NOT FOUND THEN RETURN jsonb_build_object('capacity',0,'available',0,'reason','PRODUCT_NOT_FOUND'); END IF;
 IF coalesce(p.maximum,0)>0 THEN
  capacity:=p.maximum;
  available:=greatest(0,p.maximum-(SELECT count(*) FROM eshop.order_product_ticket WHERE product=p.id));
 END IF;
 FOR c IN SELECT pic.inventory_context,pic.quantity,ip.sellable_capacity FROM eshop.product_inventory_contexts pic
  JOIN public.inventory_contexts ic ON ic.id=pic.inventory_context JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool WHERE pic.product=p.id LOOP
  SELECT count(*),count(*) FILTER(WHERE order_product_ticket IS NOT NULL OR (secret IS NOT NULL AND secret_expiration_time>statement_timestamp()))
   INTO total,occupied FROM eshop.spots WHERE inventory_context=c.inventory_context;
  cap:=least(total,coalesce(c.sellable_capacity,total));
  capacity:=least(capacity,cap/greatest(c.quantity,1));
  available:=least(available,greatest(0,cap-occupied)/greatest(c.quantity,1));
 END LOOP;
 RETURN jsonb_build_object('capacity',capacity,'available',CASE WHEN p.is_hidden THEN 0 ELSE available END,
  'reason',CASE WHEN p.is_hidden THEN 'PRODUCT_HIDDEN' WHEN available=0 THEN 'PRODUCT_CAPACITY_EXCEEDED' ELSE NULL END);
END $$;
-- Assigning a blueprint to a form offers its bound seats and capacity areas.
-- Form fields configure additional questions/products, not a second seat allowlist.
CREATE OR REPLACE FUNCTION public.blueprint_form_product_bindings_internal(p_form bigint)
RETURNS TABLE(product bigint,has_seats boolean,has_capacity boolean)
LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT offered.product,offered.has_seats,offered.has_capacity
 FROM public.forms f JOIN eshop.blueprints b ON b.id=f.blueprint AND b.occasion=f.occasion
 CROSS JOIN LATERAL (
  SELECT s.product,true AS has_seats,false AS has_capacity
  FROM eshop.blueprint_seat_bindings sb JOIN eshop.spots s ON s.id=sb.spot
  WHERE sb.blueprint=b.id AND s.blueprint=b.id AND s.occasion=f.occasion
  UNION ALL
  SELECT ab.product,false,true FROM eshop.blueprint_area_bindings ab WHERE ab.blueprint=b.id
 ) offered
 JOIN eshop.products p ON p.id=offered.product AND p.occasion=f.occasion
 WHERE f.id=p_form
$$;
CREATE OR REPLACE FUNCTION public.blueprint_form_products_internal(p_form bigint)
RETURNS TABLE(product bigint,has_seats boolean,has_capacity boolean)
LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT bound.product,bool_or(bound.has_seats),bool_or(bound.has_capacity)
 FROM public.blueprint_form_product_bindings_internal(p_form) bound GROUP BY bound.product
$$;
CREATE OR REPLACE FUNCTION public.blueprint_form_product_catalog_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',p.id,'title',p.title,'type_title',pt.title,'price',p.price,
  'currency_code',p.currency_code,'maximum',p.maximum,
  'ordered_count',(SELECT count(*) FROM eshop.order_product_ticket opt WHERE opt.product=p.id),
  'is_dynamically_available',public.is_product_dynamically_available(p.id),
  'isAvailable',(availability.value->>'available')::bigint>0 AND public.is_product_dynamically_available(p.id)
 ) ORDER BY p.id),'[]'::jsonb)
 FROM public.blueprint_form_products_internal(p_form) offered JOIN eshop.products p ON p.id=offered.product
 LEFT JOIN eshop.product_types pt ON pt.id=p.product_type
 CROSS JOIN LATERAL (SELECT public.blueprint_product_availability_internal(p.id) AS value) availability
 WHERE NOT p.is_hidden
$$;
REVOKE ALL ON FUNCTION public.blueprint_form_product_bindings_internal(bigint),public.blueprint_form_products_internal(bigint),public.blueprint_form_product_catalog_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.blueprint_area_availability_internal(p_blueprint bigint,p_form bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('nodeId',b.node_id,'productId',b.product,'inventoryContextId',b.inventory_context)||
  CASE WHEN p_form IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.forms f WHERE f.id=p_form AND f.blueprint=b.blueprint)
  THEN jsonb_build_object('capacity',(public.blueprint_product_availability_internal(b.product)->'capacity'),'available',0,'reason','PRODUCT_NOT_IN_FORM')
  ELSE public.blueprint_product_availability_internal(b.product) END ORDER BY b.node_id),'[]')
 FROM eshop.blueprint_area_bindings b WHERE b.blueprint=p_blueprint
$$;
REVOKE ALL ON FUNCTION public.blueprint_product_availability_internal(bigint),public.blueprint_area_availability_internal(bigint,bigint) FROM PUBLIC,anon,authenticated;

-- SOURCE: eshop_forms/form_creation_domain.sql
-- Shared form construction. Invoker-only, private to explicit checked owners.
CREATE OR REPLACE FUNCTION public.insert_form_for_occasion_internal_v1(p_occasion_id bigint, p_link text, p_title text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    new_form_id BIGINT;
    new_form JSONB;
    new_product_type_id BIGINT;
    seat_blueprint BIGINT;
    now TIMESTAMPTZ := NOW();
    payment_default text;
    initial_data jsonb := '{"is_reminder_enabled": true,"design":{"presale_header":"event_and_date"}}'::jsonb;
BEGIN
    SELECT public.resolve_payment_method_policy_internal(o.organization,o.unit)->>'preferredMethod' INTO payment_default
    FROM public.occasions o JOIN public.organizations org ON org.id=o.organization
    WHERE o.id=p_occasion_id;
    IF payment_default='cash' THEN
      initial_data := initial_data || '{"payments":{"bankEnabled":false,"cashEnabled":true,"providerConnections":{}},"payment_deadline":{"mode":"none"}}'::jsonb;
    ELSIF public.payment_method_is_online_internal(payment_default) THEN
      -- A closed draft can await Connect without inventing a recipient or bank.
      initial_data := initial_data || '{"payments":{"bankEnabled":false}}'::jsonb;
    END IF;
    IF NOT (initial_data ? 'payments') THEN initial_data:=initial_data||jsonb_build_object('payments',jsonb_build_object('bankEnabled',payment_default='bank' AND public.payment_method_policy_enabled_internal((SELECT unit FROM public.occasions WHERE id=p_occasion_id),'bank'))); END IF;
    -- Same scope lock, taken first, as other form/product/plan writers.
    PERFORM public.lock_blueprint_scope_internal(ARRAY[p_occasion_id]);
    PERFORM public.notification_center_initialized_internal((SELECT organization FROM public.occasions WHERE id=p_occasion_id));
    -- Create the new form
    INSERT INTO public.forms(
        title,
        is_open,
        link,
        occasion,
        created_at,
        updated_at,
        deadline_duration_seconds,
        data
    )
    VALUES (
        p_title,
        false,
        NULL,
        p_occasion_id,
        now,
        now,
        NULL, -- New forms inherit the occasion policy; legacy stored durations stay custom.
        initial_data
    )
    RETURNING to_jsonb(public.forms.*) INTO new_form;

    new_form_id := (new_form->>'id')::BIGINT;

    UPDATE public.forms SET link=public.reserve_public_link_internal('form',new_form_id,p_link,true) WHERE id=new_form_id;
    SELECT to_jsonb(f) INTO new_form FROM public.forms f WHERE id=new_form_id;

    -- Create default 'email' and 'ticket' fields
    INSERT INTO public.form_fields(title, type, is_required, form, "order")
    VALUES ('', 'email', true, new_form_id, 0),
           ('', 'ticket', true, new_form_id, 1);

    -- Bind the plan first so the form uses the catalog of its own plan.
    IF EXISTS(SELECT 1 FROM public.occasions WHERE id=p_occasion_id AND
      jsonb_path_exists(features,'$[*] ? (@.code == "blueprint" && @.is_enabled == true)')) THEN
      INSERT INTO public.form_fields(form,type,is_ticket_field,is_required,is_hidden,"order")
      VALUES(new_form_id,'spot',true,true,false,-1);
      PERFORM public.sync_form_blueprint_internal(new_form_id);
      SELECT to_jsonb(f) INTO new_form FROM public.forms f WHERE id=new_form_id;
      seat_blueprint := (new_form->>'blueprint')::bigint;
    END IF;

    IF seat_blueprint IS NOT NULL THEN
      -- Rank groups by visible assignments on the bound plan. Each seat or
      -- capacity binding counts once; group ID is the stable tie breaker.
      SELECT p.product_type INTO new_product_type_id
      FROM public.blueprint_form_product_bindings_internal(new_form_id) bound
      JOIN eshop.products p ON p.id=bound.product AND NOT p.is_hidden
      JOIN eshop.product_types pt ON pt.id=p.product_type AND pt.type='spot' AND pt.occasion=p_occasion_id
      GROUP BY p.product_type ORDER BY count(*) DESC, p.product_type LIMIT 1;
    END IF;

    IF new_product_type_id IS NULL THEN
      -- Otherwise (no plan, or a plan without bound admission products) every new
      -- form owns a fresh primary group and starter variant.
      -- Never bind another form's group: it would share live stock and orders.
      INSERT INTO eshop.product_types(title, type, occasion)
      VALUES ('Spot', 'spot', p_occasion_id)
      RETURNING id INTO new_product_type_id;

      INSERT INTO eshop.products(title, price, product_type, occasion, currency_code, "order")
      VALUES ('Variant 1', 100, new_product_type_id, p_occasion_id, 'CZK', 0);
    END IF;

    -- Create the 'product_type' form field linked to 'spot'
    INSERT INTO public.form_fields(title, type, is_required, form, "order", product_type, is_ticket_field)
    VALUES ('Spot', 'product_type', false, new_form_id, 2, new_product_type_id, true);

    PERFORM public.assert_form_primary_products_internal(new_form_id);

    -- Return the raw data of the newly created form
    PERFORM public.notification_center_form_created_internal(new_form_id);
    RETURN new_form;
END;
$function$;
REVOKE ALL ON FUNCTION public.insert_form_for_occasion_internal_v1(bigint,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.insert_form_for_occasion_internal_v1(bigint,text,text) TO postgres;

-- Only the explicit occasion-create owner calls this initial-form boundary.
-- Manager-only creation uses its own domain right, not a fabricated editor role.
CREATE OR REPLACE FUNCTION public.create_initial_occasion_form_internal_v1(p_occasion_id bigint,p_link text,p_title text)
RETURNS jsonb LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE v_unit bigint;
BEGIN
  PERFORM public.lock_blueprint_scope_internal(ARRAY[p_occasion_id]);
  SELECT unit INTO v_unit FROM public.occasions WHERE id=p_occasion_id FOR UPDATE;
  IF NOT FOUND OR auth.uid() IS NULL OR NOT public.can_create_occasion(v_unit)
    OR EXISTS(SELECT 1 FROM public.forms WHERE occasion=p_occasion_id) THEN
    RAISE insufficient_privilege USING MESSAGE='initial occasion form creation unavailable';
  END IF;
  PERFORM public.check_occasion_writable(p_occasion_id);
  RETURN public.insert_form_for_occasion_internal_v1(p_occasion_id,p_link,p_title);
END $$;
REVOKE ALL ON FUNCTION public.create_initial_occasion_form_internal_v1(bigint,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_initial_occasion_form_internal_v1(bigint,text,text) TO postgres;

-- SOURCE: eshop_forms/create_form_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.create_form_client_sync_v1(
  p_occasion_link text,p_link text,p_title text,p_command_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE v_actor uuid:=auth.uid(); v_occasion bigint; v_unit bigint;
  v_begin jsonb; v_hash text; v_form jsonb;
BEGIN
  SELECT o.id,o.unit INTO v_occasion,v_unit FROM public.occasions o
    WHERE o.id=public.resolve_occasion_link_internal(p_occasion_link);
  IF v_actor IS NULL OR v_occasion IS NULL
    OR length(p_link)>80 OR length(COALESCE(p_title,''))>500
    OR NOT public.can_author_forms(v_occasion) THEN
    RAISE insufficient_privilege USING MESSAGE='occasion editor required'; END IF;
  PERFORM public.lock_blueprint_scope_internal(ARRAY[v_occasion]);
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion',v_occasion,'link',p_link,'title',p_title)::text,'UTF8'),
    'sha256'),'hex');
  v_begin:=public.begin_client_mutation_v1(p_command_id,
    'inventory.form.create',v_occasion,v_actor,v_hash);
  IF v_begin->>'disposition'='replay' THEN RETURN v_begin->'response'; END IF;
  v_form:=public.create_form_internal_v1(v_occasion,p_link,p_title);
  RETURN public.complete_private_inventory_mutation_v1(p_command_id,v_occasion,
    'inventory.form.create',jsonb_build_array(jsonb_build_object(
      'entityType','form','entityId',v_form->>'id','operation','insert',
      'safeLabel',left(p_title,240),'changedFields',jsonb_build_array(
        'configuration','fields','products'))),'{}'::uuid[],
    jsonb_build_object('form',v_form,'authoring',public.get_form_authoring_snapshot_internal((v_form->>'id')::bigint)));
END; $$;
REVOKE ALL ON FUNCTION public.create_form_client_sync_v1(text,text,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.create_form_client_sync_v1(text,text,text,uuid) TO authenticated;

-- SOURCE: eshop/delete_product_client_sync_v1.sql
CREATE OR REPLACE FUNCTION public.delete_product_domain_command_internal_v1(p_product_id bigint,p_command_id uuid,p_expected_version bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE actor uuid:=auth.uid(); oc bigint; title text; begin_result jsonb; hash text; version bigint; used bigint; original_key uuid;
BEGIN
 SELECT occasion INTO oc FROM public.client_mutation_receipts WHERE command_id=p_command_id AND actor_id=actor AND command_name='inventory.product.delete';
 IF NOT FOUND THEN SELECT t.occasion INTO oc FROM eshop.products t WHERE id=p_product_id; END IF;
 IF actor IS NULL OR oc IS NULL OR public.can_write_orders(oc) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='product editor required'; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[oc]);
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
