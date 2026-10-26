# Explicit real local MCP pilot integration

`pilot.e2e.mjs` runs real GoTrue, the production Edge exchange handler, the OAuth
issuer and ordinary-user canonical SQL. It is opt-in rather than a skipped test
in the normal Node suite. Use Node 24, pnpm 11.24.0, Deno and local Docker.

Prepare the guarded authorization database with
`bash automation/authorization/prepare-local.sh`. Privately configure its
`FESTAPP_AUTHORIZATION_DATABASE_URL`; the runner requires the same explicit
61022 URL in `FESTAPP_MCP_TEST_DATABASE_URL`, verifies its marker and retains
cron-off and paused/null-worker email guards. No remote URL is accepted.

Explicitly select a running **local** Supabase service-template project. On this
workstation the tested source was `festapp-notification-feed-e2e-20261026`:

```sh
FESTAPP_MCP_TEST_DATABASE_URL="$FESTAPP_AUTHORIZATION_DATABASE_URL" \
FESTAPP_MCP_LOCAL_TEMPLATE_PROJECT=festapp-notification-feed-e2e-20261026 \
FESTAPP_MCP_LOCAL_RECEIPT=/tmp/festapp-mcp-real-auth-receipt.json \
pnpm --dir tools/festapp exec node test/local/pilot.e2e.mjs
```

Only its existing local Auth/REST image/environment templates are read. The
source project's services, database, users, cron and configuration are not changed
or called. The runner starts its own containers attached to the marker-verified
authorization database, disables external Auth hooks, and keeps signing/verifier
key sets paired. Secret environment files live only in a private temporary
folder. It creates and removes only its new synthetic organization/users/events;
all operation reads use the minted ordinary-user delegation, never service-role
SQL. Auth admin access is limited to fixture setup and the existing real broker's
session issuance. The runner removes its own containers and temporary files.

Ports 61421, 61425, 61426, 61431 and 61432 must be free. The explicit loopback
HTTP proxy/TLS-config mapping is a test transport boundary; it does not establish
public TLS or actual ChatGPT acceptance. The separate remote test fixture owns
the two-client protocol matrix and byte/call/timing measurements; this runner does
not duplicate that benchmark.

The historical `consent.e2e.mjs` is not this runner and retains its historical
absolute-path setup requirements. Do not run it unchanged for the current pilot.
