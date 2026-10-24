# Hosted remote MCP over canonical Festapp operations

Date: 2026-10-20. Status: phase-4 design and execution gates; not deployed.
Verification: standard for implementation; existing production release gates
apply to separately authorized activation.

This is the phase-4 child of the authoritative
[canonical operations and access plan](festapp-canonical-operations-plan-2026-10-20.md).
It does not authorize implementation or release by itself.

## First distinguish remote data from a remote MCP server

A local MCP stdio process can already use the canonical remote Festapp backend
over authenticated HTTPS. It does not need a local copy of event/order data or
an SSH/database-admin tunnel. Phase 3 delivers that mode.

A hosted remote MCP endpoint is needed when the chosen MCP client cannot launch
our local process or the connector must run independently of this workstation.
Phase 4 supplies that HTTP interface. It adds hosting, authorization and grant
lifecycle responsibilities; it does not add a second business API implementation.
Do not expose a public HTTP listener just to make local MCP reach remote data.

The initial audience is an allowlisted internal operator and selected tenant,
not automatic self-service for every organizer. The first hosted surface has
the same four read operations as the local bootstrap. Subsequent required
ticketing writes are specified in 4D below. No shell, arbitrary RPC,
raw SQL, release, bank-control or provider-callback tool is registered.

## Architecture and ownership

```text
Local MCP client                  Remote MCP client
       | stdio                          | HTTPS + MCP OAuth token
       v                                v
local adapter                    hosted Streamable HTTP adapter
local credential context         per-request delegated context
       |                                |
       +-------- shared operation handlers --------+
                              |
                  normal user-scoped Supabase HTTPS
                              |
             canonical SQL/RPC + required Edge workflows
```

Use the same private `tools/festapp` package. Operation handlers and their
allowlisted backend mappings must not depend on Keychain, stdin, terminal
prompts, a shared mutable current user or an MCP session-global principal.
Local context and remote context are distinct providers for an immutable
operation context containing verified actor, tenant, resource restrictions,
allowed operation set, backend client and correlation/audit sink.

Proposed additions after phase 3:

- `src/mcp/http/`: official SDK HTTP adapter and lifecycle, one `/mcp` resource.
- `src/remote/auth/`: validated OAuth resource-server integration with a selected
  maintained issuer; no handwritten OAuth protocol implementation.
- `src/remote/grants/`: actor/client/tenant/resource consent and revocation.
- `src/remote/backend-session/`: protected downstream user session ownership,
  bounded refresh serialization and cleanup.
- `test/remote/`: SDK interoperability, identity isolation and revocation tests.

Deploy as a bounded Node service supporting the same runtime as the shared
package on existing approved hosting. A separate process/container is a narrow
MCP adapter, not a general replacement REST server. Do not force business RPCs
through an Edge Function proxy. Record CPU, memory, request/DB latency and
connection use before considering a different host/runtime; no resource saving
is assumed from moving to HTTP or removing Edge.

## Authorization and delegation contract

1. The MCP HTTP resource validates its own OAuth token issuer, audience/resource,
   expiry and scope on every request. It rejects a Supabase user token presented
   as an MCP access token. Protected-resource discovery and authorization-code
   flow with PKCE follow the selected supported MCP revision.
2. Use existing Festapp login as the identity source. The MCP access issuer is
   separate from downstream Supabase authentication. Do not assume the deployed
   self-hosted GoTrue supports acting as an MCP OAuth issuer; no such existing
   integration was established in source reconnaissance.
3. Consent creates a grant bound to exact verified Festapp actor, approved MCP
   client, one organization, explicitly selected occasion IDs and allowed
   operations. Initial read scopes: `festapp:context:read`,
   `festapp:occasions:read`, `festapp:reports:read`, `festapp:orders:read`.
   A grant cannot exceed current backend permissions. No implicit access to
   future occasions, other tenants or every event belonging to the operator.
4. The hosted adapter uses a separately authorized ordinary-user Supabase session
   obtained by a proper login/connection flow. Keep its refresh credential
   encrypted in server-owned storage, isolated by grant/connection and backend.
   Never copy the workstation Keychain session or read browser cookies. The
   downstream token never reaches the MCP client, tool arguments, logs or results.
5. Validate the OAuth subject-to-Festapp-account association server-side. Resolve
   current grant, actor, organization and resource restriction on every tool
   invocation. Then invoke existing SQL/RPC as that user, so backend role and
   row-scope checks remain authoritative. The incoming MCP token is not blindly
   relayed to Supabase, and a service-role client must not impersonate the actor.
6. Tool inputs cannot set backend origin, profile, actor or grant. Occasion/order
   arguments are domain inputs constrained by the verified grant. Inventory
   pagination and report/inspection readers must apply the resource restriction
   without leaking names/counts/cursors for disallowed occasions. Extend the
   bounded domain reader filter when necessary; keep normal DB authorization.
7. Restrict initial OAuth client registration to reviewed clients and exact
   callback URIs; no open registration or shared operator identity for unrelated
   users. Login/consent validates state and resource binding. Unsupported identity
   or MFA flow fails explicitly without admin-generated session shortcuts.
8. Revoke a grant independently of application login. Check active/revoked state
   before an invocation; do not rely solely on a short token expiry or MCP session
   initialization. For reads revoked while in flight, recheck before returning
   sensitive output and discard it if revoked. Do not promise recall of data
   already returned. Backend membership removal also takes effect through the
   next user-scoped backend check. For writes, revocation prevents new admissions;
   an already admitted SQL call may still commit. Do not promise rollback or
   immediate cancellation of in-flight domain work. Record admission/outcome and
   preserve receipt-based resolution after reconnect without leaking revoked
   private results. Define any stronger transaction-bound delegation separately.
9. Expired/revoked connection credentials require reauthorization. Serialize
   downstream refresh across hosted replicas/requests using the selected storage
   mechanism; never race stale refresh tokens or fall back to another account.
   Revocation cleanup must not globally log the operator out of the Festapp app.
10. Audit grant/client/actor, operation, tenant/resource, time, outcome and request
    ID, with redacted payloads. Restrict rate/concurrency per grant and tenant.
    Logs must not contain customer response fields, email bodies, capability
    secrets or bearer/refresh credentials. Reuse the canonical minimal read
    projections; an MCP read annotation is not a permission boundary.

The ordinary user session retains that user's backend permissions internally;
the remote grant narrows access at the hosted adapter. Do not claim that the
underlying Supabase JWT is a cryptographically read-only delegated credential.
Protect it as a downstream credential and never expose generic backend access.

Official primary references consulted:
[MCP HTTP authorization](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/basic/authorization/index.mdx),
[token audience and no passthrough](https://modelcontextprotocol.io/docs/2025-11-25/tutorials/security/security_best_practices),
[TypeScript SDK](https://ts.sdk.modelcontextprotocol.io/).
Pin a compatible SDK/protocol pair and verify actual intended clients rather
than claiming interoperability from the protocol name alone.

## Execution gates

### 4A. Resolve identity/hosting integration before building a public endpoint

Check the selected client can use the supported HTTP/OAuth flow; use the official
SDK client as the deterministic initial acceptance client. Record whether the
operator only needs remote backend access through local MCP, or needs an
independently hosted connector. Hosted implementation follows only for the
latter outcome; phase 3 remains useful in either case.

Inspect pinned GoTrue configuration, exact Festapp login-client registrations,
supported normal-user session handoff and available approved hosting. Choose a
maintained OAuth issuer implementation and its storage integration with the
MCP resource, not a speculative supported feature in the existing Auth server.
Prove login -> consent -> MCP token -> mapped downstream ordinary-user context
with disposable local Auth and fake/loopback-only provider fixtures.

Record the chosen issuer/version, origins/callbacks, subject mapping, token
audience, consent schema, encrypted session storage, refresh locking, revocation
and exact role/grants in `docs/architecture/operations/remote-mcp-auth.md`.
Any new project SQL functions stay in `public` with explicit grants; no broad
service-role domain access. Do not select a paid/external identity service or
create public DNS/secrets as an incidental implementation step.

**Exit:** a concrete verified identity/storage design replaces unverified
capability assumptions. Missing infrastructure/credentials is an exact release
prerequisite, not permission to skip token separation or consent. Do not proceed
to live publication while this gate is unresolved.

### 4B. Implement the hosted adapter and grant-constrained reads

Add the modules above, protected-resource discovery, allowlisted OAuth client
configuration and per-request immutable context. The same operation handlers
serve local and HTTP MCP; transport adapters contain no copied domain SQL or
business algorithms. No current-user global or user-specific singleton client.

Implement grant creation/list/revocation through properly authenticated operator
management, not tools callable by the model. Expose only granted read tools;
hidden tools are not an authorization control, so direct `tools/call` is checked
again. Add the bounded occasion allowlist predicate to readers if required and
test deny behavior in the backend as well as at the adapter.

**Validation:** official SDK HTTP client discovers/calls the same four operations;
wrong issuer/audience, expired token, direct Supabase bearer, unknown client and
ungranted tool calls fail before domain work. Invalid target/resource input
cannot redirect credentials. Two actors/clients/grants on the same process and
replicas never reuse each other's backend session or data.

### 4C. Prove lifecycle and prepare a reviewable release

Test revocation while a token remains valid, denied occasion listing/order
inspection, membership removal, rotating-refresh contention, issuer/DB outage,
reauthorization and session cleanup. Compare local/remote handler contracts using
the same fixtures. No provider emails or production reads in tests.

Package bounded runtime configuration, health check without private data,
shutdown behavior, protected secret handling, redacted audit and an exact
selected-tenant release/rollback runbook. Document endpoint/metadata/client
configuration for the tested client. Keep public registration disabled.

**Exit:** isolated hosted-MCP acceptance passes and release artifacts/configuration
are concrete. Report a separately pending production activation explicitly.
Publication, tenant live probes and adding the connector to an external client
need authority for those actions. If authorized later, delegate routine
deployment/live verification under repository rules.

### 4D. Enable the required ticketing writes through operation grants

Implement the [ticketing-write child](festapp-ticketing-mcp-plan-2026-10-20.md)
for families that have passed parent 1I and local 3B/3C. The read-only pilot is
an intermediate milestone. Use the same handlers and original version/command
identity contracts; do not create a remote-specific mutation engine.

Define fixed capabilities for blueprint, form, product/inventory and layout
editing; separate sales activation, issued-ticket changes, order creation/
cancellation, PDF export and manual delivery. Suggested grant vocabulary:
`festapp:blueprints:write`, `festapp:forms:write`, `festapp:products:write`,
`festapp:inventory:write`, `festapp:ticket-layouts:write`, `festapp:sales:activate`,
`festapp:tickets:write`, `festapp:orders:create`, `festapp:orders:cancel`,
`festapp:tickets:export`, `festapp:tickets:send`. Bind each to specific registered
operations and approved occasions; a scope name alone never grants all actions
in that domain. Avoid blanket `ticketing:*` or an order-editor grant implicitly
allowing unit-scoped layout changes. Bank/refund/admin permissions remain separate.

Trusted connection policy determines which actions need a host/user approval.
A grant may authorize routine reversible design edits without repeated prompts.
For an action requiring approval, bind the trusted approval to exact operation,
resources, normalized payload and baseline; model-supplied `approved:true` is
not proof. Read-only/destructive tool annotations remain hints, not authority.
Opening sales and manual delivery always have separate explicit operation intent;
a geometry preview does not grant authorization or reserve seats.

Persist the immutable command intention before submission and retain it across
HTTP timeout, reconnect and same-account reauthorization. OAuth/session IDs are
not command IDs. Serialize grant-specific session refresh without substituting
an account. Check active grant/current roles at admission and backend mutation
permissions as the actor. Log exact command ID plus redacted outcome; do not log
form responses, hold secrets or PDF/email content. Grant storage is not a second
domain-receipt engine. Revocation semantics remain those in rule 8: admitted
writes can finish, and unknown outcomes require authorized receipt recovery.

**Validation/exit:** local/hosted result parity, forbidden-operation denial,
design-only grant unable to activate sales/send/edit issued tickets, layout
unit-role denial, cross-occasion argument denial, write timeout/replay and
revocation before admission versus during an admitted transaction are covered
with isolated fixtures. Verify payload substitution cannot reuse trusted approval.
No real sales, payments or mail. Prepare exact scope/consent migration and rollback
instructions before selected-tenant release. Disabling exposure preserves domain
receipts, allocations and queued delivery commitments.

## Completion

The read pilot is complete when an allowlisted operator can grant selected read
access, call canonical operations through HTTP and revoke access independently,
with actor/tenant/resource isolation proved. The requested ticketing-write scope
additionally requires 4D for locally ready authoring and issued-ticket families;
it is not satisfied by four read tools. Hosted activation is necessary only if
the chosen client needs hosted access. Local tests demonstrate implementation,
not live availability; publication and actual tenant changes remain separate
explicitly authorized operations.
