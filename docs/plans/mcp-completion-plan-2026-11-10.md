# Complete general MCP client interoperability and write verification

Date: 2026-11-10
Status: Implemented and verified locally; production source/migration pending
Verification: standard (OAuth, authorization and public contracts)

## Outcome and evidence

The November 10 browser-only test connected official Inspector 2.14.0 to the
deployed MCP endpoint, created hidden occasion 1072645 and closed form 625,
saved fields and an existing-field update, verified administration after reload,
then revoked its connection. The local receipt is
`/Users/miakh/Downloads/festapp-mcp-ui-20261110/result.json`.

The first failures were a missing Inspector registration and an attempt to use
the Codex callback. Inspector's web callback is fixed at
`<origin>/oauth/callback`; the issuer correctly rejected a different registered
path. A separate native registration corrected the live configuration without
changing the server image or public ChatGPT client. This proves that journey,
not exhaustive MCP certification. Replay, stale-version rejection and a narrow
grant's isolation remained untested in the browser.

Canonical implementation starts from origin/main 4038713b9 in the isolated
`/Users/miakh/source/festapp-mcp-completion` worktree. Other working trees and
uncommitted email work are outside this change.

## Scope and architecture

1. One client-policy module owns registration lookup, data profile, optional scope ceiling
   and redirect validation. Static clients and trusted native metadata clients
   use that same policy during consent, token refresh, invocation and management.
2. Add opt-in Client ID Metadata Documents (CIMD), supported by the pinned
   oidc-provider SDK. Configuration explicitly chooses trusted HTTPS origins,
   optional scope ceiling and explicit data profile. General clients default to
   the complete implemented catalog; only public native clients with literal
   loopback HTTP callbacks are admitted. Disabled configurations remain static.
3. Fix the reproduced partial-consent loop by recording declined scopes through the provider Grant API, shared by both consent entry points. The standalone consent must visibly list and explicitly submit requested functional permissions.
4. Add a reproducible Inspector configuration command derived from existing
   operation-to-scope definitions, and safe errors for registration/callback
   problems. Do not print OAuth parameters, codes, tokens or upstream details.
5. Close the confirmed inventory-assignment parity gap with bounded spot/slot reads and a delegated facade over the existing UI command.
6. Complete automated contract checks and the missing live browser scenarios.

MCP and the existing Make adapter remain transport adapters over `Operations`;
those adapters call existing canonical Supabase RPC/command owners. SQL owns
live business authorization, transactions, versions and command receipts.
Browser/native clients use ordinary actor sessions; OAuth narrows that actor's
authority. A future HTTP API must reuse these contracts and owners rather than
introduce parallel business rules, tables, service-role writes or idempotency
stores. No speculative API framework is introduced here.

## Decisions and constraints

- CIMD uses the maintained provider's validation, caching, bounded HTTP fetches,
  PKCE, exact callbacks and issuer binding. Do not implement another OAuth stack.
- Trust is explicit and fail-closed. Metadata outside approved origins is not
  fetched; metadata cannot choose its own Festapp data profile or scope ceiling.
  Removing trust must invalidate already issued access as static policy removal
  does. Static registrations always take precedence.
- Public ChatGPT stays order-summary and read-only. Existing registrations and
  grants do not gain permissions from this work. Dynamic registration stays off.
- Remote web CIMD clients are excluded: their redirect/CSP and browser-completion
  policy requires a separate coherent design. Native metadata clients address
  the observed desktop/CLI/Inspector integration seam.
- Business operations and live authorization tests remain UI-only through
  Panerelay. Source/unit/HTTP fixture checks are local development validation,
  not substitutes for the live UI acceptance.
- A forward SQL migration is required for the inventory delegation/read adapters and is tested only on the owned disposable database. No production migration, Supabase restart, production source deployment, push or publication is part of this task. The already applied
  Inspector registration is retained. Production activation of the new opt-in
  CIMD setting requires its own normal release and trusted-origin choice.

## Implementation waves

### 1. Consolidate client policy and add native CIMD

First fix `completeConsent`: declined scopes are final decisions using `Grant.rejectOIDCScope` and `Grant.rejectResourceScope`, not reasons to restart login. Add translated functional checkboxes to standalone consent, using the existing translation owner. Then update `tools/festapp/src/remote/config.mjs`, introduce
`remote/client-policy.mjs`, and migrate all policy lookups in `server.mjs`,
`delegation.mjs`, `tenant-bridge.mjs` and `management.mjs`. Enable the provider's
CIMD feature only for explicit configuration. Reuse redirect validation for
static clients and metadata clients. Reject web clients, shared secrets,
unsupported grants, foreign scopes and untrusted origins. Keep provider fetch
separate from authenticated Supabase fetch.

Validation: real HTTP/OAuth fixture tests in `test/remote.test.mjs` cover
discovery, metadata fetch/validation, full PKCE consent and MCP invocation,
refresh, removal of trust, identity mismatch, callback and scope rejection.
Exit: all entry points use one policy; static behavior remains covered.

### 2. Make supported setup reproducible and failures actionable

Add a non-mutating Inspector setup command to `remote/main.mjs` backed by a
small configuration function. Derive scopes from named existing operations,
validate the exact UI origin, and emit both issuer registration and Inspector
configuration. Never change live configuration from this command. Return
bounded, static guidance for unknown clients and callback mismatch on OAuth
error pages, without echoing untrusted request details.

Update the existing operator README and remote authorization documentation with
the actual endpoint, separate public/native client capabilities, Inspector
callback, CIMD trust model and canonical future-API seam. Remove conflicting
claims that the entire server is a read-only pilot.

Validation: contract tests for emitted configuration and OAuth error outcomes;
existing static-client tests and generated reference checks remain green.

### 3. Complete stock-assignment administration parity

The existing 109-action UI inventory maps every occasion action except stock spot assignment to the implemented 193-tool catalog. Account connection/Google login are account UI operations, outside occasion administration. Add `inventory.spots.list`, `inventory.slots.list` and `inventory.assignments.save` with existing inventory read/write scopes. Bound SQL reads to ID pages without customer or hold secrets. The write facade pins organization/occasion/optional organizer, locks/rechecks stored resource bindings and delegates to `update_spot_assignments_client_sync_v1` with the same UUID and existing receipt. No new allocator, receipt store or UI writer is introduced. Preserve replay after entity deletion by using the existing receipt's stored occasion, never a caller-invented binding. Freeze only the new canonical SQL in a forward migration, update the source contract and existing capability inventory. Test actual SQL through the same Operations adapter, including UI/MCP same-receipt replay, cross-occasion rejection, stale original assignment, batch rollback, paging and secret omission.

### 4. Close acceptance and record honest evidence

Through Inspector UI, edit the existing test form once, replay the exact same
command UUID/payload, and prove no duplicated field or version bump. Submit a
new command using the stale pre-edit version and verify conflict plus unchanged
saved content. Reload the actual administration editor. Reconnect with only
form-read permission and occasion-only consent; confirm writes are absent and
cross-scope inspection is denied while permitted inspection still succeeds.
Revoke only task grants and clear their OAuth state.

Add focused automated adapter cases where missing for form conflict and
same-command retry semantics. Include new tests in the existing canonical
MCP CI contract, without adding a second suite definition. Run affected normal
targeted checks once on final source; run `server-policy` before any later source
publication. Store sanitized live results in a dated operational receipt.

## Deletion ledger

| Existing artifact | Action | Proof |
|---|---|---|
| Scattered client lookup and ceiling decisions | Replace with shared policy | Scoped search plus static/CIMD HTTP tests |
| Generic OAuth failure text as the sole diagnosis | Retain generic fallback; add classified guidance | Actual provider error tests, no parameter echo |
| Read-only-pilot claims applied to all MCP clients | Correct in existing documentation | One authoritative setup and architecture explanation |
| Temporary Inspector grants and OAuth copies | Revoke/clear through UI | Post-revoke reauthorization requirement |

## Completion and residual risks

Done means the policy and setup code is implemented, security/contract tests pass,
live replay/conflict/isolation/readback cases have concrete outcomes, and the
result distinguishes deployed static-client verification from locally verified
opt-in CIMD support. Do not claim CIMD is live or every MCP requirement is
certified. Metadata trust origins are an operator decision and remain explicit.


## Execution result

All four waves are implemented in the isolated worktree. The canonical MCP
contract passed 124 Node, 51 web and 15 Deno tests. Four actual PostgreSQL
adapter tests and both selected SQL regression files passed, with no skips.
The browser-only continuation proved same-command replay, stale-version
rejection, event isolation and administration reload; all Inspector test grants were
revoked. The live Inspector registration now has no artificial scope ceiling.
See [sanitized execution receipt](../operations/mcp-completion-2026-11-10.json)
and [implementation result](mcp-completion-RESULT-2026-11-10.md).

### Subsequent production release ordering

Production source deployment remains separate from local implementation. After
normal canonical publication/release gates, apply the additive SQL migration
before publishing the updated standalone MCP image. Preserve the protected
configuration, issuer, profiles, encryption keys and original client policies.
The image must include the canonical Czech translation JSON used by standalone
consent. First retain static registrations; enable native CIMD only after an
operator chooses trusted metadata origins and an explicit profile. General
operator policy has no default functional ceiling. Existing grants never widen.
Rollback may restore the preceding MCP image and disable metadata advertising;
the additive SQL facades can remain without creating a competing domain owner.
Do not restart Supabase or Functions for this standalone server update.


## Authorized deployment continuation (2026-11-10)

The user explicitly requested deployment followed by a more sophisticated
browser-only test. This supersedes the earlier local-only scope. Preserve main's
required pull request and one approving review, all affected canonical local
mirror lanes, and required GitHub CI on the exact canonical deployed source.
Only the regional standalone MCP server and its additive SQL migration are in
scope; there is no tenant web/Flutter production build or public-plugin change.

Pre-publication hardening reproduced a same-command UI/MCP deadlock. The scoped
wrapper must call the original receipt owner before taking parent binding locks,
then lock/recheck bindings even on replay. Those post-replay locks must not
introduce a printed-content mutation prohibition, because replay performs no
mutation. A real three-connection parent barrier exercises both ordinary commands;
the old order fails and the corrected order yields one receipt and assignment.

After release, use the official Inspector through Panerelay in Testovací
organizace. Create a hidden two-day dance event, edit and duplicate closed forms,
then create an accommodation pool with two contexts and rooms of capacity two
and one. Exercise generated physical spots, assignments, same-command replay,
over-capacity all-or-nothing rejection and actual administration reload.
Finally request more scopes than approved and confirm the deployed partial-
consent fix completes a restricted read connection without looping. Revoke only
test grants and retain hidden/closed fixtures for inspection. No checkout,
payment, customer messaging or public publication is part of this acceptance.


The standalone form parser budget includes the existing resource/device budget
plus all functional scope choices. A real OAuth fixture with 100 maximum-range
occasion IDs and every functional permission previously returned HTTP 400 and
now completes a narrowed token without creation rights. This preserves the
supported resource limit rather than imposing an accidental function limit.
