-- Public metadata only. Credentials stay in the service-role external-services RPC.
CREATE OR REPLACE FUNCTION public.get_order_deletion_context_v1(
  p_order bigint, p_command_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE
  v_occasion bigint; v_unit bigint; v_state text; v_vs bigint;
  v_command text; v_response jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager or editor required';
  END IF;
  -- Deletion removes the order, so a lost response is recovered from its receipt.
  IF p_command_id IS NOT NULL THEN
    SELECT r.response INTO v_response FROM public.client_mutation_receipts r
    JOIN public.occasions oc ON oc.id=r.occasion
    WHERE r.command_id=p_command_id AND r.actor_id=auth.uid()
      AND r.command_name='inventory.order.delete' AND r.status='completed'
      AND r.request_sha256=encode(extensions.digest(convert_to(
        jsonb_build_object('order',p_order)::text,'UTF8'),'sha256'),'hex')
      AND (public.get_is_manager_on_unit(oc.unit) OR public.get_is_editor_on_unit(oc.unit));
    IF FOUND THEN RETURN jsonb_build_object('response',v_response); END IF;
    IF EXISTS(SELECT 1 FROM public.client_mutation_receipts WHERE command_id=p_command_id) THEN
      RAISE insufficient_privilege USING MESSAGE='command id unavailable';
    END IF;
  END IF;
  SELECT o.occasion,oc.unit,o.state,pi.variable_symbol
    INTO v_occasion,v_unit,v_state,v_vs
  FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
    LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE o.id=p_order;
  IF v_occasion IS NULL OR NOT (public.get_is_manager_on_unit(v_unit)
      OR public.get_is_editor_on_unit(v_unit)) THEN
    RAISE insufficient_privilege USING MESSAGE='unit manager or editor required';
  END IF;
  PERFORM public.check_occasion_writable(v_occasion);
  IF v_state IN ('waitlisted','preparing_payment')
    OR EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE order_id=p_order)
    OR EXISTS(SELECT 1 FROM eshop.orders WHERE source_waitlist_order_id=p_order)
    OR EXISTS(SELECT 1 FROM eshop.waitlist_acceptance_attempts
      WHERE target_order_id=p_order OR source_order_id=p_order) THEN
    RAISE EXCEPTION 'ORDER_HAS_WAITLIST_HISTORY';
  END IF;
  SELECT m.data->>'command_id' INTO v_command FROM public.email_messages m
    WHERE m.order_id=p_order AND m.code='TICKET_ORDER_CONFIRMATION'
    ORDER BY m.id DESC LIMIT 1;
  RETURN jsonb_build_object('hasFakturoid',EXISTS(
    SELECT 1 FROM eshop.external_services WHERE unit=v_unit AND type='FAKTUROID'),
    'commandId',v_command,'variableSymbol',v_vs);
END; $$;
REVOKE ALL ON FUNCTION public.get_order_deletion_context_v1(bigint,uuid)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_order_deletion_context_v1(bigint,uuid)
  TO authenticated;
