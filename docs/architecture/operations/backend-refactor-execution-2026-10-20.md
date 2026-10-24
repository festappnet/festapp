# Backend refactor execution, 2026-10-20

Status: **selected local backend scope implemented and verified**. CW01-CW24
are reconciled below. Production activation and MCP write enablement are not
completed or authorized by this record. CLI, MCP, OAuth, a new editor and visual
preview were excluded.

The existing dirty working tree was preserved on
`feat/occasion-setup-wizard-20261007`, HEAD `eb2304724`. This is not an immutable
release revision. No production access, provider calls, deployment, commit or
push was performed. All database execution used the disposable
`festapp-db-tests-pg15` project at `127.0.0.1:55432`.

## Canonical owners and current callers

| Family | Owner and callers | Result |
|---|---|---|
| Auth definitions | `abuse/auth_contracts.sql`; GoTrue hook in `abuse/auth.sql` | One authored owner per selected signature. Duplicated Google/password-reset definitions and the redundant Auth assembler were removed. Historical budget adoption is not re-executed. |
| Order deletion | `delete_order_client_sync_v1` -> `delete_order_internal_v1`; `DbOrders`, existing invoice Edge workflow | Receipt recovery precedes dependence on the deleted order. Capacity/order/activity/group parents serialize teardown. Payment facts are detached, not deleted. |
| Cancellation | `cancel_order_domain_internal_v1` -> ticket teardown + `enqueue_order_email`; single/bulk/legacy commands | State, history and automatic email intent commit together. Replays and overlapping cancellation requests produce one automatic notice. Manual resends and optional external invoice deletion remain separate. |
| Durable commands | `ClientCommandIdentity`, `ClientCommandTransport` | Supplied IDs survive retry. Frozen content, original revisions and backend/actor binding are persisted before dispatch. Exact compare-and-clear prevents a late acknowledgement deleting another intent; unresolved payment intents and tombstones remain stored. |
| Ticket appearance | Existing occasion command; `TicketLayoutSaver` -> `DbOccasions.updateTicketLayout` | Original occasion revision, unit-editor permission and narrow appearance/layout merging preserve unrelated features. This path does not perform form/reminder setup. Minimal authorized layout reads omit buyer/hold data. |
| Forms / blueprints | `update_form_internal_v1`, `update_blueprint_internal_v1` through their commands; `DbForms` | Late JSON rejections roll back domain writes. Seat IDs, products, form attachment, holds and allocations are checked under parents. Draft versions remain original until an authoritative save succeeds. Explicit deletion and omission semantics survive. |
| Form lifecycle | Existing create/duplicate owners; `delete_form_domain_command_internal_v1`; typed form adapter | Authoring creation is atomically closed. Modern deletion requires the original revision and recovers its receipt after deletion. Another form keeps a shared empty product type. Ordinary duplication remains a distinct operation with its existing copy policy. |
| Products / contexts | `update_product_internal_v1` + shared context owner; `delete_product_domain_command_internal_v1`; product grid and blueprint dialogs | Configuration and submitted contexts save atomically. Shared product/type revisions detect competing form edits and scheduled changes. Readers, immutable snapshots and current delete calls carry original revisions. Blueprint dialogs save only their supported basic fields. |
| Group members | `write_user_group_members_internal_v1` shared by full save and additive command; Users UI | Additions preserve existing members/admins and advance the group revision. Imported replacements remain a separate intent. Current group/member/place DML was removed and fenced. |
| Price wave + target | `save_product_wave_target_client_sync_v1` over existing wave resolution/target validation | One durable inline-create action; failed target validation rolls back creation/adoption. Standalone wave operations remain separate. |
| Inventory pools/resources | Private pool reconciliation -> pool command; resource/delete commands are sole DML owners; typed inventory adapter | Old public shapes delegate. Moves lock both pools in one order and reconcile both sides. Resource changes advance the parent pool revision. Sold/held/context/slot dependencies prevent destructive capacity changes and deletion. |
| Spot assignments / swaps | `update_spot_assignments_internal_v1`, `swap_spot_tickets_internal_v1`; typed spot/ticket callers | Parent and spot locks, resource/slot/context scope, original assignment checks and active-hold guards are shared. Assignments, buyer holds, ticket swaps and checkout remain distinct operations. |
| Cleaning | Private report/resolve/mute/block helpers -> receipted commands; `DbCleaning` | No facade recursion. Abuse admission, duplicate/blocked-reporter behavior, role asymmetry and one push intent remain. Helpers are private. |
| Activity publication | Existing publish command and exact `_consume_autosave` control; `DbActivities` | Publication consumes only the selected actor's draft row/time under the aggregate lock. Newer drafts survive. Explicit draft deletion remains separate. Direct two-call publication is fenced. |
| Exclusive groups / news | Explicit save/delete/publish/read commands; `DbEvents`, `DbNews` | Group/link replacement and news/read-pointer DML were removed. Original reader revisions and direct-DML fences are present. News notification stays a durable outbox intent. |
| Profiles / memberships | Save/create/ensure/import/delete commands; `DbUsers` | Failed creation rolls back account and membership. Global identity changes invalidate every affected occasion projection under the shared profile parent; legacy unit account updates reject foreign-organization IDs. Companion-owner invalidation occurs inside receipt ownership, once on replay. Teardown clears group leadership and activity assignments through the existing shared helper. |
| Speakers / counseling / events | Event and speaker commands; shared `delete_events_domain_internal_v1`; typed adapters | Speaker changes share the event revision. Event deletion invalidates surviving children and exclusive groups. Empty-slot deletion shares teardown, rechecks bookings after waiting and preserves booked-slot metadata. Legacy speaker selection delegates. |
| Units / occasions | Existing scoped commands and private owners; unit/occasion adapters | Original editor revisions and role boundaries remain. Service/game/banner writes advance the configuration revision they can invalidate. Occasion blueprint attachment advances the form revision. Occasion deletion can recover completed/expired receipts after the row disappears. |
| Information / maps / icons | Scoped information, map and unit-icon commands; current typed adapters | Valid unit information/quotes are supported; unit games are rejected. Private group locations use group-before-place locks, invalidate the group revision and carry original place revisions in both readers. Shared historical organization icons remain read-only; references block owned deletion. |
| Companion lifecycle / feedback / program | Existing explicit self/admin, actor-kind, attendance and saved-program commands | Self-created deletion retains its account/ownership restriction and receipt recovery; admin unassignment never becomes account deletion. Feedback preserves anonymous proof versus user identity. Saved-program outbox/coordinator/freshness logic stays intact. |

The source manifest assembles 221 authored files into one deterministic forward
migration. The database integration lane compares **every assembled function
body** with the effective catalog, including overloads, and checks trusted
search paths. The source lane checks one authored owner per selected identity.

## Concurrency, versions and receipt boundaries

- Product and shared type baselines are captured when the editor/catalog loads.
  Form drafts retain them through edits and explicit deletion. Scheduled product
  changes and scheduled form opening advance the same configuration revisions.
  A fresh read immediately before submission is not used to rebase a draft.
- Modern product/form deletion has a required-version, three-argument shape.
  Its private owner also serves the released two-argument shape without changing
  that shape's existing request hash. Modern `NULL` versions are rejected.
- Lock order follows the actual dependencies: forms/orders before products and
  inventory pools; both pools before a moved resource; group before private
  place; event parents before dependent links. Parent sets are rechecked after
  waiting. A newly committed order/link parent produces SQLSTATE `40001` before
  mutation, without a terminal receipt; retry uses the same command ID.
- Real allocation, the anonymous reservation RPC, resource movement/deletion,
  product/form competition, private group-place competition, event-link
  phantoms and an in-flight counseling booking are covered by controlled
  multi-connection tests. Held secrets never appear in rejection payloads.
- Result recovery checks actor, scope, operation, normalized request and current
  authorization before returning a stored response. Tests cover deleted orders,
  occasions, forms, products, blueprint sources, inventory references, attendance
  targets and owned companions, including expired tombstones and revocation.
- Operational form `capacity_revision` is distinct from authoring configuration.
  Unit quote rotation changes a non-submitted feature cache; scanner rotation
  changes its separate credential/epoch relationship. Neither is routed through
  a broad configuration save or treated as an alternate editor writer.

## Removal and compatibility policy

Current mutation routing no longer depends on the selected read projection.
Product grid's second context RPC, its legacy selectors, direct group/member/
place/news/link replacement, broad publication draft deletion and automatic
post-cancellation client email requests were removed.

Public compatibility signatures remain only as adapters to the owner. They serve
released Flutter clients and existing external boundaries; remove them only
when installed-client and unresolved-intent inventory proves no supported caller
remains. This includes scalar product/form/blueprint/pool/resource/group/map
shapes and legacy cancellation/deletion/email boundaries. Former raw CSV/ticket
import bodies, the old three-argument profile writer, obsolete scheduled-change
entrypoint and the unused invoker schedule-maintenance routine are fenced from
ordinary application roles, including service execution where applicable.
Historical migrations remain unchanged.

Direct application DML is fenced for the migrated configuration, inventory,
profile, group, program, news, map, information and icon paths. Trusted definer
owners retain access. These ACL changes are **pre-activation client-upgrade
gates**, not permission to apply them against installed clients without review.

Original-baseline compatibility remains deliberately bounded:

- Existing form/blueprint/product JSON commands can still accept missing legacy
  controls, and old context arrays/deletion overloads retain their hashes.
- Pool/resource and other legacy adapters can obtain a current locked revision;
  they cannot reconstruct an original editor baseline.
- Therefore these legacy-reachable families are **not enabled for MCP writes**.
  Activation requires enforcing modern controls and closing every applicable
  unversioned facade/overload for the tool's executor role. Merely upgrading the
  current UI or publishing a modern signature is insufficient.
- Existing unresolved invoice intents bound only to an actor remain stored and
  fail closed until their original backend is established explicitly.

No new dispatcher, application trigger, idempotency store or business server was
introduced. W03/W05, the other W/S workflows and R01-R07 retain their sequence
review dispositions. A new remote orchestrator and optional read consolidation
are not unfinished requirements of this backend execution.

## CW01-CW24 closure matrix

“Local” below means source, current callers, removal/fence and targeted proof.
It does not mean production activation or blanket MCP readiness.

| Slice | Local closure | Remaining activation condition |
|---|---|---|
| CW01 | Group save/delete/add, imports and private-place revision coupling; DML fenced. | Upgrade old DML/facade clients. |
| CW02 | Versioned exclusive replacement/delete and read; DML fenced. | Selected client/ACL rollout. |
| CW03 | Receipted publication with exact chosen-draft consumption; two-call writer fenced. | Upgrade two-call clients first. |
| CW04 | News save/publish/delete/read acknowledgement and outbox; DML fenced. | Existing notification worker remains external. |
| CW05 | Profile create/save/ensure/import/delete, shared identity version fanout and one-time companion effects. | Keep unit-account intent separate; upgrade legacy shapes. |
| CW06 | Private pool/context owner, versioned reads, parent/link checks and allocation proof. | Close unversioned baseline adapters before MCP. |
| CW07 | One resource command DML owner; deterministic move/capacity locks, parent revisions and both-pool reconciliation. | Same legacy baseline gate. |
| CW08 | Sold/held/context/resource-slot deletion guards and common reconciliation. | Same legacy baseline gate. |
| CW09 | Typed closed creation and original-version deletion, including post-delete replay. | Retire released create/delete shapes after inventory. |
| CW10 | Form/blueprint rollback, ownership, original child baselines, copy owner, shared-writer versions and DML fence. | Enforce original controls for legacy-reachable JSON routes before MCP. |
| CW11 | Atomic product/context save, immutable current snapshots, scheduled versions and versioned deletion. | Same gate for legacy JSON/array/deletion shapes. |
| CW12 | Authored assignment/swap owners, parent/seat locks, scope/hold/replay proof and thin facades. | Preserve swap/hold/checkout as separate intents. |
| CW13 | Full speaker owner, locked legacy patch adapters and event-speaker revision invalidation. | Installed-client compatibility inventory. |
| CW14 | Shared slot/event teardown, occupied-slot recheck and private helpers. | Existing counseling feature/role policy remains. |
| CW15 | Report command, private domain owner and one push intent. | Existing push delivery remains external. |
| CW16 | Resolve/mute/block commands and role asymmetry; private helpers. | Selected-client rollout. |
| CW17 | Manager unit save, versioned readers, locked legacy shape and banner invalidation; creation/delete stay separate. | Upgrade legacy configuration callers. |
| CW18 | Authored occasion lifecycle, narrow layout, service/game/banner versions, form attachment and deletion receipt recovery. | No media/provider workflow collapse; selected-tenant rollout only. |
| CW19 | Unit information/quotes plus scoped occasion deletion; unit games rejected. | Upgrade old DML clients. |
| CW20 | Map command owners, original reader revisions, protected group places, group/place conflicts and role parity. | Upgrade legacy location/DML clients. |
| CW21 | Unit icon ownership, reference guards, read-only historic assets and original receipt scope. | Upgrade old icon DML callers. |
| CW22 | Scoped self-create/owned-delete and distinct assign/unassign; technical-account deletion guards and replay. | Preserve self/admin origin and current capability checks. |
| CW23 | Anonymous/signed feedback and editor moderation through canonical commands. | Browser client identity remains a scoped capability, not a user. |
| CW24 | Event/attendance/saved-program/delete owners, link/version impacts, source parity and current caller cutover. | Keep offline outbox/coordinator and freshness semantics. |

There is no unexplained selected CW writer or outstanding selected local cutover
in this matrix. MCP exposure and production activation remain separate gates.

## Verification and limits

Exact commands, logs and source hashes are in
[the verification receipt](backend-refactor-verification-2026-10-20.json).

- Fresh baseline `20260805230000` plus all forward migrations passed on the final
  SQL inputs. Reapplying the actual forward assembly preserves consumed Auth
  budgets and completed mutation receipts.
- Final discovery found and passed **62 SQL suites**. The **26-test** DB integration lane
  covers every assembled catalog body plus controlled multi-connection races.
- **18** source/assembly/Edge-coverage/inventory checks pass. Current inventory
  records 352 RPC names, 33 Edge entries and 30 explicitly unresolved source call
  sites; these are inventory candidates, not claimed deployed writers.
- Final client command/form/product/group/map batch: **18 Flutter tests** pass.
  Core product snapshot/scheduling: **8 tests** pass. Targeted analysis of 11
  changed Dart files has no errors/warnings and 13 existing info-level lints.
  Earlier unaffected client batches and **28 Deno tests** remain recorded.
  Edge Auth/REST/provider boundaries are mocked; SQL permissions and effects are
  exercised against real PostgreSQL. No Flutter build or production release ran.

The three broader validation blockers were repaired in the local-only follow-up.
The scanner shared root passes **357 tests** against occasion-defined field IDs.
The client-sync SQL contract recognizes the exact closed-action, service-only
waitlist boundary and checks the current private owners for search-path and
occasion lifecycle protections. The source-fingerprint fixture is now generated
from the effective baseline and forward SQL, retaining all **56** original
identities while covering all **290** foundation definitions. It checks **302**
current bodies and **23** absent obsolete identities; catalog assertions pass.
The updated source lane passes **19** checks, including **6** generator regression
cases. No runtime SQL, migration or grant was changed by these repairs. A full
repository release suite was not run or claimed.

The [release preparation](backend-refactor-release-preparation-2026-10-20.md)
now records migration/client ordering, shared-database ACL impact, legacy and
pending-intent policies, and a read-only scoped preflight. Its local report and
four invalid-target rejection cases pass. Server evidence deliberately does not
claim completeness for installed clients or offline device intents.

Production still requires a clean canonical revision, installed-client and
pending-intent inventory, approved ACL/migration ordering, an explicitly selected
tenant release and ordinary-user/live-version verification. None ran here.
