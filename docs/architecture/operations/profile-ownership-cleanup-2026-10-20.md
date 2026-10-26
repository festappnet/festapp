# Canonical profile ownership cleanup, 2026-10-20

MCP implementation is deferred while the existing operation modules are cleaned up. This is a bounded follow-up to the deployed refactor, not another repository-wide rewrite. Blueprint V2 is excluded. No user session, connector, production migration or release is part of this local change.

## Findings and decisions

| Seam | Finding | Change |
|---|---|---|
| Profile command | `save_profile_client_sync_v1` was a pure forwarding function. Its complete transaction lived in a second private command implementation. | Move that unchanged implementation into the public command. Preserve its signature, grants, authorization, request hash, receipt/replay, versions and companion invalidation. Remove the private forwarding target. |
| Profile import, group assignment import, occasion-member deletion | Three private `*_companion_internal_v1` implementations had no current SQL/client caller. Their names differed from the active commands, so signature-uniqueness checks did not detect this duplication. Existing source-inspection tests even pointed at these unused implementations. | Delete those authored files and retire the database identities in a narrow forward migration. Keep the active group-aware commands and shared domain writers. Retarget contract checks to the actual active owners; existing behavior/race tests continue to verify companion invalidation. |
| Profile-head helper | `advance_group_profile_heads_internal_v1` had no current authored SQL, Dart, web or worker caller. | Retire that unused implementation alongside the other private identities; keep active domain impact/publication owners. |
| Source ownership versus release history | The foundation assembler reread rolling authored sources and could rewrite a migration already applied in production. | Freeze the installed foundation digest and make its command verify-only. A clearly named current source registry selects authored owners; the existing source-contract parser checks those against the complete ordered migration history. New changes use new forward SQL. No second SQL parser or replacement business engine is added. |

The migration checks stored function callers before retiring private identities and uses `DROP ... RESTRICT`, without CASCADE. An unexpected stored caller aborts the whole transaction. Current external signatures and deliberate compatibility adapters are retained; these are not part of the removal set. No global compatibility contraction or build-floor change is included.

The current source registry is `automation/canonical-operation-sources.json`. The retired identity list is part of the existing effective source contract. Generation fails if a retired implementation is revived, even under a later migration. The same existing parser now verifies one transaction owner per literal receipted operation identity across selected sources, rather than relying only on unique SQL names. All 80 current literal operation identities have one owner; signed/anonymous branches inside one function remain one owner. This scoped check is not a proof about dynamic calls outside the selected registry. Historical source hashes and generated migrations remain immutable evidence, not active source ownership.

SQL owns domain permissions, transactional changes, aggregate versions and notification intent. Dart keeps typed adapters, editor feedback and transport/session mechanics. The future CLI/MCP package must share invocation/context and call these domain owners; it must not reproduce their business rules, introduce a universal RPC/SQL executor or a second ticket renderer. Different domain commands and intentional compatibility adapters are not merged merely because their code looks similar.

## Verification and rollout

Targeted verification covers effective source/absence, public command grants, existing companion/profile/group behavior, stale revisions, replay and multi-connection races. A stored-caller regression exercises the actual new migration and verifies rollback before safe reapplication. The existing foundation digest is checked unchanged.

The new forward migration is `20261020150000_canonical_profile_ownership_cleanup.sql`. It has not been applied to production. Local completion must not be reported as global compatibility retirement or MCP activation. Executed checks passed:

- Fresh disposable baseline plus all forward migrations, including the new cleanup.
- Seven SQL files: profile fanout, companion contract, remaining cutovers, canonical groups, neighboring mutations, full effective source parity and retired identities/grants.
- Six real database integration cases: cancellation receipt fixture, complete forward reassembly without resetting Auth budgets/receipts, companion-owner import replay, cross-occasion profile conflict, owned-companion deletion/attendance race, and stored-caller rejection with rollback and safe reapplication.
- Source/inventory lane and generator regression cases, including revival of a retired identity, duplicate receipt owners under different SQL names, and legitimate signed/anonymous admission branches.

Local logs are `/tmp/festapp-profile-architecture-baseline.log`, `/tmp/festapp-profile-architecture-sql.log`, `/tmp/festapp-profile-architecture-concurrency.log` and `/tmp/festapp-profile-architecture-source-final.log`. No Flutter build or production write was needed.


## Follow-up cleanup

Five retired private identities are now checked absent. The source/inventory lane passed 13 checks on final inputs. After adding the unused profile-head helper to retirement, the three affected SQL files and both forward-reassembly/stored-caller integration cases passed again; unchanged behavior/race evidence above remains valid. The companion/profile transport follow-up is recorded in [command recovery unification](command-recovery-unification-2026-10-20.md).

Subsequent authorization and implementation: [local MCP E0](mcp-e0-local-execution-2026-10-20.md). Statements above about deferred MCP describe this earlier cleanup checkpoint.
