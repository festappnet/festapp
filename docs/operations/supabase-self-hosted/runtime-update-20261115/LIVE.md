# Production result - 2026-11-15

The shared backend is running Supabase self-hosted/v0.8.4 and PostgreSQL 17.12.
Public admission reopened at **04:30:08 UTC** (05:30:08 Prague). The original
PGDATA, configuration/key volume, confirmed writes, email/cron state, MCP
containers and timers were retained. No production backup was restored or data
rewound. This is a backend release; no frontend update is required for it.

The deployed source was `1464872fd2c08226109f698856a38acb70ca6964`, whose eight
mandatory exact-SHA CI checks passed before deployment. The owner explicitly
waived independent review for the ongoing release after the review gate was
identified. The sealed derivative is
`sha256:ac20ae95be84d0bb429889d4f9c55c6533fc45fcb974f26280cf96316a88094f`.
Actual results are in [production-live.json](production-live.json) and adjacent
receipts. That receipt explicitly distinguishes still-running monitoring and
logical backup from completed checks.

## Availability and production corrections

The rehearsal's 59.552 s upgrade and conservative 103.871 s recovery did not
predict the complete production window. Confirmed public maintenance lasted
approximately **16 min 5 s**, from the first verified 503 at 04:14:03 to the
public Auth recovery at 04:30:08. This is an approximation from explicit HTTP
observations, not uninterrupted client sampling. The complete updater/pause
window was 1267.826 s. **The planned 15-minute budget was exceeded.**

Admission remained fenced during the incomplete service state. Pre-migration
failures did not change data. After vendor migrations began, recovery proceeded
forward; no earlier snapshot was restored over confirmed writes.

Four production boundaries required correction:

1. Caddy's file bind referenced a stale inode even though the host pathname
   matched. Reload kept reading the previous configuration. Caddy was recreated
   with its exact original image, environment, command, entrypoint, volumes and
   host configuration; the old container was retained. Host/container file
   identity and public 503/Retry-After/no-store then passed. The updater now
   rejects a stale inode before pausing jobs.
2. Docker returned the same eleven complete database mount objects in a
   different array order. Every field was verified equal by destination;
   an audited transport adapter presented those same objects in saved order.
   PGDATA and key volume identities stayed unchanged. The canonical updater now
   compares complete sorted objects and still rejects actual replacement.
3. YAML serialization removed quotes around optional key substitutions. In the
   actual legacy-key environment, empty values became null, causing Envoy RBAC
   validation to reject the listener. Restoring quotes preserved the YAML object
   and string types through substitution. No key or permission was introduced.
4. The REST OpenAPI root deliberately rejects the anonymous key with 403.
   Health checks were corrected to use the same bounded service-role read used
   in the native rehearsal. Public Auth, used REST, Functions and key rejection
   checks passed before original admission and jobs were restored.

Supabase 0.8.4 also disables gateway CORS for Functions. That change broke
existing browser clients whose disabled-feature errors rely on gateway CORS.
The original inherited Functions gateway policy was restored through an atomic
Envoy LDS update, without restarting Envoy. Authorization, RBAC, tenant/client
registries and disabled Google/MCP features stayed unchanged. The CAV owner
verified preflight and actual browser behavior with the same frontend artifact.
The package preparer now preserves this installed CORS contract.

The original journal records failed attempts. The successful operator closure
is [forward-recovery-receipt.json](forward-recovery-receipt.json); do not infer
current runtime failure from the earlier attempt's journal phase alone.

## Live proof and backup recovery

- Public Auth 200; bounded service-role REST read 200; unauthorized Functions
  worker 401; absent, invalid and empty API keys denied. The Functions cap is
  exactly 2147483648 bytes. Original email, cron, MCP and timer states restored.
- An existing connected MCP session returned the canonical org 3 context after
  the upgrade without a new login. The separate CAV owner verified newly
  committed permissions: one organization admin, two full unit memberships and
  four full occasion memberships. No grant was reapplied by this rollout.
- New encrypted full backup **20261115-043147F** passed its owner and archive
  checks. An independent retained recovery kit/read-only R2 reader downloaded
  this new set and WAL. A fresh network-none container restored to
  04:34:25.121645 UTC, paused at 04:34:24.484832 UTC / `27/8B0A12E8`, and passed
  catalog checks in 13.96 s. No ports, host binds or production integrations ran.
- The dedicated 30-minute monitor and the logical backup owner run after live
  recovery. Their current completion state is recorded in production-live.json.
  Existing host monitoring remains active for the subsequent 24-hour window;
  future observations are not represented as already performed.

The corrected package was generated again from the protected original installed
snapshot. Its LDS hash exactly matches the repaired production file
`0f780d3c29e14331f5d673236a6ae65473c9c1bdfaef3dac09ed9553af4b6de2`;
the other six payload hashes are unchanged. The correction changes neither
selected images nor the vendor/catalog migrations already performed.

Completed local rehearsal containers, copies and dependency caches were released
after the new independent restore passed. Original runtime image/config guards
and protected image archives remain retained through 2026-11-22. Existing backup
retention remains owned by its established maintenance scripts.
