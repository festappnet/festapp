# Wix submission kit - vstupenky.online

Latest 2026-10-28: Erel explicitly confirmed the service-fee-only reporting
basis, exclusion of organizer ticket proceeds, retained external checkout and
zero separate fixed publisher fees. The account email `info@festapp.net` is now
confirmed by Wix's verification page. See
[commercial clarification](evidence/commercial-clarification-20261028.json).
The earlier request for clarification of the revenue base is resolved; addendum
execution, actual external-billing activation and the production reporting flow
remain outstanding. Historical uncertainty below is superseded by this receipt.

Update 2026-10-28: Contact Info and Security & Privacy now load. Contacts were
saved and verified after reload; the app profile was updated and reads
Up-to-date. The owner then confirmed the company privacy answers. The complete
security/privacy declaration was saved and verified after reload, accurately
retaining No for the blanket full-encryption question. The native checklist
fell from four to zero blockers after the validated unlisted minor version 1.1
was released. See [the release receipt](evidence/minor-release-20261028.json).
See [current portal evidence](evidence/portal-20261028.json).
Later pricing investigation resolved the earlier Free readback by adding the
missing Custom plan: the saved draft now reads DYNAMIC after reload, with a
percentage-based ticketing-service description and no independent app
subscription. See [pricing evidence](evidence/pricing-20261028.json). External
billing activation remains unconfirmed (`isExternalBilling: false`).
The addendum is unsigned
and live billing event delivery is not implemented. Local CSV/API preparation
now uses one service-fee projection and the same commercial approval predicate
as submission; see [reporting](reporting/README.md). This does not replace
authenticated attribution, authoritative service-fee settlement or API dispatch.
The actual addendum was reviewed: its transaction-revenue clause does not
expressly exclude organizer proceeds, so a correction is needed before signing.
See [addendum findings](evidence/addendum-review-20261028.json).
The Partner Agreement is unchecked and
App Market submission remains disabled. Zero native checklist blockers does not
supersede these commercial gates. The historical portal/CDN failures
described below are superseded.

Preparation version 0.1.0; **app/widget registered and installation verified in
Wix Editor, Wix Studio and Harmony. Published synthetic checkout observations use
adapted test transport. The full payment/lifecycle matrix and commercial approval remain pending; not
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
- Wix guide: `https://festapp-wix.pages.dev/help`.
- General help: `https://vstupenky.online/napoveda/vlozeni-na-web/`.
- Privacy: `https://vstupenky.online/privacy/`.
- Terms: `https://vstupenky.online/terms/`.
- Support: `https://vstupenky.online/support/`.
- Framework: self-managed Site Widget (Custom Element) + settings panel.
- Requested additional data permissions: none for the current public form wrapper.
  Native installation still displays baseline access to site/business details and
  the owner login email; do not claim that Wix grants no permissions. If
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
case; the existing billing request is case **3000345850**, acknowledged but not approved.

The remaining native portal blockers are Contact Info and Security & Privacy.
Two unedited 1200x900 published-Studio gallery screenshots are saved and verified
after reload; see [gallery evidence](evidence/gallery-20261025.json).
The live helper contrast fix is verified on 0.20.402+903. Registration/profile saves do not
constitute Marketplace submission or commercial approval.

The documented Harmony development-site flow was rechecked: this owner/app
selector still offers Editor and Studio only. This is a portal limitation, not
a claim of global incompatibility. An ordinary free Harmony site now passed
installation, saved settings, Editor/Preview isolation and published 320 px summary
with QA transport, using the unlisted 1.0 owner-site install flow. See
[Harmony qualification](evidence/harmony-qualification-20261025.json).
The owner authorized a [technical follow-up](SUPPORT-FOLLOWUP.md) about only
the two CDN403 pages. One reply attempt in the existing case thread was SMTP
rejected, so it was not delivered. Wait for the actual Expert reply channel;
the native case detail is read-only. Do not open a duplicate request.

## Additional qualification, 25 October

[Harmony checkout evidence](evidence/final-checkout-qualification-20261025.json) now
covers real seat selection/release, zoom/fit, Escape/back/focus, native blocked
storage, lost-response retry without duplicate orders, and bank QR decoding
against SQL payment details. These use an adapted disposable transport; no real
payment or external email was sent. Native Safari and production CORS remain
unqualified. Provider redirects apply only if such a provider is offered.

[Editor installation A/B](evidence/editor-install-ab-20261025.json) retained the
native warning with both released manual setup and draft homepage insertion.
Manual configuration remains usable; the draft was restored and no version 1.1 released.
The technical follow-up email was SMTP rejected. The existing Wix case is Open
but its portal detail is read-only; no duplicate intake was submitted.
