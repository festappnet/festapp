# Wix submission kit - vstupenky.online

Preparation version 0.1.0; **not a publicly released or registered Wix app**.

## Draft listing identity

- App/service name: `vstupenky.online` (Czech market).
- Working tagline: `Sell event tickets directly on your website.`
- Working summary: `Add your vstupenky.online ticket form to a page and manage
  tickets, seating and orders in the connected service.`
- Installation model: free widget installation; connected service charges for
  ticket sales. Final Wix pricing model and billing text require approval.
- Support contact: `info@festapp.net`.
- Service: `https://vstupenky.online/`.
- General help: `https://vstupenky.online/napoveda/vlozeni-na-web/`.
- Privacy: `https://vstupenky.online/privacy/`.
- Terms: `https://vstupenky.online/terms/`.
- Support: `https://vstupenky.online/support/`.
- Framework: self-managed Site Widget (Custom Element) + settings panel.
- Requested data permissions: none for the current public form wrapper. If
  later instance-linked billing needs extra permissions, review them separately.

The site owner saves only a public form URL, accessible title and appearance
preference in Wix. Visitors enter purchase/contact information directly into the
service iframe. Host protocol messages expose bounded presentation/price data,
not order contents, authentication credentials or payment instructions.
Do not describe the service as having no analytics or cookies solely because
this wrapper does not add its own analytics.

## Remaining material before actual review

1. An authorized owner workspace, assigned app ID and widget extension ID.
   Account signup for `info@festapp.net` currently needs human CAPTCHA completion;
   see [the account receipt](evidence/account-20261025.json).
2. Approved billing model, service-fee-only revenue base and external ticket
   checkout permission, with actual reporting implemented if required.
   Confirm zero fixed publisher upfront/recurring fees with actual terms evidence.
3. Approved HTTPS hosting with CORS/cache/CSP and live source hashes.
4. Real installation and published development-site receipts for Harmony,
   Editor and Studio, including authorized synthetic purchases/payment returns.
5. Verified Wix-specific public setup guide and source-grounded screenshots of
   the editor panel, installed widget and published mobile/desktop checkout.
6. Current Wix listing artwork/asset specifications, original brand assets,
   truthful pricing and a maintained synthetic review/demo account. No demo
   account credentials belong in this repository or public assets.
7. Check the current review flow and submit the **assigned app version** in the
   Wix app dashboard after all gates pass. A local `dist/` bundle is not proof
   of a release, installation or marketplace acceptance.

The current [distribution documentation](https://dev.wix.com/docs/build-apps/launch-your-app/app-distribution/about-app-distribution)
distinguishes App Market listing from direct installation. Do not claim that an
unlisted install link is a public catalog listing.

## Validation performed locally

Nine Node tests cover canonical URL validation, no live checkout in editor or
preview, rejected/missing SDK context, detached asynchronous completion, instance
isolation, no checkout reload on presentation changes, settings persistence/read
back, the zero-fixed-fee constraint, sealed package contents and the incomplete
release gate. `pnpm run build` successfully bundles the pinned official Wix SDK
modules; `pnpm run package` verifies their manifest and excludes private inputs.
These checks do not prove Wix editor/runtime
integration or grant commercial approval.

The default `pnpm run release:check` is expected to fail until genuine missing
inputs and independent real-site receipts are supplied. No submission has been
attempted and no support/reviewer message has been sent. Signup verification
requests are distinct from a marketplace submission.
