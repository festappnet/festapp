# Work item: complete image delivery cost cutover

Opened: 2026-08-24
Updated: 2026-10-07
Status: blocked
Verification: release

> Current production readback: [2026-10-07 evidence](../../image-delivery-readback-2026-10-07.md).
> Old release identities and Windows commands below are historical receipts.
> They do not authorize or define a new build, store release or routing change.

## Authoritative sources

- Plan: [`../../../plans/image-delivery-cost-cutover-plan-2026-08-23.md`](../../../plans/image-delivery-cost-cutover-plan-2026-08-23.md)
- Execution prompt: [`../../../plans/image-delivery-cost-cutover-EXECUTION-PROMPT-2026-08-23.md`](../../../plans/image-delivery-cost-cutover-EXECUTION-PROMPT-2026-08-23.md)
- Evidence: [`../../../plans/image-delivery-cost-cutover-evidence-2026-08-23.md`](../../../plans/image-delivery-cost-cutover-evidence-2026-08-23.md)

This work item tracks live operational state only. The linked plan remains
authoritative for architecture, security, migration and validation.

## Scope clarification - 2026-10-07

The Supabase data/backend switch is completed, as recorded in
[the backend closure](../completed/canonical-self-hosted-cutover-2026-09-02.md).
This remaining work item concerns direct public R2 delivery, installed-client
adoption and legacy image-control contraction. It does not request another
backend migration. The source still declares all four image Worker hosts;
the subsequent read-only production verification confirms that P3/P4 remain
unfinished. See the linked current readback for routing, bucket and client evidence.

## Target outcome

- `img.festapp.net` and `a.img.festapp.net` serve public images directly from
  their project-specific R2 buckets through Cloudflare CDN without public-view
  Worker invocations.
- `image-api.festapp.net` is the only authenticated plane for upload, delete,
  private reads and signing.
- Android, iOS and web production clients use the dedicated control origin and
  stable `projectId`.
- Every temporary legacy control route, alias, fallback, binding and secret is
  removed after installed-client adoption.

## Historical fixed point - August 2026

- Canonical branch: `prod/csmostrava2026`.
- Image-cutover source SHA: `cbb3fa7425b7c33b2cab1bba4e2ffe8765f5b6cc`.
- Current release source/branch SHA: `4eb1d556c74d63233af5bdc971f02bcbea0c7314`;
  the image-cutover source is a verified ancestor.
- Target client version: `0.19.91+441`.
- Google Play production version: `438` at full distribution.
- Submitted iOS build: `439`; it predates the image cutover.
- Worker version: `4369e694-9b6b-4705-a67a-7397770ff21a`.
- WAF ruleset/rule: `b9abeff61b454e0a870da4bbe5b1153b` version 2 /
  `b7bdd5d823704830b3da13f8eaa1eda7`.

## Completed actions

- P0 inventory, pricing/entitlement and topology checks completed.
- Private R2 buckets created; aggregate inventory proved no private source
  objects required copying or deletion.
- `authorize_image_deletion` migration applied and verified in both Supabase
  projects.
- Dedicated control Worker, private bindings, project registry, CORS and purge
  secret deployed and smoke-tested.
- Exact Images source allowlist and bounded fail-closed transformation WAF rule
  applied and positively/negatively probed.
- Clean source `0.19.90+440` validated, committed and pushed to the canonical
  production branch. No Android build ran on the Mac.
- Production Windows command `1027` enqueued against the exact current branch
  SHA for read-only Play inspection and a new signed AAB build; it supersedes
  commands `1025` and `1026`, and Play mutation is explicitly forbidden.
- The post-build CSM overlay was regenerated from canonical `main`, passed its
  drift/config/legacy-absence gates and was published only as
  `cutover/csm-after-1027`; the production ref remains unchanged.
- The production branch subsequently advanced to `0.19.91+441` at `4eb1d556c`.
  Command `1027` is therefore superseded for promotion purposes. Read-only Play
  inspection and a local signed build for the exact current source were queued
  as command `1028`; Play mutation is explicitly forbidden.

## Current result and next action

[Production verification on October 7](../../image-delivery-readback-2026-10-07.md)
confirms all four image hosts still belong to the image Worker and all three
public R2 buckets have no custom domain. The Worker is active infrastructure,
not a deletion candidate. Its latest deployed version is
`63e8aab7-74fa-48e3-9d59-18bafaa9258c` from October 2.

All 11 active web tenants have canonical activation and their deployed Flutter
bundles contain the dedicated control origin. CSM source is `0.20.135+619`
(`e9d49e409b013757b67e3adaf03de141c02046a6`); its web manifest is
`0.20.134+618`. Native store versions and installed-client adoption have not
been verified. Old target `0.19.91+441` and commands 1025-1028 must not be replayed.

Two concrete prerequisites were found:

1. Reconcile Slunovrat's deployed `projectId=slunovrat` with the running
   Worker's registry, which contains only `default`, `a`, `akhweb`. Establish
   the intended backend/bucket mapping before changing any tenant or Worker.
2. Classify 99 default-bucket and five a-bucket objects outside the registry's
   public prefixes. All three public buckets have zero `private/` objects,
   but the 104 other objects are not proven public or safe to delete.

The 30-day sampled analytics query observes no exact upload/delete or presign
traffic on public hosts; private requests returning 401 continue through
October 6. Rejected attempts do not prove old app usage, and sampled analytics
cannot prove exhaustive zero traffic. Obtain current native/client evidence
before accepting an adoption or minimum-version gate.

The subsequent [Slunovrat administration recovery](../completed/slunovrat-administration-recovery-2026-10-07.md)
deployed web version `0.20.135+619` and repaired the forced occasion context.
It also granted the explicitly authorized administration roles to the existing
organization-19 account. That repair did not change `projectId=slunovrat`,
the Worker registry or public R2 routing; the image-specific prerequisites
above remain open.

## Remaining order

1. Resolve the project-contract mismatch and public-object classification.
2. Verify current native release identity and client compatibility. Prepare
   new artifacts only if the actual current state requires a release.
3. Establish the authoritative adoption window or approved minimum version.
4. Prepare exact P3 host scope, pre-state and rollback; attach public R2 domains
   and verify headers, CORS, cache, images and zero public Worker invocation delta.
5. Execute P4 after verified P3/adoption, removing obsolete public routes,
   aliases, fallback source and unused bindings/secrets.
6. Record the required seven-day/full-cycle cost and health observation before
   closing this work item.

## Authority gates

| Action | Required authority | State |
|---|---|---|
| Google Play production release | Exact package, version code, source SHA, AAB SHA-256, production track and rollout action | waiting for AAB |
| App Store submission/release | Exact bundle/build identity, source SHA, archive identity and release action | waiting for archive |
| P3 R2 custom-domain mutation | Recorded pre-state, rollback IDs, zero-private inventory and completed adoption gate | pending |
| P4 destructive contraction | Verified P3 state and zero legacy control traffic | pending |

## Rollback and recovery

- Android/iOS artifacts authorize no store mutation; discard and rebuild from a
  higher valid version if identity or provenance fails.
- Store rollout rollback uses halt/superseding release semantics; version codes
  are never reused.
- P3 records Worker route/version, DNS/custom-domain and cache ruleset versions
  immediately before mutation. Private storage and server-owned authorization
  are not rolled back to the mixed legacy architecture.

## Definition of complete

- [ ] The current Android release carrying the image contract and its exact
  artifact are verified.
- [ ] iOS is released from the same canonical image-cutover source and its exact artifact is verified.
- [ ] The web client with the canonical image contract is deployed and verified.
- [ ] The adoption/minimum-version gate excludes every legacy control client.
- [ ] Both public image hosts serve directly from their project-specific R2
  buckets with zero public-view Worker invocations.
- [ ] P4 removes every temporary alias, route, fallback, binding and secret.
- [ ] Final cost/health metrics and resource versions are recorded in evidence.
- [ ] This file is moved to `../completed/` and removed from the open index.

## Operational log

| Date | Action | Receipt/evidence | Result |
|---|---|---|---|
| 2026-08-23 | P0-P2 infrastructure execution | authoritative evidence document | infrastructure live; client gate open |
| 2026-08-24 | Canonical source push | `cbb3fa7425b7c33b2cab1bba4e2ffe8765f5b6cc` | `0.19.90+440` available on `origin/prod/csmostrava2026` |
| 2026-08-24 | Windows build request | control-channel command `1026` | queued; no result yet |
| 2026-08-24 | Canonical replacement build request | control-channel command `1027` | queued for branch tip `4429055d1`; supersedes `1026` |
| 2026-08-24 | Post-build tenant candidate | `d90d42a3d5551cf3871734d6f36cc3967d9025ed` | verified and published on `cutover/csm-after-1027`; production ref unchanged |
| 2026-08-25 | Canonical replacement build request | control-channel command `1028` | queued for current production source `4eb1d556c`, version `0.19.91+441`; no Play mutation authorized |
| 2026-09-23 | Repository-only revalidation | `origin/prod/csmostrava2026` config declares `0.20.14+498` | old command and version are superseded; no store, Worker or traffic mutation |
| 2026-09-23 | Active-tenant and R2 readback | 11/11 public activation documents canonical generation 1; three named R2 buckets have no custom domain; image Worker retains all four host routes | P3/P4 still pending; no app or infrastructure mutation |
| 2026-09-23 | 30-day Cloudflare HTTP analytics | `httpRequestsAdaptiveGroups`, three public image hosts, exact legacy control paths | no observed upload/delete/presign; `/private/` 401 attempts through 2026-09-22, so zero-legacy gate remains open; no route mutation |
| 2026-10-07 | Read-only current production verification | [Current evidence](../../image-delivery-readback-2026-10-07.md) | P3 absent; 11 web origins verified; 104 non-registry objects and Slunovrat project mismatch require resolution; no production mutation |
