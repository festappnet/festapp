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

### Round-table gala seating

`tickets-seating-desktop.png` was captured on 2026-11-07 from Festapp source
`307b614057b18dea2eb8b4d3f784f2992388d3dd`, using the real public web-client
seat picker at **1440 x 900**, in English and light mode, against a dedicated
loopback-only disposable Supabase fixture. No production data was changed.

The local Grand Gala plan starts from the approved `approvedRoundBall()` template:
12 native circular tables with eight seats each, a stage, and the Champagne/wood
palette. The local layout positions the tables around an added central dance
floor and distinguishes the first four tables visually. Its 96 seat bindings
use local VIP (CZK 650) and standard (CZK 450) products. Stage, table numbers
and dance-floor labels use canonical prepared text resources. A VIP seat was
selected through the actual picker, producing the visible `1x CZK 650` summary.
This is a local fixture reservation, not a live sale or submitted checkout.

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
