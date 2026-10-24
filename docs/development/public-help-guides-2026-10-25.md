# Core organizer help, 2026-10-25

The public help hub now contains the twelve agreed task guides in six areas:
HTML/WordPress/Webnode integration; event creation and form publication; ticket
prices/capacity, seating and ticket PDF; payments and order delivery; check-in;
troubleshooting. Matching English source articles remain preview-only. Topic IDs
are shared across languages, with distinct slugs, text and screenshot metadata.

## Content authority

Instructions were checked against the occasion-setup story, form editor/settings,
product/inventory, blueprint and ticket-layout modules; current Czech/English
translation keys; the email-delivery recovery dialog; and `docs/runbooks/web-scanner.md`.
The copy distinguishes event publication from sales opening, order creation from
payment, queued sending from delivery, cancellation from refunds, and local
pending admissions from server-confirmed admissions. Card payment availability
is not promised for organizations where it is not activated.

## Actual UI evidence

An owned disposable Supabase project `festapp-wizard-help-20261025` used API
127.0.0.1:56821, database 56822 and the real Flutter development entry point at
56880. The entry point rejects non-loopback backends. Auth, REST, draft writes,
ticket resources and generated PDF were real; external push callbacks were
stubbed by the existing entry point. Production API/OneSignal requests were
blocked in the isolated headless browser. No customer order email or real payment
was dispatched.

Fresh screenshots show event naming/dates, the product offer, sales-opening
choices, ticket setup/editor/PDF and bank-account prerequisites. UI language was
changed through Settings. Screenshots use fictional events/products and a
synthetic preview QR. The PDF image shows an actual generated PDF in Chrome.
English retains separate localized captures; its remaining publication gate
also covers detailed screenshot parity and final content qualification.

Seating, buyer seat selection, report, public payment instructions and native
mobile check-in reuse existing real synthetic product-recording posters.
`media.json` records their source asset, dimensions, review date, alt text and
SHA-256. Reused bytes are not presented as newly captured images. The native
mobile screenshot is explicitly distinguished from the web scanner controls.
Changed reviewed source assets fail help generation until reviewed again.

A supplementary historical report-capture helper no longer matched the current
demo seed dependencies; its attempts rolled back. The canonical demo seed then
succeeded in the owned local database. A new occasion-administration deep link
failed to resolve permissions in this fixture, so no new order-detail screenshot
or order-edit E2E success is claimed. The report image retains its original
successful capture provenance; order instructions were checked against current
source. The full purchase/payment/scanner-admission journeys were not rerun.

The owned browser, Flutter server, Edge process and disposable Supabase project
were closed after capture. Local private logs/SQL are not publication artifacts.

## Validation and previews

The help-renderer test requires all eight core operation topics and all six
categories. Both languages must render their actual screenshot figures and
resolve every local guide/asset. The existing CSP and offline-cache checks remain
applicable. Browser layout receipts are under `.private/help-preview/`.

Run `node automation/release/preview_help.mjs` (Czech) and append `--en` for the
English preview. Both output static file URLs, with embedded styles/fonts/images,
and need no server. The preview is separate from production publication.
