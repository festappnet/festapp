# Cookiebot linked-form validation - 2026-11-12

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
