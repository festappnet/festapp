# Work item: complete image delivery cost cutover

Opened: 2026-08-24
Updated: 2026-09-23
Status: blocked
Verification: release

> Revalidation required (2026-09-10): the fixed point and queued Windows
> commands below predate later `0.20.x` releases. Do not resume command `1028`
> or execute P3/P4 from this snapshot until current store, client, Worker, R2
> and traffic state has been read back without mutation.

## Authoritative sources

- Plan: [`../../../plans/image-delivery-cost-cutover-plan-2026-08-23.md`](../../../plans/image-delivery-cost-cutover-plan-2026-08-23.md)
- Execution prompt: [`../../../plans/image-delivery-cost-cutover-EXECUTION-PROMPT-2026-08-23.md`](../../../plans/image-delivery-cost-cutover-EXECUTION-PROMPT-2026-08-23.md)
- Evidence: [`../../../plans/image-delivery-cost-cutover-evidence-2026-08-23.md`](../../../plans/image-delivery-cost-cutover-evidence-2026-08-23.md)

This work item tracks live operational state only. The linked plan remains
authoritative for architecture, security, migration and validation.

## Outcome

- `img.festapp.net` and `a.img.festapp.net` serve public images directly from
  their project-specific R2 buckets through Cloudflare CDN without public-view
  Worker invocations.
- `image-api.festapp.net` is the only authenticated plane for upload, delete,
  private reads and signing.
- Android, iOS and web production clients use the dedicated control origin and
  stable `projectId`.
- Every temporary legacy control route, alias, fallback, binding and secret is
  removed after installed-client adoption.

## Fixed point

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

## Next action

Read back current CSM store versions, installed-client compatibility, image
Worker/R2 routing and traffic before defining a new release candidate. The
recorded `0.19.91+441` target and command `1028` are superseded: the current
`origin/prod/csmostrava2026` config declares `0.20.14+498` on 2026-09-23.
Do not replay any old Windows command or deploy P3/P4 from this snapshot.

## Remaining order

1. Establish the current release source and produce an independently inspected
   Android AAB on Windows only if the refreshed plan still requires it.
2. Produce the iOS archive from that same source through
   the established Apple release workflow; do not substitute build `439`.
3. Present and obtain exact artifact-specific production authorizations for
   Google Play and App Store, release both clients, and read back store state.
4. Deploy and verify the web client carrying the canonical image contract.
5. Prove zero legacy control traffic for the authoritative window or enforce an
   approved minimum Android/iOS version.
6. Execute P3: reconfirm public-bucket safety, attach both public hostnames
   directly to R2, apply cache/header/CORS/Smart Tiered Cache configuration and
   prove zero public Worker invocation delta.
7. Execute P4: remove public Worker routing, `legacySupabaseUrl`, private
   fallback, migration-only code and unused bindings/secrets/tests/docs.
8. Record a seven-day/full-cycle cost and health observation, update evidence,
   and close this work item.

## Current blocker

The old control-channel observation (`health=200`, cursor `1024`, no result for
commands `1025` through `1028`) is historical and has not been rechecked.
Current store, client, Worker, R2 and traffic state is unverified. This work
item targets CSM and shared image infrastructure; a separate exact rollout
scope is required before changing other tenant branches or routes.

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
