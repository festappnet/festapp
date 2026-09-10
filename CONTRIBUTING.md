# Contributing to Festapp

> **Single Source of Truth** for workflows, testing, and committing.

## 0. Developer Setup (First Time)

Follow [docs/setup/local_development.md](docs/setup/local_development.md) for
the supported Flutter/FVM and isolated database setup. Project-specific agent
rules are tracked in `AGENTS.md`, `CLAUDE.md`, and
`docs/architecture/ai_context.md`; no third-party skill repository is required.

## 1. Testing Workflow

### A. The "One-Click" Way (Recommended)

Runs all project tests: Web Client (JavaScript), Database (SQL), Flutter,
Deno Edge Functions, and Integration tests.

```bash
./automation/test_all.sh
```

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
during a test is undone automatically.

### C. Troubleshooting

If a test fails saying "function does not exist":

1. Rebuild the isolated local database: `./automation/bootstrap_local_db.sh`.
2. Check that every active migration has a unique 14-digit timestamp.
3. Run schema check tests if available.

### D. Remote database and Edge Function changes

Do not use a remote database as a substitute for the isolated test database.
Version every SQL change in the repository and deploy it through the approved
release workflow. Until the self-hosted cutover is complete, schema, function,
and data-contract changes must remain semantically identical on the self-hosted
target and cloud sources `default` and `a`.

Resolve the live target from `SUPABASE_URL` in `automation/project.conf`, then
verify `FORCE_OCCASION_LINK` in that same database. Never select a target from
the project ref in `.env.local`. Deploy Deno functions from their checked-in
`supabase/functions/<name>/` source and follow
[docs/backend/edge_functions.md](docs/backend/edge_functions.md).

## 2. Secrets & Configuration

- **Local**: Keys in `.env.local` (NOT committed). This file is automatically
  loaded by local scripts and Vite. **Put all secrets here.**
- **Web Client**: Public keys in `web_client/src/app_config.js`.
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

Run the full test suite (Web, DB, Integration, and Edge Functions).

```bash
./automation/test_all.sh
```

> All tests must PASS.

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
npm install
npm run dev    # Vite dev server
npm test       # Node.js native test runner
```

### Component Pattern

All components extend a base class (`src/components/base/component.js`) with a
standard lifecycle:

- `init()` - Initialize state and fetch data
- `render()` - Build DOM elements
- `clear()` - Cleanup listeners and DOM

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

# Deploy
supabase functions deploy <function-name>
```

### Shared Utilities

Common code lives in `supabase/functions/_shared/`:

- `supabaseUtil.ts` - Admin client, template fetching
- `emailClient.ts` - Email sending (SMTP via nodemailer)
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
