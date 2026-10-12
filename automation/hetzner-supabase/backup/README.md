# Encrypted Festapp backups

Ordinary online backups in `festapp-supabase-backups/backups/festapp-supabase-rehearsal-01/` retain all complete sets from the last 14 days plus the newest complete set in each of the four most recent completed ISO calendar weeks. The latest three complete sets are always kept. Weekly copies can overlap the daily window. The user selected this policy on 2026-10-08.

`create-online-encrypted-backup.sh` first uploads and checks a fresh encrypted set, then calls `prune-online-backups.py`. The helper checks manifests and artifact sizes, preserves incomplete/unrecognized sets, records a protected deletion manifest, rechecks the inventory and verifies both deletion and preserved recovery points. Other bucket prefixes, migration exports, restore evidence and runtime logs are outside its cleanup scope.

Run a read-only preview on the verified backup host:

```sh
flock -n /var/backups/festapp-supabase/.lock python3 /opt/festapp-backup/prune-online-backups.py \
  --evidence-dir /var/lib/festapp-rehearsal-evidence
```

`--apply` performs deletion. Credentials are read only from the root-owned mode-0600 `/etc/festapp-backup/r2.env`; they must never be passed through command arguments or logs. The helper uses Cloudflare's supported [S3 ListObjectsV2/GetObject/DeleteObjects APIs](https://developers.cloudflare.com/r2/api/s3/api/).

Override policy only through the explicit `FESTAPP_BACKUP_RETENTION_DAYS` and `FESTAPP_BACKUP_WEEKLY_COPIES` variables of the scheduled backup. The helper enforces a minimum of 7 daily days and 4 weekly copies. Install it together with the scheduled shell script using `install-online-backup.sh`.

Validation: `node --test automation/tests/hetzner_supabase_backup.test.mjs` (includes the Python selection/regression tests).
