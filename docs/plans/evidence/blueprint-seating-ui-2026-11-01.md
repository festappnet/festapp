# Blueprint seating UI regression - 2026-11-01

Scope: simulate the reported existing-order seating journey locally, including a
blank plan, Bus template, Save, purchased-product mapping, assignment, refresh,
reassignment and cancellation of a staged pair. No production writes or release.

## Confirmed failures and fixes

- Cold `preview-ticket-layout` `layout-text` requests returned HTTP 400 in the
  production Edge 1.74.0 image. The caught exception was `PermissionDenied:
  Deno.readFileSync is blocklisted on the current context`, from
  `unicode-properties/2.0.1/binaryTrie.node.js`. Use the same pinned upstream
  property tables with its embedded browser trie loader. Font, shaping policy
  and resource identities remain unchanged.
- Main Save returned a Future from a `setState` callback, causing a Flutter debug
  assertion. Make that callback synchronous and refresh seating context after a
  confirmed save so product repairs update the summary immediately.
- Product mismatch offered the wrong next step when the plan had no seats bound
  to the purchased product. Explain mapping under Reservations and orders and
  expose the existing product-editing workspace. Selecting the Bus group and
  changing its product repairs the mapping without rewriting purchases.
- Waiting-only NULL-product groups appeared as `#null` with a false mismatch.
  Exclude waiting/offered items and NULL products from compatibility aggregation;
  keep their independent counts and publication checks.
- Product-picker cancellation uses the shared Cancel wording.

## UI evidence

Used the real Flutter app with local Auth/REST/SQL/Edge services, isolated muted
browser sessions and synthetic data. Only external notification callbacks and
font storage transport were adapted. Font transport supplied SHA-256 verified
original Roboto bytes, not substitute font geometry.

- Blank revision-0 plan -> Bus (45 seats) -> Save initially reproduced HTTP 400.
  The first local rejection was missing font-storage configuration; that was a
  fixture boundary, not evidence of the production cause.
- Repeated the actual handler in the exact production Edge image without
  `useReadSyncFileAPI`; its cold dynamic import reproduced the production error.
  The new runtime canary now passes cold and warm requests with both original
  Bus/Driver texts and one complete registration per request.
- Assigned nine existing admissions, refreshed and retained all nine; one waiting
  registration stayed unchanged. Reassigned one seat and removed a staged pair
  without changing orders. Publication correctly remained blocked by waiting.
- Recreated the reported 0 unassigned / 9 blocked / 3 waiting state with a Bus
  group bound to a different product. Correcting the group product through UI
  changed nine blocked admissions to nine unassigned, then assignment succeeded.
- With the final code and synchronous file reads disabled, a fresh Bus Save
  returned 200, displayed Saved and produced no `setState` assertion. The new
  product-repair action opened the correct workspace; saving the purchased
  product updated the summary immediately to 9 unassigned / 3 waiting. The
  false `#null` row was absent and the picker displayed Cancel.
- A fresh isolated browser reopened that saved, remapped event, committed an
  assignment and refreshed to 8 unassigned / 1 assigned / 0 blocked / 3 waiting.
  An earlier nonresponding browser automation session did not recur.

Historical ambiguous admission snapshots remain nonassignable diagnostics, as
specified by the admission-transition plan. This work does not silently repair
or reinterpret purchased entitlement.

## Checks

- `deno test --frozen --lock=supabase/functions/deno.lock --allow-read --allow-env --allow-net` for `layoutTextEdgeRuntime_test.ts`, `layoutTextPreparation_test.ts`, and preview `preview_test.ts`, `resourceAdmission_test.ts`, `entrypoint_test.ts`: 41 passed.
- `node web_client/scripts/run_db_tests.js` filtered to `seating_transition_test.sql`,
  `seating_assignment_test.sql`, `seating_publication_test.sql`, with explicit
  disposable loopback `DATABASE_URL`: 3 suites passed. The new compatibility
  assertion first failed with expected 1 group, actual 2, then passed after SQL.
- `fvm flutter test --concurrency=1 test/components/blueprint/seating_transition_test.dart`: 16 passed. New widget test checks the product-repair action without mutation.
- Targeted `fvm dart analyze` for the three changed UI files and seating test:
  no errors or warnings; existing informational style diagnostics remain.
- `python3 automation/tickets/verify-blueprint-text-runtime.py --evidence build/blueprint-text-runtime-final-20261101`: passed. Receipt and original error log are in that ignored build directory.
- Python compilation and `git diff --check`: passed.

Host Deno and the local CLI's default readSync override did not reproduce the
production loader restriction. The former preview benchmark also patched the
current trie loader in its test bundle, hiding this bug. Restrict that shim to
its frozen historical baseline; the new regression invokes the real cold
handler in a production worker without a dependency rewrite or readSync override.

Production rollout still requires the UI, Functions source and migration
`20261101173000_seating_compatibility_admissions.sql`; none were deployed here.
The owned browser, Flutter server, Functions service and disposable Supabase
project were stopped after the final UI check.
