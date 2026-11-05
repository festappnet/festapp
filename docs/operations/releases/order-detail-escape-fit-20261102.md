# Order detail Escape and dense map release - 2026-11-02

Live https://vstupenky.online, **0.20.486+992**.

- PR #700 administratively merged following explicit user approval; all five required CI checks passed for head `47911064a17b9292b20d6d31546c9aef3a7269a8`.
- Canonical main: `d5f286c8755e60e6cd95a2caaff020313d3f6a96`.
- Selected tenant `prod/festapptickets`: `b706d881fef938f6697e7537dfdca4a82c8a9a14`.
- Previous production `49f901023596e523e03a5bd16c4fd0edb1ebd61f` retained as ancestor.
- Canonical drift/manifest checks, local Flutter/web build and build verifier passed.
- Direct Pages release: https://5de5c541.vstupenkyonline.pages.dev.
- Live version/build/legal verification passed three consecutive coherent probes. Primary independently checked published refs and deployment receipt.

The swallowed outside-focus Escape reproducer failed before correction. The panel now follows blueprint dismissal ownership with early outside-focus handling and enclosing-route dialog guards, including stale focus. Focused inline children and active grid editing retain local Escape handling. Dense map fit targets order seats with at most 1.6x overview zoom; selection does not move the camera and Whole hall restores overview.

Validation: 72 targeted tests passed, then all 16 route tests passed after the final stale-focus guard. Includes production-shaped nested navigation, outside Escape consumers, root dialogs retaining focus on callers, viewport-scale cap/reset and small/dense plan selection. Targeted Dart analysis has no errors or warnings.

Logs: `/tmp/festapptickets-escape-fit-build.log`, `/tmp/festapptickets-escape-fit-deploy.log`, `/tmp/order-escape-red.log`, `/tmp/order-escape-fit-final-tests.log`, `/tmp/order-escape-final-route-tests.log`, `/tmp/order-escape-final-analyze.log`.
Worktree: `/Users/miakh/source/festapp-festapptickets-order-escape-fit-release-20261102`.

No backend operations or other tenant releases. Local review ports 58631/58621/58622 remain off, independently checked after release.
