# Timeline production release

ACTIVE on vstupenky.online, 0.20.98+582.

- PR https://github.com/festappnet/festapp/pull/294; canonical main f480d30b25937a7fb67112acc4556ca725dd7102; source 82aa7679c67bba7c87fab4fcce34a725b7f7c6ae.
- Production prod/festapptickets at 06572bfd4bb404743217af11cced3c5376cb26e0. Base main and previous production tip were fetched and unchanged before publication. Tenant drift, config matrix and legal checks passed. No other tenant release.
- Deployment https://github.com/festappnet/festapp/actions/runs/37211676694 succeeded. Its coherent-release verifier passed three consecutive probes. Independent public manifest and /admin identify 0.20.98+582; downloaded immutable bundle contains FeatureOrders.waveNow.
- Bundle main.dart.0.20.98-582.js, SHA-256 51622fc6d44de6ff05984667e0590ee03b4885ed8b3151ea9e2c15f421d92fa0. The additional local verifier produced no completion output, so the three-probe result above is attributed to the successful CI verifier.
- 1085 Flutter tests (one skip), web and automation suites passed. Targeted analysis has no errors or warnings. Real-widget synthetic screenshots cover mobile timeline and reduced-height editor with Storno. No production editing or database migration was performed.

Verified 2026-10-04T15:13:51.969383+00:00.
