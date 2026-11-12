-- Private read assembly. Prepared permissions never come from a client or live
-- beyond this invocation; mutation entrypoints re-authorize stored scopes.
CREATE OR REPLACE FUNCTION public.payment_method_contexts_internal(p_orders bigint[])
RETURNS TABLE(order_id bigint,context jsonb)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=public,extensions AS $$
DECLARE selected_orders bigint[]; payments bigint[]; financials jsonb; permissions jsonb; refunds jsonb;
 providers eshop.payment_providers[]; online_methods text[]; fences bigint[]; entry record;
 o eshop.orders; pi eshop.payment_info; r eshop.payment_providers; fin jsonb; permission jsonb;
 refund_data jsonb; policy_data jsonb; policy jsonb; caps jsonb; methods jsonb; requests jsonb; pending numeric; is_online boolean;
BEGIN
 SELECT array_agg(ord.id),array_agg(DISTINCT pay.id) INTO selected_orders,payments
 FROM eshop.orders ord JOIN eshop.payment_info pay ON pay.id=ord.payment_info WHERE ord.id=ANY(p_orders);
 IF selected_orders IS NULL THEN RETURN; END IF;
 SELECT jsonb_object_agg(s.id,public.resolve_payment_method_policy_internal(s.organization,s.id)) INTO policy_data
 FROM (SELECT DISTINCT u.id,u.organization FROM public.units u JOIN public.occasions oc ON oc.unit=u.id JOIN eshop.orders ord ON ord.occasion=oc.id WHERE ord.id=ANY(selected_orders)) s;

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
  SELECT policy_data->oc.unit::text INTO policy FROM public.occasions oc WHERE oc.id=o.occasion;
  permission:=coalesce(permissions->o.id::text,
   '{"can_record_cash":false,"can_refund_bank":false,"can_refund_provider":false}'::jsonb);
  refund_data:=refunds->pi.id::text; pending:=coalesce((refund_data->>'pending')::numeric,0);
  methods:='[]'; is_online:=coalesce(pi.payment_method=ANY(online_methods),false);
  FOREACH r IN ARRAY providers LOOP
   IF NOT ((NOT is_online AND NOT r.hosted_checkout) OR r.provider_key=pi.payment_method) THEN CONTINUE; END IF;
   caps:=public.payment_provider_call_internal(r.provider_key,'operation_capabilities',
    jsonb_build_object('orderId',o.id,'permissions',permission));
   IF NOT r.refund_write_supported THEN caps:=caps||jsonb_build_object('refund',false,'reason','unsupported_operation');
   ELSIF NOT r.refund_write_enabled THEN caps:=caps||jsonb_build_object('refund',false,'reason','connector_write_disabled'); END IF;
   caps:=caps||jsonb_build_object('refundWriteSupported',r.refund_write_supported,'partialRefundSupported',r.partial_refund_supported,'refundObservationSupported',r.refund_observation_supported);
   IF NOT r.hosted_checkout AND policy#>ARRAY['methods',r.provider_key,'policyEnabled'] IS DISTINCT FROM 'true'::jsonb THEN
    caps:=caps||jsonb_build_object('refund',false,'record',false,'instructions',false,'visible',false,'reason',policy#>>ARRAY['methods',r.provider_key,'reason']);
   END IF;
   caps:=caps||jsonb_build_object('method',r.provider_key,'purpose',CASE WHEN r.verification='bank_event' THEN 'bank_refund_instruction' ELSE 'refund' END,
    'policyRevision',policy->'revision');
   IF NOT r.partial_refund_supported AND greatest((fin->>'available')::numeric-pending,0)<(fin->>'net_received')::numeric THEN caps:=caps||jsonb_build_object('refund',false,'reason','full_refund_amount_unavailable'); END IF;
   IF r.hosted_checkout AND NOT (permission->>'can_refund_provider')::boolean THEN caps:=caps||jsonb_build_object('refund',false); END IF;
   IF caps->>'id' IS DISTINCT FROM r.provider_key THEN RAISE EXCEPTION 'PAYMENT_CAPABILITY_IDENTITY_MISMATCH'; END IF;
   IF o.id=ANY(fences) THEN caps:=caps||jsonb_build_object('refund',false,'record',false,'instructions',false,'reason','order_deletion_in_progress'); END IF;
   IF refund_data->'review'='true'::jsonb THEN caps:=caps||jsonb_build_object('refund',false,'instructions',false,'reason','refund_requires_review'); END IF;
   IF o.state NOT IN ('created','ordered','paid','sent','storno','expired') OR (fin->>'invalid_identity')::boolean OR (fin->>'net_received')::numeric<0 THEN
    caps:=caps||jsonb_build_object('refund',false,'instructions',false,'reason','payment_identity_or_state_unavailable'); END IF;
   IF o.state IN ('storno','expired','waiting','preparing') THEN caps:=caps||jsonb_build_object('record',false); END IF;
   methods:=methods||jsonb_build_array(caps);
  END LOOP;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id',req->'id','method',req->'method','verification',req->'verification',
   'amount',req->>'amount','currency',req->'currency','status',req->'status','createdAt',req->'created_at',
   'instructions',CASE WHEN req->>'verification'='bank_event' AND req->>'status'='pending' AND req->'hasSettlement'='false'::jsonb AND NOT is_online AND policy#>'{methods,bank,policyEnabled}'='true'::jsonb AND (permission->>'can_refund_bank')::boolean THEN req#>'{payload,instructions}' END,
   'purpose',CASE WHEN req->>'verification'='bank_event' THEN 'bank_refund_instruction' ELSE 'refund' END,
   'sourceOrderId',o.id,'sourcePaymentId',pi.id,'sourceMethod',pi.payment_method,
   'instructionAllowed',req->>'verification'='bank_event' AND req->>'status'='pending' AND req->'hasSettlement'='false'::jsonb AND NOT is_online AND policy#>'{methods,bank,policyEnabled}'='true'::jsonb AND (permission->>'can_refund_bank')::boolean,
   'canReopen',CASE WHEN req->>'verification'='bank_event' THEN req->>'status'='pending' AND req->'hasSettlement'='false'::jsonb AND NOT is_online AND policy#>'{methods,bank,policyEnabled}'='true'::jsonb AND (permission->>'can_refund_bank')::boolean ELSE (permission->>'can_refund_provider')::boolean END,
   'canCancel',req->>'verification'='bank_event' AND req->>'status'='pending' AND (permission->>'can_refund_bank')::boolean,
   'canCorrect',NOT is_online AND (permission->>'can_record_cash')::boolean AND req->>'verification'='local_commit' AND req->>'status'='succeeded' AND (req->>'hasSettlement')::boolean,
   'transactionId',req->'transactionId') ORDER BY ordinal),'[]') INTO requests
  FROM jsonb_array_elements(coalesce(refund_data->'requests','[]')) WITH ORDINALITY items(req,ordinal);
  order_id:=o.id;
  context:=jsonb_build_object('sourceOrderId',o.id,'sourcePaymentId',pi.id,'sourceMethod',pi.payment_method,'gross',fin->>'gross_received','refunded',fin->>'refunded','net',fin->>'net_received',
   'pending',pending::text,'available',greatest((fin->>'available')::numeric-pending,0)::text,'currency',trim(pi.currency_code),
   'methods',methods,'requests',requests,'invalidIdentity',(fin->>'invalid_identity')::boolean,
   'due',greatest(coalesce(o.price,0)-(fin->>'net_received')::numeric,0)::text,'deposit',pi.deposit_amount);
  RETURN NEXT;
 END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public.payment_method_contexts_internal(bigint[]) FROM PUBLIC,anon,authenticated,service_role;
