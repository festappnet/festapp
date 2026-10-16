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
