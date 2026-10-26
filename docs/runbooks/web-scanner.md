# Web scanner

The scanner uses the existing web client and Supabase RPCs. Its server source is
`database/functions/scanning/`. The initial migration is immutable after release.
Generate the settings/editor follow-up with
`python3 automation/assemble-scanner-settings-migration.py`; do not edit generated SQL.
The migration also includes the retained native wrappers, scan-code rotation,
parent locks, occasion copy and the additive program companion projection.

## Operator workflow

1. Open `/scan/<code>` or `/scan?occasion=<id>` with an authorized signed-in account.
   The successful exchange removes the credential from the URL. Choose the event
   explicitly when changing devices or saved sessions.
2. Use the live camera; manual entry is available as a fallback. New codes keep
   being collected while tickets await confirmation. Confirm the displayed tickets; unpaid admission requires its explicit checkbox.
3. When the event permits it and its snapshot contains at most 1,000 tickets, a
   complete matching PWA shell prepares the offline cache automatically in the
   background. The count includes unpaid and stock tickets with order links, not
   just paid/used tickets. Larger events require initial manual preparation; an
   existing snapshot continues refreshing if the event grows. An unknown count
   never starts an automatic download. Manual preparation remains available. Readiness
   requires persistent storage, the matching complete PWA shell, the local decoder
   and an atomically verified snapshot. Check authorization expiry.
4. Pending means saved on this device. Accepted means a server receipt exists.
   Counts describe current tickets, with conditional unpaid and local pending
   separate. They never describe people currently inside a building.
5. Keep the app open to send the queue. Retry uses the original operation IDs.
   Review conflicts through History/Offline; an authorized editor can record a
   reason without changing the ticket or erasing the original event.
6. Locking preserves the outbox and removes the active guest snapshot. Reopening
   a different session never transfers pending operations to the new identity.
   Keep the original device available for reconciliation and supervisor review.

Do not clear browser data with unresolved records. A lost device or externally
cleared browser storage can lose unsent operations. There is no promise of sync
while the browser is closed. An expired grant blocks new offline admissions.
Clock rollback blocks offline admission until online verification.

Offline ticket payloads are encrypted with AES-GCM using a non-extractable
WebCrypto key. This reduces casual plaintext exposure in IndexedDB; a user with
control of the browser/device or same-origin script can still use the key. It
is not protection against a compromised device. Expiry/locking clear guest caches;
legacy plaintext caches are protected or discarded without dropping admissions.

Storage failure blocks confirmation even with working internet. Online lookup
remains available. Use another prepared device rather than treating an in-memory
record as saved. A missing offline ticket means unverified, not invalid.

Administration ticket settings and the scan-code dialog link to `/scan/settings`
with the current occasion ID. The web settings editor is the only administration
editor for manual search and hidden-note visibility; the former ticket-feature
checkbox panel is removed. The administration link opens a new tab so unsaved
ticket-layout drafts remain in place. Historical feature keys remain a retained
native-client and first-configuration seed boundary, not another web editor.

Shared settings require editor or reservation-editor permission on the same event.
One server configuration applies to every scanner; per-device field overrides are
not applied. A scan code never grants settings access. Products use
all/none/explicit selection; fields refer to their actual form and ticket/order
scope. Local visibility is a subset of the server projection. Draft CAS conflicts
can reload the saved revision and restore the unsaved draft.

Program checking is read-only and retains the existing participant permissions
and registered companions. Reception login stays on `/login-qr`, uses the existing
`exchange-login-qr`, validates the target organization and refuses to replace an
existing worker account or active scanner. Use a separate browser profile for
reception credentials. Password reset stays online under the existing scan reset
policy, including privileged-target restrictions and abuse limits.

## Local verification

Use a disposable local database with the complete current schema and ACLs.
Never infer isolation from `.env.local`. The two-connection/browser harness rejects
non-loopback hosts and database names outside `festapp_scanner_*`.

```sh
# Example only: use the port of your explicitly isolated local database.
export SCANNER_DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:59132/festapp_scanner_20261018?sslmode=disable'
DATABASE_URL="$SCANNER_DATABASE_URL" node web_client/scripts/run_db_tests.js database/tests/scanning
(cd web_client && node --test tests/scan/*.test.js)
SCANNER_DATABASE_URL="$SCANNER_DATABASE_URL" node web_client/scripts/scanner_integration_server.mjs
```

The scanner SQL runner loads its fixture helper in each test transaction. The
browser harness uses real RPC SQL through a loopback-only test adapter and real
IndexedDB. Its 10,000 tickets are fictional, created exclusively in the isolated
database. The adapter is never included in the application build. Node store tests
use fake-indexeddb; browser evidence covers the actual browser storage boundary.

The optional `build_scanner_browser_fixture.mjs` generates a standalone test shell
in `/tmp/festapp-scanner-pwa-20261018`, using fixture metadata captured from the
loopback harness in `/tmp/scanner-current-fixture.json`. It embeds fictional test
configuration, not production auth. Serve it through the harness's
`SCANNER_PWA_DIR` option to exercise the actual generated PWA worker. This is an
application integration test, not a general static preview server.

## Release and recovery

Production migration, publishing and tenant rollout require a separate task.
Select exactly one tenant. Verify canonical main/tenant ancestry, backup and DB
identity, apply the reviewed additive SQL, build locally and deploy through
`automation/deploy_direct.sh`. Do not dispatch the GitHub build workflow unless
explicitly requested. Delegate routine release execution according to AGENTS.md.

Before calling a release ready, test the physical camera on supported iOS/Safari
and Android/Chrome devices with several QR codes in one view. Test an outage,
reopening the prepared device, expiry and reconciliation at the expected event
size. Verify the new `/scan`, legacy/hash, program, settings, history, offline and
reception routes on the selected live tenant.

Rollback must retain IDB operations and server receipts. Never undo ticket states
to hide conflicts. Retain a compatible old shell while it has live queues; stop
new sessions/preparations if required. Receipts have no automatic deletion policy.
Expired server snapshots are cleaned on preparation after their retention window;
local snapshot data is cleaned after expiry plus 24 hours, never the outbox.

Evidence for this implementation is in
`docs/plans/web-scanner-implementation-2026-10-18.md`.
