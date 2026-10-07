# Canonical mutation G3 observation

The backend/database relocation is complete. All selected live tenants resolve
canonical generation 1 on `https://api.festapp.net`. Former cloud databases are
not queried or migrated by this work. G3 concerns released clients calling old
write contracts on this same self-hosted server.

Read-only discovery on 2026-10-07 found 11 enabled occasions, live tenant web
builds 617/618, and CSM Ostrava Android/iOS 0.20.14 plus older web/PWA generations
still bootstrapping today. The prepared CSM build 619 has not been deployed.
Retained gateway logs covering October 3-7 contain one successful
`delete_occasion_user_ws` request. These are observations, not an assertion that
those clients all have editor privileges. Bootstrap logs do not identify build
numbers. The active database has pgAudit installed but no effective write audit.

This additive change supplies measurement before a supported observation window:

- Flutter and JS identify version/build/platform in the already CORS-allowed
  `X-Client-Info: festapp/<version>+<build>/<platform>` header. Bootstrap platform
  metadata also gains buildNumber. Unavailable native package metadata cannot
  prevent initialization. This is self-reported compatibility metadata, never
  authorization or proof of a minimum write build.
- The invoker-only PostgREST hook logs bounded request fields, the server actor,
  role and a server-generated request ID. The existing group/domain locking seam
  adds the resolved occasion under that request ID. It does not modify clocks,
  receipts, locks, authorization, persistence or routing. The private scope helper
  has no client/service EXECUTE grant. No new persistent application trigger.
- The separately activated operational SQL enables pgAudit write/relation records
  with statement text off and requires parameter logging already off. The local
  Supabase postgres role cannot SET log_parameter; the operation deliberately
  checks/preserves the off setting instead of granting elevated authority.
  An existing pre-request hook causes a rollback, rather than being replaced.
- `summarize_mutation_observation.mjs` exports only bounded fields and actor hashes.
  It discards raw request headers/bodies, JWTs, SQL/parameters and URI query strings.
  Its output always says measurementOnly/G3-unsatisfied. Audit presence and zero
  counted traffic cannot establish complete coverage or authorize contraction.

## Operational sequence

1. Merge this verified source onto authoritative main. Apply only migration
   `20261007150000_canonical_mutation_observation.sql` through the protected
   canonical target executor, with its migration ledger row in the same
   transaction. Do not apply the deferred active-registry migration.
2. Check the deployed request/scope/lock bodies against current main, preserve
   existing named pgaudit/pgrst settings for recovery, and verify there is no
   environment-configured pre-request hook. Never dump the full runtime .env,
   Docker environment, pg_db_role_setting or arbitrary app.settings values.
3. Review/apply `database/operations/canonical_mutation_observation.sql` through
   the same identity/organization/occasion checks. Confirm effective settings in
   a new authenticator connection; an existing PostgREST pool may retain its login
   settings. Reloading config alone does not prove pgAudit is active.
4. Use the existing encrypted hourly runtime-log archive (70-minute overlap,
   30-day retention). Aggregate inside the protected host/archive pipeline; do
   not export raw gateway/Postgres logs. Record actual archive interval coverage,
   correlate request IDs and process IDs with domain scopes/audit, and classify
   unattributed service, direct-history and SQL writes explicitly. Run the CLI
   over the retained input: `node automation/client-sync/summarize_mutation_observation.mjs`.
5. Record the supported editor-release/minimum-build and offline/idle/scheduled
   writer policy for every consumer of this shared ACL boundary. Establish a
   technically enforced editor-write fence, including direct history DML and
   nine legacy RPCs; informational update prompts and version headers alone do
   not provide it. Declare the observation interval before starting it.
6. Prepare a CSM overlay from that main with a fresh version containing the
   request metadata. Release only CSM. Open canonical editors after the approved
   shared write restriction/upgrade and G3/G4 contraction, never concurrently
   with unversioned bypasses. The contraction validator remains unchanged.

This document does not authorize another tenant rollout, invent a supported
mobile/editor policy, set global registry readiness, or mark G3 satisfied.
No observation window has been declared on the basis of the one-hour JWT lifetime:
maximum supported offline return and scheduled integrations are still required.

## Validation

The disposable schema chain includes the new additive migration. The standard
full batch passed: 214 JS, 137 SQL suites, 1169 Flutter, 271 Deno and automation
checks; 9 web/1 Flutter/27 remote integration cases skipped by their normal gates.
Targeted checks after the CORS-safe header adjustment: SQL observation/source
parity, JS Supabase initialization/config, Flutter request headers, four Node
privacy/configuration tests, and the inventory checker. All 58 current SQL owners
are represented. Dart analysis has only two pre-existing main.dart diagnostics.
Production measurement activation and minimum-build enforcement are still pending;
the wizard and other tenant branches were not changed.
