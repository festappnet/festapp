-- Confirmed swap effects use one financial mutation and one existing receipt.

-- SOURCE: inventory/lock_spot_assignment_scope_internal_v1.sql
-- One parent-before-child lock owner. Financial seat commands include the
-- complete order-product closure; existing inventory callers keep their scope.
CREATE OR REPLACE FUNCTION public.lock_spot_assignment_scope_internal(
 p_spots bigint[],p_resources bigint[],p_financial boolean)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE before_spots jsonb;after_spots jsonb;before_resources jsonb;after_resources jsonb;
 resource_ids bigint[];v_orders bigint[];v_order_products bigint[]:='{}';
BEGIN
 IF p_financial IS NULL THEN RAISE invalid_parameter_value USING MESSAGE='assignment lock mode required'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_array(s.id,s.occasion,s.product,s.blueprint,s.inventory_context,s.resource,s.resource_slot,s.order_product_ticket) ORDER BY s.id),'[]')
 INTO before_spots FROM eshop.spots s WHERE s.id=ANY(p_spots);
 SELECT ARRAY(SELECT DISTINCT id FROM (
  SELECT unnest(p_resources) id UNION SELECT s.resource FROM eshop.spots s WHERE s.id=ANY(p_spots)
  UNION SELECT rs.resource FROM public.resource_slots rs JOIN eshop.spots s ON s.resource_slot=rs.id WHERE s.id=ANY(p_spots)) r WHERE id IS NOT NULL)
 INTO resource_ids;
 SELECT coalesce(jsonb_agg(jsonb_build_array(r.id,r.inventory_pool) ORDER BY r.id),'[]') INTO before_resources FROM public.resources r WHERE r.id=ANY(resource_ids);
 SELECT ARRAY(SELECT DISTINCT i."order" FROM eshop.order_product_ticket i JOIN eshop.spots s ON s.order_product_ticket=i.id WHERE s.id=ANY(p_spots) ORDER BY i."order") INTO v_orders;
 PERFORM public.lock_order_capacity_scope_internal(v_orders);
 IF p_financial THEN
  IF v_orders IS DISTINCT FROM ARRAY(SELECT DISTINCT i."order" FROM eshop.order_product_ticket i JOIN eshop.spots s ON s.order_product_ticket=i.id WHERE s.id=ANY(p_spots) ORDER BY i."order") THEN
   RAISE serialization_failure USING MESSAGE='assignment order parents changed; retry the same command'; END IF;
  SELECT ARRAY(SELECT DISTINCT product FROM eshop.order_product_ticket WHERE "order"=ANY(v_orders) AND product IS NOT NULL ORDER BY product) INTO v_order_products;
 END IF;
 -- Union every affected product before taking any blueprint/inventory child.
 PERFORM 1 FROM eshop.products WHERE id IN(
  SELECT product FROM eshop.spots WHERE id=ANY(p_spots) UNION SELECT unnest(v_order_products)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eshop.blueprints WHERE id IN(
  SELECT blueprint FROM eshop.spots WHERE id=ANY(p_spots)
  UNION SELECT blueprint FROM public.forms WHERE p_financial AND id IN(SELECT form FROM eshop.orders WHERE id=ANY(v_orders))
  UNION SELECT blueprint FROM eshop.spots WHERE product=ANY(v_order_products)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.inventory_pools WHERE id IN(
  SELECT inventory_pool FROM public.resources WHERE id=ANY(resource_ids)
  UNION SELECT c.inventory_pool FROM public.inventory_contexts c JOIN eshop.spots s ON s.inventory_context=c.id WHERE s.id=ANY(p_spots)
  UNION SELECT c.inventory_pool FROM public.inventory_contexts c JOIN eshop.product_inventory_contexts pc ON pc.inventory_context=c.id WHERE pc.product=ANY(v_order_products)) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM public.resources WHERE id=ANY(resource_ids) ORDER BY id FOR UPDATE;
 SELECT coalesce(jsonb_agg(jsonb_build_array(r.id,r.inventory_pool) ORDER BY r.id),'[]') INTO after_resources FROM public.resources r WHERE r.id=ANY(resource_ids);
 IF before_resources IS DISTINCT FROM after_resources THEN RAISE serialization_failure USING MESSAGE='resource parent changed; retry the same command'; END IF;
 IF p_financial THEN
  PERFORM 1 FROM public.inventory_contexts WHERE id IN(
   SELECT inventory_context FROM eshop.product_inventory_contexts WHERE product=ANY(v_order_products)
   UNION SELECT inventory_context FROM eshop.spots WHERE id=ANY(p_spots)) ORDER BY id FOR UPDATE;
 END IF;
 PERFORM 1 FROM public.resource_slots WHERE resource=ANY(resource_ids) ORDER BY id FOR UPDATE;
 IF p_financial THEN
  PERFORM 1 FROM eshop.payment_info WHERE id IN(SELECT payment_info FROM eshop.orders WHERE id=ANY(v_orders)) ORDER BY id FOR UPDATE;
 END IF;
 PERFORM 1 FROM eshop.spots WHERE id=ANY(p_spots) ORDER BY id FOR UPDATE;
 IF p_financial THEN
  PERFORM 1 FROM eshop.tickets WHERE id IN(SELECT i.ticket FROM eshop.order_product_ticket i JOIN eshop.spots s ON s.order_product_ticket=i.id WHERE s.id=ANY(p_spots)) ORDER BY id FOR UPDATE;
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_array(s.id,s.occasion,s.product,s.blueprint,s.inventory_context,s.resource,s.resource_slot,s.order_product_ticket) ORDER BY s.id),'[]')
 INTO after_spots FROM eshop.spots s WHERE s.id=ANY(p_spots);
 IF before_spots IS DISTINCT FROM after_spots THEN RAISE serialization_failure USING MESSAGE='spot parent changed; retry the same command'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.lock_spot_assignment_scope_internal(bigint[],bigint[],boolean) FROM PUBLIC,anon,authenticated,service_role;

-- Existing private SQL callers retain their arity, not a second implementation.
CREATE OR REPLACE FUNCTION public.lock_spot_assignment_scope_internal_v1(p_spots bigint[],p_resources bigint[] DEFAULT '{}')
RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT public.lock_spot_assignment_scope_internal(p_spots,p_resources,false)
$$;
REVOKE ALL ON FUNCTION public.lock_spot_assignment_scope_internal_v1(bigint[],bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop/swap_spot_tickets.sql
CREATE OR REPLACE FUNCTION public._swap_spots_generate_product_json(
    p_product_id BIGINT,
    p_spot_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SET search_path = public, extensions
AS $$
DECLARE
    product_data RECORD;
BEGIN
    -- This query joins product, its type, and the spot (if provided)
    -- to get all data needed for the JSON object.
    SELECT
        p.id,
        p.price,
        p.title,
        p.description,
        p.currency_code,
        pt.title AS type_title,
        pt.type AS type,
        s.title AS spot_title
    INTO
        product_data
    FROM
        eshop.products AS p
    JOIN
        eshop.product_types AS pt ON p.product_type = pt.id
    LEFT JOIN
        eshop.spots AS s ON s.id = p_spot_id -- Use p_spot_id for spot_title
    WHERE
        p.id = p_product_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Product data not found for product_id %', p_product_id;
    END IF;

    -- Build the JSON object.
    -- jsonb_strip_nulls ensures that if 'spot_title' is NULL
    -- (because p_spot_id was NULL), the key is removed entirely.
    RETURN jsonb_strip_nulls(jsonb_build_object(
        'id', product_data.id,
        'type', product_data.type,
        'price', product_data.price,
        'title', product_data.title,
        'spot_title', product_data.spot_title,
        'type_title', product_data.type_title,
        'description', product_data.description,
        'currency_code', product_data.currency_code
    )) || coalesce(public.order_spot_metadata_internal(p_spot_id), '{}'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public._swap_spots_update_ticket(
    p_opt_id BIGINT,
    p_new_product_id BIGINT,
    p_new_spot_id BIGINT
)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    opt RECORD;
    ord RECORD;
    original_product_id BIGINT;
    original_product_json JSONB;
    original_price NUMERIC;

    new_product_json JSONB;
    new_price NUMERIC;
    new_data JSONB;
    new_order_price NUMERIC;
    new_state TEXT;

    price_delta NUMERIC;
    history_needed BOOLEAN;
    now_time TIMESTAMP WITH TIME ZONE := NOW();
BEGIN
    -- 1. Get current ticket and order data
    SELECT * INTO opt FROM eshop.order_product_ticket WHERE id = p_opt_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order Product Ticket % not found', p_opt_id; END IF;

    PERFORM public.check_ticket_is_mutable(opt.ticket);
    SELECT * INTO ord FROM eshop.orders WHERE id = opt."order" FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order % not found', opt."order"; END IF;

    original_product_id := opt.product;

    -- 2. Find the *original* product JSON and price from the order_ids.data
    SELECT prod, (prod->>'price')::numeric
    INTO original_product_json, original_price
    FROM jsonb_array_elements(ord.data->'tickets') tckt,
         jsonb_array_elements(tckt->'products') prod
    WHERE (tckt->>'id')::bigint = opt.ticket
      AND (prod->>'id')::bigint = original_product_id;

    IF original_price IS NULL THEN
        RAISE EXCEPTION 'Could not find original price for product % on ticket %', original_product_id, opt.ticket;
    END IF;

    -- 3. Generate the *new* product JSON
    new_product_json := public._swap_spots_generate_product_json(p_new_product_id, p_new_spot_id);
    new_price := (new_product_json->>'price')::numeric;
    IF new_product_json->>'currency_code' IS DISTINCT FROM ord.currency_code THEN
      RAISE EXCEPTION 'BLUEPRINT_CURRENCY_MISMATCH'; END IF;

    -- 4. Check if an update is even needed.
    -- If the new JSON is identical to the old, nothing needs to be done.
    IF original_product_json = new_product_json THEN
        RETURN;
    END IF;

    -- 5. Calculate financials and state
    price_delta := new_price - original_price;
    history_needed := (original_product_id IS DISTINCT FROM p_new_product_id);
    new_order_price := COALESCE(ord.price, 0) + price_delta;

    -- Recalculate order state
    SELECT CASE
        WHEN COALESCE(pi.paid, 0) >= new_order_price AND new_order_price > 0 THEN 'paid'
        WHEN new_order_price <= 0 THEN 'paid'
        ELSE 'ordered'
    END INTO new_state
    FROM (SELECT COALESCE((SELECT paid FROM eshop.payment_info WHERE id=ord.payment_info),0) AS paid) pi;

    -- 6. Build the new order_ids.data JSON
    new_data := jsonb_set(
        ord.data,
        '{tickets}',
        (SELECT jsonb_agg(
            -- Find the matching ticket
            CASE WHEN (tckt->>'id')::bigint = opt.ticket
            THEN jsonb_set(
                tckt,
                '{products}',
                (SELECT jsonb_agg(
                    -- Find the matching product and replace it
                    CASE
                        WHEN (prod->>'id')::bigint = original_product_id
                        THEN new_product_json -- Swap in the new product JSON
                        ELSE prod
                    END
                ) FROM jsonb_array_elements(tckt->'products') prod)
            )
            ELSE tckt
            END
        ) FROM jsonb_array_elements(ord.data->'tickets') tckt)
    );

    -- 7. Perform all database updates

    -- Update payment info
    IF price_delta <> 0 THEN
        IF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=ord.payment_info AND payment_method='stripe') THEN
            RAISE EXCEPTION 'STRIPE_ORDER_PRICE_IMMUTABLE'; END IF;
        UPDATE eshop.payment_info SET amount = amount + price_delta WHERE id = ord.payment_info;
    END IF;

    -- Update the order itself
    UPDATE eshop.orders
    SET
        price = new_order_price,
        data = new_data,
        state = new_state,
        updated_at = now_time
    WHERE id = ord.id;

    -- Update the link table
    UPDATE eshop.order_product_ticket
    SET
        product = p_new_product_id
    WHERE id = p_opt_id;

    -- 8. Create history log *only if* the product ID actually changed
    IF history_needed THEN
        INSERT INTO eshop.orders_history("order", data, state, price, currency_code)
        VALUES (ord.id, new_data, new_state, new_order_price, ord.currency_code);
    END IF;

END;
$$;


-- Only the aggregate applier calls this worker, after locking the complete
-- assignment graph and checking scope, holds and atomic-unit eligibility.
-- The price/order helper remains the sole financial calculation.
CREATE OR REPLACE FUNCTION public.apply_blueprint_seat_pair_locked_internal(p_first bigint,p_second bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE first_spot eshop.spots;second_spot eshop.spots;
BEGIN
 SELECT * INTO STRICT first_spot FROM eshop.spots WHERE id=p_first;
 SELECT * INTO STRICT second_spot FROM eshop.spots WHERE id=p_second;
 IF first_spot.order_product_ticket IS NOT NULL AND second_spot.order_product_ticket IS NOT NULL THEN
  PERFORM public._swap_spots_update_ticket(first_spot.order_product_ticket,second_spot.product,p_second);
  PERFORM public._swap_spots_update_ticket(second_spot.order_product_ticket,first_spot.product,p_first);
 ELSIF first_spot.order_product_ticket IS NOT NULL THEN
  PERFORM public._swap_spots_update_ticket(first_spot.order_product_ticket,second_spot.product,p_second);
 ELSIF second_spot.order_product_ticket IS NOT NULL THEN
  PERFORM public._swap_spots_update_ticket(second_spot.order_product_ticket,first_spot.product,p_first);
 ELSE RETURN;
 END IF;
 UPDATE eshop.spots SET order_product_ticket=CASE WHEN id=p_first THEN second_spot.order_product_ticket ELSE first_spot.order_product_ticket END
 WHERE id IN(p_first,p_second);
END $$;
REVOKE ALL ON FUNCTION public.apply_blueprint_seat_pair_locked_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.swap_spot_tickets(spot_id_1 bigint,spot_id_2 bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
BEGIN
  PERFORM public.swap_spot_tickets_client_sync_v1(
    spot_id_1,spot_id_2,extensions.gen_random_uuid());
END; $$;
REVOKE ALL ON FUNCTION public.swap_spot_tickets(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.swap_spot_tickets(bigint,bigint) TO authenticated;

REVOKE ALL ON FUNCTION public._swap_spots_generate_product_json(bigint,bigint),public._swap_spots_update_ticket(bigint,bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: blueprint/swap_money_projection.sql
-- One financial projection for preview and committed results. Never invent a
-- zero quote for missing data or let an unrepresentable result commit first.
CREATE OR REPLACE FUNCTION public.get_blueprint_swap_money_internal(p_orders jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 IF jsonb_typeof(p_orders) IS DISTINCT FROM 'array' OR EXISTS(
  SELECT 1 FROM jsonb_array_elements(p_orders) e WHERE
   jsonb_typeof(e->'beforeAmount') IS DISTINCT FROM 'number'
   OR jsonb_typeof(e->'afterAmount') IS DISTINCT FROM 'number'
   OR jsonb_typeof(e->'delta') IS DISTINCT FROM 'number'
   OR length(e->>'beforeAmount')>40 OR length(e->>'afterAmount')>40 OR length(e->>'delta')>40
   OR coalesce(btrim(e->>'currencyCode'),'')!~'^[A-Za-z]{3}$'
   OR coalesce(length(e->>'beforeState'),0) NOT BETWEEN 1 AND 64
   OR coalesce(length(e->>'afterState'),0) NOT BETWEEN 1 AND 64) THEN
  RAISE check_violation USING MESSAGE='BLUEPRINT_SWAP_MONEY_UNAVAILABLE'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('orderId',e->'orderId','beforeAmount',e->>'beforeAmount',
  'afterAmount',e->>'afterAmount','delta',e->>'delta','currencyCode',upper(btrim(e->>'currencyCode')),
  'beforeState',e->>'beforeState','afterState',e->>'afterState') ORDER BY (e->>'orderId')::bigint),'[]')
 INTO result FROM jsonb_array_elements(p_orders) e;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.get_blueprint_swap_money_internal(jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: blueprint/apply_seat_swap_internal.sql
-- Validate only entities actually participating in this swap before locking
-- their parents, then again once the complete assignment closure is locked.
CREATE OR REPLACE FUNCTION public.check_blueprint_swap_scope_internal(p_occasion bigint,p_spots bigint[])
RETURNS void LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF (SELECT count(*) FROM eshop.spots WHERE id=ANY(p_spots) AND occasion=p_occasion)<>cardinality(p_spots)
  OR EXISTS(SELECT 1 FROM eshop.spots s LEFT JOIN eshop.blueprints b ON b.id=s.blueprint
   LEFT JOIN eshop.products p ON p.id=s.product LEFT JOIN eshop.product_types pt ON pt.id=p.product_type
   LEFT JOIN eshop.order_product_ticket i ON i.id=s.order_product_ticket
   LEFT JOIN eshop.orders o ON o.id=i."order" LEFT JOIN eshop.tickets t ON t.id=i.ticket
   WHERE s.id=ANY(p_spots) AND (
    (s.blueprint IS NOT NULL AND b.occasion IS DISTINCT FROM p_occasion)
    OR (s.product IS NOT NULL AND (p.occasion IS DISTINCT FROM p_occasion OR pt.occasion IS DISTINCT FROM p_occasion))
    OR (s.order_product_ticket IS NOT NULL AND (o.occasion IS DISTINCT FROM p_occasion OR t.occasion IS DISTINCT FROM p_occasion)))) THEN
  RAISE insufficient_privilege USING MESSAGE='swap assignment scope unavailable'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_blueprint_swap_scope_internal(bigint,bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- Capture the actual financial owner's effects, never a second price calculation.
-- Preview callers roll this work back; confirmed command callers retain it only
-- when its digest matches the effects previously approved by the operator.
CREATE OR REPLACE FUNCTION public.apply_blueprint_seat_swap_internal(p_first bigint,p_second bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE occ bigint; left_ids bigint[];right_ids bigint[];ids bigint[];v_order_ids bigint[];
 before_orders jsonb;sides jsonb;revisions jsonb;effects jsonb;facts jsonb;result jsonb;i integer;
BEGIN
 SELECT min(occasion) INTO occ FROM eshop.spots WHERE id IN(p_first,p_second);
 IF p_first IS NULL OR p_second IS NULL OR p_first=p_second OR occ IS NULL
  OR (SELECT count(*) FROM eshop.spots WHERE id IN(p_first,p_second) AND occasion=occ)<>2
  OR public.can_write_orders(occ) IS NOT TRUE THEN
  RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 PERFORM public.check_occasion_writable(occ);
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 left_ids:=public.blueprint_selection_unit_spots_internal(p_first);
 right_ids:=public.blueprint_selection_unit_spots_internal(p_second);
 IF cardinality(left_ids)<>cardinality(right_ids) OR left_ids && right_ids THEN
  RAISE EXCEPTION 'BLUEPRINT_UNIT_SIZE_MISMATCH'; END IF;
 ids:=left_ids||right_ids;
 PERFORM public.check_blueprint_swap_scope_internal(occ,ids);
 PERFORM public.lock_spot_assignment_scope_internal(ids,'{}'::bigint[],true);
 PERFORM public.check_blueprint_swap_scope_internal(occ,ids);
 -- Ticket rows are locked before rechecking used atomic-unit members.
 PERFORM public.check_blueprint_selection_units_internal(ids);
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'revision',layout_revision) ORDER BY id),'[]')
 INTO revisions FROM eshop.blueprints WHERE id IN(SELECT blueprint FROM eshop.spots WHERE id=ANY(ids));
 SELECT array_agg(DISTINCT i."order") INTO v_order_ids FROM eshop.spots s
 JOIN eshop.order_product_ticket i ON i.id=s.order_product_ticket WHERE s.id=ANY(ids);
 IF EXISTS(SELECT 1 FROM eshop.spots s LEFT JOIN eshop.blueprint_seat_bindings b ON b.spot=s.id
  WHERE s.id=ANY(ids) AND (b.blocked OR s.product IS NULL OR (s.secret IS NOT NULL AND s.secret_expiration_time>statement_timestamp()))) THEN
  RAISE EXCEPTION 'BLUEPRINT_SEAT_PROTECTED'; END IF;
 SELECT coalesce(jsonb_object_agg(o.id::text,jsonb_build_object('amount',o.price,'state',o.state,
  'payment',CASE WHEN p.id IS NULL THEN NULL ELSE jsonb_build_object('id',p.id,'method',p.payment_method,
   'amount',p.amount,'paid',p.paid,'returned',p.returned,'currency',p.currency_code) END)),'{}')
 INTO before_orders FROM eshop.orders o LEFT JOIN eshop.payment_info p ON p.id=o.payment_info WHERE o.id=ANY(v_order_ids);
 WITH lifecycle AS MATERIALIZED (SELECT id,state FROM public.blueprint_spot_facts_internal(occ,ids))
 SELECT coalesce(jsonb_agg(jsonb_build_object('spotId',s.id,'title',s.title,'state',lifecycle.state,'productId',s.product,
  'productTitle',p.title,'orderId',o.id,'ticketId',i.ticket,
  'customer',jsonb_build_object('name',o.data->>'name','surname',o.data->>'surname','email',o.data->>'email')) ORDER BY s.id),'[]'),
 coalesce(jsonb_agg(jsonb_build_object('spot',s.id,'blueprint',s.blueprint,'item',i.id,'ticketState',t.state,
  'product',s.product,'price',p.price,'currency',p.currency_code) ORDER BY s.id),'[]')
 INTO sides,facts FROM eshop.spots s LEFT JOIN eshop.products p ON p.id=s.product
 LEFT JOIN eshop.order_product_ticket i ON i.id=s.order_product_ticket LEFT JOIN eshop.tickets t ON t.id=i.ticket
 LEFT JOIN eshop.orders o ON o.id=i."order" LEFT JOIN lifecycle ON lifecycle.id=s.id WHERE s.id=ANY(ids);
 FOR i IN 1..cardinality(left_ids) LOOP PERFORM public.apply_blueprint_seat_pair_locked_internal(left_ids[i],right_ids[i]); END LOOP;
 SELECT coalesce(jsonb_agg(jsonb_build_object('orderId',id,
  'beforeAmount',(before_orders->id::text->>'amount')::numeric,'afterAmount',price,
  'delta',price-(before_orders->id::text->>'amount')::numeric,'currencyCode',currency_code,
  'beforeState',before_orders->id::text->>'state','afterState',state) ORDER BY id),'[]')
 INTO effects FROM eshop.orders WHERE id=ANY(v_order_ids);
 result:=jsonb_build_object('code',200,'spotIds',to_jsonb(ids),'sourceSpotIds',left_ids,'targetSpotIds',right_ids,
  'blueprints',revisions,'sides',sides,'orders',effects);
 RETURN result||jsonb_build_object('confirmationHash',encode(extensions.digest(convert_to(
  jsonb_build_object('first',p_first,'second',p_second,'result',result,'facts',facts,'beforeOrders',before_orders)::text,'UTF8'),'sha256'),'hex'));
END $$;
REVOKE ALL ON FUNCTION public.apply_blueprint_seat_swap_internal(bigint,bigint) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: blueprint/swap_command_internal.sql
CREATE OR REPLACE FUNCTION public.swap_blueprint_seats_command_internal(
 p_first bigint,p_second bigint,p_command_id uuid,p_confirmation jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE actor uuid:=auth.uid();occ bigint;started jsonb;fingerprint text;users uuid[];
 effect jsonb;affected bigint[];result_data jsonb;money jsonb;
BEGIN
 SELECT occasion INTO occ FROM public.client_mutation_receipts
 WHERE command_id=p_command_id AND actor_id=actor AND command_name='inventory.spots.swap';
 IF NOT FOUND THEN SELECT min(occasion) INTO occ FROM eshop.spots WHERE id IN(p_first,p_second); END IF;
 IF actor IS NULL OR p_first IS NULL OR p_second IS NULL OR p_first=p_second OR occ IS NULL
  OR public.can_write_orders(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 fingerprint:=encode(extensions.digest(convert_to((jsonb_build_object('spot1',p_first,'spot2',p_second)
  ||CASE WHEN p_confirmation IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('confirmation',p_confirmation) END)::text,'UTF8'),'sha256'),'hex');
 started:=public.begin_client_mutation_v1(p_command_id,'inventory.spots.swap',occ,actor,fingerprint);
 IF started->>'disposition'='replay' THEN
  IF public.can_write_orders(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  RETURN started->'response';
 END IF;
 IF (SELECT count(*) FROM eshop.spots WHERE id IN(p_first,p_second) AND occasion=occ)<>2 THEN
  RAISE insufficient_privilege USING MESSAGE='foreign spot swap'; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 affected:=CASE WHEN p_confirmation IS NULL THEN ARRAY[p_first,p_second] ELSE
  public.blueprint_selection_unit_spots_internal(p_first)||public.blueprint_selection_unit_spots_internal(p_second) END;
 SELECT coalesce(array_agg(DISTINCT ou."user"),'{}') INTO users FROM eshop.spots s
 JOIN eshop.order_product_ticket i ON i.id=s.order_product_ticket
 JOIN public.occasion_users ou ON ou.ticket=i.ticket AND ou.occasion=occ WHERE s.id=ANY(affected);
 BEGIN
  effect:=public.apply_blueprint_seat_swap_internal(p_first,p_second);
  IF p_confirmation IS NOT NULL THEN money:=public.get_blueprint_swap_money_internal(effect->'orders'); END IF;
  IF p_confirmation IS NOT NULL AND
   (effect->>'confirmationHash' IS DISTINCT FROM p_confirmation->>'hash'
    OR effect->'sourceSpotIds' IS DISTINCT FROM p_confirmation->'source'
    OR effect->'targetSpotIds' IS DISTINCT FROM p_confirmation->'target'
    OR effect->'blueprints' IS DISTINCT FROM jsonb_build_array(jsonb_build_object(
     'id',(p_confirmation->>'blueprint')::bigint,'revision',(p_confirmation->>'revision')::bigint))) THEN
   RAISE SQLSTATE 'BP002' USING MESSAGE='confirmed swap changed'; END IF;
 EXCEPTION WHEN SQLSTATE 'BP002' THEN
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,jsonb_build_object('reason','BLUEPRINT_SWAP_CHANGED'));
 WHEN serialization_failure OR deadlock_detected OR insufficient_privilege THEN RAISE;
 WHEN OTHERS THEN
  IF p_confirmation IS NULL THEN RAISE; END IF;
  RETURN public.complete_client_mutation_outcome_v1(p_command_id,'rejected',409,jsonb_build_object('reason','BLUEPRINT_SWAP_REJECTED'));
 END;
 -- Legacy adapters share the same late guard, not just the scoped UI/MCP RPC.
 IF public.can_write_orders(occ) IS NOT TRUE OR
  (SELECT count(*) FROM eshop.spots WHERE id IN(p_first,p_second) AND occasion=occ)<>2 THEN
  RAISE insufficient_privilege USING MESSAGE='swap selection unavailable'; END IF;
 PERFORM public.check_occasion_writable(occ);
 result_data:=jsonb_build_object('spotIds',jsonb_build_array(p_first,p_second));
 IF p_confirmation IS NOT NULL THEN
  result_data:=result_data||jsonb_build_object('blueprintId',(p_confirmation->>'blueprint')::bigint,
   'layoutRevision',(p_confirmation->>'revision')::bigint,'sourceSpotIds',effect->'sourceSpotIds',
   'targetSpotIds',effect->'targetSpotIds','orders',money);
 END IF;
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,occ,'inventory.spots.swap',
  jsonb_build_array(jsonb_build_object('entityType','spot_assignment','entityId',NULL,'operation','update',
   'safeLabel','Spot ticket swap','changedFields',jsonb_build_array('order_product_ticket','product'))),users,result_data);
END $$;
REVOKE ALL ON FUNCTION public.swap_blueprint_seats_command_internal(bigint,bigint,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: blueprint/swap_spot_tickets_client_sync_v1.sql
-- Released clients retain their original receipt fingerprint and response.
CREATE OR REPLACE FUNCTION public.swap_spot_tickets_client_sync_v1(p_spot_1 bigint,p_spot_2 bigint,p_command_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.swap_blueprint_seats_command_internal(p_spot_1,p_spot_2,p_command_id)
$$;
REVOKE ALL ON FUNCTION public.swap_spot_tickets_client_sync_v1(bigint,bigint,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.swap_spot_tickets_client_sync_v1(bigint,bigint,uuid) TO authenticated;

-- SOURCE: blueprint/preview_blueprint_swap.sql
-- SQL work is deliberately rolled back after capturing the authoritative result.
-- The existing financial owner is executed; preview maintains no alternate maths.
CREATE OR REPLACE FUNCTION public.preview_blueprint_swap(p_spot_1 bigint,p_spot_2 bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE result jsonb; occ bigint;
BEGIN
 SELECT min(occasion) INTO occ FROM eshop.spots WHERE id IN(p_spot_1,p_spot_2);
 IF occ IS NULL THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 IF public.can_write_orders(occ) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[occ]);
 BEGIN
  result:=public.apply_blueprint_seat_swap_internal(p_spot_1,p_spot_2);
  RAISE SQLSTATE 'BP001' USING MESSAGE='rollback successful swap preview';
 EXCEPTION WHEN SQLSTATE 'BP001' THEN NULL;
 WHEN serialization_failure OR deadlock_detected OR insufficient_privilege THEN RAISE;
 WHEN OTHERS THEN result:=jsonb_build_object('code',409,'reason',SQLERRM,'issues',jsonb_build_array(jsonb_build_object('reason',SQLERRM)));
 END;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.preview_blueprint_swap(bigint,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.preview_blueprint_swap(bigint,bigint) TO authenticated;

-- SOURCE: blueprint/seat_swap.sql
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
  money:=public.get_blueprint_swap_money_internal(effect->'orders');
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

DROP FUNCTION IF EXISTS public.swap_spot_tickets_internal_v1(bigint,bigint);
DROP FUNCTION IF EXISTS public.swap_spot_pair_internal_v1(bigint,bigint);
