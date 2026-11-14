-- Explicit rollout readiness; shared backend deployment does not activate other tenants.
ALTER TABLE eshop.ticket_wallet_integrations ADD COLUMN IF NOT EXISTS collection_enabled boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS eshop.ticket_wallet_collections (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization bigint NOT NULL, occasion bigint NOT NULL, order_id bigint NOT NULL,
 recipient text NOT NULL, message_id uuid NOT NULL,
 members jsonb NOT NULL CHECK(jsonb_typeof(members)='array' AND jsonb_array_length(members) BETWEEN 2 AND 1000),
 fingerprint text NOT NULL CHECK(fingerprint ~ '^[a-f0-9]{64}$'),
 token_hash text UNIQUE NOT NULL CHECK(token_hash ~ '^[a-f0-9]{64}$'),
 sealed jsonb NOT NULL, event_end_at timestamptz NOT NULL, expires_at timestamptz NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), revoked_at timestamptz,
 UNIQUE(organization,occasion,order_id,recipient,fingerprint)
);
ALTER TABLE eshop.ticket_wallet_collections ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.ticket_wallet_collections FROM PUBLIC,anon,authenticated;
