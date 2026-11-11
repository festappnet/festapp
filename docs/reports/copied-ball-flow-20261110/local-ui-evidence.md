# Copied-ball UI verification - 2026-11-10

**Result: passed through the real Flutter interface and local backend.** Business source is deployed main `5a16ef20b16c64967c348505ad72bb0a7c566de3`. The synthetic source has a four-seat plan, a primary admission catalog attached directly to the ticket container, dinner and transport groups, and a closed form.

## Verified actions

| Action through the interface | Evidence |
| --- | --- |
| Create a copy from the organizer card and destination dialog | Lifecycle command HTTP 200; source occasion 3, copied occasion 5 |
| Edit and save the copied form | Actual `update_form_client_sync_v1` HTTP 200, status `applied`, code 200 |
| Reopen the editor | Renamed dinner group and required checkbox persisted; Save disabled |
| Open the copied form and save | Actual UI save succeeded; [light screenshot](opened-form.png) |
| Close the form again and save | Actual UI save succeeded; form 5 remains `is_open=false` |
| Select a seat and confirm an order while the form is closed | Actual preview 200 CZK; real local `send-ticket-order` Edge endpoint HTTP 200; [light screenshot](closed-form-seat-ordered.png) |

Final database readback: order 2 belongs to copied occasion 5 in state `ordered`; ticket 2 is connected through order_product_ticket 2 to copied seat 5/S1. Source occasion 3 remains closed with zero orders. Primary groups are independent (source 3, copy 6). Source dinner remains optional, while its renamed copied field is required. The media job is complete, with an empty asset manifest.

## Environment and limits

The disposable project `festapp-copy-e2e-20261110` used PostgreSQL 15, API `127.0.0.1:56521`, DB `127.0.0.1:56522` and the real full-app browser fixture. A task-only generated tenant configuration supplied synthetic blocked HTTPS sync origins and a digest-matched local canonical activation manifest, selecting production's v219 contract against the local API. Application business and bootstrap code were unchanged. External notification callbacks were stubbed by the canonical fixture; local email capacity was paused with worker URL NULL and cron disabled. No production writes or real emails were made.

The real canonical image Worker ran in Miniflare with local R2 and authenticated local GoTrue/PostgREST transport. The browser rewrote only its lifecycle request origin to the local adapter. Its first completion attempt failed transiently; replaying the same committed job succeeded HTTP 200/state complete. The fixture has no banner: image byte transfer or production R2 copying is outside this check.

Canonical baseline `20260906140000` and shared forward definitions were installed. Tenant-specific migrations `20261013093000`, `20261013103000`, `20261025200000` and `20261101190000`, plus protected provider/security operations `20261016172000`, `20261018103000` and `20261019020000`, were excluded. The shared presale archive definitions from `20261105170000` were initially omitted by mistake and restored before the successful save. After repair, a read-only audit matched all 972 checked canonical function signatures/body hashes against deployed main; see [function parity](function-parity.json). This is a functional workflow check, not a proof of full production ACL parity.

The DDC browser build failed to load scripts, so the successful run used a release build in isolated headless Chrome. Direct `/login` avoided a local unauthenticated-root startup loop. Headless semantics required scoped DOM clicks; for seat selection, the obstructing fullscreen `web-selectable-region-context-menu` overlay's pointer events were disabled locally and normal pointer events were delivered to the visible Flutter glass pane. The real Flutter selection/order handlers and backend commands performed the operation; no controller state or successful response was fabricated.

Local infrastructure also produced transient 57014 timeouts and 502/503 responses. Actual save recovery retained the existing intent and eventually returned applied/200. Initial order confirmations encountered an absent local Edge runtime; DB showed zero orders, then the exact-source Edge function was started with JWT verification enabled and the same UI intent succeeded. These harness failures are not reported as successful actions.

## Cleanup

Owned headless sessions, Panerelay tab t24/participant, Flutter, Edge runtime, local Worker and disposable Supabase project were stopped. The user's other Chrome tabs were untouched. Temporary bearer tokens and the task-only configured checkout were removed; the deployed-source checkout remains clean. The regression and screenshots remain in this validation worktree.
