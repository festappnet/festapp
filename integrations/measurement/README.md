# Host measurement preset

Import `festapp-host-gtm.json` into the organizer website's **web GTM container**.
The website owns consent, its Google tag and attribution. The preset consumes
Festapp's approved first-party dataLayer events; it neither scrapes checkout nor
copies cookies or promises a shared session with an isolated Unit runtime.

## Import and configure

1. Back up the website container and create a separate workspace. Import using
   **Merge** and **Rename conflicting tags, triggers and variables**. Review the
   conflict preview, including the gallery template. Do not overwrite published
   configuration. All 18 imported tags remain paused in the **Festapp** folder.
2. Fill the five destination constants once: **GA4 ID - Festapp**, **GAds ID -
   Festapp**, the two **GAds label - Festapp** constants, and **FB Pixel ID -
   Festapp**. Use the website's intended measurement destinations. Placeholder
   values are not a working destination. Retire the previous four-tag Festapp
   preset (two grouped GA4 tags, Ads purchase and Meta Custom HTML) before
   enabling this version, and review any other overlapping event/conversion tags.
3. Keep the website's existing Google tag and Conversion Linker. This preset
   adds no Google initialization or native website page-view tag. Embedded
   `form_page_view` stays distinct from the website's `page_view`.
4. Review the existing Meta installation before enabling our Meta tags. The
   official template loads/reuses the SDK and initializes its configured pixel;
   Advanced Matching can reinitialize that same pixel with customer data. Use
   one coherent site pixel setup and the same configured ID. Preserve the site's
   intended baseline PageView and prove that conversions/PageViews do not double.
   Do not modify SDK-private globals to hide duplicate initialization.

## Consent and contact setup

This preset selects **advanced Google Consent Mode**: native Google tags have
**No additional consent required**, letting their built-in checks adapt storage,
contact use and cookieless measurement. The website CMP must set Consent Mode v2
states before tags and update them from the saved visitor choice. Denied states
are not changed to grants by the preset. `ad_personalization` governs personalized
advertising, not an extra firing condition for the conversion tags. A merchant
choosing basic Consent Mode needs a separately reviewed website setup.

GA4 `purchase` and `generate_lead` and both Ads conversion tags use the native
**User-Provided Data - Festapp - manual** variable. It reads only the existing
canonical email/phone from those embedded conversion events. Configure GA4's
user-provided-data feature, required Ads linking/data capabilities and relevant
Google Ads enhanced-conversion eligibility/policies in the merchant accounts
before enabling those destinations. The preset accepts no policies, enables no
account feature and performs no automatic DOM contact detection. Google calls
GA4 user-provided data an open beta; review its current account prerequisites.
Never map email/phone as ordinary custom dimensions, ordinary event fields or URLs.

Meta tags require **ad_storage** as an additional GTM check. The merchant CMP
must map that gate to consent covering Meta tracking and, for Purchase/Lead,
customer matching. The name of a Google consent type alone is not proof of that
coverage. The site CMP owns SDK consent withdrawal too, including queued work
while the SDK loads; confirm its supported Meta consent/revocation integration.

Only Meta Purchase/Lead tags supply Advanced Matching fields. Google retains
canonical E.164 phone numbers; the Meta adapter removes only the leading `+`
from an already valid E.164 value. It never guesses a country or rewrites source
contact data. Invalid/missing contacts are omitted. Public Meta properties and
`contents` use only currency/value and item ID/quantity/price.

Meta matching state can remain in the SDK after a conversion. Clearing Festapp's
dataLayer contact state does not erase dataLayer history or SDK matching state;
do not promise that subsequent SDK events can never be associated with that
identity. Review this behavior and notice coverage with the website's pixel setup.

Every Meta tag explicitly sets **Meta-enabled Conversions API** to **false**.
No access token or server destination is configured. This opt-out does not mean
that no external library can load: the pinned official template can load its
client parameter builder from jsDelivr/unpkg behind a Meta SDK gate. Its gallery
permissions/dependencies are retained and must be included in the site's review.
The preset does not supply Meta `eventID`; canonical Festapp event and order IDs
remain available for a separately designed future server integration.

## Event meanings

- Ten fixed-name GA4 tags share scoped event triggers; ecommerce is enabled only
  for view/cart/checkout/payment/purchase events. Non-ecommerce events cannot
  inherit the website's earlier ecommerce payload.
- Ads **Nákup vstupenek** records an accepted priced order. It is not proof of
  bank/card settlement. Order identity supplies the conversion transaction ID.
- Ads **Registrace** uses a dedicated `generate_lead` trigger restricted to
  `lead_source = free_registration`. Waitlist and sale-opening interest stay
  generic leads for GA4/Meta and do not count as completed registrations. The
  eleven triggers therefore include ten shared events plus this subtype filter.
- Meta uses ViewContent, AddToCart, InitiateCheckout, AddPaymentInfo, Purchase and
  Lead. It sends no duplicate website PageView. Lead value remains zero.
- VAT/net-revenue policy and estimated lead values are separate domain changes.
  The preset preserves the current charged item amounts and never invents a
  VAT rate, subtracts assumed taxes or estimates a lead's commercial value.

## Preview and publish

In the task-owned test workspace, verify denied/granted/withdrawn consent, delayed
SDK loading, native website events and two interleaved forms. Check purchase and
all three lead sources, value/currency/transaction identity, contact scoping,
existing pixel coexistence and no stale data after a conversion. Google tags may
run in denied mode; Meta must not run before its mapped consent is granted.

Unpause only reviewed destination tags, preview again and use the merchant's
normal publishing process. A descriptive version name is **Added Festapp form
tracking for GA4, Google Ads and Meta**. Import acceptance does not establish
account eligibility, delivery, attribution or campaign reporting. Confirm these
in the approved destination accounts before treating the installation as live.

## Canonical sources

`build_gtm_preset.mjs` generates the sole `festapp-host-gtm.json`; run it with
`node integrations/measurement/build_gtm_preset.mjs` and use `--check` for parity.
The help download copies those exact bytes. The pinned official Meta source,
license and provenance are in `vendor/meta-pixel/`; the gallery-linked container
record is `meta-pixel-template.json`. It contains no merchant account identity.
See `VALIDATION.md` for evidence tied to the current artifact, not an earlier file.

References: [GTM import/export](https://support.google.com/tagmanager/answer/6106997?hl=en),
[consent checks](https://support.google.com/tagmanager/answer/10718549?hl=en-GB),
[GA4 native user-provided data](https://support.google.com/analytics/answer/14179229?hl=en),
[GA4 prerequisites](https://support.google.com/analytics/answer/14077171?hl=en),
[official Meta template](https://github.com/meta/GoogleTagManager-WebTemplate-For-FacebookPixel).
