-- Reconcile seat swaps through the shared payment lifecycle and expose seating changes in customer updates.

-- SOURCE: eshop_orders/recalculate_order_payment_status.sql
-- One financial eligibility decision for bank facts and actual product changes.
-- Callers own authorization; this private invoker owns no history snapshots.
CREATE OR REPLACE FUNCTION public.reconcile_order_payment_internal_v1(p_order_id bigint, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, extensions
AS $$
DECLARE
    v_order eshop.orders;
    v_payment eshop.payment_info;
    v_eligible boolean;
    v_was_eligible boolean;
    v_transition jsonb;
    v_final_state text;
    v_final_version bigint;
    v_promote boolean;
BEGIN
    IF p_reason IS NULL OR p_reason NOT IN ('payment_fact','product_edit','refund_fact') THEN
        RAISE EXCEPTION 'INVALID_PAYMENT_RECONCILIATION_REASON';
    END IF;
    PERFORM public.lock_order_capacity_scope_internal(ARRAY[p_order_id]);
    SELECT * INTO v_order FROM eshop.orders WHERE id=p_order_id FOR UPDATE;
    SELECT * INTO v_payment FROM eshop.payment_info WHERE id=v_order.payment_info FOR UPDATE;
    v_was_eligible := coalesce(v_order.state IN ('paid','sent'),false);
    -- Online payment prices are immutable at the mutation boundary. A seat-only
    -- edit still invalidates queued content, without reinterpreting provider facts.
    IF p_reason='product_edit' AND public.payment_method_is_online_internal(v_payment.payment_method)
       AND v_order.state IN ('created','ordered','expired','paid','sent') THEN
        PERFORM public.cancel_order_email_intents(p_order_id);
        UPDATE eshop.orders SET email_payment_version=email_payment_version+1,updated_at=now()
        WHERE id=p_order_id RETURNING email_payment_version INTO v_final_version;
        PERFORM public.enqueue_paid_order_tickets(p_order_id);
        RETURN jsonb_build_object('previous_state',v_order.state,'final_state',v_order.state,
            'eligibility_changed',false,'email_payment_version',v_final_version);
    END IF;
    -- Provider facts and non-admission shells retain their existing owners.
    IF v_payment.id IS NULL OR public.payment_method_is_online_internal(v_payment.payment_method)
       OR v_order.state NOT IN ('created','ordered','expired','paid','sent') THEN
        RETURN jsonb_build_object('previous_state',v_order.state,'final_state',v_order.state,
            'eligibility_changed',false,'email_payment_version',v_order.email_payment_version);
    END IF;

    IF p_reason='refund_fact' AND v_order.state IN ('storno','expired') THEN
        RETURN jsonb_build_object('previous_state',v_order.state,'final_state',v_order.state,
            'eligibility_changed',false,'email_payment_version',v_order.email_payment_version);
    END IF;

    IF p_reason='product_edit' THEN
        PERFORM public.ensure_order_payment_instructions_internal(p_order_id);
        SELECT * INTO v_payment FROM eshop.payment_info WHERE id=v_order.payment_info;
    END IF;

    -- The saved deposit is a commercial snapshot, capped by the current price.
    v_eligible := coalesce(v_order.price,0)<=0 OR (coalesce(v_payment.paid,0)-coalesce(v_payment.returned,0))>=
        least(coalesce(v_payment.deposit_amount,v_order.price),v_order.price);
    v_promote := v_eligible AND NOT v_was_eligible;

    IF p_reason='product_edit' OR v_eligible IS DISTINCT FROM v_was_eligible THEN
        PERFORM public.cancel_order_email_intents(p_order_id);
        -- The paid primitive owns the single version bump when promoting.
        IF NOT v_promote THEN
            UPDATE eshop.orders SET email_payment_version=email_payment_version+1,updated_at=now()
            WHERE id=p_order_id;
        END IF;
    END IF;

    IF v_promote THEN
        -- Reuse the existing atomic primitive and delivery boundary. A failed
        -- receipt must abort its outer pairing or receipted product command.
        v_transition := public.update_order_and_tickets_to_paid(p_order_id);
        IF v_transition->>'code' IS DISTINCT FROM '200' THEN
            RAISE EXCEPTION 'ORDER_PAID_TRANSITION_FAILED: %',
                coalesce(v_transition->>'message','invalid transition receipt');
        END IF;
    ELSIF NOT v_eligible AND v_was_eligible THEN
        UPDATE eshop.orders SET state='ordered',updated_at=now() WHERE id=p_order_id;
        UPDATE eshop.tickets t SET state='ordered',updated_at=now()
        FROM eshop.order_product_ticket opt
        WHERE opt.ticket=t.id AND opt."order"=p_order_id AND t.state IN ('paid','sent');
    ELSIF p_reason='product_edit' THEN
        -- An eligible paid order needs the edited content at its final version.
        -- Already sent admission stays sent; used/cancelled tickets stay intact.
        PERFORM public.enqueue_paid_order_tickets(p_order_id);
    END IF;

    -- Cancellation above invalidates the old reminder version. Rebuild only this
    -- payment's eligible reminders, including the balance after a paid deposit.
    IF p_reason='product_edit' OR v_eligible IS DISTINCT FROM v_was_eligible THEN
        PERFORM public.queue_payment_reminders_internal(v_order.occasion,v_payment.id);
    END IF;

    PERFORM public.notification_center_order_state_internal(p_order_id);
    SELECT state,email_payment_version INTO v_final_state,v_final_version FROM eshop.orders WHERE id=p_order_id;
    RETURN jsonb_build_object('previous_state',v_order.state,'final_state',v_final_state,
        'eligibility_changed',v_eligible IS DISTINCT FROM v_was_eligible,
        'email_payment_version',v_final_version);
END;
$$;
REVOKE ALL ON FUNCTION public.reconcile_order_payment_internal_v1(bigint,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reconcile_order_payment_internal_v1(bigint,text) TO postgres,service_role;

CREATE OR REPLACE FUNCTION public.recalculate_order_payment_status(p_order_id bigint)
RETURNS void
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public, extensions
AS $$
BEGIN
    PERFORM public.reconcile_order_payment_internal_v1(p_order_id,'payment_fact');
END;
$$;

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

    price_delta NUMERIC;
    now_time TIMESTAMP WITH TIME ZONE := NOW();
BEGIN
    -- 1. Get current ticket and order data
    SELECT * INTO opt FROM eshop.order_product_ticket WHERE id = p_opt_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order Product Ticket % not found', p_opt_id; END IF;

    PERFORM public.check_ticket_is_mutable(opt.ticket);
    PERFORM public.check_batch_ticket_print_immutable_internal(ARRAY[opt.ticket]);
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

    -- 5. Calculate the final price delta
    price_delta := new_price - original_price;
    new_order_price := COALESCE(ord.price, 0) + price_delta;

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
        IF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=ord.payment_info AND public.payment_method_is_online_internal(payment_method)) THEN
            RAISE EXCEPTION 'STRIPE_ORDER_PRICE_IMMUTABLE'; END IF;
        UPDATE eshop.payment_info SET amount = amount + price_delta WHERE id = ord.payment_info;
    END IF;

    -- Update the order itself
    UPDATE eshop.orders
    SET
        price = new_order_price,
        data = new_data,
        updated_at = now_time
    WHERE id = ord.id;

    -- Update the link table
    UPDATE eshop.order_product_ticket
    SET
        product = p_new_product_id
    WHERE id = p_opt_id;

    -- The aggregate swap reconciles each affected order once, after all seat
    -- pairs have their final products and totals, and appends one final snapshot.

END;
$$;


-- Only the aggregate applier calls this worker, after locking the complete
-- assignment graph and checking scope, holds and atomic-unit eligibility.
-- The pair helper updates purchased prices; the aggregate owns reconciliation.
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
 before_orders jsonb;sides jsonb;revisions jsonb;effects jsonb;facts jsonb;result jsonb;i integer;v_order_id bigint;
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
 before_orders:=public.order_payment_snapshot_internal(v_order_ids);
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
 -- Seat-only edits invalidate customer content too. Reconcile final totals once
 -- per order, so swaps within one order cannot create intermediate paid emails.
 FOR v_order_id IN SELECT id FROM eshop.orders WHERE id=ANY(v_order_ids) ORDER BY id LOOP
  PERFORM public.reconcile_order_payment_internal_v1(v_order_id,'product_edit');
  PERFORM public.refresh_order_payment_deadline_internal(v_order_id);
  INSERT INTO eshop.orders_history("order",data,state,price,currency_code)
  SELECT id,data,state,price,currency_code FROM eshop.orders WHERE id=v_order_id;
 END LOOP;
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

-- SOURCE: eshop_orders/get_order_change_summary_v1.sql
-- Internal read model shared by the editor preview and email preparation.
CREATE OR REPLACE FUNCTION public.get_order_change_summary_v1(p_order_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = public, extensions AS $$
DECLARE
 v_current jsonb; v_currency text; v_current_price numeric; v_reference eshop.orders_history; v_latest bigint;
 v_sent_at timestamptz; v_ref_tickets jsonb; v_cur_tickets jsonb;
 v_ref jsonb; v_cur jsonb; v_ticket jsonb; v_symbol text; v_state text;
 v_before jsonb; v_after jsonb; v_added jsonb; v_removed jsonb; v_changed jsonb;
 v_cancelled jsonb:='[]'; v_removed_tickets jsonb:='[]'; v_added_tickets jsonb:='[]';
 v_product_changes jsonb:='[]'; v_old_total numeric:=0; v_new_total numeric:=0;
 i integer; j integer; v_has_changes boolean;
BEGIN
 SELECT data,currency_code,price INTO v_current,v_currency,v_current_price FROM eshop.orders WHERE id=p_order_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'order_not_found'; END IF;
 SELECT id INTO v_latest FROM eshop.orders_history WHERE "order"=p_order_id
 ORDER BY created_at DESC,id DESC LIMIT 1;
 SELECT * INTO v_reference FROM eshop.orders_history WHERE "order"=p_order_id
 AND data->>'is_sent_to_customer'='true' ORDER BY created_at DESC,id DESC LIMIT 1;
 IF FOUND THEN v_sent_at:=v_reference.created_at;
 ELSE
  SELECT * INTO v_reference FROM eshop.orders_history WHERE "order"=p_order_id
  ORDER BY created_at ASC,id ASC LIMIT 1;
 END IF;
 v_ref_tickets:=coalesce(v_reference.data->'tickets','[]');
 v_cur_tickets:=coalesce(v_current->'tickets','[]');
 SELECT coalesce(sum(coalesce((p->>'price')::numeric,0)),0) INTO v_old_total
 FROM jsonb_array_elements(v_ref_tickets) t,jsonb_array_elements(coalesce(t->'products','[]')) p;
 SELECT coalesce(sum(coalesce((p->>'price')::numeric,0)),0) INTO v_new_total
 FROM jsonb_array_elements(v_cur_tickets) t,jsonb_array_elements(coalesce(t->'products','[]')) p;
 v_old_total:=coalesce(v_reference.price,v_old_total);
 v_new_total:=coalesce(v_current_price,v_new_total);
 -- Without history there is no evidence from which to invent a change.
 IF v_reference.id IS NOT NULL THEN
  FOR v_ref IN SELECT value FROM jsonb_array_elements(v_ref_tickets) LOOP
   SELECT value INTO v_cur FROM jsonb_array_elements(v_cur_tickets)
   WHERE (v_ref->>'id' IS NOT NULL AND value->>'id'=v_ref->>'id')
      OR (v_ref->>'id' IS NULL AND value=v_ref) LIMIT 1;
   v_symbol:=NULL; v_state:=NULL;
   -- Order membership prevents historical/foreign IDs leaking ticket metadata.
   SELECT t.ticket_symbol,t.state INTO v_symbol,v_state FROM eshop.tickets t
   WHERE t.id::text=v_ref->>'id' AND EXISTS(SELECT 1 FROM eshop.order_product_ticket opt
      WHERE opt.ticket=t.id AND opt."order"=p_order_id);
   v_ticket:=jsonb_build_object('id',v_ref->'id','ticket_symbol',
     coalesce(nullif(v_ref->>'ticket_symbol',''),v_symbol),'products',coalesce(v_ref->'products','[]'));
   IF v_cur IS NULL THEN
    IF v_state='storno' THEN v_cancelled:=v_cancelled||jsonb_build_array(v_ticket);
    ELSE v_removed_tickets:=v_removed_tickets||jsonb_build_array(v_ticket); END IF;
    CONTINUE;
   END IF;
   v_before:=coalesce(v_ref->'products','[]'); v_after:=coalesce(v_cur->'products','[]');
   v_added:='[]'; v_removed:='[]'; v_changed:='[]';
   -- Preserve duplicate instances; never pair products across different tickets.
   IF jsonb_array_length(v_after)>0 THEN
    FOR i IN REVERSE jsonb_array_length(v_after)-1..0 LOOP
     SELECT ordinality::integer-1 INTO j FROM jsonb_array_elements(v_before) WITH ORDINALITY
     WHERE value->>'id' IS NOT DISTINCT FROM v_after->i->>'id'
       AND value->>'title' IS NOT DISTINCT FROM v_after->i->>'title'
       AND value->>'currency_code' IS NOT DISTINCT FROM v_after->i->>'currency_code'
       AND value->>'spot_title' IS NOT DISTINCT FROM v_after->i->>'spot_title'
       AND value->>'spot_group_title' IS NOT DISTINCT FROM v_after->i->>'spot_group_title'
       AND abs(coalesce((value->>'price')::numeric,0)-coalesce((v_after->i->>'price')::numeric,0))<0.001
     ORDER BY ordinality LIMIT 1;
     IF j IS NOT NULL THEN v_before:=v_before-j; v_after:=v_after-i; END IF;
    END LOOP;
   END IF;
   IF jsonb_array_length(v_after)>0 THEN
    FOR i IN REVERSE jsonb_array_length(v_after)-1..0 LOOP
     SELECT ordinality::integer-1 INTO j FROM jsonb_array_elements(v_before) WITH ORDINALITY
     WHERE value->>'id' IS NOT DISTINCT FROM v_after->i->>'id' ORDER BY ordinality LIMIT 1;
     IF j IS NOT NULL THEN
      v_changed:=v_changed||jsonb_build_array(jsonb_build_object('from',v_before->j,'to',v_after->i));
      v_before:=v_before-j; v_after:=v_after-i;
     END IF;
    END LOOP;
   END IF;
   v_added:=v_after; v_removed:=v_before;
   IF jsonb_array_length(v_added)+jsonb_array_length(v_removed)+jsonb_array_length(v_changed)>0 THEN
    v_product_changes:=v_product_changes||jsonb_build_array(v_ticket||jsonb_build_object(
     'added',v_added,'removed',v_removed,'changed',v_changed));
   END IF;
  END LOOP;
  FOR v_cur IN SELECT value FROM jsonb_array_elements(v_cur_tickets) LOOP
   IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_ref_tickets) r
     WHERE (v_cur->>'id' IS NOT NULL AND r->>'id'=v_cur->>'id') OR (v_cur->>'id' IS NULL AND r=v_cur)) THEN
    v_added_tickets:=v_added_tickets||jsonb_build_array(v_cur);
   END IF;
  END LOOP;
 END IF;
 v_has_changes:=v_reference.id IS NOT NULL AND (jsonb_array_length(v_cancelled)+jsonb_array_length(v_removed_tickets)
   +jsonb_array_length(v_added_tickets)+jsonb_array_length(v_product_changes)>0 OR v_old_total<>v_new_total);
 RETURN jsonb_build_object('version',1,'cancelledTickets',v_cancelled,'removedTickets',v_removed_tickets,
   'addedTickets',v_added_tickets,'productChanges',v_product_changes,'referenceTotal',v_old_total,
   'currentTotal',v_new_total,'currencyCode',coalesce(v_currency,'CZK'),'hasChanges',v_has_changes,'referenceOrder',to_jsonb(v_reference),
   'referenceHistoryId',v_reference.id,'latestHistoryId',v_latest,'latestSentAt',v_sent_at);
END $$;
REVOKE ALL ON FUNCTION public.get_order_change_summary_v1(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_order_change_summary_v1(bigint) TO service_role;
