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
 refund_sequence bigint NOT NULL,
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
 CHECK((original_allocation_id IS NULL AND refund_sequence=0) OR (original_allocation_id IS NOT NULL AND refund_sequence>0)),
 UNIQUE(original_allocation_id,refund_sequence),
 UNIQUE(settlement_id,order_id)
);
ALTER TABLE public.service_fee_agreements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_fee_customer_acquisitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_fee_settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_fee_allocations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.service_fee_agreements,public.service_fee_customer_acquisitions,
 public.service_fee_settlements,public.service_fee_allocations FROM PUBLIC,anon,authenticated,service_role;
