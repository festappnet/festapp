# Příležitosti pro rozdělení Flutter webu - 2026-10-15

Novější výsledky: [odložení celého textového editoru, programu a společný build](flutter-bundle-opportunities-followup-2026-10-15.md). Následující text zachovává první fázi průzkumu.

## Co bylo skutečně změřeno

Produkce vstupenky.online má verzi `0.20.212+696`. Pro rozpad kódu a experimenty vznikla izolovaná kopie kanonického `origin/main`, commit `488988612`. Základní build a tři jednotlivé experimenty používají stejné zdroje, konfiguraci, Flutter 3.47.2 / Dart 3.13.2 a přepínače. Produkční aplikace se neměnila.

Lokální základ má hlavní JS 10 978 187 B; živá verze měla při předchozím měření 10 961 048 B. Jde o porovnání experimentů proti stejnému lokálnímu základu, nikoli přesnou reprodukci tenant release. Neběžel release postprocessing fontů; zde uvádíme JS, nikoli úspory fontových souborů.

| Samostatně odložená část našeho kódu | Hlavní JS po změně | Úbytek hlavního JS | Úbytek po stejné Brotli kompresi |
| --- | ---: | ---: | ---: |
| Základ | 10 978 187 B | - | - |
| Mapový runtime | 10 752 610 B | 225 577 B (2,05 %) | 60 138 B (2,43 %) |
| Návrhář vstupenek | 10 873 839 B | 104 348 B (0,95 %) | 24 777 B (1,00 %) |
| Editor formulářů | 10 885 032 B | 93 155 B (0,85 %) | 20 411 B (0,82 %) |

Brotli používá lokálně quality 9. Základ má při tomto nastavení 2 479 487 B; nejde o přesné nastavení CDN. Varianty byly sestaveny jednotlivě. Jejich úspory nelze bez společného buildu sčítat. Nebyl změřen časový přínos ani chování těchto prototypů v UI. Nové části navíc mírně zvyšují celkovou velikost JS.

## Náš kód v úvodním balíku

Kompilátor připisuje balíčku `fstapp` přibližně 2,70 MB generovaného kódu. Jednotlivé knihovny a jejich součty nejsou přesnou velikostí přenosu ani velikostí samostatně odstranitelného modulu; sdílejí runtime, konstanty a závislosti.

| Oblast | Příspěvek knihoven před kompresí | Význam pro vstup do objednávek |
| --- | ---: | --- |
| Eshop | 296 kB | Značná část je potřeba; oddělit lze konkrétní vedlejší nástroje |
| Formuláře | 288 kB | Smíchané veřejné zobrazení, datové modely a editory |
| Program | 170 kB | Další kandidát pro samostatný funkční modul |
| Návrhář vstupenek | 164 kB | Prototyp reálně odložil jen 104 kB, ostatní zůstává sdílené |
| Mapy | 151 kB | Prototyp odložil i některé závislosti, celkem 226 kB |
| Aktivity / dobrovolníci | 119 kB | Další kandidát, samostatný experiment zatím neproběhl |
| HTML komponenty | 83 kB | Přitahují textový editor přes společná rozhraní |
| Blueprint / plán sálu | 63 kB | Část používají i rezervace, nelze ji celou automaticky odložit |

### Důležitá vazba: společné tabulky a textový editor

`single_data_grid_controller.dart` a `single_table_data_grid.dart` přímo importují `rich_html_editor_controller.dart`. Stejný soubor obsahuje editor, `HtmlSaveCoordinator`, `HtmlEditingScope` a identitu pole. Současně importuje `super_editor`. Také `data_grid_helper.dart` přímo používá editorový dialog.

Proto pouhé přesunutí widgetu editoru do odloženého souboru nestačí k odložení celého editoru. Nejdřív je třeba oddělit lehké rozhraní pro rodičovský koncept/ukládání od konkrétní implementace editoru. Teprve pak lze načítat textový editor při aktivaci pole nebo otevření dialogu. Balíček `super_editor` má v tomto buildu příspěvek přibližně 417 kB a naše HTML komponenty dalších 83 kB; nejsou to potvrzené sčitatelné úspory.

### Další vazby našeho kódu

- Router má `deferredLoading: false` a odkazuje na všechny obrazovky. Zobrazení jen jedné záložky proto neznamená samostatný síťový balík.
- `FeatureForm` přímo importuje `TicketSettings`, které importuje návrhář. Prototyp odložil návrhář až před otevřením dialogu a přesunul návratový typ `TicketLayoutResult` do lehkého společného souboru.
- Mapové routy a ostatní stránky používají `MapEditorMode`, `MapPage.ROUTE` a `MapPage.isEditingNotifier`. Prototyp ponechal tento kontrakt v lehké fasádě a odložil implementaci mapy. Nevytvářel stovky routových částí.
- Editor formulářů má i režim používaný průvodcem vytvoření akce. Prototyp ponechal konstruktor a datové typy ve fasádě a odložil editor i generátor jeho polí. Stejné sdílené editory zůstávají dosažitelné jinými cestami.

## Co se načítá na produkci

Předchozí živé měření současné verze zachytilo hlavní JS (přibližně 2,90 MB přenos / 10,96 MB po rozbalení), CanvasKit WASM (2,01 MB přenos / 5,43 MB po rozbalení), malý CanvasKit JS a devět fontových požadavků. Při přímém vstupu do správy jednotky nepozorovalo stahování mapových dlaždic ani editorových chunků; jejich Dart kód je součástí hlavního JS.

Katalog Google Fonts je již oddělený: `main.dart.js_1.part.js`, 10,11 MB před kompresí. PWA worker tento kód stahuje během instalace do cache. To zachovává možnost použít oddělený kód offline, ale rozdělení nesnižuje celý instalační objem. `PRECACHE_URLS` v workeru obsahuje i jiné renderery; jejich pouhá přítomnost v seznamu neznamená úvodní stažení. Instalace používá užší `CORE_URLS`, které další CanvasKit/WASM varianty neobsahuje.

Z větších knihoven dále zůstává `timezone` (806 kB), `flutter_localizations` (466 kB), `super_editor` (417 kB), `trina_grid` (247 kB) a `image` (88 kB). Časová pásma jsou nyní záměrně vložená do kódu kvůli dřívější chybě síťového načítání; vrátit je bez náhrady na síť by obnovilo toto riziko. Grid potřebují přímo objednávky, jeho odložení proto tuto obrazovku zásadně neodlehčí.

## Doporučený postup

1. Zachovat jednu aplikaci a jeden tenant konfigurační mechanismus. Zkoušet odložené funkční moduly, například mapy, návrhář vstupenek a editor formulářů. Samostatné pub balíčky nejsou podmínkou rozdělení výsledného JS.
2. Pro větší úsporu rozdělit společné rozhraní HTML konceptů/ukládání od editoru. Tato vazba drží editor i tam, kde se právě needituje. Následně změřit celý editor jako modul.
3. Pokud bude požadován širší zásah, samostatně změřit modul programu a dobrovolníků. Oddělit lehké modely a routové argumenty od obrazovek; zatím nemáme potvrzenou velikost této úspory.
4. Před produkční změnou změřit i čas startu a první otevření odložené funkce. Ověřit offline první otevření a starou kartu po aktualizaci PWA. Dosavadní prototypy prokazují velikost a kompilovatelnost, nikoli připravenost k nasazení.

Největší změřená jednotlivá příležitost v našem kódu jsou mapy, ale ani ty samy nesníží úvodní přenos dramaticky. Významnější rozdělení vyžaduje odstranit konkrétní vazby mezi společnými službami a editory.

## Reprodukce a evidence

Izolované zdroje a celé buildy: `/tmp/festapp-bundle-audit-20261015`. Základní příkaz ve zdrojové kopii:

```sh
fvm flutter pub get --offline
fvm flutter build web --release --no-pub --base-href / \
  --no-web-resources-cdn --no-wasm-dry-run --dump-info \
  --output /tmp/festapp-bundle-audit-20261015/baseline
```

Stejné přepínače byly použity pro všechny tři varianty. Všechny čtyři finální buildy prošly. Mapový prototyp měl při prvním pokusu chybějící dva importy lehkých typů; po jejich doplnění build prošel. Neproběhly UI, offline ani časové testy prototypů. Nepublikoval se commit ani release.

[Strojový souhrn](flutter-bundle-opportunities-2026-10-15/summary.json), [živý PWA inventář](flutter-bundle-opportunities-2026-10-15/live-pwa-inventory.json), [prototyp editoru formulářů](flutter-bundle-opportunities-2026-10-15/form-editor-experiment.patch). Pomocné `prepare-*.py` jsou záznamy scratch experimentů a závisejí na původních souborech uložených v uvedeném dočasném adresáři; nejsou instalační skripty.

Oficiální popis mechanismu: [Dart deferred loading](https://dart.dev/language/libraries#lazily-loading-a-library). Konkrétní velikosti a vazby v tomto dokumentu pocházejí z místních buildů a kódu projektu.
