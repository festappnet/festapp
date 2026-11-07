# README media provenance

## Festapp platform diagram

`festapp-platform.svg` is the editable vector source. Festapp is the shared event
platform; Festapp Tickets and vstupenky.online are its international and Czech
ticketing services. Festival Slunovrat is an example of a branded event app on
that platform. The diagram describes product relationships, not data sharing
between independently scoped organizations.

## Native iOS: summer Slunovrat 2026

Captured on 2026-11-07 directly from the real Flutter iOS application running in
a task-owned **iPhone 16 Pro simulator, iOS 26.5 (23F77)**. The raw PNGs include
the iOS status bar, Dynamic Island and home indicator. They are native simulator
screenshots, not mobile-browser captures or images painted into a phone mockup.
The standalone HTML preview adds an outer phone border without altering the PNGs.

| Image | Actual app view | Native pixel dimensions |
| --- | --- | --- |
| `slunovrat-ios-program.png` | Summer festival program, June 18 | 1206 x 2622 |
| `slunovrat-ios-map.png` | Summer festival venues in Opava | 1206 x 2622 |
| `slunovrat-ios-detail.png` | Vypsaná fiXa, June 18, 19:20-20:20 Prague | 1206 x 2622 |

The public source is [Slunovrat 2026](https://slunovrat.festapp.net/2025-copy-98cf835a/event),
**June 18-21, 2026**, occasion **1072558**, organization 19, canonical tenant
`festivalslunovrat`. This is the summer festival, not Winter Edition. Artist
names, places, dates and photographs remain from the public event data.
Geographic and proper names retain their original spelling.

The isolated capture checkout uses shared source `1080cadc1ddd5df1d09c9790dacdcfb6b06baa91`
with public Slunovrat configuration/branding from
`f89359611d4ffab7175e74a179ec956e33941bf6`, generated through `apply_config.sh`.
Capture-only changes select the summer route, use English UI, translate visible
activity titles/categories and the selected artist description **locally in
decoded display models**, and choose June 18 with the existing local app clock.
Public sync assets retain their integrity checks and original bytes. No live
event data or main-checkout application source was changed.

The simulator uses light appearance and the standard Medium Dynamic Type setting.
Its status bar is normalized to 9:41 and a full battery. Push is disabled in the
capture build; the local notification choice is set to disabled. The simulator's
location permission is acknowledged before capture. Public backend transport is
guarded against writes; no account is signed in. The scene contains no audio.

Native build and capture entrypoints:

```sh
# In the isolated Slunovrat capture checkout, with its local capture entrypoint:
fvm flutter build ios --simulator --debug --no-pub \
  --target=lib/readme_capture.dart --no-codesign
xcrun simctl install <owned-simulator> build/ios/iphonesimulator/Runner.app
xcrun simctl launch <owned-simulator> festapp.festivalslunovrat
xcrun simctl io <owned-simulator> screenshot <output.png>
```

The build uses task-local Rustup/Cargo paths and an arm64-only Xcode override for
the Apple Silicon simulator. Navigation and scrolling occur in the running app;
AXe supplies native HID input where needed. No screenshot pixels are translated,
recolored or composited. Task-specific build/control scripts and logs remain in
the ignored `.private/readme-preview/` directory; the capture checkout is also
isolated from the documentation branch.

## English ticketing examples

### Existing Lucerna hall template

`tickets-seating-desktop.png` was captured on 2026-11-07 from source
`cd9dbe25b1deffb93d4554bc996086eb200967ee`, using the real public web-client
seat picker at **1440 x 900**, in English and light mode, against a dedicated
loopback-only disposable Supabase fixture. No production data was changed.

The plan is the existing approved **`reference-lucerna`** gallery template,
based on Lucerna's public organizer seating plans. It contains ground-floor
seating, boxes, two balconies, a stage and a large dance floor. Its original
seating geometry, colors and materials are preserved. See the
[template reference notes](../../../vendor/blueprint/venue_seat_picker/doc/reference-templates.md).

The local fixture translates the plan labels into English before rendering.
Longer ground-floor labels use a smaller font to fit their original boxes;
exact text resources are prepared by the canonical layout text engine.
All **1,066 template seats** are bound to local products. One seat was selected
through the actual picker, producing the visible `1x CZK 450` summary. This is
a local fixture reservation, not a live sale or submitted checkout. No text
or other pixels were painted over the screenshot.

### Existing arena template

`tickets-arena-desktop.png` is the **1440 x 900** candidate captured on 2026-11-07
alongside the Lucerna comparison, using the same real public web-client picker,
English locale, light theme and disposable local fixture. It shows the existing
approved **`studio-arena`** template: 96 seats in four curved sectors around a
central stage. Seat positions, colors and materials are preserved; all 96
chair rotations were corrected by 180 degrees so their fronts face the stage.
The replacement capture uses canonical template source `c1d4a28` from
`festappnet/venue_seat_picker`, rendered by the same public picker. The source
fix includes a regression test of every rendered chair backrest; it does not
upgrade Festapp's vendored SDK or change saved production layouts.
The complete plan is visible; no seat is selected in this view. It is a second
ready-made venue layout, not a zoomed region of the Lucerna plan.

### Order administration

`tickets-admin-desktop.png` was captured on 2026-11-07 from source `99dc29ae7`
using the real Flutter web app against a disposable local Supabase database,
at **1440 x 900**, in English and light mode. The canonical baseline, migrations
and demo seed supplied English event, organizer, form, product and synthetic
customer names. No live customer information is shown. The fixture stubs
external notification callbacks. The tenant's dark header/navigation belongs
to its light theme.

Both capture sessions were isolated and headless. The dedicated local servers,
Supabase fixtures and owned browser sessions were stopped after capture.
