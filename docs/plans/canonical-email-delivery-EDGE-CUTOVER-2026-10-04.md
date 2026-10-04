# Canonical email delivery - Edge Function cutover

Status: ACTIVE on the shared production backend. Owner confirmed receipt of both new Edge Function canaries and opening the PDF on 2026-10-04. User explicitly superseded the separate gateway architecture on 2026-10-04 and authorized production replacement and removal.

`process-email-queue` now prepares and sends in the existing Supabase Edge Runtime. PostgreSQL remains the durable queue, one-shot send fence, account budget, retry authority and acceptance journal. Public adapters, encrypted immutable attachments, signed Auth/SNS handlers and Orders delivery history retain their contracts. No schema or frontend rollout is required. All canonical tenants share this backend, including live.festapp.net, vstupenky.online and Hvězda mořská.

The host router exposes SES credentials only to the machine-proof-authorized queue worker. Its background task includes quota refresh and dispatch so HTTP client disconnection does not terminate journal completion. Provider acceptance followed by database failure remains fenced and becomes unknown, never an automatic resend. Unknown historical messages remain untouched.

Remove the old function directory, gateway Dockerfile/service, internal token/URL/image variables and live container/image/archive. Historical protected backups and original deployment evidence remain records, not live alternatives. Preserve the existing payload key, SES IAM permissions, SNS topic/subscriptions, Auth hook, budget and recovery cron.

Production gate: targeted sender/fencing/security/router tests, verified canonical main bundle, paused queue with drained in-flight attempts, runtime/config backup, pinned Edge Runtime deployment, actual owner plain/PDF sends with durable acceptance and signed delivery, and absence of the old active process. Do not run capacity tests. Production results will be appended after deployment.

## Production evidence

Reviewed main source: `209156fce8a6383cc3a75e3e9f8e85f240b92455` ([PR #271](https://github.com/festappnet/festapp/pull/271)). Main was synchronized before publication. Existing owner-admin merge exemption was used; branch protection was unchanged. Verification passed 242 Deno backend tests and 49 Node security/router/schema/inventory/bundle checks.

Protected deployment evidence: `/var/lib/festapp-rehearsal-evidence/email-edge-cutover-209156fce8a6` on `festapp-supabase-rehearsal-01`; runtime database `festapp_rehearsal_20260909220601`, organization 1, festapp activation generation 1. Configuration and function backup retained with private permissions. No database migration was needed. Installer evidence: `production-function-bundle-20261004T084117Z/result.json`. Runtime remains digest-pinned `supabase/edge-runtime:v1.74.0@sha256:ac5a8314e0c45b0f65d091643c1d6f5293e3a38f31fd3d15186e04a9d5c91cb7`.

Queue paused and in-flight count reached zero before the old worker stopped. The first HTTP wake during runtime restart received 503 while upstream connected; queue stayed paused. A subsequent real AWS preflight returned 200 with zero claimed messages and refreshed verified quotas. Queue then resumed and both designated messages sent successfully.

| Canary to bujnmi@gmail.com | Canonical message | Provider message | Accepted UTC | Signed delivery UTC |
| --- | --- | --- | --- | --- |
| Plain | 951adde6-5b3b-45dd-8c50-83dd7a27b25e | 010701a1061487cb-cd547550-2a72-4fd3-be0d-f62d6e29c9ba-000000 | 08:42:51.343521 | 08:42:51.930 |
| PDF attachment | b627f110-bfc9-4bef-905f-45b08db740d0 | 010701a106148c82-e2899850-5392-40d6-889c-6104b32ae5ff-000000 | 08:42:52.525741 | 08:42:53.061 |

Both acceptance journals and post-actions completed. Owner also confirmed both deliveries and readable PDF. Signed SNS handler remains active; unauthenticated queue invocation returns 401. Auth health returned 200. Recovery cron job 12 remains active in postgres and targets the canonical database. Health reports fresh quota, no circuit or incident and no operational alerts; allocation remains 2/second and 10,000/day. Historical unknown count remains two and neither was resent.

The live gateway container, Docker image and staged image archive were removed; its active function directory, service configuration and environment inputs are absent. Local gateway images were also removed. Historical protected backups remain archival evidence. Before removal the gateway used 66.23 MiB; the restarted Edge Runtime measured 203.5 MiB afterward, versus 706.9 MiB beforehand. These are snapshots after a restart, not a controlled RAM savings comparison.
