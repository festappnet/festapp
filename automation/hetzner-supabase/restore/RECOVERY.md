# Independent recovery bootstrap

The user explicitly authorized an iCloud recovery copy on 2026-10-16. The
private ZIP contains the existing age identity, encrypted pgBackRest escrow,
a separately scoped Object Read only backup-bucket credential, pinned recovery
sources and a Czech recovery procedure. It contains no SSH machine credentials.
The source-image backup reader is a different token, limited to four image
buckets. Neither token can write or delete objects.

The uploaded ZIP is sensitive because it contains the private age identity.
Do not publish it, attach it to issues or commit its contents. No public share
link or iCloud security-setting change was made. iCloud upload confirmation
proves independent key custody; it does not establish a second full backup of
all customer data outside Cloudflare or prove end-to-end iCloud encryption.

`download-offhost-backup.py` is copied into the private kit as
`download-backup.py`, next to `age-identity.txt` and `backup-reader.json.age`.
It uses standard age and rclone, with credentials supplied only through child
environment variables. It lists backup run IDs or downloads one selected set
to a new private directory, checking artifact sizes and SHA-256. `--pgbackrest`
downloads the encrypted physical repository to another new private directory.
No original server or original SSH access is needed. A replacement workstation
still needs access to iCloud and the R2 bucket must remain available.

Actual verification extracted the uploaded iCloud ZIP into a new temporary
folder, used only that identity/reader to GET an R2 manifest and the remote PITR
escrow, and decrypted the escrow. No original workstation key path or server
access was used. See `icloud-recovery-result.json` for sanitized evidence.

For full recovery, first run the isolated DB/Auth/REST/Storage drill against the
chosen downloaded set. It never executes the encrypted runtime configuration.
Inspect that configuration privately when preparing a replacement host: it
contains active Compose overrides, integration credentials and local image IDs.
Rebuild the pinned pgBackRest image and replace the old host-local image ID with
the rebuilt image ID. Preserve Storage extended attributes and compare database
references with the selected R2 archive. Keep production email/payment processing
disabled until the separate cutover decision; never replay historical unknown
email outcomes automatically. Tested isolated restore time excludes bare-host
provisioning, image downloads and complete integration cutover.

On a workstation with limited free disk, pass
`--consume-downloaded-artifacts` to the isolated drill. This explicit option
removes each local encrypted artifact only after its complete successful age
decryption; all manifest hashes are checked before any input is removed.
The manifest/acquisition receipt and off-host copies remain. A failed later
restore may require downloading the set again. The drill checks free local
space before decryption, including a Docker reserve, to avoid disk-induced WAL
fsync failures. This option never deletes from the server or R2.

`verify-r2-dump-local.py` provides a Docker-independent check using standard
`pg_restore --data-only` to read the chosen dump's image COPY records. It never
executes SQL or contacts a database. The two encrypted inputs must match their
selected manifest's hashes. A missing image reference writes a bounded failure
receipt and exits nonzero; a successful archive checksum alone is insufficient.

The first actual archive contains all 1,074 source objects (341,530,791 bytes),
with verified content hashes. The chosen DB has 997 R2 registry links, of which
50 already have no source object: 45 contain a test marker. None of these exact
URLs appears in the checked occasion/event/information payloads. Public samples
return 404; legacy private routes require auth. This is not evidence that every
registry row is dispensable. No rows or links were removed, and the strict
reference gate remains unsuccessful. The full service drill still runs its
independent application checks and saves the result before returning a nonzero
status for R2 gaps; the gaps are never silently accepted as consistency.

The local Storage drill streams the private archive into tar on stdin rather
than copying a mode-0600 workstation-owned file into a capability-restricted
container. Extraction uses `mkdir && tar`, so a tar failure cannot be hidden by
a subsequent cleanup command. `tar -o` sets ownership to the isolated runtime
user; original archive bytes and HTTP xattrs are preserved. All metadata is
prepared before the pinned Storage application starts. An isolated test with
all capabilities dropped restored all 1,732 files/attribute records successfully.
