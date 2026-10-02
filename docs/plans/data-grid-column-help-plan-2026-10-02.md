# Opakovaně použitelná nápověda v hlavičkách DataGridu

Datum: 2026-10-02\
Stav: Implementováno a cíleně ověřeno\
Verification: standard pro implementaci sdíleného chování; průzkum low-risk\
Výchozí bod: lokální `main`, HEAD `b7b62b899`, včetně rozpracovaných změn

## Výsledek a rozsah

Sloupec může mít volitelné vysvětlení. Je-li neprázdné, zobrazí hlavička informační ikonu v kroužku. Stejnou nápovědu lze otevřít najetím myší, kliknutím, klepnutím a z klávesnice. Bez vysvětlení zůstane původní hlavička včetně rozměrů a chování.

Rozsah: sdílený Flutter `SingleTableDataGrid`, konfigurace controlleru, jeden společný renderer hlavičky a cílené widgetové testy. Jde o přidání funkce, nikoli migraci. Součástí je dokumentovaný příklad použití a testovací tabulka; konkrétní obchodní texty a plošné zapnutí na existujících sloupcích nejsou zadány a nejsou podmínkou dokončení. Nezasahovat do vanilla JS klienta, databáze, tenantů ani release konfigurace.

## Pravidla práce

- Před implementací číst `AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md` a příslušné části `CONTRIBUTING.md`.
- Pracovní strom obsahuje mnoho cizích rozpracovaných změn. Zachovat je; žádný hromadný reset, formátování ani staging.
- Používat `fvm`. Neupravovat `.pub-cache`, neforkovat ani neupgradovat TrinaGrid kvůli této funkci.
- Uživatelské texty dodává volající přes stávající `*_strings.dart`. Nevkládat pevné české nebo anglické texty do widgetu.
- Tato dvojice dokumentů autorizuje přípravu implementace v navazující relaci, nikoli commit, push, build produkce nebo nasazení.

## Ověřený současný stav

| Fakt | Evidence | Důsledek |
|---|---|---|
| Jediné vytvoření `TrinaGrid` v `lib` je ve společném wrapperu. | `lib/components/single_data_grid/single_table_data_grid.dart`, `_buildDataGrid` | Centrální místo napojení, není třeba upravovat každou tabulku. |
| Controller nese mutable `List<TrinaColumn> columns`. | `single_data_grid_controller.dart`, `SingleDataGridController` | Nápovědu párovat podle `column.field`, ne indexu nebo přeloženého názvu. |
| Načítání uživatelů nahrazuje celý seznam sloupců. | `lib/components/users/views/users_tab.dart`, `_loadUsersForGrid` | Instalace pouze v konstruktoru controlleru by selhala. |
| `forceReload` načte data a změní klíč tabulky. | `single_data_grid_controller.dart`, `forceReload` | Nové instance sloupců musí dostat nápovědy před dalším vytvořením gridu. |
| Sdílený `SingleDataGridHeader` je horní panel, nikoli hlavička sloupce. | `single_table_data_grid.dart`, `createHeader`; `single_data_grid_header.dart` | Neimplementovat sloupcové ikony do horního panelu. |
| Zamčená závislost je `trina_grid 2.2.2`; manifest má `^2.1.1`. | `pubspec.lock`, `pubspec.yaml` | Rozhodující je API instalované/zamčené verze. |
| `TrinaColumn.titleRenderer` nahrazuje celý standardní obsah hlavičky. | Instalovaný `trina_grid-2.2.2/lib/src/ui/columns/trina_column_title.dart`, `build` | Renderer musí převzít styl, checkbox, indikaci filtru a context/resize ikonu. |
| Renderer dostane `contextMenuIcon`, `showContextIcon`, `isFiltered`, `height`, `column` a `stateManager`. Vnější sort/drag wrappery zůstávají. | Tamtéž a `lib/src/model/trina_column.dart`, `TrinaColumnTitleRendererContext` | Použít předanou context ikonu; neimplementovat vlastní řazení nebo resizing. |
| Context ikona obsahuje i stav řazení a pointer obsluhu změny šířky. | `TrinaColumnTitle._buildContextMenuIcon`, `_buildContextMenuWidget` | Pouhá náhrada za tři tečky by odstranila důležité chování. |
| Žádný aktuální aplikační sloupec nenastavuje `titleRenderer` ani `titleSpan`. | Cílené `rg` nad `lib` při průzkumu | Není potřeba migrovat existující vlastní hlavičky. |
| Flutter poskytuje `TooltipState.ensureTooltipVisible`. | Lokální SDK, `packages/flutter/lib/src/material/tooltip.dart` | Jeden tooltip může obsloužit hover i explicitní aktivaci tlačítka. |

Tok: obrazovka vytvoří controller -> načtení může nahradit `columns` -> wrapper sestaví `TrinaGrid` -> TrinaGrid volá renderer hlavičky -> vysvětlení se zobrazí v overlay nad tabulkou. Žádné ukládání ani síťové operace.

## Rozhodnutý kontrakt

### Konfigurace a vlastnictví

- Přidat do `SingleDataGridController` volitelný `Map<String, String> columnHelp`, výchozí prázdná mapa. Uložit neměnnou kopii; platí po dobu života controlleru. Změna jazyka/textů používá stejný životní cyklus obnovy controlleru jako ostatní lokalizované názvy.
- Klíč je `TrinaColumn.field`, hodnota je již lokalizovaný prostý text. `trim().isEmpty` znamená nepřítomnou nápovědu. HTML, Markdown a interaktivní obsah nejsou součástí kontraktu.
- Klíč pro sloupec, který aktuálně není přítomen, je povolen: tabulky mají dynamicky vybrané sloupce. Skryté sloupce nevyvolávají žádné overlay.
- Přidat společný modul `lib/components/single_data_grid/data_grid_column_header.dart` pro renderer a jeho instalaci. Wrapper jej použije bezprostředně před předáním aktuálních sloupců do `TrinaGrid`, po načtení dat.
- Instalace musí být idempotentní: opakovaný build nesmí obalovat předchozí renderer, přidávat další ikony ani opakovaně zvětšovat minimum šířky. Konfigurace nepřítomné nápovědy nesmí změnit sloupec.
- Konfigurované sloupce jsou vlastněné controllerem; nesdílet stejný mutable `TrinaColumn` mezi souběžnými controllery. Nedělat kopii všech sloupců a jejich měnícího se runtime stavu.
- Kolize s cizím `titleRenderer` je chyba konfigurace s jasnou diagnostikou, nikoli tiché přepsání. Vlastní již nainstalovaný renderer rozpoznat. Pro `titleSpan` zachovat obsah jako `Text.rich` v textové části.
- `column.title` zůstává beze změny pro CSV, menu a ostatní spotřebitele. Nápovědu nepřidávat do názvu, dat buněk ani exportu.

### Vzhled a rozměry

- Hlavička používá aktuální styl TrinaGridu: výšku, padding, textové zarovnání, pozadí, svislý okraj, barvy a směr textu.
- Rozložení: případný checkbox výběru všech řádků, pružný název, info tlačítko, případná indikace filtru a předaná context/resize ikona. Dodržet podmínky knihovny pro checkbox (`enableRowChecked`, `rowCheckBoxGroupDepth`, `enableTitleChecked`). Veřejný `CheckboxAllSelectionWidget` je exportován přes UI knihovny; neimportovat privátní implementace.
- Název má jeden řádek s výpustkou. Info tlačítko má pevný prostor a nesmí se oříznout společně s názvem. Ikona přibližně 16-18 logických pixelů, samostatná hit oblast alespoň 40 x 40 při standardní výšce hlavičky.
- Minimální šířku u sloupce s nápovědou zvýšit jen podle potřebných ovládacích prvků: stávající minimum vs. padding + hit oblasti + mezery + malý prostor názvu. Zohlednit případný checkbox a rezervovat případný filtr předem, aby aktivace filtru nezpůsobila overflow. Při instalaci narovnat i počáteční `width`, pokud je pod novým minimem.
- Nepoužívat jednu velkou minimální šířku pro všechny sloupce. U sloupců bez nápovědy zachovat i velmi malé původní šířky. Fyzicky nemožné rozměry řešit minimem, ne zmenšováním ikony až k neklikatelnosti.
- Tooltip je mimo ořez sloupce, zalamuje dlouhé vysvětlení, má šířku omezenou například na 360 logických pixelů i dostupnou šířku viewportu. Primárně krátká vysvětlení, nikoli celé dokumenty.

### Interakce a životní cyklus

- Jediný Flutter `Tooltip` pro info tlačítko. Hover otevírá nápovědu po krátké prodlevě; `IconButton.onPressed` ji otevře přes lokální `GlobalKey<TooltipState>.ensureTooltipVisible`. Explicitní aktivace musí fungovat i s vnořeným tlačítkem; samotné nastavení `triggerMode: tap` není důkaz.
- Kliknutí/klepnutí na info se nesmí propagovat do řazení. Běžné kliknutí na název nadále řadí. Tažení z plochy názvu nadále přesouvá sloupec; tažení začaté na info nesmí přesunout sloupec. Pokud je třeba, zastavit gesto pouze uvnitř hit oblasti info tlačítka, nikoli na celé hlavičce.
- Tabulátor dosáhne info tlačítka, Enter/Space otevře nápovědu. Semantický popis obsahuje název sloupce a vysvětlení bez dvojitého čtení stejného tooltipu. Escape nápovědu zavře; nesmí změnit editaci buněk, pokud fokus není v nápovědě/tlačítku.
- Hover zavírá po opuštění; kliknutí mimo a Escape zavírají explicitně otevřenou nápovědu. Nastavit dostatečnou dobu zobrazení po klepnutí, například 10 s. Dlouhý stisk nesmí být jediný způsob otevření na mobilu.
- Klíč a případný stav patří konkrétní hlavičce, ne globálnímu singletonu. Odstranění sloupce, refresh nebo odchod z obrazovky nesmí zanechat overlay. Po přesunu a horizontálním scrollu nesmí zůstat bublina na neodpovídající pozici; využít životní cyklus Flutter tooltipu, chování ověřit.

## Upřesnění při implementaci

Lokální Flutter 3.47.2 (`packages/flutter/lib/src/widgets/raw_tooltip.dart`,
`RawTooltipState.ensureTooltipVisible`) výslovně uvádí, že ručně otevřený tooltip
zůstává viditelný do zavření. `showDuration` sám tuto aktivaci neomezuje.
Proto hlavička přidává lokální desetisekundový časovač. Veřejné API nabízí pouze
hromadné zavření tooltipů; Escape a změna polohy zavírají konkrétní tooltip
obnovou jeho lokálního klíče, která odstraní overlay přes běžný dispose.
Žádný další popover ani změna SDK/závislostí není potřeba.

`TrinaColumnTitleState.updateState` sleduje pouze sort; `rendererContext.isFiltered`
proto po změně filtru nemusí odpovídat skutečnosti. Společná hlavička odebírá
notifikace manageru a čte `stateManager.isFilteredColumn(column)` při buildu.
`FocusState.setKeepFocus` navíc při vstupu do scope vyžádá fokus buněk a standardní
Tab přesouvá buňky. Tabulka s nápovědou proto při vstupu řadí info tlačítka před
fokus gridu a dokončí fokus tlačítka po požadavku scope. Tab uvnitř buněk a Escape
při jejich editaci nadále zpracovává TrinaGrid. Test používá skutečný vstup přes
Tab z okolního ovládacího prvku, nikoli přímé spuštění `onPressed`.

## Implementační kroky

### 1. Společný kontrakt a hlavička

Změnit `single_data_grid_controller.dart`, přidat `data_grid_column_header.dart`, napojit `_buildDataGrid` v `single_table_data_grid.dart`. Přidat mapu, idempotentní přípravu aktuálních sloupců a renderer podle výše uvedeného kontraktu. Nepřepisovat controller, načítání dat, ukládání ani horní panel.

Výstup: libovolný controller může přidat nápovědy bez vlastní implementace hlavičky. Prázdná mapa ponechává standardní cestu knihovny. Obnovené instance sloupců dostávají nápovědy stejně jako původní. Žádná migrace ani mazání existujících implementací.

Ověření tohoto kroku je součástí závěrečné cílené dávky níže; nekontrolovat každý jednotlivý edit zvlášť.

### 2. Použití a důkaz chování

Přidat `test/components/single_data_grid/data_grid_column_header_test.dart` a stručný `lib/components/single_data_grid/README.md` s příkladem:

```dart
columnHelp: {
  UserColumns.EMAIL: UserStrings.emailHelp,
},
```

Jde o ilustrační API: `UserStrings.emailHelp` aktuálně není zavedený getter. README výslovně vysvětlí, že text/getter dodává volající podle významu konkrétního sloupce; do produkčního kódu nevkládat neexistující symbol. Testovací tabulka dodá skutečné lokální testovací texty.

Testy mají používat skutečný `TrinaGrid` v malém Flutter harnessu a alespoň jeden případ skutečného `SingleTableDataGrid` s in-memory modelem, aby prokázaly i napojení a reload. Model může implementovat `ITrinaRowModel` s lokálními operacemi; žádná autentizace, Supabase ani síť. Pokud wrapper vyžaduje lokalizaci či theme inicializaci, doplnit minimální stávající testový setup, neměnit kvůli testu produkční boot.

Výstup: použití je dokumentované a doložené vykonatelnými testy. Nelze dokončit pouze izolovaným testem tooltipu bez gridu. Žádné plošné doplňování překladů nebo náhodně vybrané produkční nápovědy.

## Cílená validace implementace

Spustit po koherentní implementaci, ne při plánování:

```sh
fvm dart analyze lib/components/single_data_grid/single_data_grid_controller.dart lib/components/single_data_grid/single_table_data_grid.dart lib/components/single_data_grid/data_grid_column_header.dart test/components/single_data_grid/data_grid_column_header_test.dart
fvm flutter test test/components/single_data_grid
```

Testovací matice:

1. Žádná mapa, chybějící klíč, prázdný/whitespace text: bez info tlačítka, nezměněný renderer a minimum šířky. Konfigurovaný nepřítomný klíč nezpůsobuje chybu.
2. Hover skutečným mouse pointerem, kliknutí, touch tap a aktivace klávesnicí: stejné vysvětlení; Escape/klik mimo zavře. Tap na info nezmění `column.sort`, tap na název jej změní.
3. Dlouhý název a dlouhé vysvětlení, počáteční šířka pod minimem, resize na minimum, filtrovaný sloupec a checkbox: žádný RenderFlex overflow; ikona a ovládání jsou dosažitelné. Prověřit úzký viewport a zvětšený text.
4. Menu funguje; řazení je vidět; filtr otevře správný popup; změna šířky funguje přes předanou ikonu. Drag názvu zachovává přesun; drag info jej nespustí.
5. Opakovaný rebuild a `forceReload` s novými instancemi sloupců: právě jedno info tlačítko, stabilní minimum, žádný starý tooltip. Zkontrolovat také skrytí/odebrání sloupce a scroll s otevřenou nápovědou.
6. Hlavička bez nápovědy zůstává funkční vedle hlavičky s nápovědou. CSV zachová původní názvy bez vysvětlení. Light/dark styly a zarovnání používají konfiguraci gridu.

Testy seskupit podle uživatelských scénářů, ne podle jednotlivých interních helperů. Nepsat snapshot testy lokalizovaných vět. Běžná lokální implementace vyžaduje uvedené cílené kontroly; před samostatně autorizovaným publikováním uplatnit i publikační brány z `CONTRIBUTING.md`, včetně plné sady, pokud jsou v tu chvíli vyžadované. Browser/server není pro plán ani tyto widgetové testy potřeba.

## Předpoklady a rizika

- **Předpoklad:** nápovědy jsou krátké texty pevné po dobu života controlleru. Pokud bude požadována aktualizace bez jeho obnovy nebo bohatý obsah, jde o rozšíření kontraktu, ne důvod preventivně přidat nový stavový systém.
- **Riziko:** vlastní renderer nahrazuje i nenápadné standardní prvky. Implementátor porovná jen dotčené části `_DefaultColumnTitleContent` a `_ColumnTextWidget` zamčené verze a zachová jejich relevantní chování; nekopírovat celou knihovnu.
- **Riziko:** Flutter tooltip a vnější gesta gridu mohou kolidovat. Vyřešit a prokázat skutečnou integrací, ne pouze očekáváním podle API. Pokud současné SDK nesplní konkrétní požadavek, nejprve zaznamenat důkaz a upravit tento plán; nezavádět souběžný tooltip a popover pro stejnou nápovědu.
- **Riziko:** obnovení `columns` přes prosté `reloadData` nyní pouze aplikuje řádky do existujícího manageru. Neměnit obecnou sémantiku reloadu; nápověda musí fungovat při skutečném vytvoření hlaviček a při `forceReload`. Případnou nezávislou chybu reloadu popsat odděleně.
- **Blokery:** žádné pro implementaci sdílené funkce. Konkrétní produkční sloupce a jejich texty se mohou doplňovat samostatně.

## Dokončení a návrat změny

- [x] Existuje jedna společná konfigurace a jeden renderer, žádné kopie po obrazovkách.
- [x] Bez textu zůstává standardní hlavička beze změn; s textem funguje hover, tap i klávesnice.
- [x] Ikona se při podporované minimální šířce neztrácí a nápověda není oříznutá sloupcem.
- [x] Řazení, filtrování, resize, přesun a checkboxy zůstávají funkční.
- [x] Reload a odstranění widgetu nezanechají duplicity ani overlay.
- [x] Cílené testy a analýza prošly, případné nesouvisející selhání je přesně doložené.
- [x] README vysvětluje zapojení; žádné placeholdery v produkčním kódu, nové závislosti, změny dat ani tenantů.

Deletion ledger: žádná původní cesta se neruší. Standardní renderer TrinaGridu zůstává záměrnou cestou pro sloupce bez nápovědy. Vrácení funkce znamená odstranění nového napojení, konfigurace a souvisejících testů/dokumentace; nemá datové ani provozní důsledky. Nasazení a publikování nejsou součástí této práce.

## Výsledek ověření

`fvm flutter test --no-pub test/components/single_data_grid`: 11 testů prošlo.
Cílená analýza podle zadání: bez chyb a varování; zůstávají čtyři původní
informační diagnostiky v `single_table_data_grid.dart` (privátní návratový typ
`createState` a tři použití `withOpacity`). Implementace, README a widgetové
integrační testy jsou připravené lokálně; commit ani publikace nebyly provedeny.
