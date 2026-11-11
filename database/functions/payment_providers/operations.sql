-- Private context is only embedded in authorized admin readers.
CREATE OR REPLACE FUNCTION public.payment_method_context_internal(p_order bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 SELECT c.context INTO result FROM public.payment_method_contexts_internal(ARRAY[p_order]) c;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.payment_method_context_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.get_payment_operation_context(p_order_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE occasion_id bigint;
BEGIN
 SELECT occasion INTO occasion_id FROM eshop.orders WHERE id=p_order_id;
 IF occasion_id IS NULL OR NOT public.can_read_orders(occasion_id) THEN RAISE insufficient_privilege; END IF;
 RETURN jsonb_build_object('code',200,'orderId',p_order_id,'context',public.payment_method_context_internal(p_order_id));
END $$;
REVOKE ALL ON FUNCTION public.get_payment_operation_context(bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_payment_operation_context(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.command_payment_operation(input_data jsonb,p_command_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; pi eshop.payment_info; op text:=input_data->>'operation'; v_method text:=input_data->>'method';
 c jsonb; cap jsonb; start_result jsonb; result jsonb; req eshop.refund_requests; users uuid[]; tx eshop.transactions; amount numeric; existing_debits bigint[]; debit_id bigint; observed jsonb;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=(input_data->>'orderId')::bigint;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info;
 IF input_data ? 'currency' AND input_data->>'currency' IS DISTINCT FROM trim(pi.currency_code) THEN RAISE EXCEPTION 'PAYMENT_CURRENCY_MISMATCH'; END IF;
 IF jsonb_typeof(input_data)<>'object' OR octet_length(input_data::text)>8192 THEN RAISE EXCEPTION 'PAYMENT_INPUT_INVALID'; END IF;
 IF op NOT IN ('record_payment','prepare_refund','cancel_pending','correct_record') OR op IS NULL THEN RAISE EXCEPTION 'PAYMENT_OPERATION_INVALID'; END IF;
 IF op IN ('cancel_pending','correct_record') AND input_data ? 'requestId' THEN
  SELECT * INTO STRICT req FROM eshop.refund_requests WHERE id=(input_data->>'requestId')::uuid AND order_id=o.id;
  v_method:=req.method;
 END IF;
 -- Re-authorize before receipt replay. Actual account and unit are stored facts.
 IF NOT coalesce((CASE WHEN public.payment_method_verification_internal(v_method)='local_commit' THEN public.can_record_order_cash(o.id)
  WHEN public.payment_method_verification_internal(v_method)='bank_event' THEN public.can_prepare_order_bank_refund(o.id)
  ELSE public.payment_method_verification_internal(v_method)='verified_provider_observation' AND v_method=pi.payment_method AND public.can_prepare_order_provider_refund(o.id) END),false)
 THEN RAISE insufficient_privilege USING MESSAGE='PAYMENT_OPERATION_FORBIDDEN'; END IF;
 -- Existing imported debits are locked before capacity/order/payment, matching
 -- ingest/pairing. A later unseen debit causes a retry instead of a reverse lock.
 IF op='prepare_refund' AND public.payment_method_verification_internal(v_method)='bank_event' THEN
  SELECT array_agg(candidate.id ORDER BY candidate.id) INTO existing_debits FROM (
   SELECT t.id FROM eshop.transactions t WHERE t.amount<0 AND t.payment_info IS NULL
    AND t.ingest_source IN ('banksync_api','fio_api')
    AND (t.bank_account_id=pi.bank_account OR public.bank_sync_accounts_match(t.id,pi.bank_account))
    AND (trim(t.vs)=pi.variable_symbol::text OR (pi.currency_code='EUR' AND public.normalize_creditor_reference(t.payer_reference)=pi.creditor_reference))
   ORDER BY t.id FOR UPDATE OF t) candidate;
 END IF;
 PERFORM public.lock_order_capacity_scope_internal(ARRAY[o.id]);
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=o.id FOR UPDATE;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info FOR UPDATE;
 start_result:=public.begin_client_mutation_v1(p_command_id,'orders.payment.operation',o.occasion,auth.uid(),encode(extensions.digest(input_data::text,'sha256'),'hex'));
 IF start_result->>'disposition'='replay' THEN RETURN jsonb_set(start_result->'response','{mutation,replayed}','true'); END IF;
 IF EXISTS(SELECT 1 FROM eshop.order_deletion_fences WHERE order_id=o.id) THEN RAISE EXCEPTION 'ORDER_DELETION_IN_PROGRESS'; END IF;
 c:=public.payment_method_context_internal(o.id);
 IF op='cancel_pending' THEN
  SELECT * INTO STRICT req FROM eshop.refund_requests WHERE id=req.id FOR UPDATE;
  IF public.payment_method_verification_internal(req.method) IS DISTINCT FROM 'bank_event' OR input_data->'transferNotSubmitted' IS DISTINCT FROM 'true'::jsonb OR req.status<>'pending' THEN
   RAISE EXCEPTION 'REFUND_CANCELLATION_UNSAFE'; END IF;
  UPDATE eshop.refund_requests SET status='cancelled',updated_at=now() WHERE id=req.id;
  result:=jsonb_build_object('nextAction','recorded');
 ELSIF op='correct_record' AND req.id IS NOT NULL THEN
  IF public.payment_method_verification_internal(req.method) IS DISTINCT FROM 'local_commit' OR nullif(trim(input_data->>'reason'),'') IS NULL THEN RAISE EXCEPTION 'REFUND_CORRECTION_INVALID'; END IF;
  -- This path only voids the immutable CASH fact; never bank/provider facts.
  UPDATE eshop.refund_settlements s SET voided_at=now(),void_reason=input_data->>'reason'
   FROM eshop.transactions t JOIN eshop.bank_accounts ba ON ba.id=t.bank_account_id
   WHERE s.transaction_id=t.id AND s.request_id=req.id AND s.voided_at IS NULL AND ba.type='CASH' AND t.ingest_source='manual';
  IF NOT FOUND THEN RAISE EXCEPTION 'REFUND_CORRECTION_INVALID'; END IF;
  UPDATE eshop.refund_requests SET status='cancelled',updated_at=now() WHERE id=req.id;
  PERFORM public.refresh_payment_info_totals_internal(pi.id);
  PERFORM public.reconcile_order_payment_internal_v1(o.id,'refund_fact');
  result:=jsonb_build_object('nextAction','recorded');
 ELSE
  SELECT value INTO cap FROM jsonb_array_elements(c->'methods') WHERE value->>'id'=v_method;
  IF op='prepare_refund' THEN
   IF cap->'refund' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'PAYMENT_REFUND_UNAVAILABLE'; END IF;
  ELSIF op='record_payment' THEN
   IF cap->'record' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'PAYMENT_RECORD_UNAVAILABLE'; END IF;
  ELSIF op='correct_record' AND (public.payment_method_verification_internal(v_method) IS DISTINCT FROM 'local_commit' OR nullif(trim(input_data->>'reason'),'') IS NULL) THEN
   RAISE EXCEPTION 'PAYMENT_CORRECTION_INVALID';
  END IF;
  IF jsonb_typeof(input_data->'amount') IS DISTINCT FROM 'string' OR input_data->>'amount' !~ '^-?[0-9]{1,8}(\.[0-9]{1,2})?$' THEN
   RAISE EXCEPTION 'PAYMENT_AMOUNT_INVALID'; END IF;
  amount:=(input_data->>'amount')::numeric;
  IF amount=0 OR (op<>'correct_record' AND amount<0) THEN RAISE EXCEPTION 'PAYMENT_AMOUNT_INVALID'; END IF;
  IF op='prepare_refund' THEN
   IF amount>(c->>'available')::numeric THEN RAISE EXCEPTION 'REFUND_AVAILABLE_EXCEEDED'; END IF;
   IF public.payment_method_verification_internal(v_method)='bank_event' THEN
    PERFORM 1 FROM eshop.unit_bank_accounts link JOIN public.occasions oc ON oc.unit=link.unit
     WHERE oc.id=o.occasion AND link.bank_account=pi.bank_account FOR SHARE OF link;
    IF NOT FOUND THEN RAISE EXCEPTION 'BANK_REFUND_SOURCE_UNLINKED'; END IF;
    -- An already imported debit with the same owned reference is evidence that
    -- must be reconciled before another instruction can be issued. No reverse locks.
    IF EXISTS(SELECT 1 FROM eshop.transactions t WHERE t.amount<0 AND t.payment_info IS NULL AND NOT t.id=ANY(coalesce(existing_debits,'{}'::bigint[]))
     AND (t.bank_account_id=pi.bank_account OR public.bank_sync_accounts_match(t.id,pi.bank_account))
     AND (trim(t.vs)=pi.variable_symbol::text OR (pi.currency_code='EUR' AND public.normalize_creditor_reference(t.payer_reference)=pi.creditor_reference))) THEN
      RAISE EXCEPTION 'REFUND_RETRY_NEW_BANK_FACT' USING ERRCODE='40001'; END IF;
   END IF;
   INSERT INTO eshop.refund_requests(id,order_id,payment_info,method,amount,currency,status,payload,created_by)
    VALUES(p_command_id,o.id,pi.id,v_method,amount,trim(pi.currency_code),'pending',input_data||jsonb_build_object('existingDebits',coalesce(to_jsonb(existing_debits),'[]')),auth.uid()) RETURNING * INTO req;
   IF public.payment_method_verification_internal(v_method)='verified_provider_observation' THEN
    UPDATE eshop.refund_requests SET payload=payload||jsonb_build_object('binding',public.payment_provider_call_internal(v_method,'refund_binding',jsonb_build_object('orderId',o.id))) WHERE id=req.id;
    result:=jsonb_build_object('nextAction','processing');
   ELSE
    result:=public.payment_provider_call_internal(v_method,op,input_data||jsonb_build_object('requestId',req.id));
    IF public.payment_method_verification_internal(v_method)='bank_event' AND cardinality(existing_debits)>0 THEN
     FOREACH debit_id IN ARRAY existing_debits LOOP
      observed:=public.observe_bank_refund_internal(debit_id);
      IF observed->'matched' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'REFUND_EXISTING_DEBIT_REQUIRES_RECONCILIATION'; END IF;
     END LOOP;
     result:=jsonb_build_object('nextAction','recorded');
    END IF;
   END IF;
  ELSE
   result:=public.payment_provider_call_internal(v_method,op,input_data);
  END IF;
 END IF;
 IF req.id IS NOT NULL THEN
  INSERT INTO eshop.payment_operation_events(request_id,operation,actor,details) VALUES(req.id,op,auth.uid(),input_data);
  SELECT * INTO req FROM eshop.refund_requests WHERE id=req.id;
  result:=result||jsonb_build_object('request',jsonb_build_object('id',req.id,'method',req.method,'verification',public.payment_method_verification_internal(req.method),'status',req.status,
   'amount',req.amount::text,'currency',req.currency,'instructions',req.payload->'instructions',
   'canReopen',CASE WHEN public.payment_method_verification_internal(req.method)='bank_event' THEN public.can_prepare_order_bank_refund(o.id) ELSE public.can_prepare_order_provider_refund(o.id) END,
   'canCancel',public.payment_method_verification_internal(req.method)='bank_event' AND req.status='pending' AND public.can_prepare_order_bank_refund(o.id),
   'canCorrect',public.payment_method_verification_internal(req.method)='local_commit' AND req.status='succeeded' AND public.can_record_order_cash(o.id)));
 END IF;
 SELECT coalesce(array_agg(DISTINCT "user"),'{}') INTO users FROM public.occasion_users WHERE occasion=o.occasion;
 RETURN public.complete_private_inventory_mutation_v1(p_command_id,o.occasion,'orders.payment.operation',
  jsonb_build_array(jsonb_build_object('entityType','order','entityId',o.id,'operation','update','changedFields',jsonb_build_array('payment'))),users,
  jsonb_build_object('code',200,'orderId',o.id,'context',public.payment_method_context_internal(o.id))||result);
END $$;
REVOKE ALL ON FUNCTION public.command_payment_operation(jsonb,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.command_payment_operation(jsonb,uuid) TO authenticated;

-- Read-only impact preview. Final command repeats these checks under order locks.
CREATE OR REPLACE FUNCTION public.preview_payment_operation(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; pi eshop.payment_info; c jsonb; cap jsonb; amount numeric; threshold numeric;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=(input_data->>'orderId')::bigint;
 IF NOT public.can_read_orders(o.occasion) THEN RAISE insufficient_privilege; END IF;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info;
 c:=public.payment_method_context_internal(o.id);
 SELECT value INTO cap FROM jsonb_array_elements(c->'methods') WHERE value->>'id'=input_data->>'method';
 IF cap->'refund' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'PAYMENT_REFUND_UNAVAILABLE'; END IF;
 IF jsonb_typeof(input_data->'amount') IS DISTINCT FROM 'string' OR input_data->>'amount' !~ '^[0-9]{1,8}(\.[0-9]{1,2})?$' THEN RAISE EXCEPTION 'PAYMENT_AMOUNT_INVALID'; END IF;
 amount:=(input_data->>'amount')::numeric;
 IF amount<=0 OR amount>(c->>'available')::numeric THEN RAISE EXCEPTION 'REFUND_AVAILABLE_EXCEEDED'; END IF;
 threshold:=least(coalesce(pi.deposit_amount,o.price),o.price);
 RETURN jsonb_build_object('code',200,'preview',jsonb_build_object('netAfter',((c->>'net')::numeric-amount)::text,
  'availableAfter',((c->>'available')::numeric-amount)::text,'paidThreshold',threshold::text,
  'eligibleAfter',(c->>'net')::numeric-amount>=threshold,'lifecyclePreserved',o.state IN ('storno','expired') OR public.payment_method_is_online_internal(pi.payment_method),
  'currency',trim(pi.currency_code)));
END $$;
REVOKE ALL ON FUNCTION public.preview_payment_operation(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.preview_payment_operation(jsonb) TO authenticated;

-- Rendering payment instructions is a read, not a refund reservation or ledger write.
CREATE OR REPLACE FUNCTION public.get_bank_refund_instructions(input_data jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; pi eshop.payment_info; c jsonb; cap jsonb; amount numeric; iban text; name text;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=(input_data->>'orderId')::bigint;
 IF NOT public.can_read_orders(o.occasion) THEN RAISE insufficient_privilege; END IF;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info;
 c:=public.payment_method_context_internal(o.id);
 SELECT value INTO cap FROM jsonb_array_elements(c->'methods') WHERE value->>'id'='bank';
 IF cap->'instructions' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'PAYMENT_REFUND_UNAVAILABLE'; END IF;
 IF input_data->>'currency' IS DISTINCT FROM trim(pi.currency_code) THEN RAISE EXCEPTION 'PAYMENT_CURRENCY_MISMATCH'; END IF;
 IF jsonb_typeof(input_data->'amount') IS DISTINCT FROM 'string' OR input_data->>'amount' !~ '^[0-9]{1,8}(\.[0-9]{1,2})?$' THEN RAISE EXCEPTION 'PAYMENT_AMOUNT_INVALID'; END IF;
 amount:=(input_data->>'amount')::numeric;
 IF amount<=0 OR amount>(c->>'available')::numeric THEN RAISE EXCEPTION 'REFUND_AVAILABLE_EXCEEDED'; END IF;
 iban:=public.canonical_payment_reference_account_internal(input_data->>'recipientIban');
 name:=trim(input_data->>'recipientName');
 IF name IS NULL OR length(name) NOT BETWEEN 1 AND 70 OR name ~ '[[:cntrl:]]' THEN RAISE EXCEPTION 'REFUND_RECIPIENT_INVALID'; END IF;
 IF trim(pi.currency_code)='CZK' AND iban NOT LIKE 'CZ%' THEN RAISE EXCEPTION 'SPD_DOMESTIC_ACCOUNT_REQUIRED'; END IF;
 RETURN jsonb_build_object('code',200,'instructions',jsonb_build_object('recipientIban',iban,'recipientName',name,
  'amount',amount::text,'currency',trim(pi.currency_code),'variableSymbol',pi.variable_symbol::text,
  'creditorReference',pi.creditor_reference,'reference',CASE WHEN trim(pi.currency_code)='EUR' THEN pi.creditor_reference ELSE pi.variable_symbol::text END));
END $$;
REVOKE ALL ON FUNCTION public.get_bank_refund_instructions(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_bank_refund_instructions(jsonb) TO authenticated;
