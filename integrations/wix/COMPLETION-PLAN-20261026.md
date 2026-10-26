# Complete Wix checkout verification

Date: 2026-10-26
Status: Background software-keyboard case passed; remaining external gates retained
Verification: standard (production reads, order retry and shared behavior)

## Outcome and completion

Verify four remaining technical areas with recorded evidence: real production
form/API integration, real mobile Safari, reload with storage denied, and repeatable
compatibility checks when the shared checkout changes. Fix demonstrated defects.
A passing local simulation must never be reported as a production or Safari pass.
All four waves must have an actual pass or a named external blocker; a blocked
wave keeps full technical qualification incomplete. Marketplace/billing approval
and the independently diagnosed native Wix install callback are separate gates.

## Ownership and current facts

- `src/element.js` embeds the canonical `/form/<slug>` webclient; Flutter is absent.
- `web_client/public/embed.js` and `src/services/embed_bridge.js` own protocol1,
  height, focus/scroll coordination and independent instances.
- `tests/checkout-proxy.mjs` currently adapts HTML, auth and CORS to an isolated
  backend. Previous purchase receipts therefore do not qualify production CORS.
- `web_client/src/services/browser_storage.js` intentionally falls back to memory
  when storage is denied. Memory cannot survive a full document reload.
- `ReservationCapabilityStore` persists only the hold capability. Seat state and
  order creation remain SQL-authoritative. Never restore seat/price authority
  from a browser snapshot or infer an unknown order failed.
- Existing disposable project `festapp-wix-qa-20261025`, API59921/DB59922, had
  preserved orders166/167 before this plan. Never reset them or repeat their recorded buyers.
- Full Safari checkout interaction is not yet qualified. Local Safari27 and an
  iOS26.5 simulator are present. A disposable background MobileSafari26.5 run
  initially proved rendering; WebDriver typing has a reproduced limitation, later
  bypassed through native AXe HID without foregrounding. Owner
  has no physical iPhone and explicitly declined foreground Simulator use.
- Canonical CI before this plan ran shared checkout checks, but did not explicitly run the Wix
  wrapper suite with the shared embed protocol suite on checkout changes.

## Constraints

Use an isolated headless browser and preserve the user's windows. Production
checks may read public form data only: no orders, holds, payments, provider/email
activation, database fixtures or migrations. Never expose credentials, capability
secrets or buyer data in receipts. Use native backend DNS blocking before/after
QA interception. No new billing commitment, paid browser provider or duplicate
support case. Reuse passing results for unchanged inputs; no Flutter task needed.

## Execution waves

### 1. Real production read path and CORS

Inspect the exact public `get_form_by_link` SQL entry before allowing it. Add a
strict QA allowlist to the owned CDP transport (or a narrowly separate readonly
runner if sharing would weaken the checkout guard): only OPTIONS and POST to
`https://api.festapp.net/rest/v1/rpc/get_form_by_link`, with exactly the selected
public form link, may reach production. All other backend requests fail closed.
Keep browser launch DNS fencing active. Preserve actual response CORS/auth and
public HTML/assets, with no synthetic response or credentials substitution.

Open the existing published Wix QA host, temporarily point its runtime attribute
to a real public form, and observe the public form/API response and UI. Record
build/helper/asset identities, HTTP and application status, actual CORS headers,
blocked request counts and zero checkout/hold calls. Restore through reload.
Record the protective relay boundary; do not claim an unguarded direct browser
network run or an actual production purchase. Exit: real production form loads
inside actual Wix with unchanged CORS, or the precise failing boundary is fixed.

### 2. Reload while browser storage is denied

Use the dedicated backend and fresh native-blocked Chrome profile. Verify both
storage APIs really throw. Reuse existing fixtures where no stock/order write is
needed; otherwise create a distinct guarded fixture/slug and synthetic buyer.
Do not rewrite immutable earlier payments, free their seats or clear orders.

Check a filled draft across full iframe reload and parent reload. Expected:
no automatic order submission, no stale purchased seat shown as owned, bounded
server hold expiry read from actual hold.duration policy (form payment deadline
is not a seat TTL), and no duplicate order caused by reload. When storage is
unavailable, record that draft/capability retention is not promised. Inspect a
lost-success-response followed by full reload as a separate scenario from the
already-passing same-page retry. Verify SQL counts before/after; explicitly
state whether the previous outcome can be recovered. If it cannot, record the
user-visible limitation and correct misleading automatic-retry/success behavior
without introducing a parallel order identity or storing secrets in public URLs.
Exit: actual browser/SQL proof of safe reload behavior, demonstrated defects fixed.

### 3. Real Safari/iPhone

Do one bounded capability investigation: native Safari automation, existing iOS
simulator and existing installed inspection tooling. Do not foreground desktop
Safari or Simulator. A task-only hidden Simulator.app may run when inactive and
zero visible Mac windows are verified. The background simulator must actually
run MobileSafari and be controlled/inspected.
No new paid provider or unapproved account setup. A desktop WebKit or Chrome
mobile user-agent is not a Safari/iPhone pass.

On a real usable Safari surface, check public readonly loading, width/height,
keyboard overlap, focus, summary/Back/Escape where supported, and storage denial
against disposable data only. Record exact OS/browser/device, transport and
observed cases. If no compliant surface exists, prepare a short owner-executable
public readonly iPhone checklist and keep its gate explicitly pending until
actual results arrive. Simulator results must remain distinguished from hardware.
Exit: real evidence for each claimed Safari case; untested cases remain blocked.

### 4. Ongoing checkout compatibility and final review

Add one targeted CI lane using pinned pnpm and existing owning suites: Wix widget
suite/build and `web_client/tests/core/embed.test.js`, browser storage and hold
capability tests. Trigger on Wix runtime/settings, shared embed/forms/storage,
relevant locks and this workflow. Keep checkout SQL/browser regressions as the
existing owner, not duplicate business logic. Do not deploy every tenant.

Run the new affected check batch once on final code. Preserve actual browser
receipts separately from unit/CI evidence. Independent critic reviews source,
guards, plan versus receipts and remaining limitations (standing owner request).
Fetch/reconcile main before publication; merge only after required green checks.
If production wrapper behavior changes, seal/deploy only reviewed exact assets
and verify hashes via the existing free Pages project. Delegate routine release
monitoring as authorized. Otherwise no product deployment is needed.

## No cutover or deletion

No production path is replaced. The disposable write proxy and readonly public
probe are different test boundaries. Retain historical evidence with its original
source/build identity. Remove only this run's temporary routes/processes, close
its browser, stop local Edge/backend with retained database volume, and record it.

## Final evidence and status

Update this plan with executed wave results and exact blockers, plus a sanitized
`evidence/completion-20261026.json`. Full completion requires every requested
technical gate passed; a written checklist or an automation script alone is not
proof that its test was executed. Commercial/native portal gates stay separate.

## Execution record

- Wave1 PASS: actual public form/API in published Harmony, production client
  0.20.409+910, exact SELECT/preflight HTTP200/application200, original CORS,
  enforced browser web security, 320px host/281px iframe without overflow and
  real helper resizing to1167px. Guarded relay boundary retained in evidence.
- Wave2 PASS with an explicit retention limit: native blocked local/session
  storage, filled draft cleared across iframe and parent reload, no autosubmit.
  Fresh local form36 committed exactly order200; its successful response was
  deliberately lost. Candidate displayed unconfirmed outcome rather than failed.
  Full reload left one order and A1 occupied, not selected. The actual hold TTL
  was900sec, not the form payment deadline. Previous orders166/167 retained.
- The discovered unknown-outcome fix was incorporated by concurrent approved
  main commit5436b9f80 and shipped in0.20.410+911. Independent readonly release
  verification confirmed exact public module markers and all6 live translations;
  no duplicate build/deployment was performed.
- Wave3 PARTIAL: actual MobileSafari26.5 on isolated iPhone17Pro/iOS26.5
  rendered the production form in Wix at353px without overflow. WebDriver typing
  failed even its standalone control (WebKit322938). Installed AXe native HID
  then passed email/name input and visible caret in normal Safari on published
  Wix without foregrounding Simulator (activefalse, visible windows0). Native
  input, summary, SafariBack and Escape with retained fields also passed in the
  local cross-site checkout; no Submit was pressed and its order count stayed1.
  The temporary owned Editor QA URL was restored, cold-read and republished;
  public HTML confirms original QA URL and absence of temporary Country URL.
  At this wave, full software-keyboard geometry, Safari payment handoff and
  physical hardware remained unqualified; bank/storage follow-up appears below. See the remaining-checks checklist and exact receipt.
- Wave4 implemented: dedicated pinned CI job for wrapper/build plus shared
  embed/storage/hold, command identity, unknown outcome and payment handoff.
  Local43 targeted tests,4 handoff tests and15 Wix tests passed. The exact combined CI suite passes45 tests on reconciled main. GitHub
  required checks on the publishing branch remain the authoritative CI result.
  Final independent evidence review is required before publication.
- Local checkout browser, Edge and backend stopped; retained volume preserves
  all3 recorded orders. No production orders/holds, external emails, billing
  changes, new support cases or other-tenant releases were performed.

### Follow-up: native Safari storage and bank flow

Executed in background on the same disposable device, source2e701e4de. Native
Settings Block All Cookies enabled; the actual cross-site checkout iframe threw
SecurityError for both storage APIs. Native input/summary succeeded, then one
local submit created order233 (buyer0->1, form count1->2). Expanded bank QR
decoded through native Vision and matched SQL150CZK/VS4412. Fresh parent navigation
retained exactly that order, blanked the draft and did not resubmit. Occupied
A1 in local form34 remained sold after native tap, with no secret/expiry.
The settings toggle was restored OFF, task keyboard preference restored through
the preferences API, device shut down and Vite/Edge/backend stopped with backup.
Orders166/167/200/233 retained. No production write, transfer or external email.

At that follow-up, the software keyboard remained offscreen (AX q y898 on874px display). The initial
local bank receipt also displayed literal icon names with overflow; later font
diagnostics loaded the Material Icons face successfully but did not establish
the original cause. Its layout remains unqualified; no app font fix is claimed.
See `evidence/safari-storage-bank-20261026.json` for the exact boundary.

### Follow-up: receipt icon independence

A minimized actual OrderResult renderer reproduced literal glyph text and
copy overflow without the external icon stylesheet (18px control,107px content).
The same renderer with Google font CSS and explicit load passed18/18, with
Material Icons/liga/normal ligatures. This proves the dependency's failure mode,
not the original Safari cold-load trigger. Fixed status/copy/check SVG paths
remove that dependency in this receipt layer. Actual320px Chrome measured
component320/scroll320 and icon30/30,18/18; background MobileSafari screenshots
show proper icons and wrapped IBAN. Existing clipboard/reset/accessibility
behavior retained. No backend, purchase or foreground window was used.
Local fix verified; PR599 passed all five checks and was merged. The concurrent
approved pending-ready release shipped the same reviewed files in0.20.415+916.
Independent live module/build/legal verification passed; no duplicate deployment.
See `evidence/receipt-icons-20261026.json`.

### Follow-up: actual Wix software keyboard

Hidden task-only Simulator.app (`open -g -j`, explicit UDID, hardware keyboard NO)
plus completion of the native first-use keyboard tutorial exposed full software
keys. Actual published Editor QA/Country form passed onscreen J/a/n/a input,
direct surname focus with onscreen N, manual content scroll while keys stayed
visible, and Done retaining both values. Focused fields were above the keyboard.
Native application frame402x874; Q y590 and return y752 are inside the display.
Simulator active=false, visible Mac windows0 before and after. No production
hold/order, payment or local backend start. Actual public form/API reads occurred.
Native cached client version was not read; no current-build or320px claim.
The original synthetic URL/title were cold-read and republished, public HTML
confirmed rollback, and owned browsers/device/app were closed. Keyboard preference
restored. See `evidence/software-keyboard-20261026.json`.

### Final live readback

Live0.20.415+916 maps to prod0c205732c (base mainb0e0dcf51), containing the exact
reviewed receipt SVG source. Canonical deployment verification passed three
consecutive build/legal probes. Live manifest and form module SHA256 match the
owner build and the module contains the reviewed SVG path. No extra release was
created for these verification notes. Native Wix clean-install/portal and written
commercial approval remain external gates; this is not Marketplace submission.
See `evidence/live-receipt-icons-20261026.json`.
