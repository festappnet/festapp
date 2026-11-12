# Google Wallet operations

Google Event Tickets uses existing ticket IDs and exact admission QR values.
SQL is canonical under `database/functions/ticket_wallet/`; the additive forward
migration is `20261110230000_ticket_wallet.sql`. Regenerate it with
`python3 automation/assemble-ticket-wallet-migration.py`; verify with `--check`.
No application trigger, separate ticket lifecycle or email queue is introduced.

## Activation boundary

Google approved publishing on 2026-11-12. Wallet is activated for the explicitly
selected `vstupenky.online` organization only. The original
[registration receipt](google-wallet-registration-2026-11-10.md) describes the
earlier demo stage. Each additional tenant still needs its own readiness and
authorized rollout; shared issuer access alone does not activate it.

After a separately authorized release, use the canonical release gate, approved
backend access/restart process and one explicitly selected tenant. Configure:

- Backend secret `GOOGLE_WALLET_SERVICE_ACCOUNT`: dedicated service account JSON.
  Retrieve from its verified Keychain item without shell tracing or output.
  `EMAIL_PAYLOAD_KEY` remains the existing shared encrypted-email source owner.
- `GOOGLE_WALLET_ALLOWED_ORIGINS`: exact comma-separated HTTPS tenant origins.
  No wildcard, redirect parameter or permissive origin reflection is accepted.
- One `eshop.ticket_wallet_integrations` row per selected organization: issuer,
  immutable backend environment identity, exact web origin and verified localized
  badge URLs. Set `publishing_ready` only after real publishing approval,
  valid signing credentials, asset availability, route and demo checks.
  The local disposable demonstration deliberately simulates readiness; it does
  not represent Google publishing approval.
- `eshop.ticket_wallet_worker.worker_url`: the canonical deployed
  `/functions/v1/sync-ticket-wallet` endpoint. The null default disables wakes.
  The additive migration installs dormant cron job `festapp_google_ticket_wallet`
  for `public.wake_ticket_wallet_worker()` once per minute. Verify its trusted
  scheduler identity/service-role execution and worker probe before explicitly
  activating it. This task does not install or activate it on production.

Publish the unmodified official badges in `assets/brand/google-wallet/` through
the canonical image Worker/R2 public `assets/google-wallet/v1/<locale>.png` path
on `https://img.festapp.net`. The web page and email renderer share this fixed
versioned badge path. Do not configure nonexistent
URLs. Verify badge URLs before switching readiness on. Website and email links
must use the official artwork with a text fallback. Confirm the gateway replaces
client-supplied forwarding headers before relying on the per-source limiter.
The capability limiter remains effective independently of source headers.

## Portal branding and email previews

The stored ticket's organization owns its Wallet brand. `organizations.data.APP_NAME`
is the existing canonical display name, `DEFAULT_URL` is its canonical portal
URL, and `WALLET_LOGO_URL` selects an immutable public platform logo on the image
Worker. Configure these values per organization, not on the shared Functions
environment and not by guessing a brand from a hostname or numeric tenant ID.
For the regional portal use `vstupenky.online`; the global portal uses
`Festapp Tickets`. A shared Google issuer can retain both brands on distinct
ticket classes. Changing branding never changes the class/object identity or QR.
The platform logo is the default ahead of an inherited event logo. Explicit
Wallet appearance overrides, including removal, still apply; event artwork,
colors and the native QR retain their separate roles. `DEFAULT_LANGUAGE` supplies the
default email and badge language when no message-specific language is present.

The forward `20261112233000_ticket_wallet_branding.sql` projects branding and
read-only preview availability. Assemble/check it with
`automation/assemble-ticket-wallet-branding-migration.py`; earlier migration
bytes remain immutable. Setting a logo does not enable Wallet publishing.

Real delivery and server-rendered draft previews use the same Wallet email
section. Native template/ticket previews use the same localized copy and
unmodified official badge assets, including PDF-only delivery. Preview actions
are inert and never mint a capability, call Google or create an email intent.
The per-ticket action area can accommodate Apple Wallet after that integration
is operational; no Apple badge, device claim or placeholder action is shown now.

## Claims, rate and recovery

`ticket-wallet` accepts only explicit POST with one 256-bit fragment capability.
GET never creates a Class or Object. The page removes the fragment before other
resources run, holds it only in memory and is excluded from public analytics.
Every resolution rechecks ticket, event, order and online payment state. The
preference controls future offers; it never revokes already issued links or passes.
`begin_email_send` discards only unstarted snapshots when the current preference
or readiness differs. Existing provider attempts and unknown outcomes retain the
original queue/fencing behavior.

Identity includes issuer, immutable environment, organization, event and ticket.
Never change an established environment label or add an object-ID suffix on a
retry. Objects cannot be deleted remotely. Registration precedes Google I/O;
leases last 45 seconds, each outbound request checks its lease, and completion is
conditional on that lease. A late external response cannot be made atomic with
SQL; subsequent reconciliation repairs remote state. Failed attempts retain the
same identity and back off from 15 seconds to one hour.

The worker processes all registered objects by `next_attempt,ticket_id`, including
failed, deleted and inactive tickets. Each healthy pass is due again after three
minutes; each invocation processes at most 25 claims for up to 45 seconds. Issuer
requests share an 8 requests/second SQL reservation across tenant rows. Before
activation, measure `ticket_wallet_health()` and prove the selected issuer's
volume fits the five-minute healthy reconciliation target; scale invocation
frequency/batch work within Google's quota when required. A static batch size
alone is not evidence of the target at production volume.

A timeout after a remote write is retried with the same object identity. Expired
leases can be reclaimed; stale owners cannot complete or begin another request.
Do not delete the registration to recover. `last_error` stores a fixed sanitized
code; never log capabilities, JWTs, QR contents, email addresses or private keys.

Authenticated support can invoke `manage_ticket_wallet(ticket,'revoke')` or
`'reissue'` only through the canonical order-write predicate for the stored event.
Revoke is irreversible for the generation. Reissue leaves an audit and tombstone;
only a new valid email intent created afterward may bind a new token. Old intent
replays cannot restore access. Reissue reuses the existing Google object identity.
A contact repair alone never rotates or rewrites historical recipient evidence.

## Appearance and admission

Google controls the native card layout, font, barcode rendering and platform
state. The editor provides an explicitly approximate native preview; it never
issues a pass. Wallet inherits the active ticket template's solid color, event
logo and compatible public artwork, with optional `wallet_appearance` overrides
for `background_color`, `logo`, `hero_image`. Missing keys inherit; explicit null
removes the field; resetting to `{}` restores inheritance. Older feature/draft
payloads preserve saved choices. Local decorative PDF gallery assets and PDF
geometry/fonts are not uploaded as Wallet images.

Only canonical public image Worker URLs are passed to Google, as PNG variants.
Private/signed URLs, other origins and embedded ticket screenshots are excluded.
Google's [current guidelines](https://developers.google.com/wallet/tickets/events/resources/brand-guidelines)
recommend square logos of at least 660 x 660 pixels with a 15% safe margin, and
hero images of 1032 x 812 pixels without embedded text. The hero sits separately
from the high-contrast native QR. It cannot cover or recolor the admission QR.

`ACTIVE`, `COMPLETED`, `INACTIVE`, `EXPIRED` are presentation states derived from
current domain data. The exact original QR remains the scanner's input. A used
pass becomes `COMPLETED`; storno/revocation/invalid payment/deletion becomes
`INACTIVE`. Event term and venue edits update the same class/object. Rescheduling
updates the capability's event-based expiry, without reviving explicit revocation.
Online reconciliation does not instantly change an offline phone's appearance.
The canonical scanner remains the admission authority and rejects repeat use.

## Key rotation

Create a replacement dedicated service-account key without deleting the existing
key, persist and verify it in Apple Passwords/iCloud where supported, otherwise
the encrypted login Keychain, and record synchronization limitations. Stage it
through the approved backend secret/restart procedure. Verify OAuth, signing and
same-identity updates with a demo tester before retiring the old key in Google.
Do not rotate a key merely to change its storage location. A compromise requires
an explicit incident/revocation action, separate from the organizer's offer setting.
