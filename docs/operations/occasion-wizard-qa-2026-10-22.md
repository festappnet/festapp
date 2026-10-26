# Occasion wizard QA - 2026-10-22

Source before fixes: `0859506d613b31602190e866a6dd6b8d8d6dee6c`.
Production initially matched `0.20.332+826`; main had no open pull requests.

Two complete browser journeys used the real Flutter application, authentication,
RPCs and blueprint editor against the isolated local Supabase tenant. Browser
automation used a dedicated headless session; no customer records were changed.

## Completed journeys

- Free registration: name, dates, appearance and font, tickets disabled, zero-price
  product, immediate registration, server-rendered confirmation preview, no plan,
  review and creation. Exactly one hidden occasion was created (local ID 129),
  with an open form and no bank account or blueprint.
- Paid tickets: appearance and Russo One font, Cinema ticket template, price
  100 CZK, confirmed synthetic bank account, closed presale, server confirmation
  preview, Bus blueprint with 45 seats, review and double-click on creation.
  Exactly one occasion resulted (local ID 135, blueprint 41, 45 stored spots).

## Edge cases exercised

Empty name; end before start; past scheduled opening; negative product price;
missing bank account; invalid reply email and preview recovery; empty blueprint;
ticket off/on; backtracking; reload and draft resume; 390px mobile navigation and
font selection; confirmation required before creation; double submission.
The editor's gallery showed the 15 approved plans in their approved order.

## Fixes from this audit

1. Deferred ticket gallery loading until after mounting. Its synchronous draft
   flush could notify the parent during build and leave autosave permanently
   pending. Retried loading follows the same lifecycle.
2. Automatic form links now normalize punctuation to underscores. Mixed hyphens
   and underscores previously produced a suggestion rejected by form validation.
   Migration `20261022190000` carries the canonical RPC change.
3. Active products with negative, nonnumeric or nonfinite prices block advance
   and review with an explicit validation message. Hidden/inactive configuration
   remains dormant.
4. The selected font uses an unpadded, single-line dropdown representation so
   its name remains legible on mobile.

Affected UI behavior was exercised again after fixes. Regression coverage includes
parent-save notifications during gallery mounting, retry and template selection,
active/inactive price validation, font selection at 1x/2x text scale, and SQL link
normalization including punctuation-only and truncated names.

## Boundaries

These complete journeys ran on disposable local data. Production verification
checks release identity and deployment coherence, rather than creating test events
in the live tenant. Browser OneSignal callbacks were stubbed. The editor's font
transport used an existing local font fixture; its missing initial local endpoint
configuration was repaired without changing production settings. No real emails,
invitations, payments, bank synchronization, Stripe onboarding or paid checkout
were performed.

## Two additional journeys

Follow-up source: `fd5a7d47036a3db57b1c43b10ab13e3f4493bf4c` plus
the form and QR corrections accompanying this report.

- Free registration with seats, without tickets: custom solid color, added
  required participant-name field, scheduled opening with countdown, informal
  server-rendered email, independently copied Bus plan and explicit product
  replacement. Reload/resume retained the review. Completed local occasion 187
  has a new blueprint 62 with 45 seats, the required field, and no ticket feature.
- Copied paid occasion: enabled email-template copying, boarding-pass ticket,
  contrast appearance, removed copied seating, two products at 200/50 CZK,
  immediate presale, a future price of 81 CZK for the newly added Student product,
  sequential variable symbols starting at 5000, two-day deadline, reminders off.
  Reload/resume and creation completed. Local occasion 190 has no blueprint,
  exactly two new products (210/211), and the canonical planned change targets
  product 211. Its current price remains 50 CZK until the scheduled change.

The additional journeys exposed and reproduced these defects:

- Independently selected plans copied geometry without their source text paths.
  Finalization now resolves the authorized resource origin from the selected
  stored blueprint. Migration `20261022200000` shipped in `0.20.334+828`.
- New form products/types had no stable draft identity, so price waves could
  retain a null product reference. Serialization assigns stable negative IDs,
  preserves existing IDs and avoids reusing removed identities after reload.
- New products could have an empty currency when no draft bank was available.
  Defaults now use the available/group currency or the existing CZK fallback.
- Disabling seat selection inside the form left the wizard's copied-plan intent
  active, restoring selection after reload. An explicit form save now clears it.
- Decimal millimeter QR geometry acquired unequal width/height from floating
  point subtraction, so the server rejected the boarding-pass template. QR
  decoding now uses the editor's existing binary-exact resize precision; styled
  draft templates use the same normalized boxes. Genuine nonsquare QR remains
  nonsquare, and server validation remains enforced.

Both journeys completed through actual UI controls after the relevant fixes.
Targeted regression coverage exercises independent plan sources and access
boundaries, local product identity/currency and price-wave references, and repeated
QR JSON roundtrips. The same local/external-service boundaries above apply.
