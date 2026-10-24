# Backend server deployment

The Festapp backend runs a self-hosted Supabase stack behind Cloudflare and
Caddy. Web frontends deploy separately to Pages. Adding a tenant to the existing
backend normally needs configuration and tenant data, not another server.
Start with [tenant setup](howto.md) if that is your goal.

The checked-in host tooling was built for the original canonical-backend
migration. It can prepare a rehearsal foundation, but it is not a complete,
portable fresh-production installer. In particular, promotion expects the
original three-source import evidence, a timestamped database and the approved
host name. Provisioning a new machine alone does not satisfy those contracts.

## What you need

| Location | Requirements |
|---|---|
| Operator workstation | Git, SSH, Python 3, Node.js, `jq`; Terraform for host provisioning; protected access to private runtime inputs |
| New host | Ubuntu 26.04 on ARM64 for the current bootstrap; root access; persistent disk and outbound package/container access |
| Host runtime | Docker and Compose versions selected by `runtime/bootstrap-host.sh`; Git for the upstream stack checkout; Python 3 for configuration |
| Backup host tools | `age`, `rclone`, `flock`, `jq`, Python 3, Docker, `sha256sum` and `tar`; an off-host decryption identity for restore |
| External services | Cloudflare DNS/proxy, protected administration tunnel, R2 backup storage, outbound email service and configured integrations |
| Application data | Reviewed schema/migration state, organization/unit ownership, initial administrator and public tenant activation profile |

Repository paths below are relative to `automation/hetzner-supabase/`.
Read version values from the source; do not substitute the newest independent
Supabase container tags. The compatible image bundle is pinned in
[`runtime/pins.json`](../../automation/hetzner-supabase/runtime/pins.json).

The Terraform defaults select a `cax11` host in `nbg1`; those are configuration
defaults, not a production capacity guarantee. Size disk for the database,
Storage, backups in progress, logs, staging and a restore rehearsal. The original
migration gates require at least 50% free disk before promotion.

## 1. Prepare host and network

Use the [Terraform module](../../automation/hetzner-supabase/terraform/README.md)
with state and real `.tfvars` outside Git. Its firewall admits SSH only from
explicit administrator CIDRs and HTTP/HTTPS only from the listed Cloudflare
proxy ranges. PostgreSQL must not be exposed to the Internet. Check current
proxy ranges before provisioning a new host.

Cloud-init configures SSH hardening and basic utilities. It does not install
the complete runtime. `runtime/bootstrap-host.sh` checks root, ARM64 and Ubuntu
26.04, then installs pinned Docker/Compose packages and the Docker log policy.
Git, Python 3, `age` and `rclone` are not installed by that script; verify or
provision them separately before the steps that use them.

For existing production operations, use the
[protected backend access channel](../../.agents/skills/festapp-backend-access/SKILL.md).
The public SSH firewall rule is a provisioning boundary, not a replacement for
that established access path.

## 2. Prepare the Supabase runtime

`runtime/deploy-rehearsal.sh` requires root and refuses to overwrite
`/opt/festapp-supabase`. It checks out the pinned upstream Supabase revision,
copies the Festapp Compose/Caddy files and operational tools, generates a
root-only `.env`, then starts Compose. Its companion
`configure-rehearsal-env.py` writes rehearsal endpoints and defaults.

Treat this as a rehearsal initialization step on an empty host. It does not:

- populate the canonical application schema and tenant data;
- install the reviewed production Function bundle;
- configure the full email queue or BankSync integration;
- create DNS, R2 buckets, Cloudflare Access or backups;
- establish production activation or verified administrator access.

The production stack combines the upstream `docker-compose.yml`,
`docker-compose.festapp.yml` and `docker-compose.database-target.yml`.
The email queue uses the additional `docker-compose.email.yml` overlay.
Validate the exact composed configuration with `docker compose config -q`
before changing services. Avoid printing an expanded Compose configuration,
which can contain secret values.

## 3. Supply private runtime configuration

Provision runtime files outside the source checkout with root ownership and
mode `0600`. The public schemas
[`private-inputs.schema.json`](../../automation/private-inputs.schema.json) and
[`tenant-external-services.schema.json`](../../automation/tenant-external-services.schema.json)
declare input names and contracts; neither contains the secret values.

The base stack needs database/JWT/Auth/gateway credentials, public API/site URLs,
Auth redirect origins, an internal administrator credential and the Function
inputs required by Compose, including `QR_RATE_SALT`, `AWS_SNS_TOPIC_ARN` and
`NOTIFY_WEBHOOK_TOKEN`. Rehearsal placeholder values are not production provider
configuration. Keep stable encryption, signing and identity keys through normal
runtime upgrades.

Configure each enabled service through its own guide:

| Service | Inputs and checks |
|---|---|
| Outbound email and Auth email | [SES queue](aws_ses.md): `EMAIL_SES_*`, payload encryption, signed Auth hook, exact feedback topic and global quota/pause state |
| Google sign-in | [Google broker](../operations/auth/google-sign-in.md): client credentials, callback, encryption and mailbox HMAC keys |
| Bank synchronization | [BankSync](bank_import.md): instance identity, control credentials, webhook HMAC and explicit account rollout |
| Image writes and private reads | [Image Worker](../backend/image_worker.md): registry, R2 bindings, CORS, signing and purge inputs |
| Client Sync | [Sync runbook](../runbooks/client-sync-v1.md): publisher credentials, exact occasion scope, R2 delivery and scheduler |

Fresh application provisioning needs a reviewed tenant seed and administrator
assignment. The local baseline plus `supabase/seed.sql` creates a disposable test
fixture; it is not a production seed. Do not run the removed browser SQL installer,
cloud CLI deployment or the historical cloud-source import sequence as a shortcut.

## 4. Install schema and Functions through their reviewed paths

Author schema and RPC changes in the repository and package their forward
migrations. Use the verified canonical database and protected access path for
an existing production target. The
[SQL fallback](../operations/supabase-self-hosted/admin-dashboard-security.md#command-line-sql-fallback)
checks the expected database and file digest; its example historical migration
must not be replayed.

For Edge Functions, follow the
[bundle procedure](../backend/edge_functions.md#deployment).
`build-production-function-bundle.sh` requires clean synchronized `main` and
writes an immutable artifact outside the repository.
`install-production-function-bundle.sh` verifies the package and replaces the
installed Function tree while retaining the previous tree. Installation does
not restart the runtime. Plan the affected service restart and canaries as a
separate release step.

Several host tools, including runtime promotion, upgrades and backup installation,
require `hostname -s` to equal `festapp-supabase-rehearsal-01`. That historical name
also identifies the existing production host. A new host or independent
installation requires reviewed tooling/configuration changes; renaming a machine
to bypass a check does not establish its identity or migration evidence.

## 5. Connect Cloudflare and administration

Configure the public API through proxied DNS and Caddy; keep the gateway bound
to loopback. The Caddy configuration rejects direct Internet origin requests
and forwards only the documented API path families. Check origin TLS and
Cloudflare routing before changing an application activation document.

The browser dashboard uses its own Cloudflare Tunnel and Access application,
ending at `127.0.0.1:8999`. It must not share a public origin-IP record with the
API. The exact identities, MFA/session policy and ordered activation checks are
in the [dashboard guide](../operations/supabase-self-hosted/admin-dashboard-security.md).
The [Cloudflare infrastructure guide](cloudflare.md) covers the other services.

## 6. Establish recovery and monitoring

Online backups need an R2 bucket, an `age` recipient and root-only
`/etc/festapp-backup/r2.env`. The decryption identity belongs in a separately
protected restore location. Install the scheduled backup/log jobs only after
checking their host guard, credentials and dependencies. Then verify a fresh
encrypted set in R2 and rehearse its restore on a disposable target.

The backup includes PostgreSQL, globals, legacy Storage and runtime material.
Image and Client Sync buckets are separate stores; confirm their recovery
policy too. The runtime tar uses an explicit path list and currently omits the
email Compose overlay and other auxiliary inputs such as Tunnel token files and
systemd jobs. Preserve those from the protected release/configuration source
when rehearsing complete recovery. A successful database backup does not prove
that separate object stores or all service files were copied.
See [backup retention and verification](../../automation/hetzner-supabase/backup/README.md).

Configure the self-hosted monitor's R2 evidence binding and private heartbeat/
monitor inputs. Confirm API canaries, Auth, the expected database, queue health,
publisher freshness and protected dashboard access. Record the exact runtime,
schema, Function bundle and tenant generation being checked.

## 7. Activate the selected tenant

Use the [tenant overlay policy](../architecture/tenant_overlays.md) and
[Pages release guide](../../automation/cloudflare/README.md). Verify that
`backend-activation.json` agrees with the configured tenant, canonical endpoint,
generation and organization before testing event data. A web upload does not
migrate the backend or activate an external integration.

The [original cutover runbook](../archive/operations/supabase-self-hosted/cutover-runbook.md)
is retained for migration/recovery evidence. Its frozen-source inventories,
three-source validation and promotion acknowledgements are specific to that
migration, not general instructions for a new empty installation.
