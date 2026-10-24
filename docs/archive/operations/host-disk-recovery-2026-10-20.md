# Production host disk recovery - 2026-10-20

Incident: monitoring `festapp-host`, code `host_disk`, reason
`disk_space_percent`, reported 95.9%. Direct SSH `df` confirmed 96% usage on
`festapp-supabase-rehearsal-01` (38 GiB root filesystem, about 1.5 GiB available).
Inode use was 17%. Repeated occurrences represented repeated observations of the
same capacity condition.

Seven encrypted backup staging directories from October 18-20 occupied
12,681,606,556 bytes. Their uploads had succeeded. The installed backup script
used an age-based `find ... -mtime +2 ... rm -rf` cleanup, allowing multiple
successful runs to accumulate. The working-tree source already contained an
immediate-cleanup change, but the installed script also contained newer asset
format 2 functionality absent from this checkout. Replacing the entire installed
script with the checkout would have discarded those live capabilities.

The prepared live patch replaces only that age-based cleanup with removal of
the current run's `artifact_files` plus manifest, followed by `rmdir`. This runs
after upload, remote verification, retention and the durable success receipt.
Failed or incomplete runs are preserved. Using the same artifact array for the
manifest and cleanup also covers `r2-images.tar.age` without a separate filename
list. The repository cleanup now follows this same rule.

Before removing accumulated local staging, a scoped one-off script verified all
seven runs against their success receipts, exact remote manifests, remote object
sizes and SHA-256 of every local artifact. It acquires the backup lock, refuses
unknown files/symlinks and deletes only these explicitly selected local sets.
Remote backup objects and retention were not changed by the recovery script.
Remote size/manifest checks do not constitute a new download/decrypt/restore drill.

Live script hashes:

- Before: `7c219e9ac0c167aedb0b71bb9d33ddf1c0bce7ec19f748bd5ec7b5933944dae6`
- Prepared fix: `0818ef062d6512f517c70b56ada3a53255aa93faa0bca0162e2c756b8f65069f`

Protected host evidence:
`/var/lib/festapp-rehearsal-evidence/host-disk-cleanup-20261020.json`.
Rollback script:
`/opt/festapp-backup/create-online-encrypted-backup.sh.before-host-disk-20261020`.

Validation: four existing backup tests passed; the added cleanup regression test
passed for both legacy Storage and canonical image archive lists, preserving an
incomplete sibling run. The live patch passed `bash -n` and the same cleanup
fixtures. No full backup or restore was started for this incident.

Completed live recovery: all seven local sets removed (12,681,606,556 bytes).
`df /` then showed 63% usage and 14 GiB available. The existing monitoring service
submitted four accepted receipts, with disk `62.7`, status `ok`, reason `ok`.
Existing running containers remained up, including all previously healthy ones.
The installed script matched the prepared-fix SHA-256 above. The next scheduled
full backup has not yet run; its current-run cleanup is covered by the fixtures.
