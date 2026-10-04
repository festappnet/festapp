# Ticket fonts

The font IDs are a closed catalog in ticketGeneration.ts. Never fetch a font
from a client-supplied URL. All renderers use these same bundled bytes.

- font.ttf: existing Futura PT asset (unchanged).
- roboto-slab.ttf: historical wide-ticket source, https://github.com/google/fonts/raw/refs/heads/main/apache/robotoslab/RobotoSlab%5Bwght%5D.ttf
- roboto.ttf: historical named-ticket source, https://fonts.cdnfonts.com/s/12165/Roboto-Regular.woff
- russo-one.ttf: existing av2025 named-ticket source, https://fonts.cdnfonts.com/s/15876/RussoOne-Regular.woff

The two WOFF containers were losslessly unpacked to sfnt with fontTools TTFont
(`flavor=None`) for Flutter and pdf-lib. Outlines and metrics were not modified.

Roboto Slab is pinned to its default 400 weight using fontTools varLib.instancer,
so browser, Flutter and PDF engines receive a static Regular face. Roboto/Roboto
Slab use Apache 2.0 (Roboto-LICENSE.txt); Russo One uses OFL (RussoOne-OFL.txt).
