# Katalog vstupenky.online pro WordPress

Zdrojem identity je `assets/brand/vstupenky-online/`: schválený široký znak V bez hlavy, původní SVG wordmark, navy #19243b a blue #80bdf2. Nevytvářet alternativní logo. Náhled `preview.html` i renderer `artwork.html` fungují přímo přes `file://` bez serveru.

Export po načtení místních fontů a všech obrázků:

- `artwork.html?kind=banner`: viewport 1544x500 a 772x250.
- `artwork.html?kind=icon`: viewport 256x256 a 128x128.
- `artwork.html?kind=shot&shot=1` až `5`: viewport 1600x1100.

Výstup je PNG s DPR 1. Pět screenshotů zachovává význam a pořadí popisků readme české distribuce. Zdrojové snímky v `source/` zachycují skutečný český WordPress a lokální jednorázový formulář s ukázkovými daty. Výřezy jsou pouze oříznuté originály; text a barvy rozhraní se nepřekreslují. Marketingový text je mimo snímek. Mobilní náhledy jsou Chrome, nikoli Safari.

Publikovat pouze devět schválených katalogových PNG do SVN `/assets/`. Neměnit vydaný `trunk`, tag 1.0.4 ani původní technický seal. Historický důkaz původní grafické aktualizace je v `../evidence/catalog-refresh-20261106.json`. Globální Festapp Tickets obrázky zůstávají beze změny; `?product=festapp-tickets` zachovává předchozí renderer.

Central appearance cutover: screenshots1/2 now use actual1.0.5 captures with no local appearance control and an Open forms link. `source/provenance-1.0.5.txt` records the new capture. The final candidate asset manifest is `../evidence/catalog-assets-central-20261106.json`.
