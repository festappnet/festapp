# Wix setup and qualification

Verified against official documentation on 2026-10-24/25. App/extension
registration, dedicated free static hosting and the first free development site
are now recorded in [registration evidence](evidence/registration-20261025.json).
The steps below remain the repeatable setup procedure; the qualification matrix
must separately record actual results rather than infer them from registration.

## Supported route

Use a self-managed **Site Widget (Custom Element)**. Wix lists self-managed site
extensions as supported in Harmony, Wix Editor and Wix Studio. Legacy iframe
widgets have partial Harmony support; Blocks widgets are not supported there.
Do not publish a claim of verified compatibility until the matrix below passes.

1. Select the authorized Wix owner workspace, create a self-managed app, and
   record the assigned app ID. Account/contract acceptance is an operator action.
   Check for an existing account before creating one. Do not buy a publisher
   subscription, pay a listing charge or start a trial that converts to a paid
   plan. Development sites are free; record actual zero-fixed-fee terms before
   commercial submission.
2. Publish the built assets at an approved HTTPS location. Verify:
   - deploy the verified archive's contents, including dependency legal notices;
     `_headers` targets a dedicated Cloudflare Pages/static-assets root. When
     hosting under a path prefix, scope the rules to that prefix explicitly;
   - widget and settings JS return JavaScript, not the Flutter/marketing fallback;
   - settings HTML returns HTML, with its sibling CSS and JS available;
   - widget JS allows public CORS (`Access-Control-Allow-Origin: *`) because the
     editor sandbox can have origin `null`; these are public assets, not an
     authenticated API;
   - script URLs revalidate after a release; no API key or credentials appear in
     HTML, widget attributes, URLs, source maps or logs;
   - CSP allows the built scripts, the live service helper and checkout iframe.
3. In the app dashboard open Extensions, create **Site Widget (Custom Element)**:
   - Widget name: `vstupenky.online` (Wix limits this field to 30 characters).
   - Tag name: `vstupenky-online-form`.
   - Script URL: the actual published HTTPS URL of built `widget.js`.
   - Settings action URL: the actual published HTTPS URL of `settings.html`.
     On our Pages host use `https://festapp-wix.pages.dev/settings`.
   - Enable **frontend modules from the Wix JavaScript SDK**. This adds the
     native Site host dependency required by the self-managed SDK bootstrap.
   - Width: full-width capable, resizable, initially 100% of the containing area.
   - Height: **automatically adjusted to custom-element content**, not a fixed
     outer Wix iframe. Initial fallback content height is 800 px.
   - Placement: a user-chosen page; do not insert a live sales form on every page.
   - Non-essential widget; provide a thumbnail so it is available in Add Elements.
4. Save and record the generated widget extension ID. Define these public
   string attributes/properties where the dashboard requests them:

   | Property | Initial value | Meaning |
   | --- | --- | --- |
   | `form-url` | empty | Canonical public service form URL |
   | `form-title` | `Prodej vstupenek - vstupenky.online` | Accessible iframe title |
   | `inherit-style` | `true` | Opt into host typography/colors |

   Wix widget properties bind to custom-element attributes. Use the settings
   panel for subsequent changes; no credentials or hidden order state are stored.
5. Use **Test App -> Test on dev site** to choose/create a free Premium
   development site for each supported editor. Do not install into an unrelated
   user's site or use production ticket inventory as a fixture.
6. Add the widget, open Settings, save an authorized synthetic public form URL,
   close/reopen the panel and verify persistence. Publish the development site
   to run actual checkout qualification. Editor/Preview intentionally show the
   placeholder to avoid opaque-origin/storage/payment behavior being mistaken
   for the published visitor experience.
7. Store the actual IDs and receipt references in the ignored release inputs.
   Do not use the example's nulls or invented UUIDs as a registered Wix identity.

## Required real-site matrix

The first two Wix Editor rows passed on the registered development site; see
[evidence/editor-20261025.json](evidence/editor-20261025.json). Other rows remain
**NOT RUN**. This does not establish published-site compatibility.
The parent checkout must use the same disposable backend and synthetic stock as
existing integration tests; never place real orders or reserve production seats.

| Area | Harmony | Wix Editor | Wix Studio |
| --- | --- | --- | --- |
| Install, add widget, settings persist after editor reload | not run | pass | not run |
| Editor/Preview have no checkout iframe or helper loaded | not run | pass | not run |
| Published form, auto height, helper/version handshake | not run | not run | not run |
| 320 px mobile, keyboard/focus, light/dark host typography | not run | not run | not run |
| Two widgets, changing one URL, deleting/re-adding one widget | not run | not run | not run |
| Validation, seat map, Escape/back, close restores scroll | not run | not run | not run |
| Summary reveals submit; submission shows receipt top | not run | not run | not run |
| Authorized synthetic payment redirect/return and browser storage | not run | not run | not run |
| Uninstall/reinstall, latest helper, CSP/CORS and helper outage | not run | not run | not run |

Payment-return qualification must cover supported browsers and mobile Safari;
third-party iframe storage and payment-provider redirects cannot be established
by DOM unit tests. Preserve duplicate-order/idempotency checks from the canonical
checkout. Do not collect browser payment details into the Wix settings panel.

## Official sources

- [Self-managed custom-element widgets](https://dev.wix.com/docs/build-apps/develop-your-app/develop-a-self-managed-app/supported-extensions/site-extensions/site-widgets-and-plugins/add-self-managed-site-widget-extensions-with-custom-elements)
- [Settings panel and serial property writes](https://dev.wix.com/docs/build-apps/develop-your-app/extensions/site-extensions/create-a-settings-panel-for-a-site-widget-or-plugin-wix-cli-and-self-hosting)
- [Harmony app compatibility](https://dev.wix.com/docs/build-apps/get-started/overview/about-wix-harmony-and-apps)
- [Editor sandboxing and viewMode](https://dev.wix.com/docs/build-apps/develop-your-app/extensions/site-extensions/handle-sandboxing-in-the-editor)
- [CLI create app and its remote registration effects](https://dev.wix.com/docs/wix-cli/command-reference/project-creation/create-app)
