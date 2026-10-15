# Další příležitosti pro odložení vlastního kódu

Navazuje na [první průzkum](flutter-bundle-opportunities-2026-10-15.md). Stejný izolovaný snapshot kanonického main `488988612`, Flutter 3.47.2 / Dart 3.13.2 a stejná konfigurace i přepínače. Produkce se neměnila.

## Nová měření

| Varianta | Hlavní JS | Úbytek hlavního JS | Úbytek hlavního JS při Brotli Q9 |
| --- | ---: | ---: | ---: |
| Základ | 10 978 187 B | - | - |
| Správa programu + dobrovolnická časová osa | 10 812 912 B | 165 275 B | 39 466 B |
| Celý textový editor, jeho řadič a editor novinek | 10 210 993 B | 767 194 B | 176 657 B |
| Společná varianta popsaná níže | 9 846 501 B | 1 131 686 B (10,31 %) | 263 383 B (10,62 %) |

Společná varianta zahrnuje textový editor s editorem novinek, správu programu a dobrovolníků, návrhář vstupenek a editor formulářů. **Nezahrnuje odložený mapový runtime.** Úspora pochází ze skutečného společného buildu, nikoli ze součtu jednotlivých odhadů.

Brotli Q9 je stejné lokální nastavení pro všechny varianty, nikoli přesné nastavení CDN. Po kompresi má hlavní JS základní varianty 2 479 487 B a společné varianty 2 216 104 B. Jde o úsporu hlavního JS; ostatní úvodní soubory, například CanvasKit, zůstávají.

## Nejlepší kandidát: celý textový editor

V původním kódu se v `rich_html_editor_controller.dart` potkávají konkrétní editor, rodičovská správa rozpracovaných změn a společné widgety pro jejich ukládání. Tabulky potřebují správu změn a tím si přitahují celý editor.

Prototyp ponechává v úvodním kódu `HtmlSaveCoordinator`, `HtmlEditingScope` a lehký kontrakt `HtmlDraftController` se třemi vlastnostmi: HTML, původní HTML a příznak změn. Konkrétní řadič, dokument a UI se načítají odloženě. Odložené vstupy jsou:

- inline HTML pole,
- editorový dialog,
- obrazovka editoru novinek.

Třetí vstup je podstatný: kdyby editor novinek zůstal přímo dostupný přes router se svou těžkou implementací, držel by editor dál v hlavním JS. Stejně musí být odložena implementace inline pole, nestačí změnit samotný dialog.

Dump-info potvrzuje, že ze 118 knihoven `super_editor` už 113 nemá žádného potomka přiřazeného hlavnímu výstupnímu souboru. Pět knihoven má nadále sdílené odkazy na main i odloženou část. Netvrdíme tedy, že z hlavního souboru zmizel každý symbol balíčku. Největší nová sdílená editorová část má přibližně 745 kB před kompresí.

Toto je nejvýnosnější jednotlivý z dosud změřených zásahů do struktury našeho kódu. Odkládá také závislosti, které náš editor přitahuje.

## Správa programu a dobrovolníků

Prototyp má dvě lehké fasády nad `ScheduleContent` a `ActivitiesContent`. Modely, oprávnění a sdílené služby zůstávají dostupné; těžké widgety se načtou při otevření příslušné části. U programu je zachovaný lehký vstup `reloadIfClean`, který používá podezřelý program při návratu do záložky.

Naměřených 165 kB je podstatně méně než součet veškerého kódu programu a aktivit. Veřejné události, společné databázové funkce, tabulky a modely jsou dál dosažitelné z ostatních obrazovek. Tento experiment tedy není oddělením celého veřejného programu jako jednoho produktu.

## Upřesnění map a MapLibre

Původní mapový pokus odložil naši implementaci stránky mapy a část závislostí. Samotný Dart webový plugin MapLibre zůstal v hlavním souboru. Automaticky generovaný `web_plugin_registrant.dart` při startu přímo volá `MapLibrePlugin.registerWith(registrar)`.

Kompilátor připisuje `maplibre_web` přibližně 9,65 kB kódu. Rozhraní `maplibre_platform_interface` má dalších přibližně 5,76 kB a v experimentu je rozdělené mezi hlavní a odložený soubor. Tyto hodnoty se týkají Dart adaptéru a rozhraní, nikoli velikosti externího MapLibre GL JS enginu. Původní úspora 226 kB proto nebyla odložením celého MapLibre enginu.

## Náklad rozdělení a PWA

Společný build má 16 odložených JS souborů včetně již existujícího katalogu fontů. Po kompresi se celý soubor všech JS mírně zvětšil:

- základ: 3 023 327 B,
- společná varianta: 3 068 424 B,
- rozdíl: +45 097 B, přibližně +1,49 %.

Úvodní hlavní soubor je tedy menší, ale celý kód není celkově menší. Existující PWA instalační mechanismus zahrnuje všechny `main.dart.js_<n>.part.js` do instalačního jádra. Zachování tohoto mechanismu znamená, že se odložené funkce připravují pro offline provoz, a jejich přenos může probíhat souběžně se startem. Přenos z hlavního souboru proto nelze označit za stejnou úsporu celého prvního načtení PWA.

## Co výsledky dokazují a co zbývá

Všechny tři finální varianty prošly release kompilací. U editoru bylo při prvním pokusu potřeba doplnit explicitní import typu `HtmlMediaDraft`, poté build prošel. Společná varianta byla ověřena podle skutečných odložených vstupů; mapový runtime v ní odložen není.

Výsledky dokazují velikost a kompilovatelnost. **Nedokazují časové zrychlení, bezztrátové chování formulářů nebo připravenost k nasazení.** Před implementací do main je potřeba dopracovat chybové stavy a opakování načítání, zachování konceptů při změně identity, focus editoru, návrat do záložek a asynchronní zavření obrazovky. Potom ověřit skutečné načtení chunků při přímém vstupu do objednávek, čas do použitelné tabulky a offline první otevření funkcí i staré karty po aktualizaci PWA.

Doporučená první implementace je oddělení textového editoru. Ostatní moduly mohou následovat v další malé změně; jejich samostatný přínos je menší.

## Evidence

[Strojový souhrn](flutter-bundle-opportunities-2026-10-15/followup-summary.json), [přiřazení knihoven editoru do výstupních částí](flutter-bundle-opportunities-2026-10-15/html-editor-dependencies.json), [přiřazení mapových závislostí](flutter-bundle-opportunities-2026-10-15/map-module-dependencies.json), [prototyp rozdělení editoru](flutter-bundle-opportunities-2026-10-15/html-editor-experiment.patch).

Celé buildy a dump-info jsou v `/tmp/festapp-bundle-audit-20261015`, přípravné skripty a logy pokračování v `/tmp/festapp-bundle-audit-more-20261015`. Základní příkaz je shodný s prvním průzkumem, mění se pouze `--output`. Žádné produkční soubory ani uživatelova browser session se při tomto pokračování neměnily.
