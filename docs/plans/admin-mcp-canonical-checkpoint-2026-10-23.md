# Execution checkpoint - admin UI/MCP

Base: GitHub origin/main `4cfc9b7bc66f48c2d6e42155f08e905dde112d0d`.
Workspace: `/private/tmp/festapp-admin-mcp-canonical-20261023`.
Main dirty checkout untouched. Verification: standard.

## Stage 0 - locally complete

Migration: `20261023160000_product_catalog_keyset.sql`.
SHA-256: `f13603e3ae3a76f94d7212d237e21171875b7abdeb5774e275d1e4dc4e07f5fa`.
Source owners: `get_product_catalog_data_internal`, `get_product_catalog`,
`get_product_catalog_page`; released-client adapter `get_products_and_types_for_edit`.
Callers: Flutter `DbEshop.getProductsAndTypes` keeps full bundle; MCP
`invokeProductOperation` now requests server pages. No write/receipt change.
Removed: Node full catalog sorting/filtering/slicing and per-product link scans.

Evidence: `docs/reports/admin-data-network-keyset-2026-10-23.json` includes actual
executor output sizes and inner SELECT EXPLAIN ANALYZE, all audit DDL/data rolled back.
3 product PostgreSQL tests and 14 remote HTTP/OAuth/consent tests passed, 0 skipped.
Canonical SQL source parity generator check and catalog generation passed (94 actions / 15 remote tools). Concurrent fixture is committed
only inside the marked, mail-fenced disposable DB, then explicitly cleaned up.
No new index: page reduces correlated subplan loops from 1000 to 50.
No production writes, no build/deploy, no publication yet.

## Stage 0B - administration meaning, locally complete

User explicitly requested the operational administration view, including useful
relations and aggregate semantics. See `docs/architecture/product-admin-read-contract.md`.
SQL purchased_count now owns paid+sent totals; current UI consumes it and retains
counts during edits. MCP exposes form IDs/titles and stock pool names/type/date,
with no public form links. Three independent count scans became one lateral
aggregate; forms/inventory joins cannot multiply the counts.
Migration `20261023163000_product_admin_read_semantics.sql` SHA-256:
`a61747a53d860161f1e3d0cf451f3a794cd9d0eac8ba38fc5814e5980935fa11`.
Tests: 3 real SQL tests, 0 skipped, include 2 paid tickets in one order, sent and
storno relationships, duplicate form fields and 2 inventory assignments; actual
MCP executor returns purchased_count=3, ordered_count=4. 4 Flutter grid tests
passed, including preservation of canonical counts through local edits/copyWith.
Evidence: `admin-data-network-admin-view-2026-10-23.json`; previous files retained.
Publication/deployment still pending; no production writes.

## Stage 1 - locally complete

Owners/callers:
- UI DbEshop -> SupabaseProductScheduleCommands -> manage_product_schedule.
- MCP product_schedules.list/change -> get_product_schedule/manage_product_schedule.
- Shared wave matrix projection: get_product_price_waves_internal, consumed by
  the full administration catalog and bounded schedule list.
- save_target delegates to the existing target receipt with no outer receipt.
  ensure/move/cancel and standalone price save/cancel each have one domain receipt.
- Existing raw wave/price functions retain their actual rules. Current UI raw
  calls removed; occasion_setup/finalize.sql still uses create/target inside its
  own existing transaction. Published old clients retain compatibility RPCs.
  Removal gate: last supported client upgraded plus SQL caller migration.

Conflicts are receipted 409 outcomes; true 40001/40P01 remain retryable with the
same identity. Failure after new term creation rolls back term/adoption/targets.
Scheduler prelocks due products by ID to eliminate time-order inversion against
wave move. Target edit preserves separate price/visibility revisions and explicit
null/false semantics. Setup draft new target uses one onChanged, not create+save.
No historical purchased prices, payments, ticket lifecycle or email effects change.

Migration: `20261023170000_product_schedule_commands.sql` (digest and exact request/
byte evidence in `docs/reports/admin-product-schedule-evidence-2026-10-23.json`).
Verification: all 87 MCP tests passed with real DB, 0 skipped; final targeted
10 schedule SQL tests passed, including 6 canonical regressions, actual
checkout/history/payment price preservation, sync-failure rollback and source
parity for 8 changed owners. 18 scheduling/setup Flutter tests passed; final
13 setup/transport tests passed after adding the atomic draft test; 29 consent
web tests passed. Targeted Dart analysis: no errors/warnings, 10 existing style
infos. New test registered in eshop_unit_cases for the shared client runner.

Disposable fixture corrections: regression tests run as their intended postgres
role with service JWT for scheduler probes; checkout fixture now supplies the
canonical form/blueprint/seat binding and hold expiration, like the supported
checkout tests. The disposable DB has unrelated older `_swap_spots_update_ticket`
body drift, so runtime source checks are limited to the 8 affected owners;
authored-vs-effective whole-repository generator check still passes. No readiness
hash regenerated. No production writes, no publication or release yet.

## Exact next steps

1. Publish verified stages 0/0B/1 to fresh authoritative main; reconcile any
   intervening commits and rerun only affected checks.
2. Delegate routine frozen-source festapptickets release: target/org/activation,
   backup and atomic SQL+ledger, consent web build/direct deployment, then issuer
   image using the same MCP registry. Preserve known rollback images and probe
   exact live SQL/ACL, issuer health and coherent tenant version/build/legal.
3. Continue stage 2: replace BlueprintStandingInventory.prepare's three writes
   and _pool/_resource/_linked memory with one durable domain transaction, first
   reusing the internal owners behind inventory pool/resource/product commands.
   Preserve actual existing-order allocations; inspect the relevant inventory
   administration RPCs and table meaning before extending MCP.


## Publication / stage 2 start

Stages 0/0B/1 are published in PR https://github.com/festappnet/festapp/pull/564,
frozen head `aa2a191e5f82bcfbbaf8f556d8087a1136202762`, refreshed base
`9eef213f2b664b2b7f4978f51b43a90535ab7c8a` (only organization entry guard
changed upstream; no overlap with tested owners). Main currently requires one
approving review. No administrative bypass or production deployment performed.
Stage 2 continues on `feat/admin-mcp-standing-20261023`, stacked on that frozen head.

Delegated read-only release preflight verified canonical activation generation 1,
organization 3 and matching host/runtime/database assertions. Legacy names contain
rehearsal but are the actual canonical production target documented in the current
admin-dashboard guide; names alone are not a mismatch. Current tenant build is
0.20.365+860. MCP issuer is healthy at the prior 4cfc9b7 image. Candidate SQL
versions are absent from the live ledger. Private operational details and exact
commands are in `/tmp/festapp-admin-mcp-release-preflight-20261023.md`.

Stage 2A boundary before implementation:
- prepare_standing_inventory: existing product ID/version, actual occasion,
  organization/unit selection, capacity 0-1000000, immutable command ID.
- Existing owners: update_inventory_pool_bundle_internal_v1, resource rules
  extracted from save_resource_client_sync_v1 into one internal domain function,
  update_product_inventory_contexts_internal_v1 and apply_allocations.
- One outer receipt and one sync publication; no nested pool/resource/link
  receipt calls. Locks: receipt -> sorted existing order dependencies -> product
  -> newly created pool/context/resource/spots -> existing allocator reentry.
- UI BlueprintStandingInventory.prepare and setup dialog switch to one typed
  durable RPC; remove _pool/_resource/_linked/_capacity partial-success state and
  post-save catalog reload. Return authoritative product (including occasion,
  type, new aggregate version), new pool/context/resource snapshots/versions.
- Relevant UI read RPCs inventoried: get_inventory_pools_by_occasion_link,
  get_inventory_pool_bundle, get_resources_for_inventory_pool_v1. Their existing
  stock/allocation semantics remain owners for follow-on inventory read cuts;
  raw spots/hold secrets are not a general MCP read DTO.
- Targeted final batch: real PostgreSQL atomic rollback after pool/resource,
  lost-response replay and single receipt, version conflict and competing
  preparations via two connections, existing sold-item/addressed-seat allocation
  preservation and insufficient capacity. Resource command regressions, targeted
  standing adapter/dialog tests. No full suite after each edit.
- Follow-on read issue found: page-related types/contexts omit unused editor
  choices, including a type with no products. Supply a separate bounded choices
  read through the same projections before declaring full product authoring
  coverage; do not restore full-catalog transfer as a workaround.


## Stage 2A - locally complete

One `prepare_standing_inventory` transaction/receipt now creates pool, context,
resource and the existing product assignment. Shared mutation owners extracted:
`save_inventory_pool_internal` and `save_inventory_resource_internal`. Existing
pool full-editor snapshot and resource receipt APIs delegate to those rules.
Standing avoids constructing the unused full pool-editor bundle, and returns
one authoritative product/pool/context/resource snapshot (including product
occasion/type/version and existing form references). Sync publishes once to the
union of existing pool/resource/assignment audiences.

Removed `lib/components/blueprint/blueprint_standing_inventory.dart`, its
_pool/_resource/_linked partial-success memory, preparedCapacity state, retained
partial-operation text/getter, and setup dialog's post-command catalog reload.
Current UI `SupabaseInventoryCommands.prepareStanding` and MCP
`inventory.prepare_standing` use the same RPC. A separate explicit standing
consent never expands existing product-edit grants.

Final validation: 7 real PostgreSQL tests, no skips, including injected failures
after pool and resource, insufficient-capacity terminal rejection, authoritative
versions, existing paid item/addressed blueprint seat preservation, two-connection
competing command conflict and overlapping same-UUID replay, 3 existing inventory
regressions and source parity/ACL for 5 owners. 34 Flutter inventory/blueprint
checks, 15 remote and 30 consent tests passed. Targeted Dart analysis has no
errors/warnings (4 existing informational style/deprecation diagnostics).
Exact source digest and actual request/JSON-byte measurements:
`docs/reports/admin-standing-inventory-evidence-2026-10-23.json`.

Still local on stacked standing branch. PR #564 was updated independently to
head 6b7ce25f973aafb7b75e981077ee517e93df1cfc after the scoped deploy-gate test
correction and merge of main's unrelated public-link change (14a2f091f).
Review/merge is still required before production release; no live mutation ran.

Next: bounded inventory administration reads using the RPC behind actual stock
cards, including per-context physical/allocated/unassigned counts; then typed
pool/resource save/delete adapters. Preserve published client RPC boundaries.
Also close the unused product-type/context editor-choice gap with a bounded read,
not a whole catalog transfer. Operational seat cut 2B remains pending.
## PR publication and deployment gate

Published stages 0/0B/1 as PR https://github.com/festappnet/festapp/pull/564
against refreshed authoritative main `9eef213f2b664b2b7f4978f51b43a90535ab7c8a`.
One approving review is required by current GitHub branch protection; it is not
bypassed. No production changes or release have run. Delegated read-only
preflight confirmed canonical tenant activation generation 1 and organization 3,
matching host/runtime/database assertions, healthy previous MCP image and
absence of candidate versions from the live SQL ledger.

CI image, seat-checkout and ticket-preview/delivery gates passed. Web-startup's
static deployment test looked for the image fallback literally in cloudflare_build.sh,
although that script now inlines the canonical public_page_seo.js. The guard now
checks the shared source plus its actual build wiring. The corrected
`bash automation/tests/deploy_workflow.test.sh` passed locally. Runtime source
and the 87-test MCP result are unchanged by this test-only correction.

Stage 2A is now locally validated on feat/admin-mcp-standing-20261023. Its
completed source is being integrated with the frozen PR fixes; further inventory
reads and operational seat commands remain separate pending cuts.
Release remains gated on an approved, merged authoritative main revision.


## Inventory read cut - boundary before implementation

Frozen completed bundle is PR #564 head c6dea8392c6f56be2993447b970a28e46b9467b5;
new work is isolated on feat/admin-mcp-inventory-read-20261023.
Actual UI source: get_inventory_pools_by_occasion_link -> InventoryPoolsListBundle
-> InventoryPoolsTab/InventoryPoolCard. Pool detail's selector uses only pool IDs
and the actual occasion. Resource editing uses its separate existing resource RPC.

UI card meanings: physical spots per context; allocated spots (OPT not null);
unassigned allocated spots (resource null); saved sellable ceiling. These are
slot allocations, not unique people/orders. Introduce shared SQL facts before
projecting pool/context rows, so joining resources and contexts cannot multiply
counts. Active holds are a separate disjoint count, never exposed as secrets.
No new independent checkout-availability/revenue formula is introduced.

Current UI will explicitly request complete summary mode; MCP gets bounded ID
pages for pools and context rows. No raw spot list in either current adapter.
Keep the released get_inventory_pools_by_occasion_link response shape and its
existing permissions/spot fields as a documented compatibility boundary, reusing
shared metadata projections; no new MCP access to that payload. New scoped
reader uses live typed can_read_orders plus actual org/unit/occasion, including
pool binding under lock. General pool/resource mutations follow after this
read cut; editor options for unused product types/contexts remain a known next gap.

Verification batch: actual old/current UI/MCP results on the same 100/1000-slot
fixtures, bytes/entity counts, null/empty contexts, duplicate child joins,
no secret/OPT leakage, bounded pages/foreign pool and ordinary role matrix;
context-card and navigation widget contracts, source parity and catalog generation.

## Inventory summary read cut - complete locally

Shared SQL administration projection now supplies current UI stock cards and two
bounded MCP readers (pool/context ID pages, max 100). Complete summary mode is
explicit UI intent and includes no spot rows. Physical/allocated/unassigned/held
counts are per context; independent resource/context aggregation prevents child
multiplication, including slot-only resource assignments. Cards use each own
context's physical count and the pool's actual resource supply. Saved sellable
capacity is retained as its separate ceiling. No duplicate client spot counting.

New explicit inventory read consent is required in both grant and OAuth token;
old product/standing scopes gain no new access. Scope and live rights rechecked
before return for inventory, product and wave reads. Context pages lock the
actual pool. Released legacy full inventory RPC retains old response fields and
its original permission gate; current UI no longer consumes its raw spot array.

Final verification: 40 targeted PostgreSQL/MCP/remote tests PASS, zero skips,
including 4 new inventory tests, actual two-connection revocation during each of
five reads and a concurrent pool move, keysets, invalid modes/limits, role matrix,
source parity for 10 read owners and regression receipts/retry/allocation tests.
Consent UI: 24 PASS. Czech card/catalog group: 42 PASS in ordinary and reversed
fixture order. Navigation behavior cases passed. Targeted Dart analysis has no
errors or warnings (6 existing informational notices). No production fixtures.

Final immutable evidence admin-inventory-summary-network-2026-10-23.json:
100 spots: previous UI 13647 B -> current summary 668 B;
1000 spots: previous UI 127947 B -> summary 672 B.
MCP pool+context SQL responses total 789/791 B in two domain requests, projected
DTOs 628/630 B. These are actual serialized SQL/DTO bytes, excluding HTTP/auth.
Inner SQL plan retained; small local fixture uses a single spot scan, no speculative
index. Preliminary admin-inventory-read-network report remains historical evidence.

Next: finish scoped pool/resource read/save/delete adapters using InventoryCommands
and extracted existing mutation owners; add bounded unused type/context choices
for product editing. Operational seat cut 2B and stages 3-10 remain pending.
PR #564 still requires one approving review; no production migrations/deployments
have run. Frozen PR ticket text test was corrected to distinguish ordinary clipping
from intentional adaptive full occasion titles, and current client-contract CI passed.
## Client CI contract correction

Current canonical ticket text fitting (introduced by ef3005e22) intentionally
shrinks occasionTitle below its preferred minimum to preserve the full title.
The inherited long-text regression incorrectly expected title truncation.
It now tests ellipsis on the ordinary orderName binding and separately proves
that an occasion title stays complete, within its box, below the preferred
minimum. Both focused Flutter cases passed. No renderer, font metrics, PDF
readiness contract or readiness hash was changed.

## Pool/resource authoring cut - current boundary

Starting from frozen read candidate 709d47c5 on a separate authoring branch.
Existing InventoryCommands use four receipt owners. Preserve those receipts,
locks, expected versions, sold/held guards and sync publication. A scoped common
manage_inventory RPC will delegate to exactly one owner, with a final live scope
check including replay; no outer receipt. Pool save's receipt implementation is
extracted unchanged into one private owner with explicit editor/compact snapshots
so MCP does not build or transfer unrelated full resource/place/product bundles.
Authoring pool reads must include complete replacement context settings (bounded
by the existing 2000-context save limit, fail above it), resource reads use bounded
ID pages. Do not expose slot/customer/hold data. Retain old public RPC identities
for released clients. Test untitled pool deletion: current owner mistakes NULL
title for absence and therefore silently leaves an existing untitled pool intact.

## Pool/resource authoring cut - completed locally

UI InventoryCommands and MCP now call scoped manage_inventory. Each action
(save/delete pool/resource) delegates exactly one existing receipt owner, then
checks actual entity and live tenant/unit/occasion rights again, including replay.
Pool receipt implementation extracted into one private command owner; old public
identity delegates to it. Editor mode preserves the historical hash and full
snapshot. Compact mode has its own hash discriminator, avoids full editor SQL
and private replacement hydration. Sync publication still advances normal source
revisions. MCP SQL responses exclude private sync replacements and unused resource
fields. No nested receipts or separate commits.

Shared pool/context and resource projection owners serve the current scoped full
UI editor and compact MCP reads. Complete pool settings refuse >2000 contexts or
>1 MiB instead of truncation; resource settings select bounded IDs before projection,
with max 100 and 1 MiB ceiling. Full editor boundary remains intact. Old bare-ID
public editor API retains its response, now locks its pool and rechecks read rights.
Untitled pool deletion fixed: check NOT FOUND rather than NULL title.

Verification: full MCP suite 105 PASS/0 skips before the final shared-read
refinement; final affected PostgreSQL batch 17 PASS/0 skips. Six final authoring
cases include pre-extraction deployed-migration receipts replaying unchanged,
full UI field compatibility, 125-resource pages, 2001-context refusal versus full
UI read, held-allocation guards, untitled deletion, actual two-connection scope
move rolling back state/version/commit/receipt, and 13 owner source assertions.
Read revocation test now exercises eight actual SQL APIs. Existing sold/addressed
seat and resource-safety regressions pass. Inventory command Flutter cases: 6 PASS.
Targeted commands/tests analysis: no issues. Consent UI: 25 PASS.
Final DbInventoryPools scoped-read adapter awaits current-head client CI compilation;
a different session owns the workstation's single Flutter slot, so no concurrent
Flutter task was started. Previous read candidate 709d47c5 passed all 7 CI gates.

Evidence admin-inventory-authoring-evidence-2026-10-23.json records the exact SQL
digest, limits and test boundaries. A real sample returns 567 B for compact pool
create and 19688 B for full UI save on the same fixture; different outcomes, so no
before/after reduction or HTTP/latency claim. No production writes/deployment.

Next: bounded unused product type/context editor choices, then operational seat
cut 2B and stages 3-10. Main review/merge is still required before production.

## Product authoring options - completed locally

Correction to the earlier gap assessment: SQL full editor mode already returned
all types and inventory contexts (p_limit IS NULL), including unused choices.
The missing capability was MCP discovery after product pages became related-only,
especially an empty catalog. UI does not need another request or a replacement
choice-loading mechanism. Its complete metadata and bounded product page metadata
now share two internal projections with the new bounded choice endpoint.

get_product_catalog_options / products.options selects either product types or
inventory contexts by ID before projection, max 100 plus one lookahead, max 1 MiB.
Context choices contain actual pool title/type/date; no context data, spots,
customer/form access data or sales aggregate. New explicit product-options consent
requires product-read; existing issued product grants gain no new operation.
Late live scope/rights checks apply to both choice kinds. Actual product occasion
now participates in catalog selection as well as its type occasion, preventing
malformed legacy cross-occasion rows from being exposed through a local type.

Targeted final batch: 27 PostgreSQL/MCP/remote tests PASS, 0 skips, and 26 consent
UI tests PASS. Added 125 unused types and 125 unused contexts over an empty product
catalog, with 1000 physical spots: three independent 50/50/25 pages each, matching
full UI metadata and no private context data. Replacing the full catalog owner with
a failing dependency still permits choice pages. A >1 MiB type title rejects even
a one-row page. Invalid kind/null/limit/cursor, actual org/unit scope, private ACL
and four owner source assertions pass. Actual two-connection revocation now covers
both choice kinds in addition to the eight preceding read paths.
Full final current-source MCP batch: 109 PASS, 0 failures, 0 skips (58.1 s),
including real PostgreSQL, CLI modern/legacy SDK interoperability and issuer auth.

Authoring candidate cb8baafe2 client-contract and navigation-interactions CI passed,
covering the final scoped DbInventoryPools adapter without a concurrent local
Flutter task. No production changes or deployment have run. All owned source still
requires main review/merge; next engineering cut is operational seats 2B, starting
with inspection and block/unblock through the canonical blueprint aggregate owner.
Stages 3-10 remain pending; no claim of full-plan completion.

## Publication refresh after final verification

Authoritative main advanced to 671a83f7692316e5b2da5e1989e5d4ba790d55a0
(PR #567, stronger shared SEO fallback regression guards). Inspected both changed
test files, merged main, and retained its stricter deploy_workflow.test.sh rather
than the subsumed candidate assertion. The affected shell/embedded SEO gate passed.
No domain/runtime code changed; the 109-test MCP result remains applicable.
Final current UI adapter already passed cb8baafe2 client/navigation CI. Production
remains blocked by required approving review and final-head release gates; no
review bypass or production write. Worktree remains separate from the dirty user
checkout. Exact next cut: operational seats 2B inspection + block/unblock, with
shared selection-unit expansion, original revision, blueprint save owner, and
checkout/hold/sold/concurrent-retry tests. Do not start by directly updating flags.

## Operational seat cut 2B - first slice in progress

Starting from published 2aa1e7de with 109 MCP tests and all seven CI gates passed.
UI setBlockedForSeats expands the document's complete selection unit and rejects
any protected member, retaining changes in the draft until Save. Backend save
previously checked changed seats individually but did not enforce complete block
selection units. Add the missing check at that existing aggregate owner; retain
UI draft/Save/Cancel. MCP uses existing checkout selection-unit expansion, previews
all affected spot IDs and requires that exact set plus the original layout revision.
Block has one new receipt over the existing non-receipted canonical save owner;
no nested receipt and no direct flag UPDATE. Reuse its exact financial/spot lock
sequence in a private helper. Shared lifecycle SQL feeds UI and bounded inspection;
MCP never receives hold secrets or order/customer identifiers. Production review
remains a release gate, not a reason to pause the independent implementation.

User-visible report mirror (standing requirement from this turn): after EACH
completed/verified cut regenerate the capability JSON/HTML, then atomically copy
both to /private/tmp/festapp-mcp-recovery-20261022/docs/reports/ under their same
admin-capabilities-2026-10-23 names. The former recovery checkout had disappeared;
restored the requested static artifact and missing linked supporting documents.
That path is now the user's report preview, not an implementation checkout. Keep
it on the last VERIFIED cut and distinguish implementation from actual deployment.

## Operational seats 2B - first slice locally verified

Added bounded seat inspection, complete-selection preview and block/unblock with
original revision + exact confirmed expanded spot IDs. One new receipt delegates
to the existing canonical non-receipted aggregate save; its helper is still the
only flag mutation owner. UI retains draft/Save/Cancel, now backed by complete-unit
server validation as well as existing client checks. Shared lifecycle facts feed
both UI and MCP; metadata excludes reservation/customer/order identifiers. Shared
financial/spot lock ordering retained. Set-based membership/change joins avoid
correlated repeated JSON scans. Limits 100 requested/1000 expanded/100 per page,
1 MiB read/preview; no silent truncation. New explicit seat-read/block scopes.

Seven final PostgreSQL cases PASS: actual two-connection checkout versus block in
both directions, revocation during preview, used ticket/order preservation, partial
confirmation/full-editor half-unit rejection, unchanged geometry, receipt replay,
foreign scope/ACL and 12 source owner assertions, existing layout/auth regressions.
Consent UI 27 PASS; remote seat consent passed. Workstation Flutter slot belongs
to another session; no new local Flutter task. Existing controller draft/undo/unit
coverage is unchanged and will be covered by the normal client CI.

The prior disposable DB disappeared during work. Canonical prepare-local.sh
safely recreated only the marked cron/mail-fenced authz project from all migrations.
Full MCP suite on this fresh schema: 113 PASS, 4 FAIL, 0 skips. Reproduced those
same four cases on frozen parent 2aa1e7de, independently of the new seat slice:
(1) authorization reference omits Stripe unit feature field; (2) pre-cutover ACL
snapshot predates later Stripe tables/column and SEO/unit-reader grant changes;
(3) validate_ticket_layout(jsonb) differs from the readiness seal, which correctly
hides ticket-layout writes; (4) order-test migration installer incorrectly assumes
postgres owns every function. No readiness hash or permission gate was overridden.
These are unresolved overall validation issues, not green full-suite evidence.
Exact evidence: admin-seat-block-evidence-2026-10-23.json. Fresh seed's explicit
organization id19 caused one sequence collision while progressing naturally;
no sequence was reset. All seven seat tests then passed on final source.

User report HTML/JSON now mirrors 27 implemented tools on the EXACT requested
recovery path. It shows progress and pending deployment per changed operation;
first 2B slice is verified locally, not production-deployed. Mirror its new linked
seat evidence when refreshing. Next cut: release temporary holds with explicit
expanded-selection preview; then swaps, seat orders and ticket cancellations.
Continue independent implementation while required GitHub review gates release.

Publication base refresh: inspected and merged main 01ed297d0 (organizer media and
capture/encoding tooling only). It changes no seat/domain owner; existing targeted
verification remains valid. The four fresh-schema failures reproduced on frozen
parent are confirmed, not assumed. Do not overwrite or weaken ticket readiness
for a green test. Their follow-up remains part of overall completion, separate
from the locally passing first seat slice. User-facing report now links this
explicit evidence and the pending-deployment state.

## 2B hold release - boundary before implementation

Current UI filters selected temporary holds again after confirmation and invokes
an unversioned receipt. To avoid clearing a different buyer's newly acquired hold
between preview/confirmation or during retry, bind the new UI/MCP intent to an
opaque snapshot of the exact reservation state as well as full expanded IDs and
layout revision. Hashes never expose checkout secrets; compare under canonical
occasion/spot locks after receipt replay handling. Replay must return the original
outcome even if a new buyer subsequently holds those seats. Extract the old
release receipt into one private owner; retain its public legacy adapter/hash.
New current UI previews before confirmation and must not silently refilter afterward.
Order-editor rights govern release independently of blueprint-editor block rights.

User clarification: `client_sync_v1` is not a request to reintroduce the old
Cloudflare diff-cache path. It is an overloaded historical name covering the
existing DB mutation receipts, audit/revision publication and optional client
projection activation. New MCP writes call Supabase RPC directly; no sync feature
flag is enabled and no Cloudflare worker/cache transport is introduced. Preserve
canonical receipts and already-owned publication compatibility, but do not make
domain success depend on external cache delivery. Explain the command/receipt
boundary separately from cache terminology in future progress notes.

Hold UI validation: first short Flutter window compiled all changed code; two
port/model cases passed, one existing UI workspace assertion did not yet see the
new async preview dialog. Its actual Supabase mock/JSON decode crosses native
async scheduling; the case now uses the existing suite's runAsync handoff before
assertions and records that preview completes before confirmation. Await the
coordinator's next explicit Flutter slot before rerun/analyze; their archive and
production tenant build take precedence. No Flutter task is currently owned here.
Use applyConfirmedReplacements for this new UI receipt boundary so optional cache
repair cannot turn confirmed DB success into an apparent release failure.


Hold release targeted final Node batch: 31 PASS, 0 skips (11 actual PostgreSQL
cases plus remote transport/consent cases). Expanded source parity covers all
17 seat/hold owners. New negative case proves complete confirmation, actual unit
scope, used-ticket protection with paid order unchanged, and helper/public ACL.
Consent UI 28 PASS; RPC extraction regression 1 PASS; generated SQL contract and
git diff whitespace checks pass. First invocation safely failed the disposable
DB guard because its second explicit URL was omitted; rerun supplied both local
URLs and verified the marked, email/cron-fenced fixture. No production SQL ran.
Flutter UI rerun still awaits coordinator slot; the cut remains unverified as a
whole and is not published or marked complete in the capability report.


Hold cut additional actual two-connection test PASS: a checkout transaction clears
buyer A and acquires buyer B; the administrative release demonstrably waits on
that transaction, then rejects BLUEPRINT_HOLDS_CHANGED without touching buyer B.
All 12 targeted PG cases PASS. Flutter rerun: two model/transport PASS, UI preview
HTTP request count is 1 (not 0), but confirmation has not rendered at assertion.
The fixture now explicitly advances fake-async work before real HTTP continuations
and awaits the dialog with the suite's existing bounded condition-driven pattern;
assertion includes rendered text to distinguish a domain/decoding error from
scheduling. Not yet rerun. Targeted Dart analyze: 0 errors/warnings, 24 brace-style
infos. Coordinator owns the slot again for archive/integration/release work.

## Next 2B swap boundary - focused reconnaissance

Current UI preview is DbForms.previewBlueprintSwap -> preview_blueprint_swap,
which executes swap_spot_tickets_internal_v1 inside a rolled-back subtransaction.
It returns actual before/after order amounts plus seat/ticket/customer facts.
Commit currently re-reads controller.selectedSpotIds after confirmation and calls
TicketCommands.swapSpots -> swap_spot_tickets_client_sync_v1. Thus the next cut
must freeze original source/target and expanded atomic units, and bind the actual
assignment and money effects shown to the editor, not merely layout revision.
Do not copy price maths to MCP or introduce a second receipt. Preserve released
adapter hash/replay via one extracted owner, as in the hold cut. Preserve actual
order-capacity/product locking, used-ticket rejection, currency rules and Stripe
price immutability from the existing swap domain owner. MCP needs no customer
email/name in its default projection. Existing finance_integration_test.sql covers
paid delta, currency and used companions and should accompany new scoped tests.
Before implementing, resolve the current hold UI check; keep PR564 frozen3513
and do not include unpublished2300 in the coordinator's current release.


UI diagnosis resolved the preview failure: new mock response omitted request,
which the real PostgREST parser dereferences. Added request exactly as existing
pickerRead fixture. Dialog, expanded companion/count and Cancel assertions now
pass. Next execution reaches the existing durable journal, but this formerly
read-only workspace fixture lacks path_provider. Reused LocalAppStorageFixture
in suite setup/teardown to own a real disposable journal. Pending rerun, no
production code workaround or transport bypass. Slot returned to tenant release.
Report now explicitly marks this action Probíhá ověření, alongside 29 registered
operations, without claiming completion/deployment; exact requested HTML mirrored.


With a real journal installed, confirm reached a pending Sembast write in the
widget fake-async zone rather than an HTTP call. The test now starts the actual
button taps inside tester.runAsync and advances virtual time while awaiting UI
continuations, keeping real I/O out of fake timers. Previous failing test process
was explicitly stopped (only owned Flutter/tool tester PIDs) to return the slot.
Latest change awaits the next slot; do not claim the UI write passed yet.


Independent inherited-fixture fixes while production build owns Flutter:
- Truth-table now explicitly asserts the approved Stripe default feature flag,
  then compares the remainder with the unchanged historical context reference.
  Actual 2048 role combinations PASS; no permission assertion was removed.
- Orders setup no longer recreates supabase_admin-owned functions as a different
  non-owner postgres role. Read-only protected production check verified all four
  relevant queue/command owners are postgres on canonical org3. Fixture now sets
  only the eight exact2330 signatures to that production owner within its rolled-
  back transaction before reinstalling; queue requires_service_role is unchanged.
  Complete orders MCP scenario PASS (including queued email and idempotent replay).
  Thus the intermediate local42501 was an ownership-fixture mismatch, not evidence
  of a live production bug. All email/cron fences remain on; no mail is delivered.
Other two older full-suite failures (ACL historical snapshot and real PDF validator
seal mismatch) remain open. Do not call the whole suite passing or override seals.
Coordinator merged integrated PR569 incl frozen3513 to main d97835e798e48f17047de4b438a2db6b9e0f8a9c;
current hold2300 and these fixture fixes are excluded from that production release.
No main publication until coordinator completes rollout; rebase next cut afterward.


Historical ACL test fixed from reviewed migration contracts, not a fresh snapshot:
- Exact pre-cutover ACL JSON remains untouched. All old column grants are still
  compared exactly; schema/default/role/member comparisons remain unchanged.
- Only thirteen explicitly named Stripe tables from221600/221700 are allowed as
  additions, and every table/column grant must be postgres-only. Additional API
  column grants on these tables or an unexpected table still fail.
- Only payment_info.payment_method/stripe_connection_id additions may inherit
  their existing table's exact column privilege pattern.
- get_unit_edit_data (212300) and get_occasion_seo_data (222255) are verified to
  have only their documented PUBLIC/anon revocations, including full grant rows.
Targeted historical ACL plus effective direct-write-bypass tests: 2 PASS. This
resolves the third inherited fixture/expectation failure without loosening actual
runtime permissions. Fresh full MCP batch on main d978+nextcut is now running;
PDF validator readiness drift remains a real known failure, no seal regeneration.


## 2B hold release - coherent slice verified

Actual reservation workspace now PASS: first preview shows every companion and
count, Escape sends no release, second confirmation sends exact original IDs/hash
although local overlay changes, real durable journal completes and refreshed UI
has no command error. Root-zone real I/O and completed cancellation are awaited
explicitly; no production transport seam or bypass was introduced. Two immutable
model/transport cases also PASS. Final targeted Dart analyze 0 errors/0 warnings,
27 brace-style infos. Full MCP on canonical main d978+nextcut:123 tests, 122 PASS,
1 FAIL, 0 skips. Sole remaining failure is known PDF readiness mismatch. Frozen
prior release not modified, no new migration/deploy executed. Report 29 registered
operations is updated, hold cut locally verified/pending publication. Next: same
confirmed financial effects boundary for swaps. Current branch
feat/admin-mcp-seat-holds-main-20261023, source40b135831 plus final fixture/docs
updates; await preceding production rollout before publishing this next cut.


## Next 2B swap - SQL owner implemented, UI/MCP cut still open

Verified hold slice is frozen separately at546d37f90 on
feat/admin-mcp-seat-holds-main-20261023. New uncommitted swap work is isolated on
feat/admin-mcp-confirmed-swap-20261023; never publish it as the finished hold cut.

Financial rules/locks moved once from retired private swap_spot_tickets_internal_v1
into apply_blueprint_seat_swap_internal. Existing pair/price maths remain untouched;
the applier captures before facts and actual after effects while holding the same
financial/spot locks. Preview rolls the real apply back; confirmed receipt applies
it once inside a rollback scope and persists only when its actual effects match
the approved hash, expanded IDs and layout revision. Superseded private owner is
explicitly dropped, source contract records retirement. Legacy public receipt is
one thin adapter with original hash and replay. New scoped SQL preview/command
are written; Node registration, UI, grant, contention/ACL tests and report stage
completion remain outstanding. Migration2330 has NOT run on production.

Six targeted PG cases PASS: existing layout/authorization/finance regressions,
actual paid delta100->150 with preview rollback and replay, changed destination
price/incomplete confirmation rollback without history/money effects, pre-upgrade
receipt replay. Inspection found an intentional existing distinction: UI and
financial owner allow used singleton swaps, but reject used atomic-unit members.
Preserve this existing policy; a ticket becoming used after preview invalidates
that consent. Shared lifecycle projection shows current state before approval.
Do not silently invent a new blanket used-ticket prohibition. Actual two-connection
contention and permission loss must still be added for this new swap boundary.


## 2B confirmed seat swap - final SQL/MCP batch verified, final UI gate pending

Current source: feat/admin-mcp-confirmed-swap-20261023, parent546d37f90.
Authoritative origin/main fetched: ee0287419 (ticket-delivery changes use2310;
no swap helper/financial owner overlap; translation additions require merging).
Migration2330 is NOT deployed. Hold PR571 head0c1431d9 has six green CI checks
but remains review-gated and engineering-stopped until the preview identity fix
is included in a newly validated source. Earlier bundle is deployed as
festapptickets0.20.367+864, tenant8a390d70/main d97835e.

One aggregate apply_blueprint_seat_swap_internal owns actual price/order updates,
full atomic groups, lifecycle and semantic money projection. Preview executes it
inside rollback. Confirmed command validates original hash/IDs/revision inside
an effect rollback scope, then finalizes the existing inventory.spots.swap receipt.
Old public adapters preserve fingerprints/replay. Both superseded private swap
owners are dropped; the two-argument private lock helper is only a thin arity
adapter to the single canonical parent-graph implementation. Existing financial
calculation helpers remain unchanged. Missing order header money rejects the new
quote/confirmed write, never defaults to zero or commits before typed decoding.

Final real disposable PostgreSQL MCP batch:135 tests,134 PASS,1 known PDF readiness
FAIL,0 skips. Seat suite23 PASS including three inherited blueprint SQL regressions.
Source parity28 owners, helper ACL, legacy pre-upgrade receipts, checkout and role
revocation, actual used-ticket race, foreign parent rejection and four-seat
second-member rollback all PASS. Actual form/order-before-blueprint deadlock
regression reproduced RED (57014), then GREEN after aggregate lock correction.
Measured four-seat preview parent-graph calls3->1, pair applications2; no latency
claim. Actual serialized SQL JSON preview653/write530/replay530 bytes (no HTTP/TLS).

UI uses immutable complete preview and displays affected seats/products/tickets,
customer facts only in authorized editor mode, and actual per-order price changes.
MCP omits customer facts. Dedicated seats:swap consent requires seats:read and
orders:read. Normal path is one preview RPC and one write RPC. Uncertain durable
write is resumed with original UUID/payload before a new preview; expired recovery
retains the original intent. Changed local selection cannot alter approved input.
Preview discards a response after actor identity changes (RED/GREEN verified).
Three final recovery/identity port cases PASS; prior actual workspace UI PASS.
Final workspace UI rerun after identity guard awaits the shared Flutter slot.
No Cloudflare diff-cache flag/transport has been enabled.

Protected production read-only scope audit:4182 org3 spots on canonical layouts,
zero occasion/product/product-type/order/ticket parent mismatches; no IDs or PII
returned. No production fixture or new migration was executed.

Next: final short UI/analyzer gate when workstation slot is released, freeze
source, update PR571 with exact validated scope/revision and preserve required
review. Rebase onto current authoritative main and rerun affected checks before
publication. Then continue seat-order creation and ticket cancellation (2B),
followed by stages3-10. This is not completion of the whole plan.
