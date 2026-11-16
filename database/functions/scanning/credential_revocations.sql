-- A previously shared bearer credential must never become valid again merely
-- because one of its occasions was deleted or an old hidden row was removed.
CREATE TABLE IF NOT EXISTS public.scanner_revoked_credentials (
 secret_hash text PRIMARY KEY CHECK(secret_hash ~ '^[0-9a-f]{64}$'),
 revoked_at timestamptz NOT NULL DEFAULT now(),
 reason text NOT NULL CHECK(reason IN ('historical_shared','rotated'))
);
ALTER TABLE public.scanner_revoked_credentials ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.scanner_revoked_credentials FROM PUBLIC,anon,authenticated,service_role;

-- Security metadata only: no occasion, ticket, session or credential is changed.
-- Freeze the rejection of every currently ambiguous secret across this shared
-- backend, including identical secret text on separate historical hidden rows.
INSERT INTO public.scanner_revoked_credentials(secret_hash,reason)
 SELECT encode(extensions.digest(h.secret,'sha256'),'hex'),'historical_shared'
 FROM public.occasions o JOIN public.occasions_hidden h ON h.id=o.occasion_hidden
 WHERE h.secret IS NOT NULL
 GROUP BY h.secret HAVING count(*)>1
 ON CONFLICT(secret_hash) DO NOTHING;
