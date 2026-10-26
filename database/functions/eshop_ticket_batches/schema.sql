-- Tickets/OPT remain the sole admission/product identities. No historical backfill.
ALTER TABLE eshop.orders DROP CONSTRAINT IF EXISTS orders_stock_finance;
ALTER TABLE eshop.orders ADD CONSTRAINT orders_stock_finance
 CHECK(state IS DISTINCT FROM 'stock' OR (price IS NULL AND payment_info IS NULL));
CREATE TABLE IF NOT EXISTS eshop.ticket_batches (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
 occasion bigint NOT NULL REFERENCES public.occasions(id) ON DELETE RESTRICT,
 form bigint NOT NULL REFERENCES public.forms(id) ON DELETE RESTRICT,
 stock_order_id bigint NOT NULL UNIQUE REFERENCES eshop.orders(id) ON DELETE RESTRICT,
 title text NOT NULL CHECK(length(trim(title)) BETWEEN 1 AND 200),
 created_by uuid NOT NULL REFERENCES auth.users(id), created_at timestamptz NOT NULL DEFAULT now(),
 currency_code text NOT NULL CHECK(currency_code ~ '^[A-Z]{3}$'),
 snapshot jsonb NOT NULL CHECK(jsonb_typeof(snapshot)='object'),
 resource_manifest jsonb, manifest_hash text CHECK(manifest_hash ~ '^[a-f0-9]{64}$'),
 CHECK((resource_manifest IS NULL)=(manifest_hash IS NULL))
);
CREATE TABLE IF NOT EXISTS eshop.ticket_batch_items (
 batch_id uuid NOT NULL REFERENCES eshop.ticket_batches(id) ON DELETE RESTRICT,
 ticket_id bigint NOT NULL UNIQUE REFERENCES eshop.tickets(id) ON DELETE RESTRICT,
 ordinal integer NOT NULL CHECK(ordinal BETWEEN 1 AND 200),
 sale_order_id bigint REFERENCES eshop.orders(id) ON DELETE RESTRICT,
 PRIMARY KEY(batch_id,ticket_id), UNIQUE(batch_id,ordinal)
);
CREATE INDEX IF NOT EXISTS ticket_batch_items_sale_order ON eshop.ticket_batch_items(sale_order_id) WHERE sale_order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ticket_batches_occasion ON eshop.ticket_batches(occasion,created_at,id);
CREATE TABLE IF NOT EXISTS eshop.ticket_batch_document_parts (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
 batch_id uuid NOT NULL REFERENCES eshop.ticket_batches(id) ON DELETE RESTRICT,
 part_key text NOT NULL, kind text NOT NULL CHECK(kind IN ('single','print')),
 ticket_ids bigint[] NOT NULL CHECK(cardinality(ticket_ids) BETWEEN 1 AND 20),
 manifest_hash text NOT NULL CHECK(manifest_hash ~ '^[a-f0-9]{64}$'),
 object_key text, content_digest text CHECK(content_digest ~ '^[a-f0-9]{64}$'),
 page_count integer CHECK(page_count BETWEEN 1 AND 20), byte_count bigint CHECK(byte_count BETWEEN 1 AND 16777216),
 state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','rendering','ready','failed')),
 lease_token uuid, lease_expires_at timestamptz, error_code text,
 UNIQUE(batch_id,part_key),
 CHECK(state<>'ready' OR (object_key IS NOT NULL AND content_digest IS NOT NULL AND page_count IS NOT NULL AND byte_count IS NOT NULL)),
 CHECK(state<>'rendering' OR (lease_token IS NOT NULL AND lease_expires_at IS NOT NULL))
);
ALTER TABLE eshop.ticket_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.ticket_batch_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.ticket_batch_document_parts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.ticket_batches,eshop.ticket_batch_items,eshop.ticket_batch_document_parts FROM PUBLIC,anon,authenticated;
-- The canonical database administrator owns fixture/maintenance access even
-- when a local extension-owning administrator installs this migration.
GRANT ALL ON eshop.ticket_batches,eshop.ticket_batch_items,eshop.ticket_batch_document_parts TO postgres;
ALTER TABLE eshop.ticket_batches ADD COLUMN IF NOT EXISTS resource_lease_token uuid;
ALTER TABLE eshop.ticket_batches ADD COLUMN IF NOT EXISTS resource_lease_actor uuid REFERENCES auth.users(id);
ALTER TABLE eshop.ticket_batches ADD COLUMN IF NOT EXISTS resource_lease_expires_at timestamptz;
ALTER TABLE eshop.ticket_batches ADD COLUMN IF NOT EXISTS resource_error_code text;
ALTER TABLE eshop.ticket_batch_document_parts ADD COLUMN IF NOT EXISTS lease_actor uuid REFERENCES auth.users(id);
