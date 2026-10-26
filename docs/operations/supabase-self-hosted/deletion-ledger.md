# Migration deletion ledger

The table below is the original migration-planning inventory. Entries such as
"not created" and "retained" are not a fresh runtime inventory. Later disposition
is recorded by the [legacy retention decision](../work-items/completed/legacy-supabase-decommission-2026-09-23.md)
and [October cleanup receipt](../work-items/completed/preactivation-and-migration-tool-cleanup-2026-10-07.md).
The latter proves preactivation Worker script absence, not an independent route
inventory. The retired external HTTP importer now fails before I/O; see its
[source boundary](../../../database/functions/synchronization/README.md).

| Legacy path | Earliest removal gate | Required evidence | Status |
|---|---|---|---|
| Cloud `default` runtime | canonical retention complete | encrypted final export and zero traffic | retained |
| Cloud `a` runtime | canonical retention complete | encrypted final export and zero traffic | retained |
| `a.api.festapp.net` | all `a` tenants canonical | DNS and gateway reachability scan | not created |
| Source journal/RPC/grants | final marker and stabilization | schema and privilege diff | not created |
| Target ingest/receipts | journal removal and audit export | schema and reachability scan | not created |
| Forwarder and secrets | zero lag and contraction approval | service and secret inventory | not created |
| Runtime staging/maps | encrypted evidence archived | schema diff | not created |
| Inter-project sync rows/maps/cron | external-source reachability decided | DB/cron inventory | retained |
| Cloud refs/Management API paths | self-hosted deploy proven | repo/config scan | retained |
| Old JWT/API/service keys | adoption and rotation complete | revoke test | retained |
| `supabase-legacy-keepalive` Worker and anon-key secret | approved cloud retention complete | Worker/cron/secret inventory and zero required keepalive traffic | retained boundary; read-only GET only |
| `self-hosted-preactivation-guard` Worker route | canonical Function bundle promoted and internally verified | exact route inventory plus external hardened Function canaries | Worker script absent from the configured Cloudflare account on 2026-09-23; route inventory still unverified |

Cloud project deletion is never implied by another gate. It requires explicit
destructive approval after retention.

Original migration directive (2026-08-27): **delete nothing**. It covered
cloud projects, data, Storage objects, DNS records, credentials, branches,
journals, sync tables, volumes and local evidence. No deletion-ledger row is an
authorization to remove its target. Later explicitly authorized cleanup has its
own scope and receipts; this historical directive does not forbid current
user-authorized repository documentation/code cleanup.
