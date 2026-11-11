-- Frozen pre-batch single-order assembly. Used only to detect cross-order
-- grouping/serialization differences in the real bulk reader. Never installed.
CREATE OR REPLACE FUNCTION pg_temp.order_payment_context_reference(p_order bigint)
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
  IF EXISTS(SELECT 1 FROM eshop.order_deletion_fences WHERE order_id=o.id) THEN caps:=caps||jsonb_build_object('refund',false,'record',false,'reason','order_deletion_in_progress'); END IF;
  IF EXISTS(SELECT 1 FROM eshop.refund_requests WHERE payment_info=pi.id AND result->'deviation'='true'::jsonb) THEN caps:=caps||jsonb_build_object('refund',false,'reason','refund_requires_review'); END IF;
  IF o.state NOT IN ('created','ordered','paid','sent','storno','expired') OR f.invalid_identity OR f.net_received<0 THEN
   caps:=caps||jsonb_build_object('refund',false,'reason','payment_identity_or_state_unavailable'); END IF;
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
