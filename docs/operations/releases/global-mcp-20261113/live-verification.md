# Global MCP production verification - 2026-11-13

Global service source: `a37389cc225a139725a935d014f1df10f091484e`.
Selected broker Function source: `09cdd991fa30dd848324df586e188040931d3bd2`.
The earlier preparation inventories in this directory describe the pre-release
state. This document and the accompanying final receipts describe live checks.
Production verification passed. Both Official MCP Registry records are public.
Both Glama submissions are pending external review, publisher claim and
authenticated health/indexing; the complete directory objective is not done.

The initial global browser flows required a diagnostic reload of the context
selector and therefore did not satisfy the end-to-end release gate. CDP then
confirmed `form-action 'self'` blocked the selector POST's redirect to
first-party consent. Source correction
`a37389cc225a139725a935d014f1df10f091484e` derives CSP destinations from the
protected tenant registry and registered callbacks, including native ephemeral
loopback ports. It preserves the provider script hash, CSRF and OAuth callback
validation. The canonical local server-policy lane passed before publication;
all eight exact-source GitHub release checks subsequently passed. Packaged
smoke and production promotion passed. Fresh uninterrupted regional and BISCUP
browser flows now both passed, retaining cookies across account switches.
See `oauth-browser-diagnosis.jsonl`, `csp-local-ci-evidence.json` and
`pre-fix-oauth-diagnostic-evidence.json` for qualified observations.

## Runtime and first-party application

- Global endpoint: <https://mcp.festapp.net/mcp>.
- Existing regional endpoint: <https://mcp.vstupenky.online/mcp>.
- Separate global ARM64 image, loopback 3400, configuration, signing/encryption
  keys and state; regional loopback 3399 and existing grants retained.
- First-party regional application: `0.20.598+1121`, tenant
  `defdf72778c1c5e6c329fb680f2b73863ce4aafc`, base main
  `74262fe1929f55beb365d994bb0c64c6bc5a33c4`, which contains the MCP UI source.
  Its release owner confirmed canonical direct deployment and three coherent
  public version probes. No separate global ticketing portal release occurred.

See `backend-live-evidence.json` and `image-packaging-evidence-a37389.json` for
the final image, exact-source CI jobs, deployment, configuration and smoke
checks. The earlier `image-packaging-evidence.json` retains original native
provenance and packaging evidence. See
`public-routing-evidence.json` for public routing, issuer/resource metadata,
documentation, legal/support routes and unauthenticated MCP challenge checks.

## Actual OAuth and domain operation

An isolated browser approved separate new, seven-day read-only connections for
one explicitly selected existing regional event and one existing BISCUP event.
The latter used a newly provisioned account with only occasion editor-view
rights, explicitly authorized by the user. Actual GoTrue login and normal
program reads succeeded; a foreign organization returned SQLSTATE 42501.
See `verification-account-evidence.json` for the privileged operational
provisioning audit, not an impersonated manager operation.
A task-owned loopback callback
verified state, issuer and an actual PKCE code exchange. Tokens remain only in
the callback process memory and are excluded from these receipts.

The official modern SDK negotiated pinned `2026-07-28` and the official legacy
SDK negotiated `2025-11-25`, both over public Streamable HTTP. Authenticated
context/access reads succeeded and every exposed tool had a read-only hint.

The actual `festapp_orders_report` result matched the ordinary signed-in
first-party application's `get_operator_order_report_v1` response after
sorting object keys and excluding `generated_at`. See
`normal-app-parity-evidence.json`. The shared SQL report owner, authorization
and calculations were used without introducing a separate MCP report path.

Both contexts rotated refresh tokens and retained authenticated reads. The
BISCUP connection read its actual program through `festapp_events_list`.
Each connection denied the other context's occasion using its real domain read
tool. Forged organization arguments were denied, untrusted Origins returned
403 and both global tokens presented to the regional issuer returned 401.
After UI revocation the regional access/refresh tokens returned 401/400 while
BISCUP still refreshed and read its program. BISCUP was then revoked and
returned 401/400 too. See `live-oauth-evidence.json` for final observations,
including an explicitly cancelled incorrect automation selection.

Installed Codex CLI completed actual static-client read-only OAuth against both
issuers using isolated state and ephemeral loopback callbacks. These are
auth-only checks; SDK tool calls are separately evidenced. See both
`native-codex-oauth-evidence.json` and
`native-codex-global-oauth-evidence.json` receipts. An existing regional ChatGPT app
connection also passed authenticated context/access reads without changing its
grant; see `regional-existing-client-evidence.json`. No new ChatGPT publication
occurred. All named verification grants were removed after testing.

## Canonical operations, SQL and checks

No domain SQL migration was required for this release. The protocol adapter
uses the same `get_operator_order_report_v1`, `manage_program_authoring` and
ticket/layout command owners as the ordinary application. SQL authorization,
calculations, command receipts and side-effect boundaries remain canonical.
The selected broker Function and single-key protected environment migration
are recorded separately in `backend-live-evidence.json`; unrelated Functions,
their shared dependency bytes and the existing regional registry entry were
preserved. Wallet migrations and queue activation were not installed.

The canonical local lanes passed: seat-checkout, navigation-interactions,
client-contract, server-policy, web-startup and wix-checkout-compatibility.
The final CSP server-policy batch passed 133 auth/remote tests, 54 web tests,
16 broker tests and the selected-bundle/environment checks. Earlier failed
preparation checks were fixed and their affected lanes rerun; no failed,
pending, skipped or missing required job was substituted for release success.
All eight required GitHub jobs succeeded on exact final source; their URLs
are in the backend receipt.

`tools/festapp/test/mcp-tree-postgres.test.mjs` ran against disposable PostgreSQL
through the canonical seat-contract lane, covering membership, revocation,
ordinary-app/MCP parity and shared command idempotency. A separate actual
PostgreSQL role check covered one actor's own editor/manager context versus
foreign organizer-viewer context and rolled back its test transaction; see
`cross-tenant-postgres-role-evidence.jsonl`. Production was not used for these
SQL fixtures. Flutter MCP tests passed with concurrency one. An additional
optional font-catalog regeneration test exposed two pre-existing failures
parsing the local google_fonts `aBeeZee` source format. Only the generator's
tests invoke that regeneration helper; the issued runtime and selected bundle
use the checked-in catalog and bundled assets, whose proof passed. No mandatory
gate was replaced by that optional check.

## Directory publication and external follow-up

- [Festapp - Official MCP Registry](https://registry.modelcontextprotocol.io/v0.1/servers/net.festapp%2Ffestapp/versions/0.1.0): published and read-back verified.
- [vstupenky.online - Official MCP Registry](https://registry.modelcontextprotocol.io/v0.1/servers/net.festapp%2Fvstupenky-online/versions/0.1.0): published and read-back verified.
- Glama: both free Hosted submissions accepted, review pending. No public
  listing URL, verified publisher claim, authenticated health test or indexing
  is claimed. Both descriptions say "Published by Festapp"; the personal
  operator profile was retained accurately. After review, claim each connector,
  obtain its exact supported OAuth callback/Test Profile requirements, configure
  only that verified client and confirm healthy public records. Do not infer a
  callback or enable unrestricted registration. Minimum external prerequisite:
  Glama approval and access to each connector's Admin/Test Profile settings.
- [PulseMCP](https://www.pulsemcp.com/submit): submissions paused; automatic
  Official Registry ingestion awaits its resumed pipeline.
- MCP.so: remote form is paid and was not purchased. Recent official GitHub
  issues show manual remote-server listings, but current free availability
  was not established. No paid action or unsupported free-listing claim.

See `registry-publication-evidence.json` for submission/readback results.
There are exactly two identities under Festapp; Festapp Tickets is included
in Festapp. No third duplicate was created. The Glama pending state remains a
real external completion blocker, requiring no new user credential input now.

## Proxy incident and recovery

An initial assembled Caddy candidate omitted the regional site and used the
regional Host for the global upstream. The regional endpoint temporarily
failed TLS and the global endpoint rejected requests. Reloading the restored
host file initially reused the old inode of a read-only single-file container
mount. Recovery loaded the verified complete backup from a distinct
`/config` path inside the container.

The corrected full configuration preserves every byte outside the former
global 410 block and leaves the regional upstream unchanged. It is loaded
from `/config/Caddyfile.global-cfb0b204779f`; the persistent host startup
source has the same digest. Do not overwrite the read-only `/etc` mount or
assume that replacing its host file changes the container's existing inode.
Validate and reload the explicitly staged `/config` path.

Cloudflare Browser Integrity Check separately rejected a standard HTTP client
on the new hostname. A free Configuration Rule
`9e55ea378b9f4f48a7bef72efc54075a` disables only that check for exact host
`mcp.festapp.net`. OAuth, audience, consent, RBAC and other hosts remain subject
to their existing controls. Public probes passed after recovery.

Rollback backup: the protected host evidence directory
`/var/lib/festapp-rehearsal-evidence/global-mcp-20261113-global-transfer/`,
file `Caddyfile.before`, SHA-256
`ee4059ae02013c7d12220513500f4950bb372f92d16efa98f9e274fde3ccc9c9`.
Stage the verified full backup under a distinct writable container path,
validate and reload that exact path. Preserve independent service state and
keys; do not restore unrelated business data.

New credentials are retained and read-back verified in the encrypted macOS
login Keychain. iCloud synchronization has not been verified.
