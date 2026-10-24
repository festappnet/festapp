# Dotykové posouvání a snazší výběr objektů ve Flutter blueprintu

Datum: 2026-10-24
Stav: Lokální implementace a cílené ověření; publikace a integrační pin čekají
Verification: low-risk (plán); standard při implementaci sdílených gest knihovny

## Výsledek a rozsah

Prstem lze začít posouvat v celém viewportu plánu, včetně prázdného okolí
vykresleného sálu. Klepnutí těsně vedle vybíratelného objektu vybere zamýšlený
objekt: židli, stůl, text nebo další vybavení podle aktivního režimu.
Rezervační režim tím nezískává nové akce pro dosud neinteraktivní objekty.
Posunutí ani pinch nevyvolají výběr,
rezervaci, přesun objektu nebo změnu dokumentu omylem.

Řešit Flutter web i nativní Flutter, používaný gridový `VenueSeat*` adaptér
Festappu a objektový `VenueLayout*` editor/picker knihovny. JS veřejný klient je
existující referencí pro chování a regrese. Nemigrovat kvůli této opravě formát
blueprintů ani celé UI z gridového na objektový model. Neměnit SQL, oprávnění,
rezervační zámky, vzhled židlí nebo data uložených plánků.

Implementace byla autorizována provedením souvisejícího execution promptu.
Publikace knihovny, změna git pinu a vydání klienta autorizovány nejsou.

## Potvrzený stav a důkazy

Zkoumáno v `/Users/miakh/source/festapp`, HEAD `353394511`, větev
`feat/occasion-setup-wizard-20261007`, s rozsáhlými existujícími necommitnutými
změnami. Nejde o ověření produkčního artefaktu ani o čistý stav HEAD.

| Fakt | Důkaz | Důsledek |
|---|---|---|
| JS veřejný picker má přesah 8 CSS px, nezávislý na zoomu. | `web_client/src/components/blueprint/blueprint_config.js`: `seatHitSlop`; `blueprint_renderer.js`: `handleTap`; `tests/components/blueprint_viewport.test.js` | Oprava je v pracovním kódu JS; její produkční vydání nebylo ověřeno. |
| Flutter rezervace používá `VenueSeatPicker`, správa `VenueSeatViewer(editorMode: true)`. | `lib/components/blueprint/seat_reservation/widgets/seat_reservation_widget.dart`; `views/blueprint_editor_tab.dart` | Oprava pouze v JS nepomůže těmto obrazovkám, ani když Flutter běží v prohlížeči. |
| Gridový Flutter viewer má `InteractiveViewer` nad rozměry scény a jednotlivé `_SeatTapTarget` s `InkResponse`. | `../venue_seat_picker/lib/src/widgets/venue_seat_viewer.dart`: `build`, `_SeatTapTarget` | Není zde ekvivalent centrálního vyhledání nejbližší židle s tolerancí. Samotné zvětšení ink efektu nezvětší zásah. |
| Objektový editor předává `8 / _viewportScale`, ale jádro tuto toleranci používá jen pro otevřené čáry. Vyplněné tvary mají `pointInPolygon`. | `../venue_seat_picker/lib/src/layout_editor/widgets/venue_layout_editor.dart`: `_hitAt`; `packages/venue_layout_core/lib/src/geometry.dart`: spatial index `hitTest` | Přítomnost parametru tolerance nedokazuje přesah kolem židle. |
| Objektový picker volá geometrický `hitTest` bez screen-space tolerance. | `../venue_seat_picker/lib/src/layout_editor/widgets/venue_layout_picker.dart`: `onTap` | I nový picker potřebuje stejný záměr výběru jako editor. |
| Objektová surface rozlišuje pan a editaci. V Select režimu prázdný zásah začíná marquee. | `layout_scene_surface.dart`: `_updateScale`, `onScaleStart`; `venue_layout_editor.dart`: `_dragStart`, konfigurace `pan` | Přepnutí všech dotyků na pan by rozbilo editaci. Rozhodovat podle počátku gesta, zařízení a nástroje. |
| Existující testy ověřují pan/pinch a zachování panelů, nikoli výslovně začátek mimo transformovaný půdorys. | Festapp `test/components/blueprint/blueprint_mobile_scroll_view_test.dart`; knihovna `test/venue_seat_viewport_test.dart`, `layout_mobile_gestures_test.dart`, `layout_surface_navigation_test.dart` | Nová regrese musí začínat prokazatelně v prázdném okolí, nikoli jen ve středu widgetu. |
| Vývojová a připnutá závislost nejsou totožné zdroje. | Festapp `pubspec.yaml`: git ref `143026c6c733662d417471a3eb448dee0b0d7252`; `pubspec_overrides.yaml`, `pubspec.lock`, `.dart_tool/package_config.json`: lokální `../venue_seat_picker`; lokální knihovna HEAD `c829a33` a 75 změněných cest | Lokální průchod neprokazuje, že opravu obsahuje standardní nebo vydaný build. |

README zmiňuje objektové API, ale přímí Flutter volající v tomto pracovním
stromu stále používají gridové API. Implementaci řídit skutečnými volajícími.

## Zjištění při lokální implementaci

- Výchozí Festapp HEAD `353394511`, knihovna HEAD
  `c829a33d07de9a8fa376b407658875d22abd246e`; oba pracovní stromy již
  obsahovaly cizí změny. Dotčené vstupní soubory byly před úpravami zachyceny
  mimo repozitáře v `/tmp/blueprint-touch-20261024/` pro oddělené porovnání.
- Regrese gridu `touch pans from blank viewport outside the transformed grid`
  prošla už na původním kódu. `InteractiveViewer` přijímá pan i z prázdného
  okraje, proto se jeho rozměry ani Festapp wrapper neopravují. Přidána je pouze
  centrální souřadnicová tap cesta a sémantické aktivace.
- Regrese objektového editoru `Select touch pans blank margin and near miss;
  mouse keeps marquee` na zachyceném původním kódu selhala při porovnání kamery:
  touch drag z prokazatelně prázdného okraje ponechal matici beze změny.
- Model `LayoutNode` podporuje hierarchickou translaci a rotaci, nikoli parent
  scale. Resolver měří obrysy po těchto skutečných transformacích a kamerový
  zoom pokrývají testy 0.5/1/2. Nevzniká nový transformační model jen kvůli
  plánovanému testu parent scale.
- Blokující cíl resolver vrací dosavadnímu handleru, aby se zachovala informace
  o nedostupnosti; nikdy za ním nehledá volné místo. Handler vlastní zákaz akce,
  pending stav a rollback.

## Nejistoty a první reprodukce

- Screenshot neidentifikuje URL, build ani konkrétní vstupní obrazovku. Při
  reprodukci zaznamenat obrazovku, platformu, verzi aplikace a skutečný zdroj
  knihovny. Pokud je dostupný jiný aktivní checkout s objektovým hostem,
  nejprve porovnat vstupní bod; nekopírovat jeho nesouvisející změny.
- Původní hypotézy před implementací (výsledky reprodukce viz výše): zásah mimo menší
  transformovanou scénu nezasáhne recognizer; editor v Select režimu interpretuje
  dotyk jako marquee; používaný artefakt neobsahuje vývojové změny. Rozlišit
  stejnou scénou a počátkem uvnitř/vně půdorysu, s touch/mouse a Pan/Select.
- Chybějící Flutter přesah je potvrzený kódem; nelze tím samotným určit,
  co bylo dříve opraveno nebo vydáno. Produkční stav zůstává neověřený.

## Cílový kontrakt

1. Viewport vlastní gesta v celé své přidělené ploše. „Mimo plánek“ znamená
   prázdnou plochu uvnitř viewportu, nikoli formuláře, panely a toolbar kolem něj.
2. V pickeru jeden prst posouvá a dva prsty posouvají/zoomují i při startu
   mimo půdorys. Pro malý plán respektovat dosavadní meze kamery; nepovažovat
   správně omezenou kameru za nefunkční recognizer. Testovat i zvětšený plán.
3. V objektovém Select režimu touch drag v prázdné ploše posouvá kameru.
   Mouse drag v prázdné ploše zachová marquee. Drag na objektu zachová přesun
   a na úchytu resize/rotaci. Pan nástroj naviguje odkudkoli. Kreslicí nástroje
   zachovají kresbu jedním prstem; dva prsty navigují.
4. Druhý prst převezme celé gesto pro navigaci; zrušit rozpracovanou editaci a
   tap kandidáta. Ani po zvednutí prvního prstu nesmí zbylý prst editaci obnovit.
   Pointer cancel nesmí ponechat visící drag, výběr nebo autopan.
5. Všechny vybíratelné objekty mají stejný radiální přesah 8 logických px Flutter /
   CSS px JS mimo skutečný obrys. Hodnota se s kamerou ani DPR nezvětšuje.
   Přesah je vlastnost uživatelského výběru, bez změny geometrie, vzhledu,
   uložených souřadnic nebo přesných geometrických operací. Čáry měřit od
   vykresleného tahu, vyplněné tvary od obrysu; respektovat otvory a rotaci.
6. Přímý zásah podle existujících pravidel režimu a pořadí kreslení má vždy
   přednost před přesahem jiného objektu. Jinak vyhrává nejbližší skutečný obrys
   cíle v toleranci; shody rozhoduje pořadí kreslení, pak stabilní ID.
   Nepreferovat velký stůl kvůli jeho středu před bližší židlí. Respektovat
   hierarchické transformace a stávající mapování členů skupiny na výběrový cíl.
   Obsazená a zakázaná sedadla zůstávají překážkami: nikdy nepřeskočit bližší
   obsazenou židli na volnou. Nevybírat neinteraktivní dekorace, pozadí ani
   organizační skupiny jen proto, že mají geometrický obrys. Pravidla zamčených
   objektů a překryvů převzít z existujícího režimu, nikoli obejít tolerancí.
7. Picker po nalezení cíle zachová existující dostupnost, pending stav a rollback.
   Editor zachová práva, selection target skupin a existující význam prázdné
   gridové buňky. V editoru lze legitimně cílit i obsazené sedadlo.
8. Tap vyvolá nejvýše jeden callback. Drag, pinch a cancel nevyvolají rezervaci.
   Desktopové ovládání, tooltipy, sémantické akce a dostupný seznam zůstanou funkční.
9. Přesah se uplatní při dokončeném tapu. Rozhodnutí mezi tahem objektu a panem
   používá přesný zásah a existující úchyty, nikoli rozšířenou tap oblast.
   Dotykový drag těsně vedle stolu tak může začít posouvat kameru, zatímco
   krátké klepnutí ve stejném místě vybere stůl. Tap kandidát se po překročení
   pohybového prahu zruší; samotný pointer down nesmí přes toleranci změnit výběr.

Geometrii objektů vlastní `venue_layout_core`: přidat jasně
pojmenovaný resolver uživatelského výběru s přesnými zásahy a volitelnou tolerancí
pro všechny objekty. Resolver dostává pravidla cílení aktivního režimu včetně
blokujících cílů; picker a editor nesmějí mít vlastní kopie výpočtu vzdáleností.
Zachovat přesný `hitTest` pro geometrické operace, kreslení, drag ownership a snap.
Flutter surface dodá souřadnice a aktuální měřítko; editor i picker použijí stejný
resolver. Gridový viewer použije jednu odpovídající resolver cestu nad sloty,
nikoli překrývající se zvětšené widgety nebo druhou implementaci ve Festappu.

## Úsporný postup a povolený rozsah změn

- Začít soubory a symboly z tabulky důkazů; přečíst jejich dotčené volající.
  Další soubor otevřít až při konkrétní závislosti nebo selhání. Neopakovat
  architektonický průzkum, nespouštět nezávislý audit ani subagenty.
- Výchozí změnová plocha: `geometry.dart`, `venue_seat_viewer.dart`,
  `layout_scene_surface.dart`, `venue_layout_editor.dart`, `venue_layout_picker.dart`
  a jejich vlastnické testy. Export doplnit jen pokud jej nový resolver potřebuje.
  Festapp hosty upravit pouze při prokázané chybě layoutu nebo integrace.
- Reuse existující spatial index, kontury, transformace a gesture lifecycle.
  Přidat jeden resolver objektového tapu a jeden adaptér pro gridové sloty.
  Nezavádět obecný framework gest, nový model, dependency ani konfigurační UI.
- Reprodukci spojit s budoucí regresí. Selhávající test spustit jednou pro určení
  příčiny; pak dokončit souvislou opravu před společným cíleným ověřením.
  Úspěšné kontroly opakovat jen po změně kódu, který pokrývají.
- Výstupy příkazů držet stručné; log rozbalit při selhání. Pokud nález mění
  předpoklad plánu, opravit příslušný odstavec a pokračovat v témže rozsahu.

## Implementační vlny

### 1. Reprodukce a regrese na správné vrstvě

- Přečíst pravidla knihovny před její úpravou. Zachovat cizí rozpracované změny
  v obou repozitářích; pro implementaci zajistit izolaci a evidovat výchozí SHA.
- V uvedených widget testech vytvořit scénu menší než viewport na jedné ose.
  Explicitně vypočítat bod v prázdném okraji a prokázat, že neleží v půdorysu.
  Startovat touch drag na něm a porovnat transformaci kamery i dokument.
- Přidat near-miss scénu s obdélníkovým stolem a šesti židlemi jako na screenshotu,
  v pickeru i editoru, při více zoomech. Test musí před opravou selhat z důvodu
  popsaného chování, nikoli chybné fixture nebo nepřipravené kamery.
- Stejný kontrakt ověřit pro stůl, text a čáru v editoru. Zahrnout přímý zásah
  do židle uvnitř přesahu stolu, překryvy, zamčený objekt a dekoraci. V pickeru
  stůl bez vlastní akce nesmí přes toleranci dostat novou rezervační funkci.
- Výstup: reprodukovaný problém po konkrétních vstupních bodech; odlišit
  vadné chování kódu od chybějícího vydání. Nespouštět celou aplikaci s produkčními daty.

### 2. Jedna navigační cesta na viewport

- Grid: `venue_seat_viewer.dart` upravit rozměry a hit-test plochu recognizeru tak,
  aby přijímal začátek gesta v celém viewportu. Kamera a její meze zůstávají u
  stávajícího controlleru; nevytvářet konkurenční pan recognizer ve Festapp wrapperu.
- Objekt: v `layout_scene_surface.dart` určit vlastníka gesta při pointer down
  z druhu zařízení, nástroje a výsledku zásahu/úchytu. V Select režimu rozlišit
  touch na prázdné ploše od mouse marquee a tahu objektu. Pokud bude třeba
  interní callback hosta, sděluje záměr hitu, nikoli druhou implementaci gest.
- Zachovat pinch, přechod 1-2-1 prsty, cancel a existující bounds.
- Výstup: regrese z vlny 1 pro navigaci projde, dokument i undo historie zůstanou
  při navigaci beze změny. Bez přepínání na nástroj Pan při každém dotyku.

### 3. Sdílený záměr výběru s tolerancí

- `packages/venue_layout_core/lib/src/geometry.dart`: resolver vrací ID cíle
  nebo `null`, bez změny dokumentu. Vstupy: dokument/index, bod ve world-space,
  tolerance `8 / viewportScale` a pravidla aktivního režimu. Použít dvě fáze:
  přímé zásahy podle stávajícího pořadí; teprve při jejich absenci nejbližší obrys
  včetně hranice tolerance. Kandidáty omezit spatial indexem. Vzdálenost měřit
  ve world-space po hierarchických transformacích, aby scale rodiče neměnil 8 px.
  Cíle klasifikovat jako aktivovatelné, blokující nebo ignorované; obsazené místo
  neodfiltrovat před rozhodnutím o vítězi a nehledat za ním náhradní volné místo.
  Netestovat pouze bounding box rotovaných objektů. Použít společný přesah pro
  všechny vybíratelné typy, bez seznamu výjimek pro židle, stoly a další vybavení.
  Oddělit pravidla interaktivity režimu od geometrického výpočtu vzdálenosti.
- `venue_layout_editor.dart`: nepřidávat toleranci plošně do `_hitAt`.
  Dnes jej volají také `_selectDown` a `_dragStart`. Ponechat přesnou cestu pro
  pointer down, drag, úchyty a ostatní geometrické volající; resolver s přesahem
  volat až z `_tap`. Zachovat `_selectionTarget` a přesný footprint řad jako
  existující pravidlo editoru. Prověřit větev `_selectionBeforeDown`, aby prázdný
  přesný zásah při down nepotlačil tolerantní tap ani neprovedl Shift výběr dvakrát.
- `venue_layout_picker.dart`: `LayoutSceneSurface.onTap` přepojit na tentýž
  resolver; měřítko převzít přes `onViewportScaleChanged`. Zvolený cíl předat
  dosavadnímu `_choose`, který nadále vlastní dostupnost a rezervační akci.
- `venue_seat_viewer.dart`: jedna koordinátová tap cesta přes slot resolver,
  která zachová `_tap`, tooltipy a editorMode. Odstranit konkurenční pointer tap
  callbacky; sémantická aktivace sedadla musí dál dojít na stejný handler.
- Výstup: 7 px vedle vybíratelného objektu vybírá, 9 px ne; diagonální odchylka
  se měří radiálně. Přímý zásah souseda má přednost. Drag ze stejného prázdného
  místa vedle objektu naviguje a nemění objekt ani výběr přes tap toleranci.
  Nejbližší obsazená židle nevybere sousední volnou. Jeden tap = jeden handler.

### 4. Integrace ověřitelné revize a společné ověření

- Lokální implementaci ověřit s existujícím path override. Reprodukovatelný git
  pin je následný integrační gate: teprve po samostatně autorizovaném zveřejnění
  opravy knihovny připnout `venue_seat_picker` i `venue_layout_core` na stejné
  dostupné SHA a ověřit lockfile bez override v izolovaném prostředí.
  Nevymýšlet SHA, nepinovat necommitnutý obsah a nemazat uživatelův override.
- `BlueprintViewport`, `BlueprintMobileScrollView` a rezervační hosty měnit
  jen při prokázaném problému jejich layoutu. Doplnit jednu integrační regresi
  pro skutečné Festapp hostování, nikoli jen přímé vložení knihovního widgetu.
- README upřesní skutečně konzumovaný kontrakt a stav; oddělit lokální opravu,
  pin knihovny, sestavení klienta a ověřené nasazení.
- Výstup: lokální cílená sada prochází; pin a ověření bez override jsou buď
  prokázané dostupným SHA, nebo výslovně čekají na publikaci knihovny.
  Nasazení a vydání mobilní aplikace zůstávají samostatný neprovedený krok.

## Odstranění a hranice

| Cesta | Akce a důkaz |
|---|---|
| Samostatné pointer tap handlery jednotlivých grid sedadel | Nahradit koordinátovou cestou; zachovat sémantické akce. Test jednoho callbacku. |
| `_hitAt` tolerance pouze pro čáry vydávaná za toleranci židlí | Přepojit uživatelský výběr na resolver; přesnou geometrii ponechat pro její původní účel. |
| Bezpodmínečné zahájení marquee při touch na prázdné ploše v Select | Nahradit rozhodnutím vlastníka gesta; mouse marquee zůstává otestované. |
| Lokální path override jako jediný nositel opravy | Pro release nahradit ověřeným git pinem; lokální vývojové nastavení uživatele zachovat. |

Žádné databázové migrace, nové přepínače verzí ani odstranění gridového API.

## Ověření při implementaci

Verification standard pro sdílená gesta; bez plošného testování aplikace.
Před Flutter/Dart kontrolou ověřit volný workstation slot. Nejvýše jeden Flutter
proces, widget testy `--concurrency=1`; respektovat vlastnické test roots knihovny
a Festappu. V plánování testy ani buildy nespouštět.

| Vrstva | Minimální důkaz |
|---|---|
| Core resolver | Parametrizované testy 7/8/9 px při zoomu 0.5/1/2; diagonála; přímý soused před přesahem; nejbližší obrys; pořadí při shodě; blokující místo; ignorovaná dekorace; rotace, parent scale, otvor a tah čáry. Sdílet fixture pro židli, stůl a text. |
| Surface a hosté knihovny | Touch z prokazatelně prázdného okraje mění kameru, nikoli dokument/undo. Tap a drag ze stejného bodu v přesahu mají odlišný výsledek. Mouse marquee, tah objektu/úchytu, 1-2-1 prsty a cancel zůstávají funkční; žádný duplicitní tap. Pokrýt grid i objektový picker/editor. |
| Festapp | Jedna regrese skutečného hostování v `test/components/blueprint/blueprint_mobile_scroll_view_test.dart`; další root jen při změně jeho chování. |

Spustit jednou po souvislé opravě, sekvenčně:

1. V core `fvm dart test` s konkrétním přidaným/změněným resolver testem.
2. V knihovně jeden `fvm flutter test --concurrency=1` nad dotčenými testy.
   Začít `venue_seat_viewport_test.dart`, `layout_surface_navigation_test.dart`,
   `layout_mobile_gestures_test.dart`; picker/editor pokrýt jejich vlastnickým
   testem, pokud je tyto soubory nepokrývají. Nedělat kartézský součin scénářů.
3. Festapp host test přes vlastnický root dle
   `automation/client_test_classification.json`; pokud je samostatně spustitelný,
   `fvm flutter test --concurrency=1 test/components/blueprint/blueprint_mobile_scroll_view_test.dart`.
4. Cílený `fvm dart analyze <změněné Dart soubory>` v příslušném repozitáři.

JS test ani build nespouštět při změně pouze Flutter knihovny. Pokud se prokáže
nutnost změnit JS, přidat jeho `blueprint_viewport.test.js` přes pnpm 11.24.0.
Vlastní Festapp editor actions mají session root v
`test/sessions/czech_catalog_3_cases.dart`; přidat jen při jejich změně.
Reálný telefon a prohlížeč použít pro potvrzení nahlášené platformní chyby nebo
před vydáním. Nedostupný telefon uvést jako neověřený bod; emulaci nevydávat za
ověření nativního zařízení. Případný browser check běží izolovaně na testovacích datech.

## Dokončení a provozní hranice

### Lokální ověření 2026-10-24

- Core: `fvm dart test test/tap_resolver_test.dart`, 16 úspěšných testů.
- Knihovna: cílené `fvm flutter test --concurrency=1` nad roots
  `venue_seat_viewport_test.dart`, `layout_surface_navigation_test.dart`,
  `layout_mobile_gestures_test.dart`, `layout_touch_selection_test.dart`,
  `layout_chair_selection_test.dart`, `layout_picker_lifecycle_test.dart`,
  `layout_multi_selection_gesture_test.dart`,
  `layout_row_assembly_interaction_test.dart`, `venue_seat_picker_test.dart`.
  Po opravách byly opakovány pouze dotčené kontroly; výsledné případy procházejí.
- Festapp: `fvm flutter test --concurrency=1
  test/components/blueprint/blueprint_mobile_scroll_view_test.dart`, 2 úspěšné
  testy. První používá skutečný `BlueprintTab.prototype` a explicitní začátek
  dotyku nad transformovaným půdorysem; nepotřebuje změnu hostitelského widgetu.
- Cílené `fvm dart analyze` pro změněné Dart soubory knihovny/core a host test.
  Ověření používá existující lokální path overrides.
- Stav: lokální oprava připravena; knihovna nepublikována, oba git piny a lockfile
  bez override čekají na samostatně autorizovanou publikaci. Klient nesestaven
  pro vydání a nenasazen. Git commit/push ani databázové změny neprovedeny.

- Posouvání z prázdného okolí prokazatelně funguje; editace a mouse marquee zůstávají.
- Společný přesah funguje pro všechny vybíratelné objekty v objektovém editoru
  a pro dosavadní interaktivní cíle v pickerech i gridovém modelu.
- Testy dokazují skutečný hit/slop a změnu kamery, ne pouze existenci widgetu.
- Lokální implementace je oddělena od integrace; před vydáním pin a lockfile
  musí reprodukovat ověřené chování bez sousedního checkoutu.
- Žádné změny dat, rezervací nebo produkce; žádný commit/push v rámci tohoto plánu.

Při později autorizovaném vydání určit jediného cílového tenanta a kanál.
Webový deploy sám neaktualizuje instalovaný Android/iOS build. Rutinní deployment
delegovat dle AGENTS.md. Do ověření živé verze nepoužívat označení „nasazeno“.
Případný rollback klienta vrací předchozí pin a sestavení, bez zásahu do dat.

Zbytkové riziko: obrazovka a verze ze screenshotu nebyly identifikované.
Neověřené zůstává ovládání na fyzickém telefonu a v reálném prohlížeči.
Navigace a tap resolver jsou ověřovány lokálními Dart/Flutter testy; ty samy
neprokazují vydaný ani produkční artefakt.
