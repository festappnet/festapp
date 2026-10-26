# Canonical self-hosted Supabase architecture

Production uses one PostgreSQL/Auth/Storage authority at `https://api.festapp.net`.
Resolve the tenant's published activation, generation and canonical organization
before reading event/user data; see [AI context](../../architecture/ai_context.md).
A compiled legacy cloud URL does not select the live database.

## Runtime boundaries

Typed domain RPCs own authorization, business writes, idempotency and audit in
one database transaction. The selected Client Sync v1 adapters call those
explicit commands. Retained legacy adapters do not authorize a return to cloud
writes or a second persistence authority.

Cloudflare fronts the public API and hosts the web, image and sync services.
Workers may orchestrate authorized RPCs; relational rules and commits remain in
PostgreSQL. R2/object writes are separately reconciled side effects, with their
own admission, object ownership, checksums/receipts and failure recovery. A
Worker/Hyperdrive hop would not make an R2 write atomic with SQL.

The public front door uses proxied DNS and strict origin TLS. The tracked
Terraform foundation admits ports 80/443 only from listed Cloudflare ranges;
Caddy forwards allowed API paths to the loopback gateway. Existing operations
use the [protected access channel](../../../.agents/skills/festapp-backend-access/SKILL.md),
not an assumed public SSH rule. Studio has its separate
[Access/Tunnel boundary](admin-dashboard-security.md).

## Migration history

The 2026 consolidation used the `default` cloud source as its base and staged
`a` and `slunovrat` through versioned mappings. Source organization identities
were scoped by `(source_project, organization_id)` during import; runtime
clients use the assigned canonical organization IDs. Preserve mapping/provenance
where it supplies authorization or audit identity.

The migration required a coordinated full freeze of application, Auth, Storage,
Function, cron, webhook, Worker and operator writes. That was the original
cutover procedure, completed on 2026-09-10, not a freeze prerequisite for each
ordinary release. Journal hybrid, client dual-write and reverse sync were not
approved fallback paths. Persistent application triggers remain prohibited.

Former cloud sources are retained history/reconciliation targets. Routine writes
and migrations stay on the canonical backend; retention and cleanup are recorded
in [the completed disposition](../work-items/completed/legacy-supabase-decommission-2026-09-23.md).
