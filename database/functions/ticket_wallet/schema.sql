-- Provider metadata only. Deliberately retain identities when a ticket is deleted.
CREATE TABLE IF NOT EXISTS eshop.ticket_wallet_integrations (
 organization bigint PRIMARY KEY REFERENCES public.organizations(id),
 issuer text NOT NULL CHECK(issuer ~ '^[0-9]+$'),
 environment text NOT NULL CHECK(environment ~ '^[a-zA-Z0-9_-]{1,40}$'),
 publishing_ready boolean NOT NULL DEFAULT false,
 web_origin text NOT NULL CHECK(web_origin ~ '^https://[^/#?]+$'),
 badge_urls jsonb NOT NULL DEFAULT '{}',
 next_request_at timestamptz NOT NULL DEFAULT now(),
 paused boolean NOT NULL DEFAULT false
);
CREATE TABLE IF NOT EXISTS eshop.ticket_wallet_capabilities (
 ticket_id bigint PRIMARY KEY, organization bigint NOT NULL, occasion bigint NOT NULL,
 order_id bigint NOT NULL, generation integer NOT NULL DEFAULT 1,
 token_hash text UNIQUE NOT NULL CHECK(token_hash ~ '^[a-f0-9]{64}$'),
 sealed jsonb NOT NULL, recipient text NOT NULL, message_id uuid NOT NULL,
 expires_at timestamptz NOT NULL, event_end_at timestamptz, revoked_at timestamptz, reissue_after timestamptz,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS eshop.ticket_wallet_objects (
 ticket_id bigint PRIMARY KEY, organization bigint NOT NULL, occasion bigint NOT NULL,
 issuer text NOT NULL, environment text NOT NULL, object_id text UNIQUE NOT NULL,
 class_id text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS eshop.ticket_wallet_audit (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, ticket_id bigint NOT NULL,
 generation integer NOT NULL, token_hash text NOT NULL, actor uuid NOT NULL, action text NOT NULL CHECK(action IN ('revoke','reissue')),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ticket_wallet_revoked_hash ON eshop.ticket_wallet_audit(token_hash);
CREATE TABLE IF NOT EXISTS eshop.ticket_wallet_limits (
 key text PRIMARY KEY, window_at timestamptz NOT NULL, attempts integer NOT NULL
);
ALTER TABLE eshop.ticket_wallet_integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.ticket_wallet_capabilities ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.ticket_wallet_objects ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.ticket_wallet_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.ticket_wallet_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.ticket_wallet_integrations,eshop.ticket_wallet_capabilities,eshop.ticket_wallet_objects,eshop.ticket_wallet_audit,eshop.ticket_wallet_limits FROM PUBLIC,anon,authenticated;
