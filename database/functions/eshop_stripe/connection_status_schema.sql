ALTER TABLE eshop.stripe_connections ADD COLUMN status_lease uuid;
ALTER TABLE eshop.stripe_connections ADD COLUMN status_lease_expires_at timestamptz;
ALTER TABLE eshop.stripe_connections ADD COLUMN next_check_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE eshop.stripe_connections ADD COLUMN status_failures integer NOT NULL DEFAULT 0 CHECK(status_failures>=0);
ALTER TABLE eshop.stripe_connections ADD CONSTRAINT stripe_connection_status_lease CHECK((status_lease IS NULL)=(status_lease_expires_at IS NULL));
ALTER TABLE eshop.stripe_connection_audit DROP CONSTRAINT stripe_connection_audit_action_check;
ALTER TABLE eshop.stripe_connection_audit ADD CONSTRAINT stripe_connection_audit_action_check
 CHECK(action IN ('connected','reconnected','replaced','paused','resumed','revoked','status_changed'));
