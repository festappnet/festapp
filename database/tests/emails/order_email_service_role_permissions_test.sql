BEGIN;

-- No real delivery: the worker remains paused and every fixture rolls back.
UPDATE public.email_capacity SET paused = true, worker_url = NULL;

DO $$
DECLARE
  v_org bigint;
  v_unit bigint;
  v_occ bigint;
  v_order bigint;
  v_update_order bigint;
  v_payment bigint;
  v_type bigint;
  v_product bigint;
  v_ticket bigint;
BEGIN
  INSERT INTO public.organizations(title)
    VALUES ('Order email service-role fixture') RETURNING id INTO v_org;
  INSERT INTO public.units(title, organization)
  VALUES ('Fixture unit', v_org) RETURNING id INTO v_unit;
  INSERT INTO public.occasions(title, organization, unit, link, start_time, end_time)
  VALUES ('Fixture occasion', v_org, v_unit, gen_random_uuid()::text, now(), now() + interval '1 day')
  RETURNING id INTO v_occ;
  INSERT INTO eshop.payment_info(id, amount, paid, currency_code)
  VALUES (900000000000 + v_occ, 100, 0, 'CZK') RETURNING id INTO v_payment;
  INSERT INTO eshop.orders(order_sequence, order_symbol, occasion, state, data, price, currency_code)
  VALUES (public.next_order_sequence(v_occ), public.generate_order_symbol(), v_occ, 'storno', '{"email":"storno@example.invalid"}', 0, 'CZK')
  RETURNING id INTO v_order;
  INSERT INTO eshop.orders(order_sequence, order_symbol, occasion, state, data, price, currency_code, payment_info)
  VALUES (public.next_order_sequence(v_occ), public.generate_order_symbol(), v_occ, 'ordered', '{"email":"update@example.invalid"}', 100, 'CZK', v_payment)
  RETURNING id INTO v_update_order;
  -- A real registration order without the optional ticket feature reproduces
  -- the production incident; rendering still projects seating metadata.
  INSERT INTO eshop.product_types(occasion,title,type)
  VALUES(v_occ,'Registration','select_one') RETURNING id INTO v_type;
  INSERT INTO eshop.products(occasion,product_type,title,price,currency_code)
  VALUES(v_occ,v_type,'Registration',100,'CZK') RETURNING id INTO v_product;
  INSERT INTO eshop.tickets(occasion,state,ticket_symbol)
  VALUES(v_occ,'paid',public.generate_ticket_symbol(v_org,v_occ)) RETURNING id INTO v_ticket;
  INSERT INTO eshop.order_product_ticket("order",product,ticket)
  VALUES(v_update_order,v_product,v_ticket);
  PERFORM set_config('festapp.storno_fixture', jsonb_build_object(
    'organization', v_org, 'unit', v_unit, 'occasion', v_occ, 'order', v_order, 'update_order', v_update_order
  )::text, true);
END;
$$;

SET LOCAL ROLE service_role;
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);

DO $$
DECLARE
  v_fixture jsonb := current_setting('festapp.storno_fixture')::jsonb;
  v_result jsonb;
  v_replay jsonb;
  v_code text;
  v_order_id bigint;
  v_details jsonb;
  v_template jsonb;
  v_secret text;
BEGIN
  FOREACH v_code IN ARRAY ARRAY[
    'TICKET_ORDER_STORNO', 'TICKET_ORDER_UPDATE', 'TICKET_ORDER_CONFIRMATION',
    'TICKET_ORDER_PAYMENT_DONE', 'TICKET_ORDER_REMINDER', 'ORDER_TICKETS'
  ] LOOP
    v_order_id := (v_fixture->>CASE WHEN v_code = 'TICKET_ORDER_STORNO' THEN 'order' ELSE 'update_order' END)::bigint;
    -- These invoker RPCs are the actual worker preparation boundary. Merely
    -- enqueueing as service_role does not detect missing renderer table grants.
    IF current_user<>'service_role' THEN RAISE EXCEPTION 'Test must use the runtime role'; END IF;
    v_details:=public.get_order_details_for_email(v_order_id);
    IF v_details->>'code'<>'200' OR (v_details#>>'{data,order,id}')::bigint<>v_order_id THEN
      RAISE EXCEPTION 'Renderer cannot read order for %',v_code;
    END IF;
    v_template:=public.get_email_template_and_wrapper(
      CASE WHEN v_code='ORDER_TICKETS' THEN 'TICKET_ORDER_PAYMENT_DONE' ELSE v_code END,
      v_fixture-'order'-'update_order');
    IF coalesce(v_template#>>'{template,subject}','')='' OR coalesce(v_template#>>'{template,html}','')='' THEN
      RAISE EXCEPTION 'Renderer cannot resolve template for %',v_code;
    END IF;
    IF v_code<>'TICKET_ORDER_STORNO' AND jsonb_array_length(public.get_tickets_with_details(v_order_id))<>1 THEN
      RAISE EXCEPTION 'Renderer lost admission ticket for %',v_code;
    END IF;
    v_secret:=public.generate_request_secret(120);
    IF NOT public.check_request_secret(v_secret) THEN RAISE EXCEPTION 'Renderer authorization proof failed'; END IF;
    IF public.get_order_email_overview_source_v1(v_order_id,
      v_details#>>'{data,order,data,email}',gen_random_uuid()) IS NOT NULL THEN
      RAISE EXCEPTION 'No public form must produce no overview link';
    END IF;
    v_result := public.enqueue_order_email(
      v_code, jsonb_build_object('order_id', v_order_id),
      (v_fixture->>'organization')::bigint, (v_fixture->>'occasion')::bigint,
      (v_fixture->>'unit')::bigint
    );
    v_replay := public.enqueue_order_email(
      v_code, jsonb_build_object('order_id', v_order_id),
      (v_fixture->>'organization')::bigint, (v_fixture->>'occasion')::bigint,
      (v_fixture->>'unit')::bigint
    );
    IF v_result->>'state' <> 'pending' OR v_result->>'message_id' IS NULL
      OR v_result->>'message_id' <> v_replay->>'message_id' THEN
      RAISE EXCEPTION 'Producer % must enqueue once under its actual runtime role', v_code;
    END IF;
  END LOOP;
END;
$$;

ROLLBACK;
