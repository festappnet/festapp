# Hetzner rehearsal host — verified state on 2026-08-27

The first real Festapp self-hosted Supabase rehearsal host is online in the same
Hetzner project/account used by Mendelio. This is an isolated target for restore
and merge rehearsals, not the production cutover.

## Provisioned foundation

| Item | Verified value |
|---|---|
| Host | `festapp-supabase-rehearsal-01` |
| Hetzner class | CAX11 ARM, 2 shared vCPU, 4 GB RAM, 40 GB local disk |
| Location / OS | NBG1 / Ubuntu 26.04.1 LTS, `aarch64` |
| Protection | Hetzner delete + rebuild protection; Terraform `prevent_destroy` |
| Runtime | Docker 29.7.2, Compose 5.5.0 |
| Supabase | pinned `self-hosted/v0.8.0` commit and 11 ARM64 image digests |
| PostgreSQL | 17.6 |
| Network | SSH restricted to the approved administrator CIDR; ports 80/443 restricted to official Cloudflare proxy ranges; gateway only on loopback; no public PostgreSQL |
| Application state | all 11 Compose services healthy; Auth health endpoint answered |

The host successfully pulled and runs each of the 11 declared service digests
on `aarch64`. The separate authenticated Docker Hub registry recheck was blocked
by the anonymous pull limit and therefore remains an explicit pre-production
gate; it is not recorded as passed.

No DNS or production write owner was changed, and none of the three existing
Supabase cloud sources was mutated or deleted. Isolated rehearsal copies of all
three sources are now imported and validated on this host. Storage remains in the Supabase
architecture; the existing R2 image-delivery path stays separate.

## Monthly operating price

The live pricing API in this same Hetzner account returned, including 21% VAT:

- CAX11 server: EUR 7.2479/month
- primary IPv4: EUR 0.605/month
- current rehearsal total: **EUR 7.8529/month**
- optional Hetzner server backup: 20% of server price; total would become
  **EUR 9.30248/month**

Paid Hetzner backups are currently disabled. Append-only encrypted off-host
PostgreSQL, Storage and runtime backup plus two isolated restore drills have now
passed. This rehearsal evidence does not replace the final production backup
policy or the fresh pre-cutover recovery point.

## Capacity interpretation

Immediately after the stack settled, Linux reported 3.7 GiB total RAM, 1.7 GiB
used and approximately 2.0 GiB **available**. Much of the remainder was useful
buffer/cache. There was no swap and the kernel journal contained no OOM kill.
Memory PSI was low at this idle snapshot. Disk usage was 14/38 GiB after image
pulls, leaving 23 GiB.

The `used` column is not a sizing gate. CAX11 remains a rehearsal candidate until
two realistic restore/merge runs measure `MemAvailable`, memory and CPU PSI,
OOM events, load average/run queue, peak connections, p95/p99 latency, WAL growth
and disk headroom. The steady-state acceptance window after each run requires no
OOM kill, at least 15% `MemAvailable`, CPU PSI `some avg60` below 10%, no run
queue above both vCPUs for five continuous minutes, and 15-minute load average
below 2.0. Restore-batch spikes are recorded separately rather than confused
with steady traffic. If those or the application latency/disk gates fail, the
next reviewed option is CAX21; idle cache occupancy alone is not a reason to
resize.

## Current post-merge state and next gate

The first full transformed merge is validated: 7,198 Auth users, 1,199 Storage
objects, zero validated FK orphans, preserved password hashes and a forward-only
client-sync rebuild. A 200-transaction concurrent materializer test completed
without error at 114.301 ms average per six-component set. After load the host
had 2.05 GB available RAM, zero memory PSI/OOM and 20.4 GB (51%) disk free.

The post-fix endpoint canary passed old cloud → self-hosted → old cloud with
exact CSM Ostrava fallback counts (26 information, 47 news, 128 places and 969
events). A fresh encrypted recovery point then restored exactly into another
isolated database and Storage path: 7,198 Auth users, 1,199 Storage metadata
rows, 762 public scopes, two validated imports and 1,463 files / 606,950,851
bytes. All prior artifacts and failed drill databases remained preserved; no
path was deleted.

On 2026-08-28 the isolated `rehearsal-api.festapp.net` origin was activated
through Cloudflare, Caddy and the loopback gateway. Strict origin TLS, Auth,
REST, Realtime, a real Storage object and direct-origin denial all passed. The
full evidence is in `rehearsal-origin-2026-08-28.md`.

The second complete rehearsal from a newer cloud snapshot passed on 2026-08-28
in a new isolated database and the rehearsal runtime now targets it. The CSM web
release, signed iOS candidate and password/refresh/rights/idempotent-write
canaries now pass against rotated rehearsal runtime credentials. Historical
Android commands `1029` and `1030` are invalid for the refreshed overlay and
have no retained result. A new build-only command remains deferred to the
paired Windows workstation. The remaining operational gate is that AAB plus the final
full-freeze snapshot/marker. Production `api.festapp.net`, cloud credentials,
stores and write ownership remain unchanged.

The additive Slunovrat rehearsal then increased the canonical target to 9,648
Auth users, 1,453 Storage metadata objects and three validated imports. Its
coordinated encrypted backup and clean-cluster restore passed with 1,717 files /
1,296,547,327 bytes, RPO 0 and RTO 790 seconds. Because every older successful
and failed restore target is still retained, the 40 GB filesystem now has only
about 304 MB free at that time. A read-only host check on 2026-08-30 reports
approximately 19 GB free, so that historical capacity blocker is closed. Fresh
pre-freeze capacity and backup checks remain mandatory; off-host backups and
evidence ledgers are not cleanup targets.
