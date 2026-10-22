# Remote MCP authorization pilot

Date: 2026-10-20. Public issuer: `https://mcp.festapp.net`.
Deployment scope: `festapptickets` / vstupenky.online. Blueprint V2 is excluded.
Access choices come from the authenticated actor's live domain rights, not a
second per-user/event allowlist. Tenant identity remains pinned by the existing
registry and ordinary-user organization check.

## Delegation scope and creation

Web consent groups occasions under organizer checkboxes. Selecting an organizer
includes its current and future occasions and, when the OAuth request includes
`festapp:occasions:create` and the actor has the live creation capability, also
permits creating new hidden occasions with sales closed. The checkbox description
states that scope before approval. Selecting individual occasions never includes
future occasions or creation. Several organizers and individual occasions can be
combined in one `selection` grant with explicit per-organizer creation flags.
Existing `unit` and `occasions` grants retain their original scope, including
native consent requests. A whole-organizer grant excludes other organizers and
the rest of the tenant (`organization`).
The canonical `get_operator_access_v1` projection exposes only authorized units
and occasions visible to editors/managers. Artwork reads retain their narrower canonical permission check. It accepts no caller-supplied actor identity.
Every operation still uses the ordinary session and canonical domain checks.
Moving an occasion to another organizer removes it from a unit grant.

Creating occasions requires the requested OAuth scope `festapp:occasions:create`,
explicit consent for the target organizer, its `canCreateOccasions` flag and
current creation rights from the canonical SQL boundary. It is never inferred
from selecting every visible child occasion. Read-only clients do not advertise
the create tool. The existing read scope is `festapp:ticket-layouts:read`.
`festapp_access_inspect` lists only the connection's current authorized scope.
`festapp_occasions_create` calls `create_occasion_client_sync_v1` unchanged, with
an explicit command UUID, hidden=true and sales closed. It cannot publish, send
messages, copy Blueprint V2 or alter another organizer. An uncertain result must
retry the identical UUID and payload; canonical receipts prevent duplicate writes.
An expired/mismatching receipt is an error, never permission to generate a new ID.

Remote config schema 2 removes `operators` and `occasionLabels`. Before switching
the image, back up the protected config, set schemaVersion=2 and remove those
fields; do not change profile, client callbacks, storage/signing/cookie keys or
broker secret. Startup upgrades existing persisted selected-occasion grants to
`access: {type: 'occasions', occasionIds: [...]}` once, preserving their expiry,
identity and restrictions. Existing tokens/consents never acquire create scope
or whole-organizer access. In-flight old consent pages must reload the new UI.
Apply `20261020210000_operator_access_projection.sql` before the new MCP image,
then deploy the first-party UI. Add both requested scopes in clients that should
show the optional creation choice; a new explicit consent is required.

Cloudflare Browser Integrity Check is disabled only for the MCP host's machine
routes `/mcp`, `/token`, `/token/revocation`, `/jwks`, `/healthz` and
`/.well-known/*` using a Configuration Rule. Browser consent routes and other
hosts retain their settings. Default TLS verification stays enabled; probes
must verify OAuth JSON responses for non-browser User-Agents as well.

## Identity and ownership

The maintained `oidc-provider` 9.12.2 runs the OAuth authorization-code/PKCE,
discovery, code exchange, issuer identification, opaque access tokens, rotating
refresh and revocation protocol. Express 5.3.0 supplies bounded HTTP routing.
Both are pinned in the existing package lock. Node 24 LTS is the hosted runtime;
the existing self-hosted GoTrue v2.189.0 remains ordinary downstream Auth.
No unsupported GoTrue OAuth-server capability is assumed or enabled.

The user clicks Connect in the MCP client and continues to the configured
first-party tenant. Its existing app login identifies the actor; the user chooses
individual allowed occasions or one organizer and consents. The first-party broker reuses the
existing session-issuance owner and identity/MFA/organization checks with a
separate encrypted server store. It does not read workstation Keychain/browser
credentials. Passwords are transient request input, never persisted or audited.
The tenant retains its existing login choices; MFA session issuance currently
fails closed. MCP does not implement a parallel Google or device identity provider.

Issuer and resource are respectively `https://mcp.festapp.net` and
`https://mcp.festapp.net/mcp`. Resource metadata is available at both the root and
path-specific `/.well-known/oauth-protected-resource` URLs. OAuth and OIDC
discovery return JSON directly. Authorization/token requests use the exact
resource. Codes require S256 and expire in 60 seconds. Access tokens are opaque,
last five minutes and resolve only through this issuer's encrypted adapter.
They cannot be a downstream Supabase JWT. Issuer lookup, exact audience, client,
actor, expiry and scope are checked on each HTTP invocation; the grant is checked
again by each shared operation and after a private read completes.

The reviewed client `festapp-chatgpt` is public (`none` token-endpoint auth),
with exact callback allowlisting. Open/Dynamic registration is disabled; CIMD
is not advertised. The issuer supports RFC 9207 `iss`; tests verify the exact
issuer in the callback. The prepared callback is
`https://chatgpt.com/connector_platform_oauth_redirect`. Confirm it against the
actual ChatGPT management page before activation. A different client/callback
must be explicitly registered, never accepted from arbitrary request metadata.

The separately registered public native client `festapp-codex` uses
`applicationType: native` and `http://127.0.0.1/callback`. Its callback port may
vary as required for a local listener; the path is exact, and non-loopback hosts
are rejected. Native callback configuration rejects userinfo, query and fragment.
This does not widen web-client redirects or enable dynamic registration.

The browser logs into downstream Supabase normally. Explicit consent binds one
new independent backend refresh session to one actor/client/tenant/profile and
the selected access scope for seven days. The MCP token and the Supabase token
remain separate. The adapter has no service-role key and never relays a supplied
MCP bearer to Supabase. Existing SQL/RPC permissions remain the final domain
authority. The OAuth grant narrows access; the stored ordinary Supabase session
is not claimed to be a cryptographically read-only credential.

Only `festapp:ticket-layouts:read` is admitted. It maps to `context.inspect` and
`ticket_layouts.inspect` in the existing shared `Operations` catalog. Hidden
tools are not the boundary: invocation checks the operation and occasion before
any backend call. No remote preview/quota consumption, saves, sales, issued
tickets, orders, arbitrary RPC, payment or mail action is admitted.

## Storage, lifecycle and isolation

One Node process owns one private SQLite volume, using FULL synchronous commits
and AES-256-GCM for every payload with model/record binding as AAD. Record IDs
and lookup indexes are hashed. A separate mode-0600 secret file supplies the
32-byte AES key, two cookie keys and issuer signing JWK. The database mode is
0600 and its root is 0700. A sentinel detects a wrong encryption key, and a
deployment binding rejects reuse against a different issuer/backend profile.
Backups of the data volume must not include the separate issuer key mount.

A process-directory lease refuses another process/replica. This is deliberately
single-process storage, not a distributed lock claim. OAuth token exchanges are
bounded and serialized; adapter consumption refuses a second consume. Each
downstream refresh plus operation uses the existing cross-process session lock,
bound to the unique connection. Rotation is persisted before domain reads.
Abandoned login credentials expire after ten minutes; consent promotes them to
the original grant deadline. New refreshes cannot revive a revoked session.

`/connections` requires a fresh ordinary login and a rotated HttpOnly/SameSite
management cookie. It lists/revokes only that actor's grants, under Origin and
CSRF protection. Revocation deletes downstream credentials and issuer grant
tokens; it never globally signs out the Festapp application. A still-valid MCP
token is denied immediately. A read revoked in flight is discarded before
return; already returned data cannot be recalled. Downstream identity/membership
is checked through Auth/user-scoped SQL on invocation, not JWT claims alone.
An invalid downstream session revokes the connection and supplies the standard
MCP OAuth challenge for relinking. Only explicitly consented occasion creation is admitted as a remote write.

Fixed HTTP/body/token/storage/concurrency bounds apply. Audit records contain
hashed actor/connection, client, tenant, operation, request ID and outcome only.
They never contain passwords, bearer/refresh tokens or business payloads. There
is no mutable session-global principal: each HTTP request creates an immutable
delegated owner and its own shared-handler instance. Stateless SDK HTTP handling
does not rely on an MCP session ID for authentication.

## Evidence and remaining activation gates

37 Node cases passed with Node 24.20.0, including the existing real disposable
PostgreSQL owner integration (zero skipped). New cases execute the actual issuer
and official MCP SDK HTTP client: discovery, exact callbacks, bad PKCE, code
single-use, refresh rotation, direct Supabase bearer denial, ungranted resource
and write denial, two-actor isolation, encrypted restart, second-process/wrong-key
denial, browser CSRF, own-grant revocation and in-flight revocation. Auth/REST
responses in the new HTTP cases are mocked; they do not prove a successful real
GoTrue login, live Google/SSO or real ChatGPT connection. Existing SQL integration
executes synthetic data in a rollback fixture, never production.

Headless static login/consent checks passed at 320px with no horizontal overflow,
keyboard focus and zero axe WCAG2 A/AA violations. Browser session was closed.
The local stdio/client path is unchanged and covered by existing SDK acceptance.

The actual target reports aarch64. The locally built linux/arm64 image is
`sha256:3b35dd42fb9ef8b625c56acd0dbdc0c8857fa7251b022a4ae1b5ea4c696aacfd`,
from runtime source `466a7a75b3f3255c0c7944d2bfd2668d41da9400`. Its identical
runtime inputs were verified through Compose fix
`8b58adc82232f39014879b0d88322b5e3342a5f7`. Packaged startup, exact Compose
healthcheck, discovery and 401 challenge passed in an isolated container with
no network/published ports. Compose and pinned Caddy validation passed. Startup
RSS was 96,180 kB (one sample, not a load test). The initial Node-fetch health
probe rewrote Host; the final core-HTTP probe preserves the required exact Host.
Temporary containers, volumes and fixture secrets were removed.

Logs: `/tmp/festapp-mcp-oauth-full-tests-20261020.log`; screenshots and synthetic
static views: `/tmp/festapp-mcp-oauth-ui/`. Private reviewed pilot configuration:
`~/Library/Application Support/Festapp MCP/remote-config.json` (0600).
Container evidence: `/tmp/festapp-mcp-oauth-image-preparation-20261020.json`.

External activation blockers at this checkpoint: main's required approving PR
review is outstanding, `mcp.festapp.net` has no DNS answer, and the available
Cloudflare OAuth login has `zone:read` without DNS-edit permission. No credential
was exported or broadened. These are concrete activation prerequisites, not a
claim that a real ChatGPT connection already works.

Production reads verified canonical activation/runtime/org 3, the named user's
unit membership and the five current unit occasions. No business records or
production configuration were changed. The shared backend host had 1072 MiB
available and 14 GiB disk free at inspection. This is a point-in-time inventory,
not proof of runtime headroom. The prepared sidecar has 384 MiB/0.5 CPU bounds;
measure its actual RSS, latency and error rate before expanding the pilot.

Before a public connection:

1. Publish through a PR and obtain the repository's required approving review.
   Main branch protection requires one review; do not repeat an administrative
   direct-push bypass. Freeze the exact main commit for release.
2. Build the pinned Node image from that commit, capture its digest, prove
   packaged startup/health/discovery, and record architecture/resource evidence.
   `Dockerfile.remote` only copies the package source and existing profile helper.
3. Provision the private allowlist/profile and generate issuer secrets on the
   approved host, outside Git and outside the data-volume backup. Preserve the
   same keys across restarts. Use UID 1000 and private file/directory modes.
4. Start only the standalone `remote-compose.yml` service using the immutable
   image. Listener stays at loopback port 3399; no Supabase restart/schema change.
   Prove health/discovery and unauthenticated challenge locally before routing.
5. Configure only the approved `mcp.festapp.net` DNS/TLS site and merge the
   prepared Caddy site block without changing existing API/admin sites. Validate
   config and reload Caddy, preserving the current origin firewall/proxy policy.
   The exact Host and HTTPS proxy header are required; no access log captures
   authorization URLs. Check the live metadata/challenge without credentials.
6. Add the endpoint in ChatGPT with the reviewed public client ID and confirm
   its exact displayed callback. The operator completes browser login/consent;
   exercise an allowed read, denied occasion and Disconnect while tokens remain
   valid. Record real Auth/ChatGPT evidence distinctly from fixture tests.

Routine build/deployment/live probes are delegated per repository rules. No
Flutter rebuild or unrelated tenant rollout is required for the separate MCP
sidecar. If an issuer/storage/identity/client gate fails, leave routing disabled.
Rollback removes only the MCP route/service and revokes its connections;
preserve keys and encrypted evidence for authorized recovery. No domain data,
payment receipts or application login is rolled back.

## References and Mendelio Voice comparison

The user requested inspiration from Mendelio Voice. The local
`mendelionet-sdk/packages/voice-mcp` implementation and its SDK `voice/src/login.ts`
distinguish remote OAuth from local device authorization, surface a user approval
URL and return actionable reauthorization errors. That interaction pattern is
retained here. Festapp does not import Voice credentials, issue a general API key
as a downstream user, or copy its service-specific scopes and billing behavior.

Primary guidance: [OpenAI authentication](https://developers.openai.com/plugins/build/auth),
[maintained issuer](https://github.com/panva/node-oidc-provider),
[MCP SDK HTTP transport](https://ts.sdk.modelcontextprotocol.io/),
[Supabase user sessions](https://supabase.com/docs/guides/auth/sessions).

## First-party tenant consent

The public MCP issuer stays on `mcp.festapp.net`. With `tenantOrigin` configured,
its connection interaction redirects to `/settings/mcp-connect` on the exact
first-party tenant origin. The app reuses its ordinary session and login page
(including its existing provider choices), displays the requesting client and
read-only scope, and requires an explicit occasion selection and approval.
The opaque request expires with the interaction. No app refresh token or
password is sent to the MCP issuer and no Auth token is placed in a URL.

`mcp-session-exchange` accepts only the configured tenant Origin. The issuer's
private broker secret authenticates the Edge-to-MCP backchannel. Details use a
transient verified user access proof and the existing `Operations` permission
checks. Approval consumes a single-use preparation lease bound to that actor,
client, profile and occasion selection. The Edge function resolves only the
verified actor and uses the existing `issueExistingUserSession` owner and lease
to issue an independent ordinary Auth session. It sends this session directly
to MCP, never to the browser. MFA accounts remain explicitly unsupported by
this session-issuance boundary and fail closed. The MCP process still has no
service-role key. Failed/uncertain transfers revoke only the new session.

OAuth completion requires the original issuer interaction cookie and a short
opaque continuation. The tenant cannot supply an OAuth callback or completion
destination. Consent, downstream authorization and grant issuance have one
shared owner; tenant consent cannot expand the configured pilot allowlist.
The production tenant UI is released before enabling `tenantOrigin` routing.
The Edge runtime needs a protected `FESTAPP_MCP_TENANTS_JSON` registry: an array
of `{tenantId, tenantOrigin, organizationId, issuer, brokerSecret}`. Origins are
exact HTTPS origins, unique within the registry. Only the HTTP Origin selects a
registry entry; client bodies cannot select an organization, issuer or credential.
Every backchannel call carries the resolved tenant identity; the issuer checks
it against its bound backend profile before inspecting a request or minting.
The `brokerSecret` matches the separately protected issuer secrets file. Never
rotate storage/signing/cookie keys as part of adding this bridge secret.

The Flutter confirmation page, Edge handler and issuer bridge are reusable
adapters; none chooses a tenant from an email, URL parameter or hardcoded brand.
Adding another approved website requires registering its exact origin/profile
and issuer routing, plus that tenant's own release. The current issuer remains
bound to the single approved `festapptickets` profile; the registry does not
silently enable a second tenant or share a grant across organizations. A future
multi-profile issuer must resolve that same tenant boundary before constructing
its operation/session owner, rather than making a current-tenant singleton.

## Native completion experience

Native clients complete their loopback callback in a short-lived helper window,
opened synchronously from the user's approval gesture with its opener severed.
The tenant never reads that cross-origin window, callback URL or authorization
code. A blocked popup retains the standard top-level callback behavior. Web
clients retain their own top-level OAuth completion.

The original tenant page observes its own opaque request through the same
origin-bound Edge broker. Status requires the existing app actor proof, matches
the request's actor and expires after ten minutes. It returns only a lifecycle
status, never credentials or grant IDs. Consent alone and token issuance alone
remain pending: `connected` requires an accepted MCP bearer request from the
client. Revoked grants cannot produce a successful completion screen. Only after
that proof does the tenant close its app-owned helper and render the branded
completion page. An uncertain observation stays explicitly unconfirmed.

Display email uses the existing `AppConfig.removeUserPrefix` tenant adapter;
raw Auth addresses and account identity used by the protocol remain unchanged.
