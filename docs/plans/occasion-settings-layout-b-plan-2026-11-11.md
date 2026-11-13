# Nastavení celé akce: varianta B ve skutečném Flutteru

Datum: 2026-11-11
Stav: implementováno lokálně; viz [výsledek a ověření](occasion-settings-layout-b-RESULT-2026-11-11.md)
Ověřování plánování: low-risk, jeden cílený průzkum, bez spouštění testů
Ověřování implementace: standard pro společnou validaci a ukládání; cílené kontroly na konečném kódu

## Výsledek a autorita

Implementovat propracovanou variantu B pro **Nastavení celé akce**, nikoli Nastavení konkrétního formuláře. Prvním vizuálním výstupem bude skutečné Flutter UI se skutečnými editory funkcí a bezpečnými ukázkovými daty, otevřené v hlavním Chromu. HTML není výsledná implementace.

Vizuální reference: `docs/previews/occasion-settings-variants/variant-b-refined.html#features`. Funkční inventář a výzkum: `docs/previews/occasion-settings-variants/proposal.md`. Přednost před zjednodušením HTML mají stávající Flutter komponenty, jejich podmínky a tento plán.

- Souvislý dokument se sekcemi Údaje o akci, Vzhled a viditelnost, Funkce a Pokročilé. Smazání je oddělená poslední oblast.
- Desktop má kompaktní navigaci **nad vlastním scrollem**, nikoli osnovu vlevo ani překrývající sticky vrstvu.
- Funkce jsou přehledné dlaždice; skutečný editor se otevře přes celou šířku pod příslušným řádkem. Nastavit a zapnout/vypnout jsou odlišné akce.
- Mobil má svislé rozbalovací kapitoly a jeden sloupec funkcí. Nejde o zmenšený desktop.
- Zůstává jedna spodní lišta Uložit / Zahodit pro akci a stávající samostatný vlastník uložení rozložení vstupenky.

Tato úloha nevytváří aplikační změnu, commit, push, migraci ani nasazení. Pozdější pokyn k realizaci autorizuje implementaci a lokální Flutter náhled podle tohoto plánu; produkční publikace se řeší podle tehdy platného zadání a publikačních bran.

## Pracovní místo a rozsah

Ověřený kanonický zdroj při původním průzkumu: `origin/main` = `f3752a0d94e7f9925edf4628de6829ca25c46faa`. Pracovní kořen je na `docs/festapp-tickets-readme-20261107`, HEAD `742d614b722bbe619b3a095f66605bd4bb536006`, s rozsáhlými cizími rozpracovanými změnami.

Realizace používá `/Users/miakh/source/festapp-occasion-settings-b`, větev `feat/occasion-settings-layout-b-20261111`, výchozí aktuální `origin/main` `a0cc06649`. Na tomto main neexistuje `test/browser/form_editor_layout_preview.dart`; fixture proto vychází z existujícího `product_price_waves_preview.dart` a veřejného AutoRoute vzoru. Odebrání obrázku je již pouze odpojení v konceptu, bez vzdáleného mazání. Přímé wallet readiness, delivery preview a wallet upload účinky byly přesunuty pod injektovaný `TicketLayoutService`, s původními produkčními defaulty.

Při realizaci založit čistý worktree z aktuálního autoritativního main. Nečistit současnou kopii, nepřepínat ji násilně a nekopírovat celý její diff. Přenést jen schválené referenční dokumenty, pokud v novém worktree dosud nejsou. Změna patří do sdíleného kódu; žádná automatická propagace do dalších `prod/*`.

V rozsahu jsou rozložení, navigace, prezentace funkcí, nezbytné veřejné UI propojení pro validaci a skutečný Flutter preview. SQL, RPC, platby, pravidla způsobilosti funkcí, oprávnění, média a ticket designer se znovu neimplementují.

## Potvrzený současný stav

| Fakt | Zdroj a důsledek |
| --- | --- |
| Nastavení je jeden dlouhý formulář omezený na `StylesConfig.formMaxWidth`. | `occasion_settings_tab.dart`, `_buildHtmlParent`: kompozice se rozšíří, vlastníci hodnot zůstanou. |
| Rodič vlastní koncept, `_formKey`, `_snapshot`, `_draftRevision`, `_htmlSave`, načítání a zápis. | `_draftChanged`, `_saveSettings`, `_performHtmlSave`, `_loadData`: navigace nesmí založit další koncept nebo ukládat. |
| Některé hodnoty se přenesou do modelu až přes `onSaved`. | Základní pole a `features/editors/form_feature_editor.dart`: nelze editory při přepnutí prostě zničit a obnovit z modelu. |
| Funkce se filtrují podle názvu i popisu a podpory aplikace; dělí se na zapnuté a ostatní. | `OccasionFeaturesSection.build`, `FeatureMetadata`, `FeatureService.appSupportedFeatures`: tato projekce zůstane jediná. |
| `FeatureForm` současně poskytuje ExpansionTile, vlastní kopii `isEnabled` a editor. | `feature_form.dart`: nahradit tuto prezentační cestu gridem a hosty; nezavádět další kopii stavu zapnutí. |
| Výběr skutečného editoru už existuje. | `buildFeatureSettingsEditor`: zachovat dispatcher všech typů, včetně `TicketSettings(key: ValueKey(feature.layout))`. |
| Zapnuté funkce jsou dnes při prvním zobrazení rozbalené. | `FeatureForm.initiallyExpanded`: jejich pole jsou registrovaná pro validaci. Lazy vytvoření pouze vybraného editoru by změnilo rozsah validace. |
| Vypnutá funkce dnes nemá vytvořená editační pole. | `FeatureForm.children`: skrytý ponechaný editor nesmí nově blokovat uložení validací vypnuté funkce. |
| Vzhled vstupenky má samostatné uložení a řešení konfliktů. | `onSaveTicket`, `TicketLayoutSaver`, `TicketSettings`: tuto cestu nepřesměrovat na obecné uložení akce. |
| Timezone je dnes v pokročilých volbách; identita a hodnoty data jsou u rodiče. | `OccasionAdvancedSettings`, `_selectedTimezone`, `_from`, `_to`: přesunout stejné pole k termínu, nezměnit časovou semantiku. |
| Zápisy a některé náhledy mají skutečné externí účinky. | `DbOccasions.updateOccasion`, `refreshSavedOccasion`, `DbImages.uploadImage`, `_removeImage`, ticket service a HTML media: preview musí mít výslovně izolované I/O. |

## Cílové rozložení

### Široká a střední plocha

Použít `LayoutBuilder` nad skutečně dostupnou plochou. Maximální šířka dokumentu je přibližně 1210 logických px včetně paddingu; nezachovat starý limit 680 px pro celý grid.

1. Údaje: název, termín, místo; timezone přímo u termínu jako podružná rozbalovací volba. Datum/čas používají dosavadní picker.
2. Vzhled a viditelnost: skutečný obrázek a HTML editor; na dostatečné šířce vedle nich stávající `OccasionCard` jako prezentační náhled. Veřejnost detailů, skrytí v seznamech a propagace zůstávají třemi nezávislými volbami.
3. Funkce: hledání, Zapnuté a Další funkce, grid a skutečný vybraný editor.
4. Pokročilé: uložený odkaz/historie a e-mail pro odpovědi s existující dědičností.
5. Oddělené smazání s původními podmínkami.

Navigace sekcí zabírá vlastní řádek nad `Expanded` se svislým scrollem. Spodní `EditorActionBar` zůstává mimo scroll. Žádná vrstva nesmí zakrýt tlačítka po automatickém posunu; tento problém byl v HTML návrhu opraven a nesmí se vrátit ve Flutteru.

Grid rozhoduje podle **vnitřní šířky po paddingu**: 3 sloupce od přibližně 900 px, 2 od přibližně 600 px, jinak 1. Mezery 12-16 px, minimální pohodlná šířka dlaždice přibližně 288 px. Při velkém písmu počet sloupců snížit; nevynucovat pevný aspect ratio, který ořízne český text.

### Telefon

Při lokální šířce nejvýše přibližně 700 px přepnout celý dokument na mobilní kompozici a vynutit jeden sloupec funkcí. Horní navigační řádek se vůbec nevytváří. Kapitoly se otevírají nezávisle; Údaje jsou zpočátku otevřené. Jejich zavření schová obsah i fokus, ale nezničí jeho stav.

Obrázek, popis a náhled se skládají svisle, náhled může být rozbalovací. Vybraný editor je hned pod svou dlaždicí. Spodní akce zůstávají dosažitelné i s klávesnicí a safe-area insetem; žádné vodorovné přechody nebo posun stránky.

## Matice zachování

| Oblast | Zachovaná cesta nebo invariant |
| --- | --- |
| Údaje a termín | Dosavadní title/place `onSaved`, `TimeDateRangePicker`, timezone validace a časové hodnoty. |
| Média a popis | `ImageArea`, dosavadní upload/ořez/odebrání, `EditableHtmlField`, `HtmlSaveCoordinator` a existující media owner. |
| Viditelnost | Původní tři booleany, `AppConfig.isAppSupported`, podmínka obrázku pro propagaci a její zrušení po odebrání obrázku. |
| Pokročilé | Uložená versus rozepsaná adresa, historické odkazy a současná pravidla reply-to. |
| Funkce | Skutečný seznam/defaulty, tenantový filtr, pořadí, title+description search, `feature.isEnabled`, `feature.canBeDisabled`. |
| Specializované editory | Beze zkrácení použít `buildFeatureSettingsEditor`: Form, Ticket, Companions, Contract, Counseling, Deposit, Import, Map, Schedule, Services, Workshops. Jednoduché funkce zůstanou jednoduché. |
| Vstupenka | Původní doručení, wallet/readiness, předgenerování, scanner link, náhledy a layout; samostatné uložení a konflikty zůstávají. |
| Uložení akce | Původní validátory, HTML příprava, save/conflict flow, refresh a snapshot. Jedna skutečná operace Uložit/Zahodit. |
| Oprávnění a smazání | Původní predicate/capability, read-only a loading/saving/error stavy; zákaz smazání při objednávkách včetně stornovaných. |

HTML je návrhová reference, ne zdroj pravidel. Nepřebírat jeho zjednodušené režimy peněženky, plateb, médií nebo validace jako novou implementaci.

## Vlastnictví a životní cyklus

### Jedna data, dva prezentační stavy

`OccasionSettingsTab` dál vlastní `OccasionModel`, formulář akce, HTML koordinátor a persistenci. `OccasionFeaturesSection` vlastní projekci seznamu a výběr `feature.code`.

| Soubor | Odpovědnost po změně |
| --- | --- |
| `occasion_settings/occasion_settings_tab.dart` | Dosavadní data/save owner, explicitní fixture I/O seams a koordinace validace. |
| `occasion_settings/occasion_settings_layout.dart` | Responzivní dokument, kapitoly a navigace mimo scroll; malé prezentační pomocné widgety mohou zůstat v tomto souboru. |
| `occasion_settings/occasion_features_section.dart` | Jediná projekce, grid/řádky, dlaždice a výběr; bez kopie doménového stavu. |
| `occasion_settings/occasion_feature_editor_host.dart` | Stabilní host skutečného editoru, jeho veřejný FormState a viditelnost/fokus. |
| `occasion_settings/occasion_features_controller.dart` | Lokální UI registrace a koordinace veřejných validate/save/reveal operací. |
| `occasion_settings/occasion_timezone_field.dart` | Přesunutý dosavadní timezone autocomplete. |
| `occasion_settings/occasion_advanced_settings.dart` | Pokročilá pole bez druhého vnějšího rozbalovacího obalu. |
| `features/feature_settings_editor.dart` | Dosavadní dispatcher; jen nezbytné předání fixture služeb skutečným editorům. |
| `_shared/editor_scroll.dart` | Jediný přesunutý svislý reveal helper; upravit i oba původní callers ve formuláři. |

Cesty v tabulce jsou pod `lib/components/`. Nové popisky patří do `occasion_settings_strings.dart` a všech šesti stávajících katalogů. Nepřidávat obecný editor framework ani nový stavový balíček.

Controller je pouze UI propojení pro výběr, registraci veřejných FormState operací, validaci a zviditelnění. Neobsahuje druhý model funkcí, JSON cache, RPC, pravidla plateb ani globální službu. Žádný přístup přes `GlobalKey` k cizímu privátnímu State; klíče veřejného `FormState` jsou přípustné.

### Grid a skutečné editory

- Dlaždice jsou prezentační. Nastavit neukládá ani nepřepíná zapnutí. V panelu je explicitní přepínač respektující dosavadní oprávnění a `canBeDisabled`.
- Identita je generace načtené akce a `feature.code`, nikdy index nebo přeložený název.
- Grid skládat z řádků. Host vybraného editoru je přímý, klíčovaný potomek stejného nadřazeného `Column`, vložený pod příslušný řádek. Při změně počtu sloupců nebo skupiny se mění jeho pozice mezi sourozenci, ne jeho rodič.
- Ostatní zachovávané hosty ponechat jako přímé potomky téhož Column, skryté přes `Offstage`, bez fokusu a s vypnutými tickery. Nepoužít `IndexedStack` zvětšující panel na nejvyšší skrytý editor.
- Zapnuté editory vytvořit již při počátečním zobrazení, jako dnes. Dosud nezapnuté editory nevytvářet jen kvůli dlaždici. Jednou otevřený rozpracovaný editor nesmí zmizet při zavření, filtrování, změně skupiny či breakpointu.
- Výběr jiné funkce uchová předchozí editaci. Zavření vrátí fokus na Nastavit stejné funkce. Hledání, které vybranou dlaždici odstraní z projekce, panel schová bez zahození jeho hodnot. Vymazání hledání samo nic neuloží.
- Změna zapnutí přepočítá skupiny. Pokud vybraná funkce přejde mezi skupinami, zpřístupnit cílovou skupinu a ponechat editor ve správném řádku.
- Po reloadu nebo Zahodit vznikne nová generace a staré registrace, kotvy a editory se uvolní. Post-frame práce ověří mounted, generaci a existenci cíle. Žádné notify/setState při build.

### Validace skrytých polí je součást změny

Samotné zachování widgetů přes Offstage nestačí: vypnutá funkce nesmí nově blokovat Uložit svými skrytými validátory, ale zapnutá neotevřená funkce nesmí validaci obejít.

Použít per-feature veřejný `FormState` ve stabilním hostu a lokální UI registraci do controlleru. Koordinátor pouze zavolá původní validátory a `onSaved`; nevytváří nové validační výrazy. Rodič při `_draftChanged` a `_performHtmlSave` vědomě koordinuje základní FormState i registrované feature formuláře, protože vnořená Form oddělí jejich registraci.

- Validovat základní pole a **všechny zapnuté funkce**, včetně těch skrytých nebo dosud nevybraných. Vypnuté se nevalidují.
- Každý nový per-feature Form musí svým `onChanged` předat skutečnou editaci do dosavadního `EditorDraftScope.changed`. Jinak by `onSaved` pole přestala aktualizovat rodičův koncept a dirty stav. Mount, přesun hostu a změna výběru tuto zprávu nevydávají.
- Přenášet `onSaved` hodnoty před porovnáním snapshotu a před sestavením payloadu. Při vypnutí nejprve zachytit rozpracované hodnoty daného editoru; neodvozovat je z nově inicializované kopie modelu.
- Použít veřejné `FormState.validateGranularly()` dostupné v současném SDK k určení chybných polí. Podle jejich registrované sekce/feature otevřít správnou mobilní kapitolu a panel, ukázat první chybu a přístupný souhrn. Fokus řídit vlastními veřejnými FocusNode/hlavičkami, ne privátním State textového pole.
- Zachovat pořadí současného HTML/save procesu a `runOccasionSaveAction`; neobcházet validaci ani konflikt při samostatném save ticket layoutu.

### Jen svislá navigace

Sdílet již ověřený svislý reveal algoritmus z `forms/widgets_editor/form_editor_scroll.dart`. Přesunout jej do `components/_shared/editor_scroll.dart`, pojmenovat obecně a aktualizovat oba dosavadní form-editor callers. Původní soubor a importy odstranit. Nezavádět druhou kopii algoritmu a nevrátit obecné `Scrollable.ensureVisible` procházející vodorovné PageView.

Každý editor má jednoho vlastníka hlavního svislého scrollu. Navigace musí skončit u něj. Ověřit průběh animace po jednotlivých framech, nejen konečný stav.

## První skutečný Flutter náhled

Přidat `test/browser/occasion_settings_layout_preview.dart`. Použije stejné produkční widgety, téma, `material_ui`, české lokalizace a skutečný routovací kontext. Vzor bezpečného lokálního entrypointu už existuje v `test/browser/form_editor_layout_preview.dart`; pro route data použít veřejné AutoRoute fixture postupy z `test/support/navigation_fixture.dart`.

Ukázka: Společenský ples U Lípy, přirozený název/místo/termín, zapnutý Formulář a Vstupenka a další skutečné modely funkcí. Začít v kapitole Funkce; předvést Formulář, Vstupenku, přepnutí, zavření, hledání a změnu šířky. Nastavení skutečně upravuje místní koncept, nikoli server.

Rozšířit existující `loadOccasion` seam jen o nejmenší potřebné typované I/O callbacky a služby pro uložení/refresh, média a ticket náhled. Produkční defaulty dál volají dosavadní vlastníky. Preview předá in-memory implementace; nesmí přeskočit validátory ani zfalšovat úspěšný serverový zápis. Pro ticket využít stávající injekci `TicketLayoutService`; příklady jsou `SettingsService`/`FakeService` v `test/components/ticket_layout/ticket_layout_cases.dart`. Zachovat dispatcher a vnitřní layout identity.

Před povolením preview projít přesně identifikované účinky `_performHtmlSave`, `_removeImage`, HTML media prepare, `onSaveTicket`, ticket readiness/preview a post-save refresh. Každý dostane místní fixture službu nebo skutečný nepřipojený stav, který zastaví I/O před transportem. Nestačí vyměnit pouze loader, zatímco Uložit, obrázek nebo ticket použije produkční singleton. Deletion capability ve fixture nezpřístupnit. Výchozí produkční cesta zůstane jedna, bez preview feature flagu nebo paralelního V2 editoru.

Flutter náhled potřebuje HTTP runtime; statický HTML server jej nenahradí. Po ověření volného globálního Flutter slotu lze při realizaci spustit:

```sh
fvm flutter run -d web-server --target test/browser/occasion_settings_layout_preview.dart --web-hostname 127.0.0.1 --web-port 59273
```

Port je návrh: nejdříve ověřit volnost, neukončovat cizí proces. Použít PTY. Před další Flutter úlohou vlastní preview server ukončit. Po konečných testech znovu spustit pro prohlídku.

Terra provede izolovanou headless kontrolu, se světlým režimem a ztlumením. Pak otevře nový aktivní panel **hlavního Google Chromu**; nepoužije ani nenaviguje existující panel. Není potřeba produkční login ani úplný lokální Supabase. Fixture musí prokazatelně nevydávat produkční zápisy. Backendové integrační a OAuth chování tím ověřené není.

## Delegace a provedení

UI provádí **gpt-6-astra, reasoning medium, fork_turns="none"**, podle výslovné preference uživatele. Předat tento plán, konkrétní vlastněné soubory, relevantní UI skill a referenci B. Neopakovat hledání tří návrhů ani výzkum konkurence. Astra nepřidává další subagenty a nespouští Flutter/build/test/release.

Primární agent připraví čistý worktree a dohodnuté I/O/validační rozhraní. Astře předá souvislý UI balík včetně nezbytného propojení rodiče. Během její práce stejné soubory neupravuje. Primární agent vlastní fixture, behaviorální testy a závěrečnou integraci po předání. Browser a otevření Chrome patří Terra subagentovi. Žádný další nezávislý audit není součástí této úlohy.

### 1. Vlastnictví, stabilní hosty a reálný Flutter základ

Zavést lokální controller/hosty a minimální fixture I/O seams, připravit veřejný validační tok. Extrahovat čistou kompozici tak, aby ji používal stejný `OccasionSettingsTab`. Převést seznam funkcí na grid se skutečným `buildFeatureSettingsEditor`; vložené editory zachovat stavové.

Výstup: první skutečný Flutter průchod s Formulářem a Vstupenkou, jednou spodní lištou a místními daty. Žádné Text('zde bude editor') nebo HTML uvnitř Flutteru.

Kontrola tohoto milníku: jeden vizuální průchod ve skutečném Flutteru a kontrola, že fixture I/O nevolá produkci. Nespouštět celou testovací sadu po jednotlivých komponentách.

### 2. Celý dokument a obě šířky

Přeskládat existující základní, obrazové/HTML, visibility a advanced komponenty. Extrahovat timezone widget z advanced k termínu. Zavést kapitoly, navigaci mimo scroll a svislý reveal; otestovat zachování identity při 3/2/1 sloupcích a přechodu mobil/desktop. Doplnit pouze skutečně nové texty přes strings a všech šest překladů.

Výstup: uživatel může ve Flutteru prohlédnout celou B, ne jen izolovaný katalog funkcí. Všechny řádky matice zachování mají skutečnou komponentu a vlastníka.

Kontrola tohoto milníku: ověřit kompozici a stabilitu skutečných widgetů při změně šířky v již běžícím preview. Behaviorální důkazy celé změny patří do závěrečné dávky.

### 3. Dokončení, odstranění staré cesty a finální dávka

Odstranit nahrazené obaly, doplnit registrované behaviorální případy a provést jednu závěrečnou přiměřenou dávku na konečných zdrojích. Průběžná vizuální kontrola prvního Flutter průchodu není opakovaný plný testovací běh. Po posledních opravách kontrolovat jen zneplatněné důkazy.

Výstup: projde cílená dávka níže, seznam odstranění odpovídá skutečným callers a znovu otevřený Flutter preview používá konečné zdroje.

## Deletion ledger

| Nahrazená cesta | Konečný stav |
| --- | --- |
| `FeatureForm` a jeho ExpansionTile/kopie `isEnabled` | Grid + stabilní hosty + skutečný `feature.isEnabled`. Současní veřejní callers jsou jen v `OccasionFeaturesSection`; před smazáním zkontrolovat symbolické callers. `_ImportFeatureForm` a `_ScheduleFeatureForm` jsou jiné interní widgety, nemažou se. |
| Starý lineární render `enabledFeatures.map(FeatureForm)` a disabled varianta | Jediná projekce do nového gridu, bez paralelní staré větve. |
| Limit `formMaxWidth` na celé stránce | Lokální responzivní dokument; rozumné šířky jednotlivých polí zůstávají. |
| Vnější ExpansionTile advanced + `_advancedSettingsExpanded` | Kapitolu vlastní layout. Obsah advanced je jeden; timezone má jediný widget u termínu. |
| `forms/widgets_editor/form_editor_scroll.dart` | Přesun do `_shared`, všichni callers aktualizováni, původní soubor odstraněn. |
| Návrhové HTML A/B/C | Zůstává výslovně návrhovým archivem, není produkční feature flag ani další runtime editor. |

## Ověření při realizaci

Při psaní tohoto plánu se testy ani buildy nespouštějí. Před každou Flutter úlohou platí globální limit jednoho procesu; testy `--concurrency=1`.

Nové `test/components/occasion_settings/occasion_settings_layout_cases.dart` a `occasion_features_grid_cases.dart` explicitně registrovat v `test/sessions/shared_czech_test.dart` pod `occasion_settings_layout` a `occasion_features_grid`. Samotný soubor `_cases.dart` není spuštěná suite.

Finální cílená dávka:

1. Příkaz `fvm dart analyze` s explicitním seznamem skutečně změněných Dart souborů a parse/shoda nových klíčů šesti JSON katalogů.
2. `fvm flutter test --concurrency=1 test/sessions/shared_czech_test.dart --plain-name occasion_settings_layout`
3. Stejný příkaz pro `occasion_features_grid`, stávající `advanced_link_visibility` a `forms_editor_widget` kvůli přesunu scroll helperu. Doložit skutečné počty, nulový výběr není úspěch.
4. Dotčené capability případy také s `--dart-define=FESTAPP_APP_SUPPORTED=false`, bez současně spuštěného preview serveru.
5. Jeden skutečný Flutter browser průchod ve 390 px, střední a široké ploše; aktivní reálný náhled pro uživatele po testech. Při potřebě plného lokálního backend E2E použít `festapp-local-e2e`; jeho nedostupnost nesmí zablokovat izolovaný UI preview.

Testy mají prokázat zejména:

- Grid 3/2/1, mobilní kapitoly a zvětšené písmo bez přetečení a zakrytých akcí.
- Editace Form/Ticket, close/reopen, jiná funkce, hledání, enabled/disabled regroup a resize zachovají koncept, controllery a aktivní HTML stav.
- Výběr, zavření a scroll nemění dirty stav; skutečná editace ano. Zahodit odstraní starou generaci, starý post-frame callback nezasáhne novou akci.
- `onSaved` text přežije změny layoutu. Neplatné skryté pole zapnuté funkce blokuje Save a otevře správnou kapitolu/editor. Vypnutá funkce takové blokování nezavede. Po opravě proběhne jediný zápis se správnými hodnotami.
- Topologie neobejde `canBeDisabled`, read-only ani filtr bez podpory aplikace. Nastavit umožní prohlížet read-only stav bez zápisu.
- Ticket layout save zůstává oddělený a zachovává konflikt/reload; běžné uložení akce nepředstírá jeho úspěch.
- Navigace neanimuje žádný nadřazený vodorovný PageView ani během jednotlivých framech. Focus/close a mobilní klávesnice jsou použitelné.
- Preview callbacks jsou in-memory, nevznikne žádný produkční request/zápis; produkční defaulty dál volají původní vlastníky.

Nové backendové testy nezměněných platebních pravidel, rozsáhlé goldeny a testy přesných českých vět nejsou součástí této změny. Před případnou později autorizovanou publikací navíc platí dotčené kanonické mirror lanes a všech osm úspěšných GitHub jobs na přesném main před tenant overlay/deploy. Lokální preview je nenahrazuje.

## Definice hotovo a zbytková rizika

Hotovo znamená skutečné Flutter komponenty celé varianty B, grid se skutečnými editory, stejné hodnoty a práva ve všech šířkách, správnou validaci a ukládání, odstraněnou starou UI cestu a otevřený lokální náhled v hlavním Chromu. Předání uvede soubory, počty skutečně spuštěných testů, URL Flutter preview a přesné zbývající integrační omezení.

Největší rizika jsou životní cyklus controllerů, oddělení validace disabled editorů a izolace přímých I/O ve fixture. Tento plán je pokrývá konkrétním hostem, veřejnými validačními registry a inventářem účinků. Přesná šířka a náklady offstage ticket editoru se musí posoudit na skutečném Flutteru; při problému upravit kompozici nebo měřeně omezit práci skrytých editorů, nikoli ztratit jejich koncept nebo vynechat validaci. Pokud se současný zdroj změní, opravit faktickou část tohoto plánu a dotčený krok bez tiché změny schváleného výsledku.
