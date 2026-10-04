-- Automatic import authority is connection-scoped. Alias membership is an
-- explicit reviewed decision, never inferred from VS or account titles.
CREATE TABLE IF NOT EXISTS eshop.bank_sync_connections (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  instance_id text NOT NULL,
  consumer_app_id text NOT NULL CHECK (consumer_app_id = 'festapp'),
  remote_bank_account_id text NOT NULL,
  bank_account_id bigint NOT NULL UNIQUE REFERENCES eshop.bank_accounts(id),
  physical_account text NOT NULL,
  provider text NOT NULL CHECK(provider IN ('FIO','AIRBANK')),
  mode text NOT NULL CHECK(mode IN ('api','email')),
  state text NOT NULL CHECK(state IN ('provisioning','shadow','connected','degraded','suspended')),
  pairing_code text CHECK(pairing_code ~ '^[0-9a-f]{10}$'),
  pairing_history jsonb NOT NULL DEFAULT '[]',
  legacy_blocked_at timestamptz,
  epoch bigint NOT NULL DEFAULT 1,
  manifest_sha256 text NOT NULL CHECK(manifest_sha256 ~ '^[0-9a-f]{64}$'),
  token_expiry_at timestamptz,
  bank_pull_at timestamptz,
  receiver_commit_at timestamptz,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(instance_id,consumer_app_id,remote_bank_account_id),
  UNIQUE(instance_id,provider,physical_account)
);
CREATE TABLE IF NOT EXISTS eshop.bank_sync_account_aliases (
  bank_account_id bigint PRIMARY KEY REFERENCES eshop.bank_accounts(id),
  connection_id bigint NOT NULL REFERENCES eshop.bank_sync_connections(id)
);
CREATE TABLE IF NOT EXISTS eshop.bank_sync_inbox (
  instance_id text NOT NULL,
  consumer_app_id text NOT NULL CHECK(consumer_app_id='festapp'),
  delivery_id text NOT NULL,
  body_sha256 text NOT NULL CHECK(body_sha256 ~ '^[0-9a-f]{64}$'),
  event_version text NOT NULL CHECK(event_version='2'),
  remote_transaction_id text NOT NULL,
  connection_id bigint REFERENCES eshop.bank_sync_connections(id),
  legacy_blocked_at timestamptz,
  epoch bigint,
  payload jsonb NOT NULL CHECK(octet_length(payload::text)<=65536),
  outcome text,
  receipt jsonb,
  received_at timestamptz NOT NULL DEFAULT now(),
  committed_at timestamptz,
  PRIMARY KEY(instance_id,consumer_app_id,delivery_id)
);
CREATE TABLE IF NOT EXISTS eshop.bank_transaction_identities (
  instance_id text NOT NULL,
  provider text NOT NULL,
  physical_account text NOT NULL,
  identity_kind text NOT NULL CHECK(identity_kind IN ('movement','remote_transaction')),
  identity_value text NOT NULL,
  transaction_id bigint NOT NULL REFERENCES eshop.transactions(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(instance_id,provider,physical_account,identity_kind,identity_value)
);
CREATE TABLE IF NOT EXISTS eshop.bank_sync_operations (
  id uuid PRIMARY KEY,
  bank_account_id bigint NOT NULL REFERENCES eshop.bank_accounts(id),
  actor uuid NOT NULL REFERENCES public.user_info(id),
  operation text NOT NULL CHECK(operation IN ('create','set_token','rotate_pairing','sync','suspend','update_details')),
  payload_sha256 text NOT NULL CHECK(payload_sha256 ~ '^[0-9a-f]{64}$'),
  state text NOT NULL CHECK(state IN ('pending','running','uncertain','completed','failed')),
  remote_reference text,
  request jsonb CHECK (request IS NULL OR octet_length(request::text)<=8192),
  token_cipher jsonb,
  lease_token uuid,
  result jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS bank_sync_operations_active_account_uidx ON eshop.bank_sync_operations(bank_account_id) WHERE state IN ('pending','running','uncertain');
ALTER TABLE eshop.bank_sync_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.bank_sync_account_aliases ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.bank_sync_inbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.bank_transaction_identities ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.bank_sync_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.bank_sync_connections,eshop.bank_sync_account_aliases,eshop.bank_sync_inbox,
  eshop.bank_transaction_identities,eshop.bank_sync_operations FROM PUBLIC,anon,authenticated;
