# AI Context — Festapp

Festapp is an event management platform: Flutter (mobile+web) + Supabase (PostgreSQL, Edge Functions, Auth) + vanilla JS web client for public forms/eshop.

## Critical: Resolve the Live Supabase Target from Activation

Since the 2026-09-10 production activation, `https://api.festapp.net` is the
canonical live Auth, REST, Storage and Function endpoint. For a tenant, verify
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

Business logic is split between **SQL functions** (`database/functions/`) and Dart/JS. Before modifying any data flow, check if the logic lives in SQL.

- Search for `supabase.rpc('...')` in Dart/JS to find which SQL function handles the operation
- **In SQL**: Order creation, permissions, payments, ticket scanning, sign-ups, inventory
- **In Dart/JS**: UI, navigation, file operations (image upload/copy via `workers/image-worker/`)
- **Hybrid**: Occasion duplication/deletion — SQL copies DB rows, Dart copies images from Storage

## Critical: Post-Cutover Database Authority

Author database schema, function and data-contract changes as canonical
repository SQL and apply them to the self-hosted production target through the
approved release workflow. The former cloud sources are frozen retention or
reconciliation targets, not migration targets. Do not reopen cloud writes or
apply routine production migrations to them. A recovery or reconciliation
operation against a former source requires its own explicit plan and authority.

Key SQL directories: `eshop_orders/` (orders), `eshop_forms/` (form→order), `user_permissions/` (RBAC), `events/` (schedule), `inventory/` (capacity).

## Critical: Security Rules

All functions MUST be created in the `public` schema. Never create functions in other schemas.

Every `SECURITY DEFINER` function MUST:
1. Set `search_path = public, extensions` — always use explicit `eshop.tablename` for eshop schema tables, never rely on search_path to resolve them
2. Check permissions explicitly (`check_is_editor_order_on_occasion`, `check_is_manager_on_unit`, etc.)
3. Use parameterized queries, never `EXECUTE` with raw strings

Permission patterns: `check_is_*` raises exception (for writes), `get_is_*` returns boolean (for reads).

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

- **FVM**: Always prefix flutter/dart commands with `fvm`
- **Error handling**: Prefer `ExceptionHandler.guard()` over try-catch in UI code
- **Localization**: `*_strings.dart` files with static getters (`CommonStrings.save`) not `"key".tr()`
- **Routing**: `auto_route`, `app_router.gr.dart` is generated — don't edit
- **Permissions**: Check `RightsService` before showing admin/editor UI
- **No `dart:io`** in shared UI code (breaks web). Exception: `map/` uses it for platform-specific offline maps
- **Config**: `automation/project.conf` → `apply_config.sh` propagates to all targets
- **Web client**: Page components extend `base/component.js` with `init()`/`render()`/`clear()` lifecycle; smaller widgets (dialogs, fabs) don't

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

These components have non-obvious architecture worth reading before modifying:

- **[Eshop](../../lib/components/eshop/README.md)**: Orders, payments, Split Brain SQL
- **[Blueprint](../../lib/components/blueprint/README.md)**: Seat reservation with SQL locking
- **[Forms](../../lib/components/forms/README.md)**: Dynamic form engine, massive data bundles
- **[Schedule](../../lib/components/schedule/README.md)**: Sign-ups with SQL error codes, offline sync
- **[Users](../../lib/components/users/README.md)**: Bundle re-stitching, multi-tenancy
- **[Inventory](../../lib/components/inventory/README.md)**: Pool/Resource/Context hierarchy
- **[Activities](../../lib/components/activities/README.md)**: Draft & Publish with version history
- **[Email Templates](../../lib/components/email_templates/README.md)**: 3-level inheritance
- **[Bank Accounts](../../lib/components/bank_accounts/README.md)**: Dual-layer auth, eshop schema
