# Supabase 0.8.4 / PostgreSQL 17.12 - execution record and runbook

Preparation and isolated recovery passed on 2026-11-15. This document alone
does not attest production deployment. The subsequent live receipt owns that
claim. Scope is the shared canonical api.festapp.net backend, organization 3;
no frontend, Android, tenant branch, OS or unrelated dependency release.

## Frozen inputs and evidence

- Supabase revision `189adda99d1b56da55fc5a6ee3f849354aaea92a`.
- ARM64 PostgreSQL base `supabase/postgres:17.12.0.000@sha256:6c056e9a0f81d423c1a81fdf4e6587c16efd3f63960897371dab8ae2694a4714`.
- Rehearsed derivative `sha256:ac20ae95be84d0bb429889d4f9c55c6533fc45fcb974f26280cf96316a88094f`, pgBackRest 2.57.0-r0 from its own Alpine 3.23 repository.
- Original production derivative `sha256:58ab4c77b25c7dc79582c23ed872619ee2494ad7dc12cd3af4c6e6b053571bd0`.
- [Combined native rehearsal](combined-rehearsal.json): upgrade 59.552 s;
  full old-service recovery at fencing LSN 103.871 s. The latter is a
  conservative wall bound including an interrupted fixture readiness assertion
  and resume. Sum 163.423 s, below the 900 s production budget.
- Independent encrypted recovery kit and read-only off-host backup reader
  restored the real production backup, not a schema-only fixture. Every clone
  containing production data had no network, published port or host bind.
  Original Vault key configuration was retained. Scheduler execution was
  disabled and pg_net had no usable target database.
- Old Auth refresh token survived real candidate migrations. All installed
  services started; Realtime and pooler received startup health checks only.
  Realtime is unused by the app. Storage/imgproxy remained absent.
- Used SQL contracts, reservation concurrency, eight ticket PDF renderers,
  outbound TLS, error CORS, all four database catalogs, required index rebuilds,
  used Vault decryption, and encrypted post-upgrade backup/PITR passed. See
  adjacent receipts. Unused extensions received compatibility checks only.
- Transport/state tests mock operating-system commands; they are separate from
  the native restore/service evidence. Twenty targeted Node tests and nine
  Python tests passed. Current main's inventory check passed after rebase.

The November 12 archive failure was a transient DNS failure resolving R2 through
the host resolver at 09:41:53-54 UTC. The exact affected WAL segment
`000000010000002400000001` was subsequently verified in off-host storage.
Do not reset pg_stat_archiver counters to conceal the historical failure.

## Publication and staging

Publish only the isolated reviewed changes to authoritative main after a fresh
fetch and rebase. Require the existing exact-SHA gate:

```sh
python3 automation/ci/release_gate.py --source-sha "$(git rev-parse HEAD)"
node automation/hetzner-supabase/runtime/verify-pins.mjs --bundle --registry
```

The GoTrue 2.197 native MFA delegation/refresh freshness test also passed
on an owned PostgreSQL 17.12 runtime (one executed test, no skips, 26.2 s).
Preflight compares Compose null commands with image defaults and resolves its
rendered dollar escaping before strict comparison with running containers.

The source archive on the host is immutable under
`/var/lib/festapp-runtime-update-staging-20261115/source`. The prepared package
is under the sibling `package` directory. Its manifest carries the exact
published source SHA, all payload hashes, baseline hashes, image IDs and the
passing combined receipt. Both directories and expanded Compose models are
root-only. No environment file, credential or database copy belongs in Git.
Use prepare-runtime-update.py against the protected installed configuration
snapshot, including all six Compose files, Caddy, both Envoy files, installed
main worker and installed Studio customization. Load the sealed derivative and
pull selected pinned images before opening the window. Never build on production.

## Production execution

Resolve the source and arguments from the sealed manifest. Run on
`ssh festapp-backend-agent` as root, from the staged source, with no inherited
COMPOSE_* variables. First run the identical command with `--dry-run`.

```sh
cd /var/lib/festapp-runtime-update-staging-20261115/source
SOURCE_SHA=$(python3 -c 'import json; print(json.load(open("../package/manifest.json"))["source_sha"])')
python3 automation/hetzner-supabase/runtime/apply-runtime-update.py \
  --package /var/lib/festapp-runtime-update-staging-20261115/package \
  --source-sha "$SOURCE_SHA" --target api.festapp.net \
  --ack apply-rehearsed-supabase-0.8.4-postgres-17.12 --dry-run
```

After the exact-SHA CI gate, confirm low traffic and no current scanning,
in-flight email or active maintenance writer. Launch the same command without
`--dry-run` through systemd-run so loss of SSH does not terminate it. Capture
public availability probes independently. No further user confirmation is needed.

The updater acquires runtime and backup locks; preserves all six installed
overlays, mounts, keys and original job states; retains old image references;
pauses/drains email and schedulers; closes Caddy admission with 503/Retry-After;
drains Functions; stops MCP and database clients; records the fencing LSN;
changes the DB image on the same PGDATA; checks archive health; performs bounded
catalog/index work; starts the selected service set; probes the worker; then
restores exact original admission/jobs/MCP/timer states. The original business
Functions tree stays installed. Only main, memory-pressure and import map change.

## Stop points and recovery

Protected state and command diagnostics are in
`/var/lib/festapp-runtime-update-20261115`. Inspect `phase`, `done`,
`migration_point`, `fencing_lsn`, original mounts and snapshot hashes. Never
print the protected environment or command log into a public receipt.

An identity/config/image mismatch blocks the first mutation. There is a 720 s
forward-progress stop point, leaving 180 s for the measured 104 s recovery.
Service startup waits are bounded at DB 90 s and clients 150 s. A failed step
keeps admission fenced and jobs paused. Diagnose the protected command result
before a retry; `--resume` skips completed steps and checks boot/snapshot/source
identity. A host reboot requires explicit state review.

Before `migration_point`, append `--resume --rollback` to the production command.
This restores original images/configuration and starts the same data directory,
then restores the recorded original states. It does not restore a backup.

After service migrations, binary/config rollback alone is forbidden. Keep the
503 fence, email/jobs/MCP paused, and all client services stopped. The rehearsed
data recovery sequence is:

The restore invocation below obtains its target and source from protected
state. Run only after stopping the client services and DB as described below;
it creates a new directory and does not replace the original data:

```python
import json, os, pathlib, subprocess
state = json.loads(pathlib.Path('/var/lib/festapp-runtime-update-20261115/state.json').read_text())
assert state['migration_point'] and 'admission_restored' not in state['done']
mount = next(m for m in state['db_mounts'] if m['Destination']=='/var/lib/postgresql/data')
assert mount['Type']=='bind'
original = pathlib.Path(mount['Source'])
recovered = original.with_name(original.name+'-recovered-20261115')
assert not recovered.exists()
recovered.mkdir(mode=0o700)
owner = original.stat()
os.chown(recovered, owner.st_uid, owner.st_gid)
subprocess.run(['docker','run','--rm','--user','postgres',
  '--volumes-from','supabase-db:ro','--mount',
  'type=bind,source='+str(recovered)+',target=/var/lib/postgresql/data',
  '--entrypoint','pgbackrest',state['original_images']['db'],
  '--stanza=festapp','--set='+state['pre_window_backup'],
  '--pg1-path=/var/lib/postgresql/data','--log-path=/tmp','--lock-path=/tmp',
  '--spool-path=/tmp','--archive-async=n','--type=lsn',
  '--target='+state['fencing_lsn'],'--target-action=promote','restore'],check=True)
```

1. Stop the new DB after stopping every client. Preserve its original PGDATA
   intact. Keep the protected original configuration, Vault key volume and all
   old images. Never use down -v, prune or reset.
2. With the original derivative, restore the latest successful pre-window
   physical backup into a **new empty directory**, using the existing protected
   pgBackRest configuration, `--stanza=festapp --type=lsn`, the exact recorded
   `fencing_lsn`, `--target-action=promote`, and an explicit `--pg1-path` for the
   new directory. The new directory needs the original data directory's owner
   and permissions. Keep config/key mounts and encrypted repository unchanged.
3. Keep both data directories. Switch the stopped DB's data bind to the recovered
   directory (rename the stopped original to a distinct retained sibling, then
   rename the recovered directory to the original bind path), restore the hashed original six-file configuration and worker
   files, and start the original derivative. Wait for SQL to accept connections
   and `NOT pg_is_in_recovery()`, rather than relying solely on pg_ctl readiness.
4. Verify canonical org/database, pre-migration heads and archive health. Start
   the original service images with the complete installed overlay list; verify
   API/Auth/REST/Functions and installed-service startup health. Restore recorded
   cron/email/MCP/timer state and original Caddy only after the worker probe.

The local native drill executed pgBackRest's LSN recovery with a committed
pre-fence marker preserved and a later deliberately unacknowledged fixture
excluded. Production recovery is permitted only while admission has remained
closed and no subsequent writes have been acknowledged. Once admission opens,
use forward repair; never roll acknowledged writes back to a snapshot.

## Live completion gates

Record actual SQL 170012, running image IDs, complete Compose configuration,
public Auth/REST/Functions/CORS, preserved MCP connection, healthy email producer
and original job states, current WAL archival and measured availability window.
Run the existing physical full and encrypted logical backup owners after the
window; independently download and restore the new physical backup with the
retained recovery kit. A successful upload alone is insufficient. Leave existing
24-hour monitoring active, record pending timed observations honestly, and keep
old image guards/configuration for seven days. Remove only finished isolated
fixtures after retaining their receipts.
