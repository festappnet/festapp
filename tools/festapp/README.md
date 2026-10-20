# Festapp operator - MCP ticket artwork

This private Node package exposes the same fixed operations through a diagnostic
CLI and the official MCP SDK's stdio transport. SQL remains the domain owner;
`preview-ticket-layout` remains the only ticket renderer. Every profile starts
with inspection/preview and enables artwork commands only after an authenticated
backend contract check. The optional hosted OAuth pilot is described below;
it is prepared separately from the local stdio release. No arbitrary SQL/shell
tools or Blueprint V2 are exposed.

The E0 surface is:

- `festapp_context_inspect`: verified ordinary-user identity and pinned target.
- `festapp_ticket_layouts_inspect`: bounded layout projection, original aggregate
  version, owned image references, canonical presets and registered font metadata.
- `festapp_ticket_layouts_preview`: explicit synthetic draft rendering. Returns
  an inline PNG of the canonical PDF, exact draft/scenario fingerprint, source
  aggregate version and a short-lived authenticated PDF resource.

Preview consumes the existing document quota. It does not save active artwork,
open sales, create real tickets or send email. When no candidate is supplied,
the existing resolve endpoint freezes the template/background before PDF rendering.
Both the saved and explicit-candidate paths use the canonical schema/parser.

## Install and provision the selected tenant

Requires Node >=22.13 and macOS Keychain for persistent operator sessions.
`npm test` also requires Deno for the canonical renderer fixture.

```sh
npm ci --prefix tools/festapp
```

Use an explicitly reviewed tenant `project.conf`, never main's generic config.
The following exports only literal activation assignments; it never sources
shell configuration. Review the public profile before importing it.

```sh
git show origin/prod/festapptickets:automation/project.conf > /tmp/festapp-selected-tenant.conf
node tools/festapp/src/cli/main.mjs profile from-tenant /tmp/festapp-selected-tenant.conf --name vstupenky-online > /tmp/festapp-operator-profile.json
node tools/festapp/src/cli/main.mjs profile import /tmp/festapp-operator-profile.json
node tools/festapp/src/cli/main.mjs auth login --profile vstupenky-online
node tools/festapp/src/cli/main.mjs context inspect --profile vstupenky-online
```

Login prompts for email and a hidden password in a terminal. Never put passwords
or tokens in arguments, environment variables, tool inputs or profile JSON.
MFA-required accounts fail explicitly until an MFA interaction is implemented.
Local logout removes only this operator's Keychain record; it never globally
signs the user out of the application:

```sh
node tools/festapp/src/cli/main.mjs auth logout --profile vstupenky-online
```

Profiles live under `~/Library/Application Support/Festapp Operator/profiles`.
The root must be owned by the current user with mode 0700. Import creates a
mode-0600 file exclusively; it never silently overwrites a bound profile.
`FESTAPP_OPERATOR_HOME` selects another absolute, private configuration root.
Refresh credentials are kept only in macOS Keychain, bound to the complete
profile/target identity and verified user. No plaintext fallback exists.

Before login and every operation/resource read, activation must match the pinned
manifest digest, generation and tenant. Manifest data never selects the credential
destination. The backend origin/key/organization hash reuses release tooling.
Redirects fail closed. Every operation reloads refresh state under the same
cross-process directory lock, persists rotation before reading domain data,
validates Auth identity/MFA and reads the user's organization with their own JWT.
No JWT-claim-only authorization or service credential is used.

Lock acquisition is bounded to 10 seconds. A crashed process can leave its empty
profile lock directory under `locks/`; after confirming all operator processes
using that profile have stopped, remove only that exact empty directory and retry.
Do not remove a lock while another process may still rotate its session.

## Start MCP

```sh
node tools/festapp/src/cli/main.mjs mcp serve --profile vstupenky-online
```

Example client entry, using absolute paths in that client's configuration:

```json
{
  "mcpServers": {
    "festapp": {
      "command": "/absolute/path/to/node",
      "args": ["/absolute/path/to/festapp/tools/festapp/src/cli/main.mjs", "mcp", "serve", "--profile", "vstupenky-online"]
    }
  }
}
```

No credentials belong in this entry. The process cannot change profiles through
a tool call. Stdout is exclusively MCP JSON-RPC. CLI diagnostics share handlers:

Generate the absolute paths for JSON-based desktop clients instead of copying
placeholders (this only prints configuration; it never edits another client):

```sh
node tools/festapp/src/cli/main.mjs mcp config --profile vstupenky-online
```

```sh
printf '%s\n' '{"occasionId":7}' | node tools/festapp/src/cli/main.mjs ticket-layouts inspect --profile vstupenky-online
printf '%s\n' '{"occasionId":7,"type":"named","scenario":"normal"}' | node tools/festapp/src/cli/main.mjs ticket-layouts preview --profile vstupenky-online
```

The occasion ID must come from an authorized selected-tenant context. Preview
accepts an optional explicit layout and background; validation/asset permission
remain in the existing backend. It never accepts a real ticket ID or QR secret.
PDFs expire after 15 minutes or process termination; at most four bounded PDFs
remain in memory. Resource reads recheck user identity and current occasion
permission, including after logout or revocation. The PNG is an MCP image block,
not a filesystem path that the client cannot view.

## E1: reviewed save and exact recovery

All profiles, including disposable loopback fixtures, use the same readiness
check. After login, restart the MCP process: `get_ticket_layout_write_contract_v1`
must attest the reviewed SQL definitions, search paths, executor grants and
absence of ordinary direct DML before registering `festapp_ticket_layouts_save`,
`festapp_ticket_layouts_pending` and `festapp_ticket_layouts_resume`. A missing,
changed or unready contract leaves the three E0 tools available. Each artwork
command rechecks readiness before submission; drift disables its registered
write-family tools. There is no profile/environment override or local bypass.

Preview returns `data.saveRequest`: the original aggregate version/layout,
resolved next layout, narrow background/type appearance, scenario and fingerprint.
Pass that exact reviewed request to `ticket-layouts save`. Editing the candidate
requires another preview/fingerprint; hashes are consistency checks, not a
substitute for server authorization. Resolving a default preview preserves other
saved template variants. SQL still validates layout/font/product/image rules.

The adapter calls only `save_occasion_client_sync_v1` with
`{id,ticket_layout_change:{expected,next,appearance}}`. It never imports the
occasion-wide model or replaces a stale baseline with the preflight reader.
All saves use one original command ID persisted before dispatch in a private
mode-0600 file under `pending-layouts`. Profile/actor/occasion and the original
request are bound and verified on reopening. File/directory fsync, atomic rename
and the shared SessionOwner lock protect recovery across processes/restarts.
This is client recovery state; the existing SQL receipts remain the sole backend
idempotency store. Other clients' payment intents are untouched.

An ambiguous response keeps that intent. New content on the same occasion is
refused until the old outcome is resolved. `ticket-layouts pending` returns the
original command and request; `ticket-layouts resume` takes its occasion and
command ID and sends the stored bytes/baseline. Malformed replies, ID mismatch,
expired receipts and unconfirmed errors never allocate a replacement ID.
Only a valid terminal receipt can compare-and-clear its exact pending identity.
A confirmed conflict is returned as a domain outcome for a new inspect/review;
it is never automatically rebased. The backend may return its stored envelope
verbatim on replay, including the original `replayed` flag.

Logout removes credentials but preserves pending artwork state for the same
actor's later login. Do not delete a pending file to work around an uncertain
outcome. Backend exceptions without a confirmed receipt remain pending and need
authoritative diagnosis/recovery; this wave deliberately provides no abandon or
force-save bypass. Save results expose only status/version/identity/fingerprint,
never the full occasion payload returned by SQL.

Released `update_occasion`, `update_occasion_203` and `update_occasion_182`
retain their signatures and general settings/create behavior. Their one private
facade now rejects an explicit layout change or changed background/type without
the original editor version, using SQLSTATE 40001 and
`ticket_layout_editor_upgrade_required`. They never reconstruct a version for
artwork updates. The modern versioned occasion command remains the only writer
for such changes. No unversioned alternative is removed or silently treated as
an original editor baseline.

The new forward migration must be deployed before a live connection can expose
E1. If deployment is absent or rolled back, the runtime contract fails closed.

## Verification and next wave

```sh
npm test --prefix tools/festapp
FESTAPP_MCP_TEST_DATABASE_URL=YOUR_DISPOSABLE_LOCAL_DB npm test --prefix tools/festapp
DATABASE_URL=YOUR_DISPOSABLE_LOCAL_DB node web_client/scripts/run_db_tests.js database/tests/ticket_layout_mcp_read_test.sql
```

Tests cover activation/tenant/ordinary-role boundaries, session rotation,
revocation/MFA, secure-persistence failure, fixed schemas, actual SDK stdio
interoperability, shared CLI/MCP results and a synthetic canonical PDF rendered
to PNG. Node boundary tests mock Auth/HTTP and secure storage; they do not prove
a successful real-account Keychain login or live tenant operation. The SQL test
uses a real disposable backend and rolls back its two synthetic identities.

The optional real PostgreSQL test requires the marked `festapp-db-tests-pg15`
fixture on loopback port 55432 plus the existing web-client test dependencies.
It exercises MCP preview/save/lost-response replay/conflict through the actual
SQL owner under `authenticated`, inside an outer rollback fixture transaction.
Without that explicit variable, the database integration case is skipped; the
ordinary Node suite still runs.

E1 code, the legacy artwork fence and authenticated runtime registration are
implemented. Live exposure depends on the selected backend migration and a
normal operator login; no service credential is used. The remaining report/event/order readers belong to later
E5; the current visual/layout slice is not completion of the overall MCP plan.
The hosted OAuth read pilot is implemented in `src/remote`, with its activation
gates and client setup in [remote-mcp-auth.md](../../docs/architecture/operations/remote-mcp-auth.md).
It adds two read tools for explicitly selected occasions, using the same handlers.
Hosted preview/writes and issued-ticket actions remain separate waves.

## Hosted OAuth pilot: connect in a browser

The selected endpoint is `https://mcp.festapp.net/mcp`. Implementation and local
acceptance do not mean the endpoint has been activated. The release record must
confirm DNS/TLS, the exact image/config and the real ChatGPT connection first.

After activation, add that URL as a custom remote MCP server in ChatGPT, choose
OAuth and the pre-registered public client `festapp-chatgpt` with no client secret.
Register the exact callback shown by ChatGPT's server management page. The
prepared configuration uses its stable callback
`https://chatgpt.com/connector_platform_oauth_redirect`; issuer identification is
advertised and verified locally. Automatic/open client registration is disabled.

Click connect, log into Festapp in the browser, select allowed occasions and
confirm access. No API key or refresh token is copied into ChatGPT. The first
pilot allows only `context.inspect` and `ticket_layouts.inspect`; the configured
operator/resource list is checked again for every call. Disconnect at
`https://mcp.festapp.net/connections`, independently of the Festapp application.

The browser currently supports ordinary Festapp password authentication. MFA
accounts fail explicitly; Google/SSO and device login are not implemented in
this pilot. The local terminal login is unchanged. Mendelio Voice's remote
OAuth and local device-login pattern informed the connection UX, not shared
credentials or identity-provider configuration.

Runtime: Node 24 LTS. Configuration and the separate secret file are private,
outside Git. Validate and provision without printing secrets:

```sh
node tools/festapp/src/remote/main.mjs check /absolute/private/config.json
node tools/festapp/src/remote/main.mjs secrets init /absolute/private/secrets/issuer.json
node tools/festapp/src/remote/main.mjs serve /absolute/private/config.json --secrets /absolute/private/secrets/issuer.json --data /absolute/private/data --port 3399
```

Secret initialization is exclusive. Keep the AES storage key, cookie keys and
issuer signing key stable across restarts. The server binds only loopback;
canonical requests require the exact Host and trusted HTTPS proxy header.
`Dockerfile.remote`, `remote-compose.yml` and `Caddyfile.remote` prepare the
bounded sidecar, leaving the existing API release separate. Only one process
may own its SQLite volume. After an unclean stop, verify that process is stopped
before removing only its empty `remote-process.lock`; never clear another
operator's per-profile refresh lock while it is active.

References: [MCP SDK v1 server documentation](https://ts.sdk.modelcontextprotocol.io/server),
[Supabase password authentication](https://supabase.com/docs/reference/javascript/auth-signinwithpassword),
[Keychain binding](https://github.com/Brooooooklyn/keyring-node).

### Codex remote connection

Register a separate public client `festapp-codex` with `applicationType: "native"`
and redirect URI `http://127.0.0.1/callback`. Native clients accept only literal
IP loopback HTTP callbacks; the maintained provider permits a variable port,
while the callback path remains exact. Web clients retain their HTTPS policy.

```sh
codex mcp add festapp --url https://mcp.festapp.net/mcp --oauth-client-id festapp-codex --oauth-resource https://mcp.festapp.net/mcp
codex mcp login festapp --scopes festapp:ticket-layouts:read
```

Complete the fresh browser login and occasion consent for this client. The
native client uses the same scoped read handlers and separate OAuth grant.
