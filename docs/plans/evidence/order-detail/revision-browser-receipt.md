# Order detail browser verification - 2026-11-01

Local release `http://127.0.0.1:58631`, served `main.dart.js` SHA-256 `6aa8ca2bb43bdebbc7992bb032eae5b38370054aef0bf5eb09b139ca15ea5504`; disposable Supabase project `festapp-order-detail-20261101`. Isolated headless browser and fixture login. External notification and production service requests blocked.

- Klára `?orderId=9`: direct link outlines its whole row; next selects Tomáš `orderId=10`, previous returns Klára, and dragging the divider retains the outline. Divider movement was bounded and survived reload in the same browser profile.
- A single customer-cell click selected only; double-click opened detail. Copy and checkbox actions left the list route intact; a single order-symbol click opened the detail. Green Ordered/Paid badges and English singular/plural ticket and place counts were visible.
- Original gray defect: Overview > Edit email > Delivery details > expand detail > Emails > expand failed confirmation. The final build rendered the controls without the previous `bool` to `double?` exception. Desktop, email and mobile screenshots are `revision-desktop.png`, `revision-email.png`, and `revision-mobile.png`; mobile puts expand and close at top right.
- Local authorized product edit: orderId 5, ticket PLES-2-2, added Dětské menu Kč150 alongside Vstup do hlavního sálu Kč650. The editor saved and a full reload showed both; order total Kč1600, received Kč1450, outstanding Kč150. No contact or cash edits or email send were performed.
- Single saved plan appeared automatically. After clearing the browser network log, Entire venue, All places and Show place produced no requests. Existing product dialog presents `Storno` in English UI; this is outside the new detail content.

Browser sessions closed; local HTTP and Supabase left running. Czech plural coverage and isolated-default width were not independently checked in this browser pass.
