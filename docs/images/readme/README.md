# README screenshot provenance

Captured 2026-11-07 from repository source `99dc29ae7` using the real Flutter web app and public web client, against a dedicated disposable local Supabase database. The canonical baseline, forward migrations, and demo seed supplied the data. The seed was localized in the database before capture: English event, organizer, form, product, customer, schedule, and place names; the event map uses London coordinates. Public links were registered for the local fixtures. The seating fixture's Czech text nodes were removed and most local seat assignments cleared to show available seats. No production data was changed.

| Image | View | Viewport |
| --- | --- | --- |
| `tickets-seating-desktop.png` | Public web client seat picker with a selected seat, local ball fixture | 1100 x 750 |
| `tickets-admin-desktop.png` | Flutter web administration, synthetic orders | 1440 x 900 |
| `event-map-mobile.png` | Flutter web event map, online map tiles and local markers | 390 x 844 |
| `event-schedule-mobile.png` | Flutter web event schedule, synthetic festival | 390 x 844 |

Captures use English locale and light appearance; the tenant's dark header and navigation are part of its light theme. The mobile images are responsive browser views, not native-device captures. The Flutter release build used `test/browser/full_app_e2e.dart` and loopback-only backend defines; the fixture stubs external notification callbacks. The public web client used a local Vite fixture pointed to the same local backend. Browser sessions were isolated and headless.

## Festival Slunovrat web app

`slunovrat-web-program.png`, `slunovrat-web-map.png`, and `slunovrat-web-detail.png` were captured on 2026-11-07 from the live [Festival Slunovrat web app](https://app.festivalslunovrat.cz/), which redirected to `slunovrat.festapp.net`. They show the real 2026 Winter Edition programme, Opava map, and an artist detail. The deployed web build reported `0.20.474+980`.

A task-owned headless browser translated selected public JSON response text locally before rendering: the programme category, an explanatory translation of the podcast title, the artist description and the ticket link text. The event title, artist, dates, venue, image, link destination, map, and interaction state remain from the live public data. No production data was edited. Geographic and proper names remain original. Captures use English UI and a 390 x 844 browser viewport in light mode. They are **mobile web views, not native iPhone screenshots**; Apple’s public listing and lookup did not provide current screenshot assets at capture time.
