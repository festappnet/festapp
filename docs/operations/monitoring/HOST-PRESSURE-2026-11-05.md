# Host pressure and notification idle wake correction

Live monitoring reported 90-96% MemAvailable-based memory use on the canonical
3.8 GiB host, with no swap. Memory PSI confirmed real reclaim stalls. The Edge
working set increased from 213 MiB after restart to roughly 850 MiB, then
plateaued; PostgreSQL used roughly 550 MiB. No contemporary OOM or container
restart was observed. These samples do not prove a continuing memory leak.

The new notification safety cron generated about 3600 Edge requests per hour
while queues were empty. The correction keeps the one-second database check,
but dispatches HTTP only for pending delivery events, due non-quarantined
projection scopes or existing views requiring live repair/expiry coverage.
Domain-transaction fast wakes remain unconditional. Durable work remains in
PostgreSQL; no new queue, daemon or permission cache is introduced.

The idle regression fails on the released unconditional scheduler wrapper and
passes with the correction. It also covers pending events, future retry times,
due work, quarantined scopes, existing views and the direct domain wake.
Prepared lifecycle/retention, delivery operations and canonical SQL parity pass.
The sealed earlier migrations remain unchanged; forward migration 203000 owns
this delta.

`install-host-swap.py` performs read-only preflight by default. Authorized apply
adds a root-only 2 GiB swap file on ext4, retaining at least 4 GiB free disk,
and persists its fstab entry and swappiness 10. It refuses conflicting swap or
managed configuration and preserves previous fstab/swappiness evidence. No
service restart, container quota, monitoring threshold or paid capacity change
is involved. Swap is emergency headroom, not additional physical RAM or proof
that this host meets representative peak capacity.

The single 16:03 UTC Edge HTTP500 incident belongs to
`process-notification-center`. A native isolate termination occurred in the
same time window, but available logs do not establish memory as its cause.
The independent Monitoring pipeline was degraded from 15:01 through 15:26 UTC,
then recovered. Its queued memory alert waited between 14:56 and 15:27 UTC
following the prior recovery send at 14:26 UTC; sender/watchdog policy parity is
being checked in the standalone Monitoring repository. No alert is dismissed
or manually resolved merely to hide the original failure.

Final deployment, headroom and monitoring readbacks belong in the local release
receipt. No frontend build or production-tenant branch change is required.
