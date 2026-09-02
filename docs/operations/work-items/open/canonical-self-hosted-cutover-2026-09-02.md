# Work item: complete canonical self-hosted Supabase cutover

Opened: 2026-09-02
Updated: 2026-09-02
Status: in-progress
Verification: release

## Authoritative sources

- Runbook: [`../../supabase-self-hosted/cutover-runbook.md`](../../supabase-self-hosted/cutover-runbook.md)
- Client matrix: [`../../supabase-self-hosted/client-cutover-release-matrix-2026-08-28.md`](../../supabase-self-hosted/client-cutover-release-matrix-2026-08-28.md)
- Writer matrix: [`../../supabase-self-hosted/write-authority-matrix.md`](../../supabase-self-hosted/write-authority-matrix.md)
- Architecture: [`../../supabase-self-hosted/architecture.md`](../../supabase-self-hosted/architecture.md)

## Outcome

`https://api.festapp.net` is the only relational/Auth/Storage authority. Cloud
projects `default`, `a` and `slunovrat` are retained read-only; no client,
Function, cron, callback, worker or operator can write to them.

## Fixed point

- Repository: `main` / `4a1565547ea2a2c00fd8ca65ccb870e1ccd7aaa2`
- Runtime bundle: Supabase `self-hosted/v0.8.0`, PostgreSQL `17.6.1.136`, Terraform `1.16.1`
- Last verified production state: CSM iOS `0.19.95 (467)` is ready for sale; the other six `0.19.95` iOS versions are in review. Slunovrat Android production is `0.19.94 (479)`.

## Completed actions

- Two complete three-source merge rehearsals, Auth/Storage canaries and clean restore drill passed with RPO 0 and measured RTO 790 seconds.
- Three-target SQL parity closed on 2026-08-29.
- Expanded repository writer discovery from 68 to 146 candidate files, including Auth, external side effects, Edge, Workers, SQL/operator and deployment paths; all are assigned to fail-closed full-freeze controls.
- Added an exact fail-closed policy for all 20 Edge Functions and three Worker entrypoints; 18 can mutate persisted authority, while read-only and external-delivery routes are also classified.
- Restored the missing `sync-worker` deployment manifest and added a fail-closed canonical `sync-publisher` template; its final scope IDs must come from fresh private merge evidence, never historical cloud-`a` ID `643`.
- Hardened `fetch-http-data`, AWS SNS bank ingress and the OneSignal database webhook. Live provider/Vault canaries remain activation gates; remote-SQL `instance-install` is excluded from production.
- Classified all 14 production refs: zero unknown tenants, two pending legacy retirements, one closed retirement boundary and five broad source-`a` clients requiring live application-freeze evidence.
- Refreshed runtime versions against primary upstreams; Supabase remains `v0.8.0` and Terraform advanced to `1.16.1`.
- Added a read-only App Store status lane covering editable, review and live states and read back all seven active iOS identities.

## Next action

Complete the local repository preflight and reconcile the checked-in runtime
surface policy with the cutover runbook. Windows polling and Google Play
readback are intentionally deferred by the operator; produce no Windows command,
build or upload meanwhile.

## Remaining order

1. Build and release the seven Android transition versions sequentially on Windows; run no tests there.
2. Wait for six remaining Apple reviews and collect store plus active-version adoption evidence.
3. Close external retirement evidence for `prod/avapp` and `prod/slunovratopava`; complete the Farnost Opava WEDOS CNAME handoff.
4. Reconcile payment/bank callbacks, DNS routes, Edge Functions, cron, workers, provider dashboards and manual credentials with live freeze controls.
5. Run physical-device/web cold-start, refresh/reauth, rights and idempotent-write canaries for every active identity.
6. Schedule the maintenance window; acquire fresh encrypted snapshots only after full write/Auth/Storage/Function freeze and zero mutating sessions.
7. Import final state, validate exact markers/conflicts/FKs/Auth/Storage, create and restore the encrypted promotion backup, then run the production promotion gate.
8. Switch server writers, activate the pinned client manifests, open canonical writes, run canaries and retain both clouds read-only.

## Current blocker

Windows work is intentionally deferred by the operator. Six Apple versions
remain in review. External legacy retirement, provider callback, live freeze and
WEDOS DNS evidence are also pending. Final canonical publisher scope IDs cannot
be fixed until the fresh production merge mapping exists. Repository readiness
also remains blocked until AWS Signature Version 2 and the Vault-backed notify
secret have tested live ingress evidence.

## Authority gates

| Action | Required authority | State |
| --- | --- | --- |
| Google Play upload/release | Exact package, version, source SHA, AAB SHA and production action | pending readback/build |
| Production maintenance freeze | Scheduled window and named operator | pending |
| Fresh production export/import | Passing pre-snapshot freeze decision | pending |
| Runtime promotion | Passing final marker, backup and isolated restore evidence | pending |
| Client activation/open canonical writes | Separate final go/no-go after promotion canaries | pending |
| Cloud deletion | Separate destructive approval after retention | not authorized |

## Rollback and recovery

- Before canonical writes open, rollback restores routing to the still-frozen cloud sources.
- After canonical writes open, self-hosted remains the only writer; recovery uses its encrypted backup/forward repair and cloud writes never reopen.

## Definition of complete

- [ ] Every active client/store/web lane is released and adopted or proven read-only/retired.
- [ ] Every writer lane is frozen and then moved to the canonical runtime with live evidence.
- [ ] Fresh final data/Auth/Storage import and isolated restore pass.
- [ ] `api.festapp.net` is the only write authority and both clouds remain read-only.
- [ ] Legacy activation paths and credentials are removed after the retention/adoption gate.
- [ ] The item is moved to `../completed/` and the open index is updated.

## Operational log

| Date/time | Action | Receipt/evidence | Result |
| --- | --- | --- | --- |
| 2026-09-02 | Expanded writer and tenant inventories | repository tests and private append-only JSON outputs | static reachability classified; live freeze still blocked |
| 2026-09-02 | Runtime upstream check | official GitHub/Ubuntu/PostgreSQL sources | Supabase current; Terraform updated to 1.16.1 |
| 2026-09-02 | App Store readback | guarded read-only Fastlane lane | CSM ready for sale; six versions in review |
| 2026-09-02 | Control-channel check | health 200, unauthenticated queue 401, paired client | commands 1045/1046 still have no result |
| 2026-09-02 | Runtime surface reconciliation | checked-in exact Edge/Worker policy | 20 Functions and three Workers covered; Windows deferred |
