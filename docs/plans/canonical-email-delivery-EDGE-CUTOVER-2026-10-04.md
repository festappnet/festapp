# Canonical email delivery - Edge Function cutover

Status: implementation and verification in progress. User explicitly superseded the separate gateway architecture on 2026-10-04 and authorized production replacement and removal.

`process-email-queue` now prepares and sends in the existing Supabase Edge Runtime. PostgreSQL remains the durable queue, one-shot send fence, account budget, retry authority and acceptance journal. Public adapters, encrypted immutable attachments, signed Auth/SNS handlers and Orders delivery history retain their contracts. No schema or frontend rollout is required. All canonical tenants share this backend, including live.festapp.net, vstupenky.online and Hvězda mořská.

The host router exposes SES credentials only to the machine-proof-authorized queue worker. Its background task includes quota refresh and dispatch so HTTP client disconnection does not terminate journal completion. Provider acceptance followed by database failure remains fenced and becomes unknown, never an automatic resend. Unknown historical messages remain untouched.

Remove the old function directory, gateway Dockerfile/service, internal token/URL/image variables and live container/image/archive. Historical protected backups and original deployment evidence remain records, not live alternatives. Preserve the existing payload key, SES IAM permissions, SNS topic/subscriptions, Auth hook, budget and recovery cron.

Production gate: targeted sender/fencing/security/router tests, verified canonical main bundle, paused queue with drained in-flight attempts, runtime/config backup, pinned Edge Runtime deployment, actual owner plain/PDF sends with durable acceptance and signed delivery, and absence of the old active process. Do not run capacity tests. Production results will be appended after deployment.
