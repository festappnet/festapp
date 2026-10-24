> Novější česká iterace a skutečný Festapp picker: [real-product-refinement.md](real-product-refinement.md). Níže je historická evidence.

> Historická iterace před novou uživatelskou připomínkou. Aktuální design a nahrazené layout/ticket klipy viz [product-design-refinement.md](product-design-refinement.md). Předchozí ivory/ink/wine nebylo schváleno.

# Media provenance - local implementation

All production clips are real UI recordings with synthetic data. Editing is
limited to trims, focused crops, synchronized views of the same frame, scaling
and short result holds. No animated fake application state, competitor video,
production customer data, testimonial or sales metric is included.

- `layout-build`, `layout-style`, `seat-select`: genuine reusable editor package
  takes from `venue-seat-picker-public-preview-20261021/build/showcase-chapters-final-20261021/`.
  Four tables, 32 seats, two selected, synthetic total 500. Export SHA256
  `b4bbe0ebf88b08c4bea19692714c41814e5a611147183a16c14cf39c3eaf448b`
  identifies the same authored document passed into the picker. Editor-only
  boundary is visible in landing copy; this proves no reservation/payment.
- Static `hero-hall.jpg`: real package classic-ball preview, 12 tables/72 seats,
  stage, reception and dance floor. The separate phone view is labelled mobile
  selection; no claim that the hero image is the four-table handoff document.
- `form-build`, `form-style`: real Flutter administration over local synthetic
  occasion 6/form 7, an ordinary editable clone made through the real clone UI.
  Added Večeře, Kuřecí menu/Vegetariánské menu, required flag and saved through
  normal controls/RPC. Public result loaded from the same form in the real JS
  client. Default public design was restored only as disposable fixture setup
  outside capture for a truthful same-content before view; recorded edits select
  Ocean and Playfair Display and save normally.
- `ticket-design`: same clone, real template picker (Ples - hedvábná pozvánka),
  Futura PT, bold and centered guest name, real save and local PDF renderer. Final
  PDF contains matching sample name, price, date and QR. Preview required local
  static font/background packaging; no product guard was removed.
- `check-in`: independent ordinary synthetic occasion 7. A canvas QR camera
  stream is decoded by production jsQR, valid entry is confirmed through the
  real sync RPC, and the same QR produces the used-ticket warning. The mobile
  clip is captured at an actual narrow viewport.
- `orders-overview`: synthetic demo data, real order filter 95 -> 12, followed
  by the actual ticket-table download button. Downloaded CSV has 260 data rows,
  16 columns, 30,943 bytes. There is no order-table export control in current UI.

Flutter accessibility semantics required activation of rendered controls via
DOM click and scrolling the rendered scroll container in some takes. These
operate actual UI handlers; no fields, RPC responses or application state were
fabricated. Visible pointer gestures track the selected rendered controls.

Capture masters, cue timestamps, reproducible encoders, CSV proof and the
complete review gallery remain outside Git under
`~/Downloads/festapp-landing-review-2026-10-22/`. Production exports alone are
in `web/organizers-media/`. `media-validation.json` records their hashes and
full-decode checks. The same folder contains the browser-isolation audit;
subsequent captures always use an explicit empty config, owned namespace and
headless profile on every command.
