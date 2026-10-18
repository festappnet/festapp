# Retire Supabase Storage and consolidate Festapp assets on R2

Date: 2026-10-18
Status: Production copy, Worker, references and scoped Edge activated; new recovery and runtime retirement gates pending
Verification: standard

Actual execution state is recorded in
`docs/operations/security-remediation-20261016/storage-r2-retirement-execution-20261018.md`.
The full 2,817-object copy, canonical Worker and transactional reference rewrite
are deployed. The scoped Edge activation took 18.55 seconds within the user's
subsequently approved two-minute window. New-format recovery, source retirement
and the enforced capacity budget remain pending; see the execution receipt.

## Outcome and scope

Festapp stores and serves its files through one public-serving and one private
R2 asset bucket. Current application content, including HTML and nested JSON,
resolves the migrated objects. Ticket generation keeps identical font IDs and
bytes. Supabase Storage and its unused image proxy no longer run on the 4 GB
server. A verified replacement-host rehearsal proves the new recovery path.

Include file producers/readers/deletion, persisted references, asset ownership,
backups, recovery kit, metrics and numerical capacity budget. Keep Studio always
available. Keep the independent AKH application and its R2 bucket unchanged.
Do not combine this with direct R2 custom-domain/P3 delivery cutover, changing
the payment/email engines, provider upgrades, or arbitrary tenant web releases.

## Decisions and operational boundaries

- User selected 4 GB RAM, continuously available Studio, and at most 10 minutes
  production outage in an agreed maintenance window. Recovery experiments run
  on an isolated copy, with no production outage. No live disaster switch now.
- Database recovery-point objective: at most 15 minutes with healthy PITR.
  File recovery-point objective: up to 24 hours. These do not imply atomic
  DB/file snapshots or a ten-minute full-disaster recovery guarantee.
- User requests complete file/font migration, including references hidden in
  product/form descriptions, HTML, nested JSON and templates. Legacy Supabase
  Storage addresses must cease functioning. Breakage in previously sent
  messages/documents and offline copies of those URLs is accepted.
- Breakage of existing R2 URLs was not accepted. Preserve them at the existing
  Worker read/control boundary while consolidating their backing storage.
- The unrelated AKH R2 backend is not part of the consolidation. Imported
  objects in the canonical Storage bucket named `akhweb` remain part of the
  source inventory and must be preserved; never infer disposal from its name.
- Do not change daily/weekly backup retention or independent key custody. Do
  not copy customer URLs, object names, raw HTML, payloads or secrets into Git.
- Publication must obey current branch protection. Use reviewed canonical main
  for production code/SQL. Default frontend release scope remains one selected
  tenant, `prod/festapptickets`, only if a release is necessary. Shared database
  inspection/rewrites do not authorize builds or pushes to other prod branches.
  Identify any additional required tenant release and obtain its explicit scope
  before publishing it; data/Worker-only migration may need no tenant build.

## Fixed point and evidence

Reviewed main: `8b1420ea1da7349db68b4a293bb37da049fb9047`; refresh before implementation.

| Fact | Evidence | Consequence |
|---|---|---|
| 228 Storage image registry links remain; three event-image reads returned 206 | `docs/operations/security-remediation-20261016/storage-usage-audit-20261018.json` | This is a live dependency, not just old files |
| Storage has 1,479 objects; local directory about 1.3 GB; fonts are 13 objects / 2.17 MB | Same receipt | Inventory images, PDF, JSON/GeoJSON and arbitrary binary files |
| Current Storage/imgproxy memory samples about 181 / 24 MiB | Same receipt | Copying bytes alone does not free RAM; services must retire |
| Public R2 has 410 default + 664 `a` objects; both private buckets and temp are empty | `r2-bucket-topology-20261018.json` in the same evidence directory | Consolidate after copy/consumer proof, not by deleting nonempty buckets |
| All eight related r2.dev endpoints disabled; only sync has a direct custom domain | Same receipt | Preserve private isolation; public image reads currently use Worker |
| New image uploads already use Worker; old delete branch uses Storage | `lib/components/images/db_images.dart` | Move/delete remaining branches and preserve exact ownership checks |
| Deployed font adapter matches main and reads/writes ticket-fonts | `_shared/ticketFontStorage.ts`, audit receipt | Replace transport while retaining resolver and content hash contract |
| Account deletion calls Storage remove | `supabase/functions/confirm-account-deletion/index.ts` | Move cleanup ownership before stopping Storage |
| Existing backup/restore assumes four R2 buckets plus Storage archive | `backup/create-r2-image-archive.py`, `restore/r2_archive.py`, `restore/RECOVERY.md` | Migrate recovery consumers before deleting buckets |
| Original 50 missing-source registry rows were removed with accepted loss; current R2 check has zero gaps | `r2-registry-cleanup-20261018.json` | Do not reuse historical failures to exempt new missing data |
| 31.43 hours of samples still fail the conservative 4 GB budget screen | `resource-followup-20261017.json` | Storage retirement alone does not prove a complete enforced budget |
| AKH main `e5f6cdfc89c30eabb4c5f5919e830437d485b21a` uploads/deletes through projectId=akhweb; deployed Worker has IMAGES_BUCKET_AKHWEB binding; 18 rendered homepage R2 images and three public reads return 200 | `akh-storage-dependency-audit-20261018.json` | Preserve the shared Worker AKH route/auth/binding while deleting the three other buckets |

## Target topology and ownership

| Bucket | Target role |
|---|---|
| `festapp-images` | All public-serving Festapp assets; retain existing keys where safe |
| `festapp-images-private` | Protected Festapp assets and service-only font binaries |
| `festapp-public` | Existing public sync/offline artifacts, unchanged contract |
| `festapp-supabase-backups` | Private encrypted backups/WAL/logs/key escrow; retain name and paths |
| `festapp-images-akhweb` | Separate AKH application, unchanged |

Retire `festapp-images-temp`, `festapp-images-a-private`, and, after transferring
its 664 objects, `festapp-images-a`. Target: five related buckets, four for
Festapp and one for the separate AKH app. Do not create buckets per organization,
occasion, font, or former source database.

The existing image Worker owns asset delivery and control. Extend it with a
focused binary-asset storage module; do not build a second storage service.
The separate `/Users/miakh/source/akhweb` main uses this same Worker, its own
Supabase database/Auth configuration, and `festapp-images-akhweb`. It is already
included in both the eight-bucket inventory and the five-bucket target. The
static Praha subsite serves repository assets through GitHub Pages. No AKH
repository change, backend migration or extra bucket retirement is required.
Public/private destinations are explicit classifications, never inferred from
file extension. New object keys encode canonical owner/purpose and an immutable
identity/hash. Prefixes organize data; actual authorization stays in the
canonical SQL permission boundary. Private files never become public to simplify
HTML rendering. Font reads/writes use a narrowly scoped service boundary and
immutable hash keys in a private `ticket-fonts/` namespace, not end-user tokens
or credentials in a browser.

The same old key may occur in multiple buckets with different bytes. Keep
default keys where possible and namespace imported `a` keys deterministically.
The Worker can translate existing `a.img.festapp.net` URLs to the canonical key;
its deletion path resolves the same identity before the existing SQL ownership
check and invalidates all applicable cache representations. This is a thin R2
boundary, not a fallback to old buckets or a Supabase Storage redirect.

## Implementation waves

### 1. Seal a complete inventory and exact reference manifest

Extend `automation/image-migration/` rather than running its old scripts as-is:
they match `supabase.co/storage` and the former project, missing canonical URLs.
Build a protected, resumable manifest of every Storage object, existing R2 `a`
object, visibility, owner, source locator, byte length, SHA-256 and destination.
Account for unreferenced disk files separately; do not silently discard them.

Discover text, JSON/JSONB and relevant array columns through pg_catalog in
application schemas. Include all `eshop` tables: products, product_types,
blueprints, layouts and forms, as well as images/icons, events/information,
occasions, organizations/units, email templates/wrappers, news/places and caches.
Parse HTML attributes, srcset, CSS URLs, HTML entities, escaped JSON strings and
nested JSON structurally. Recognize canonical and owned historical Storage
hosts, public/authenticated/signed routes and percent-encoded object keys.
Signed URL query tokens are not object identity and must stay out of reports.
Do not rewrite third-party URLs or replace unrelated substrings.

Classify immutable audit/delivery history separately from current application
data. Previously sent messages are an accepted external boundary, not mutable
application content. Inventory current producer jobs that can repopulate caches.
Use durable row keys, field identity and exact original values/digests to detect
concurrent edits. Unknown ownership, source mismatch or private semantics blocks
only that mutation and is a concrete inventory failure, never a guessed mapping.

Validation: isolated fixtures with HTML/JSON/encoded/signed references, identical
keys with differing bytes, shared objects and genuine external URLs. Exit:
every in-scope object/reference is accounted for with no unresolved mapping.

### 2. Complete the canonical asset service and move producers

Update `workers/image-worker/src/{project-registry,types,delete}.ts` and the
focused storage handlers. Default, `a` and Slunovrat use the canonical Festapp
bucket pair; AKH retains its own binding/auth contract. Keep old R2 read/control
URLs at one translation boundary with no old-bucket fallback. Extend public key
validation for the approved binary-asset namespace. Keep image transforms for
images only; PDFs, fonts and JSON must retain identical bytes/MIME.

Replace the transport of `supabase/functions/_shared/ticketFontStorage.ts`;
keep font IDs, metadata, resolver, 8 MiB limit, conditional create and SHA checks.
Use a fixed, authenticated service-only font namespace. If a new service secret
is needed, keep it in existing protected secret stores, scope it to font
read/create, and never reuse or expose a user's/service-role credential.
Account deletion must remove owned canonical objects through the same owner,
with durable retry semantics, before retiring Storage cleanup SQL.

Validation: image-worker typecheck and affected Vitest suites; Deno font
resolver/generation and account-deletion tests; test cross-owner denial, private
read denial, replay/partial failure, duplicate create and unchanged font bytes.
Include AKH project resolution, existing public prefixes and its own permission
contract in shared-Worker regression coverage. After deployment, re-read known
public AKH assets; do not run production upload/delete fixtures for this audit.
Exit: every new file/font producer and cleanup consumer has one owner on R2.

### 3. Copy and verify; rewrite all current references

Copy additively with per-object immutable receipts; never overwrite a conflicting
destination. Read source bytes inside the verified backend's protected storage
context without exporting service-role keys. Stream/hash instead of loading the
whole inventory into RAM. Recheck length/hash on destination and preserve MIME
and access classification. Include imported Storage `akhweb` objects without
changing the independent AKH Worker/bucket. Leave source files intact for now.

Author exact, reviewed repository SQL for field changes from the protected
manifest; apply through the canonical workflow with its ledger. Match original
field values, reject changed rows and retry them through a refreshed manifest.
Publish existing client-sync commits/invalidation for every affected scope so
HTML, form/catalog/layout readers and caches see the same state. No persistent
application triggers, broad textual replacements or asynchronous partial commit.
New producers/imports must not reintroduce owned Storage URLs after cutover.

Validation: isolated PG17 matching production, mixed-owner batch rollback,
concurrent edit refusal, signed/private mapping, all URL syntaxes, and positive
public form/product/ticket flows. Exit: exact byte parity and zero owned Storage
references in current application fields, including all discovered HTML/JSON.

### 4. Move backup and recovery to the new inventory

Version new backup manifests explicitly. New sets cover DB/globals/runtime and
the complete canonical public/private R2 assets, including font bytes, metadata
and per-object hashes. Preserve the existing encryption, bucket, timers, 14-day
plus four-week retention and read-only independent recovery credential.
Update `backup/create-r2-image-archive.py`, online backup/manifest consumers,
`restore/r2_archive.py`, downloader and smoke helpers. New recovery no longer
requires Storage/imgproxy. Retained historical sets keep an explicit old-format
reader for their retention boundary, not a live application fallback. Never
rewrite or relabel old sets as new-format or consistent.

Run one actual new off-host backup and isolated restore using independent key
custody. Validate DB references against the selected R2 snapshot. Compare the
15-minute DB point and up-to-24-hour file point and report any actual gap; do
not call them atomic. Include acquire/provision/image pulls/service starts in
timings, keep real email/payments/webhooks disabled. Refresh the protected
recovery-kit sources and preserve the original kit. Exit: new set restores
without Storage, exact hashes and selected-point consistency are proven.

### 5. Retire services and three redundant buckets

Remove old Storage SDK branches in DbImages and account cleanup, storage-only
policy/helper/config/monitor consumers and obsolete tests. Preserve historical
migrations and read-only old-backup readers as named history boundaries.
Update `bootstrap-host.sh`, runtime generation/promotion and canonical Compose
inputs so `docker compose up` cannot recreate Storage/imgproxy. Removing only
the override image entries is insufficient if pinned upstream Compose still
defines the services. Remove their routes, env, dependency/readiness checks and
image pins from the active contract. Prove imgproxy has no other consumer first.

Remove old bucket bindings, source-reader permissions and current backup
allowlists. Inspect deployed Worker/service bindings, notifications, lifecycle,
credentials and external consumers before deleting each redundant bucket.
`festapp-images-temp` currently has zero objects, no repository caller, no
domain/r2.dev access, only the default multipart-abort lifecycle, and the API
reports no notification configuration (code 11015); still check deployed
bindings before deletion. Empty `a-private` is currently bound and backed up,
so it cannot be deleted first. Nonempty `a` needs verified transfer and read
translation before source retirement. Do not delete the five retained buckets.

Execute final service stop in an agreed window, staying within ten minutes if
any downtime is needed. Monitor login, forms, ticket generation, file reads,
private denial, sync, SSH and WAL. Delete source volumes/buckets only after copy,
reference, new-backup/restore and consumer gates pass. Exit: old Storage routes
do not serve files, normal startup omits the services, and target topology is
five buckets with preserved R2 delivery and private isolation.

### 6. Complete the measured 4 GB budget and recovery evidence

Use existing minute collector plus controlled isolated bursts, including file
copy/backup, Edge concurrency and representative app traffic. Keep Studio
available. Test lower admin ceilings, bounded Edge concurrency and backup
working memory as needed; do not set critical caps from sampled working sets.
Version a numerical RAM/CPU/PID budget including actual cache accounting, DB,
OS and concurrent backup reserve. Validate OOM/restart/backpressure recovery in
isolation, then stage justified limits through existing Compose/systemd owners.
If constraints still do not fit, report measured shortfall and a concrete
tradeoff rather than claiming completion or buying RAM contrary to the decision.

Prove alert delivery, successful new backups/WAL and full isolated application
recovery. Report the measured end-to-end recovery time; no incident RTO promise
has been selected. Exit: complete enforceable budget and recovery receipt,
or a precisely identified remaining capacity/objective decision.

## Publication, execution and rollback

Run normal targeted standard checks on final inputs, plus mandatory repository
publication gates. Fetch current main immediately before publishing; reconcile
overlap and current protection/review requirements. A local plan or passing
fixture is not a deployed source. Stage exact main, Worker and Edge revisions;
delegate routine release/monitor/readback to the authorized lower-cost release
agent with those frozen revisions and no broader tenant scope.

Keep copies and originals through verification; pointer/field changes retain
protected exact prestate. On partial transfer, resume recorded verified objects.
On an edit conflict, abort the batch. Before contraction, a data rollback must
restore exact matching fields and publish sync invalidation. After deleting old
sources, recovery is from verified canonical copies/backups; do not silently
restore Supabase Storage or dual writers. Never weaken security or replay the
two historical unknown email outcomes. Live disaster promotion is outside scope.

## Completion and residual risks

- All intended file/font producers, readers, cleanup and current HTML/JSON
  references use canonical R2 objects with preserved bytes and permissions.
- Exactly three redundant related buckets retired; AKH remains independent.
- Normal runtime has no Storage/imgproxy, old routes are unavailable, and
  backups/recovery do not depend on the retired services for new sets.
- Studio remains available on 4 GB; justified caps, real backup/restore, alert
  proof and selected DB/file recovery objectives are recorded.
- Production mutation and source digests, migration versions, live reads and
  unaffected boundaries are receipted; no claimed completion from local code.

Known accepted risk: historical Supabase Storage links in delivered/offline
content break. Remaining execution-time unknowns: same-key collisions, ownership
of retained orphan files, deployed temp-bucket consumers, private embedding
semantics, exact affected client rollout and whether the complete conservative
budget fits 4 GB. Each is resolved in the corresponding wave before destruction.
