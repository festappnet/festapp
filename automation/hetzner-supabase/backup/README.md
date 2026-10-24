# Encrypted Festapp backups

For host/runtime preparation, see [server deployment](../../../docs/setup/server_deployment.md).
The backup installer requires root on the approved host and the explicit
`FESTAPP_BACKUP_INSTALL_ACK=install-encrypted-off-host-backup-without-cutover` acknowledgement.
Check the literal acknowledgement in `install-online-backup.sh` before use.
The backup script needs `age`, Docker, `flock`, `jq`, Python 3, `rclone`,
`sha256sum` and `tar`; these are not all installed by the host bootstrap.

Provision `/etc/festapp-backup/r2.env` as root-only mode `0600`, containing
`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `R2_ACCOUNT_ID`, `R2_BUCKET`,
`R2_ENDPOINT` and `AGE_RECIPIENT`. The bucket guard accepts only
`festapp-supabase-backups`. Keep the decryption identity in a separate protected
restore location. An independent installation needs reviewed host/bucket changes.

The daily timer is scheduled for 02:30 UTC with up to 20 minutes of randomized
delay. Log upload has a separate timer. After installation, verify a fresh
remote manifest/artifact set and a disposable restore; an enabled timer is not
restore proof. The backup covers the database, roles, legacy Storage and runtime
files, not every separate image or Client Sync R2 bucket.


Ordinary online backups in `festapp-supabase-backups/backups/festapp-supabase-rehearsal-01/` retain all complete sets from the last 14 days plus the newest complete set in each of the four most recent completed ISO calendar weeks. The latest three complete sets are always kept. Weekly copies can overlap the daily window. The user selected this policy on 2026-10-08.

`create-online-encrypted-backup.sh` first uploads and checks a fresh encrypted set, then calls `prune-online-backups.py`. The helper checks manifests and artifact sizes, preserves incomplete/unrecognized sets, records a protected deletion manifest, rechecks the inventory and verifies both deletion and preserved recovery points. Other bucket prefixes, migration exports, restore evidence and runtime logs are outside its cleanup scope.

The server holds encrypted artifacts only while creating and uploading a backup.
After the R2 check and retention step succeed and the upload receipt is saved,
the script removes that run's local artifacts immediately. Failed or incomplete
runs remain for investigation or retry; local age alone never authorizes deletion.

The runtime archive is an explicit path list, not a copy of the complete host.
It includes `.env`, base/Festapp/database-target Compose, Caddy, the Function tree
and proxy files. The current list does not include `docker-compose.email.yml`,
admin Tunnel token files, systemd jobs or every auxiliary runtime file. Preserve
those exact release inputs in their protected configuration source and include
them in the restore plan. The database dump alone cannot recreate them; do not
claim complete service recovery from the four archive files without that proof.

The upload receipt uses `rclone check --size-only --one-way`: it proves the
uploaded set has the expected object sizes, not that a fresh remote download
was decrypted or restored. Manifest SHA-256 values describe local encrypted
artifacts at creation. Full downloaded-content verification and a disposable
restore are separate recovery evidence; keep them with the backup identity.

Run a read-only preview on the verified backup host:

```sh
flock -n /var/backups/festapp-supabase/.lock python3 /opt/festapp-backup/prune-online-backups.py \
  --evidence-dir /var/lib/festapp-rehearsal-evidence
```

`--apply` performs deletion. Credentials are read only from the root-owned mode-0600 `/etc/festapp-backup/r2.env`; they must never be passed through command arguments or logs. The helper uses Cloudflare's supported [S3 ListObjectsV2/GetObject/DeleteObjects APIs](https://developers.cloudflare.com/r2/api/s3/api/).

Override policy only through the explicit `FESTAPP_BACKUP_RETENTION_DAYS` and `FESTAPP_BACKUP_WEEKLY_COPIES` variables of the scheduled backup. The helper enforces a minimum of 7 daily days and 4 weekly copies. Install it together with the scheduled shell script using `install-online-backup.sh`.

Validation: `node --test automation/tests/hetzner_supabase_backup.test.mjs` (includes the Python selection/regression tests).
