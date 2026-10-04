# Prepared form editor release

Status: ACTIVE on vstupenky.online, version 0.20.87+571. User explicitly requested the remaining prepared changes, including form-box deletion, only on vstupenky.online.

Prepared changes were ported from the user's older dirty working branch into a clean worktree on current canonical main using three-way application. The user's working tree was not edited. Current main's canonical email enqueue paths and newer report were preserved; the older report draft and already released editor/navigation changes were not reapplied. Translation additions were merged by changed keys, preserving current report text.

Included: removal of saved unused form boxes/product groups/products through explicit deleted-ID payloads; disabled deletion controls with reasons for responses, order history, blueprint seats, inventory and shared references; transaction-time eligibility checks and form/product locks; older payloads that omit fields remain compatible. Product deletion also removes its default selection correctly. Products have short-title/maximum help and a narrower type column; the Users group column respects the user-groups feature. Existing ticket short-title rendering has new regression coverage.

The runtime migration updates get_form_for_edit, versioned update_form/create_ticket_order implementation bodies and update_order_responses while preserving the public command wrappers. It was regenerated from the merged canonical bodies, including canonical e-mail enqueue logic. No Edge Function or separate worker is added.

Validation: full test_all.sh passed (110 SQL files, 1060 Flutter tests with one skip, 242 Deno tests, web/automation checks and three worker integration tests; remote credential-dependent cases skipped). The form deletion SQL regression additionally uses real editor permissions, covering denied saves, late answers, historical data, blueprint/inventory/shared/order references, wrong-form IDs and older partial payloads. Changed-file analysis has no errors/warnings (existing informational diagnostics remain). A fresh protected production dump and old function definitions are staged under /var/lib/festapp-rehearsal-evidence/form-editor-safe-deletion-20261004. Production results follow below.


## Production evidence

Canonical main `f168a4461b87289c879e70525367284184ec71e9` ([PR #280](https://github.com/festappnet/festapp/pull/280)) supplied migration `20261004120000`. A fresh protected dump/catalog/hash and old function definitions preceded execution; source SQL and the atomic ledger wrapper were digest-verified and compared with unchanged live definitions before application. Four functions and the migration ledger were committed together, then PostgREST notified. Read-only verification confirmed deletion metadata and the new internal form implementation. Existing private internal function grants remain denied to anon/authenticated, and the public wrapper definitions were not replaced.

`prod/festapptickets` advanced from `ac3e6623d40c4fce4b01b83e8e0ada6f68a256de` to `e581ef7f3efabafa630fee7291de94155288b6b1`, base `f168a4461b87289c879e70525367284184ec71e9`, version `0.20.87+571`. The canonical tenant drift check passed; upstream main and production were fresh before publication. [Deployment 37194634598](https://github.com/festappnet/festapp/actions/runs/37194634598) succeeded with the live release gates. No other tenant frontend was pushed or built.

At `2026-10-04T10:19:23.650Z`, independent manifest/bundle fetch verified `0.20.87+571`, `main.dart.0.20.87-571.js`, explicit field/product deletion payloads and error handling, retained Orders email history and absent standalone Email route. Bundle SHA-256: `d725cf979c8b78bf188c3a87df90cea41a756bfc1ccf8b4c02894d1fa6891ad9`. The order-email cleanup is also live as separately documented.

## Requested user-table follow-up

After completing and verifying the prepared release, move the existing admin-only read-only email-history action immediately after `UserColumns.INVITED` (Invitation sent) in Users. No history/permissions/loading behavior changes. Rollout remains only vstupenky.online; live evidence will be recorded after the follow-up release.


The Users-column follow-up is ACTIVE as `0.20.88+572`, main `f951abb918183ce9b074a19d953d0653856653a4` (PR #281), production `cdca343627af664af05aaa90724ca834f90b9f59`. Deployment run `37195147320` succeeded. Independent live proof at `2026-10-04T10:29:21.376Z` verified bundle SHA-256 `1505361568adcf1f76cd45e543178905d363e440e33484e3caeb2a16240cab35`.

A later user instruction supersedes historical-usage protection: deletion eligibility must consider current order data and current references only. The next canonical migration updates both read metadata and save-time checks without deleting historical snapshots.
