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
