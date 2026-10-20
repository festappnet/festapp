-- Blueprint assignment offers its bound places without duplicate form product fields.
BEGIN;

-- Source: database/functions/blueprint/availability.sql
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
CREATE OR REPLACE FUNCTION public.blueprint_form_products_internal(p_form bigint)
RETURNS TABLE(product bigint,has_seats boolean,has_capacity boolean)
LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT offered.product,bool_or(offered.has_seats),bool_or(offered.has_capacity)
 FROM public.forms f JOIN eshop.blueprints b ON b.id=f.blueprint AND b.occasion=f.occasion
 CROSS JOIN LATERAL (
  SELECT s.product,true AS has_seats,false AS has_capacity
  FROM eshop.blueprint_seat_bindings sb JOIN eshop.spots s ON s.id=sb.spot
  WHERE sb.blueprint=b.id AND s.blueprint=b.id AND s.occasion=f.occasion
  UNION ALL
  SELECT ab.product,false,true FROM eshop.blueprint_area_bindings ab WHERE ab.blueprint=b.id
 ) offered
 JOIN eshop.products p ON p.id=offered.product AND p.occasion=f.occasion
 WHERE f.id=p_form GROUP BY offered.product
$$;
CREATE OR REPLACE FUNCTION public.blueprint_form_product_catalog_internal(p_form bigint)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',p.id,'title',p.title,'price',p.price,
  'currency_code',p.currency_code,'maximum',p.maximum,
  'ordered_count',(SELECT count(*) FROM eshop.order_product_ticket opt WHERE opt.product=p.id),
  'is_dynamically_available',public.is_product_dynamically_available(p.id),
  'isAvailable',(availability.value->>'available')::bigint>0 AND public.is_product_dynamically_available(p.id)
 ) ORDER BY p.id),'[]'::jsonb)
 FROM public.blueprint_form_products_internal(p_form) offered JOIN eshop.products p ON p.id=offered.product
 CROSS JOIN LATERAL (SELECT public.blueprint_product_availability_internal(p.id) AS value) availability
 WHERE NOT p.is_hidden
$$;
REVOKE ALL ON FUNCTION public.blueprint_form_products_internal(bigint),public.blueprint_form_product_catalog_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.blueprint_area_availability_internal(p_blueprint bigint,p_form bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(jsonb_build_object('nodeId',b.node_id,'productId',b.product,'inventoryContextId',b.inventory_context)||
  CASE WHEN p_form IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.forms f WHERE f.id=p_form AND f.blueprint=b.blueprint)
  THEN jsonb_build_object('capacity',(public.blueprint_product_availability_internal(b.product)->'capacity'),'available',0,'reason','PRODUCT_NOT_IN_FORM')
  ELSE public.blueprint_product_availability_internal(b.product) END ORDER BY b.node_id),'[]')
 FROM eshop.blueprint_area_bindings b WHERE b.blueprint=p_blueprint
$$;
REVOKE ALL ON FUNCTION public.blueprint_product_availability_internal(bigint),public.blueprint_area_availability_internal(bigint,bigint) FROM PUBLIC,anon,authenticated;

-- Source: database/functions/eshop/get_blueprint.sql
CREATE OR REPLACE FUNCTION get_blueprint(
    my_secret UUID,
    form_key UUID,
    blueprint_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    blueprintData JSONB;
    spotsData JSONB;
    productsData JSONB;
    valid_spots JSONB;
BEGIN
    -- Validate the form and blueprint association
    IF NOT EXISTS (
        SELECT 1
        FROM public.forms f
        WHERE f.key = form_key
          AND (NOT public.is_demo_occasion(f.occasion) OR public.can_read_demo_occasion(f.occasion))
          AND (f.is_open = true OR public.get_is_editor_order_view_on_occasion(f.occasion))
          AND EXISTS (
              SELECT 1
              FROM eshop.blueprints b
              WHERE b.id = blueprint_id
                AND f.blueprint = blueprint_id
          )
    ) THEN
        RETURN jsonb_build_object(
            'code', 400,
            'message', 'Invalid form key or blueprint association.'
        );
    END IF;

    IF EXISTS(SELECT 1 FROM eshop.blueprints WHERE id=blueprint_id AND layout IS NULL) THEN
      RETURN jsonb_build_object('code',409,'reason','BLUEPRINT_LAYOUT_MIGRATION_REQUIRED');
    END IF;

    -- Fetch blueprint details
    SELECT jsonb_build_object(
        'id', b.id,
        'occasion', b.occasion,
        'created_at', b.created_at,
        'data', b.data,
        'title', b.title,
        'layout', public.blueprint_public_document_internal(b.layout), 'layout_revision', b.layout_revision,
        'layoutResources', public.blueprint_layout_resources_internal(public.blueprint_public_document_internal(b.layout),b.occasion)
    )
    INTO blueprintData
    FROM eshop.blueprints b
    WHERE b.id = blueprint_id;

    -- Every runtime spot belongs to a canonical node binding.
    SELECT coalesce(jsonb_agg(spot),'[]'::jsonb) INTO valid_spots
      FROM eshop.blueprint_seat_bindings WHERE blueprint=blueprint_id;

    -- Fetch enriched spots data
    SELECT jsonb_agg(jsonb_build_object(
        'id', s.id,
        'title', s.title,
        'product', s.product,
        'state', CASE
            WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
            WHEN s.secret IS NOT NULL AND s.secret_expiration_time > now() THEN
                CASE
                    WHEN s.secret = my_secret THEN 'selected_by_me'
                    ELSE 'selected'
                END
            ELSE 'available'
        END
    ))
    INTO spotsData
    FROM eshop.spots s
    WHERE s.id = ANY(SELECT jsonb_array_elements_text(valid_spots)::BIGINT)
      AND s.occasion = (
        SELECT occasion FROM public.forms WHERE key = form_key
      );

    -- The associated blueprint is the seat/area offer authority. Product and
    -- inventory availability remain shared with reservation and checkout.
    productsData:=public.blueprint_form_product_catalog_internal(
      (SELECT id FROM public.forms WHERE key=form_key));

    -- Add spots data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{spots}',
        COALESCE(spotsData, '[]'::jsonb)
    );

    -- Add products data to the blueprint object
    blueprintData = jsonb_set(
        blueprintData,
        '{products}',
        COALESCE(productsData, '[]'::jsonb)
    );

    blueprintData:=blueprintData||public.blueprint_public_binding_projection_internal(blueprint_id,my_secret);

    blueprintData:=blueprintData||jsonb_build_object('areaAvailability',public.blueprint_area_availability_internal(blueprint_id,(SELECT id FROM public.forms WHERE key=form_key)));

    -- Return combined data
    RETURN jsonb_build_object(
        'code', 200,
        'data', blueprintData
    );
END;
$$;

-- Source: database/functions/eshop/select_spot.sql
-- One admission preflight for the complete atomic unit. These are the same
-- bound blueprint offer, maximum counts and physical/context quantities as checkout.
CREATE OR REPLACE FUNCTION public.blueprint_hold_admission_internal(p_form bigint,p_spots bigint[],p_secret uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE item record; counts jsonb; requested bigint; occupied bigint; physical bigint; cap bigint;
BEGIN
 -- Serialize all products and required inventory contexts in canonical ID order.
 PERFORM 1 FROM eshop.products WHERE id IN (SELECT product FROM eshop.spots WHERE id=ANY(p_spots)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_pools WHERE id IN (SELECT ic.inventory_pool FROM public.inventory_contexts ic
  JOIN eshop.product_inventory_contexts pic ON pic.inventory_context=ic.id JOIN eshop.spots s ON s.product=pic.product WHERE s.id=ANY(p_spots)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_contexts WHERE id IN (SELECT pic.inventory_context FROM eshop.product_inventory_contexts pic
  JOIN eshop.spots s ON s.product=pic.product WHERE s.id=ANY(p_spots)) ORDER BY id FOR UPDATE;
 FOR item IN SELECT p.*,count(*) AS requested FROM eshop.spots s JOIN eshop.products p ON p.id=s.product
  WHERE s.id=ANY(p_spots) AND NOT coalesce(s.secret=p_secret AND s.secret_expiration_time>statement_timestamp(),false)
  GROUP BY p.id ORDER BY p.id LOOP
  IF item.is_hidden THEN RETURN jsonb_build_object('code',409,'reason','PRODUCT_HIDDEN'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.blueprint_form_products_internal(p_form) offered WHERE offered.product=item.id AND offered.has_seats) THEN
   RETURN jsonb_build_object('code',409,'reason','PRODUCT_NOT_IN_FORM'); END IF;
  IF coalesce(item.maximum,0)>0 THEN
   SELECT count(*) INTO occupied FROM eshop.order_product_ticket WHERE product=item.id;
   SELECT occupied+count(*) INTO occupied FROM eshop.spots WHERE product=item.id AND order_product_ticket IS NULL
    AND secret IS NOT NULL AND secret_expiration_time>statement_timestamp();
   IF occupied+item.requested>item.maximum THEN RETURN jsonb_build_object('code',409,'reason','PRODUCT_CAPACITY_EXCEEDED'); END IF;
  END IF;
  counts:=public.blueprint_product_availability_internal(item.id);
  IF (counts->>'available')::bigint<item.requested THEN RETURN jsonb_build_object('code',409,'reason',coalesce(counts->>'reason','PRODUCT_CAPACITY_EXCEEDED')); END IF;
 END LOOP;
 -- Two differently priced products can consume the same context. Sum their
 -- quantities before holding either member, rather than checking them alone.
 FOR item IN SELECT pic.inventory_context,ip.sellable_capacity,sum(pic.quantity)::bigint AS requested
  FROM eshop.spots s JOIN eshop.product_inventory_contexts pic ON pic.product=s.product
  JOIN public.inventory_contexts ic ON ic.id=pic.inventory_context JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool
  WHERE s.id=ANY(p_spots) AND NOT coalesce(s.secret=p_secret AND s.secret_expiration_time>statement_timestamp(),false)
  GROUP BY pic.inventory_context,ip.sellable_capacity ORDER BY pic.inventory_context LOOP
  SELECT count(*),count(*) FILTER(WHERE order_product_ticket IS NOT NULL OR
   (secret IS NOT NULL AND secret_expiration_time>statement_timestamp())) INTO physical,occupied
   FROM eshop.spots WHERE inventory_context=item.inventory_context;
  -- Addressed seats usually have no inventory_context. Their existing spot
  -- holds nevertheless promise all PIC quantities at checkout. Count that
  -- same hold record, subtracting any physical occupancy already counted.
  SELECT occupied+coalesce(sum(greatest(pic.quantity-CASE
    WHEN held.inventory_context=item.inventory_context THEN 1 ELSE 0 END,0)),0)
   INTO occupied FROM eshop.spots held JOIN eshop.product_inventory_contexts pic ON pic.product=held.product
   WHERE pic.inventory_context=item.inventory_context AND held.blueprint IS NOT NULL
    AND held.order_product_ticket IS NULL AND held.secret IS NOT NULL
    AND held.secret_expiration_time>statement_timestamp();
  cap:=least(physical,coalesce(item.sellable_capacity,physical));
  IF occupied+item.requested>cap THEN RETURN jsonb_build_object('code',409,'reason','PRODUCT_CAPACITY_EXCEEDED'); END IF;
 END LOOP;
 RETURN jsonb_build_object('code',200);
END $$;
REVOKE ALL ON FUNCTION public.blueprint_hold_admission_internal(bigint,bigint[],uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.select_spot_single_internal_v1(form_key uuid,secret_id uuid,spot_id bigint,selecting boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE bp bigint; occ bigint; org bigint; un bigint; s eshop.spots; policy jsonb; scopes jsonb; costs jsonb; r jsonb; held bigint; duration_seconds integer; form_data jsonb; form_open boolean; fid bigint;
BEGIN
 IF secret_id IS NULL OR selecting IS NULL THEN RETURN jsonb_build_object('code',400,'message','Invalid reservation'); END IF;
 SELECT f.blueprint,f.occasion,o.organization,o.unit,f.id,f.is_open INTO bp,occ,org,un,fid,form_open FROM public.forms f
 JOIN public.occasions o ON o.id=f.occasion WHERE f.key=form_key;
 IF bp IS NULL THEN RETURN jsonb_build_object('code',404,'message','Form blueprint not found'); END IF;
 PERFORM public.check_occasion_writable(occ);
 -- A buyer's active inventory is serialized before the individual spot lock.
 PERFORM pg_advisory_xact_lock(hashtextextended('hold:'||secret_id::text,0));
 SELECT * INTO s FROM eshop.spots WHERE id=spot_id AND blueprint=bp FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('code',404,'message','Spot not found'); END IF;
 IF s.order_product_ticket IS NOT NULL THEN RETURN jsonb_build_object('code',409,'message','Spot is already ordered'); END IF;
 IF s.secret_expiration_time<=statement_timestamp() THEN
  UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL WHERE id=spot_id;
  s.secret:=NULL; s.secret_expiration_time:=NULL;
 END IF;
 IF s.secret IS NOT NULL AND s.secret IS DISTINCT FROM secret_id THEN
  RETURN jsonb_build_object('code',403,'message','Spot is held by another buyer'); END IF;
 IF NOT selecting THEN
  UPDATE eshop.spots SET secret=NULL,secret_expiration_time=NULL,updated_at=now() WHERE id=spot_id;
  RETURN jsonb_build_object('code',200,'message','Spot deselected');
 END IF;
 -- A retry cannot move the original expiration, including after another tab reload.
 IF s.secret=secret_id THEN RETURN jsonb_build_object('code',200,'message','Spot selected','expiresAt',s.secret_expiration_time); END IF;
 r:=public.blueprint_hold_admission_internal(fid,ARRAY[s.id],secret_id);
 IF (r->>'code')::integer<>200 THEN RETURN r; END IF;
 IF selecting AND public.get_is_editor_order_on_occasion(occ) IS NOT TRUE THEN
  form_data:=public.get_effective_form_data(fid);
  IF form_open IS NOT TRUE OR
   (coalesce(form_data#>>'{schedule,start_time}',form_data->>'start_time'))::timestamptz>statement_timestamp() OR
   (coalesce(form_data#>>'{schedule,end_time}',form_data->>'end_time'))::timestamptz<statement_timestamp() THEN
   RETURN jsonb_build_object('code',403,'message','Form is not open'); END IF;
 END IF;
 policy:=public.abuse_effective_rules_v1('spot.hold',un,org);
 scopes:=jsonb_build_object('recipient',secret_id,'unit',un,'organization',org);
 FOR r IN SELECT value FROM jsonb_array_elements(policy->'rules') ORDER BY value->>'rule_key' LOOP
  PERFORM pg_advisory_xact_lock(hashtextextended('abuse:'||(r->>'rule_key')||':'||(scopes->>(r->>'scope_kind')),0));
 END LOOP;
 SELECT count(*) INTO held FROM eshop.spots WHERE secret=secret_id AND secret_expiration_time>statement_timestamp() AND order_product_ticket IS NULL;
 costs:=jsonb_build_object('hold.active.buyer',held+1);
 PERFORM public.abuse_charge_v1(policy,scopes,costs);
 SELECT (x->>'base_limit')::integer INTO duration_seconds FROM jsonb_array_elements(public.abuse_effective_rules_v1('hold.duration',un,org)->'rules') x;
 IF duration_seconds IS NULL THEN RAISE configuration_limit_exceeded USING MESSAGE='abuse_policy_missing'; END IF;
 UPDATE eshop.spots SET secret=secret_id,secret_expiration_time=statement_timestamp()+make_interval(secs=>duration_seconds),updated_at=now() WHERE id=spot_id RETURNING * INTO s;
 RETURN jsonb_build_object('code',200,'message','Spot selected','expiresAt',s.secret_expiration_time);
END $$;
REVOKE ALL ON FUNCTION public.select_spot_single_internal_v1(uuid,uuid,bigint,boolean) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.select_spot(form_key uuid,secret_id uuid,spot_id bigint,selecting boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ids bigint[]; member_id bigint; r jsonb; occ bigint; bp bigint; fid bigint;
BEGIN
 SELECT occasion,blueprint,id INTO occ,bp,fid FROM public.forms WHERE key=form_key;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 PERFORM pg_advisory_xact_lock(hashtextextended('hold:'||secret_id::text,0));
 ids:=public.blueprint_selection_unit_spots_internal(spot_id);
 PERFORM 1 FROM eshop.spots WHERE id=ANY(ids) ORDER BY id FOR UPDATE;
 BEGIN
  IF selecting AND EXISTS(SELECT 1 FROM eshop.spots s LEFT JOIN eshop.blueprint_seat_bindings b ON b.spot=s.id
   WHERE s.id=ANY(ids) AND (b.blocked OR s.product IS NULL)
    AND NOT coalesce(s.secret=secret_id AND s.secret_expiration_time>statement_timestamp(),false)) THEN
   RAISE check_violation USING MESSAGE='BLUEPRINT_SEAT_UNAVAILABLE'; END IF;
  IF selecting THEN
   r:=public.blueprint_hold_admission_internal(fid,ids,secret_id);
   IF (r->>'code')::integer<>200 THEN RETURN r; END IF;
  END IF;
  FOREACH member_id IN ARRAY ids LOOP
   r:=public.select_spot_single_internal_v1(form_key,secret_id,member_id,selecting);
   IF coalesce((r->>'code')::integer,500)<>200 THEN RAISE check_violation USING MESSAGE='BLUEPRINT_HOLD_REJECTED'; END IF;
  END LOOP;
 EXCEPTION WHEN check_violation THEN
  RETURN coalesce(r,jsonb_build_object('code',409,'reason',SQLERRM,'message',SQLERRM));
 END;
 RETURN r||jsonb_build_object('spotIds',to_jsonb(ids));
END $$;
REVOKE ALL ON FUNCTION public.select_spot(uuid,uuid,bigint,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.select_spot(uuid,uuid,bigint,boolean) TO anon,authenticated;

-- Source: database/functions/eshop/finalize_ticket_order.sql
CREATE OR REPLACE FUNCTION public.finalize_ticket_order_internal_v1(p_target_order bigint,input_data JSONB,p_offer boolean DEFAULT false)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions
AS $$
DECLARE
    result JSONB;
    order_id BIGINT;
    assigned_order_symbol TEXT;
    assigned_order_sequence BIGINT;
    allocation_attempt INTEGER;
    ticket_data JSONB;
    spot_data RECORD;
    spot_id BIGINT;
    spot_product RECORD;
    now TIMESTAMPTZ := NOW();
    calculated_price NUMERIC(10,2) := 0;
    spot_secret UUID;
    product_id BIGINT;
    ordered_count BIGINT;
    used_spots JSONB := '[]'::JSONB;
    occasion_id BIGINT;
    organization_id BIGINT;
    unit_id BIGINT;
    occasion_title TEXT;
    occasion_features JSONB;
    account_number TEXT;
    account_number_human_readable TEXT;
    creditor_name TEXT;
    generated_creditor_reference TEXT;
    ticket_details JSONB := '[]'::JSONB;
    product_data RECORD;
    ticket_id BIGINT;
    order_product_ticket_id BIGINT;
    v_ticket_symbol TEXT;
    ticket_products JSONB := '[]'::JSONB;
    payment_info_id BIGINT;
    generated_variable_symbol BIGINT;
    bank_account_id BIGINT;
    form_key UUID;
    deadline TIMESTAMPTZ;
    form_deadline_duration BIGINT;
    form_data JSONB;
    currency_code TEXT;
    first_currency_code TEXT := NULL;
    field_item JSONB;
    products_array BIGINT[] := '{}';
    form_id BIGINT;
    field_type TEXT;
    key_val RECORD;
    order_data JSONB;
    order_note TEXT;
    ticket_note TEXT;
    reply_to TEXT;
    is_open_val BOOLEAN;
    is_editor BOOLEAN;
    v_product_deposit NUMERIC;
    v_total_deposit NUMERIC := 0;
BEGIN
    PERFORM public.lock_blueprint_scope_internal(ARRAY[(SELECT occasion FROM public.forms WHERE key=(input_data->>'form')::uuid)]);
    PERFORM public.check_occasion_writable((SELECT occasion FROM public.forms WHERE key=(input_data->>'form')::uuid));
    -- Wrap the entirelogic in a subtransaction block
    BEGIN
        PERFORM public.check_blueprint_selection_units_internal(ARRAY(SELECT (t->>'spot')::bigint FROM jsonb_array_elements(coalesce(input_data->'ticket','[]')) t WHERE t->>'spot' IS NOT NULL));
        -- Validate input_data and extract form key and email
        IF input_data IS NULL OR input_data->'form' IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1001, 'message', 'Missing form key in input data')::TEXT;
        END IF;

        IF input_data ?| ARRAY['order_symbol','orderSymbol','order_sequence','orderSequence']
            OR COALESCE(input_data->'data', '{}'::jsonb) ?| ARRAY['order_symbol','orderSymbol','order_sequence','orderSequence'] THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1001, 'message', 'Order symbol is server assigned')::TEXT;
        END IF;

        IF jsonb_typeof(input_data->'ticket') = 'array' AND
            jsonb_array_length(input_data->'ticket') > public.ticket_order_limit() THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1023,
                'message', 'Maximum number of tickets per order exceeded',
                'limit', public.ticket_order_limit())::TEXT;
        END IF;

        form_key := (input_data->>'form')::UUID;
        SELECT id, occasion, bank_account, deadline_duration_seconds, data, is_open
        INTO form_id, occasion_id, bank_account_id, form_deadline_duration, form_data, is_open_val
        FROM public.forms
        WHERE key = form_key FOR UPDATE;

        now:=clock_timestamp();
        IF occasion_id IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1003, 'message', 'Form is not linked to any occasion')::TEXT;
        END IF;


        -- The order payload captures the effective tone for its confirmation email.
        form_data := public.get_effective_form_data(form_id);

        is_editor := public.get_is_editor_order_on_occasion(occasion_id);

        IF NOT is_editor AND NOT p_offer THEN
            IF is_open_val IS FALSE THEN
                 RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1021, 'message', 'Form is closed')::TEXT;
            END IF;

            -- Check for start_time and end_time constraints only if not editor
            IF COALESCE(form_data->'schedule'->>'start_time', form_data->>'start_time') IS NOT NULL THEN
                IF now < (COALESCE(form_data->'schedule'->>'start_time', form_data->>'start_time'))::TIMESTAMPTZ THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1019, 'message', 'Form is not yet open')::TEXT;
                END IF;
            END IF;

            IF COALESCE(form_data->'schedule'->>'end_time', form_data->>'end_time') IS NOT NULL THEN
                IF now > (COALESCE(form_data->'schedule'->>'end_time', form_data->>'end_time'))::TIMESTAMPTZ THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1020, 'message', 'Form is closed')::TEXT;
                END IF;
            END IF;
        END IF;

        -- Fetch organization, unit, and occasion title from the occasion
        SELECT organization, unit, title, features
        INTO organization_id, unit_id, occasion_title, occasion_features
        FROM public.occasions
        WHERE id = occasion_id;

        IF organization_id IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1005, 'message', 'No organization found for the occasion')::TEXT;
        END IF;

        IF input_data ? 'fields' THEN
            DECLARE
                valid_fields JSONB := '[]'::JSONB;
                elem JSONB;
                field_key TEXT;
            BEGIN
                FOR elem IN SELECT * FROM jsonb_array_elements(input_data->'fields')
                LOOP
                    field_key := (SELECT key FROM jsonb_object_keys(elem) AS key);

                    IF field_key IS NULL THEN
                        CONTINUE;
                    END IF;

                    -- Validate the field against the form_fields table
                    SELECT ff.type INTO field_type
                    FROM public.form_fields ff
                    WHERE ff.id = field_key::BIGINT AND ff.form = form_id AND ff.is_hidden = false;

                    IF FOUND THEN
                        valid_fields := valid_fields || elem;

                        IF field_type IN ('email', 'name', 'surname', 'phone', 'note') THEN
                            input_data := jsonb_set(input_data, ARRAY[field_type], elem->field_key, true);
                        END IF;
                    END IF;
                END LOOP;

                input_data := jsonb_set(input_data, '{fields}', valid_fields);
            END;
        END IF;

        IF input_data->>'email' IS NULL THEN
            RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1002, 'message', 'Missing email in input data')::TEXT;
        END IF;

        input_data:=jsonb_set(input_data,'{ticket}',public.normalize_form_ticket_answers_internal(form_id,input_data->'ticket'));

        SELECT id,order_symbol,order_sequence INTO order_id,assigned_order_symbol,assigned_order_sequence
        FROM eshop.orders WHERE id=p_target_order AND form=form_id FOR UPDATE;
        IF order_id IS NULL OR EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE "order"=order_id AND (NOT p_offer OR product IS NOT NULL)) THEN
          RAISE EXCEPTION 'Invalid finalization target'; END IF;
        IF NOT p_offer AND (SELECT participant_capacity IS NOT NULL FROM public.forms WHERE id=form_id)
           AND jsonb_array_length(input_data->'ticket') >
           (public.get_form_capacity_snapshot_internal(form_id)->>'remainingPublic')::bigint THEN
          RAISE EXCEPTION '%',jsonb_build_object('code',409,'errorCode','FORM_CAPACITY_EXCEEDED',
            'capacity',public.get_form_capacity_snapshot_internal(form_id))::text; END IF;
        PERFORM public.lock_ticket_order_products_internal(order_id,input_data);
        UPDATE eshop.orders SET state='ordered' WHERE id=order_id;

        PERFORM public.validate_waitlist_answers_internal(form_id,input_data,input_data->'ticket',false);
        -- Process each ticket
        FOR ticket_data IN SELECT * FROM JSONB_ARRAY_ELEMENTS(input_data->'ticket') LOOP

            spot_data := NULL;
            spot_product := NULL;
            spot_id := NULL;
            ticket_note := NULL;

            IF ticket_data->>'spot' IS NOT NULL THEN
                SELECT s.* INTO spot_data
                FROM eshop.spots s
                JOIN public.forms f ON f.id=form_id AND f.blueprint=s.blueprint AND f.occasion=s.occasion
                JOIN eshop.blueprint_seat_bindings sb ON sb.spot=s.id AND sb.blueprint=f.blueprint
                WHERE s.id = (ticket_data->>'spot')::BIGINT
                  AND s.occasion = occasion_id;

                IF spot_data IS NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1007, 'message', 'Invalid or unrelated spot')::TEXT;
                END IF;

                IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings b WHERE b.spot=spot_data.id AND b.blocked) OR spot_data.product IS NULL THEN
                    RAISE EXCEPTION 'BLUEPRINT_SEAT_UNAVAILABLE'; END IF;
                IF spot_data.order_product_ticket IS NOT NULL THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1008, 'message', 'Spot is already reserved or in use')::TEXT;
                END IF;

                spot_secret := (input_data->>'secret')::UUID;
                IF spot_data.secret IS DISTINCT FROM spot_secret THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1009, 'message', 'Invalid secret for spot')::TEXT;
                END IF;

                spot_id := spot_data.id;
                used_spots := used_spots || JSONB_BUILD_ARRAY(spot_id);

                SELECT i.*, it.type, it.title as type_title, spot_data.title as spot_title
                INTO spot_product
                FROM eshop.products i
                LEFT JOIN eshop.product_types it ON i.product_type = it.id
                WHERE i.id = spot_data.product;
            END IF;

            products_array := '{}';
            IF ticket_data ? 'fields' THEN
                FOR field_item IN SELECT * FROM JSONB_ARRAY_ELEMENTS(ticket_data->'fields')
                LOOP
                    IF field_item ? 'note' THEN
                        ticket_note := field_item->>'note';
                    END IF;
                    IF field_item ? 'product_type' THEN
                        products_array := products_array || ((field_item->>'product_type')::BIGINT);
                    END IF;
                END LOOP;
            END IF;

            v_ticket_symbol := generate_ticket_symbol(organization_id, occasion_id);
            IF p_offer THEN
              ticket_id:=(ticket_data->>'ticketId')::bigint;
              UPDATE eshop.tickets t SET state='ordered',ticket_symbol=v_ticket_symbol,
                note=ticket_note,data=public.extract_ticket_answers_internal(form_id,ticket_data),updated_at=now
              WHERE t.id=ticket_id AND t.state='waitlisted' AND t.ticket_symbol IS NULL
                AND EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=t.id AND x."order"=order_id AND x.product IS NULL)
                AND EXISTS(SELECT 1 FROM eshop.waitlist_offer_slots x WHERE x.ticket_id=t.id AND x.outcome='accepted');
              IF NOT FOUND THEN RAISE EXCEPTION 'Invalid waiting ticket finalization'; END IF;
              DELETE FROM eshop.order_product_ticket WHERE "order"=order_id AND ticket=ticket_id AND product IS NULL;
            ELSE
              IF ticket_data ? 'ticketId' THEN RAISE EXCEPTION 'Ticket identity is server assigned'; END IF;
              INSERT INTO eshop.tickets (state,occasion,ticket_symbol,note,data,created_at,updated_at)
              VALUES('ordered',occasion_id,v_ticket_symbol,ticket_note,public.extract_ticket_answers_internal(form_id,ticket_data),now,now) RETURNING id INTO ticket_id;
            END IF;
            ticket_products := '[]'::JSONB;

            IF spot_id IS NOT NULL THEN
                products_array := products_array || spot_product.id;
            END IF;

            FOREACH product_id IN ARRAY products_array LOOP

                IF product_id IS NULL THEN
                    CONTINUE;
                END IF;

                SELECT i.*, it.type, it.title AS type_title, '' AS spot_title
                INTO product_data
                FROM eshop.products i
                LEFT JOIN eshop.product_types it ON i.product_type = it.id
                WHERE i.id = product_id
                  AND it.occasion = occasion_id;

                IF product_data.id IS NOT NULL AND spot_id IS NULL AND NOT EXISTS(SELECT 1 FROM public.form_fields ff
                  WHERE ff.form=form_id AND ff.product_type=product_data.product_type AND NOT ff.is_hidden)
                  AND NOT EXISTS(SELECT 1 FROM public.blueprint_form_products_internal(form_id) offered
                    WHERE offered.product=product_data.id AND offered.has_capacity) THEN
                  RAISE EXCEPTION '%',jsonb_build_object('code',400,'errorCode','PRODUCT_SCOPE_MISMATCH','productId',product_id)::text;
                END IF;
                IF product_data IS NULL THEN
                    RAISE EXCEPTION '%',
                        jsonb_build_object(
                            'code', 1011,
                            'message', 'Product not found or not part of occasion',
                            'details', product_id
                        )::text;
                END IF;

                IF COALESCE(product_data.maximum, 0) > 0 THEN
                    SELECT COUNT(*) INTO ordered_count
                    FROM eshop.order_product_ticket
                    WHERE product = product_id;
                    IF ordered_count + 1 > product_data.maximum THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                            'code', 1017,
                            'errorCode','PRODUCT_CAPACITY_EXCEEDED',
                            'message', 'Product is overbooked',
                            'product', jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                                'id', product_data.id,
                                'title', product_data.title,
                                'price', product_data.price,
                                'type', product_data.type,
                                'currency_code', product_data.currency_code
                            ))
                        )::TEXT;
                    END IF;
                END IF;

                IF product_data.type = 'spot' AND spot_product IS NULL THEN
                    spot_product := product_data;
                END IF;

                IF product_data.is_hidden THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1012,
                        'message', 'Selected product is hidden and cannot be ordered',
                        'id', product_id
                    )::TEXT;
                END IF;

                IF first_currency_code IS NULL THEN
                    first_currency_code := product_data.currency_code;
                ELSE
                    IF product_data.currency_code IS DISTINCT FROM first_currency_code THEN
                        RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                            'code', 1014,
                            'message', 'Products in the order must have the same currency',
                            'expected_currency', first_currency_code,
                            'actual_currency', product_data.currency_code
                        )::TEXT;
                    END IF;
                END IF;

                -- Build the product details for the ticket
                DECLARE
                    v_spot_title TEXT := NULL;
                    v_spot_description TEXT := NULL;
                BEGIN
                    -- Safe extraction of spot details
                    IF spot_id IS NOT NULL AND spot_product IS NOT NULL THEN
                         -- Only access fields if we have a spot_id (implies spot_product is fully set from spot lookup)
                         -- AND product_id matches.
                         IF product_id = spot_product.id THEN
                             v_spot_title := spot_product.spot_title;
                             v_spot_description := spot_product.description;
                         END IF;
                    END IF;

                    ticket_products := ticket_products || jsonb_strip_nulls(JSONB_BUILD_OBJECT(
                        'id', product_id,
                        'title', product_data.title,
                        'type', product_data.type,
                        'type_title', product_data.type_title,
                        'price', product_data.price,
                        'currency_code', product_data.currency_code,
                        'spot_title', v_spot_title,
                        'description', v_spot_description,
                        'data', product_data.data
                    ));
                END;

                -- Accumulate the product price into the order total
                calculated_price := calculated_price + COALESCE(product_data.price, 0)::NUMERIC(10,2);

                -- Accumulate the product deposit into the order deposit total
                v_product_deposit := COALESCE((product_data.data->'deposit'->>'amount')::NUMERIC, 0);
                IF v_product_deposit > COALESCE(product_data.price, 0) THEN
                    RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                        'code', 1016,
                        'message', 'Deposit amount cannot exceed product price',
                        'product_id', product_id,
                        'deposit', v_product_deposit,
                        'price', product_data.price
                    )::TEXT;
                END IF;
                v_total_deposit := v_total_deposit + v_product_deposit;

                -- Link the ticket and product to the order
                INSERT INTO eshop.order_product_ticket ("order", product, ticket)
                VALUES (order_id, product_id, ticket_id)
                RETURNING id INTO order_product_ticket_id;

                -- For the spot product, link the generated order product ticket id to the spot record
                IF spot_id IS NOT NULL THEN
                    IF product_id = spot_product.id THEN
                        UPDATE eshop.spots
                        SET order_product_ticket = order_product_ticket_id, updated_at = now
                        WHERE id = spot_id;
                    END IF;
                END IF;
            END LOOP;

            -- If no explicit ticket->spot was provided, then at least one of the fields must be a spot product.
            IF spot_product IS NULL THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT('code', 1015, 'message', 'Spot product is missing in ticket fields')::TEXT;
            END IF;

            -- Append the ticket details (with its products and the extracted ticket note) to the overall ticket_details array
            IF NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x."order"=order_id AND x.ticket=ticket_id) THEN
              INSERT INTO eshop.order_product_ticket("order",ticket,product) VALUES(order_id,ticket_id,NULL);
            END IF;
            ticket_details := ticket_details || JSONB_BUILD_OBJECT(
                'id', ticket_id,
                'ticket_symbol', v_ticket_symbol,
                'note', ticket_note,
                'products', ticket_products
            );
        END LOOP;

        order_data := input_data - 'ticket' || JSONB_BUILD_OBJECT('tickets', ticket_details);

        -- Determine the bank account details based on the form and supported currency fallback using unit accounts only
        -- Modified Bank Account Selection: Exclude CASH Accounts
        IF bank_account_id IS NULL THEN
            SELECT uba.bank_account, ba.account_number, ba.account_number_human_readable, ba.creditor_name
            INTO bank_account_id, account_number, account_number_human_readable, creditor_name
            FROM eshop.unit_bank_accounts uba
            JOIN eshop.bank_accounts ba ON uba.bank_account = ba.id
            WHERE uba.unit = (SELECT unit FROM public.occasions WHERE id = occasion_id)
              AND ba.supported_currencies @> ARRAY[first_currency_code]
              AND (ba.type IS DISTINCT FROM 'CASH') -- EXCLUDE CASH ACCOUNTS
            ORDER BY uba.priority ASC, ba.id ASC
            LIMIT 1;

            IF bank_account_id IS NULL THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                    'code', 1018,
                    'message', 'No available bank account supports the required currency',
                    'required_currency', first_currency_code
                )::TEXT;
            END IF;
        ELSE
            -- Validate manually selected account: Exclude CASH Accounts
            PERFORM 1
            FROM eshop.unit_bank_accounts uba
            JOIN eshop.bank_accounts ba ON uba.bank_account = ba.id
            WHERE uba.unit = (SELECT unit FROM public.occasions WHERE id = occasion_id)
              AND ba.id = bank_account_id
              AND ba.supported_currencies @> ARRAY[first_currency_code]
              AND (ba.type IS DISTINCT FROM 'CASH'); -- EXCLUDE CASH ACCOUNTS

            IF NOT FOUND THEN
                RAISE EXCEPTION '%', JSONB_BUILD_OBJECT(
                    'code', 1018,
                    'message', 'The specified bank account does not support the required currency, is not linked, or is invalid (CASH type)',
                    'expected_currency', first_currency_code,
                    'provided_bank_account', bank_account_id
                )::TEXT;
            END IF;

            SELECT b.account_number, b.account_number_human_readable, b.creditor_name
            INTO account_number, account_number_human_readable, creditor_name
            FROM eshop.bank_accounts b
            WHERE b.id = bank_account_id;
        END IF;

        -- A configured account holder takes precedence. Otherwise use the
        -- occasion's organization name for EPC payment instructions.
        IF upper(trim(first_currency_code)) = 'EUR' AND NULLIF(trim(creditor_name), '') IS NULL THEN
          SELECT left(trim(regexp_replace(title, '[[:space:][:cntrl:]]+', ' ', 'g')), 70)
          INTO creditor_name
          FROM public.organizations
          WHERE id = organization_id;
        END IF;

        -- If user chose to pay full amount, skip deposit
        IF input_data->>'payment_type' = 'full' THEN
            v_total_deposit := 0;
        END IF;

        -- Generate a variable symbol and create the payment info record
        IF calculated_price>0 AND NOT public.payment_reference_scope_enabled_internal(form_id) THEN
          generated_variable_symbol := public.generate_payment_variable_symbol(bank_account_id, form_id);
        END IF;
        INSERT INTO eshop.payment_info (bank_account, variable_symbol, amount, deposit_amount, currency_code, created_at)
        VALUES (bank_account_id, generated_variable_symbol, calculated_price, NULLIF(v_total_deposit, 0), first_currency_code, now)
        RETURNING id INTO payment_info_id;
        IF calculated_price>0 AND public.payment_reference_scope_enabled_internal(form_id) THEN
          UPDATE eshop.orders SET payment_info=payment_info_id WHERE id=order_id;
          generated_variable_symbol:=public.reserve_order_payment_reference_internal(payment_info_id,form_id);
          UPDATE eshop.payment_info SET variable_symbol=generated_variable_symbol WHERE id=payment_info_id;
        END IF;

        IF upper(trim(first_currency_code)) = 'EUR' AND calculated_price > 0 THEN
          IF creditor_name IS NULL OR length(trim(creditor_name)) NOT BETWEEN 1 AND 70 THEN
            RAISE EXCEPTION 'EUR_CREDITOR_NAME_REQUIRED';
          END IF;
          IF account_number IS NULL OR NOT public.is_valid_iban(account_number) THEN
            RAISE EXCEPTION 'EUR_VALID_IBAN_REQUIRED';
          END IF;
          generated_creditor_reference := public.generate_creditor_reference(generated_variable_symbol);
          UPDATE eshop.payment_info
          SET creditor_reference = generated_creditor_reference
          WHERE id = payment_info_id AND creditor_reference IS NULL;
        END IF;

        -- persist all of the non‐state fields
        UPDATE eshop.orders
        SET
          price         = calculated_price,
          currency_code = first_currency_code,
          payment_info  = payment_info_id,
          data          = order_data,
          updated_at    = now
        WHERE id = order_id;

        -- Apply inventory allocations. This will raise an overbooking error if spots are unavailable.
        PERFORM apply_allocations(order_id);

        -- Always mark as 'ordered' initially to satisfy state requirements
        IF calculated_price = 0 THEN
          PERFORM update_order_and_tickets_to_paid(order_id);
        ELSE
          UPDATE eshop.orders
          SET state      = 'ordered'
          WHERE id = order_id;

          -- NULL inherits the occasion default; zero is an explicit immediate deadline.
          form_deadline_duration := coalesce(form_deadline_duration,
            (SELECT (feature->>'deadline_duration_seconds')::bigint
             FROM jsonb_array_elements(occasion_features) feature WHERE feature->>'code'='form'),604800);
          -- Calculate deadline if deadline duration is provided
          IF form_deadline_duration IS NOT NULL THEN
              deadline := now + make_interval(secs => form_deadline_duration);
              PERFORM public.set_payment_deadline(payment_info_id, deadline);
          ELSE
              deadline := NULL;
          END IF;
        END IF;

        -- Check via Unified Helper if order is already paid (e.g. price is 0)
        PERFORM public.recalculate_order_payment_status(order_id);

        -- Queue deposit reminder if deposit exists and deadline is days-based (not "on site")
        IF v_total_deposit > 0 THEN
            DECLARE
                v_occ_start_time TIMESTAMPTZ;
                v_deposit_deadline_days INT;
                v_deposit_deadline TEXT;
                v_deposit_deadline_ts TIMESTAMPTZ;
                v_deposit_feature JSONB;
            BEGIN
                -- Read occasion start_time
                SELECT start_time INTO v_occ_start_time
                FROM public.occasions WHERE id = occasion_id;

                -- Get deposit feature config from features JSONB
                SELECT elem INTO v_deposit_feature
                FROM jsonb_array_elements(occasion_features) elem
                WHERE elem->>'code' = 'deposit';

                v_deposit_deadline_days := (v_deposit_feature->>'deposit_deadline_days')::int;
                v_deposit_deadline := v_deposit_feature->>'deposit_deadline';

                -- Store deposit deadline on payment_info and queue reminder
                IF v_deposit_deadline IS DISTINCT FROM 'on_site' AND v_deposit_deadline_days IS NOT NULL THEN
                    v_deposit_deadline_ts := v_occ_start_time - make_interval(days => v_deposit_deadline_days);

                    -- Store the calculated deposit deadline on the payment_info record
                    UPDATE eshop.payment_info
                    SET deposit_deadline = v_deposit_deadline_ts
                    WHERE id = payment_info_id;

                    -- One queue boundary resolves form and occasion reminder settings.
                    PERFORM public.queue_payment_reminders(occasion_id,0);
                END IF;
                -- Note: if deposit_deadline = 'on_site', deposit_deadline stays NULL → means "Na místě"
            END;
        END IF;

        -- Log the order to orders_history with details
        INSERT INTO eshop.orders_history (created_at, data, "order", state, price, currency_code)
        VALUES (
            now,
            JSONB_BUILD_OBJECT('input_data', input_data, 'tickets', ticket_details),
            order_id,
            'ordered',
            calculated_price,
            first_currency_code
        );

        UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id=form_id;
        -- Get the reply-to email for the order
        reply_to := get_reply_to_email_for_order(order_id);

        -- Check features and auto-import users if enabled
        PERFORM public.process_occasion_auto_import(occasion_id);

        -- Prepare the success response JSON
        result := JSONB_BUILD_OBJECT(
            'code', 200,
            'order', JSONB_BUILD_OBJECT(
                'id', order_id,
                'order_symbol', assigned_order_symbol,
                'data', order_data,
                'form', JSONB_BUILD_OBJECT(
                    'id', form_id,
                    'data', form_data
                ),
                'payment_info', JSONB_BUILD_OBJECT(
                    'id', payment_info_id,
                    'variable_symbol', generated_variable_symbol,
                    'creditor_reference', generated_creditor_reference,
                    'creditor_name', creditor_name,
                    'amount', calculated_price,
                    'deposit_amount', NULLIF(v_total_deposit, 0),
                    'deposit_deadline', (SELECT deposit_deadline FROM eshop.payment_info WHERE id = payment_info_id),
                    'deadline', deadline,
                    'account_number', account_number,
                    'account_number_human_readable', account_number_human_readable,
                    'currency_code', first_currency_code
                ),
                'occasion', JSONB_BUILD_OBJECT(
                    'id', occasion_id,
                    'organization', organization_id,
                    'unit', unit_id,
                    'title', occasion_title,
                    'features', occasion_features,
                    'data', (SELECT data FROM public.occasions WHERE id = occasion_id)
                ),
                'reply_to', reply_to
            )
        );

    EXCEPTION WHEN OTHERS THEN
        -- In case of any error, the inner block is rolled back and we capture the error message.
        result := CASE
            WHEN left(SQLERRM, 1) = '{' THEN SQLERRM::JSONB
            ELSE JSONB_BUILD_OBJECT('code', 1013, 'message', SQLERRM)
        END;
    END;

    RETURN result;
END;
$$;

REVOKE ALL ON FUNCTION public.finalize_ticket_order_internal_v1(bigint,jsonb,boolean) FROM PUBLIC,anon,authenticated;

COMMIT;
