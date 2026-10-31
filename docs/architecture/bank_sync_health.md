# Bank synchronization health and incident response

BankSync owns bank credentials, Fio requests, rate limits, retries and statement
recovery. Festapp never retries Fio from the health monitor. Every five minutes
it reads BankSync account metadata and ingress state, then records an observation.
The legacy BankSync error strings are decoded only in `bankSyncRemote.ts` into
an allowlist of safe codes. Raw errors and token material never reach the client.
The notification-center adapter translates detailed temporary Fio failures to
its existing `bank_sync_retry_required` reason before committing a leased
observation. The notification-center SQL reason allowlist remains authoritative;
new account-health codes must never be forwarded to that contract implicitly.

Festapp SQL owns the diagnosis, incident lifetime and notification policy.
`bank_sync_problem` is the shared diagnosis for account settings, order readers
and notifications. `bank_sync_alert_ready` is used both before enqueueing and
before sending. Email rendering and Flutter consume the diagnosis rather than
independently deciding whether a bank is broken.

| Observation | Diagnosis | Response |
| --- | --- | --- |
| BankSync reports Fio token invalid/inactive | `token_invalid` | Bank admin verifies token authorization and validity. |
| BankSync reports a receiving-account mismatch | `account_mismatch` | Bank admin verifies which account the token belongs to. |
| Confirmed missing token or forwarding setup | `token_missing`, `email_missing` | Bank admin completes setup. |
| Fio 5xx, rate limit, timeout or abort | `temporary_failure` | BankSync retries; do not rotate the token or disable sync. |
| Cannot read BankSync management state | `unavailable` | Availability is unknown; do not claim Fio or its token failed. |
| Fresh observation shows no successful pull for 30 minutes | `stale` | Automatic retries continue; successful payment delivery is not proof of a successful bank pull. |
| Other bank error | `bank_error` | Unknown cause; automatic retry/support guidance, without a credential diagnosis. |
| Unexpectedly disabled polling/ingress | `connection_disabled` | Bank admin checks connection configuration; do not promise retries. |
| Deliberately suspended connection | `suspended` | Show disabled state; do not send outage mail. |

Actionable faults require ten minutes of observation before notification.
Availability faults require sixty minutes. These windows start with the first unresolved
observation, rather than counting failed requests. Changing between availability symptoms
preserves the incident and its clock. A new actionable fault starts a new
incident, including when a different actionable fault replaces the previous one.
A confirmed recovery clears the incident and invalidates pending outage mail.
There is no automatic recovery email; the live warning disappears on recovery.

Notifications go to admins of the receiving bank account and its configured
aliases, independently of event/tenant admin roles. One mailbox receives at most
one warning per incident, even when several identities share that address.
Before sending, the email queue rechecks the current incident, fresh health,
notification threshold and the selected recipient's current bank-admin right and
delivery address. Email describes the recorded observation; switching between
retry symptoms does not create another notification. A change requiring a new
administrator action invalidates the earlier advice through its new incident ID.

No monitor result proves the exact source of a 502: Fio, a relay or their network
may be responsible. Do not claim a bank outage based on this status alone.
All changes are local until the migration, Edge Functions bundle and selected
tenant web UI are released through the repository workflows.
