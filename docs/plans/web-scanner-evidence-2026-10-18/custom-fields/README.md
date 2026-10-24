# Custom field scanner scenarios - 2026-10-18

Isolated local database `festapp_scanner_20261018`, occasion 1281, Festival · Hlavní vstup.
No production writes. Data prepared by `web_client/scripts/scanner_demo_custom_cases.mjs` with explicit local database/fixture/output arguments.
The generated local fixture is `web_client/tests/scan/custom_cases.json`; it contains no scan secret or session token.

| Scene | QR symbol | Expected content |
| --- | --- | --- |
| custom | DEMO-1281-CUSTOM | Klára Veselá, Taneční klub Orion, group size 4, vegetarian meal; entry note under Další údaje |
| ball | DEMO-1281-BALL-A | Jana Dvořáková from linked user account, table 7 seat 1, reservation Novákovi a přátelé, 2 seats in order, chicken meal, admission and dinner products |
| ball_group | DEMO-1281-BALL-A and DEMO-1281-BALL-B | Same order, two guests, separate seats and menu answers; opening Petr shows gluten-free meal and seat 2 |
| empty | DEMO-1281-EMPTY | Unanswered custom fields are omitted, no empty extra-details section |
| long | DEMO-1281-LONG | Long group name and entry note, no horizontal overflow at 390 px |

All cases are real local orders/tickets. The ball seats link to `eshop.spots` and the local blueprint Demo - plesový sál; this is a scanner seat-reference fixture, not a finished visual blueprint editor layout. The disabled contact field is excluded from the rendered scanner detail. No admission was confirmed while preparing or checking these examples.

Validation:
- Two SQL files passed: `scanning/custom_fields_test.sql` and `scanning/authorization_test.sql`. Custom order/ticket answers are isolated and match offline snapshots. Same-organization cross-event lookup, manual search, snapshot access, mixed bearer and a forged foreign-ticket admission are denied; foreign ticket state remains unchanged.
- Scanner JS: 34 passed, 1 skipped.
- Isolated headless browser checked actual custom data, linked holder name, two products, seat, per-guest menu isolation, hidden/empty fields and long text. Screenshots at desktop and 390 px are included. Camera access was denied in this automated profile; these screenshots do not verify physical camera hardware.

Open `/scan?scene=custom`, `/scan?scene=ball`, `/scan?scene=ball_group`, `/scan?scene=empty`, or `/scan?scene=long` on the existing localhost:5174 demo. QR pro kameru displays the selected custom case codes.

## Order grouping and visible products

The canonical ticket projection now includes `order_id`; the scanner groups by this identity, preserves original controller/selection indexes and leaves unknown orders independent. Individual rows show seat and all configured visible product titles before expanding details. A shared table header is displayed only when every scanned ticket in the order has the same explicitly labelled table/seat reference (for example `Stůl 7 · místo 1`). Mixed tables, missing seats and arbitrary seat codes do not imply a shared table. This grouping is presentation only; confirmation still checks each ticket independently.

The canonical SQL and assembled scanner migration match; only the isolated local projection was applied. Scanner JS: 36 passed, 1 skipped; all six scanning SQL files passed. The final hint removal was followed by the five affected grouping/camera lifecycle tests. Actual browser rendering checked both demo guests, same order/table, individual seats and both products on unexpanded cards, plus mobile width 390 px without horizontal overflow. Desktop screenshot before removing the redundant hint is `order-groups-desktop.png` (automated profile has no physical camera permission). A final browser restart/recheck timed out and is not counted as passing evidence; the affected five final DOM/grouping tests passed.

## Purchaser and menu model from a real ball configuration

Reference: the private local configuration snapshot (2026-10-05) of Sportovní ples Větřkovice 2026, not a fresh production inventory. Its order form has order-level name/surname and per-ticket seat/menu. Dinner products are Bez večeře; Menu 1: Hovězí guláš, houskový knedlík; Menu 2: Vepřová panenka zabalená ve slanině, pepřová omáčka, šťouchaný brambor; Menu 3: Kuřecí soté, rýže. The Skautský ples reference has compact seat labels such as 28A and explicit blueprint group references, rather than the earlier synthetic Stůl 7 · místo 1 text. No claim is made that AKH/Country configurations were freshly inspected.

`scanner_demo_ball_reference.mjs` creates two synthetic local orders / four unnamed tickets in occasion 1281, using the referenced product types/menu names and a subset of the referenced blueprint configuration with local seat IDs. Petra Svobodová orders seats 7A/7B with menus 1/2; Tomáš Novák orders seats 8A/8B with menu 3 / Bez večeře. No real customers, answers, transactions or ticket symbols were imported. New JSON cases and the two-page `Festapp-model-plesu-QR.pdf` contain no scanner credential.

Projection separates `purchaser_name` from `holder_name` and resolves `spot_group` through the actual blueprint object/group mapping. Same group numbers from different blueprints are not merged. Products carry their configured type/title, allowing the exact dinner choice to appear first on the collapsed card. Unnamed tickets show Vstupenka rather than fabricated holder names; purchaser appears once at order level, and is explicitly labelled in a single-ticket detail.

Validation: 38 JS tests passed, 1 skipped; all 7 SQL scanning files passed, with the added offline identity/menu assertions rerun in ball_order_test.sql. That test covers one purchaser/two tickets, absence of fabricated holder names, compact seat-to-group mapping, source product/food types, legacy order-name field answers and snapshot parity. Browser readback checked Petra's two menus, Tomáš's menu/Bez večeře, no purchaser-name repetition on cards, two separate groups for four tickets, and 390 px layout. Desktop/mobile screenshots are reference-order-desktop.png / reference-order-mobile.png. No admission confirmed. PDF has two A4 pages with four QR symbols and expected results.

## Simplified card presentation

Order header shows only the purchaser name and common table. Each card shows a labelled seat (or an independently recorded holder name), a green check/text/border for eligible tickets, and plain dinner text. Pending/unpaid remain amber and blocked tickets red; eligibility is never communicated by color alone. Removed nested order border, menu badges, duplicate generic spot product (only when the canonical spot product title equals its type title and the actual seat is available) and collapsed raw code. Special seat-product variants remain visible; codes remain in the expandable detail and on unknown-code rows. No speculative price total was added.

38 JS tests passed, 1 skipped. Actual browser verified order name, Místo 7A/7B, exact two meals without duplicate Místo products, green status computed styles, and no horizontal overflow at 390 px. Final screenshots: simple-cards-desktop.png and simple-cards-mobile.png. Camera permission is absent only in the isolated automated profile. SQL unchanged in this presentation pass.

## Consistent status, short product titles and visible notes

Cards now share a neutral surface/border. Valid status uses a green ticket-with-check icon plus Platná, with the full accessible label. Products use a shared short-title/fallback formatter in the row and detail; a meaningful short title is not suppressed as a generic seat product. Order notes render once above related tickets and individual notes on the corresponding row; both appear in single-ticket detail. Gated internal order/ticket notes are included only when the server's existing sensitive.hidden_note permission allows them. User notes are escaped and multiline text wraps. Group detail does not duplicate notes already shown on its row.

The model adds a synthetic order note about arrival and an individual accessibility note. Its second menu has an explicitly configured demo short title Menu 2: Panenka s pepřovou omáčkou; this is a local presentation override, not a claim about the reference source's current settings. Existing ticket states are preserved.

Validation: 39 JS tests passed, 1 skipped; the five affected presentation/lifecycle tests passed after the final small formatter/deduplication adjustment. All seven scanner SQL suites passed including public/private note separation, sibling isolation, configured short title and offline snapshot parity. Browser readback verified shared note once, individual note only on its ticket, shortened second menu, equal neutral card surfaces and compact valid labels; desktop/mobile screenshots are notes-desktop.png and notes-mobile.png. SQL projection was applied only to the isolated local database, and assembled migration matches canonical SQL.
