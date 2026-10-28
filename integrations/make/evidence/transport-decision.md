# Native transport decision - 2026-10-28

Chosen: one thin JSON HTTP adapter in the existing regional OAuth service.
All calls retain `DelegatedOwner` and `Operations.invoke`. There is no new
order projection, authentication system, database migration or service token.

The real Make native OAuth connection 12447881 completed PKCE S256 against
`festapp-make`. Scenario 8226665, execution `d87b441065ac4b7dbdc7cd7fb2717fd9`,
failed with `Invalid module output. Expected Object, but found String.` when
using the complete initialize/initialized/report MCP request sequence.
The SDK uses SSE for the legacy 2025-11-25 wire protocol. The SDK Functions
endpoint also returned HTTP 403 `IM002`, requiring `apps edit` administrator
permission. Do not maintain an ad-hoc SSE parser or another MCP implementation
inside Make. Replace the private prototype's communication with the chosen
JSON transport; no prototype module will be published.

## HTTP contract

Origin: `https://mcp.vstupenky.online`.

`GET /make/v1` serves public OpenAPI 3.1 documentation derived from the same
canonical catalog and summary profile. It contains schemas, not live data.

`POST /make/v1/operations/{operation}` accepts the **canonical operation input
object**, without an additional DTO. Allowed operations are `context.inspect`,
`access.inspect`, `orders.report`, `orders.list`, `orders.inspect`. Inputs and
outputs are generated from `Operations.catalog` with `orderSummaryOnly: true`
and the registered two-scope ceiling. The response is the canonical
`{ok, operation, data?, error?, meta}` envelope. Transport validation failures
use `{ok:false,error:{code,message,retryable}}` with no domain data.

Only `festapp-make` tokens with `order-summary` profile can use this route.
Other clients, unknown operations, artwork and all writes are forbidden.
The existing token verifier, stored consent, current roles, revocation,
concurrency counters and rate limits are shared with `/mcp`.

Audience strategy: **one existing protected resource**,
`https://mcp.vstupenky.online/mcp`, covers these two explicitly defined
transports of the same delegated service. Both authorize/token/refresh requests
continue to name that exact resource. The verifier still checks `aud` against
`config.resource`; arbitrary resource values and other origins are not accepted.
This is an explicit transport alias for this one client, not permission to use
the token at arbitrary APIs.

Status mapping: 200 success, 401 expired/revoked authentication, 403 denied
client/profile/operation/scope, 404 inaccessible detail when reported by the
canonical operation, 422 invalid input, 429 throttling, 504 timeout, 502 upstream
or schema failure. A failed canonical operation never becomes a successful
Make bundle. Other HTTP methods return 405. No endpoint redirects a bearer.

Lists keep the canonical page limit 50 and descending ID cursor. The adapter
rejects non-descending rows or a next cursor that differs from the last row.
Make sends the page number in `X-Festapp-Make-Page` and the requested total
limit in `X-Festapp-Make-Total-Limit`. Empty total means all available results
within technical bounds. At page 50, a further cursor fails explicitly with
409 `PAGINATION_LIMIT_EXCEEDED` unless the requested count was reached. These
headers affect export bounds only, never authorization. The module must request
50 rows per page. Make's separate 40-second execution bound can fail sooner.
Earlier bundles and external writes are not rolled back by a later failure.

The universal module constructs URLs under the fixed origin and `/make/v1`
prefix, accepts only relative operation paths, exposes POST only, and uses the
same server allowlist and canonical schema validation. It cannot select another
origin or supply a different Authorization header.

State: JSON transport deployed from canonical main `903145af65e4a3c1944464078c472bee26400ae9`. Real Make report execution `1e9f8f1a4876485189167788c594ee77` succeeded after refresh of the expired access token. Full-module qualification is in progress.
