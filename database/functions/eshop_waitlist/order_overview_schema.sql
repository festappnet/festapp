-- Forward-only follow-up. The published capacity migration remains immutable.
ALTER TABLE eshop.waitlist_capabilities DROP CONSTRAINT IF EXISTS waitlist_capabilities_kind_check;
ALTER TABLE eshop.waitlist_capabilities DROP CONSTRAINT IF EXISTS waitlist_capabilities_check;
ALTER TABLE eshop.waitlist_capabilities ADD CONSTRAINT waitlist_capabilities_kind_check CHECK(kind IN ('manage','offer','order_view'));
ALTER TABLE eshop.waitlist_capabilities ADD CONSTRAINT waitlist_capabilities_check CHECK(
 (kind='offer' AND offer_id IS NOT NULL AND expires_at IS NOT NULL) OR
 (kind='manage' AND offer_id IS NULL) OR
 (kind='order_view' AND offer_id IS NULL AND expires_at IS NOT NULL));
CREATE TABLE eshop.order_overview_sources (
 token_hash text PRIMARY KEY REFERENCES eshop.waitlist_capabilities(token_hash) ON DELETE CASCADE,
 sealed jsonb NOT NULL, content_hash text NOT NULL CHECK(content_hash ~ '^[0-9a-f]{64}$'),
 created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL,
 command_id uuid NOT NULL UNIQUE);
ALTER TABLE eshop.order_overview_sources ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.order_overview_sources FROM PUBLIC,anon,authenticated;
