# Review handoff - vstupenky.online

Status: SUBMITTED, case `2351677:2082001`. The vendor follow-up form was accepted. Do not repeat Publish, Request review or the follow-up submission. AppBot feedback was addressed, fresh scenarios passed, and a technical reply was sent in the existing case; human approval is pending. See [review knowledge](REVIEW-LESSONS.md) and [reply](RESPONSE-20261028.md).

App: `vstupenky-online-buoz5u`, version 1, EU1. Publisher account: info@festapp.net, organization 9450617, team 3387186. Standard verified app, first-party service owner. No Community submission or optional partner application is required by the documented verified-app route.

Service: https://vstupenky.online/
API documentation (public OpenAPI 3.1): https://mcp.vstupenky.online/make/v1
Privacy: https://vstupenky.online/privacy/
Terms: https://vstupenky.online/terms/
Support and partnership contact: info@festapp.net
Legal operator, as displayed in service terms: Michael Bujnovský, IČO 06455361, Přívozská 1704/24, 702 00 Ostrava, Czech Republic. Festapp is the platform name; vstupenky.online is the service brand.
Submitted category: Commerce / E-Commerce (actual form options; no Event Management category offered).
Logo source: `integrations/chatgpt/assets/logo.png` (same regional service identity, uploaded to this app).

## Scenarios

- All five modules: https://eu1.make.com/3387186/scenarios/8226665/edit
- Expected error / fixed-origin read allowlist: https://eu1.make.com/3387186/scenarios/8228261/edit

Both are on-demand and inactive. Do not enable a recurring schedule. Positive scenario returns one report, one consented event, 52 order bundles across two pages, one order detail and one universal read call. The error scenario intentionally rejects a foreign URL. Existing successful executions and expected errors are recorded in `../evidence/`; refresh logs before actual submission if delayed.

## Synthetic reviewer access

Use the retained Make-only synthetic account. Its credentials live in `~/.festapp/make-review-20261028/credentials.json` (0600 inside 0700 directory). Never commit the password, bearer tokens or OAuth codes. Provide credentials only through Make's intended private reviewer channel when requested.

Consent to event 1072620 only. The account can read two different events with identical names (IDs 1072620 and 1072621); consent remains restricted to the selected ID. The third fixture event 1072622 is inaccessible. The retained dataset has 52 orders per readable event, invalid email destinations and no queued email or payment provider configuration. Do not rerun the provisioner or create another account.

The API is read-only, uses the canonical order-summary projection, and excludes buyer names, emails, notes, registration answers and QR content. Universal calls cannot change orders, submit payments or select arbitrary origins. Access tokens last 300 seconds; refresh rotates; the server delegation expires after seven days and requires fresh consent. The UI's displayed connection expiry is advisory and may roll; it does not extend authorization.

## Submission discipline

Before the first Publish, verify source manifest/readback and existing app state. Publish exactly this app/version once, expose all five modules, then use the native Review form with the API and scenario links. Check any separately supplied contribution terms for fees or a paid subscription before acceptance. No paid commitment is authorized.

After Request review, inspect app status and the confirmation email before retrying. Complete the follow-up vendor/contact/category/logo form in the same review. Track request acceptance, approval and catalogue release separately. Confirm catalogue discovery and OAuth from another authorized account only after release; do not create a duplicate account or application for this check.

Public cost conclusion is documented in `../evidence/publisher-costs.json`. The secondary public directory explicitly reports $0 listing, while official MSA fees require an agreed Order and the account is Free. This is not a written Make guarantee; no support question was sent, per the owner's instruction.

## Submitted 2026-10-28

Publish, all five visible modules, one review request and its follow-up form were accepted. Case `2351677:2082001`, confirmation message `1a1822f6b03104a4`, form record `191861`. No optional partner application was selected and no fixed fee or paid subscription was presented. See `../evidence/submission-20261028.json`. Await feedback in this existing thread; do not resubmit. Approval and catalogue release are pending.

Review corrections were published from `1967445f97bb6a91b256672ec346eac06e9796c3`; the API documentation link was updated in the existing review and the technical response was sent as message `1a18258af1b4ad0b`. No new Review request or partner application was created.
