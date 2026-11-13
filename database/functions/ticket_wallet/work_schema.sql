-- Scheduling belongs here; provider identity remains in ticket_wallet_objects.
ALTER TABLE eshop.ticket_wallet_integrations ADD COLUMN IF NOT EXISTS paused boolean NOT NULL DEFAULT false;
CREATE TABLE IF NOT EXISTS eshop.ticket_wallet_work (
 provider text NOT NULL DEFAULT 'google' CHECK(provider='google'),
 kind text NOT NULL CHECK(kind IN ('object','class','occasion','organization')),
 resource text NOT NULL,
 organization bigint NOT NULL,
 occasion bigint,
 ticket_id bigint,
 requested bigint NOT NULL DEFAULT 1 CHECK(requested>0),
 captured bigint NOT NULL DEFAULT 0,
 applied bigint NOT NULL DEFAULT 0,
 lease uuid,
 lease_until timestamptz,
 due_at timestamptz NOT NULL DEFAULT now(),
 dirty_since timestamptz NOT NULL DEFAULT now(),
 failures integer NOT NULL DEFAULT 0,
 last_error text,
 last_success timestamptz,
 claimed_at timestamptz NOT NULL DEFAULT '-infinity',
 cursor_ticket bigint NOT NULL DEFAULT 0,
 cursor_version bigint NOT NULL DEFAULT 0,
 repair_at timestamptz NOT NULL DEFAULT now()+interval '1 day',
 boundary_at timestamptz,
 PRIMARY KEY(provider,kind,resource),
 CHECK(applied<=captured AND captured<=requested),
 CHECK((lease IS NULL)=(lease_until IS NULL))
);
CREATE INDEX IF NOT EXISTS ticket_wallet_work_due ON eshop.ticket_wallet_work(due_at,dirty_since,resource) WHERE requested>applied;
CREATE INDEX IF NOT EXISTS ticket_wallet_work_repair ON eshop.ticket_wallet_work(repair_at) WHERE kind='object';
CREATE INDEX IF NOT EXISTS ticket_wallet_work_boundary ON eshop.ticket_wallet_work(boundary_at) WHERE boundary_at IS NOT NULL;
ALTER TABLE eshop.ticket_wallet_work ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eshop.ticket_wallet_work FROM PUBLIC,anon,authenticated,service_role;
