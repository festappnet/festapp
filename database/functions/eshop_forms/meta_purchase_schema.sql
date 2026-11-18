-- Provision one approved connector per organizer. The token itself lives in Vault.
CREATE TABLE analytics.meta_purchase_connectors (
 unit bigint PRIMARY KEY REFERENCES public.units(id) ON DELETE CASCADE,
 dataset text NOT NULL CHECK(dataset ~ '^[0-9]{5,30}$'),
 vault_secret uuid NOT NULL UNIQUE,
 website_origin text NOT NULL CHECK(website_origin ~ '^https://[a-z0-9.-]+$'),
 revision uuid NOT NULL DEFAULT gen_random_uuid(),
 enabled boolean NOT NULL DEFAULT false,
 test_event_code text CHECK(test_event_code ~ '^[A-Za-z0-9_-]{1,60}$'),
 paused_at timestamptz
);
CREATE TABLE analytics.meta_purchase_forms (
 form bigint PRIMARY KEY REFERENCES public.forms(id) ON DELETE CASCADE,
 unit bigint NOT NULL REFERENCES analytics.meta_purchase_connectors(unit) ON DELETE CASCADE
);
CREATE TABLE analytics.meta_purchase_deliveries (
 order_id bigint PRIMARY KEY REFERENCES eshop.orders(id) ON DELETE CASCADE,
 unit bigint NOT NULL REFERENCES analytics.meta_purchase_connectors(unit) ON DELETE CASCADE,
 connector_revision uuid NOT NULL,
 consent_revision text NOT NULL,
 consent_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 consent_snapshot jsonb,
 consent_scope text,
 consent_decided_at timestamptz,
 email_hash text,
 client_agent text,
 source_url text,
 revoked_at timestamptz,
 next_attempt_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 attempts integer NOT NULL DEFAULT 0,
 lease uuid,
 lease_until timestamptz,
 prepared boolean NOT NULL DEFAULT false,
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','sent','revoked','expired','invalid','failed')),
 done_at timestamptz,
 error_code text
);
CREATE INDEX meta_purchase_delivery_due ON analytics.meta_purchase_deliveries(next_attempt_at,order_id)
 WHERE status='pending';
ALTER TABLE analytics.meta_purchase_connectors ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.meta_purchase_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.meta_purchase_forms ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON analytics.meta_purchase_connectors,analytics.meta_purchase_forms,analytics.meta_purchase_deliveries FROM PUBLIC,anon,authenticated,service_role;
