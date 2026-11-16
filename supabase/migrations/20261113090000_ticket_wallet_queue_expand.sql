-- Wallet queue forward. Apply only through the documented pause/drain cutover.

-- Transitional owner, installed only during the paused cutover window.
-- Registration precedes external I/O. No FK cascade may erase a remote identity.
CREATE OR REPLACE FUNCTION public.claim_ticket_wallet(p_ticket bigint DEFAULT NULL,p_object text DEFAULT NULL,p_class text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE w eshop.ticket_wallet_objects; c eshop.ticket_wallet_capabilities; i eshop.ticket_wallet_integrations; lease_id uuid:=extensions.gen_random_uuid();
BEGIN
 PERFORM public.require_service_role();
 IF p_ticket IS NOT NULL THEN PERFORM public.refresh_ticket_wallet_term_internal(p_ticket); END IF;
 IF p_ticket IS NOT NULL AND p_object IS NOT NULL THEN
  SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE ticket_id=p_ticket AND revoked_at IS NULL AND expires_at>now();
  SELECT * INTO i FROM eshop.ticket_wallet_integrations WHERE organization=c.organization;
  IF c.ticket_id IS NULL OR i.organization IS NULL OR i.paused OR p_object NOT LIKE i.issuer||'.%' OR p_class NOT LIKE i.issuer||'.%' THEN RETURN NULL; END IF;
  INSERT INTO eshop.ticket_wallet_objects(ticket_id,organization,occasion,issuer,environment,object_id,class_id)
  VALUES(c.ticket_id,c.organization,c.occasion,i.issuer,i.environment,p_object,p_class) ON CONFLICT(ticket_id) DO NOTHING;
 END IF;
 SELECT * INTO w FROM eshop.ticket_wallet_objects
 WHERE (p_ticket IS NULL OR ticket_id=p_ticket) AND (p_ticket IS NOT NULL OR next_attempt<=now())
 AND NOT EXISTS(SELECT 1 FROM eshop.ticket_wallet_integrations i WHERE i.organization=ticket_wallet_objects.organization AND i.paused)
 AND (lease_until IS NULL OR lease_until<=now()) ORDER BY next_attempt,ticket_id LIMIT 1 FOR UPDATE SKIP LOCKED;
 IF w.ticket_id IS NULL THEN RETURN NULL; END IF;
 PERFORM pg_advisory_xact_lock_shared(hashtextextended('wallet-claim:'||w.organization,0));
 IF NOT EXISTS(SELECT 1 FROM eshop.ticket_wallet_integrations WHERE organization=w.organization AND NOT paused) THEN RETURN NULL; END IF;
 PERFORM public.refresh_ticket_wallet_term_internal(w.ticket_id);
 UPDATE eshop.ticket_wallet_objects SET lease=lease_id,lease_until=clock_timestamp()+interval '45 seconds',next_attempt=now()+interval '1 minute' WHERE ticket_id=w.ticket_id;
 RETURN jsonb_build_object('ticketId',w.ticket_id,'organization',w.organization,'occasion',w.occasion,'issuer',w.issuer,'environment',w.environment,
 'objectId',w.object_id,'classId',w.class_id,'lease',lease_id,'projection',public.ticket_wallet_projection_internal(w.ticket_id));
END $$;



-- SOURCE: ticket_wallet/work_schema.sql
-- Scheduling belongs here; provider identity remains in ticket_wallet_objects.
ALTER TABLE eshop.ticket_wallet_integrations ADD COLUMN IF NOT EXISTS paused boolean NOT NULL DEFAULT false;
CREATE TABLE IF NOT EXISTS eshop.ticket_wallet_work (
 provider text NOT NULL DEFAULT 'google' CHECK(provider='google'),
 kind text NOT NULL CHECK(kind IN ('object','class','occasion','organization')),
 resource text NOT NULL,
 organization bigint NOT NULL,
 occasion bigint,
 ticket_id bigint,
 requested bigint NOT NULL DEFAULT 1 CHECK(requested>0),
 captured bigint NOT NULL DEFAULT 0,
 applied bigint NOT NULL DEFAULT 0,
 lease uuid,
 lease_until timestamptz,
 due_at timestamptz NOT NULL DEFAULT now(),
 dirty_since timestamptz NOT NULL DEFAULT now(),
 failures integer NOT NULL DEFAULT 0,
 last_error text,
 last_success timestamptz,
 claimed_at timestamptz NOT NULL DEFAULT '-infinity',
 cursor_ticket bigint NOT NULL DEFAULT 0,
 cursor_version bigint NOT NULL DEFAULT 0,
 repair_at timestamptz NOT NULL DEFAULT now()+interval '1 day',
 boundary_at timestamptz,
 PRIMARY KEY(provider,kind,resource),
 CHECK(applied<=captured AND captured<=requested),
 CHECK((lease IS NULL)=(lease_until IS NULL))
);
CREATE INDEX IF NOT EXISTS ticket_wallet_work_due ON eshop.ticket_wallet_work(due_at,dirty_since,resource) WHERE requested>applied;
CREATE INDEX IF NOT EXISTS ticket_wallet_work_repair ON eshop.ticket_wallet_work(repair_at) WHERE kind='object';
CREATE INDEX IF NOT EXISTS ticket_wallet_work_boundary ON eshop.ticket_wallet_work(boundary_at) WHERE boundary_at IS NOT NULL;
ALTER TABLE eshop.ticket_wallet_work ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.ticket_wallet_work FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: ticket_wallet/enqueue.sql
-- Private invokers inherit only the existing authorized domain definer.
CREATE OR REPLACE FUNCTION public.enqueue_ticket_wallet_internal(p_tickets bigint[])
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE w eshop.ticket_wallet_objects;
BEGIN
 FOR w IN SELECT * FROM eshop.ticket_wallet_objects WHERE ticket_id=ANY(p_tickets) ORDER BY ticket_id LOOP
  INSERT INTO eshop.ticket_wallet_work(kind,resource,organization,occasion,ticket_id)
  VALUES('object',w.object_id,w.organization,w.occasion,w.ticket_id)
  ON CONFLICT(provider,kind,resource) DO UPDATE SET requested=ticket_wallet_work.requested+1,
   due_at=least(ticket_wallet_work.due_at,now()),
   dirty_since=CASE WHEN ticket_wallet_work.requested=ticket_wallet_work.applied THEN now() ELSE ticket_wallet_work.dirty_since END;
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.enqueue_order_wallet_internal(p_order bigint)
RETURNS void LANGUAGE sql SET search_path=public,extensions AS $$
 SELECT public.enqueue_ticket_wallet_internal(ARRAY(SELECT DISTINCT ticket FROM eshop.order_product_ticket WHERE "order"=p_order ORDER BY ticket));
$$;
CREATE OR REPLACE FUNCTION public.enqueue_wallet_scope_internal(p_occasion bigint DEFAULT NULL,p_organization bigint DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE org bigint; scope_kind text; scope_id bigint;
BEGIN
 IF p_occasion IS NOT NULL THEN
  SELECT organization INTO org FROM public.occasions WHERE id=p_occasion;
  scope_kind:='occasion';scope_id:=p_occasion;
 ELSE org:=p_organization;scope_kind:='organization';scope_id:=p_organization; END IF;
 IF org IS NULL OR NOT EXISTS(SELECT 1 FROM eshop.ticket_wallet_integrations WHERE organization=org) THEN RETURN; END IF;
 INSERT INTO eshop.ticket_wallet_work(kind,resource,organization,occasion)
 VALUES(scope_kind,scope_id::text,org,p_occasion)
 ON CONFLICT(provider,kind,resource) DO UPDATE SET requested=ticket_wallet_work.requested+1,
 due_at=least(ticket_wallet_work.due_at,now()),
 dirty_since=CASE WHEN ticket_wallet_work.requested=ticket_wallet_work.applied THEN now() ELSE ticket_wallet_work.dirty_since END;
END $$;
CREATE OR REPLACE FUNCTION public.enqueue_wallet_class_internal(p_ticket bigint)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE w eshop.ticket_wallet_objects;
BEGIN
 SELECT * INTO w FROM eshop.ticket_wallet_objects WHERE ticket_id=p_ticket;
 IF NOT FOUND THEN RETURN; END IF;
 INSERT INTO eshop.ticket_wallet_work(kind,resource,organization,occasion,ticket_id)
 VALUES('class',w.class_id,w.organization,w.occasion,w.ticket_id)
 ON CONFLICT(provider,kind,resource) DO UPDATE SET requested=ticket_wallet_work.requested+1,
 due_at=least(ticket_wallet_work.due_at,now()),
 dirty_since=CASE WHEN ticket_wallet_work.requested=ticket_wallet_work.applied THEN now() ELSE ticket_wallet_work.dirty_since END;
END $$;
REVOKE ALL ON FUNCTION public.enqueue_ticket_wallet_internal(bigint[]),public.enqueue_order_wallet_internal(bigint),public.enqueue_wallet_scope_internal(bigint,bigint),public.enqueue_wallet_class_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: ticket_wallet/control.sql
-- Installed during expansion so the old and new claim owner share one fence.
CREATE OR REPLACE FUNCTION public.pause_ticket_wallet(p_organization bigint,p_paused boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 PERFORM pg_advisory_xact_lock(hashtextextended('wallet-claim:'||p_organization,0));
 UPDATE eshop.ticket_wallet_integrations SET paused=p_paused WHERE organization=p_organization;
 IF NOT FOUND THEN RAISE EXCEPTION 'wallet_integration_missing'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.pause_ticket_wallet(bigint,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.pause_ticket_wallet(bigint,boolean) TO service_role;

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
 PERFORM public.enqueue_ticket_wallet_internal(ARRAY(SELECT ticket FROM eshop.order_product_ticket WHERE id IN(first_spot.order_product_ticket,second_spot.order_product_ticket) ORDER BY ticket));
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

-- SOURCE: eshop_orders/update_ticket_products_ws.sql
CREATE OR REPLACE FUNCTION public.update_ticket_products_wsv2(
  p_ticket_id    bigint,
  p_products     jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions AS
$$
DECLARE
  v_order_id         bigint;
  v_occasion_id      bigint;
  v_payment_info_id  bigint;
  v_currency_code    char(3);
  v_state            text;
  v_old_data         jsonb;
  v_new_data         jsonb;
  v_sum_old          numeric := 0;
  v_sum_new          numeric := 0;
  v_diff             numeric;
  v_products_json    jsonb;
  v_old_products     jsonb;
  v_old_ids          bigint[];
  v_new_ids          bigint[];
  v_price            numeric;
  v_reconciliation   jsonb;
  v_occasion_features jsonb;
  v_form_settings     jsonb;
  v_current_products_for_compare jsonb;
BEGIN
  PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT "order" FROM eshop.order_product_ticket WHERE ticket=p_ticket_id));
  /* 0) Lookup & permission */
  SELECT opt."order", o.occasion, o.payment_info, o.currency_code, o.data, o.state, occ.features
    INTO v_order_id, v_occasion_id, v_payment_info_id, v_currency_code, v_old_data, v_state, v_occasion_features
  FROM eshop.order_product_ticket AS opt
  JOIN eshop.orders              AS o   ON o.id = opt."order"
  JOIN public.occasions          AS occ ON occ.id = o.occasion
  WHERE opt.ticket = p_ticket_id
  LIMIT 1 FOR UPDATE OF o;

  IF NOT FOUND THEN
    RAISE EXCEPTION '%', jsonb_build_object('code', 404, 'message', 'Ticket not linked to any order')::text;
  END IF;

  IF NOT public.can_write_orders(v_occasion_id) THEN
    RAISE EXCEPTION '%', jsonb_build_object('code', 403, 'message', 'Not authorized')::text;
  END IF;

  PERFORM public.check_ticket_is_mutable(p_ticket_id);
  PERFORM public.check_batch_ticket_print_immutable_internal(ARRAY[p_ticket_id]);
  IF EXISTS(SELECT 1 FROM eshop.payment_info WHERE id=v_payment_info_id AND public.payment_method_is_online_internal(payment_method)) THEN
    RAISE EXCEPTION 'STRIPE_ORDER_PRICE_IMMUTABLE'; END IF;

  /* Check for negative prices in the input */
  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_products) AS p
    WHERE (p.value->>'price')::numeric < 0
  ) THEN
    RAISE EXCEPTION '%', jsonb_build_object('code', 400, 'message', 'Product prices cannot be negative.')::text;
  END IF;

  PERFORM public.lock_ticket_order_products_internal(v_order_id,jsonb_build_object('ticket',jsonb_build_array(jsonb_build_object('fields',
    (SELECT coalesce(jsonb_agg(jsonb_build_object('product_type',x->'id')),'[]') FROM jsonb_array_elements(p_products) x)))));
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_products) x JOIN eshop.products p ON p.id=(x->>'id')::bigint
    WHERE p.maximum>0 AND (SELECT count(*) FROM eshop.order_product_ticket WHERE product=p.id)+
      CASE WHEN EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE ticket=p_ticket_id AND product=p.id) THEN 0 ELSE 1 END>p.maximum) THEN
    RAISE EXCEPTION 'PRODUCT_CAPACITY_EXCEEDED'; END IF;
  /* get old products for the ticket */
  SELECT jsonb_path_query_first(v_old_data, '$.tickets[*] ? (@.id == $tid).products', jsonb_build_object('tid', p_ticket_id))
  INTO v_old_products;
  v_old_products := COALESCE(v_old_products, '[]'::jsonb);

  /* compute old/new ID arrays and check for changes */
  SELECT array_agg((p->>'id')::bigint) INTO v_old_ids FROM jsonb_array_elements(v_old_products) p;
  SELECT array_agg((p->>'id')::bigint) INTO v_new_ids FROM jsonb_array_elements(p_products) p;

  -- Create a comparable representation of products (id and price)
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', p->'id', 'price', p->'price') ORDER BY (p->>'id')::int), '[]'::jsonb)
  INTO v_current_products_for_compare
  FROM jsonb_array_elements(v_old_products) p;

  -- If product sets (ID and price) are identical, bail early.
  IF v_current_products_for_compare = (
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id', p->'id', 'price', p->'price') ORDER BY (p->>'id')::int), '[]'::jsonb)
    FROM jsonb_array_elements(p_products) p
  ) THEN
    RETURN jsonb_build_object('code',200,'data',v_old_data, 'message', 'No changes detected.');
  END IF;

  /* 1) old subtotal */
  SELECT COALESCE(SUM((p->>'price')::numeric), 0)
  INTO v_sum_old
  FROM jsonb_array_elements(v_old_products) AS p;

  /* 2) new products JSON + subtotal (FIXED HERE) */
  -- We now find the matching old product and merge it (||) with the new data.
  -- This preserves 'spot_title', 'spot_id' or any other extra fields.
  SELECT
    jsonb_agg(
      -- Start with the old product object if it exists (for this ID)
      COALESCE(
        (
           SELECT old_p
           FROM jsonb_array_elements(v_old_products) AS old_p
           WHERE (old_p->>'id')::bigint = p_info.id
           LIMIT 1
        ),
        '{}'::jsonb
      )
      ||
      -- Overwrite with refreshed/new standard fields
      jsonb_build_object(
        'id',            p_info.id,
        'type',          pt.type,
        'price',         (p_new.data->>'price')::numeric, -- Use price from input
        'title',         p_info.title,
        'type_title',    pt.title,
        'currency_code', p_info.currency_code
      )
    ),
    COALESCE(SUM((p_new.data->>'price')::numeric), 0)
  INTO v_products_json, v_sum_new
  FROM jsonb_array_elements(p_products) AS p_new(data)
  JOIN eshop.products           AS p_info ON p_info.id = (p_new.data->>'id')::bigint
  LEFT JOIN eshop.product_types AS pt     ON pt.id = p_info.product_type
  WHERE p_info.occasion = v_occasion_id;

  v_products_json := COALESCE(v_products_json, '[]'::jsonb);

  /* 3) rewrite just that ticket’s products array in orders.data */
  SELECT jsonb_set(
    v_old_data,
    '{tickets}',
    (
      SELECT jsonb_agg(
        CASE WHEN (tckt->>'id')::bigint = p_ticket_id
             THEN jsonb_set(tckt, '{products}', v_products_json)
             ELSE tckt
        END
      )
      FROM jsonb_array_elements(v_old_data->'tickets') AS tckt
    )
  ) INTO v_new_data;

  UPDATE eshop.orders
     SET data = v_new_data
   WHERE id = v_order_id;

  /* Update the ticket timestamp */
  UPDATE eshop.tickets
     SET updated_at = now()
   WHERE id = p_ticket_id;

  /* 4) granularly update the link‐table rows */
  v_old_ids := COALESCE(v_old_ids, ARRAY[]::bigint[]);
  v_new_ids := COALESCE(v_new_ids, ARRAY[]::bigint[]);

  -- Before deleting order_product_ticket rows, nullify the reference in eshop.spots
  UPDATE eshop.spots s
     SET order_product_ticket = NULL
  WHERE s.order_product_ticket IN (
      SELECT opt.id
      FROM eshop.order_product_ticket opt
      WHERE opt.ticket = p_ticket_id
        AND opt.product IN (SELECT unnest FROM unnest(v_old_ids) EXCEPT SELECT unnest FROM unnest(v_new_ids))
  );

  -- Delete link-table rows for products that were removed.
  DELETE FROM eshop.order_product_ticket
  WHERE ticket = p_ticket_id
    AND product IN (SELECT unnest FROM unnest(v_old_ids) EXCEPT SELECT unnest FROM unnest(v_new_ids));

  -- Insert new link-table rows for products that were added.
  INSERT INTO eshop.order_product_ticket ("order", ticket, product)
  SELECT v_order_id, p_ticket_id, new_pid
    FROM (SELECT unnest FROM unnest(v_new_ids) EXCEPT SELECT unnest FROM unnest(v_old_ids)) AS t(new_pid)
  ON CONFLICT DO NOTHING;

  /* 5) adjust payment_info.amount and order.price by the delta */
  v_diff := v_sum_new - v_sum_old;
  IF v_diff <> 0 THEN
      UPDATE eshop.payment_info
         SET amount = amount + v_diff
       WHERE id = v_payment_info_id;
      UPDATE eshop.orders
         SET price      = COALESCE(price,0) + v_diff,
             updated_at = now()
       WHERE id = v_order_id;
  END IF;

  /* 5a) the shared owner decides eligibility and owns one invalidation. */
  v_reconciliation := public.reconcile_order_payment_internal_v1(v_order_id,'product_edit');
  SELECT price INTO v_price FROM eshop.orders WHERE id=v_order_id;

  PERFORM public.refresh_order_payment_deadline_internal(v_order_id);

  PERFORM public.apply_allocations(v_order_id);

  /* 6) append history */
  INSERT INTO eshop.orders_history("order", data, state, price, currency_code)
  VALUES (
    v_order_id,
    v_new_data,
    v_reconciliation->>'final_state',
    (SELECT price FROM eshop.orders WHERE id = v_order_id),
    v_currency_code
  );

  PERFORM public.enqueue_ticket_wallet_internal(ARRAY[p_ticket_id]);
  RETURN jsonb_build_object('code',200,'data',v_new_data);
END;
$$;

-- The receipted Client Sync command must use the same payment and email
-- transition as the legacy RPC, rather than its pre-email-cutover copy.
CREATE OR REPLACE FUNCTION public.update_ticket_products_internal_v1(
  p_ticket_id bigint, p_products jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, extensions AS $$
BEGIN
  RETURN public.update_ticket_products_wsv2(p_ticket_id, p_products);
END;
$$;
REVOKE ALL ON FUNCTION public.update_ticket_products_internal_v1(bigint,jsonb)
  FROM PUBLIC, anon, authenticated;

-- SOURCE: blueprint/save.sql
CREATE OR REPLACE FUNCTION public.save_blueprint_layout_impl_internal(p_blueprint jsonb,p_reviewed_demo boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE b eshop.blueprints; c jsonb; binding eshop.blueprint_seat_bindings; s eshop.spots;
 node uuid; group_id uuid; unit_id uuid; product_id bigint; spot_id bigint; blocked_value boolean; assignment_mode text;
 pool public.inventory_pools; capacity_int bigint; physical_supply bigint;
 node_index jsonb; unit_index jsonb; seat_count bigint; text_ids text[]:='{}';
 doc jsonb:=p_blueprint->'layout'; result jsonb; expected bigint; issue text; all_seats uuid[]; supplied uuid[];
BEGIN
 IF nullif(p_blueprint->>'id','') IS NULL THEN
  IF public.can_write_blueprints((p_blueprint->>'occasion')::bigint) IS NOT TRUE THEN
   RAISE insufficient_privilege USING MESSAGE='blueprint editor required'; END IF;
  INSERT INTO eshop.blueprints(occasion,organization,title) SELECT id,organization,p_blueprint->>'title' FROM public.occasions WHERE id=(p_blueprint->>'occasion')::bigint RETURNING * INTO b;
 ELSE
  SELECT * INTO b FROM eshop.blueprints WHERE id=(p_blueprint->>'id')::bigint;
  PERFORM 1 FROM eshop.products WHERE occasion=b.occasion ORDER BY id FOR UPDATE;
  SELECT * INTO b FROM eshop.blueprints WHERE id=(p_blueprint->>'id')::bigint FOR UPDATE;
 END IF;
 IF b.id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_NOT_FOUND'; END IF;
 IF p_reviewed_demo AND public.is_demo_occasion(b.occasion) THEN
  IF NOT public.can_migrate_reviewed_legacy_blueprint(b.occasion) THEN RAISE insufficient_privilege USING MESSAGE='blueprint migration reviewer required'; END IF;
 ELSE
 IF public.can_write_blueprints(b.occasion) IS NOT TRUE THEN RAISE insufficient_privilege USING MESSAGE='blueprint editor required'; END IF;
 END IF;
 IF p_reviewed_demo AND public.is_demo_occasion(b.occasion) THEN
  IF b.layout IS NOT NULL THEN RAISE check_violation USING MESSAGE='BLUEPRINT_MIGRATION_INITIAL_LAYOUT_REQUIRED'; END IF;
 ELSE PERFORM public.check_occasion_writable(b.occasion); END IF;
 expected:=(p_blueprint->>'expected_layout_revision')::bigint;
 IF expected IS NULL OR expected<>b.layout_revision THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_REVISION_CONFLICT'; END IF;
 PERFORM public.validate_blueprint_layout_internal(doc);
  PERFORM public.check_blueprint_text_resources_internal(doc,b.occasion);
  text_ids:=public.blueprint_text_resource_ids_internal(doc,b.occasion);
  IF jsonb_typeof(p_blueprint->'textResourceIds') IS DISTINCT FROM 'array'
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_blueprint->'textResourceIds') id WHERE jsonb_typeof(id)<>'string')
    OR (SELECT coalesce(array_agg(id ORDER BY id),'{}'::text[]) FROM jsonb_array_elements_text(p_blueprint->'textResourceIds') id) IS DISTINCT FROM text_ids
    THEN RAISE check_violation USING MESSAGE='BLUEPRINT_TEXT_RESOURCE_REFS_MISMATCH'; END IF;

 PERFORM public.check_blueprint_image_resource_internal(doc,b.occasion);
 PERFORM public.check_blueprint_bitmap_resources_internal(doc,b.occasion);
 SELECT coalesce(jsonb_object_agg(x->>'id',x),'{}'),count(*) FILTER(WHERE x->>'kind'='seat') INTO node_index,seat_count FROM jsonb_array_elements(doc->'nodes') x;
 -- Membership is projected from the document, never trusted from an overlay.
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(doc->'selectionUnits','[]')) u WHERE
   (u->>'id')::uuid IS NULL OR jsonb_array_length(u->'nodeIds')=0 OR coalesce(u->>'kind','atomic')<>'atomic')
  OR EXISTS(SELECT member FROM jsonb_array_elements(coalesce(doc->'selectionUnits','[]')) u
   CROSS JOIN LATERAL jsonb_array_elements_text(u->'nodeIds') member GROUP BY member HAVING count(*)>1)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(coalesce(doc->'selectionUnits','[]')) u
   CROSS JOIN LATERAL jsonb_array_elements_text(u->'nodeIds') member
   WHERE coalesce(node_index->member->>'kind','')<>'seat') THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_SELECTION_UNITS'; END IF;
 SELECT coalesce(jsonb_object_agg(member,u->>'id'),'{}') INTO unit_index
 FROM jsonb_array_elements(coalesce(doc->'selectionUnits','[]')) u CROSS JOIN LATERAL jsonb_array_elements_text(u->'nodeIds') member;
 PERFORM public.lock_blueprint_inventory_internal(b.occasion,b.id);
 PERFORM public.check_batch_blueprint_print_immutable_internal(b.id,doc);
 PERFORM public.check_blueprint_block_changes_internal(b.id,doc,p_blueprint->'seatChanges');
 IF EXISTS(SELECT change->>'nodeId' FROM jsonb_array_elements(coalesce(p_blueprint->'seatChanges','[]')) change GROUP BY change->>'nodeId' HAVING count(*)>1) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_DUPLICATE_SEAT_CHANGE'; END IF;
 FOR c IN SELECT * FROM jsonb_array_elements(coalesce(p_blueprint->'seatChanges','[]')) LOOP
  node:=(c->>'nodeId')::uuid;
  SELECT * INTO binding FROM eshop.blueprint_seat_bindings WHERE blueprint=b.id AND node_id=node;
  IF c->>'operation'='delete' THEN
   IF binding.node_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_BINDING_NOT_FOUND',DETAIL=c::text; END IF;
   SELECT * INTO s FROM eshop.spots WHERE id=binding.spot;
   IF s.order_product_ticket IS NOT NULL OR (s.secret IS NOT NULL AND s.secret_expiration_time>clock_timestamp()) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_SEAT_PROTECTED',DETAIL=c::text; END IF;
   DELETE FROM eshop.blueprint_seat_bindings WHERE blueprint=b.id AND node_id=node;
   DELETE FROM eshop.spots WHERE id=s.id;
   CONTINUE;
  END IF;
  IF c->>'operation' IS DISTINCT FROM 'upsert' OR coalesce(node_index->node::text->>'kind','')<>'seat' THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_SEAT_CHANGE',DETAIL=c::text; END IF;
  IF NOT c ? 'productId' OR NOT c ? 'blocked' OR NOT c ? 'groupNodeId' OR NOT c ? 'selectionUnitId' THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INCOMPLETE_SEAT_CHANGE',DETAIL=c::text; END IF;
  assignment_mode:=coalesce(c->>'productAssignmentMode','override');
  IF assignment_mode NOT IN ('inherit','override') OR NOT c ? 'productAssignmentMode' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INVALID_PRODUCT_ASSIGNMENT_MODE'; END IF;
  product_id:=(c->>'productId')::bigint; group_id:=(c->>'groupNodeId')::uuid; unit_id:=(c->>'selectionUnitId')::uuid; blocked_value:=(c->>'blocked')::boolean;
  IF blocked_value IS NULL OR (product_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.products WHERE id=product_id AND occasion=b.occasion)) THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_PRODUCT',DETAIL=c::text; END IF;
  IF group_id IS NOT NULL AND coalesce(node_index->group_id::text->>'kind','') NOT IN ('group','table','furniture') THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_GROUP',DETAIL=c::text; END IF;
  IF unit_id IS DISTINCT FROM (unit_index->>node::text)::uuid THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_UNIT_MEMBERSHIP_MISMATCH',DETAIL=c::text; END IF;
  spot_id:=(c->>'spotId')::bigint;
  IF binding.node_id IS NOT NULL AND spot_id IS DISTINCT FROM binding.spot THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_SPOT_IDENTITY_CHANGED',DETAIL=c::text; END IF;
  IF spot_id IS NOT NULL THEN
   SELECT * INTO s FROM eshop.spots WHERE id=spot_id AND blueprint=b.id AND occasion=b.occasion;
   IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_SPOT_SCOPE_MISMATCH',DETAIL=c::text; END IF;
   IF (s.order_product_ticket IS NOT NULL OR (s.secret IS NOT NULL AND s.secret_expiration_time>clock_timestamp()))
    AND (s.product IS DISTINCT FROM product_id OR s.title IS DISTINCT FROM c->>'title'
     OR coalesce(binding.blocked,false) IS DISTINCT FROM blocked_value OR binding.selection_unit IS DISTINCT FROM unit_id OR binding.group_node IS DISTINCT FROM group_id OR binding.product_assignment_mode IS DISTINCT FROM assignment_mode) THEN
    RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_SEAT_PROTECTED',DETAIL=c::text; END IF;
   UPDATE eshop.spots SET product=product_id,title=c->>'title',updated_at=now() WHERE id=spot_id
    AND (product IS DISTINCT FROM product_id OR title IS DISTINCT FROM c->>'title');
  ELSE
   INSERT INTO eshop.spots(blueprint,occasion,product,title) VALUES(b.id,b.occasion,product_id,c->>'title') RETURNING id INTO spot_id;
  END IF;
  INSERT INTO eshop.blueprint_seat_bindings(blueprint,node_id,spot,selection_unit,group_node,blocked,product_assignment_mode)
   VALUES(b.id,node,spot_id,unit_id,group_id,blocked_value,assignment_mode)
   ON CONFLICT(blueprint,node_id) DO UPDATE SET selection_unit=excluded.selection_unit,group_node=excluded.group_node,blocked=excluded.blocked,product_assignment_mode=excluded.product_assignment_mode;
 END LOOP;
 IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings sb WHERE sb.blueprint=b.id AND coalesce(node_index->sb.node_id::text->>'kind','')<>'seat')
  OR (SELECT count(*) FROM eshop.blueprint_seat_bindings sb WHERE sb.blueprint=b.id)<>seat_count
  OR EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings sb WHERE sb.blueprint=b.id AND sb.selection_unit IS DISTINCT FROM
   (unit_index->>sb.node_id::text)::uuid) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_BINDING_SET_MISMATCH'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings sb WHERE sb.blueprint=b.id AND sb.group_node IS NOT NULL AND coalesce(node_index->sb.group_node::text->>'kind','') NOT IN ('group','table','furniture')) THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_GROUP'; END IF;
 FOR c IN SELECT * FROM jsonb_array_elements(coalesce(p_blueprint->'groupProductChanges','[]')) LOOP
  IF NOT c ? 'productId' THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INCOMPLETE_GROUP_CHANGE',DETAIL=c::text; END IF;
  node:=(c->>'groupNodeId')::uuid; product_id:=(c->>'productId')::bigint;
  -- The client includes baseline group defaults as null tombstones after their
  -- nodes are removed. Only a default owned by this blueprint may be removed.
  IF product_id IS NULL AND NOT (node_index ? node::text)
   AND EXISTS(SELECT 1 FROM eshop.blueprint_group_products WHERE blueprint=b.id AND group_node=node) THEN
   DELETE FROM eshop.blueprint_group_products WHERE blueprint=b.id AND group_node=node;
   CONTINUE;
  END IF;
  IF coalesce(node_index->node::text->>'kind','') NOT IN ('table','group','furniture')
   OR (product_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.products WHERE id=product_id AND occasion=b.occasion)) THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_GROUP_PRODUCT',DETAIL=c::text; END IF;
  DELETE FROM eshop.blueprint_group_products WHERE blueprint=b.id AND group_node=node;
  IF product_id IS NOT NULL THEN INSERT INTO eshop.blueprint_group_products VALUES(b.id,node,product_id); END IF;
 END LOOP;
 DELETE FROM eshop.blueprint_group_products gp WHERE blueprint=b.id AND NOT node_index ? gp.group_node::text;
 IF EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings sb JOIN eshop.spots bound_spot ON bound_spot.id=sb.spot LEFT JOIN eshop.blueprint_group_products gp ON gp.blueprint=sb.blueprint AND gp.group_node=sb.group_node WHERE sb.blueprint=b.id AND sb.product_assignment_mode='inherit' AND (sb.group_node IS NULL OR gp.product IS NULL)) THEN RAISE check_violation USING MESSAGE='BLUEPRINT_INHERITED_PRODUCT_MISMATCH'; END IF;
 FOR c IN SELECT * FROM jsonb_array_elements(coalesce(p_blueprint->'areaBindingChanges','[]')) LOOP
  node:=(c->>'nodeId')::uuid; product_id:=(c->>'productId')::bigint;
  DELETE FROM eshop.blueprint_area_bindings WHERE blueprint=b.id AND node_id=node;
  IF c->>'operation'='delete' THEN CONTINUE; END IF;
  IF c->>'operation' IS DISTINCT FROM 'upsert' OR coalesce(node_index->node::text->>'kind','')<>'capacityArea'
   OR NOT EXISTS(SELECT 1 FROM eshop.product_inventory_contexts pic JOIN eshop.products p ON p.id=pic.product JOIN public.inventory_contexts ic ON ic.id=pic.inventory_context JOIN public.inventory_pools ip ON ip.id=ic.inventory_pool WHERE pic.product=product_id AND pic.inventory_context=(c->>'inventoryContextId')::bigint AND p.occasion=b.occasion AND ip.occasion=b.occasion) THEN
   RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_AREA_BINDING',DETAIL=c::text; END IF;
  IF c ? 'capacity' THEN
   capacity_int:=(c->>'capacity')::bigint;
   IF capacity_int IS NULL OR capacity_int<0 OR capacity_int>1000000 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_INVALID_CAPACITY'; END IF;
   SELECT ip.* INTO pool FROM public.inventory_pools ip JOIN public.inventory_contexts ic ON ic.inventory_pool=ip.id WHERE ic.id=(c->>'inventoryContextId')::bigint;
   PERFORM public.update_inventory_pool_bundle(jsonb_build_object('pool',jsonb_build_object(
    'id',pool.id,'occasion',pool.occasion,'title',pool.title,
    'description',pool.description,'type',pool.type,'data',pool.data,
    'sellable_capacity',capacity_int)));
   -- The standing count owns the complete setup: a higher count must also
   -- provide real supply. Preserve existing resources/allocations and add only
   -- the missing quantity through the canonical inventory resource command.
   SELECT coalesce(sum(r.capacity),0) INTO physical_supply
    FROM public.resources r WHERE r.inventory_pool=pool.id;
   IF physical_supply<capacity_int THEN
    PERFORM public.update_resource(jsonb_build_object('inventory_pool',pool.id,
     'title',coalesce(pool.title,b.title),'capacity',capacity_int-physical_supply));
   END IF;
  END IF;
  INSERT INTO eshop.blueprint_area_bindings VALUES(b.id,node,(c->>'inventoryContextId')::bigint,product_id);
 END LOOP;
 IF EXISTS(SELECT 1 FROM eshop.blueprint_area_bindings ab WHERE blueprint=b.id AND coalesce(node_index->ab.node_id::text->>'kind','')<>'capacityArea') THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_AREA_BINDING_SET_MISMATCH'; END IF;
 UPDATE eshop.blueprints SET layout=doc,layout_text_resource_ids=text_ids,layout_revision=layout_revision+1,updated_at=now(),title=coalesce(p_blueprint->>'title',title) WHERE id=b.id RETURNING * INTO b;
 result:=public.blueprint_binding_projection_internal(b.id)||jsonb_build_object('code',200,'blueprint_id',b.id,'layout_revision',b.layout_revision,
  'document_hash',encode(extensions.digest(convert_to(doc::text,'UTF8'),'sha256'),'hex'));
 IF octet_length(result::text)>4194304 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='BLUEPRINT_RESULT_TOO_LARGE'; END IF;
 PERFORM public.sync_form_blueprint_internal(id) FROM public.forms WHERE occasion=b.occasion ORDER BY id;
 PERFORM public.assert_form_seating_source_internal(id) FROM public.forms WHERE occasion=b.occasion;
 PERFORM public.notification_center_blueprint_capacity_internal(b.id);
 PERFORM public.enqueue_wallet_scope_internal(b.occasion);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.save_blueprint_layout_impl_internal(jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;

-- Runtime entry always enforces occasion writability, including demo read-only.
CREATE OR REPLACE FUNCTION public.save_blueprint_layout_internal_v1(p_blueprint jsonb)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT public.save_blueprint_layout_impl_internal(p_blueprint,false);
$$;
REVOKE ALL ON FUNCTION public.save_blueprint_layout_internal_v1(jsonb) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: scanning/admission.sql
-- Parents before ticket, shared by web and retained native/admin writers.
CREATE OR REPLACE FUNCTION public.scanner_lock_ticket_internal(p_ticket bigint)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
DECLARE parents bigint[]; current_parents bigint[]; parent bigint;
BEGIN
 SELECT array_agg(DISTINCT x."order" ORDER BY x."order") INTO parents FROM eshop.order_product_ticket x WHERE x.ticket=p_ticket;
 PERFORM public.lock_order_capacity_scope_internal(parents);
 FOREACH parent IN ARRAY coalesce(parents,ARRAY[]::bigint[]) LOOP
  PERFORM 1 FROM eshop.orders WHERE id=parent FOR UPDATE;
 END LOOP;
 PERFORM 1 FROM eshop.tickets WHERE id=p_ticket FOR UPDATE;
 SELECT array_agg(DISTINCT x."order" ORDER BY x."order") INTO current_parents FROM eshop.order_product_ticket x WHERE x.ticket=p_ticket;
 IF parents IS DISTINCT FROM current_parents THEN RAISE serialization_failure USING MESSAGE='ticket_parent_changed'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.scanner_admit_ticket_internal(p_ticket bigint)
RETURNS void LANGUAGE plpgsql SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.check_ticket_is_mutable(p_ticket);
 IF NOT public.provider_ticket_admission_allowed_internal(p_ticket) THEN RAISE EXCEPTION 'stripe_admission_hold'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.tickets WHERE id=p_ticket AND state='used') THEN RAISE EXCEPTION 'already_used'; END IF;
 UPDATE eshop.tickets SET state='used',updated_at=clock_timestamp() WHERE id=p_ticket;
 PERFORM public.enqueue_ticket_wallet_internal(ARRAY[p_ticket]);
END $$;
CREATE OR REPLACE FUNCTION public.scanner_lookup_ticket_internal(p_session uuid,p_token text,p_symbol text,p_ticket bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; cfg public.scanner_settings; tid bigint; result jsonb;
BEGIN
 s:=public.scanner_session_internal(p_session,p_token);
 IF NOT public.admit_scan_access_v1(s.occasion_id,true) THEN RETURN jsonb_build_object('code',429,'reason','abuse_limit_exceeded','server_time',now()); END IF;
 SELECT * INTO cfg FROM public.scanner_settings WHERE occasion_id=s.occasion_id;
 IF p_ticket IS NOT NULL AND NOT coalesce((cfg.config#>>'{manual_search,tickets}')::boolean,false) THEN
  RAISE insufficient_privilege USING MESSAGE='manual_search_disabled';
 END IF;
 IF p_ticket IS NOT NULL THEN
  SELECT t.id INTO tid FROM eshop.tickets t WHERE t.occasion=s.occasion_id AND t.id=p_ticket;
 ELSE
  SELECT t.id INTO tid FROM eshop.tickets t WHERE t.occasion=s.occasion_id AND t.ticket_symbol=p_symbol LIMIT 1;
 END IF;
 IF p_ticket IS NULL AND tid IS NULL AND p_symbol ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' THEN
  SELECT t.id INTO tid FROM public.occasion_users ou JOIN eshop.tickets t ON t.id=ou.ticket WHERE ou.occasion=s.occasion_id AND ou."user"=p_symbol::uuid AND t.occasion=s.occasion_id LIMIT 1;
 END IF;
 SELECT dto INTO result FROM public.scanner_ticket_projection_internal(s.occasion_id,cfg.config,tid) WHERE ticket_id=tid;
 IF result IS NOT NULL THEN result:=result||jsonb_build_object('can_reset_password',public.scanner_can_reset_password_internal(s.occasion_id,tid)); END IF;
 RETURN jsonb_build_object('code',CASE WHEN result IS NULL THEN 404 ELSE 200 END,'reason',CASE WHEN result IS NULL THEN 'not_found' ELSE 'found' END,
 'data',result,'settings_revision',cfg.revision,'server_time',now());
END $$;
REVOKE ALL ON FUNCTION public.scanner_lookup_ticket_internal(uuid,text,text,bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.lookup_scanner_ticket(p_session uuid,p_token text,p_symbol text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 RETURN public.scanner_lookup_ticket_internal(p_session,p_token,p_symbol,NULL);
END $$;
CREATE OR REPLACE FUNCTION public.lookup_scanner_ticket_by_id(p_session uuid,p_token text,p_ticket bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 RETURN public.scanner_lookup_ticket_internal(p_session,p_token,NULL,p_ticket);
END $$;
REVOKE ALL ON FUNCTION public.lookup_scanner_ticket_by_id(uuid,text,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lookup_scanner_ticket_by_id(uuid,text,bigint) TO anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.search_scanner_tickets(p_session uuid,p_token text,p_query text,p_after bigint DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; cfg public.scanner_settings; result jsonb;
BEGIN
 s:=public.scanner_session_internal(p_session,p_token); SELECT * INTO cfg FROM public.scanner_settings WHERE occasion_id=s.occasion_id;
 IF NOT coalesce((cfg.config#>>'{manual_search,tickets}')::boolean,false) THEN RAISE insufficient_privilege USING MESSAGE='manual_search_disabled'; END IF;
 IF length(p_query) NOT BETWEEN 2 AND 100 THEN RETURN jsonb_build_object('code',400,'reason','invalid_query','server_time',now()); END IF;
 IF NOT public.admit_scan_access_v1(s.occasion_id,true) THEN RETURN jsonb_build_object('code',429,'reason','abuse_limit_exceeded','server_time',now()); END IF;
 SELECT coalesce(jsonb_agg(dto ORDER BY ticket_id),'[]'::jsonb) INTO result FROM (
 SELECT * FROM public.scanner_ticket_projection_internal(s.occasion_id,cfg.config) WHERE ticket_id>p_after
 AND (strpos(lower(dto->>'holder_name'),lower(p_query))>0 OR strpos(lower(dto->>'purchaser_name'),lower(p_query))>0 OR strpos(lower(dto->>'purchaser_email'),lower(p_query))>0 OR strpos(lower(dto->>'batch_title'),lower(p_query))>0 OR strpos(lower(dto->>'symbol'),lower(p_query))>0) ORDER BY ticket_id LIMIT 30) found;
 RETURN jsonb_build_object('code',200,'data',result,'server_time',now());
END $$;
CREATE OR REPLACE FUNCTION public.sync_scanner_operations(p_session uuid,p_token text,p_operations jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; cfg public.scanner_settings; op jsonb; canonical jsonb; h text; prior public.scanner_operations;
 tid bigint; proj jsonb; receipt jsonb; outcome text; reason text; results jsonb:='[]'; existing boolean; snap public.scanner_snapshots;
BEGIN
 s:=public.scanner_session_internal(p_session,p_token);
 IF p_operations IS NULL OR jsonb_typeof(p_operations)<>'array' OR jsonb_array_length(p_operations) NOT BETWEEN 1 AND 50 OR octet_length(p_operations::text)>262144 THEN
  RETURN jsonb_build_object('code',400,'reason','invalid_batch','server_time',now()); END IF;
 SELECT * INTO cfg FROM public.scanner_settings WHERE occasion_id=s.occasion_id;
 IF NOT public.admit_scan_access_v1(s.occasion_id,true) THEN RETURN jsonb_build_object('code',429,'reason','abuse_limit_exceeded','retry_after_ms',30000,'server_time',now()); END IF;
 FOR op IN SELECT value FROM jsonb_array_elements(p_operations) LOOP
  IF op->>'action' IS DISTINCT FROM 'admit_ticket' OR op->>'origin_session_id' IS DISTINCT FROM p_session::text
   OR op->>'eligibility_fingerprint' IS NULL OR length(op->>'eligibility_fingerprint')<>64
   OR op->>'operation_id' IS NULL OR op->>'ticket_id' IS NULL THEN
   RAISE invalid_parameter_value USING MESSAGE='invalid_operation'; END IF;
  tid:=(op->>'ticket_id')::bigint;
  canonical:=jsonb_build_object('operation_id',(op->>'operation_id')::uuid,'origin_session_id',p_session,'occasion_id',s.occasion_id,
   'ticket_id',tid,'action','admit_ticket','snapshot_id',op->'snapshot_id','settings_revision',op->'settings_revision',
   'eligibility_fingerprint',op->'eligibility_fingerprint','confirm_unpaid',coalesce((op->>'confirm_unpaid')::boolean,false),'captured_at',op->'captured_at');
  h:=encode(digest(canonical::text,'sha256'),'hex');
  -- Serializes global identity before any domain mutation. No incomplete receipt survives a transaction.
  PERFORM pg_advisory_xact_lock(hashtextextended(op->>'operation_id',5317));
  SELECT * INTO prior FROM public.scanner_operations WHERE operation_id=(op->>'operation_id')::uuid;
  IF FOUND THEN
   IF prior.session_id<>p_session OR prior.payload_hash<>h THEN
    results:=results||jsonb_build_array(jsonb_build_object('operation_id',op->>'operation_id','outcome','rejected','reason','operation_payload_mismatch'));
   ELSE results:=results||jsonb_build_array(prior.receipt||jsonb_build_object('replayed',true)); END IF;
   CONTINUE;
  END IF;
  IF NOT public.admit_scan_access_v1(s.occasion_id,true) THEN
   RETURN jsonb_build_object('code',429,'reason','abuse_limit_exceeded','retry_after_ms',30000,'server_time',now());
  END IF;
  outcome:='rejected'; reason:='not_found'; proj:=NULL;
  IF EXISTS(SELECT 1 FROM eshop.tickets WHERE id=tid AND occasion=s.occasion_id) THEN
   PERFORM public.scanner_lock_ticket_internal(tid);
   PERFORM public.check_occasion_writable(s.occasion_id);
   SELECT dto INTO proj FROM public.scanner_ticket_projection_internal(s.occasion_id,cfg.config,tid);
   IF op->>'snapshot_id' IS NOT NULL AND coalesce((proj->>'online_required')::boolean,false) THEN reason:='online_required';
   ELSIF proj->>'state'='used' THEN outcome:='conflict'; reason:='already_used';
   ELSIF proj->>'state' IN ('storno','waitlisted') OR NOT coalesce((proj->>'admission_allowed')::boolean,false) THEN reason:='admission_not_allowed';
   ELSIF proj->>'eligibility_fingerprint' IS DISTINCT FROM op->>'eligibility_fingerprint' THEN outcome:='conflict'; reason:='eligibility_changed';
   ELSIF (proj->>'requires_unpaid_confirmation')::boolean AND (NOT coalesce((op->>'confirm_unpaid')::boolean,false) OR op->>'snapshot_id' IS NOT NULL) THEN reason:='unpaid_confirmation_required';
   ELSE
    reason:='admitted'; outcome:='accepted';
    IF op->>'snapshot_id' IS NOT NULL THEN
     SELECT * INTO snap FROM public.scanner_snapshots WHERE id=(op->>'snapshot_id')::uuid AND session_id=p_session;
     IF snap.id IS NULL OR snap.expires_at<=now() OR s.offline_until<=now() OR NOT EXISTS(
      SELECT 1 FROM public.scanner_snapshot_pages pg CROSS JOIN LATERAL jsonb_array_elements(pg.payload_text::jsonb) item
      WHERE pg.snapshot_id=snap.id AND item->>'ticket_id'=tid::text AND item->>'eligibility_fingerprint'=op->>'eligibility_fingerprint') THEN
      outcome:='conflict'; reason:='offline_grant_invalid'; END IF;
    END IF;
    IF outcome='accepted' THEN
     PERFORM public.scanner_admit_ticket_internal(tid);
    END IF;
   END IF;
  END IF;
  receipt:=jsonb_build_object('operation_id',op->>'operation_id','ticket_id',tid,'outcome',outcome,'reason',reason,
   'committed_at',clock_timestamp(),'eligibility_fingerprint',op->>'eligibility_fingerprint');
  INSERT INTO public.scanner_operations(operation_id,session_id,occasion_id,ticket_id,payload_hash,payload,receipt)
   VALUES((op->>'operation_id')::uuid,p_session,s.occasion_id,tid,h,canonical,receipt);
  results:=results||jsonb_build_array(receipt);
 END LOOP;
 RETURN jsonb_build_object('code',200,'data',results,'server_time',now());
END $$;
CREATE OR REPLACE FUNCTION public.get_scanner_receipts(p_session uuid,p_token text,p_operation_ids uuid[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; result jsonb;
BEGIN
 s:=public.scanner_session_internal(p_session,p_token,true);
 IF coalesce(array_length(p_operation_ids,1),0)>50 THEN RAISE invalid_parameter_value; END IF;
 -- Expired/revoked devices can reconcile their immutable history, never perform a new write.
 SELECT coalesce(jsonb_agg(receipt),'[]'::jsonb) INTO result FROM public.scanner_operations WHERE session_id=p_session AND operation_id=ANY(p_operation_ids);
 RETURN jsonb_build_object('code',200,'data',result,'server_time',now());
END $$;
CREATE OR REPLACE FUNCTION public.get_scanner_summary(p_session uuid,p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE s public.scanner_sessions; result jsonb;
BEGIN
 s:=public.scanner_session_internal(p_session,p_token);
 WITH eligible AS MATERIALIZED (
 SELECT t.id,t.state FROM eshop.tickets t WHERE t.occasion=s.occasion_id AND t.ticket_symbol IS NOT NULL
 AND t.state IN ('used','paid','sent','ordered') AND EXISTS(SELECT 1 FROM eshop.order_product_ticket z WHERE z.ticket=t.id)
 AND NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket z JOIN eshop.orders o ON o.id=z."order" WHERE z.ticket=t.id AND (o.state IN ('stock','storno','waitlisted','preparing_payment') OR o.occasion<>s.occasion_id)))
 SELECT jsonb_build_object('used_current',count(*) FILTER(WHERE state='used'),'unused_eligible',count(*) FILTER(WHERE state IN ('paid','sent')),
 'eligible_total',count(*) FILTER(WHERE state IN ('used','paid','sent')),'unpaid_conditional',count(*) FILTER(WHERE state='ordered'),
 -- Count the same ticket population as the offline projection, including unpaid/stock records.
 'snapshot_ticket_count',(SELECT count(*) FROM eshop.tickets t WHERE t.occasion=s.occasion_id
 AND EXISTS(SELECT 1 FROM eshop.order_product_ticket z JOIN eshop.orders o ON o.id=z."order" WHERE z.ticket=t.id)),
 'definition_version',1,'definition','used + paid/sent; excludes conditional unpaid, cancelled and waitlisted',
 'server_time',now(),'settings_revision',(SELECT revision FROM public.scanner_settings WHERE occasion_id=s.occasion_id)) INTO result FROM eligible;
 RETURN jsonb_build_object('code',200,'data',result,'server_time',now());
END $$;
CREATE OR REPLACE FUNCTION public.resolve_scanner_conflict(p_operation uuid,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE op public.scanner_operations;
BEGIN
 SELECT * INTO STRICT op FROM public.scanner_operations WHERE operation_id=p_operation;
 PERFORM public.check_is_editor_order_on_occasion(op.occasion_id);
 IF auth.uid() IS NULL OR op.receipt->>'outcome'<>'conflict' THEN RAISE insufficient_privilege; END IF;
 INSERT INTO public.scanner_conflict_resolutions(operation_id,actor_user_id,reason) VALUES(p_operation,auth.uid(),p_reason) ON CONFLICT DO NOTHING;
 RETURN jsonb_build_object('code',200,'server_time',now());
END $$;
REVOKE ALL ON FUNCTION public.lookup_scanner_ticket(uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.lookup_scanner_ticket(uuid,text,text) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.search_scanner_tickets(uuid,text,text,bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.search_scanner_tickets(uuid,text,text,bigint) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.sync_scanner_operations(uuid,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.sync_scanner_operations(uuid,text,jsonb) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_scanner_receipts(uuid,text,uuid[]) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_scanner_receipts(uuid,text,uuid[]) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_scanner_summary(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_scanner_summary(uuid,text) TO anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.resolve_scanner_conflict(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.resolve_scanner_conflict(uuid,text) TO authenticated,service_role;

-- SOURCE: eshop_orders/update_ticket_to_unused_ws.sql
CREATE OR REPLACE FUNCTION public.update_ticket_to_unused_ws(
    ticket_id bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    occasion_id bigint;
    updated_count integer;
BEGIN
    SELECT occasion
    INTO STRICT occasion_id
    FROM eshop.tickets
    WHERE id = ticket_id;

    PERFORM public.check_is_editor_order_on_occasion(occasion_id);

    IF NOT public.admit_scan_access_v1(occasion_id,true) THEN
        RAISE SQLSTATE 'PT429' USING MESSAGE='abuse_limit_exceeded';
    END IF;
    PERFORM public.check_ticket_is_mutable(ticket_id);

    UPDATE eshop.tickets
    SET
        -- `sent` is the canonical unused state that can be scanned again.
        state = 'sent',
        updated_at = clock_timestamp()
    WHERE id = ticket_id
      AND state = 'used';

    GET DIAGNOSTICS updated_count = ROW_COUNT;
    IF updated_count <> 1 THEN
        RAISE EXCEPTION 'Ticket % is not used.', ticket_id;
    END IF;
    PERFORM public.enqueue_ticket_wallet_internal(ARRAY[ticket_id]);
END;
$$;

REVOKE ALL ON FUNCTION public.update_ticket_to_unused_ws(bigint)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_ticket_to_unused_ws(bigint)
TO authenticated, service_role;

-- SOURCE: eshop_orders/mark_order_and_tickets_paid_internal_v1.sql
-- Shared state transition. Public callers own authorization and delivery intent.
CREATE OR REPLACE FUNCTION public.mark_order_and_tickets_paid_internal_v1(order_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE occasion_id bigint; current_state text; provider_guard jsonb;
BEGIN
    PERFORM public.lock_order_capacity_scope_internal(ARRAY[order_id]);
    -- Retrieve the occasion associated with the order
    SELECT occasion, state INTO occasion_id, current_state FROM eshop.orders WHERE id = order_id FOR UPDATE;

    -- Check if the order exists and has an associated occasion
    IF occasion_id IS NULL THEN
        RAISE EXCEPTION 'Order not found or no associated occasion.';
    END IF;

    provider_guard:=public.provider_paid_guard_internal(order_id);
    IF provider_guard IS NOT NULL THEN RETURN provider_guard; END IF;
    -- Check if the order is in 'ordered' or 'created' state before proceeding
    -- Allow 'created' to support direct payments (e.g. manual cash) without explicit confirmation step
    -- FIX: Allow 'expired' too, as late payments should reactivate the order
    IF current_state != 'ordered' AND current_state != 'created' AND current_state != 'expired' THEN
        RETURN jsonb_build_object('code', 400, 'message', 'Order is not in "ordered", "created" or "expired" state (current: ' || current_state || ')');
    END IF;

    -- Update the state of the order to 'paid'
    UPDATE eshop.orders
    SET state = 'paid', updated_at = now(),email_payment_version=email_payment_version+1
    WHERE id = order_id;

    -- Update the state of all tickets linked to the order to 'paid', except those with state 'storno'
    UPDATE eshop.tickets
    SET state = 'paid', updated_at = now()
    FROM eshop.order_product_ticket
    WHERE eshop.order_product_ticket.ticket = eshop.tickets.id
    AND eshop.order_product_ticket."order" = order_id
    AND eshop.tickets.state IN ('ordered','expired','paid');

    PERFORM public.enqueue_order_wallet_internal(order_id);
    PERFORM public.notification_center_order_state_internal(order_id);
    RETURN jsonb_build_object('code',200,'message','Update successful');
END $$;
REVOKE ALL ON FUNCTION public.mark_order_and_tickets_paid_internal_v1(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mark_order_and_tickets_paid_internal_v1(bigint) TO service_role;

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
        PERFORM public.enqueue_order_wallet_internal(p_order_id);
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

    PERFORM public.enqueue_order_wallet_internal(p_order_id);
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

-- SOURCE: eshop_orders/internal_storno_tickets_221.sql
CREATE OR REPLACE FUNCTION internal_storno_tickets_221(ticket_ids_to_storno BIGINT[])
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public, extensions

AS $$
DECLARE
    opt_ids BIGINT[];
    nc_changed record;
    nc_changes jsonb;
    nc_products bigint[];
    nc_event uuid;
    nc_contexts bigint[];
    nc_blueprints bigint[];
BEGIN
    PERFORM public.lock_blueprint_scope_internal(ARRAY(SELECT DISTINCT occasion FROM eshop.tickets WHERE id=ANY(ticket_ids_to_storno)));
    PERFORM public.check_blueprint_selection_units_internal(ARRAY(SELECT s.id FROM eshop.spots s JOIN eshop.order_product_ticket opt ON opt.id=s.order_product_ticket WHERE opt.ticket=ANY(ticket_ids_to_storno)));
    IF ticket_ids_to_storno IS NULL OR array_length(ticket_ids_to_storno, 1) = 0 THEN
        RETURN; -- Nothing to do
    END IF;

    PERFORM public.lock_order_capacity_scope_internal(ARRAY(SELECT DISTINCT "order" FROM eshop.order_product_ticket WHERE ticket=ANY(ticket_ids_to_storno)));
    PERFORM public.lock_ticket_order_products_internal(o.id) FROM eshop.orders o WHERE o.id IN
      (SELECT "order" FROM eshop.order_product_ticket WHERE ticket=ANY(ticket_ids_to_storno)) ORDER BY o.id;
    UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id IN
      (SELECT o.form FROM eshop.order_product_ticket x JOIN eshop.orders o ON o.id=x."order" WHERE x.ticket=ANY(ticket_ids_to_storno));
    UPDATE eshop.waitlist_offer_slots SET outcome='cancelled',updated_at=clock_timestamp()
      WHERE ticket_id=ANY(ticket_ids_to_storno) AND outcome='pending';
    SELECT array_agg(DISTINCT s.inventory_context),array_agg(DISTINCT s.blueprint) INTO nc_contexts,nc_blueprints FROM eshop.spots s JOIN eshop.order_product_ticket x ON x.id=s.order_product_ticket WHERE x.ticket=ANY(ticket_ids_to_storno);
    SELECT array_agg(DISTINCT product) INTO nc_products FROM eshop.order_product_ticket WHERE ticket=ANY(ticket_ids_to_storno) AND product IS NOT NULL;
    SELECT coalesce(jsonb_agg(to_jsonb(changes)),'[]') INTO nc_changes FROM (
      SELECT x."order" order_id,array_agg(DISTINCT t.id ORDER BY t.id) ticket_ids FROM eshop.order_product_ticket x
      JOIN eshop.tickets t ON t.id=x.ticket WHERE t.id=ANY(ticket_ids_to_storno) AND t.state IS DISTINCT FROM 'storno' GROUP BY x."order"
    ) changes;
    -- 1. Get all related order_product_ticket IDs
    SELECT ARRAY_AGG(opt.id) INTO opt_ids
    FROM eshop.order_product_ticket opt
    WHERE opt.ticket = ANY(ticket_ids_to_storno);

    -- 2. (NEW) Delete any occasion_users linked to these tickets.
    -- We delete directly because the parent function already
    -- verified the user has 'editor' permissions.
    PERFORM public.notification_center_prepared_invalidate_user(m."user",m.occasion) FROM public.occasion_users m WHERE m.ticket=ANY(ticket_ids_to_storno);
    DELETE FROM public.occasion_users
    WHERE ticket = ANY(ticket_ids_to_storno);

    -- 3. Update the tickets themselves to 'storno'
    UPDATE eshop.tickets
    SET state = 'storno', updated_at = NOW()
    WHERE id = ANY(ticket_ids_to_storno);

    PERFORM public.enqueue_ticket_wallet_internal(ticket_ids_to_storno);

    -- 4. Nullify the relevant spots
    IF opt_ids IS NOT NULL THEN
        UPDATE eshop.spots
        SET order_product_ticket = NULL,
            secret = NULL,
            secret_expiration_time = NULL,
            updated_at = NOW(),
            resource = NULL,
            state = NULL
        WHERE order_product_ticket = ANY(opt_ids);
    END IF;

    -- 5. Nullify the product link on the order_product_ticket records
    UPDATE eshop.order_product_ticket
    SET product = NULL
    WHERE ticket = ANY(ticket_ids_to_storno);

    FOR nc_changed IN SELECT * FROM jsonb_to_recordset(nc_changes) AS r(order_id bigint,ticket_ids bigint[]) LOOP
      PERFORM public.notification_center_order_internal(nc_changed.order_id,'order_cancelled',encode(extensions.digest(array_to_string(nc_changed.ticket_ids,','),'sha256'),'hex'),auth.uid(),
        jsonb_build_object('count',cardinality(nc_changed.ticket_ids)));
      SELECT id INTO nc_event FROM public.notification_center_events WHERE kind='order_cancelled' AND data->>'orderId'=nc_changed.order_id::text
        AND source_key='order_cancelled:'||nc_changed.order_id||':'||encode(extensions.digest(array_to_string(nc_changed.ticket_ids,','),'sha256'),'hex');
      PERFORM public.notification_center_form_capacity_internal((SELECT form FROM eshop.orders WHERE id=nc_changed.order_id),auth.uid(),nc_event);
    END LOOP;
    PERFORM public.notification_center_product_capacity_internal(p) FROM unnest(nc_products) p;
    PERFORM public.notification_center_inventory_capacity_internal(c) FROM unnest(nc_contexts) c WHERE c IS NOT NULL;
    PERFORM public.notification_center_blueprint_capacity_internal(b) FROM unnest(nc_blueprints) b WHERE b IS NOT NULL;
END;
$$;

-- SOURCE: eshop_orders/delete_order.sql
CREATE OR REPLACE FUNCTION public.delete_order_internal_v1(order_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  payment_info_id BIGINT;
  order_product_ticket_ids BIGINT[];
  ticket_ids BIGINT[];
  order_oc BIGINT;
  ou_record RECORD;
  form_id BIGINT;
  related_orders BIGINT[];
  offer_ids UUID[];
  v_activity_impacts jsonb := '[]'::jsonb;
BEGIN
  -- Retrieve the order's occasion and payment_info.
  SELECT occasion, payment_info, form
    INTO order_oc, payment_info_id, form_id
    FROM eshop.orders
   WHERE id = delete_order_internal_v1.order_id;

  IF order_oc IS NULL THEN
    RAISE EXCEPTION 'Order not found.';
  END IF;

  -- Deletion belongs to scoped unit managers/editors and organization admins.
  IF auth.uid() IS NULL OR NOT public.can_delete_orders(order_oc) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager, editor or organization admin required';
  END IF;
  -- The queue send gate locks global capacity before an order. Deletion must
  -- acquire that outer lock before the form/order helper to avoid inversion.
  PERFORM 1 FROM public.email_capacity FOR UPDATE;
  -- Form serialization fences offer issuance, acceptance, expiry and recovery.
  -- Lock every directly related order in ID order before changing any links.
  PERFORM 1 FROM public.forms WHERE id=form_id FOR UPDATE;
  SELECT array_agg(DISTINCT id ORDER BY id) INTO related_orders FROM (
    SELECT o.id FROM eshop.orders o WHERE o.id=delete_order_internal_v1.order_id OR o.source_waitlist_order_id=delete_order_internal_v1.order_id
      OR o.id=(SELECT source_waitlist_order_id FROM eshop.orders WHERE id=delete_order_internal_v1.order_id)
    UNION SELECT a.source_order_id FROM eshop.waitlist_acceptance_attempts a WHERE a.source_order_id=delete_order_internal_v1.order_id OR a.target_order_id=delete_order_internal_v1.order_id
    UNION SELECT a.target_order_id FROM eshop.waitlist_acceptance_attempts a WHERE a.source_order_id=delete_order_internal_v1.order_id OR a.target_order_id=delete_order_internal_v1.order_id
  ) related;
  IF EXISTS(SELECT 1 FROM eshop.orders o WHERE o.id=ANY(related_orders)
      AND (o.occasion<>order_oc OR o.form IS DISTINCT FROM form_id)) THEN
    RAISE EXCEPTION 'ORDER_WAITLIST_SCOPE_MISMATCH'; END IF;
  PERFORM public.check_batch_order_delete_internal(order_id);
  PERFORM public.lock_order_capacity_scope_internal(related_orders);
  IF EXISTS(SELECT 1 FROM eshop.orders WHERE id=delete_order_internal_v1.order_id AND state='preparing_payment')
    OR EXISTS(SELECT 1 FROM eshop.waitlist_acceptance_attempts a
      WHERE (a.target_order_id=delete_order_internal_v1.order_id OR a.source_order_id=delete_order_internal_v1.order_id) AND a.state='preparing') THEN
    RAISE EXCEPTION 'WAITLIST_ACCEPTANCE_IN_PROGRESS'; END IF;
  UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id IN(SELECT form FROM eshop.orders WHERE id=delete_order_internal_v1.order_id);
  -- Match occasion configuration/deletion: forms precede the occasion row.
  -- The group/activity advisory lock does not fence an occasion's unit move.
  PERFORM 1 FROM public.occasions WHERE id=order_oc FOR SHARE;
  PERFORM public.lock_activity_aggregate_internal_v1(order_oc);
  IF auth.uid() IS NULL OR NOT public.can_delete_orders(order_oc) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager, editor or organization admin required';
  END IF;

  -- After authorization, match the worker lock order (capacity, order,
  -- attempts, message). Recheck the order after locking against concurrent edits.
  PERFORM 1 FROM public.email_capacity FOR UPDATE;
  SELECT o.payment_info INTO payment_info_id
    FROM eshop.orders o
   WHERE o.id = delete_order_internal_v1.order_id AND o.occasion = order_oc
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found or occasion changed.';
  END IF;

  PERFORM public.check_order_refund_delete_internal(order_id);

  -- Delete attention while message identities still exist. Cascading recipients
  -- and deliveries make every overview, count and badge agree immediately.
  PERFORM public.notification_center_prepared_delete_events(ARRAY(SELECT * FROM public.notification_center_prepared_order_events(delete_order_internal_v1.order_id)));
  DELETE FROM public.notification_center_events WHERE id=ANY(ARRAY(SELECT * FROM public.notification_center_prepared_order_events(delete_order_internal_v1.order_id)));
  DELETE FROM public.notification_center_source_state s
  USING public.email_messages m
  WHERE m.order_id=delete_order_internal_v1.order_id
    AND s.organization=m.organization AND s.source_key='email:'||m.message_id;

  -- Remove every queued/reminder/provider record for this order. log_emails
  -- and address suppressions are independent audit/safety records and remain.
  DELETE FROM public.email_delivery_events e
   WHERE e.message_id IN (SELECT m.message_id FROM public.email_messages m
                           WHERE m.order_id = delete_order_internal_v1.order_id)
      OR e.attempt_id IN (SELECT a.attempt_id FROM public.email_attempts a
                          JOIN public.email_messages m USING (message_id)
                         WHERE m.order_id = delete_order_internal_v1.order_id)
      OR e.provider_message_id IN (
           SELECT m.provider_message_id FROM public.email_messages m
            WHERE m.order_id = delete_order_internal_v1.order_id
           UNION
           SELECT a.provider_message_id FROM public.email_attempts a
           JOIN public.email_messages m USING (message_id)
            WHERE m.order_id = delete_order_internal_v1.order_id);

  DELETE FROM public.email_confirmation_receipts r
   WHERE r.message_id IN (SELECT m.message_id FROM public.email_messages m
                          WHERE m.order_id = delete_order_internal_v1.order_id);
  DELETE FROM public.email_attempts a
   WHERE a.message_id IN (SELECT m.message_id FROM public.email_messages m
                          WHERE m.order_id = delete_order_internal_v1.order_id);
  DELETE FROM public.email_messages m
   WHERE m.order_id = delete_order_internal_v1.order_id;

  -- Collect all order_product_ticket IDs for the order.
  SELECT ARRAY(SELECT id FROM eshop.order_product_ticket WHERE "order" = delete_order_internal_v1.order_id)
    INTO order_product_ticket_ids;

  -- Collect all ticket IDs from the order_product_ticket rows.
  SELECT ARRAY(SELECT ticket
                 FROM eshop.order_product_ticket
                WHERE "order" = delete_order_internal_v1.order_id
                  AND ticket IS NOT NULL)
    INTO ticket_ids;

  IF EXISTS(SELECT 1 FROM eshop.order_product_ticket x WHERE x.ticket=ANY(ticket_ids) AND x."order"<>delete_order_internal_v1.order_id) THEN
    RAISE EXCEPTION 'TICKET_LINKED_TO_ANOTHER_ORDER'; END IF;

  -- Remove only this order's capability/offer evidence. Accepted children are
  -- independent orders: detach their source FK, never their tickets or finance.
  SELECT coalesce(array_agg(w.id),'{}') INTO offer_ids FROM eshop.waitlist_offers w WHERE w.order_id=delete_order_internal_v1.order_id;
  PERFORM 1 FROM eshop.waitlist_acceptance_attempts a
    WHERE a.source_order_id=delete_order_internal_v1.order_id OR a.target_order_id=delete_order_internal_v1.order_id ORDER BY a.command_id FOR UPDATE;
  PERFORM 1 FROM eshop.waitlist_offers w WHERE w.id=ANY(offer_ids) ORDER BY w.id FOR UPDATE;
  PERFORM 1 FROM eshop.waitlist_offer_slots x
    WHERE x.offer_id=ANY(offer_ids) OR x.ticket_id=ANY(ticket_ids) OR x.resulting_order_id=delete_order_internal_v1.order_id ORDER BY x.id FOR UPDATE;
  DELETE FROM eshop.waitlist_capabilities c WHERE c.order_id=delete_order_internal_v1.order_id OR c.offer_id=ANY(offer_ids);
  DELETE FROM eshop.waitlist_acceptance_attempts a WHERE a.source_order_id=delete_order_internal_v1.order_id OR a.target_order_id=delete_order_internal_v1.order_id;
  UPDATE eshop.waitlist_offer_slots x SET resulting_order_id=NULL,updated_at=clock_timestamp() WHERE x.resulting_order_id=delete_order_internal_v1.order_id;
  DELETE FROM eshop.waitlist_offer_slots x WHERE x.offer_id=ANY(offer_ids) OR x.ticket_id=ANY(ticket_ids);
  DELETE FROM eshop.waitlist_offers w WHERE w.id=ANY(offer_ids);
  UPDATE eshop.orders o SET source_waitlist_order_id=NULL,updated_at=clock_timestamp() WHERE o.source_waitlist_order_id=delete_order_internal_v1.order_id;

  -- Free any spots that reference these order_product_ticket rows:
  -- set order_product_ticket, secret, and secret_expiration_time to NULL.
  UPDATE eshop.spots
     SET order_product_ticket      = NULL,
         secret                  = NULL,
         secret_expiration_time  = NULL,
         updated_at              = NOW()
   WHERE order_product_ticket = ANY(order_product_ticket_ids);

  -- Delete the related order_product_ticket entries.
  DELETE FROM eshop.order_product_ticket WHERE "order" = delete_order_internal_v1.order_id;

  -- Ticket-bound membership teardown has one domain owner, independent of
  -- the retired public RPC. Authorization remains the order's manager boundary.
  IF EXISTS(SELECT 1 FROM public.occasion_users WHERE ticket=ANY(ticket_ids) AND occasion<>order_oc) THEN
    RAISE invalid_parameter_value USING MESSAGE='ticket membership belongs to another occasion';
  END IF;
  FOR ou_record IN SELECT "user",occasion FROM public.occasion_users
    WHERE ticket=ANY(ticket_ids) AND occasion=order_oc ORDER BY "user"
  LOOP
    v_activity_impacts:=v_activity_impacts || public.remove_occasion_user_domain_internal_v1(order_oc,ou_record."user");
  END LOOP;
  -- The canonical order facade already invalidates profiles for remaining members.
  -- Teardown must also invalidate affected activity projections in sorted order.
  INSERT INTO public.client_sync_private_scopes(component,occasion,user_id,source_revision)
  SELECT DISTINCT x->>'component',order_oc,(x->>'userId')::uuid,1
  FROM jsonb_array_elements(v_activity_impacts) x
  JOIN public.occasion_users ou ON ou.occasion=order_oc AND ou."user"=(x->>'userId')::uuid
  WHERE x->>'component'='private_activity' ORDER BY 1,3
  ON CONFLICT(component,occasion,user_id) DO UPDATE
    SET source_revision=public.client_sync_private_scopes.source_revision+1,updated_at=clock_timestamp();

  -- Delete the related tickets.
  -- This is now safe, as any occasion_users foreign key constraints
  -- should be resolved by the loop above.
  PERFORM public.enqueue_ticket_wallet_internal(ticket_ids);
  DELETE FROM eshop.tickets WHERE id = ANY(ticket_ids);

  -- Delete order history rows.
  DELETE FROM eshop.orders_history WHERE "order" = delete_order_internal_v1.order_id;

  -- Order-specific bank requests must not keep the order alive through their FK.
  DELETE FROM eshop.bank_account_requests WHERE "order" = delete_order_internal_v1.order_id;

  -- If a payment_info row exists, first free it from the order reference, then delete it.
  IF payment_info_id IS NOT NULL THEN
    UPDATE eshop.orders
       SET payment_info = NULL
     WHERE id = delete_order_internal_v1.order_id;

    -- Retain imported/manual bank transactions while removing their payment link.
    UPDATE eshop.transactions
       SET payment_info = NULL
     WHERE payment_info = payment_info_id;

    DELETE FROM eshop.payment_info WHERE id = payment_info_id;
  END IF;

  -- Finally, delete the order record.
  DELETE FROM eshop.orders WHERE id = delete_order_internal_v1.order_id;

END;
$$;

REVOKE ALL ON FUNCTION public.delete_order_internal_v1(bigint) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.delete_order_221(order_id bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public, extensions AS $$
BEGIN
  PERFORM public.delete_order_client_sync_v1(
    order_id,extensions.gen_random_uuid());
END; $$;
REVOKE ALL ON FUNCTION public.delete_order_221(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_order_221(bigint) TO authenticated;

-- SOURCE: payment_providers/effects.sql
-- Lock order: capacity/form scope -> order -> payment -> provider attempt -> tickets.
-- All facts are read back from connector storage. No caller-supplied markPaid/amount.
CREATE OR REPLACE FUNCTION public.apply_provider_payment_effects_internal(
 p_provider text,p_attempt uuid,p_revision text,p_before jsonb,p_expired boolean DEFAULT false,
 p_unresolved boolean DEFAULT false,p_action text DEFAULT 'observe',p_tickets bigint[] DEFAULT '{}'
) RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE context jsonb; prior jsonb; o eshop.orders; pi eshop.payment_info; totals record; projection jsonb; transition jsonb;
 received numeric; refunded numeric; payment_time timestamptz; deadline timestamptz; cancelled bigint[];
 conflict boolean; action_required boolean; changed boolean:=false; args jsonb:=jsonb_build_object('attemptId',p_attempt); decision jsonb; fact jsonb;
BEGIN
 IF p_provider IS NULL OR p_provider='bank' OR p_attempt IS NULL OR nullif(p_revision,'') IS NULL
  OR p_action IS NULL OR p_action NOT IN ('observe','keep','cancel_selected') THEN RAISE EXCEPTION 'PAYMENT_EFFECT_INPUT_INVALID'; END IF;
 context:=public.payment_provider_call_internal(p_provider,'effect_context',args);
 IF context IS NULL OR jsonb_typeof(context)<>'object' OR NOT context ?& ARRAY['attemptId','orderId','paymentId','connectionId','organizationId','unitId','accountId','livemode','amountMinor','currency','reservationExpiresAt','state','incomplete','receivedMinor','refundedMinor','paymentTime','decisions']
  OR context->>'attemptId' IS DISTINCT FROM p_attempt::text OR nullif(context->>'accountId','') IS NULL
  OR nullif(context->>'connectionId','') IS NULL OR (context->>'connectionId')::uuid IS NULL
  OR context->>'state' IS NULL OR context->>'state' NOT IN ('preparing','open','uncertain','paid','expired','action_required')
  OR jsonb_typeof(context->'livemode') IS DISTINCT FROM 'boolean' OR jsonb_typeof(context->'incomplete') IS DISTINCT FROM 'boolean'
  OR jsonb_typeof(context->'decisions') IS DISTINCT FROM 'array'
  OR jsonb_typeof(context->'amountMinor') IS DISTINCT FROM 'number' OR jsonb_typeof(context->'receivedMinor') IS DISTINCT FROM 'number'
  OR jsonb_typeof(context->'refundedMinor') IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'PAYMENT_EFFECT_CONTEXT_INVALID'; END IF;
 prior:=context;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[(context->>'orderId')::bigint]);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=(context->>'orderId')::bigint FOR UPDATE;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info FOR UPDATE;
 PERFORM public.payment_provider_call_internal(p_provider,'effect_lock',args);
 context:=public.payment_provider_call_internal(p_provider,'effect_context',args);
 IF context IS DISTINCT FROM prior OR pi.id IS DISTINCT FROM (context->>'paymentId')::bigint
  OR pi.payment_method IS DISTINCT FROM p_provider OR pi.amount*100 IS DISTINCT FROM (context->>'amountMinor')::numeric
  OR pi.currency_code::text IS DISTINCT FROM context->>'currency'
  OR NOT EXISTS(SELECT 1 FROM public.occasions WHERE id=o.occasion AND organization=(context->>'organizationId')::bigint AND unit=(context->>'unitId')::bigint)
  OR (p_before IS NOT NULL AND p_before->>'method' IS DISTINCT FROM p_provider) THEN RAISE EXCEPTION 'PAYMENT_EFFECT_SCOPE_INVALID'; END IF;
 IF (context->>'amountMinor')::numeric<=0 OR (context->>'amountMinor')::numeric<>trunc((context->>'amountMinor')::numeric) THEN RAISE EXCEPTION 'PAYMENT_EFFECT_TOTALS_INVALID'; END IF;
 received:=(context->>'receivedMinor')::numeric/100;refunded:=(context->>'refundedMinor')::numeric/100;
 deadline:=(context->>'reservationExpiresAt')::timestamptz;payment_time:=(context->>'paymentTime')::timestamptz;
 IF received<0 OR refunded<0 OR received>pi.amount OR refunded>received OR deadline IS NULL
  OR received*100<>trunc(received*100) OR refunded*100<>trunc(refunded*100)
  OR (received>0 AND payment_time IS NULL) THEN RAISE EXCEPTION 'PAYMENT_EFFECT_TOTALS_INVALID'; END IF;
 PERFORM public.refresh_payment_info_totals_internal(pi.id);
 SELECT * INTO STRICT totals FROM public.payment_financial_totals_internal(pi.id);
 conflict:=totals.gross_received>pi.amount OR totals.external_received<>0;
 action_required:=context->>'state'='action_required';
 IF p_action<>'observe' THEN
  IF auth.uid() IS NULL OR NOT public.can_write_orders(o.occasion) OR NOT EXISTS(SELECT 1 FROM public.user_info WHERE id=auth.uid() AND organization=(context->>'organizationId')::bigint)
   THEN RAISE insufficient_privilege USING MESSAGE='order editor required'; END IF;
  IF refunded<=0 OR refunded>=pi.amount OR context->>'state'<>'paid' OR o.state NOT IN ('paid','sent') OR totals.invalid_identity
   OR context->'incomplete'='true'::jsonb THEN RAISE EXCEPTION 'PAYMENT_PARTIAL_REFUND_REQUIRED'; END IF;
  IF (p_action='keep' AND cardinality(p_tickets)<>0) OR (p_action='cancel_selected' AND cardinality(p_tickets) NOT BETWEEN 1 AND 1000)
   OR EXISTS(SELECT 1 FROM unnest(p_tickets) selected(id) WHERE selected.id IS NULL OR NOT EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) t WHERE t.id=selected.id AND t.state IN ('paid','sent','ordered'))) THEN RAISE EXCEPTION 'PAYMENT_REFUND_TICKET_UNAVAILABLE'; END IF;
  PERFORM 1 FROM eshop.tickets WHERE id=ANY(p_tickets) ORDER BY id FOR UPDATE;
  IF p_action='cancel_selected' THEN
   PERFORM public.internal_storno_tickets_221(p_tickets);
   UPDATE eshop.orders SET email_payment_version=email_payment_version+1,updated_at=clock_timestamp() WHERE id=o.id;
   IF EXISTS(SELECT 1 FROM public.get_order_tickets_internal(o.id) WHERE state<>'storno') THEN PERFORM public.enqueue_paid_order_tickets(o.id); END IF;
  END IF;
  decision:=public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('reason',CASE WHEN p_action='keep' THEN 'partial_refund_keep' ELSE 'partial_refund_cancel' END,'revision',p_revision,'tickets',to_jsonb(p_tickets)));
  PERFORM public.enqueue_order_wallet_internal(o.id);
  RETURN jsonb_build_object('changed',true,'decisionId',decision,'payment',public.provider_order_payment_projection_internal(o.id));
 END IF;
 IF conflict AND NOT context->'decisions' ? 'financial_conflict' THEN
  action_required:=true;
  PERFORM public.payment_provider_call_internal(p_provider,'effect_state',args||'{"state":"action_required"}');
  PERFORM public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('reason','financial_conflict','revision',p_revision));
  UPDATE eshop.orders SET email_payment_version=email_payment_version+1 WHERE id=o.id;
  PERFORM public.cancel_order_email_intents(o.id);changed:=true;
 END IF;
 IF received>=pi.amount AND refunded<pi.amount AND NOT conflict AND context->'incomplete'='false'::jsonb THEN
  IF o.state IN ('ordered','created') AND payment_time<=deadline THEN
   transition:=public.update_order_and_tickets_to_paid(o.id);
   IF transition->>'code' IS DISTINCT FROM '200' THEN RAISE EXCEPTION 'PAYMENT_PAID_TRANSITION_FAILED'; END IF;
   changed:=true;
  ELSIF o.state NOT IN ('paid','sent') THEN
   action_required:=true;
   PERFORM public.payment_provider_call_internal(p_provider,'effect_state',args||'{"state":"action_required"}');
   IF NOT context->'decisions' ? 'late_payment' THEN PERFORM public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('reason','late_payment','revision',p_revision)); END IF;
  END IF;
  PERFORM public.payment_provider_call_internal(p_provider,'effect_state',args||jsonb_build_object('state',CASE WHEN action_required THEN 'action_required' ELSE 'paid' END));
 END IF;
 IF refunded>=pi.amount AND received>0 THEN
  IF NOT context->'decisions' ? 'full_refund' THEN
   SELECT array_agg(t.id) INTO cancelled FROM public.get_order_tickets_internal(o.id) t WHERE coalesce(t.state,'') NOT IN ('used','storno');
   PERFORM public.internal_storno_tickets_221(cancelled);
   PERFORM public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('reason','full_refund','revision',p_revision,'tickets',to_jsonb(coalesce(cancelled,'{}'))));
   UPDATE eshop.orders SET state='storno',email_payment_version=email_payment_version+1,updated_at=clock_timestamp() WHERE id=o.id;
   PERFORM public.cancel_order_email_intents(o.id);changed:=true;
  END IF;
 ELSIF totals.gross_received=0 AND (p_expired OR (p_unresolved AND deadline<=clock_timestamp())) AND o.state='ordered' THEN
  SELECT array_agg(t.id) INTO cancelled FROM public.get_order_tickets_internal(o.id) t WHERE coalesce(t.state,'') NOT IN ('used','storno');
  PERFORM public.internal_storno_tickets_221(cancelled);
  UPDATE eshop.orders SET state='expired',email_payment_version=email_payment_version+1,updated_at=clock_timestamp() WHERE id=o.id;
  -- Releasing inventory does not prove financial absence. Keep uncertain recovery alive.
  IF NOT p_unresolved THEN PERFORM public.payment_provider_call_internal(p_provider,'effect_state',args||'{"state":"expired"}'); END IF;
  PERFORM public.cancel_order_email_intents(o.id);changed:=true;
 END IF;
 projection:=public.provider_order_payment_projection_internal(o.id);
 IF projection->>'admissionState' IS DISTINCT FROM p_before->>'admissionState' AND
  (projection->>'status'='disputed' OR p_before->>'status'='disputed' OR projection->'reconciliationPending'='true'::jsonb OR p_before->'reconciliationPending'='true'::jsonb) THEN
  UPDATE eshop.orders SET email_payment_version=email_payment_version+1 WHERE id=o.id;
  PERFORM public.payment_provider_call_internal(p_provider,'effect_decision',args||jsonb_build_object('revision',p_revision,'reason',
   CASE WHEN projection->>'status'='disputed' THEN 'dispute_hold' WHEN p_before->>'status'='disputed' THEN 'dispute_release'
   WHEN projection->'reconciliationPending'='true'::jsonb THEN 'reconciliation_hold' ELSE 'reconciliation_release' END));
  IF projection->>'admissionState'='valid' THEN PERFORM public.enqueue_paid_order_tickets(o.id); END IF;
  changed:=true;
 END IF;

 FOR fact IN SELECT value FROM jsonb_array_elements(public.payment_provider_call_internal(p_provider,'notification_facts',args)) LOOP
  PERFORM public.notification_center_payment_fact_internal(o.id,p_provider,fact->>'identity',(fact->>'amount')::numeric,fact->>'currency',(fact->>'occurredAt')::timestamptz);
 END LOOP;
 PERFORM public.notification_center_payment_problem_internal(o.id,action_required OR conflict,
  CASE WHEN conflict THEN 'financial_conflict' ELSE 'action_required' END);
 PERFORM public.enqueue_order_wallet_internal(o.id);
 RETURN jsonb_build_object('changed',changed,'payment',projection);
END $$;
REVOKE ALL ON FUNCTION public.apply_provider_payment_effects_internal(text,uuid,text,jsonb,boolean,boolean,text,bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: ticket_wallet/capabilities.sql
CREATE OR REPLACE FUNCTION public.prepare_ticket_wallet(p_message uuid,p_ticket bigint,p_hash text DEFAULT NULL,p_sealed jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE m public.email_messages; o public.occasions; f jsonb; c eshop.ticket_wallet_capabilities; i eshop.ticket_wallet_integrations;
BEGIN
 PERFORM public.require_service_role();
 IF p_hash IS NOT NULL AND EXISTS(SELECT 1 FROM eshop.ticket_wallet_audit WHERE token_hash=p_hash) THEN RETURN NULL; END IF;
 SELECT * INTO m FROM public.email_messages WHERE message_id=p_message;
 IF m.message_kind IS DISTINCT FROM 'order_tickets' OR NOT public.email_intent_valid(m)
 OR NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE ticket=p_ticket AND "order"=m.order_id) THEN
  RAISE insufficient_privilege USING MESSAGE='Wallet unavailable'; END IF;
 SELECT * INTO o FROM public.occasions WHERE id=m.occasion;
 SELECT x INTO f FROM jsonb_array_elements(o.features) x WHERE x->>'code'='ticket';
 SELECT * INTO i FROM eshop.ticket_wallet_integrations WHERE organization=m.organization AND publishing_ready;
 IF NOT coalesce((f->>'is_enabled')::boolean,false) OR NOT public.ticket_wallet_enabled(f) OR i.organization IS NULL
 OR nullif(btrim(o.title),'') IS NULL OR (o.data->>'timezone' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=o.data->>'timezone'))
 OR o.end_time IS NULL OR o.start_time IS NULL OR o.end_time+interval '7 days'<=now() THEN RETURN NULL; END IF;
 -- Serialize issuance/reissue on the existing ticket; revoked rows never disappear.
 PERFORM 1 FROM eshop.tickets WHERE id=p_ticket AND occasion=m.occasion AND state IN ('paid','sent','used') AND ticket_symbol IS NOT NULL AND public.provider_ticket_admission_allowed_internal(id) FOR UPDATE;
 IF NOT FOUND THEN RETURN NULL; END IF;
 PERFORM public.refresh_ticket_wallet_term_internal(p_ticket);
 SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE ticket_id=p_ticket;
 IF c.reissue_after IS NOT NULL AND m.created_at>c.reissue_after AND p_hash IS NOT NULL AND p_sealed IS NOT NULL THEN
  UPDATE eshop.ticket_wallet_capabilities SET token_hash=p_hash,sealed=p_sealed,recipient=m.recipient,message_id=m.message_id,
   revoked_at=NULL,reissue_after=NULL,event_end_at=o.end_time,expires_at=o.end_time+interval '7 days' WHERE ticket_id=p_ticket RETURNING * INTO c;
  PERFORM public.enqueue_ticket_wallet_internal(ARRAY[p_ticket]);
 END IF;
 IF c.ticket_id IS NULL AND p_hash IS NOT NULL AND p_sealed IS NOT NULL THEN
  INSERT INTO eshop.ticket_wallet_capabilities(ticket_id,organization,occasion,order_id,token_hash,sealed,recipient,message_id,expires_at,event_end_at)
  VALUES(p_ticket,m.organization,m.occasion,m.order_id,p_hash,p_sealed,m.recipient,m.message_id,o.end_time+interval '7 days',o.end_time) RETURNING * INTO c;
 END IF;
 IF c.reissue_after IS NOT NULL AND m.created_at>c.reissue_after AND p_hash IS NULL THEN c.ticket_id:=NULL; END IF;
 IF c.ticket_id IS NOT NULL AND (c.revoked_at IS NOT NULL OR c.expires_at<=now() OR c.recipient IS DISTINCT FROM m.recipient
 OR c.organization<>m.organization OR c.occasion<>m.occasion OR c.order_id<>m.order_id) THEN RETURN NULL; END IF;
 RETURN jsonb_build_object('organization',m.organization,'occasion',m.occasion,'ticketId',p_ticket,'issuer',i.issuer,
 'environment',i.environment,'webOrigin',i.web_origin,'badgeUrls',i.badge_urls,
 'source',CASE WHEN c.ticket_id IS NOT NULL THEN jsonb_build_object('sealed',c.sealed,'tokenHash',c.token_hash,'generation',c.generation) END);
END $$;

CREATE OR REPLACE FUNCTION public.resolve_ticket_wallet(p_hash text,p_source text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c eshop.ticket_wallet_capabilities; i eshop.ticket_wallet_integrations; n integer; k text;
BEGIN
 PERFORM public.require_service_role();
 IF p_hash !~ '^[a-f0-9]{64}$' OR p_source !~ '^[a-f0-9]{64}$' THEN RETURN NULL; END IF;
 DELETE FROM eshop.ticket_wallet_limits WHERE window_at<now()-interval '10 minutes';
 FOREACH k IN ARRAY ARRAY['token:'||p_hash,'source:'||p_source] LOOP
  INSERT INTO eshop.ticket_wallet_limits(key,window_at,attempts) VALUES(k,now(),1)
  ON CONFLICT(key) DO UPDATE SET attempts=CASE WHEN ticket_wallet_limits.window_at<now()-interval '1 minute' THEN 1 ELSE ticket_wallet_limits.attempts+1 END,
  window_at=CASE WHEN ticket_wallet_limits.window_at<now()-interval '1 minute' THEN now() ELSE ticket_wallet_limits.window_at END RETURNING attempts INTO n;
  IF n>20 THEN RETURN NULL; END IF;
 END LOOP;
 PERFORM public.refresh_ticket_wallet_term_internal((SELECT ticket_id FROM eshop.ticket_wallet_capabilities WHERE token_hash=p_hash));
 SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE token_hash=p_hash AND revoked_at IS NULL AND expires_at>now();
 IF c.ticket_id IS NULL THEN RETURN NULL; END IF;
 SELECT * INTO i FROM eshop.ticket_wallet_integrations WHERE organization=c.organization;
 IF i.organization IS NULL THEN RETURN NULL; END IF;
 RETURN jsonb_build_object('ticketId',c.ticket_id,'organization',c.organization,'occasion',c.occasion,'issuer',i.issuer,'environment',i.environment,
 'webOrigin',i.web_origin,'projection',public.ticket_wallet_projection_internal(c.ticket_id));
END $$;

-- Explicit support operation. A new generation always requires a fresh valid email intent.
CREATE OR REPLACE FUNCTION public.manage_ticket_wallet(p_ticket bigint,p_action text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE c eshop.ticket_wallet_capabilities; scope bigint;
BEGIN
 SELECT occasion INTO scope FROM eshop.ticket_wallet_capabilities WHERE ticket_id=p_ticket;
 IF auth.uid() IS NULL OR public.can_write_orders(scope) IS NOT TRUE THEN RAISE insufficient_privilege; END IF;
 IF p_action NOT IN ('revoke','reissue') THEN RAISE invalid_parameter_value; END IF;
 PERFORM 1 FROM eshop.tickets WHERE id=p_ticket FOR UPDATE;
 SELECT * INTO c FROM eshop.ticket_wallet_capabilities WHERE ticket_id=p_ticket FOR UPDATE;
 UPDATE eshop.ticket_wallet_capabilities SET revoked_at=coalesce(revoked_at,now()) WHERE ticket_id=p_ticket;
 -- Reissue retains the tombstone and audit while removing access to the previous source.
 IF p_action='reissue' THEN
  UPDATE eshop.ticket_wallet_capabilities SET generation=generation+1,reissue_after=clock_timestamp(),sealed='{}',token_hash=encode(extensions.gen_random_bytes(32),'hex'),
   recipient='',message_id='00000000-0000-0000-0000-000000000000',expires_at=now() WHERE ticket_id=p_ticket;
 END IF;
 INSERT INTO eshop.ticket_wallet_audit(ticket_id,generation,token_hash,actor,action) VALUES(p_ticket,c.generation,c.token_hash,auth.uid(),p_action);
 PERFORM public.enqueue_ticket_wallet_internal(ARRAY[p_ticket]);
END $$;
REVOKE ALL ON FUNCTION public.prepare_ticket_wallet(uuid,bigint,text,jsonb),public.resolve_ticket_wallet(text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_ticket_wallet(uuid,bigint,text,jsonb),public.resolve_ticket_wallet(text,text) TO service_role;
REVOKE ALL ON FUNCTION public.manage_ticket_wallet(bigint,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.manage_ticket_wallet(bigint,text) TO authenticated;

-- SOURCE: others/update_occasion.sql
CREATE OR REPLACE FUNCTION public.update_occasion_internal_v1(input_data JSONB)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
SET search_path = public, extensions
 AS $$
 DECLARE
     updated_occ public.occasions;
     occ_id BIGINT;
     now TIMESTAMPTZ := NOW();
     final_unit BIGINT;

     -- Variable for the determined support flag
     is_app_supported BOOLEAN;

     -- Variable to help find the organization to check settings
     v_org_id BIGINT;

     -- Variables for feature handling
     new_blueprint_id BIGINT;
     v_form_id BIGINT;
     v_form_blueprint BIGINT;
     v_form_settings JSONB;
     v_form_link TEXT;
     v_reminder_interval_seconds BIGINT;
     v_email_order record;

     input_features JSONB;
     old_features JSONB;
     old_sync_enabled boolean := false;
     processed_features JSONB;
     feature JSONB;
     form_feature_found BOOLEAN;
 BEGIN
     -- Validate input data. Raise an exception if it's missing or empty.
     IF input_data IS NULL OR input_data = '{}'::jsonb THEN
         RAISE EXCEPTION 'Input data is missing or empty';
     END IF;

     -- 1. Identify the Organization ID
     IF (input_data->>'id') IS NOT NULL THEN
         -- Case A: UPDATE - Get organization from the existing occasion
         SELECT organization INTO v_org_id
         FROM public.occasions
         WHERE id = (input_data->>'id')::BIGINT;
     ELSE
         -- Case B: INSERT - Try to get organization from input
         v_org_id := (input_data->>'organization')::BIGINT;

         -- Case C: INSERT fallback - If org is missing, try to get it via the Unit
         IF v_org_id IS NULL AND (input_data->>'unit') IS NOT NULL THEN
            SELECT organization INTO v_org_id
            FROM public.units
            WHERE id = (input_data->>'unit')::BIGINT;
         END IF;
     END IF;

     -- 2. Fetch the setting from public.organizations.data
     -- Defaults to TRUE if the organization or the key is not found to ensure backward compatibility
     IF v_org_id IS NOT NULL THEN
         SELECT COALESCE((data->>'IS_APP_SUPPORTED')::BOOLEAN, false)
         INTO is_app_supported
         FROM public.organizations
         WHERE id = v_org_id;
     ELSE
         is_app_supported := false;
     END IF;

     -- Ensure is_app_supported is not null (redundant safety check)
     is_app_supported := COALESCE(is_app_supported, false);

     --
     -- Prepare features based on is_app_supported flag
     --
     input_features := COALESCE(input_data->'features', '[]'::jsonb);
     processed_features := '[]'::jsonb;

     IF NOT is_app_supported THEN
         -- If the app is not supported, we must enable the 'form' feature.
         form_feature_found := false;
         -- Loop through existing features to find and enable the form feature
         FOR feature IN SELECT * FROM jsonb_array_elements(input_features)
         LOOP
             IF feature->>'code' = 'form' THEN
                 -- If form feature exists, ensure it is enabled
                 feature := feature || '{"is_enabled": true}';
                 form_feature_found := true;
             END IF;
             processed_features := processed_features || feature;
         END LOOP;

         -- If the form feature was not found in the original array, add it.
         IF NOT form_feature_found THEN
             processed_features := processed_features || '{"code": "form", "is_enabled": true}';
         END IF;
     ELSE
         -- If app is supported, use features as they were provided.
         processed_features := input_features;
     END IF;

     -- Determine if this is an UPDATE or INSERT based on the presence of an 'id'
     occ_id := (input_data->>'id')::BIGINT;

     IF occ_id IS NOT NULL THEN
         PERFORM public.lock_blueprint_scope_internal(ARRAY[occ_id]);
         PERFORM public.check_occasion_writable(occ_id);
         -- This is an UPDATE operation

         -- Check for the existence of the occasion and get its current unit
         SELECT unit, features, is_order_synchronization_enabled INTO final_unit, old_features, old_sync_enabled FROM public.occasions WHERE id = occ_id FOR UPDATE;
         IF NOT FOUND THEN
             RAISE EXCEPTION 'Occasion with ID % not found', occ_id;
         END IF;

         processed_features := public.merge_ticket_layout_features(old_features, processed_features, input_data->'ticket_layout_change');
         PERFORM public.validate_ticket_layout_references(occ_id, f->'layout') FROM jsonb_array_elements(processed_features) f WHERE f->>'code'='ticket' AND f ? 'layout';

         -- Determine the final unit, allowing it to be updated.
         final_unit := COALESCE((input_data->>'unit')::BIGINT, final_unit);

         -- Security check: ensure the current user has editor rights on the target unit.
         IF NOT public.can_edit_occasion(occ_id,final_unit) THEN
             RAISE insufficient_privilege USING MESSAGE = 'unit editor required';
         END IF;

         IF (input_data ? 'organization' AND (input_data->>'organization')::bigint IS DISTINCT FROM v_org_id)
           OR NOT EXISTS(SELECT 1 FROM public.units WHERE id=final_unit AND organization=v_org_id) THEN
           RAISE insufficient_privilege USING MESSAGE='Occasion tenant cannot change'; END IF;

         IF jsonb_path_exists(coalesce(old_features,'[]'), '$[*] ? (@.code == "blueprint" && @.is_enabled == true)')
           AND NOT jsonb_path_exists(processed_features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)') THEN
           IF EXISTS(SELECT 1 FROM public.forms WHERE occasion=occ_id AND blueprint IS NOT NULL)
             OR EXISTS(SELECT 1 FROM eshop.spots WHERE occasion=occ_id AND blueprint IS NOT NULL AND
               (order_product_ticket IS NOT NULL OR (secret IS NOT NULL AND secret_expiration_time>clock_timestamp()))) THEN
             RAISE EXCEPTION 'ASSIGNMENTS_EXIST'; END IF;
         END IF;

         UPDATE public.occasions
            SET updated_at  = now,
                title       = COALESCE(input_data->>'title', title),
                description = COALESCE(input_data->>'description', description),
                link        = public.reserve_public_link_internal('occasion',occ_id,input_data->>'link',false),
                data        = COALESCE(input_data->'data', data),
                is_hidden   = COALESCE((input_data->>'is_hidden')::BOOLEAN, is_hidden),
                is_open     = COALESCE((input_data->>'is_open')::BOOLEAN, is_open),
                is_promoted = COALESCE((input_data->>'is_promoted')::BOOLEAN, is_promoted),
                start_time  = COALESCE((input_data->>'start_time')::TIMESTAMPTZ, start_time),
                end_time    = COALESCE((input_data->>'end_time')::TIMESTAMPTZ, end_time),
                organization = COALESCE((input_data->>'organization')::BIGINT, organization),
                services    = COALESCE(input_data->'services', services),
                unit        = final_unit,
                is_order_synchronization_enabled=COALESCE((input_data->>'is_order_synchronization_enabled')::boolean,is_order_synchronization_enabled),
                features    = processed_features -- Use the processed features
          WHERE id = occ_id
          RETURNING * INTO updated_occ;

     ELSE
         -- This is an INSERT operation

         -- For new occasions, the 'unit' field is mandatory.
         final_unit := (input_data->>'unit')::BIGINT;
         IF final_unit IS NULL THEN
             RAISE EXCEPTION 'The "unit" field is required for new occasions';
         END IF;

         -- Security check for the new occasion's unit.
         IF NOT public.can_create_occasion(final_unit) THEN
             RAISE insufficient_privilege USING MESSAGE = 'unit editor required';
         END IF;

         -- We still need to default 'reminder_is_enabled' for the 'form' feature if not specified.
         -- We do this on the already processed_features array.
         input_features := processed_features; -- Use the result from the is_app_supported logic
         processed_features := '[]'::jsonb;
         FOR feature IN SELECT * FROM jsonb_array_elements(input_features)
         LOOP
             -- If the current feature is the 'form' feature
             IF feature->>'code' = 'form' THEN
                 -- And if 'reminder_is_enabled' is NOT specified, default it to true.
                 IF NOT (feature ? 'reminder_is_enabled') THEN
                     feature := feature || '{"reminder_is_enabled": true}';
                 END IF;
             END IF;
             processed_features := processed_features || feature::jsonb;
         END LOOP;

         processed_features := public.merge_ticket_layout_features('[]', processed_features, input_data->'ticket_layout_change', true);

         INSERT INTO public.occasions(
             created_at, updated_at, title, description, link, data,
             is_hidden, is_open, is_promoted, start_time, end_time, organization,
             services, unit, features
         )
         VALUES(
             now, now,
             COALESCE(input_data->>'title', ''),
             COALESCE(input_data->>'description', ''),
             '',
             COALESCE(input_data->'data', '{}'::jsonb),
             COALESCE((input_data->>'is_hidden')::BOOLEAN, false),
             COALESCE((input_data->>'is_open')::BOOLEAN, true),
             COALESCE((input_data->>'is_promoted')::BOOLEAN, false),
             (input_data->>'start_time')::TIMESTAMPTZ,
             (input_data->>'end_time')::TIMESTAMPTZ,
             (input_data->>'organization')::BIGINT,
             COALESCE(input_data->'services', '{}'::jsonb),
             final_unit,
             processed_features
         )
         RETURNING * INTO updated_occ;

         -- Set the occ_id from the newly created record for subsequent logic
         occ_id := updated_occ.id;
         UPDATE public.occasions SET link=public.reserve_public_link_internal('occasion',occ_id,input_data->>'link',true) WHERE id=occ_id RETURNING * INTO updated_occ;
     END IF;

     PERFORM public.validate_ticket_layout_references(occ_id, f->'layout') FROM jsonb_array_elements(processed_features) f WHERE f->>'code'='ticket' AND f ? 'layout';
     --
     -- Post-update/insert feature handling
     --

     -- Check if form feature is enabled and handle related logic.
     -- This will now be triggered if is_app_supported was false (based on organization settings).
     IF jsonb_path_exists(updated_occ.features, '$[*] ? (@.code == "form" && @.is_enabled == true)') THEN
         -- Extract the settings for the 'form' feature from the newly saved data
         SELECT elem INTO v_form_settings
         FROM jsonb_array_elements(updated_occ.features) AS elem
         WHERE elem->>'code' = 'form';

         -- Create a default form if one doesn't exist for the occasion
         IF NOT EXISTS (SELECT 1 FROM public.forms WHERE occasion = occ_id) THEN
             v_form_link := NULLIF(btrim(input_data->>'form_link'), '');
             IF input_data->>'id' IS NULL THEN
               PERFORM public.create_initial_occasion_form_internal_v1(occ_id,v_form_link,'Registration');
             ELSE
               PERFORM public.create_form(occ_id,v_form_link,'Registration');
             END IF;
         END IF;

         -- Check if reminders are enabled within the form feature
         IF (v_form_settings->>'reminder_is_enabled')::boolean IS TRUE THEN
             -- Get the reminder interval, defaulting to 1 day (86400 seconds) if not specified
             v_reminder_interval_seconds := COALESCE(
                 (v_form_settings->>'reminder_interval_seconds')::bigint,
                 86400
             );
             -- Call the function to queue payment reminders for all relevant orders

         END IF;
     END IF;

     -- Revalidate in-flight reminders after every relevant occasion update.
     PERFORM public.queue_payment_reminders(occ_id,coalesce(v_reminder_interval_seconds,86400));
     IF updated_occ.is_order_synchronization_enabled AND (
       NOT coalesce(old_sync_enabled,false) OR (
        NOT jsonb_path_exists(coalesce(old_features,'[]'), '$[*] ? (@.code == "ticket" && @.is_enabled == true)')
        AND jsonb_path_exists(updated_occ.features, '$[*] ? (@.code == "ticket" && @.is_enabled == true)'))) THEN
       FOR v_email_order IN SELECT id FROM eshop.orders WHERE occasion=occ_id AND state='paid' LOOP
         PERFORM public.enqueue_paid_order_tickets(v_email_order.id);
       END LOOP;
     END IF;
     PERFORM public.enqueue_wallet_scope_internal(occ_id);
     -- Check if the blueprint feature is enabled in the final, saved state
     IF jsonb_path_exists(updated_occ.features, '$[*] ? (@.code == "blueprint" && @.is_enabled == true)') THEN
         -- Prepare a plan even when all forms use capacity/waitlisting.
         SELECT id INTO new_blueprint_id FROM eshop.blueprints
          WHERE occasion=occ_id AND (SELECT count(*) FROM eshop.blueprints WHERE occasion=occ_id)=1;
         IF new_blueprint_id IS NULL AND NOT EXISTS(SELECT 1 FROM eshop.blueprints WHERE occasion=occ_id) THEN
             INSERT INTO eshop.blueprints(occasion, organization, created_at, updated_at,layout)
             VALUES (occ_id, COALESCE(updated_occ.organization, 1), now, now,
              '{"schemaVersion":2,"symbolSetVersion":1,"canvas":{"x":0,"y":0,"width":1120,"height":2080,"fill":"#ffffffff"},"styles":{},"seatingDefaults":{},"textPolicy":{"language":"und","direction":"auto"},"nodes":[],"selectionUnits":[],"attachments":[],"sections":[],"presets":[]}'::jsonb)
             RETURNING id INTO new_blueprint_id;
         END IF;

         -- Saved seat selectors use the plan immediately. Ordinary forms keep
         -- their product choices, capacity and waitlist until that selector is enabled.
         PERFORM public.sync_form_blueprint_internal(id) FROM public.forms WHERE occasion=occ_id ORDER BY id;
     END IF;
 END;
 $$;

-- SOURCE: others/save_occasion_domain_command_internal_v1.sql

-- The public save wrapper and the settings UI allow unit editors. The renamed
-- canonical domain command retained its older occasion-only guard, so it must
-- accept the same role before it reaches update_occasion_internal_v1.
CREATE OR REPLACE FUNCTION public.save_occasion_domain_command_internal_v1(
  p_occasion bigint,
  p_command_id uuid,
  p_expected_version bigint,
  p_config jsonb
) RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_version bigint;
  v_begin jsonb;
  v_hash text;
  v_entity jsonb;
  v_old_hidden boolean;
  v_new_hidden boolean;
  v_old_unit bigint;
  v_new_unit bigint;
  v_features jsonb;
  v_seating_provenance jsonb;
  v_fanout_units bigint[] := '{}';
BEGIN
  SELECT o.unit INTO v_old_unit
  FROM public.occasions o
  WHERE o.id = p_occasion;

  IF v_actor IS NULL OR NOT public.can_edit_occasion(p_occasion,(p_config->>'unit')::bigint) THEN
    RAISE insufficient_privilege USING MESSAGE = 'occasion editor required';
  END IF;

  IF p_config IS NULL OR jsonb_typeof(p_config) <> 'object'
    OR octet_length(p_config::text) > 1048576
    OR (p_config->>'id')::bigint IS DISTINCT FROM p_occasion
    OR EXISTS (
      SELECT 1
      FROM jsonb_object_keys(p_config) key
      WHERE key NOT IN (
        'id', 'start_time', 'end_time', 'is_open', 'is_hidden', 'is_promoted',
        'link', 'title', 'description', 'data', 'services', 'organization',
        'unit', 'features', 'settings', 'feature_changes', 'form_link', 'has_orders', 'stats', 'ticket_layout_change'
      )
    )
  THEN
    RAISE invalid_parameter_value USING MESSAGE = 'invalid occasion aggregate';
  END IF;

  PERFORM public.lock_blueprint_scope_internal(ARRAY[p_occasion]);
  v_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'occasion', p_occasion,
    'expectedVersion', p_expected_version,
    'config', p_config
  )::text, 'UTF8'), 'sha256'), 'hex');
  v_begin := public.begin_client_mutation_v1(
    p_command_id,
    'occasion.config.save',
    p_occasion,
    v_actor,
    v_hash
  );
  IF v_begin->>'disposition' = 'replay' THEN
    RETURN v_begin->'response';
  END IF;

  PERFORM public.notification_center_initialized_internal((SELECT organization FROM public.occasions WHERE id=p_occasion));
  IF NOT (p_config ? 'ticket_layout_change' AND p_config-ARRAY['id','ticket_layout_change']='{}'::jsonb) THEN
    PERFORM 1 FROM public.forms WHERE occasion=p_occasion ORDER BY id FOR UPDATE;
  END IF;

  SELECT o.is_hidden, o.unit INTO v_old_hidden, v_old_unit
  FROM public.occasions o
  WHERE o.id = p_occasion
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,
      'rejected',
      404,
      jsonb_build_object('version', 0, 'occasion', NULL)
    );
  END IF;

  INSERT INTO public.client_aggregate_versions(
    aggregate_type, scope_type, scope_id, aggregate_id, version
  ) VALUES ('occasion', 'occasion', p_occasion, p_occasion::text, 0)
  ON CONFLICT DO NOTHING;
  SELECT version INTO v_version
  FROM public.client_aggregate_versions
  WHERE aggregate_type = 'occasion'
    AND scope_type = 'occasion'
    AND scope_id = p_occasion
    AND aggregate_id = p_occasion::text
  FOR UPDATE;
  IF p_expected_version IS DISTINCT FROM v_version THEN
    SELECT to_jsonb(o) || jsonb_build_object('aggregate_version', v_version,'seatingPreviousConfiguration',v_seating_provenance)
    INTO v_entity
    FROM public.occasions o
    WHERE o.id = p_occasion;
    RETURN public.complete_client_mutation_outcome_v1(
      p_command_id,
      'conflict',
      409,
      jsonb_build_object('version', v_version, 'occasion', v_entity)
    );
  END IF;

  SELECT jsonb_build_object('features',o.features,'bindings',(SELECT coalesce(jsonb_agg(jsonb_build_object('formId',f.id,'blueprintId',f.blueprint) ORDER BY f.id),'[]') FROM public.forms f WHERE f.occasion=p_occasion AND f.blueprint IS NOT NULL)) INTO v_seating_provenance FROM public.occasions o WHERE o.id=p_occasion;

  IF p_config ? 'ticket_layout_change' AND p_config - ARRAY['id','ticket_layout_change']='{}'::jsonb THEN
    IF NOT public.can_edit_ticket_layout(p_occasion) THEN
      RAISE insufficient_privilege USING MESSAGE='unit editor required';
    END IF;
    SELECT features INTO v_features FROM public.occasions WHERE id=p_occasion;
    v_features:=public.merge_ticket_layout_features(v_features,v_features,p_config->'ticket_layout_change');
    v_features:=public.merge_ticket_appearance_internal_v1(p_occasion,v_features,p_config#>'{ticket_layout_change,appearance}');
    PERFORM public.validate_ticket_layout_references(p_occasion,f->'layout')
      FROM jsonb_array_elements(v_features) f WHERE f->>'code'='ticket' AND f ? 'layout';
    UPDATE public.occasions SET features=v_features,updated_at=clock_timestamp() WHERE id=p_occasion;
    PERFORM public.enqueue_wallet_scope_internal(p_occasion);
  ELSE
    PERFORM public.update_occasion_internal_v1(
      public.apply_occasion_settings_intent_internal_v1(p_occasion,p_config));
  END IF;
  UPDATE public.client_aggregate_versions
  SET version = version + 1, updated_at = clock_timestamp()
  WHERE aggregate_type = 'occasion'
    AND scope_type = 'occasion'
    AND scope_id = p_occasion
    AND aggregate_id = p_occasion::text
  RETURNING version INTO v_version;
  SELECT to_jsonb(o) || jsonb_build_object('aggregate_version', v_version,'seatingPreviousConfiguration',v_seating_provenance)
  INTO v_entity
  FROM public.occasions o
  WHERE o.id = p_occasion;

  v_new_hidden := (v_entity->>'is_hidden')::boolean;
  v_new_unit := (v_entity->>'unit')::bigint;
  IF NOT v_old_hidden THEN
    v_fanout_units := array_append(v_fanout_units, v_old_unit);
  END IF;
  IF NOT v_new_hidden AND v_new_unit IS DISTINCT FROM v_old_unit THEN
    v_fanout_units := array_append(v_fanout_units, v_new_unit);
  ELSIF NOT v_new_hidden AND v_old_hidden THEN
    v_fanout_units := array_append(v_fanout_units, v_new_unit);
  END IF;

  RETURN public.complete_client_mutation_applied_v1(
    p_command_id,
    p_occasion,
    'occasion.config.save',
    'configuration',
    jsonb_build_array(jsonb_build_object(
      'entityType', 'occasion',
      'entityId', p_occasion,
      'operation', 'update',
      'safeLabel', left(v_entity->>'title', 240),
      'changedFields', jsonb_build_array('configuration')
    )),
    CASE WHEN v_old_hidden AND NOT v_new_hidden THEN ARRAY[
      'occasion_config', 'program_catalog', 'map_catalog', 'content_catalog',
      'live_public'
    ] ELSE ARRAY['occasion_config'] END,
    '[]',
    '[]',
    jsonb_build_object('version', v_version, 'occasion', v_entity),
    CASE WHEN NOT v_new_hidden THEN ARRAY['occasion_config'] ELSE '{}'::text[] END,
    '[]',
    'user',
    NULL,
    '[]',
    v_fanout_units
  );
END;
$$;

REVOKE ALL ON FUNCTION public.save_occasion_domain_command_internal_v1(
  bigint, uuid, bigint, jsonb
) FROM PUBLIC, anon, authenticated;

-- SOURCE: eshop/update_product.sql

CREATE OR REPLACE FUNCTION public.update_product_internal_v1(p_input JSONB)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_product_id BIGINT;
  v_occasion_id BIGINT;
  v_product_type_id BIGINT;
  v_existing_price NUMERIC;
  v_input_price NUMERIC;
  v_effective_price NUMERIC;
  v_input_deposit NUMERIC;
  v_primary_forms bigint[];
  v_primary_form bigint;
BEGIN
  -- Extract product id from the input JSON
  v_product_id := (p_input->>'id')::BIGINT;

  -- Try to find the product to determine if we are updating or creating.
  -- This also gets the *current* occasion for the permission check on UPDATE.
  IF v_product_id IS NOT NULL THEN
    SELECT pt.occasion, p.price
    INTO v_occasion_id, v_existing_price
    FROM eshop.products p
    JOIN eshop.product_types pt ON p.product_type = pt.id
    WHERE p.id = v_product_id FOR UPDATE OF p;
  END IF;

  -- CASE 1: Product was found (v_product_id was not null and existed)
  IF FOUND THEN
    -- We are UPDATING.

    -- Ensure the caller has permission to edit this product's *current* occasion.
    -- This function is expected to raise an exception on failure.
    PERFORM public.check_is_editor_order_on_occasion(v_occasion_id);

    SELECT coalesce(array_agg(DISTINCT ff.form),'{}'::bigint[]) INTO v_primary_forms
    FROM public.form_fields ff JOIN eshop.product_types pt ON pt.id=ff.product_type
    JOIN eshop.products p ON p.product_type=pt.id
    WHERE p.id=v_product_id AND pt.type='spot';

    -- VALIDATION: deposit amount must be less than effective price (input price overrides existing)
    v_input_price := NULLIF(p_input->>'price', '')::NUMERIC;
    v_effective_price := COALESCE(v_input_price, v_existing_price);
    v_input_deposit := NULLIF(p_input->'data'->'deposit'->>'amount', '')::NUMERIC;
    IF v_input_deposit IS NOT NULL AND v_input_deposit > 0
       AND v_effective_price IS NOT NULL AND v_input_deposit >= v_effective_price THEN
      RAISE EXCEPTION '%', jsonb_build_object(
          'code', 'DEPOSIT_AMOUNT_TOO_HIGH',
          'message', 'Deposit amount (' || v_input_deposit || ') must be less than price (' || v_effective_price || ').'
      )::text;
    END IF;

    PERFORM public.validate_product_price_update(v_product_id,v_effective_price,
      COALESCE(p_input->'data',(SELECT data FROM eshop.products WHERE id=v_product_id)),
      COALESCE(p_input->>'currency_code',(SELECT currency_code FROM eshop.products WHERE id=v_product_id)));
    -- A product with schedules cannot silently move to another occasion/type.
    IF EXISTS (SELECT 1 FROM eshop.planned_changes WHERE subject_id=v_product_id
      AND change_type IN('products.price','products.is_hidden') AND NOT applied) AND (
      NULLIF(p_input->>'occasion','')::bigint IS DISTINCT FROM v_occasion_id AND p_input->>'occasion' IS NOT NULL
      OR NULLIF(p_input->>'product_type','')::bigint IS DISTINCT FROM
        (SELECT product_type FROM eshop.products WHERE id=v_product_id) AND p_input->>'product_type' IS NOT NULL
    ) THEN RAISE EXCEPTION 'CANCEL_PRICE_CHANGES_BEFORE_PRODUCT_MOVE'; END IF;

    IF p_input->>'product_type' IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.product_types WHERE id=(p_input->>'product_type')::bigint AND occasion=v_occasion_id) THEN RAISE EXCEPTION 'Product type occasion mismatch'; END IF;
    IF p_input->>'occasion' IS NOT NULL AND (p_input->>'occasion')::bigint<>v_occasion_id THEN RAISE EXCEPTION 'Product occasion cannot change'; END IF;
    -- Update only the fields that are provided in the input JSON.
    -- COALESCE is used to keep the existing value if a new one isn't provided.
    -- NULLIF is added to safely handle empty strings '' during casting.
    PERFORM 1 FROM public.occasions WHERE id=v_occasion_id FOR UPDATE;
    IF p_input ? 'product_type' AND NULLIF(p_input->>'product_type','')::bigint IS DISTINCT FROM (SELECT product_type FROM eshop.products WHERE id=v_product_id)
      AND EXISTS(SELECT 1 FROM eshop.order_product_ticket WHERE product=v_product_id)
    THEN RAISE EXCEPTION 'Purchased product type cannot change'; END IF;
    IF nullif(p_input->>'maximum','')::integer>0 AND
      nullif(p_input->>'maximum','')::integer<(SELECT count(*) FROM eshop.order_product_ticket WHERE product=v_product_id) THEN
      RAISE EXCEPTION 'PRODUCT_CAPACITY_BELOW_COMMITTED'; END IF;
    UPDATE eshop.products p
    SET
      occasion      = COALESCE(NULLIF(p_input->>'occasion', '')::BIGINT, p.occasion),
      title         = COALESCE(p_input->>'title',         p.title),
      description   = COALESCE(p_input->>'description',   p.description),
      price         = COALESCE(NULLIF(p_input->>'price', '')::NUMERIC, p.price),
      currency_code = COALESCE(p_input->>'currency_code', p.currency_code),
      data          = COALESCE(p_input->'data',           p.data),
      product_type  = COALESCE(NULLIF(p_input->>'product_type', '')::BIGINT, p.product_type),
      "order"       = COALESCE(NULLIF(p_input->>'order', '')::INT,  p."order"),
      maximum       = COALESCE(NULLIF(p_input->>'maximum', '')::INT, p.maximum),
      is_hidden     = COALESCE(NULLIF(p_input->>'is_hidden', '')::BOOLEAN, p.is_hidden),
      updated_at    = NOW()
    WHERE p.id = v_product_id;

    FOREACH v_primary_form IN ARRAY v_primary_forms LOOP
      PERFORM public.assert_form_primary_products_internal(v_primary_form);
    END LOOP;

    -- Return the ID of the updated product on success.
    IF p_input ? 'inventory_contexts' THEN
      PERFORM public.update_product_inventory_contexts_internal_v1(v_product_id,p_input->'inventory_contexts');
    END IF;
    IF NOT (p_input ? 'inventory_contexts') THEN
      PERFORM public.advance_ticketing_authoring_version_internal_v1('product',v_occasion_id,v_product_id);
    END IF;
    PERFORM public.notification_center_product_capacity_internal(v_product_id);
    PERFORM public.enqueue_wallet_scope_internal(v_occasion_id);
    RETURN v_product_id;

  -- CASE 2: Product was NOT found (v_product_id was NULL or was an ID that doesn't exist)
  ELSE
    -- We are CREATING, as per the request.

    -- 1. Get the product_type from the JSON.
    v_product_type_id := (p_input->>'product_type')::BIGINT;

    -- 2. Validate product_type is provided (it's required for creation).
    IF v_product_type_id IS NULL THEN
      RAISE EXCEPTION '%', jsonb_build_object(
          'code', 'PRD422',
          'message', 'Field "product_type" is required when creating a new product.'
      )::text;
    END IF;

    -- 3. Find the occasion for the *new* product_type to check permissions.
    SELECT occasion
    INTO v_occasion_id
    FROM eshop.product_types
    WHERE id = v_product_type_id;

    -- 4. Handle invalid product_type.
    IF NOT FOUND THEN
      RAISE EXCEPTION '%', jsonb_build_object(
          'code', 'PTY404',
          'message', 'Product type with ID ' || v_product_type_id || ' not found.'
      )::text;
    END IF;

    -- 5. Ensure the caller has permission to create a product on this occasion.
    PERFORM public.check_is_editor_order_on_occasion(v_occasion_id);

    -- 6. VALIDATION: deposit amount must be less than price (both from input on CREATE)
    v_input_price := NULLIF(p_input->>'price', '')::NUMERIC;
    v_input_deposit := NULLIF(p_input->'data'->'deposit'->>'amount', '')::NUMERIC;
    IF v_input_deposit IS NOT NULL AND v_input_deposit > 0
       AND v_input_price IS NOT NULL AND v_input_deposit >= v_input_price THEN
      RAISE EXCEPTION '%', jsonb_build_object(
          'code', 'DEPOSIT_AMOUNT_TOO_HIGH',
          'message', 'Deposit amount (' || v_input_deposit || ') must be less than price (' || v_input_price || ').'
      )::text;
    END IF;

    PERFORM public.validate_product_price(v_input_price,p_input->'data',p_input->>'currency_code');

    -- 7. Insert the new product.
    -- We ignore the `id` from the JSON (v_product_id) and let the sequence generate a new one.
    -- We use NULLIF to safely cast potentially empty strings.
    INSERT INTO eshop.products (
      occasion,
      title,
      description,
      price,
      currency_code,
      data,
      product_type,
      "order",
      maximum,
      is_hidden
      -- created_at and updated_at are assumed to have defaults (e.g., NOW())
    )
    VALUES (
      v_occasion_id,
      p_input->>'title',
      p_input->>'description',
      NULLIF(p_input->>'price', '')::NUMERIC,
      p_input->>'currency_code',
      p_input->'data',
      v_product_type_id, -- We already extracted and validated this
      NULLIF(p_input->>'order', '')::INT,
      NULLIF(p_input->>'maximum', '')::INT,
      -- Default to 'false' if is_hidden is not provided on create
      COALESCE(NULLIF(p_input->>'is_hidden', '')::BOOLEAN, false)
    )
    RETURNING id INTO v_product_id; -- Get the newly created ID

    -- Return the ID of the newly created product.
    IF p_input ? 'inventory_contexts' THEN
      PERFORM public.update_product_inventory_contexts_internal_v1(v_product_id,p_input->'inventory_contexts');
    END IF;
    IF NOT (p_input ? 'inventory_contexts') THEN
      PERFORM public.advance_ticketing_authoring_version_internal_v1('product',v_occasion_id,v_product_id);
    END IF;
    PERFORM public.notification_center_product_capacity_internal(v_product_id);
    PERFORM public.enqueue_wallet_scope_internal(v_occasion_id);
    RETURN v_product_id;

  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.update_product_internal_v1(jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.update_product(p_input jsonb)
RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 RETURN (public.update_product_client_sync_v1(p_input,extensions.gen_random_uuid())->'data'->>'productId')::bigint;
END $$;
REVOKE ALL ON FUNCTION public.update_product(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_product(jsonb) TO authenticated;

-- SOURCE: organization/update_organization_admin.sql
CREATE OR REPLACE FUNCTION public.update_organization_admin(
  organization_id bigint,
  title text,
  data jsonb,
  phone_prefixes text[]
)
RETURNS SETOF public.organizations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF update_organization_admin.data ? 'ONESIGNAL_REST_API_KEY' THEN
    RAISE invalid_parameter_value
      USING MESSAGE = 'OneSignal REST API key is managed server-side';
  END IF;

  IF update_organization_admin.data ? 'IS_GOOGLE_LOGIN_ENABLED'
     AND jsonb_typeof(update_organization_admin.data->'IS_GOOGLE_LOGIN_ENABLED') IS DISTINCT FROM 'boolean' THEN
    RAISE invalid_parameter_value USING MESSAGE = 'Google login setting must be boolean';
  END IF;

  IF update_organization_admin.data ? 'FORM_MEASUREMENT_ENABLED'
     AND jsonb_typeof(update_organization_admin.data->'FORM_MEASUREMENT_ENABLED') IS DISTINCT FROM 'boolean' THEN
    RAISE invalid_parameter_value USING MESSAGE = 'Form measurement setting must be boolean';
  END IF;

  -- Verify admin status
  IF public.can_manage_organization_settings(organization_id) THEN
    -- Update the organization record
    RETURN QUERY
    UPDATE organizations
    SET
      title = COALESCE(update_organization_admin.title, organizations.title),
      data = organizations.data || update_organization_admin.data,
      phone_prefixes = COALESCE(
        update_organization_admin.phone_prefixes,
        organizations.phone_prefixes
      )
    WHERE id = organization_id
    RETURNING organizations.id, organizations.created_at,
      organizations.updated_at,
      organizations.data - 'ONESIGNAL_REST_API_KEY',
      organizations.title, organizations.phone_prefixes;

    PERFORM public.enqueue_wallet_scope_internal(NULL,organization_id);

    -- Project the organization switch onto operator-provisioned clients in the
    -- same transaction. Unprovisioned platforms must never become available.
    IF update_organization_admin.data ? 'IS_GOOGLE_LOGIN_ENABLED' THEN
      UPDATE public.external_login_clients c
      SET enabled = c.provisioned AND
          (update_organization_admin.data->>'IS_GOOGLE_LOGIN_ENABLED')::boolean
      WHERE c.organization = organization_id;
    END IF;
  ELSE
    RAISE EXCEPTION 'Access Denied: User is not an admin of this organization.';
  END IF;
END;
$$;

-- SOURCE: others/get_ticket_layout_write_contract_v1.sql
-- Generated by automation/generate_ticket_layout_write_contract.py.
-- A readiness probe, not a write dispatcher or a grant to any new executor.
CREATE OR REPLACE FUNCTION public.get_ticket_layout_write_contract_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ready boolean;
BEGIN
 IF auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.user_info WHERE id=auth.uid()) THEN
  RAISE insufficient_privilege USING MESSAGE='authenticated user required'; END IF;
 SELECT coalesce(bool_and(p.oid IS NOT NULL AND md5(btrim(p.prosrc,E' \n\r\t'))=expected.body_md5
  AND p.prosecdef=expected.definer AND (EXISTS(SELECT 1 FROM unnest(p.proconfig) setting
   WHERE regexp_replace(setting,'[[:space:]]','','g')='search_path=public,extensions')=expected.needs_path)),false)
 INTO ready FROM (VALUES
  ('public.active_membership(boolean,boolean)','2dd31a8b531c745b2ed16af90e0260ea',false,false),
  ('public.administration_navigation_rule(boolean,boolean,boolean,boolean,boolean)','7a9559975e19ae53e8b15a23a4b8b68a',false,false),
  ('public.blueprint_write_rule(boolean,boolean)','0c68680b6879b48966f2bf3bc0210d37',false,false),
  ('public.can_create_occasion(bigint)','f13b39c68d18a53dbb79125c23d7dc23',true,true),
  ('public.can_delete_orders(bigint)','8db8081db5e65a6948f4cefe1b109f93',true,true),
  ('public.can_edit_occasion(bigint,bigint)','af8850fc3a3bed9a06274880669c340d',true,true),
  ('public.can_edit_ticket_layout(bigint)','bb45fdb1e72cd16860e9719c8f9ab84f',true,true),
  ('public.can_edit_ticket_layout_as_actor_internal_v1(uuid,bigint)','f6ee7e318387522f6146e13b3c4854f7',true,true),
  ('public.can_manage_occasion_participants(bigint)','8cb3dd4327ae5c9302da134994dd5d07',true,true),
  ('public.can_manage_unit_users(bigint)','700c32f30396d2bc5bb21553c2f42ca8',true,true),
  ('public.can_preview_ticket_readonly(bigint)','48efb47c1529b5106cbab4edf641fd0a',true,true),
  ('public.can_read_information_editor_bundle(bigint)','ba203be730cbf9acca46c0b3e63363ad',true,true),
  ('public.can_read_map_editor_bundle(bigint)','02c9fbcfcd61c8598e88407a9f3070fa',true,true),
  ('public.can_read_orders(bigint)','795b29c048acb37bc949683bfc586f43',true,true),
  ('public.can_read_ticket_layout(bigint)','50105a20a0ff5d89389f80e5dd9f891c',true,true),
  ('public.can_read_unit_users(bigint)','76b08038f169406ba1ba56652e44608e',true,true),
  ('public.can_write_orders(bigint)','680cbd3862cc0f6abc89d7d2497c7fb1',true,true),
  ('public.can_write_orders_as_actor_internal(uuid,bigint)','064d9d9fe95cfbb62ccbe39efa120a62',false,false),
  ('public.cleaning_crew_navigation_rule(boolean)','30e845096d248f7112e1d570bb489e6a',false,false),
  ('public.client_activity_read_rule(boolean,boolean,boolean)','002ce7bce477126bcdab9e94db022734',false,false),
  ('public.client_commit_read_rule(boolean,boolean,boolean)','229306cbca2f8a160f4d66b2598fc127',false,false),
  ('public.closed_occasion_enrolment_rule(boolean,boolean,boolean,boolean)','9f7f53c36711c06eb5a130dc339b325b',false,false),
  ('public.companion_assignment_rule(boolean,boolean)','7d53e2d7e2196b118c29f85cc90d0ab2',false,false),
  ('public.context_private_access_rule(boolean,boolean,boolean)','a187283398f1802a1b79b46963ff98b6',false,false),
  ('public.demo_own_work_rule(boolean,boolean,boolean,boolean)','3dd99e356714a2005743f678f09f7ae9',false,false),
  ('public.email_template_read_rule(boolean,boolean)','6501d868e3a245da411c8685a6c39406',false,false),
  ('public.email_template_write_rule(boolean,boolean)','ace7a31980f690d9f854ab8c0474ae25',false,false),
  ('public.event_attendance_read_rule(boolean,boolean)','e85f194d54fb7db63b079e5d689de085',false,false),
  ('public.form_authoring_rule(boolean,boolean)','378d42348079d8d5df8ed0d914f5d007',false,false),
  ('public.form_catalog_read_rule(boolean,boolean,boolean)','7a7263f988a28c0272c14f0234b12563',false,false),
  ('public.form_copy_source_rule(boolean,boolean)','0fff049746a86488382290a67c8c9838',false,false),
  ('public.group_assignments_write_rule(boolean,boolean,boolean,boolean)','0221c1b7823f38a4d5afa4abe5e0912f',false,false),
  ('public.group_data_read_rule(boolean,boolean)','a5a4e0f5924790a0c9e68e79bc606a1e',false,false),
  ('public.group_editor_read_rule(boolean,boolean,boolean)','c1fd67eb4de0001ed5aaffb65d36b437',false,false),
  ('public.group_members_read_rule(boolean,boolean,boolean)','c8e7fdf47b08fac95a18ed026d4d07bc',false,false),
  ('public.group_members_write_rule(boolean,boolean)','46f6cef5344290b2caf0182185c3ce4e',false,false),
  ('public.group_places_read_rule(boolean,boolean,boolean,boolean,boolean,boolean)','937805bab351b685970512e7f5e6f285',false,false),
  ('public.group_write_rule(boolean,boolean,boolean)','3dd26a325ee3dd2e391136570cbc5f60',false,false),
  ('public.inventory_copy_target_rule(boolean,boolean)','604bd24712dc418a35616de6d38e0578',false,false),
  ('public.map_editor_read_rule(boolean,boolean)','3f4dc9022d50562b6a48d6e46b0c5928',false,false),
  ('public.merge_ticket_appearance_internal_v1(bigint,jsonb,jsonb)','337628341725ae78a7c14a130a0fe7a4',false,true),
  ('public.merge_ticket_layout_features(jsonb,jsonb,jsonb,boolean)','d8c6d2e6a64880af2fa1e5553dbf85f5',false,true),
  ('public.news_data_read_rule(boolean,boolean,boolean,boolean,boolean,boolean)','f68f00938a5a8efee47af7edc0062f94',false,false),
  ('public.occasion_commit_read_rule(boolean,boolean)','f85d72057735264187b467f21764e2d9',false,false),
  ('public.occasion_context_read_rule(boolean,boolean,boolean)','b54f8cf02bc1580acba23e2497d1cc9f',false,false),
  ('public.occasion_create_rule(boolean,boolean)','faa2f799767b4c9edb52c58944b4a66b',false,false),
  ('public.occasion_directory_read_rule(boolean,boolean)','d4937332739a00292987baae5b876b2b',false,false),
  ('public.occasion_edit_rule(boolean,boolean)','1d4987935db34cc6011f633ef3f6f291',false,false),
  ('public.occasion_editor_read_rule(boolean,boolean,boolean)','1702aa0f9d1003c29f02ef70a017dee6',false,false),
  ('public.occasion_list_read_rule(boolean,boolean)','7ecb040f0c43bb540a15e2ab868ac31e',false,false),
  ('public.occasion_media_upload_rule(boolean,boolean)','ace7a31980f690d9f854ab8c0474ae25',false,false),
  ('public.occasion_staff_navigation_rule(boolean,boolean,boolean,boolean,boolean)','6c7cfeabfb173e0283543f575272d4d8',false,false),
  ('public.occasion_users_write_rule(boolean,boolean,boolean)','2a1ee1bc8a910030a6010ff778df7bc4',false,false),
  ('public.operator_occasion_discovery_rule(boolean,boolean,boolean,boolean,boolean,boolean,boolean)','939699b1b32832f4e2ad0c3af5f22210',false,false),
  ('public.order_delete_rule(boolean,boolean,boolean)','6fdbd70c92f774e10d2be6e0e30eb219',false,false),
  ('public.order_editor_membership_as_actor_internal(uuid,bigint)','aa05414eef3f73d8792cdaaa22023c39',false,false),
  ('public.order_read_rule(boolean,boolean,boolean)','d8acd43d69e2797bbd63063512eb4e69',false,false),
  ('public.order_write_rule(boolean,boolean)','4dd2fa01cd16e5c36983aa7aeb280d3f',false,false),
  ('public.participant_contacts_read_rule(boolean,boolean,boolean)','c371f5c035213b1fd9c8a5f15ba3c6e3',false,false),
  ('public.participant_manage_rule(boolean,boolean)','2ddebfa1df2bdd7becf910d5b619a3c0',false,false),
  ('public.place_move_rule(boolean,boolean,boolean,boolean)','73f870eaea9c56088435b4d80cbf5315',false,false),
  ('public.public_publication_actor_rule(boolean,boolean,boolean)','47ad63e39013d34b5a4105a18f04457d',false,false),
  ('public.readable_membership(boolean,boolean,boolean)','057c3a891e1c41c9b77dc8af67983e20',false,false),
  ('public.reception_enabled(jsonb)','0844ea35e4e7bfad821b8f09f81e8fbb',false,false),
  ('public.reception_use_rule(boolean,boolean,boolean,boolean)','99350a72fb204f5160cb72714b85882c',false,false),
  ('public.reviewed_blueprint_write_rule(boolean,boolean,boolean,boolean)','53eb537fe636ad48274e61bafb683e4a',false,false),
  ('public.save_occasion_client_sync_v1(bigint,uuid,bigint,jsonb)','56bf52d069b80a2ffa254509afdaa5a1',true,true),
  ('public.save_occasion_domain_command_internal_v1(bigint,uuid,bigint,jsonb)','4a2bacea00089021e673b0ef3fd67237',true,true),
  ('public.save_occasion_legacy_facade_internal_v1(jsonb)','eda19f32835616334b3adc0f4d2cd2f6',true,true),
  ('public.scanner_settings_rule(boolean,boolean,boolean)','2b1717b65933cede78c39b44f5d6230d',false,false),
  ('public.schedule_entry_navigation_rule(boolean)','f0258b7a3cc8e3a024dee1a96d34d407',false,false),
  ('public.schedule_feedback_read_rule(boolean,boolean)','a546bbfc24dce06e231e832a11ddb4b4',false,false),
  ('public.schedule_participants_read_rule(boolean,boolean,boolean)','7f6977ddb21f0e2044e154b4428275d1',false,false),
  ('public.ticket_delivery_mode(jsonb)','c2590b2701840fc3cba0df9e8d0359cd',false,true),
  ('public.ticket_layout_rule(boolean,boolean)','8bc8e0cd6a5a45d10d57f79cec655768',false,false),
  ('public.ticket_layout_uses_product_type(bigint,bigint)','dddc7962230734dd5835601b455d8bb4',false,true),
  ('public.ticket_wallet_enabled(jsonb)','ccbb73fd52b030315763e2be50b8e7a7',false,true),
  ('public.ticket_wallet_fingerprint(bigint)','b925aa31ec85daa749b9be964813dfbd',true,true),
  ('public.ticket_wallet_ready(bigint)','d1827ba2afea0b03bf617631d00c9515',true,true),
  ('public.unit_abuse_policy_read_rule(boolean,boolean)','42fc89183ec978eccce36173bc6c3a50',false,false),
  ('public.unit_discovery_rule(boolean,boolean,boolean)','d49526989a25babf6f7ca9ba34b3061c',false,false),
  ('public.unit_landing_read_rule(boolean,boolean,boolean,boolean)','14e7808464b1206a6842240b8db567ff',false,false),
  ('public.unit_legal_profile_read_rule(boolean,boolean)','f85d72057735264187b467f21764e2d9',false,false),
  ('public.unit_template_read_rule(boolean,boolean,boolean)','a22a3f456bfac47bcc58b72c2ec5f75f',false,false),
  ('public.unit_users_read_rule(boolean,boolean,boolean)','a7131760aa20a35fa57d63f718037a34',false,false),
  ('public.unit_workspace_navigation_rule(boolean,boolean,boolean,boolean)','5ba3417d0406073b8ce9421770304558',false,false),
  ('public.update_occasion(jsonb)','0425e6f46c20d2c30a2ffd054619b2b0',true,true),
  ('public.update_occasion_182(jsonb)','bdcda71506ac0abb50a466bb18eb1cc7',true,true),
  ('public.update_occasion_203(jsonb)','916b23b47758d87e478b3b7d84a50ee2',true,true),
  ('public.update_occasion_internal_v1(jsonb)','19ef5dae0f946b65406440e82703e2cd',true,true),
  ('public.validate_ticket_layout(jsonb)','53d7703a06dbde87349a0ac04e50cd54',false,true),
  ('public.validate_ticket_layout_references(bigint,jsonb)','aad01d93c9f0a7035efa243caa3d5a20',false,true),
  ('public.validate_ticket_wallet_appearance(jsonb)','bdcc55cb2a986056fbae005acee1990c',false,true)
 ) expected(signature,body_md5,definer,needs_path)
 LEFT JOIN pg_proc p ON p.oid=to_regprocedure(expected.signature);
 ready:=ready AND NOT EXISTS(
  SELECT 1 FROM (VALUES('authenticated'),('anon')) actor(role_name)
  WHERE has_table_privilege(actor.role_name,'public.occasions','INSERT,UPDATE,DELETE,TRUNCATE')
   OR has_any_column_privilege(actor.role_name,'public.occasions','INSERT,UPDATE'))
 AND NOT EXISTS(SELECT 1 FROM (VALUES
  ('public.update_occasion_internal_v1(jsonb)'),
  ('public.save_occasion_domain_command_internal_v1(bigint,uuid,bigint,jsonb)'),
  ('public.save_occasion_legacy_facade_internal_v1(jsonb)')
 ) private(signature) WHERE has_function_privilege('authenticated',to_regprocedure(private.signature),'EXECUTE'))
 AND NOT EXISTS(SELECT 1 FROM (VALUES
  ('public.update_occasion(jsonb)'),('public.update_occasion_203(jsonb)'),('public.update_occasion_182(jsonb)'),
  ('public.save_occasion_client_sync_v1(bigint,uuid,bigint,jsonb)')
 ) boundary(signature) WHERE NOT has_function_privilege('authenticated',to_regprocedure(boundary.signature),'EXECUTE')
 OR has_function_privilege('anon',to_regprocedure(boundary.signature),'EXECUTE'));
 RETURN jsonb_build_object('family','ticket_layouts','contractVersion',1,'ready',coalesce(ready,false));
END $$;
REVOKE ALL ON FUNCTION public.get_ticket_layout_write_contract_v1() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_ticket_layout_write_contract_v1() TO authenticated;

-- SOURCE: others/delete_occasion.sql
CREATE OR REPLACE FUNCTION public.delete_occasion_internal_v1(oc bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    unit_id BIGINT;
BEGIN
  PERFORM public.check_occasion_writable(oc);

  SELECT unit
  INTO unit_id
  FROM public.occasions
  WHERE id = oc;

  IF NOT public.can_delete_occasion_in_unit(unit_id) THEN RAISE EXCEPTION 'User is not manager.'; END IF;

  PERFORM public.notification_center_initialized_internal((SELECT organization FROM public.occasions WHERE id=oc));

-- ***********************************************************
  -- 0. SAFETY CHECK: Strict Order Check
  --    Prevent deletion if ANY order exists (even storno).
  -- ***********************************************************
  IF EXISTS (
      SELECT 1
      FROM eshop.orders
      WHERE occasion = oc
  ) THEN
      RAISE EXCEPTION 'Cannot delete occasion % because it contains orders (including storno).', oc;
  END IF;

  -- ***********************************************************
  -- 1. Delete records that depend on 'events'.
  -- ***********************************************************
  PERFORM public.lock_blueprint_scope_internal(ARRAY[oc]);
  DELETE FROM public.scanner_settings WHERE occasion_id=oc;

  DELETE FROM public.event_groups
    WHERE event_parent IN (SELECT id FROM public.events WHERE occasion = oc)
       OR event_child  IN (SELECT id FROM public.events WHERE occasion = oc);

  DELETE FROM public.event_roles
    WHERE event IN (SELECT id FROM public.events WHERE occasion = oc);

  DELETE FROM public.event_users
    WHERE event IN (SELECT id FROM public.events WHERE occasion = oc);

  DELETE FROM public.event_users_saved
    WHERE event IN (SELECT id FROM public.events WHERE occasion = oc);

  DELETE FROM public.exclusive_events
    WHERE event IN (SELECT id FROM public.events WHERE occasion = oc);

  -- ***********************************************************
  -- 2. Delete the 'events' themselves.
  -- ***********************************************************
  DELETE FROM public.events
    WHERE occasion = oc;

  -- ***********************************************************
  -- 3. Delete 'orders' dependent records.
  -- ***********************************************************
  DELETE FROM eshop.order_product_ticket
    WHERE "order" IN (SELECT id FROM eshop.orders WHERE occasion = oc);

  DELETE FROM eshop.orders_history
    WHERE "order" IN (SELECT id FROM eshop.orders WHERE occasion = oc);

  DELETE FROM eshop.bank_account_requests
    WHERE "order" IN (SELECT id FROM eshop.orders WHERE occasion = oc);

  -- ***********************************************************
  -- 4. Delete form-related records.
  -- ***********************************************************
  DELETE FROM public.form_fields
    WHERE form IN (SELECT id FROM public.forms WHERE occasion = oc);

  DELETE FROM public.notification_center_source_state WHERE source_key LIKE 'form-availability:%'
    AND (state->>'formId')::bigint IN (SELECT id FROM public.forms WHERE occasion=oc);
  DELETE FROM public.forms
    WHERE occasion = oc;

  -- ***********************************************************
  -- 5. Delete records from tables that reference the occasion directly.
  -- ***********************************************************
  DELETE FROM public.email_templates
    WHERE occasion = oc;

  DELETE FROM public.email_wrappers
    WHERE occasion = oc;

  DELETE FROM public.information
    WHERE occasion = oc;

  DELETE FROM public.information_hidden
    WHERE occasion = oc;

  DELETE FROM public.log_notifications
    WHERE occasion = oc;

  UPDATE public.email_messages SET workflow_state='cancelled',last_error='occasion_deleted',data='{}',prepared=NULL,recipient=NULL,occasion=NULL,unit=NULL
    WHERE occasion = oc;

  DELETE FROM public.log_emails
    WHERE occasion = oc;

  DELETE FROM public.news
    WHERE occasion = oc;

  DELETE FROM public.occasion_users
    WHERE occasion = oc;

  DELETE FROM public.user_news
    WHERE occasion = oc;

  -- Resources can reference places and own slots referenced by copied spots.
  -- Remove them before places; slot references detach through their FK rules.
  DELETE FROM public.resources
    WHERE occasion = oc OR inventory_pool IN (
      SELECT id FROM public.inventory_pools WHERE occasion = oc);

  DELETE FROM public.places
    WHERE occasion = oc;

  DELETE FROM public.role_info
    WHERE occasion = oc;

  DELETE FROM public.user_groups
    WHERE "group" IN (SELECT id FROM public.user_group_info WHERE occasion = oc);

  DELETE FROM public.user_group_info
    WHERE occasion = oc;

  DELETE FROM public.exclusive_groups
    WHERE occasion = oc;

  -- ***********************************************************
  -- 6. Delete remaining records from the eshop schema.
  -- ***********************************************************
  PERFORM public.enqueue_wallet_scope_internal(oc);
  DELETE FROM eshop.tickets
    WHERE occasion = oc;

  -- Configuration bindings depend on seats/products as well as their plan.
  DELETE FROM eshop.blueprint_seat_bindings WHERE blueprint IN (SELECT id FROM eshop.blueprints WHERE occasion=oc);
  DELETE FROM eshop.blueprint_group_products WHERE blueprint IN (SELECT id FROM eshop.blueprints WHERE occasion=oc);
  DELETE FROM eshop.blueprint_area_bindings WHERE blueprint IN (SELECT id FROM eshop.blueprints WHERE occasion=oc);

  DELETE FROM eshop.spots
    WHERE occasion = oc;

  DELETE FROM eshop.products
    WHERE occasion = oc;

  DELETE FROM eshop.product_types
    WHERE occasion = oc;

  DELETE FROM eshop.planned_changes
    WHERE occasion = oc;

  DELETE FROM eshop.bank_account_requests
    WHERE occasion = oc;


  DELETE FROM eshop.blueprints
    WHERE occasion = oc;

  -- Blueprint area bindings and product mappings no longer retain contexts.
  DELETE FROM public.inventory_contexts
    WHERE inventory_pool IN (SELECT id FROM public.inventory_pools WHERE occasion = oc);
  DELETE FROM public.inventory_pools
    WHERE occasion = oc;

  -- Delete orders (Safe now: we checked for non-storno orders at step 0,
  -- and deleted dependents in step 3).
  DELETE FROM eshop.orders
    WHERE occasion = oc;

  -- ***********************************************************
  -- 7. Null out referencing images.
  -- ***********************************************************
  UPDATE public.images
    SET occasion = NULL
    WHERE occasion = oc;

  -- ***********************************************************
  -- 8. Finally, delete the occasion itself.
  -- ***********************************************************
  DELETE FROM public.occasions
    WHERE id = oc;

  RETURN;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_occasion_internal_v1(bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.delete_occasion(oc bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path=public,extensions
AS $function$
BEGIN
  PERFORM public.delete_occasion_client_sync_v1(oc,extensions.gen_random_uuid());
END; $function$
;
REVOKE ALL ON FUNCTION public.delete_occasion(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.delete_occasion(bigint) TO authenticated;

-- SOURCE: blueprint/seating_assignment.sql
-- Public adapters verify organizer authority; this private seam owns exact scope.
CREATE OR REPLACE FUNCTION public.seating_assignment_scope_internal(p_blueprint bigint,p_mappings jsonb)
RETURNS eshop.blueprints LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE tr eshop.blueprints; v_mapping jsonb;
BEGIN
 SELECT * INTO tr FROM eshop.blueprints WHERE id=p_blueprint;
 IF tr.id IS NULL OR NOT public.can_assign_existing_admissions(tr.occasion) THEN RAISE insufficient_privilege USING MESSAGE='order reader and writer required'; END IF;
 IF tr.layout->>'schemaVersion' IS DISTINCT FROM '2' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_LAYOUT_MIGRATION_REQUIRED'; END IF;
 IF jsonb_typeof(p_mappings) IS DISTINCT FROM 'array' OR jsonb_array_length(p_mappings) NOT BETWEEN 1 AND least(256,(SELECT hard_cap FROM public.abuse_policy_rules WHERE rule_key='order.mutation.items')) OR octet_length(p_mappings::text)>131072 THEN
 RAISE invalid_parameter_value USING MESSAGE='invalid assignment batch'; END IF;
 FOR v_mapping IN SELECT value FROM jsonb_array_elements(p_mappings) LOOP
 IF jsonb_typeof(v_mapping) IS DISTINCT FROM 'object' OR NOT v_mapping ?& ARRAY['ticketId','admissionItemId','expectedSpotId','targetSpotId']
 OR EXISTS(SELECT 1 FROM jsonb_object_keys(v_mapping) k WHERE k NOT IN ('ticketId','admissionItemId','expectedSpotId','targetSpotId'))
 OR v_mapping->>'ticketId' IS NULL OR v_mapping->>'admissionItemId' IS NULL THEN
 RAISE invalid_parameter_value USING MESSAGE='exact changed item mapping required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM eshop.order_product_ticket i JOIN eshop.orders o ON o.id=i."order"
 JOIN public.blueprint_seating_sources_internal(tr.id) source ON source.form_id=o.form
 WHERE i.id=(v_mapping->>'admissionItemId')::bigint AND i.ticket=(v_mapping->>'ticketId')::bigint AND o.occasion=tr.occasion)
 OR EXISTS(SELECT 1 FROM eshop.spots WHERE id IN ((v_mapping->>'expectedSpotId')::bigint,(v_mapping->>'targetSpotId')::bigint) AND (occasion<>tr.occasion OR blueprint IS DISTINCT FROM tr.id)) THEN
 RAISE insufficient_privilege USING MESSAGE='assignment context unavailable'; END IF;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_mappings) m WHERE m->'expectedSpotId' IS DISTINCT FROM m->'targetSpotId') THEN
 RAISE invalid_parameter_value USING MESSAGE='changed assignment batch required'; END IF;
 IF (SELECT count(DISTINCT value->>'admissionItemId') FROM jsonb_array_elements(p_mappings))<>jsonb_array_length(p_mappings)
 OR (SELECT count(*) FROM jsonb_array_elements(p_mappings) WHERE value->>'targetSpotId' IS NOT NULL)<>(SELECT count(DISTINCT value->>'targetSpotId') FROM jsonb_array_elements(p_mappings)) THEN
 RAISE invalid_parameter_value USING MESSAGE='duplicate assignment identity'; END IF;
 RETURN tr;
END $$;
REVOKE ALL ON FUNCTION public.seating_assignment_scope_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.seating_assignment_preview_internal(p_blueprint bigint,p_mappings jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE tr eshop.blueprints; v_mapping jsonb; a record; v_spot eshop.spots; why text; blockers jsonb:='[]'; mappings jsonb:='[]'; revisions jsonb; semantic jsonb; affected bigint[]; ids bigint[]; before_ids bigint[]; target_ids bigint[]; rev bigint;
BEGIN
 tr:=public.seating_assignment_scope_internal(p_blueprint,p_mappings);
 SELECT layout_revision INTO rev FROM eshop.blueprints WHERE id=tr.id;
 SELECT ARRAY(SELECT DISTINCT v FROM jsonb_array_elements(p_mappings) m CROSS JOIN LATERAL unnest(ARRAY[(m->>'expectedSpotId')::bigint,(m->>'targetSpotId')::bigint]) v WHERE v IS NOT NULL ORDER BY v) INTO ids;
 SELECT ARRAY(SELECT DISTINCT member FROM unnest(ids) id CROSS JOIN LATERAL unnest(public.blueprint_selection_unit_spots_internal(id)) member ORDER BY member) INTO affected;
 -- Each side independently covers its complete units. A single item moving
 -- between two members cannot count as the two purchased couch admissions.
 SELECT ARRAY(SELECT (m->>'expectedSpotId')::bigint FROM jsonb_array_elements(p_mappings)m WHERE m->>'expectedSpotId' IS NOT NULL),
 ARRAY(SELECT (m->>'targetSpotId')::bigint FROM jsonb_array_elements(p_mappings)m WHERE m->>'targetSpotId' IS NOT NULL)
 INTO before_ids,target_ids;
 IF EXISTS(SELECT 1 FROM unnest(before_ids) requested CROSS JOIN LATERAL unnest(public.blueprint_selection_unit_spots_internal(requested)) member WHERE NOT member=ANY(before_ids))
 OR EXISTS(SELECT 1 FROM unnest(target_ids) requested CROSS JOIN LATERAL unnest(public.blueprint_selection_unit_spots_internal(requested)) member WHERE NOT member=ANY(target_ids)) THEN
 blockers:=blockers||jsonb_build_array(jsonb_build_object('reason','ATOMIC_UNIT_INCOMPLETE')); END IF;
 FOR v_mapping IN SELECT value FROM jsonb_array_elements(p_mappings) ORDER BY (value->>'admissionItemId')::bigint LOOP
 SELECT * INTO a FROM public.seating_admissions_internal(p_blueprint) WHERE ticket_id=(v_mapping->>'ticketId')::bigint AND item_id=(v_mapping->>'admissionItemId')::bigint;
 why:=NULL;
 IF NOT FOUND THEN why:='ADMISSION_DATA_AMBIGUOUS';
 ELSIF a.category NOT IN ('assigned','unassigned') THEN why:=coalesce(a.reason,'MODE_CHANGED');
 ELSIF EXISTS(SELECT 1 FROM eshop.tickets WHERE id=a.ticket_id AND state='used') THEN why:='USED_TICKET_PROTECTED';
 ELSIF EXISTS(SELECT 1 FROM eshop.ticket_batch_items WHERE ticket_id=a.ticket_id) THEN why:='BATCH_TICKET_PRINT_IMMUTABLE';
 ELSIF a.spot_id IS DISTINCT FROM (v_mapping->>'expectedSpotId')::bigint THEN why:='CONTEXT_CHANGED'; END IF;
 IF why IS NULL AND v_mapping->>'targetSpotId' IS NOT NULL THEN
 SELECT * INTO v_spot FROM eshop.spots WHERE id=(v_mapping->>'targetSpotId')::bigint;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM eshop.blueprint_seat_bindings WHERE blueprint=tr.id AND spot=v_spot.id AND NOT blocked) THEN why:='SEAT_UNAVAILABLE';
 ELSIF v_spot.product IS DISTINCT FROM a.product_id THEN why:='PRODUCT_MISMATCH';
 ELSIF v_spot.order_product_ticket IS NOT NULL AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_mappings) other WHERE (other->>'admissionItemId')::bigint=v_spot.order_product_ticket AND (other->>'expectedSpotId')::bigint=v_spot.id) THEN why:='SEAT_UNAVAILABLE';
 ELSIF v_spot.secret IS NOT NULL AND v_spot.secret_expiration_time>clock_timestamp() THEN why:='HOLD_ACTIVE';
 ELSIF v_spot.inventory_context IS NOT NULL AND NOT EXISTS(SELECT 1 FROM eshop.product_inventory_contexts WHERE product=a.product_id AND inventory_context=v_spot.inventory_context) THEN why:='INVENTORY_CONFLICT'; END IF;
 END IF;
 IF why IS NOT NULL THEN blockers:=blockers||jsonb_build_array(jsonb_build_object('reason',why,'ticketId',v_mapping->'ticketId','spotId',v_mapping->'targetSpotId')); END IF;
 mappings:=mappings||jsonb_build_array(v_mapping||jsonb_build_object('formId',a.form_id,'productId',a.product_id));
 END LOOP;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'revision',t.capacity_revision) ORDER BY t.id),'[]') INTO revisions
 FROM public.forms t WHERE t.id IN (SELECT (m->>'formId')::bigint FROM jsonb_array_elements(mappings) m);
 semantic:=jsonb_build_object('mappings',mappings,'revisions',revisions,'layoutRevision',rev,'blockers',blockers,
 'seats',(SELECT jsonb_agg(to_jsonb(s)-'updated_at'-'created_at' ORDER BY s.id) FROM eshop.spots s WHERE s.id=ANY(affected)),
 'bindings',(SELECT jsonb_agg(to_jsonb(sb) ORDER BY sb.spot) FROM eshop.blueprint_seat_bindings sb WHERE sb.spot=ANY(affected)),
 'admissions',(SELECT jsonb_agg(jsonb_build_object('item',to_jsonb(i),'ticket',to_jsonb(t)-'updated_at','order',to_jsonb(o)-'updated_at','payment',to_jsonb(pi)) ORDER BY i.id)
 FROM eshop.order_product_ticket i JOIN eshop.tickets t ON t.id=i.ticket JOIN eshop.orders o ON o.id=i."order" LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE i.id IN (SELECT (m->>'admissionItemId')::bigint FROM jsonb_array_elements(p_mappings)m)),
 'allocations',(SELECT jsonb_agg(jsonb_build_array(s.id,s.inventory_context,s.resource,s.resource_slot,s.order_product_ticket) ORDER BY s.id) FROM eshop.spots s WHERE s.order_product_ticket IN(SELECT (m->>'admissionItemId')::bigint FROM jsonb_array_elements(p_mappings)m)),
 'requirements',(SELECT jsonb_agg(to_jsonb(pic) ORDER BY pic.product,pic.inventory_context) FROM eshop.product_inventory_contexts pic WHERE product IN(SELECT (m->>'productId')::bigint FROM jsonb_array_elements(mappings)m)));
 RETURN jsonb_build_object('fingerprint',encode(extensions.digest(semantic::text,'sha256'),'hex'),'revisions',revisions,'mappings',mappings,'blockers',blockers,'layoutRevision',rev);
END $$;
REVOKE ALL ON FUNCTION public.seating_assignment_preview_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.preview_ticket_seat_assignment(p_blueprint bigint,p_mappings jsonb)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('code',200,'data',public.seating_assignment_preview_internal(p_blueprint,p_mappings))
$$;
REVOKE ALL ON FUNCTION public.preview_ticket_seat_assignment(bigint,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.preview_ticket_seat_assignment(bigint,jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_ticket_seat_assignments(p_blueprint bigint,p_mappings jsonb,p_fingerprint text,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE tr eshop.blueprints; started jsonb; preview jsonb; v_orders bigint[]; v_items bigint[]; v_spots bigint[]; v_products bigint[]; v_mapping jsonb; dest eshop.spots; required integer; occupied integer; spare bigint; oid bigint; touched bigint[];
BEGIN
 SELECT * INTO tr FROM eshop.blueprints WHERE id=p_blueprint;
 IF tr.id IS NULL OR NOT public.can_assign_existing_admissions(tr.occasion) THEN RAISE insufficient_privilege USING MESSAGE='order reader and writer required'; END IF;
 IF tr.layout->>'schemaVersion' IS DISTINCT FROM '2' THEN RAISE check_violation USING MESSAGE='BLUEPRINT_LAYOUT_MIGRATION_REQUIRED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.client_mutation_receipts WHERE command_id=p_command_id AND actor_id=auth.uid() AND command_name='seating.assignment.set') THEN
 tr:=public.seating_assignment_scope_internal(p_blueprint,p_mappings); END IF;
 PERFORM public.lock_blueprint_scope_internal(ARRAY[tr.occasion]);
 started:=public.begin_client_mutation_v1(p_command_id,'seating.assignment.set',tr.occasion,auth.uid(),encode(extensions.digest(jsonb_build_array(p_blueprint,p_mappings,p_fingerprint)::text,'sha256'),'hex'));
 IF NOT public.can_assign_existing_admissions(tr.occasion) THEN RAISE insufficient_privilege USING MESSAGE='order reader and writer required'; END IF;
 IF started->>'disposition'='replay' THEN RETURN started->'response'; END IF;
 tr:=public.seating_assignment_scope_internal(p_blueprint,p_mappings);
 PERFORM public.admit_order_mutation_v1(tr.occasion,jsonb_array_length(p_mappings));
 SELECT ARRAY(SELECT (m->>'admissionItemId')::bigint FROM jsonb_array_elements(p_mappings)m ORDER BY 1) INTO v_items;
 SELECT array_agg(DISTINCT "order" ORDER BY "order"),array_agg(DISTINCT product ORDER BY product) INTO v_orders,v_products FROM eshop.order_product_ticket WHERE id=ANY(v_items);
 PERFORM 1 FROM public.forms WHERE id IN(SELECT form FROM eshop.orders WHERE id=ANY(v_orders)) ORDER BY id FOR UPDATE;
 -- Lock union of before/after units and all allocation parents before children.
 SELECT ARRAY(SELECT DISTINCT s.id FROM eshop.spots s WHERE s.order_product_ticket=ANY(v_items)
 OR s.inventory_context IN(SELECT inventory_context FROM eshop.product_inventory_contexts WHERE product=ANY(v_products))
 OR s.id IN(SELECT member FROM jsonb_array_elements(p_mappings)m CROSS JOIN LATERAL unnest(ARRAY[(m->>'expectedSpotId')::bigint,(m->>'targetSpotId')::bigint]) id CROSS JOIN LATERAL unnest(public.blueprint_selection_unit_spots_internal(id)) member) ORDER BY s.id) INTO v_spots;
 PERFORM public.lock_spot_assignment_scope_internal(v_spots,'{}',true,v_products,false,v_orders,v_items);
 tr:=public.seating_assignment_scope_internal(p_blueprint,p_mappings);
 preview:=public.seating_assignment_preview_internal(p_blueprint,p_mappings);
 IF jsonb_array_length(preview->'blockers')>0 OR preview->>'fingerprint' IS DISTINCT FROM p_fingerprint THEN
 RETURN public.complete_client_mutation_outcome_v1(p_command_id,'conflict',409,jsonb_build_object('reason',CASE WHEN jsonb_array_length(preview->'blockers')>0 THEN preview#>>'{blockers,0,reason}' ELSE 'CONTEXT_CHANGED' END,'blockers',preview->'blockers')); END IF;
 -- Remove only explicitly reviewed before associations, preserving physical resources.
 UPDATE eshop.spots SET order_product_ticket=NULL,state=NULL,updated_at=clock_timestamp()
 WHERE id IN(SELECT (m->>'expectedSpotId')::bigint FROM jsonb_array_elements(p_mappings)m);
 FOR v_mapping IN SELECT value FROM jsonb_array_elements(p_mappings) ORDER BY (value->>'admissionItemId')::bigint LOOP
 IF v_mapping->>'targetSpotId' IS NULL THEN CONTINUE; END IF;
 SELECT * INTO STRICT dest FROM eshop.spots WHERE id=(v_mapping->>'targetSpotId')::bigint;
 IF dest.inventory_context IS NOT NULL THEN
 SELECT quantity INTO required FROM eshop.product_inventory_contexts WHERE product=dest.product AND inventory_context=dest.inventory_context;
 SELECT count(*) INTO occupied FROM eshop.spots WHERE order_product_ticket=(v_mapping->>'admissionItemId')::bigint AND inventory_context=dest.inventory_context;
 IF occupied>=required THEN
 SELECT id INTO spare FROM eshop.spots WHERE order_product_ticket=(v_mapping->>'admissionItemId')::bigint AND inventory_context=dest.inventory_context AND blueprint IS NULL ORDER BY id LIMIT 1;
 IF spare IS NULL THEN RAISE EXCEPTION 'INVENTORY_CONFLICT'; END IF;
 UPDATE eshop.spots SET order_product_ticket=NULL,state=NULL,resource=NULL,updated_at=clock_timestamp() WHERE id=spare;
 END IF;
 END IF;
 UPDATE eshop.spots SET order_product_ticket=(v_mapping->>'admissionItemId')::bigint,state='ordered',secret=NULL,secret_expiration_time=NULL,updated_at=clock_timestamp() WHERE id=dest.id;
 END LOOP;
 FOREACH oid IN ARRAY v_orders LOOP PERFORM public.apply_allocations(oid); END LOOP;
 IF EXISTS(SELECT 1 FROM eshop.order_product_ticket i JOIN eshop.product_inventory_contexts pic ON pic.product=i.product WHERE i.id=ANY(v_items) AND
 (SELECT count(*) FROM eshop.spots WHERE order_product_ticket=i.id AND inventory_context=pic.inventory_context)<>pic.quantity) THEN RAISE EXCEPTION 'INVENTORY_CONFLICT'; END IF;
 UPDATE public.forms SET capacity_revision=capacity_revision+1 WHERE id IN(SELECT form FROM eshop.orders WHERE id=ANY(v_orders));
 PERFORM public.enqueue_ticket_wallet_internal(ARRAY(SELECT DISTINCT ticket FROM eshop.order_product_ticket WHERE id=ANY(v_items) ORDER BY ticket));
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,tr.occasion,'seating.assignment.set',
 jsonb_build_array(jsonb_build_object('entityType','blueprint','entityId',tr.id,'operation','update','safeLabel','Admission placement','changedFields',jsonb_build_array('seating'))),
 ARRAY(SELECT "user" FROM public.occasion_users WHERE occasion=tr.occasion),jsonb_build_object('blueprintId',tr.id,'mappings',preview->'mappings','context',public.get_blueprint_seating_context(tr.id)->'data'));
END $$;
REVOKE ALL ON FUNCTION public.set_ticket_seat_assignments(bigint,jsonb,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_ticket_seat_assignments(bigint,jsonb,text,uuid) TO authenticated;
