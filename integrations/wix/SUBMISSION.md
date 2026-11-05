# Wix submission kit - vstupenky.online

Current authoritative state: [execution result](../../docs/plans/wix-partner-billing-RESULT-2026-10-28.md)
and [continuation receipt](evidence/continuation-20261101.json). Native external
billing and BI ingestion are confirmed; normal financial dispatch remains disabled
until actual settlement/acquisition evidence exists. The owner-signed addendum
is complete. Version 2.2 is submitted and persistently **IN REVIEW** after cold portal readback;
see [submission evidence](evidence/native-submission-20261101.json).
Approval and a live public catalogue listing are not yet confirmed.

The visible-time authentication fix passes the real native proof probe in all
three owned QA environments. The original 12-second wall-clock timeout was not
proof of a vendor failure: token delivery could occur later during background
hydration. Keep current proof, historical full-checkout/lifecycle tests and store
verification distinct; do not invent missing purchases or reviewer credentials.

The native profile/configuration is 2.2, with canonical icon saved and CDN bytes
verified. Organizer help is public at https://wix-guide.festapp-wix.pages.dev/help.
Source publication and exact stable asset deployment are complete; see
[deployment evidence](../../docs/operations/releases/wix-runtime-20261101.json)
and [live authentication evidence](evidence/live-native-auth-20261101.json).
Reviewer/checkout qualification and the readiness gate passed before submission;
see [the current demo receipt](evidence/reviewer-demo-20261101.json) and
[readiness receipt](evidence/submission-readiness-20261101.json). Zero native
blockers alone does not establish those effects.

## Draft listing identity

- App/service name: `vstupenky.online` (Czech market).
- Public developer name: `Festapp`. Keep the verified legal identity separate
  from the public developer brand.
- App language: Czech (`cs`). The listing copy below is Czech; saving this
  document does not update the native Wix profile or its published listing.
- App icon: [canonical PNG](media/icon-1000.png), exported from
  [the approved square logo](../../assets/brand/vstupenky-online/vstupenky-online-square.svg).
- Working tagline: `Prodávejte vstupenky na akce přímo na svém webu.`
- Working summary: `Přidejte na svůj web prodejní formulář vstupenky.online.
  Vstupenky, místa k sezení a objednávky spravujte v propojené službě.`
- Overview features:
  - `Vložte uložený veřejný prodejní formulář pomocí jeho adresy ze vstupenky.online.`
  - `Akce, kapacity a objednávky spravujte ve službě vstupenky.online.`
  - `Zvolte název formuláře a přizpůsobte jeho písmo svému webu.`
  - `Stejný formulář otevřete také přímo na vstupenky.online.`
- Overview description: `Přidejte na svůj web existující prodejní formulář
  vstupenky.online. V nastavení vložte jeho veřejnou adresu, zvolte název a
  případně převezměte písmo svého webu. Nastavení akce, kapacity vstupenek,
  nákup, objednávky a doručení vstupenek zajišťuje vstupenky.online. Pro použití
  potřebujete v této službě připravený veřejný formulář. Prodej se řídí
  podmínkami služby a vztahují se na něj příslušné servisní poplatky. Editor
  zobrazuje zástupný náhled, který při úpravách brání nechtěným objednávkám.`
- Installation model: free widget installation; connected service charges for
  ticket sales at the organizer-agreed rate. Native Custom pricing is approved.
- Canonical public support copy: `info@vstupenky.online` (native operational contacts may retain the existing owner mailbox).
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

## Historical local validation - initial preparation

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

## Historical portal state - 25 October

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

## Historical additional qualification - 25 October

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
