# Order deletion email cleanup

Status: ACTIVE on the canonical production backend. Shared backend change; no frontend build required.

Production read-only diagnosis found message 2632 / order 6498 in occasion 1072585 (`Ples AKH 2026`, organization 3). The order was absent but its reminder remained pending for 2026-10-04 10:54:30 UTC. The existing send validator returned false, with zero attempts and no provider acceptance. The deployed deletion function did not cancel email intents. A local deletion regression reproduced the missing cancellation (expected four cancelled messages, found zero).

The canonical deletion function locks the order, checks its existing manager permission, then cancels all linked unsent intents (`pending`, `retry_wait`, `blocked`, `preparing`) in the same transaction. It clears preparation leases and closes preparing attempts with `order_deleted`. No email history is deleted, and sending/accepted/unknown evidence remains unchanged. The migration replaces the function and applies the same repair to already orphaned unsent order intents.

Validation: eight targeted email/storno SQL suites passed; the new regression covers authorization denial, transaction rollback, pending reminders and other unsent kinds, preparation fencing, retained provider history and unrelated orders. A disposable migration fixture confirms cancellation of four orphaned unsent states while preserving accepted/unknown and unlinked mail. Full `automation/test_all.sh` passed: 109 SQL files, 1056 Flutter tests (one skip), 240 Deno tests, web/automation checks and three worker integration tests (remote cases skipped without credentials). No production fixture, sending or capacity test ran.

Production preparation: protected full dump, validated catalog, hash and old function definition under `/var/lib/festapp-rehearsal-evidence/order-email-delete-cleanup-20261004`. Read-only inventory found one unsent orphan each in organizations 1, 3 and 7. The repair deliberately preserves provider evidence for these organizations and only cancels mail whose parent order no longer exists.

Cutover confirmation: the canonical container inventory contains the Supabase Edge runtime and no email gateway container, and the image inventory contains no gateway image. Queue preparation and sending remain in `process-email-queue`; this cleanup adds no worker, process or endpoint.


## Production evidence

Canonical main `35c97619ce1e40a377e5845eb4a714eb13b8003f` ([PR #279](https://github.com/festappnet/festapp/pull/279)) supplied the exact migration SQL. Its digest and ledger wrapper were verified on the asserted host/database after a fresh validated protected dump and a comparison proving that the previous function had not changed since backup. Migration `20261004103000` and its ledger were committed atomically and PostgREST notified.

Read-only verification confirmed message 2632 / order 6498 is now `cancelled` with `order_deleted`, and no orphaned unsent order intents remain. The three pre-existing orphaned intents in organizations 1, 3 and 7 were repaired; preparing attempt update affected zero rows. No provider sending/accepted/unknown state was modified. Evidence remains in the protected directory above. This backend fix is live for all shared consumers and requires no frontend build.
