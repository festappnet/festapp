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
fix. No live fixed-link pass is claimed until this source is released.

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

## Remaining investigation

After accepting and signing in, the invited event-only editor reaches
`/eug63xh4/reservations/orders/current` and sees Access denied. This is distinct
from the URL routing defect: invitations grant occasion editor/view rights,
whereas reservations entry currently requires order-read rights. Do not grant
extra permissions merely to hide this navigation problem. Google OAuth still
requires the user's account confirmation in the separately authorized new tab.
Actual paid provider transactions and organization verification are not covered
by the zero-price Gmail proof.
