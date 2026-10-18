# Storage retirement execution - 2026-10-18

The full plan is **not complete**. The latest production state appears in the
final section; earlier sections retain their historical execution boundaries.
The prepared implementation
was transferred onto freshly fetched main
`2aa995c6c` on branch `feat/storage-r2-retirement-20261018`, in
`/tmp/festapp-storage-r2-main-20261018`. The earlier isolated worktree remains
preserved at `/tmp/festapp-storage-r2-20261018`, based on
`8b1420ea1da7349db68b4a293bb37da049fb9047`. No unrelated checkout changes were imported.
Only the authoritative plan, its execution prompt and five sanitized evidence
receipts were transferred from the planning worktree.

## Actual inventory

The protected SSH target, runtime database and published `festapptickets`
canonical activation were verified before the read-only capture. Application
schemas are public/eshop; managed and retained merge schemas are classified
separately. No production mutation was executed.

- 141 application relations scanned; 533 current fields contain 572 recognized
  owned Storage references. This includes HTML, JSON, arrays, product data,
  templates and configuration. Stored generated search documents are derived
  from their source fields and are not independently rewritten or treated as
  original object locators.
- Every one of 1,479 Storage registry objects has a matching versioned local
  file and SHA-256. There are 1,743 disk files in total; the other 264 files
  remain inventoried and preserved, with disposition unresolved.
- 563 objects have no proven owner binding after recognizing image-registry
  scopes, original Storage ownership and the service font namespace. The
  original nullable owner record is retained verbatim in protected evidence;
  no human owner is guessed from a filename or a reference.
- Two current offline-map references in `public.occasions`, id 63, field
  `features`, have neither a Storage registry object nor an exact/filename
  candidate among the 1,743 disk files. Both must be resolved before claiming
  complete migration. These are distinct from the already removed 50 R2 rows.
- All 1,074 R2 source objects were streamed through SHA-256: 410 default and
  664 `a`, totaling 341,530,791 bytes. Four source bucket listings were checked
  again after hashing; no listing changes were detected. Fourteen equal keys
  occur in both public buckets; their present bytes match. The implementation
  still namespaces `a` keys to avoid collapsing independent identities.

Detailed identities, customer values, exact prestates, MIME metadata, file
names and hashes are kept only in mode-0700 protected evidence:
`~/.local/share/festapp-storage-retirement-20261018/`. The combined manifest is
`manifest-current/manifest.json`; the small unresolved-map extract is
`missing-current-sources.json`. Captures are separate online points, not an
atomic DB/file snapshot. Sanitized counts and digests are in the adjacent JSON
receipt.

Follow-up investigation located the two missing map references in a hidden
occasion dated December 11-13, 2025. Its map feature and forced native offline
mode remain configured. Current web code does not initialize native offline
maps; this does not prove that no installed mobile client uses a cached copy.
The offline layer selects one package; the other package property belongs to
the online layer and is not selected by the current offline configuration.

All 47,125 objects in the public sync/map bucket were listed. Its six tile
packages belong to other published event bundles; neither missing package was
found. The other related asset buckets and targeted generated/local/simulator
and server paths yielded no matching package. Complete encrypted Storage
archives from the oldest retained set (20260920T024421Z) and the selected
20261016T164727Z set were streamed through verified decryption and scanned;
neither contains the packages. No plaintext archive was written. This is not
an exhaustive scan of every retained snapshot or inaccessible former cloud
storage. Among 27,319 retained Caddy access records spanning approximately two
days, neither missing binary was requested. Absence in this bounded log window
does not prove zero use, particularly for previously cached native maps.
Configuration was not removed or silently reclassified as immutable history.
Private evidence is in `map-investigation-result.json` beside the manifest.

## Jubilee map and approved test-occasion cleanup follow-up

The user authorized removing the identified Roma test occasion (63, org 1,
`romatrip`). This does not authorize blanket deletion of unrelated occasions
based only on membership count. A fresh read-only check found one membership,
zero orders, one event, eleven places, three forms and one image. The deployed
internal delete body matches canonical main (MD5
`b566e2ab608fc9fe61a19373184cab4a`). Deletion has **not** executed: the canonical
client-sync delete owner must preserve tombstones and the original destructive
recovery gate remains unmet. Calling the internal helper or deleting the parent
row directly would not establish those guarantees. Keep the two missing map
references in the live manifest until the approved cleanup actually completes.

Jubilee is a distinct retained production occasion. Its published activation is
canonical, tenant `jubileum2025`, generation 1; the published web version is
0.20.141+625 and the matching tenant branch head is `a826b4ace`. The canonical
occasion has 1,234 memberships and 94 places. Its Rome package and style both
return HTTP 200 without credentials. The complete 18,505,728-byte package matches
the inventory SHA-256
`a553b7ffaeae07f30a2de483b0804c7f0bf81785ada0d1068cb141a1659868e8`;
SQLite quick_check returns `ok`, with 624 tiles, zooms 0-14 and bounds covering
Rome. The 170,054-byte style also matches its inventoried hash. These retained
assets are still in Supabase Storage, not in the surveyed R2 buckets.

The published web source uses online OpenStreetMap tiles (one sampled tile
returns 200). Native configuration forces Legacy MBTiles: it reuses the local
package or downloads it on first use. This is configuration/source evidence,
not a physical-device smoke test or proof about every installed mobile build.
Two limitations predate migration: the style's 1x/2x sprite JSON and PNG URLs
return 404, and the pinned Legacy StyleReader fetches the style over HTTP even
when its local copy exists. Sprite-index failures are caught, so they do not
alone prove that the entire base map fails; icons can be missing. A cold offline
reopen can fail at the network style request despite a cached MBTiles package.
Preserving the package alone is insufficient evidence of complete offline use.
Protected evidence is `jubilee-live-map-probe.json` beside the manifest. No map
configuration, occasion data or production deployment changed in this check.

### Retained sprite assets found on R2

The subsequent dependency search found existing 1x/2x sprite JSON and PNG pairs
under the CSM and Slunovrat map bundles in `festapp-public`. All four CSM v2
sprite objects were downloaded through their published URLs and checked against
their published manifest lengths and SHA-256 hashes. There is no need to infer
their contents from filenames or replace the image atlas with a new drawing.
The new read-only `map_dependencies.py` auditor checks both atlas scales,
geometry and actual icon-output expressions. For the exact retained Jubilee
style it identifies 110 required symbols: 109 exist in each retained atlas;
`icon-church` is missing at both scales. The receipt correctly exits 2 rather
than approving a partial sprite replacement. Four new focused tests pass along
with the seven existing reference/manifest tests (11 total).

This confirms useful retained R2 dependencies, **not** a completed Jubilee
cutover. The missing original symbol, complete offline dependency closure,
asset ownership/rewrite receipts and existing publication/restore gates remain
unresolved. No new R2 object, source deletion or live style rewrite occurred.
Private receipt: `jubilee-sprite-audit.json`; downloaded source/style/atlases
remain in the protected evidence directory. The user reaffirmed that all
retained map content belongs on R2 and no local Supabase Storage should remain.

## Latest implementation and verified inventory follow-up

Fresh main still resolves to `8b1420ea1da7349db68b4a293bb37da049fb9047`.
A fresh read-only inventory includes the actual Storage RLS, client-role flags
and policies. The protected connection's current selected context is
`festapptickets`, org 3; its canonical generation-1 activation, configured org,
SSH hostname, runtime DB and database org were verified before this capture.
The live database is PostgreSQL 17.6 despite its retained rehearsal-era name.
The disk inventory hash is unchanged. All 1,479 registry objects still have
exact versioned source files; every original owner/owner_id is either the
recorded original binding or an explicitly preserved null.

The manifest builder now supports explicit retention of proven ownerless objects
under service custody without assigning a human owner. This requires the audited
closed private-client policy/role boundary. All 264 unregistered disk files are
assigned exact private R2 retention destinations, not discarded or exposed as
application objects. The resulting candidate has zero unresolved source-object
issues and is ready for **additive copying**. The one field containing the two
missing Roma references still blocks reference rewrites and final cutover.
Protected manifest: `manifest-ready-copy-20261018/manifest.json`; sources are in
`capture-policy-20261018/`. R2 source inventory must still be refreshed at execution.
Copy readiness does not waive reviewed-main, source delta, rewrite or restore gates.

Account-deletion implementation is now prepared locally end to end: exact
canonical asset/owner registry, durable per-account queue, SQL acknowledgement
and completion guard, a dedicated bounded Worker deletion capability and Edge
transport. The old active Storage batch RPC/helper/SDK branch is removed from
current sources; historical migrations remain unchanged. The new forward
migration is generated from canonical sources and defaults to an inactive asset
cutover flag. User ownership survives Auth deletion; confirmed object tombstones
remove the original owner/key metadata. Provider failures and lost acknowledgements
leave durable work to retry. Public cache purge completes before acknowledgement.
Fonts, AKH and noncanonical buckets cannot use this cleanup route.

Validation in this follow-up: Worker typecheck and 108 unit tests pass; the full
Deno suite passes 361 tests; 12 Python inventory/map-dependency tests, four Node
copy tests and two route-disposition checks pass. The generated migration source
parity check passes. An actual task-owned PostgreSQL 17 container loaded the
canonical registry, service-role owner, cleanup functions and updated account
completion function and passed the SQL lifecycle test, including cross-owner
denial, wrong-hash rejection, retry, unassigned-file retention and terminal
privacy cleanup. This is a minimal disposable SQL fixture, not a full application
restore or actual R2 provider delete. The container was stopped and removed.

Routine live health readback was delegated per AGENTS.md. Canonical Festapp
activation was verified; Studio, Storage and imgproxy are healthy, without
reported OOM/restarts. Studio has a 768 MiB/256 PID/1 CPU ceiling; Storage and
imgproxy have no configured ceilings. Approximately 1.07 GB RAM was available
and no swap was enabled. This point sample does not prove the 4 GB budget.
No deployment, production mutation or bucket operation occurred.

## Locally prepared code

- Catalog-driven read-only collectors, recursive exact reference parsing,
  candidate manifests and a gated, resumable conditional-create copy driver.
  The driver checks exact source/destination length, SHA-256, MIME and access
  class; preserves conflicting destinations; and writes atomic immutable
  receipts carrying source/manifest/inventory digests. Mutation requires a
  resolved manifest and clean reviewed canonical main. The real copy path has
  not been run; provider behavior is not claimed from its simulated tests.
- A single Worker key boundary for default/`a`/Slunovrat in the canonical
  bucket pair, preserving `a` URLs via `imports/a/`. AKH retains its separate
  bucket, prefixes and Auth/SQL contract. Public serving rejects private/font
  namespaces and hidden physical aliases; binary MIME bypasses transforms.
  Deletion authorization still receives the original URL before translation;
  source and normalized cached image representations are purged together.
- Dedicated private immutable font read/create capability and Edge transport,
  preserving resolver IDs/hash checks/limits. Its secret is scoped by the Edge
  environment owner to download, preview and the queued email renderer.
  Provisioning and activation have not occurred. The Flutter image-deletion
  branch no longer calls Storage in this local change.
- Staged v2 canonical-asset archive writer/verifier library with explicit v1
  historical-reader behavior. The active online backup contract remains v1;
  it has not been switched to omit uncopied source objects. No retained backup
  was relabeled or modified.

Worker bindings and font transport are **not safe to deploy yet**. Their
activation requires the full source-copy/delta/producer gates and protected
secret provisioning. No tenant branch has been changed, built or released.

## Validation and publication

Targeted checks passed: Worker typecheck; 104 Worker tests; 33 Deno font,
PDF-renderer and secret-isolation tests; 7 inventory/parser Python tests;
8 archive Python tests; 4 immutable-copy Node tests; 22 affected automation
tests; and targeted Dart analysis. Twenty-seven provider integration cases
were skipped without their fixture credentials. Fixture results do not prove
live file copy, production ownership, private serving or a full restore.

The required full test command was also attempted. Web tests passed (411
passed, nine skipped). Its auto-selected shared local DB lacked newer schema
objects, producing 30 SQL failures; that database was not rebuilt. A separate
task-owned DB was bootstrapped through the repository workflow on port 56342.
Its full SQL run passed 193 tests and failed 22, including canonical source
parity, retired-facade assertions and admission/email fixtures. No SQL,
migration, bootstrap or database-test source is changed by this work. These
failures must not be presented as a passing publication gate or repaired by
importing unrelated work from the main checkout. Remaining full-run component
results are recorded in the adjacent JSON receipt. Portable core and native
adapters passed; Flutter failed existing sign-in transport expectations and
reported three unclassified test roots. All 359 Deno tests passed. The new
font-route security inventory was corrected and its two targeted disposition
checks passed. Three other automation failures remain: canonical abuse and
server-security migration assembly parity, and a stale literal restore-source
assertion. The task-owned database fixture was stopped and removed after use;
the original shared fixture was preserved.

These older failures describe the original base, not the refreshed main.
Integration PRs #464 and #472 subsequently corrected those baseline contracts.
Publication validation is now rerun against the refreshed implementation below.
Main branch protection requires one approving review. No Worker deployment or
Edge promotion has occurred; publication never proves production activation.

## Main integration readiness

The staged changes were transferred onto main
`a7e0f01596258f0be454ec9c2754d97b9a719832` without importing other checkout WIP.
The single Dart conflict retained upstream's removal of an obsolete cleanup
helper. The obsolete Storage-SDK font test was removed with its deleted adapter;
the new R2 transport has separate success/missing/denied/interrupted tests.
New service-only SQL definers now declare their signatures and role ACLs in the
canonical security contracts. Current release-manifest digests were regenerated;
no previously applied migration SQL was rewritten.

The required complete test surface now passes on this base: web 418 passed and
10 conditional skips; all 220 SQL files passed in a new task-owned local DB;
the complete client runner passed architecture and registration checks, with
157 core, 78 adapter (one skip) and 1,313 Flutter cases; Deno 362 passed;
automation's final batch 139 passed; Worker typecheck and all 108 unit tests
passed. Python inventory/map tests (12), archive tests (8), four Node copy tests
and generated migration parity also passed through the normal runner. The 27
real provider integration tests remain skipped without provider fixture inputs.
These are not evidence of an actual production copy or R2 delete.

The initial complete invocation stopped at missing package-local dependency
resolution and an obsolete Deno import. After those corrections, all affected
and remaining lanes were run through `test_all.sh flutter` and
`test_all.sh integration automation`. The security declaration/digest correction
was followed by the complete automation lane and two affected SQL lifecycle
tests. Passing unchanged web/DB/Worker lanes were not repeatedly rebuilt.
The production copy CLI also rejects this dirty source before loading any
provider credentials. Reviewed detached worktrees at the exact main revision
are accepted; a branch label alone grants no authority.

This publication stages the reviewed source needed for additive verified copying.
It does **not** authorize deploying the prepared bucket bindings, new font
transport or account-cleanup consumer before their copy/registry/secret/delta
gates. Existing online backups and production services remain active. Main still
requires one approving review; the repository does not enable automatic merges.

## Final refreshed-main validation

Immediately before publication, main advanced with registration-form and
Fakturoid order-deletion changes. The implementation was rebased onto
`5bc3addccffed0d2dfdeda9655d447c32677fe65`. Conflicting ACL declarations
were combined by retaining upstream declarations and adding only the two asset
service signatures; both runtime digest manifests were regenerated. No upstream
feature or previously applied migration was discarded.

The single complete `automation/test_all.sh` invocation on this final code
passed: web 423 (10 skips), all 221 SQL files, full client architecture/inventory
and 158 core / 78 adapter / 1,314 Flutter cases (one adapter skip), Deno 382,
and automation 139 in its final Node batch. Worker typecheck and 108 unit tests
also passed. The 27 provider integration cases remain explicitly skipped.
Results are execution evidence for staged source, not a production copy/restore.

The last pre-push refresh additionally included upstream PR #476, changing only
three draft-card UI/test files. Rebase was conflict-free, with no migration-file
change; the affected standalone Flutter suite passed all three tests. Final
publication base: `2aa995c6c406fcd23adb79bcae8cfeaa3e7c84eb`.

## Earlier staged-state boundary

The reference-completeness gate has not passed. Additive source-copy inventory
and account-deletion ownership/retry code are now prepared locally. Registry
import/activation and the exact transactional field rewrite with sync invalidation
are not implemented or applied. The new
off-host backup, independently keyed isolated application restore, recovery-kit
refresh, Storage/imgproxy runtime contraction, three bucket retirements and
enforced measured 4 GB capacity budget remain undone. Neither recovery-point
objective nor a recovery time is newly proven here.

All original objects, volumes, buckets, services, Studio availability and
production references remain intact. Final read-only runtime inspection found
13 running containers, Studio/Storage/imgproxy running and no current OOM flags.
This single readback does not prove the capacity budget. The accepted 50-row cleanup was not
repeated. No disaster promotion, email/payment replay, paid resize or additional
tenant rollout was attempted.

## Production execution follow-up

PR #478 merged the canonical service implementation; PR #484 merged the
conditional remote R2 transport and verified cutover-bundle preparation.
Production copying runs from clean authoritative main
`a0c212c9523d94f34409ae8d408c942371513596`, using existing Cloudflare OAuth.
The fixed transport can read the four source buckets and conditionally create
only in the two canonical destinations. Per-object receipts distinguish new
creates from independently verified existing bytes. The complete source set is
2,817 identities, including all 264 private unregistered disk files. Copy is in
progress, with no source deletion or overwrite. A fresh independent capture
found source objects, orphan provenance and all 533 reference fields unchanged.

Two separate font/cleanup capabilities are installed in protected stores. Their
same-code Worker secret deployment preserves the active code SHA and all five
R2 bindings, including AKH. The provider route-list API was unavailable; no route
write was issued. The prepared canonical Worker implementation is not deployed.

Fresh encrypted production backup `20261018T152837Z` completed off-host
verification. An isolated restore acquired its key/reader from the existing
iCloud recovery ZIP, downloaded the selected set and restored the real DB on the
pinned PG17 image with no network, ports, host mounts or production integrations.
It verified 1,180 selected archive objects and 947 DB R2 references with zero
missing. Restore execution took 80.17 seconds; acquisition/download are recorded
separately in protected evidence. This is an old-format pre-cutover DB/R2 proof,
not a new-format full application/PITR recovery or an RTO guarantee.

The next source increment implements the exact operator transaction and v2
backup/restore path. Registry import, typed original-value matching and canonical
public/private sync commits share one atomic transaction. Five actual isolated
PG17 tests passed, including concurrent edits, changed source ownership and sync
failure rolling back every mutation. The explicit approved exception discards
only the fingerprinted broken map feature on test occasion 63, preserving other
features; production guards also require the unchanged hidden test identity,
one membership and zero orders. No general low-user occasion cleanup is added.

V2 sets require both canonical asset buckets and sealed private orphan provenance
inside the encrypted runtime archive, without a Storage artifact. The reader
checks all current application fields, registry hashes/size/MIME and retained
orphan identities. Historical v1 sets retain their named reader. Marker activation,
actual new off-host backup/full isolated restore and recovery-kit refresh remain
unexecuted. Reference SQL is implemented but not applied; cleanup remains fenced.

Targeted Python/archive checks and all five actual PG17 transaction tests pass.
The affected normal automation lane passed on frozen inputs. Previously passing
unchanged web/SQL/client/Edge lanes from PR #484 remain recorded separately.
Final publication must reconcile current main and its affected checks. Runtime
contraction, old bucket retirement and the numerical enforced 4 GB budget remain
required; no production completion is claimed from this source increment.


## Production activation at canonical main 036244b63

This section supersedes the earlier staged-state descriptions. PR #487 merged
source `036244b63c5d9ea08cc7588281d946a43492271c` after all four required CI
checks passed. No other tenant release was performed.

- All 2,817 source identities were independently hash/length verified at their
  canonical destinations: 2,407 conditional creates and 410 existing objects.
  All 264 retained disk-only objects have encrypted private custody provenance.
  A fresh canonical listing comparison found all 664 former `a` objects
  unchanged. No source was deleted or overwritten.
- The canonical Worker is actually deployed at version
  `e664db1b-c25f-4b17-a37b-16107a25c5ca`, with exactly public, private and AKH
  bindings. Former `a` reads translate to canonical imports. Three independent
  reads each for default, former `a` and AKH matched their expected hashes;
  unauthenticated private reads were denied. All 13 service fonts matched
  their original bytes, totaling 2,170,816 bytes.
- The guarded production transaction imported all 1,479 original registry
  identities, rewrote the 533 exact typed fields, recorded 145 canonical sync
  commits and sealed manifest SHA-256
  `6453d0a89442e93cd6e5d9e4c96a3270e13390d9470632c6c69f33a6bb19bb65`.
  The cleanup flag remains inactive. Only the fingerprinted broken test map
  feature was discarded; the Jubilee map and other occasion content remain.
- A new catalog scan of 2,339 current matching values found zero owned Storage
  URLs. All 66 latest sync components matched source revisions, with 11 of 11
  existing public heads current. The tenant rollout scope was unchanged.
- Six exact font/account-cleanup Edge files and the two required capability
  references were activated without unrelated main changes. The user approved
  a maximum two-minute restart; measured service interruption was 18.55 seconds.
  Studio, Auth and database container identities and health remained unchanged.
  Safe read-boundary probes passed, the original email pause was restored and
  historical unknown email outcomes were not replayed.
- Backup format v2 was enabled with protected custody metadata. Official backup
  `20261018T163914Z` is streaming its encrypted canonical R2 archive. It is not
  yet a completed backup or a new-format recovery proof. No plaintext artifact
  is written. The independent 4 GB recovery VM has been started using its
  existing pinned cached images, without production access or a paid resize.

Detailed per-object and customer-bearing evidence stays outside Git under
`~/.local/share/festapp-storage-retirement-20261018/`; Worker release evidence
is in `~/.local/share/festapp-r2-worker-activation-20261018/`.

The next source increment removes Storage/imgproxy from canonical Compose and
Envoy inputs, makes the public legacy endpoint return 410, retires application
metadata privileges and the legacy deletion helper, and preserves an explicit
v1 backup reader with its historical Storage image pin. Configuration preparation
refuses any unexpected remaining consumer and changes no live service. It also
fixes restored database ownership to the verified canonical owner `postgres`,
rather than broadening schema privileges to hide a recovery failure. The
obsolete initial migration-only integration script is removed; it exported an
old service credential and created Storage fixtures outside the active owner.

Actual new-format full application/PITR recovery, recovery-kit refresh, runtime
activation, source-volume/three-bucket retirement and an enforced measured 4 GB
capacity budget still require their ordered gates. No production completion or
new RPO/RTO guarantee is claimed from this source publication.

Runtime source validation passed the normal complete automation lane (140 final
Node cases plus the archive/manifest/configuration Python suites), all 225
isolated SQL files, changed Python/shell syntax and both immutable migration
assemblers. Real production Compose/Envoy inputs were prepared additively with
no unexpected consumers. The retirement migration must execute as protected
`supabase_admin`: PostgreSQL's non-superuser `postgres` cannot revoke grants
issued by the Storage owner. An explicit guard and final privilege assertion
prevent that silent partial retirement. Actual-role denial also passed against
a deliberately permissive test policy. Unchanged client/Worker release lanes
retain PR #487's passing evidence.


## Recovery cadence and retained-set format follow-up

Runtime source PR #488 merged as canonical main
`1c28f2c0ef63501cdef45d039cc6a6070e4329c7`; all four CI checks passed.
Its production contraction remains gated by actual new-format recovery.
Jubilee's map and style now pass real public canonical-R2 GET verification:
18,675,782 bytes in total, exact original SHA-256 and MIME. This is not a
physical-device cold-offline test; the documented pre-existing sprite/style
limitations remain. A read-only account-wide audit checked all 43 deployed
Workers and found no binding to any of the three retired-source buckets. Their
custom-domain lists remain empty, managed public access is disabled and only
the default multipart abort lifecycle remains. Notification API code 11015
again indicates no configured notifications. The current OAuth authority
returns HTTP 403 for API-token policy administration; source-reader grant
retirement has not been performed or represented as complete.

The next source increment schedules the existing backup owner twice daily
rather than relying on a 24-hour interval plus execution time to meet a
24-hour file objective. Monitoring warns after 18 hours without success; the
separate physical PITR base-backup threshold remains unchanged. Retention stays
14 days and four completed weekly copies. The pruner recognizes exact v2 sets
through the same format validator used by recovery; incomplete, unknown and
extended sets remain outside destructive cleanup. This source change has not
yet been installed and does not modify the currently running backup.

Cadence/retention validation passed the complete normal automation lane, the
six retention cases (including mixed exact v1/v2 sets, unknown-format custody
and changed-size rejection), and the monitor's 18-hour threshold boundary.
These checks do not constitute production timer installation.


## Actual new backup, PITR and first complete v2 recovery attempt

Backup `20261018T163914Z` completed in approximately 29m55s and passed off-host
verification. It contains exactly four encrypted v2 artifacts, no Storage
archive and no plaintext artifacts. Selected manifest SHA-256:
`c76db6511c266c230a4e8135984290f658a44f017f55fc62c164eb829656a2ff`.
Independent acquisition from the retained iCloud key/reader verified every
artifact again. The matching public Edge source cache contains all 34 entrypoints
and prepared in 32.96s before any private data/key entered the recovery VM.
Both IPv4/IPv6 guest egress guards preceded private transfer.

Actual PITR using full `20261018-031955F` paused at
`2026-10-18T16:44:59.063008Z` for the selected 16:45 UTC target; catalog and
isolated REST reads passed in 25.15s. The initial attempt exhausted the local
24 GB VM disk. Its receipt is preserved; only the local disk increased to
32 GB, keeping two CPUs, 4 GB RAM and no mounts. Production was untouched.
Acquisition duration was not captured and is not invented. This selected older
PITR copy does not establish a current wall-clock recovery point.

The first complete v2 application drill failed at Caddy startup after 86.58s:
its fixture port 8081 collided with postgres-meta's actual admin listener at
`PG_META_PORT+1`. The pinned image source confirms that listener. The next
source change uses isolated public proxy port 18081 and makes Studio's image
health check probe its actual fixture port 3001, leaving the original port
3000 assigned to PostgREST. This changes no production service or request path.
Failure evidence is retained; no success, orphan/font proof or source retirement
is claimed from that attempt.

Cadence PR #489 merged as `868e89d4531140556dbd441ef03d0d95ed929581`; its
four exact backup/monitor files are installed and verified. The persistent
timer's catch-up attempt stopped on the held deployment backup lock before
creating any new artifact. Its journal was preserved and only the failed status
was reset, without retrying a backup. Normal monitoring then passed; the timer
is enabled with both daily points and unchanged 14-day/four-week retention.

The fixture port/health correction passed 15 targeted archive/Edge/service
isolation cases and the complete normal automation lane. Its actual complete
v2 retry remains the decisive validation before production retirement.


## Complete service recovery and exact pre-existing reference disposition

The corrected complete drill at source `1622eaac8623cf86fefc182e92628dd21afe02d7`
recovered DB/Auth/REST, Studio/Meta, Envoy/Caddy and the actual Edge router/worker
in 51.43s, without Storage, external integrations or production credentials.
Studio and Meta each completed an 80-request burst with no OOM or restart.
All 2,817 archived objects / 1,642,200,830 bytes passed SHA-256 validation.
Its final reference check still failed: 46 missing references, zero mismatches.
The original failure/partial receipts are preserved, not relabelled as success.

All 46 URLs were already present before this migration. Forty-one occur only
in immutable commit audit labels and durable idempotency replay responses;
those are history, not current file consumers. No such field was changed in
the production Storage rewrite. The next source correction explicitly names
these two history tables in inventory/recovery, while continuing to inspect
active pending/blocked/preparing/sending/retry messages. It does not ignore
active templates or content.

Five references in four current fields are genuinely absent and return 404:
two wrapper images, two event header images, and one occasion image. They were
not found in original asset buckets, local files, the 47,125-object sync
inventory or the independent 516-object AKH inventory. The user explicitly
approved removal of these five links. A narrow operator removes exactly two
img tags and the three image properties, preserving every other value and
recording three existing canonical occasion sync commits in the same transaction.
It rejects changed original fields and replay. No image registry row or object
is deleted, and the original accepted 50-row cleanup is not repeated.

This disposition is prepared locally, not yet applied or backed up. The new
actual post-disposition backup/complete restore remains the destruction gate.
Current source buckets, local Storage files and services remain preserved.

The exact disposition passed three actual isolated PG17 transaction cases with
the real canonical sync owner: success/replay denial, changed-field rollback,
and sync-failure rollback. Three preparation/history cases and the complete
normal automation lane also passed. No production cleanup was executed by tests.
