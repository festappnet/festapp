-- Read-only bank refund QR; no payment reservation or financial write.

-- SOURCE: payment_providers/builtin.sql
CREATE OR REPLACE FUNCTION public.bank_payment_provider_internal(p_operation text,p_args jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE ready jsonb; r eshop.refund_requests; iban text; name text; pi_id bigint; cfg jsonb; bank boolean; p_form bigint;
BEGIN
 IF p_operation='observe_payment' THEN
  RETURN public.match_bank_transaction((p_args->>'transactionId')::bigint);
 ELSIF p_operation='observe_refund' THEN
  RETURN public.observe_bank_refund_internal((p_args->>'transactionId')::bigint);
 ELSIF p_operation='initialize_payment' THEN
  INSERT INTO eshop.payment_info(amount,deposit_amount,currency_code,created_at,payment_method)
   VALUES((p_args->>'amount')::numeric,CASE WHEN p_args#>>'{input,payment_type}'='full' THEN NULL ELSE nullif((p_args->>'deposit')::numeric,0) END,
    p_args->>'currency',(p_args->>'createdAt')::timestamptz,'bank') RETURNING id INTO pi_id;
  RETURN jsonb_build_object('paymentInfoId',pi_id);
 ELSIF p_operation='form_availability' THEN
  p_form:=(p_args->>'formId')::bigint;
  SELECT data->'payments' INTO cfg FROM public.forms WHERE id=p_form;
  bank:=FOUND AND coalesce(cfg->'bankEnabled','true')='true'::jsonb;
  bank:=bank AND EXISTS(SELECT 1 FROM public.forms f JOIN public.occasions oc ON oc.id=f.occasion
   JOIN eshop.unit_bank_accounts link ON link.unit=oc.unit JOIN eshop.bank_accounts b ON b.id=link.bank_account
   WHERE f.id=p_form AND (f.bank_account IS NULL OR f.bank_account=b.id) AND b.type IS DISTINCT FROM 'CASH'
   AND NOT EXISTS(SELECT 1 FROM public.form_fields ff JOIN eshop.products p ON p.product_type=ff.product_type
    WHERE ff.form=f.id AND NOT coalesce(ff.is_hidden,false) AND NOT coalesce(p.is_hidden,false)
    AND p.price>0 AND NOT coalesce(b.supported_currencies,'{}'::text[]) @> ARRAY[trim(p.currency_code)]));
  RETURN jsonb_build_object('providerId','bank','configured',bank,'available',bank,'supportedSurfaces','[]'::jsonb);
 ELSIF p_operation='operation_capabilities' THEN
  ready:=public.bank_refund_readiness_internal((p_args->>'orderId')::bigint);
  RETURN jsonb_build_object('id','bank','displayName','Bank transfer','record',false,
   'instructions',EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.payment_info pi ON pi.id=o.payment_info
    WHERE o.id=(p_args->>'orderId')::bigint AND public.can_read_orders(o.occasion)
    AND ((trim(pi.currency_code)='CZK' AND pi.variable_symbol IS NOT NULL)
     OR (trim(pi.currency_code)='EUR' AND public.is_valid_creditor_reference(pi.creditor_reference)))),
   'refund',public.can_prepare_order_bank_refund((p_args->>'orderId')::bigint) AND ready IS NOT NULL,
   'reason',CASE WHEN ready IS NULL THEN 'original_reference_or_bank_sync_unavailable' END,'verification','bank_event');
 ELSIF p_operation='prepare_refund' THEN
  SELECT * INTO STRICT r FROM eshop.refund_requests WHERE id=(p_args->>'requestId')::uuid;
  ready:=public.bank_refund_readiness_internal(r.order_id);
  IF ready IS NULL THEN RAISE EXCEPTION 'BANK_REFUND_NOT_READY'; END IF;
  iban:=public.canonical_payment_reference_account_internal(p_args->>'recipientIban');
  name:=trim(p_args->>'recipientName');
  IF name IS NULL OR length(name) NOT BETWEEN 1 AND 70 OR name ~ '[[:cntrl:]]' THEN RAISE EXCEPTION 'REFUND_RECIPIENT_INVALID'; END IF;
  IF r.currency='CZK' AND iban NOT LIKE 'CZ%' THEN RAISE EXCEPTION 'SPD_DOMESTIC_ACCOUNT_REQUIRED'; END IF;
  UPDATE eshop.refund_requests SET payload=payload||jsonb_build_object('instructions',ready||jsonb_build_object(
    'recipientIban',iban,'recipientName',name,'amount',r.amount::text,'currency',r.currency)),
   source_account=(SELECT bank_account FROM eshop.payment_info WHERE id=r.payment_info),reference_namespace=ready->>'namespace',
   variable_symbol=(ready->>'variableSymbol')::bigint,creditor_reference=ready->>'creditorReference'
   WHERE id=r.id;
  RETURN jsonb_build_object('nextAction','show_bank_instructions');
 END IF;
 RAISE EXCEPTION 'PAYMENT_OPERATION_UNAVAILABLE';
END $$;

-- SOURCE: payment_providers/operations.sql
CREATE OR REPLACE FUNCTION public.payment_method_context_internal(p_order bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; pi eshop.payment_info; f record; r record; caps jsonb; methods jsonb:='[]'; pending numeric; requests jsonb;
BEGIN
 SELECT * INTO o FROM eshop.orders WHERE id=p_order;
 SELECT * INTO pi FROM eshop.payment_info WHERE id=o.payment_info;
 IF pi.id IS NULL THEN RETURN NULL; END IF;
 SELECT * INTO STRICT f FROM public.payment_financial_totals_internal(pi.id);
 SELECT coalesce(sum(amount),0) INTO pending FROM eshop.refund_requests WHERE payment_info=pi.id AND status IN ('pending','processing','unknown');
 FOR r IN SELECT * FROM eshop.payment_providers WHERE
  (NOT public.payment_method_is_online_internal(pi.payment_method) AND NOT hosted_checkout)
  OR provider_key=pi.payment_method ORDER BY provider_key LOOP
  caps:=public.payment_provider_call_internal(r.provider_key,'operation_capabilities',jsonb_build_object('orderId',o.id));
  IF NOT r.refund_write_enabled THEN caps:=caps||jsonb_build_object('refund',false,'reason','refund_write_not_enabled'); END IF;
  IF r.hosted_checkout AND NOT public.can_prepare_order_provider_refund(o.id) THEN caps:=caps||jsonb_build_object('refund',false); END IF;
  IF caps->>'id' IS DISTINCT FROM r.provider_key THEN RAISE EXCEPTION 'PAYMENT_CAPABILITY_IDENTITY_MISMATCH'; END IF;
  IF EXISTS(SELECT 1 FROM eshop.order_deletion_fences WHERE order_id=o.id) THEN caps:=caps||jsonb_build_object('refund',false,'record',false,'instructions',false,'reason','order_deletion_in_progress'); END IF;
  IF EXISTS(SELECT 1 FROM eshop.refund_requests WHERE payment_info=pi.id AND result->'deviation'='true'::jsonb) THEN caps:=caps||jsonb_build_object('refund',false,'instructions',false,'reason','refund_requires_review'); END IF;
  IF o.state NOT IN ('created','ordered','paid','sent','storno','expired') OR f.invalid_identity OR f.net_received<0 THEN
   caps:=caps||jsonb_build_object('refund',false,'instructions',false,'reason','payment_identity_or_state_unavailable'); END IF;
  IF o.state IN ('storno','expired','waiting','preparing') THEN caps:=caps||jsonb_build_object('record',false); END IF;
  methods:=methods||jsonb_build_array(caps);
 END LOOP;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'method',method,'verification',public.payment_method_verification_internal(method),'amount',amount::text,'currency',currency,
  'status',status,'createdAt',created_at,'instructions',CASE WHEN public.payment_method_verification_internal(method)='bank_event' AND public.can_prepare_order_bank_refund(p_order) THEN payload->'instructions' END,
  'canReopen',CASE WHEN public.payment_method_verification_internal(method)='bank_event' THEN public.can_prepare_order_bank_refund(p_order) ELSE public.can_prepare_order_provider_refund(p_order) END,
  'canCancel',public.payment_method_verification_internal(method)='bank_event' AND status='pending' AND public.can_prepare_order_bank_refund(p_order),
  'canCorrect',public.can_record_order_cash(p_order) AND public.payment_method_verification_internal(method)='local_commit' AND status='succeeded' AND EXISTS(SELECT 1 FROM eshop.refund_settlements s WHERE s.request_id=id AND s.voided_at IS NULL),
  'transactionId',(SELECT s.transaction_id FROM eshop.refund_settlements s WHERE s.request_id=id LIMIT 1)) ORDER BY created_at),'[]') INTO requests
 FROM eshop.refund_requests WHERE payment_info=pi.id;
 RETURN jsonb_build_object('gross',f.gross_received::text,'refunded',f.refunded::text,'net',f.net_received::text,
  'pending',pending::text,'available',greatest(f.available-pending,0)::text,'currency',trim(pi.currency_code),
  'methods',methods,'requests',requests,'invalidIdentity',f.invalid_identity,
  'due',greatest(coalesce(o.price,0)-f.net_received,0)::text,'deposit',pi.deposit_amount);
END $$;

-- SOURCE: payment_providers/operations.sql
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
