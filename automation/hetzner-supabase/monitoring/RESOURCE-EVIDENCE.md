# Capacity evidence in the existing host monitor

The existing minute timer records host memory and cgroup working-set/cache,
cumulative CPU and PID counters in bounded private seven-day JSONL history.
It now also records one read-only aggregate of PostgreSQL client connections,
active/idle-in-transaction/long transactions, max connections and reserved slots.
The collector's own connection is excluded. No query text, addresses, roles or
application rows are retained. Database failure still preserves the host sample.

The main Edge worker samples its native `getRuntimeMetrics()` API once per
minute and emits six numeric fields through existing Docker logs. Sampling does
not overlap. A strict host-side allowlist selects a fresh timestamp and four
counters; other log lines and native heap details are discarded. The collector
reads at most the last 20,000 lines within 180 seconds, with its existing eight-
second command timeout. There is no public metrics endpoint, token or daemon.
`activeUserWorkersCount` counts live user isolates, including warm workers;
received/handled request counters are cumulative. They are not an instantaneous
HTTP concurrency gauge. Missing/stale counters are explicitly marked unavailable.

Pinned Edge Runtime 1.74.0 applies `--max-parallelism` separately to each service
path. It is not a process-wide memory/concurrency ceiling. The reproducible local
fixture sends 16 requests to two functions with a per-path limit of one, verifies
two live workers and complete request counters, and parses the actual native log
using the production collector. It runs with network=none, no host binds/ports,
fixture code only, a 768 MiB cgroup and checks for OOM/restarts.

Run `runtime/test-edge-resource-metrics-local.py --evidence <new-private-file>`.
Activation uses `runtime/apply-runtime-resource-metrics.py` from a digest-verified
canonical source stage. It requires the exact previous router SHA-256, canonical
host/DB/org and runtime/backup locks. Only functions is recreated, with email
paused/drained and then returned to its previous state; unknown sends are not
replayed. Source changes are limited to the router import/start, one shared
numeric sampler, the existing collector and future bundle-install hook. Failure
restores the previous router/collector. Critical service caps and paid capacity
are separate decisions requiring representative peaks and relevant burst tests.

Primary implementation references for the pinned runtime:
[pool registry and per-service semaphore](https://github.com/supabase/edge-runtime/blob/v1.74.0/crates/base/src/worker/pool.rs),
[native counter fields](https://github.com/supabase/edge-runtime/blob/v1.74.0/ext/runtime/lib.rs),
[CLI flags](https://github.com/supabase/edge-runtime/blob/v1.74.0/cli/src/flags.rs).
