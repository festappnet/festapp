# Wizard delivery and invitation follow-up - 2026-10-29

Continuation of the two wizard-followup UI reports. Real production checks used
one newly registered QA account, its own unit 1012 and hidden occasion 1072628
(`QA Gmail delivery private 20261029-36e315`). No customer occasions were changed.
Mail was delivered to explicitly authorized Gmail aliases; passwords and
invitation proofs are retained privately outside the repository.

## Real delivery proof

- Public registration and initial-code email succeeded, followed by normal login.
- The real wizard created a hidden event with a free ticket and explicitly confirmed team invitation delivery. Public order submission succeeded.
- PDF-only order `5I7R6M4X5Y`: actual Gmail attachment, event title, zero price, embedded fonts and decoded ticket QR `X3284W2Q7E` verified.
- Inline-only order `3A2G5U4X3K`: no PDF attachment; inline PNG decoded to `X3287L8V3W`, matching the email ticket code and CID reference.
- Both-mode order `6U5I8A6J8F`: PDF plus inline PNG delivered; PNG decoded to `X3285C8V1C`, matching PDF filename/text and email. Gmail reports SPF, DKIM and DMARC pass.
- Delivery-mode changes used the authenticated canonical occasion-save RPC of the QA owner, preserving hidden status and scope, rather than claiming a live dropdown UI pass.
- The delivered team invitation was accepted through the existing `/transfer` Flutter handoff as a diagnostic workaround. Account creation and normal password login succeeded. Read-only authoritative readback confirmed event editor=true, manager=false and zero unit memberships.

## Fixed: invitation URL swallowed by occasion routing

The original emailed `/team-invitation?token=...` navigated to the marketing
homepage. The public-route policy misclassified this single-segment auth route
as an occasion. Three routing owners now explicitly recognize it: public path
classification, web-client Flutter handoff and hosting-worker Flutter prefixes.
The last prevents an unrelated occasion-slug lookup returning 404 even with the
other two fixes. Query parameters remain intact.

Regression evidence: web-client router suite 42 tests, generated hosting worker
suite 7 tests, all passing; production web-client build and diff whitespace
check pass. The backend-configured worker test failed 404 before the prefix
fix. Live verification after release 955 is recorded below.

## Additional date UI proof

A compiled, loopback-only Flutter fixture exercised actual date/time widgets,
with persisted draft readback after the Saved indicator:

- Prague overnight 2026-11-28 23:30 to 2026-11-29 02:15: 9,900 seconds.
- Spring DST 2027-03-28 01:30 to 03:30: 3,600 seconds.
- Autumn DST 2027-10-31 01:30 to 03:30: 10,800 seconds.
- Nonexistent spring 02:30 normalizes to 03:30; end 03:45 gives 900 seconds.
- End date before start displays validation and blocks Continue.

The temporary test bridge and raw evidence remain outside published product
source. Earlier driver attempts before a stable save were discarded.

## Separate workspace access defect

After accepting and signing in, the invited event-only editor reaches
`/eug63xh4/reservations/orders/current` and sees Access denied. This is distinct
from the URL routing defect: invitations grant occasion editor/view rights,
whereas reservations entry currently requires order-read rights. Do not grant
extra permissions merely to hide this navigation problem. The resolution and negative permission checks are recorded below. Google,
paid local checkout and verification have separate evidence below; the zero-price
Gmail proof alone does not establish them.

## Further completed checks

- The actual wizard delivery dropdown persisted `inline_qr`, then `both`, verified after Saved against its draft. Finalization retained `both` and hidden status.
- The DST-gap draft became occasion 177 on the isolated backend. Normal Settings loaded start 03:30; changing end to 03:50 and saving persisted 01:50Z, preserving start 01:30Z, hidden status and both delivery. Reopening the actual time picker confirmed 03:30.
- Organization verification UI rejected invalid registration lookup, loaded the real public ARES record for a valid test number, validated email/HTTPS fields, saved synthetic local details and submitted into pending status (revision 2). The disposable fixture needed its notification function owner aligned with production (`postgres`) and a synthetic HTTPS DEFAULT_URL. Read-only production catalog inspection confirmed these were local fixture differences; no production verification data or permissions changed.
- Existing payment-policy and organization-verification database suites passed 5/5. The paid checkout test uses the canonical payment-reference allocator.
- Read-only RPC checks as the real accepted Gmail invitee: forms reader returns 200 and one form, product catalog returns 403, order reader denies access. This proves the UI entry failure is separate from the invitation role contract.

- Release 955 included the invitation-route fix. The original delivered URL in a fresh isolated browser remained `/team-invitation` with its token query, zero HTTP redirects, and rendered the real invitation/sign-in page. An older QA browser retained the previous redirect; the fresh-profile result separates that cache from the current route.
- Paid local web-client checkout created order 38 (`2Y1F4M7K7H`) at CZK 175. Normal administration Add Payment recorded CZK 175; readback confirmed state paid and paid amount 175, with ticket-delivery queued. No real money moved. The disposable email queue remained paused without a worker URL and cron had zero active jobs. The local Edge runtime was started to exercise this actual web-client workflow. The older Flutter-form attempt is not counted as a paid pass.
- Both-mode Gmail PDF was also rasterized and its QR decoded, matching the inline PNG and issued ticket code exactly.

## Google sign-in

The user completed the Google confirmation in the separately authorized new
Chrome tab. Browser returned to the original private test form with no proof
query parameters and no pending attempt. The current account session's sign-in
time advanced. A read-only, organization-3 query scoped to that exact current
account confirmed the matching login attempt was consumed and its external
identity linked. No shared browser logout or credential reset was used.

## Fixed: event-only team member workspace entry

Invited editors and readers retain their existing SQL permissions. Workspace
navigation now accepts either order-read or form-catalog-read capability.
Orders, issued tickets, products, reports, inventory and sales blueprint tabs
remain behind order-read; the existing tab router normalizes the old orders
destination to Forms before constructing protected children. Order-read checks
used by data/report code are unchanged. Menu entry and remembered workspace
restoration use the same workspace predicate.

Real local Auth/REST reproduction used two synthetic invitation fixtures, then
normal account acceptance/password login. Before the fix the editor was denied.
After the fix it opened the actual form editor; network captured Forms 200 and
zero order/product-catalog requests. The reader opened the form with availability
disabled and no Edit/Add Field/Delete actions. A further visible Create/Copy
control was found in both list/detail UI and is now guarded by forms.create.
The payment dialog's dismiss action also uses Common.cancel, correcting its
visible Storno wording.

Targeted rights tests passed 18/18, workspace metadata tests 4/4, and actual
list/detail creation-visibility widget tests 4/4. Targeted analyzer reported no
errors or warnings, with informational lints. The diagnostic
pointer fixture is local-only and is excluded from the checkpoint.

Final source compiled successfully in 85.1 seconds. Both accounts were physically
reloaded against that final build. The editor retains Create/Copy and Add Field;
the reader has neither these nor Edit/Delete, and neither account dispatched
any order-reading request. A direct valid-scope form-save attempt as the reader
returned HTTP 403 / SQLSTATE 42501 (`form editor required`); authoritative form
title stayed unchanged. Both accounts have zero unit memberships and no order
read role. [Readback](wizard-complete-2026-10-29/role-ui-readback.json),
[editor UI](wizard-complete-2026-10-29/editor-final.png),
[reader UI](wizard-complete-2026-10-29/reader-final.png).
