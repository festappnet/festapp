# AI Context — Festapp

Festapp is an event management platform: Flutter (mobile+web) + Supabase (PostgreSQL, Edge Functions, Auth) + vanilla JS web client for public forms/eshop.

## Critical: Resolve the Live Supabase Target from Activation

Since the 2026-09-10 production activation, `https://api.festapp.net` is the
canonical live Auth, REST and Function endpoint. For a tenant, verify
`BACKEND_ACTIVATION_PHASE=canonical` in its `automation/project.conf` and read
its current `WEB_LINK/backend-activation.json` before investigating live data.
The document must match the tenant ID and canonical generation. Verify the
configured `BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID` and, when present,
`FORCE_OCCASION_LINK` against the same canonical database before querying user
or event data. Stop and report a mismatch rather than searching another source.

`SUPABASE_URL` remains a compiled legacy fallback in transition mobile builds;
it does not identify the live database. `FESTAPP_SUPABASE_PROJECT_REF` in
`.env.local` also does not select the target; it may refer to a development or
legacy project. Credentials from that file may authenticate the management
interface only for a project they actually grant access to.

## Critical: Split Brain Logic

Functions code reloads must use
`automation/hetzner-supabase/runtime/restart-production-functions.py`, with the
email queue paused and drained before `--restart`. It preserves the existing
container and environment and rejects configuration drift. Never recreate
Functions with a partial `docker compose -f` list: that replaces `COMPOSE_FILE`
and caused a production email outage on 2026-10-27. Environment/image migrations
require a separate plan preserving every installed overlay, health checks and
rollback evidence. Resume email only after the worker probe succeeds, then
check `get_email_delivery_health()`.

Business logic is split between **SQL functions** (`database/functions/`) and Dart/JS. Before modifying any data flow, check if the logic lives in SQL.

- Search for `supabase.rpc('...')` in Dart/JS to find which SQL function handles the operation
- **In SQL**: Order creation, permissions, payments, ticket scanning, sign-ups, inventory
- **In Dart/JS**: UI, navigation, file operations (image upload/copy via `workers/image-worker/`)
- **Hybrid**: Occasion duplication/deletion - SQL copies DB rows; Dart uses the canonical image Worker for asset copies/deletion.

## Critical: Canonical Asset Authority

Festapp files and fonts use the shared image Worker and one public/private R2
bucket pair. Existing `a` URLs translate at that boundary; AKH retains its own
bucket and Auth/DB. Never introduce a new Supabase Storage producer or legacy
URL fallback. The 2026-10-18 production reference rewrite and scoped adapters are
active. Independent v2 recovery passed and local Storage/imgproxy and its
source volume are retired. All three redundant buckets and their dedicated
source-reader grants are retired; existing R2 URLs and AKH remain intact.
The measured 4 GB capacity decision remains explicit.
See `docs/operations/supabase-self-hosted/storage-authority.md` and its linked
execution receipt for the current deployment boundary.

## Critical: Post-Cutover Database Authority

Author database schema, function and data-contract changes as canonical
repository SQL and apply them to the self-hosted production target through the
approved release workflow. The former cloud sources are frozen retention or
reconciliation targets, not migration targets. Do not reopen cloud writes or
apply routine production migrations to them. A recovery or reconciliation
operation against a former source requires its own explicit plan and authority.

Key SQL directories: `eshop_orders/` (orders), `eshop_forms/` (form→order), `user_permissions/` (RBAC), `events/` (schedule), `inventory/` (capacity).

When production SSH is unavailable, use the reviewed
`automation/hetzner-supabase/runtime/access-sql.py` fallback through the
existing named-user Cloudflare Access login. It verifies the database identity
and SQL file digest before execution. See
[`admin-dashboard-security.md`](../operations/supabase-self-hosted/admin-dashboard-security.md#command-line-sql-fallback).

## Critical: Security Rules

All functions MUST be created in the `public` schema. Never create functions in other schemas.

Every `SECURITY DEFINER` function MUST:
1. Set `search_path = public, extensions` — always use explicit `eshop.tablename` for eshop schema tables, never rely on search_path to resolve them
2. Check the canonical typed operation predicate in `user_permissions/` before data access, mutations and receipt replay; bind resource scope from stored rows.
3. Use parameterized queries, never `EXECUTE` with raw strings

Operation predicates (`can_read_orders`, `can_create_occasion`, etc.) own authorization. Private immutable expression rules also serve the SQL capability projection. `get_is_*` helpers provide live role facts; new callers must not rebuild combinations of them. Dart/JS consume capabilities in the normal context response and fail closed after identity, role or context changes.

Occasion creation and setup finalization accept a unit editor or unit manager independently. Bank management is the explicit two-role exception: account admin AND manager of an actually linked non-demo unit. Linking a new account requires account admin AND manager of the target unit. Tenant admin is a distinct scope and does not substitute for either bank role. See the [bank matrix](../plans/canonical-authorization-BANK-2026-10-21.md).

This authorization migration and its inventory, contraction and performance gates are complete locally; production application remains a separate, unperformed step. See the [execution result](../plans/canonical-authorization-RESULT-2026-10-20.md) for evidence and deployment status.

## Critical: No Persistent Application Triggers

Do not implement application behavior with persistent PostgreSQL triggers.
Prefer explicit RPC/service boundaries whose callers and transaction semantics
are visible in code. A temporary operational trigger is allowed only when its
removal is part of the same release workflow and is verified immediately after
the replacement client or RPC is deployed. Never leave a compatibility merge
trigger behind after cutover. Narrow technical triggers that maintain purely
mechanical metadata such as `updated_at` or audit timestamps are allowed; they
must not encode domain decisions, permissions, patch semantics, or workflow
transitions.

## Critical: Canonical Main and Tenant Overlays

`main` is the only owner of shared application and release-tooling code.
Production branches contain only the source/data paths allowed by the policy at
their recorded main SHA plus deterministic outputs from `apply_config.sh`.
Read [tenant_overlays.md](tenant_overlays.md) before changing production branch
configuration or performing a branch cutover. Never load drift policy from the
production branch being checked.

## Data Hierarchy

Organization (tenant/domain) > Unit (real-world org) > Occasion (event instance). Features configured per Occasion. "Unit" is used because "Organization" was reserved for the domain level.

## Code Patterns

- **Upgraded UI contract**: Application, tests and the canonical vendored venue editor use `material_ui`/`cupertino_ui` together. `DependencyMaterialBridge` supplies SDK theme/localizations to external SDK Material widgets; flutter_colorpicker has the equivalent local boundary inside the shared editor. Use the standalone UI localization delegates in app/test MaterialApp roots.
- **Time ownership**: `festapp_core/time.dart` owns embedded `latest_all` timezone initialization and instant/wall conversion; `program.dart` re-exports the API. `TimeHelper` delegates to it. Keep legacy IANA aliases, saved settings, Prague fallback, UTC precision, 04:00 program boundaries, overnight grouping and DST gaps/overlaps. Tests must initialize through this owner instead of replacing its data with timezone's reduced default dataset.
- **Imported files**: `ImportFile` owns stable metadata and lazy/retained bytes. Await desktop_drop consumers and retain content before returning it from selection dialogs. Keep size preflight before byte reads; imports use copy. Picker and SDK compatibility patches live under versioned `packages/`; no machine-specific package override is needed.

- **FVM**: Always prefix flutter/dart commands with `fvm`
- **Error handling**: Prefer `ExceptionHandler.guard()` over try-catch in UI code
- **Admin modals**: Use `widgets/app_dialog.dart` (`AppAlertDialog`,
  `AppSimpleDialog`, or `AppDialog` for custom/fullscreen content), and
  `AppDialogHeader`/`AppDialogAppBar` for custom headers. The shared shell owns
  shape, rightmost close button and Escape focus. Pass the same `onClose` as
  Cancel and set `dismissible: false` while closing is blocked; preserve draft
  `PopScope` guards. `StandardDialog` is the compact content adapter. Native
  date/time pickers and public song/game views keep their specialized controls.
- **Localization**: `*_strings.dart` files with static getters (`CommonStrings.save`) not `"key".tr()`
- **Number display**: Group digits only from absolute 10000; smaller values have no grouping separator. Keep locale decimal/currency conventions and monetary precision. Dart uses `festapp_core/formatting.dart`; web and Edge Functions use `supabase/functions/_shared/numberFormatting.ts` (web re-export in `utils/formatters.js`). Exact server decimals use `formatExactDisplayNumber`. Stored values, identifiers and editable input formats remain canonical.
- **Date/time display**: Use locale-aware Intl skeletons (`DateFormat.yMd`, `jm`, `jms`, etc.) with the interface locale. `main` keeps `Intl.defaultLocale` in sync for context-free presentation helpers. Grid values stay canonical for sorting and editor/RPC round trips; localize their display with `LocaleDateTime` formatters. Explicit patterns belong only to stored/wire formats or internal picker controller values, never user-facing labels or tooltips.
- **Routing**: `auto_route`, `app_router.gr.dart` is generated — don't edit
- **Permissions**: Check `RightsService` before showing admin/editor UI
- **No `dart:io`** in shared UI code (breaks web). Exception: `map/` uses it for platform-specific offline maps
- **Config**: `automation/project.conf` → `apply_config.sh` propagates to all targets
- **Web client**: Page components extend `base/component.js` with `init()`/`render()`/`clear()` lifecycle; smaller widgets (dialogs, fabs) don't

## Blueprint draft text and persistence

Blueprint editors render draft labels locally using the loaded font. Renaming,
composition and switching editor modes must not generate canonical vectors or
save the plan. Native draft text preview does not grant geometry editing rights.
Explicit Save captures the draft, prepares its canonical text resources and then
persists that exact snapshot. Cancel restores the confirmed plan. Public viewers
and PDF rendering consume the saved canonical resources.

## Occasion feature configuration

`occasions.features` stores each event's feature array. `Feature.fromJson`
selects typed settings or `SimpleFeature`; `FeatureService` controls UI availability.
When adding a feature, register its code, parsing/defaults and UI/SQL behavior.
`appSupportedFeatures` lists only features restricted to `AppConfig.isAppSupported`;
form/ticket features also serve ticketing-only tenants. UI flags never replace
server authorization. Creation/save SQL remains authoritative for stored defaults
and validation.

## Directory Structure

- `lib/components/[feature]/` — Feature-oriented Flutter (views/, models/, sub-features)
- `lib/data_services/` — DB interaction. Key singletons: `RightsService` (context + permissions), `OfflineDataService` (cache), `SynchroService` (sync)
- `database/functions/` — SQL functions organized by domain. `database/tests/` for SQL tests (auto-rollback)
- `supabase/functions/` — Deno Edge Functions (email, tickets, payments). See `docs/backend/edge_functions.md`
- `web_client/src/` — Vanilla JS (Vite). Components + services (supabase, router, auth, theme, i18n)
- `workers/image-worker/` — Authenticated image control plane for public/private R2 objects; public bytes use the configured image host
- `workers/sync-worker/` and `workers/sync-publisher/` — Client Sync v1 delivery and immutable artifact publication
- `automation/hetzner-supabase/` — Self-hosted Supabase infrastructure, merge, rehearsal and operational tooling
- `automation/` — `project.conf` (single source of truth), `apply_config.sh`, `test_all.sh`
- `automation/image-migration/` — One-time migration scripts (Supabase Storage → R2). See `automation/image-migration/README.md`

## Feature READMEs (Complex Components Only)

Keep a feature README when it explains a cross-layer contract, ownership or
failure mode that is hard to infer from one file. File/class inventories, getter
lists and change-by-change release notes belong in source, generated references
or dated operational records. Shared concepts have one owner; other clients link
to it and document only their own adapter differences.

These components have such local contracts:

- **[Eshop](../../lib/components/eshop/README.md)**: Orders, payments, Split Brain SQL
- **[Blueprint](../../lib/components/blueprint/README.md)**: Seat reservation with SQL locking
- **[Forms](../../lib/components/forms/README.md)**: Server availability, editor drafts and capability-scoped orders
- **[Schedule](../../lib/components/schedule/README.md)**: Sign-ups with SQL error codes, offline sync
- **[Users](../../lib/components/users/README.md)**: Bundle re-stitching, multi-tenancy
- **[Inventory](../../lib/components/inventory/README.md)**: Pool/Resource/Context hierarchy
- **[Activities](../../lib/components/activities/README.md)**: Draft & Publish with version history
- **[Email Templates](../../lib/components/email_templates/README.md)**: 3-level inheritance
- **[Bank Accounts](../../lib/components/bank_accounts/README.md)**: Dual-layer auth, eshop schema

- **[Tab deep links](tab_deep_links.md)**: AutoRoute ownership, retained admin tabs, object identities, access boundaries and calendar/panel query state.

## Critical: Universal outbound email gate

Every outbound application email, whether automatic or manually requested, must enqueue through `public.email_messages`. This includes registration, sign-in, password reset, GoTrue Auth hooks, orders/tickets, custom messages and account deletion. Only `process-email-queue` owns provider credentials and sends. Security priorities do not bypass global quota, rate, pause, suppression or send fencing. Producers wake the same worker after their SQL commit; cron is recovery. Never send directly from a bank webhook or another producer, and do not add a parallel queue.

## BankSync consumer boundary

BankSync is a shared bank-fact service for independent clients, including Festapp and Mendelio. Festapp's explicit v2 consumer uses `bank-sync-webhook` and `public.ingest_bank_sync_transaction`; raw HMAC authentication precedes the atomic inbox/identity/ledger/existing-matcher/receipt commit. Original bank references and signed amounts remain facts. Payment matching, account aliases, orders and ticket delivery belong to Festapp.

Canonical SQL is in `database/functions/eshop_bank_sync/`; regenerate its scoped migration with `automation/assemble-bank-sync-migration.py`. Activation adopts historical movement identities under an account lock. Legacy bank import/token/email RPCs and the separate polling worker are retired by the guarded full-cutover migration; suspension never reinstates them. No persistent application triggers or second payment engine are introduced.

BankAccountAdmin control uses `bank-sync-manage` with durable, fenced operation intents; encrypted token recovery uses `bank-sync-reconcile` and versioned protected control keys. Paid ticket intent creation is atomic with the SQL paid transition and immediately wakes the globally gated queue. Failed transition receipts abort payment recalculation, keeping the bank webhook retryable. See [implementation and production gates](../operations/banksync/IMPLEMENTATION-2026-10-04.md). See the [full cutover runbook](../operations/banksync/FULL-CUTOVER-2026-10-04.md) for the ordered account rollout and retirement proof. Unproven bank email identities remain quarantined observations until the required real-email evidence is established.

## Form capacity and waitlist ownership

`eshop.tickets` is the sole entity for an individual admission or waiting item.
Capacity counts DISTINCT eligible tickets through existing order_product_ticket
relationships; do not introduce a person ledger, shadow lifecycle or historical
ticket backfill. Waiting tickets have no valid admission symbol, products or finance.
Offers bind directly to ticket IDs, and acceptance reuses those IDs through the
existing order finalizer. Offer status is derived from offer slots, not mirrored
into an independent person state.

## Public links

`database/functions/public_links/` owns globally unique form/occasion slug
reservations (separate namespaces), cryptographic allocation and copy titles.
`forms.link`/`occasions.link` remain canonical. Historical reservations point
directly to IDs and survive deletion as tombstones. All writers use the same
transactional allocator, never an application trigger; direct table writes are
revoked. Existing readers resolve IDs before applying their existing access
checks. Clients replace only resolved slugs and copy only saved public URLs.

Existing cross-tenant occasion duplicates keep frozen tenant-scoped ID bindings.
New writes cannot claim those slugs; canonical links and titles are never bulk renamed.

## Payment-reference ownership

Festapp owns VS allocation and reservation under `database/functions/eshop_payment_references/`.
Activated organizations reserve against a canonical receiving-account namespace in
same-transaction checkout SQL; BankSync is not a reservation or invoice dependency.
The registry retains committed symbols after cancellation/deletion, with form
watermarks and private exact/sequence/random allocation. Unactivated organizations
retain the guarded legacy allocator until separately authorized activation. The
preexisting BankSync issuance API is retired in source; its historical registry
is retained for audit/backup. See [local cutover and operational gates](../operations/banksync/FESTAPP-PAYMENT-REFERENCES-2026-10-18.md).

## Platform service fees

`database/functions/service_fees/` owns evidenced organizer contracts, customer
acquisition, actual settled Festapp fee imports and exact allocations. These
platform-income facts are separate from buyer payments and organizer invoices in
`eshop`. No percentage default or inferred income from ticket totals. Wix reporting
uses the sole existing USD projection and a separate delivery-only journal with
unknown-outcome reconciliation. Source and dispatch are implemented locally,
not deployed or activated; no actual accounting feed is connected. See
[service fee architecture](service-fees.md).

## Native offline maps

MapLibre is the only native offline renderer. `OfflineMapConfiguration` accepts
`offlineMapBundleManifestURL` and `forceOfflineMap`; `OfflineMapBundleManager`
verifies the assets before `MapLibreStyleAssembler` creates a local style.
CSM Ostrava's schema 2 MBTiles and schema 3 PMTiles bundles remain supported.
Schema 2 retains its existing `mbtiles` asset role and absent/null
`bundle_mode`; this format does not select an old renderer. Online and web maps use
`RasterMapSurface` with network tiles.
There is no standalone package/style URL downloader or renderer rollback flag.
See [offline map tooling](../../automation/offline-map/README.md).
