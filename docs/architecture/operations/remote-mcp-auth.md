# Remote MCP authorization pilot

Date: 2026-10-20. Status: implemented and locally verified; public activation and
real ChatGPT/account login remain pending. Selected origin: `https://mcp.festapp.net`.
Scope: `festapptickets` / vstupenky.online only, the approved pilot account and
the five current occasions of its Testovací organizace unit. Private actor IDs,
labels, public backend profile and exact resource allowlist live outside Git.
No future occasion is automatically included. Blueprint V2 remains excluded.

## Identity and ownership

The maintained `oidc-provider` 9.12.2 runs the OAuth authorization-code/PKCE,
discovery, code exchange, issuer identification, opaque access tokens, rotating
refresh and revocation protocol. Express 5.3.0 supplies bounded HTTP routing.
Both are pinned in the existing package lock. Node 24 LTS is the hosted runtime;
the existing self-hosted GoTrue v2.189.0 remains ordinary downstream Auth.
No unsupported GoTrue OAuth-server capability is assumed or enabled.

The user clicks Connect in ChatGPT, logs into Festapp in our browser interaction,
chooses individual allowed occasions and consents. The initial interaction uses
the existing `SessionOwner.login` and identity/MFA/organization checks with a
separate encrypted server store. It does not read workstation Keychain/browser
credentials. Passwords are transient request input, never persisted or audited.
Current supported login is password; MFA fails closed. Google/SSO and local
device authorization are explicitly outside this pilot.

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

The browser logs into downstream Supabase normally. Explicit consent binds one
new independent backend refresh session to one actor/client/tenant/profile and
the selected occasion IDs for seven days. The MCP token and the Supabase token
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
MCP OAuth challenge for relinking. No remote domain write is admitted.

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
