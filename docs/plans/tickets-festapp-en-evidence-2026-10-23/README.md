# English ticketing implementation evidence

Worktree: `/Users/miakh/source/festapp-worktrees/tickets-en-20261023`, branch `feat/festappticketsglobal`, upstream base `d97835e798e48f17047de4b438a2db6b9e0f8a9c`. Changes are deliberately uncommitted. The original working tree was not replaced, reset or stashed.

Current naming: deployment branch `prod/festappticketsglobal`, profile `festappticketsglobal`, public brand Festapp Tickets. The latest instruction chooses a separate organization. Organization **25 - Festapp Tickets Global** now exists on the canonical backend for `tickets.festapp.net`, with English locale and Stripe defaults. The sandbox acceptance below uses synthetic organization 900001 and does not establish deployed production acceptance.

## Later shared-core and original-video clarification

Global now permits only profile configuration and named brand/icon assets as
branch-owned sources. Main owns all code, translations, capture scenarios and
media; drift tests reject a Global-only capture implementation.

The current Czech page was checked in an isolated headless browser. All eight
rendered chapters and all 32 video/poster hashes match the frozen production
reference in `automation/landing_capture/scenarios/reference-live.json`.
The shared [storyboard](../../../automation/landing_capture/scenarios/README.md)
now defines original narrative, numeric fixture data, cameras, gestures and
reviewed-pair acceptance. Row/form have shared executable recipes; the remaining
historical compositions still need consolidation before automated retakes.

The previously accepted EN media evidence below proves real English footage,
playback and decode, not original-scenario identity. The new
[scenario audit](media-scenario-audit.json) deliberately leaves paired acceptance
unproven. Existing video files were preserved, not relabeled as matching. The user subsequently deferred exact parity and allowed separate English scenarios; paired receipts are optional future reproduction evidence, not a current release gate.

## Implemented contract

- One landing HTML/CSS renderer, marketing entry, wizard, form/editor, payment stack and mail queue. Locale/profile/content select English. The current main configuration is restored to Czech.
- Explicit landing flag and English tenant policy/fixture. Organization 900001 and its `.invalid` origins are synthetic test values, never production provisioning inputs.
- One organization/source predicate uses existing `external_sync_maps`. It covers catalog RPCs and organization-aware SEO; Worker sitemap/catalog fail closed and do not reuse a global external feed or an organization-1 fallback. English references are empty. `CATALOG_SOURCE_POLICY=explicit` activates the strict policy for Global; tenants without the opt-in retain their existing external-catalog behavior.
- Trusted organization defaults select Stripe without implicitly enabling bank payments. Closed drafts can await Connect; paid publication and checkout remain server-gated. Existing bank configuration remains the compatibility default outside this profile. Cross-unit copies cannot retain a foreign Stripe recipient.
- The bounded wizard interaction question was delegated as requested to gpt-6-astra at medium effort. Its accepted result reuses `PaymentMethodCards`, keeps draft payment choice independent from Connect status, and renders bank fields only after an explicit bank/both choice.
- Checkout snapshots trusted locale; legacy attempts keep `auto` and their original provider body. New English templates are insert-only and preserve overrides/prepared or historical messages. PDF rendering uses trusted locale, exact card amounts and event civil time. Account deletion/legal/support rendering shares the original templates.
- End-to-end testing exposed and fixed missing service-role reads for seating enrichment and missing authenticated execution for the existing checked scanner-code RPC. No anonymous geometry or scanner-code mutation access was added.

## Acceptance

[sandbox-acceptance.json](sandbox-acceptance.json) records the synthetic IDs and effects. The actual wizard created event 20. A real existing test-mode Stripe merchant accepted one CZK 350.00 Checkout payment; canonical reconciliation persisted `paid`. No live charge/refund or account creation occurred. CZK is an explicit example, not the future pilot currency.

The canonical durable mail worker accepted confirmation and ticket messages through a local file transport. The final ticket resend uses the corrected English date format. PDF assertions check the English title, `Nov 22-25, 2026`, `Price: CZK350.00` and the actual admission symbol. This proves rendering/queue behavior, not SES delivery.

The purchased ticket passed manual online admission. An authorized canonical admin reset made the same local ticket unused for a separate camera rehearsal. Chrome then decoded the QR rendered from that actual PDF through its fake-video device and performed the real online admission operation. The final ticket is `used`; the saved admin note is `Ready for doors`. Neither the decoder nor RPC/provider results were mocked.

## Media and public page

The source manifest inventories 11 clips. The original six rendered sections and hero use eight: `layout-build`, `layout-refine`, `layout-grid`, `form-build`, `ticket-design`, `seat-select`, `check-in`, `orders-overview`. Those eight were retaken in actual English UI with English examples. The unused `layout-style`, `form-style`, `payment-qr` entries remain outside both pages' rendered requirements; they are not substituted for required clips.

All 16 desktop/mobile exports were fully decoded and played from beginning to end in isolated headless Chrome. Seeking also passed. Authoring mobile presentations adapt the same desktop take; the customer/scanner takes come from actual 430x900 UI. English ticket stills use the same production preset/data/PDF renderer. Hall stills use actual English editor views; the hero shows the authored English hall, not Czech reference artwork.

- [Decode, dimensions, duration and asset hashes](media-decode.json)
- [All 16 full browser playbacks](media-playback.json)
- [Source artifacts, original timing and capture IDs](media-provenance.json)
- [Built landing: desktop/mobile source choice, English controls, missing-file fallback and mobile overflow](landing-browser.json)

Normal English generation rejects pending recordings and missing English assets. The shared built landing was also opened directly from disk using its actual Vite marketing bundle. Public demo playback works without a preview server. Its account backend is deliberately the `.invalid` fixture; the authenticated organizer/customer journey was verified separately against the disposable backend.

Raw masters, build artifacts, PDFs, fixture secrets and the protected DB backup remain outside Git under `/Users/miakh/Downloads/festapp-video-en-20261023` and `/Users/miakh/.cache/festapp-wizard-en-20261023`. Local review: self-contained `review.html` with embedded videos for all exports, `landing/index.html` for the built English public page. Earlier form/ticket takes retain their exact compiled artifact hash; the final Flutter source archive identifies the later authoring build. No committed source revision is invented for the uncommitted implementation.

## Verification

- Forward migration matches its canonical SQL sources and was applied transactionally to the fresh canonical local backend, then replayed successfully as an upgrade/idempotence check.
- SQL: eight targeted catalog/default/payment/setup/admission files plus the locale/ACL regression file passed (9 files). Tests roll back their fixtures.
- JavaScript: 66 form/login/router/payment tests plus 5 SEO/account tests passed. Automation: 35 organizer/SEO/PWA tests passed.
- Missing setup labels in the existing DE/PL/SK/UK catalogs receive English fallback text rather than raw translation keys; existing translations are preserved.
- Tenant matrix: all 12 profiles were rendered twice with identical generated hashes, including explicit CS/EN landing assertions and a third-tenant isolation check. Legal configuration checks passed. The main-owned branch drift checker also exercises the new English profile in its synthetic repository.
- Deno: 29 Stripe provider/payment tests and the final 11 ticket-data/date tests passed. Targeted Edge/capture script type checks passed.
- Targeted Dart analysis had no errors or warnings; existing style information remains. The targeted widget suite's gallery fixture now loads the real localization environment; its corrected gallery tests passed alongside the retained passing setup tests. The final English Flutter release build passed.
- The later one-line review display adjustment localizes Unlimited and keeps card prices at two decimals; Dart parsing/format validation passed. A second Flutter task was not launched while another session owned the workstation slot and its queued release build.
- Final diff whitespace checks passed. No production release/full release gate is claimed.

## Operational gates

[The concrete production manifest](../../../automation/release/tenants/festappticketsglobal.manifest.json) records real organization 25; unit/pilot/currency values remain null. Host ownership, operator/legal/contact/sender approval, existing source-map inventory, pilot merchant and online-only admission/reservation/dispute acceptance remain external gates.

[Organization provisioning](organization-provisioning.json) records the authorized creation of organization 25 and disabled sandbox/live Stripe policies. Read-only verification found zero occasions, units, members and external-source maps; Czech organization 3 retained its Czech locale. No schema migration, commit, push, tenant branch publication, DNS, deploy or live activation was performed. Production execution must use the separately authorized single tenant and local direct-deploy workflow. Local new-payment policy is switched back off and task-owned runtime processes/browser sessions are stopped after evidence capture; data is retained for review.
