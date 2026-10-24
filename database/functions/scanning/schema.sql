-- Scanner data is private. Only the scoped RPC boundary may read/write it.
CREATE TABLE IF NOT EXISTS public.scanner_settings (
 occasion_id bigint PRIMARY KEY REFERENCES public.occasions(id), revision bigint NOT NULL DEFAULT 1,
 epoch bigint NOT NULL DEFAULT 1, config jsonb NOT NULL, updated_at timestamptz NOT NULL DEFAULT now(), updated_by uuid
);
CREATE TABLE IF NOT EXISTS public.scanner_sessions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), occasion_id bigint NOT NULL REFERENCES public.occasions(id),
 actor_user_id uuid, access_origin text NOT NULL, token_hash text NOT NULL,
 scan_secret_hash text, epoch bigint NOT NULL, device_name text NOT NULL,
 issued_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL,
 offline_until timestamptz NOT NULL, revoked_at timestamptz
);
CREATE TABLE IF NOT EXISTS public.scanner_snapshots (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), session_id uuid NOT NULL REFERENCES public.scanner_sessions(id),
 manifest jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL
);
CREATE TABLE IF NOT EXISTS public.scanner_snapshot_pages (
 snapshot_id uuid NOT NULL REFERENCES public.scanner_snapshots(id) ON DELETE CASCADE,
 page_index integer NOT NULL, payload_text text NOT NULL, digest text NOT NULL, PRIMARY KEY(snapshot_id,page_index)
);
CREATE TABLE IF NOT EXISTS public.scanner_operations (
 operation_id uuid PRIMARY KEY, session_id uuid NOT NULL REFERENCES public.scanner_sessions(id),
 occasion_id bigint NOT NULL REFERENCES public.occasions(id), ticket_id bigint NOT NULL,
 payload_hash text NOT NULL, payload jsonb NOT NULL, receipt jsonb NOT NULL, committed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS scanner_operations_scope ON public.scanner_operations(occasion_id,committed_at);
CREATE TABLE IF NOT EXISTS public.scanner_conflict_resolutions (
 operation_id uuid PRIMARY KEY REFERENCES public.scanner_operations(operation_id), actor_user_id uuid NOT NULL,
 reason text NOT NULL CHECK(length(reason) BETWEEN 3 AND 1000), resolved_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.scanner_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scanner_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scanner_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scanner_snapshot_pages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scanner_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.scanner_conflict_resolutions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.scanner_settings,public.scanner_sessions,public.scanner_snapshots,
 public.scanner_snapshot_pages,public.scanner_operations,public.scanner_conflict_resolutions FROM PUBLIC,anon,authenticated;
