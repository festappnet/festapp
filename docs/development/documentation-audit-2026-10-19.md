# Documentation audit - 2026-10-19

## Scope and authority

Reviewed repository Markdown entrypoints, feature READMEs, setup instructions,
architecture references and dated operational/planning material. The repository
scan covered 336 Markdown files before this report, excluding installed
third-party dependencies. Local path/link and named-RPC searches identified
candidates; current source, scripts and policy resolved the actionable findings.
Vendored MapLibre upstream documentation remains upstream reference material.

Current procedures start at [the documentation map](../README.md). Production
uses the canonical self-hosted backend and tenant-specific direct Cloudflare
releases. Supabase CLI remains required by the isolated local database bootstrap;
cloud project installation/deployment is not a supported system setup path.

## Corrections

- Removed the `instanceInstall` Flutter page and route, its Cloudflare routing
  prefix and the `instance-install` Edge source. Kept the production package
  denylist and exclusion evidence so the installer cannot be reintroduced into
  a canonical production bundle. `/install` remains the end-user mobile/PWA page.
- Removed unused `automation/sync_db.js`, which could mark a failed migration as
  applied. `apply_sql.js` is explicitly a low-level helper, not a production
  installer or identity-checked release workflow.
- Updated root/setup/automation/web-client guides to describe tenant configuration,
  protected production changes and the actual local database prerequisites.
- Replaced the iOS guide's obsolete Fastlane setup, interactive release notes and
  automatic-submission claims with the existing private manifest, pinned Bundler,
  upload-only script and separate gated submission lanes.
- Corrected Cloudflare build steps, routing and new-tenant instructions. Removed
  the cloud Supabase project example; canonical activation and main-owned tenant
  drift checks are required.
- Corrected occasion image copying/deletion documentation against `DbOccasions`
  and `DbImages`: Worker/R2 copies, preserved partial copy results, and no
  client-side orphan Storage deletion.
- Replaced nonexistent `delete_user` references, distinguished mutation-design
  examples from implemented RPCs, completed the Edge inventory with customer
  order access and waitlist commands, and repaired the ticket-font license path.
- Marked February review checklists as historical, updated the retained installer
  exclusion notes and clarified dated version research.

## Verification and limits

Regenerated AutoRoute from annotations. Targeted validation covers the router,
Edge coverage/runtime inventory, production bundle guards, shell syntax and local
links in active Markdown references. This is a source/documentation audit, not a
fresh production inventory, external provider-console review or release rehearsal.
No remote SQL, deployment, cloud resource deletion, mobile publication or local
database reset was performed. Existing dated receipts and archived commands are
retained as evidence and must not be replayed as current setup instructions.

Validation results:

- Active Markdown local-link scan: 84 files, zero missing file targets. This
  checks file targets, not remote sites or every heading anchor.
- AutoRoute generation completed successfully; no `InstanceInstall` route or
  page reference remains in the application source.
- Shell syntax and scoped whitespace checks passed.
- The initial three-file Node batch passed 40 of 43 tests. The focused follow-up
  passed 9 of 10 selected tests, including Edge coverage and production bundle
  guards. Installer removal required allowing the denylist to retain a name
  after source deletion; that stale-policy issue was corrected.
- Runtime inventory remains blocked by the unrelated, unclassified
  `exchange-sign-in-code` Function in the existing working tree. Two other
  inventory tests disagree with current DML-adapter counts and event RPC
  search-path inventory. These were left for their owning implementation work.
- Targeted Dart analysis reported no errors, one generated-route
  `invalid_use_of_visible_for_testing_member` warning (`editorOverride`) and
  one existing `LINK` naming info. The analyzer therefore returned nonzero.

The audit does not certify a green full test suite. No release was attempted.


## Second pass: server setup, Cloudflare and implementation contracts

The README is now a project overview with task-based links. The previous feature
screenshots are retained in `docs/overview/features.md`. Setup detail lives in
`docs/setup/server_deployment.md` and `docs/setup/cloudflare.md`; the Pages and
backend tooling READMEs point to those guides. Historical Wave 0 commands moved
to an explicitly historical operational reference.

| Finding | Correction and source evidence |
|---|---|
| Host provisioning could be read as a complete production installation | Documented ARM64/Ubuntu checks, host dependencies, rehearsal defaults, missing production seed/integration steps and hardcoded hostname/three-source promotion constraints. Sources: `runtime/bootstrap-host.sh`, `deploy-rehearsal.sh`, `promote-production-runtime.sh`, Terraform and Compose. |
| Pages upload appeared to provision the whole platform | Separated Pages, shared Workers, R2, DNS, Access/Tunnel, image product, backup and sync setup. Account credentials and origin CORS have distinct owners. |
| Upload script appeared to prove branch readiness | Clarified that ancestry, clean release inputs and main-owned drift checks are preparation steps; `deploy_direct.sh` itself validates a branch tag and allows dirty uploads. |
| OAuth appeared equivalent to token-based setup | Documented that OAuth checks an existing project/domain but does not reconcile Pages runtime variables. Token setup can mutate the project/DNS before a later build failure. Source: `deploy_direct.sh`, `ensure-pages-project.mjs`. |
| Test wrapper exit status implied every lane passed | Documented warning-only web/integration failures, conditional skips, explicit automation list and Deno scope selection; supplied isolated DB overrides and direct lane commands. Source: `test_all.sh`. |
| Client runner suggested an unsupported `--no-pub` option | Explained that the wrapper already supplies it to Flutter; it is an option for direct Flutter invocation. Source: `test_client.py`. |
| CSV email treated as one participant identity | Documented mailbox/name reconciliation, stable aliases, separate delivery email, ambiguity rejection, actual import roles, v1 transport and blank date/sex behavior. Sources: `ImportHelper`, `CsvImportHelper`, CSV SQL and `DbUsers`. |
| Activities publication described only two legacy requests | Documented atomic versioned v1 publish separately from autosave and the retained legacy path. Sources: `db_activities.dart`, `activity_commands.dart`. |
| Inventory writes omitted selected v1 commands | Documented versioned pool/resource/spot commands and legacy adapters. Sources: `db_inventory_pools.dart`, `inventory_commands.dart`, `spot_commands.dart`. |
| Context checks implied server authorization | Distinguished UI permission/context state from SQL/RLS and Edge enforcement. Source: `RightsService` and permission boundaries. |
| App-config fallback description was too narrow | Recorded exact missing-function fallback and the real helper name. Source: `app_config_rpc.dart`. |
| Blueprint zoom and performance claims were absolute | Corrected fit-relative zoom, both-axis bounds, controller ownership and renderer cleanup; removed guaranteed frame-rate claim. |
| Form fonts described a fixed global default | Documented tenant-inherited font/scale and per-form overrides. Source: `theme_service.js`, generated theme configuration. |
| Wizard finalization described as unimplemented | Documented current SQL finalization, replay handling, real hidden/closed occasion and the local launcher's limited RPC refresh. Sources: `occasion_setup/finalize.sql`, `occasion_setup_page.dart`, `run_occasion_setup_local.py`. |
| Historical image scan implied canonical Storage coverage | Corrected configured source filtering, `.supabase.co` URL scope and absent dual-write verification. Sources: migration URL helper and `verify.js`. |
| Backup setup omitted prerequisites and coverage | Added exact installer acknowledgement, root-only input names, timer, host/bucket guards, restore checks and separate R2 coverage. Source: backup installer, creator and timer. |
| Fastlane commands used shell-invalid optional brackets and omitted lanes | Made Bundler commands executable and included existing internal TestFlight/editable-version/release-status lanes. Source: `Fastfile`. |
| Dated cloud rollout was titled current status | Marked the August implementation record as historical; preserved its original evidence and stable path. |

Writing structure follows
[crafting-effective-readmes](https://github.com/softaworks/agent-toolkit/blob/main/skills/crafting-effective-readmes/SKILL.md).
The prose pass used
[humanizer](https://github.com/blader/humanizer/blob/main/SKILL.md), retaining
technical contracts, commands and source-backed limitations. These references
were read for this task; no global skill installation was required.

Cloudflare setup links to the official Direct Upload, custom domain, R2 CORS and
Tunnel references. Provider behavior was checked against those references;
repository-specific behavior was checked against the scripts above.

This pass changes documentation only. It does not make the migration-specific
host tooling portable, repair the test wrapper, provision private inputs or
certify a fresh production installation. Those implementation limits are now
explicit rather than hidden behind apparent setup instructions.

Second-pass validation passed: 87 active Markdown documents, 203 local file/heading
links, balanced fenced blocks and 33 shell examples parsed with `bash -n`.
The Fastlane lane reference matches the checked-in lane names; the backup
acknowledgement matches its installer. Scoped `git diff --check` passed.
No application tests or deployment scripts were executed in this documentation-only
pass. External links were checked selectively against the cited provider/skill
sources, not exhaustively crawled.


## Third pass: local README value

Local READMEs should retain context that crosses source-file boundaries: ownership,
transaction/retry semantics, authorization, resource cleanup and test-data provenance.
Shared concepts have one owner; adapter-specific differences stay beside that adapter.
The rule is recorded in `docs/architecture/ai_context.md`.

- Removed `lib/components/features/README.md`; its useful feature/profile boundary
  is now a short central architecture section. Class/default inventories stay in
  source.
- Removed the JS `forms/README.md` and `eshop/README.md`. The web-client entrypoint
  retains browser session/theme ownership and links to the shared form/order
  contracts, avoiding two copies of backend rules.
- Reduced ticket-layout documentation to the current schema/resource, rendering,
  persistence, preview and release boundaries. Removed accumulated migration-by-
  migration rollout instructions and conflicting older resize/font descriptions.
  The source table points to the validators/controllers instead of duplicating
  their complete field and numeric-limit inventories. Updated the active blueprint
  plan's section references.
- Corrected the form README: `create_form_ws` creates an administrative form; it
  does not submit participant registration. Regular/free customer orders use the
  order endpoint; waitlist acceptance has its separately documented command.
- Kept a short Information README for the public/editor hidden-answer boundary,
  online game command and cache/reading lifecycle. Authorized editors can read
  hidden configuration; public participant projections must not expose it.
- Replaced the `_shared` function inventory, including removed named-ticket
  functions, with the email/auth and single-renderer boundaries.
- Replaced the obsolete external-sync startup guide with the actual retired
  service-role stubs and their `unbounded_http_import_retired` failure. Retained
  the distinction between that importer and Client Sync v1.
- Shortened Flutter test-session documentation to registration/ownership/cleanup
  rules. Classifications and benchmark history remain in their existing artifacts,
  without a second hardcoded session count here.
- Kept package, fixture, inventory, seat-map, email and other domain READMEs whose
  invariants or provenance remain useful. Folder depth or short length alone is
  not a reason to delete documentation.

This pass changes Markdown only. It does not remove any runtime implementation
or test fixtures and does not rerun application suites for prose changes.

Third-pass validation passed: 84 active Markdown documents, 220 local file/heading
links, balanced fences, the existing 33 shell examples and scoped whitespace
checks. Three redundant READMEs were removed. Ticket layout's README is now 89
lines instead of 376; its executable schema remains in source.

## Fourth pass: operational instructions and recovery evidence

This pass compared active operational prose with its scripts/SQL, including
references previously excluded as dated records. No live system was queried.

- Backend architecture now identifies the canonical database as runtime authority,
  source-project IDs as import provenance, and the full freeze as the original
  cutover requirement. Worker orchestration does not create a second relational
  authority or an atomic SQL/R2 transaction.
- Storage/merge/deletion documents distinguish original migration inventories and
  directives from current operations. The retained cloud sources must not regain
  routine writes. The later cleanup/retention receipts take precedence over the
  original planning table; script absence is not zone-route inventory proof.
- The unattended-access proposal now points to the active protected SSH channel
  and states that its proposed restricted SQL broker remains unenabled.
- Version policy uses repository pin/Compose inputs and correct repository-root
  verifier paths. Local format checks, upstream comparisons and actual installed
  versions are separate evidence. The old "writable according to migration wave"
  statement was removed.
- Email operations separate routine maintenance from the completed first-cutover
  sequence. Dated versions, pause state and unresolved counts are not current
  health. Routine changes preserve prior operator pause, payload keys and intents.
- The historical email harness chooses filenames using an old Git tree but reads
  SQL bytes from the current checkout; it is not an immutable replay or full
  current-schema bootstrap. SQL test failures propagate after retry, while a
  filter selecting zero tests still exits successfully.
- Offline-map setup now requires an explicit verified canonical public target;
  the builder itself still falls back to legacy config fields and checks only
  link/ID, not activation/organization. No tool adaptation was performed.
- Offline-map docs no longer advise hiding a tracked manifest to bypass immutable
  version checks. Verification covers all asset hashes; MBTiles/SQLite and legacy
  rollback requirements depend on dual-renderer versus MapLibre-only mode.
- Backup evidence distinguishes local encrypted SHA-256, size-only upload checks
  and a downloaded/decrypted restore. The explicit runtime archive omits the
  email Compose overlay, Tunnel token files, systemd jobs and other auxiliary
  inputs. Complete recovery therefore needs protected release/configuration
  inputs as well; the backup implementation was not changed.
- Tenant font instructions now document explicit `FONT_FILES` under `fonts/` and
  the shared `automation/fonts/` fallback rather than a single unconditional path.
- The work-item index now matches the EUR item's recorded `in progress` status
  and its real next action: a bank transfer/pairing check after the recorded QR
  pilot. This does not constitute a fresh payment readback.

All Markdown file targets across guides, plans and records were scanned without
missing targets. Active operational heading links were also checked. The 111
literal abuse seed rows recognized by static extraction matched the corresponding
printed scope/limit/cap/window/bucket values; remaining derived/default rows were
not evaluated through a database, and no production policy state is certified.

Fourth-pass validation passed: 145 active/operational Markdown files and 310
local file/heading links, plus the retained shell-example and whitespace checks.
No application tests, restore, provider mutation or deployment was run.

## Native map canonical cutover

Removed the reachable pre-CSM offline renderer, standalone package/style
URL downloader, renderer setting and benchmark override. Online/web raster
behavior now belongs to `RasterMapSurface`; native offline maps use only the
verified manifest manager and MapLibre. Removed the unused one-off
`configure-rollout.mjs` writer and the builder's fallback to compiled backend
credentials. Updated the settings UI, translations, dependency graph, test
registrations and semantic inventory for the surviving contract.

CSM's immutable schema 2 bundles remain supported through MapLibre MBTiles;
schema 3 PMTiles also remains supported. Older notes above describing a legacy
renderer rollback reflect the audit before this code cutover and no longer
prescribe current behavior. No production data, published bundles or live
client was changed. Native device acceptance remains a release step.

Validation for this cutover: 104 targeted Flutter cases and 34 core map cases
passed. The changed Dart files have no analyzer diagnostics; the semantic
inventory accounts for 25 retained and 3 new configuration/surface cases without
missing or duplicate execution. Documentation checks passed for 145 active
files, 311 local links/anchors and 33 shell examples. Builder shell syntax,
translation JSON, obsolete dependency absence and whitespace checks passed.

The repository-wide architecture guard remains blocked by unrelated working-tree
registrations: unclassified `image_upload_contract_test.dart`,
`price_wave_availability_test.dart` and `client_command_identity_test.dart`, plus
a classified but missing `ticket_background_image_cases.dart`. These files and
their registrations were not changed as part of the map cutover. A broader map
analyzer pass also reports an existing rasterizer async warning and four style
infos outside the changed implementation; the targeted changed-file pass is clean.

## Integration onto current main

The final publication was prepared in an isolated checkout of current main,
without bringing unrelated changes from the original working tree. Upstream
asset/backup and public-order cutovers take precedence over the earlier audit
snapshots above: canonical image buckets are consolidated, API Storage URLs are
retired, and `archive-runtime.sh` now includes email/PITR overlays and the Tunnel
credential. The setup/backup guides were reconciled accordingly. Current activity,
ticket-layout and customer-order documentation was preserved rather than replaced
with the older working-tree descriptions. Public URL and authorization details
from main were retained; the obsolete installer remains removed.

Final isolated-main validation passed: 104 Flutter map/configuration cases, 34
core map cases, 43 backend inventory/coverage/promotion cases and the architecture
registration/dependency guard. All 25 retained semantic cases and 3 new cases
were accounted for. Documentation validation covered 159 active/operational files,
312 local links/anchors and 34 shell examples without findings. The router was
regenerated after installer removal. Targeted analysis reports only the existing
generated `editorOverride` warning and `LINK` naming info; no Dart errors.
No deployment or live data change was performed.
