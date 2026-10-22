CREATE TABLE eshop.stripe_connection_flows (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
 state_hash text NOT NULL UNIQUE CHECK(state_hash ~ '^[a-f0-9]{64}$'),
 actor uuid NOT NULL REFERENCES public.user_info(id),
 organization_id bigint NOT NULL REFERENCES public.organizations(id),
 unit_id bigint NOT NULL REFERENCES public.units(id), livemode boolean NOT NULL,
 previous_connection_id uuid REFERENCES eshop.stripe_connections(id),
 state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','claimed','uncertain','completed','denied')),
 lease_token uuid, result jsonb,
 created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL,
 CHECK(expires_at>created_at)
);
CREATE TABLE eshop.stripe_connection_audit (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(), connection_id uuid REFERENCES eshop.stripe_connections(id),
 flow_id uuid REFERENCES eshop.stripe_connection_flows(id), actor uuid REFERENCES public.user_info(id),
 action text NOT NULL CHECK(action IN ('connected','reconnected','replaced','paused','resumed','revoked')),
 created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE eshop.stripe_connection_flows ENABLE ROW LEVEL SECURITY;
ALTER TABLE eshop.stripe_connection_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.stripe_connection_flows,eshop.stripe_connection_audit FROM PUBLIC,anon,authenticated,service_role;
