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

`gallery-published-desktop.png` and `gallery-summary.png` are unedited native
1200x900 screenshots of the actual published Wix Studio host. The guarded local
fixture uses Czech sample labels, a fictional buyer and reserved example.com;
it explicitly states that no actual payment takes place. No production buyer,
payment receipt or ticket QR is included. Both images are saved in Wix and were
verified after reload; hashes and original CDN URLs are in
[gallery evidence](../evidence/gallery-20261025.json). The desktop image also
replaces the old development thumbnail in Add Elements.
