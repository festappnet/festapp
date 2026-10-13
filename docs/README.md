# Festapp documentation map

## Active reference

- [AI context](architecture/ai_context.md) - mandatory architecture, canonical
  backend authority and security rules
- [Services](architecture/SERVICES.md) - permissions, offline stores and sync
- [Database](architecture/database.md) - SQL domains, RPCs and security
- [Mutation architecture](architecture/mutations.md) - canonical write boundary
- [Tenant overlays](architecture/tenant_overlays.md) - production branch policy
- [Edge Functions](backend/edge_functions.md) - inventory, auth and bundle releases
- [Image delivery](backend/image_worker.md) - Worker routing and pending P3/P4 gates
- [Local development](setup/local_development.md) and [tenant setup](setup/howto.md)
- [Automation](../automation/README.md) and
  [Cloudflare deployment](../automation/cloudflare/README.md)

## Operation guides and feature entrypoints

- [Canonical backend tooling](../automation/hetzner-supabase/README.md),
  [access and SQL fallback](operations/supabase-self-hosted/admin-dashboard-security.md),
  [completed backend switch](operations/work-items/completed/canonical-self-hosted-cutover-2026-09-02.md)
- [Google sign-in](operations/auth/google-sign-in.md) - broker setup and dated rollout evidence
- [BankSync setup](setup/bank_import.md) and
  [full cutover](operations/banksync/FULL-CUTOVER-2026-10-04.md) - ownership,
  ordered account adoption and bank email identity gates
- [Outbound SES queue](setup/aws_ses.md) - intents, acceptance and delivery feedback
- [Client Sync v1](runbooks/client-sync-v1.md) - health, lifecycle gates and
  cloud-only tooling limitations
- [Ticket layout editor](../lib/components/ticket_layout/README.md) and
  [occasion reports](../lib/components/eshop/README.md#occasion-report-snapshot)
- [Tab deep links](architecture/tab_deep_links.md) - tab ownership and access boundaries

Other feature README files live beside the Flutter and web-client code.

## Operational records and historical material

[Work items](operations/work-items/README.md) own cross-session operational status:
`open/` includes blocked and verification work; `completed/` retains closed
receipts, including work closed by user decision with resources still retained.
Do not equate code merged, a dated canary, or closure by decision with a fresh
production inventory or successful resource deletion.

`docs/archive/` preserves completed plans, audits and superseded setup guides.
`docs/plans/` also contains designs, execution prompts and dated release/evidence
records; location or age alone does not prove a plan is pending or complete.
Read each status and its linked evidence before moving or executing it.
Current procedures live in `docs/runbooks/`, relevant `docs/operations/` guides
and the active references above. Preserve historical commands as evidence,
not instructions to deploy again.
