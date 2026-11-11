-- Batch ledger facts and distinct stored-scope policies per read.
-- Nothing is cached across reads; money commands still re-authorize.

-- Order lists and payment details resolve movements by payment, independently
-- of the bank's external transaction identity.
CREATE INDEX IF NOT EXISTS transactions_payment_info_idx
 ON eshop.transactions(payment_info);
CREATE INDEX IF NOT EXISTS orders_payment_info_idx
 ON eshop.orders(payment_info);
CREATE INDEX IF NOT EXISTS refund_requests_payment_info_idx
 ON eshop.refund_requests(payment_info);
CREATE INDEX IF NOT EXISTS refund_settlements_request_id_idx
 ON eshop.refund_settlements(request_id);

-- SOURCE: eshop_transactions/payment_totals.sql
CREATE OR REPLACE FUNCTION public.payment_transaction_movements_bulk_internal(p_payments bigint[])
RETURNS TABLE(transaction_id bigint,payment_info bigint,amount numeric,currency text,
 occurred_at timestamptz,is_refund boolean,voided boolean)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 RETURN QUERY
 SELECT t.id::bigint,t.payment_info::bigint,t.amount,t.currency::text,t.date::timestamptz,
  coalesce(t.transaction_type='return',false) OR s.transaction_id IS NOT NULL,
  s.voided_at IS NOT NULL
 FROM (
  SELECT tx.* FROM eshop.transactions tx WHERE p_payments IS NULL
  UNION ALL
  SELECT tx.* FROM eshop.transactions tx WHERE p_payments IS NOT NULL AND tx.payment_info=ANY(p_payments)
 ) t LEFT JOIN eshop.refund_settlements s ON s.transaction_id=t.id;
END;
$$;
REVOKE ALL ON FUNCTION public.payment_transaction_movements_bulk_internal(bigint[]) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.payment_financial_totals_bulk_internal(p_payments bigint[])
RETURNS TABLE(payment_id bigint,gross_received numeric,refunded numeric,external_received numeric,
 disputed numeric,net_received numeric,available numeric,invalid_identity boolean)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 RETURN QUERY
 WITH payments AS MATERIALIZED (
  SELECT pi.* FROM eshop.payment_info pi WHERE pi.id=ANY(p_payments)
 ), bank AS MATERIALIZED (
  SELECT t.payment_info,
   coalesce(sum(t.amount) FILTER(WHERE NOT t.is_refund AND NOT t.voided),0) received,
   abs(coalesce(sum(t.amount) FILTER(WHERE t.is_refund AND NOT t.voided),0)) returned,
   coalesce(bool_or(t.currency IS DISTINCT FROM p.currency_code),false) invalid
  FROM public.payment_transaction_movements_bulk_internal(p_payments) t
  JOIN payments p ON p.id=t.payment_info GROUP BY t.payment_info
 ), provider_raw AS MATERIALIZED (
  SELECT p.id,CASE WHEN coalesce(r.hosted_checkout,false)
   THEN public.provider_financial_totals_internal(p.payment_method,p.id) ELSE '{}'::jsonb END facts
  FROM payments p LEFT JOIN eshop.payment_providers r ON r.provider_key=p.payment_method
 ), totals AS (
  SELECT p.id,
   coalesce(b.received,0)+coalesce((v.facts->>'received')::numeric,0) gross,
   coalesce(b.returned,0)+coalesce((v.facts->>'returned')::numeric,0) returned,
   coalesce(p.paid_externally,0) external,coalesce((v.facts->>'held')::numeric,0) held,
   coalesce(b.invalid,false) OR coalesce((v.facts->>'invalid')::boolean,false) invalid
  FROM payments p LEFT JOIN bank b ON b.payment_info=p.id JOIN provider_raw v ON v.id=p.id
 )
 SELECT t.id::bigint,t.gross,t.returned,t.external,t.held,t.gross-t.returned,
  greatest(t.gross-t.returned-t.held,0),t.invalid FROM totals t;
END;
$$;
REVOKE ALL ON FUNCTION public.payment_financial_totals_bulk_internal(bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- Actual bank/cash movements have one classification owner. A bank refund
-- retains its raw type; only the settlement classifies it as a return. Historical
-- signed manual corrections remain signed receipts. A voided cash refund stays
-- auditable in the ledger and is excluded from every financial projection.
CREATE OR REPLACE FUNCTION public.payment_transaction_movements_internal(p_payment bigint DEFAULT NULL)
RETURNS TABLE(transaction_id bigint,payment_info bigint,amount numeric,currency text,
 occurred_at timestamptz,is_refund boolean,voided boolean)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 RETURN QUERY SELECT * FROM public.payment_transaction_movements_bulk_internal(
  CASE WHEN p_payment IS NULL THEN NULL::bigint[] ELSE ARRAY[p_payment] END);
END;
$$;
REVOKE ALL ON FUNCTION public.payment_transaction_movements_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- One financial projection over actual ledgers. External/manual settlement is
-- retained as its own fact; disputes are an availability hold, never a refund.
CREATE OR REPLACE FUNCTION public.payment_financial_totals_internal(p_payment bigint)
RETURNS TABLE(gross_received numeric,refunded numeric,external_received numeric,
 disputed numeric,net_received numeric,available numeric,invalid_identity boolean)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 RETURN QUERY SELECT f.gross_received,f.refunded,f.external_received,f.disputed,
  f.net_received,f.available,f.invalid_identity
 FROM public.payment_financial_totals_bulk_internal(ARRAY[p_payment]) f;
END;
$$;
REVOKE ALL ON FUNCTION public.payment_financial_totals_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.refresh_payment_info_totals_internal(p_payment bigint)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE totals record;
BEGIN
 PERFORM 1 FROM eshop.payment_info WHERE id=p_payment FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'PAYMENT_INFO_NOT_FOUND'; END IF;
 SELECT * INTO STRICT totals FROM public.payment_financial_totals_internal(p_payment);
 IF totals.invalid_identity THEN RAISE EXCEPTION 'PAYMENT_FACT_IDENTITY_MISMATCH'; END IF;
 UPDATE eshop.payment_info SET paid=totals.gross_received,returned=totals.refunded WHERE id=p_payment;
 -- paid_externally is deliberately not rewritten or converted into a bank movement.
END $$;
REVOKE ALL ON FUNCTION public.refresh_payment_info_totals_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- Call only while holding the canonical order/payment locks. Corrections and
-- unpairing may not consume funds already promised by an issued instruction.
CREATE OR REPLACE FUNCTION public.assert_payment_refund_reservations_internal(p_payment bigint,p_removed numeric DEFAULT 0)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE reserved numeric; facts record;
BEGIN
 SELECT coalesce(sum(amount),0) INTO reserved FROM eshop.refund_requests
 WHERE payment_info=p_payment AND status IN ('pending','processing','unknown');
 IF reserved=0 THEN RETURN; END IF;
 SELECT * INTO STRICT facts FROM public.payment_financial_totals_internal(p_payment);
 IF facts.invalid_identity OR facts.net_received-facts.disputed-p_removed<reserved THEN
  RAISE EXCEPTION 'PAYMENT_REFUND_RESERVATION_CONFLICT';
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.assert_payment_refund_reservations_internal(bigint,numeric) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.check_order_refund_delete_internal(p_order bigint)
RETURNS void LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM eshop.refund_requests WHERE order_id=p_order)
 OR EXISTS(SELECT 1 FROM eshop.orders o JOIN eshop.transactions t ON t.payment_info=o.payment_info
   JOIN eshop.refund_settlements s ON s.transaction_id=t.id WHERE o.id=p_order) THEN
  RAISE EXCEPTION 'ORDER_HAS_REFUND_HISTORY';
 END IF;
END $$;
REVOKE ALL ON FUNCTION public.check_order_refund_delete_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: user_permissions/domain_operations.sql (can_read_orders)
CREATE OR REPLACE FUNCTION public.can_read_orders(p_occasion bigint)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, extensions AS $$
BEGIN
 RETURN (
 SELECT public.order_read_rule(
   (SELECT ou.is_editor_order_view FROM public.occasion_users ou WHERE ou.occasion=p_occasion AND ou."user"=auth.uid()),
   public.is_demo_occasion(p_occasion),public.can_read_demo_occasion(p_occasion))
 );
END;
$$;
REVOKE ALL ON FUNCTION public.can_read_orders(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_read_orders(bigint) TO anon, authenticated, service_role;

-- SOURCE: user_permissions/bank_operations.sql (can_manage_bank_account)
CREATE OR REPLACE FUNCTION public.can_manage_bank_account(p_bank_account bigint)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 RETURN (
 SELECT public.bank_account_write_rule(public.get_is_admin_on_bank_account(p_bank_account),
 EXISTS(SELECT 1 FROM eshop.unit_bank_accounts link JOIN public.unit_users membership
   ON membership.unit=link.unit AND membership."user"=auth.uid() AND membership.is_manager
   WHERE link.bank_account=p_bank_account AND NOT EXISTS(
     SELECT 1 FROM public.demo_unit_ids_internal() demo WHERE demo.unit_id=membership.unit)),
 public.is_demo_bank_account(p_bank_account))
 );
END;
$$;
REVOKE ALL ON FUNCTION public.can_manage_bank_account(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.can_manage_bank_account(bigint) TO authenticated,service_role;

-- SOURCE: user_permissions/get_is_manager_on_unit.sql (get_is_manager_on_unit)
CREATE OR REPLACE FUNCTION public.get_is_manager_on_unit(unit_id bigint) RETURNS bool
    LANGUAGE plpgsql STABLE
    SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
 RETURN (
 SELECT NOT public.is_demo_unit(unit_id) AND EXISTS (
    SELECT 1
    FROM public.unit_users membership
    WHERE membership."user" = auth.uid()
      AND membership.unit = unit_id
      AND membership.is_manager
  )
 );
END;
$$;
REVOKE ALL ON FUNCTION public.get_is_manager_on_unit(bigint) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_is_manager_on_unit(bigint) TO anon,authenticated,service_role;

-- SOURCE: user_permissions/payment_operations.sql
CREATE OR REPLACE FUNCTION public.payment_operation_permissions_internal(p_orders bigint[])
RETURNS TABLE(order_id bigint,can_record_cash boolean,can_refund_bank boolean,can_refund_provider boolean)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 RETURN QUERY
 WITH orders AS MATERIALIZED (
  SELECT o.id,o.occasion,oc.unit,pi.bank_account
  FROM eshop.orders o JOIN public.occasions oc ON oc.id=o.occasion
  LEFT JOIN eshop.payment_info pi ON pi.id=o.payment_info WHERE o.id=ANY(p_orders)
 ), units AS MATERIALIZED (
  SELECT scope.unit,public.get_is_manager_on_unit(scope.unit) manager FROM (SELECT DISTINCT o.unit FROM orders o) scope
 ), occasions AS MATERIALIZED (
  SELECT scope.occasion,public.is_demo_occasion(scope.occasion) demo FROM (SELECT DISTINCT o.occasion FROM orders o) scope
 ), banks AS MATERIALIZED (
  SELECT scope.bank_account,public.can_manage_bank_account(scope.bank_account) manager
  FROM (SELECT DISTINCT o.bank_account FROM orders o WHERE o.bank_account IS NOT NULL) scope
 ), links AS MATERIALIZED (
  SELECT scope.unit,scope.bank_account,EXISTS(SELECT 1 FROM eshop.unit_bank_accounts link
   WHERE link.unit=scope.unit AND link.bank_account=scope.bank_account) linked
  FROM (SELECT DISTINCT o.unit,o.bank_account FROM orders o) scope
 )
 SELECT o.id::bigint,coalesce(u.manager AND NOT oc.demo,false),
  coalesce(b.manager AND u.manager AND link.linked AND NOT oc.demo,false),
  coalesce(u.manager AND NOT oc.demo,false)
 FROM orders o JOIN units u ON u.unit IS NOT DISTINCT FROM o.unit
 JOIN occasions oc ON oc.occasion=o.occasion
 LEFT JOIN banks b ON b.bank_account=o.bank_account
 JOIN links link ON link.unit IS NOT DISTINCT FROM o.unit AND link.bank_account IS NOT DISTINCT FROM o.bank_account;
END;
$$;
REVOKE ALL ON FUNCTION public.payment_operation_permissions_internal(bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- Typed operations bind scope from stored orders, never a caller-supplied unit.
CREATE OR REPLACE FUNCTION public.can_record_order_cash(p_order bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT p.can_record_cash FROM public.payment_operation_permissions_internal(ARRAY[p_order]) p),false);
$$;
CREATE OR REPLACE FUNCTION public.can_prepare_order_bank_refund(p_order bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT p.can_refund_bank FROM public.payment_operation_permissions_internal(ARRAY[p_order]) p),false);
$$;
CREATE OR REPLACE FUNCTION public.can_prepare_order_provider_refund(p_order bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
 SELECT coalesce((SELECT p.can_refund_provider FROM public.payment_operation_permissions_internal(ARRAY[p_order]) p),false);
$$;
REVOKE ALL ON FUNCTION public.can_record_order_cash(bigint),public.can_prepare_order_bank_refund(bigint),public.can_prepare_order_provider_refund(bigint) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.can_record_order_cash(bigint),public.can_prepare_order_bank_refund(bigint),public.can_prepare_order_provider_refund(bigint) TO authenticated;

-- SOURCE: payment_providers/builtin.sql (cash_payment_provider_internal)
CREATE OR REPLACE FUNCTION public.cash_payment_provider_internal(p_operation text,p_args jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE o eshop.orders; u bigint; tx bigint; r eshop.refund_requests; pi_id bigint; cfg jsonb; can_record boolean;
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
  can_record:=CASE WHEN p_args ? 'permissions' THEN coalesce((p_args#>>'{permissions,can_record_cash}')::boolean,false)
   ELSE public.can_record_order_cash(o.id) END;
  RETURN jsonb_build_object('id','cash','displayName','Cash','record',can_record,
   'refund',can_record AND trim(o.currency_code) IN ('CZK','EUR','PLN','USD','GBP'),
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

-- SOURCE: payment_providers/builtin.sql (bank_payment_provider_internal)
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
   'refund',(CASE WHEN p_args ? 'permissions' THEN coalesce((p_args#>>'{permissions,can_refund_bank}')::boolean,false)
    ELSE public.can_prepare_order_bank_refund((p_args->>'orderId')::bigint) END) AND ready IS NOT NULL,
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

-- SOURCE: payment_providers/operation_contexts.sql
-- Private read assembly. Prepared permissions never come from a client or live
-- beyond this invocation; mutation entrypoints re-authorize stored scopes.
CREATE OR REPLACE FUNCTION public.payment_method_contexts_internal(p_orders bigint[])
RETURNS TABLE(order_id bigint,context jsonb)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE selected_orders bigint[]; payments bigint[]; financials jsonb; permissions jsonb; refunds jsonb;
 providers eshop.payment_providers[]; online_methods text[]; fences bigint[]; entry record;
 o eshop.orders; pi eshop.payment_info; r eshop.payment_providers; fin jsonb; permission jsonb;
 refund_data jsonb; caps jsonb; methods jsonb; requests jsonb; pending numeric; is_online boolean;
BEGIN
 SELECT array_agg(ord.id),array_agg(DISTINCT pay.id) INTO selected_orders,payments
 FROM eshop.orders ord JOIN eshop.payment_info pay ON pay.id=ord.payment_info WHERE ord.id=ANY(p_orders);
 IF selected_orders IS NULL THEN RETURN; END IF;

 SELECT jsonb_object_agg(f.payment_id,to_jsonb(f)) INTO financials
 FROM public.payment_financial_totals_bulk_internal(payments) f;
 SELECT jsonb_object_agg(p.order_id,to_jsonb(p)) INTO permissions
 FROM public.payment_operation_permissions_internal(selected_orders) p;
 SELECT array_agg(p ORDER BY p.provider_key),array_agg(p.provider_key) FILTER(WHERE p.hosted_checkout)
 INTO providers,online_methods FROM eshop.payment_providers p;
 SELECT coalesce(array_agg(f.order_id),'{}') INTO fences FROM eshop.order_deletion_fences f WHERE f.order_id=ANY(selected_orders);

 -- Load requests and their settlement facts once, including reservations that
 -- have not changed the actual ledger. Instructions remain permission-filtered.
 SELECT jsonb_object_agg(summary.payment_info,summary.data) INTO refunds FROM (
  SELECT rr.payment_info,jsonb_build_object(
   'pending',coalesce(sum(rr.amount) FILTER(WHERE rr.status IN ('pending','processing','unknown')),0),
   'review',coalesce(bool_or(rr.result->'deviation'='true'::jsonb),false),
   'requests',jsonb_agg(to_jsonb(rr)||jsonb_build_object('verification',p.verification,
    'hasSettlement',EXISTS(SELECT 1 FROM eshop.refund_settlements s WHERE s.request_id=rr.id AND s.voided_at IS NULL),
    'transactionId',(SELECT s.transaction_id FROM eshop.refund_settlements s WHERE s.request_id=rr.id LIMIT 1)) ORDER BY rr.created_at)
  ) data
  FROM eshop.refund_requests rr JOIN eshop.payment_providers p ON p.provider_key=rr.method
  WHERE rr.payment_info=ANY(payments) GROUP BY rr.payment_info
 ) summary;

 FOR entry IN SELECT ord AS order_row,pay AS payment_row FROM eshop.orders ord
  JOIN eshop.payment_info pay ON pay.id=ord.payment_info WHERE ord.id=ANY(selected_orders)
 LOOP
  o:=entry.order_row; pi:=entry.payment_row;
  fin:=financials->pi.id::text;
  permission:=coalesce(permissions->o.id::text,
   '{"can_record_cash":false,"can_refund_bank":false,"can_refund_provider":false}'::jsonb);
  refund_data:=refunds->pi.id::text; pending:=coalesce((refund_data->>'pending')::numeric,0);
  methods:='[]'; is_online:=coalesce(pi.payment_method=ANY(online_methods),false);
  FOREACH r IN ARRAY providers LOOP
   IF NOT ((NOT is_online AND NOT r.hosted_checkout) OR r.provider_key=pi.payment_method) THEN CONTINUE; END IF;
   caps:=public.payment_provider_call_internal(r.provider_key,'operation_capabilities',
    jsonb_build_object('orderId',o.id,'permissions',permission));
   IF NOT r.refund_write_enabled THEN caps:=caps||jsonb_build_object('refund',false,'reason','refund_write_not_enabled'); END IF;
   IF r.hosted_checkout AND NOT (permission->>'can_refund_provider')::boolean THEN caps:=caps||jsonb_build_object('refund',false); END IF;
   IF caps->>'id' IS DISTINCT FROM r.provider_key THEN RAISE EXCEPTION 'PAYMENT_CAPABILITY_IDENTITY_MISMATCH'; END IF;
   IF o.id=ANY(fences) THEN caps:=caps||jsonb_build_object('refund',false,'record',false,'reason','order_deletion_in_progress'); END IF;
   IF refund_data->'review'='true'::jsonb THEN caps:=caps||jsonb_build_object('refund',false,'reason','refund_requires_review'); END IF;
   IF o.state NOT IN ('created','ordered','paid','sent','storno','expired') OR (fin->>'invalid_identity')::boolean OR (fin->>'net_received')::numeric<0 THEN
    caps:=caps||jsonb_build_object('refund',false,'reason','payment_identity_or_state_unavailable'); END IF;
   IF o.state IN ('storno','expired','waiting','preparing') THEN caps:=caps||jsonb_build_object('record',false); END IF;
   methods:=methods||jsonb_build_array(caps);
  END LOOP;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',req->'id','method',req->'method','verification',req->'verification',
   'amount',req->>'amount','currency',req->'currency','status',req->'status','createdAt',req->'created_at',
   'instructions',CASE WHEN req->>'verification'='bank_event' AND (permission->>'can_refund_bank')::boolean THEN req#>'{payload,instructions}' END,
   'canReopen',CASE WHEN req->>'verification'='bank_event' THEN (permission->>'can_refund_bank')::boolean ELSE (permission->>'can_refund_provider')::boolean END,
   'canCancel',req->>'verification'='bank_event' AND req->>'status'='pending' AND (permission->>'can_refund_bank')::boolean,
   'canCorrect',(permission->>'can_record_cash')::boolean AND req->>'verification'='local_commit' AND req->>'status'='succeeded' AND (req->>'hasSettlement')::boolean,
   'transactionId',req->'transactionId') ORDER BY ordinal),'[]') INTO requests
  FROM jsonb_array_elements(coalesce(refund_data->'requests','[]')) WITH ORDINALITY items(req,ordinal);
  order_id:=o.id;
  context:=jsonb_build_object('gross',fin->>'gross_received','refunded',fin->>'refunded','net',fin->>'net_received',
   'pending',pending::text,'available',greatest((fin->>'available')::numeric-pending,0)::text,'currency',trim(pi.currency_code),
   'methods',methods,'requests',requests,'invalidIdentity',(fin->>'invalid_identity')::boolean,
   'due',greatest(coalesce(o.price,0)-(fin->>'net_received')::numeric,0)::text,'deposit',pi.deposit_amount);
  RETURN NEXT;
 END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public.payment_method_contexts_internal(bigint[]) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: payment_providers/operations.sql (payment_method_context_internal)
CREATE OR REPLACE FUNCTION public.payment_method_context_internal(p_order bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 SELECT c.context INTO result FROM public.payment_method_contexts_internal(ARRAY[p_order]) c;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.payment_method_context_internal(bigint) FROM PUBLIC,anon,authenticated,service_role;

-- SOURCE: eshop/order_seating.sql (order_spot_metadata_bulk_internal)
CREATE OR REPLACE FUNCTION public.order_spot_metadata_bulk_internal(p_spots bigint[])
RETURNS TABLE(spot_id bigint,metadata jsonb)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 RETURN QUERY
 WITH spots AS MATERIALIZED (
  SELECT s.id,s.title,s.blueprint,s.occasion FROM eshop.spots s WHERE s.id=ANY(p_spots)
 ), plans AS (
  SELECT DISTINCT s.blueprint,s.occasion FROM spots s WHERE s.blueprint IS NOT NULL
 ), nodes AS MATERIALIZED (
  SELECT b.id blueprint,b.occasion,n.node,n.ordinal FROM plans p
  JOIN eshop.blueprints b ON b.id=p.blueprint AND b.occasion=p.occasion
  CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.layout->'nodes','[]')) WITH ORDINALITY n(node,ordinal)
 ), first_nodes AS (
  SELECT DISTINCT ON (n.blueprint,n.occasion,n.node->>'id') n.blueprint,n.occasion,n.node
  FROM nodes n WHERE n.node->>'id' IS NOT NULL ORDER BY n.blueprint,n.occasion,n.node->>'id',n.ordinal
 ), plan_labels AS MATERIALIZED (
  SELECT n.blueprint,n.occasion,jsonb_object_agg(n.node->>'id',n.node->'label') labels
  FROM first_nodes n GROUP BY n.blueprint,n.occasion
 )
 SELECT s.id::bigint,jsonb_build_object('spot_title',s.title,'spot_group_title',(
  SELECT p.labels->>binding.group_node::text FROM eshop.blueprint_seat_bindings binding
  JOIN plan_labels p ON p.blueprint=binding.blueprint AND p.occasion=s.occasion
  WHERE binding.spot=s.id AND binding.blueprint=s.blueprint LIMIT 1))
 FROM spots s;
END;
$$;
REVOKE ALL ON FUNCTION public.order_spot_metadata_bulk_internal(bigint[]) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.order_spot_metadata_bulk_internal(bigint[]) TO service_role;

-- SOURCE: eshop/order_seating.sql (order_spot_metadata_internal)
CREATE OR REPLACE FUNCTION public.order_spot_metadata_internal(p_spot bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT jsonb_build_object('spot_title',s.title,'spot_group_title',(
   SELECT n->>'label' FROM eshop.blueprint_seat_bindings binding
   CROSS JOIN LATERAL jsonb_array_elements(coalesce(b.layout->'nodes','[]')) n
   WHERE binding.spot=s.id AND binding.blueprint=b.id AND n->>'id'=binding.group_node::text LIMIT 1
))
 FROM eshop.spots s LEFT JOIN eshop.blueprints b ON b.id=s.blueprint AND b.occasion=s.occasion
 WHERE s.id=p_spot;
$$;
REVOKE ALL ON FUNCTION public.order_spot_metadata_internal(bigint) FROM PUBLIC,anon,authenticated;

-- SOURCE: eshop/order_seating.sql (order_tickets_with_seating_bulk_internal)
CREATE OR REPLACE FUNCTION public.order_tickets_with_seating_bulk_internal(p_snapshots jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE result jsonb;
BEGIN
 WITH snapshots AS MATERIALIZED (
  SELECT nullif(key,'')::bigint AS order_id,key,value FROM jsonb_each(coalesce(p_snapshots,'{}'))
 ), tickets AS MATERIALIZED (
  SELECT s.order_id,s.key,t,ti FROM snapshots s
  CROSS JOIN LATERAL jsonb_array_elements(s.value) WITH ORDINALITY ticket(t,ti)
 ), products AS MATERIALIZED (
  SELECT t.order_id,t.key,t.ti,p,pi,(t.t->>'id')::bigint ticket_id,(p->>'id')::bigint product_id
  FROM tickets t CROSS JOIN LATERAL jsonb_array_elements(coalesce(t.t->'products','[]')) WITH ORDINALITY product(p,pi)
 ), selected_items AS MATERIALIZED (
  SELECT DISTINCT p.order_id,p.ticket_id,p.product_id FROM products p
 ), seated_spots AS MATERIALIZED (
  SELECT DISTINCT s.id FROM selected_items item
  JOIN eshop.order_product_ticket x ON x."order"=item.order_id AND x.ticket=item.ticket_id AND x.product=item.product_id
  JOIN eshop.spots s ON s.order_product_ticket=x.id AND s.blueprint IS NOT NULL
  JOIN eshop.orders o ON o.id=x."order" AND o.occasion=s.occasion
 ), seated_metadata AS MATERIALIZED (
  SELECT m.spot_id,m.metadata FROM public.order_spot_metadata_bulk_internal(ARRAY(SELECT id FROM seated_spots)) m
 ), assignments AS MATERIALIZED (
  SELECT DISTINCT ON (x."order",x.ticket,x.product) x."order" order_id,x.ticket,x.product,
   CASE WHEN s.blueprint IS NOT NULL THEN sm.metadata ||
    jsonb_build_object('is_standing',false,'standing_area_title',NULL)
   ELSE jsonb_build_object('spot_title',NULL,'spot_group_title',NULL,
    'is_standing',true,'standing_area_title',area.node->>'label') END metadata
  FROM selected_items item JOIN eshop.order_product_ticket x ON x."order"=item.order_id AND x.ticket=item.ticket_id AND x.product=item.product_id
  JOIN eshop.spots s ON s.order_product_ticket=x.id
  LEFT JOIN seated_metadata sm ON sm.spot_id=s.id
  JOIN eshop.orders o ON o.id=x."order" AND o.occasion=s.occasion
  LEFT JOIN public.forms f ON f.id=o.form AND f.occasion=o.occasion
  LEFT JOIN eshop.blueprint_area_bindings ab ON ab.blueprint=coalesce(f.blueprint,(SELECT min(candidate.blueprint) FROM eshop.blueprint_area_bindings candidate
       JOIN eshop.blueprints target ON target.id=candidate.blueprint WHERE candidate.inventory_context=s.inventory_context
         AND candidate.product=x.product AND target.occasion=o.occasion HAVING count(DISTINCT candidate.blueprint)=1))
   AND ab.inventory_context=s.inventory_context AND ab.product=x.product
  LEFT JOIN eshop.blueprints b ON b.id=ab.blueprint AND b.occasion=o.occasion
  LEFT JOIN LATERAL (SELECT n AS node FROM jsonb_array_elements(coalesce(b.layout->'nodes','[]')) n
   WHERE n->>'id'=ab.node_id::text AND n->>'kind'='capacityArea') area ON true
  WHERE s.blueprint IS NOT NULL OR area.node IS NOT NULL
  ORDER BY x."order",x.ticket,x.product,(s.blueprint IS NOT NULL) DESC,x.id,s.id
 ), ticket_products AS MATERIALIZED (
  SELECT p.key,p.ti,jsonb_agg(p.p||coalesce(a.metadata,'{}') ORDER BY p.pi) products
  FROM products p LEFT JOIN assignments a ON a.order_id=p.order_id AND a.ticket=p.ticket_id AND a.product=p.product_id
  GROUP BY p.key,p.ti
 ), enriched AS (
  SELECT t.key,jsonb_agg(t.t||jsonb_build_object('products',coalesce(p.products,'[]')) ORDER BY t.ti) tickets
  FROM tickets t LEFT JOIN ticket_products p ON p.key=t.key AND p.ti=t.ti GROUP BY t.key
 )
 SELECT coalesce(jsonb_object_agg(s.key,coalesce(e.tickets,'[]')),'{}') INTO result
 FROM snapshots s LEFT JOIN enriched e ON e.key=s.key;
 RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.order_tickets_with_seating_bulk_internal(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.order_tickets_with_seating_bulk_internal(jsonb) TO service_role;

-- SOURCE: eshop/order_seating.sql (order_tickets_with_seating_internal)
CREATE OR REPLACE FUNCTION public.order_tickets_with_seating_internal(p_order bigint,p_tickets jsonb)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT coalesce(jsonb_agg(t || jsonb_build_object('products',(
   SELECT coalesce(jsonb_agg(p || coalesce((
     SELECT CASE WHEN s.blueprint IS NOT NULL THEN public.order_spot_metadata_internal(s.id) ||
       jsonb_build_object('is_standing',false,'standing_area_title',NULL)
       ELSE jsonb_build_object('spot_title',NULL,'spot_group_title',NULL,
         'is_standing',true,'standing_area_title',area.node->>'label') END
     FROM eshop.order_product_ticket x JOIN eshop.spots s ON s.order_product_ticket=x.id
     JOIN eshop.orders o ON o.id=x."order" AND o.occasion=s.occasion
     LEFT JOIN public.forms f ON f.id=o.form AND f.occasion=o.occasion
     LEFT JOIN eshop.blueprint_area_bindings ab ON ab.blueprint=coalesce(f.blueprint,(SELECT min(candidate.blueprint) FROM eshop.blueprint_area_bindings candidate
       JOIN eshop.blueprints target ON target.id=candidate.blueprint WHERE candidate.inventory_context=s.inventory_context
         AND candidate.product=x.product AND target.occasion=o.occasion HAVING count(DISTINCT candidate.blueprint)=1))
       AND ab.inventory_context=s.inventory_context AND ab.product=x.product
     LEFT JOIN eshop.blueprints b ON b.id=ab.blueprint AND b.occasion=o.occasion
     LEFT JOIN LATERAL (SELECT n AS node FROM jsonb_array_elements(coalesce(b.layout->'nodes','[]')) n
       WHERE n->>'id'=ab.node_id::text AND n->>'kind'='capacityArea') area ON true
     WHERE x."order"=p_order AND x.ticket=(t->>'id')::bigint AND x.product=(p->>'id')::bigint
       AND (s.blueprint IS NOT NULL OR area.node IS NOT NULL)
     ORDER BY (s.blueprint IS NOT NULL) DESC,x.id,s.id LIMIT 1),'{}') ORDER BY pi),'[]')
   FROM jsonb_array_elements(coalesce(t->'products','[]')) WITH ORDINALITY products(p,pi)
 )) ORDER BY ti),'[]')
 FROM jsonb_array_elements(coalesce(p_tickets,'[]')) WITH ORDINALITY tickets(t,ti);
$$;
REVOKE ALL ON FUNCTION public.order_tickets_with_seating_internal(bigint,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.order_spot_metadata_internal(bigint), public.order_tickets_with_seating_internal(bigint,jsonb) TO service_role;

-- SOURCE: eshop_orders/get_orders.sql (get_orders)
CREATE OR REPLACE FUNCTION public.get_orders(
    p_occasion_link TEXT,
    p_form_link TEXT DEFAULT NULL,
    p_options JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_occasion_id BIGINT;
    v_form_id BIGINT;
    spotsData JSONB;
    productsData JSONB;
    productTypesData JSONB;
    ticketsData JSONB;
    ordersData JSONB;
    ordersHistoryData JSONB;
    orderProductTicketsData JSONB;
    paymentInfoData JSONB;
    formsData JSONB;
    usersData JSONB; -- ADDED: Variable for user info data
BEGIN
    -- This function retrieves order and reservation details for a given occasion.
    -- It can conditionally include related data like spots, history, and users.
    --
    -- 'include_orders_history': If true, it fetches 'orders_history' and the
    --                           associated 'users' who created those history records.

    -- 1. Input Validation: Ensure at least one link is provided.
    IF p_occasion_link IS NULL AND p_form_link IS NULL THEN
        RETURN jsonb_build_object('code', 400, 'message', 'Either occasion_link or form_link must be provided');
    END IF;

    -- 2. Determine occasion_id based on the provided link.
    IF p_occasion_link IS NOT NULL THEN
        SELECT id
        INTO v_occasion_id
        FROM public.occasions
        WHERE id = public.resolve_occasion_link_internal(p_occasion_link)
          AND organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid());
    ELSE
        SELECT occasion, id
        INTO v_occasion_id, v_form_id
        FROM public.forms
        WHERE id = public.resolve_form_link_internal(p_form_link)
          AND occasion IN (SELECT o.id FROM public.occasions o WHERE o.organization = (SELECT ui.organization FROM public.user_info ui WHERE ui.id = auth.uid()));
    END IF;

    -- 3. Check if a valid occasion was found.
    IF v_occasion_id IS NULL THEN
        RETURN jsonb_build_object('code', 404, 'message', 'The provided link is invalid or not linked to any occasion');
    END IF;

    -- 4. Authorization check.
    IF (SELECT can_read_orders(v_occasion_id)) <> TRUE THEN
        RETURN jsonb_build_object('code', 403, 'message', 'User is not authorized to access this occasion');
    END IF;

    -- Conditionally fetch spots based on p_options for optimization
    IF (p_options->>'include_spots')::BOOLEAN = TRUE THEN
        SELECT jsonb_agg(jsonb_build_object(
            'id', s.id,
            'title', s.title,
            'product', s.product,
            'order_product_ticket', s.order_product_ticket,
            'state', CASE
                WHEN s.order_product_ticket IS NOT NULL THEN 'ordered'
                WHEN s.secret IS NOT NULL AND s.secret_expiration_time > now() THEN 'selected'
                ELSE 'available'
            END
        ))
        INTO spotsData
        FROM eshop.spots s
        WHERE s.occasion = v_occasion_id
          AND s.order_product_ticket IS NOT NULL;
    END IF;

    -- Fetch all products linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', p.id,
        'title', p.title,
        'price', p.price,
        'currency_code', p.currency_code,
        'type', pt.type
    ))
    INTO productsData
    FROM eshop.products p
    JOIN eshop.product_types pt ON pt.id = p.product_type
    WHERE pt.occasion = v_occasion_id;

    -- Fetch product types for the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', pt.id,
        'type', pt.type,
        'title', pt.title,
        'description', pt.description
    ))
    INTO productTypesData
    FROM eshop.product_types pt
    WHERE pt.occasion = v_occasion_id;

    -- Fetch tickets linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', t.id,
        'created_at', t.created_at,
        'updated_at', t.updated_at,
        'ticket_symbol', t.ticket_symbol,
        'state', t.state,
        'note', t.note,
        'note_hidden', t.note_hidden,
        'batch', (SELECT jsonb_build_object('id',i.batch_id,'title',b.title,'ordinal',i.ordinal,'saleOrderId',i.sale_order_id) FROM eshop.ticket_batch_items i JOIN eshop.ticket_batches b ON b.id=i.batch_id WHERE i.ticket_id=t.id),
        'allowedActions',CASE WHEN EXISTS(SELECT 1 FROM eshop.ticket_batch_items i WHERE i.ticket_id=t.id) THEN
          jsonb_build_array('view') || CASE WHEN EXISTS(SELECT 1 FROM eshop.ticket_batch_document_parts d WHERE d.kind='single' AND d.ticket_ids=ARRAY[t.id] AND d.state='ready') THEN jsonb_build_array('download') ELSE '[]'::jsonb END ||
          CASE WHEN public.can_write_orders(t.occasion) THEN jsonb_build_array('note') ||
            CASE WHEN t.state<>'storno' AND EXISTS(SELECT 1 FROM eshop.ticket_batch_items i WHERE i.ticket_id=t.id AND i.sale_order_id IS NOT NULL)
              THEN jsonb_build_array('use','reset','cancel') ELSE '[]'::jsonb END ELSE '[]'::jsonb END END,
        'data', t.data
    ))
    INTO ticketsData
    FROM eshop.tickets t
    WHERE t.occasion = v_occasion_id;

    -- Fetch forms linked to the occasion
    SELECT jsonb_agg(jsonb_build_object(
        'id', f.id,
        'data', f.data,
        'key', f.key,
        'occasion', f.occasion,
        'type', f.type,
        'deadline_duration_seconds', f.deadline_duration_seconds,
        'participant_capacity',f.participant_capacity,
        'waitlist_enabled',f.waitlist_enabled,
        'show_remaining_capacity',f.show_remaining_capacity,
        'waitlist_offer_duration_seconds',f.waitlist_offer_duration_seconds,
        'capacity',public.get_form_capacity_snapshot_internal(f.id),
        'registrationMode',public.get_form_registration_mode_internal(f.id),
        'is_open', f.is_open,
        'link', f.link,
        'blueprint', f.blueprint,
        'title', f.title
    ))
    INTO formsData
    FROM public.forms f
    WHERE f.occasion = v_occasion_id;

    -- Ordinary orders need only activity/actions. Resolve ticket/offer lifecycles
    -- once only for orders that expose a full waitlist summary.
    WITH selected_orders AS MATERIALIZED (
        SELECT o.*, CASE WHEN o.state='waitlisted' OR o.source_waitlist_order_id IS NOT NULL
          OR EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE order_id=o.id)
          THEN public.get_waitlist_summary_internal(o.id)
          ELSE public.get_order_action_summary_internal(o.state)
        END AS waitlist_summary
        FROM eshop.orders o
        WHERE o.occasion = v_occasion_id
          AND (v_form_id IS NULL OR o.form = v_form_id)
    ), seating_data AS MATERIALIZED (
        SELECT CASE WHEN (p_options->>'include_full_order_data')::boolean = TRUE
            THEN public.order_tickets_with_seating_bulk_internal(coalesce(jsonb_object_agg(o.id,coalesce(o.data->'tickets','[]')),'{}')) END snapshots
        FROM selected_orders o WHERE (p_options->>'include_full_order_data')::boolean = TRUE
    )
        SELECT jsonb_agg(jsonb_build_object(
            'id', o.id, 'order_symbol', o.order_symbol, 'order_sequence', o.order_sequence, 'created_at', o.created_at, 'updated_at', o.updated_at, 'price', o.price, 'state', o.state, 'currency_code', o.currency_code,
            'waitlistSummary',CASE WHEN o.state='waitlisted' OR o.source_waitlist_order_id IS NOT NULL
              OR EXISTS(SELECT 1 FROM eshop.waitlist_offers WHERE order_id=o.id)
              THEN o.waitlist_summary END,
            'isActive',(o.waitlist_summary->>'isActive')::boolean,
            'allowedActions',public.get_order_allowed_actions_internal_v1(o.id,o.waitlist_summary),
            'paymentChannel',CASE WHEN o.data ? 'ticketBatchOrigin' THEN 'cash' END,
            'batchId',(SELECT b.id FROM eshop.ticket_batches b WHERE b.stock_order_id=o.id),
            'source_waitlist_order_id',o.source_waitlist_order_id,
            'form_id', o.form,
            'form', jsonb_build_object('id', o.form),
            'data', CASE
                WHEN (p_options->>'include_full_order_data')::BOOLEAN = TRUE THEN o.data || jsonb_build_object('tickets', sd.snapshots->o.id::text)
                ELSE jsonb_build_object('name', o.data->>'name', 'surname', o.data->>'surname', 'email', o.data->>'email', 'note', o.data->>'note')
            END,
            'payment_info', o.payment_info, 'note_hidden', o.note_hidden
        ))
        INTO ordersData
        FROM selected_orders o CROSS JOIN seating_data sd;

    -- Extract order IDs from the (potentially filtered) ordersData JSONB
    WITH order_ids AS (
        SELECT (order_obj->>'id')::BIGINT AS id
        FROM jsonb_array_elements(COALESCE(ordersData, '[]'::jsonb)) order_obj
    )
    -- Fetch relevant order-product-ticket data based on extracted order IDs
    SELECT jsonb_agg(jsonb_build_object('id', opt.id, 'order', opt."order", 'product', opt.product, 'ticket', opt.ticket))
    INTO orderProductTicketsData
    FROM eshop.order_product_ticket opt
    WHERE opt."order" IN (SELECT id FROM order_ids);

    -- One statement keeps the bulk context and stored payment values on the
    -- same snapshot. Reuse pending totals and each account's warning as well.
    WITH payment_contexts AS MATERIALIZED (
        SELECT jsonb_object_agg(c.order_id,c.context) AS contexts
        FROM public.payment_method_contexts_internal(ARRAY(
            SELECT (order_obj->>'id')::bigint
            FROM jsonb_array_elements(COALESCE(ordersData,'[]'::jsonb)) order_obj
        )) c
    ), selected_payments AS MATERIALIZED (
        SELECT pi.*,pc.contexts->(SELECT id::text FROM eshop.orders WHERE payment_info=pi.id) AS operation_context
        FROM eshop.payment_info pi CROSS JOIN payment_contexts pc
        WHERE pi.id IN (
            SELECT DISTINCT (order_obj->>'payment_info')::bigint
            FROM jsonb_array_elements(COALESCE(ordersData,'[]'::jsonb)) order_obj
            WHERE order_obj->>'payment_info' IS NOT NULL
        )
    ), bank_warnings AS MATERIALIZED (
        SELECT scope.bank_account,public.bank_sync_warning(scope.bank_account) AS warning
        FROM (SELECT DISTINCT bank_account FROM selected_payments) scope
    )
    SELECT jsonb_agg(jsonb_build_object(
        'id', pi.id, 'payment_method', pi.payment_method, 'bank_account', pi.bank_account, 'variable_symbol', pi.variable_symbol, 'amount', pi.amount, 'deposit_amount', pi.deposit_amount,
        'deposit_deadline', pi.deposit_deadline, 'paid', pi.paid, 'returned', pi.returned, 'net',coalesce(pi.paid,0)-coalesce(pi.returned,0),
        'pending',coalesce((pi.operation_context->>'pending')::numeric,0),
        'paymentOperations',pi.operation_context, 'deadline', pi.deadline, 'currency_code', pi.currency_code, 'data', pi.data,
        'bank_sync_warning', bw.warning
    ))
    INTO paymentInfoData
    FROM selected_payments pi
    JOIN bank_warnings bw ON bw.bank_account IS NOT DISTINCT FROM pi.bank_account;

    -- Conditionally fetch orders history and related users based on p_options
    IF (p_options->>'include_orders_history')::BOOLEAN = TRUE THEN
        -- First, fetch the history records
        WITH order_ids AS (
            SELECT (order_obj->>'id')::BIGINT AS id
            FROM jsonb_array_elements(COALESCE(ordersData, '[]'::jsonb)) order_obj
        )
        SELECT jsonb_agg(jsonb_build_object(
            'id', oh.id, 'created_at', oh.created_at, 'created_by', oh.created_by, 'data', oh.data,
            'order', oh."order", 'order_symbol', (SELECT o.order_symbol FROM eshop.orders o WHERE o.id=oh."order"), 'order_sequence', (SELECT o.order_sequence FROM eshop.orders o WHERE o.id=oh."order"), 'state', oh.state, 'price', oh.price, 'currency_code', oh.currency_code
        ))
        INTO ordersHistoryData
        FROM eshop.orders_history oh
        WHERE oh."order" IN (SELECT id FROM order_ids);

        -- Second, fetch the unique users who created those history records
        WITH user_ids AS (
            SELECT DISTINCT (history_obj->>'created_by')::UUID AS id
            FROM jsonb_array_elements(COALESCE(ordersHistoryData, '[]'::jsonb)) history_obj
            WHERE history_obj->>'created_by' IS NOT NULL
        )
        SELECT jsonb_agg(jsonb_build_object(
            'id', ui.id,
            'name', ui.name,
            'surname', ui.surname,
            'email_readonly', ui.email_readonly
        ))
        INTO usersData
        FROM public.user_info ui
        WHERE ui.id IN (SELECT id FROM user_ids);
    END IF;


    -- Return combined data
    RETURN jsonb_build_object(
        'code', 200,
        'occasion_id', v_occasion_id,
        'data', jsonb_build_object(
            'spots', COALESCE(spotsData, '[]'::jsonb),
            'products', COALESCE(productsData, '[]'::jsonb),
            'product_types', COALESCE(productTypesData, '[]'::jsonb),
            'tickets', COALESCE(ticketsData, '[]'::jsonb),
            'orders', COALESCE(ordersData, '[]'::jsonb),
            'order_product_ticket', COALESCE(orderProductTicketsData, '[]'::jsonb),
            'payment_info', COALESCE(paymentInfoData, '[]'::jsonb),
            'forms', COALESCE(formsData, '[]'::jsonb),
            'orders_history', COALESCE(ordersHistoryData, '[]'::jsonb),
            'users', COALESCE(usersData, '[]'::jsonb)
        )
    );
END;
$$;

-- SOURCE: emails/email_reporting.sql (order_email_current_issues_bulk)
CREATE OR REPLACE FUNCTION public.order_email_current_issues_bulk(p_orders bigint[])
RETURNS TABLE(order_id bigint,issues jsonb)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 RETURN QUERY

 WITH RECURSIVE selected_orders AS MATERIALIZED (
  SELECT o.* FROM eshop.orders o WHERE o.id=ANY(p_orders) AND o.state<>'storno'
 ), scoped_messages AS MATERIALIZED (
  SELECT m.* FROM public.email_messages m JOIN selected_orders o ON o.id=m.order_id AND o.occasion=m.occasion
  JOIN public.occasions oc ON oc.id=o.occasion AND oc.organization=m.organization
 ), event_times AS MATERIALIZED (
  SELECT e.message_id,max(e.provider_time) FILTER(WHERE e.event_type='bounce') bounce,
   max(e.provider_time) FILTER(WHERE e.event_type='delivery') delivery,
   max(e.provider_time) FILTER(WHERE e.event_type IN ('bounce','complaint','reject','rendering_failure')) failure
  FROM public.email_delivery_events e JOIN scoped_messages m ON m.message_id=e.message_id GROUP BY e.message_id
 ), messages AS MATERIALIZED (
  SELECT m.*,CASE WHEN m.complained_at IS NULL AND m.last_error IS DISTINCT FROM 'post_action_failed'
   AND coalesce(m.provider_failure,'') NOT IN ('reject','rendering_failure')
   AND greatest(m.bounced_at,events.bounce) IS NOT NULL
   AND greatest(m.delivered_at,events.delivery)>greatest(m.bounced_at,events.bounce)
   THEN 'delivery' ELSE public.email_reporting_state(m::public.email_messages) END rs,events.failure FROM scoped_messages m
  LEFT JOIN event_times events ON events.message_id=m.message_id),
 problem_orders AS MATERIALIZED (
  SELECT DISTINCT m.order_id FROM messages m
  WHERE m.rs IN ('bounce','complaint','reject','rendering_failure','dead','suppressed','unknown','retry_wait','delay','blocked','sending','post_action_failed')
   OR (m.message_kind IN ('order_confirmation','order_tickets') AND m.workflow_state IN ('pending','preparing') AND m.target_time<=now())
 ), chain AS (
  SELECT m.order_id,m.message_id root,m.message_id leaf,ARRAY[m.message_id] path FROM messages m JOIN problem_orders problem ON problem.order_id=m.order_id
  WHERE NOT EXISTS(SELECT 1 FROM messages parent WHERE parent.message_id::text=m.data->>'repair_source_message_id' AND parent.message_kind=m.message_kind AND parent.order_id=m.order_id)
  UNION ALL
  SELECT c.order_id,c.root,m.message_id,c.path||m.message_id FROM chain c JOIN messages parent ON parent.message_id=c.leaf
  JOIN messages m ON m.data->>'repair_source_message_id'=c.leaf::text AND m.message_kind=parent.message_kind AND m.order_id=c.order_id
  WHERE NOT m.message_id=ANY(c.path)),
 leaves AS (SELECT DISTINCT ON (c.order_id,c.root) * FROM chain c ORDER BY c.order_id,c.root,cardinality(c.path) DESC,c.leaf),
 issues AS (
  SELECT c.order_id,root.message_id source_message_id,leaf.message_id,root.message_kind kind,root.recipient original_recipient,
   leaf.recipient,leaf.rs state,
   coalesce(leaf.last_error,CASE WHEN leaf.workflow_state IN ('pending','preparing','blocked') THEN
    (SELECT CASE WHEN paused THEN 'queue_paused' WHEN daily_quota<=provider_sent_24h THEN 'queue_limit' END FROM public.email_capacity) END) reason,
   (SELECT reason FROM public.email_suppressions WHERE recipient=lower(leaf.recipient)) suppression_reason,
   CASE WHEN o.state='storno' THEN 'cancelled'
    WHEN leaf.rs IN ('delivery','open','click') AND leaf.delivered_at IS NOT NULL
     AND (leaf.recipient IS DISTINCT FROM o.data->>'email' OR leaf.source_version IS DISTINCT FROM o.email_payment_version
      OR (leaf.data->>'repair_payment_fingerprint' IS NOT NULL AND leaf.data->>'repair_payment_fingerprint' IS DISTINCT FROM public.order_email_payment_fingerprint(o.id))) THEN 'stale_delivery'
    WHEN leaf.message_id<>root.message_id AND leaf.rs IN ('pending','preparing','accepted','open','click','sending','blocked') THEN 'waiting_repair'
    ELSE leaf.rs END resolution,
   (root.message_kind<>public.order_checkout_email_kind_internal(o.id)) obsolete
  FROM leaves c JOIN messages root ON root.message_id=c.root JOIN messages leaf ON leaf.message_id=c.leaf
  JOIN selected_orders o ON o.id=c.order_id
  WHERE (EXISTS(SELECT 1 FROM messages m WHERE m.message_id=ANY(c.path)
    AND (m.rs IN ('bounce','complaint','reject','rendering_failure','dead','suppressed','unknown','retry_wait','delay','blocked','sending','post_action_failed')
     OR (m.message_kind IN ('order_confirmation','order_tickets') AND m.workflow_state IN ('pending','preparing') AND m.target_time<=now()))))
   -- Delivered current tickets supersede the obsolete checkout confirmation,
   -- even though confirmation and ticket repairs intentionally have separate chains.
   -- Acceptance/open tracking alone, stale snapshots and unrelated message kinds
   -- must never clear an actionable delivery failure.
   AND NOT (root.message_kind='order_confirmation' AND o.state IN ('paid','sent')
    AND EXISTS(SELECT 1 FROM messages tickets WHERE tickets.order_id=c.order_id AND tickets.message_kind='order_tickets'
     AND tickets.rs IN ('delivery','open','click') AND tickets.delivered_at IS NOT NULL
     AND tickets.recipient=o.data->>'email' AND tickets.source_version=o.email_payment_version
     AND (tickets.data->>'repair_payment_fingerprint' IS NULL
      OR tickets.data->>'repair_payment_fingerprint'=public.order_email_payment_fingerprint(o.id))
     AND tickets.delivered_at>greatest(leaf.created_at,leaf.bounced_at,leaf.complained_at,
      leaf.failure)))
   AND NOT (leaf.delivered_at IS NOT NULL AND leaf.rs IN ('delivery','open','click')
    AND leaf.recipient=o.data->>'email' AND leaf.source_version=o.email_payment_version
    AND (leaf.data->>'repair_payment_fingerprint' IS NULL OR leaf.data->>'repair_payment_fingerprint'=public.order_email_payment_fingerprint(o.id))))
 SELECT o.id::bigint,coalesce(jsonb_agg(to_jsonb(i)-'order_id' ORDER BY i.source_message_id)
  FILTER(WHERE i.source_message_id IS NOT NULL),'[]'::jsonb)
 FROM eshop.orders o LEFT JOIN issues i ON i.order_id=o.id WHERE o.id=ANY(p_orders) GROUP BY o.id;

END;
$$;
REVOKE ALL ON FUNCTION public.order_email_current_issues_bulk(bigint[]) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.order_email_current_issues_bulk(bigint[]) TO service_role;

-- SOURCE: emails/email_reporting.sql (order_email_current_issues)
CREATE OR REPLACE FUNCTION public.order_email_current_issues(p_order bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
BEGIN
 RETURN coalesce((SELECT b.issues FROM public.order_email_current_issues_bulk(ARRAY[p_order]) b),'[]'::jsonb);
END;
$$;
REVOKE ALL ON FUNCTION public.order_email_current_issues(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.order_email_current_issues(bigint) TO service_role;

-- SOURCE: emails/email_reporting.sql (get_order_email_summaries)
CREATE OR REPLACE FUNCTION public.get_order_email_summaries(p_occasion bigint,p_orders bigint[]) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE v_summary jsonb;
BEGIN
 IF NOT coalesce(public.can_read_orders(p_occasion),false) THEN RAISE EXCEPTION 'email_read_denied'; END IF;
 IF EXISTS(SELECT 1 FROM eshop.orders WHERE id=ANY(p_orders) AND occasion<>p_occasion) THEN RAISE EXCEPTION 'email_scope_mismatch'; END IF;
 WITH selected_orders AS MATERIALIZED (
  SELECT o.id FROM eshop.orders o WHERE o.id=ANY(p_orders) AND o.occasion=p_occasion
 ), messages AS MATERIALIZED (
  SELECT m.*,public.email_reporting_state(m) reporting_state FROM public.email_messages m
  WHERE m.order_id=ANY(p_orders) AND m.occasion=p_occasion AND m.workflow_state NOT IN ('cancelled','expired')
 ), current_issues AS MATERIALIZED (
  SELECT b.order_id,b.issues FROM public.order_email_current_issues_bulk(p_orders) b
 ), ranked AS MATERIALIZED (
  SELECT m.*,i.issues,CASE WHEN m.reporting_state IN ('complaint','bounce','reject','rendering_failure','unknown','dead','suppressed','retry_wait','post_action_failed')
   AND EXISTS(SELECT 1 FROM jsonb_array_elements(i.issues) issue WHERE issue->>'message_id'=m.message_id::text) THEN 0
   WHEN m.workflow_state IN ('pending','preparing','sending','blocked') AND m.target_time<=now() THEN 1
   WHEN m.workflow_state='accepted' AND m.reporting_state NOT IN ('complaint','bounce','reject','rendering_failure') THEN 2 ELSE 3 END rank
  FROM messages m JOIN current_issues i USING(order_id)
 ), histories AS MATERIALIZED (
  SELECT n.order_id,count(*) FILTER(WHERE n.rank=0) attention_count,
   jsonb_agg(jsonb_build_object('kind',n.message_kind,'state',n.reporting_state,'at',coalesce(n.delivered_at,n.accepted_at,n.created_at)) ORDER BY n.created_at DESC) messages
  FROM ranked n GROUP BY n.order_id
 ), latest AS (
  SELECT DISTINCT ON (r.order_id) * FROM ranked r ORDER BY r.order_id,r.rank,r.created_at DESC,r.id DESC
 )
 SELECT coalesce(jsonb_object_agg(o.id,CASE WHEN r.order_id IS NULL
  THEN jsonb_build_object('state','unavailable','messages','[]'::jsonb,'current_issues',i.issues,'loaded_at',now())
  ELSE jsonb_build_object('state',r.reporting_state,'kind',r.message_kind,'recipient',r.recipient,'message_id',r.message_id,
   'at',coalesce(r.clicked_at,r.opened_at,r.delivered_at,r.accepted_at,r.created_at),'current_issues',i.issues,
   'scheduled_at',r.target_time,'attention_count',h.attention_count,'loaded_at',now(),'messages',h.messages) END),'{}')
 INTO v_summary FROM selected_orders o JOIN current_issues i ON i.order_id=o.id
 LEFT JOIN latest r ON r.order_id=o.id LEFT JOIN histories h ON h.order_id=o.id;
 RETURN v_summary;
END $$;
REVOKE ALL ON FUNCTION public.get_order_email_summaries(bigint,bigint[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_order_email_summaries(bigint,bigint[]) TO authenticated,service_role;

-- SOURCE: others/get_ticket_layout_write_contract_v1.sql (get_ticket_layout_write_contract_v1)
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
  ('public.save_occasion_domain_command_internal_v1(bigint,uuid,bigint,jsonb)','00af445f9e641905e395adaca48ce248',true,true),
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
  ('public.update_occasion_internal_v1(jsonb)','2446d470f7e49092199946b0cc8fa6bd',true,true),
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

NOTIFY pgrst, 'reload schema';
