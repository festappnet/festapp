# ChatGPT MCP pilot - 2026-10-26

Current status, 2026-10-27: regional deployment and authenticated ChatGPT consent
completed at `https://mcp.vstupenky.online/mcp`; ChatGPT discovers six read tools.
Live report/list/detail/search, scope denial, continuity across token expiry
and immediate revocation passed. Remaining adversarial cases are recorded below.
Earlier observations are historical. This record does not claim public directory approval.

Implementation authority: [hardened plan](../plans/chatgpt-mcp-plan-2026-10-26.md),
revised 2026-10-27 for client portability and efficiency. The public checks here
are historical observations, not proof that its new client scope ceilings are
implemented. A base-only bare-URL OAuth connection does not establish order-read
access; use explicit read scopes as described in that plan.

## Scope

Use the existing Festapp ticketing tenant (vstupenky.online), remote issuer and
ordinary operator identity. Start with selected occasions and read permissions:
`festapp:ticket-layouts:read` and, if supported by the current client configuration,
`festapp:orders:read`. Do not request creation, editing, payments or ticket delivery.
No completion of the remaining administration MCP roadmap is required.

The live issuer advertises order-read scope, and source descriptors include
`festapp_orders_report`, `festapp_orders_list` and `festapp_orders_inspect`.
Neither fact proves these tools are enabled for an authenticated live connection.
Confirm its discovered tools before promising sales/order functionality.

## Public checks performed

Unauthenticated HTTPS requests from this workstation on 2026-10-26:

| Request | Observed result |
| --- | --- |
| GET `/healthz` | 200 JSON, `ok: true` |
| GET `/.well-known/oauth-authorization-server` | 200 JSON; issuer `https://mcp.festapp.net`; authorization-code flow and S256 advertised |
| GET `/.well-known/oauth-protected-resource/mcp` | 200 JSON; resource `https://mcp.festapp.net/mcp`; matching authorization server |
| POST `/mcp`, MCP initialize without credentials | 401 JSON `invalid_token`; Bearer challenge points to the resource metadata and base read scope |
| GET `/mcp` | 405; use protocol POST, not a browser page GET, to assess authentication |

No user/business records were read or changed. No configuration, deployment,
OAuth grant or billing was changed. Historical missing-DNS blockers in
`../architecture/operations/remote-mcp-auth.md` are superseded only by the public
checks above; other historical gates must be reconciled separately if deploying.

## Connect the pilot account

1. In the intended ChatGPT account/workspace, open Plugins, then Add custom MCP
   server. Account/workspace policy must allow this feature.
2. Name: `Festapp`. Server URL: `https://mcp.festapp.net/mcp`.
3. Choose OAuth with the existing registered public client `festapp-chatgpt`,
   no client secret. Automatic client registration is disabled. If the interface
   cannot configure the registered client/scopes, stop and use the documented
   registered-client configuration route rather than weakening the issuer.
4. Compare ChatGPT's actual redirect URL with the registered callback. Source
   documents `https://chatgpt.com/connector_platform_oauth_redirect`; this is
   prepared configuration, not a callback confirmed in this account today.
5. The operator completes first-party login and explicitly grants selected
   occasions and read permissions only. Passwords/tokens must not be copied
   into chat, source files or this record. Existing MFA issuance limitations
   must fail closed; do not disable MFA to get the pilot working.
6. Install the connection and inspect its discovered tool names. Record only
   non-sensitive capability information and sanitized outcomes below.

## Acceptance scenarios - prepared, not yet executed

- Ask which occasions this connection may access. Expect only consented and
  currently authorized occasions (`festapp_access_inspect`, if exposed).
- Ask for a sales summary of one selected occasion. If order-read tools are
  available, expect `festapp_orders_report` and real returned counts. Otherwise
  record the missing capability; never invent a sales result.
- Ask for unpaid orders, if the discovered list tool supports the necessary
  filtering. Expect bounded results for the selected occasion; avoid copying
  customer details into evidence.
- Ask to read an occasion outside the grant. Expect denial without its data.
- Ask to cancel an order or send tickets. Expect no mutation under this read
  grant. Do not execute a real write to demonstrate the rejection.
- Disconnect through `https://mcp.festapp.net/connections`; attempt a previously
  allowed read while the former access token would otherwise still be valid.
  Expect denial. Distinguish ChatGPT uninstall from issuer-side revocation.

## Costs and publication

The fetched OpenAI submission documentation does not specify a listing/review
fee. This is not a contractual guarantee of free publication. Account feature
availability and our MCP hosting remain separate costs. This pilot introduces
no OpenAI API model call; any future model calls from Festapp would be separately
metered under their provider's pricing.

Claude is outside the current implementation scope. Its current submission
documentation requires a paid Claude plan and does not specify a separate
listing fee. No subscription or paid service was purchased.

Public ChatGPT submission follows successful authenticated pilot acceptance:
verified publisher, listing/legal/support URLs, safe demo account, five positive
and three negative review cases and a walkthrough. These materials are not
completed or submitted by this readiness record.

Sources checked 2026-10-26:

- https://developers.openai.com/plugins/quickstart
- https://developers.openai.com/plugins/deploy/submission
- https://learn.chatgpt.com/docs/plugins
- https://claude.com/docs/connectors/building/submission

## Remaining evidence

Pending: intended ChatGPT account feature availability, actual redirect/client
configuration, ordinary-user login/consent, authenticated tools list, acceptance
outcomes and revocation. These require the operator's account authorization;
public health and fixture tests cannot establish them.

## Execution update - 2026-10-27

Status: local implementation and focused checks passed; **regional production
cutover is not performed and the ChatGPT pilot is not accepted**. The user now
requires the final regional URL **before any further ChatGPT setup**, superseding
the old-address setup steps above. Current live URL remains
`https://mcp.festapp.net/mcp`; approved target is
`https://mcp.vstupenky.online/mcp`. The new hostname does not resolve publicly yet.

The [authoritative plan](../plans/chatgpt-mcp-plan-2026-10-26.md) adds a mandatory
regional cutover phase. [Branding and URL evidence](../plans/chatgpt-mcp-branding-and-urls-2026-10-27.md)
records the two product identities, directory rules and the discrepancy between
OpenAI's detailed and general URL-change instructions. No global domain was
invented or provisioned, and no second production client was registered.

### Actual account observation

The user explicitly authorized operating a new tab in their logged-in ChatGPT
account. The existing private cloud plugin was present and unconnected. Its
connection route successfully reached the first-party consent page through the
registered ChatGPT client, using the existing app session. The observed capability
summary contained only base read access, without order reads. Consent was
cancelled without selecting an occasion or creating an accepted pilot grant.
No sales/order answer, normal live token-expiry follow-up or live revocation test
was completed. Further connection work is paused until the regional cutover.

The private app name was changed from `Festapp` to `vstupenky.online`; its
region-specific description explains that the service runs on Festapp. No public
listing, upload or submission was made. The downloaded private plugin ZIP was an
existing integration reference (`.app.json`), not evidence that explicit order-read
scopes are saved. The reviewed private connection config in `integrations/chatgpt`
now targets the final hostname, uses the existing provided public client and
requests both read scopes. It must be installed/verified after cutover; a base-only
personal connection is not an acceptable substitute.

### Changed source contract

- One shared hosted-operation lookup returns base and transitive domain scopes;
  unknown operations fail closed. The local CLI does not acquire OAuth gates.
- Optional `clients[].allowedScopes` validates known scopes/dependencies, limits
  issuer consent/issuance, rejects obsolete wider refresh credentials, and narrows
  invocation even for old wider grants/tokens. Omitted ceilings retain existing
  client behavior. Requested base scope is required rather than silently added.
- The shared SDK registration/result serializer publishes top-level authentication
  metadata plus an identical `_meta` mirror and useful read-tool titles. Text JSON
  and structuredContent are preserved; no token-savings claim is made.
- Missing scope has HTTP 403 with a complete scope challenge only when allowed by
  client policy. Ceiling/resource/right denial has no escalation. Lost identity
  uses HTTP 401 or a matching during-call linking result; MFA revokes the unusable
  delegation. Upstream status is retained by order adapters for safe throttling
  and denial classification. A PostgREST-serialized network timeout is a retryable
  unavailable result, not an invented login failure.
- SQL action labels are constrained by actual delegated operations, retaining
  `view` for read-only orders and withholding write actions. SQL business owners,
  totals, decimal money, currency and pagination remain unchanged.
- Regional branding is optional deployment metadata, absent for the global
  product. The first-party exchange now supplies its configured issuer with a
  continuation. The browser validates the exact origin/path/proof against this
  protected-registry value, allowing a coordinated URL migration without a
  hardcoded old-domain fallback. Request bodies cannot select that issuer.
- Caddy's regional site and private config target `mcp.vstupenky.online`; Compose
  probes use the issuer from the protected runtime config, supporting both the
  hardening stage and final cutover without a second health authority.

### Checks and their limits

Final evidence: [sanitized local receipt](chatgpt-mcp-local-2026-10-27.json).
Node runtime: 24.20.0; pnpm: 11.24.0. Retained passing inputs cover 45 Node checks
(37 remote, 1 real PostgreSQL order test, 4 readiness, 2 stdio, 1 image import),
39 consent/account UI checks and 12 Edge broker/config/management checks, with
zero skips. The final remote suite includes both protocol eras and two synthetic
registered clients, callback/PKCE/resource checks, explicit read catalogs, forced
writes, cross-client separation, expired access with refresh, replay revocation,
grant expiry, encrypted restart, during-call auth/MFA/throttling/errors and
in-flight revocation through the delegated owner.

The marked `festapp-authz-20261020` PostgreSQL fixture on 61022 passed marker,
cron-off and paused/null-worker email guards. Real canonical SQL covered totals,
filters/search, a 50-item boundary with a further page, read-only action projection,
rights removal, writes/replay/payment/mail intent invariants within rollback.
The remote protocol fixture simulates Auth responses; an additional explicit
[real local runner](../../tools/festapp/test/local/README.md) then passed real
GoTrue -> production Edge exchange -> issuer -> ordinary-user SQL. Its own
Auth/REST containers used the guarded authorization DB and matching signing/
verification keys. The existing local service-template project's database,
services and cron were not changed. The runner verified allowed/denied actors,
an independent real session, six read tools, selected-occasion narrowing, empty
canonical report/list, live role removal and issuer-side revocation. It removed
its synthetic rows, own containers and private temporary files. The historical
absolute-path consent runner was not run. This proves local integration, not a
live ChatGPT conversation; the receipt labels its loopback transport boundary.

The same 51-order fixture measured serialized bytes, one tool call per task,
backend request count (five per measured read), and three warmed timing samples
per selected result and protocol. These are local fixture measurements, not live
ChatGPT latency or tokenizer counts. No private-data/rights/revocation cache or
DTO truncation was introduced. The regional paragraph was inspected in isolated
headless file previews at 390 and 1280 px; the global variant omitted it and had
no horizontal overflow. No preview server or browser session remains running.

### Existing live source and release gate

A concurrent approved release advanced authoritative main from `00c1da5ce` to
`b58e2bbd3` with documentation only. The final read-only deployment probe confirmed
image `sha256:c8f7fcb2a6e29086660c632c0fb29101f752b756bd2ede29e4922c0eba18f9b8`,
healthy, matching the recorded deployment of source
`00c1da5cef9bb1e949bf230f270f221b1b9f69d8`. Selected live server/order source
hashes match that source. Public health/metadata return 200; unauthenticated MCP
returns 401. The exact registered `festapp-chatgpt` exists with no `allowedScopes`.
Thus this is **not** the new read-only client-policy deployment. These final
read-only probes were delegated under the standing cheaper-agent release rule.

Current main protection requires one independent approving review. Prepare the
reviewed canonical source before deploying; no administrator bypass is performed.
No production source/config/DNS/issuer state, Edge registry or first-party web
release was changed by this task. Wrangler auth is available, but the observed
OAuth permissions include zone read and omit DNS write; provisioning must use an
authorized DNS-management path rather than assume that token can edit records.

Next gated execution: merge reviewed source,
then delegate the bounded regional cutover using that exact main SHA and immutable
image. Stage hardened sidecar/registry responses and compatible first-party web
before switching issuer/state/DNS, preserve protected keys/backups/client ceilings,
require new consent for changed issuer/resource, and verify the final regional
host before resuming ChatGPT. No old-address pilot acceptance or public package
can close these gates. Rollback must retain the read-only ceiling; it must never
reactivate broader historical grants just to start an old image.

### Source publication gate

Implementation revision: `c278a48baeb715eea636677dcac3a36622149bb9`, rebased onto
canonical main `b58e2bbd3cf2f6220c3452805985dab5675bc82f`. Only release documentation
advanced upstream; validated source-file hashes remained unchanged. Source is
published for required review in [PR #621](https://github.com/festappnet/festapp/pull/621).
The source PR is not a deployed regional issuer. No immutable candidate image
has been promoted and no ChatGPT acceptance can be claimed until cutover.

## Regional deployment and live account evidence - 2026-10-27

This section supersedes the pending deployment/account statements above.

- Canonical source: `c58c1e03087f5be03b988692b707836bde8ff489` (PR #621),
  translation publication fix `fdc8ecb27e80379bbf25bf364c134c5731f0e6b2`
  (PR #622), canonical Festapp terminology `ae2f9c929146d2fe924a2069c7f5127609539562`
  (PR #623). The standing brand rule is recorded in `CLAUDE.md`.
- Regional issuer/resource: `https://mcp.vstupenky.online/mcp`. Proxied DNS,
  TLS, health, both metadata documents and unauthenticated protocol challenge
  passed. The old host returns HTTP 410, without redirecting credentials.
- Sidecar image: `sha256:cfc895e8e58d19e0833763cb6c24d4691b4ab803dbd6b7a5af8b3448ded09819`,
  source label `c58c1e03087f5be03b988692b707836bde8ff489`. Canonical Compose
  health reads the configured issuer; container is healthy. Protected keys were
  retained, regional state is fresh, existing revoked grants were not reactivated.
- Edge handler SHA256: `ec8239d351c1c47188f68fbee33a4d9c8f09cebd0c2299dcdd058c3d100cca3e`.
  Only the selected tenant's protected registry entry changed. Database and
  other tenant configuration remained outside this rollout.
- Selected tenant `prod/festapptickets`, organization 3: deployed source
  `0758a992f6ed292679185cdace7659fbb9950b3d`, base main `fdc8ecb27e80379bbf25bf364c134c5731f0e6b2`,
  version `0.20.428+930`. Direct local release passed drift, sealed manifest and
  three coherent live probes. Pages deployment `b6a7125c-8510-47ac-ac48-1172aad05bea`.
- The private ChatGPT app is named `vstupenky.online`; its description explains
  that the regional portal runs on Festapp. The account form accepted public
  client `festapp-chatgpt`, no secret, PKCE S256 and the exact registered callback
  `https://chatgpt.com/connector_platform_oauth_redirect`. Only the two read
  scopes were selected; automatically discovered write scopes were deselected.
- First-party consent completed using the ordinary app session and only occasion
  99, in the existing test organization. No whole-unit or future-event grant.
  ChatGPT discovered exactly `festapp_access_inspect`, `festapp_context_inspect`,
  `festapp_orders_inspect`, `festapp_orders_list`, `festapp_orders_report`, and
  `festapp_ticket_layouts_inspect` in its Read 6 group.

### Reported consent-page loop

The affected tab loaded document version `0.20.428+930` while its active service
worker was `0.20.427+929`; the matching `0.20.428+930` worker was waiting.
The tab initially rendered blank, then displayed an untranslated regional key
and the application's recovery banner. Using that existing banner's refresh
action activated the prepared version. The consent page then rendered its full
Festapp explanation, no recovery banner, and completed the return to ChatGPT.
No browser-wide cache, login storage or unrelated tabs were cleared. This was
an observed recovery of this installation, not a new service-worker code fix.

### Executed live reads

The task-owned ChatGPT conversation completed access inspection, sales report
and a bounded five-row order read against occasion 99. Access inspection returned
only the selected occasion and no delegated whole units; `writesEnabled` was
false. Report/list answers distinguished orders from tickets, current value
from received payments, preserved CZK, and explained that five rows did not
cover the sixth order in the requested stored state. Customer personal data
was excluded from the prompt and answer evidence. Despite its name, this
existing test occasion is populated; it is not an empty-results fixture.

The follow-up successfully read a test order detail, explained its stored state
and missing payment, then found exactly the same order by its returned symbol.
The detail advertised only `view`. A report request for unconsented occasion 1
returned domain `FORBIDDEN`, no business data and `retryable: false`; ChatGPT's
runtime wrapped the tool error as `INVALID_ARGUMENT` while retaining that domain
payload. Neither cancellation nor ticket-delivery tools were advertised or run.

At 00:35:18 UTC a newly requested report succeeded, followed at 00:35:21 UTC by
a bounded search for a unique nonexistent test string: `orders: []`, no next
cursor. This is over five minutes after the first successful report, while the
issuer source explicitly uses `accessTokenTTL: 300`. The account continued
without login or reconsent, establishing continuity across normal token expiry;
the opaque refresh-token exchange itself was not inspected or logged.

The first-party connections page then removed the test delegation. An immediate
fresh report request in the same ChatGPT conversation returned no report and
displayed "Your vstupenky.online connection has expired" with Reconnect. This
was within the new access-token window and proves immediate revocation rather
than waiting for token expiry. The same private app was reconnected with the
same selected occasion; no replacement app or broader grant was needed. This
second consent page loaded immediately with the correct regional explanation
and no recovery banner or reload loop.

After the operator completed that new consent, ChatGPT automatically resumed
the suspended report request. It succeeded at 00:37:38 UTC, request ID
`4d4fb398-0143-438e-a9f0-e199c2424021`. Its initial answer incorrectly interpreted
that post-reconsent result as an ineffective revocation because the earlier
prompt still described the revoked state. The operator supplied the missing
UI/reconsent chronology in the conversation. Keep the expired-connection gate
and the later newly authorized result distinct; the latter is not evidence of
access under the revoked delegation.

Full wave 4 acceptance and public submission remain unclaimed: the existing
local hostile-note fixture is not relabeled as an executed live case, and
ambiguous-selection handling has not been exercised live.
