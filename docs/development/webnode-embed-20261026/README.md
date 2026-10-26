# Webnode embed qualification - 26 October 2026

The public guide was followed on the existing owned Webnode project after support
activated its Standard trial through 9 November. Editor HTML paste/save, cold
readback and actual publication passed. No paid plan was purchased.

The run found and fixed a real generator defect: cross-origin iframes lacked
`allow="clipboard-write"`, so Chromium denied payment-detail copying. Adding the
attribute dynamically to an already-loaded frame did not qualify the fix. After
saving the corrected code in Webnode, publishing and loading a new document,
the native policy was enabled and the actual amount-copy action resolved with
its “Copied” label. Both generator modes now delegate write only. Existing
snippets require replacement and republication.

| Case | Observed result |
| --- | --- |
| Actual published Webnode and live service | Public form loaded; helper and iframe attributes survived native save/publish. Production SELECT/auth/CORS were relayed unchanged through the guarded allowlist. |
| Automatic height, default and inherited appearance | Passed at 1280 px and 320 px; mobile iframe 300 px, no horizontal overflow. Opt-in inherited Futura/white theme applied. |
| Fixed height without helper | Actual published iframe 800 px; natural content 1122 px and native focus/PageDown reached inner scrollY 322. |
| Fallbacks | Generated standalone link and native Webnode “Koupit vstupenky” button opened the correct canonical form in a new task tab. |
| Seating and summary | Actual pointer release and keyboard select reached local SQL; Escape and summary Close retained synthetic email/name/seat. |
| Bank checkout | Two distinct local fixtures/buyers produced one 150 CZK order each; each had exactly one send-ticket-order POST. The first order’s QR decoded to the same account/amount/currency/variable symbol as SQL. |
| Reload | First accepted order remained single and sold after parent reload; blank form, no automatic resubmit. |
| Clipboard regression | Before: policy false, no copied state. Cold new published candidate: policy true and native copy action succeeded. |
| Native MobileSafari | Real iOS 26.5/iPhone 17 Pro Simulator, 402x874: published form, necessary-cookie dismissal, native swipe and bottom controls passed. Simulator remained inactive/hidden with 0 visible Mac windows. |

[Machine-readable receipt](receipt.json) records source/build identities, SQL
observations, the zero-write production read boundary and image hashes.
[Published mobile view](published-mobile.png), [local summary](local-summary.png),
[local payment QR](local-payment-qr.png), and the
[native Safari screenshot](../../../automation/release/help/media/cs/webnode/03-published-mobile.png)
are unedited captures. The real Webnode host/live client do not make the adapted
local purchase a production checkout or CORS qualification.

The public final Webnode page was restored to the real public Country form with
automatic height, opt-in inherited style, corrected clipboard delegation and a
native fallback button. Test slugs were removed from the published HTML.
No real money transfer, email delivery, external provider or physical iPhone
result is claimed. Safari purchase and every privacy/browser combination remain
outside this receipt. The support trial will expire; this is not a promise of
free HTML embedding on future free-plan projects.

## Repeat without touching production orders

Use task-owned headless Chrome and the committed Wix diagnostic launch guard.
The same production-readonly proxy permits only the public Country SELECT;
never allow holds or order endpoints through that boundary. The independent
checkout transport derives from the committed guarded Wix proxy with the
explicit disposable project/API/container/form replaced by this receipt's
Webnode values. The client HTML snapshot is a current public service document;
no frontend application JavaScript was mocked. Launch fencing remains active
before, during and after the relay.

Bootstrap only a fresh dedicated project using the canonical local bootstrap
and the documented FESTAPP_LOCAL_DB_* overrides. The fixture derives from
`integrations/wix/tests/seat-fixture.sql`, retaining its marker guard and
existing-form early return; use only the two exact Webnode slugs in the receipt.
The second fixture explicitly disables bank fetching. Pause the email queue,
leave its worker URL null and supply no provider credentials. Preserve accepted
orders 166/167 and sold seats; do not reset or replay them. The private task
metadata, authentication and transport scripts are in `.private/webnode/`.
Stop the task Edge process/browser relays and Supabase with backup after use.

Canonical source merge, required CI, independent review and final selected-tenant
help deployment are subsequent publication steps, not implied by these captures.
