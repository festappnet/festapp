-- Unified method installation and durable operation intents. No tenant activation.
ALTER TABLE eshop.bank_sync_connections ADD COLUMN IF NOT EXISTS refund_rf_verified boolean NOT NULL DEFAULT false;
ALTER TABLE eshop.payment_providers ADD COLUMN IF NOT EXISTS refund_write_enabled boolean NOT NULL DEFAULT false;
ALTER TABLE eshop.payment_providers ADD COLUMN IF NOT EXISTS hosted_checkout boolean NOT NULL DEFAULT false;
ALTER TABLE eshop.payment_providers ADD COLUMN IF NOT EXISTS operation_mode text;
ALTER TABLE eshop.payment_providers ADD COLUMN IF NOT EXISTS verification text;
DO $$ DECLARE c record; BEGIN
 FOR c IN SELECT conname FROM pg_constraint WHERE conrelid='eshop.payment_providers'::regclass AND contype='c'
  AND pg_get_constraintdef(oid) LIKE '%handler%' LOOP
  EXECUTE format('ALTER TABLE eshop.payment_providers DROP CONSTRAINT %I',c.conname);
 END LOOP;
END $$;
UPDATE eshop.payment_providers SET hosted_checkout=source_field IS NOT NULL,
 operation_mode=CASE WHEN source_field IS NOT NULL THEN 'remote' ELSE 'local' END,
 verification=CASE WHEN source_field IS NOT NULL THEN 'verified_provider_observation' ELSE 'local_commit' END;
CREATE TABLE IF NOT EXISTS eshop.refund_requests (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
 order_id bigint NOT NULL REFERENCES eshop.orders(id) ON DELETE RESTRICT,
 payment_info bigint NOT NULL REFERENCES eshop.payment_info(id) ON DELETE RESTRICT,
 method text NOT NULL REFERENCES eshop.payment_providers(provider_key),
 amount numeric(12,2) NOT NULL CHECK(amount>0),currency text NOT NULL,
 status text NOT NULL CHECK(status IN ('pending','processing','unknown','succeeded','cancelled','failed')),
 source_account bigint REFERENCES eshop.bank_accounts(id) ON DELETE RESTRICT,
 reference_namespace text REFERENCES eshop.payment_reference_namespaces(id),
 variable_symbol bigint,creditor_reference text,
 payload jsonb NOT NULL DEFAULT '{}',
 created_at timestamptz NOT NULL DEFAULT now(),
 created_by uuid REFERENCES public.user_info(id) ON DELETE SET NULL,
 lease_token uuid,lease_until timestamptz,dispatched_at timestamptz,
 provider_refund_id text,result jsonb,updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS refund_requests_bank_pending ON eshop.refund_requests(payment_info)
 WHERE method='bank' AND status IN ('pending','processing','unknown');
CREATE TABLE IF NOT EXISTS eshop.refund_settlements (
 transaction_id bigint PRIMARY KEY REFERENCES eshop.transactions(id) ON DELETE RESTRICT,
 request_id uuid REFERENCES eshop.refund_requests(id) ON DELETE RESTRICT,
 created_at timestamptz NOT NULL DEFAULT now(),
 voided_at timestamptz,void_reason text,
 actor uuid REFERENCES public.user_info(id) ON DELETE SET NULL,
 CHECK ((voided_at IS NULL)=(void_reason IS NULL))
);
CREATE TABLE IF NOT EXISTS eshop.payment_operation_events (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 request_id uuid NOT NULL REFERENCES eshop.refund_requests(id) ON DELETE RESTRICT,
 operation text NOT NULL,actor uuid REFERENCES public.user_info(id) ON DELETE SET NULL,
 details jsonb NOT NULL DEFAULT '{}',created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE eshop.refund_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.refund_settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.payment_operation_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.refund_requests,eshop.refund_settlements,eshop.payment_operation_events FROM PUBLIC,anon,authenticated,service_role;
-- No current application producer exists. Retain historical requests read-only;
-- future writes must enter the same authorized command boundary.
REVOKE INSERT,UPDATE,DELETE ON eshop.bank_account_requests FROM PUBLIC,anon,authenticated,service_role;

-- A destructive remote preflight fences subsequent money operations until its
-- same receipted deletion completes. Uncertain external deletion never times out.
CREATE TABLE IF NOT EXISTS eshop.order_deletion_fences (
 order_id bigint PRIMARY KEY REFERENCES eshop.orders(id) ON DELETE CASCADE,
 command_id uuid NOT NULL,created_by uuid REFERENCES public.user_info(id) ON DELETE SET NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE eshop.order_deletion_fences ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.order_deletion_fences FROM PUBLIC,anon,authenticated,service_role;
