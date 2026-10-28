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
