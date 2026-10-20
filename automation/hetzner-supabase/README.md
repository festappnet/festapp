# Self-hosted backend tooling

The canonical Festapp backend is `https://api.festapp.net`. This directory
contains its host configuration, Function packaging, backups and retained
migration/recovery tools.

For a new host, start with [server deployment](../../docs/setup/server_deployment.md).
For a tenant on the existing backend, use [tenant setup](../../docs/setup/howto.md).
The host scripts retain original migration-specific constraints; the directory
is not a portable one-command production installer.

## Current operations

| Task | Reference |
|---|---|
| Provision host resources | [Terraform](terraform/README.md) |
| Prepare runtime, schema, secrets and recovery | [Server deployment](../../docs/setup/server_deployment.md) |
| Reach the canonical backend | [Protected backend access](../../.agents/skills/festapp-backend-access/SKILL.md) |
| Configure Studio and SQL fallback | [Dashboard boundary](../../docs/operations/supabase-self-hosted/admin-dashboard-security.md) |
| Build and stage Edge Functions | [Function bundle release](../../docs/backend/edge_functions.md#deployment) |
| Verify backups and retention | [Encrypted backups](backup/README.md) |
| Configure DNS, Workers and R2 | [Cloudflare infrastructure](../../docs/setup/cloudflare.md) |

Resolve the selected tenant's activation, organization and any forced occasion
before reading live data. Staging a Function bundle does not restart services;
a web release does not apply SQL. Record exact source, schema and artifact
revisions for each authorized operation.

Production exports, identity mappings, credentials and raw evidence belong in
protected locations outside this repository. Public input schemas declare the
interface; private configuration supplies the values.

## Migration and recovery records

The [completed cutover](../../docs/operations/work-items/completed/canonical-self-hosted-cutover-2026-09-02.md)
records the switch. Former cloud sources remain retention/reconciliation targets,
with no routine application writes or migrations. The
[retention record](../../docs/operations/work-items/completed/legacy-supabase-decommission-2026-09-23.md)
and [cleanup receipt](../../docs/operations/work-items/completed/preactivation-and-migration-tool-cleanup-2026-10-07.md)
describe retained resources and removed tools.

[Historical Wave 0 instructions](../../docs/operations/supabase-self-hosted/historical-wave-0-tooling.md)
and the [original cutover runbook](../../docs/operations/supabase-self-hosted/cutover-runbook.md)
preserve migration gates. They are not current tenant installation procedures.

## Completed cleanup

The [October 7 cleanup receipt](../../docs/operations/work-items/completed/preactivation-and-migration-tool-cleanup-2026-10-07.md)
records removal of the preactivation Worker and unused standalone migration tools.
Former cloud sources remain frozen retention/reconciliation targets; routine writes
and migrations belong only to the canonical backend.
