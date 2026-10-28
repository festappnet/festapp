-- Shared validation of retained evidence references; no data or money calculation.
CREATE OR REPLACE FUNCTION public.service_fee_reference_valid_internal(p_value text)
RETURNS boolean LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=public,extensions AS $$
 SELECT p_value IS NOT NULL
  AND length(btrim(p_value,U&' \00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF'))>0
  AND p_value !~ '[[:cntrl:]]'
  -- Match JavaScript's UTF-16 length limit, including supplementary characters.
  AND (SELECT coalesce(sum(CASE WHEN ascii(c)>65535 THEN 2 ELSE 1 END),0)
       FROM unnest(string_to_array(p_value,NULL)) AS chars(c))<=1000
$$;
REVOKE ALL ON FUNCTION public.service_fee_reference_valid_internal(text) FROM PUBLIC,anon,authenticated,service_role;

-- Deliberate operator import of real contract and accounting evidence. No UI or
-- tenant admin may assert platform income. Replay cannot amend historical facts.
CREATE OR REPLACE FUNCTION public.register_service_fee_agreement(p_id uuid,p_unit bigint,p_reference text,p_rate_bps integer,p_from timestamptz,p_until timestamptz DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,extensions AS $$
DECLARE prior public.service_fee_agreements;
BEGIN
 PERFORM public.require_service_role();
 IF NOT public.service_fee_reference_valid_internal(p_reference) OR NOT isfinite(p_from)
  OR (p_until IS NOT NULL AND NOT isfinite(p_until)) THEN
  RAISE invalid_parameter_value USING MESSAGE='INVALID_FEE_AGREEMENT'; END IF;
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
 IF p_until IS NULL OR NOT isfinite(p_until) OR p_until<=prior.valid_from OR NOT public.service_fee_reference_valid_internal(p_evidence) THEN
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
 IF NOT public.service_fee_reference_valid_internal(p_evidence) OR NOT isfinite(p_acquired_at) THEN
  RAISE invalid_parameter_value USING MESSAGE='INVALID_FEE_ACQUISITION'; END IF;
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
 expenses numeric; amount numeric; allocation_id uuid; order_at timestamptz; refund_sequence bigint;
BEGIN
 PERFORM public.require_service_role();
 IF jsonb_typeof(p_input) IS DISTINCT FROM 'object' OR octet_length(p_input::text)>1048576
  OR jsonb_typeof(p_input->'allocations') IS DISTINCT FROM 'array' OR jsonb_array_length(p_input->'allocations') NOT BETWEEN 1 AND 1000 THEN
  RAISE invalid_parameter_value USING MESSAGE='INVALID_FEE_SETTLEMENT'; END IF;
 SELECT * INTO STRICT agreement FROM public.service_fee_agreements WHERE id=(p_input->>'agreementId')::uuid;
 -- Serialize imports/refunds for this customer, including aggregate caps.
 PERFORM 1 FROM public.units WHERE id=agreement.unit_id FOR UPDATE;
 -- A termination can commit while the importer waits for the customer lock.
 SELECT * INTO STRICT agreement FROM public.service_fee_agreements WHERE id=(p_input->>'agreementId')::uuid;
 SELECT * INTO prior FROM public.service_fee_settlements WHERE id=ident;
 IF FOUND THEN
  IF prior.input_digest<>digest THEN RAISE check_violation USING MESSAGE='FEE_SETTLEMENT_REPLAY_CONFLICT'; END IF;
  RETURN ident;
 END IF;
 IF NOT public.service_fee_reference_valid_internal(p_input->>'sourceReference')
  OR NOT isfinite((p_input->>'settledAt')::timestamptz) OR NOT isfinite((p_input->>'serviceAt')::timestamptz) THEN
  RAISE invalid_parameter_value USING MESSAGE='INVALID_FEE_SETTLEMENT_EVIDENCE'; END IF;
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
  proof:=NULL; origin:=NULL; order_at:=NULL; refund_sequence:=0;
  IF expenses>0 AND NOT public.service_fee_reference_valid_internal(allocation->>'expenseApprovalReference') THEN
   RAISE invalid_parameter_value USING MESSAGE='INVALID_FEE_EXPENSE_EVIDENCE'; END IF;
  IF p_input->>'kind'='charge' THEN
   IF allocation->>'originalAllocationId' IS NOT NULL THEN RAISE check_violation USING MESSAGE='INVALID_FEE_ALLOCATION'; END IF;
   IF NOT EXISTS(SELECT 1 FROM eshop.orders o JOIN public.occasions c ON c.id=o.occasion
    WHERE o.created_at <@ tstzrange(agreement.valid_from,agreement.valid_until,'[)') AND o.id=(allocation->>'orderId')::bigint AND c.unit=agreement.unit_id AND c.organization=agreement.organization_id AND NOT public.is_demo_occasion(c.id)) THEN
    RAISE check_violation USING MESSAGE='FEE_ORDER_SCOPE_MISMATCH'; END IF;
   SELECT created_at INTO STRICT order_at FROM eshop.orders WHERE id=(allocation->>'orderId')::bigint;
   SELECT * INTO proof FROM eshop.order_checkout_origins WHERE order_id=(allocation->>'orderId')::bigint;
   IF allocation->>'partnerTermsReference' IS NOT NULL THEN
    IF NOT public.service_fee_reference_valid_internal(agreement.source_reference)
     OR EXISTS(SELECT 1 FROM public.service_fee_customer_acquisitions c WHERE c.unit_id=agreement.unit_id AND NOT public.service_fee_reference_valid_internal(c.evidence_reference))
     OR NOT public.service_fee_reference_valid_internal(allocation->>'partnerTermsReference')
     OR jsonb_typeof(allocation->'fx') IS DISTINCT FROM 'object'
     OR jsonb_typeof(allocation#>'{fx,reference}') IS DISTINCT FROM 'string'
     OR NOT public.service_fee_reference_valid_internal(allocation#>>'{fx,reference}')
     OR jsonb_typeof(allocation#>'{fx,usdMinorNumerator}') IS DISTINCT FROM 'string'
     OR jsonb_typeof(allocation#>'{fx,sourceMinorDenominator}') IS DISTINCT FROM 'string'
     OR coalesce(allocation#>>'{fx,usdMinorNumerator}','') !~ '^[1-9][0-9]{0,29}$'
     OR coalesce(allocation#>>'{fx,sourceMinorDenominator}','') !~ '^[1-9][0-9]{0,29}$'
     OR jsonb_typeof(allocation->'wixShareBps') IS DISTINCT FROM 'number'
     OR coalesce(allocation->>'wixShareBps','') !~ '^(0|[1-9][0-9]{0,3}|10000)$'
     OR (p_input->>'currency'='USD' AND allocation#>>'{fx,usdMinorNumerator}' IS DISTINCT FROM allocation#>>'{fx,sourceMinorDenominator}') THEN
     RAISE invalid_parameter_value USING MESSAGE='INVALID_WIX_FEE_REPORTING_METADATA'; END IF;
   END IF;
  ELSE
   SELECT * INTO STRICT origin FROM public.service_fee_allocations WHERE id=(allocation->>'originalAllocationId')::uuid;
   -- Serialized import order, not provider dates or random UUID order, owns
   -- cumulative rounding. Late facts append without repricing earlier receipts.
   SELECT coalesce(max(a.refund_sequence),0)+1 INTO refund_sequence
    FROM public.service_fee_allocations a WHERE a.original_allocation_id=origin.id;
   IF origin.settlement_id<>original.id OR origin.order_id<>(allocation->>'orderId')::bigint THEN
    RAISE check_violation USING MESSAGE='FEE_REFUND_ALLOCATION_MISMATCH'; END IF;
   IF (SELECT coalesce(sum(fee_minor),0) FROM public.service_fee_allocations WHERE original_allocation_id=origin.id)+amount>origin.fee_minor
    OR (SELECT coalesce(sum(agreed_expenses_minor),0) FROM public.service_fee_allocations WHERE original_allocation_id=origin.id)+expenses>origin.agreed_expenses_minor
    OR (SELECT coalesce(sum(fee_minor-agreed_expenses_minor),0) FROM public.service_fee_allocations WHERE original_allocation_id=origin.id)+amount-expenses>origin.fee_minor-origin.agreed_expenses_minor THEN
    RAISE check_violation USING MESSAGE='FEE_REFUND_EXCEEDS_ALLOCATION'; END IF;
  END IF;
  INSERT INTO public.service_fee_allocations(id,settlement_id,order_id,order_created_at,original_allocation_id,refund_sequence,fee_minor,
   agreed_expenses_minor,expense_approval_reference,instance_id,instance_verification_reference,order_origin_snapshot,fx,wix_share_bps,partner_terms_reference) VALUES(allocation_id,ident,(allocation->>'orderId')::bigint,coalesce(order_at,origin.order_created_at),origin.id,refund_sequence,amount,expenses,
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
 RETURN jsonb_build_object('schemaVersion',2,'receipts',(SELECT coalesce(jsonb_agg(jsonb_build_object(
  'id',a.id,'kind',s.kind,'sourceReference',s.source_reference,
  'productName','Ticketing service fee','instanceId',a.instance_id,'instanceVerificationReference',a.instance_verification_reference,
  'occurredAt',to_char(s.settled_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  'currency',s.currency,'amountBasis','settled-service-fee-excluding-tax','feeMinor',a.fee_minor::text,
  'refundSequence',a.refund_sequence::text,'agreedExpensesMinor',a.agreed_expenses_minor::text,'expenseApprovalReference',a.expense_approval_reference,
  'organizerAgreementReference',g.source_reference,'organizerFeeRateBps',g.fee_rate_bps,
  'customerOrigin',c.channel,'customerOriginEvidenceReference',c.evidence_reference,
  'fx',a.fx,'wixShareBps',a.wix_share_bps,'chargeReceiptId',a.original_allocation_id
 ) ORDER BY s.settled_at,a.id),'[]'::jsonb)
 FROM public.service_fee_allocations a JOIN public.service_fee_settlements s ON s.id=a.settlement_id
 JOIN public.service_fee_agreements g ON g.id=s.agreement_id JOIN public.units u ON u.id=g.unit_id
 JOIN public.service_fee_customer_acquisitions c ON c.unit_id=u.id
 LEFT JOIN public.service_fee_allocations original ON original.id=a.original_allocation_id

 WHERE g.organization_id=p_organization AND c.channel='wix' AND c.acquired_at<=a.order_created_at
  AND a.instance_id IS NOT NULL AND coalesce(original.partner_terms_reference,a.partner_terms_reference)=p_partner_terms));
END $$;

REVOKE ALL ON FUNCTION public.register_service_fee_agreement(uuid,bigint,text,integer,timestamptz,timestamptz),
 public.end_service_fee_agreement(uuid,timestamptz,text),public.register_service_fee_acquisition(bigint,text,timestamptz,text),public.record_service_fee_settlement(jsonb),
 public.export_wix_service_fee_receipts(bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.register_service_fee_agreement(uuid,bigint,text,integer,timestamptz,timestamptz),
 public.end_service_fee_agreement(uuid,timestamptz,text),public.register_service_fee_acquisition(bigint,text,timestamptz,text),public.record_service_fee_settlement(jsonb),
 public.export_wix_service_fee_receipts(bigint,text) TO service_role;
