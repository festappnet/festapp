# Backend refactor release preparation, 2026-10-20

Status: **production release complete** for vstupenky.online, version 0.20.296+785. See the [verified release result](backend-refactor-release-result-2026-10-20.md) and [production receipt](backend-refactor-release-result-2026-10-20.json). The integration receipt and preparation decisions below record the state before publication. The unrelated dirty feature checkout was preserved.

## Repaired repository gates

- Scanner shared root now tests arbitrary occasion-defined IDs and numeric
  backend keys. It no longer requires the removed tenant-specific constant.
- The client-sync contract rejects generic executors while recognizing only the
  exact existing waitlist signature. It verifies its six closed actions,
  service guard, lack of anon/authenticated execution and absence of extra
  overloads. Trusted search paths and occasion delete/copy assertions follow
  the current facade-to-owner graph, preserving the original safety checks.
- `automation/generate_canonical_source_contract.py` deterministically replays
  the baseline and subsequent migrations, including function renames/drops.
  It checks all authored foundation definitions against the final release
  and retains all 56 original catalog identities. The generated SQL checks 302
  current bodies and the absence of 23 obsolete identities. No fingerprint is
  learned from a database. Source edits absent from the release assembly fail
  generation. The normal canonical source test invokes regeneration checking
  and the generator's regression cases.

Refresh after a deliberate SQL change:

```sh
python3 automation/assemble-operations-foundation-migration.py --output supabase/migrations/20261020120000_canonical_operations_foundation.sql
python3 automation/generate_canonical_source_contract.py
python3 automation/generate_canonical_source_contract.py --check
```

## Prepared production evidence collection

`automation/release/operations_preflight.sql` is a read-only, explicit
organization/occasion inventory. It refuses missing IDs and mismatched scopes,
uses a read-only transaction and bounded statements, and emits aggregate
observed client versions, receipt status, migration presence and sampled grants.
It does not emit actor IDs, request/response contents, tokens or order data.
It was exercised on the disposable database, including rejection paths. A subsequent read-only production observation is recorded separately.

For a later authorized release, first establish the canonical backend identity
from the selected tenant's activation document and configuration, through the
[protected backend access workflow](../../../.agents/skills/festapp-backend-access/SKILL.md).
Use the resulting approved connection and verified numeric IDs:

```sh
psql "$APPROVED_DATABASE_URL" -XqAt -v ON_ERROR_STOP=1 \
  -v organization_id="$APPROVED_ORGANIZATION_ID" \
  -v occasion_id="$APPROVED_OCCASION_ID" \
  -f automation/release/operations_preflight.sql
```

The report deliberately cannot set production readiness or enable MCP writes.
Observed commits exclude dormant/offline installations and can have unreported
versions. Receipts are sampled for the selected occasion and its unit; deleted
occasion IDs need their own explicit inventory. Offline command intents live
on devices and are not recoverable from server receipts. Obtain device/release
channel evidence before declaring an installed-version or pending-intent gate
satisfied. Do not infer a numeric minimum supported build from this dirty tree.

## Release ordering and compatibility decisions

| Boundary | Prepared decision | Evidence required at actual release |
|---|---|---|
| Shared source and tenant | Shared changes go to canonical main, then one explicitly selected tenant overlay. Current feature-tree hashes are local evidence only. | Clean committed SHA, fetched authoritative main, selected tenant/base SHA, main-owned drift check and sealed build digests. |
| Historical migrations and data | Apply the reviewed forward definition delta exactly once against the verified current schema. Never replay baseline/adoption or blindly apply unrelated pending SQL. Preserve receipt, budget, queue and payment-reference data. | Current migration inventory, exact reviewed SQL digest, dependency/catalog comparison, backup/recovery evidence. |
| Ordinary direct DML clients | Foundation contains immediate DML revokes. Treat it as a coordinated compatibility cutover, not an additive migration safe for every old client. | Inventory all tenants/consumers sharing the affected database roles; demonstrate upgrade or server-side fencing before revokes. A single-tenant frontend release does not isolate global DB grants. |
| Product/form/blueprint controls | Modern editors send original aggregate and nested product/type baselines. Missing legacy JSON controls, old arrays and two-argument deletion overloads remain compatibility paths. | Identify supported releases and pending old shapes; verify old clients are upgraded/fenced. Keep old receipt hashes until no supported pending intent can need them. |
| Pool/resource/group/map facades | Legacy locked-current-version adapters cannot reconstruct an original editor baseline. | Either retain adapters for ordinary legacy use with MCP disabled, or approve a separate scoped fence/cutover after inventory. Do not claim baseline safety for these adapters. |
| Pending commands and external work | Resume the original ID, request, actor and backend. Preserve completed/expired receipts and exact compare-and-clear. Automatic cancellation notices use the existing queue; resend/invoice deletion are separate intentions. | Account for offline stores and unknown outcomes; actor-only invoice intents require explicit original-backend recovery. Do not clear/rebind/reissue uncertain intents. |
| MCP and service execution | This release grants no MCP writes. A service credential is not a safe tool executor: some legacy service boundaries are intentionally broad. | Separate family-specific approval, executor grants, strict version controls, removal of all applicable unversioned reachability, and authenticated denial/revocation checks. |

A compatible cutover must cover both SQL and client deployment. Stage the exact
validated client artifact and arrange the reviewed write admission/fence before
changing global ACLs. Apply the definition delta, deploy the staged selected
tenant, verify both under ordinary identities, then reopen writes. If the
existing infrastructure cannot enforce that window, prepare the compatible
staging change before production authorization; neither a quiet traffic period
nor client refresh advice constitutes a fence. No new maintenance mechanism or
fabricated minimum-version switch was introduced here.

For the selected web tenant, build Flutter and web locally and deploy with
`automation/deploy_direct.sh`, following the existing release skill and
[overlay rules](../tenant_overlays.md). Do not dispatch the GitHub production
build. At release verify coherent live asset/backend activation versions and
ordinary-user read/write, stale conflict, denied foreign scope and same-ID
recovery. No real email/provider action belongs in smoke tests.

Rollback is an assessed forward repair or the existing authorized recovery
workflow. Do not restore competing writers, reset receipts, undo consumed
budgets or roll back financial facts to make an older client work. Keep writes
fenced if a cutover check fails.

The canonical source and selected tenant revisions, protected rollback evidence,
atomic migration execution and coherent live-version readback are now verified
in the production receipt. Installed-client and offline pending-intent inventories
remain incomplete; retained compatibility signatures and MCP contraction remain
gated as described in the release result.
