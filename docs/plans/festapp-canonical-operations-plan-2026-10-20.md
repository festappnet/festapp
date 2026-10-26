# Canonical Festapp operations and MCP access

Date: 2026-10-20  
Status: Selected backend scope released; subsequent architecture cleanup and [MCP E0](../architecture/operations/mcp-e0-local-execution-2026-10-20.md) plus [local E1](../architecture/operations/mcp-e1-local-execution-2026-10-20.md) verified. Live operator login, connection and later write/hosted waves remain.
Verification for implementation: standard (authorization, destructive commands,
email commitments, shared contracts and database migrations)

## Outcome and authority

First refactor the selected existing operations so every supported entrypoint
reaches one canonical implementation with explicit transaction, effects and
retry semantics. Refactor each selected family before exposing its writes.
Read/preview work can proceed without waiting for unrelated domain refactors.
Success includes removing replaced implementations and client coordination,
not merely adding a working new route.

This is the authoritative parent plan. The
[CLI/MCP plan](festapp-operations-plan-2026-10-20.md) remains the detailed design
for the phases 2-3 read bootstrap under the dependency gates below. The required
[ticketing-write child](festapp-ticketing-mcp-plan-2026-10-20.md) extends it with
seating-plan creation/editing, forms, products/capacity, ticket artwork and
issued-ticket changes. Read-only bootstrap exclusions do not exclude these
subsequent deliverables. The
[operation catalog](../architecture/operations/README.md) owns the wider domain
map and the generated inventory owns source references.

Local backend implementation was authorized through the execution prompt on
2026-10-20. See the [execution state and remaining CW gates](../architecture/operations/backend-refactor-execution-2026-10-20.md).
Production access, deployment, CLI/MCP/OAuth implementation, commit and push remain
outside that authorization. The full backend refactor is not complete.

Pro samostatnou realizaci backendu použij
[backendový exekuční prompt](festapp-backend-refactor-EXECUTION-PROMPT-2026-10-20.md).
Vybírá 1A-1I a nutné přesuny současných volajících; neobjednává implementaci MCP/CLI.

## Delivery phases and access modes

| Phase | Deliverable | Exit / dependency |
|---|---|---|
| 1 | Canonical backend operations and removed parallel writes | Apply 1A-1H to each affected family before its exposure; 1H closes the full refactor workstream. 1I additionally gates ticketing writes. |
| 2 | Shared operation contracts/handlers and minimal diagnostic CLI | Ordinary-user context plus four bounded read operations work against isolated fixtures. |
| 3 | Local stdio MCP as the first AI-facing interface | 3A read bootstrap, 3B ticketing authoring, 3C issued-ticket lifecycle; same handlers, family readiness gates and SDK interoperability. |
| 4 | Hosted remote HTTP MCP with independent grants | Identity integration gate, per-client/user/tenant/event scope, revocation, 4D ticketing-write parity and locally verified release package; separate authority for activation. |

Local MCP already reaches the canonical **remote backend** over HTTPS. Phase 4
is for clients that cannot run our local connector or require a hosted service;
it is not necessary simply to access live Festapp data from an authorized
workstation. CLI is a thin diagnostic/script adapter, not a separate product
milestone or a second business interface. MCP is the intended AI-facing surface.

## Implementation order and efficiency

This schedule controls execution order across the numbered workstreams below.
It replaces the earlier requirement to finish every phase-1 domain before any
CLI/MCP result. The user's refactor-first requirement still applies to each
operation being exposed. All promised refactors remain in scope; unrelated ones
are tracked unfinished rather than turned into prerequisites for ticket design.

| Slice | Smallest useful outcome | Actual dependencies / work |
|---|---|---|
| E0 | Local MCP inspects ticket-design resources and returns a visual draft preview | Trusted profile/activation, ordinary-user session, minimal operation schemas and stdio adapter; scoped layout read and existing `preview-ticket-layout` resolve/PDF flow. No active-layout write, no cancellation/Auth-definition refactor or complete report CLI prerequisite. |
| E1 | Refine artwork and save the reviewed revision | E0 plus layout/occasion owner reachability, original-version checks, narrow permissions, durable command identity and applicable 1I tests. Reuse the existing occasion writer, font catalog, schema and PDF renderer. |
| E2 | Create/edit a seating plan and closed form | Shared E0/E1 infrastructure; blueprint/form effective SQL extraction, rollback/scope/version repairs, usage/hold constraints and legacy-writer policy. No group/news/cleaning cutover dependency unless an actual shared helper requires it. |
| E3 | Configure products, prices and inventory for that form | Parent 1E product/context and wave-target consolidation, CW06-CW08 inventory owner extraction where used; form/product/seat references from E2. |
| E4 | Edit issued tickets, create/cancel orders, export/resend | Applicable canonical ticket/order writers and their permissions/capacity/payment/queue semantics; 1C/1D cancellation before exposing cancel. Deletion/invoice workflow before exposing deletion only. |
| E5 | Close the remaining canonicalization and read-bootstrap scope | Complete outstanding 1A-1H/CW ledger work, Auth definition consolidation, group/news/etc. cutovers and the four planned read operations. Per-family proof already earned is reused; nothing is declared removed while still active. |
| E6 | Hosted access when the chosen client requires it | Phase 4A identity/hosting decision followed by scoped HTTP adapter and grants for ready operations. Read-only pilot first; 4D for writes. No hosted OAuth/server build on the E0/E1 critical path. |

E0 is the first reviewable result; E1 is the first complete authoring result.
For every slice, record implemented files/owners, removed paths or bounded
external adapters, relevant check commands, exact passing source revisions and
remaining local/live gates. A dependency discovered in a shared helper can pull
that helper's repair forward; it does not automatically pull the entire domain.
Workstreams may interleave on one agent; this schedule does not request extra
agents or concurrent Flutter processes. Overall completion still includes E5.

### Reuse and scope limits

Start with existing source evidence and one targeted call-chain check per slice.
Reopen discovery only for changed or conflicting evidence. Do not regenerate the
whole operation inventory after every slice; regenerate at canonicalization
closure or after scanner changes. The 107-family catalog is a map, not a tool
implementation checklist or reason for another repository-wide audit.

Implement one private Node package and a small operation descriptor/handler
pattern using the first real operations. Add tools as their handlers pass gates;
do not require a universal plugin framework, code generator, workflow engine,
complete CLI UX or all tool schemas upfront. Login/profile setup and JSON
execution are the necessary CLI surface. Bring stdio MCP into E0 rather than
waiting for the four-read CLI to be fully packaged. Profiles and authentication
remain mandatory even for previews.

Reuse `preview-ticket-layout` modes and `generateTicketPdf`; reuse the registered
fonts and existing normal/long/missing fixtures. Add only the image/resource
adapter needed to view canonical PDF output. Do not implement another Flutter
canvas, text-measurement algorithm, font service, preset catalog or PDF renderer.
Batch draft edits before explicit preview; resolve unchanged resources once per
bounded draft context. Any preview cache is bounded and keyed by actor/backend/
occasion, layout/resource revisions and scenario, and cleared on context change;
no cross-user reuse of authorized assets. Durable receipts are needed for save/
delivery, not for each in-memory move or text change. Reuse existing visual
fixtures and one representative composition instead of a new benchmark suite.

### Verification and turnaround

Each slice ends in one coherent standard validation batch against final inputs.
Use domain SQL tests for state/guards/concurrency, Node boundary tests for input/
identity/adapters and one actual API/MCP journey for the slice. Avoid repeating
the full domain matrix through both CLI and MCP. A shared-handler parity test
proves adapter reuse; it does not replace the real backend checks. Keep required
repository gates and test-discovery verification.

Reuse one disposable backend setup with isolated fixture identities/data;
reset changed fixture state between tests. Replay a fresh baseline+forward path
when migration assembly/dependencies change and at schema closure, not for every
Node edit. Keep explicit final-input receipts for passing checks; rerun only
checks invalidated by changes. Flutter analysis/tests run only for affected Dart
code or shared renderer contracts, obeying the workstation limit. No Flutter
build or hosted deployment is needed to prove a Node/SQL-only slice locally.

Record setup/check wall time, requests per preview/save and the time to first
viewable preview at each milestone. These are observations to find a bottleneck,
not unmeasured speed promises or a new telemetry system. If one dependency
blocks a family, keep that tool disabled, report the precise gate and complete
other ready slices. Never bypass authorization, atomicity or version checks to
shorten implementation.

## Fixed scope and non-goals

Phase 1 covers the identified cancellation split, duplicate deletion command,
duplicate Auth SQL definitions, affected migration assembly, selected client
branches and selected operation contracts. The expanded
[cross-domain sequence review](../architecture/operations/sequence-review-2026-10-20.md)
adds product configuration/inventory-link save, additive group membership,
inline price-wave initialization, conditional draft cleanup/unit-information
contracts, and remaining parallel mutation paths covered in 1E-1G below.
It preserves the existing manual
choice to delete an external invoice. It does not invent automatic invoice
deletion, change refund policy or redesign checkout/payment allocation.

Do not make all 107 catalog families a prerequisite. Many are legitimate
projections, helpers, system protocols or complete external workflows. In
particular, migration-only definition ownership is technical debt, not proof
of a duplicate business implementation. Extract only selected dependencies
needed by these refactors, with exact current bodies and ownership recorded.

Retain complete checkout/Fakturoid orchestration, BankSync fencing, reception
Auth cleanup, account-deletion recovery and media Worker workflows. Occasion
duplication/media recovery remains a separate future contract before exposing
that write. The ticketing-write scope explicitly includes forms, blueprint
creation/editing, ticket appearance, products/pricing/inventory and issued-ticket
lifecycle; payment/bank/system administration is not implied by design access.
No new API server, generic JSON operation dispatcher, application
trigger, parallel email queue or second command receipt engine is introduced.

## Source evidence and unresolved runtime state

| Confirmed source fact | Evidence | Implication |
|---|---|---|
| Single-order cancellation performs a command and then a separate email request. | `lib/components/eshop/db_orders.dart`: `stornoOrder`, `sendStornoTicketOrderEmail`; `lib/components/eshop/order_commands.dart` | Move the required automatic notification intent into the domain transaction; remove the client follow-up. |
| Bulk cancellation already queues a notice when it cancels the last ticket. | `database/functions/eshop_orders/storno_tickets_bulk.sql`; `storno_tickets_client_sync_v1.sql` | Single/bulk/legacy cancellation must share the same transition and automatic email identity, not add another enqueue path. |
| Legacy cancellation facades already delegate, but have their own result shapes. | `database/functions/abuse/legacy_order_facades.sql`; `_221` declaration in client-sync migrations | Preserve required external shapes using mechanical adapters to one owner. |
| The same deletion signature is authored twice with different admission/locks. | `database/functions/eshop_orders/delete_order.sql`; `delete_order_client_sync_v1.sql` | Merge invariants deliberately; one source file must own that signature. |
| Deletion with optional invoice cleanup is already a distinct workflow. | `DbOrders.deleteOrder`, `views/order_delete_dialog.dart`; `supabase/functions/delete-order/delete.ts` | Direct database deletion versus explicitly selected external invoice deletion is not itself duplicate business logic. Preserve both intentions over one DB command. |
| Lost delete responses have an authorized receipt lookup. | `database/functions/eshop_orders/get_order_deletion_context_v1.sql`; `database/tests/eshop/orders/fakturoid_deletion_context_test.sql` | Reuse receipt/actor/request-hash validation after the order is gone; do not replay external deletion unnecessarily. |
| Three additional same-text-signature definitions are duplicated. | `consume_password_reset_rate_limit_v1` in `abuse/auth.sql` and `users/password_reset_rate_limit.sql`; `google_auth_rate_limit_v1` and `cleanup_external_login_v1` in `abuse/auth.sql` and `users/google_auth.sql` | Bodies inspected here are semantically aligned. Consolidate source ownership without changing rate policy, Auth ACL or cleanup behavior. |
| Existing assemblers bind mutable sources to fixed migration filenames. | `automation/assemble-form-capacity-waitlist-migration.py`, `assemble-abuse-migration.py`; `automation/tests/abuse_policy_coverage.test.mjs` | A source refactor must not silently regenerate already-applied migrations or invalidate a historical-source check without replacing it. |
| Current commands already have receipts, domain outcomes and sync projections. | `ClientCommandResponse`; `ClientCommandTransport`; `begin_client_mutation_v1` in the client-sync migrations | Reuse these contracts. Transport retries and retries after restarting an interaction need the same logical command identity. |

The source inventory currently finds four duplicate same-text-signature groups
and 93 called RPC names with migration-only definition evidence. These are
reconnaissance results, not a compiler-accurate overload audit or live state.
No production catalog, release/application status or installed mobile versions
were inspected. Never assume a source definition is the live winner.

## Canonical contracts and invariants

### Cancellation

Canonical public command remains `storno_order_client_sync_v1(p_order,
p_command_id)` and its existing mutation envelope. The function is authored in
`database/functions/eshop_orders/storno_order_client_sync_v1.sql`. The full-order
state transition is owned once by
`update_order_and_tickets_to_storno_ws_internal_v1`; the bulk path uses that same
transition when the selection cancels the whole order. Internal composition
does not require another network request or an Edge wrapper.

- The domain transaction owns order/ticket/history/allocation/membership changes
  and the required automatic cancellation email intent for a valid recipient.
  Preserve existing order editor guards, tenant consistency, write gates,
  admission, capacity locks, immutable-state rules and sync effects.
- Both single-order cancellation and final-ticket cancellation reach the same
  full-order transition and automatic notification key. Remove the old bulk
  special-case enqueue after that responsibility moves to the canonical owner.
- Missing or invalid recipient follows the existing bulk skip behavior and
  returns an explicit skipped notification outcome. For a valid recipient, a
  failed durable intent insertion fails the transaction; never return complete
  cancellation while silently losing a required notification. Queue pause or
  provider outage after persistence means pending delivery, not a failed command.
  Preserve global queue/admission gates; do not bypass them to force a result.
- Replaying the same actor/payload/command ID returns the saved outcome without
  another history entry, enqueue, capacity change or admission charge. A second
  command for an already-cancelled order is unchanged, without new side effects.
- Partial-ticket cancellation keeps its existing update-notification semantics;
  do not force it into the full-order cancellation contract. Compare the full
  `storno_tickets_bulk` remainder and current tests before moving code.

### Automatic notice versus deliberate re-send

Old installed clients may still call `send-email` after the updated SQL command.
Do not infer a manual resend just because that Edge handler adds `requested_by`.

Make automatic `TICKET_ORDER_STORNO` requests without an explicit resend identity
resolve to the same server-derived cancellation intent used by SQL. Preserve
the current transition/version/recipient identity and queue input-hash contract.
Do not generate a fresh UUID for an automatic retry. Existing historical intent
keys, message state and receipt payloads are data compatibility, not disposable
source names; add a targeted forward reconciliation only if evidence requires it.

A deliberately requested resend uses its explicit request ID and existing
authorization. It is a separate operation. Trace all request producers and
`enqueue_order_email` key normalization before changing dedupe, including
cancelled/expired intent states. If historical automatic and manual requests
cannot be distinguished, do not guess or disable manual messaging: add the
minimal explicit boundary contract and record old-client behavior in the gate.

### Deletion

Keep `delete_order_client_sync_v1(bigint,uuid)` as the one authoritative DB
command, authored only in its dedicated SQL file. `delete_order.sql` retains
only the internal deletion implementation and any justified mechanical facade.

Merge required admission, email cleanup, capacity/order/activity/group locks,
private-scope cleanup, aggregate versions, immutable history constraints and
sync publication effects. Do not concatenate both lock sequences blindly;
establish one order consistent with related cancellation/membership writers.
Preserve the current `ORDER_HAS_WAITLIST_HISTORY` constraints.

The existing `delete-order` Edge workflow retains explicitly selected invoice
deletion, user-scoped authorization, protected external credentials and replay
recovery. Ordinary delete does not acquire permission to delete an invoice.
Reuse authorized receipt lookup before depending on the deleted order row for a
lost-response retry. Bind replay to actor, command name, request hash, tenant and
current unit authority; reject reused command IDs for another order or actor.
If a direct SQL caller needs recovery, share that validation rather than copy it.

### Auth definitions

Create a reusable, definition-only owner
`database/functions/abuse/auth_contracts.sql` for `consume_auth_abuse_v1` and the
three duplicated compatibility/cleanup functions. Preserve exact guard behavior,
server-owned limits, grants and cleanup. Remove those definitions from the
other authored files. Retain any still-required domain DDL and one-time budget
adoption separately. Do not re-run legacy counter adoption or old table drops
by reapplying a mixed DDL/DML source during this refactor.

No Auth endpoint rename, session-policy change, budget reset, new privilege or
global logout is part of this source consolidation. Existing public signatures
remain mechanical boundaries over the same policy engine.

### Cross-client and compatibility rules

Unversioned catalog IDs name domain operations; deployed RPC/protocol tokens
need not be renamed just to remove a suffix. Current Dart cancellation/deletion
callers converge on their typed command adapters without local legacy branch
selection. Do not remove the global Client Sync selector used by other domains.

Keep legacy SQL/Edge shapes only where an actual supported deployed client or
integration requires them. Each retained adapter needs an owner, concrete
consumer, delegation proof and removal condition. Unknown installed-client
state prevents dropping an external contract; it does not justify keeping
another implementation or skipping the source refactor. If no consumer exists,
drop the obsolete entrypoint with a forward migration and remove its grants.

## Phase 1: canonical operation refactor (mandatory per-family gates)

### 1A. Freeze reachability, migration and compatibility evidence

Update the four traced catalog contracts with UI entrypoints, typed adapters,
legacy facades, direct RPC callers, Edge selectors, SQL-internal callers, jobs,
queue producers, grants and tests. Use the existing inventory and scoped search;
do not re-audit every business family. Record rollback-safe input assumptions.

Map the four duplicate signatures by actual PostgreSQL identity arguments,
not only source text. In the disposable baseline/forward-migration setup,
identify the final function bodies/ACL and which source/migration supplied them.
Document installed-client support from repository release evidence where
available; otherwise explicitly retain the necessary mechanical boundaries.
Production observations remain a separately authorized release prerequisite.

**Exit:** a reviewed owner/caller/grant/compatibility ledger exists for every
in-scope path, with no guessed live winner or unexplained external removal.
Static source inspection is sufficient for this substep; no production queries.

### 1B. Consolidate authored SQL and forward migration assembly

Move the deletion command to its dedicated owner and merge its invariants.
Extract Auth definition-only contracts as specified above. Keep existing receipt
tables, IDs, email intents and provider facts. Add
`automation/assemble-operations-foundation-migration.py` with an explicit fresh
14-digit forward migration destination and a deterministic `--check` mode.
Its ordered source manifest includes each selected definition once and never
re-runs historic data adoption. Refuse to overwrite historical migration targets.

Before modifying old assemblers/checks, establish whether their fixed snapshots
are frozen release inputs or genuinely unapplied candidates. Default to frozen:
preserve checked-in historical SQL bytes. Retire their mutable-source rebuild
path for frozen targets and move current-source equivalence checks to the new
forward manifest. Update `automation/tests/abuse_policy_coverage.test.mjs` and
current authoring instructions accordingly; preserve historical provenance.
If an old assembler has no active consumer, delete it rather than leave a dead
alternate release path. Do not run its former default writer as a validation.

Add `automation/tests/canonical_operation_sources.test.mjs` to verify selected
function identity ownership and ordered forward assembly, including the Auth
signatures. It must allow immutable historic copies and genuine overloads,
while rejecting two active authored owners of the same selected identity.

**Validation:** new source-ownership/assembly check; targeted deletion, abuse
and Auth SQL tests listed below on an isolated DB with the fresh migration.
**Exit:** one authored owner per selected signature; fresh migration reproduces
the intended bodies and ACL; no historical migration rewritten.

### 1C. Make cancellation one complete transactional operation

Implement the cancellation and notification contracts above across
`storno_order_client_sync_v1.sql`, `update_order_and_tickets_to_storno_ws.sql`,
`update_order_and_tickets_to_storno.sql`, `storno_tickets_bulk.sql`,
`storno_tickets_client_sync_v1.sql`, and `emails/email_domain.sql` as required.
Keep one full-order transition, one automatic message identity and the existing
receipt protocol. Change `send-email/index.ts` only for required normalization
of old automatic requests versus explicit resend, not provider dispatch.

Review permission/tenant context before receipt access, normalize the intended
ticket set for command identity, and preserve parent lock order. Do not add
application triggers or perform provider HTTP while holding DB locks.

**Validation:** extend `database/tests/emails/ticket_cancellation_outcomes_test.sql`
and add `database/tests/eshop/orders/canonical_order_cancellation_test.sql` for
single/bulk/legacy same outcome, replay, new-command unchanged, missing/invalid
recipient, forced enqueue failure rollback, permission/tenant denial and pending
delivery. Add a two-connection integration test for concurrent whole-order and
last-ticket cancellation; one surviving transition/intent/history result.
Test an old client's subsequent automatic `send-email` and a genuine explicit
resend through the Edge handler. Use fixtures, never send real email.

**Exit:** state and required intent commit together; provider outage does not
ask clients to redo the domain command; no duplicate automatic message across
single/bulk/legacy callers or simultaneous requests.

### 1D. Move current clients and remove replaced paths

Update `DbOrders.stornoOrder` and `deleteOrder` to their canonical command
adapters. Remove their cancellation/deletion legacy selector branches. Delete
the automatic `sendStornoTicketOrderEmail` follow-up and helper if no deliberate
resend consumer remains. Keep manual resend only behind its explicit operation.

Use `ClientCommandIdentity` for stable logical cancellation/deletion identity
across uncertain outcomes, scoped to backend, actor and payload. Extend typed
adapters/`ClientCommandTransport` narrowly to accept a supplied command ID while
preserving its existing generated-ID behavior for other domains; do not let the
transport overwrite a supplied identity. Persist an immutable handle including
original expected revisions before submission; normalize set-like IDs before
hashing while retaining meaningful geometry/field ordering. Clear pending intent
only on verified terminal outcomes by atomic comparison of exact command ID and
principal, never just namespace/payload. A delayed response must not clear a newer
intent. Migrate existing unresolved payment intents without discarding or rebinding
them. Preserve expired receipt tombstones as explicit non-replayable outcomes;
never replace an uncertain/expired command with a fresh ID to force execution.
Distinguish committed deletion recovery from a new delete.
Reuse existing invoice deletion recovery and do not repeat external work.

Remove duplicate definitions, bulk special-case enqueue, dead helpers, obsolete
tests and in-scope active fallback references. Keep historical SQL snapshots.
For required old entrypoints, replace business code with mechanical delegation
and record their consumer/removal condition. Do not retain fallback routing
in current client code to make compatibility look complete.

**Validation:** affected Dart adapter/transport/identity behavior, canonical SQL
and Edge tests. Test lost response with the same command ID, cancellation queue
pending status, deletion replay after the row is gone, and no post-cancel email
call from the current client. Use supported session test discovery as below.
**Exit:** every known supported caller reaches one owner; all deletion-ledger
items are removed or explicitly bounded external adapters.

### 1E. Consolidate confirmed cross-domain atomic saves

Implement A02-A04 from the sequence review as separate coherent slices. Each
uses the existing mutation receipt and publication contracts, with all inputs
included in request hashing and the same ID retained after an uncertain result.
Do not create a generic multi-RPC batch endpoint.

**1E-product:** extend `update_product_client_sync_v1` and
`update_product_internal_v1` to accept the explicitly present
`inventory_contexts` collection in `p_product`. Extract the effective command
definition to `database/functions/eshop/update_product_client_sync_v1.sql` if
still migration-only. Share existing context validation/replacement internally
with `update_product_inventory_contexts_client_sync_v1`; preserve its standalone
contract while it has callers. Omitted collection preserves links; empty clears
them. Update `ProductGridRecord.updateMethod`, `EshopCommands` and its Supabase
adapter to perform one save with links, then remove that caller's second RPC.

Preserve price/deposit/currency/type rules, inventory validation, lock ordering
and the union of both commands' sync effects. Use a scoped forward migration;
do not copy an early migration body without checking later overrides.
Add `database/tests/eshop/product_inventory_save_test.sql` for atomic rollback
on invalid/foreign link, omission versus clear, permissions, replay and
concurrency. Extend affected Dart command tests and existing product/price tests.
**Exit:** a rejected context never leaves a newly saved product/configuration.

**1E-group:** add typed `GroupCommands.addMembers` and one proposed
`public.add_user_group_members_client_sync_v1(p_occasion bigint,p_group bigint,
p_users uuid[],p_command_id uuid)` authored under `database/functions/groups/`.
Validate/bound the selected user set, preserve current leader/editor authority,
lock the group and union selected members with current membership. Preserve
existing admins; do not import a stale whole-group snapshot or overwrite place,
title or description. Full-group save and additive membership must share one
internal membership writer and synchronization rules.

Move `UsersTabHelper.addToGroup` from `updateUserGroupParticipants` to this
command. Complete its remaining legacy aggregate caller during 1F and delete
the old delete-all/insert-per-member helper. Test denial/foreign member rollback,
replay, retained admin flags and concurrent additive edits in
`database/tests/groups/add_members_test.sql`, plus affected Dart tests.
**Exit:** adding members cannot erase existing or concurrently added members.

**1E-wave:** add a fixed-schema receipted wave-target command authored under
`database/functions/eshop/`, proposed name
`save_product_wave_target_client_sync_v1(p_target jsonb,p_command_id uuid)`.
The schema explicitly identifies occasion link, product, either existing wave
ID/revision or new wave time, nullable price/visibility targets, and expected
target revisions. Reject unknown fields and ambiguous wave selection. Reuse
internal resolution/adoption/target validation with existing wave functions;
do not maintain duplicate pricing or adoption algorithms.

Move only the unpersisted-wave target action in
`product_price_waves_dialog.dart` to this complete command. Keep standalone
create/move/cancel wave actions and existing-wave target editing as supported
intentions over canonical helpers. Failed target validation must roll back wave
creation and planned-change adoption. Extend
`database/tests/eshop/product_price_waves_test.sql` and corresponding Dart tests
for permissions, conflict rollback, same-time concurrent creation and replay.
**Exit:** one UI target-save intention has one atomic backend outcome.

### 1F. Complete remaining parallel mutation-routing cutovers

Use the concrete [remaining-write ledger](../architecture/operations/remaining-write-cutover-ledger-2026-10-20.md)
CW01-CW24 as this phase's ownership/removal matrix. It distinguishes independent
DML, shared helpers that omit command effects, already-delegating facades and
scope/identity gaps. The pool/report commands currently call old public writers:
extract internal owners first so facade conversion cannot introduce recursion.
The matrix is part of this authoritative plan, not an optional follow-up.

Follow L01-L11 in the sequence review, grouped by domain so each change is
reviewable. The exact removal set includes:

- `DbGroups.updateUserGroupInfo` / delete direct table branches and
  `DbPlaces.updateLegacyPrivateGroupPlace` / `deleteLegacyPrivateGroupPlace`;
  preserve aggregate place/membership logic in existing group commands.
- `DbEvents.updateExclusiveGroup` / delete direct group/link replacement;
  use existing exclusive-group commands and expected versions.
- `DbActivities.saveActivitiesForEdit` legacy history-then-update publication;
  use the existing atomic publish command.
- `DbNews.sendMessage` legacy insert-then-enqueue and delete/read-pointer
  reconstruction; use existing publication/delete commands while preserving
  explicit send-notification/add-to-news choices and standalone read acknowledgements.
- `DbUsers.updateOccasionUser` fallback create/add-membership/upsert sequence;
  use existing create/save profile contracts, preserving field and role scope.
- Remaining alternate path/information/form/product/inventory/speaker/cleaning/
  unit mutation callers: compare scopes and outcome contracts, then use their
  existing canonical command owners. Do not count mutually exclusive branches
  as sequential writes; remove actual alternate implementations where equivalent.

Before each move, verify the canonical owner works for supported non-sync read
contexts as well as sync contexts. Extend backend admission/publication glue
if required without restoring a second business implementation. Keep unit scope
distinct from occasion scope and do not infer a missing occasion from UI state.
This does not authorize a wholesale read-sync architecture cutover or deletion
of the global projection selector. Keep required installed-client facade shapes
with the parent's explicit consumer/removal conditions.

**Validation:** canonical command behavior through both selected and nonselected
read contexts; domain role/version/foreign-scope tests; failure during member/link
replacement leaves prior aggregate intact; no direct table-DML fallback from
current callers. Include group, exclusive-group, activities, news and profile
test seams plus narrower checks for each additional moved caller.
**Exit:** all reviewed parallel write paths either delegate to one owner or are
explicitly excluded for a documented distinct scope/operation, not left as
unexplained migration branches. Update the deletion ledger per moved family.

### 1G. Resolve conditional and retained-workflow contracts

Resolve A05 before activity publication writes are exposed: if publication
consumes its selected draft, pass the expected autosave identity/version and
consume only that draft in the publish transaction. Remove broad client
`deleteAutosave(occasion)` after publication. If cleanup is intentionally best
effort, return separate cleanup state and use a conditional cleanup command;
never delete another tab's newer autosave or replay the publish for cleanup
failure. Explicit user-requested draft deletion remains a separate action.

Resolve A06's supported unit/type combinations from unit information callers,
fixtures and current RLS before implementing anything. If unit game/hidden data
is supported, one unit-authorized command must commit public/hidden data with
consistent scope. If unsupported, reject the combination before either write;
do not expand hidden-answer permissions or create a new feature to fix the
sequence. Keep ordinary unit information and occasion game contracts distinct.

Record W01-W18 and S01-S09 dispositions in the catalog. In particular retain
BankSync details' same-intent accelerator, provider/queue recovery, optional
invoice deletion, manual update-email confirmations and force-delete prompts.
For W05/W03, specify staged ensure-token/duplicate-media recovery before exposing
those writes; no immediate provider-workflow rewrite is required for read-only
CLI. L12's legacy storage writes need separately established target authority.
R01-R07 read-bundle improvements stay bounded, prioritized separately by payload
and consistency evidence; do not make every screen a mandatory new endpoint.

**Validation:** two-tab publish/draft race and supported/unsupported unit-shape
tests for any changed behavior. Retained-workflow ledger documents why each
sequence stays staged and its existing recovery owner.
**Exit:** no conditional finding is silently called fixed or allowed to broaden
permissions; retained external/user-choice sequences are explicit contracts.

### 1H. Prove and record the refactor gate

Regenerate source inventory and update the semantic catalog with canonical owner,
contracts, retained boundary adapters and unresolved runtime steps. Run scoped
absence/reachability checks, behavior tests and local migration state checks.
Add new targeted tests to their actual repository lanes/discovery lists.

The implementation handoff must separately report local code/migration readiness
and production activation. Do not call the operation fully live or remove an
externally used entrypoint based on local checks alone.

**Full workstream closure (1H):** source canonicalization, cancellation atomicity, product/link
save, additive group membership, atomic inline wave-target creation, duplicate
notice protection, receipt safety, current-client routing cutovers, preserved
guards and target checks are complete locally. Conditional findings and retained
workflows have the explicit outcomes required by 1G. Any remaining old facade is one explicitly
documented external adapter. No competing implementation remains. The pending
production release is recorded. Earlier isolated reads/previews need their own
scoped contract/permission proof; write exposure requires the relevant family
refactor and 1I. Unrelated unfinished refactors do not block E0/E1.

### 1I. Prove ticketing write readiness per family

This gate is mandatory before each phase-3B/3C family is enabled; it does not
block independent reads/previews. Execute the concrete repairs and source traces
in the [ticketing-write child](festapp-ticketing-mcp-plan-2026-10-20.md).

For blueprints, extract the effective `update_blueprint_internal_v1`/command
chain into authored SQL. The original `update_blueprint.sql` may mutate earlier
spots before returning a later JSON rejection, and updates submitted spot IDs
without a blueprint predicate. The migration wrapper does not itself roll back
such a rejection. Enforce full seat/product/form scope and wrap domain effects
in a rollback subtransaction before completing a rejected receipt. Strip hold
secrets from errors and authoring reads. Lock affected rows consistently with
public holds/order allocation; reject sold/held-seat deletion under those locks.

Add minimal versioned authoring reads instead of returning full blueprint order/
customer bundles. Form and blueprint writes must compare the editor's original
baseline under lock, and all competing writers must advance existing aggregate
versions. Use explicit JSON control fields for existing JSON command signatures,
consumed outside persisted documents; avoid ambiguous default-argument overloads.
A supported old caller without a baseline requires a documented upgrade/fence
policy: an adapter cannot reconstruct the original revision. Keep affected MCP
writes disabled until that policy is enforceable. Do not silently break a public
contract or claim lost-update safety from a freshly fetched baseline.

Preserve form explicit deletion lists, omitted-versus-empty semantics, actual
usage guards and capacity/waitlist/blueprint constraints. Check the entire form
chain for rejection atomicity. Guarantee closed form creation atomically before
exposing creation. Layout saving must use narrow `ticket_layout_change` expected/
next semantics and unit-editor permission, preserving unrelated occasion features
and refusing unknown-schema downgrade. Issued-ticket mutations retain canonical
price/payment/capacity calculations; editing, export and delivery stay distinct.

**Validation:** targeted isolated SQL/adapter tests prove zero domain changes on
a later-object rejection, foreign-seat denial, hold/allocation concurrency,
stale-baseline conflicts, legacy-writer fencing, form deletion guards, layout
permission isolation and durable exact-identity retry/compare-and-clear. Add
source ownership/removals and migration ordering to the per-family ledger.
**Exit:** each enabled family has one safe writer, versioned minimal readers,
explicit permission/effects contracts and tested replay/legacy policy. Disabled
families are reported individually; four read tools do not complete this scope.

## Phase 2: shared read operations and diagnostic CLI

Execute the detailed [child plan](festapp-operations-plan-2026-10-20.md), including
its contract phase and implementation waves 1-2, interleaved with MCP under
E0-E5 instead of requiring all four readers before ticket design. Use the updated catalog,
existing canonical report, bounded domain-owned readers, protected ordinary user
sessions and shared CLI/MCP invocation handlers. Reuse domain error/receipt
semantics rather than inventing a competing backend envelope.

This phase supplies context inspection, occasion report, authenticated occasion
listing and bounded order inspection. It does not expose phase-1 writes by
default. Its local checks do not require production migration activation, but
live use of new readers does. Exit: the four operation handlers are usable
without terminal/MCP coupling and their diagnostic JSON matches their contracts.

## Phase 3: local MCP over the same operation handlers

Phase 3A supplies stdio, SDK interoperability and protected context starting
in E0 with context/layout inspect and preview. Complete the four planned domain
readers by E5. CLI remains a thin login/diagnostic/script adapter. Execute
the [ticketing-write child](festapp-ticketing-mcp-plan-2026-10-20.md): 3B enables
blueprints, forms, ticket appearance, products/waves/capacity after each family's
1I gate; 3C adds issued-ticket edits and order lifecycle/export/delivery with
separate capabilities and explicit side-effect intent. Ticket artwork includes
iterative visual design with viewable MCP previews and matching canonical PDF,
not just template-JSON editing; use the child visual acceptance gate.
These writes are required
planned deliverables, not an unspecified follow-up after a read-only product.

Exit: the local MCP client can create and edit a closed ticketing setup, inspect
its geometry/artwork, explicitly activate sales and perform authorized issued-
ticket changes through ordinary-user domain commands. CLI/MCP share handlers,
schemas and outcomes with no copied business rules, direct SQL/admin access or
shell tools. Connecting to the remote backend requires no hosted MCP server.
Production use remains conditional on the relevant release and compatibility gates.

## Phase 4: hosted remote MCP and delegated access

Follow the [remote MCP child plan](festapp-remote-mcp-plan-2026-10-20.md):
4A resolves actual client/login/issuer/storage integration; 4B implements the
HTTP adapter and grant-scoped ordinary-user context; 4C proves revocation and
isolation and prepares the release package; 4D enables the same ready ticketing
write families with separate operation grants. These are explicit planned steps.

The initial remote surface stays read-only with allowlisted clients and selected
organization/occasion grants. No passthrough of arbitrary bearer tokens or
hosted reuse of a workstation operator session. The same handlers are used;
remote hosting does not reimplement the backend. Subsequent write grants
distinguish design, sales activation, issued-ticket changes, export and delivery.
Revocation blocks new write admissions; it cannot undo a transaction already
admitted or committed. Keep receipt/audit recovery for uncertain outcomes.
A properly scoped and revocable
connection is separate from the user's normal Festapp session.

Do not publish or create live identity/hosting configuration during planning or
local implementation. If phase 4A establishes that local MCP satisfies the
actual access requirement, record that decision and keep hosted activation out
of the release. If hosted access is needed, its auth/identity gate is mandatory.

## Deletion and retention ledger

| Artifact | Action / proof |
|---|---|
| Command definition embedded in `eshop_orders/delete_order.sql` | Delete that duplicate declaration; retain internal deletion and justified adapter. One active definition by PostgreSQL identity. |
| Auth definitions duplicated in `abuse/auth.sql`, `users/google_auth.sql`, `users/password_reset_rate_limit.sql` | Move to `abuse/auth_contracts.sql`; delete duplicate function/grant blocks and the emptied password-reset file if unused. Keep other required domain schema/logic. |
| Historic Auth counter adoption/drop statements | Retain only as historic migration/adoption provenance; exclude from reusable fresh definition assembly. Never reset consumed budgets. |
| Client `sendStornoTicketOrderEmail` after automatic cancellation | Remove call and helper when no manual consumer remains; Edge legacy request behavior converges on the canonical intent. |
| Product-grid `updateProductInventoryContexts` follow-up | Remove from full product save after links join the canonical product transaction; retain standalone context operation only for actual separate callers. |
| `DbGroups.updateUserGroupParticipants` delete/insert loop | Remove after additive-user UI and legacy aggregate-save callers migrate; no stale full replacement for an additive action. |
| Inline `createProductPriceWave` then target-save caller | Replace with one atomic command using shared existing helpers; retain deliberate standalone wave creation. |
| Group/exclusive-group/news/activity/profile direct-write alternate paths | Remove per 1F after supported-context parity; no current client write selector routes to independent business implementations. |
| Post-publish broad autosave cleanup | Replace with selected-draft conditional semantics or separate explicit best-effort outcome; retain deliberate draft deletion. |
| Bulk-only full-cancellation enqueue block | Remove after canonical full-order transition owns intent creation; retain partial-cancellation behavior. |
| `ClientSyncRuntime.isV1Selected` cancellation/deletion branches | Remove only selected client branches; retain unrelated global sync selection. |
| Old SQL facades and versioned external tokens | Drop where no supported consumer; otherwise retain one mechanical adapter with named consumer and removal condition. Do not invent unversioned alias RPCs solely for naming. |
| Old fixed-target migration assembler/check paths | Freeze history; retire unsafe regeneration and obsolete current-source equality checks; one fresh forward assembler owns this release. Preserve documented historical evidence. |
| Existing mutation receipts and email intents | Retain IDs/data; replay and dedupe compatibility tests prove continuity. Reconcile only if a concrete mismatch requires a scoped forward migration. |
| Historical migrations and dated evidence | Retain unchanged; expected historic references are not active alternate implementations. |

## Verification and production ordering

Planning does not run application tests. Implementation uses standard targeted
checks in one coherent batch per slice against final inputs. Reuse passing
evidence at closure unless affected inputs change; no repeated full builds
after each edit.

- SQL runner: explicit disposable `DATABASE_URL` and
  `node web_client/scripts/run_db_tests.js <test-file>`; verify selected count.
  Cover `canonical_order_cancellation_test.sql`,
  `emails/ticket_cancellation_outcomes_test.sql`,
  `emails/order_delete_email_cleanup_test.sql`,
  `eshop/orders/delete_cancelled_order_test.sql`,
  `eshop/orders/delete_paid_order_test.sql`,
  `eshop/orders/fakturoid_deletion_context_test.sql`,
  `abuse/order_mutation_test.sql`, `abuse/email_auth_test.sql`,
  `abuse/password_test.sql`, `users/password_reset_rate_limit_test.sql` and
  `google_auth_test.sql` as affected. Rebuild fresh local baseline+forward SQL
  when necessary; production is never a test database.
- Concurrency: add a two-connection local fixture under
  `database/tests/eshop/orders/` following existing
  `database/tests/abuse/concurrency.test.mjs` conventions. Record locks, retries
  and final receipt/intent counts, not just SQL function return codes.
- Edge: run existing deletion tests and new automatic-request/resend tests via
  the repository Deno lane with its documented local dependencies/permissions.
  Inspect `supabase/functions/test-coverage.json` before choosing commands; do
  not treat a mocked helper test as real handler/auth integration.
- Dart: locate current semantic session roots/discovery in
  `automation/client_test_inventory.json` and the client runner before running
  `order_commands_cases.dart` or transport cases; a `_cases.dart` path alone may
  not be a runnable suite. Use targeted analyzer checks where relevant. At most
  one workstation Flutter task, always `--concurrency=1`.
- Source/assembly: new `canonical_operation_sources.test.mjs`, affected
  `abuse_policy_coverage.test.mjs`, inventory tests and generator `--check`.
  Prove one active authored identity, moved callers, correct grants and absence
  of the removed post-cancellation client flow.

For a separately authorized production release: verify canonical backend/tenant
activation and exact migration application state; prepare a clean selected
source revision; apply additive canonical SQL and backward-compatible dedupe
handling before releasing current clients. Verify ordinary-user SQL and Edge
boundaries, then release only the selected tenant. Remove externally used
facades only after their documented compatibility gate is satisfied. Preserve
all existing backend/web release safeguards and direct local release rules.

If deployment/monitoring is later requested, delegate routine execution according
to the repository standing instruction; engineering failures return to the
primary agent. No deployment agent is needed during planning.

Rollback may restore a client version only if it works with the new canonical
owner and automatic-request dedupe. Do not restore the duplicate SQL definitions,
independent automatic sender or reset receipt/budget data. Fix database defects
with a targeted forward migration; retain queued commitments.

## Decisions, assumptions and completion

- **Decision:** phase 1 is mandatory before each affected write is exposed,
  with full refactor closure tracked in E5. Independent reads/design preview do
  not wait for unrelated domains. Selected contract names stay stable for clients.
- **Decision:** full cancellation automatically creates a notification intent
  for a valid recipient, matching existing client behavior and the bulk path.
  Manual resend and optional invoice deletion remain explicit intentions.
- **Assumption:** current queue key/version semantics can safely identify the
  same automatic cancellation intent from an old follow-up request. Resolve in
  1C with producer/key/state tracing and handler tests; if false, design the
  minimal explicit compatibility contract before client release, not a new sender.
- **Assumption:** fresh migrations can depend on already-active queue/abuse/sync
  schema. Resolve in 1A from isolated migration replay and release evidence;
  never blindly apply every pending migration or rerun historic adoption.
- **Unverified:** production migration state and installed-client support. These
  gate live rollout and destructive external-contract removal, not local work.
- **Residual risk:** concurrent capacity/membership/email locks and external
  invoice partial failure require targeted behavioral proof. Removing duplicate
  text alone is not evidence of preserved behavior or improved performance.

Complete phase 1 requires every removal-set item to be deleted or an explicit
external boundary; one authored owner per selected function identity; atomic
required cancellation effects; atomic product/link and wave-target saves;
non-destructive additive membership; explicit conditional/workflow dispositions;
replay/dedupe safety across supported callers;
passing targeted migration/guard/concurrency checks; and precise local/live
state reporting. The overall project additionally requires phase-2 reads, CLI
and phases 2-3 passing the bootstrap and ticketing-write completion gates, with
1I proved for each enabled write family. Hosted remote access additionally
requires phase 4's identity, scope, revocation, write-grant parity and release gates
when that hosting mode is selected. No production effect
is claimed while its release steps remain unapplied.


## Backend-only execution reconciliation

The [backend execution record](../architecture/operations/backend-refactor-execution-2026-10-20.md)
closes the selected local CW01-CW24 scope and distinguishes it from this parent
plan's later exposure/release phases. Its final forward manifest, catalog-body
checks, compatibility gates and per-family evidence are authoritative for that
execution. Historical migrations and Auth budget adoption remain immutable.

CW07 retains the resource command as its single DML owner because every legacy
shape delegates to it; no second resource business engine was introduced.
Private pool/report extraction was necessary for their actual recursive graphs.
A preexisting authored occasion-copy statement referenced an absent
`inventory_pools.order` column; materialization preserves the effective schema's
supported pool fields and configured capacity instead of introducing an
unrelated schema change. The copy fixture exercises a populated pool.

Configuration versions cover fields that the selected editor can submit.
Operational capacity counters, scanner credential/epoch state and quote feature
rotation keep their existing separate semantics. Modern destructive form/product
calls now carry original versions; released shapes retain hashes behind an
explicit installed-client/pending-intent fence gate. No MCP write exposure or
production migration is authorized by the local completion claim.
