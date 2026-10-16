# Festapp pgBackRest

Standard pgBackRest 2.57.0 (Alpine packaged version 2.57.0-r0), added to the
exact existing Supabase PostgreSQL 17.6 image. PostgreSQL/extensions are not
upgraded. All backup, differential, WAL, retention, checks and restore semantics
are implemented by pgBackRest, not by application code.

The user authorized installation and production activation on 2026-10-16.
No RAM resize, new cloud service, new bucket or billing-plan change is included.
Existing R2 usage increases by encrypted physical backups and archived WAL.

## Operation

- One backup worker, zstd level 1, 1 MiB buffers; synchronous archive-push.
- Full on Sundays, differential daily otherwise; first activation forces full.
- Four weekly full backups retained, with dependent differentials and continuous
  WAL. No shortened archive retention or queue-discard limit is configured.
- PostgreSQL archive_timeout=300s; operational objective is RPO <=15 minutes
  while archiving is healthy, not a guarantee during an uncorrected failure.
- Existing host monitor reports archive failures, pending WAL older than 10
  minutes, disabled archiving and backup older than 26 hours. Existing disk
  alerts remain essential if the archive destination is unavailable.
- AES-256-CBC repository encryption, TLS to the existing R2 bucket, separate
  `/pgbackrest/festapp-production` prefix. No credentials in image/Compose/env.
- Database OS user reads only its mounted mode 0640 config. Database connection
  uses existing local supabase_admin access; no new public SQL grants/passwords.
- Cipher key escrow is age-encrypted to the EXISTING recovery public key and
  uploaded separately from the repository. Independent custody of the age
  private key remains an operational requirement, not proven by this setup.
- Existing 14 daily + 4 weekly encrypted logical/Storage/runtime backups and
  retention remain. Their lock serializes physical/logical full scans.

## Activation and recovery

Run `test-pitr-local.py` with the locally built derivative. It verifies an
actual differential restore, a time target excluding a later commit, and that
archive failure retains WAL. No network, host mounts, production fixtures.

Publish reviewed sources to canonical main, stage their exact git archive in a
root-only directory, verify SHA-256, then run `install.py` with
`--ack activate-encrypted-pitr-with-db-restart --source-commit <main-sha>`.
It asserts canonical host/DB/org/image/command, shares the runtime upgrade lock,
builds the derivative, preserves .env, provisions encrypted key escrow, appends
one Compose override and restarts ONLY db after pausing/draining email attempts.
It restores the previous pause state, takes/checks the first full backup and
starts the daily timer. SQL application migrations and customer data are not
changed. Unexpected existing provisioning fails closed rather than replacing a
key or guessing a partial-install recovery.

The derivative is sealed by its local Docker image ID in .env. Recovery on a
replacement host must rebuild/import that image from this Dockerfile before
Compose starts; the base image and package version are pinned. The encrypted
runtime archive includes all active overrides, pgBackRest config and Dockerfile.
Never copy a physical restore over the live PGDATA. Use a new isolated cluster,
disable application preload/background workers, outbound network and integrations,
restore to a chosen time and verify before a separately authorized cutover.
Existing dump/Storage/runtime restore remains available; PITR covers the entire
PostgreSQL cluster, not Storage or external R2 images at the same timestamp.

References: https://pgbackrest.org/user-guide.html and
https://pgbackrest.org/configuration.html (S3-compatible storage, repository
encryption, full/differential backups, retention and point-in-time recovery).
