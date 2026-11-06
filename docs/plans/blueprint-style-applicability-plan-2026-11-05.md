# Jednotná pravidla dostupnosti nastavení vzhledu

Stav: dokončeno lokálně a integrováno do Festapp. Ověřování: cílené kontroly
standard pro sdílené chování editoru; bez publikace a produkčního nasazení.

## Cíl a hranice

Objekt nabízí pouze nastavení, která odpovídají jeho typu a tvaru. Inspector,
rychlý dialog a globální nastavení používají stejná pravidla. Zachovat existující
dědění stylů, uložené plánky a dokončenou opravu stavových značek.

Tento navazující úkol sjednocuje rozhodování editoru. Není to přepis modelu,
nová hierarchie tříd ani optimalizace rendereru. Dosavadní oprava je funkční;
nový krok má zjednodušit další údržbu. Produkční nasazení není součástí.

## Ověřený výchozí stav

Cesty níže jsou relativní ke kanonickému repozitáři balíčku:

- `packages/venue_layout_core/lib/src/model.dart`, `resolveNodeAppearance`:
  core defaults → document label defaults → kind defaults → table child-seat
  defaults → node override. Vnořené label listy se slučují jednotlivě.
  `patchCanonicalStyle` rozlišuje explicitní hodnotu a odstranění přepsání.
- `packages/venue_layout_core/lib/src/canonical_contract.dart`: metadata
  uložených listů a podporovaných typů. Nejde o kompletní pravidla zobrazení UI.
- `lib/src/layout_editor/widgets/canonical_appearance_panel.dart`: společný
  panel pro node/kind/children/document scope; podmínky media/openPath/labelVisible
  a další podmínky dostupnosti jsou zatím přímo v sestavení widgetů.
- `lib/src/layout_editor/widgets/layout_style.dart`: nový
  `layoutHasConstructionStyle` sdílí podmínku seat/table/furniture; rychlý dialog
  k ní samostatně přidává group/global scope.
- `lib/src/layout_editor/layout_scene_cache.dart`, `LayoutSceneCache.update`:
  scéna již používá inkrementální aktualizace. Její přepis není potřeba.

Referenční oprava je v commitu `c069b04d6eb738c01dbc2afdc095b359001d264f`,
aktuálně dostupném v `/private/tmp/festapp-venue-current`. Festapp má její ověřené
archivy v `vendor/blueprint/manifest.json`; vendored kopie se přímo neupravují.
Pokud worktree chybí, najděte commit v repozitáři
`/Users/miakh/source/venue_seat_picker` a vytvořte z něj izolovaný worktree.

## Rozhodnutí

1. Zachovat jeden resolver a řídká lokální přepsání. Rozlišení schopností objektu
   řešit kompozicí a malou čistou interní politikou editoru, nikoliv podtřídou
   pro každou kombinaci typu, tvaru a stylu.
2. Dostupnost ovládání není validace uložených dat. Skrytí volby nesmí mazat
   existující deklarace, měnit kaskádu ani zavádět nový serializovaný formát.
3. Použít nejmenší interní reprezentaci skutečně potřebných podmínek v pickeru.
   Nepřidávat generický registry/plugin systém, druhý seznam výchozích stylů
   nebo veřejné core API jen kvůli interním widgetům.
4. Konstrukce patří sedadlům, stolům a podporovanému nábytku. Výplň, obrys,
   text a zaoblení mají vlastní dostupnost. Otevřená čára nemá výplň ani
   konstrukci. Media nezískají textové či nábytkové volby jen společným předkem.
   Globální a skupinové předvolby jsou záměrné agregované operace, nikoli
   důvod označit samotnou skupinu za nábytek.

## Realizace ve dvou krocích

### 1. Sjednotit současné rozhodování

Ve výše uvedených dvou UI souborech projít pouze existující podmínky dostupnosti.
Vyčlenit jejich společné, duplicitní části do jedné interní čisté politiky
(v existujícím souboru, případně jediném malém souboru vedle panelu).
Vstupy: efektivní cíl úpravy a scope; pro agregované operace jen potřebný kontext.
Výstup: dostupná současná ovládání. Nevytvářet schopnosti pro hypotetické funkce.

Převést inspector i rychlý dialog. Scope children musí vyhodnotit sedadlo, scope
kind zvolený typ. Zachovat záměrné global/group operace a nezávislé nastavení
barev, obrysů a textu. Smazat nahrazené podmínky a původní helper, pokud jej nová
politika nahrazuje; neponechat paralelní rozhodovací cestu. Neodstraňovat běžné
kontroly typu při vykreslování geometrie, které mají jiný účel.

Hotovo: stejné cíle mají v obou vstupních bodech stejnou dostupnost; rozdíly
způsobené scope jsou explicitní. JSON, undo/reset i výsledek resolveru se nemění.

### 2. Ověřit a integrovat jednou

Rozšířit `test/layout_construction_controls_test.dart` o skutečné přesuny scope,
čáru, text, image/vector a group/global operace. Neověřovat jen samotné boolean
gettery. Existující `test/layout/canonical_appearance_test.dart` a core
`test/appearance_test.dart` použít pro dědění, lokální přepsání a návrat k dědění;
nové případy přidat pouze pro dosud nepokrytý kontrakt. Opravu značek neopakovat.

Provést jednu cílenou validační dávku po ucelené změně, Flutter sériově
s `--concurrency=1`. Pokud se mění balíček, připravit jeho ověřené archivy podle
`tool/archive_check.sh`, importovat přes
`automation/blueprint_vendor_artifacts.py`, aktualizovat vybraný pnpm archiv
se zachováním immutable souborů a ověřit host archive/lock/hash contract.
Při zachování stávajících změn použít postup doložený předchozím plánem, ne
přepsání pracovního stromu. Náročné distribuční kontroly spustit až na finálních
vstupech a neopakovat bez změny pokrytých vstupů.

## Úsporné provedení a podmínky dokončení

Začít jmenovanými symboly a testy, nehledat znovu v celém projektu. Bez nového
architektonického auditu, benchmarku nebo dalších agentů na implementaci.
Rutinní build/browser delegaci ponechat podle AGENTS.md. Nepřidávat cache bez
měření problému. Tokenovou úsporu nevyčíslovat bez srovnatelného měření.

Hotovo znamená jednu politiku dostupnosti, zachované dědění a uložená data,
odstraněné nahrazené podmínky, cílené testy a konzistentní host archivy.
Žádné schéma, migrace, nový renderer, registry publication nebo nasazení.
Předpoklad: většina stávajících podmínek vyjadřuje záměrné chování; případný
rozpor s rendererem doložit jedním konkrétním případem a opravit v tomto rozsahu.
Blokery při přípravě plánu nejsou. Hlavní riziko je zaměnit dostupnost UI se
sémantikou starých deklarací; obě odpovědnosti musí zůstat oddělené.


## Výsledek realizace

- Kanonický zdroj: commit `adf4a8000466d3c5c863ecae1413233ed101cbca`
  v `/private/tmp/festapp-venue-current`, navazuje na referenční opravu značek.
- Interní `widgets/appearance_controls.dart` vlastní dostupnost konstrukce,
  výplně, obrysu, textu, zaoblení a opacity. Panel i rychlý dialog používají
  tutéž politiku; nahrazený `layoutHasConstructionStyle` byl odstraněn.
  Scope children předává sedadlo, kind vybraný typ; group/document předvolby
  zůstávají explicitně agregované. Barevné palety zůstávají nezávislé.
- Konkrétní nesoulad původního UI: otevřená čára měla v Advanced appearance
  nabídku Corner radius přes podmínku `!media && target.kind != 'text'`.
  Politika ji nyní skrývá spolu s výplní. Deklarace ani resolver se nemění.
- Ověření: 12 widget testů dostupnosti včetně skutečných přepnutí scope,
  14 stávajících widget testů vzhledu, 4 core testy dědění a cílený Dart
  analyzer prošly. Nové scénáře porovnávají i JSON před a po procházení UI.
- Distribuční gate `tool/archive_check.sh` proběhl jednou na finálním commitu:
  360 produkčních importů, 92 core a 254 picker souborů shodných se zdrojem,
  4 testy čistého konzumenta, 15 npm scén a start archivované Flutter ukázky.
  Výstupy: `build/qa/style-applicability-20261105` v kanonickém worktree.
- Host import přes `automation/blueprint_vendor_artifacts.py` prošel;
  `vendor/blueprint/manifest.json` zaznamenává zdroj a hashe 346 souborů.
  JS archiv zůstal bajtově shodný:
  `festapp-venue-layout-0.3.9-a167f6fadc9f.tgz`. Pnpm lock i frozen offline
  instalace odpovídají vybranému immutable archivu. Host archive/lock/hash
  contract a 4 Flutter testy focus/navigation prošly.
- Původní integrační vstupy a vybraný archiv jsou zachovány v
  `.codex-artifacts/blueprint/style-applicability-20261105/previous-inputs/`.
  Rozpracované nesouvisející změny zůstaly zachovány. Blokery nejsou.
