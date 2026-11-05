# Sale opening subscription bot protection

Public subscription uses Cloudflare Turnstile Managed with `appearance:
interaction-only`. Verification starts on submit; most normal checks run in the
background, and only a provider-requested interaction becomes visible. There is
no image puzzle UI added by Festapp, registration/login or confirmation email.
The current browser adapter serves both public JS and Flutter **web**. Native
Flutter has no Turnstile WebView adapter and fails closed; it must not bypass
verification. Native support requires a separate browser/WebView continuation.

## Server boundary

`operation=protection` returns only the public sitekey and action, with no-store
headers and no database lookup. The `subscribe` POST must provide `botToken`.
Before any contact write, the Edge function calls Cloudflare Siteverify and
requires all of:

- `success=true` (Cloudflare enforces one-use tokens and five-minute expiry).
- Exact hostname in the configured server allowlist, independent of client headers.
- Action `sale_opening_subscribe`.
- cData equal to SHA-256 of JSON `[formLink, trimmedLowercaseEmail]`.

Missing/invalid proof returns 400; missing configuration, provider timeout/error
or malformed provider response fails closed. Raw IPs/forwarded headers are not
trusted or sent. The existing transactional recipient/unit/organization quotas,
suppression, launch dedupe and final send fences remain in force. Unsubscription
uses its existing secret capability and does not require Turnstile.

The client obtains a fresh token for each submission attempt, including retries.
It preserves the entered email when verification fails. The shared adapter removes
the widget after success, failure or timeout; third-party script loading is lazy
and retries after a load failure. No tracking or browser fingerprint is persisted
by Festapp for this feature. This is bot mitigation, not proof of address ownership
or a guarantee against every automated browser or HTTP flood.

## Runtime configuration and release

Protected Edge environment variables:

```
SALE_OPENING_TURNSTILE_SITE_KEY=<public widget key>
SALE_OPENING_TURNSTILE_SECRET_KEY=<secret, server only>
SALE_OPENING_TURNSTILE_HOSTNAMES=vstupenky.online
```

Dedicated Managed widget: `Festapp sale opening notifications`, sitekey
`0x4AAAAAAF0EthB2MjFMDUQd`. It permits vstupenky.online, localhost and 127.0.0.1
so a separate disposable backend can test real tokens. **Production's verifier
allowlist must contain only `vstupenky.online`**, never the local hostnames.
The disposable environment instead allows localhost and 127.0.0.1. Do not reuse
Mendelio/plesy widgets or copy their secrets. Any further public form origin needs
an explicit widget-domain and server-hostname update before its rollout. Embeds
must keep the form iframe hosted on an allowed origin.

The local widget credentials are protected outside the repository; secrets must
be installed using the existing protected backend configuration workflow.
No production Edge restart or environment change was performed for this work.
Ship the browser helper, index references and clients with the mandatory server
verifier as one compatible release. Missing configuration deliberately prevents
subscriptions instead of disabling protection. Keep the email queue pause/drain/
probe/resume safeguards when restarting the shared Functions runtime.

Official dummy keys are rejected with nonlocal backend/public hostnames. Tests
inject provider responses to prove rejection paths; they do not certify
Cloudflare's classifier or real provider availability. Do not automate solving
real interactive challenges.

References: [Widget configuration](https://developers.cloudflare.com/turnstile/get-started/client-side-rendering/widget-configurations/),
[mandatory server validation](https://developers.cloudflare.com/turnstile/get-started/server-side-validation/).

## Local verification 2026-11-05

Real dedicated Managed widget and real Siteverify were configured only in the
disposable Edge stack. Both desktop and 375px isolated headless browsers were
classified for interactive verification; the checkbox was not solved. Therefore
real-provider successful enrollment is **not established** by this test. This is
separate from the passing simulated positive-path unit tests.

Missing and forged tokens returned HTTP 400 `verification_failed`; all four
attempted contacts remained absent, active subscriptions remained 2 and queued
email count remained 1 (zero new messages). Blocking the provider script preserved
the typed email, displayed the existing retry error and re-enabled the button.
Browser session was closed. Local JS/Flutter previews and disposable backend
remain running, with queue paused, no worker URL and cron off.

Challenge screenshot:
`/Users/miakh/source/festapp-sale-opening-e2e-20261104/turnstile-mobile-challenge.png`.

## Extended real-provider verification requested 2026-11-05

One normal checkbox interaction in the isolated headless browser failed before
any subscribe POST. Only the public-config request completed (200); neither a
contact nor an email was created. Its generic error alone does not establish
whether the cause was classification, configuration or another provider issue.
A normal Chrome process could not remain safely in the background and was
immediately closed without navigating; user windows were not reused.

The shared adapter now emits a diagnostic custom event containing only a bounded
six-digit provider error code or `unavailable`. It never emits tokens or contacts.
Five adapter/client tests pass, including diagnostic redaction and cleanup.
Positive real-provider signup, duplicate/retry completion and Flutter web remain
pending until a real challenge can be completed and its SQL effects inspected.

The diagnostic reproduction returned actual Cloudflare code `600010` after one
ordinary checkbox click. Cloudflare's 600* family describes generic challenge
failure / detected bot behavior, not the invalid-sitekey/hostname codes. The
safe error-code event contains no submitted address or proof. Source parity of
the local index, handler and verifier with canonical repository files was checked;
no provider stub or verification bypass serves the pending manual test.

A human completion request is pending for the local form using synthetic address
`overeni-cloudflare-20261105@example.com`. Baseline: zero matching subscriptions,
one existing email message, email capacity paused and worker URL null. No positive
result should be claimed until the live guarded endpoint writes the active
subscription and its capabilities and the unchanged mail count is read back.


## Reviewed production configuration migration

`configure-sale-opening-turnstile.py --credentials <mode-0600-widget-json>` runs a
read-only preflight against the exact canonical host/database and complete six-file
Compose configuration. `--apply` additionally requires email paused and no
preparing/sending messages. It saves protected copies of `.env`, the email overlay
and current container inspection. It adds only the three Turnstile inputs, proves
the complete resulting Compose model differs only at those inputs, and deliberately
recreates only Functions with **all six overlays**, the pinned image and every
existing provider/monitoring/database input. Worker authorization is probed before
completion. Any failure restores old environment/overlay and the old configuration;
email remains paused throughout. The previous code bundle is retained separately.
The existing guarded restart tool checks the resulting model/container coherence.
Turnstile variables are routed only to the sale-opening worker. The runtime writer
policy classifies this endpoint, and the canonical pinned router registers its
handler-owned proof route. Existing function-bundle manifest and install gates
remain mandatory. Enable only the new maintenance cron after the worker probe,
then restore the previous email pause state and inspect delivery health.

During local human testing the user reported success. A new active subscription
at 2026-11-04T23:43:53.645878Z follows installation of the real widget at23:11/23:12,
has exactly one current unsubscribe capability, and coincides with a logged Edge
request. No fixture source contains this contact and no new mail was created.
The guarded local index/handler/verifier match canonical code. No raw provider
response or request token was logged; this is UI/state correlation evidence.
