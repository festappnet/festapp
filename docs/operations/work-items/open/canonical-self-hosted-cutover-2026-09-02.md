# Work item: complete canonical self-hosted Supabase cutover

Opened: 2026-09-02
Updated: 2026-09-10
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

- Published cutover tooling: `main` / `603989d879781086960bd2db3b61a270eb62c7e7`
- Runtime bundle: Supabase `self-hosted/v0.8.0`, PostgreSQL `17.6.1.136`, Terraform `1.16.1`
- Last verified production state: all seven active iOS identities serve `0.19.95`; six authorized Android identities serve `0.20.1 (485)` at full rollout. `fstapp.fstapp` is excluded.

## Completed actions

- Two complete three-source merge rehearsals passed. The refreshed encrypted
  three-source backup and isolated restore drill passed on 2026-09-08 with RPO
  0 and measured RTO 308 seconds.
- Three-target SQL parity was closed on 2026-08-29. The later
  `20260831220000_reconcile_invitation_delivery_status.sql` migration was
  rechecked on 2026-09-05: both canonical cloud targets contain its ledger row,
  column and wrapper RPCs with byte-equivalent normalized wrapper definitions;
  the active self-hosted API resolves the new RPC and enforces its anon revoke.
  Historical `slunovrat` is an import source, not a parity target.
- Expanded repository writer discovery from 68 to 146 candidate files, including Auth, external side effects, Edge, Workers, SQL/operator and deployment paths; all are assigned to fail-closed full-freeze controls.
- Added an exact fail-closed policy for all 20 Edge Functions and six Worker
  entrypoints; 18 can mutate persisted authority. The two `.mjs` Workers are
  the external self-hosted monitor and the read-only legacy-cloud retention
  keepalive; neither mutates Festapp authority. A third `.mjs` Worker is the
  temporary pre-activation Function guard.
- Added a fail-closed test-coverage manifest for all 19 production Edge Functions; the repository runner now discovers both established Deno test naming conventions, while operator-only `instance-install` remains explicitly excluded with bundle evidence.
- Restored the missing `sync-worker` deployment manifest and added a fail-closed canonical `sync-publisher` template; its final scope IDs must come from fresh private merge evidence, never historical cloud-`a` ID `643`.
- Hardened `fetch-http-data`, AWS SNS bank ingress and the OneSignal database webhook. Live provider/Vault canaries remain activation gates; remote-SQL `instance-install` is excluded from production.
- Classified all 14 production refs: zero unknown tenants, zero pending legacy
  retirements and five broad source-`a` clients requiring live
  application-freeze evidence.
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
- Synchronized and deployed all 11 active web overlays from current `main` on
  2026-09-04. Every public activation document returns `200`, `no-store`,
  `backend=legacy` and `generation=0`; no client activation occurred.
- Replaced the Farnost Opava public application at
  `rezervace.farnostopava.cz` with a path/query-preserving retirement redirect
  to `farnostopava.festapp.net`. The former WEDOS CNAME handoff is no longer a
  cutover dependency.
- Published the six authorized Android transition identities to Google Play
  production as `0.20.1 (485)`, full rollout, with independent production
  readback. `fstapp.fstapp` remained explicitly excluded.
- Raised each of those six source organizations' Android update prompt to
  `0.20.1` while preserving its Play link and all non-Android platform data.
  This is migration pressure only; the current client prompt is dismissible and
  is not evidence of a hard minimum-version gate.
- Deployed the temporary Cloudflare pre-activation guard on exactly
  `api.festapp.net/functions/v1/*` (version
  `e48e70db-3d19-4eed-8ee4-60b4f5c7f541`). Public Function probes now return
  `503`, `no-store` and `Retry-After: 300`; Auth, REST and Storage remained on
  their expected statuses.
- Deployed the read-only legacy Supabase retention keepalive (version
  `f8ba3e28-2eb9-4cb7-81ea-e4992ca16467`) with one daily cron and only the
  three source anon keys. All three exact source GET probes returned `200`;
  the Worker has no public route or write credential.
- Updated all five Worker dependency trees to Wrangler `4.131.0`; Miniflare now
  resolves patched Sharp `0.35.4`. All Worker unit/type checks and npm audits
  pass, and Dependabot reports no remaining open alert.

## Next action

Approve the single-node recovery disposition and name a maintenance window,
owner and on-call. Every residual mobile lane already has an adoption-or-freeze
read-only disposition. A passing operational-readiness decision can only be
produced for the exact final target inside that maintenance window.

## Remaining order

1. Record authoritative Android/iOS adoption evidence where available; all
   other mobile lanes become technically read-only for the complete freeze.
   `fstapp.fstapp` remains excluded and technically read-only.
2. Approve `single-node-recovery` with measured RTO 308 seconds or provision a
   separately designed replica, then name the maintenance owner/on-call and a
   window of at least 60 minutes.
3. Confirm the live AWS SNS subscription and callback, install the prepared
   notification token in the final target Vault, and exercise payment/bank,
   Edge Function, cron, worker and manual-credential canaries.
4. Run physical-device/web cold-start, refresh/reauth, rights and
   idempotent-write canaries for every active identity.
5. Schedule the maintenance window; acquire fresh encrypted snapshots only
   after full write/Auth/Storage/Function freeze and zero mutating sessions.
6. Import final state, validate exact markers/conflicts/FKs/Auth/Storage, create
   and restore the encrypted promotion backup, then run the production
   promotion gate.
7. Switch server writers, activate the pinned client manifests, open canonical
   writes, run canaries and retain all cloud sources read-only.

## Current blocker

The authorized Android publication gate is complete. Every residual mobile lane
has a selected fail-closed disposition: authoritative adoption when available,
otherwise technically read-only through the source freeze; `fstapp.fstapp`
remains excluded from Play and uses the read-only disposition. The fresh freeze
receipt remains a window gate. Final canonical publisher scope IDs cannot be fixed
until the fresh production merge mapping exists. Repository readiness is closed:
`main` `c47f5dd81` and all 11 active tenant refs passed the canonical drift gate;
the clean remote preflight is blocker-free. Installed runtime tooling, provider
input preparation, scheduled independent backup and off-host monitoring/logging are closed. Operational
readiness still requires fresh AWS SNS/Vault/provider canaries and the evidence
that can only be produced during the maintenance window.
The current runtime is also a single-node topology; production requires an
explicit acceptance of the measured restore-based RTO or a replicated design.

## Pre-cutover gap ledger

| Gate | Current evidence | State |
| --- | --- | --- |
| Repository and tenant overlays | `main` `c47f5dd81` is published; all 11 active overlays contain it and passed canonical drift; clean remote preflight returns `repository_ready=true`, no blockers, report SHA-256 `a228b610eb42c8ae9be55aead3c58f4a979b31931630652f87bea077791de22d` | pass |
| Host baseline | NTP synchronized; 12/12 containers running, zero unhealthy; 10,522,382,336 bytes free against a 2,416,741,010-byte measured peak; zero OOM events in 24 hours; direct origin is blocked outside Cloudflare | pass |
| DNS/TLS | `api.festapp.net` and rehearsal origin use 300-second TTL; certificate remains valid through 2026-11-13 | pass now; recheck in window |
| Installed runtime contract | current promotion/compose tooling and reviewed Function bundle staged without restart or write activation | pass now; refresh after final repository head |
| Runtime provider inputs | pre-activation Function guard and legacy retention keepalive are deployed; exact SNS ARN, SMTP inputs and generated notification token are present in the root-only host env; Vault is installed on both databases; the final target-bound Vault write and live callbacks require the final target | pre-window inputs pass; final-target activation is window-only |
| Recovery failure domain | encrypted complete three-source backup `20260908T042903Z` passed with manifest SHA-256 `280b8ff00aac9490bddef1650712c30dc1dccdd31a6b10d86cd49607b7c6dae5`; isolated restore SHA-256 `bc3340bc3f9335ec03c298927d8d5f25dca6e84038182fa1f861030f30033dcb`, RPO 0, RTO 308 seconds | pass for seven days; exact final-target promotion backup/restore remains window-only |
| Observability | daily encrypted backup and hourly encrypted log timers are enabled and active; latest runs succeeded; five-minute Cloudflare monitor version `74d72d78-bc29-40b7-9bf3-52a168dc264e` has a Healthchecks secret and fresh external Auth/REST/Storage probes; direct Realtime WebSocket probes returned `101` on both origins | pass now; refresh integration/alert receipts in window |
| Availability | one CAX11 node; no replica/failover target | decision required |
| Client adoption | six Android `0.20.1 (485)` full rollouts and soft prompts are live; all seven Apple releases are live; 11 web transition deployments are live in pinned legacy phase; every residual mobile lane has an adoption-or-source-freeze read-only disposition and `fstapp.fstapp` remains excluded | disposition pass; fresh freeze and phase-canary receipts remain window-only |
| External writers | legacy retirements are closed; provider callbacks, workers, cron and manual credentials lack final live freeze evidence | blocked |
| SQL parity | `default`, `a` and self-hosted contain migrations `20260906120000`, `20260906130000`, `20260906140000`; self-hosted helper SHA `281821babff4fc837c5747f0aeca7d24` and reset SHA `347b86e44782965df0a3ef3cd3b077cc` have the required ACL and `public, extensions` search path | pass |

Passing rows are observations, not durable waivers. The 30-minute operational
gate must re-evaluate all volatile checks immediately before the freeze.

## Authority gates

| Action | Required authority | State |
| --- | --- | --- |
| Google Play upload/release | Exact package, version, source SHA, AAB SHA and production action | complete for the six authorized packages; `fstapp.fstapp` excluded |
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
| 2026-09-04 | Current web transition deployment | 11 successful GitHub Actions deploy runs from synchronized tenant heads | all activation documents return `200`, `no-store`, `backend=legacy`, `generation=0` |
| 2026-09-05 | Repository refresh | clean-checkout `repository-cutover-preflight.mjs` at `ea7f13d2e` | `repository_ready=true`; 148 writers, 0 unknown writers/tenants, 0 pending retirements |
| 2026-09-05 | Post-closure SQL parity refresh | read-only management catalog on `default` and `a`; public canonical RPC probe | latest wrapper RPC definitions match on both parity clouds; canonical API resolves the RPC and denies anon execute as required |
| 2026-09-05 | Runtime inventory closure | `.mjs` Worker discovery, policy and tests | monitor, keepalive and pre-activation guard are explicit boundaries; six Workers total, mutating surface count remains 18 |
| 2026-09-05 | Canonical Function exposure audit | unauthenticated public probes | active pre-promotion runtime still exposed obsolete Function routes; temporary fail-closed edge guard added for deployment before further public probing |
| 2026-09-05 | Public retirement refresh | DNS/HTTP readback | Farnost, TicketOnline and Slunovrat legacy origins preserve path/query through canonical 301 boundaries |
| 2026-09-05 | Full repository release verification | `./automation/test_all.sh` | pass: 194 web, 657 Flutter and all discovered Deno/automation tests; database integration tests skipped because `DATABASE_URL` was not supplied |
| 2026-09-08 | Android transition publication | guarded Windows release channel and independent Play readback | six authorized packages serve `0.20.1 (485)` in production at full rollout; `fstapp.fstapp` untouched |
| 2026-09-08 | Android update prompt | optimistic source-organization updates plus immediate semantic readback | all six matching `droid` entries advertise `0.20.1`; links and all other organization data preserved; prompt is dismissible, not a hard gate |
| 2026-09-08 | Web activation refresh | public readback of all 11 active `backend-activation.json` documents | 11/11 return `backend=legacy`, `generation=0`, matching tenant ID and `no-store, max-age=0` |
| 2026-09-08 | Post-September cloud SQL parity | management catalog on `default` and `a` | all three 6 September migrations and final scan-reset function contract match; later same-day self-hosted readback is recorded below |
| 2026-09-08 | Canonical Function guard | Cloudflare deploy plus four public Function and three unaffected-service probes | guard version `e48e70db-3d19-4eed-8ee4-60b4f5c7f541`; Function routes fail closed with `503`; Auth/REST/Storage unchanged |
| 2026-09-08 | Legacy retention keepalive | direct source probes, Worker tests and Cloudflare deploy | three source GETs pass; daily read-only cron version `f8ba3e28-2eb9-4cb7-81ea-e4992ca16467`; no public route |
| 2026-09-08 | Worker toolchain refresh | npm install/audit and both Worker unit suites | Wrangler `4.129.1`; zero vulnerabilities; monitor 3/3 and keepalive 5/5 tests pass |
| 2026-09-08 | Full pre-window release verification | `./automation/test_all.sh` | exit `0`; web, Flutter, Deno and automation suites pass, including 95/95 canonical storage/recovery contract tests; database integration tests skipped because local database endpoints were not supplied |
| 2026-09-08 | Repository and tenant rollout closure | `main` `c47f5dd81`, 11 sequential tenant drift gates and clean remote preflight | all 11 active overlays contain the final main; `repository_ready=true`, no blockers, report SHA-256 `a228b610eb42c8ae9be55aead3c58f4a979b31931630652f87bea077791de22d`; obsolete local rollout worktrees/branches removed |
| 2026-09-08 | Self-hosted SQL parity | temporary restricted SSH access plus exact catalog readback | all three September migrations applied transactionally; final helper/reset definitions, ACL and search paths match the canonical contract |
| 2026-09-08 | Complete recovery drill | encrypted backup `20260908T042903Z` plus isolated no-network restore | three-source inventory, 9,648 Auth users, 1,453 Storage objects and 792 scopes reproduced exactly; RPO 0, RTO 308 seconds; production target/clouds unmodified |
| 2026-09-08 | Host/observability refresh | systemd, R2 monitor receipt, external probes, TLS and Hetzner firewall readback | backup/log timers and latest runs pass; Auth/REST/Storage/Realtime pass on both origins; TLS valid through 2026-11-13; ports 80/443 are Cloudflare-only |
| 2026-09-08 | Temporary SSH closure | Hetzner firewall UI readback | temporary operator `/32` removed after host work; original restricted administrator source retained; firewall fully applied |
