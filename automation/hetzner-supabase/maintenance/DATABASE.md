# Database maintenance on the canonical host

`database-cleanup.py` is an explicitly authorized one-time operation. The
`database-retention.py` service is the recurring operational retention owner.
Both assert the exact canonical host, runtime database and organization. They
share a nonblocking lock, use the existing local `supabase_admin` maintenance
superuser through the protected socket transport without password retrieval, and keep protected receipts in
`/var/lib/festapp-database-maintenance/`.

## Retirement and recovery

Only these four exact historical names/OIDs are eligible:

- `festapp_rehearsal_20260828234500` / 84190
- `festapp_stage_a` / 185319
- `festapp_stage_default` / 185025
- `festapp_stage_slunovrat` / 185613

Inspection on 2026-11-12 found no configured container, scheduled job,
replication slot, prepared transaction, active session, stored function,
dependent view or tracked live query using these databases/imported schemas.
Statistics since the 2026-10-20 restart showed no writes or application traffic.
The preflight permits only a small number of diagnostic read transactions.
Foreign server/table definitions in `postgres` and the runtime remain historical
migration metadata; there are no active consumers. They are not removed by this
operation, and would need an archived database restored before historical replay.
Do not delete the still-used local `festapp_merge.id_mappings` table.

The operation first validates current pgBackRest health and backup age (<26h).
It captures a fresh custom-format dump of the live runtime and every selected
old database. Identical dump bytes stream to age encryption and to a real
isolated PostgreSQL restore using the exact running database image. The clone
has no network, ports or host bind mounts; application preloads and archiving are disabled,
with one CPU and 512 MiB RAM. The required extension libraries pg_net, pgaudit,
pg_stat_statements and supabase_vault are loaded for restoration. pg_net is
fenced to an explicitly nonexistent database, asserted before any restore;
pg_cron and other application preloads remain disabled. Docker network-none
provides an independent outbound boundary. Only source role names are created in the clone to support ownership; live
login capabilities, role GUCs and membership grants are not enabled there. Full
source role definitions are archived without role password hashes. Application Auth hashes inside dumps remain
encrypted in the retained artifacts. Every permanent ordinary table's row count must
match for inactive sources; the changing runtime verifies restored identity
instead. An online compaction of the restored runtime's `information` table
also verifies the exact installed pg_repack client/extension before live use.

Encrypted dumps and role definitions go to the existing private backup bucket,
under `retired-databases/<host>/<run>/`. Each full ciphertext is downloaded and
SHA-256 verified. A protected per-database receipt is persisted before deletion.
Only then are new connections disabled and the old database dropped WITHOUT
FORCE. Any existing connection blocks deletion and connection permission is
restored on failure. The temporary restore container and its anonymous volumes
are removed. Off-host retirement archives are not automatically deleted.
The recorded roles exclude role passwords: restore human/service credentials
from their existing protected stores/cluster backup when needed.

## Daily retention

The daily 06:15 UTC timer (up to 15m jitter) requires a healthy pgBackRest backup
less than 26 hours old and healthy WAL archiving. Policies are:

| History | Retain |
| --- | --- |
| Completed successful `cron.job_run_details` | 7 days |
| Completed failed `cron.job_run_details` | 90 days |
| `public.log_app_config` | 90 days |
| `auth.audit_log_entries` | 365 days |

In-flight/unfinished cron rows are untouched. Authentication sessions/tokens,
emails, orders, tickets, payments and migration mapping data are untouched.
Deletion is in 5000-row batches with SKIP LOCKED, a 250ms lock timeout, 15s
statement timeout and a maximum of 400 batches per policy per invocation.
Ordinary VACUUM ANALYZE follows on explicit tables; TRUNCATE FALSE avoids the
stronger end-of-relation truncation lock. Existing free pages are reusable.
Failures produce a failed service and preserve the last successful receipt.

## One-time online compaction

The one-time operation repacks only the seven reviewed operational/content
relations listed in its COMPACT constant. It temporarily installs bundled
`pg_repack` 1.5.2, uses no-order table repacking and
`--wait-timeout=1 --no-kill-backend`, then drops the extension with RESTRICT.
No application connection is canceled or terminated. Online repacking still
needs brief exclusive locks at setup/swap; the timeout bounds acquisition,
not the entire job or lock-holding duration. Each server statement has a
120-second timeout. The clone exercises the exact client/extension first.
No pg_repack extension or technical trigger may remain on success.
Never blindly DROP EXTENSION CASCADE after a failure: inspect the protected
state, live dependencies and interrupted-operation artifacts first.

Sources: [pg_repack](https://reorg.github.io/pg_repack/),
[PostgreSQL extension removal](https://www.postgresql.org/docs/17/sql-dropextension.html).
The installed package is 1.5.2; do not assume later versions' locking behavior.
No application RPC, policy, grant or migration ledger is changed by this
operational maintenance, and no tenant release or app restart is involved.

## Validate and install

`python3 -m unittest automation/tests/test_database_retention.py` exercises real
PostgreSQL17 policy boundaries, locked-row exclusion and streaming encrypted
backup/restore in a newly created network-none local container. Existing local
projects are untouched. Compile the Python sources and validate the units with
systemd-analyze verify. Install scripts root0755 under `/opt/festapp-maintenance/`
and the two retention units root0644 under `/etc/systemd/system/`.

Review `database-cleanup.py` without `--apply` first, then execute its authorized
one-time run. Enable the recurring timer only after this run succeeds, so the
first live deletion follows a newly verified runtime recovery archive. Verify
installed digests, timer next run, all active container identities/start times,
app health, remaining databases, relation sizes and pgBackRest health.

Disable future retention with `systemctl disable --now festapp-database-retention.timer`.
A database is never dropped by the daily service. Future retirement requires
new investigation and explicit authorization rather than name/age heuristics.
