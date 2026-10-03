# Festapp agent diagnostics

Implemented candidate, **not provisioned or active in production**. This is the
first stage of the approved unattended access proposal. It cannot deploy reports,
execute SQL supplied by clients, install migrations, or bypass Studio MFA.
A separately reviewed release capability is still required for unattended releases.

The only operations are `probe` (canonical database, restricted role and Festapp
organization identity) and `ledger` (latest 50 migration versions). Both use fixed
queries, a read-only transaction, a 3-second statement timeout and a 16 KiB result
limit. No customer data is exposed. Organization 1 and tenant `festapp` are fixed;
requests with different identities or additional fields are rejected.

Cloudflare Service Auth protects a **new** `agent-supabase.festapp.net`
application. A separate random broker credential also protects the origin;
forwarded Cloudflare headers alone do not authenticate requests. The broker only
stores a SHA-256 digest, expiry and revocation flag. It reloads these for every
request, so origin revocation takes effect immediately. The agent CLI reads its
service and broker credentials from macOS Keychain and refuses redirects.
Studio `supabase.festapp.net` retains its existing named-user/MFA policy.

## Provisioning prerequisites and sequence

1. Obtain administrator access to the verified server `46.224.187.4`, checking
   hostname `festapp-supabase-rehearsal-01`, and a Cloudflare credential permitted
   to manage Access applications/service tokens and the existing admin tunnel.
   Wrangler Pages OAuth is not evidence of these permissions. Do not open SSH
   globally or add a machine token to Studio.
2. Verify active runtime database `festapp_rehearsal_20260909220601`, tenant
   activation and organization 1. Audit existing PUBLIC schema/table/function
   grants before enabling this role in production: NOINHERIT does not remove
   PUBLIC privileges. The application boundary accepts only its two fixed queries.
3. Apply `diagnostics.sql` in a transaction on that database. It deliberately
   fails on an existing role/schema instead of silently changing existing access.
   Generate a dedicated random database password separately; do not log it.
4. Build the broker image, pin the validated image digest for production, and
   verify the runtime Docker network and `db` DNS alias. Install
   `/etc/festapp-agent/pgpass` and `/etc/festapp-agent/broker.json` as 0600 files
   owned by container UID 10001. pgpass contains only the dedicated diagnostic
   role/password, never postgres or service_role. broker.json has
   `token_sha256`, Unix-seconds `expires_at` (at most one year), and `revoked:false`.
   Limit parent-directory traversal and mount only these two files read-only.
5. Start `compose.yml` with the verified `FESTAPP_RUNTIME_DOCKER_NETWORK`.
   The host publishes port 8789 only on 127.0.0.1; no Docker socket is mounted.
   Keep the broker outside the human Studio gateway.
6. Create the dedicated Access application and one named workstation service
   token with a finite expiry. Add a Service Auth policy accepting only that
   token. Preserve all existing applications/policies. Confirm anonymous and
   incorrect service credentials are rejected before exposing the hostname.
7. Add only the new hostname's ingress to tunnel
   `40e1a9a2-d1d5-4789-a691-20818d648b95`, targeting
   `http://127.0.0.1:8789`, preserving existing Studio ingress and 404 catchall.
   Add its proxied tunnel DNS record. Verify Studio still redirects anonymous
   clients to its human Access login.
8. Feed JSON containing `client_id`, `client_secret`, `broker_token` into
   `swift store-credential.swift` on stdin from the provisioning process.
   Do not place credential values in shell arguments or paste them into chat.
   Run `python3 client.py probe` and `python3 client.py ledger` for read-only
   production identity evidence. No production fixtures or writes are allowed.

Rotate both machine credentials before expiry. To revoke immediately, mark the
origin credential revoked and revoke the Cloudflare service token. Remove the
local Keychain item if decommissioning the workstation. Production read-only
probes, invalid-service-token rejection, Studio MFA preservation and actual
Cloudflare expiry/revocation are still pending until provisioning is possible.

## Local verification

```sh
FESTAPP_AGENT_LOCAL_DB_TEST=1 python3 -m unittest discover \
  -s automation/hetzner-supabase/agent-access -p 'test_*.py' -q
```

Five tests pass. Database verification creates and removes a synthetic isolated
database on **127.0.0.1:55432 only**; it refuses an existing matching database or
role. It verifies wrong database rejection, no base-table access or writes,
only organization 1 and 50 migration rows. HTTP tests verify missing/wrong,
expired/revoked origin credentials, tenant rejection, forbidden operations,
request/result limits, database identity, query timeout configuration and logs
without credential values. Cloudflare-side authentication is not mocked into a
claim of production readiness. Container execution and real timeout saturation
remain deployment gates.

## Current infrastructure blocker (2026-10-03)

SSH to the documented host timed out. No active Hetzner CLI context/token was
available. Existing Wrangler OAuth showed Pages permissions but no Access
application/service-token administration scopes. Hetzner rejected the isolated
headless browser at its security check. Gmail is connected, but its connector
redacts authentication codes. No existing policies, production data or credentials
were changed. The report remains separately prepared in PR #251.

Cloudflare's official machine authentication instructions:
https://developers.cloudflare.com/cloudflare-one/access-controls/service-credentials/service-tokens/
