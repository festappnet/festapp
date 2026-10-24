# Shared Festapp operations for CLI and local MCP

This is the **read-bootstrap child design for phases 2-3** of the authoritative
[canonical-operations plan](festapp-canonical-operations-plan-2026-10-20.md).
Follow the parent E0-E6 dependency schedule: prove the selected contract and
refactor affected operations before exposing their writes. Completing every
phase-1 domain is not a prerequisite for independent read/design previews. Write-refactor
exclusions and separate-follow-up notes below describe this child phase only;
the parent now includes cancellation/deletion/Auth canonicalization in phase 1.
Parent phase 2 maps to this document's contract phase and waves 1-2; parent
phase 3 uses waves 3-4. These are work packages, not a requirement to finish
all four readers/CLI commands before stdio or ticket design. Hosted access has its own concrete
[phase-4 plan](festapp-remote-mcp-plan-2026-10-20.md). CLI is a thin internal
execution/diagnostic adapter; local MCP is the first AI-facing deliverable.

Date: 2026-10-20  
Status: Proposed implementation plan; architecture deepened after user feedback; implementation not requested yet  
Verification: standard for implementation (authentication, tenant isolation and new API contracts)  
Evidence: working tree at HEAD `eb2304724`, including existing uncommitted work

The required [ticketing-write child](festapp-ticketing-mcp-plan-2026-10-20.md)
extends this bootstrap with blueprint/form/product/layout authoring and issued-
ticket operations. Exclusions below apply to this first read milestone only.
Completion of four read tools is not completion of the overall MCP scope.

## Outcome and scope

An internal operator can inspect one selected tenant's events, reports and
orders through `festapp`, or through equivalent local MCP tools. Both interfaces
call the same application-operation functions and return the same structured
data. Existing PostgreSQL/RPC and Edge Function boundaries retain business rules.

This includes a bounded review and improvement of the selected SQL/RPC contracts,
not just a wrapper around every existing entrypoint. It is not a wholesale
migration of Flutter or the public web client. The first deliverable is read-only with respect to event, order, payment
and email data. Authentication creates/refreshes/revokes sessions as expected.
Implement shared context/handlers with minimal CLI setup and stdio together
in E0; complete the reader/CLI surface incrementally by E5.

Excluded from this implementation: remote/public MCP, customer OAuth clients,
public package publication, event creation/duplication, reservations, payment
changes, email sends, ticket/PDF exports, arbitrary SQL/RPC tools, infrastructure
commands, and automatic migration of operational scripts. These are future work,
not incomplete requirements of the first deliverable.

## Current-state evidence

| Fact | Evidence | Design consequence |
|---|---|---|
| SQL owns permissions, order/payment transitions and capacity; Edge Functions own specific orchestration. | `docs/architecture/ai_context.md`; `docs/backend/edge_functions.md` | Share invocation and contracts, not a second implementation of business rules. |
| An authenticated, tenant-scoped report already exists with typed report data and server-formatted text. | `database/functions/eshop/get_report_ws.sql`: `get_report_ws`; `database/tests/get_report_tenant_scope_test.sql` | Use this as the first end-to-end operation. Preserve its definitions and currency separation. |
| Existing order overview retrieves event-wide collections. | `database/functions/eshop_orders/get_orders.sql`: `get_orders`; `get_orders_tab_data.sql` | A CLI single-order lookup must not fetch an entire event and filter locally. |
| Email status is available through permission-checked readers, separate from send endpoints. | `database/functions/emails/email_reporting.sql`: `get_order_email_summaries`, `get_order_email_summary` | Reuse status semantics; do not expose the private queue tables or provider credentials. |
| Public event listing is a public discovery projection, not an operator's event inventory. | `database/functions/others/get_public_occasions.sql` | Add a bounded authenticated listing rather than presenting the public catalog as all accessible events. |
| An edit reader explicitly resolves organization and permissions; other readers have different contracts. | `database/functions/others/get_occasion_for_edit_v1.sql`; `get_occasion_by_link.sql` | Expose selected operations, not every existing RPC by name. |
| Password login uses Supabase sessions; external login checks resulting user and organization. | `lib/data_services/auth_service.dart`; `web_client/src/services/auth_service.js` | Use normal user sessions, and verify organization before any domain read. No service-role credentials. |
| Production identity comes from canonical activation and configured tenant identity. | `docs/architecture/ai_context.md`; `automation/project.conf`; `web_client/src/services/backend_activation_service.js` | Resolve a pinned tenant profile and fail closed on mismatch; do not copy the web client's legacy fallback behavior. |
| JavaScript ESM, the Supabase JS client and Node's native test runner are established here. | `web_client/package.json`; `automation/lib/supabase_client_config.mjs` | A small independent Node ESM package fits existing tooling without Flutter builds. |

Repository files are evidence of source behavior, not proof of deployment or
current live data. The working tree contains extensive unrelated work. Do not
revert, commit or include that work as part of this task.

## Target architecture

### Existing API and where sharing belongs

Festapp already has an HTTP API: Supabase's PostgREST exposes database reads and
RPC, alongside Edge Function endpoints. A separately maintained REST/GraphQL
server is not required to add CLI or MCP. Calling an RPC is an API call, not a
direct database connection. See the official
[Data REST API](https://supabase.com/docs/guides/api) and
[Functions as RPC](https://docs.postgrest.org/en/v16/references/api/functions.html)
documentation. Local inspection confirms both RPC and Edge Function consumers.

There are two distinct types of sharing:

1. The authoritative cross-client operation contract lives in the backend.
   Flutter, web, CLI and MCP can all call it, using language-specific adapters.
   Authorization, transactionality, domain outcomes, durable receipts and
   mandatory side effects belong here. This is the important common interface.
2. A small Node library shares invocation/schema/formatting work between CLI and
   local MCP. It is a convenience for these two callers, not the new source of
   business authority, and Flutter need not embed or call a Node runtime.

Improve an existing domain contract when it is incomplete. Add a focused reader
when an existing projection has a different purpose. Do not create a second
family of backend functions named after `operations`, `cli` or `mcp` for every
existing domain function. Keep individual typed entrypoints; do not introduce
`execute_operation(name, json)` as a universal privileged dispatcher.

```text
Flutter / web adapters     CLI / MCP adapters
          |                shared Node invocation library
          |                          |
          +------ existing Supabase HTTP interface ------+
                                     |
              domain SQL/RPC + selected Edge orchestration
                permissions / receipts / effects / projections
```

### Concrete consolidation opportunities found

| Observation in current source | Recommended architecture | Scope / confidence |
|---|---|---|
| `get_orders` returns `{code,data}`, `get_orders_tab_data` returns the data directly and raises on failure; other writers return void/SQL exceptions or JSON codes. | Document stable success/error semantics for the selected domain operations; preserve old contracts until their callers move. Use explicit adapters for existing shapes, not a new global envelope migration. | Confirmed response-shape differences. Establish contracts now, migrate incrementally. |
| `ClientCommandResponse` already defines `status`, `code`, `data`, `sync.replacements`; `ClientCommandTransport` adds a command ID and retains it during transport retries. | Reuse this command/receipt model for future writes. The CLI/MCP presentation envelope must not become a competing backend mutation protocol. Keep synchronization metadata optional for non-UI callers, not a reason to fork the domain command. | Confirmed in `packages/festapp_core/lib/src/sync/client_command_response.dart` and `lib/data_services/client_sync/client_command_transport.dart`. |
| `DbOrders.stornoOrder` commits cancellation and then calls `sendStornoTicketOrderEmail`; the traced single-order SQL path does not enqueue that notification. Bulk cancellation already enqueues a cancellation email inside its SQL transaction. | If cancellation includes a notification by product policy, make the canonical cancellation command own the durable intent atomically. Keep manual re-send a separate explicit operation. All clients then call one complete command. | Confirmed source flow, not a live incident. Product semantics, variants and existing dedupe keys must be traced before a separate write refactor. |
| `delete_order_client_sync_v1(bigint,uuid)` has two source definitions: one in `eshop_orders/delete_order.sql`, another in `eshop_orders/delete_order_client_sync_v1.sql`; lock/admission steps differ. Two migration assemblers consume different definitions. | Establish one canonical authored definition and have future assemblers use it, preserving the union of required invariants and lock order. Do not let file application order choose behavior. | Confirmed source divergence in `automation/assemble-form-capacity-waitlist-migration.py` and `automation/assemble-abuse-migration.py`. Deployed winner and all release dependencies are unverified; separate high-risk repair before exposing deletion. |
| Event duplication commits SQL, then `DbOccasions.duplicateOccasion` copies media client-side; its existing code explicitly handles committed-with-media-failure. | A future cross-client duplicate operation needs resumable media orchestration with a durable result. An Edge Function may own that workflow; adding a new API server would not itself solve it. | Confirmed hybrid flow in `lib/components/occasion/db_occasions.dart` and `occasion_media_copier.dart`. Deferred, not necessary for readers. |
| The web catalog calls `get_available_occasions`, which intentionally includes public external events; `get_public_occasions` has another public projection. | Keep public discovery distinct from authenticated ticketing inventory. Consolidate genuinely duplicated internal query fragments only after comparing their visibility/product requirements. | Confirmed. Similar names are not proof that endpoints should merge. |

These findings correct the initial assumption that existing backend entrypoints
can always be treated as complete operations. Existing command modules are a
useful foundation, but the completeness of each operation must be established
before exposing it to another caller. There is no need to fix the entire backend
as a prerequisite for read-only CLI/MCP.

### Package implementation

Create `tools/festapp/` as one private npm package with a lockfile and a
`festapp` bin. Use ESM JavaScript with JSDoc; do not introduce a monorepo framework
or a build service. Suggested ownership:

- `src/operations/`: operation descriptors, input/output schemas and handlers.
- `src/backend/`: explicit allowlisted RPC mappings and response normalization.
- `src/context/`: trusted profiles, activation verification and authenticated identity.
- `src/auth/`: interactive login and protected credential/session lifecycle.
- `src/cli/`: argument parsing, human rendering, JSON output and exit codes.
- `src/mcp/`: SDK registration, schema adaptation and protocol rendering only.
- `test/`: boundary and adapter behavior tests; `README.md`: local installation,
  login, selected profile, examples and recovery.

The adapters import handlers in-process. MCP must not shell out to the CLI or
parse its human output. Handlers must not depend on terminal, MCP, UI globals or
browser storage. Keep the small catalog explicit; do not build plugins, dynamic
dispatch of arbitrary backend names or a generic workflow engine.

## First operation contract

| Operation | CLI shape | Backend / result |
|---|---|---|
| `context.inspect` | `festapp context inspect --profile NAME` | Verify target and authenticated `user_info` organization; return non-secret identity and readiness. Not an infrastructure health dashboard. |
| `occasions.report` | `festapp occasions report --profile NAME --occasion LINK` | `get_report_ws(occasion_link)`; preserve server report and text. |
| `occasions.list` | `festapp occasions list --profile NAME [--cursor ID] [--limit N]` | New `public.list_ticketing_occasions`; minimal authorized event metadata, stable ID cursor, default 25 / maximum 100 rows. |
| `orders.inspect` | `festapp orders inspect --profile NAME --occasion LINK --order-id ID` | New `public.get_order_inspection`; one scoped order, persisted payment totals and bounded canonical email status. |

MCP names are `festapp_context_inspect`, `festapp_occasions_report`,
`festapp_occasions_list`, and `festapp_orders_inspect`. The MCP process is bound
to one profile at startup; tools cannot change destination, tenant or credentials.
CLI requires an explicit profile; there is no ambient production default.

The catalog owns stable operation IDs, descriptions, input/output JSON schemas,
and domain-read-only metadata. One validation path is used by CLI and MCP.
Reject unknown input fields. Keep schemas small and compatible with the selected
official MCP SDK; choose and lock its supported version at implementation time.

Normalize results as `{ok:true, operation, data, meta}` or
`{ok:false, operation, error:{code,message,retryable}, meta}`. Metadata includes
contract version, request ID, profile name, tenant/organization and read time,
but never credentials. Request IDs are correlation only, not durable receipts.
Use stable codes for invalid input, authentication required, forbidden,
not-found-or-inaccessible, target mismatch, timeout, unavailable and upstream
contract failure. Parse SQL/Edge domain codes even when HTTP status is 200.
Do not leak SQL exception text or sensitive backend details.

`--json` emits exactly one JSON result on stdout, including errors; human output
is presentation over that result. Diagnostics go to stderr. Suggested exit codes:
0 success, 2 invalid invocation, 3 authentication, 4 access/not-found, 5 target
mismatch, 6 backend/network/contract failure. MCP returns the same operation
payload as structured content, a short text rendering, and marks execution
errors according to its SDK; malformed protocol calls remain protocol errors.
MCP stdout contains only protocol traffic.

Represent bigint identifiers and decimal money as strings at the SQL JSON
boundary, before JavaScript can lose precision. Preserve currency and time basis
from the server. A report's free blueprint spots are not a promise of checkout
availability or capacity after temporary holds; do not rename/recalculate them.

Order inspection returns ID, symbol, state, timestamp, currency, stored amounts
and delivery summary. No contact fields, arbitrary form responses, hidden notes,
QR secrets, capability links, raw email bodies or transaction payloads. Reuse
canonical email-reporting semantics, but return only summary fields and a bounded
recent-message subset; do not forward its potentially growing `messages` array.
No single operation promises a consistent snapshot across separate RPC calls.
Keep the order projection in one database call where practical and label read time.

## Authentication and tenant boundary

1. A reviewed profile contains tenant ID, canonical backend HTTPS origin, public
   API key, organization ID, activation URL/generation/hash and profile identity.
   Generate/import it explicitly from selected tenant configuration; do not infer
   the tenant from `main`, `.env.local` or a historic cloud reference. Do not source
   a shell config or accept executable profile fields.
2. Validate activation against pinned profile expectations before sending user
   credentials or reading domain data. Manifest fields identify activation; they
   must not dynamically choose a token destination. Reject redirects to a different
   origin, unexpected generations and identity mismatches. No legacy fallback.
3. `festapp auth login --profile NAME` obtains a normal user session through the
   established Supabase password flow with hidden terminal input. Passwords,
   access tokens and refresh tokens must not be CLI arguments or tool inputs.
   Honor MFA requirements through the SDK; unsupported challenges fail explicitly
   without downgrade. Browser/Google/device-code login is deferred.
4. Initially support persistent sessions on this macOS workstation using Keychain
   through a maintained, bounded credential adapter. Store refresh credentials
   only there, namespaced by target/profile/user. No plaintext fallback, browser
   session copying, generated admin tokens, JWT signing keys or service-role use.
   If secure storage is unavailable, fail with actionable setup instructions.
5. Serialize session read/refresh/persist across CLI and long-running MCP processes
   for the same profile; reload saved refresh state within that lock, persist
   rotation before releasing it, and bound lock acquisition. Do not independently
   auto-refresh stale sessions in each process. SDK session settings must make
   this ownership explicit. Local logout removes only this tool's credentials
   and session; do not globally log the user out of the application.
6. Verify the user through the Auth service, then its organization through a
   user-scoped `user_info` read. Never authorize from decoded JWT claims alone.
   Each SQL operation also verifies authenticated tenant and event permission;
   process startup or `tools/list` is not continuing authorization.
7. Production profiles use canonical activation; a separately marked disposable
   local-test profile permits only the configured loopback fixture endpoints.
   Never retry against another project or enumerate other tenant branches.

The local tool cannot grant read-only credentials merely by labeling tools as
read-only: its user JWT retains the user's existing backend permissions. The
delivered surface invokes only approved readers. Strong delegated read-only
tokens and independently revocable client grants belong to the remote-MCP phase.

## Backend additions

Author the list reader under `database/functions/others/` and order inspection
under `database/functions/eshop_orders/`, with a scoped forward
migration under `supabase/migrations/`; use normal repository migration assembly
conventions. No new Edge Function or generic API proxy is necessary for this slice.

- `public.list_ticketing_occasions(p_organization bigint, p_before bigint DEFAULT
  NULL, p_limit integer DEFAULT 25)`: require organization equals authenticated
  `user_info.organization`; apply existing `get_is_editor_order_view_on_occasion`
  to every returned event. This intentionally lists ticketing-readable events,
  not every type of event membership. Return only ID, canonical link, title,
  start/end and unit ID, with pagination metadata. Stable descending ID keyset;
  reject invalid limits and cursors. No client-side tenant filtering.
- `public.get_order_inspection(p_organization bigint, p_occasion_link text,
  p_order_id bigint)`: check tenant, resolve the event in that tenant, require
  existing order-view permission, and select the order only inside that event.
  Use the same not-found-or-inaccessible result for missing and foreign objects.
  Project persisted amounts/state and canonical email summary, with bounds as
  specified above. Do not recompute payment allocation or read private queue
  tables using a new broad reporting privilege.
- Both are `SECURITY DEFINER` with `search_path = public, extensions`, explicit
  schema qualification, parameterized SQL, and execute grants only to intended
  authenticated callers. Revoke implicit PUBLIC/anon execution explicitly.

An existing read helper's acceptance of an occasion ID is not proof of tenant
isolation. The new outer readers must enforce both tenant and event scopes.

## Implementation waves

### 0. Freeze the selected backend contracts

Start with the maintained [internal operation catalog](../architecture/operations/README.md)
and its generated source inventory. Update those contracts as findings are
resolved instead of creating another independent list of operations.

Before each operation is registered, record its row in the small contract
matrix for the four selected operations: caller, SQL/Edge owner, input, projection, grants, domain
errors, transaction and effects. Check current readers and tests in the domains
already listed here; inspect applicable definitions/migrations, not every RPC in
the repository. Resolve whether an existing bounded reader can satisfy either
proposed new operation before adding it; preserve the listed semantics either way.

Record the existing mutation-envelope model as the future write contract. Keep
the cancellation, duplicate-definition and media-orchestration findings as
explicitly separate follow-ups; do not silently implement write/payment repairs
inside this read-only deliverable. For the parent phase-1 consolidation,
require a caller/grant/migration map and a replacement/deletion ledger before
changing public RPC behavior.

Validation: static inspection of the named SQL, direct callers, grants and
targeted tests. Exit: each initial operation has a single identified backend
owner or an explicitly justified new projection; no new generic API server or
tool-specific parallel domain facade is proposed.

### 1. Prove context/session infrastructure and the first handler

Create the private package, reviewed profile import, secure login/session owner,
operation contracts and `context.inspect` / `occasions.report`. Reuse existing
RPCs. Under E0, share context/session setup immediately with layout inspect/
preview and the stdio adapter; report completion can follow in E5. This reader
work package itself needs no backend migration. Keep profile provisioning separate from
tool input and inspect a selected tenant's config without checking out or
modifying tenant branches. Start with local fixtures, not production credentials.

Validate one meaningful batch with the package's Node tests: invalid activation
causes zero credential/domain calls; foreign organization and expired login are
rejected; concurrent processes serialize refresh; upstream domain errors with
HTTP 200 fail; bigint/money survive; CLI JSON and exit codes match the contract.
Add one local user-scoped report integration test through the actual API boundary.
Exit: a fixture operator obtains the same server report through one CLI command,
without browser state, privileged credentials or Flutter tooling.

### 2. Add bounded event and order readers

Add the two SQL readers and migration, then register `occasions.list` and
`orders.inspect`. Add `database/tests/operations/readers_test.sql` for authorized
reads, duplicate links in different organizations, foreign IDs, denied roles,
anonymous calls, pagination, response field restrictions and email summary bounds.
Use existing report/email fixtures and helpers rather than new status algorithms.

Validate via the documented runner against the disposable database:
`node web_client/scripts/run_db_tests.js database/tests/operations/readers_test.sql`
with an explicitly selected local `DATABASE_URL`; verify a nonzero selected test
count. Run the package's operation tests and local API integration for its new
readers. Migration must reproduce these readers in the local baseline/forward
migration setup. No production SQL is applied by this wave.
Exit: single-order inspection never downloads all orders; every returned event
and order is authorized by the database and belongs to the requested tenant.

### 3. Add the local MCP adapter over exactly those handlers

Implement `festapp mcp serve --profile NAME` using the official SDK and stdio.
For this bootstrap register the four domain readers as each is ready. The
ticketing child adds its separate approved layout/authoring tools starting in E0;
this four-reader specification is not a global tool ceiling. Expose no login, shell, SQL, arbitrary RPC
or profile-editing tools. Set accurate read-only annotations, but do not treat
annotations as authorization. MCP's profile is immutable for the process.

Validate via the official SDK client as a child process: list tools, call them,
reject extra fields/target overrides, preserve structured errors, avoid stdout
diagnostic pollution, and close cleanly. Compare CLI JSON and MCP structured
payloads under the same injected fixture clock/IDs; do not compare prose.
Exit: both adapters reach identical operation handlers and backend mappings.
Document local registration examples without editing the user's installed MCP
configuration or changing existing `mcp.json` servers automatically.

### 4. Package and record readiness

Document installation with `npm ci --prefix tools/festapp`, local invocation,
profile onboarding, login/logout, operation examples, output contracts, session
expiry, target mismatch and migration/release prerequisites. Integrate the new
test lane into the explicit automation list in `automation/test_all.sh`, respecting
its existing warning/exit behavior; package tests must fail the lane on failure.
The package's `npm test` should execute Node tests without starting remote work;
keep local API integration behind a separately named explicit command.

Use the parent per-slice verification map. Run affected package/SQL/API/MCP
checks once against final slice inputs; reuse unchanged passing evidence at
packaging and run remaining mandatory checks once. Rerun
only for changed coverage or a diagnosed failure. No Flutter task is needed.
The package commands are `npm test --prefix tools/festapp` and
`npm run test:integration --prefix tools/festapp`; the latter requires an explicit
disposable local API profile and must reject production profiles. MCP adapter
tests belong in the ordinary package suite with an injected backend fixture.
Exit: all four operations and both adapters are usable locally, tests pass, and
backend rollout status is recorded precisely. Production rollout and live probes
remain separate authorized operations, not claimed complete by local tests.

## Required ticketing writes and remote MCP

Hosted remote MCP is now specified in the parent's phase 4 and its linked child
plan. The notes here constrain the local package and do not replace those
execution/authentication gates.

The user has selected ticketing authoring and issued-ticket edits as the next
write scope; execute the linked ticketing-write child after its per-family
parent-1I readiness gate. Each added write needs a
specific command contract: permission, target, side effects, durable command ID,
retry outcome, audit and preview semantics. A preview is advisory; it neither
reserves capacity nor bypasses authorization/revalidation at commit. Use existing
receipted domain commands (for example
`database/functions/eshop_orders/create_ticket_order_client_sync_v1.sql`), not
generic CRUD or a second idempotency store. Email uses the existing global queue.
Never retry a timed-out write with a freshly generated command ID.

Remote MCP requires its own OAuth/delegation design, token audiences, client
grants, per-request actor context and revocation, resource restrictions and
rate limits. Import the same operation handlers with server context providers;
do not copy the local operator's Keychain session into a hosted server or relay
arbitrary incoming bearer tokens to Supabase. That is a separate implementation
decision and release, not a transport flag to enable in this project.

Official protocol references consulted for these boundaries:
[tools](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/server/tools.mdx),
[annotation limits](https://blog.modelcontextprotocol.io/posts/2026-03-16-tool-annotations/),
[token passthrough and security](https://modelcontextprotocol.io/docs/2025-11-25/tutorials/security/security_best_practices).
Pin SDK/protocol compatibility during implementation instead of assuming every
installed client supports the newest revision.

## Retention, rollout and rollback

There is no legacy cutover in this slice. Retain Flutter/web adapters, existing
operational scripts, existing MCP configuration and business RPCs at their
current boundaries. Do not mass-route them through a Node-specific library.
If a future task replaces a particular script, move that caller and remove only
the proven obsolete implementation in the same task.

For a separately authorized backend rollout, apply the additive SQL migration
before distributing a package that needs its readers; verify grants and scoped
reads through a normal user. Do not add missing-RPC fallbacks to broad readers.
Rollback disables/reverts distribution of the new tool, leaving established app
paths working; new read-only functions can remain until separately removed.
Do not deploy unrelated working-tree changes or roll out to other tenants.

## Assumptions, risks and completion

- **Decision:** backend operation contracts first, then internal macOS operator
  tooling with four read operations and a local MCP proof. The existing Supabase
  HTTP API is sufficient; no additional persistent hosted service is needed.
- **Assumption:** a normal operator account can use password login, with any
  required MFA supported by the existing backend SDK. Resolve during wave 1
  using local Auth fixtures. If the real account is exclusively Google-based,
  record that onboarding limitation and design a proper login handoff before
  live use; do not manufacture a session or add admin access.
- **Assumption:** reviewed selected-tenant activation material can be exported
  without secrets from its existing config/profile artifacts. Resolve exact
  field mapping in wave 1, requiring all production identity pins; do not guess
  a tenant or fill missing values from a former cloud project.
- **Risk:** source readers may differ from deployed functions. No live state was
  inspected for this plan. Record a pending backend migration/release where
  required; local success is not production availability.
- **Risk:** secure session rotation and SDK/schema compatibility are the main
  integration work; a full event-wide report may remain expensive on large
  events. Set bounded network timeouts and surface failures, without silently
  changing report semantics or inventing a cache.
- **Current blockers:** none for local implementation planning. Production writes,
  deployment, live data access and external publication are outside this task.

Complete means four shared operations, both thin adapters, protected sessions,
database-enforced isolation, bounded projections, passing targeted checks and
usable local documentation. No temporary privileged credential path, broad-data
fallback or duplicated business calculation remains in the delivered tool.
