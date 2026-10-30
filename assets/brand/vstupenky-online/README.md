# vstupenky.online

The selected identity is the wide ticket / V mark **without the head**, based on `concepts/selected-wide-no-head.png`, approved as the direction on 2026-10-29. Earlier exploratory images remain in `concepts/` for provenance.

## Canonical vector assets

- `vstupenky-online-square.svg` and `vstupenky-online-square-dark.svg`: complete square logo, with white/navy background.
- `vstupenky-online-transparent.svg` and `vstupenky-online-transparent-dark.svg`: same composition without background, for light/dark surfaces respectively.
- `vstupenky-online-symbol.svg` and `vstupenky-online-symbol-dark.svg`: tightly framed standalone symbol without background.
- `vstupenky-online-icon.svg` and `vstupenky-online-icon-dark.svg`: square symbol-only avatars.
- `vstupenky-online-wordmark.svg` and `vstupenky-online-wordmark-dark.svg`: tightly framed original stacked lettering, without the ticket.

Every SVG uses actual paths, including the lettering. There are no embedded raster images, external references, font dependencies, filters or gradients. Navy is `#19243b`; blue is `#80bdf2`. Light/dark versions use identical paths with inverted foreground/background colors. PNG exports include 1024px masters, 300px/400px company avatars and smaller symbol-only icons.

## Reconstruction and review

The ticket geometry is mapped from the selected image, with mirrored halves, clean circular side notches and a mathematically straight triangular center. The lettering is outlined from Roboto Bold with -0.035em tracking, as explicitly requested from the archived landing preview `docs/previews/vstupenky-rough-print-2026-10-28/index.html?scenes=revised-crowd-medium&style=original` at commit `5629de3a1`. The font is preserved in `source/Roboto-Bold.ttf`; runtime assets have no font dependency. This supersedes the generated image lettering. This is a vector reconstruction of a raster concept, not recovery of a pre-existing vector original. Generated highlights, gradients and texture are deliberately removed. `vector-verification.json` records the vector contract. Each lettering row is one compound path created by a true boolean union of all glyph outlines; overlapping internal boundaries are removed and counters are preserved. Glyph coordinates are flattened into the logo coordinate system. Animation must stroke these unified paths, not separately redrawn letters.

Rebuild with `uv run assets/brand/vstupenky-online/tools/build_vectors.py`. The script uses temporary isolated tooling and the checked-in source reference. It does not modify app code. `preview.html` works directly from disk and includes a source/vector comparison. The selected tenant configuration consumes dedicated `assets/icons/vstupenky*.svg` copies. Festapp artwork remains independent. `vstupenky-online-header*.svg` is the horizontal lockup for navigation; `web-icons/` contains install/favicon exports. Production publication is separate from these source changes.

## Loading animation

`vstupenky-online-loading.svg` and `vstupenky-online-loading-dark.svg` implement the 4.4-second whole-signature outline/fill reveal, played once, followed by a gentle 2.2-second opacity pulse (76-100%). `source/loading-timeline.json` is the single timing source. Rebuilding emits both CSS/SVG animations and `lib/widgets/brand_loading_paths.dart`; Flutter uses these exact paths in a native painter. The unioned word rows are stroked as whole contours. Reduced motion displays the full static logo, and application readiness never waits for a cycle to finish.
