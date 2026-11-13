# Public integrations API

This connector is generated from the versioned regional `order-summary` OpenAPI
in `tools/festapp/contracts/api-v1/regional-api/profiles/order-summary/`.
It imports no server operation implementation. The API base is
`https://api.vstupenky.online/integrations/v1`; the canonical issuer is
`https://mcp.festapp.net` and resource is
`https://api.vstupenky.online/integrations`. These are prepared release targets,
not a claim that this working tree is deployed.

Use a **new** code + PKCE connection and explicit reconsent. Preserve client ID
`festapp-make`, registered callback, scopes and summary ceiling. Verify callback
`iss` and state. Old regional MCP/Make tokens remain valid only on their old
boundary during the documented migration. No redirects or token copying.

Operations: context.inspect, access.inspect, orders.report, orders.list and
orders.inspect. Each uses POST `/operations/{id}` with its public schema.
Errors are `application/problem+json` (RFC 9457), with `code`, `requestId`,
`retryable` and outcome. Limits return actual Retry-After when available. Scope
and live consent/SQL rights apply to every page and detail. No buyer PII, QR
payloads, internal notes or write operations are exposed by this profile.

Money remains the canonical string/number union defined by the report schema;
never derive types from samples. Keyset pages are not snapshots. The server owns
page size/membership/cursor validation; the connector owns total-run limits.
Page/total-limit Make-specific headers are absent. The connector rejects a remaining cursor at its technical page ceiling unless
the requested result limit is fulfilled. The generated IML ceiling still requires
real Make qualification before publication, especially a blank Limit over a large event.
Do not claim successful complete export after silently stopping a technical cap.

Refresh is single-flight and the rotated token must be persisted atomically.
Do not fall back to the consumed refresh token. A lost token response requires
reconnect. API consent currently lasts at most seven days; refresh never extends
its fixed deadline. No client secret, service-role token or API key is added.

Raw reference and offline docs are shipped with the same API source/image and
projection digest. Read-only SDK evidence confirms an existing legacy reviewer connection and two
known scenarios. Legacy endpoint removal is blocked until actual consumers migrate.
