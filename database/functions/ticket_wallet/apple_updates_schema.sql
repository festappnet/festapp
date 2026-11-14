-- Provider-local presentation and registration state; admission stays canonical.
CREATE SEQUENCE IF NOT EXISTS eshop.apple_ticket_wallet_update_tag;
CREATE TABLE IF NOT EXISTS eshop.apple_ticket_wallet_passes (
 ticket_id bigint PRIMARY KEY, organization bigint NOT NULL, occasion bigint NOT NULL,
 environment text NOT NULL, serial text UNIQUE NOT NULL, pass_type text NOT NULL, team text NOT NULL,
 auth_hash text NOT NULL CHECK(auth_hash ~ '^[a-f0-9]{64}$'), auth_sealed jsonb NOT NULL,
 projection jsonb NOT NULL, projection_hash text NOT NULL,
 update_tag bigint NOT NULL DEFAULT nextval('eshop.apple_ticket_wallet_update_tag'),
 updated_at timestamptz NOT NULL DEFAULT date_trunc('second',clock_timestamp()),
 next_check timestamptz NOT NULL DEFAULT now(), lease uuid, lease_until timestamptz,
 failures integer NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS apple_ticket_wallet_due ON eshop.apple_ticket_wallet_passes(next_check,ticket_id);
CREATE TABLE IF NOT EXISTS eshop.apple_ticket_wallet_devices (
 device text NOT NULL, pass_type text NOT NULL, serial text NOT NULL REFERENCES eshop.apple_ticket_wallet_passes(serial),
 push_token text NOT NULL, notified_tag bigint NOT NULL DEFAULT 0,
 PRIMARY KEY(device,pass_type,serial)
);
ALTER TABLE eshop.apple_ticket_wallet_passes ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.apple_ticket_wallet_devices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.apple_ticket_wallet_passes,eshop.apple_ticket_wallet_devices FROM PUBLIC,anon,authenticated;
REVOKE ALL ON SEQUENCE eshop.apple_ticket_wallet_update_tag FROM PUBLIC,anon,authenticated;
