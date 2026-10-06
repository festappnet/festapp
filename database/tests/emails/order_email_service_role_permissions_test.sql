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
  INSERT INTO eshop.orders(order_symbol, occasion, state, data, price, currency_code)
  VALUES (public.generate_order_symbol(), v_occ, 'storno', '{"email":"storno@example.invalid"}', 0, 'CZK')
  RETURNING id INTO v_order;
  INSERT INTO eshop.orders(order_symbol, occasion, state, data, price, currency_code, payment_info)
  VALUES (public.generate_order_symbol(), v_occ, 'ordered', '{"email":"update@example.invalid"}', 100, 'CZK', v_payment)
  RETURNING id INTO v_update_order;
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
BEGIN
  FOREACH v_code IN ARRAY ARRAY[
    'TICKET_ORDER_STORNO', 'TICKET_ORDER_UPDATE', 'TICKET_ORDER_CONFIRMATION',
    'TICKET_ORDER_PAYMENT_DONE', 'TICKET_ORDER_REMINDER', 'ORDER_TICKETS'
  ] LOOP
    v_order_id := (v_fixture->>CASE WHEN v_code = 'TICKET_ORDER_STORNO' THEN 'order' ELSE 'update_order' END)::bigint;
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
