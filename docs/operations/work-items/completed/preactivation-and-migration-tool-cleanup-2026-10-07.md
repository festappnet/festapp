# Work item: retire preactivation Worker and completed-migration tools

Opened: 2026-10-07
Updated: 2026-10-07
Status: completed
Closed: 2026-10-07
Verification: standard

## Authoritative sources

- [Completed backend switch](canonical-self-hosted-cutover-2026-09-02.md)
- [Legacy resource disposition](legacy-supabase-decommission-2026-09-23.md)
- [Canonical runtime tooling](../../../../automation/hetzner-supabase/README.md)
- [Open image routing/adoption gates](../open/image-delivery-cost-cutover-2026-08-24.md)

## Outcome and scope

The repository no longer contains the retired preactivation Worker or six
standalone tools of the completed migration. The runtime writer policy classifies
only existing Workers and retains canonical Function authentication, production
exclusions and per-worker credential requirements.

This closes repository cleanup only. Changes are local and uncommitted; no runtime
policy, Function bundle, application, database or DNS change was deployed.

## Fixed point and external evidence

- Source checkout: `feat/occasion-setup-wizard-20261007`, HEAD `eb2304724`.
- Existing uncommitted application and documentation changes were preserved.
- Read-only Cloudflare request on 2026-10-07 at approximately 11:40 UTC:
  `wrangler deployments list --name festapp-self-hosted-preactivation-guard`.
  Cloudflare returned code `10007`, "This Worker does not exist on your account".
  This confirms script absence in the authenticated account; no Worker deletion
  was executed and no independent zone-route inventory is claimed.
- The completed backend-switch receipt already records guard script absence in
  the 2026-09-23 readback and the operational switch on 2026-09-10.

## Completed actions

- Removed all four files under `workers/self-hosted-preactivation-guard/`.
- Removed its writer-policy entry and replaced the historical temporary-guard
  prerequisite with the current Function bundle/auth/credential release invariant.
- Removed these six scripts, each with no references in other tracked repository
  code, tests, configuration or docs at removal time:
  - `automation/generate_cutover_ledger.mjs`
  - `automation/hetzner-supabase/rehearsal/import-merge-source-canonical.sh`
  - `automation/hetzner-supabase/rehearsal/import-merge-source-auth.sh`
  - `automation/hetzner-supabase/rehearsal/prepare-merge-source-id-mappings.sh`
  - `automation/hetzner-supabase/rehearsal/extend-merge-source-registry.sh`
  - `automation/hetzner-supabase/rehearsal/canary-auth-refresh-continuity.mjs`
- Preserved historical migration SQL, archived audit outputs, source/reference
  registries, retained-source keepalive, backup/restore tooling, used rehearsal
  paths and image migration tools required by unresolved operational gates.

The removed generator was pinned to August branch SHAs and wrote the already
archived cutover ledger; its outputs remain historical evidence. Removed tools
remain recoverable from Git history if a separately authorized historical replay
needs them. Routine production work must not revive the cloud migration.

## Closure and remaining work

The backend switch is already completed; no duplicate backend migration task
needs reopening. Image P3/P4, real EUR payment evidence and credential rotation
remain separate work items. Completion of the database migration does not prove
image-domain contraction, client adoption, a real payment or credential revocation.
No open item was marked completed or withdrawn based on that assumption.

## Validation and closure proof

- PASS: all 37 tests in `hetzner_supabase_inventory.test.mjs`,
  `hetzner_supabase_backup.test.mjs` and `client_rehearsal_canary_contract.test.mjs`.
- PASS: runtime policy evaluation covers 30 Edge Functions, five Worker
  entrypoints and 25 mutating surfaces, with no missing/unclassified entrypoints.
- PASS: all 10 retired paths are absent, removed guard references are absent
  from active policy, 19 local documentation links resolve and `git diff --check`
  passes for this change set.
- The image work item remains blocked with its original adoption/routing and
  observation gates; no unverified production milestone was marked complete.

Repository cleanup is complete locally. Publication and installed runtime policy
refresh belong to the next authorized release; they were not executed here.
