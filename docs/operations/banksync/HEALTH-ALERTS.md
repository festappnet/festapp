# Bank synchronization health

Account administrators can pause and resume automatic synchronization from the
bank connection tab without replacing credentials. Resume verifies BankSync's
ingress and API polling flags and attempts a bank pull; bank verification failure
keeps retries enabled and exposes a degraded state. Recorded token expiry does
not prevent an explicit administrator resume.

The existing authenticated `bank-sync-reconcile` endpoint also accepts a scoped
`monitor_organization_id`. Monitoring reads BankSync account/ingress status; it
never introduces another bank polling or payment matching engine. Only the
configured organization's linked connections are observed. The service-only
`configure_bank_sync_health_monitor(organization_id)` installs its five-minute
cron using the canonical email worker origin when pg_cron is installed in that
same database. On the self-hosted backend pg_cron lives in the separate postgres
control database: install the same job there with
`automation/banksync/install_health_monitor.sql`, supplying the verified runtime
database and selected organization as psql variables. Production activation for this
release is limited to organization 3 (festapptickets).

For enabled connections, a bank error, missing token/email configuration, disabled
remote ingress/polling, or no successful API pull for 30 minutes creates a health
incident. After at least 10 minutes of observed failure, one warning per account
administrator is enqueued through the existing global email gateway. Incident
identity, queue deduplication and the notification timestamp suppress repeats.
A healthy observation starts a new notification window for any later outage.
Intentionally paused connections do not generate warning mail. Queued warnings
are invalidated before sending after recovery, suspension, administrator removal
or an explicit credential/synchronization change. Normal global email pause,
quota, suppression, expiry and delivery fences apply.

Authorized order bundles include a safe warning and account-administrator
contacts for the order's actual bank account, including canonical aliases. Only
regular orders with an outstanding payment balance display the warning. CASH
accounts, fully paid orders and inactive waiting/cancelled registrations do not.
Form bank-account cards and unit account lists use the same diagnosis. No token,
raw bank error or unrestricted contact lookup is exposed to clients.

Canonical SQL: `database/functions/eshop_bank_sync/bank_sync_health.sql`, the
three updated order/form/account reader RPCs and `email_intent_valid` in
`database/functions/emails/email_queue.sql`. Apply migrations before installing
the Function bundle, then configure monitoring for the explicitly selected
organization before deploying that tenant's web client.
