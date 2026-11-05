# Combined order-focus and HTML release - 2026-11-02

Live: https://vstupenky.online, **0.20.484+990**.

- PR #696: order focus, canonical detail/Transactions and static e-mail field; explicit user admin-merge approval, all seven CI checks passed.
- PR #697: canonical pasted HTML formatting; other session merged it with all seven CI checks passed. Release waited for this merge as requested.
- Final canonical main: `61bc106d49ea929c6f48ba7da09bc0d2abad3741`.
- Published tenant: `prod/festapptickets`, `eb273a07a6d57f860a3e7dc7f9aa8d96047fcd62`.
- Previous prod `dacd34283692ecde7d3065f73ca60bc2b5007ff6` remains an ancestor.
- The earlier candidate `2555d6a3b8823e945f57daabd2ca43c2bcefa58d` was paused before build/push/upload and never deployed.
- Fresh combined-main overlay, canonical drift, ancestry, manifest contract, local Flutter/web-client build and web-build verifier passed.
- Direct Pages deployment: https://f0282c63.vstupenkyonline.pages.dev.
- Live version/build/legal verification passed three consecutive coherent probes for 0.20.484+990; remote main/prod refs independently confirmed.
- No backend/provider operations or existing HTML data repairs were performed.

Validation receipts for our UI changes: `docs/plans/evidence/order-detail-focus/`. PR #697 records 35 focused Flutter tests, 12 JS tests and Chromium security checks passed; its broader forms run had one unrelated settings snapshot failure alongside 170 passing tests. Required release/CI gates passed.

Local review HTTP port 58631 and Supabase project `festapp-order-detail-20261101` (ports 58621/58622) are stopped. Normal Supabase backup was retained; other projects and stored data were untouched. Primary independently confirmed none of these ports listens.

Logs: `/tmp/festapptickets-order-focus-html-build.log`, `/tmp/festapptickets-order-focus-html-deploy.log`, `/tmp/festapp-order-detail-local-stop.log`.
Worktree: `/Users/miakh/source/festapp-festapptickets-order-focus-html-release-20261102`.
