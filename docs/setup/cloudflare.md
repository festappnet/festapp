# Cloudflare infrastructure

Festapp uses Pages for each tenant's combined Flutter/JavaScript website,
Workers for shared application services, and R2 for objects. Publishing a Pages
bundle updates the website; it does not deploy the shared Workers, prepare the
backend or provision all external services.

For a routine tenant web release, follow the
[Pages deployment guide](../../automation/cloudflare/README.md).
For the backend origin, follow [server deployment](server_deployment.md).

## Services and ownership

| Service | Repository source | Purpose |
|---|---|---|
| Tenant Pages project | `automation/project.conf`, `automation/cloudflare_build.sh` | Combined web bundle, routing Worker, metadata and legal pages |
| Image Worker | `workers/image-worker/wrangler.toml` | Authenticated image control and current public image delivery |
| Public sync Worker | `workers/sync-worker/wrangler.toml` | Public sync heads and immutable artifact delivery |
| Sync publisher | `workers/sync-publisher/wrangler.example.toml` | Scoped SQL projections, artifact publication and scheduled recovery |
| Backend monitor | `workers/self-hosted-monitor/wrangler.toml` | API/abuse probes, private R2 evidence and heartbeat |
| Legacy keepalive | `workers/supabase-legacy-keepalive/wrangler.toml` | Read-only retention of former cloud sources; unnecessary for a new independent installation |
| Administration tunnel | Backend Compose `admin-dashboard` profile | Protected Studio origin behind Cloudflare Access |

The hostnames and account IDs in tracked configuration belong to Festapp's
existing infrastructure. Reusing this source for another account requires
reviewing each domain, account, bucket, project and tenant mapping.

## Access and credentials

Use a Cloudflare account with the selected DNS zone and the required Pages,
Workers and R2 resources. Pages API credentials and R2 S3 credentials have
different roles; an R2 key does not authorize a Pages deployment.

| Operation | Credential or access needed |
|---|---|
| First Pages activation | Account Pages Edit plus Zone Read and DNS Edit for the exact domain's zone; the helper discovers the zone before creating the proxied CNAME |
| Routine token-based Pages release | Pages Edit once the domain is active; the script refreshes project branch/public runtime settings |
| Routine OAuth Pages release | Existing Wrangler login and an already bound project/domain; it does not run the project/DNS setup helper |
| Worker release | Workers deployment and binding permissions for that service |
| Private image signing | R2 S3 credentials scoped to the private image buckets |
| Public image cache invalidation | Cache Purge token scoped to the configured zone |
| Backup upload | R2 S3 credentials scoped to the backup bucket |
| Studio administration | Named-user Access login with the configured MFA policy and a protected Tunnel token on the host |

Keep secret values in the designated private input source or Cloudflare secrets.
Public anon keys, origins and tenant IDs may be client configuration; service-role
keys, provider credentials and signing keys must never enter Pages public vars or
compiled browser assets. Consult the
[private-input schema](../../automation/private-inputs.schema.json).

## Pages project and DNS

Prepare the tenant overlay and canonical activation profile first. Its Pages
project name, `prod/<tenant>` branch name and custom domain can differ; use the
exact values from the selected configuration.

The token-based `automation/deploy_direct.sh` path calls
`automation/cloudflare/ensure-pages-project.mjs` before building. That helper
can create a Direct Upload project, set its production branch, refresh the three
public runtime variables and attach the custom domain. If the domain is not yet
active, it discovers the zone and creates the proxied CNAME to
`<project>.pages.dev`. A conflicting record fails unless the exact reviewed
legacy takeover fields are provided. Never replace unrelated DNS records.

This setup has external effects even if the following build fails. When a run
stops, inspect the project, domain status and recorded revision before retrying.
Creating the CNAME alone is insufficient: Cloudflare also requires the domain
to be associated with the Pages project. See
[Cloudflare custom domains](https://developers.cloudflare.com/pages/configuration/custom-domains/).

The production Worker settings are `SUPABASE_URL`, `SUPABASE_ANON_KEY` and
`ORGANIZATION_ID`, resolved from the selected backend profile. The API-token
path updates them before upload. The OAuth path verifies the existing project
and domain but does not refresh those settings; use the reviewed token path
when they need to change.

No dashboard build command is required for direct uploads: compilation runs
locally. Git pushes alone do not publish this repository's production website.
Cloudflare's [Direct Upload guide](https://developers.cloudflare.com/pages/get-started/direct-upload/)
explains the underlying project and branch behavior.

## R2 objects and browser CORS

The checked-in bindings refer to these existing buckets:

| Objects | Buckets |
|---|---|
| Public sync artifacts | `festapp-public` |
| Public images | `festapp-images`, `festapp-images-a`, `festapp-images-akhweb` |
| Private images | `festapp-images-private`, `festapp-images-a-private` |
| Encrypted backup and monitoring evidence | `festapp-supabase-backups` |

Create/review required buckets separately before deploying their consumers.
A Worker binding names a bucket; it does not create it. Private-image and backup
buckets must remain private.

`assets.festapp.net` serves public sync artifacts directly from R2. Its browser
CORS policy is tracked in `automation/cloudflare/festapp-public-cors.json`.
When adding a tenant origin, update that allowlist and apply it through the
approved infrastructure change. Verify an actual browser-origin GET and response
headers, including after cache invalidation where required. A successful
server-side download does not establish browser CORS. See
[Cloudflare R2 CORS](https://developers.cloudflare.com/r2/buckets/cors/).

Public image hosts still appear as Worker custom domains in the tracked image
configuration. Moving them to direct R2 domains is a separate adoption-gated
cutover; do not attach the same host to both services. Current contracts and
pending P3/P4 gates are in [image delivery](../backend/image_worker.md).
The image configuration also declares an `IMAGES` binding, which requires the
corresponding Cloudflare Images product; Pages setup does not enable it.

## Workers and schedules

Install each Worker's locked npm dependencies in its own directory. Follow its
service-specific validation and release path; Pages uploads do not update it.
For images, `deploy.sh --check` performs typecheck, tests and a Wrangler dry run.
`--deploy-control` additionally requires the script's authority/prestate/rollback
inputs and performs the actual deployment.

The publisher's tracked file is an example, with a placeholder occasion scope.
Its real `wrangler.toml` is ignored. Resolve canonical occasion IDs, provision
`SUPABASE_SERVICE_ROLE_KEY` and `PUBLISHER_WAKE_TOKEN`, configure the exact public
asset origin and bind `PUBLIC_SYNC` before release. Preserve the five-second SQL
wake path, one-minute recovery tick and retention settings described by the
[Client Sync runbook](../runbooks/client-sync-v1.md). The old cloud-management
schedule mutators are not supported for canonical production.

The monitor uses the backup/evidence bucket plus `HEALTHCHECKS_PING_URL`,
`ABUSE_MONITOR_TOKEN` and its public API configuration. Verify a fresh evidence
object and heartbeat; the presence of a cron expression alone proves neither.
Legacy keepalive credentials belong only to retained cloud sources and must not
be reused for application writes.

## Backend DNS and protected administration

The public API uses the origin server's proxied DNS route and Caddy's restricted
API listener. The Studio hostname uses a separate Tunnel ending on loopback and
an Access application over the whole hostname. A Tunnel supplies connectivity;
the Access policy supplies user authentication. Preserve the
[dashboard boundary and activation checks](../operations/supabase-self-hosted/admin-dashboard-security.md).
Cloudflare describes the connector model in its
[Tunnel guide](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/).

## Verify the configured system

After the selected changes, verify the corresponding boundary: coherent website
version and legal pages, matching backend activation, image control CORS and
project mapping, sync freshness and artifact CORS, then protected administration
and monitor evidence where those services changed. Use read-only probes before
any separately authorized test order, email or other business write.

A passing website probe certifies that web release's response contract. It does
not establish provider quotas, account adoption, database migrations or every
application journey.
