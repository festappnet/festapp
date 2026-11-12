# Cookiebot linked-form validation - 2026-11-12

## Initial public-site compatibility check

The generated `web_client/public/embed.js` was exercised with the real Cookiebot SDK and opt-in dialog on Cookiebot's public site in an isolated, muted, light-mode headless Chromium session. A temporary HTTPS localhost form used the actual `FormMeasurementSession` and Klaro integration with an in-memory transport; measurement endpoints were blocked and no order was placed. The generated helper's exact bytes were evaluated with `document.currentScript` temporarily bound to the local script element because Chromium blocked loading that script across the local-network boundary. The CMP, its saved choices and cross-origin opener and `postMessage` channel were real.

- In one continuous form visit, real Cookiebot choices changed from deny to allow all, to analytics only, and back to deny. The open form received each choice on the same lease, with no local notice or form cookie. The transport briefly received a fail-closed denial during one change.
- Closing the host revoked the open form's lease and restored its local notice. Host reload also revoked an earlier linked visit.
- Against the real loaded SDK, separate injected invalid origin, CBID and future cutoff cases returned no choice; advancing the clock beyond maximum age did likewise.
- Real renewal exposed Cookiebot's transient `inlineoptin` response mode. After adding that observed opt-in mode, the continuous live sequence above passed. Cookie/API stamp mismatch still denies without a grace period.
- A simulated `__tcfapi` against a real accepted Cookiebot choice suppressed marketing. This was not a live TCF CMP test; TCF coverage in the automated fixtures is simulated.

This is Chromium evidence only, not a live test in Firefox or WebKit. The temporary browser session and local server were closed after the test.

The final browser helper and source retain immediate denial on missing or
mismatched storage. Existing linked visits are checked every second; a
non-atomic CMP write may still safely restore the local notice rather than
continue from cached acceptance. The observed normal renewal sequence with
`inlineoptin` preserved its lease.


## Own WordPress site with genuine TCF

A disposable WordPress 7.1.3 site and the official Cookiebot plugin were installed
locally and published through a free temporary HTTPS tunnel. A dedicated Cookiebot
trial account and domain group were registered, with no card or payment method.
The plugin was connected through its actual WordPress admin UI. Enabling its
IAB TCF integration required selecting a TCF vendor and saving the settings.

The fresh visitor loaded the genuine SDK with `data-framework=TCFv2.2`.
`__tcfapi('ping', ...)` returned success, `cmpLoaded:true`, `cmpStatus:loaded`
and `gdprApplies:true` (TCF policy version 5). This was a real TCF CMP, rather
than the simulated API used in the initial check.

The Czech WordPress page loaded the exact generated helper normally through
its HTTPS script URL and opened a separate HTTPS form through its real link.
No helper evaluation, mocked CMP or fabricated consent state was used.
The form used the actual FormMeasurementSession and Klaro with an in-memory
transport, a test policy and no production backend or order. Measurement
endpoints were blocked.

- Real **Allow all** left both statistics and marketing true in Cookiebot. The
  form and transport received analytics true and marketing false, without a
  local notice or consent cookie.
- Real **Deny** from the WordPress renewal dialog updated the same open form
  lease to analytics false and marketing false, again without a local notice
  or consent cookie.

All browser evidence above is from isolated, muted, light-mode Chromium. Live
Firefox/WebKit remain outside this validation. Test passwords were retained and
verified in encrypted macOS login Keychain; iCloud synchronization is not claimed.
TCF was exercised during Cookiebot's free trial, not claimed as a permanently
free Cookiebot feature.

## Local regression checks

The implementation and generated assets at `ba67dc04f` were frozen for the
canonical local CI mirror. Six lanes passed in the combined run; the web-startup
contract encountered a race with the runtime-checkpoint fixture temporarily
creating/removing a migration probe, leaving its dependent Wix lane unexecuted.
Both lanes then passed in isolation on the same unchanged source. The resulting
coverage includes all eight canonical jobs, with 528 measurement contract tests
and the normal browser measurement gates in the web-startup lane.

Three targeted Flutter brand-loading widget tests passed, including delayed
wordmark geometry, full-logo pulsing, reduced motion and inactive-route cleanup.
Desktop/mobile visual checks showed only the symbol at 1.3 seconds, outlined
Festapp Tickets at 2.4 seconds and the complete wordmark at 4 seconds. Reduced
motion showed the complete static identity. No Flutter task remained running.
