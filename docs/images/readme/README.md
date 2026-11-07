# README screenshot provenance

Captured 2026-11-07 from repository source `99dc29ae7` using the real Flutter web app and public web client, against a dedicated disposable local Supabase database. The canonical baseline, forward migrations, and demo seed supplied the data. The seed was localized in the database before capture: English event, organizer, form, product, customer, schedule, and place names; the event map uses London coordinates. Public links were registered for the local fixtures. The seating fixture's Czech text nodes were removed and most local seat assignments cleared to show available seats. No production data was changed.

| Image | View | Viewport |
| --- | --- | --- |
| `tickets-seating-desktop.png` | Public web client seat picker with a selected seat, local ball fixture | 1100 x 750 |
| `tickets-admin-desktop.png` | Flutter web administration, synthetic orders | 1440 x 900 |
| `event-map-mobile.png` | Flutter web event map, online map tiles and local markers | 390 x 844 |
| `event-schedule-mobile.png` | Flutter web event schedule, synthetic festival | 390 x 844 |

Captures use English locale and light appearance; the tenant's dark header and navigation are part of its light theme. The mobile images are responsive browser views, not native-device captures. The Flutter release build used `test/browser/full_app_e2e.dart` and loopback-only backend defines; the fixture stubs external notification callbacks. The public web client used a local Vite fixture pointed to the same local backend. Browser sessions were isolated and headless.
