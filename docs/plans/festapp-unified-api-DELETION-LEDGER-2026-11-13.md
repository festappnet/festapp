# API cutover ledger - local implementation

Owner: Festapp integration runtime maintainer (Michael Bujnovský).
Legacy migration review/sunset: 2026-12-13 00:00:00 UTC. No publication authorized.

| Path | Local result | Remaining evidence |
| --- | --- | --- |
| Make generator imports of Operations, Zod DTOs and server Make policy | Removed. Generator reads the public regional summary OpenAPI and connector-owned UI/run policy. | Published connector and reconsented real scenario are not authorized. |
| Make generated `/make/v1`, old issuer/resource and custom pagination headers | Removed from generated connector. | Rebuild/republish only after API rollout. |
| Make-specific pagination semantics on new API | Absent. Generic order membership/keyset/detail checks live in Operations for every adapter. | Connector runtime ceiling still needs real Make qualification before publication. |
| Duplicate hosted authentication/admission/artifact execution | Removed from server route; one hosted runner owns all transports. | Full mixed-workload container benchmark remains a release gate. |
| `/make/v1`, `make-transport.mjs`, `make-contract.mjs` | Retained only for registered legacy-make clients and their original MCP audience. Thin adapter uses the same runner. Deprecation/Sunset headers and enforced expiry added. No new API clients can use it. | Read-only Make SDK evidence confirms the legacy definition, one existing reviewer connection and two known scenarios. This blocks deletion pending new API consent and authorized rollout. Verify distribution, migrate/reconsent, then delete files/route and leave only a proxy 410 tombstone. |
| New API process, auth DB, Redis, docs server, SQL receipt store | Not introduced. | Existing resource limits preserved. |
| Implicit DPoP/PAR defaults | Replaced by registered proof/PAR policy; defaults are disabled. Bound tokens cannot use Bearer. | Confidential/PAR/step-up operational qualification remains gated. |
| Shared API/MCP audience | Not implemented. Both API resources and MCP remain distinct. | Verify both actual proxy destinations and public metadata at authorized rollout. |

The ledger is deliberately not closed: read-only live evidence proves that the legacy consumer transition is still required, and this execution does not authorize connector
publication, remote revocation or a production rollout.
