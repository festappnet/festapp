# PR747 measurement completion

## Scope

Keep sale opening (`FormModel.startTime`, availability and countdown) separate
from analytics `form_start` (a visitor beginning to fill the available form).
Retain the existing consent/policy gates, one FormDataLayer event owner and the
two supported transports. Work in the isolated PR worktree; do not modify the
other worktree's unfinished changes or deploy production.

## Implementation

1. Route meaningful visitor interaction through one optional renderer/widget
   callback. Native input/change and explicit custom answer/ticket/seat actions
   may invoke it; email blur, initialization, restored drafts and background
   session updates must not.
2. Keep `FormDataLayer.started()` as the only event and deduplication owner.
   Preserve once-per-form-load behavior and no replay of pre-consent activity.
3. Document the difference from scheduled sale opening and GA4's automatic
   session-level event. Keep shared contracts and generated artifacts canonical;
   avoid additional transport abstractions or unrelated cleanup.
4. Add integration regression coverage for real renderer/widget wiring,
   including untouched email blur, native input, custom actions, restoration,
   repeated input and consent gating.

## Verification

Use the normal web-client tests plus the affected committed browser gate in an
isolated muted session operated by the browser subagent. Reuse prior passing
browser evidence for unchanged boundaries. No Flutter, live GA4 or real orders
are necessary for this client interaction correction. Source publication, if
performed, additionally requires the repository's affected canonical CI lanes.

## Completion

Implemented on `fix/pr747-form-interaction`, based on PR head `c020f8d52`.
The renderer owns native input/change detection and passes the same optional
callback through nested widgets. Radio clear, ticket add/remove, date selection
and blueprint seat/quantity intent notify the existing event gate. Schedule
opening and countdown behavior are unchanged. Duplicate GA4 setup prose in the
runtime README now links to the integration guide.

Verification on the final application sources:

- `pnpm test`: 994 passed, 30 skipped, 0 failed. Includes a real selector callback
  integration test for silent loading/presentation updates, selection attempts
  before reservation completion and quantity intent.
- `pnpm run test:form-interaction-browser`: passed in isolated headless Chrome.
  Uses the real renderer, FormSession, widgets and FormDataLayer with a local
  consent/transport stub. Covers blank email blur, native typing, repeated input,
  ticket add/remove, nested radio clear, calendar selection, silent date/draft
  restoration, synthetic events and consent/no replay.
- `pnpm run test:measurement-browser`: all four scenario groups passed.

The new browser regression is part of the canonical web-startup shell gate.
Live GA4 receipt, real orders, production deployment and source publication are
outside this local implementation. No changes to the other worktree.
