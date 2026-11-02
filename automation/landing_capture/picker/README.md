# Actual Festapp picker and QR payment capture

The old grid/SVG fixture writer was retired by the canonical blueprint cutover. Use a saved canonical native plan from the disposable demo seed; capture scripts must not restore the retired geometry columns.

Source checkout for this delivery: `venue-seat-picker-public-preview-20261021`. Set `LAYOUT_PACKAGE` to that checkout. Set optional `CAPTURE_PROVENANCE=/absolute/provenance.json` to save source SHA256, counts and coordinate mapping. Prices, occasion and customer details are synthetic local fixture data; the underlying hall geometry is the existing reference. Local occasion6/form7/blueprint3 remain the task fixture, with seat IDs421-602 mapped in original reference order and original labels such as 1A/1B. Extra legacy fixture spots are not rendered and are not deleted.

## Local preparation

1. Follow the `festapp-local-e2e` runbook to restore the existing disposable synthetic backend. This recipe assumes its `Ples pod hvězdami` occasion exists; the SQL refuses a different occasion. Set `LOCAL_CONTAINER` to the owned disposable PostgreSQL container. Never run against production.
3. From `web_client`, use pnpm11.24.0: `FESTAPP_CAPTURE_DEFINES=/absolute/private-defines.json pnpm exec vite --config ../automation/landing_capture/picker/vite.config.mjs`. The private file has `FESTAPP_SUPABASE_URL` and `FESTAPP_SUPABASE_ANON_KEY`; config rejects a non-loopback backend. Default web127.0.0.1:56841, backend56831.
4. Create an empty JSON browser config and task-owned wrapper ALWAYS passing `agent-browser --config "$EMPTY_CONFIG" --headed false --namespace "$UNIQUE_NAMESPACE" --session picker "$@"`. Set `BROWSER_WRAPPER`. Launch about:blank, verify one tab, HeadlessChrome user agent, session daemon and its Chrome child. Read only that child's DevToolsActivePort into `CAPTURE_CDP_PORT`. Never use personal Chrome or Panerelay.
5. Set `CAPTURE_URL=http://127.0.0.1:56841/form/d45ajbtj`, `CAPTURE_OUT` outside Git, and `CAPTURE_OBSERVER` to the installed product-demo-video skill's `scripts/capture-cdp.mjs`.

## Seat selection

Before each rehearsal/take release ONLY the uncommitted synthetic holds:

```sh
docker exec "$LOCAL_CONTAINER" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -qc 'update eshop.spots set secret=null,secret_expiration_time=null where blueprint=3 and occasion=6 and id in(423,424) and order_product_ticket is null;'
python3 automation/landing_capture/picker/capture.py
# Release those holds again before the mobile run:
CAPTURE_MOBILE=1 python3 automation/landing_capture/picker/capture.py
```

The real backend reservation guard remains active. Never clear committed order links for a retake; use a fresh disposable snapshot or choose other available seats consistently. The final mobile selection can continue into the QR workflow below without reloading. Current default seats are423/424 (1C/1D); `CAPTURE_SEAT_IDS` chooses another available pair. Original seats1A/1B belong to the retained unpaid order155 and must not be cleared.

Actual beats: whole hall1.3s, real zoom buttons (desktop2/mobile4 clicks), native pan based on rendered first-seat bounds, select1C, hold1.3s, select1D, hold1.5s, Continue into actual participant form, hold3s. Price is 2x650 = 1300CZK. Desktop1440x900; mobile390x844. Zoom is real product CSS bottom-right, independently of the cart.

## Actual synthetic order and QR receipt

Apply `payment_fixture.sql` only to the same owned disposable container (`docker exec -i "$LOCAL_CONTAINER" psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q < automation/landing_capture/picker/payment_fixture.sql`). Run full local Edge functions, including `send-ticket-order`, from the task backend. No provider secrets are needed. Configure ONLY the synthetic fixture: form7 bank_account1 and deadline259200; bank1 title `Ukázkový účet pořadatele`, creditor_name `Ukázkový pořadatel`, account_number `CZ0000000000000000000000`, account_number_human_readable `0000000000/0000`. This is intentionally impossible test bank data. Do not substitute a real bank account or weaken payment/checkout guards.

After the mobile seat-selection take, stay in the actual form. Through fresh accessibility refs, fill order contact `ukazka@example.invalid`, contact first name Jana and contact surname Nováková; select Kuřecí menu and Souhlasím s podmínkami. Click Pokračovat, review the genuine summary, then Odeslat objednávku. These actions create an actual **local unpaid order**, not a mock success screen. Wait for the success heading and `.result-payment-more`. Do not claim email delivery: the UI says queued, and the recipient domain is non-deliverable. No bank app or payment transfer is opened.

```sh
python3 automation/landing_capture/picker/capture_payment.py
CAPTURE_MOBILE=1 python3 automation/landing_capture/picker/capture_payment.py
```

The receipt must already be open; this runner deliberately never fabricates/reloads receipt state. It records the real closed payment disclosure for1.5s, clicks it, holds the genuine QR+amount for4s, saves screenshot and readback. First delivery's local order155 remained `ordered`, unpaid, amount1300CZK; generated order/variable symbols are actual local values and will differ next time.

Outputs: `seat-select{,-mobile}.{mp4,jpg}` and `payment-qr{,-mobile}.{mp4,jpg}`. Payment poster shows QR+amount and synthetic details. Copy only verified artifacts to `web/organizers-media`; manifest owner adds ninth clip `payment-qr` after picker and before scanner.

## Encoding, evidence and reuse

Native CDP JPEG frames, absolute timestamps and named cues stay outside Git. `encode.py` trims only pixels outside the actual viewport: Chrome's minimum outer window may be500px wide despite390px emulation. Normalize each frame before concat or mixed widths can shorten FFmpeg's timeline. No editorial crop/time acceleration/fabricated application UI. H26430fps CRF20 yuv420p faststart; every image including final repeat declares30fps. Decode final videos and compare duration to cue span (within one frame); confirm genuine2 selections/1300 and unpaid order state. Inspect the first map frame, selected result and QR reveal.

`CAPTURE_LOCALE=cs` selects actual Czech UI. For English, run fixture preparation with `CAPTURE_LOCALE=en`, translate the contact/data labels via the provided fixture branch, and submit a fresh local order in that locale before the QR runner. Restore the saved Czech fixture to return to Czech. Only Czech takes are delivered now. Preserve masters and timing manifests for a later YouTube cut; extend real form-entry/review beats rather than inventing payment completion. No long cut is produced now.

A prior missing CommonStrings.price getter was corrected to existing Common.price translations (cs/en checked). Geometry and capture fixes never suppress errors or weaken reservation/authentication rules.

Revision 4 fixes local fixture scope only: fields27/28 had `is_ticket_field=true`, which the real form model correctly grouped into every ticket. They now have false, order-level contact labels and ordering before ticket. No shared product code changed. Readback JSON proves one contact name/surname and zero person inputs in either ticket item; an encoded final-frame PNG accompanies the take. The separate original QR receipt footage remains unchanged and unpaid.

Revision 5 mobile presentation: canonical form design primary#253759 and secondary#ebf1f6, no custom font override (bundled Futura). Intro is the fixture's real saved `Vyberte si místo v sále.`. Actual product derives its body background by blending12%primary over white; no capture CSS changes it. Run the mobile capture normally, then `python3 phone_frame.py RAW_MP4 OUTPUT_MP4` and likewise for poster/result PNG. The actual390x844 viewport remains uncropped at18,28 in426x900; a compact rounded device bezel surrounds it, with no large letterbox. Apply `phone_frame.py` to the final form screenshot to obtain optional `public-form-mobile.jpg`; the same form already appears in the final3s of the picker video. This is a real responsive browser view, not physical-device evidence. Desktop presentation may embed this same portrait media at its native aspect ratio; never stretch it. Keep raw masters separate and verify identical duration after composition. No payment videos or archived assets are modified in this revision.


## Revision 6 - continuous native pinch, whole table
Use `capture_six.py` with the same environment as capture.py, `CAPTURE_MOBILE=1`,
`CAPTURE_SEAT_IDS=427,428,429,430,431,432`, and `CAPTURE_LOCALE=cs` (future en supported).
Verify these are available seats 2A-2F on authentic scout-ball-182, product8 at650 CZK.
Do not clear any ordered seats. Keep canonical form7 Futura (no font_family override),
primary #FF253759, secondary #FFEBF1F6 and name/surname is_ticket_field=false.
`native_pinch.mjs` targets only the owned exact local URL and sends one native two-finger
Input.dispatchTouchEvent sequence:90 paced25ms movement samples, eased distance24->120px,
with actual centre translation towards165,270. No zoom buttons, CSS transforms, fake
animation, time compression, order submission or email. Native paint timestamps remain
in outside-Git take frames.json. The six real selections finish with UI6x /3900 Kč.
Raw viewport390x844 is encoded unchanged then phone_frame.py wraps it at426x900,
matte exact #ebf1f6. Desktop and mobile use the same narrow composition. Produce JPG
and WEBP from the real selected-state poster. Keep raw take and cues for localized
retakes and longer YouTube edits; do not stretch this short take to pretend more activity.
Approved candidate location: real-picker/v6 under the review output root (outside Git).

Revision7 uses the actual Festapp web_client with vertical bottom-right zoom controls. Product CSS flex-direction column and upper reset divider; no injected controls. Same native six-seat flow, 426x900,10.6s. Proof in outside-Git real-picker/v7/runtime-proof.json;3 existing blueprint viewport checks pass.

Revision8 supersedes7: actual renderer uses + / minus / inline SVG fit icon, each44px, Czech aria-label/title retained. No text reset label or capture-only override. Both outputs426x900,10.566667s; runtime-proof.json records real bounding boxes and SVG. Native six-seat capture unchanged.
