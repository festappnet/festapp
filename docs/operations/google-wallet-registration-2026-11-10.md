# Google Wallet registration - 2026-11-10

## Identity and setup

- Google account and issuer administrator: `bujnmi@gmail.com` (Michael Bujnovský).
- Existing Google Cloud project: `festapp-d23ef` (Festapp). Google Wallet API is enabled.
- Google Pay & Wallet Console public business name: `Festapp` (corrected from `FestApp` after registration), merchant ID `BCR2DN6DWL4N5QKI`; issuer ID `3388000000023240663`. The business profile is approved. It uses the existing Michael Bujnovsky individual payments profile, a Czech business location and category Theatrical Ticket Agencies (7922).
- Business and support site: `https://vstupenky.online`, `https://vstupenky.online/support/`; support email `info@festapp.net`. The owner supplied the support phone in the console.
- The owner explicitly authorized accepting the [Google Pay & Wallet Console additional terms](https://pay.google.com/intl/en_us/about/business/terms/) and [Google Wallet API terms](https://developers.google.com/wallet/terms-of-service), which were accepted during registration.
- Dedicated service account `festapp-google-wallet@festapp-d23ef.iam.gserviceaccount.com` is enabled and has Developer access in the Wallet Console. No project IAM role was assigned during creation.
- Service account JSON, base64 encoded, was stored in the encrypted macOS login Keychain as generic password service `festapp-google-wallet-service-account-json-base64`, account `festapp-google-wallet`. A readback matched the downloaded JSON; the downloaded copy was removed. This is verified local Keychain storage, not verified iCloud synchronization. Do not print the credential or place it in the repository.

## Demo and publishing status

A demo `EventTicketClass` and `EventTicketObject` were created using a ticket in a disposable local database. Google returned the class as approved and object as active. A signed Google save link was opened in a background tab under the issuer admin account, and Add produced a saved pass detail page with Archive and Remove actions. The pass displayed `[TEST ONLY] Festapp Tickets` and the Czech demo title. A light, QR-free detail crop is at [saved-demo-title.png](google-wallet/saved-demo-title.png); it is a partial visual record, not proof of scanning or synchronization.

The implementation and demo are local. No production Wallet route, backend credentials, migration or integration was deployed or activated, and no ticket email was sent. The demo used the direct Google save link; it does not demonstrate a deployed email-to-Wallet journey. Local admission and update evidence is recorded below.

The Console showed business profile complete and publishing access at 1/2 steps. Request was clicked once after the demo, but an independent Console readback still showed 1/2 and an enabled Request button. Submission is therefore **not confirmed**; do not represent it as pending or approved. Investigate the response before another attempt. [Google's event-ticket instructions](https://developers.google.com/wallet/tickets/events/test-and-go-live/request-publishing-access), updated 2026-11-09, state that screenshots are no longer required to raise a production-access request. Publishing approval remains a Google decision and is distinct from deployment or activation.

## Local admission and saved-pass update

The local scanner admission RPC accepted the demo ticket's original QR value; a second admission returned conflict/already used. This verifies the admission contract using the QR value, not an optical camera scan. The Wallet synchronization worker then updated the same saved object: API readback reported `COMPLETED`, unchanged QR value, and `hasUsers=true`.

After one refresh of the saved pass in the issuer administrator's Google Wallet, the web detail showed 14 November 2026, 19:04-23:04 and `Nový ukázkový sál`, matching the updated demo data. Its control changed from `Archive` to `Unarchive`; the web detail did not explicitly label the pass completed. This verifies visible metadata and archive-state changes, while the `COMPLETED` state is established by the Google API readback. No QR screenshot was captured.

After a local storno, the worker synchronized the same saved object again. Google API readback reported `INACTIVE`, unchanged QR value, and `hasUsers=true`. This is API evidence; the post-storno Wallet UI and an optical camera scan were not verified.


## Optical simulation from the real Wallet rendering

The owner subsequently requested an optical scan simulation. A fresh disposable
local ticket (347) was issued through the normal capability resolver and Google
Wallet orchestration and saved in the authorized Google account. Its actual
Google-rendered QR container was captured in light mode at 364 x 364 pixels,
device pixel ratio 2. The private original capture remains outside the repository;
its SHA-256 and metadata are in [optical-scan-evidence.json](google-wallet/optical-scan-evidence.json).
No QR was regenerated from the API value for this test.

The captured RGBA pixels were supplied as a simulated camera frame to the
unmodified production `ScannerInput.frame` and `decodeQRCodes` with jsQR 1.4.0.
The decoded symbol matched the original ticket. That decoded output, rather than
a substituted database symbol, was submitted through the canonical scanner
lookup/admission RPC: first admission was accepted; a second image scan returned
`conflict/already_used`. The local ticket became `used`.

Normal Wallet reconciliation updated that same object. An independent Google
REST GET confirmed `completed`, `hasUsers=true` and unchanged barcode. The saved
Google Wallet UI was refreshed and showed `Unarchive all`, `Remove` and
`Remove all`, confirming saved/archived presentation rather than an Add preview.
This is a successful optical simulation from authentic displayed pixels; physical
camera optics, glare and a phone display were not exercised. Production and
publishing status are unchanged.
