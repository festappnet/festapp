# Hidden note, overdue payment and Wix help release - 2026-11-02

Live https://vstupenky.online, **0.20.487+993**.

- PR #701 administratively merged following user approval; all five required checks passed for final head `8907d6f532c05560682da28198981f83d90be13c`.
- User explicitly requested all latest main changes. New main commit `4cc8fe4de` (public Wix installation help) was inspected and merged into PR before final CI; final canonical main `522809b5cca7c34b627d1d55318c19e0be1abcfe` includes both.
- Only tenant `prod/festapptickets` published: `1fceb696972d7c594cfc30732c8bb7a61dfe86f6`.
- Previous production `b706d881fef938f6697e7537dfdca4a82c8a9a14` retained as ancestor.
- Canonical drift/manifest checks, local Flutter/web-client build and build verifier passed.
- Direct Pages release: https://6228b01d.vstupenkyonline.pages.dev.
- Live version/build/legal verifier passed three consecutive coherent probes. Primary independently confirmed remote refs and deployment receipt.

Hidden note now uses a standard outlined directly editable multiline input with one fixed floating label; global Save/Discard remains the draft owner. Server-owned overdue state is shown consistently in overview and Payments, with canonical amount/due date and no local recalculation. Existing Transactions content and N/A semantics retained.

Validation: 78 targeted tests passed, then 61 locale-corrected presentation/summary tests passed. Targeted analyzer has no errors/warnings. Native 400px/1.4x text-scale light/dark captures reviewed by Astra Medium and primary; Czech formatting confirmed. Evidence under docs/plans/evidence/order-note-overdue-20261102/.

Wix build artifacts verified: generated Czech guide, search entry, sitemap entry, CSP manifest and worker routing. Live guide `/napoveda/wix/`, search asset and sitemap GETs returned 200 with expected Wix content. The selected tenant serves Czech; English guide remains in canonical source for the existing preview flow.

Logs: `/tmp/festapptickets-note-overdue-build.log`, `/tmp/festapptickets-note-overdue-deploy.log`, `/tmp/order-note-overdue-tests.log`, `/tmp/order-note-overdue-locale-tests.log`, `/tmp/order-note-overdue-analyze.log`.
Worktree: `/Users/miakh/source/festapp-festapptickets-note-overdue-release-20261102`.

No backend/provider operations or other tenant releases. Local review ports 58631/58621/58622 remain stopped, independently checked after deployment.
