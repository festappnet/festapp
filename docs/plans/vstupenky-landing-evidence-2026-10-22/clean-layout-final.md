# Clean-stage layout revision - final frozen media

Only layout-build assets and its manifest fields changed. Other media and root-owned hero-plan.json were preserved.

- Desktop 1140x828, mobile 820x824, both 26.066667 seconds. Both MP4s fully decode; JPG and WebP posters regenerated together.
- Actual capture starts with only a grouped stage rectangle and label, zero obstacles or columns. Native canvas fill and workspace screenshot samples are exactly RGB235,241,246 (#ebf1f6). Decoded H264 differs by at most 2 RGB levels at sampled points; no screenshot pixel replacement.
- Slow actual palette drag remains continuous, including the original source-column corridor. Seventeen native tables are created by held-Control pointer copies. Native 5x8 arc assembly is inserted, its actual curvature field changed to9 and then moved by pointer.
- Native Ctrl-copy duplicates initially at its source. Forty-four brief overlap-warning frames in accelerated copy cues were omitted editorially, with no recoloring or synthetic ghost. All782 final decoded frames scanned: zero warning-color candidates in the canvas ROI (2xdownscale, r>170,g<105,b<105, more than4pixels). This is a color-based frame audit, not a claim that original duplication never overlapped. See clean-layout-copy-cuts.json.
- Shared sibling fix: `lib/src/layout_editor/widgets/layout_style.dart`, only light `layoutWorkspaceColor` now follows host scaffoldBackgroundColor; dark remains#151B24. Callers inspected. `fvm flutter test --concurrency=1 test/layout_dark_preview_test.dart`:3/3PASS, including new host-theme/dark regression. Existing sibling dirty changes preserved; HEAD0b881853bd9071784fd66102a03a1606a81afa79. Full diff receipt is external, because the sibling file already had unrelated dirty changes.

Reproduction: automation/landing_capture/layout/clean-stage.md, clean_growth.py, encode_clean.py, remove_copy_collision_frames.py. Locale cs/en uses actual host and UI strings. Source takes, raw document checkpoints, exact frame cuts and encodes remain under `/Users/miakh/Downloads/festapp-landing-review-2026-10-22/layout-clean/`; final take `layout-clean-cs-1792683605`. Actual encoded proof images are in `encoded/{empty,drag-mid,first-table,arc-before,arc-after,finished}.png`. Hashes and RGB receipt: clean-layout-proof.json.

Owned capture browser and loopback server55907 closed after export. No backend, production, order, payment, email, deployment or publication operation performed in this revision.
