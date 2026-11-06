# Wix artwork

`icon-1000.png` is a 1000x1000 export of the canonical
[`vstupenky-online-square.svg`](../../../assets/brand/vstupenky-online/vstupenky-online-square.svg),
approved on 2026-10-29. It is rendered directly with the canonical vector tool's
`resvg-py` renderer, preserving the approved navy/blue paths and outlined lettering.
The November 1 refresh replaces the earlier ticket vector from the WordPress
artwork page. Historical upload hashes remain in their original receipts.

Reproduce from the repository root without rebuilding unrelated brand exports:

```sh
uv run --with resvg-py python - <<'PY'
from pathlib import Path
import resvg_py
source = Path('assets/brand/vstupenky-online/vstupenky-online-square.svg')
Path('integrations/wix/media/icon-1000.png').write_bytes(
    resvg_py.svg_to_bytes(svg_string=source.read_text(), width=1000, height=1000))
PY
```

The public help/settings header and favicon are copied at build time directly
from the same canonical brand directory; there is no separate Wix logo drawing.
`dist/app-icon.png` exposes this canonical PNG for Wix's native URL importer when
browser-extension file upload is unavailable. Verify the saved native app icon
separately from local generation. Do not change a shared developer-company logo
or another app's identity as part of this app-specific update.

The current gallery source assets are `gallery-form-20261106.png` and
`gallery-seats-20261106.png`, both 1200x900. They show the actual current
standalone web client with a disposable, Czech Ples U Lípy example. They do
not show a Wix editor or an embedded host, and no order was submitted. Capture
provenance and hashes are in [the current evidence](../evidence/catalog-screenshots-20261106.json).

The earlier `gallery-published-desktop.png` and `gallery-summary.png` are retained
as historical evidence only. Their old checkout wording is obsolete; do not
reuse them for the current gallery. Their original Wix CDN readback is documented
in [the historical receipt](../evidence/gallery-20261025.json).

The current pair and central-appearance listing text were published and read back
on the public App Market on November 6, 2026. Native version 2.2 and pricing
were retained; the invalid optional historical promotional banner was removed.
See [the publication receipt](../evidence/market-listing-update-20261106.json).
