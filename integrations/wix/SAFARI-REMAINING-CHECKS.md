# Remaining MobileSafari checks

The owner requires background-only operation. Do not foreground Simulator or
repeat the permission question. Real iPhone17Pro simulator/iOS26.5/MobileSafari26.5
passed production rendering and native HID email/name entry on published Wix.
Local cross-site checkout passed native input, summary, Safari Back and Escape
with fields retained. No production hold/order or local Safari order was sent.
The temporary owned QA widget URL was restored and republished, verified through
cold Editor readback and public HTML. See `evidence/completion-20261026.json`.

Still unqualified:

- Full onscreen software-keyboard geometry and overlap while scrolling. AXe HID
  produced real input and an accessory bar, but not the full software keys.
- Safari payment handoff, storage denial, and seat-map interaction. Chrome/local
  results do not qualify these Safari cases.
- Physical iPhone hardware. The owner has no iPhone; no hardware pass is claimed.

For a future background-capable run, first prove a full native software keyboard
is visible, then verify the focused field remains reachable above it. Keep exact
actual viewport dimensions. Use marked disposable checkout for summary, seats,
orders and payment scenarios. Never submit, select seats or initiate payment on
production. WebDriver typing returned success with an empty standalone control
(WebKit322938); do not replace native input with synthetic DOM value assignment.
AXe native HID succeeded in normal Safari after stopping the WebDriver session.
Always verify the settled field value rather than command success alone.
