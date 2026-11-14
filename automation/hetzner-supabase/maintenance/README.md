# Canonical host disk retention

`festapp-host-retention.timer` runs daily at 05:30 UTC with up to 15 minutes
of jitter and catches up after downtime. It complements the existing hourly
BuildKit cache cleanup and the existing database/log backup retention.

- Unreferenced Docker images created more than 14 days ago are pruned using
  Docker's image-only pruning API. All running and stopped containers protect
  their images. Images created within the last 14 days remain for rollback.
- Only `functions.pre-production-YYYYMMDDTHHMMSSZ` directories older than
  14 days are removed. The latest two are always retained. Current Functions,
  mounted paths, recent trees and symlinked trees are excluded.
- Recovery payloads of at least 10 MiB (`.dump`, `.dump.age`, `.tar`, `.tar.age`,
  `.tar.gz`, `.sql.gz`) in evidence trees untouched for 14 days are archived
  with relative paths into gzip tar streams encrypted with the existing backup
  age recipient. Symlinked, mounted and recent trees are excluded. SQL, receipts
  and other small audit evidence remain local.

Archives go only to `festapp-supabase-backups/host-evidence/<canonical-host>/`,
using a content-addressed object name. The entire encrypted object is read back
and SHA-256 verified before the original files are removed. File identity and
modification fingerprints are rechecked before deletion. Errors preserve
unverified originals and fail the service. Local encrypted staging is temporary;
only one evidence directory is processed at a time, with a 1 GiB free-space
reserve. Small protected receipts record exact object locators and checksums in
`/var/lib/festapp-host-retention/` and alongside the original evidence metadata.
Off-host recovery archives have no automatic deletion in this job. Existing
routine backup retention (daily/weekly) and runtime log retention are unchanged.

No database, Docker volume, container, current application source or live
configuration is removed or restarted. Host/database assertions and a
nonblocking job lock prevent running this policy on another host or twice.
The service fails visibly on archive/verification errors; inspect with
`journalctl -u festapp-host-retention.service` and `systemctl --failed`.

## Install and operate

Review source digests and run `python3 -m unittest
 automation/tests/test_host_retention.py`. Install `host-retention.py` root-owned
mode 0755 in `/opt/festapp-maintenance/`, and install both units mode 0644 in
`/etc/systemd/system/`. Run `systemd-analyze verify` on the units and run
`python3 /opt/festapp-maintenance/host-retention.py` for a read-only inventory.
Then `systemctl daemon-reload`, enable/start the timer and start the service.
Verify installed digests, service exit status, next timer execution, disk usage
and unchanged runtime container IDs, start times, status and image IDs.
Disable future runs with `systemctl disable --now festapp-host-retention.timer`.

For recovery, read a protected `archived-payloads-*.json` locator and retrieve
its exact object with the existing backup credentials. Verify the ciphertext
SHA-256, decrypt using the existing backup recovery identity, and extract into
an isolated directory. Archive member names are relative to the original
`/var/lib/festapp-rehearsal-evidence/` root. Never extract directly over live data.
