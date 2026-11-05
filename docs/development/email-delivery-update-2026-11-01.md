# Email delivery platform update

Canonical content: `content/platform-updates/email-delivery-control/`.
The Czech article is the requested deliverable; English is included for the
existing bilingual publishing contract. The source remains a draft, without a
publication timestamp. No deployment or customer notification is part of this
content change.

## Editorial checks

An independent dramaturg reviewed the order of information: locate the order,
read its symbol, distinguish messages, choose an action, verify the outcome.
An independent factual critic checked the source implementation and identified
the repair entry point: the red envelope beside the order status. The separate
E-mail column opens the explanation and history. Both language versions use
these distinct paths.

The article distinguishes provider acceptance, recipient-server delivery and
recorded opens/clicks. It does not equate any of these with a customer reading
an inbox message. Save-only, queued requests, uncertain attempts, blocked
recipients and state-dependent resend actions are described separately.
Per the owner's direction, the public copy omits sample-data disclosures and
editorial process notes. Synthetic capture provenance belongs in the companion
`email-update-captures-2026-11-01.json`, not in the article.

Source references:

- `lib/components/email_delivery/email_delivery_indicator.dart`
- `lib/components/email_delivery/email_delivery_history.dart`
- `lib/components/email_delivery/order_email_issue.dart`
- `lib/components/eshop/views/order_state_cell.dart`
- `lib/components/eshop/views/order_email_repair_dialog.dart`
- `assets/translations/cs.json`, `EmailDelivery`

## Preview and publication

Use the canonical `automation/release/platform_updates/preview.mjs` with a
private copy of this content directory. Set only that copy to `published` with
the current UTC timestamp, as documented in `content/platform-updates/README.md`.
The generated HTML embeds screenshots and CSS and opens directly from disk.
The copy is for preview only and must never become the production content root.

Article screenshots open at full resolution in a separate tab. The preview
copies those originals beside its HTML and embeds configured brand logos, so
neither image viewing nor the header needs a local server.

Before publication, verify the described interface on the selected live tenant,
set the actual publication timestamp in canonical metadata and use the normal
authorized web release. A local screenshot or passing renderer test does not
establish current live availability.

## Validation receipt

- All five tests in `automation/tests/platform_updates.test.mjs` passed,
  including the assertion for safe full-size screenshot links.
- The mechanical design detector found no issues in the changed article renderer.
- A headless browser checked the canonical generated Czech preview at 1280 and
  390 CSS pixels. All six images (three screenshots and three brand-logo uses)
  loaded, and document width equalled viewport width at both sizes.
- Clicking the orders screenshot opened its actual 1968 px local PNG in a
  separate tab. History and repair originals are 1200 px wide.
- The initially broken preview logo URLs were corrected by embedding the
  configured SVGs; the browser rechecked the final result.
- Owned browser, Flutter server and disposable backend were stopped. No live
  delivery, production mutation or publication was performed.

Local review artifact:
`.private/email-update-preview/cs-email-delivery-control.html`.

## Full state reference and order detail follow-up

The owner's follow-up requested every state. Both article languages now include
all 27 exact `EmailDelivery.state` labels, with distinct explanations for message
progress, provider/attempt events and tracking/operational diagnostics. `done`
means completed follow-up processing, not a completed sending attempt.

Astra (medium reasoning) prepared three static interactive order-detail designs
at `docs/prototypes/order-detail-prototype-2026-11-01.html`, supported by the UX
and technical plans under `docs/plans/order-detail-*2026-11-01.md`.
The user has not selected an implementation. No application behavior changed.
