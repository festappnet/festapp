# MapLibre jako výchozí offline renderer s vypnutelným legacy fallbackem

Date: 2026-08-01
Status: Ready for execution
Verification: standard

## Outcome

Nativní Android/iOS aplikace používá pro nakonfigurovaný offline mapový podklad
ve výchozím stavu GPU-akcelerovaný MapLibre renderer z balíčku `maplibre` od
Joschy Eckerta. Správce occasion jej může v nastavení mapové feature explicitně
vypnout; potom se stejná mapa vykreslí dnešním `flutter_map` +
`vector_map_tiles` legacy rendererem.

Nový renderer zachová celé současné chování mapy: lokální vektorový podklad a
popisky, místa a jejich ikony/názvy/popupy, stavové barvy WC, filtrování typů,
skupinové trasy a jejich směrové značení, aktuální polohu, deep-link a pohyb
kamery, editaci polohy, kreslení/import GPX tras, atribuci a online/offline
přepínač tam, kde není `forceOfflineMap`.

Než se začne plná migrace, vznikne omezený nativní prototyp nad skutečnými CSM
Ostrava assety. Prototyp se otevře v iOS Simulatoru k vizuálnímu schválení a
zároveň prokáže na iOS i Androidu, že lokální PMTiles, styl, sprity, glyphy a
cold-start v letadlovém režimu fungují bez síťového dotazu. Plná implementace
nesmí pokračovat, pokud tato brána neprojde.

## Scope

### In scope

- Výběr a připnutí moderního balíčku `maplibre`, s `maplibre_gl` pouze jako
  předem popsanou technickou alternativou při neúspěchu feasibility brány.
- Nativní prototyp skutečného ostravského stylu a lokálního vektorového balíku.
- PMTiles varianta současného CSM tilesetu a úplný offline balík včetně glyphů,
  spritů, checksumů a manifestu; MBTiles zůstane pro legacy renderer.
- Renderer-neutrální datový a kamerový kontrakt mezi `MapPage` a dvěma povrchy.
- MapLibre implementace všech dnešních vrstev, interakcí a editačních toků.
- Enum v JSON konfiguraci mapové feature a přepínač v Occasion Settings.
- Kompatibilní migrace existujících occasion, postupný rollout, měření na
  slabším fyzickém Androidu a okamžitý konfigurační rollback na legacy.

### Out of scope

- Nahrazení současné online raster mapy nebo webové/PWA mapy MapLibre; nový
  renderer se v této etapě týká pouze nativní offline větve.
- Změna formátu míst, tras, `PathNode` CSV/GPX nebo databázových tabulek.
- Odstranění legacy rendereru a jeho dependencies; fallback je výslovný
  produktový požadavek, ne dočasný migrační dluh.
- Redesign mapy, značek, filtrů či popupů.
- Produkční změna occasion, upload assetů, release, commit nebo push bez
  samostatné autorizace.

## Constraints

- Platí `docs/architecture/ai_context.md` a projektová pravidla; jde o změnu
  širokého sdíleného chování a nativních dependencies, proto `standard`.
- Flutter je v repozitáři 3.44.x; zvolený `maplibre 0.3.5` vyžaduje Flutter
  `>=3.44.0` a Dart `^3.12.0`. Přidání dependency prošlo read-only
  `fvm dart pub add --dry-run maplibre`; solver nehlásí konflikt.
- Android minSdk 23 a iOS deployment target 15.6 se nesnižují.
- Mapa musí být skutečně `force offline`: úspěšný test se provede po stažení,
  ukončení aplikace a cold-startu bez konektivity a bez síťově dostupných
  stylů, tiles, spritů či glyphů.
- Aktuální CSM styl používá font stacky `noto_sans_regular` a
  `noto_sans_bold` a vzdálenou glyph URL. MapLibre popisky proto nejsou offline,
  dokud balík neobsahuje potřebné `{fontstack}/{range}.pbf` soubory a lokálně
  přepsaný styl.
- `maplibre` dokumentuje lokální PMTiles, nikoli MBTiles. PMTiles je primární
  MapLibre kontrakt; existující MBTiles zůstává samostatným legacy kontraktem.
- `maplibre` má na Androidu `androidTextureMode=true` jako default, přestože
  jeho API upozorňuje na významný výkonnostní postih. Produkční volba režimu se
  určí měřením a nesmí implicitně zůstat na tomto defaultu.
- Simulátor slouží k vizuální ukázce a funkčnímu průchodu, ne jako důkaz výkonu.
  Výkonový gate vyžaduje profile/release build na fyzickém telefonu.
- Pracovní strom obsahuje uživatelské a předchozí mapové změny. Realizace smí
  upravovat jen související soubory a nesmí je zahodit ani použít `git add -A`.

## Current-state evidence

| Claim | Evidence | Consequence |
|---|---|---|
| Nativní offline větev dnes používá Dart/Flutter renderer | `lib/components/map/map_page.dart:_buildOfflineMap` skládá `fm.FlutterMap`, `vmt.VectorTileLayer` a `MbTilesVectorTileProvider` | MapLibre musí být druhý povrch pod stejnou aplikační logikou, nikoli další větev celé stránky. |
| Online, offline a aplikační vrstvy jsou dnes propojené typy `flutter_map` | `MapPage._mapOptions`, `_buildCommonMapLayers`, `_polylines`, `_markers` a `MapPageHelper.loadGroupPolylines` | Nejprve vzniknou renderer-neutrální scene/camera modely; jinak by plná funkčnost musela být duplikovaná. |
| Mapa obsahuje víc než podklad | `MapPage` obsluhuje typové filtry, group paths, popupy, current location, deep links, editaci polohy, kreslení, undo, segmenty a GPX import | Akceptace se řídí capability matrix, ne pouze screenshotem podkladu. |
| Běžný stav CSM má přibližně 189 mapových míst | evidence a manifest předchozího plánu `docs/plans/2026-08-01_csmostrava_offline_map_assets_plan.md` | Všechny body ve Flutter `WidgetLayer` by mohly přesunout bottleneck; běžné body se vykreslí nativní GeoJSON/Symbol vrstvou. |
| Trasy dnes generují hlavní čáru, trojúhelníky a hatch linky | `lib/components/map/map_page_helper.dart:loadGroupPolylines` | Renderer-neutrální geometrie musí zachovat i směrové značení; MapLibre ji pošle do nativní GeoJSON/Line vrstvy. |
| Popup a editace používají `MapMarkerWithText`, který dědí z `fm.Marker` | `lib/components/map/map_marker_with_text.dart` a `MapPage.showPopupOrDialogFor` | Aplikační marker/popup stav se oddělí od konkrétního marker widgetu. |
| Offline konfigurace je součástí JSON feature | `lib/components/features/map_feature.dart:MapLayer` a `FeatureConstants` | Renderer lze přidat bez SQL schema migrace, ale živá JSON data potřebují řízený compatibility rollout. |
| Současný downloader drží celý soubor v `List<int>` a zapisuje rovnou do cíle | `lib/components/map/offline_map_helper.dart:getOrDownloadFile` | Vícesouborový MapLibre bundle potřebuje stream do dočasného souboru, checksum a atomické zveřejnění; neúplný download nesmí být považován za cache hit. |
| Styl má online source, sprite a glyph URL | `automation/offline-map/style/style.json:sources`, `sprite`, `glyphs` | Runtime vytvoří lokální style JSON s PMTiles, sprite a glyph URI; vzdálená URL nesmí zůstat v offline aktivaci. |
| Moderní balíček nabízí eventy, projekce, hit testing, GeoJSON update, images a user location | `maplibre 0.3.5`: `MapController`, `StyleController`, `WidgetLayer`; [dokumentace balíčku](https://flutter-maplibre.pages.dev/docs/) | Potřebné stavební bloky existují, ale parity musí potvrdit prototyp a integrační testy. |
| Moderní balíček používá přímé JNI/FFI a nativní MapLibre SDK | [MapLibre Flutter v0.3 announcement](https://maplibre.org/news/2025-10-04-maplibre-newsletter-september-2025/) | Je preferovaný před starším method-channel forkem pro nový povrch. |
| PMTiles je podporovaný nativně na iOS/Androidu a v moderním Flutter balíčku | [MapLibre iOS PMTiles dokumentace](https://maplibre.org/maplibre-native/ios/latest/documentation/maplibre/) a `flutter-maplibre/website/docs/sources.md` | CSM build vytvoří vedle MBTiles také lokální PMTiles; použití se ověří na obou platformách. |
| Přímý MBTiles postup je komunitně doložený u staršího forku | [`flutter-maplibre-gl` issue #318](https://github.com/maplibre/flutter-maplibre-gl/issues/318) | `maplibre_gl` je záložní feasibility kandidát, ne runtime fallback ani první volba. |
| `maplibre 0.3.5` má otevřený crash OfflineManageru při glyph URL | [`flutter-maplibre` issue #535](https://github.com/josxha/flutter-maplibre/issues/535) | Nepoužije se `OfflineManager.downloadRegion`; Festapp stáhne předem sestavený bundle vlastním správcem. |
| Runtime přidané tiled sources na iOS zahazují zoom/tile options | [`flutter-maplibre` issue #546](https://github.com/josxha/flutter-maplibre/issues/546) | PMTiles source bude deklarovaný v připraveném style JSON/TileJSON, ne přidávaný přes postižené `StyleController.addSource(tiles:)`. |
| Widget-to-image může být na iOS rozmazaný | [`flutter-maplibre` issue #499](https://github.com/josxha/flutter-maplibre/issues/499) | Ikony se rasterizují explicitně v cílovém device pixel ratio a vizuálně porovnají; není dovoleno problém ignorovat. |

### Reprezentativní tok

Occasion JSON vybere `offlineMapRenderer=maplibre` →
`OfflineMapBundleManager` stáhne a atomicky ověří manifest, PMTiles, style,
sprity a glyphy → `MapLibreStyleAssembler` přepíše pouze povolené URI na
prototypem potvrzené lokální resource URI → `MapPage` vytvoří
renderer-neutrální `MapScene` →
`MapRendererHost` zvolí `MapLibreMapSurface` → podklad, body a trasy renderuje
MapLibre Native → tap/hit-test vrátí place id → existující aplikační logika
otevře Flutter popup nebo editační tok. Při `offlineMapRenderer=legacy` tentýž
scene/controller kontrakt obslouží dnešní `FlutterMapSurface` a MBTiles.

## Target architecture and invariants

### Canonical owner and contract

- **Volba rendereru:** `OfflineMapRenderer` v `MapLayer`; hodnoty `maplibre` a
  `legacy`. Neznámá hodnota je konfigurační chyba, nikoli tichý fallback.
- **Host povrchu:** nový `MapRendererHost` je jediný bod, který smí podle
  konfigurace zvolit `MapLibreMapSurface` nebo `LegacyMapSurface`.
- **Aplikační vstup:** renderer-neutrální `MapScene` obsahuje mapová místa,
  zobrazené place ids, trasy/geometrii, focus/edit/draw stav a atribuci.
- **Ovládání:** `MapViewportController` poskytuje `animateTo`, `fitCoordinates`,
  aktuální center/zoom a převod bod ↔ obrazovka; `MapPage` nevolá konkrétní
  controller balíčku.
- **Offline assety:** `OfflineMapBundleManager` vlastní download, checksum,
  atomické uložení, verzi a lokální cesty. Vstupem je immutable HTTPS manifest;
  výstupem je pouze kompletně ověřený bundle.
- **MapLibre styl:** `MapLibreStyleAssembler` přijme ověřený bundle a vrátí raw
  style JSON, kde source, sprite a glyph odkazy míří výhradně do bundle.
- **MapLibre dynamika:** body a trasy jsou GeoJSON sources + nativní
  Symbol/Line layers. Flutter widget overlay se používá jen pro aktivní popup,
  ovládací prvky a případný jednotlivý editovaný marker.

### Invariants

1. Na nativní platformě s kompletním offline nastavením je `maplibre` výchozí
   hodnota; vypnutí v Occasion Settings uloží explicitní `legacy`.
2. Každá před vydáním existující occasion s offline mapou dostane explicitní
   `legacy`, než klient začne interpretovat chybějící hodnotu jako `maplibre`.
   Tím se žádná stará occasion nepřepne nepozorovaně.
3. Renderer se vybírá právě jednou v `MapRendererHost`; žádná business logika,
   filtr ani editace se podle rendereru neduplikuje.
4. `legacy` a `maplibre` zobrazují stejnou množinu míst, názvů, barev, tras a
   stavů při stejném `MapScene`.
5. MapLibre offline cold-start neprovede žádný HTTP(S) požadavek na tiles,
   style, sprite ani glyph. Chybějící či chybný bundle ukáže retry/error stav;
   nesmí se tiše přepnout na legacy nebo online mapu.
6. Přepnutí `maplibre` → `legacy` je pouze explicitní změna occasion nastavení.
   Runtime chyba se loguje s rendererem a bundle verzí, ale nemění konfiguraci.
7. Legacy MBTiles a MapLibre PMTiles jsou odvozené ze stejného zdroje, bboxu,
   zoomů a verze; manifest obsahuje velikost a SHA-256 všech souborů.
8. MapLibre body a trasy se aktualizují přes existující GeoJSON sources; změna
   filtru/focusu nesmí reloadovat podkladový style ani znovu registrovat vrstvy.
9. Android produkční konfigurace explicitně nastaví benchmarkem vybraný
   `androidTextureMode` a platform-view mode; nespoléhá na package default.
10. Dnešní online a webová větev zůstane funkčně i konfiguračně beze změny.

### Entry points and forbidden bypasses

- `MapPage` smí vytvořit mapový povrch pouze přes `MapRendererHost`.
- MapLibre nesmí číst vzdálený style přímo; používá pouze style sestavený z
  ověřeného lokálního bundle.
- Dynamické mapové objekty se nesmí přidávat každý jako samostatný platform
  channel/JNI objekt ani všechny jako `WidgetLayer` bez měřeného důkazu.
- `OfflineManager.downloadRegion` se nepoužije, dokud upstream issue #535 není
  opravené a cíleně ověřené; vlastní bundle manager je kanonický download tok.
- Přímý SQL update occasion, upload assetů nebo release není součástí lokální
  implementace a vyžaduje samostatnou autoritu.

## Decisions, assumptions, and blockers

### Decisions

- **D1:** Primární knihovna je `maplibre 0.3.5` (`package:maplibre`), nikoli
  `maplibre_gl`. Moderní balíček odpovídá druhé knihovně zmíněné uživatelem,
  používá přímé JNI/FFI, má renderer-neutrálnější deklarativní API a projekt už
  splňuje jeho Flutter/Dart minima.
- **D2:** `maplibre_gl` se netahá do produkčního dependency graphu souběžně.
  Použije se jen jako omezený alternativní spike, pokud moderní balíček nesplní
  Wave 1 a pro konkrétní blokátor nebude dostupný malý upstream fix. Výsledek
  musí aktualizovat tento plán před další prací.
- **D3:** MapLibre používá PMTiles; legacy používá MBTiles. Dva malé odvozené
  soubory jsou přijatelná cena za spolehlivý rollback a zdokumentovanou nativní
  podporu, zvlášť když velikost podle uživatele není hlavní kritérium.
- **D4:** Přepínač je enum `offlineMapRenderer`, ne boolean. UI jej může zobrazit
  jako switch, ale JSON zůstane čitelný a rozšiřitelný.
- **D5:** Chybějící `offlineMapRenderer` znamená po compatibility migraci
  `maplibre`, aby byla knihovna skutečně výchozí. Před vydáním se všechny
  existující offline occasion explicitně označí `legacy`; CSM se přepne na
  `maplibre` až po akceptaci.
- **D6:** Aplikační stav zůstane v `MapPage`; dva renderery implementují pouze
  map surface/camera kontrakt. Nevzniknou dvě plné kopie mapové stránky.
- **D7:** Běžné markery, názvy a trasy vykreslí nativní style layers. Aktivní
  popup a ovládací UI zůstanou Flutter overlay, aby se zachoval dnešní obsah a
  akce bez stovek průběžně projektovaných widgetů.
- **D8:** MapLibre source je součást raw style JSON. Tím se obejde známá iOS
  chyba runtime `addSource(tiles:)`; GeoJSON sources pro aplikační overlay jsou
  runtime a nejsou tiled sources.
- **D9:** Bundle stáhne Festapp sám a ověří jej SHA-256. Nevyužije MapLibre
  OfflineManager, který má známý glyph crash a jiný databázový formát.
- **D10:** Tichý automatický fallback je zakázaný. Uživatel/správce může
  přepnout renderer, ale chyba MapLibre musí být pozorovatelná a opravitelná.

### Assumptions

- **A1:** Některý dokumentovaný lokální PMTiles URI tvar funguje v
  `maplibre 0.3.5` na MapLibre Android 13.3.x i iOS 6.27.x; přesná syntaxe není
  v upstream mobilním příkladu potvrzená. Dopad pokud ne: primární volba není
  realizovatelná bez upstream opravy; resolve by: Wave 1 cold-start spike na
  obou platformách a zaznamenání jediného potvrzeného URI kontraktu.
- **A2:** Raw style přijme lokální sprite/glyph file URI na obou platformách;
  dopad pokud ne: popisky či symboly nejsou force-offline; resolve by: síťový
  audit a render českých názvů v prototypu. Pokud file URI selže, ověřit
  loopback asset server pouze jako experiment; nepřijímat jej bez lifecycle a
  security rozhodnutí.
- **A3:** Dynamické SVG ikony lze deterministicky rasterizovat do PNG ve
  správném pixel ratio a registrovat přes `StyleController.addImages`; dopad
  pokud ne: nutný malý WidgetLayer nebo vlastní sprite atlas; resolve by:
  vizuální gate na iOS, zejména kvůli issue #499.
- **A4:** Nativní symbol/line vrstvy odstraní hlavní bottleneck CPU Dart
  rendereru; dopad pokud ne: migrace nepřinese uživatelskou hodnotu; resolve by:
  opakovatelný benchmark proti legacy na stejném slabším telefonu.
- **A5:** Existující oprávnění k poloze stačí pro MapLibre native location;
  dopad pokud ne: poloha nebude paritní; resolve by: permission-denied,
  while-in-use a návrat z backgroundu v parity matrix.

### Blockers

- **B1:** Po Wave 1 je potřeba uživatelské vizuální schválení prototypu v iOS
  Simulatoru před pokračováním do plné parity.
- **B2:** Pro finální výkonový gate je potřeba určit a připojit alespoň jeden
  reprezentativní slabší fyzický Android telefon; simulátor tento důkaz
  nenahrazuje.
- **B3:** Produkční upload PMTiles/glyph bundle, compatibility update occasion,
  změna CSM rendereru a release vyžadují samostatnou autorizaci.

## Deletion ledger

| Artifact | Current role | Final action | Removal proof |
|---|---|---|---|
| Dočasná debug route/page `MapLibrePrototypePage` | Umožní časnou ukázku a feasibility test bez zásahu do živé mapy | Po schválení a začlenění stejného kódu do `MapLibreMapSurface` odstranit | `rg "MapLibrePrototype" lib test` nic nenajde; běžná navigace nemá prototyp route. |
| Přímé mapové typy `fm.Marker`/`fm.Polyline` v business stavu `MapPage` | Svazují aplikační logiku s legacy rendererem | Přesunout za `LegacyMapSurface`; doménový stav bude renderer-neutrální | `rg "fm\.(Marker|Polyline)" lib/components/map/map_page.dart` nic nenajde. |
| Přímé `_animatedMapController` volání z feature logiky | Ovládá pouze FlutterMap kameru | Nahradit `MapViewportController` | V `MapPage` nejsou importy/volání `flutter_map_animations`. |
| Vzdálené source/sprite/glyph URI v aktivním MapLibre stylu | Online závislosti současného zdrojového stylu | Zachovat v build source stylu, ale runtime je deterministicky přepsat na lokální bundle | Airplane-mode síťový audit neukáže HTTP(S) map request; assembler test kontroluje URI. |
| Neatomický download do cílového souboru | Současný jednoduchý cache helper | Pro bundle cestu nahradit `.part` + streaming hash + atomic rename; legacy helper smí být zachován jen pokud používá stejný bezpečný primitive | Test přerušeného downloadu nezanechá validně pojmenovaný soubor. |
| Implicitní chybějící renderer ve starých occasion | Dnešní JSON nemá nový klíč | Před vydáním zapsat explicitní `legacy`; nové/chybějící hodnoty potom znamenají `maplibre` | Read-only inventory vrací renderer pro každou offline occasion. |
| `flutter_map`, `vector_map_tiles`, `vector_map_tiles_mbtiles`, `mbtiles` | Povinný legacy fallback a online/web renderer | Záměrně ponechat, dokud produkt vyžaduje vypnutelný fallback | Dependency a `LegacyMapSurface` mají testované volání pouze přes host. |

## Implementation waves

### Wave 1 — Prototyp prokáže nativní offline základ a ukáže vzhled

**Goal**

Na skutečném CSM stylu a datech je v iOS Simulatoru vidět MapLibre mapa s
českými popisky, jedním reprezentativním místem a trasou; stejný bundle funguje
po cold-startu bez sítě na iOS i Androidu. Výsledek je uživatelsky schválený,
než se mění produkční `MapPage`.

**Changes**

- `pubspec.yaml`, `pubspec.lock` — přidat přesně kompatibilní `maplibre: 0.3.5`;
  nepřidávat současně `maplibre_gl`.
- `automation/offline-map/build.sh` — ze stejného zdroje/bboxu/zoomu vytvořit
  vedle MBTiles i PMTiles; stáhnout font stacky `noto_sans_regular` a
  `noto_sans_bold` pro všechny 256-codepoint rozsahy skutečně potřebné texty v
  regionu; přidat je, oba sprite scale a oba tile formáty do manifestu.
- `automation/offline-map/README.md` — zdokumentovat dvojí artefakt, glyph
  enumeraci, licence, checksumy a force-offline probe.
- `lib/components/map/offline_map_bundle_manifest.dart` — minimální typed parser
  manifestu pro prototyp: verze, URL, lokální relativní cesta, bytes, SHA-256 a
  role souboru.
- `lib/components/map/maplibre/maplibre_style_assembler.dart` — načíst style a
  nahradit source URL lokálním PMTiles URI potvrzeným na obou platformách,
  sprite base lokální cestou a glyph template lokální cestou; odmítnout
  nečekané/nezískané assety.
- `lib/components/map/maplibre/maplibre_prototype_page.dart` a dočasná debug-only
  route — vykreslit lokální bundle, jednu skutečnou ikonu/místo, jednu skutečnou
  trasu, attribution a tap; na Androidu explicitně porovnat
  `androidTextureMode=false` s relevantními `AndroidPlatformViewMode` variantami.
- Prototyp nesmí měnit Occasion JSON ani existující `MapPage`; použije lokální
  debug konfiguraci/manifest.

**Migration/deletion**

- Žádná datová ani produkční migrace. PMTiles/glyphy jsou aditivní lokální
  build output a nesmí se dostat do gitu.

**Failure and compatibility**

- Jestli moderní `maplibre` selže na PMTiles, file glyph/sprite URI, cold-startu
  nebo lifecycle na jedné platformě, zastavit plnou implementaci. Nejprve
  ověřit existující upstream issue/fix. Pouze pokud není malá oprava, vytvořit
  oddělený minimal spike `maplibre_gl` nad MBTiles a porovnat nutný Kotlin 2.1
  upgrade, API paritu a výkon. Před změnou D1/D3 aktualizovat tento plán.
- Nepoužít síťovou mapu jako „dočasný úspěch“ offline prototypu.

**Validation**

- `fvm dart analyze lib/components/map/maplibre` a cílený manifest unit test —
  compile/API kontrakt prototypu; finální wave spustí projektový analyze rozsah.
- Cílené unit testy assembleru/manifestu — všechny aktivní resource URI jsou
  lokální a checksum mismatch selže.
- iOS Simulator: otevřít prototyp k uživatelské ukázce, ověřit popisky, ikonu,
  trasu, tap, pan/zoom a cold restart v airplane/offline režimu.
- Android emulator/zařízení: stejný funkční cold-start a porovnání surface
  režimů; síťový log/proxy nesmí zachytit mapové HTTP(S) požadavky.

**Exit condition**

Uživatel výslovně schválí vzhled v iOS Simulatoru a oba mobilní prototypy
projdou úplným offline resource testem. Bez obou podmínek Wave 2 nezačne.

### Wave 2 — Jeden renderer-neutrální mapový kontrakt

**Goal**

`MapPage` vlastní business stav a interakce bez typů konkrétní mapové knihovny;
legacy povrch přes nový kontrakt stále funguje beze změny chování.

**Changes**

- `lib/components/map/map_scene.dart` — zavést immutable `MapScene`,
  `MapPlacePresentation`, `MapPathPresentation`/segment geometrie a draw/focus
  stav. Zachovat place id jako stabilní hit-test identitu.
- `lib/components/map/map_viewport_controller.dart` — zavést rozhraní pro
  center/zoom, `animateTo`, `fitCoordinates`, projekci a lifecycle-ready stav.
- `lib/components/map/map_renderer_host.dart` — jediný selection point; nejdřív
  připojit pouze `LegacyMapSurface`, aby refaktor šel ověřit před MapLibre
  paritou.
- `lib/components/map/legacy_map_surface.dart` — přesunout dnešní
  `_buildOnlineMap`/`_buildOfflineMap` pouze v rozsahu povrchu, adaptovat scene
  na `fm.Marker`/`fm.Polyline`, PopupMarkerLayer a AnimatedMapController.
- `lib/components/map/map_page.dart` — zachovat načítání dat, filtry, focus,
  popup rozhodnutí, cleaning akce, edit/draw/GPX; publikovat scene a reagovat na
  neutrální callbacks `onMapTap`, `onPlaceTap`, `onCameraReady`.
- `lib/components/map/map_page_helper.dart` — výpočet tras vrací neutrální
  geometrii; legacy převod je v legacy povrchu.
- `lib/components/map/map_marker_with_text.dart` — oddělit prezentační marker
  od dědičnosti `fm.Marker`, případně ponechat pouze legacy wrapper.

**Migration/deletion**

- Odstranit přímé `fm.Marker`, `fm.Polyline` a AnimatedMapController z business
  stavu `MapPage`; legacy implementation se nemaže.

**Failure and compatibility**

- Tato wave nesmí změnit renderer ani asset tok živých map. Když legacy parity
  test selže, opravit neutrální seam před přidáním druhého surface.

**Validation**

- Cílené unit/widget testy scene, filtrů, tras, controller volání a legacy hostu.
- Jeden existující nativní map smoke průchod: deep-link místo, type filter,
  group path, popup, editace a draw path.

**Exit condition**

Současný renderer prochází parity matrix přes nový host a `MapPage` již
neimportuje mapové typy legacy knihovny kromě výslovně ohraničeného adaptéru.

### Wave 3 — Atomický a úplný offline bundle kontrakt

**Goal**

MapLibre nikdy neuvidí částečný nebo síťově závislý mapový balík a legacy
MBTiles zůstane dostupný pro konfigurační rollback.

**Changes**

- `lib/components/map/offline_map_bundle_manager.dart` — stáhnout manifest,
  streamovat každý soubor do `.part`, průběžně hashovat, ověřit bytes/SHA-256 a
  po kompletním bundle atomicky publikovat version directory + ready marker.
  Starou kompletní verzi držet do úspěšného dokončení nové.
- `lib/components/map/offline_map_bundle_manifest.dart` — dokončit validaci
  povinných rolí `style`, `pmtiles`, `mbtiles`, sprite JSON/PNG 1x/2x a všech
  deklarovaných glyphů; zakázat path traversal, HTTP lokální cesty a duplicitní
  role/path.
- `lib/components/map/offline_map_helper.dart` — delegovat bundle download na
  nový manager; progress agregovat podle bytes. Staré single-file API ponechat
  jen pro skutečně legacy konfigurace a napravit jeho částečný-file cache hit.
- `lib/components/map/maplibre/maplibre_style_assembler.dart` — používat pouze
  manifestem ověřené cesty a validovat source name/layer zoom contract.
- Přidat uživatelský error/retry/download progress stav bez automatického
  přepnutí rendereru.

**Migration/deletion**

- Rozšířit build manifest předchozí mapové pipeline; existující immutable v1
  se nepřepisuje, nový úplný bundle dostane další `vN` prefix.

**Failure and compatibility**

- Přerušený download zachová poslední ready bundle. Checksum/path validation
  selže zavřeně a odstraní pouze konkrétní `.part`, nikoli platnou verzi.
- Nedostatek místa a HTTP failure se zobrazí jako retry stav; cleanup smí mazat
  jen přesně identifikované staré map bundle directories.

**Validation**

- Unit test manifestu: missing role, checksum, size, duplicate, traversal a
  neznámá schema version.
- Test downloadu: přerušení v polovině, retry, atomický swap, reuse hotového
  bundle a cleanup pouze staré verze.
- Cold-start airplane-mode test s vyčištěnou nativní MapLibre ambient cache.

**Exit condition**

Renderer se inicializuje pouze z ready bundle; síťový audit po cold-startu je
čistý a legacy MBTiles z téže verze je stále otevřitelný.

### Wave 4 — MapLibre dosáhne úplné funkční parity

**Goal**

`MapLibreMapSurface` umí všechny capability současné mapy nad stejným
`MapScene` a kamera/interakce se chovají stejně jako legacy.

**Changes**

- `lib/components/map/maplibre/maplibre_map_surface.dart` — sestavit
  `MapLibreMap` z lokálního raw style, explicitního Android surface nastavení,
  center/zoom 0–18, event streamu a MapLibre viewport adaptéru.
- `lib/components/map/maplibre/maplibre_scene_controller.dart` — při style load
  jednou registrovat image atlas, GeoJSON source pro místa, source/layers pro
  cesty a draw overlay; další změny posílat přes `updateGeoJsonSource`.
- Markery: rasterizovat/cacheovat ikony podle icon id, focus a cleaning barvy;
  GeoJSON properties nesou place id, title, icon key, viditelnost a z-order.
  Symbol layer vykreslí ikonu i požadovaný název. Tap použije
  `featuresAtPoint` omezený na place layer.
- Popup: aktivní place id a projekce kamery ukotví jeden Flutter
  `MapDescriptionPopup`; zachovat cleaning report/rating, detail dialog,
  eventy a change-position akci.
- Trasy: neutrální hlavní čáry, trojúhelníky a hatch geometrie se serializují
  do GeoJSON s barvou/šířkou a zobrazí nativními Line layers; group selection
  pouze aktualizuje source/filter a fit bounds.
- Draw/edit: map click přidá free point nebo přesune editovaný marker; place tap
  v draw režimu přidá place-ref node; zachovat import GPX, undo, nový segment,
  save/cancel/show groups a všechny existující Flutter controls.
- Current location: použít MapLibre native location až po existujícím permission
  toku; respektovat `_showLocation` při změně tabu a korektně disable/dispose.
- Zachovat type filter (včetně `Other`, default/saved typu a deep-link override),
  forced-visible place, titles vybrané skupiny, attribution a camera animace.
- `lib/components/map/map_renderer_host.dart` — připojit MapLibre surface pro
  offline `maplibre`; online/web větev zůstane legacy.

**Migration/deletion**

- Po dosažení parity odstranit dočasnou prototype page/route a sdílet její
  assembler/surface kód, ne jej kopírovat.

**Failure and compatibility**

- Style reload znovu idempotentně registruje dynamické sources/layers/images.
  Background/foreground, rotace, změna tabu a hot restart nesmí volat zničený
  controller.
- Popup nesmí blokovat pan/zoom mimo vlastní bounds; běžné nativní symboly
  nesmí vyžadovat `WidgetLayer` interaction workaround.

**Validation**

- Controller/scene testy s fake surface pro každou capability.
- Nativní parity matrix na iOS a Androidu: první load, cold offline load,
  pan/pinch/double-tap, marker popup/long detail, WC akce, type/group filter,
  deep-link, current location granted/denied, edit place, draw free/place nodes,
  GPX, undo/segment/save/cancel, background/foreground a návrat mezi taby.

**Exit condition**

Capability matrix je zelená na obou platformách a neexistuje uživatelská
funkce dostupná pouze na legacy povrchu.

### Wave 5 — Occasion switch, kompatibilita a testovatelný default

**Goal**

Správce nastaví výchozí MapLibre nebo vypnutý legacy renderer jediným polem a
nové i staré klienty lze bezpečně provozovat během rollout okna.

**Changes**

- `lib/components/features/feature_constants.dart` — přidat
  `offlineMapRenderer` a `offlineMapBundleManifestURL`.
- `lib/components/features/map_feature.dart` — přidat enum parser/serializer;
  chybějící renderer mapovat na `maplibre`, neznámý odmítnout/logovat jako
  invalid config. Do offline settings přidat default-on switch „Použít
  MapLibre renderer“; OFF uloží `legacy`. Pro MapLibre vyžadovat bundle manifest,
  pro legacy zachovat dnešní package/style/layer fields.
- `lib/components/features/features_strings.dart` a locale JSON — přidat
  uživatelské labely/popisy/error texty běžným lokalizačním mechanismem.
- `MapRendererHost` — číst pouze typed enum, ne volný string/boolean.
- Přidat model testy pro default, obě hodnoty, round-trip a neznámou hodnotu;
  widget test admin switchu a renderer selection test.
- Doplnit provozní návod do `automation/offline-map/README.md`: inventář,
  compatibility zápis, canary, rollback a immutable asset update.

**Migration/deletion**

- Před release nové app verze vypsat všechny živé occasion s kompletní
  `map_layer_offline`; atomickým autorizovaným JSON updatem jim doplnit
  `offlineMapRenderer=legacy` beze změny ostatních keys. Snapshot před/po a
  readback jsou povinné.
- CSM Ostrava dostane `offlineMapBundleManifestURL` a explicitní `maplibre` až
  ve Wave 6. Staré klienty nové keys ignorují a nadále použijí MBTiles.

**Failure and compatibility**

- Release nesmí předběhnout compatibility zápis, protože absence znamená nový
  default. Pokud inventář/readback není úplný, rollout se zastaví.
- Admin switch není runtime user preference; je to occasion-wide nastavení.

**Validation**

- Targeted Flutter model/widget tests a `fvm flutter analyze` změněných mapových
  a feature souborů.
- Read-only produkční inventory dokazuje explicitní renderer pro všechny
  stávající offline occasion před release.

**Exit condition**

Nová konfigurace defaultuje na MapLibre, OFF spolehlivě vybere legacy a žádná
existující offline occasion nemůže být nechtěně přepnuta absencí pole.

### Wave 6 — Výkonový gate, canary rollout a ohraničený fallback

**Goal**

MapLibre má prokazatelně lepší plynulost na slabším telefonu, CSM jej používá
v produkci a správce jej může bez deploye vypnout na legacy.

**Changes**

- Připravit deterministický 60sekundový scénář nad stejným CSM bundle a scene:
  cold open, dvě fit operace, opakovaný pan přes hustou část, pinch z14↔z18,
  type filter a group route. Tři měřené běhy po jednom warm-upu pro renderer.
- Android na 60Hz slabším fyzickém zařízení: release/profile build, systémové
  frame stats/Perfetto a memory peak; porovnat explicitní surface varianty.
  Přijmout jen variantu bez kompozičních/touch vad.
- iOS na fyzickém reprezentativním zařízení: release/profile + Instruments
  Core Animation/render statistics; simulátor zůstane pouze vizuální.
- Akceptační práh: MapLibre má na slabším Androidu alespoň o 30 % méně frames
  nad 32 ms než legacy, jank nad 32 ms nejvýše 5 % měřených frames, žádný stall
  nad 250 ms během warm map interaction a žádný OOM/crash. Pokud absolutní práh
  zařízení objektivně nesplní oba renderery, zaznamenat raw výsledky a vyžádat
  produktové rozhodnutí; relativní zlepšení samo nesmí být vydáváno za hladký
  výsledek.
- Po samostatné autorizaci publikovat nový immutable bundle, ověřit HEAD/GET a
  checksum, zapsat CSM manifest + `offlineMapRenderer=maplibre`, vydat canary a
  provést Android/iOS cold-start airplane acceptance.
- Po dobu nejméně jednoho stabilního release cyklu ponechat legacy dependency,
  asset fields a switch. Jejich budoucí odstranění je nové produktové rozhodnutí.

**Migration/deletion**

- Žádné automatické mazání starého MBTiles ani aktivní ready bundle během
  canary. Cleanup až po úspěšném přechodu a pouze pro přesné staré verze.

**Failure and compatibility**

- Funkční, vizuální, offline nebo výkonový neúspěch blokuje aktivaci MapLibre.
  Rollback je změna CSM `offlineMapRenderer` na `legacy`; URL MBTiles/style
  zůstávají platné. Při chybě bundle verze lze vrátit předchozí immutable
  manifest, nikdy nepřepisovat existující objekty.

**Validation**

- Uložit device/OS/build mode, raw frame data, memory peak a tři výsledky obou
  rendererů do rollout záznamu.
- Ověřit produkční JSON readback, úplný asset GET/checksum a Android+iOS
  airplane cold-start.
- Po přepnutí na legacy ověřit jedním canary průchodem, že rollback nevyžaduje
  nový app deploy.

**Exit condition**

Výkonové prahy a celá parity matrix projdou, CSM canary je stabilní, produkční
readback vrací `maplibre` a ověřený manifest a zdokumentovaný přepínač prokazatelně
vrací současný renderer bez deploye.

## Rollout and rollback

1. Lokálně dokončit a uživatelsky schválit Wave 1; nic neuploadovat a neměnit
   živou occasion.
2. Dokončit neutrální seam, bundle manager a plnou paritu; release build zatím
   stále používá explicitní `legacy` na všech živých occasion.
3. S autorizací provést produkční inventory a compatibility zápis `legacy` do
   všech existujících offline feature JSON. Ověřit readback před vydáním appky.
4. Publikovat nový CSM immutable bundle s PMTiles/glyphy i legacy MBTiles a
   ověřit každý checksum.
5. Vydat app verzi podporující oba renderery. Staré klienty nové keys ignorují.
6. Pouze pro CSM zapsat manifest a `maplibre`, provést Android+iOS canary,
   airplane cold-start a výkonové sledování.
7. Při regresi nastavit CSM `offlineMapRenderer=legacy`. Neprovádět deploy,
   nemažat MapLibre data ani tiše fallbackovat v klientu; zachovat diagnostiku.
8. MapLibre se stane defaultem pro nové konfigurace díky enum defaultu. Další
   existující occasion se přepínají jednotlivě až po vlastní vizuální/offline
   kontrole.

## Verification strategy

| Risk or invariant | Verification seam | Command/observation |
|---|---|---|
| Dependency je kompatibilní s projektem | Pub solver + nativní compile | `fvm dart pub add --dry-run maplibre` před změnou; potom cílený iOS/Android build ve Wave 1 |
| Manifest nepřijme neúplný/škodlivý bundle | Typed parser a bundle manager | Cílené Dart testy missing role, hash, size, traversal, duplicate, interrupted download |
| Style je skutečně offline | `MapLibreStyleAssembler` output | Unit test: source/sprite/glyph jsou lokální a raw style neobsahuje mapové `http://`/`https://` URI |
| České popisky a sprity fungují | Skutečný CSM bundle | iOS + Android screenshot/visual pass na ulicích, POI a všech použitých ikonách |
| Offline znamená cold-start bez sítě | Nativní resource loading | Airplane-mode relaunch po vyčištění ambient cache; proxy/log neukáže mapový request |
| Oba renderery sdílejí funkční stav | `MapScene` + fake viewport | Unit/widget parity matrix pro filtry, focus, paths, draw/edit a camera commands |
| Markery a trasy neběží jako stovky Flutter overlayů | MapLibre scene controller | Test počtu sources/layers a code search; WidgetLayer pouze výslovně ohraničený aktivní overlay |
| Style reload/lifecycle je bezpečný | Controller lifecycle | Background/foreground, tab switch, dispose/recreate a style reload na obou platformách |
| Default a vypnutí jsou deterministické | Feature JSON + host selection | Model round-trip/default/invalid tests a Occasion Settings widget test |
| Staré occasion se nepřepnou | Produkční compatibility inventory | Autorizovaný before/after snapshot a read-only readback všech offline occasion |
| Výkon řeší původní problém | Stejný CSM benchmark | Tři release/profile běhy obou rendererů na slabším fyzickém Androidu + iOS evidence |
| Rollback nevyžaduje deploy | Occasion enum | Canary změna `maplibre` → `legacy`, readback a cold open legacy mapy |

## Definition of complete

- [ ] Uživatel schválil MapLibre vzhled v iOS Simulatoru po Wave 1.
- [ ] Moderní `maplibre` prokázal lokální PMTiles, sprite a glyph cold-start bez
      sítě na iOS i Androidu.
- [ ] `MapPage` používá jeden renderer-neutrální scene/camera kontrakt a jediný
      `MapRendererHost` selection point.
- [ ] Oba renderery procházejí celou capability matrix včetně edit/draw/GPX,
      current location, filtrů, popupů a cleaning akcí.
- [ ] MapLibre vykresluje běžné body a trasy nativními layers a splní výkonové
      prahy na slabším fyzickém Androidu.
- [ ] Bundle download je streamovaný, checksumovaný, atomický a aktivní style
      nemá síťové map resources.
- [ ] Occasion Settings defaultuje na MapLibre a explicitní OFF vybírá legacy.
- [ ] Všechny starší offline occasion mají před release explicitní `legacy`.
- [ ] Dočasná prototype route je odstraněná; legacy závislosti jsou ponechané
      pouze jako úmyslný, testovaný fallback.
- [ ] Cílená standard verifikace projde a výsledky device benchmarku jsou
      zaznamenané.
- [ ] Produkční upload/konfigurace/release jsou buď autorizovaně ověřené, nebo
      přesně označené jako neprovedené provozní kroky.

## Residual risks

- `maplibre` je mladší balíček a jeho iOS podpora je výrazně novější než u
  `maplibre_gl`; připnutí verze, feasibility gate a explicitní legacy switch
  snižují dopad, ale neodstraňují budoucí upstream regresi.
- Nativní platform view může mít modelově specifické kompoziční/touch chyby.
  Jeden slabší Android a jeden iOS přístroj nedokazují celý device matrix;
  canary a rollback proto zůstávají nutné.
- Dva tile formáty a lokální glyphy zvětší veřejný bundle/storage. Uživatel
  velikost nepovažuje za hlavní omezení, přesto manifest a downloader musí před
  stažením ukázat/znát celkovou velikost a korektně řešit nedostatek místa.
