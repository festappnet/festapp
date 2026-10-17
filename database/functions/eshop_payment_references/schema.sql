-- Festapp-only registry. A migration installs dormant schema, never activates a tenant.
CREATE TABLE IF NOT EXISTS eshop.payment_reference_scopes (
 organization_id bigint PRIMARY KEY REFERENCES public.organizations(id),
 phase text NOT NULL CHECK(phase IN ('inactive','active','paused')),
 manifest_sha256 text NOT NULL CHECK(manifest_sha256 ~ '^[a-f0-9]{64}$'),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE IF NOT EXISTS eshop.payment_reference_namespaces (
 id text PRIMARY KEY CHECK(id ~ '^[a-f0-9]{64}$'),
 canonical_account text NOT NULL UNIQUE,
 allocation_enabled boolean NOT NULL DEFAULT false,
 manifest_sha256 text CHECK(manifest_sha256 ~ '^[a-f0-9]{64}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
-- Alias tombstones survive bank-account deletion; IDs are never namespace identity.
CREATE TABLE IF NOT EXISTS eshop.payment_reference_accounts (
 bank_account_id bigint PRIMARY KEY,
 namespace_id text NOT NULL REFERENCES eshop.payment_reference_namespaces(id),
 account_number_snapshot text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE IF NOT EXISTS eshop.payment_reference_reservations (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
 namespace_id text NOT NULL REFERENCES eshop.payment_reference_namespaces(id),
 variable_symbol bigint NOT NULL CHECK(variable_symbol BETWEEN 0 AND 9999999999),
 source_ref text NOT NULL CHECK(length(source_ref) BETWEEN 1 AND 255),
 policy jsonb NOT NULL,
 payload_sha256 text NOT NULL CHECK(payload_sha256 ~ '^[a-f0-9]{64}$'),
 payment_info_id bigint REFERENCES eshop.payment_info(id) ON DELETE SET NULL,
 original_payment_info_id bigint,
 form_id bigint,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(namespace_id,variable_symbol),UNIQUE(namespace_id,source_ref)
);
CREATE TABLE IF NOT EXISTS eshop.payment_reference_sequences (
 namespace_id text NOT NULL REFERENCES eshop.payment_reference_namespaces(id),
 form_id bigint NOT NULL,
 high_water bigint NOT NULL CHECK(high_water BETWEEN 1 AND 9999999999),
 PRIMARY KEY(namespace_id,form_id)
);
CREATE TABLE IF NOT EXISTS eshop.payment_reference_form_watermarks (
 form_id bigint PRIMARY KEY,
 high_water bigint NOT NULL CHECK(high_water BETWEEN 0 AND 9999999999)
);
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['payment_reference_scopes','payment_reference_namespaces','payment_reference_accounts',
  'payment_reference_reservations','payment_reference_sequences','payment_reference_form_watermarks'] LOOP
  EXECUTE format('ALTER TABLE eshop.%I OWNER TO postgres',t);
  EXECUTE format('ALTER TABLE eshop.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON eshop.%I FROM PUBLIC,anon,authenticated,service_role',t);
  EXECUTE format('GRANT SELECT ON eshop.%I TO service_role',t);
 END LOOP;
END $$;
