# Přetažení podkladu editorů - implementace 2026-10-20

Implementace [autoritativního plánu](../../plans/editor-image-drop-plan-2026-10-20.md) je lokální, bez commitu, push nebo produkčních operací.

## Výsledek

- `EditorFileDropRegion` přijímá právě jeden podporovaný soubor přes celé tělo editoru. Kontroluje aktivitu retained tabu a nadřazených route; pluginové listenery za modálem nesmějí spustit import.
- Vstupenka sdílí `upload(XFile)` mezi pickerem a dropem, vypíná vnořený drop v `ImageArea` a zachovává resolve, crop i dialog poměru stran. Rastr se ověřuje podle bajtů, velikost před čtením. Selhání zachová dosavadní podklad.
- Blueprint vlastní import a odebrání podkladu ve stavu tabu. Lišta předává operace hostu. Model a controller se mění po dokončené validaci/uploadu. Import blokuje save/discard/reload a další úpravy; pozdní výsledek po zániku draftu se nepoužije.
- Prototype nabízí lokální SVG a blokuje rastrový remote upload. Opravená původně obrácená podmínka menu tento zákaz vynucuje i v hostu. SVG ve vstupenkách ani HEIC se nepřidávají.
- Picker a importní dialog používají stejná omezení podporovaných souborů. Výchozí chování ostatních použití obecných komponent zůstává zachované.

## Ověření

Vždy nejvýše jeden Flutter task, testy s `--concurrency=1`.

```sh
fvm flutter test --concurrency=1 \
  test/components/shared/editor_file_drop_region_test.dart \
  test/components/ticket_layout/ticket_layout_cases.dart \
  test/components/blueprint/blueprint_editor_actions_cases.dart
```

Výsledek celých pojmenovaných sad: **100 prošlo, 3 selhaly**. Nové testy používají skutečný channel `desktop_drop`, nikoli přímé volání drop callbacku. Pokrývají počet/typ/složku, deaktivaci, vnořeného příjemce, souběh, chyby, limit před čtením, oprávnění, starý i prázdný podklad, poměr stran, menu, SVG, prototype a save/discard.

Závěrečný cílený běh stejných souborů s filtrem `plugin accepts|root modal|background drop imports|prototype SVG menu|raster host|seat plan resize`: **7/7 prošlo**.

Tři selhání jsou v existujících testech palet:

- `mobile palettes align left and scroll on one row`
- `palette paints its colors in Material 2 and 3, light and dark`
- `text and QR share the color picker and HEX entry`

Všechna tři se reprodukovala při diagnostickém běhu bez nového drop obalu a `AbsorbPointer` v editoru vstupenek. Původní implementace byla ihned obnovena. Opravy palet ani sourozeneckého repozitáře nejsou součástí této změny.

Cílený `fvm dart analyze` změněných Dart souborů: **bez chyb a varování**, zbývají informační linty v existujícím kódu. `git diff --check` pro dotčené soubory prošel.

## Webový smoke

`test/components/ticket_layout/editor_preview.dart` byl sestaven pomocí `fvm flutter build web --debug --target=test/components/ticket_layout/editor_preview.dart --no-wasm-dry-run --no-web-resources-cdn` do samostatného dočasného adresáře. Harness nově obsahuje také Blueprint fixture s injektovaným loaderem, uploaderem a lokálním save. Byly aktualizovány zastaralé fixture kontrakty `resolve` a autorizace dokumentových limitů v existujícím loopback serveru. Žádná produkční data ani backend se nepoužily.

Prohlížeč: samostatný Chrome for Testing, `--headless=new`, dočasný profil; obsluha přes `agent-browser` s explicitním prázdným configem. Protože syntetický JS `DataTransfer` nevytváří `FileSystemEntry` potřebné pluginem, ověření souborů použilo nativní `Input.dispatchDragEvent` přes CDP pouze do tohoto izolovaného prohlížeče.

Ověřeno:

- PNG přes postranní panel vstupenky, JPG přes plátno, vždy právě jeden upload; nahrazení podkladu a dialog změny poměru stran.
- Drop za dialogem nespustil upload. Odmítnutý upload poškozeného PNG vrátil 400, editor odemkl ovládání a ponechal původní podklad. Ovládání zoomu a režimu posunu zůstalo funkční.
- Blueprint: PNG přes panel a JPG přes plátno, zobrazení a dirty/save. Drop při deaktivovaném `TickerMode` a za modálem nezvýšil počet importů.
- Simulované selhání Blueprint uploaderu ponechalo původní podklad; následný lokální SVG import fungoval bez HTTP uploadu. Save přijal SVG jako baseline, discard další změny obnovil uložený podklad.
- Prototype: rastr nezměnil draft ani nespustil upload; menu obsahovalo pouze SVG. Drop do importního dialogu vybral soubor a až potvrzení ho vložilo do podkladu. Ověřen také drop při šířce 680 px.

Browser session a fixture server byly zastaveny. Snímky a běhové logy jsou dočasné pracovní artefakty, nejsou produkčním důkazem.

## Zbylé hranice

Přetažení z Finderu nebo jiného konkrétního OS správce souborů a externí drop na dotykových/mobile zařízeních nebyly ověřeny. Webový test používá nativní browser drag události v Chromiu. Jednoduchá SVG validace Blueprintu nadále může odmítnout XML deklaraci. Celá testová sada není zelená kvůli třem reprodukovaným chybám palet.
