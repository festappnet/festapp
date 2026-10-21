# Contributing to Festapp

> **Single Source of Truth** for workflows, testing, and committing.

## 0. Developer Setup (First Time)

Follow [docs/setup/local_development.md](docs/setup/local_development.md) for
the supported Flutter/FVM and isolated database setup. Project-specific agent
rules are tracked in `AGENTS.md`, `CLAUDE.md`, and
`docs/architecture/ai_context.md`; no third-party skill repository is required.

## 1. Testing Workflow

### A. Broad test wrapper

Selects the repository's Web Client, SQL, client, Deno, image integration and
explicit automation lanes. Install their dependencies and choose a disposable
local database before running it. The wrapper loads `.env.local`; an existing
`DATABASE_URL` there takes precedence over automatic local-DB detection unless
you supply an explicit shell override.

```bash
DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' \
  ./automation/test_all.sh
```

Public form startup has a real Chromium gate in `automation/test_web_startup.sh`
and every web release build. Install its pinned runner with
`pnpm add --global agent-browser@0.33.1 && agent-browser install`.
`pnpm --dir web_client run test:form-access-browser` exercises the real HTML,
Main startup, unbranded form routing, catalogue login/Google handoff and editor/visitor access
for open and closed forms. Backend transport and the final provider/admin
handoffs are simulated; element visibility is checked in the browser.

The Google broker also runs against actual SQL in the seat-checkout CI job.
To reproduce it against a bootstrapped disposable local database, run:

```bash
GOOGLE_AUTH_DATABASE_URL="$DATABASE_URL" deno test --allow-env --allow-net --allow-read --allow-run=psql supabase/functions/_shared/googleAuthFlow_test.ts
```

This mode rejects remote/unmarked databases and rolls back admission counters.

The database must already be running; this command does not start it. Every
selected lane reports PASS, FAIL or INCOMPLETE with monotonic elapsed time.
Missing required tools, credentials or files make the run incomplete and nonzero.
Failures do not prevent later selected lanes from running. Established optional
skips inside individual tests retain their own test-runner semantics.
A JSON summary is written under `FESTAPP_ALL_RESULTS` (a fresh temporary directory
by default). The web lane retains its 60-second timeout and executes `pnpm test`;
timeout and interruption terminate the owned process group, including descendants.
Use pnpm 11.24.0 for JavaScript packages; install with
`pnpm install --frozen-lockfile` in the package directory.

Scopes are `web`, `db`, `flutter`, `integration` and `automation`. Both `db` and
`integration` also run the Deno lane. `automation` uses `automation/test_all_commands.json` as its explicit
command list; it does not discover every test in that directory.

### B. Running Only Database Tests

Use when modifying SQL functions or migrations.

```bash
# Rebuild the isolated local DB from the schema baseline (destructive only to
# the dedicated festapp-db-tests-pg15 Docker volume).
./automation/bootstrap_local_db.sh

# Run all DB tests
DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' \
  node web_client/scripts/run_db_tests.js

# Run specific test file
DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' \
  node web_client/scripts/run_db_tests.js database/tests/path/to/test.sql
```

**Key concept:** Tests run in a transaction and auto-rollback. Any data inserted
during a test is undone automatically. The SQL runner exits nonzero when files
still fail after its sequential retry; it also exits zero when the filter selects
no files. Check the selected count and summary as well as the exit status. This
is separate from the broad wrapper's warning-only web/integration lanes.

The payment-reference concurrency/restore test uses a separate disposable
PostgreSQL template via `PAYMENT_REFERENCE_DATABASE_URL`. The template must
contain the current schema and bootstrap disposable marker, use a dedicated
`festapp_*_template` database name, and have no active clients while it is cloned.
Its local admin connection must be able to fence fixture extension workers. It is separate
from `DATABASE_URL`, so concurrent web tests cannot block its database copy.

### C. Client tests

```bash
./automation/test_client.sh              # Complete Dart + Flutter client suite
./automation/test_client.sh core         # Partial: portable package only
./automation/test_client.sh flutter      # Partial: Flutter lane only
(cd packages/festapp_core && fvm dart test test/sync) # One core area
fvm dart test test_dart                  # Dart/VM adapters and SDK contracts, no engine
fvm flutter test --concurrency=1 test/sessions/shared_czech_test.dart # One environment group
fvm flutter test test/components/forms/default_values_cases.dart # One suite
```

Resolve dependencies with `fvm flutter pub get` in the repository and
`fvm dart pub get` in `packages/festapp_core` before running the client runner.
The complete command runs the architecture check, core and native Dart adapters
together, then Flutter, each exactly once. It checks semantic discovery against
the migration inventory and propagates every
failure. It works from any working directory and needs no backend credentials.
Separate JSON results and lane timings are saved in a temporary directory; set
`FESTAPP_CLIENT_RESULTS` to select an artifact directory. Dependencies are not
resolved during measured test runs. `fvm flutter test` alone covers only the
Flutter lane. Pure rules belong in the core package; application composition
chooses their storage, network and platform adapters explicitly.

The client runner uses one worker per lane. `FESTAPP_CLIENT_CONCURRENCY=1`
is accepted; other positive values are rejected under the workstation policy.
Run only one Flutter task across the workstation at a time.
Small compatible suites share an engine through `registerClientSuites`; verify
both normal and `FESTAPP_FIXTURE_ORDER=reverse` group orders when changing them.

Small suites in the same feature share a `<feature>_unit_test.dart` or
`<feature>_widget_test.dart` entrypoint to avoid starting a Flutter engine for
each file. Their original
tests live in `*_cases.dart` files, each with its own `main()`, registered under
a named `group` in the entrypoint. Flutter discovers only the entrypoint during
a directory run; explicitly naming a cases file still runs that suite directly.

Add new tests as `*_test.dart` by default. Use `*_cases.dart` only when importing
and registering it in the feature entrypoint. Group related widget suites only
when their setup and teardown can safely share one engine. Keep tests that
replace platform singletons, use custom bindings, or leave process state behind
in separate `*_test.dart` files. Shared suites must use local instances or
restore any state they change; setup and teardown hooks belong inside their
named group. Initialization that mutates shared state belongs in scoped hooks,
not in the suite's `main()`.

The exact remaining Flutter roots and reasons are listed in
`automation/client_test_classification.json`; the architecture guard rejects
missing/stale classifications, registration-time resource setup and private
SDK fixture imports. Localized suites use the public widget/delegate fixture. Explicit
physical-source moves and added parent groups preserve semantic test origins.
Fixture contracts live in `test/support/fixtures/README.md`.

For a comparable measurement after implementation is final:

```bash
python3 automation/benchmark_client.py --output /tmp/festapp-client-benchmark
```

This runs the complete command once to warm it and three times for the median,
checks source/lock/tool inputs before and after every run, and records each
lane, counts, SDK/host and sampled owned-process RSS. It fails on test/inventory
errors or changed inputs; unmet performance targets remain explicit in JSON.
The pre-existing loopback-only GoTrue SDK test is in `test_dart/integration`;
it retains its explicit skip without its `FESTAPP_FIXTURE_*` environment.

`test_client.sh` already passes `--no-pub` to its Flutter lane and does not
accept that flag itself. When running `fvm flutter test` directly, add
`--no-pub` only after resolving dependencies.

### D. Troubleshooting

If a test fails saying "function does not exist":

1. Verify the runner is using the dedicated local database. If its schema is
   stale, rebuild it with `./automation/bootstrap_local_db.sh`; this deletes
   that fixture's data.
2. Check that every active migration has a unique 14-digit timestamp.
3. Run schema check tests if available.

### E. Remote database and Edge Function changes

Do not use a remote database as a substitute for the isolated test database.
Version every SQL change in the repository and deploy it through the approved
release workflow to the canonical self-hosted backend at `https://api.festapp.net`.
The production switch completed on 2026-09-10. Former cloud sources are frozen
retention/reconciliation targets; routine changes must not reopen their writes.

For a production tenant, require `BACKEND_ACTIVATION_PHASE=canonical` in
its `automation/project.conf` and verify the published
`WEB_LINK/backend-activation.json`: tenant ID, canonical generation and endpoint
must match the selected configuration. Verify
`BACKEND_ACTIVATION_CANONICAL_ORGANIZATION_ID` and any `FORCE_OCCASION_LINK`
in that same canonical database before reading event or user data. Stop on a
mismatch. `SUPABASE_URL` can be a compiled legacy mobile fallback; neither it
nor a project ref in `.env.local` selects the live database. The shared main
configuration is a development template, not evidence of a tenant's activation.

Deploy Deno functions from their checked-in
`supabase/functions/<name>/` source and follow
[docs/backend/edge_functions.md](docs/backend/edge_functions.md).

## 2. Secrets & Configuration

- **Local**: Ignored `.env.local` holds private local inputs for scripts that
  explicitly load them. Follow service-specific secret paths and production
  private-input schemas; never expose private values through Vite/client assets.
- **Web Client**: Generated public settings in `web_client/src/app_config.js`,
  sourced from `automation/project.conf`; no service-role or provider credentials.
- **Database**: `DATABASE_URL` required for test runner.

## 3. Security Audit (Before Commit)

**CRITICAL**: Every time you write a new PostgreSQL function (RPC), especially
with `SECURITY DEFINER`, you MUST verify:

1. **Search Path**: Use `SET search_path = public, extensions`. Qualify every
   `eshop` object explicitly (for example `eshop.orders`); never add `eshop` to
   the search path.
   - _Why?_ Prevents search_path hijacking where malicious users create objects
     in public schema.
2. **Permissions Check**: If the function modifies data or returns sensitive
   info, it MUST check permissions.
   - Example: `PERFORM public.check_is_admin_for_bank_account(p_account_id);`
   - _Why?_ `SECURITY DEFINER` runs with superuser-like (or owner) privileges,
     bypassing RLS. explicit checks are mandatory.
3. **Input sanitization**: Avoid `EXECUTE` with raw strings. Use `format()` or
   parameter binding.

## 4. Commit Workflow

Shared application, SQL, Edge, worker, test and generic automation changes are
made on a branch from `main`. A `prod/*` change may contain only an approved
tenant overlay path and must record the main SHA it overlays. Before proposing a
production-branch commit, run the checker extracted from that recorded main SHA
as documented in `docs/architecture/tenant_overlays.md`.

Tenant releases are sequential. Push exactly one `prod/*` release, then run the
canonical `automation/deploy_direct.sh` path or explicitly dispatch the GitHub
`Deploy` workflow for that exact branch. Wait for deployment to finish and
complete the public production smoke test before preparing or pushing the next
tenant release. A push alone never starts a production build. Do not batch,
queue, or run several Flutter tenant builds in parallel unless the user
explicitly asks for that specific release batch.

Follow this checklist **before** every commit:

### Step 1: Configuration Check

Ensure your local configuration is applied to the code:

```bash
./automation/apply_config.sh
```

### Step 2: Cleanup and Hygiene

Ensure the codebase is clean:

- **Remove Temporary Files**: `rm database/tests/temp_*.sql`,
  `rm web_client/scripts/temp_*.js`, `rm analysis.txt test_results.txt`.
- **Remove Dead Code**: Delete unused files/comments.
- **Remove Debug Logs**: No `console.log` in production code.

### Step 2.5: Dealing with Complex Refactors (Checklist Strategy)

If you are dealing with a complex issue (e.g., data leaks, wide-spread API
changes):

1. **Search**: Use `rg` and `rg --files` to identify all affected files.
   - Example: `rg -l "CREATE OR REPLACE FUNCTION" database/tests`
2. **List**: Create a checklist in `task.md` or a temporary artifact.
3. **Execute**: systematically go through each file in the list.
4. **Mark and Verify**: Check off each item as you fix it. Verify after each
   batch.

### Step 3: Verify Integrity

Run checks appropriate to the change and required by repository/user
verification scope. For a full validation, run the broad wrapper with explicit
local database configuration and inspect every lane as described above.

```bash
./automation/test_all.sh
```

> A skipped or warning-only failed lane is not a passing full validation.

### Step 4: Synchronize Translations

If you modified `en.json` or `cs.json`:

1. **Unify** (Flutter <-> Web):
   ```bash
   node web_client/scripts/unify_translations.js
   ```
2. **Reorder** (CS structure matches EN):
   ```bash
   node web_client/scripts/reorder_cs_like_en.js
   ```

### Step 5: Stage and Commit

Review status, stage, and commit.

Stage only the files belonging to the change. Agents follow `AGENTS.md` and the
user's explicit commit and publication scope.

```bash
git status
git add path/to/changed-files
git commit -m "feat: description of changes"
```

## 5. Web Client Development

The `web_client/` directory contains a standalone vanilla JavaScript application
for public-facing features (forms, blueprints, e-shop). It is separate from the
Flutter app but shares the same Supabase backend.

### Setup

```bash
cd web_client
pnpm install
pnpm run dev    # Vite dev server
pnpm test       # Node.js native test runner
```

### Component Pattern

Page components extend a base class (`src/components/base/component.js`) with a
standard lifecycle:

- `init()` - Initialize state and fetch data
- `render()` - Build DOM elements
- `clear()` - Cleanup listeners and DOM

Small widgets such as dialogs and floating action buttons need not inherit
this page lifecycle.

### Key Directories

- `src/components/` - UI components (forms, blueprint, eshop, feedback, etc.)
- `src/services/` - Singleton services (supabase, router, auth, theme, localization, rights, seo, time)
- `scripts/` - Build tools (version sync, DB test runner, translation scripts)
- `tests/` - Test files organized by area (components, core, forms, logic, issues)

### Relationship to Flutter App

- Both apps share the same Supabase backend (same PostgreSQL functions/RPC)
- Configuration is shared via `automation/project.conf` (propagated by
  `apply_config.sh` to both `lib/app_config.dart` and
  `web_client/src/app_config.js`)
- Translation keys should be kept in sync using `unify_translations.js`

## 6. Edge Function Development

Edge Functions live in `supabase/functions/` and are written in TypeScript for
the Deno runtime.

### Local Development

```bash
# Serve locally
supabase functions serve <function-name> --env-file .env.local

```

Production deployment uses the canonical reviewed Function bundle, not the
cloud CLI deploy command. Follow [Edge deployment](docs/backend/edge_functions.md#deployment).

### Shared Utilities

Common code lives in `supabase/functions/_shared/`:

- `supabaseUtil.ts` - Admin client, template fetching
- `emailQueueClient.ts` / `emailDelivery.ts` - Render and encrypt snapshots,
  enqueue durable intents, and optionally await provider acceptance
- `emailSender.ts` - SES transport used only by `process-email-queue` after the
  canonical SQL send gate grants its fenced permit
- `auth.ts` - Request authorization (`authorizeRequest`)
- `utilities.ts` - General helpers

### Testing

Edge Functions are tested as part of the full test suite
(`./automation/test_all.sh`). For manual testing, use `curl` or the Supabase
Dashboard.

## 7. Code Review Checklist

Before submitting code for review, verify:

### Dart / Flutter

- [ ] No `print()` statements in production code (use proper logging)
- [ ] No hardcoded strings in UI (use `*_strings.dart` localization pattern)
- [ ] `ExceptionHandler.guard()` used instead of raw `try-catch` in UI code
- [ ] `RightsService` checked before displaying admin/editor features
- [ ] No `dart:io` imports in shared UI code (breaks web)

### SQL / PostgreSQL

- [ ] `SECURITY DEFINER` functions have `SET search_path = public, ...`
- [ ] Permission checks present (e.g., `check_is_editor_order_on_occasion`, `check_is_manager_on_unit`)
- [ ] No `EXECUTE` with raw string concatenation (use `format()`)
- [ ] Function follows `verb_noun` naming convention
- [ ] Corresponding test in `database/tests/`

### Web Client

- [ ] No `console.log` in production code
- [ ] Event listeners cleaned up in `clear()` method
- [ ] Supabase calls use service layer (not direct client access)

### Edge Functions

- [ ] CORS headers present on all responses
- [ ] Auth check via `authorizeRequest()` for sensitive operations
- [ ] Error responses include proper HTTP status codes
- [ ] Shared code imported from `_shared/` (no duplication)
