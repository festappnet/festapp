# API cutover ledger - local implementation

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
| Duplicate hosted authentication/admission/artifact execution | Removed from server route; one hosted runner owns all transports. | Full mixed-workload container benchmark remains a release gate. |
| `/make/v1`, `make-transport.mjs`, `make-contract.mjs` | Retained only for registered legacy-make clients and their original MCP audience. Thin adapter uses the same runner. Automatic calendar retirement is removed from the follow-up source. The original regional runtime remains unchanged; no Sunset or 410 cutover is activated while review is pending. No new API clients can use it. | Read-only Make SDK evidence confirms the legacy definition, one existing reviewer connection and two known scenarios. Review acceptance is an explicit prerequisite; then prove consumer transition and new API consent before deletion. Verify distribution, migrate/reconsent, then delete files/route and leave only a proxy 410 tombstone. |
| New API process, auth DB, Redis, docs server, SQL receipt store | Not introduced. | Existing resource limits preserved. |
| Implicit DPoP/PAR defaults | Replaced by registered proof/PAR policy; defaults are disabled. Bound tokens cannot use Bearer. | Confidential/PAR/step-up operational qualification remains gated. |
| Shared API/MCP audience | Not implemented. Both API resources and MCP remain distinct. | Verify both actual proxy destinations and public metadata at authorized rollout. |

The ledger remains intentionally open under the user's review condition.
Do not sync the prepared API connector, reauthorize its connection, update its
native README/review, revoke old grants or install a 410 tombstone before the
existing review is accepted. The live original regional runtime remains intact.
After acceptance, apply the approved-app maintenance workflow, qualify the
actual connection/scenarios, prove consumer migration, and then close this ledger.

## Shared operator expansion - source candidate

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
This candidate must still pass canonical CI and deployment gates. Make review
acceptance remains the prerequisite for its connector cutover.
