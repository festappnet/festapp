# Order detail polish browser verification - 2026-11-01

Local release at port 58631, served `main.dart.js` SHA-256 `63fb919f77ada1270c4fca180c9e593202367e87880e9491f749dd1c967f3541`, disposable local Supabase. Isolated headless session; external production endpoints blocked. No order or email mutations.

- Header has visible Cancel order; its confirmation opened and Back dismissed it. Expand control is absent on desktop and mobile. Grid order symbol displays the open icon beside the separate copy control. Thin divider dragged and its position survived reload.
- On order 5 the sole plan opened automatically. Clicking its assigned seat selected Petr; selecting the second place selected and expanded Host 2, without changing the full-venue camera. Selected ticket is marked, accordion opens and closes, and Entire venue remains available. See `polish-map.png` and `polish-selection.png`.
- Switched to Czech using the app's language picker. Detail labels, ticket counts and field fallback displayed correctly; Czech grid labels appeared after reload. The grid retained English headers immediately after switching until reload. The form section was open by default; this fixture had no order-level answer rows. Expanded ticket answers showed Strava and Typ produktu. Compact Czech diagnostic help opened from the information icon (`polish-help.png`).
- Desktop, Czech and mobile captures: `polish-desktop.png`, `polish-cs.png`, `polish-cs-reload.png`, `polish-mobile.png`. Prior browser receipt covers symbol/copy/checkbox behavior and the product save on the same local fixture.

Browser closed; local server and backend left running.
