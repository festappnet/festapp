# Festapp documentation

For an introduction to the platform, see the [project README](../README.md)
and [features and screenshots](overview/features.md).

## Development

| Task | Guide |
|---|---|
| Set up dependencies and application configuration | [Developer setup](setup/howto.md) |
| Start an isolated database and run SQL tests | [Local database](setup/local_development.md) |
| Change code and choose checks | [Contributing](../CONTRIBUTING.md) |
| Understand architecture and repository conventions | [Architecture context](architecture/ai_context.md) |
| Work with tenant branding and branches | [Tenant overlays](architecture/tenant_overlays.md) |

## Architecture and feature contracts

- [Database](architecture/database.md) and [mutation architecture](architecture/mutations.md):
  SQL domains, authorization and transactional writes.
- [Client services](architecture/SERVICES.md) and [Client Sync](runbooks/client-sync-v1.md):
  permissions, local stores, synchronization and runtime health.
- [Edge Functions](backend/edge_functions.md), [image delivery](backend/image_worker.md)
  and [outbound email](setup/aws_ses.md): service boundaries and configuration.
- [BankSync](setup/bank_import.md) and [Google sign-in](operations/auth/google-sign-in.md):
  integration ownership and operation.
- [Web scanner](runbooks/web-scanner.md), [ticket layout editor](../lib/components/ticket_layout/README.md)
  and [tab deep links](architecture/tab_deep_links.md): feature-specific contracts.

Complex features keep their contracts beside the code. The
[architecture context](architecture/ai_context.md#feature-readmes-complex-components-only)
links to those READMEs; use them when changing a feature across SQL and clients.

## Deployment and operation

| Task | Guide |
|---|---|
| Set up or maintain the backend host | [Server deployment](setup/server_deployment.md), [backend tooling](../automation/hetzner-supabase/README.md) |
| Access the backend and SQL administration | [Protected administration](operations/supabase-self-hosted/admin-dashboard-security.md) |
| Configure Cloudflare infrastructure | [Cloudflare](setup/cloudflare.md) |
| Publish one tenant's web application | [Web deployment](../automation/cloudflare/README.md) |
| Build or publish mobile apps | [Android](../automation/release/android_play_release.md), [iOS](../automation/release/ios_howto.md) |
| Inspect or recover email delivery | [Email operator runbook](../automation/email-delivery/RUNBOOK.md) |

## Plans and records

[Plans](plans/README.md) describe proposed work and designs with remaining gates.
[Operational work items](operations/work-items/README.md) track approved external
work, blockers and closure evidence. [The archive](archive/README.md) holds
completed plans, superseded procedures and dated records.

Use current guides for operating procedures. A historical command, version or
successful check describes its recorded scope and date; it is not an instruction
to repeat that rollout or proof of today's production state.
