-- Additive only. Historical amounts come from sold JSON, never today's catalogue.
CREATE TABLE IF NOT EXISTS eshop.discount_codes (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 occasion bigint NOT NULL, -- retained scope identity, including after occasion deletion
 normalized_code text NOT NULL CHECK (normalized_code COLLATE "C" ~ '^[A-Z0-9-]{4,32}$'),
 kind text NOT NULL CHECK(kind IN ('percent','fixed')),
 value numeric NOT NULL CHECK(value>0 AND value::text NOT IN ('NaN','Infinity','-Infinity')),
 currency_code text,
 form_ids bigint[] NOT NULL DEFAULT '{}', product_ids bigint[] NOT NULL DEFAULT '{}',
 valid_from timestamptz, valid_until timestamptz,
 usage_limit bigint CHECK(usage_limit>0), is_active boolean NOT NULL DEFAULT false,
 revision bigint NOT NULL DEFAULT 1,
 created_by uuid NOT NULL, updated_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(occasion,normalized_code),
 CHECK(valid_until IS NULL OR valid_from IS NULL OR valid_until>valid_from),
 CHECK((kind='percent' AND value=trunc(value) AND value<=10000 AND currency_code IS NULL)
 OR (kind='fixed' AND currency_code ~ '^[A-Z]{3}$'))
);
-- No cascading FK to orders/items/products: the receipt survives deletion/storno.
CREATE TABLE IF NOT EXISTS eshop.order_discounts (
 order_id bigint PRIMARY KEY, code_id bigint NOT NULL REFERENCES eshop.discount_codes(id),
 command_id uuid NOT NULL UNIQUE, snapshot jsonb NOT NULL,
 base_amount numeric(10,2) NOT NULL, discount_amount numeric(10,2) NOT NULL,
 net_amount numeric(10,2) NOT NULL, currency_code text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK(base_amount>=discount_amount AND discount_amount>0 AND net_amount=base_amount-discount_amount)
);
CREATE INDEX IF NOT EXISTS order_discounts_code_idx ON eshop.order_discounts(code_id);
CREATE TABLE IF NOT EXISTS eshop.discount_code_audit (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, code_id bigint NOT NULL REFERENCES eshop.discount_codes(id),
 actor uuid NOT NULL, revision bigint NOT NULL, definition jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), UNIQUE(code_id,revision)
);
ALTER TABLE eshop.discount_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.order_discounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.discount_code_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.discount_codes,eshop.order_discounts,eshop.discount_code_audit FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON SEQUENCE eshop.discount_codes_id_seq,eshop.discount_code_audit_id_seq FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE eshop.order_product_ticket ADD COLUMN IF NOT EXISTS base_price numeric(10,2);
ALTER TABLE eshop.order_product_ticket ADD COLUMN IF NOT EXISTS discount_amount numeric(10,2) NOT NULL DEFAULT 0;
ALTER TABLE eshop.order_product_ticket ADD COLUMN IF NOT EXISTS net_price numeric(10,2);
UPDATE eshop.order_product_ticket x SET base_price=(p->>'price')::numeric,net_price=(p->>'price')::numeric
 FROM eshop.orders o CROSS JOIN LATERAL jsonb_array_elements(coalesce(o.data->'tickets','[]')) t
 CROSS JOIN LATERAL jsonb_array_elements(coalesce(t->'products','[]')) p
 WHERE x."order"=o.id AND x.ticket=(t->>'id')::bigint AND x.product=(p->>'id')::bigint AND x.base_price IS NULL;
COMMENT ON COLUMN eshop.order_product_ticket.net_price IS 'Sold net price; orders.data.tickets.products.price has the same net meaning. Unknown historical prices remain NULL.';
-- Reuse central bounded abuse accounting, including unsuccessful lookups.
INSERT INTO public.abuse_policy_rules(rule_key,budget_key,scope_kind,kind,window_seconds,bucket_seconds,base_limit,hard_cap)
 VALUES('discount.quote.form.minute','discount.quote','recipient','rolling',60,60,120,120),
 ('discount.quote.organization.minute','discount.quote','organization','rolling',60,60,1000,1000)
 ON CONFLICT(rule_key) DO NOTHING;
