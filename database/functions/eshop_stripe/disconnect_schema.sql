CREATE TABLE eshop.stripe_disconnect_intents (
 id uuid PRIMARY KEY DEFAULT extensions.gen_random_uuid(),
 connection_id uuid NOT NULL REFERENCES eshop.stripe_connections(id),
 actor uuid NOT NULL REFERENCES public.user_info(id),
 state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','claimed','uncertain','completed')),
 result jsonb,created_at timestamptz NOT NULL DEFAULT now(),claimed_at timestamptz,completed_at timestamptz
);
CREATE UNIQUE INDEX stripe_one_disconnect_intent ON eshop.stripe_disconnect_intents(connection_id) WHERE state<>'completed';
ALTER TABLE eshop.stripe_disconnect_intents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.stripe_disconnect_intents FROM PUBLIC,anon,authenticated,service_role;
