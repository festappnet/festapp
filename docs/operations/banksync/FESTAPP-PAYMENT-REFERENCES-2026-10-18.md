# Festapp-owned references and BankSync issuance retirement

Local source only. No organization is selected, no deployment/import is authorized,
and no live registry or API usage inventory has been inspected.

## Ownership and deletion ledger

| Artifact | Result |
| --- | --- |
| BankSync reservation/admin HTTP endpoints | Retired with HTTP 410; old idempotency cache cannot intercept retirement. |
| BankSync allocator, grants/import/activation runtime and reference package exports | Removed. Generic receiving-account normalization remains for polling/health. |
| BankSync schema 0012 and existing registry data | Historical only, backed up and locked. Forward migration 0014 removes the registry's bank-account edit trigger; no obligations are erased. |
| BankSync VS/RF bank facts, v1 compatibility utilities, v2 signatures/import/delivery | Retained; no registry prerequisite, uniqueness rule or order matching added. |
| Festapp normal checkout, waitlist acceptance, atomic blueprint replacement | Existing finalizer reserves locally, in the order transaction, for activated scopes. |
| Festapp legacy allocator | Private, explicitly unactivated organizations only. Active/paused scopes cannot call it as fallback. |
| Identity-free creation and destructive preparation-only replacement RPCs | Rejected in active scopes. Receipted atomic replacement stays available. |
| Manual VS mutation/table writes | Old RPC and direct payment DML revoked; authenticated editor command reserves exact VS only on an unpublished null-reference draft. |
| Fakturoid CZK overwrite and email substitution | Removed. CZK/EUR use and validate Festapp's symbol. Ambiguous lookup is rejected. |
| Distributed reference attempts, HTTP adapter, recovery/rematch workers | Abandoned design removed. No reference API dependency remains in Festapp. |

Uniqueness applies within this Festapp database's enrolled physical accounts.
Independent applications/databases need a range agreement. Deleted historical
symbols without archives are not provably inventoried. Existing invoice uncertainty
and invoice-dependent replacement staging are separate work; this change does not
claim exactly-once external invoice creation.

## Prepare a selected organization

The commands deliberately refuse missing scope. They are preparation instructions,
not authorization to run them on production. Resolve the canonical backend activation
identity and obtain rollout authorization before any live SQL or deployment.

```sh
: "${FESTAPP_ORGANIZATION_ID:?Select one authorized organization}"
: "${DATABASE_URL:?Select its verified canonical database}"
: "${REFERENCE_INVENTORY_DIR:?Choose a new private artifact directory}"
node automation/payment-references/inventory.mjs \
  --organization-id "$FESTAPP_ORGANIZATION_ID" \
  --output-dir "$REFERENCE_INVENTORY_DIR"
```

The inventory is read-only and generates `manifest.json` plus review-only import
SQL when no live-row collision/invalid account exists. It covers all positive
payment rows sharing the selected physical identities, including aliases. Review
retained orders/invoices/archives for deleted obligations; merge approved archival
entries with stable sources before treating a manifest as complete. The generated
SQL never activates allocation. Record the final manifest digest and scope-owner
assessment of any missing historical evidence. Never manufacture uniqueness by
renumbering existing obligations.

All configured payable destination candidates must be enrolled. An unselected
organization sharing the physical account blocks activation until its owner
separately authorizes migration or freezes that writer. An unactivated writer subsequently pointing at a protected physical account is
blocked until its owner coordinates enrollment; it cannot bypass the namespace.
New aliases start in the same namespace; account recreation cannot recycle a committed reference.

## Authorized rollout sequence

1. Record exact Festapp/BankSync source revisions and the one selected tenant's
   main/production ancestry. This task has no new commits to name yet.
2. Verify external consumers before withdrawing BankSync's public capability.
   Local searches found no caller in Festapp or the available Mendelio sources;
   that is not proof of zero live/external usage. Obtain any required compatibility
   release approval; publish/deploy neither package nor worker implicitly.
3. Deploy the issuance-free BankSync runtime compatible with schema 13 and 14,
   verify bank import/health/delivery, take a restorable backup, then separately
   apply `0014_retire_payment_reference_allocator.sql`. Confirm registry locked,
   edit trigger absent, original bank facts unchanged and former endpoints 410.
   Use this compatible runtime as rollback; old schema-13-only runtime is unsafe
   after 0014. Do not drop historical tables under this rollout.
4. Install Festapp's dormant migration
   `20261018200000_festapp_payment_reference_reservations.sql` after its preceding
   migrations and release compatible command-identity clients before activation.
   No BankSync URL/key or worker scheduler is required for local reference allocation.
5. During an authorized scoped checkout freeze, drain existing form transactions,
   reconcile any pending invoices by their original identity, and execute the final
   reviewed imports/delta. Do not blindly repeat an uncertain invoice POST. Confirm
   no independent unregistered writer still issues VS on the receiving accounts.
6. Activate exactly the reviewed organization:

   ```sh
   : "${FESTAPP_ORGANIZATION_ID:?Required}"
   : "${REFERENCE_MANIFEST_SHA256:?Required reviewed final manifest}"
   psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 \
     -v organization_id="$FESTAPP_ORGANIZATION_ID" \
     -v manifest_sha256="$REFERENCE_MANIFEST_SHA256" <<'SQL'
   BEGIN;
   SET LOCAL request.jwt.claim.role='service_role';
   SELECT public.activate_payment_reference_scope(
     :'organization_id'::bigint, :'manifest_sha256', true);
   COMMIT;
   SQL
   ```

   The activation gate drains form writers, checks mappings, shared writers and
   current live-row import coverage. The final boolean is the operator's explicit
   historical review attestation, not a database proof of missing archives.
7. Verify one authorized isolated checkout/replay/cancellation, local reservation,
   EUR RF and configured invoice agreement. No real paid movement or email is
   authorized by this document. Delegate routine approved deployment/monitoring
   to the cheaper agent as required by AGENTS.md.

## Pause, backup and restore

After activation, pause the selected organization by setting its scope phase to
`paused` under an authorized operator transaction. Keep reservations and watermarks;
never roll back to independent local random generation. Repair forward.

The normal PostgreSQL `eshop` backup includes all six new tables, FK tombstones and
form/namespace watermarks. Test a restore against an isolated database. Before any
restored clone accepts writes, set namespace allocation disabled and scopes paused;
reconcile later committed references/invoices before reopening a disaster recovery
restore. A test clone must remain isolated from real providers and customers.

## Local verification

Tests use the dedicated disposable `festapp_local_references_v2` database on
127.0.0.1:55432, never production. The concurrency runner clones it to a new uniquely
named database and removes that clone after closing its connections.

```sh
python3 automation/assemble-payment-reference-migration.py --check \
  --output supabase/migrations/20261018200000_festapp_payment_reference_reservations.sql
DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:55432/festapp_local_references_v2 \
  node web_client/scripts/run_db_tests.js payment_reference_reservations_test.sql
DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:55432/festapp_local_references_v2 \
  node --test web_client/tests/database/payment_reference_concurrency.test.js
```

## Recorded implementation evidence

Source baselines: Festapp `eb23047248d59bf86345b9e0b79db4a988275231`
(on the existing `feat/occasion-setup-wizard-20261007` worktree, with its entry
changes preserved), BankSync `cd3c1f0ba2af7e0a4afd95e29e408fa6e0d909a1`
(on `main`). Publication is prepared on `feat/local-payment-references-20261018` against
current canonical main `8b1420ea1`. This document records local validation;
production activation remains a separate operation.

- BankSync: full release preparation passed 633 tests across 38 Vitest files, including schema
  13/14 Fio recovery, credential epochs, authenticated email recovery, bank facts,
  delivery, health, audit backup/restore and stale-cache endpoint retirement.
  `pnpm typecheck`, `pnpm build` and package export checks passed.
- Festapp: 8 passing SQL suites covering the local allocator plus existing
  checkout, EUR, pairing, deposits, overpayments and Fakturoid waitlist recovery.
- Real PostgreSQL runner: 12 contending connections, identical-source replay,
  rollback, in-place/split waitlist acceptance with stable ticket IDs, successful
  atomic replacement and cancellation rollback after failed replacement,
  read-only manifest generation, and pg_dump registry restore with identical
  parent data and preserved cursors. Its cloned database was removed afterward.
- Edge/client checks: 13 Deno tests (mocked invoice provider), 16 Node client tests
  and one Flutter concurrency/reopen/actor-binding test passed. Targeted Dart
  analysis reported no errors and one preexisting BuildContext-after-await info
  in `db_orders.dart`. After rebasing onto canonical main, 20 Node tests, 13 Deno
  tests, the real PostgreSQL concurrency/restore runner and the Flutter identity
  test passed again; the same preexisting analyzer info remains.
- The new migration matches its assembler. No reference HTTP adapter, reference
  recovery worker or scheduler remains in Festapp; no active reservation allocator
  remains in BankSync. The historical audit tables and HTTP 410 boundary are
  intentional retention, not an alternative allocation path.

Older client intents without actor/origin binding fail closed into existing
customer-access/support recovery. Do not erase those pending identities and
silently repurchase. Compatible clients and resolution of outstanding requests
are activation prerequisites. The new Flutter identity writes are transactional
and survive concurrent claims/reopening; waitlist capabilities/answers remain
in memory and never enter the new persistent identity store.

Remaining live gates: choose and authorize one tenant/organization; verify actual
external users of the withdrawn BankSync API; finalize source revisions/package
compatibility release; review complete historical manifests/archives and shared
writers; back up, deploy the compatible runtimes and apply their forward migrations;
then explicitly activate the reviewed Festapp scope. None has been executed here.
