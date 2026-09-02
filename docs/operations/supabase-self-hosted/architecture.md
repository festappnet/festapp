# Canonical self-hosted Supabase architecture

The final production authority is one pinned Supabase stack, one PostgreSQL/Auth/
Storage authority and one public endpoint: `https://api.festapp.net`.

`default` (`kjdpmixlnhntmxjedpxh`) is the canonical data base. Source `a`
(`lwfpdjxsdmkfyrzqbrlk`) is imported only through staging and versioned mapping
rules. An organization is identified by `(source_project, organization_id)`.

Production cutover uses one coordinated full freeze across `default`, `a` and
`slunovrat`. Application, Auth refresh, Storage, Functions, cron, webhook,
worker and operator writes stop before the fresh snapshots and remain stopped
until either canonical activation or rollback. Journal hybrid is not authorized
and is not a production fallback. Client dual-write, reverse sync and persistent
application migration triggers are forbidden.

The canonical application write seam is the existing typed `client_sync_v1`
command module. A Flutter call reaches one explicit domain RPC that owns
authorization, durable business DML, idempotency and audit evidence in one
PostgreSQL transaction. This seam improves normal operation but is not treated
as proof that every already-released client write is journaled; the full freeze
is therefore mandatory.

Cloudflare does not own relational writes. It fronts the public endpoint and
continues to own the existing image/R2 adapter, where globally distributed
object delivery provides actual leverage. A Worker/Hyperdrive database adapter
would be a shallow second interface over the same regional PostgreSQL and could
not make an R2/object write atomic with a relational transaction. Object
storage remains a separately reconciled side effect with checksums and receipts.

The public front door is proxied DNS/WAF with hostname-specific strict origin
TLS. Hetzner ports 80 and 443 accept only Cloudflare's published proxy ranges;
Caddy terminates TLS and forwards to the loopback-only Supabase gateway. No
Cloudflare Worker, Hyperdrive or D1 hop is used for ordinary Supabase traffic.

Production cloud projects remain read-only for the approved retention period.
Deleting them always requires a separate explicit approval.
