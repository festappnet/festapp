# Blueprint touch integration - 2026-10-24

Canonical package source: `76e494e3f71fbd6b843d4494acab4bc1f25b26b5`,
based on current package main `4da60bb`. Festapp base: `271c77e70`.
The stale sibling checkout and its unrelated drafts were preserved. The change
was adapted to the current schema-2 object hosts instead of merging that checkout.

Completed taps share one core outline resolver and an 8 logical pixel radius.
Exact down/drag ownership, Shift toggles, row selection, blocked reservation
feedback, pending state, rollback and semantic actions remain in their owners.
Grid taps use one coordinate path with separate semantic activation. Empty
Select touch drags preserve selection while panning, and a second pointer cancels
editing/tap candidates through the remaining-finger sequence.

## Verification

- Package: 16 core resolver tests and 45 targeted widget tests passed; changed
  Dart files analyzed without diagnostics.
- Source archive gate passed: actual pub-selected core/wrapper files are byte
  equivalent to the canonical source, a clean unpacked consumer passed, 15 npm
  template scenes passed and the actual archived Flutter example booted offline.
  Demo smoke checks passed as well.
- Festapp: both mobile pan tests passed, including the real `BlueprintPlanEditor`
  host starting a touch above the transformed plan and selecting a near miss
  without changing its draft or undo history. Its Dart analyzer passed.
- Web client: 9 targeted tolerance/selector tests, immutable snapshot/lock/hash
  verification and the Vite build passed.
- Flutter resolves both packages from repository-relative vendor paths using the
  tracked repository override, without an absolute sibling checkout dependency.

## Distribution and production state

`vendor/blueprint/manifest.json` records the exact shared source commit, every
selected file hash and archive digests. The JS package/lock select only
`festapp-venue-layout-0.3.5-c75497ba4a27.tgz`; its predecessor remains in Git.
Both Dart distributions retain their prepared versions (wrapper 0.3.5/core 0.2.2).
These are verified locally generated source archives; a prior pub.dev/npm release
is not an integration prerequisite. The import owner and generated README now
state this explicitly. Registry publication and a production client deployment
are separate external effects, not implied by this source integration.

No database changes, production deployment or physical-device verification were
performed. Browser evidence covers the archived example, not the deployed app.
