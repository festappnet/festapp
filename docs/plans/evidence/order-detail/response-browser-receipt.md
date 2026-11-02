# Order answer editing browser verification - 2026-11-01

Local release at port 58631, served `main.dart.js` SHA-256 `4ed62429099390fafc7bec1dd6df1e570c8131b9ad46fe8429779e85636ed53a`, disposable local Supabase and isolated headless browser. Production endpoints blocked.

- Order 5, source form Vstupenky na zimní ples #8: edited Telefon from +420 777 000 002 to +420 777 000 022 through the response editor. Contact email was read-only and absent from the editable grid. Saved and confirmed the new phone after a full reload.
- Ticket PLES-2-2 Host 2: selected Bez omezení from the configured Strava dropdown, replacing Vegetariánská. Saved and confirmed after reload; the name and purchased products remained intact. The order showed Kč1600 total and Kč1450 received before and after. No email or cancellation actions occurred.
- Single venue plan loaded after answer refresh without a stale-plan error. Category grouping displays authored Seats. Ticket icon stays the same as its accordion expands; selected tint and semantics are visible.
- Source form and ID appear above contact; Hidden (internal note) sits immediately below contact. Native underlined tabs, customer overview icon, previous/next/close and direct Cancel order are visible. The 360px pane keeps header controls visible and wraps the title; dragging from 12px outside the divider moved it. Mobile screenshot also shows the header controls.
- Evidence: `response-header.png`, `response-narrow.png`, `response-mobile.png`, `response-saved.png`, `response-ticket-saved.png`. Prior polish receipt covers actual Czech locale, diagnostic help and saved splitter width.

Only the two authorized fixture answer changes were made. Browser closed; local server and backend remain running.
