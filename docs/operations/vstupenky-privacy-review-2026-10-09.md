# Vstupenky.online privacy review - 2026-10-09

Scope: registration and public legal documents for `vstupenky.online`, including
its web administration and event-program routes. No production writes, sends,
customer-content reads, pushes or releases were performed.

## Verified deployment and services

- `origin/prod/festapptickets:automation/project.conf` selects canonical backend,
  tenant `festapptickets`, organization 3 and Cloudflare Pages project
  `vstupenkyonline`. Live `/backend-activation.json` matches tenant, canonical
  backend and generation 1. The live JavaScript bundle agrees on organization 3
  and `https://api.festapp.net`. Read-only database identity and organization
  title checks matched this target before scoped configuration queries.
- PostgreSQL/Auth run on the verified self-hosted stack. Hetzner hosts that
  stack; Cloudflare fronts requests and provides Pages and R2 images/files and
  encrypted off-host backups. Self-hosting the database does not imply that
  every other service or every backup is on the same host.
- Production transport configuration identifies Amazon SES, `eu-central-1`.
  SES receives recipient, rendered message and attachments. No test email was
  sent. Sources: `docs/setup/aws_ses.md`,
  `supabase/functions/_shared/emailSender.ts`, `sesProvider.ts`.
- Organization 3 has enabled Google sign-in clients for standalone and Flutter
  web. Google sign-in requests `openid email profile` and reads provider account
  identifier, verified email and name. Source:
  `supabase/functions/_shared/googleAuthFlow.ts`, `googleAuthProtocol.ts`.
- Live HTML loads Roboto and Material Icons from Google Fonts. This is separate
  from app-store distribution. `web_client/index.html` also configures those
  external requests.
- Production organization configuration has a OneSignal app identifier; tenant
  Flutter config enables web notifications. The standalone landing page does
  not load the OneSignal SDK itself; web administration/program handoff can
  initialize the Flutter web notification adapter. The owner subsequently
  confirmed that OneSignal is not used for Vstupenky.online. Configuration
  presence was not evidence of actual use; OneSignal and notification processing
  were removed from the tenant notice. Runtime notification settings were not changed.
- Online map fallback can request OpenStreetMap tiles:
  `lib/components/map/legacy_map_surface.dart`. This is conditional on opening
  a map and its selected renderer/resources, not an initial-registration request.
- Browser storage contains auth/session material, language/theme preferences and
  cached application data. Source: web client auth/localization/theme services
  and `lib/data_services/offline_data_service.dart`.
- Forms can request birth date/year, address, nationality or ID-document fields;
  bank matching can process payer/transaction data. These are conditional on the
  organizer's form and payment setup, not mandatory platform-account fields.

## Email measurement and retention

Scoped production aggregates confirmed `open` policy on existing organization-3
order/custom messages and `disabled` on sign-in/password-reset messages. No
`engagement` policy appeared in that scoped inventory. Click measurement is a
shared-system capability; it is not presented as currently active for this tenant.

`email-provider-events/events.ts` persists normalized events without IP address,
user agent or clicked URL/raw payload. This does not establish what AWS processes
before normalization. Open measurement uses a recipient-linked image request;
it is distinct from transport delivery feedback.

The deployed `recover_email_delivery()` definition contains the 30-day terminal
message-body and 90-day detailed-event cleanup rules found in canonical SQL.
Sensitive message bodies are cleared after termination/expiry. Correlation,
deduplication and summary metadata can remain; the policy does not promise that
all email records disappear after 30 or 90 days.

The backup service exists. Canonical backup policy specifies 14 daily days plus
four completed weekly copies and minimum recovery copies, with exclusions for
incomplete sets, migration/recovery archives and runtime logs. The public policy
therefore describes bounded backup rotation without promising a universal exact
maximum for every retained artifact. Former cloud retention archives were not
queried or represented as deleted.

## Changes and remaining decisions

The privacy notice now names actual relevant providers, browser storage,
conditional form/payment data, email opening measurement, and verified cleanup
rules. App-store terms remain absent.

Recipient-linked email-open measurement is enabled by default in
`database/functions/emails/email_queue.sql`; a separate tracking-consent check
was not found in that producer path. Disclosure alone does not establish a
lawful ePrivacy/GDPR basis. Before treating this as a completed privacy release,
decide whether to disable optional measurement for this tenant or implement an
appropriate independent choice and enforcement. No measurement settings were
changed by this review.

Contracts, subprocessor lists, third-country transfer safeguards, precise
technical-log lifetimes, organizer-specific retention and agreements under
Article 28 were not verified from signed documents. Do not claim that all data
stays in the EU or that this notice establishes comprehensive legal compliance.

References:
- [EDPB - transparency and individual rights](https://www.edpb.europa.eu/sme/be-compliant/respect-individuals-rights_en)
- [EDPB - ePrivacy technical scope, tracking pixels](https://www.edpb.europa.eu/system/files/2024-10/edpb_guidelines_202302_technical_scope_art_53_eprivacydirective_v2_en_0.pdf)
- [AWS - email metrics](https://docs.aws.amazon.com/ses/latest/dg/faqs-metrics.html)
- [Cloudflare - R2 data location](https://developers.cloudflare.com/r2/reference/data-location/)

The notice was subsequently shortened at the owner's request, retaining the
verified data categories, purposes, providers, email measurement and retention,
browser storage, rights and contact information.

## Follow-up: operational retention verification

The owner's challenge prompted a check of execution, not just configured rules:

- The active email-recovery job runs every minute against the verified canonical
  database. Its last 20 completed runs succeeded. Latest observed completion:
  2026-10-09 00:38 UTC. Scheduler metadata lives in the `postgres` database;
  application data remains in the verified canonical runtime database.
- Organization-3 email records date from 2026-10-04 to 2026-10-08. No terminal or
  expired security message retained either a prepared body or ciphertext in its
  producer data. Existing accepted sign-in/reset messages had both cleared.
- There were no matching overdue 30-day prepared copies or 90-day delivery
  events. Because the tenant's current queue records are younger than those
  thresholds, this does not empirically test an aged tenant record; the deployed
  cleanup definition and successful scheduler executions establish the rules.
- The backup and encrypted-runtime-log upload services last completed
  successfully, on 2026-10-08 and 2026-10-09 respectively. This is evidence of
  successful operations, not a universal guarantee about all archival copies.

The notice now explicitly limits the 30/90-day statements to prepared copies and
individual delivery events in the sending queue. It does not claim that every
copy of email-related data, every account/order record or every backup disappears
on those deadlines. The vague universal assertion that all backups and technical
logs have bounded operational retention was removed from the public paragraph.
No cleanup routine was manually executed and no production data was modified.

At the owner's request, the public notice subsequently omits the 30/90-day
queue implementation details entirely. The technical evidence above is retained
for internal review; public wording describes purposes of email-data retention
and the possibility of temporary copies in backups.
