# Festapp documentation map

## Active reference

- [AI context](architecture/ai_context.md) — mandatory architecture and
  security rules
- [Services](architecture/SERVICES.md) — permissions, offline data and client
  synchronization
- [Database](architecture/database.md) — SQL structure, RPCs and security
- [Mutation architecture](architecture/mutations.md) — canonical write boundary
- [Tenant overlays](architecture/tenant_overlays.md) — production branch policy
- [Edge Functions](backend/edge_functions.md) and
  [image delivery](backend/image_worker.md)
- [Local development](setup/local_development.md) and
  [tenant setup](setup/howto.md)
- [Automation](../automation/README.md) and
  [Cloudflare deployment](../automation/cloudflare/README.md)

Feature-level README files live beside the Flutter and web-client code they
describe.

## Operational records and historical material

Completed plans and audits live under `docs/archive/`. Preserve their commands,
versions and status statements as historical evidence; do not treat them as the
current operating procedure. `docs/plans/` contains only work that is still
pending or remains an input to an active gate. Current runbooks and open work
are under `docs/runbooks/` and `docs/operations/work-items/open/`.
