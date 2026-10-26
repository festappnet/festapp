# Wix checkout qualification

Runtime unit tests are `pnpm --dir integrations/wix test`. Actual Wix receipts
live under `../evidence`; they distinguish public production assets from adapted
local HTML/backend/auth/CORS. No production inventory or real payment is used.

## Current-schema backend

From the repository root, run:

```sh
node integrations/wix/scripts/setup-backend.mjs
```

This owns only `festapp-wix-qa-20261025`, API `127.0.0.1:59921` and database
port `59922`. It checks configuration before the initial canonical bootstrap,
then checks the disposable database marker. Existing initialized databases are
restored from their retained volume, never automatically rebuilt. An incomplete
or foreign state requires inspection. Credentials and logs stay in `.private`.
The earlier WordPress backend and its existing purchases remain independent.

Apply the two guarded, idempotent fixtures:

```sh
docker exec -i supabase_db_festapp-wix-qa-20261025 psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 -q < integrations/wix/tests/seat-fixture.sql
docker exec -i supabase_db_festapp-wix-qa-20261025 psql -X -U postgres -d postgres -v ON_ERROR_STOP=1 -q < integrations/wix/tests/bank-fixture.sql
supabase functions serve --workdir integrations/wix/.private/backend --env-file integrations/wix/.private/edge.env
```

The seat fixture has a validated V2 layout and a binding to A1. The bank fixture
has a separate form and synthetic IBAN for native decoding of a real generated
payment QR. Neither enables bank fetching or supplies provider credentials.
Canonical bootstrap disables cron. No email queue worker is started, so UI text
about sending confirmation does not establish external email delivery.

Keep the functions process only for the test. Stop it afterward, then use
`supabase stop --workdir integrations/wix/.private/backend` **without**
`--no-backup`. This preserves purchases for inspection and prevents accidental
stock resets. Do not submit either recorded buyer again.

## Published Wix host

Use the existing owned headless launcher and a single about:blank tab. Capture
its loopback CDP URL, a current public form HTML document, and the private backend
status. Start `checkout-proxy.mjs` with those four paths plus `--canonical-seats`
or `--canonical-bank`. Each mode permits exactly one known form slug and one
known local container/API. Keep the production backend DNS fence active.

The published Harmony fixture retains its original settings. For these checks,
temporarily change only its `form-url` attribute to the corresponding synthetic
URL. This exercises the actual element's runtime attribute handler; it does not
prove a new native saved setting. Do not alter production frontend JavaScript.

The HTML snapshot must match available public assets. If a concurrent service
release retires a versioned script, preserve the failed attempt, fetch a current
template and restart the transport. Do not report that stale snapshot as a
current production-site failure.

For storage denial, pass `--args '--festapp-wix-block-storage=1'` on the **first
launch of a fresh named session**. Chrome blocks cookies/storage through its
native disposable-profile preferences. Verify that both storage APIs actually
throw `SecurityError` inside the HTTPS checkout iframe; an argument or a changed
user agent alone is insufficient evidence.

After a no-purchase map test, natively unselect A1 and verify that its hold is
released before closing that profile. `--lose-first-order-response` is available
only with `--canonical-seats`: it forwards a real order, drops the first actual
successful application response before delivery, and retains the full payload
hash for comparison with the retry. Assert counts 0 -> 1 -> 1 and identical
request bodies. Two POST attempts must still produce one order and one ticket.

Native Safari is not qualified by Chromium, a mobile user agent or headless
WebKit. Desktop Safari has no headless mode here. A disposable MobileSafari simulator
can run in the background; its rendering pass and native-input automation
limitation are recorded in `../evidence/completion-20261026.json`. Provider
redirect/return checks are conditional on offering such a provider; this bank
transfer flow is qualified through its actual instructions and QR, without
activating Stripe or making a real transfer.


## Remaining-boundary verification, 26 October

Read [the completion plan](../COMPLETION-PLAN-20261026.md) before running the
production probe. `production-readonly-proxy.mjs <cdp-file> <private-receipt>`
requires the same one-blank-tab owned headless browser with persistent production
DNS fencing. It permits only an anonymous SELECT/preflight for the exact public
`country_bal_vetrkovice` form. HTML, authentication and CORS are not rewritten.
No production order/hold endpoint is admitted. Stop the transport with SIGTERM
before closing its browser. This is a guarded relay read, not an unguarded
production purchase test.

The separate `reload-fixture.sql` adds only `wix-qa-reload-20261026` in the marked
Wix disposable project. `--canonical-reload --local-client` on the checkout proxy
uses a locally built candidate's explicitly enumerated public assets and locale
files. Unconfigured main builds use the legacy API origin; this mode maps that
one origin to the guarded local backend only. Production and legacy network DNS
remain blocked. This adapted candidate is never evidence of production CORS.
`--lose-first-order-response` can exercise the committed-but-unconfirmed result.
Actual seat TTL comes from `hold.duration`, not `deadline_duration_seconds`.

Order200 belongs to the recorded reload case. Preserve it alongside166/167 and
do not replay the recorded synthetic buyer or reset the purchased A1. With
storage denied, a full reload loses the draft and pending in-memory identity;
only same-page retry is promised. Assert no automatic submit, one retained SQL
order and occupied/nonselected seat state instead of inventing cross-reload
receipt recovery.

The real MobileSafari26.5 simulator run is recorded separately. WebDriver typed
no text even into a standalone input control, matching
[WebKit322938](https://bugs.webkit.org/show_bug.cgi?id=322938). Installed AXe native HID later passed text entry on published Wix without
foregrounding Simulator. Local cross-site summary, Safari Back and Escape also
passed with retained fields and no submit. Actual402px software keyboard later passed on published Wix; native320px,
external-provider redirect/return and physical hardware remain unqualified.
The subsequent storage-denied bank-flow result is recorded below;
see `../SAFARI-REMAINING-CHECKS.md`.


For native Safari storage denial, enable Block All Cookies in the disposable
device's Settings > Apps > Safari > Advanced, confirming Block All. With the
explicit disposable fixture Vite running, open the localhost host with
`?form=wix-qa-bank-20261025&storage=1`. The Vite-only `qaStorage` script probes
real local/session storage inside the checkout iframe and reports native errors
to the exact localhost parent. The host checks origin and frame identity.
Restore the native toggle afterward; cross-site storage can still be denied by
Safari independently. Do not replay buyer `wix-safari-storage-20261026@example.invalid`
or order233. The executed receipt is `../evidence/safari-storage-bank-20261026.json`.
Bank QR/functionality passed; the observed icon/layout limit remains open.

The later hidden Simulator.app run completed its native first-use keyboard
tutorial and qualified actual software keys on published Wix at402x874. Launch
only the task device with `open -g -j`, explicit UDID and hardware keyboard NO;
verify inactive app/zero visible Mac windows before and after. Restore the owned
QA URL through Save, cold Editor readback and Publish, then verify public HTML.
See `../evidence/software-keyboard-20261026.json`.

Receipt SVG font independence was reproduced with actual OrderResult imports,
no external font stylesheet and synthetic immutable payment data. Copy icons
failed18px/107px before and passed18px/18px afterward; status30px/30px and full
component320px/320px. The same minimized renderer passed native Safari visually.
This is not another purchase. Existing QR clipboard/timer tests cover feedback
reset and labels, and now run in the Wix compatibility CI command (51 tests).
The reviewed fix is live; see `../evidence/live-receipt-icons-20261026.json`.
