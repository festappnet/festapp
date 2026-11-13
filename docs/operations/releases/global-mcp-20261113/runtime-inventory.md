# Global MCP release preparation inventory - 2026-11-13

Status: read-only preparation. No production or tenant mutations, no deploy, and no credential values recorded. This is not release approval or evidence that the global service is deployed.

## Runtime target and access

The protected alias target assertions and canonical production receipts match; the hostname and database names containing “rehearsal” are legacy identifiers for the canonical production backend, not evidence of a rehearsal environment:

- Alias: `festapp-backend-agent`
- Host assertion and SSH hostname: `festapp-supabase-rehearsal-01`
- Active runtime DB field: `FESTAPP_RUNTIME_DATABASE=festapp_rehearsal_20260909220601`
- Read-only SQL `current_database()`: `festapp_rehearsal_20260909220601`
- Skill profile: `festapptickets` / organization `3`
- Public `https://vstupenky.online/backend-activation.json`: tenant `festapptickets`, generation `1`, backend `canonical`
- Production receipt `festapptickets-seating-2026-11-01.json` records the same host, DB, tenant, generation and canonical backend.

This is the canonical production backend for the selected Festapp Tickets profile. The live Edge registry has exactly one entry: tenant `festapptickets`, origin `https://vstupenky.online`, organization `3`, issuer `https://mcp.vstupenky.online`; broker secret was not read or emitted. This establishes current profile routing, but does not by itself authorize adding another tenant or changing the existing registry.

The live host runs the regional MCP process from `tools/festapp/src/remote/main.mjs serve ... --port 3399`, listening on loopback `127.0.0.1:3399`; its image is `sha256:c3fca03011a51ca805e6dd4ae6ae0d2ac49e5d5f31e6856a070e5a30324a5ca9`. No MCP-named Compose service was listed because this process is managed separately. Ports 3398, 3400 and 3401 were absent from the TCP listener table during inspection; 3400 is a candidate separate listener after a fresh pre-deployment check.

Live Caddy routes `mcp.vstupenky.online` to loopback 3399 and contains an explicit `mcp.festapp.net` handler returning 410. Public probes returned regional `/healthz` 200 and retired-host 410 with no redirect. These are point-in-time read-only checks.

## Source and image evidence

Historical regional runbook evidence (`docs/operations/chatgpt-mcp-pilot-2026-10-26.md`) records the prior regional issuer/image, superseded by the live observations above. The current live image/source label is not yet confirmed against the frozen worktree SHA; capture that exact mapping before promotion.

The later MCP release receipt (`docs/operations/releases/festapptickets-mcp-final-2026-10-27.json`) reports a candidate image `sha256:690aa68171b17b6de9679771901c3748de18fc81c1332ae5074074b2ca23b979`, source `c03b28d1544e90953d637c3fe27f3d769b191dfc`, and previous running image `sha256:bdc4516832ee96af2ef232b99d861ab351ddc948c006c079cfd469836d610445`. This is also historical and tied to the existing tenant deployment. Do not reuse as a global release candidate without exact-SHA source, architecture, packaged smoke, and live-image checks.

Current worktree remote MCP source is modified in `tools/festapp/src/remote/{config,delegation,server,views}.mjs`; freeze and review the exact source SHA before building. No SHA was designated by this inventory.

## Tenant/profile and broker boundaries

The canonical remote auth runbook specifies a protected Edge registry `FESTAPP_MCP_TENANTS_JSON` with entries shaped as `{tenantId, tenantOrigin, organizationId, issuer, brokerSecret}`. Origins must be unique exact HTTPS origins; HTTP Origin selects the entry; request bodies cannot choose tenant, organization, issuer, or credential. The issuer verifies the resolved tenant identity against its bound backend profile. Broker secrets are private and must not be printed or copied into artifacts.

The runbook describes the existing issuer as bound to the `festapptickets` profile and explicitly states this does not silently enable another tenant. First-party tenant release is a prerequisite to activating its registry entry. The live registry currently contains only `festapptickets` (organization 3). No additional first-party tenant profile was present in the observed registry, and no other tenant changes are authorized by this task. Any broader global scope needs explicit named profile authorization and its own verified canonical activation.

## Rollback and release constraints

The canonical sidecar procedure is to run only the standalone remote Compose service with an immutable image, bound to loopback; preserve the existing protected data mount, keys and configuration. Route it only through an approved Caddy site after config validation. Historical guidance uses port 3399, which is occupied by the live regional sidecar. A separate listener port and matching proxy target must be chosen and freshly checked at deployment time.

Rollback removes only the MCP route/service and revokes affected MCP connections; preserve keys and encrypted evidence for recovery. Do not roll back tenant/domain data, payment receipts, or application login. If issuer/storage/identity/client checks fail, keep routing disabled. Avoid changing Supabase services or unrelated tenant configuration.

## Exact-SHA deployment sequence for the release owner

1. Freeze and publish the reviewed source through the repository-required process; fetch authoritative `main` immediately before any PR branch push/PR creation and update a stale base. Record exact main SHA, reviewed source SHA, and tenant scope.
2. Require canonical CI/release gates for the exact base main SHA; do not deploy from this inventory or bypass missing/failed/pending checks.
3. On the authorized production host, rerun the backend skill target assertions and `ssh festapp-backend-agent hostname -s`; confirm live runtime DB, canonical activation generation/org, and requested profile before any data read. The alias assertions and canonical production evidence agree; continue using this target for authorized read-only runtime checks.
4. Inspect only sanitized Compose/service/image state, listener table, Caddy routing and approved activation profiles. Capture current regional source/image and verify old `mcp.festapp.net` returns 410 with no redirect on the live service.
5. Build `tools/festapp/Dockerfile.remote` from the frozen exact source SHA. Record immutable image digest and architecture. Run isolated packaged startup, health, OAuth metadata, protected-resource discovery, unauthenticated MCP 401 challenge, SQLite quick-check, and no-network smoke before transfer.
6. Prepare the protected broker registry/config outside Git with only explicitly authorized first-party profiles. Preserve existing secrets and verify registry shape without emitting values. Do not expand or repurpose regional grants as global access.
7. Back up encrypted MCP state and prior image/config using the approved release procedure; verify archive hashes and SQLite quick-check. Start only the standalone Compose service on a newly checked loopback port; verify local probes before changing Caddy.
8. Validate and reload only the MCP Caddy site, preserving existing API/admin sites and access logging policy. Verify public health, OAuth metadata, resource metadata and unauthenticated 401 challenge, then perform approved client/consent checks and record redacted evidence.
9. On failure, disable/remove only MCP routing/service and revoke the affected MCP connections; restore the prior image/config and preserve state/keys for recovery. Recheck public endpoints and confirm no unrelated service was changed.

## Sources and access blocker

Read: `AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md`, `.agents/skills/festapp-backend-access/SKILL.md`, `docs/architecture/operations/remote-mcp-auth.md`, `docs/operations/chatgpt-mcp-pilot-2026-10-26.md`, `docs/operations/releases/festapptickets-mcp-final-2026-10-27.json`, and the current remote Compose/Dockerfile/Caddy source.

The target assertion and SSH hostname agree with the canonical production receipts and public activation. No customer rows or secret values were read. The current image source label still needs exact comparison against the frozen source SHA before any promotion.

## Additional live first-party profiles and consent compatibility

The organization lookup was limited to catalog identity rows in a read-only transaction (`id`, `title`), with no user, order, or occasion rows. The following public activations and deployment surfaces were verified:

| Tenant | Origin | Activation | Activation document SHA-256 | Canonical org identity | Live web version / source evidence |
|---|---|---|---|---|---|
| `festapptickets` | `https://vstupenky.online` | generation 1, canonical | `c964ba8e23a79e0a082a280d0a44fe3a424b5168eae0853f33d34c630b1cc31c` (recorded in Nov 1 live receipt) | `3`, `vstupenky.online` | Live root and route assets are `0.20.598+1115`; production source SHA not established in this inventory. |
| `festappticketsglobal` | `https://tickets.festapp.net` | generation 1, canonical | `3a1ac8b7d50b65f01efbd7039304f72df4cec8dacfab1f973992db9b9a966f38` | `25`, `Festapp Tickets Global` | Live route shell reports `0.20.588+1103`; matching `origin/prod/festappticketsglobal` head is `e300a64eb494a7296a84eebc2fa8ec09cd4927c3` with the same package version. No artifact receipt ties that exact SHA to the deployed bytes. |
| `doobiscup` | `https://biscup.festapp.net` | generation 1, canonical | `37910cd71e9a1ec4d5136f720534dfc2a32ec4f8bcec8e1b92046ba69d500d95` | `5`, `Ostravsko-opavská diecéze` | Live route shell reports `0.20.580+1095`; matching `origin/prod/doobiscup` head is `d30634a8112539c90671bd00a49f8d0927c456f9` with the same package version. No artifact receipt ties that exact SHA to the deployed bytes. |

Both non-regional origins returned their activation document and `/settings/mcp-connect` returned the Vite web shell (HTTP 200). Their current tracked production branches include the shared MCP connection page and router route; the page source SHA-256 is identical on both branches (`5b55b5a18aa43ad387cff2eba939bab613c872ced9b82f922df6243fa1204562`). The shared MCP route implementation's newest source commit in this checkout is `5a5587e90880e0177c2d80f79b37e4c2931d7a7c` dated 2026-11-10. This proves source and route compatibility on the tracked branch heads and live route shells, but does not establish all consent/exchange backchannel settings are configured for these profiles.

**Eligibility boundary:** `festappticketsglobal` is a separate ticketing profile (organization 25), while `doobiscup` is the verified non-ticketing first-party application (organization 5). Both are canonically activated and serve the shared MCP route. The currently observed protected MCP broker registry contains only `festapptickets`; it does not currently authorize either additional profile for MCP session exchange. Expanding that registry requires explicitly authorized web release/configuration work and protected existing-broker verification. For the authorized current scope, the regional organization 3 profile is the only confirmed existing registry entry; org 25 and org 5 are technically route-compatible but not yet MCP-eligible.

The live production source revision for each Pages artifact cannot be proven from the available read-only public activation document or served version alone. The matching branch SHAs above are exact current branch heads and version matches, not cryptographic deployment receipts. Do not claim those SHAs as deployed source without a verified artifact/deployment receipt.
