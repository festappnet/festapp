# Client sync v1 production runbook

`client_sync_v1` / protocol 1 is the only client-sync path. Public clients read
`sync.festapp.net`; immutable payloads live under
`assets.festapp.net/client-sync/v1/`. The public Worker uses Cache API with a
canonical GET key and a five-second TTL. A cache hit, including a matching ETag
304, performs no R2 read.

## Canonical target and tool scope

Production authority is the tenant's published `backend-activation.json`,
canonical generation and organization, with any forced occasion verified in
that same database. Follow [AI context](../architecture/ai_context.md).
`SUPABASE_URL` may retain a legacy fallback and must not select live authority.
The legacy application read/cache path is distinct from this v1 protocol;
capability selection is described in [Services](../architecture/SERVICES.md).

`automation/client_sync_preflight.mjs`,
`automation/release/client_sync_health.mjs`,
`automation/release/client_sync_cutover.mjs` and
`automation/release/configure_client_sync_publisher_schedule.mjs` still resolve
managed-cloud targets from `SUPABASE_URL`. The helper named
`loadCanonicalSupabaseTarget` in `automation/lib/supabase_management.mjs` also
requires a `.supabase.co` project ref and queries the cloud management API;
its name is not evidence of self-hosted support. These commands are not
canonical production health or mutation procedures.
Do not run their apply/enable/disable paths against retained sources. Until
those mutators are adapted, use a separately reviewed canonical SQL/Worker
operation through the protected backend-access channel, preserving the ordered
gates below. This documentation update does not adapt or execute those tools.

## Local contract check and health criteria

```bash
node automation/check_client_sync_registry.mjs
```

This registry check is local and does not prove production health. Read-only
canonical health inspection must use the verified self-hosted target; the
cloud-only health script above must not substitute for it.

The existing health contract fails on registry/revision lag, dirty work older than two ticks, claims
older than their lease, live p95 above 25 seconds, structural p95 above 45
seconds, projection drift, stuck receipts, invalid current hashes or a pending
head.

## Publisher and scheduler

`ClientSyncPublisher.runOnce()` is the sole publisher. Its adapters are the
authenticated internal HTTP tick, the one-minute Cloudflare recovery tick and
authorized `pnpm run once`. The five-second named Supabase cron first performs
an indexed dirty-key `EXISTS` restricted to `SYNC_SCOPE_IDS`; an empty queue
causes no HTTP request. The wake endpoint and bearer token live in Cloudflare
secret/Vault, never repository vars or output.

The historical `configure_client_sync_publisher_schedule.mjs` interface is
dry-run/read-only by default; apply and disable require the configured occasion
confirmation. Rotate the wake token Cloudflare first, Vault second, verify a
tick, then remove the old value. Never expose an unauthenticated fallback.

## Occasion lifecycle

The historical `automation/release/client_sync_cutover.mjs` implements these
ordered enable/disable gates, but its cloud target resolver must not be used
for canonical production. A reviewed canonical operation must preserve them.
Create and duplicate force the flag false; save preserves the server flag;
enabled occasions cannot be hidden or deleted.

Enable order is preflight, audited full build, canonical publication,
protocol/hash/head verification, then flag true. Disable order is exact mutable
R2 head deletion, observed endpoint 404 after the bounded edge TTL, then flag
false. Any earlier failure leaves the flag true.

## Projection repair and retention

Health detects drift but never repairs it. The hardening migration contains one
generic audited rollout repair. Future repair is a separately reviewed forward
operation; do not add triggers or silent reconciliation.

`ClientSyncRetention.runOnce({apply})` is daily maintenance, not publication.
`SYNC_RETENTION_APPLY=false` is the default. Artifact age has one explicit
setting, `SYNC_ARTIFACT_RETENTION_DAYS`; candidate lookup and metadata recheck
use the same cutoff, with the plan's safety floor enforced in SQL. Current
descriptors, current/previous manifests and young objects are protected. Only
exact `client-sync/v1/` keys may be deleted; never use a bucket-wide lifecycle.

Completed mutation responses retain exact replay for 30 days, then become
permanent response-less `expired` tombstones returning deterministic 410. The
operational setting is `SYNC_RECEIPT_RETENTION_DAYS` and SQL enforces its safety
floor. Do
not enable first artifact deletion or first receipt compaction before their
observation windows and separate approvals.

## Rollout and rollback

Order: cache Worker, bounded client store, publisher with retention disabled,
secret/custom domain provisioning, forward migration/repair, five-second
scheduler, 24-hour observation, authorized load gate, delayed retention.

Rollback is forward-only: disable the exact cron for minute fallback, set
retention apply false, or roll back only the serving Worker code. Guarded
disable removes discovery. Never regress an R2 pointer; correct data with a
higher revision. Deploys, migrations, DNS/secrets, scheduler activation, 5k
tests, first deletion and first compaction each need separate authority.
