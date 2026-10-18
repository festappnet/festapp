# Storage retirement execution - 2026-10-18

The full plan is **not implemented or deployed**. The prepared implementation
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

## Work not completed

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
