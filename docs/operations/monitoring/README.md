# Festapp Monitoring and first-login notifications

The shared `@festapp/monitoring` v0.1.1 service owns incidents and operational
alert mail. `festapp-self-hosted-monitor` batches canonical backend
availability and canonical email delivery health every minute. The
shared Monitoring service owns incident alerts and missed-heartbeat detection.
The former Festapp Healthchecks check and ping credential have been removed.
The canonical Edge router reports handled HTTP 5xx and thrown worker failures,
without request bodies, URLs, error messages, user identities or credentials.
Its bounded reporting cannot change the application response. Browser/Flutter
crash reporting is outside this integration.

An independently observed email older than five minutes past its due time
produces `email_queue_stalled` through the existing `festapp-probes` credential
and operations recipient. It covers pending/retry/preparing/sending states,
including a worker killed by a CPU limit. The error incident uses the project
occurrence threshold (currently one), without the heartbeat warning delay;
shared recipient budgets and cooldown still apply. Scheduled reminders age from
their due time. No synthetic CPU load or production queue fixture is needed.

A dedicated unprivileged systemd agent on the canonical backend samples CPU,
MemAvailable-based memory use and the filesystems backing `/`,
`/opt/festapp-supabase`, `/var/lib/docker` and `/var/backups` every minute.
It uses the identical pinned SDK and a separate `festapp-host` credential
restricted to four heartbeat checks. Shared Monitoring sends warnings after
five minutes of CPU or memory use at 90%, disk use at 90%, disk free space
below 2 GiB, or inode use at 90%. Duplicate filesystems are measured once.
A missing agent heartbeat is detected after three minutes, with the same
five-minute warning delay. The agent is the parent of metric checks to avoid
four alerts for one host outage. Measurement failures report failed checks.
CPU uses interval counters, excludes double-counted guests and treats iowait
as idle; boot/reset/stale samples start with a fresh one-second baseline.
Only percentages and bounded reason codes enter Monitoring, never paths,
process lists or credentials. The server is shared, so host alerts cover its
resources regardless of which app consumes them.

Host installation: stage `automation/hetzner-supabase/monitoring/*` with
`supabase/functions/_shared/monitoring-sdk/index.js` renamed `sdk.mjs`, its
LICENSE and a SHA256SUMS manifest. Supply a protected `token` file, verify
the selected canonical identity, and run `install.sh` as root. No backend
restart or database migration is involved. Disable the timer and revoke only
its isolated credential to remove this agent; retain other Festapp monitors.

The SDK archive is pinned with npm integrity and SHA-256
`27dc3b2fa818aeb9a7e5ae4448ee75ba0c420fc020573693453c7dd56d353207`.
The Deno copy is the identical immutable bundled JS plus declarations/license.
Router reporting credentials are filtered out of child-worker environments.

First-login messages use **Festapp's existing canonical email queue**, provider,
quota, pause/suppression and signed delivery feedback. They are business
notifications, not incidents subject to Monitoring's shared 10/hour alert budget.
The minute scheduler calls `enqueue_first_login_notifications_v1()`. GoTrue's
`last_sign_in_at` and a live session establish a successful password/Google
login; accounts with verified MFA require an `aal2` session. Creating an account,
failed login, linking Google to an existing user, and repeated login do not
create another notification. Atomic dedupe is per user UUID. At initial
activation, previously signed-in accounts become baseline tombstones. Existing
accounts that have never signed in remain eligible. A session must still exist
at observation; a login immediately followed by global signout can be detected
on the next login. Email typically queues within one minute, subject to queue
availability and global provider limits. At most 100 new accounts per tick.

## Deployment

1. Verify the selected tenant activation, host and canonical database. The
   requested first-login scope is **prod/festapptickets, vstupenky.online,
   organization 3**, generation 1. No other tenant is enabled or released.
2. Validate SQL in the disposable email database with canonical service-role
   helpers, router/SDK tests, Deno checks and the Worker dry-run. Publish reviewed
   shared code on authoritative main, build its clean production function bundle.
3. Back up the canonical database/configuration/functions; pause/drain the email
   queue before installing the renderer/router bundle. Apply only
   `20261009150000_festapp_monitoring_first_login.sql`, recording its ledger
   atomically. It starts with no tenants enabled and no live capability.
4. Provision the shared Monitoring `festapp`/`production` project in record mode,
   separate `festapp-edge` and `festapp-probes` write credentials, an ops read
   credential and management credential. Reuse the verified `miakh-operations`
   recipient (`bujnmi@gmail.com`). Register heartbeat checks `canonical-backend`,
   `email-delivery` at 300000 ms cadence / 60000 ms grace.
   Set project error occurrence threshold to 1; cooldown/budgets stay inherited.
5. Store a separate random health capability hash/expiry in
   `festapp_monitoring_credentials`. Set Worker secrets `FESTAPP_HEALTH_TOKEN`,
   `FESTAPP_ANON_KEY`, `MONITORING_TOKEN`; deploy the same-account service binding.
   The anon health RPC requires that capability and returns only ok/alert codes.
   It grants no customer-table access, role escalation or mutation capability.
6. Set the router's `FESTAPP_MONITORING_URL`, `FESTAPP_MONITORING_TOKEN`,
   `FESTAPP_MONITORING_RELEASE` in the existing protected runtime environment and
   reviewed email Compose overlay. Install the verified writer policy and bundle,
   recreate only the Functions service, verify health/unauthorized routes, resume
   the queue. Enable only organization 3 with
   `configure_first_login_notifications_v1(3,'bujnmi@gmail.com',true)` and install
   `install-first-login-notifications.sh` on the canonical control-plane scheduler.
7. Verify fresh live check receipts, actual owner canary delivery and independent
   watchdog readiness. Activate Monitoring email mode through audited management.
   No frontend/Flutter build or production-branch propagation is needed.

Capabilities expire after one year; rotate with an explicit short overlap and
remove the old hash/credential after consumers switch. Secrets and raw event/mail
receipts belong in protected operational evidence, never in repository files.

## Rollback

Change only Festapp's Monitoring project to record mode, disable organization 3
with the configuration RPC, and restore the backed-up function bundle/router and
runtime overlay. Preserve the new schema, first-login tombstones and email
journals to prevent duplicate sends. Unknown provider outcomes never auto-retry.
The existing canonical queue and Monitoring's external watchdog remain active.

The initial live probe found HTTP 525 on the old rehearsal hostname. It is
outside the requested production app and is excluded from production alerting;
no rehearsal infrastructure changes were made. Canonical Auth/REST/Storage and
email health passed with actual scheduled receipts.
