-- Canonical service fee source and disabled Wix delivery journal. No business facts seeded.

-- Source: database/tables/service_fees.sql
-- Platform income, separate from eshop buyer money. No rate defaults or payment inference.
CREATE TABLE IF NOT EXISTS public.service_fee_agreements (
 id uuid PRIMARY KEY,
 unit_id bigint NOT NULL REFERENCES public.units(id),
 organization_id bigint NOT NULL REFERENCES public.organizations(id),
 source_reference text NOT NULL CHECK(length(btrim(source_reference)) BETWEEN 1 AND 1000),
 fee_rate_bps integer NOT NULL CHECK(fee_rate_bps BETWEEN 1 AND 10000),
 valid_from timestamptz NOT NULL,
 valid_until timestamptz,
 termination_evidence_reference text,
 CHECK(valid_until IS NULL OR valid_until>valid_from),
 UNIQUE(unit_id,source_reference)
);
CREATE TABLE IF NOT EXISTS public.service_fee_customer_acquisitions (
 unit_id bigint PRIMARY KEY REFERENCES public.units(id),
 channel text NOT NULL CHECK(channel IN('wix','direct','other','pre-existing-non-wix')),
 acquired_at timestamptz NOT NULL,
 evidence_reference text NOT NULL CHECK(length(btrim(evidence_reference)) BETWEEN 1 AND 1000)
);
CREATE TABLE IF NOT EXISTS public.service_fee_settlements (
 id uuid PRIMARY KEY,
 agreement_id uuid NOT NULL REFERENCES public.service_fee_agreements(id),
 kind text NOT NULL CHECK(kind IN('charge','refund')),
 original_settlement_id uuid REFERENCES public.service_fee_settlements(id),
 source_reference text NOT NULL UNIQUE CHECK(length(btrim(source_reference)) BETWEEN 1 AND 1000),
 invoice_reference text NOT NULL CHECK(length(btrim(invoice_reference)) BETWEEN 1 AND 1000),
 payment_evidence_reference text NOT NULL CHECK(length(btrim(payment_evidence_reference)) BETWEEN 1 AND 1000),
 allocation_evidence_reference text NOT NULL CHECK(length(btrim(allocation_evidence_reference)) BETWEEN 1 AND 1000),
 settled_at timestamptz NOT NULL,
 service_at timestamptz NOT NULL,
 currency text NOT NULL CHECK(currency ~ '^[A-Z]{3}$'),
 fee_minor numeric(30,0) NOT NULL CHECK(fee_minor>0),
 tax_minor numeric(30,0) NOT NULL CHECK(tax_minor>=0),
 input_digest text NOT NULL,
 CHECK((kind='refund')=(original_settlement_id IS NOT NULL))
);
CREATE TABLE IF NOT EXISTS public.service_fee_allocations (
 id uuid PRIMARY KEY,
 settlement_id uuid NOT NULL REFERENCES public.service_fee_settlements(id),
 -- Preserve historical references even if the buyer order is later removed.
 order_id bigint NOT NULL,
 order_created_at timestamptz NOT NULL,
 original_allocation_id uuid REFERENCES public.service_fee_allocations(id),
 fee_minor numeric(30,0) NOT NULL CHECK(fee_minor>0),
 agreed_expenses_minor numeric(30,0) NOT NULL CHECK(agreed_expenses_minor BETWEEN 0 AND fee_minor),
 expense_approval_reference text,
 instance_id uuid,
 instance_verification_reference text,
 order_origin_snapshot jsonb,
 fx jsonb,
 wix_share_bps integer CHECK(wix_share_bps BETWEEN 0 AND 10000),
 partner_terms_reference text,
 CHECK(agreed_expenses_minor=0 OR coalesce(length(btrim(expense_approval_reference)),0)>0),
 UNIQUE(settlement_id,order_id)
);
ALTER TABLE public.service_fee_agreements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_fee_customer_acquisitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_fee_settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_fee_allocations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.service_fee_agreements,public.service_fee_customer_acquisitions,
 public.service_fee_settlements,public.service_fee_allocations FROM PUBLIC,anon,authenticated,service_role;

-- Source: database/functions/service_fees/source.sql
-- Deliberate operator import of real contract and accounting evidence. No UI or
-- tenant admin may assert platform income. Replay cannot amend historical facts.
CREATE OR REPLACE FUNCTION public.register_service_fee_agreement(p_id uuid,p_unit bigint,p_reference text,p_rate_bps integer,p_from timestamptz,p_until timestamptz DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE prior public.service_fee_agreements;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.units WHERE id=p_unit FOR UPDATE;
 IF NOT FOUND THEN RAISE invalid_parameter_value USING MESSAGE='FEE_UNIT_NOT_FOUND'; END IF;
 SELECT * INTO prior FROM public.service_fee_agreements WHERE id=p_id;
 IF FOUND THEN
  IF ROW(prior.unit_id,prior.source_reference,prior.fee_rate_bps,prior.valid_from,prior.valid_until)
   IS DISTINCT FROM ROW(p_unit,p_reference,p_rate_bps,p_from,p_until) THEN
   RAISE check_violation USING MESSAGE='FEE_AGREEMENT_REPLAY_CONFLICT'; END IF;
  RETURN p_id;
 END IF;
 IF EXISTS(SELECT 1 FROM public.service_fee_agreements WHERE unit_id=p_unit
  AND tstzrange(valid_from,valid_until,'[)') && tstzrange(p_from,p_until,'[)')) THEN
  RAISE check_violation USING MESSAGE='FEE_AGREEMENT_PERIOD_OVERLAP'; END IF;
 INSERT INTO public.service_fee_agreements(id,unit_id,organization_id,source_reference,fee_rate_bps,valid_from,valid_until) VALUES(p_id,p_unit,(SELECT organization FROM public.units WHERE id=p_unit),p_reference,p_rate_bps,p_from,p_until);
 RETURN p_id;
END $$;

-- End an open-ended version only against explicit contract evidence. Existing
-- settlement coverage cannot be rewritten. The next rate is a new agreement.
CREATE OR REPLACE FUNCTION public.end_service_fee_agreement(p_id uuid,p_until timestamptz,p_evidence text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE prior public.service_fee_agreements;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO STRICT prior FROM public.service_fee_agreements WHERE id=p_id;
 PERFORM 1 FROM public.units WHERE id=prior.unit_id FOR UPDATE;
 SELECT * INTO STRICT prior FROM public.service_fee_agreements WHERE id=p_id FOR UPDATE;
 IF p_until IS NULL OR p_until<=prior.valid_from OR coalesce(length(btrim(p_evidence)),0) NOT BETWEEN 1 AND 1000 THEN
  RAISE invalid_parameter_value USING MESSAGE='FEE_AGREEMENT_TERMINATION_EVIDENCE_REQUIRED'; END IF;
 IF prior.termination_evidence_reference IS NOT NULL THEN
  IF prior.valid_until IS DISTINCT FROM p_until OR prior.termination_evidence_reference<>p_evidence THEN
   RAISE check_violation USING MESSAGE='FEE_TERMINATION_REPLAY_CONFLICT'; END IF;
  RETURN;
 END IF;
 IF prior.valid_until IS NOT NULL OR EXISTS(SELECT 1 FROM public.service_fee_settlements WHERE agreement_id=p_id AND service_at>=p_until) THEN
  RAISE check_violation USING MESSAGE='FEE_TERMINATION_REWRITES_HISTORY'; END IF;
 UPDATE public.service_fee_agreements SET valid_until=p_until,termination_evidence_reference=p_evidence WHERE id=p_id;
END $$;

CREATE OR REPLACE FUNCTION public.register_service_fee_acquisition(p_unit bigint,p_channel text,p_acquired_at timestamptz,p_evidence text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE prior public.service_fee_customer_acquisitions;
BEGIN
 PERFORM public.require_service_role();
 PERFORM 1 FROM public.units WHERE id=p_unit FOR UPDATE;
 SELECT * INTO prior FROM public.service_fee_customer_acquisitions WHERE unit_id=p_unit;
 IF FOUND THEN
  IF ROW(prior.channel,prior.acquired_at,prior.evidence_reference) IS DISTINCT FROM ROW(p_channel,p_acquired_at,p_evidence) THEN
   RAISE check_violation USING MESSAGE='FEE_ACQUISITION_REPLAY_CONFLICT'; END IF;
  RETURN;
 END IF;
 INSERT INTO public.service_fee_customer_acquisitions VALUES(p_unit,p_channel,p_acquired_at,p_evidence);
END $$;

-- A complete, evidenced allocation is required. Partial/ambiguous input stays
-- outside this source and is not eligible for reporting. Amounts are facts, not
-- a recalculation of order totals. Strings preserve integer minor-unit precision.
CREATE OR REPLACE FUNCTION public.record_service_fee_settlement(p_input jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ident uuid:=(p_input->>'id')::uuid; agreement public.service_fee_agreements;
 prior public.service_fee_settlements; original public.service_fee_settlements;
 allocation jsonb; origin public.service_fee_allocations; proof eshop.order_checkout_origins;
 digest text:=encode(extensions.digest(p_input::text,'sha256'),'hex'); total numeric:=0;
 expenses numeric; amount numeric; allocation_id uuid; order_at timestamptz;
BEGIN
 PERFORM public.require_service_role();
 IF jsonb_typeof(p_input) IS DISTINCT FROM 'object' OR octet_length(p_input::text)>1048576
  OR jsonb_typeof(p_input->'allocations') IS DISTINCT FROM 'array' OR jsonb_array_length(p_input->'allocations') NOT BETWEEN 1 AND 1000 THEN
  RAISE invalid_parameter_value USING MESSAGE='INVALID_FEE_SETTLEMENT'; END IF;
 SELECT * INTO STRICT agreement FROM public.service_fee_agreements WHERE id=(p_input->>'agreementId')::uuid;
 -- Serialize imports/refunds for this customer, including aggregate caps.
 PERFORM 1 FROM public.units WHERE id=agreement.unit_id FOR UPDATE;
 SELECT * INTO prior FROM public.service_fee_settlements WHERE id=ident;
 IF FOUND THEN
  IF prior.input_digest<>digest THEN RAISE check_violation USING MESSAGE='FEE_SETTLEMENT_REPLAY_CONFLICT'; END IF;
  RETURN ident;
 END IF;
 IF p_input->>'amountBasis' IS DISTINCT FROM 'settled-service-fee-excluding-tax'
  OR jsonb_typeof(p_input->'feeMinor') IS DISTINCT FROM 'string' OR jsonb_typeof(p_input->'taxMinor') IS DISTINCT FROM 'string'
  OR p_input->>'feeMinor' !~ '^[1-9][0-9]{0,29}$' OR p_input->>'taxMinor' !~ '^(0|[1-9][0-9]{0,29})$'
  OR p_input->>'feeMinor' IS NULL OR p_input->>'taxMinor' IS NULL THEN
  RAISE invalid_parameter_value USING MESSAGE='SETTLED_FEE_FACTS_REQUIRED'; END IF;
 IF NOT ((p_input->>'serviceAt')::timestamptz <@ tstzrange(agreement.valid_from,agreement.valid_until,'[)')) THEN
  RAISE check_violation USING MESSAGE='FEE_AGREEMENT_OUTSIDE_PERIOD'; END IF;
 IF p_input->>'kind'='refund' THEN
  SELECT * INTO STRICT original FROM public.service_fee_settlements WHERE id=(p_input->>'originalSettlementId')::uuid;
  IF original.kind<>'charge' OR original.agreement_id<>agreement.id OR original.currency<>p_input->>'currency'
   OR original.settled_at>(p_input->>'settledAt')::timestamptz OR original.service_at<>(p_input->>'serviceAt')::timestamptz THEN
   RAISE check_violation USING MESSAGE='FEE_REFUND_SCOPE_MISMATCH'; END IF;
  IF (SELECT coalesce(sum(fee_minor),0) FROM public.service_fee_settlements WHERE original_settlement_id=original.id)+(p_input->>'feeMinor')::numeric>original.fee_minor
   OR (SELECT coalesce(sum(tax_minor),0) FROM public.service_fee_settlements WHERE original_settlement_id=original.id)+(p_input->>'taxMinor')::numeric>original.tax_minor THEN
   RAISE check_violation USING MESSAGE='FEE_REFUND_EXCEEDS_SETTLEMENT'; END IF;
 END IF;
 INSERT INTO public.service_fee_settlements VALUES(ident,agreement.id,p_input->>'kind',(p_input->>'originalSettlementId')::uuid,
  p_input->>'sourceReference',p_input->>'invoiceReference',p_input->>'paymentEvidenceReference',p_input->>'allocationEvidenceReference',
  (p_input->>'settledAt')::timestamptz,(p_input->>'serviceAt')::timestamptz,p_input->>'currency',
  (p_input->>'feeMinor')::numeric,(p_input->>'taxMinor')::numeric,digest);
 FOR allocation IN SELECT value FROM jsonb_array_elements(p_input->'allocations') LOOP
  IF jsonb_typeof(allocation->'feeMinor') IS DISTINCT FROM 'string' OR jsonb_typeof(allocation->'agreedExpensesMinor') IS DISTINCT FROM 'string'
   OR allocation->>'feeMinor' IS NULL OR allocation->>'feeMinor' !~ '^[1-9][0-9]{0,29}$'
   OR allocation->>'agreedExpensesMinor' IS NULL OR allocation->>'agreedExpensesMinor' !~ '^(0|[1-9][0-9]{0,29})$' THEN
   RAISE invalid_parameter_value USING MESSAGE='INVALID_FEE_ALLOCATION'; END IF;
  amount:=(allocation->>'feeMinor')::numeric; expenses:=(allocation->>'agreedExpensesMinor')::numeric;
  allocation_id:=(allocation->>'id')::uuid; total:=total+amount;
  proof:=NULL; origin:=NULL; order_at:=NULL;
  IF p_input->>'kind'='charge' THEN
   IF allocation->>'originalAllocationId' IS NOT NULL THEN RAISE check_violation USING MESSAGE='INVALID_FEE_ALLOCATION'; END IF;
   IF NOT EXISTS(SELECT 1 FROM eshop.orders o JOIN public.occasions c ON c.id=o.occasion
    WHERE o.created_at <@ tstzrange(agreement.valid_from,agreement.valid_until,'[)') AND o.id=(allocation->>'orderId')::bigint AND c.unit=agreement.unit_id AND c.organization=agreement.organization_id AND NOT public.is_demo_occasion(c.id)) THEN
    RAISE check_violation USING MESSAGE='FEE_ORDER_SCOPE_MISMATCH'; END IF;
   SELECT created_at INTO STRICT order_at FROM eshop.orders WHERE id=(allocation->>'orderId')::bigint;
   SELECT * INTO proof FROM eshop.order_checkout_origins WHERE order_id=(allocation->>'orderId')::bigint;
  ELSE
   SELECT * INTO STRICT origin FROM public.service_fee_allocations WHERE id=(allocation->>'originalAllocationId')::uuid;
   IF origin.settlement_id<>original.id OR origin.order_id<>(allocation->>'orderId')::bigint THEN
    RAISE check_violation USING MESSAGE='FEE_REFUND_ALLOCATION_MISMATCH'; END IF;
   IF (SELECT coalesce(sum(fee_minor),0) FROM public.service_fee_allocations WHERE original_allocation_id=origin.id)+amount>origin.fee_minor
    OR (SELECT coalesce(sum(agreed_expenses_minor),0) FROM public.service_fee_allocations WHERE original_allocation_id=origin.id)+expenses>origin.agreed_expenses_minor
    OR (SELECT coalesce(sum(fee_minor-agreed_expenses_minor),0) FROM public.service_fee_allocations WHERE original_allocation_id=origin.id)+amount-expenses>origin.fee_minor-origin.agreed_expenses_minor THEN
    RAISE check_violation USING MESSAGE='FEE_REFUND_EXCEEDS_ALLOCATION'; END IF;
  END IF;
  INSERT INTO public.service_fee_allocations(id,settlement_id,order_id,order_created_at,original_allocation_id,fee_minor,
   agreed_expenses_minor,expense_approval_reference,instance_id,instance_verification_reference,order_origin_snapshot,fx,wix_share_bps,partner_terms_reference) VALUES(allocation_id,ident,(allocation->>'orderId')::bigint,coalesce(order_at,origin.order_created_at),origin.id,amount,expenses,
   allocation->>'expenseApprovalReference',coalesce(origin.instance_id,proof.instance_id),
   coalesce(origin.instance_verification_reference,CASE WHEN proof.order_id IS NOT NULL THEN 'public.service_fee_allocations:'||allocation_id||':origin' END),
   CASE WHEN origin.id IS NOT NULL THEN origin.order_origin_snapshot WHEN proof.order_id IS NOT NULL THEN to_jsonb(proof) ELSE NULL END,
   CASE WHEN origin.id IS NULL THEN allocation->'fx' ELSE NULL END,
   CASE WHEN origin.id IS NULL THEN (allocation->>'wixShareBps')::integer ELSE NULL END,
   CASE WHEN origin.id IS NULL THEN allocation->>'partnerTermsReference' ELSE NULL END);
 END LOOP;
 IF total<>(p_input->>'feeMinor')::numeric THEN RAISE check_violation USING MESSAGE='FEE_ALLOCATION_TOTAL_MISMATCH'; END IF;
 RETURN ident;
END $$;

-- Full history is intentional: projection validates preceding refunds before
-- filtering by month. Wix eligibility requires acquisition AND order origin.
CREATE OR REPLACE FUNCTION public.export_wix_service_fee_receipts(p_organization bigint,p_partner_terms text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 IF p_partner_terms IS NULL OR length(btrim(p_partner_terms))=0 THEN RAISE invalid_parameter_value USING MESSAGE='PARTNER_TERMS_REQUIRED'; END IF;
 RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object(
  'id',a.id,'kind',s.kind,'sourceReference',s.source_reference||'#'||a.id,
  'productName','Ticketing service fee','instanceId',a.instance_id,'instanceVerificationReference',a.instance_verification_reference,
  'occurredAt',to_char(s.settled_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  'currency',s.currency,'amountBasis','settled-service-fee-excluding-tax','feeMinor',a.fee_minor::text,
  'agreedExpensesMinor',a.agreed_expenses_minor::text,'expenseApprovalReference',a.expense_approval_reference,
  'organizerAgreementReference',g.source_reference,'organizerFeeRateBps',g.fee_rate_bps,
  'customerOrigin',c.channel,'customerOriginEvidenceReference',c.evidence_reference,
  'fx',a.fx,'wixShareBps',a.wix_share_bps,'chargeReceiptId',a.original_allocation_id
 ) ORDER BY s.settled_at,a.id),'[]'::jsonb)
 FROM public.service_fee_allocations a JOIN public.service_fee_settlements s ON s.id=a.settlement_id
 JOIN public.service_fee_agreements g ON g.id=s.agreement_id JOIN public.units u ON u.id=g.unit_id
 JOIN public.service_fee_customer_acquisitions c ON c.unit_id=u.id
 LEFT JOIN public.service_fee_allocations original ON original.id=a.original_allocation_id

 WHERE g.organization_id=p_organization AND c.channel='wix' AND c.acquired_at<=a.order_created_at
  AND a.instance_id IS NOT NULL AND coalesce(original.partner_terms_reference,a.partner_terms_reference)=p_partner_terms);
END $$;

REVOKE ALL ON FUNCTION public.register_service_fee_agreement(uuid,bigint,text,integer,timestamptz,timestamptz),
 public.end_service_fee_agreement(uuid,timestamptz,text),public.register_service_fee_acquisition(bigint,text,timestamptz,text),public.record_service_fee_settlement(jsonb),
 public.export_wix_service_fee_receipts(bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.register_service_fee_agreement(uuid,bigint,text,integer,timestamptz,timestamptz),
 public.end_service_fee_agreement(uuid,timestamptz,text),public.register_service_fee_acquisition(bigint,text,timestamptz,text),public.record_service_fee_settlement(jsonb),
 public.export_wix_service_fee_receipts(bigint,text) TO service_role;

-- Source: database/tables/wix_billing_delivery.sql
-- Delivery metadata only; economic facts belong to service_fee_*.
CREATE TABLE IF NOT EXISTS public.wix_billing_activation (
 app_id uuid PRIMARY KEY,
 enabled boolean NOT NULL DEFAULT false,
 signed_addendum_reference text,
 activation_reference text,
 settlement_source_reference text,
 acquisition_source_reference text,
 CHECK(NOT enabled OR (
  coalesce(length(btrim(signed_addendum_reference)),0)>0 AND coalesce(length(btrim(activation_reference)),0)>0
  AND coalesce(length(btrim(settlement_source_reference)),0)>0 AND coalesce(length(btrim(acquisition_source_reference)),0)>0))
);
INSERT INTO public.wix_billing_activation(app_id) VALUES('9c099206-ce3d-43de-bd9d-deb96bb4f51e') ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS public.wix_billing_deliveries (
 app_id uuid NOT NULL REFERENCES public.wix_billing_activation(app_id),
 receipt_id text NOT NULL CHECK(length(receipt_id) BETWEEN 1 AND 1000),
 kind text NOT NULL CHECK(kind IN('CHARGE','REFUND')),
 instance_id uuid NOT NULL,
 payload jsonb NOT NULL,
 payload_digest text NOT NULL,
 state text NOT NULL DEFAULT 'prepared' CHECK(state IN('prepared','sending','confirmed','rejected','unknown')),
 attempt_id uuid,
 lease_until timestamptz,
 reconciliation jsonb NOT NULL DEFAULT '[]',
 PRIMARY KEY(app_id,receipt_id,kind)
);
CREATE TABLE IF NOT EXISTS public.wix_billing_attempts (
 id uuid PRIMARY KEY,
 app_id uuid NOT NULL,
 receipt_id text NOT NULL,
 kind text NOT NULL,
 started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 finished_at timestamptz,
 outcome text CHECK(outcome IN('confirmed','rejected','unknown')),
 evidence jsonb,
 FOREIGN KEY(app_id,receipt_id,kind) REFERENCES public.wix_billing_deliveries(app_id,receipt_id,kind)
);
ALTER TABLE public.wix_billing_activation ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wix_billing_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wix_billing_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.wix_billing_activation,public.wix_billing_deliveries,public.wix_billing_attempts FROM PUBLIC,anon,authenticated,service_role;

-- Source: database/functions/wix_billing/delivery.sql
CREATE OR REPLACE FUNCTION public.stage_wix_billing_delivery(p_app uuid,p_event jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE ident text:=p_event->>'receiptId'; delivery_kind text:=p_event#>>'{requestBody,event,billingType}';
 digest text:=encode(extensions.digest(p_event::text,'sha256'),'hex'); prior public.wix_billing_deliveries;
BEGIN
 PERFORM public.require_service_role();
 IF ident IS NULL OR delivery_kind IS NULL OR p_event->>'instanceId' IS NULL OR jsonb_typeof(p_event#>'{requestBody,event}') IS DISTINCT FROM 'object'
  OR octet_length(p_event::text)>32768 THEN RAISE invalid_parameter_value USING MESSAGE='INVALID_WIX_DELIVERY'; END IF;
 INSERT INTO public.wix_billing_deliveries(app_id,receipt_id,kind,instance_id,payload,payload_digest)
 VALUES(p_app,ident,delivery_kind,(p_event->>'instanceId')::uuid,p_event,digest) ON CONFLICT DO NOTHING;
 SELECT * INTO STRICT prior FROM public.wix_billing_deliveries WHERE app_id=p_app AND receipt_id=ident AND wix_billing_deliveries.kind=delivery_kind FOR UPDATE;
 IF prior.payload_digest<>digest THEN RAISE check_violation USING MESSAGE='WIX_DELIVERY_DIGEST_CONFLICT'; END IF;
 RETURN jsonb_build_object('state',prior.state,'digest',prior.payload_digest);
END $$;

CREATE OR REPLACE FUNCTION public.claim_wix_billing_delivery(p_app uuid,p_receipt text,p_kind text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE row public.wix_billing_deliveries; token uuid:=extensions.gen_random_uuid();
BEGIN
 PERFORM public.require_service_role();
 -- Activation changes serialize with claims. There is intentionally no enable RPC.
 PERFORM 1 FROM public.wix_billing_activation WHERE app_id=p_app AND enabled FOR SHARE;
 IF NOT FOUND THEN RAISE check_violation USING MESSAGE='WIX_BILLING_NOT_ACTIVATED'; END IF;
 SELECT * INTO STRICT row FROM public.wix_billing_deliveries WHERE app_id=p_app AND receipt_id=p_receipt AND kind=p_kind FOR UPDATE;
 IF row.payload->>'agreementReference' IS DISTINCT FROM (SELECT signed_addendum_reference FROM public.wix_billing_activation WHERE app_id=p_app) THEN
  RAISE check_violation USING MESSAGE='WIX_ACTIVATED_TERMS_MISMATCH'; END IF;
 IF row.state='sending' AND row.lease_until<=clock_timestamp() THEN
  UPDATE public.wix_billing_deliveries SET state='unknown',lease_until=NULL WHERE app_id=p_app AND receipt_id=p_receipt AND kind=p_kind;
  UPDATE public.wix_billing_attempts SET outcome='unknown',finished_at=clock_timestamp(),evidence='{"reason":"expired-attempt"}' WHERE id=row.attempt_id;
  RETURN jsonb_build_object('state','unknown');
 END IF;
 IF row.state<>'prepared' THEN RETURN jsonb_build_object('state',row.state); END IF;
 IF p_kind='REFUND' AND NOT EXISTS(SELECT 1 FROM public.wix_billing_deliveries
  WHERE app_id=p_app AND receipt_id=row.payload#>>'{basis,chargeReceiptId}' AND kind='CHARGE'
   AND instance_id=row.instance_id AND state='confirmed') THEN
  RAISE check_violation USING MESSAGE='WIX_ORIGINAL_CHARGE_UNCONFIRMED'; END IF;
 INSERT INTO public.wix_billing_attempts(id,app_id,receipt_id,kind) VALUES(token,p_app,p_receipt,p_kind);
 UPDATE public.wix_billing_deliveries SET state='sending',attempt_id=token,lease_until=clock_timestamp()+interval '60 seconds'
  WHERE app_id=p_app AND receipt_id=p_receipt AND kind=p_kind;
 RETURN jsonb_build_object('state','claimed','attemptId',token,'payload',row.payload,'instanceId',row.instance_id,'digest',row.payload_digest);
END $$;

CREATE OR REPLACE FUNCTION public.finish_wix_billing_delivery(p_app uuid,p_receipt text,p_kind text,p_attempt uuid,p_outcome text,p_evidence jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
BEGIN
 PERFORM public.require_service_role();
 IF p_outcome IS NULL OR p_outcome NOT IN('confirmed','rejected','unknown') OR jsonb_typeof(p_evidence) IS DISTINCT FROM 'object' OR octet_length(p_evidence::text)>8192 THEN
  RAISE invalid_parameter_value USING MESSAGE='INVALID_WIX_OUTCOME'; END IF;
 UPDATE public.wix_billing_deliveries SET state=p_outcome,lease_until=NULL
  WHERE app_id=p_app AND receipt_id=p_receipt AND kind=p_kind AND state='sending' AND attempt_id=p_attempt;
 IF NOT FOUND THEN RAISE check_violation USING MESSAGE='WIX_ATTEMPT_FENCE'; END IF;
 UPDATE public.wix_billing_attempts SET outcome=p_outcome,evidence=p_evidence,finished_at=clock_timestamp() WHERE id=p_attempt;
END $$;

CREATE OR REPLACE FUNCTION public.inspect_wix_billing_delivery(p_app uuid,p_receipt text,p_kind text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE row public.wix_billing_deliveries;
BEGIN
 PERFORM public.require_service_role();
 SELECT * INTO STRICT row FROM public.wix_billing_deliveries WHERE app_id=p_app AND receipt_id=p_receipt AND kind=p_kind FOR UPDATE;
 IF row.state='sending' AND row.lease_until<=clock_timestamp() THEN
  UPDATE public.wix_billing_deliveries SET state='unknown',lease_until=NULL WHERE app_id=p_app AND receipt_id=p_receipt AND kind=p_kind RETURNING * INTO row;
  UPDATE public.wix_billing_attempts SET outcome='unknown',finished_at=clock_timestamp(),evidence='{"reason":"expired-attempt"}' WHERE id=row.attempt_id;
 END IF;
 RETURN to_jsonb(row)||jsonb_build_object('attempts',(SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY started_at),'[]') FROM public.wix_billing_attempts a WHERE a.app_id=p_app AND a.receipt_id=p_receipt AND a.kind=p_kind));
END $$;

CREATE OR REPLACE FUNCTION public.reconcile_wix_billing_delivery(p_app uuid,p_receipt text,p_kind text,p_attempt uuid,p_digest text,p_resolution text,p_evidence_reference text,p_operator_reference text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE row public.wix_billing_deliveries;
BEGIN
 PERFORM public.require_service_role();
 IF p_resolution IS NULL OR p_resolution NOT IN('accepted','proven-not-accepted')
  OR coalesce(length(btrim(p_evidence_reference)),0) NOT BETWEEN 1 AND 1000
  OR coalesce(length(btrim(p_operator_reference)),0) NOT BETWEEN 1 AND 1000 THEN
  RAISE invalid_parameter_value USING MESSAGE='WIX_RECONCILIATION_EVIDENCE_REQUIRED'; END IF;
 SELECT * INTO STRICT row FROM public.wix_billing_deliveries WHERE app_id=p_app AND receipt_id=p_receipt AND kind=p_kind FOR UPDATE;
 IF row.state NOT IN('unknown','rejected') OR row.attempt_id IS DISTINCT FROM p_attempt OR row.payload_digest IS DISTINCT FROM p_digest THEN
  RAISE check_violation USING MESSAGE='WIX_RECONCILIATION_FENCE'; END IF;
 UPDATE public.wix_billing_deliveries SET state=CASE WHEN p_resolution='accepted' THEN 'confirmed' ELSE 'prepared' END,
  reconciliation=reconciliation||jsonb_build_array(jsonb_build_object('attemptId',p_attempt,'digest',p_digest,'resolution',p_resolution,
   'evidenceReference',p_evidence_reference,'operatorReference',p_operator_reference,'at',clock_timestamp()))
  WHERE app_id=p_app AND receipt_id=p_receipt AND kind=p_kind;
 RETURN jsonb_build_object('state',CASE WHEN p_resolution='accepted' THEN 'confirmed' ELSE 'prepared' END);
END $$;

REVOKE ALL ON FUNCTION public.stage_wix_billing_delivery(uuid,jsonb),public.claim_wix_billing_delivery(uuid,text,text),
 public.finish_wix_billing_delivery(uuid,text,text,uuid,text,jsonb),public.inspect_wix_billing_delivery(uuid,text,text),
 public.reconcile_wix_billing_delivery(uuid,text,text,uuid,text,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.stage_wix_billing_delivery(uuid,jsonb),public.claim_wix_billing_delivery(uuid,text,text),
 public.finish_wix_billing_delivery(uuid,text,text,uuid,text,jsonb),public.inspect_wix_billing_delivery(uuid,text,text),
 public.reconcile_wix_billing_delivery(uuid,text,text,uuid,text,text,text,text) TO service_role;

NOTIFY pgrst, 'reload schema';
