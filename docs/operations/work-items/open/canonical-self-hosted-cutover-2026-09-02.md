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

- Cutover tooling: `main` / `556fdfa3014f2f596579f9df6da1392caf15b32b`
- Runtime bundle: Supabase `self-hosted/v0.8.0`, PostgreSQL `17.6.1.136`, Terraform `1.16.1`
- Last verified production state: all seven active iOS identities serve `0.19.95` live with no editable version. Slunovrat Android production is `0.19.94 (479)`.

## Completed actions

- Two complete three-source merge rehearsals, Auth/Storage canaries and clean restore drill passed with RPO 0 and measured RTO 790 seconds.
- Three-target SQL parity closed on 2026-08-29.
- Expanded repository writer discovery from 68 to 146 candidate files, including Auth, external side effects, Edge, Workers, SQL/operator and deployment paths; all are assigned to fail-closed full-freeze controls.
- Added an exact fail-closed policy for all 20 Edge Functions and three Worker entrypoints; 18 can mutate persisted authority, while read-only and external-delivery routes are also classified.
- Added a fail-closed test-coverage manifest for all 19 production Edge Functions; the repository runner now discovers both established Deno test naming conventions, while operator-only `instance-install` remains explicitly excluded with bundle evidence.
- Restored the missing `sync-worker` deployment manifest and added a fail-closed canonical `sync-publisher` template; its final scope IDs must come from fresh private merge evidence, never historical cloud-`a` ID `643`.
- Hardened `fetch-http-data`, AWS SNS bank ingress and the OneSignal database webhook. Live provider/Vault canaries remain activation gates; remote-SQL `instance-install` is excluded from production.
- Classified all 14 production refs: zero unknown tenants, two pending legacy retirements, one closed retirement boundary and five broad source-`a` clients requiring live application-freeze evidence.
- Refreshed runtime versions against primary upstreams; Supabase remains `v0.8.0` and Terraform advanced to `1.16.1`.
- Added a read-only App Store status lane covering editable, review and live states; on 2 September all seven active iOS identities returned live `0.19.95` with no editable version.
- Synchronized the hardened `main` tooling and all 11 active tenant overlays; repository preflight reports `repository_ready: true` with no repository blockers.
- Installed the current promotion/compose contracts and a reviewed 20-Function production bundle without restarting the runtime or opening writes; excluded `hello` and `instance-install` remain outside the canonical bundle.
- Provisioned encrypted daily database/Storage/runtime backups and hourly encrypted runtime-log archives in a private Cloudflare R2 bucket with a bucket-scoped token and host IP restrictions. A downloaded encrypted database artifact decrypted and passed `pg_restore --list`.
- Deployed an external five-minute Cloudflare health probe covering both origins and all Auth/REST/Storage expectations. R2 evidence passed 6/6 and an induced failure plus recovery produced the expected Healthchecks.io email alert.
- Provisioned the exact AWS SNS topic ARN and a generated notification webhook token on the host without restarting the runtime; the webhook token is also held in the local system keychain for final Vault activation.
- Closed the AVApp and historical Slunovrat retirement boundaries through public store/origin readback. No new application was created or uploaded.
- Bound final freeze markers to exact target import runs and made promotion authorization expire; recovery manifest v3 and isolated restore preserve the same normalized import inventory.
- Added an explicit database-level target write barrier and a separate 30-minute operational readiness gate covering clients, freeze controls, recovery, DNS/TLS, monitoring, integrations, communications and rollback.
- Bound production promotion to a fresh operational-readiness decision for the exact timestamped target; the decision can be refreshed only inside the approved maintenance window and cannot outlive its source evidence.

## Next action

Finish the remaining external/provider evidence and the Android transition
releases, then schedule the maintenance window. A passing operational-readiness
decision can only be produced for the exact final target inside that window.
Produce no Windows command, build or upload meanwhile.

## Remaining order

1. Build and release the seven Android transition versions sequentially on Windows; run no tests there.
2. Collect active-version adoption evidence for the seven live Apple releases.
3. Complete the Farnost Opava WEDOS CNAME handoff.
4. Confirm the live AWS SNS subscription and callback, install the prepared
   notification token in the final target Vault, and exercise payment/bank,
   Edge Function, cron, worker and manual-credential canaries.
5. Run physical-device/web cold-start, refresh/reauth, rights and idempotent-write canaries for every active identity.
6. Schedule the maintenance window; acquire fresh encrypted snapshots only after full write/Auth/Storage/Function freeze and zero mutating sessions.
7. Import final state, validate exact markers/conflicts/FKs/Auth/Storage, create and restore the encrypted promotion backup, then run the production promotion gate.
8. Switch server writers, activate the pinned client manifests, open canonical writes, run canaries and retain both clouds read-only.

## Current blocker

Windows work is intentionally deferred by the operator. All seven Apple versions
are live, but active-version adoption evidence is still pending. Provider callback,
live freeze and WEDOS DNS evidence are also pending. Final canonical publisher scope IDs cannot
be fixed until the fresh production merge mapping exists. Repository readiness
is closed; installed runtime tooling, provider input preparation, scheduled
independent backup and off-host monitoring/logging are closed. Operational
readiness remains blocked by the live AWS SNS/Vault/provider canaries and the
cutover-window-only evidence.
The current runtime is also a single-node topology; production requires an
explicit acceptance of the measured restore-based RTO or a replicated design.

## Pre-cutover gap ledger

| Gate | Current evidence | State |
| --- | --- | --- |
| Repository and tenant overlays | `main` plus all 11 active overlays contain cutover tooling `556fdfa30`; static writer inventory is complete | pass |
| Host baseline | NTP synchronized; 12/12 reported containers healthy; about 19.4 GB free; direct origin timed out outside Cloudflare | pass |
| DNS/TLS | `api.festapp.net` and rehearsal origin use 300-second TTL; certificate remains valid through 2026-11-13 | pass now; recheck in window |
| Installed runtime contract | current promotion/compose tooling and reviewed Function bundle staged without restart or write activation | pass now; refresh after final repository head |
| Runtime provider inputs | exact SNS ARN and generated notification token are present; final Vault write and live callbacks require the final target | prepared; activation blocked |
| Recovery failure domain | encrypted daily R2 backup passed with current restricted credential; downloaded DB archive decrypted and its restore catalog validated | pass now; promotion RPO-0 backup remains a window gate |
| Observability | hourly encrypted off-host logs, five-minute external probes and failure/recovery email delivery are verified | pass now; recheck in window |
| Availability | one CAX11 node; no replica/failover target | decision required |
| Client adoption | Android deferred; all seven Apple releases are live but active-version evidence is incomplete | blocked |
| External writers | legacy retirements are closed; provider callbacks, workers, cron and manual credentials lack final live freeze evidence | blocked |

Passing rows are observations, not durable waivers. The 30-minute operational
gate must re-evaluate all volatile checks immediately before the freeze.

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
| 2026-09-02 | Repository/tenant synchronization | cutover tooling `556fdfa30` plus 11 verified overlay advances | repository preflight passes |
| 2026-09-02 | Read-only host readiness audit | NTP/disk/services/TLS/tool hashes/timers/input-name inventory | infrastructure healthy; operational observability, backup and provider-input gaps recorded |
| 2026-09-02 | Local release verification | `./automation/test_all.sh` | web, Flutter and automation suites pass; DB and live integration suites skipped because local URLs were not supplied |
| 2026-09-02 | Restricted off-host backup | R2 run `20260902T192439Z` | four encrypted payloads uploaded and remote inventory verified; no cutover action |
| 2026-09-02 | Off-host observability | R2 log archive plus external Worker/Healthchecks receipt | 6/6 probe checks and induced alert/recovery passed |
| 2026-09-02 | App Store refresh | guarded read-only Fastlane lane for seven manifests | all seven identities serve live `0.19.95`; no editable version |
| 2026-09-02 | Legacy retirement refresh | public Google Play, DNS and HTTP readback | AVApp listing 404; Slunovrat legacy origin is a retirement-only 301 boundary |
| 2026-09-02 | Edge Function coverage closure | `./automation/test_all.sh` plus fail-closed coverage manifest | 19/19 production Functions mapped; 190 web, 650 Flutter, 115 Deno and 106 automation tests passed |
