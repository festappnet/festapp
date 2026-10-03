# Unattended agent access to canonical Supabase (proposal)

Requested during the ticket-font rollout on 2026-10-03 and authorized by the
user during the occasion-report rollout. A tested read-only implementation
candidate is now in [agent-access](../../../automation/hetzner-supabase/agent-access/README.md).
It has not been provisioned: infrastructure access remains unavailable. Production
access policies and credentials are unchanged; unattended releases are not enabled.

## Observations

The current CLI fallback uses a named-user, one-hour Cloudflare Access session
for the Studio pg-meta API. It runs SQL as postgres. Giving a service token access
to the same full Studio application would turn a local token into unrestricted
administrative access and lose the existing person-level boundary.

CatalogPilot's current infra/supabase/access/README.md in
/Users/miakh/mixing/napojse-poc confirms the same Google provider, independent
MFA and a one-hour Access session. Its whole admin hostname is protected; no
service token grants administrative access. It therefore does not yet solve
unattended automation either. Preserve both human administrator boundaries.

## Proposed boundary

1. Keep supabase.festapp.net and its named-user MFA policy unchanged.
2. Add a dedicated agent endpoint behind the existing tunnel, protected by a
   Cloudflare Access Service Auth policy that accepts one explicitly named service
   token. Route it to a small loopback-only broker, never directly to Studio or
   pg-meta. Cloudflare supports CF-Access-Client-Id and CF-Access-Client-Secret
   headers; an ordinary Allow policy would still prompt for interactive login.
3. Start with read-only diagnostics. The broker uses a dedicated database role
   with explicit SELECT grants and fixed RPC operations. Verify canonical database
   identity and tenant organization, impose timeouts and result-size limits, and
   audit service identity, operation, tenant and request digest without secrets.
   Do not accept arbitrary SQL, shell commands or tenant IDs without validation.
4. Keep releases separate. A release operation may install an exact reviewed
   repository migration or verified Function bundle, with digest, ledger and
   rollback checks. Its credential and database role must be separate from routine
   diagnostics; retain the current authorized release path until these checks are
   implemented. Never pass the postgres password or Supabase service-role key to
   the assistant as the routine connection credential.
5. Store local secrets in macOS Keychain (a 0600 file only as a documented fallback),
   with one credential per workstation/service, finite expiry, rotation and
   immediate revocation. A local CLI/MCP adapter reads it and supplies headers
   without printing tokens or committing credentials. Browser login is then needed
   only for human administration or provisioning/recovery.

## Delivery and acceptance

Implement broker and local adapter against an isolated database first. Prove
anonymous and wrong-token requests fail, the diagnostics role cannot write or
read ungranted tables, cross-tenant access fails, oversized/slow requests stop,
secrets are absent from logs, expired/revoked tokens fail, and Studio still requires
human login. Then provision the dedicated hostname/token and perform a read-only
production identity probe before enabling any release operations.

Cloudflare documentation:
https://developers.cloudflare.com/cloudflare-one/access-controls/service-credentials/service-tokens/
https://developers.cloudflare.com/cloudflare-one/access-controls/authenticate-agents/
