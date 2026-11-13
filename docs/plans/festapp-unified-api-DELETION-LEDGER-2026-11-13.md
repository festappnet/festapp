# API cutover ledger - deployed shared core, Make review hold

Owner: Festapp integration runtime maintainer (Michael Bujnovský).
Make cutover gate: **accepted in the existing Make review first**, per explicit
user steering on 2026-11-13. Until acceptance, retain the original route,
client/grants, published connector definitions, README, connection and scenarios.
The former 2026-12-13 date is not permission to retire before review acceptance.
API ingress and the two consent UI releases remain authorized independently.

| Path | Local result | Remaining evidence |
| --- | --- | --- |
| Make generator imports of Operations, Zod DTOs and server Make policy | Removed. Generator reads the public regional summary OpenAPI and connector-owned UI/run policy. | Prepared source only. Publication and reconsent are deferred until review acceptance. |
| Make generated `/make/v1`, old issuer/resource and custom pagination headers | Removed from generated connector. | Publish only after both review acceptance and verified API rollout. |
| Make-specific pagination semantics on new API | Absent. Generic order membership/keyset/detail checks live in Operations for every adapter. | Connector runtime ceiling still needs real Make qualification before publication. |
| Duplicate hosted authentication/admission/artifact execution | Removed from server route; one hosted runner owns all transports. | Final D9 image passed the controlled mixed-workload benchmark under unchanged limits. |
| `/make/v1`, `make-transport.mjs`, `make-contract.mjs` | Retained only for registered legacy-make clients and their original MCP audience. Thin adapter uses the same runner. Automatic calendar retirement is removed from the follow-up source. Both MCP runtimes use the same qualified D9 image; the original regional Make interface, issuer/resource, client policy and keys remain preserved; no Sunset or 410 cutover is activated while review is pending. No new API clients can use it. | Read-only Make SDK evidence confirms the legacy definition, one existing reviewer connection and two known scenarios. Review acceptance is an explicit prerequisite; then prove consumer transition and new API consent before deletion. Verify distribution, migrate/reconsent, then delete files/route and leave only a proxy 410 tombstone. |
| New API process, auth DB, Redis, docs server, SQL receipt store | Not introduced. | Existing resource limits preserved. |
| Implicit DPoP/PAR defaults | Replaced by registered proof/PAR policy; defaults are disabled. Bound tokens cannot use Bearer. | Native DPoP/PAR qualified; sensitive operations require fresh GoTrue AAL2. Live probes reject missing MFA before dispatch; positive MFA passed the production-pinned disposable GoTrue suite. No machine client_credentials activated. |
| Shared API/MCP audience | Not implemented. Both API resources and MCP remain distinct. | Both proxy destinations and all eight live manifests verified; cross-resource token rejection passed actual API/MCP OAuth probes. |

The ledger remains intentionally open under the user's review condition.
Do not sync the prepared API connector, reauthorize its connection, update its
native README/review, revoke old grants or install a 410 tombstone before the
existing review is accepted. The original regional Make interface remains intact on the upgraded shared runtime.
After acceptance, apply the approved-app maintenance workflow, qualify the
actual connection/scenarios, prove consumer migration, and then close this ledger.

## Shared operator expansion - deployed

The sole operation registry is `packages/festapp_contracts/mcp-permissions.mjs`
(`DELEGATED_OPERATIONS`). MCP reference generation, API projections, client
registration and delegated execution consume it. Both adapters call the same
`Operations` executor and domain/SQL owners. The API-specific blanket
`mutationGaps` and duplicate `apiSupported` filters are removed. Protocol proof
requirements remain transport policy, with no duplicate domain implementation.
Shared layout recovery binds one actor/profile and exact reviewed request to
one command UUID; old pending records migrate offline without a runtime fallback.
All 196 operations have adapter-parity coverage, with real PostgreSQL workflow
coverage and production-version GoTrue MFA coverage at the effect boundaries.
Both MCP runtimes now run the same immutable D9 image; all eight exact-source
GitHub jobs and canonical local lanes passed. The bank-writer ACL migration and
canonical Functions bundle are applied and verified. Both API OAuth probes and
the actual MCP SDK tool path passed refresh, resource isolation and revocation.
See [production evidence](festapp-unified-api-evidence-2026-11-13/production-operator-d9.json).
Make review acceptance remains the prerequisite for its connector cutover.
