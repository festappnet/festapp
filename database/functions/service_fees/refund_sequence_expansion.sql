-- Deployed v1 has no business facts. Never infer a sequence for sent history.
LOCK TABLE public.wix_billing_activation IN SHARE MODE;
LOCK TABLE public.service_fee_settlements,public.service_fee_allocations,public.wix_billing_deliveries IN ACCESS EXCLUSIVE MODE;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.service_fee_allocations) OR EXISTS(SELECT 1 FROM public.service_fee_settlements)
  OR EXISTS(SELECT 1 FROM public.wix_billing_deliveries) OR EXISTS(SELECT 1 FROM public.wix_billing_activation WHERE enabled) THEN
  RAISE check_violation USING MESSAGE='WIX_REPORT_V2_REQUIRES_EMPTY_DISABLED_SOURCE'; END IF;
END $$;
ALTER TABLE public.service_fee_allocations ADD COLUMN refund_sequence bigint NOT NULL;
ALTER TABLE public.service_fee_allocations ADD CONSTRAINT service_fee_refund_sequence_scope
 CHECK((original_allocation_id IS NULL AND refund_sequence=0) OR (original_allocation_id IS NOT NULL AND refund_sequence>0));
ALTER TABLE public.service_fee_allocations ADD CONSTRAINT service_fee_refund_sequence_unique UNIQUE(original_allocation_id,refund_sequence);
