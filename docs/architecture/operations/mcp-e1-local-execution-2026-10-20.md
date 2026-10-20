# Local artwork authoring E1, 2026-10-20

The user authorized proceeding after E0 while configuring their MCP client.
The local E1 implementation adds reviewed artwork save, pending inspection and
explicit resume. Canonical profiles, including `vstupenky-online`, still expose
only the three E0 tools. They reject direct write-family invocation before any
credential/domain access. No production SQL, permissions, profile or release
was changed; Blueprint V2 remains excluded.

## Canonical ownership and contract

`save_occasion_client_sync_v1` remains the business owner. The adapter sends only
`p_occasion`, the original `p_expected_version`, stable `p_command_id` and narrow
`p_config:{id,ticket_layout_change:{expected,next,appearance}}`. Preflight reads
check current permission without substituting a new version or layout baseline.
SQL continues to own layout/font/asset/product validation, permission, locking,
aggregate advance, receipts and fanout. No business writer or SQL migration was
introduced for this wave.

Preview and save share the draft contract/fingerprint. Preview returns the exact
save request, including original layout/version and resolved appearance. Default
preview composition retains saved template variants not currently rendered.
Changed candidates fail fingerprint comparison until reviewed again. This guard
is not an authorization or human-approval mechanism.

`LayoutSave` owns command lifecycle. `FileIntentStore` owns only private client
recovery state, bound to profile/backend, authenticated actor and occasion. The
session owner's cross-process lock surrounds claim, submission and completion.
The original request/command is persisted with atomic rename and file/directory
fsync before sending. Reopening verifies identity, shape and fingerprint.
Uncertain results prevent a different request on that scope; explicit resume
uses the original parameters and baseline. Logout preserves unresolved intents.
No other client's/payment state is read, migrated or reset.

The existing receipt envelope is validated before exact compare-and-clear.
Malformed/mismatched/expired responses retain recovery state. Confirmed rejected
and conflict outcomes retire only their matching command. A stale completion
cannot clear a later command. The SQL owner replays stored response JSON verbatim,
so the adapter preserves its `replayed` flag rather than manufacturing one.
The narrow result strips the SQL response's full occasion document.

## Verification on final inputs

- 27 Node cases passed, with no skips, using the explicit disposable DB setting.
  Coverage includes E0 behavior, SDK stdio/schema checks, durable state before
  send, reopening/exact resume, changed-content refusal, malformed/expired/foreign
  replies, stale completion, corrupted stored data, logout retention and complete
  exclusion of write tools/admission on canonical profiles.
- One of those cases drives SDK MCP preview/save/pending/resume/conflict through
  the real PostgreSQL command as `authenticated`. The lost HTTP response is
  simulated after the SQL statement succeeds; the surrounding fixture transaction
  rolls back at the end. Version/receipt identity prove no repeated mutation;
  this is not a database crash/restart durability test. It verifies preservation
  of title, other data/features and the previous ticket permission flag.
- The existing `ticket_layout_authoring_test.sql` and E0 ordinary-role projection
  test both passed on the marked local PostgreSQL fixture. They cover narrow
  appearance saving, stale conflict and permission isolation.
- Synthetic preview still uses the actual Deno preview handler, canonical PDF
  renderer and PDF-to-PNG adapter. Auth/HTTP/Keychain are simulated at the Node
  boundary. No real recipient, user credential or tenant record is exercised.
- `git diff --check` passed. Logs: `/tmp/festapp-mcp-e1-test.log`,
  `/tmp/festapp-mcp-e1-sql.log`.

## Remaining E1 gate

The preserved legacy `update_occasion` facade reads a current aggregate version
for older payloads. `merge_ticket_layout_features` preserves the stored layout
without an explicit layout change, but legacy general feature writes can still
carry background/type appearance fields without the original editor baseline.
An installed-client inventory and enforceable upgrade/fence decision are still
required before canonical E1 exposure. This wave neither breaks that public
contract nor treats a local profile switch as production readiness evidence.

Canonical registration therefore remains disabled in code, with no production
opt-in flag. Errors lacking a confirmed receipt remain pending for authoritative
recovery; no abandon/force-save route is offered. Resume retains the existing
occasion command's current authorization requirement. Broader receipt recovery
following destructive resource retirement is not claimed for this layout slice.

E1 is implemented and locally verified, not production-enabled or a completed
live design/save acceptance. The next release decision must resolve the family
compatibility/executor gates. Other planned families remain sequenced separately.

Subsequent checkpoint: [artwork fence and shared runtime readiness](ticket-layout-fence-release-preparation-2026-10-20.md). Earlier local-only registration statements describe that checkpoint and are superseded by the common backend gate.
