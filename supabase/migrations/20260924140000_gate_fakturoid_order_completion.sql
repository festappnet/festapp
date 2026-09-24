-- A Fakturoid checkout is not an accepted order until its proforma exists.
-- Keep its confirmation out of the email worker until checkout finalizes it.
CREATE OR REPLACE FUNCTION public.enqueue_ticket_order_confirmation_v1(
  p_command_id uuid, p_occasion bigint, p_order_payload jsonb, p_language text
) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_organization bigint;
  v_unit bigint;
  v_order_id bigint := (p_order_payload#>>'{order,id}')::bigint;
  v_await_fakturoid boolean;
BEGIN
  SELECT o.organization, o.unit INTO v_organization, v_unit
  FROM public.occasions o WHERE o.id = p_occasion;
  IF v_organization IS NULL OR p_command_id IS NULL OR v_order_id IS NULL
     OR p_order_payload IS NULL THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid ticket order effect';
  END IF;
  SELECT (coalesce((p_order_payload#>>'{order,payment_info,amount}')::numeric,0)>0)
    AND EXISTS (SELECT 1 FROM eshop.external_services es
                WHERE es.unit=v_unit AND es.type='FAKTUROID')
  INTO v_await_fakturoid;
  IF v_await_fakturoid THEN
    UPDATE eshop.orders SET state='preparing_payment', updated_at=now()
    WHERE id=v_order_id AND occasion=p_occasion AND state='ordered';
    IF NOT FOUND THEN
      RAISE check_violation USING MESSAGE='Fakturoid order is not ready for preparation';
    END IF;
  END IF;
  INSERT INTO public.queue_emails
    (target_time,code,data,organization,occasion,unit)
  VALUES (CASE WHEN v_await_fakturoid THEN 'infinity'::timestamptz ELSE now() END,
    'TICKET_ORDER_CONFIRMATION',jsonb_build_object(
      'command_id',p_command_id,'ticket_order',p_order_payload,
      'lang',coalesce(nullif(p_language,''),'cs'),
      'fakturoid_pending',v_await_fakturoid),
    v_organization,p_occasion,v_unit)
  ON CONFLICT ((data->>'command_id'))
    WHERE code='TICKET_ORDER_CONFIRMATION' AND data ? 'command_id'
    DO NOTHING;
END;
$$;
REVOKE ALL ON FUNCTION public.enqueue_ticket_order_confirmation_v1(uuid,bigint,jsonb,text)
  FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.get_fakturoid_ticket_order_state_v1(p_order_id bigint)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE v_state text;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  SELECT o.state INTO v_state FROM eshop.orders o WHERE o.id=p_order_id;
  IF v_state IS NULL THEN
    RAISE no_data_found USING MESSAGE='ticket order not found';
  END IF;
  RETURN v_state;
END;
$$;
REVOKE ALL ON FUNCTION public.get_fakturoid_ticket_order_state_v1(bigint)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_fakturoid_ticket_order_state_v1(bigint)
  TO service_role;

CREATE OR REPLACE FUNCTION public.complete_fakturoid_ticket_order_v1(
  p_order_id bigint, p_command_id uuid, p_variable_symbol bigint
) RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_state text;
  v_currency text;
  v_payment_id bigint;
  v_existing_vs bigint;
  v_occasion bigint;
  v_queue_id bigint;
  v_impacts jsonb;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  SELECT o.state,trim(o.currency_code),o.payment_info,o.occasion,pi.variable_symbol
  INTO v_state,v_currency,v_payment_id,v_occasion,v_existing_vs
  FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info
  WHERE o.id=p_order_id FOR UPDATE OF o,pi;
  IF v_state IS NULL OR p_command_id IS NULL OR p_variable_symbol NOT BETWEEN 1 AND 9999999999 THEN
    RAISE invalid_parameter_value USING MESSAGE='invalid Fakturoid completion';
  END IF;
  IF v_state IN ('ordered','paid') THEN
    RETURN v_existing_vs;
  END IF;
  IF v_state<>'preparing_payment' THEN
    RAISE check_violation USING MESSAGE='Fakturoid order is not pending';
  END IF;
  SELECT q.id INTO v_queue_id FROM public.queue_emails q
  WHERE q.code='TICKET_ORDER_CONFIRMATION'
    AND q.data->>'command_id'=p_command_id::text
    AND (q.data#>>'{ticket_order,order,id}')::bigint=p_order_id
    AND q.data->>'fakturoid_pending'='true'
  FOR UPDATE;
  IF v_queue_id IS NULL THEN
    RAISE check_violation USING MESSAGE='Fakturoid order confirmation claim missing';
  END IF;
  IF v_currency='CZK' THEN
    UPDATE eshop.payment_info SET variable_symbol=p_variable_symbol
    WHERE id=v_payment_id;
  ELSIF v_currency='EUR' THEN
    IF v_existing_vs IS DISTINCT FROM p_variable_symbol THEN
      RAISE check_violation USING MESSAGE='Fakturoid EUR symbol differs from RF base';
    END IF;
  ELSE
    RAISE check_violation USING MESSAGE='unsupported Fakturoid order currency';
  END IF;
  UPDATE eshop.orders SET state='ordered',updated_at=now() WHERE id=p_order_id;
  UPDATE public.queue_emails SET target_time=now(),
    data=data-'fakturoid_pending'
  WHERE id=v_queue_id;
  SELECT coalesce(jsonb_agg(jsonb_build_object('component',component,
    'userId',ou."user")),'[]'::jsonb) INTO v_impacts
  FROM public.occasion_users ou CROSS JOIN unnest(
    ARRAY['private_profile','private_inventory']) component
  WHERE ou.occasion=v_occasion;
  PERFORM public.record_client_sync_commit_v1(v_occasion,
    'fakturoid.order.complete','inventory',jsonb_build_array(jsonb_build_object(
      'entityType','order','entityId',p_order_id,'operation','update',
      'safeLabel','Order payment ready','changedFields',
      jsonb_build_array('state','payment_info'))),'{}',v_impacts,'[]',
    'service',NULL);
  RETURN p_variable_symbol;
END;
$$;
REVOKE ALL ON FUNCTION public.complete_fakturoid_ticket_order_v1(bigint,uuid,bigint)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.complete_fakturoid_ticket_order_v1(bigint,uuid,bigint)
  TO service_role;

CREATE OR REPLACE FUNCTION public.abort_fakturoid_ticket_order_v1(
  p_order_id bigint, p_command_id uuid
) RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_state text;
  v_occasion bigint;
  v_queue_id bigint;
  v_before_users uuid[];
  v_abort_command uuid := extensions.gen_random_uuid();
  v_hash text;
BEGIN
  PERFORM public.require_client_sync_service_role_v1();
  SELECT o.state,o.occasion INTO v_state,v_occasion
  FROM eshop.orders o WHERE o.id=p_order_id FOR UPDATE;
  IF v_state='storno' THEN RETURN; END IF;
  IF v_state IS DISTINCT FROM 'preparing_payment' OR p_command_id IS NULL THEN
    RAISE check_violation USING MESSAGE='Fakturoid order is not pending';
  END IF;
  SELECT q.id INTO v_queue_id FROM public.queue_emails q
  WHERE q.code='TICKET_ORDER_CONFIRMATION'
    AND q.data->>'command_id'=p_command_id::text
    AND (q.data#>>'{ticket_order,order,id}')::bigint=p_order_id
    AND q.data->>'fakturoid_pending'='true'
  FOR UPDATE;
  IF v_queue_id IS NULL THEN
    RAISE check_violation USING MESSAGE='Fakturoid order confirmation claim missing';
  END IF;
  SELECT coalesce(array_agg(ou."user"),'{}'::uuid[]) INTO v_before_users
  FROM public.occasion_users ou WHERE ou.occasion=v_occasion;
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'order',p_order_id,'reason','fakturoid_failed')::text,'UTF8'),'sha256'),'hex');
  PERFORM public.begin_anonymous_client_mutation_v1(v_abort_command,
    'inventory.order.fakturoid_abort',v_occasion,extensions.gen_random_uuid(),v_hash);
  DELETE FROM public.queue_emails WHERE id=v_queue_id;
  PERFORM public.update_order_and_tickets_to_storno_221(p_order_id);
  PERFORM public.complete_profile_inventory_membership_mutation_v1(
    v_abort_command,v_occasion,'inventory.order.fakturoid_abort',
    jsonb_build_array(jsonb_build_object('entityType','order',
      'entityId',p_order_id,'operation','update','safeLabel','Failed order',
      'changedFields',jsonb_build_array('state','tickets','allocations'))),
    v_before_users,jsonb_build_object('orderId',p_order_id),'service');
END;
$$;
REVOKE ALL ON FUNCTION public.abort_fakturoid_ticket_order_v1(bigint,uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.abort_fakturoid_ticket_order_v1(bigint,uuid)
  TO service_role;
