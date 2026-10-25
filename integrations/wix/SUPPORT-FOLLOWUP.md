# Wix developer portal follow-up - draft, not sent

This is a technical addendum for owner review, not authorization to contact
support. Do not open a duplicate case or repeat the billing request. The existing
request, **Custom billing approval - vstupenky.online**, was confirmed once on
2026-10-25 at 16:10 UTC; Wix stated an email response within 72 hours. No case ID
or reply thread has been observed. Attach this only to that established
conversation if the owner authorizes the follow-up; otherwise keep it a draft.
The original zero-fixed-fee and unapproved-billing constraints remain in force.

## Proposed message

Hello Wix developer support,

This is a technical addendum to our existing request, “Custom billing approval -
vstupenky.online”, submitted on 25 October. Please keep the existing billing
request open; this message does not replace it or accept any billing terms.

App ID: 9c099206-ce3d-43de-bd9d-deb96bb4f51e
Owner: info@festapp.net

We have registered a self-managed custom-element site widget and tested native
installation in Wix Editor and Wix Studio. Three portal issues prevent us from
finishing the remaining preparation:

1. App Profile > Contact Info displays “We couldn't load this page”. The
   Contact Info module returns HTTP 403, also reproduced without the browser:
   https://static.parastorage.com/services/contact-info/1.643.0/module.bundle.min.js
2. Security & Privacy displays the same loading error. Its module returns
   HTTP 403 as well:
   https://static.parastorage.com/services/security-and-privacy/1.394.0/module.bundle.min.js
3. Test App > Test on dev site > Create Dev Site > Choose site editor offers
   only Wix Editor and Wix Studio for this owner. Your testing documentation
   lists Harmony development-site templates, and your compatibility guide lists
   self-managed site extensions as supported. Could you enable the documented
   free Harmony development-site route for this account, or identify the
   supported way to test this draft app there without buying a plan?

Could you restore the two portal pages or provide an official supported route
for completing those fields? We have not submitted the app to the App Market.
No paid publisher plan is requested or authorized.

Thank you.

## Evidence and sources

- Native owner flow was rechecked on 2026-10-25. Creating a new site was canceled
  at the editor-selection step; no third development site was created.
- Existing portal failures: [portal receipt](evidence/portal-20261025.json).
- Harmony comparison: [development-site receipt](evidence/harmony-access-20261025.json).
- [Official development-site testing guide](https://dev.wix.com/docs/build-apps/launch-your-app/app-distribution/test-your-app/test-your-app-on-a-premium-site),
  updated 22 September 2026: Harmony templates and the same Test App flow.
- [Official Harmony compatibility guide](https://dev.wix.com/docs/build-apps/get-started/overview/about-wix-harmony-and-apps),
  updated 22 July 2026: self-managed site extensions are supported.

Do not include cookies, authentication tokens, buyer information or private
backend receipts. The public module URLs and app ID above suffice to describe
the problem. Ordinary site-creation alternatives have not been exhausted;
missing Harmony in this documented flow is an account/portal observation, not a
claim that Harmony is unavailable everywhere.
