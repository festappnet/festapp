# Wix submission kit - vstupenky.online

Preparation version 0.1.0; **app/widget registered and Wix Editor installation
verified, including a published synthetic checkout with adapted test transport.
Other editor/payment qualification and commercial approval remain pending; not
submitted or publicly released in the App Market**.

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

1. Owner access and assigned app/widget identities are recorded in
   [the account receipt](evidence/account-20261025.json) and registration receipt.
   Keep the public listing identity consistent with the assigned application.
2. Approved billing model, service-fee-only revenue base and external ticket
   checkout permission, with actual reporting implemented if required.
   Confirm zero fixed publisher upfront/recurring fees with actual terms evidence.
3. Dedicated free HTTPS asset hosting is live with verified CORS, content types,
   caching and source hashes: [hosting receipt](evidence/hosting-20261025.json).
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

Twelve Node tests cover canonical URL validation, no live checkout in editor or
preview, rejected/missing SDK context, detached asynchronous completion, instance
isolation, no checkout reload on presentation changes, settings persistence/read
back, the actual bundled SDK entry and its Site host initialization, the
zero-fixed-fee constraint, sealed package contents and the incomplete
release gate. `pnpm run build` successfully bundles the pinned official Wix SDK
modules; `pnpm run package` verifies their manifest and excludes private inputs.
These checks do not prove Wix editor/runtime
integration or grant commercial approval.

The default `pnpm run release:check` is expected to fail until genuine missing
inputs and independent real-site receipts are supplied. No marketplace submission has been
attempted. One custom-billing approval request was submitted through the official
developer support intake on 2026-10-25; see the support-history receipt.

## Current portal state

The app icon, company profile, category and keywords are saved. The required
phone is `+420 792 759 379`, taken from `https://festapp.net/` at the owner's
instruction. It is prepared, not entered: Contact Info and Security & Privacy
fail to load their Wix CDN modules (HTTP403, independently reproduced). See
[portal evidence](evidence/portal-20261025.json). Do not create a duplicate support
case; the existing billing request is already submitted.

The remaining native portal blockers are contact info, gallery images and the
security/privacy questionnaire. Final gallery images are held until the shared
helper contrast fix is deployed and verified. Registration/profile saves do not
constitute Marketplace submission or commercial approval.
