# Workspace margin touch panning - 2026-10-24

In navigation mode, single-finger movement beginning outside the plan rectangle now follows raw
pointer movement after the normal touch threshold. It does not depend on a
ScaleGestureRecognizer winning against an ancestor. Camera bounds, the existing
pinch path and all document/business data remain unchanged. The pointer and
scale paths cannot apply the same movement twice; a second pointer transfers
navigation to the existing scale handler.

Canonical package source: `203b9219db34e4af8d47e9b10b85a0a673118d96` in
`festappnet/venue_seat_picker`. Import uses the verified 0.3.7 wrapper / 0.2.2 core
and 0.3.6 npm distributions, with their receipt and per-file hashes. The existing
host npm hit-tolerance patch is retained against the selected npm version.

Evidence:

- Package margin test failed before the change when an ancestor won the gesture
  arena. It passes in both axes with exact camera displacement.
- Package navigation checks: 12 passed, then 5 passed after adding pinch/cancel
  handoff coverage; unchanged viewport/editor tests were not repeated.
- Real Festapp reservation host test: failed with the previous dependency,
  passes with the imported dependency; preserves the selected seat.
- Host margin, mobile navigation and toolbar checks: 12 passed together.
- Pub/npm archive consumers, 15 archived browser scenes and demo checks passed.
- Host artifact/lock/hash contract and npm hit-tolerance/adapter tests passed.
- Targeted Dart analysis passed without issues.

The ancestor-arbitration failure is a deterministic robustness reproducer.
The original physical Android device has not been exercised, and its exact
cause is not established. No backend, payment, inventory or email writes are
part of this UI release.
