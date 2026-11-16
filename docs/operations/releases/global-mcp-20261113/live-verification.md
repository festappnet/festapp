# Global MCP production verification - 2026-11-13

Both service images: `95aa06a21898ee5a4eee09ec79f3543b86a1e8a5`.
Selected broker Function source: `09cdd991fa30dd848324df586e188040931d3bd2`.
The earlier preparation inventories in this directory describe the pre-release
state. This document and the accompanying final receipts describe live checks.
Production verification passed. Both Official MCP Registry records are public.
Both canonical Glama records are public, claimed, branded and search-indexed.
Both show Healthy and Works in Glama; actual OAuth and post-expiry refresh
verification passed. The earlier
manual duplicate records are deprecated with explicit canonical replacements.

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
- First-party regional application: `0.20.598+1123`, tenant
  `e6f652544a9e6f6e0e71d95e86ce34aee02fed07`, base main
  `95aa06a21898ee5a4eee09ec79f3543b86a1e8a5`, including the shared consent modes.
  Its release owner confirmed canonical direct deployment and three coherent
  public version probes. No separate global ticketing portal release occurred.

See `backend-promotion-95aa-evidence.json` and `image-packaging-evidence-95aa.json`
for the final image, eight exact-source CI jobs, preserved configuration/keys/state,
public TLS probes, deployment, rollback and disposable smoke checks.
`backend-live-evidence.json` and `image-packaging-evidence-a37389.json` retain the
earlier broker installation and CSP release provenance. The earlier `image-packaging-evidence.json` retains original native
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

- [Festapp - Official MCP Registry](https://registry.modelcontextprotocol.io/v0.1/servers/net.festapp%2Ffestapp/versions/0.1.2): published and read-back verified.
- [vstupenky.online - Official MCP Registry](https://registry.modelcontextprotocol.io/v0.1/servers/net.festapp%2Fvstupenky-online/versions/0.1.2): published and read-back verified.
- [Festapp - Glama](https://glama.ai/mcp/connectors/net.festapp/festapp) and
  [vstupenky.online - Glama](https://glama.ai/mcp/connectors/net.festapp/vstupenky-online):
  canonical Official Registry imports, verified ownership, logos and public
  publisher Festapp/First-party. Both appear in public search. The two manual
  copies were deprecated through the supported replacement UI and disappeared
  from search; historical URLs remain accessible. DNS ownership TXT records
  must remain for daily verification. Both show Healthy and Works in Glama;
  authenticated checks and post-expiry refresh passed.
- [PulseMCP](https://www.pulsemcp.com/submit): submissions paused; automatic
  Official Registry ingestion awaits its resumed pipeline.
- MCP.so: remote form is paid and was not purchased. Recent official GitHub
  issues show manual remote-server listings, but current free availability
  was not established. No paid action or unsupported free-listing claim.

See `registry-branding-publication-evidence.json`, `glama-consolidation-evidence.json`
and `catalogue-followup-receipt.md` for publication and public readback results.
The initial `registry-publication-evidence.json` is retained as historical evidence.
There are exactly two identities under Festapp; Festapp Tickets is included
in Festapp. No third Festapp Tickets identity was created. Glama autoimport produced two
extra records alongside the manual submissions; these were consolidated onto
the Official Registry identities and the manual duplicates were deprecated.
The public publisher is Festapp. Reverse-DNS namespaces remain technical
registry identities rather than a replacement for the brand.

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

## Final consent and canonical contract

The shared permission contract owns three consent choices: requested functions,
requested read-only functions, and basic connection/access/ticket-layout metadata.
Both first-party web consent and the issuer form use that same projection.
The existing broker consent payload remains version 2; there is no parallel
business implementation or new authorization owner. Basic/read-only choices
remove creation rights as well as functional writes. Unknown choices fail closed.
The provider records declined scopes so partial consent finishes without a loop;
refresh retains the approved scope ceiling. Current SQL rights remain mandatory.

The catalog contains 196 operations and 83 functional permissions, plus the two
existing foundation scopes. The audit found 38 read scopes, 45 other scopes,
no duplicate mappings, missing operations, dependency cycles or read/write
classification mismatches. Client/grant discovery can expose a subset; the full
supported catalog is documented at
<https://vstupenky.online/napoveda/mcp-podporovane-operace/>. Account login and
connection management remain first-party security flows. Application variants
continue to limit available domains; ticketing does not gain BISCUP program rights.

The final source also repairs the canonical disposable Docker smoke harness:
Compose itself resolves the port and health probe from explicit synthetic inputs,
without loading a workstation/production .env file. The exact final image passed
startup, duplicate-owner rejection, SIGKILL recovery, Caddy validation, spoofed-IP
handling, quota and health checks. No production database was used as a fixture.

On final source 95aa, fresh uninterrupted OAuth flows again passed for both
selected tenant contexts with modern and legacy MCP SDKs over public HTTP.
Ticket report and program digests matched the recorded ordinary-app results;
foreign context, foreign Origin and wrong audience were denied, both refresh
credentials rotated, and one grant's revocation left the other usable. See `live-oauth-95aa-evidence.json` for completion and cleanup evidence.
Both temporary grants were revoked and returned access/refresh 401/400. The
task-owned loopback listener was closed and its process terminated; token values
were held only in process memory. The retained catalogue health grants are
separate and intentionally remain active.

The selected first-party web build, sealed artifact and three coherent live
version/legal/build probes are recorded in `web-release-1123-evidence.json`.
The existing regional native connection preserved its account, tenant, organization
and granted tool set after the image promotion; see
`regional-existing-client-95aa-evidence.json`.

## Glama authenticated health and renewal

Both canonical Test Profiles persist OAuth Authenticated after fresh navigation.
First successful tests were at 06:38:43 UTC (global) and 06:41:15 UTC (regional).
After the 300-second access-token lifetime, actual Glama Test Connection passed
again at 06:47:30 and 06:47:33 UTC without another OAuth flow. Independent,
read-only inspection of each issuer's encrypted SQLite records confirmed the
same single issued, unrevoked grant, one selected occasion, zero units and empty
functional permissions. New access tokens were issued after the initial tokens
expired, refresh credentials rotated, and scopes remained exactly
`festapp:ticket-layouts:read`. No bearer values, account identities, authorization
codes or request nonces are included in the receipts.

These health grants intentionally remain active for the explicitly selected
365-day consent period. Refresh credentials have a rolling 30-day lifetime and
cannot extend the consent deadline. Reauthorize before the November 2027 consent
deadlines if continued catalogue monitoring is desired. The dedicated account's
canonical listed-demo affordances do not widen the grant to other occasions,
orders or writes; see `glama-health-account-evidence.json`.

Both stale Redirect URI checks were refreshed through the supported Re-check UI
and now show Works in Glama. Public detail pages show Healthy; public Festapp
search returns exactly two healthy canonical results and excludes deprecated
copies. Historical alert emails were from the autoimported canonical records,
which originally had no authenticated test profile. The latest matching mails
still predated the correction when checked after the successful tests. Alerts
were not unsubscribed or muted, and no support email was sent.

See `glama-live-health-evidence.json`, `glama-refresh-verification-evidence.json`
and the four initial/post-refresh snapshots for the client and issuer evidence.

## Outcome-focused catalogue copy update

Metadata-only Official Registry version 0.1.2 was published from exact source
45423958d54255ee9db7ddbb042ce9ea16e6c9ce after eight successful required checks.
Public readback confirms both descriptions, existing titles, icons and endpoints;
the latest namespace query still contains exactly two identities. This did not
change or redeploy the production runtime.

The descriptions now explain concrete event preparation: event creation, program,
hall/table/seat layout, ticket categories and prices, orders, sales and check-in.
`catalogue-copy.json` maps these claims to existing canonical operation IDs and
retains both English and Czech variants. Venue wording means the hall/seating
plan, without promising a venue-booking directory or merchant onboarding.

Glama publicly matches the full 567/558-character descriptions and remains
Healthy / Works in Glama. The native listing override preserves its richer text
from the registry's 100-character description limit; connection metadata and
health credentials remain unchanged. Both review issues and the external PR also
carry the improved copy, with successful submission validation. Pending
MCPservers.org forms cannot currently be edited through a supported route; their
older text is retained until review, without creating duplicate submissions.

See `catalogue-copy-registry-evidence.json`, `catalogue-copy-glama-evidence.json`
and `catalogue-copy-github-evidence.json` for exact text hashes and public results.
