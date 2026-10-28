# vstupenky.online read API

This is the API used by the official first-party Make connector. It adapts the same Festapp operation catalog, authorization and order-summary projection as the remote MCP service. No separate order, payment or permission implementation exists in the connector.

Service origin: `https://mcp.vstupenky.online`
OpenAPI 3.1: https://mcp.vstupenky.online/make/v1
[Generated canonical operation schemas](src/generated/schemas.json)
[Connection setup and user guide](SETUP.md)

## Authentication

OAuth authorization code with mandatory PKCE S256, public client `festapp-make`, no client secret. Authorization endpoint `/auth`; token endpoint `/token`; exact callback `https://www.make.com/oauth/cb/app`; OAuth resource `https://mcp.vstupenky.online/mcp` (explicit alias for this adapter). Dynamic client registration is disabled.

Registered read scope ceiling: `festapp:ticket-layouts:read`, `festapp:orders:read`. The event selection and permissions approved by the user further restrict each grant. Every request and refresh checks current authorization. A 300-second access token refreshes automatically; refresh tokens rotate. The server delegation has a fixed seven-day expiry that refresh cannot extend. Reauthorization is required after expiry or revocation. The summary context deliberately contains no account identifier, name or contact information.

Authenticated operation requests use `Authorization: Bearer <access_token>` and `Content-Type: application/json`. Never put tokens in URLs or share tokens between clients.

## Available operations

These are **all five operations exposed by this API version**. Every operation uses POST. A read API may use POST for typed JSON input without permitting domain writes. Other methods return HTTP 405. Unknown operations, write operations and unconsented event IDs are rejected.

| Relative path | JSON input | Successful `data` |
| --- | --- | --- |
| `/make/v1/operations/context.inspect` | `{}` | `backend`, `enabledOperations`, `writesEnabled: false` |
| `/make/v1/operations/access.inspect` | `{}` | `units`, `occasions` within current consent and permissions |
| `/make/v1/operations/orders.report` | `{"occasionId":1072620}` | One canonical `report` with counts, currencies, amounts and warnings |
| `/make/v1/operations/orders.list` | `{"occasionId":1072620,"limit":50}` | `occasionId`, `orders`, `nextCursor` |
| `/make/v1/operations/orders.inspect` | `{"occasionId":1072620,"orderId":123}` | Exactly one authorized matching row in `orders`; errors never become empty success |

The IDs above illustrate retained synthetic data; they do not grant access. The universal module can call any of these five authorized endpoints, including `context.inspect`, which has no dedicated module. Its URL must be relative to the service origin. It does not expose the MCP wire protocol, OAuth endpoints or other issuer routes.

## Pagination and fields

`access.inspect` returns the complete consent-filtered event list in one response. It has no cursor, page argument or hidden additional pages. The List accessible events module applies its total bundle limit; its RPC offers up to 500 options. Use an event ID in mapping mode if it is outside this option sample. Identical event names remain distinct by ID.

`orders.list` returns up to 50 orders per backend page. For the next page, repeat the event and filters and supply `before: <nextCursor>`. A null cursor means completion. Optional `search` accepts one exact 10-character order symbol, not a partial symbol or buyer contact. Optional `state` is the exact stored state string; the canonical API has no fixed enum, so the connector does not invent one. An unknown state can yield an empty list.

Public order fields: numeric `id`, `occasionId`, `ticketCount`; nullable text `symbol`, `price`, `currency`; text `state`; `allowedActions` restricted to `view`; nullable `payment` containing nullable decimal-text `amount`, `paid`, `returned`. Amounts retain their exact stored text and currency. No buyer contacts, names, registration responses, notes or QR content are returned.

The canonical report is passed through, preserving numeric and decimal-text money as supplied. Its `occasion.id` is text, while operation inputs and public order/event IDs are safe positive integers. This existing report representation is intentional; do not silently coerce report money or identifiers. `report.generated_at` is an ISO timestamp; the Make module declares and parses it as a date. Event capabilities include the literal key `ticket_layouts.read`; Make IML accesses it with backticks.

## Errors and technical bounds

Success envelope: `{"ok":true,"operation":"...","data":{},"meta":{...}}`.
Failure envelope: `{"ok":false,"error":{"code":"...","message":"...","retryable":false}}` with an appropriate non-2xx HTTP status. Some protected-resource authentication failures use OAuth's `{"error":"invalid_token"}` shape. The connector handles both.

- 401: expired, revoked or invalid connection; reauthorize.
- 403: missing consent, current rights, wrong client/profile or forbidden operation.
- 404: an authorized requested detail is missing; inaccessible canonical details may return 403.
- 409 `PAGINATION_LIMIT_EXCEEDED`: an export exceeded a technical bound.
- 422: invalid input or unknown body fields.
- 429: shared request/rate limit; honor `Retry-After` and retry later.
- 5xx: temporary service failure or rejected upstream contract; never interpret as zero sales.

The native list module sends `x-festapp-make-page` (one-based page) and `x-festapp-make-total-limit` (requested total). A blank total means unlimited within technical bounds, not zero. These headers enforce completion boundaries and never grant access. A request cannot silently end at the 50-page boundary when more records were requested. Make also has execution bounds. Lists are not database snapshots; an external app may already have written earlier bundles before an error. This connector performs no destination writes or rollback.

## Contract ownership

Report computations remain in `get_report_ws.sql`, through the scoped operator wrapper. `tools/festapp/src/operations/order-report-schema.mjs` owns the known report shape used by both `orders.report` and `reports.export`; optional provider/deposit blocks and unknown extensions survive. Report event/product IDs remain text. Money retains its numeric or decimal-text representation, without conversion. OpenAPI and Make interfaces derive from this schema, never samples. Make uses `any` for mixed scalar unions and collections for dynamic records; the complete value schema remains in OpenAPI and the generated schema artifact.

`make-contract.mjs` owns client identity, the read allowlist and distinct transport limits. Backend page size derives from the operation input schema; the 50-page completion guard, 3200 public input cap, default total 10 and RPC sample limit 500 retain separate meanings. The input cap is not a guarantee that an export can complete before the page guard.
