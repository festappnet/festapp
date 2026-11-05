# Notification center scalability - local execution result

Date: 2026-11-05. Verification: standard.

The local implementation now includes the prepared PostgreSQL projection, bounded
personal view API, protected Edge dispatcher and switched Flutter client. This
supersedes the earlier delivery-only checkpoint. No production migration,
deployment, commit, push or tenant propagation was performed.

## Implemented contract

Opening reads maintained personal summaries through indexed authorized scope
aliases, then freezes at most 100 row slots. It does not aggregate delivered
history. Contacts remain live, authorized and bounded to three event references
per row. Exact counts, unknown place totals, own activity, prospective muting and
seen/read separation retain their domain meaning.

The opaque token binds recipient, organization, current occasion and timezone.
Four simultaneous 30-minute leases are allowed; expiry and quota are explicit,
with user-initiated release rather than silent eviction. A ready explicit open
alone acknowledges its captured delivery sequence. Preview, pending preparation,
paging and refresh cannot certify later or unprepared activity as seen.

The payload, live authorization and source fingerprint share one SQL snapshot.
Privacy/source/read debt returns preparing slots without private counters or
contacts. Completed repair restores the same token/slots. An unchanged refresh
omits payload only after those live checks. Source roles are never taken from a
cached contact list. Settings are loaded lazily.

Rows freeze captured batch classification and the eligible sequence envelope.
Later deliveries, and newly eligible facts outside that envelope, require a new
view. Hide/unhide of originally captured members within the envelope repairs the
existing slot. Immutable range receipts include both lower and upper bounds,
including inherited holes and reverse multi-tab reads. Related-order selection
resolves the stored server group/range, including `:self:read` and `:legacy:read`.
The client releases its selection lease only after a successful orders response.

Canonical domain writers invalidate order/storno/contact, participant membership,
account deletion, email incident/redaction/recovery and bank recovery dependencies.
Captured counts/context remain historical facts. Normalized hidden-identity deltas
use indexed subject dependencies, including interrupted hide/unhide repair unions.
The writer inventory JSON is a static candidate inventory, not a claim that text
matching proves semantic ownership. Trusted direct SQL that bypasses canonical
owners remains outside the supported source-write contract.

Supported dependency ownership is explicit:

| Dependency | Canonical ownership and serving rule | Executed evidence |
| --- | --- | --- |
| Order state and captured activity | Order publish/state owners, including `cancel_order_domain_internal_v1`, invalidate before effective eligibility changes; counts/context stay captured. | Prepared orders/history, real checkout/waitlist producers, canceled-new-order/email fixtures. |
| Live order contacts and absent legacy counts | `finalize_ticket_order`, response/contact repair owners and capacity-context changes invalidate dependent contributions; bounded display fingerprint also detects live edits. | Prepared orders/lifecycle, legacy totals and source parity. |
| Participant membership/profile and account deletion | Enrolment/reception, removal/internal storno and account deletion owners invalidate participant dependencies before deletion/rejoin. | Current-participant, app activity, deleted-entity and source parity fixtures. |
| Hidden normalized user/email identities | Coherent live hidden snapshot; indexed changed-key union handles interrupted ABA repair. No cached PII authority. | Prepared hide/unhide, subject-visibility and browser privacy repair. |
| Email incident state/redaction | Shared reducer/escalation/recovery and queue redaction owners invalidate the retained event. | Actual email reducer/replay/source fixtures, prepared family comparison. |
| Bank episode/recovery | Health owner invalidates the old pointer; both serving policies validate current source episode. | Bank lease/recovery/replay plus obsolete-episode/modern-view regression. |
| Roles and target metadata | Current `notification_center_allowed`, authorized scope discovery and authorization-gated display fingerprint; no role backfill of delivered history. | Revocation/ownership/lifecycle and administration visibility fixtures. |
| Hard purge | Canonical order/member/occasion/account purge retracts indexed prepared membership before source cascade. Every prepared FK has a leading lookup index. | Delete permissions/history, deleted entities, FK catalog guard and indexed 100k cleanup. |
| Read/seen and leases | One immutable range-receipt owner; ready-open-only seen watermark; bounded worker lease cleanup. | Multi-tab concurrency/history, lifecycle expiry/quota and client generation tests. |

The [static writer candidate inventory](notification-center-scalability-writer-candidates-2026-11-05.json)
can be regenerated with `python3 automation/notification-center/writer_inventory.py`.
It also includes retained/overwritten definitions and requires the ownership
interpretation above; the count of text matches is not a coverage metric.

The existing single-writer lease remains. Delivery is nonblocking on hot personal
state, tenant-rotated and bounded. Delivery, projection and retained-view repair
are separate committed calls. Revision-scoped retry/backoff, quarantine and
service-only replay never mark failed work complete. Relation-lock contention
also defers the complete repair call, restoring the caller's timeout. Idle
projections sleep until expiry instead of polling every user each second.

The `process-notification-center` worker requires the existing request secret;
JWT gateway bypass does not make its handler public. Actual RPC transport,
independent commits, bounded lifetime and recovery are tested. pg_net is an
after-commit hint and one-second scheduled recovery covers missed/idle wakes.
No Redis, additional business queue or generic application trigger was added.

Bank eligibility now checks the current source episode, so an inherited obsolete
active-looking incident does not appear alongside the current incident in read
and unread sections. Delivery/read history is retained. The supplied scroll
report led to a reproduced settings round-trip reset: separate retained scroll
controllers, explicit offset restoration, a fixed viewport and a reserved
progress strip prevent viewport/offset changes during those widget interactions.

## Evidence and measurements

Modern raw receipt: [prepared measurements](notification-center-prepared-measurements-2026-11-05.json).
The 100k cleanup probe exposed missing leading indexes on event membership,
member-subject cascade and summary-scope cascade lookups. Those three indexes
are now canonical, and the operations test verifies every prepared-table foreign
key has a usable leading lookup index. The unindexed cleanup was canceled on the
task-owned fixture; no other session was canceled. With all three indexes, the
same fixture's event/member cascade deleted 100k facts in 1157 ms. Its complete
derived clear/rebuild (200002 work units) took 109117 ms and 536379536 WAL bytes;
final indexed warm open p50/p95/p99 was 30.4/38.4/44.5 ms over 20 samples.

Raw rows retain their schema digest. The original 1k/10k/100k burst rows precede
those additive maintenance indexes; `finalIndexed100kRead` revalidates the final
schema and reports rebuild/cleanup separately. Final fanout and maintenance
measurements include all indexes. The old-index burst write figures are not
represented as final indexed backfill write costs.

Earlier [delivery/legacy baseline](notification-center-scalability-measurements-2026-11-05.json)
remains explicitly historical and is not relabeled as a prepared-reader result.

The scale fixtures use distinct orders/customers and actual committed publication
and delivery. Every measured rollup is nonempty with the complete expected count.
Fanout rows measure all recipients' deliveries, then lazily build the measured
recipient's projection. The separate active-projection workload maintains all five.

| Events per recipient | Recipients | Deliveries | Publish ms | Delivery ms | First projection ms | Warm open p50 / p95 / p99 ms |
| --- | --- | --- | --- | --- | --- | --- |
| 1,000 | 1 | 1,000 | 263 | 586 | 1011 | 29.6 / 35.8 / 50.8 |
| 10,000 | 1 | 10,000 | 2722 | 7773 | 21575 | 30.3 / 38.5 / 40.1 |
| 100,000 | 1 | 100,000 | 40186 | 137948 | 270459 | 29.6 / 35.1 / 37.4 |
| 1,000 | 5 | 5,000 | 1479 | 2089 | 920 | 29.7 / 32.1 / 32.1 |
| 1,000 | 20 | 20,000 | 10639 | 7923 | 991 | 29.8 / 37.8 / 39.7 |

A final indexed 30-row view had warm p50/p95/p99 37.3/38.1/39.9 ms (20 samples). The separately
recorded final indexed 100k read supersedes the first 100k read row for final-schema
read validation. First samples are recorded separately and are not controlled
cold-cache tests. Twenty warm samples provide descriptive quantiles with limited
tail confidence; they do not establish production p95/p99 or the 50 ms design
objective. Browser, SQL, queue waiting and preparation times are separate metrics.

With five already-initialized personal projections, 1000 events/5000 actual
contributions took 8519 ms to deliver and maintain. Cancellation of one source
and its retained view repaired in 686 ms; hiding one contact and repairing that
view took 572 ms. Twenty-nine range receipts plus group/view repair took
1597 ms. Completed-work replay processed zero work in 2.5 ms. These are
single local workload observations, not percentile estimates. The 5000-contribution
burst does not meet a two-second end-to-end readiness objective; bulk rebuild is
also explicitly not near-instant. The faster read moves meaningful work and WAL
to delivery/repair, as the raw receipt shows.

The fixed-arrival sustained run lasted 59.87 s at 40 events/s and five recipients
(200 recipient revisions/s). It committed 12000 deliveries, 12000 maintained
contributions and 5 summaries, ending with zero backlog. Across 838 post-call
samples, maximum observed pending count was 50 and oldest pending age
110.9 ms; maximum publisher schedule delay was 1.49 ms. This is a one-minute
local stability observation and sampled post-drain lag, not a continuous bound
or proof of long-running production capacity. It does not justify parallel writers.

WAL counters can include background database work. Whole-relation byte counts
include allocation/bloat from previous disposable runs, not per-workload live
growth. The maintenance receipt also reports live tuple payload bytes, excluding
index/page overhead. Its EXPLAIN contains the actual candidate access plan:
the local planner selected a bitmap index lookup followed by sorting 30 live
headers. Do not describe that receipt as an ordered index-only scan. The modern
reader queries summary/scope metadata and bounded live display facts, not the
personal delivery history; the 2000-delivery/1000-read-batch latency fixture also
returns 30 nonempty rows. Wider sparse-role and production distributions still
need observation during the authorized staged rollout.

Browser evidence used an isolated local full Supabase/Flutter release fixture,
Czech UI and a muted headless profile. Canceled own-activity selection returned
its real ordered ID; inherited `:legacy:read` selection returned 34 IDs. These
were actual `get_orders_tab_data` responses and selected grid rows, not simulated
SQL receipts. A held view stayed at 33 orders while a fresh view admitted 34,
consistent with the frozen eligible-envelope contract.

Click-to-rendered-row samples were desktop 29.6, 49.1, 29.3, 48.2 ms and mobile
77.4, 30.3, 30.9, 31.8 ms. An earlier English warm sample was 23.4 ms; first Czech
open after reload was 94.9 ms. These are local sequential samples with roughly
10 ms polling granularity, not p95/p99 or production measurements. They predate
the final explicit offset-restoration-only UI adjustment; the opening pipeline
is unchanged. Real Edge requests returned 401 without the request secret and
200 with it, drained 37 preparation units, and two automatic pg_net requests
returned 200 while privacy repair completed without manual draining.

The Flutter panel regression uses actual Flutter drag/scroll state and verifies
retained offset and viewport during loading and settings/back at mobile/desktop
sizes and both themes. It passed all four cases. The headless browser's synthetic
semantic-scroll method still reset its DOM scroll offset and its physical wheel
input did not move the canvas, so that final browser gesture check is explicitly
inconclusive. It is not presented as an end-to-end physical-wheel certification.
The Dart design detector found no regex findings; parsed DOM contrast/layout
rules do not run on Dart source. Czech desktop/mobile content was inspected in
the real browser fixture.

Final receipts: fresh baseline plus migrations through `20261105120000` applied
successfully; 31 SQL files passed with zero failures, including canonical function
source parity, private ACL/RLS/definer checks, the FK lookup-index guard and the
actual producer-to-prepared comparisons. All 16 multi-connection concurrency
tests passed. The maintained-open latency fixture returned 30 nonempty rows at
both visible/hidden settings without changing its existing 750 ms gate.

The controller/prepared/time Flutter batch passed 42 tests; the final panel
scroll/layout batch passed four cases. Targeted controller and panel analysis
reported no issues. The migration/protocol Node batch passed five tests, Deno
worker transport/handler tests passed five, the actual Edge entrypoint passed
`deno check`, canonical generator tests passed nine, and CI mirror contract tests
passed six. Earlier failing development attempts were corrected and their
passing affected checks are recorded here; they are not counted as successes.

## Validation commands

The task-specific disposable PostgreSQL project is
`festapp-notification-scale-20261105` on `127.0.0.1:59432`; the browser used its
own full project on 60421/60422. Neither reused or reset another session's DB.
The existing 55432 instance had an unrelated older Blueprint constraint issue
and was not repaired by deleting its data. All SQL test URLs below refer only
to the task-owned disposable marker. Cron execution is disabled by bootstrap.

```sh
FESTAPP_LOCAL_DB_WORKDIR=/tmp/festapp-notification-scale-20261105 \
FESTAPP_LOCAL_DB_PROJECT_ID=festapp-notification-scale-20261105 \
FESTAPP_LOCAL_DB_PORT=59432 ./automation/bootstrap_local_db.sh

# DATABASE_URL is the task-owned localhost DB, checked by each runner.
node web_client/scripts/run_db_tests.js notification_center \
  canonical_mutation_source_parity delete_order_history_permissions
node --test --test-concurrency=1 database/tests/notification_center/*concurrency.test.mjs
python3 automation/assemble-notification-center-migration.py --check
node --test automation/tests/notification_feed_migration.test.mjs \
  automation/tests/notification_prepared_protocol.test.mjs
python3 -m unittest automation.tests.test_canonical_source_contract
uv run --with pyyaml python automation/ci/test_contract.py

deno test --frozen --lock=supabase/functions/deno.lock \
  supabase/functions/_shared/notificationDispatcher_test.ts
deno check --frozen --lock=supabase/functions/deno.lock \
  supabase/functions/process-notification-center/index.ts

# Run serially, only after the workstation's Flutter slot is free.
fvm flutter test --no-pub --concurrency=1 \
  test/components/notification_center/notification_center_cases.dart \
  test/components/notification_center/notification_center_prepared_test.dart \
  test/components/notification_center/notification_center_time_test.dart
fvm flutter test --no-pub --concurrency=1 \
  test/components/notification_center/notification_batch_panel_test.dart
fvm dart analyze lib/components/notification_center/notification_center_controller.dart
fvm dart analyze lib/components/notification_center/notification_center_panel.dart

node automation/notification-center/prepared_benchmark.mjs \
  docs/plans/notification-center-prepared-measurements-2026-11-05.json
node automation/notification-center/prepared_maintenance.mjs \
  docs/plans/notification-center-prepared-measurements-2026-11-05.json
node automation/notification-center/prepared_sustained.mjs \
  docs/plans/notification-center-prepared-measurements-2026-11-05.json
```

## Retained boundary and deployment steps

Released daily/temporal/open/read/badge contracts remain installed, using shared
source/read authority. Their history aggregation is intentionally absent from
the new Flutter route. No compatibility fallback or duplicate delivery authority
was introduced. Removing issued APIs requires installed-client usage evidence
and a separately authorized release.

A production rollout still requires separate authorization:

1. Review this local diff together with the repository's unrelated in-flight
   work; validate the exact release revision and one selected tenant. Apply the
   sealed delivery prerequisite `20261105110000` followed by prepared migration
   `20261105120000` through the canonical migration process.
2. Deploy `process-notification-center` with the service environment and existing
   request-secret owner. Preserve its gateway configuration and mandatory handler
   secret check. Verify missing-secret rejection and protected RPC transport.
3. Configure the selected backend origin with
   `configure_notification_center_worker(origin)`, then register recovery through
   canonical `setup_crons(origin)` if pg_cron is in the application DB. The
   canonical self-hosted host uses control-plane `postgres`; run the guarded
   `install-notification-center.sh` production installer instead. Verify pg_net and the one-second wake job;
   do not replace it with minute-only history maintenance.
4. Run bounded resumable projection/backfill calls and inspect
   `get_notification_center_projection_health(organization)` plus delivery health.
   No failed/quarantined scope is ready. Verify counts, privacy and readiness on
   representative tenant data; bulk backfill costs are reported separately below.
5. Build/deploy the validated Flutter client only after the modern RPC/worker is
   ready, then verify real content, selection, badge and multi-tab behavior. Keep
   the issued-client boundary during the staged release. The service-only per-org
   pause prevents modern acknowledgment while operational repairs are performed;
   rollback must select a compatible client revision explicitly.

No production step in this list has been executed. The owned browser, Edge
runtime, browser Supabase project and primary disposable DB project were stopped
after verification. No development server was left running for this task.

Release integration also adds the bounded prepared-retention retraction regression
and a canonical control-plane scheduler installer. The fresh original migrations
remain sealed; `20261105181000_notification_prepared_retention.sql` carries the
maintenance correction forward. Actual rollout evidence is separate from this
local implementation checkpoint.
