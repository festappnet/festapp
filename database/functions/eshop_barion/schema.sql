-- Sandbox-only connector. Credentials live outside SQL. No sales activation.
CREATE TABLE eshop.barion_connections (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
 organization_id bigint NOT NULL REFERENCES public.organizations(id),
 unit_id bigint NOT NULL REFERENCES public.units(id),
 account_id text NOT NULL UNIQUE CHECK(account_id ~ '^[a-f0-9]{32}$'),
 enabled boolean NOT NULL DEFAULT false,
 sandbox_form_ids bigint[] NOT NULL DEFAULT '{}',
 business_name text NOT NULL,
 UNIQUE(id,organization_id,unit_id)
);
ALTER TABLE eshop.payment_info ADD COLUMN barion_connection_id uuid REFERENCES eshop.barion_connections(id);
ALTER TABLE eshop.payment_info ADD CONSTRAINT payment_info_barion_identity CHECK((payment_method='barion')=(barion_connection_id IS NOT NULL));
CREATE TABLE eshop.barion_attempts (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
 order_id bigint NOT NULL UNIQUE REFERENCES eshop.orders(id),
 payment_info_id bigint NOT NULL UNIQUE REFERENCES eshop.payment_info(id),
 organization_id bigint NOT NULL, unit_id bigint NOT NULL, connection_id uuid NOT NULL,
 amount_minor bigint NOT NULL CHECK(amount_minor BETWEEN 1 AND 1000000000),
 currency text NOT NULL CHECK(currency IN ('CZK','EUR','USD')),
 state text NOT NULL DEFAULT 'preparing' CHECK(state IN ('preparing','open','uncertain','paid','expired','action_required')),
 created_at timestamptz NOT NULL DEFAULT date_trunc('second',clock_timestamp()),
 reservation_expires_at timestamptz NOT NULL,
 return_base_url text NOT NULL, locale text NOT NULL DEFAULT 'en',
 remote_id text UNIQUE CHECK(remote_id ~ '^[a-f0-9]{32}$'), checkout_url text,
 dispatched_at timestamptz, lease_token uuid, lease_expires_at timestamptz,
 next_reconcile_at timestamptz NOT NULL DEFAULT now(), last_synced_at timestamptz,
 reconcile_failures integer NOT NULL DEFAULT 0 CHECK(reconcile_failures>=0),
 financial_hold boolean NOT NULL DEFAULT false,
 decisions jsonb NOT NULL DEFAULT '[]',
 FOREIGN KEY(connection_id,organization_id,unit_id) REFERENCES eshop.barion_connections(id,organization_id,unit_id),
 UNIQUE(id,connection_id,currency), UNIQUE(id,order_id),
 CHECK(reservation_expires_at>created_at), CHECK((lease_token IS NULL)=(lease_expires_at IS NULL))
);
CREATE TABLE eshop.barion_movements (
 attempt_id uuid NOT NULL, connection_id uuid NOT NULL, provider_id text NOT NULL CHECK(provider_id ~ '^[a-f0-9]{32}$'),
 kind text NOT NULL CHECK(kind IN ('payment','refund')),
 amount_minor bigint NOT NULL CHECK(amount_minor>0),currency text NOT NULL,occurred_at timestamptz NOT NULL,
 FOREIGN KEY(attempt_id,connection_id,currency) REFERENCES eshop.barion_attempts(id,connection_id,currency),
 PRIMARY KEY(connection_id,provider_id), UNIQUE(attempt_id,provider_id)
);
CREATE UNIQUE INDEX barion_one_original ON eshop.barion_movements(attempt_id) WHERE kind='payment';
CREATE TABLE eshop.barion_capabilities (
 token_hash text PRIMARY KEY CHECK(token_hash ~ '^[a-f0-9]{64}$'),
 attempt_id uuid NOT NULL REFERENCES eshop.barion_attempts(id),
 scope text NOT NULL CHECK(scope IN ('order_pay','return_read','handoff')),
 expires_at timestamptz NOT NULL, consumed_at timestamptz
);
CREATE TABLE eshop.barion_sources (
 attempt_id uuid PRIMARY KEY REFERENCES eshop.barion_attempts(id),command_id uuid NOT NULL UNIQUE,
 token_hash text NOT NULL UNIQUE REFERENCES eshop.barion_capabilities(token_hash),
 sealed jsonb NOT NULL, content_hash text NOT NULL CHECK(content_hash ~ '^[a-f0-9]{64}$')
);
CREATE TABLE eshop.barion_observations (
 attempt_id uuid NOT NULL REFERENCES eshop.barion_attempts(id),
 digest text NOT NULL CHECK(digest ~ '^[a-f0-9]{64}$'),facts jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), PRIMARY KEY(attempt_id,digest)
);
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['barion_connections','barion_attempts','barion_movements','barion_capabilities','barion_sources','barion_observations'] LOOP
  EXECUTE format('ALTER TABLE eshop.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON eshop.%I FROM PUBLIC,anon,authenticated,service_role',t);
 END LOOP;
END $$;
