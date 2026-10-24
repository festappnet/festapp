# Menší závislosti konfigurace, čistý parser příkazů a úsporné testovací logování

Datum: 2026-10-15  
Stav: Provedeno lokálně; zbývající cesta přes AppConfig doložena níže  
Ověřování implementace: standard - změna sdílených modelů a aplikování synchronizačních odpovědí  
Výchozí větev / HEAD při přípravě: `feat/occasion-setup-wizard-20261007` / `eb2304724`  
Autoritativní rozsah: tři níže uvedené řezy, navazující na dokončený původní plán

## Výsledek a hranice

Konfigurace funkcí aplikace nebude importovat své editory ani číst aktuální
occasion pro předvyplnění smlouvy. Parser odpovědí příkazů bude jedinou čistou
implementací v existujícím `festapp_core/sync.dart`; aplikace bude samostatně
aktivovat jeho výsledky. Testy nebudou vypisovat tisíce očekávaných lokalizačních
zpráv, ale zachovají kontroly skutečně chybějících překladů a chyb.

Výkonový cíl je přiblížit celý klientský příkaz 30 s při limitu
**3 000 000 000 B**. Úspora pěti sekund ani dosažení 30 s nejsou prokázaným
předpokladem. Dokončení architektonických změn a splnění výkonového cíle se
vykazují odděleně. Samotný čas Flutter reporteru není čas celého příkazu.

Mimo rozsah jsou přepis RightsService/AuthService, nové DI nebo resetovací
frameworky, nový systém feature flagů, nová doménová vrstva všech features,
změna SQL/RPC, retry transportu, verze aplikace nebo balíčků, další změny workerů
či slučování testovacích prostředí. Žádný backend, commit, push ani nasazení.
Existující knihovny Flutter pro barvy, metadata a časové převody mohou v app
modelech zůstat; tato vlna neslibuje převést všechny feature modely do Dart VM.

## Závazné podmínky

- Před editací číst `AGENTS.md`, `CLAUDE.md` a `docs/architecture/ai_context.md`.
  Zachovat souběžnou práci; pracovní strom už obsahuje mnoho nesouvisejících změn.
  Pořídit kopie dotčených souborů mimo repo. Neobnovovat hromadně stav z HEAD.
- Používat FVM a stávající závislosti. Aplikace zůstává `0.20.1+485`;
  neměnit `pubspec.yaml`, lockfile ani konfiguraci tenantů kvůli těmto řezům.
- Zachovat všechny dosavadní scénáře, aserce, přesuny původu a jediný původní skip.
  Inventář se nesmí přegenerovat jako nový baseline. Přidané případy evidovat zvlášť.
- Zachovat dva workery a stávající fáze guard + Dart/VM, potom Flutter.
  Ověřování musí hlídat součet RSS vlastních procesů a ukončit vlastní procesy
  při překročení rozpočtu. Nevypínat assety nebo překlady potřebné scénáři.
- Nezavádět forwarding exporty, stará delegující API, dvojí modely ani test-only
  přepínače v produkci. Všechny produkční cesty musí používat nové vlastníky.
- Žádní subagenti a žádné opakované celé benchmarkové série. Příprava plánu
  nepouští testy. Implementace ověřuje soudržné změny, nikoli každý edit zvlášť.

## Potvrzené podklady

| Fakt | Konkrétní důkaz | Důsledek |
| --- | --- | --- |
| Poslední celý příkaz 34,90 s; Flutter 30,31 s; RSS 2,44 GB; 10 Flutter roots | `docs/development/flutter-test-sessions-performance-2026-10-15.json`, `latestSingleVerification`; surový běh `/tmp/festapp-core-execution/14-final/` | Jde o jeden běh, ne stabilní medián. Předchozí 35,14 s je téměř stejný. |
| 1 301 případů, 1 300 prošlo, jeden skip; 1 250 původních + 51 přidaných | stejný záznam a `automation/client_test_inventory.json` | Původní inventář je pevný bod. |
| Přibližně 18,80 worker-sekund loading a 38,54 worker-sekund těl; obsazenost 1,94/2 | `latestFlutterTiming` ve stejném záznamu | Tyto součty nejsou wall time; optimalizovat také těla, ne jen počet roots. |
| Factory základní Feature importuje podtypy, které vlastní i editory | `lib/components/features/feature.dart`: `Feature.fromJson`, `buildFormField`; `form_feature.dart`, `schedule_feature.dart` aj. | Přesunout UI z modelového grafu, ne pouze přejmenovat soubory. |
| Produkční dispatcher je jeden, ale testy mají tear-off odkazy | `feature_form.dart`: `_buildFeatureFields`; `test/components/features/map_feature_cases.dart`: `Builder(builder: feature.buildFormField)` | Migrovat volání i tear-off reference. TicketSettings má zvláštní kontext a callback. |
| Model smlouvy čte RightsService už mimo widget | `contract_feature.dart`: `loadFromDescription`, volání v `buildFormField` | Samotný přesun widgetů neodstraní tuto cestu k routeru. |
| Časové codecs už mají vlastní chování | `workshop_feature.dart`, `counseling_feature.dart`: `toUtcFromOccasionTime`; `schedule_feature.dart`: `EventType.getColor` | Zachovat časové převody, barvy a seed fallback. Nepřepisovat je v této vlně. |
| Parser a side effect jsou v jedné třídě | `lib/data_services/client_sync/client_command_response.dart`: `from`, `applyReplacements` | Oddělit čistý protokol od aplikační cache/projekcí. |
| Saved-program cesta předává fence a vypíná notifikaci projekce | `lib/components/schedule/saved_program_commands.dart`: `notifyProjection: false`, `expectedContextToken` a kontroly před/po aplikování | Nestačí změnit importy; musí zůstat pořadí await, fencing a způsob notifikace. |
| V běhu bylo 3 271 debug a 7 451 lokalizačních warning výpisů | přepočet `print` událostí v `14-final/flutter.jsonl`; celý soubor přibližně 2,67 MB | Potenciální režie, nikoli důkaz velkého výkonového zisku. |
| Ticket testy už kontrolují skutečná lokalizační varování | `test/components/ticket_layout/ticket_layout_cases.dart`: `localizationWarnings`, obnova `logger.printer` | Filtr nesmí tuto kontrolu obejít ani potlačit její zdroj. |

Historické výsledky a původní závazky zachovává
[dosavadní implementační záznam](../development/flutter-test-architecture-progress-2026-10-15.md)
a [původní plán](flutter-test-architecture-plan-2026-10-15.md).
Tento plán je autoritativní pro navazující tři řezy; nepřepisuje historii měření.

## Cílové vlastnictví

### 1. Feature modely a editory

- Stávající `features/feature.dart` a soubory podtypů zůstanou jedinými vlastníky
  dat, factory, wire klíčů, defaultů, `isEnabled` a `canBeDisabled`.
- Nový `features/feature_settings_editor.dart` bude jediný prezentační dispatcher
  `Widget buildFeatureSettingsEditor(BuildContext context, Feature feature,
  {required int occasionId, Future<void> Function(TicketFeature)? onSaveTicket})`.
  Konkrétní existující UI přesunout do `features/editors/`. Parametry dispatcheru
  musí výslovně nést `occasionId` a nynější `onSaveTicket`; bez globálního lookupu.
  Sem přesunout i dnešní zvláštní větev `TicketSettings` z FeatureForm.
  Jednoduché/rezervované typy dál vracejí prázdné UI.
- Zachovat tutéž editovanou instanci modelu a stávající `EditorDraftScope.changed`.
  Nezavádět kopii konfigurace, nový draft systém ani dvojí dirty stav.
- Předvyplnění smlouvy přesunout spolu s algoritmem do editorového modulu
  `features/editors/contract_feature_defaults.dart`. Vstupy budou konkrétní
  title/start/end/description získané UI při nynějším okamžiku předvyplnění.
  Model smlouvy nebude importovat OccasionModel ani RightsService kvůli defaultům.
  Zachovat guard prvního předvyplnění, ruční akci, plnění jen prázdných hodnot,
  výpočet dnů, formát dat a extrakci dopravy. Neopravovat při přesunu jiné vzorce.
- `FeatureMetadata` a nynější lokalizované title/description v konstruktorech
  zůstanou s dosavadním okamžikem vyhodnocení. Barvy a timezone codecs zůstanou
  v dosavadním vlastnictví. Požadavkem je odstranit app-context/editor cesty,
  nikoli prohlásit tyto modely za čistý Dart.

### 2. Odpověď příkazu a aktivace změn

- Jediná třída `ClientCommandResponse` se přesune do
  `packages/festapp_core/lib/src/sync/client_command_response.dart`, exportovaná
  přes existující `sync.dart`. Zůstane DTO/parser se stejným konstruktorem,
  statusy, validací, převodem code, casty a chováním při chybném vstupu.
- Neklonovat automaticky mapy, nepřitvrzovat validaci položek, které se dnes
  parsují až při aplikování, neměnit null/unknown ani synchronní výjimky.
- Nový app modul `lib/data_services/client_sync/client_command_replacements.dart`
  bude vlastnit funkci `applyClientCommandReplacements(response, ...)`.
  Přesunout přesně nynější sekvenční cyklus a dispatch do
  `ClientSyncRuntime.applyLiveReplacement/applyPrivateReplacement/applyPublicReplacement`.
  Zachovat `notifyProjection`, `expectedContextToken`, výjimky a await pořadí.
- Doménové adaptéry nadále rozhodují, zda a kdy odpověď aplikovat nebo odmítnout.
  Parser ani applier si tuto politiku nepřivlastní. Transport, UUID a retry
  `ClientCommandTransport` zůstávají beze změny.

### 3. Testovací lokalizační logy

- Jediný testovací vlastník bude
  `test/support/fixtures/localization_log_fixture.dart` s explicitním scoped
  install/dispose, zachycením původního printeru a obnovou v opačném pořadí.
  Použít jen veřejné API; žádné SDK internals ani produkční změna loggeru.
- Politika se přiřazuje nejmenší vhodné skupině, ne automaticky celému procesu:
  nynější shared SDK/locale sessions míchají skutečné i prázdné katalogy.
- Debug lze omezit. Missing-key warning lze vynechat z výpisu jen ve výslovně
  deklarovaném prostředí s očekávanou absencí katalogu/prázdným katalogem.
  Ostatní warningy a všechny errors zůstávají viditelné. Sledovat souhrn počtů.
- Zachytávání zprávy musí předcházet rozhodnutí o výpisu. Skupiny ověřující
  skutečné překlady dál obdrží všechny warning/error zprávy a jejich dosavadní
  kontrola prázdného seznamu zůstane účinná. Neřešit šum vytvořením falešných
  překladů ani odstraněním warning asercí.
- Instalaci provádět v hooks a úklid registrovat hned. Při vnoření musí rodič
  přežít úklid potomka; nesmí se přepsat cizí printer. Nepotřebujeme obecný
  globální logovací framework nebo hook závislý na privátním test runneru.

## Rozhodnutí a nejistoty

- **D1:** Feature řez je první, protože odstraňuje reálné UI závislosti i mimo testy.
- **D2:** Nevzniká nový core feature modul. V core přibude pouze existující parser
  uvnitř modulu sync. Čisté parser testy se přesunou, nikoli zkopírují.
- **D3:** Produkční kompatibilita je zachování dat a chování při atomické migraci
  všech lokálních volání; staré Dart metody/exporty se neuchovávají jako shimy.
- **A1:** Po oddělení editorů a smluvních defaultů může modelový graf stále dosáhnout
  routeru jinou cestou. Řeší implementátor AST uzávěrem po tomto konkrétním řezu.
  Pokud by oprava vyžadovala širší přepis služeb, doloží přesnou cestu a zbývající
  limit; nerozšíří tiše zadání a nebude tvrdit, že router odstranil.
- **A2:** Hluk je z významné části očekávaný fallback, ale součet warningů sám
  nerozlišuje skutečné chyby. Řeší implementátor rozdělením podle emitujícího
  testu/skupiny v existujícím JSONL před přiřazením logovací politiky.
- **A3:** Zmenšení grafu ani logu nezaručuje zrychlení celé sady. Ponechat původní
  vstupy měření a porovnat jediný závěrečný běh jako jednotlivý běh, ne medián.
- **Blokery:** Žádný pro lokální implementaci. Výkonový výsledek je otevřený.

## Vlny provedení

### Vlna 0 - Zachytit výchozí stav bez nového benchmarku

**Změny:** Sepsat dotčené soubory přes scoped `rg`, uložit jejich aktuální kopie,
verze, inventář a SHA vstupů. Vzít poslední zaznamenaný běh 34,90 s jako výchozí
jednotlivý výsledek. Spočítat AST app uzávěr `feature.dart`, reprezentativního
feature podtypu a command parseru včetně export/part/conditional hran.
Z existujícího JSONL rozdělit lokalizační výpisy podle skutečných skupin.

**Validace:** Žádné testy; čtení existujících receipts a zdrojů.
**Exit:** Známé původy scénářů, výchozí grafy, logovací skupiny a zálohy souběžné práce.

### Vlna 1 - Modelový graf bez feature editorů

**Změny:** Přesunout existující widgety všech podtypů dosažitelných z
`Feature.fromJson` do `features/editors/`. Zavést jediný dispatcher a migrovat
FeatureForm včetně ticket větve. Odstranit modelovou metodu `buildFormField`
i její overrides. Migrovat také testovací tear-off reference. Vyjmout
`ContractFeature.loadFromDescription` do editorového default helperu s explicitními
vstupy. Vyčistit importy přesunutého UI a kontextu.

**Kompatibilita:** Stejné wire DTO, neznámý typ -> SimpleFeature, stejné rezervované
program notifications, povinně zapnutý FormFeature dle AppConfig, defaulty,
mutace, draft notifikace, ticket save callback, layout key a occasion scope.

**Validace:** Jedna cílená dávka analyze + existující feature/map/forms/ticket testy
na jejich skutečných `*_cases.dart` vstupních souborech. Doplnit pouze chybějící
kontrakty dispatcheru, dirty signalizace a smluvních defaultů. Vynucovat architekturu
stávajícím AST guardem: žádný model -> editors/FeatureForm/TicketSettings/
EditorDraftScope/Contract default UI helper; přímá cesta model -> RightsService
nesmí zůstat. Přidat negativní fixture s transitive/conditional importem.

**Exit:** V app modelech není `buildFormField` ani `loadFromDescription`; všechny
skutečné UI cesty používají dispatcher a původní model. Záznam obsahuje skutečný
pokles grafu i případnou dosud zbývající cestu k routeru, nikoli odhad.

### Vlna 2 - Jeden čistý parser a jeden app applier

**Změny:** Přesunout parser do core/sync, cyklus aplikování do app applieru,
migrovat všechny importy a všechny `.applyReplacements` reference v `lib` a
`test`, včetně víceřádkových volání. Odstranit starý app parser soubor bez exportu.
Přesunout `test/data_services/client_sync/client_command_response_cases.dart`
do core testů, změnit `flutter_test` na `test`, odstranit jeho registraci z
`client_sync_unit_cases.dart`; aktualizovat moves v inventáři se zachováním
původních normalizovaných jmen. Runtime kontrakty ponechat ve Flutteru.

**Kompatibilita:** Zvlášť zkontrolovat saved-program fence před/po await,
`notifyProjection: false`, sekvenční pořadí replacements, chybu uprostřed cyklu,
rejected/conflict politiku jednotlivých adaptérů. Žádná změna UUID/retry nebo SQL.

**Validace:** Core parser testy + cílené existující command/saved-program/runtime
kontrakty. Doplňovat jen neověřenou hranici; skutečné runtime side effects musí
krýt skutečný runtime fixture, ne test-only kopie algoritmu. Core guard už
vynucuje zákaz Flutter/app importů; přidat regresi pro nový parser owner.

**Exit:** Jediný parser je veřejně dostupný přes core/sync; původní app cesta a
metoda chybí. Všichni runtime volající používají explicitní applier. Přesunuté
původní scénáře jsou v inventáři právě jednou.

### Vlna 3 - Scoped logování bez oslabení překladových kontrol

**Změny:** Zavést fixture s výše uvedenými politikami a instalovat ji pouze do
skupin identifikovaných ve vlně 0. Sjednotit vlastnictví s nynějším ticket
`logger.printer` capture tak, aby jeho warning kontrola běžela před filtrem výpisu.
Ponechat errors, neočekávané warningy a jeden stručný souhrn potlačených zpráv.

**Validace:** Cílené A-B-A a vnořený úklid printeru; částečný setup a selhání těla
nesmí zanechat změněný printer. Negativní kontrakt: ve strict skutečném katalogu
chybějící klíč stále vyvolá dosavadní selhání; v expected-fallback skupině se
jen nevypíše očekávané missing-key hlášení. Jiný warning a error se předají dál.
Ověřit skutečné ticket a mixed-locale skupiny, včetně obráceného pořadí.

**Exit:** Očekávaný výpisový šum klesl, diagnostické kontroly zůstaly účinné,
původní printer se obnovuje a není produkční test-only větev.

### Vlna 4 - Jedna závěrečná dávka a záznam výsledku

**Změny:** Dokončit importy, registrace, klasifikaci a inventář ještě před měřením.
Aktualizovat fixture/session dokumentaci. Neslučovat další skupiny jen proto,
že se v této vlně změnil počet nebo složení VM testů.

**Validace:**

1. Po hotových změnách cílený analyze, guard a relevantní obrácené pořadí fixture.
   Úspěšný cílený check neopakovat bez následné změny jeho vstupů.
2. Jednou `./automation/test_client.sh`, s `FESTAPP_CLIENT_RESULTS` v nové složce,
   externím RSS watcherem, SHA vstupů a jejich kontrolou před/po. Watcher musí
   ukončit a sklidit vlastní potomky při překročení 3 GB. Žádný warmup + tři běhy.
3. Jednou produkční web compile na finálních produkčních vstupech:
   `fvm flutter build web --release --base-href / --no-web-resources-cdn --no-wasm-dry-run --no-pub`.
   Spustit sekvenčně po testech pod stejným paměťovým dohledem; bez nasazení.
4. Zapsat celý command time, lane times, peak RSS, počty případů a skipů,
   zmenšení grafů a počty logů. Zachovat předchozí receipts pod jejich SHA.
   Pokud dojde k chybě, provést cílenou diagnózu a opakovat jen nutné zasažené gates.

**Exit:** Všechny původní případy inventáře zachované bez duplicit, nové případy
odděleně evidované, guard i web compile prošly. Čas pod 30 s buď doložen jako
jednotlivý výsledek, nebo výslovně nesplněn. Bez výmluvného přejmenování cíle.

## Odstranění starých cest

| Stará cesta | Konečný stav | Důkaz |
| --- | --- | --- |
| `Feature.buildFormField` a overrides | odstraněné; UI vlastní dispatcher/editory | scoped `rg 'buildFormField' lib/components/features test/components/features` + analyze |
| UI classes v modelových feature souborech | přesunuté, ne duplikované | AST model closure guard + existující interakční testy |
| `ContractFeature.loadFromDescription()` a modelový RightsService import | odstraněné; jeden algoritmus v editor helperu | hledání referencí + kontrakt defaultů |
| `lib/data_services/client_sync/client_command_response.dart` | smazaný bez shim exportu | žádný import této cesty v lib/test/test_dart |
| `ClientCommandResponse.applyReplacements` | odstraněná metoda; jeden app applier | žádná původní reference; skutečný saved-program/runtime kontrakt |
| původní Flutter parser cases/registrace | nahrazené jednou core registrací | AST registration guard + původní sémantický inventář |
| nekontrolované globální nahrazení printeru v dotčených fixtures | jedno scoped vlastnictví, zachované warning aserce | A-B-A, nesting, strict negativní kontrakt |

## Provedení, návrat a dokončení

Změny jsou lokální a atomicky migrují vlastníky i všechny lokální volající.
Není potřeba rollout flag ani migrace databáze. Při návratu se vrací konkrétní
soudržný řez včetně jeho volání z uložených vstupů, nikdy celý dirty pracovní
strom z HEAD. Ověřený neúčinný logovací filtr lze odstranit jako celek; nesmí po
něm zůstat mrtvé politiky, paralelní helpery nebo vypnuté kontroly.

Hotovo znamená všechny tři řezy, splněný deletion ledger, zachované kontrakty,
inventář a povinné gates. Přínos je doložen zvlášť strukturou a časem.
Pokud se čas nezlepší nebo překročí 3 GB, výsledek se tak zaznamená; není povolené
ubírat scénáře, měnit verze nebo zahájit širší přepis architektury jen kvůli číslu.

## Zjištění při provedení

AST uzávěr potvrdil zbývající cestu
`feature.dart -> form_feature.dart -> app_config.dart -> components/occasion/admin_page.dart -> components/navigation/occasion_administration_boundary.dart -> app_router.dart`.
Původní úplný app uzávěr měl 699 souborů. Oddělení editorů samo tuto cestu
neodstraní a po přidání nových editorových modulů může úplný uzávěr i růst.
FormFeature musí podle rozsahu zachovat AppConfig.isAppSupported. V této vlně
proto guard vynucuje editorovou a RightsService hranici až k explicitnímu
externímu švu AppConfig; úplný AST graf se vykazuje bez tohoto ořezu zvlášť.
Odstranění stránky z AppConfig by byl další samostatný řez, zde se neprovádí.

Výchozí logy jsou rozdělené podle testID/jména v
`/tmp/festapp-dependency-cuts/log-groups-before.json`. Missing-key filtr je
výslovně instalovaný v identifikovaných leaf suites výchozích sessions a ve
dvou empty Czech timeline suites. Mixed Google locale matrix ponechává warningy;
shared registration omezuje pouze debug. Ticket suite používá strict observer.


## Dokončení

Vlny 0-4 a deletion ledger jsou provedené. Podrobný výsledek a omezení jsou
v [implementačním záznamu](../development/flutter-test-architecture-progress-2026-10-15.md#follow-up-three-dependency-cuts-2026-10-15)
a [novém receipt](../development/flutter-test-dependency-cuts-results-2026-10-15.json).
Celý příkaz 29,92 s externě / 29,87 s runner, 1 314 případů, původní skip;
web compile 45,39 s. Oba příkazy prošly pod 3 GB na shodném SHA.
Jeden výsledek pod 30 s je prokázán, stabilní medián není měřen.
Úplný feature graf stále dosahuje routeru přes AppConfig, žádné jeho odstranění
se neprohlašuje. Historické výsledky ani baseline nejsou nahrazené novým baseline.
