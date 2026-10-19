# Napojení plánku V2 na úplné funkce Festappu

Datum: 2026-10-19. Stav: připraveno ke spuštění implementace B.
Ověřování: `verification: standard` - peníze, rezervace, veřejné kontrakty a migrace.

## Výsledek a autorita

V aplikaci půjde přímo v editoru V2 spravovat produkty/ceny jednotlivých míst i
skupin, blokování, objednávku z výběru a přesazení/výměnu zákazníků. Flutter i
webový zákazník použijí tentýž plánek, identity a stávající obchodní autoritu.

Tento dokument je autoritativní pro **provedení integrace B**. Povinnou akceptací
je všech 54 řádků [funkční parity V1](blueprint-v2-v1-functional-parity-2026-10-19.md).
Platná produktová rozhodnutí a podrobná datová pravidla zůstávají v
[původním návrhu](blueprint-v2-plan-2026-10-18.md), zejména části Ceny, Přesun,
Gauč, Datový kontrakt a vlny 7-10B. Starý execution prompt je pro etapu A a pro
tento úkol se **nespouští**. A se znovu neimplementuje. Při rozporu s aktuálním
kódem opravit tento plán s důkazem, nikoli potichu zmenšit rozsah.

Součástí jsou oba repozitáře `/Users/miakh/source/festapp` a
`/Users/miakh/source/venue_seat_picker`, SQL expanze, host adaptéry, oba pickery,
setup/copy a suchý převod V1. Není součástí nové účetnictví, nový rezervační
ledger, změna grafických rodin, přepis geometrického rendereru ani redesign
Ticket Editoru. Jeho existující font/resource provider se pouze znovupoužije.

**Provozní hranice:** vytvořit migrace a ověřit je lokálně; neaplikovat je do
produkce, nepřevádět skutečné plánky/objednávky, nenasazovat, nepublikovat balíčky,
neposílat skutečné e-maily, necommitovat ani nepushovat. Aktivace konkrétního
nájemce je samostatná etapa C s vlastním zadáním. B má skončit integračně
ověřeným kódem a přesným seznamem připravených provozních kroků.

## Potvrzený výchozí stav

| Fakt a evidence | Důsledek |
|---|---|
| `lib/components/blueprint/views/blueprint_editor_tab.dart`: `BlueprintTab`, `handleSeatTap`, `_performSwap`, `_processNewOrder` používají dosavadní `VenueSeatController`. | V2 ještě není host integrace. Tato místa jsou callery k přesunutí. |
| `blueprint_product_dialogs.dart`: skupinový produkt je materializován do míst; `BlueprintGroupModel.product` je transientní. | Zavést perzistentní default skupiny, zachovat jednotlivé výjimky. |
| `DbForms.updateBlueprint` → `SupabaseFormCommands.saveBlueprint` → `update_blueprint_client_sync_v1`. | Zachovat transport, command ID, receipts a sync; doplnit typovaný výsledek se strukturou konfliktu. |
| Definice save/swap fasád jsou dohledatelné v `supabase/migrations/20260802234000_client_sync_v1_expansion.sql` kolem 5611/5717; samostatné kanonické soubory těchto wrapperů nyní chybějí. | Vytvořit aktuální zdroje pod `database/functions/` a novou forward migraci. Neupravovat historickou migraci jako jedinou opravu. |
| `database/tables/tables.sql`: `eshop.blueprints` má `objects/groups/configuration/background_svg`, bez nového layout/revision. | Expanze schématu musí předcházet novým readerům/writerům. |
| `DbTickets.swapSpotTickets` → `TicketCommands.swapSpots` → receipted swap → `swap_spot_tickets_internal_v1`; `replace_blueprint_order_client_sync_v1.sql` drží náhradu v subtransakci. | Zpevnit existující vlastníky. Nedělat druhý `swap_v2` ani vlastní storno v UI. |
| `select_spot.sql`: nejdřív advisory hold lock, potom spot `FOR UPDATE`; swap čte spoty bez odpovídajícího explicitního row locku. | Před SQL změnou sestavit společné pořadí zámků a doložit souběh dvěma spojeními. Receipt sám odlišné příkazy neserializuje. |
| Package má `VenueLayoutEditor.inspectorBuilder`, `LayoutHistoryParticipant`, `protectedSeatIds`, `VenueLayoutPicker.onSelectionRequested`, presentation mapy a sdílený JS kernel. | Doplnit malé obecné seams, nevytvářet další renderer a nevkládat Festapp modely do balíčku. |
| Package `example/lib/main.dart` má pouze `DemoPrices`; Festapp `pubspec.yaml` má git pin a `pubspec_overrides.yaml` lokální sibling checkout. | Finální ověření musí rozlišit skutečný host, simulaci a nezávislého consumera. Lokální override není distribuční důkaz. |
| Při průzkumu je Festapp na `feat/occasion-setup-wizard-20261007`, package na `main`, oba obsahují rozsáhlé rozpracované změny. | Žádný reset/switch/clean ani hromadné převzetí dirty stromu. Před prací vymezit baseline a vlastnictví. |

## Jediný cílový tok a invarianty

1. `VenueLayoutDocument` je přenositelná geometrie. Produkty, částky, spot ID,
   objednávky, holds a zákaznické údaje jsou v hostu a SQL. Sekce/stůl/židle mají
   stabilní UUID; výměna obsazení nepřepisuje identitu fyzického místa.
2. Doplnit `eshop.blueprints.layout JSONB`, `layout_revision BIGINT`,
   `eshop.blueprint_seat_bindings(blueprint,node_id,spot)` s jedinečným spot,
   `eshop.blueprint_group_products(blueprint,group_node,product)` a area bindingy
   podle původního kontraktu. Žádné kopírování ceny do těchto tabulek.
3. Save přes stávající form command přijme immutable snapshot s
   `expected_layout_revision`, `layout`, `seatChanges`, `groupProductChanges`,
   `areaBindingChanges`. Jedna revize chrání celý aggregate. Success vrací revizi
   a úplné změněné bindings; rejection obsahuje machine reason a konkrétní issues.
   Limit result data 4 MiB / receipt 8 MiB ověřit proti skutečné transportní autoritě.
4. Při timeoutu opakovat stejný payload a command ID. Rejected receipt se uloží
   až po rollbacku změn. Žádný postupný UPDATE následovaný prostým JSON error return.
5. Produktový katalog se ukládá vlastním existujícím commandem; přiřazení produktu
   místu je undoable draft plánku. Cancel draftu nevrací již uložený katalog ani
   serverovou objednávku. Změna sdíleného produktu předem ukáže dopad na další místa.
6. Volná židle při explicitním připojení k jinému stolu převezme jeho uložený
   default. Pouhý průjezd přes jiný stůl nic nepřecení. Neznámý default smíšené
   legacy skupiny vyžaduje volbu, ne odhad podle prvního sedadla.
7. Posun/rotace/styl drženého či prodaného místa jsou dovolené při zachování
   identity. Změna prodejních metadat/produktu, smazání či odpojení obchodní vazby
   jsou chráněné. Vizuální detach od stolu není smazání seat bindingu.
8. Hromadná změna celé skupiny s blockerem se odmítne celá. Zvláštní akce
   „Pouze volná místa“ je explicitní a ukáže počet výjimek.
9. Gauč má nedělitelnou výběrovou jednotku, ale samostatná spot/ticket ID. Hold,
   finalize, storno, swap a replace musí jednotku chránit stejným guardem. Dvě
   místa gauče proti jedné židli se neswapují napůl. Stání zůstává množstevní
   produkt v existujícím inventory ledgeru.
10. Soukromá admin projekce a veřejný picker payload jsou oddělené už na serveru.
    Cizí objednávky, zákaznické údaje, interní poznámky ani secret se neposílají
    veřejnému vieweru k pouhému lokálnímu skrytí.
11. `_v1` v názvech client-sync RPC a `ClientSyncRuntime.isV1Selected` není verze
    geometrie plánku. Tyto hranice se neruší jen kvůli názvu iniciativy V2.

## Architektonická brána: samostatně použitelný veřejný balíček

Tato brána je povinná, nikoli doporučení pro pozdější úklid. Hranice se navrhují
podle skutečných dvou hostů: package example a Festapp. Přidávat jen rozhraní,
na kterých se tyto hosty skutečně liší; ne obecný framework obchodních pluginů.

### Vlastnictví a směr závislostí

| Vrstva | Vlastní | Nikdy nevlastní |
|---|---|---|
| `venue_layout_core` | Dokument, validaci geometrie, scene protocol, hit/kolize, sestavy, obecné atomic selection units a stabilní node IDs. Čistý Dart bez Flutter závislosti. | Supabase, síť, souborový backend, produkty, měny, objednávky, spot ID, účty/oprávnění. |
| Flutter `venue_seat_picker` | Editor/viewer/picker, kamera, gesto/výběr, geometrická historie, generické resources/presentations a malé host slots/callbacky. | `fstapp`, `festapp_core`, `BlueprintModel`, `ProductModel`, `Db*`, `RightsService`, konkrétní SQL/RPC a obchodní dialogy. |
| `@festapp/venue-layout` JS | DOM/SVG, přístupnost, vstupní události a presentation patche nad společným Dart kernelem. | Druhý výpočet geometrie, objednávky, hold transport a hardcoded Festapp endpointy. |
| Festapp blueprint host | Node↔spot bindingy, skupinové produkty, draft přiřazení, server state, lokalizaci/metadatové projekce a operativní UI. | Vlastní renderer, kopie package geometrie, nezávislé finanční výpočty. |
| Existující commands/SQL | Oprávnění, ceny, inventory, atomické rezervace/objednávky, receipts, transakce a publikaci sync změn. | Závislost na Flutter widgetu, klientské kameře nebo drag session. |

Směr je Festapp → veřejný Flutter/JS vstup → core, a samostatně Festapp →
existující business commands → SQL. Package nikdy neimportuje hosta. Produkty
se sdíleným názvem/cenou se řeší v hostu; do presentation může přijít formátovaný
text, nikoli číselný kontrakt, podle kterého by package tvořil objednávku.

Potvrzené současné skutečnosti: root `lib/venue_seat_picker.dart` exportuje nové
layout vstupy; `packages/venue_layout_core/pubspec.yaml` nemá Flutter dependency.
Scope import průzkum v `lib`, core `lib` a `web/src` nenašel import Festappu ani
Supabase. To není důkaz, že futura integrace hranici zachová; musí ji hlídat brána.

### Malá veřejná rozhraní, která integrace opravdu potřebuje

Koordinátor je vlastní v G0 a nejpozději ve vlně 2 je doloží oběma hosty:

1. **Dokument a prezentace odděleně.** Picker už přijímá `seatPresentation` a
   `capacityPresentation`, ale editorový tok není v tomto ohledu kompletní.
   Doplnit stejný generický transientní presentation vstup/update pro editor
   přes controller nebo widget, ne Festapp overlay renderer. Hover, pending,
   obsazenost nebo nový tooltip nemění layout, revision, dirty ani undo. Pro
   jednotlivý state patch znovupoužít existující scene patch/compile seam,
   nekompilovat celý sál.
2. **Výběr a aktivace.** `VenueLayoutController.selection` už je veřejná
   pozorovatelná sada UUID. Znovupoužít ji pro geometrický výběr. Pro provozní
   režim doplnit pouze chybějící obecný node activation callback a možnost
   potlačit transformační nástroje, aniž se zakáže čtení/klikání. Callback má
   stejné chování pro myš, dotyk a klávesnici. Žádné package enumy `swapOrder`
   nebo `createFestappOrder`, žádné kopírování soukromého `_selectDown` do hosta.
   Host vlastní oddělený dočasný order/swap selection a jeho presentation.
3. **Inspector a provozní lišta.** Použít existující `inspectorBuilder`; pro
   hromadný výběr doplnit malý výběrový kontext pouze pokud ho nelze získat z
   veřejného controlleru. Provozní toolbar je host widget nad editorem. Nezavádět
   registr business akcí do core a nevystavovat celý interní widget state.
4. **History participant.** `LayoutHistoryParticipant` zahrnuje pouze lokální
   draft bindings/defaults/overrides. Neobsahuje objednávky, live server state,
   secret, katalogový Save ani pending RPC. Immutable snapshoty nesmějí při každém
   pointer move kopírovat celou objednávkovou projekci. Reparent + produktový
   draft je jedna společná změna, serverový swap není geometrické undo.
5. **Resources a persistence.** Existující generic resources/provider a controller
   lifecycle zůstávají generické. Persistence, revision, transport, cache backendu
   a ticket font katalog implementuje Festapp adapter. Package example používá
   vlastní lokální adapter. Editor musí jít spustit i bez host inspectoru,
   pricing/permission callbacku a backendu.
6. **Asynchronní životní cyklus.** Picker nyní při výměně instance `document`
   resetuje session/generation. Proto server state patche musí zachovat instanci
   geometrie. Skutečná výměna dokumentu invaliduje staré pending odpovědi; změna
   presentation je nesmí vymazat. Dispose odstraní listenery/routes. Ověřit ve
   Flutteru i JS včetně pozdní odpovědi po zavření nebo změně plánku.

Pokud je typ veřejný, exportovat jej z veřejného package entry pointu a doplnit
krátký consumer příklad. Festapp nesmí importovat `package:venue_seat_picker/src/…`
ani načítat zdroj ze sibling checkoutu. Nový kontrakt nesmí přimět všechny ostatní
consumery znát Festapp workflow. Nepřevádět preventivně všechny existující mapy na
nový hierarchy/framework; typovat nové hranice a opakovaně používané doménové DTO.

### Důkazy nezávislosti a distribuovatelnosti

- V G0 rozšířit existující `tool/archive_check.sh`, `tool/qa_consumer_test.dart`,
  `tool/qa_archive.py` a `tool/qa_archive_browser.mjs` v package; nezakládat další
  paralelní archivační harness. Doplnit nové host seams/lifecycle případy a
  ověřit současný inventář knihovny místo slepého spoléhání na historický počet
  šablon v textu reportu. V závěru jediný finální architecture/consumer batch nad
  skutečnými archivy a source manifestem, ne nad pub cache.
- Doplnit cílený architecture test pro směry importů a zakázané host dependency
  v core/Flutter/JS produkčních zdrojích; odděleně kontrolovat Festapp imports
  package `src/`. Textový match je podnět k ověření importu, ne automatický důkaz
  stejnojmenného symbolu nebo zakázaného chování.
- Nový host-independent Flutter consumer vytvořit mimo oba checkouty. Z archivů
  nainstalovat **core i Flutter balíček**, protože `.pubignore` v root vylučuje
  `packages/`, a root závisí na samostatném `venue_layout_core`. Nesmí hledat
  `../venue_seat_picker`, Festapp `.env`, ticket endpoint, font katalog hosta ani
  absolutní workstation path. Offline smoke po přípravě dependencies s lokálními
  resources: editor → edit → save callback → reopen → picker accepted/rejected.
- Package example je první skutečný adapter, Festapp druhý. Consumer ověří také
  provoz bez business slotů a bez serveru. Simulace se označí a netvrdí nic o SQL.
- JS consumer musí z `npm pack` artefaktu načíst `dist` kernel + veřejný vstup a
  typové deklarace; ověřit mount/update/dispose, presentation patch bez ztráty
  výběru a bez Flutter runtime. `npm pack --dry-run` samo není consumer test.
- Archivy nesmějí obsahovat host bindings, kontakty, secrets, provozní snapshoty,
  soukromé obrázky nebo cesty. Generic fixtures musí být licencované a anonymní.
- Po final freeze spustit rozšířený `tool/archive_check.sh` a package
  `tool/demo.sh check` nad odpovídajícím kitem. Druhý kontroluje demo/browser,
  nenahrazuje archivní consumer. Znovupoužít sestavený output a vynechat skutečně
  shodné již pokryté kontroly; nevytvářet souběžný druhý demo systém. Runtime dependency piny pro release se řeší až s autorizací publikace;
  lokální overrides jsou povolené pro vývoj, nikdy důkaz publikované verze.

**Exit brány:** skutečné archivy lze rozbalit a použít v čistém Flutter a JS
consumeru bez Festappu; host implementuje všech 54 obchodních požadavků přes malé
veřejné rozhraní a původní business ownery. Čistota zde znamená doložený směr
závislostí a odstranění konkrétních duplicit, nikoli počet nových tříd.

## UI zadání a povinné modelové vlastnictví

**Veškeré nové host UI a jeho vizuální kontrolu vlastní Astra Medium.** Při spuštění
vytvořit subagenta s `model: gpt-6-astra`, `reasoning_effort: medium`,
`fork_turns: none`, např. `task_name: blueprint_ui`. Nedostupnost oznámit a pokračovat
nezávislým backendem; UI potichu nepřidělit jinému modelu.

Povinně načte `/Users/miakh/.codex/skills/ui-ux-pro-max/SKILL.md`. Pro skutečné
browser QA také `agent-browser` a pro full-app místní tok `festapp-local-e2e`.
Skill se týká reálných widgetů a jejich kontroly, nestačí jen zmínka v reportu.
Průzkum už ověřil vhodnost UX doporučení bulk actions/feedback/confirmation a
Flutter `LayoutBuilder` pro adaptivní dialogy. Nový design system není potřeba.

Konkrétní brief:

- Zachovat současný minimalistický styl editoru, název „plánek“, jeho paletu,
  viewport, výběr, chování židlí, sliderů a resetu podle stylu. Žádná nová rodina
  objektů kvůli produktům. Rozměry a kreslení nezahltit obchodním nastavením.
- Produkty dostupné rovnou při editaci: vybraný stůl/skupina → default a jednotný/
  smíšený stav; židle → zděděný produkt nebo explicitní výjimka. Vícenásobný výběr
  dovolí hromadnou akci s náhledem počtu změn a blockerů.
- Provozní režimy oddělit od geometrie: Správa míst / Objednávka z výběru /
  Přesadit nebo vyměnit. Výběr, souhrn, vymazání a Escape jsou zřejmé. Změna
  režimu vyčistí pouze dočasný provozní výběr, nezahodí geometrický draft.
- Před náhradou objednávky ukázat původní objednávky, úplná/částečná storna,
  nové položky a částku z backendu. Před swapem ukázat obě strany a cenový dopad;
  úspěch zobrazit až po potvrzení serveru. Selhání ponechá opravitelné UI.
- Pokročilé volby rozbalovací; desktop inspector a úzký displej přes adaptivní
  panel/dialog. Texty se nesmějí ořezávat. Přeložitelné důvody, ceny/měna z hosta,
  ovládání klávesnicí, popisky ikon, stav nevyjadřovat jen barvou.
- Pending zabrání duplicitnímu submitu, ale neblokuje zbytečně celé plátno.
  Objednávkové/metadatové změny nepřepočítávají geometrii při každém hoveru.
- Odevzdat skutečné scénáře ve Flutteru i web pickeru; screenshoty default,
  mixed/blocked, pending/error a mobilního stavu. Výhradně izolovaný headless
  browser, bez zásahu do uživatelova okna. Nepoužívat produkční testovací objednávky.

## Organizace rychlé implementace

Koordinátor vlastní smluvené DTO, obecné package seams, mapu parity, integrační
soubory a finální ověření. Nejvýše 3 pracovní subagenti vedle koordinátora:

| Pracovník | Model | Výlučné vlastnictví |
|---|---|---|
| SQL/doména | výchozí coding model | schéma, nové SQL zdroje/migrace, DB/concurrency testy, setup/copy SQL |
| Host/stav | výchozí coding model | adaptéry/saver/controller/commands/modely, nikoli nové UI widgety |
| UI | **Astra Medium** | host widgety, lokalizace a související widgetové scénáře; žádné SQL/DTO změny bez koordinátora |

Po dokončení SQL nebo host části použít uvolněný slot pro JS consumer a pak QA.
UI může připravit strukturu nad schváleným DTO, nesmí si vymyslet druhé API.
Na začátku každé vlny určit konkrétní soubory. Sdílený soubor upravuje jediný
vlastník; ostatní předají patch/zadání. Koordinátor není povinen dělat rutinní
monitoring subagentů ani opakovat jejich již doložené kontroly.

Žádné opakované stavění Flutteru po každém widgetu, paralelní full buildy,
nezávislé plošné audity ani stovky testů stejné implementace. Jeden test u vlastníka
pravidla + několik úplných UI toků. Po úspěšném checku opakovat jen pokrytou změnu
nebo řešit novou chybu. Obecné refaktory dělat jen tehdy, odstraňují-li konkrétní
zdvojení v tomto toku.

## Proveditelné vlny

### 0. Bezpečný start a zmrazení kontraktu

**Práce:** načíst `AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md`, tento
plán, 54řádkovou paritu a relevantní kontrakty původního návrhu. Zapsat HEAD,
branch a dirty manifest obou checkoutů. Založit izolované task worktrees nad
kanonickým main; přenést pouze dohledané potřebné rozpracované části A přes
kontrolovatelný patch/manifests, nikdy celý cizí feature branch. Žádný automatický
reset, commit, změna uživatelova branch ani editace pub cache. Nejasné nezbytné
závislosti zaznamenat jako přesný blocker baseline, ne potichu ignorovat.

Koordinátor smluví typovaný snapshot, save result, presentations a host action API
v `blueprint_layout_contract.dart` a malé obecné seams v package. Určí vlastníky
souborů a zapíše výchozí performance/scene parity fixture. Ověří skutečně načtené
package zdroje v `.dart_tool/package_config.json`, nikoli jen pin v pubspec.

**Kontrola/exit:** architecture/consumer harness z architektonické brány je připraven;
DTO fixture má parse/roundtrip a jeden vzor success/rejection;
agenti mají shodný kontrakt a chráněné soubory. Nepotřebuje DB ani full build.
**Zánik:** nepřidává se produkční přepínač rendererů ani paralelní finanční kontrakt.

### 1. Persistence, identity, autorizace a zámky

**Práce SQL:** expanze `database/tables/tables.sql`, kanonické nové zdroje pro
blueprint aggregate save/read a nová forward migrace. Rozšířit existující form
command; scope/revision/resource validace, atomické bindings a typované chyby z
původního kontraktu. Public read má jen bezpečnou projekci. Přímé zápisy bindings
nepovolit. Každý nový/změněný SECURITY DEFINER má explicitní oprávnění a
`search_path = public, extensions`, s kvalifikovanými `eshop.*` jmény.

Nejdřív dohledat všechny spot/order/payment writers (`select_spot`, finalize,
storno, replace, swap, setup/copy) a do komentáře/testu zapsat společné pořadí
locků. Nevzít v save buyer advisory lock. Všechny rejection cesty rollbacknou
subtransakci před potvrzením rejected receipt. Resource manifest musí být ready
před odkazem v uloženém layoutu; asset/font chyby nemění poslední potvrzený dokument.

**Kontrola:** nové `database/tests/eshop/blueprint_layout_test.sql` + grant/scope
cases, revision conflict, poslední neplatný seat change bez částečného zápisu,
stejný command replay, cizí produkt/blueprint a veřejný payload bez soukromých dat.
Dvousession Node/PG test musí změřit save-versus-hold/finalize a deadlock/rollback.
**Exit:** stejný spot ID přežije přesun a nový seat vrátí nové ID v jedné transakci.
**Migrace:** lokální expanze; nic neodstraňovat z živých legacy sloupců.
**Parita:** U01/U03-U05/U07, S06-S07 jako serverové základy; finální UI důkaz později.

### 2. Host adapter a první skutečný vertikální tok

**Práce host:** `blueprint_layout_adapter.dart`, `blueprint_layout_saver.dart`,
`blueprint_layout_controller.dart` pod `lib/components/blueprint/`. Mapy UUID ↔
spot, group defaults, oddělené server presentations a undoable draft. Výsledek
`FormCommands.saveBlueprint` nesmí přijít o machine reasons/revision. Saver drží
immutable submitted snapshot; odpověď nesmí přepsat mezitím rozpracovaný draft.
Serverové state patche nemění geometrii ani kameru.

**Práce UI Astra:** host shell `BlueprintTab` nad `VenueLayoutEditor` s obecným
inspector slotem a existing action bar. Funkční load → přesun → save → reload,
Cancel a konflikt s volbou exportovat návrh / načíst uložený. Zapojit existující
font katalog/picker/resolver z Ticket Editoru přes provider a stávající images
službu bez druhého katalogu nebo upload engine.

**Kontrola:** adapter/transport testy + widget tok skutečných callbacků; chyba a
pozdní save response neztratí draft. DB fixture z vlny 1. **Exit:** není to demo
host a žádná obchodní data nejsou ve `VenueLayoutDocument`.
**Architektonická kontrola:** generic presentations/activation/history fungují
v package example i Festappu přes veřejné vstupy; state patch nemění dokument
ani pending výběr. Žádné importy package `src/` v novém hostu.
**Zánik:** nový route už neskládá dosavadní grid/controls editor; legacy čtení je
omezené pouze na převod ve vlně 6. **Parita:** U01-U04/U06-U09, S08-S09.

### 3. Úplné produkty, skupiny a obchodní editace míst

**Práce host:** sdílený produktový snapshot podle ID, explicitní group defaults a
seat overrides v history participant. Celá skupina vs pouze volná místa,
blokery z SQL a dědění při vložení/reparent. Read-only/used/hold pravidla musí být
stejná v preflight i na serveru. Přesun přes jiný stůl sám produkt nemění.

**Práce UI Astra:** znovupoužít `SelectProductDialog`/`EditProductDialog` a
správu skupin přes menší doménové interface; odstranit závislost pouze na grid
souřadnicích. Smíšené ceny, výjimky, bez produktu, hromadné přiřazení a jasné
oddělení katalogového Save od draftu. Všechny režimy blokování/přidání/odebrání
ze seznamu V1 musí mít dosažitelný ekvivalent.

**Kontrola:** P01-P11 a S01-S10; dvě různé skupiny, jedna výjimka, prázdná a
smíšená skupina, chráněný člen, nový produkt, skutečné shared-price upozornění,
Cancel draftu po uloženém katalogu a reparent+undo. Parametrizovat core/doménové
varianty; UI testovat tok, nikoli každý přeložený label.
**Exit:** cena v inspectoru, součtu a backendu odkazuje na stejný produkt.
**Zánik:** žádné použití `DemoPrices` ani odhad defaultu podle prvního místa.

### 4. Vlastní objednávka, výměna a nedělitelné jednotky

**Práce SQL/host:** využít `analyze_new_order_spots`,
`DbEshop.createOrderFromSpots` → `DbOrders.replaceTicketOrder`,
`TicketCommands.swapSpots` a jejich existing receipt/Edge hranice. Zpevnit swap
zámky/ceny/měnu, rollback a sdílený atomic-unit guard ve finalize/storno/replace/
swap/holds. Rozšíření množinového swap rozhraní má jediný interní owner, dvojice
je jen jeho kompatibilní vstup. Žádný nový účetní nebo automatický email producer.

**Práce UI Astra:** samostatné režimy nad stabilními node IDs, summary výběru,
konflikty po objednávkách, kontakt, finanční dopady ze serveru, pending snapshot,
rollback obou míst a potvrzení. Refresh obsazenosti nesmí ztratit geometrický draft.

**Kontrola:** W01-W08 a O01-O08; obsazené↔volné, stejná/různá objednávka,
stejný/různý produkt, doplatek/refund/used/hold, částečné i úplné storno,
stejný command retry a selhání po první dílčí změně. Dvousession swap-versus-hold/
swap/save. Gauč nelze rozdělit ani storno/replace vedlejší cestou.
**Exit:** všechny finanční účinky jsou potvrzené serverem a UI je po chybě konzistentní.
**Zánik:** `_performSwap` nepřehazuje skutečná data před RPC bez rollbacku;
neexistuje čistě klientská náhrada objednávky.

### 5. Oba zákaznické pickery, ceny a stání

**Práce host/JS:** `SeatReservationWidget` přepojit na `VenueLayoutPicker`;
`web_client/src/components/blueprint/` na publikovatelný shared JS viewer/kernel.
Existující form session, `select_spot`, secret/expiry, max tickets, prodejní vlny,
produktové položky a totals zůstávají autoritou. Vektorová geometrie, stroke a
hit test se nepřepisují v JS. Area quantity napojit na skutečný produktový limit,
ne na falešný seat hold. Zachovat batch jednotek i aktualizace při znovuotevření.

**Kontrola:** C01-C08; stejné IDs/ceny/stavy v obou klientech, conflict rollback,
rapid double click, expiry/secret refresh, full unit, množství stání, sold-out a
product waves. Veřejný payload test nesmí obsahovat admin data. Astra provede
vizuální kontrolu a opraví host UI nad stejným kontraktem.
**Exit:** totožný skutečný výběr a objednávkový payload přes Flutter i web.
**Zánik:** staré `blueprint_renderer`/`SeatStyler` kreslení a duplicitní gesture
engine jsou z nového toku odstraněné; zachovat session callbacky a překlady.

### 6. Setup, kopírování a suchý převod

**Práce:** `lib/components/occasion/setup/`, existující form/occasion duplication
commands a `database/functions/occasion_setup/finalize.sql`. Setup bez prodejních
bindings nesmí vynulovat běžnou kapacitu; stání-only je validní nabídka.
Converter převádí objects/groups/configuration/background do layoutu se
zachováním dosavadních spot ID a bez odhadu smíšených cen. Copy vytvoří nová
node/spot IDs a přemapuje produkty do cílové akce; žádné objednávky/holds/secret.

**Kontrola:** SQL copy/setup + dry-run fixture známého legacy plánku, background
bounds, orphan reference, mixed unknown default, rollback a druhé načtení. Přesný
počet a identity míst před/po, není dovoleno je odvodit z vizuální podobnosti.
**Exit:** všechny vstupy vytvářejí stejný kontrakt a migration kit hlásí přesné
blockery. Skutečné legacy plánky se touto vlnou neaktivují.
**Zánik:** setup/copy nepíší novou geometrii jen do legacy `objects`.

### 7. Jeden integrovaný průchod a předání k aktivaci

Zmrazit runtime zdroje obou repo, vyřešit jen skutečné overlap konflikty, sestavit
Flutter+JS nad stejným package revision/archivem a uložit source-hash manifest.
Provést architektonickou bránu včetně clean Flutter/JS consumerů ze skutečných
archivů. Vést všech 54 řádků parity s důkazem - žádný nesmí být nahrazen „má tlačítko“ nebo
„funguje v mocku“. UI Astra Medium dodá screenshoty i kontrolu použití UI/UX skillu.

Provést integrační testy pod disposable místním tenantem podle skillu
`festapp-local-e2e`; SQL-only bootstrap nestačí pro Auth/REST/Storage/Edge. Pozitivní
toky i conflict/retry/forbidden, obě zákaznické platformy, performance a resource
parity. Výsledky běžícího starého commitu nelze připsat finálním zdrojům.

**Exit:** všechna akceptace B doložená, nebo výslovně přiznaný konkrétní blocker;
žádné označení hotovo při otevřených obchodních řádcích. Předat připravené migrace,
release pořadí, lokální repro a deployment boundary bez nasazení.

## Upřesněný rozsah uživatele: kanonický cutover všech plánků

Uživatel následně výslovně požadoval převést všechny existující plánky, jednotný
Basic vzhled a pouze V2 bez souběžné podpory V1. Inventura všech organizací našla
49 plánků a4516 fyzických míst. Všechny mají deterministický offline převod;
všech49 prošlo skutečným lokálním SQL převodem/replay s rollbackem. Uživatel
odmítl rastrové stoly/podklady; dokončení nově vyžaduje nativní editovatelné
stoly, konstrukci sálu a cikcak čáry, shodné tooltipy a fialová použitá místa bez
křížku. Původní rastrový Basic PASS byl odvolán. Opravených49 plánků má18 nativních sálů/464 stolů, skutečné popisky, cikcak a přerušované čáry; aktuální důkazy jsou v nové vizuální evidenci. Žádný skutečný sirotek neexistuje, proto se žádný plánek nemaže.
Historické geometry sloupce jsou jen vstupem kontrolovaného převodu, ne runtime
alternativou. Produkční aktivace nadále není provedena; její přesné kroky jsou v
[evidenci C](evidence/blueprint-b-20261019/activation-c-boundary.md).

## Odstranění a omezené zachování starých cest

| Artefakt | Akce v B | Důkaz / hranice |
|---|---|---|
| Grid UI uvnitř `BlueprintTab`, staré controls a operativní handler kopie | Přepojit route na jediný V2 host shell; nepotřebné widgety odstranit po přesunu callerů. | Scoped `rg` deklarací/callerů + analyzer a integrační route test. |
| Webový legacy renderer/styler/gestures | Nahradit shared viewerem; nesouvisející form session nesmazat. | Import graph a skutečný JS picker test. |
| V1 `objects/groups/configuration/background_svg` a jejich modely | Zachovat pouze pro audit/converter a do explicitní aktivace C; nové V2 read/save je nepoužívají jako fallback. | Chyba V2 nezkusí tiše starý renderer. Destruktivní schema contraction až po všech skutečných převodech. |
| `VenueSeatController`/`SeatAdapter` veřejného balíčku | Odstranit Festapp blueprint callery. Public export nerušit bez inventury ostatních consumerů. | Není důvod zavést breaking package cutover mimo tento úkol. |
| `update_blueprint_client_sync_v1`, `swap_spot_tickets_client_sync_v1`, interní order vlastníci | Zachovat veřejné kompatibilní boundary a jednu doménovou implementaci; doplnit kanonické zdroje. | `_v1` je protocol version, nikoli mrtvý blueprint renderer. |
| `DemoPrices`, místní package overrides, dočasné fixture flags | Demo zůstává pouze v package example. Test override nesmí být důkazem distribuce. | Consumer smoke ze zabaleného balíčku, žádná host produkční závislost na absolute path. |
| Dočasné preview větve/test fixtures/workers | Odstranit pouze task-owned prostředky; staging varianty nesmějí duplikovat business owner. | Cleanup manifest, ostatní práci zachovat. |

## Validace bez zbytečného opakování

Při psaní tohoto plánu se testy ani buildy nespouštějí. Při implementaci:

- Package core: `cd /Users/miakh/source/venue_seat_picker/packages/venue_layout_core && fvm dart test` jednou po související změně core; lokální dílčí testy během práce dle potřeby.
- Flutter host: registrovat nové scénáře do skutečné canonical session a spustit
  `fvm flutter test --concurrency=1 test/sessions/shared_czech_test.dart` s cíleným
  `--plain-name` pro vlny; finální dotčená session jednou bez filtru. Kontrolovat
  discovery/count. Přípona `*_cases.dart` sama není důkaz vykonání testů.
- Dart analyzovat jen změněné soubory/úzký modul. Neopakovat passing test bez změny.
- DB: po ověření výlučného task-owned lokálního DB prostředí použít
  `./automation/bootstrap_local_db.sh` podle CONTRIBUTING, potom
  `DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' node web_client/scripts/run_db_tests.js database/tests/eshop/blueprint_layout_test.sql`.
  Nikdy neresetovat cizí DB podle samotného portu. Runner s 0 vybranými testy není pass.
- Concurrency: nový test se dvěma skutečnými PG spojeními u DB ownera; deterministické
  barriers/timeout, ověřit finální bindings/holds/orders/payments a nulové částečné
  side effects. Není nahrazen sériovým SQL testem nebo replayem jednoho command ID.
- JS: package `cd web && npm test`; ve Festappu spustit dotčené blueprint/form testy
  přes jeho existující package scripts po přečtení `web_client/package.json`.
- Performance: uložit baseline a finální měření na stejném browseru/fixture (typický
  sál a 5000 míst). Žádné RPC v pointer-move/hover, žádný compile celého layoutu při
  změně jednoho server state. Nová režie nesmí způsobit pokles oproti baseline;
  problém doložit profilem a odstranit u jeho vlastníka, nikoli skrýt měřením.
- Full-app E2E: task-owned backend a headless profil podle `festapp-local-e2e`, žádné
  provozní e-maily/platby/produkční data. Načíst browser snapshot, screenshot jen
  pro grafiku/canvas. Aplikovat viditelné stavy, ne jen screenshot prázdného shellu.
- Finální build/consumer archive a test výsledky musí odpovídat hashům finálních
  zdrojů. Neprovádět deployment jako součást validace B.

## Rozhodnutí, předpoklady a zbývající rizika

- **Rozhodnutí:** celé V1 je povinné; grafiku dělá Astra Medium s UI/UX skillem;
  plánuje se skutečná integrace, nikoli rozšíření mock dema.
- **Předpoklad:** dosavadní zdroje A jsou přenositelné do izolované implementace.
  Ověří G0 patch/manifest a package consumer; nepřenositelnou závislost popsat přesně.
- **Předpoklad:** místní disposable full backend lze připravit. Ověří task-owned
  inventory a E2E skill. Když není dostupný, pokračovat v nezávislém kódu a uvést
  neprovedené E2E jako blocker, nepoužít produkci coby náhradu.
- **Riziko:** historické wrappers, lock order, resource připravenost a finanční
  product-wave pravidla mají více callerů. Vlny 0/1/4 je řeší před dokončením UI,
  nikoli odloženou poznámkou na konci implementace.
- **Provozní blocker C:** rozsah dat je všech49 plánků; produkční aktivace a koordinovaný rollout kompatibilních klientů dosud nejsou provedeny. Neblokuje
  implementaci B, blokuje produkční migration/cutover a globální contraction.

## Hotovo znamená

- [x] Všech 54 řádků parity má konkrétní ověřený end-to-end účinek ve V2.
- [x] Gauč, stání, explicitní reparent, resource/font integrace a setup/copy mají důkazy.
- [x] Jeden owner peněz a rezervací, stabilní identity, atomita, receipts, oprávnění a souběh.
- [x] Oba klienti mají stejné ceny/stavy/geometrii; veřejné projekce neobsahují soukromá data.
- [x] UI a jeho kontrolu provedla Astra Medium s `ui-ux-pro-max`; současný vzhled zůstal konzistentní.
- [x] Staré aktivní host rendering callery odstraněné; nutná kompatibilita je omezená podle ledgeru.
- [x] Cílené kontroly, místní integrovaný běh, výkon a čistý consumer odpovídají finálním zdrojům.
- [x] Core, Flutter package i JS artefakt mají správný směr závislostí; čisté archivy fungují bez Festappu, backendu a sibling cest.
- [x] Host nepoužívá package `src/`, nekopíruje renderer ani geometrické handlery; presentation patche nezahazují session ani draft.
- [x] Připravené provozní kroky jsou označené jako neprovedené; žádné skryté nasazení ani změna živých dat.

## Implementace B - evidence G0 (2026-10-19)

- Izolovaný host `/Users/miakh/source/festapp-blueprint-b-20261019` vychází z
  main `f929d0b33eabdcd3fb6ae241cb42d919a4bec878`; package
  `/Users/miakh/source/venue-seat-picker-blueprint-b-20261019` z
  `c829a33d07de9a8fa376b407658875d22abd246e`. Původní checkouty se nepřepínají.
- Přenos A obsahuje 214 dohledaných zdrojových souborů (tracked patch + untracked
  manifest); cizí Festapp runtime dirty změny se nepřenášejí. Evidence je v
  `evidence/blueprint-b-20261019/`. Lokální overrides míří pouze do task package;
  čistý archive consumer instaluje oddělené skutečné core/Flutter archivy.
- Oprava předpokladu archivačního testu: `LayoutNode.toJson()` záměrně
  kvantizuje transformace/rozměry na 1/1024 (core `model.dart`). Nekvantizovaný
  transientní template a jeho persisted snapshot proto nemusí mít bitově shodnou
  scénu (původní gate: path coordinate 8.357421875 vs 8.3564453125). Gate nyní
  prokazuje shodu canonical JSON a scény po druhém načtení canonical snapshotu;
  neodstraňuje runtime chybu ani netvrdí rovnost před kvantizací.
- Font resource používá původní ticket katalog/resolver. Serverový outline
  doplňuje existující `ticket_font_assets.layout_outline`; veřejný reader vrací
  pouze potřebné bezpečné glyph resources. Editorový preview endpoint se
  nezpřístupňuje veřejnému pickeru.


## Doložené korekce při implementaci B (2026-10-19)

- Samostatná distribuce obsahuje 14 skutečně inventarizovaných šablon, nikoli 9.
  Clean consumer ověřuje stabilní serializovaný dokument po kvantizaci souřadnic
  core (1/1024); nepovažuje původní nekvantizovaný transient za jiný persistovaný tvar.
- Dart2js kernel nesmí projít přejmenováním konstruktorů Vite/esbuild. Reálný browser
  odmítal i validní veřejný SQL dokument, zatímco native/Node parsing prošel.
  Package nyní poskytuje obecný `loadKernel(url)`; host předává bundler asset URL
  (`kernel?url`). Klasický script zachová skutečné zabalené bajty, bez eval/CDN.
  Důkaz: package loader test, skutečný Vite build a archive browser gate.
- Veřejná area projekce správně neobsahuje interní inventoryContextId. Host DTO jej
  proto toleruje pouze pro čtení; save request bez interního kontextu explicitně
  odmítne. Nejde o důvod rozšířit anonymní projekci.
- Původně zjištěná mezera U06 v manifestu je implementačně odstraněna novým
  forwardem `20261019110000_blueprint_verified_image_assets.sql`. Stávající Image
  Worker zpracuje PNG/SVG a statický výstup animovaných formátů, pak jediným
  účelovým HMAC potvrdí skutečný hash, rozměry, MIME a délku. Registry je scoped
  na occasion nebo unit; save ověřuje připravenost a public reader vrací jen
  bezpečné referenced resources. Skutečné lokální Images/R2/SQL včetně save,
  reload, copy a zamítnutých podvrhů prošly. Důkaz a limity jsou v
  [image-evidence.md](evidence/blueprint-b-20261019/image-evidence.md).
  Flutter a JS načítají ověřené bajty přes obecné resource seams; finální UI
  ověření a stav U06 uvádí paritní ledger.
- Setup draft uchovává typed V2 geometrii a obchodní bindingy bez spot ID a bez
  binárních resources. Finální vytvoření používá existující product/inventory
  ownery a aggregate save, remapuje identity a nepřenáší holds/orders. Oprávněný
  resolver skutečných fontů i unit-scoped obrázků funguje před vznikem occasion;
  žádný druhý font katalog ani rezervační engine nevznikl.

Aktuální důkazy a otevřená akceptace jsou v
[evidenci B](evidence/blueprint-b-20261019/implementation-report.md).


Novější osobní AGENTS pravidlo během realizace stanovilo nejvýše jednu Flutter
úlohu na workstation včetně dev serverů, analýzy, testů a buildů; testy mají
concurrency1. Nahrazuje dřívější plánovaný parametr concurrency2. Dřívější běh199
scénářů s concurrency1 prošel. Novější doplnění vyžadují finální sériové ověření
a odpovídající archiv/build; starší běh není důkazem novějších zdrojů.


Skutečný anonymní compiled Flutter průchod dále odhalil chybějící povinné occasion
ve veřejné projekci. Public reader nyní vrací ověřené b.occasion (stejná veřejná
akce formuláře), nikoli interní inventory ID. Dotčený SQL test znovu prošel včetně
privacy kontroly. Formát veřejného snapshotu je stejný pro oba klienty.
