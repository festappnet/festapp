-- Real builtin implementations of the same installed-method dispatch contract.
CREATE OR REPLACE FUNCTION public.bank_refund_readiness_internal(p_order bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; pi eshop.payment_info; ns text; c eshop.bank_sync_connections; account text;
BEGIN
 SELECT * INTO STRICT o FROM eshop.orders WHERE id=p_order;
 SELECT * INTO STRICT pi FROM eshop.payment_info WHERE id=o.payment_info;
 IF pi.currency_code NOT IN ('CZK','EUR','USD') OR pi.variable_symbol IS NULL THEN RETURN NULL; END IF;
 SELECT a.namespace_id,n.canonical_account INTO ns,account FROM eshop.payment_reference_accounts a
 JOIN eshop.payment_reference_namespaces n ON n.id=a.namespace_id
 JOIN eshop.payment_reference_reservations r ON r.namespace_id=a.namespace_id AND r.variable_symbol=pi.variable_symbol
 JOIN public.occasions oc ON oc.id=o.occasion
 JOIN eshop.payment_reference_scopes s ON s.organization_id=oc.organization AND s.phase IN ('active','paused')
 WHERE a.bank_account_id=pi.bank_account AND r.payment_info_id=pi.id AND r.original_payment_info_id=pi.id
 AND n.allocation_enabled;
 IF ns IS NULL OR (pi.currency_code='EUR' AND NOT public.is_valid_creditor_reference(pi.creditor_reference)) THEN RETURN NULL; END IF;
 SELECT con.* INTO c FROM eshop.bank_sync_connections con
 WHERE (con.bank_account_id=pi.bank_account OR EXISTS(SELECT 1 FROM eshop.bank_sync_account_aliases a WHERE a.connection_id=con.id AND a.bank_account_id=pi.bank_account))
 AND con.state IN ('connected','degraded') AND con.mode='api' AND con.provider='FIO' AND con.legacy_blocked_at IS NOT NULL;
 IF c.id IS NULL OR (pi.currency_code='EUR' AND NOT c.refund_rf_verified) OR EXISTS(SELECT 1 FROM eshop.bank_sync_operations op WHERE op.operation='suspend' AND op.state IN ('pending','running','uncertain')
 AND (op.bank_account_id=pi.bank_account OR op.bank_account_id=c.bank_account_id OR op.bank_account_id IN (SELECT a.bank_account_id FROM eshop.bank_sync_account_aliases a WHERE a.connection_id=c.id))) THEN RETURN NULL; END IF;
 -- The source account cannot silently change after enrollment.
 IF account IS DISTINCT FROM public.try_payment_reference_account_internal((SELECT account_number FROM eshop.bank_accounts WHERE id=pi.bank_account)) THEN RETURN NULL; END IF;
 RETURN jsonb_build_object('namespace',ns,'sourceAccount',account,'connectionId',c.id,'lastSyncedAt',c.bank_pull_at,
  'variableSymbol',pi.variable_symbol::text,'creditorReference',pi.creditor_reference,
  'reference',CASE WHEN pi.currency_code='EUR' THEN pi.creditor_reference ELSE pi.variable_symbol::text END);
END $$;
CREATE OR REPLACE FUNCTION public.cash_payment_provider_internal(p_operation text,p_args jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; u bigint; tx bigint; r eshop.refund_requests; pi_id bigint; cfg jsonb;
BEGIN
 IF p_operation='initialize_payment' THEN
  INSERT INTO eshop.payment_info(amount,currency_code,created_at,payment_method)
   VALUES((p_args->>'amount')::numeric,p_args->>'currency',(p_args->>'createdAt')::timestamptz,'cash') RETURNING id INTO pi_id;
  RETURN jsonb_build_object('paymentInfoId',pi_id);
 ELSIF p_operation='form_availability' THEN
  SELECT data->'payments' INTO cfg FROM public.forms WHERE id=(p_args->>'formId')::bigint;
  RETURN jsonb_build_object('providerId','cash','configured',coalesce(cfg->'cashEnabled','false'),
   'available',coalesce(cfg->'cashEnabled','false'),'supportedSurfaces','[]'::jsonb);
 ELSIF p_operation='operation_capabilities' THEN
  SELECT * INTO STRICT o FROM eshop.orders WHERE id=(p_args->>'orderId')::bigint;
  RETURN jsonb_build_object('id','cash','displayName','Cash','record',public.can_record_order_cash(o.id),
   'refund',public.can_record_order_cash(o.id) AND trim(o.currency_code) IN ('CZK','EUR','PLN','USD','GBP'),
   'verification','local_commit');
 ELSIF p_operation IN ('record_payment','correct_record','prepare_refund') THEN
  SELECT * INTO STRICT o FROM eshop.orders WHERE id=(p_args->>'orderId')::bigint;
  SELECT unit INTO u FROM public.occasions WHERE id=o.occasion;
  IF p_operation='prepare_refund' THEN
   SELECT * INTO STRICT r FROM eshop.refund_requests WHERE id=(p_args->>'requestId')::uuid;
   tx:=public.write_cash_movement_internal(-r.amount,r.currency,u,NULL,(p_args->>'receivedAt')::timestamptz,p_args->>'note',o.payment_info,'refund',r.id);
   UPDATE eshop.refund_requests SET status='succeeded',updated_at=now() WHERE id=r.id;
  ELSE
   tx:=public.write_cash_movement_internal((p_args->>'amount')::numeric,trim(o.currency_code),u,NULL,
    (p_args->>'receivedAt')::timestamptz,p_args->>'note',o.payment_info,'correction',NULL);
  END IF;
  RETURN jsonb_build_object('nextAction','recorded','transactionId',tx);
 END IF;
 RAISE EXCEPTION 'PAYMENT_OPERATION_UNAVAILABLE';
END $$;
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
INSERT INTO eshop.payment_providers(provider_key,handler,operation_mode,verification,refund_write_enabled)
 VALUES('cash','public.cash_payment_provider_internal(text,jsonb)'::regprocedure,'local','local_commit',true),
 ('bank','public.bank_payment_provider_internal(text,jsonb)'::regprocedure,'instructions','bank_event',true)
 ON CONFLICT(provider_key) DO UPDATE SET handler=excluded.handler,operation_mode=excluded.operation_mode,
 verification=excluded.verification,refund_write_enabled=excluded.refund_write_enabled;
ALTER TABLE eshop.payment_providers DROP CONSTRAINT IF EXISTS payment_providers_concrete_handler;
ALTER TABLE eshop.payment_providers ADD CONSTRAINT payment_providers_concrete_handler CHECK(handler IS NOT NULL);
REVOKE ALL ON FUNCTION public.bank_refund_readiness_internal(bigint),public.cash_payment_provider_internal(text,jsonb),public.bank_payment_provider_internal(text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
