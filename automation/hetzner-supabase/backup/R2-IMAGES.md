# R2 image recovery

Current image uploads use the image Worker and R2. Supabase Storage retains
historical data: on 2026-10-16, organization 1 had 24 R2 image records and no
Storage image records; Slunovrat had 224 Storage and six R2 records. Existing
Slunovrat event descriptions still fetched Storage bytes without redirection.
Do not remove Storage or rewrite those URLs as a backup operation.

The existing daily encrypted backup can include `r2-images.tar.age` using
`create-r2-image-archive.py`. It streams rclone reads into tar and the existing
age recipient, without writing plaintext files. The one encrypted archive
contains objects, original rclone metadata and per-object SHA-256. Source
objects are never written or deleted. It uses the same 14 daily/four weekly
retention policy. It adds no daemon, bucket or new encryption key.

Source scope is exactly `festapp-images`, `festapp-images-a`,
`festapp-images-private`, `festapp-images-a-private`. The unrelated akhweb
backend is outside this server-recovery package. Provision an Object Read only
S3 credential restricted to those four source buckets; the existing backup
credential cannot list them (actual AccessDenied). Its write scope must remain
limited to the existing backup destination.

Activation is the deliberate creation of root-owned mode 0600
`/etc/festapp-backup/images.env` with these generated provisioning inputs:

```dotenv
R2_SOURCE_ACCESS_KEY_ID=<read-only source access key>
R2_SOURCE_SECRET_ACCESS_KEY=<read-only source secret>
R2_SOURCE_ENDPOINT=https://84b32318ac235bf6738bdf1c8caa0795.r2.cloudflarestorage.com
```

The file is included only in the age-encrypted runtime backup, never source
control. The helper must be installed next to the existing backup script.
Without that file, existing DB/Storage/runtime backups continue unchanged;
their manifests must not be treated as R2 image backups. Implementation and
synthetic archive tests do not prove live R2 backup/restore. Activation and a
real archive integrity/reference drill remain required.

The archive is an online snapshot. Concurrent deletion/overwrite can abort
object reads, and it is not an atomic snapshot with PostgreSQL. Daily image
backup does not make image-history RPO equal to the database's 15-minute PITR
objective. Recovery must compare the chosen database's image references with
the selected R2 archive before claiming cross-store consistency.

For historical Supabase Storage, new archives preserve `user.supabase.*`
xattrs in GNU/PAX format. BusyBox tar does not restore these attributes. The
isolated service drill restores them using the pinned Storage image's existing
fs-xattr library. Older archives need explicit `--rebuild-storage-metadata`,
which recovers MIME/cache attributes from the same restored DB and reports the
number rebuilt; it does not pretend those attributes existed in the archive.
