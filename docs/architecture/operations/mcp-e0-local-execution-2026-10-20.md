# Local MCP E0 implementation, 2026-10-20

The user's subsequent request authorized proceeding from architecture cleanup to
the MCP plan. E0 is implemented and verified locally in `tools/festapp`, on top
of the existing uncommitted cleanup. This is not a production deployment or a
claim that the complete ticketing MCP plan is finished.

The shared operation catalog owns strict argument/result schemas, descriptions
and side-effect metadata for context inspection, ticket-layout inspection and
explicit synthetic preview. CLI and official SDK stdio adapters import these
handlers in process. No arbitrary SQL/RPC, shell, login tool, hosted endpoint,
active-layout write, real-ticket operation or Blueprint V2 is registered.

The business boundary remains `get_ticket_layout_for_authoring_v1` plus the
existing `preview-ticket-layout` resolve/PDF modes. Registered font metadata,
owned image references and renderer presets are exposed without buyer/order
bundles. Preview freezes the effective draft and renders the canonical PDF to
PNG with PDF.js and native canvas; it does not approximate the ticket renderer.
It returns MCP image content, draft/scenario fingerprint, original aggregate
version and a short-lived PDF resource. Resource reads recheck Auth, organization,
user ownership and current occasion permission. Four bounded in-memory PDFs
expire after 15 minutes. There is no durable customer artifact store.

Profiles pin the tenant, origin, public key, organization, generation, activation
hash and existing release-tooling backend-profile hash. Activation is validated
before credentials/domain calls with redirects prohibited. macOS Keychain is the
only persistent session backend. Cross-process profile locks serialize refresh,
rotation persistence and the complete operation. Auth service identity, MFA and
user-scoped organization checks run on every operation. Missing/revoked login,
unsupported MFA and failed secure persistence fail closed. No production service
credential is used.

Verification on final code:

- 15 Node tests passed, including real SDK stdio subprocess interoperability,
  CLI/MCP shared handler output, strict input/output schemas, session rotation
  across owners, stale/revoked sessions, MFA, organization/scope rejection,
  activation mismatch with zero credential calls, secure-persistence failure,
  and a canonical PDF-to-PNG preview. Auth/HTTP/Keychain boundaries are simulated
  in these tests; rendering executes the existing Deno handler and real PDF code.
- `database/tests/ticket_layout_mcp_read_test.sql` passed against the disposable
  local PostgreSQL backend as `authenticated`, with two synthetic identities
  and rollback. It proves the bounded projection and foreign/anonymous denials.
- The PNG at `/tmp/festapp-mcp-e0-preview.png` was visually inspected: synthetic
  event/name/table, QR and symbol rendered with readable text. It is not a final
  production ticket design.
- The native Keychain binding imported successfully. A real-account Keychain
  login has not been performed and is not claimed.
- `git diff --check` passed. No Flutter task was started, dependency lockfiles
  outside this private package were changed, production SQL applied or mail sent.

Logs: `/tmp/festapp-mcp-e0-test.log`, `/tmp/festapp-mcp-e0-sql.log`.

The `vstupenky-online` profile was derived from selected tenant revision
`189148dc8547f2510fd58bd4d9a2eeff2432da71` (`prod/festapptickets`), public
activation verified at `https://vstupenky.online/backend-activation.json`, and
imported into the operator's private local profile directory. This performed no
user login and accessed no live tenant records. No external MCP client
configuration was overwritten. Login and the client entry are documented in
[the package guide](../../../tools/festapp/README.md).

The next wave is E1 versioned artwork saving with persistent identity/replay and
family-specific compatibility/executor gates. Current E0 capabilities remain
inspection/preview. Remaining report/event/order readers close in E5; hosted
OAuth and issued-ticket lifecycle belong to their later waves. The architecture
cleanup forward migration remains locally verified and not production-applied.

Subsequent checkpoint: [local E1 artwork saving and recovery](mcp-e1-local-execution-2026-10-20.md). The E0 receipt hashes identify the earlier checkpoint, not later E1 sources. Canonical profiles retain the three-tool E0 surface.

Subsequent checkpoint: [artwork fence and shared runtime readiness](ticket-layout-fence-release-preparation-2026-10-20.md). Earlier local-only registration statements describe that checkpoint and are superseded by the common backend gate.
