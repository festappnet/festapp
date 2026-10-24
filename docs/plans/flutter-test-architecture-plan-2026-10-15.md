# Čisté Dart jádro a rychlé, izolované testy klienta

Datum: 2026-10-15  
Stav: Implementováno a ověřeno - vlny 0-7 a navazující řezy; poslední úplné ověření 34,90 s / 2,44 GB; medián pod 40 s zatím není doložen, po posledním řezu se dle pokynu uživatele opakovaně neměřilo  
Revize: zpřesněné moduly, grid adaptéry, lifecycle a mezikrokové gates  
Ověřování implementace: standard - mění se sdílené závislosti, asynchronní orchestrace a auth fixture  
Rozsah tohoto dokumentu: autoritativní plán lokální implementace; bez commitu nebo nasazení

Konečný doklad implementace, gates a benchmarku:
[flutter-test-architecture-progress-2026-10-15.md](../development/flutter-test-architecture-progress-2026-10-15.md).
Níže je zachováno zadání jednotlivých vln; výsledky a splnění gates uvádí konečný záznam.

Při pokračování implementace byla zkontrolována souběžná změna veřejných odkazů:
`test/components/shared/copy_button_test.dart:53` nyní ověřuje kopírování
serverem potvrzeného slugu i během rozepsané editace. Původní očekávání kopírování
rozepsaného slugu už není produkčním kontraktem. Inventář ponechává původní ID
v `baseline_revisions` a vyžaduje konkrétní náhradní případ; žádný případ se
nepřeskakuje. Ostatní původní případy zůstávají beze změny. Další práce nemusí
čekat na zastavení souběžných úprav, ale benchmark musí označit různé vstupy.

Další doložená oprava inventáře: `product_list_equals_cases.dart` kopíroval
nepoužívanou order-insensitive extension. `ProductsDialog._hasUnsavedChanges`
už před vlnou 3b porovnával uspořádanou sekvenci `(id, price)` přes
`ListEquality`. Toto skutečné pravidlo se přesouvá do `sameProductSelection`,
které volá dialog i test. Scénář obráceného pořadí proto nově očekává false;
ostatních osm scénářů a aserce zůstávají. Původní a nové ID s důkazem uchovává
`baseline_revisions`; test-only kopie algoritmu se odstraňuje.

## Výsledek a rozsah

Čistá klientská logika má jedno produkční provedení v samostatném Dart balíčku.
Její testy nepotřebují Flutter engine. Widgety, platformní adaptéry a jejich
integrační testy zůstanou ve Flutteru. Testovací fixture mají explicitního
vlastníka a ukončení; sdílení procesu nesmí měnit význam testu.

Zahrnuto: sync protokol a orchestrace, cache pravidla, čistá pravidla formulářů,
produktů a programu, vhodné mapové algoritmy, produkční volání těchto modulů,
fixture, registrace testů, lokální runner a existující automatizace.
Přesuny mohou změnit vnitřní rozhraní aplikace. Nestačí přesunout testy nebo
vytvořit druhou implementaci, kterou produkce nepoužívá.

SQL zůstává autoritou pro oprávnění, kapacitu, ceny objednávek, platby a další
serverová rozhodnutí. Refaktor nesmí přesunout rozhodovací pravomoc do klienta.
Nemění se RPC/HTTP kontrakty, persisted JSON, ID, časová pásma, zaokrouhlování,
retry pravidla, rozsahy soukromých dat ani chování offline režimu.
Mimo rozsah jsou databázové migrace, změny backendu, deployment, vydání,
optimalizace JS/SQL sad a úpravy vendored MapLibre balíčků.

## Zjištěný stav

| Fakt | Doklad | Důsledek |
|---|---|---|
| Původní sada běžela 184,84 s; po prvním sdružení 107,94 s; po druhém 84,03 s. | Lokální měření `fvm flutter test --no-pub --reporter=json`; `/tmp/festapp-test-perf/*meta.json`. | Historická orientační měření jednoho běhu, nikoli opakovaný benchmark. |
| Stejná současná sada s `--concurrency=10` běžela 74,41 s. | `flutter-stage2-j10.meta.json`; host arm64, 10 logických CPU, 16 GiB RAM. | Vyšší souběžnost sama nepřinese požadovaný velký skok; nehardcodovat ji pro každý stroj. |
| Poslední běh má 137 objevených sad; součet načítání je 308,92 s a těl testů 94,67 s. | `flutter-stage2.jsonl`. Časy jednotlivých procesů se překrývají. | Přibližně 76 % součtu tvoří loading. Není to 76 % prokázaného wall-time kritického řetězce. |
| Výsledek současných měření je 1 248 úspěchů, 1 skip a 1 stejný pád. | `event_feedback_admin_content_test.dart`: `admin delete is deferred until changes are saved`, hledání `ElevatedButton` s `Common.ok`. | Před změnou architektury určit a opravit skutečnou příčinu tohoto lokálního pádu; neskrývat ho v tolerovaném allowlistu. |
| Dvě dosavadní vlny přesunuly 144 souborů do `*_cases.dart`; obsah a názvy případů byly porovnány. | `test/components/**/*_unit_test.dart`, widgetové entrypointy, srovnání JSON událostí. | Další migrace musí zachovat inventář případů, ne pouze počet zelených testů. |
| Anglický fallback test převzal českou lokalizaci sousední sady. | `forms_field_widget_test.dart` záměrně odděluje `form_deletion_cases.dart` od `forms_editor_widget_test.dart`. | Náhodné seskupování není bezpečné; prostředí a jeho lifecycle jsou součástí kontraktu fixture. |
| Sync protokol je již čistý Dart. | `lib/data_services/client_sync/client_sync_protocol.dart` importuje pouze `dart:convert`. | První levný produkční řez a kontrolní vzorek nové architektury. |
| Store má port, ale sám vybírá platformní adaptér. | `client_sync_store.dart`: `ClientSyncStorage`, výchozí `StorageHelperClientSyncStorage`; import `services/storage_helper.dart`. | Oddělit port/algoritmus od adaptéru; adaptér zvolit v produkční kompozici. |
| Jeden soubor směšuje vzdálené porty, HTTP a Flutter Supabase. | `client_sync_remote.dart`: `PublicSyncHeadRemote`, `PublicComponentRemote`, `PrivateSyncRemote`, `HttpPublicSyncRemote`, `SupabasePrivateSyncRemote`. | Rozdělit podle rolí; samotná injekce parametrů bez odstranění importu nepomůže. |
| Sync orchestrace je již převážně injektovatelná. | `ClientSyncService` přijímá remotes, store a `SyncClock`; `ClientSyncRuntime` vytváří store a adaptéry. | Zachovat kontrakt a existující seam; nevyrábět paralelní testovací orchestrátor. |
| Doménové modely natahují prezentaci i efekty. | `EventModel extends ITrinaRowModel`, `toTrinaRow`, `deleteMethod`, `updateMethod`; `ProductModel` importuje Flutter, Trina, `DbEshop`, lokalizaci a `TimeHelper`. | Oddělit doménová data/pravidla, prezentaci řádků a explicitní operace. |
| Také zdánlivě čisté helpery mají UI closure. | `forms/widgets_editor/default_value_helper.dart` závisí na `FormFieldModel` a `widgets_view/form_helper.dart`; `FormModel` importuje stejný UI helper. | Přesunout společné datové pojmy spolu s jejich skutečnými spotřebiteli. |
| Fixture dnes mutují globály i při registraci. | `token_update_test.dart`: preferences v `main()`; `rights_explicit_occasion_test.dart`: dočasný adresář v `main()`, kanál, package info, Supabase a globální kontext. | Přesunout mutace do scoped lifecycle; cizí stav nepřepisovat v registrační fázi. |
| Jednotný runner dnes selhání Flutteru jen vypíše. | `automation/test_all.sh`, Flutter blok vrací po warningu dál. | Nový klientský runner i jeho volající musí propagovat nenulový exit code. |
| Grid potřebuje chování modelů, nejen jejich data. | `SingleDataGridController<T extends ITrinaRowModel>`; `SingleDataGridHeader._saveChanges` volá `deleteMethod` a `updateMethod`. | Samotné smazání superclass rozbije skutečný save tok; potřeba aplikační grid record. |
| Produkt a typ tvoří cyklus; serializace eventu mění vstup. | `ProductTypeModel.products`, `ProductModel.productType`; `EventModel.toJson` přiřazuje do `data`. | Oddělit katalog/relace a čistý codec, ne pouze přemístit stejné soubory. |
| Storage má procesově cachované otevřené databáze. | `services/storage_helper.dart`: `_databases`, `_getDatabase`, Sembast factory podle `kIsWeb`. | Disposable adresář bez vlastnictví a uzavření handle není izolovaná fixture. |

`/tmp` důkazy nejsou trvalý ani nutný vstup implementace. První vlna zaznamená
nový reprodukovatelný baseline a konfiguraci. Pracovní větev při plánování je
`feat/occasion-setup-wizard-20261007`; workspace obsahuje rozsáhlou rozpracovanou
práci. Neobnovovat soubory z HEAD, neuklízet cizí změny a nepředpokládat stabilní
obsah mezi touto poznámkou a implementací.

## Cílová architektura

```text
Flutter UI a composition roots
  ├─ prezentéry / grid adaptéry / lokalizované formátování
  ├─ Supabase, StorageHelper, pluginové a platformní adaptéry
  └─ packages/festapp_core
       ├─ sync: protokol, porty, store, orchestrace a validace
       ├─ forms: datová schémata, metadata a pravidla defaultů
       ├─ eshop: klientská produktová data a cenové projekce
       ├─ program: události a deterministická pravidla programu
       └─ map: vhodné algoritmy a datové kontrakty

core/test → package:test, bez Flutteru
test/     → Flutter widgety + testy skutečných klientských adaptérů
```

### Rozhodnutí

1. **Jeden nový čistý balíček** `packages/festapp_core`, nikoli balíček pro každý
   helper. Oddělené doménové moduly, cílené veřejné knihovny a interní `src/`;
   žádný barrel, který znovu propojí všechny závislosti. Root Flutter pubspec
   použije lokální path dependency. Balíček má vlastní pubspec a testy;
   neprovádět současně migraci celého repozitáře na pub workspaces.
2. Core nesmí importovat `package:fstapp`, Flutter, `dart:ui`, `supabase_flutter`,
   UI lokalizaci, grid ani platformní pluginy, ani je získat tranzitivně.
   Nemá závislost `sdk: flutter`. Čisté závislosti jako `crypto`, `http`, `intl`
   nebo `timezone` jsou možné, pokud jejich roli potřebuje daný modul.
   Nativní filesystem kód není automaticky UI kód, ale nesmí znemožnit web:
   parser manifestu a algoritmus patří zvlášť od `dart:io` ověřování souborů.
3. Produkce používá přesně stejné implementace jako core testy. Stávající
   exportovací shimy, duplikované modely a test-only odbočky po migraci nezůstanou.
   Během jednotlivého řezu lze použít dočasný most pouze s odstraněním v témže řezu.
4. Rozhraní mají vyjadřovat doménovou operaci, nikoli každý vnitřní getter.
   Rozhraní `ClientSyncStorage` již existuje; znovu ho použít. Nezavádět obecný
   DI framework, univerzální service locator ani testovací přepínače v aplikaci.
5. Sync store bude vyžadovat storage. `ClientSyncRuntime` explicitně vytvoří
   `StorageHelperClientSyncStorage`. Privátní Supabase adaptér zůstane v aplikaci
   a dostane klienta konstruktorem. HTTP adaptér může být čistý Dart, pokud jeho
   celý import closure zůstane čistý. Přesun samotného protokolu je jen první řez.
6. `ClientSyncProjection` dnes vrací aplikační modely. Nevynucovat jeho přesun
   před migrací těchto modelů. Do té doby zůstane jako pojmenovaný Flutter
   projekční adaptér; validace a pravidla sync orchestrace nesmějí tahat jeho UI.
7. Klientská doménová data neznají `BuildContext`, `TrinaRow`, překlady ani DB.
   Grid mapování a lokalizované zobrazení přejdou do pojmenovaných adaptérů;
   update/delete do explicitních existujících command rozhraní. Adaptéry mohou
   držet doménový objekt, nikoli vlastní konkurenční kopii jeho pravidel.
8. Čas a efekty jsou explicitní. Využít existující `SyncClock` a malé seam
   u konkrétního modulu; ceny dostanou serverový čas/offset jako vstup.
   Zachovat UTC, occasion timezone, ordering, superseding a atomické aktivace.
   Pro `Timer` testy preferovat `fake_async` a injektovaný clock; nový scheduler
   zavést jen pokud existující seam neumí skutečnou orchestrace deterministicky řídit.
9. Fixture budou v `test/support/fixtures/`, bez produkčních importů zpět do testů.
   Oddělit widget environment, lokální/mock Supabase, storage a platformní kanály.
   Žádná jedna funkce s desítkami boolean přepínačů. Každá fixture vlastní zdroje
   a async dispose; úklid v opačném pořadí, i při neúspěšném setupu/testu.
   Chyby při úklidu se hlásí; ostatní disposery se přesto dokončí.
10. Scope fixture je test nebo vědomě sdílená skupina. `main()` pouze registruje.
    Neprovádí inicializaci Supabase, zápis preferences, vytváření souborů ani
    přepínání globální identity. Frameworkový standardní binding lze inicializovat
    idempotentně; custom/live binding vyžaduje samostatný proces.
11. Preferovat lokální `SupabaseClient` a in-memory porty před resetováním singletonu.
    Singleton `Supabase.instance` je potřeba pouze pro ověření skutečného root adaptéru.
    Oprávnění testovat na skutečném modulu s explicitním kontextem, ne přepsanou
    testovací permission logikou. Flutter listenery, streamy, fronty, timery,
    method channels, timezone a vlastněný globální kontext mají konkrétní úklid.
12. Sdílení procesu schválit podle kontraktu prostředí, nikoli počtu souborů.
    České překlady a fallback řetězce jsou odlišná prostředí, dokud jejich setup
    a reset nemají veřejný, ověřený seam. Žádné reach-through do privátních internals
    lokalizačního/pluginového balíčku. Pokud reset není bezpečný, ponechat proces
    izolovaný nebo přejít na explicitní prezentační adaptér.

### Povolené závislosti uvnitř core

Jeden balíček neznamená jeden provázaný modul. Produkční závislosti směřují takto:

```text
forms -> eshop
program -> map (jen datové kontrakty místa/geometrie)
sync -> vlastní protokol a vlastní porty
map -> vlastní datové kontrakty
eshop -> vlastní datové kontrakty
```

`json_values.dart` nyní vlastní pouze rekurzivní zmrazení JSON map/seznamů,
používané eshop, map a program; neobsahuje entity ani tabulkové konstanty.

Všechny mohou použít malý společný kontrakt pouze tehdy, když ho skutečně
potřebují alespoň dva moduly. `shared/` nesmí být skladiště helperů, modelů,
tabulkových konstant ani univerzální základní entity. Importy opačným směrem,
cykly mezi moduly a přístup do cizího `src/` jsou zakázané. Závislost formuláře
na typu produktu je skutečná; závislost produktu na definici formuláře není.
Sync orchestrace nezná EventModel ani ProductModel. Projekce sync payloadů do
doménových objektů zůstává v aplikaci, dokud pro ni nevznikne doložený samostatný
modul s jednosměrnými závislostmi; nesmí vytvořit zpětný import do sync jádra.

Veřejné vstupy: `lib/sync.dart`, `lib/forms.dart`, `lib/eshop.dart`,
`lib/program.dart`, `lib/map.dart`. Exportují pouze potřebné typy a operace;
žádná knihovna `festapp_core.dart`, která exportuje celý balíček. Produkční UI
neimportuje interní implementace a čisté testy primárně testují veřejný kontrakt.
Výjimka pro cílený interní algoritmus musí mít konkrétní důvod, ne vytvořit
druhý veřejný povrch. Nativní IO a pluginy zůstanou v aplikačních adaptérech.

### Datové, prezentační a command kontrakty

| Odpovědnost | Kanonický vlastník | Co do něj nepatří |
|---|---|---|
| Snapshot produktu/události/definice formuláře a jeho klientská pravidla | Příslušný core modul | Widget, řádek gridu, lokalizovaný label, singleton či síť |
| Čtení/zápis existujícího JSON kontraktu | Pojmenovaný codec u vlastníka dat; čistý, pokud nepotřebuje platformu | Formátování pro grid a nezdokumentované nové defaulty |
| Převod snapshotu na Trina řádek a rozepsaného řádku na command vstup | Aplikační `ProductGridRecord`, `EventGridRecord`, `FormFieldGridRecord` | Druhá cenová, kapacitní nebo serializační logika |
| Uložení, smazání a aplikace command response replacements | Existující command modul a jeho Supabase adaptér | Doménový model se skrytým přístupem do DB |
| Selekce identity, životnost sync služby a publikace do notifierů | `ClientSyncRuntime` v aplikaci | Kopie sync orchestrace nebo druhý refresh timer |
| Formátování, fallback title, měny a překlady pro obrazovku | Aplikační prezentér/widget | Změna uloženého snapshotu při pouhém zobrazení |

**Grid rozhodnutí:** ponechat `ITrinaRowModel` jako kontrakt výhradně aplikačního
UI. `SingleDataGridController<T extends ITrinaRowModel>` a jeho základní chování
se kvůli přesunu domény nepřepisují na nový generický framework. Nové pojmenované
grid records implementují tento kontrakt, drží core snapshot a odkaz na potřebný
command modul. `toTrinaRow`, summary a save/delete delegace jsou jejich legitimní
adapter role, ne dočasný kompatibilní shim. Nesmějí kopírovat všechna doménová
pole do paralelní sady proměnných ani být pouhým forwarding wrapperem 50 getterů.

Konkrétní řez produktu:

1. Čistý snapshot produktu a cenová pravidla používá detail i seznam.
2. `products_tab.dart` při načtení vytvoří `ProductGridRecord` s explicitním
   `EshopCommands`. Při kopii/novém řádku použije stejný factory scope.
3. `fromPlutoJson` už nevolá síť ani nevytváří doménový objekt podle lokalizovaných
   textů. Převod řádku zachová ID, optimistic `aggregateVersion`, měnu, čas
   a dosavadní význam null/nezadané hodnoty.
4. `SingleDataGridHeader._saveChanges` nadále obslouží potvrzení a pořadí
   operací; adapter předá příslušnému existujícímu command modulu stejný payload.
   Zachovat HTML preparation před uložením a aplikaci response replacements.
5. Při neúspěchu zůstane draft/dirty stav; cancel neprovede command; úspěch
   přepne na potvrzená data. Výsledkem není druhá cache produktu uvnitř gridu.

Veřejný tvar core snapshotů má oddělit čtení od rozepsaných změn. Nové snapshoty
mají hodnotovou sémantiku: žádné zapisovatelné globály, sdílené mutable `data`
mapy ani obousměrné object graphy. Existující mutabilní UI editory se převedou
na explicitně vlastněný draft; měnit jej smí jeho editor. Rozpracovaná hodnota
není druhou uloženou pravdou. Při přesunu je nutné vyřešit vlastnictví včetně
vnořených map/seznamů; samotné `final Map` nebo mělký `copyWith` izolaci nezajišťuje.
Nevynucovat současně nový obecný immutable/patch framework nebo generátor.
Vlastnictví vnořených dat zajistit jednou na vstupu či při skutečné změně;
neprovádět deep copy celého katalogu při každém getteru nebo widget rebuild.
Výkon refaktoru se týká i běhu aplikace, ne jen rychlosti testovacího runneru.
Pro grid už draft představují `TrinaRow`/cells a controllerovy dirty množiny;
nepřidávat k nim ještě druhý synchronizovaný mutable draft. Dialog může vlastnit
vlastní draft v rámci své životnosti. Stejná editace nesmí současně probíhat
ve třech reprezentacích, které se navzájem dohánějí listenery.

Doménová jména `ProductModel`, `EventModel` a `FormModel` lze zachovat v novém
modulu; tato migrace nevyžaduje kosmetické přejmenování každého typu. Nová jména
jsou potřebná tam, kde se odpovědnost skutečně rozdělila, například
`ProductGridRecord` oproti doménovému produktu. Doménový model nesmí mít v aplikaci
stejnojmenný re-exportovaný dvojník. Formulářový aplikační bundle má explicitní
pole `definition` a kontext, nepředstírá rozhraním, že je původní doménový model.

Relace produktu a typu dnes tvoří objektový cyklus (`ProductTypeModel.products`
a `ProductModel.productType`). V core používat ID a vlastněný katalog pro lookup,
nikoli dva navzájem mutované seznamy. Vnořený wire JSON lze dekódovat do tohoto
grafu; změna vnitřní reprezentace neautorizuje změnu endpoint payloadu. Podobně
`FormModel.occasionModel` a `bankAccount` nesmějí přitáhnout celý tenant/account
objektový graf: definice formuláře drží identitu a potřebná doménová data,
aplikační bundle připojí kontext a prezentační detaily. Nevytvářet kopie pravidel
účtů nebo oprávnění pouze kvůli odstranění importu.

### Čas, wire kompatibilita a chyby

- Pro jednu cenovou/projekční operaci odebrat čas jednou a předat jej dovnitř.
  Dnešní `ProductModel.priceNow` čte hodiny při každém přístupu. Nový snapshot
  vyhodnocení nesmí získat různé „teď“ pro dvě položky stejné operace. Serverový
  offset, okamžik vlny i hraniční rovnost zůstávají explicitně ověřené.
- Oddělit UTC instant, occasion-local zobrazení a skutečná date-only pole.
  Nahradit `DateTimeRange` v čistém výpočtu rozdílem časů se stejnou dosavadní
  hranicí; DST a přes půlnoc musí mít příklady. Nedělat z tohoto refaktoru
  obecnou migraci všech časových typů aplikace.
  První řez event codec zachová dnešní occasion-time reprezentaci explicitně
  předaným timezone kontextem místo `TimeHelper` globálu. Případnou změnu celé
  aplikace na jinou časovou reprezentaci neprovádět jako skrytou část přesunu.
- Codec nesmí měnit vstupní objekt. Dnešní `EventModel.toJson` přiřazuje klíč
  do sdílené `data` mapy; nový codec vytvoří výstup bez této vedlejší mutace.
  Ověřit stejný wire výstup a nepřítomnost mutace; neslibovat zachování této
  vnitřní chyby jako produktového chování.
- Zvlášť testovat missing, explicit null, prázdný seznam, nulu, false, ID jako
  číslo/string podle dosavadního kontraktu a unknown metadata. Neodstranit
  neznámé klíče z průchozích `data` objektů. Doménové změny a wire patch se
  nemají vydávat za stejný formát; smazání klíče mapovat podle skutečného RPC.
- Ověřený původní konstruktor `EventModel` má nullable `this.title`, který
  přepíše field initializer `CommonStrings.event` i při vynechání argumentu.
  Skutečný default je null, což nový core codec i konstruktor zachovávají;
  test `event_snapshot_test.dart` zachycuje missing/null title. Lokalizované
  labely vlastní aplikační presenter, ne uložený snapshot.
- Core používá doménové výsledky/chyby u konkrétních operací. Transportní adaptér
  mapuje existující odpovědi; UI nadále používá své error handling rozhraní.
  Neobalovat každou výjimku do nečitelných generických `Result<dynamic>` a neměnit
  transient chybu na úspěch, retry nebo ztrátu identity.

### Lifecycle fixture a vlastnictví prostředků

| Prostředek | Získání | Ukončení / invariant |
|---|---|---|
| Mock/local Supabase klient | Nový klient v test scope, explicitní transport | Odpojit subscriptiony, await dispose; log requestů pro daný test, ne produkční endpoint |
| Preference, secure storage, in-memory sync store | Fresh namespace nebo instance | Žádná sdílená identita/databáze mezi testy; nelze „vyčistit“ cizí živý scope |
| Dočasný adresář a platformní storage handle | Uvnitř setupu, unikátní cesta | Nejprve close handle, potom delete; ne pouze smazat adresář při otevřené cache |
| Method channel handler | Přes veřejné testovací rozhraní, známý vlastník | Odregistrovat vlastněný handler; nespoléhat na neveřejné čtení cizího handleru |
| Locale/timezone/clock | Explicitní profil; uložit veřejně dostupný původní stav | Vrátit vlastněnou změnu; pokud knihovna neumí reset, jiný proces nebo adaptér |
| Router/controller/notifier/listener/timer | Registrovat disposer ihned po vytvoření | Zrušit a await pending work před koncem scope; žádný callback do dalšího testu |

Například `StorageHelper` má dnes statickou mapu `_databases` s otevřenými
Sembast handle. Nový fixture nesmí jen prohlásit adresář za disposable. Pro
skutečný storage adaptér je nutný explicitně vlastněný handle/factory a close
seam; nepřidávat obecný `clearAllForTests` nad produkční globální mapou. Runtime
smí dál cachovat vlastněné připojení s doloženou životností, test fixture ho nesdílí.

Pořadí testu: vytvořit profil a zdroje -> připojit adaptéry -> provést operaci ->
ověřit výsledek i effects -> odpojit UI/listenery -> await fronty/dispose ->
obnovit vlastněný platformní stav -> zavřít storage -> smazat soubory.
Disposer se registruje i u částečného setupu. Nepřidávat čekání do teardownu,
které pouze doufá v doběhnutí; známá práce musí mít awaitable completion.

Testy izolace musí odhalit konkrétní chybu: B nezdědí identitu/storage/locale A;
A spuštěné znovu funguje stejně; vyvolaná chyba v setupu přesto zavře získané
zdroje; nečekaný HTTP request selže. Není potřeba nový framework sledující každý
objekt nebo všechny Flutter timery. Pro singleton-only SDK kontrakt je samostatný
proces správný adapter test, nikoli architektonický neúspěch.

**Vlastní versus vypůjčený zdroj:** `ClientSyncService` vlastní své timery,
subscriptiony a orchestrace; injektované klienty a storage pouze používá.
Jeho dispose nesmí odhlásit uživatele, vyčistit cache jiného scope nebo zavřít
globální Supabase klient aplikace. Handle/HTTP klienta zavírá composition root,
který ho vytvořil. Test fixture může vlastnit všechny tyto vrstvy, ale zaznamená
je odděleně. Runtime může sdílet ověřené veřejné cache bloby; nová soukromá
identita nesmí převzít pozdní výsledek předchozího scope.

Ve změně contextu se nejprve změní generation/epoch a odpojí odběr staré služby;
pozitivní výsledek starého požadavku nesmí publikovat do nového kontextu.
Async completion zkouší svou platnost u publikačního/aktivačního kroku, nikoli
pouze při odeslání. Nenahrazovat toto fencing čekáním, až doběhne libovolný
HTTP request. Test musí ručně dokončit starý request až po přepnutí kontextu
a ověřit, že nová data/identity nebyly přepsány. Přesný storage scope a dosavadní
pravidla pro zachování již validních veřejných blobů zůstávají zachované.

## Výkon a doklad správnosti

**Cíle, nikoli současné výsledky:** celá klientská sada na referenčním stroji
má warm medián do 40 s; čistá core sada do 5 s; vybraná běžná doménová sada do 2 s.
Stretch cíl celé sady je 25 s. Počet enginů je diagnostika, ne náhrada za správnost.
Pokud se cíl nepodaří, reportovat nedosažení a zbývající profil - nevyřazovat testy.

Měřit celý nový klientský příkaz včetně startu všech dílčích runnerů. Warm = závislosti již
vyřešené, bez souběžného buildu, bez exportu obrázků. Zaznamenat tři celé běhy,
medián, rozptyl, CPU, RAM, SDK a souběžnost. Cold načítání reportovat zvlášť;
nepoužívat `flutter clean` ani smazání pracovních dat jako běžnou součást benchmarku.
Nekombinovat starý pomalý cold běh s novým warm během a nevydávat rozdíl za úsporu.

Před přesuny vytvořit inventář semantických ID původních případů, skupin, skipů
a prostředí. Při migraci vést explicitní mapu starý případ -> nový případ/lane.
Kontrola musí odhalit chybějící případy i dvojí spuštění; počet úspěchů sám nestačí.
Neměnit kombinatorické pokrytí, aserce ani skipy kvůli benchmarku. Změny testu
vyvolané novým rozhraním mají ověřovat stejný produkční kontrakt.

### Funkční gates pro každý vertikální řez

| Seam | Povinný důkaz správnosti | Co by byla falešná jistota |
|---|---|---|
| Protokol/codec | Původní reprezentativní validní i nevalidní payloady; missing/null/unknown metadata; neměněný vstup | Pouze `encode(decode(x))`, když obě funkce obsahují stejnou chybu |
| Sync storage | Atomic pointer replacement, odmítnutí regrese, rollback při failure, zachování jiného scope | Fake, který `replaceAtomic` rozloží na nezávislé úspěšné zápisy |
| Sync orchestrace | Starý context nepublikuje po změně identity, retry je nejvýše jeden vlastněný tok, dispose zastaví další práci | Ověřit jen konečný happy-path snapshot |
| Ceny | Explicitní now před/na/po vlně, server offset, měna, nezměněné dosavadní zaokrouhlení | Běh podle nástěnných hodin nebo nahrazení dat jednou fixní cenou |
| Event/form codec | Dosavadní fixture výstupy, timezone/DST, zachování null a nezadaných metadat | Přizpůsobit očekávání novému výstupu bez vysvětlení změny kontraktu |
| Grid record | Load -> edit -> cancel/save; failed save zůstane dirty; aggregateVersion/ID v commandu; HTML preparation | Testovat samotné mapování polí bez skutečného uloženého toku |
| Command adaptér | Skutečný adaptér, přesný stávající RPC a payload, error a response replacements | Mocknout metodu, ve které právě změněná implementace žije |
| Widget | Skutečná uživatelská akce, produkční komponenta a ověřitelný důsledek | Slabší finder nebo odstranění problematické kombinace |
| Fixture | A-B-A se změnou identity, storage a locale; failure cleanup; nulové nečekané requesty | Jednotlivě zelené testy nebo `sleep` před další skupinou |
| Runner/discovery | Core selže / Flutter selže / obě selžou / obě uspějí; chybějící case; duplicitní case; cancellation | Úspěch podle posledního procesu nebo počtu nalezených souborů |
| VM adapter root | Skutečný IO adaptér běží přes Dart VM bez bindingu; jeho selhání shodí `all` | Považovat úspěšný core package za pokrytí aplikačního IO adaptéru |

Existující hodnotné případy migrovat; nepřidávat test pro každý accessor.
Nové případy jsou potřeba především tam, kde vzniká nové rozhraní či lifecycle
nebo kde dosavadní test nemohl zachytit uvedené konkrétní selhání.

### Pravidla rozhodnutí při implementaci

1. **Čistota před metrikou:** pokud zrychlení vyžaduje falešný adaptér, skrytý
   singleton či oslabení případu, odmítnout ho a uvést konkrétní zbývající cenu.
2. **Vertikální řez před velkým přesunem:** nedržet dlouho rozbitou aplikaci
   s „už čistými“ modely. Po každém řezu lze spustit cílenou oblast a úplný runner
   stále zahrnuje všechny přesunuté případy. Úplnou drahou sadu opakovat pouze
   pro nový sdílený zásah nebo závěrečný gate/benchmark.
3. **Žádná skrytá změna domény:** objevenou chybu serializace či vlastnictví
   uvést v evidenci řezu. Viditelnou změnu produktu, RPC nebo účetní logiky
   nenormalizovat jako „cleanup“; takový rozsah vyžaduje samostatné rozhodnutí.
4. **Nevymýšlet neexistující potřeby:** nepřidávat generické repository pro každou
   entitu, globální Clock singleton, automatickou auto-discovery přes `eval`,
   izoláty v produkci nebo nový event bus jen kvůli testům.
5. **Aktualizace plánu místo improvizace:** překážku jako neobnovitelný SDK
   globál vyřešit konkrétním adaptérem nebo ohraničenou procesovou izolací;
   zapsat důvod do klasifikace a příslušné vlny, ne do neurčitého seznamu TODO.

## Implementační vlny

### 0. Zelený baseline a stabilní měření

- Znovu ověřit pracovní stav, FVM verzi, aktuální discovery a existující změny.
  Vyšetřit známý pád `event_feedback_admin_content_test.dart` samostatně. Jestli
  je problém selektor po změně sdíleného dialogu, přejít na skutečnou sémantickou
  akci a dál prokázat odložené mazání, potvrzení i uložení. Jestli je chybná
  produkční logika, opravit konkrétní regresi před refaktorem.
- Doplnit lehké profilování JSON výsledků a inventáře. Výstup benchmarku uložit
  jako malý reprodukovatelný report v `docs/development/`, surové logy jako lokální
  nebo CI artifact bez tajemství. Nedělat nový obecný benchmark framework.
- Na jednom referenčním stavu získat výše uvedený baseline; dosavadní čísla jsou
  vodítko. Ověřit existující skippovaný SDK test a podmínky jeho samostatného běhu.
- **Výstup:** reprodukovatelná zelená sada, doložené skipy, inventář a wall-time.

### 1. První čistý produkční řez: sync kontrakty

- Založit `packages/festapp_core` s čistými dev dependencies `test` a podle potřeby
  `fake_async`. Verze a SDK constraints vybrat podle aktuálního FVM SDK a root
  constraints, ne podle nejnovější dostupné verze. Přidat path dependency rootu.
- **Ještě před přesunem prvního případu** zavést `automation/test_client.sh`
  s oběma lane a povinnou propagací selhání, zapojit ho do Flutter větve
  `automation/test_all.sh` a aktualizovat úplný příkaz v aktivní dokumentaci.
  `all` nikdy nesmí při chybějícím/broken core package tiše přejít na Flutter-only.
  Podoba runneru je upřesněna ve vlně 6; jeho úplnost platí už od tohoto řezu.
- Přidat první verzi guardu směru závislostí a core čistoty. Pozdější vlny ho
  rozšiřují, ale nesmějí mezitím dovolovat tranzitivní návrat Flutter importu.
- Přesunout `client_sync_protocol.dart`, `client_sync_projection_tracker.dart`
  a `sync_polling_policy.dart`, pokud jeho aktuální closure projde purity kontrolou.
  Přesunout odpovídající případy z `test/data_services/client_sync/*_cases.dart`
  do skutečně discoverable `packages/festapp_core/test/**/*_test.dart`.
- Migrovat všechny produkční a testovací importy; odstranit staré soubory a jejich
  registrace v agregátoru. Samostatná závislost na `package:test` nestačí, pokud
  test dál tranzitivně importuje UI.
- **Validace:** `fvm dart pub get`, `fvm dart analyze`, `fvm dart test` uvnitř
  core; cílené Flutter sync/runtime kontrakty; import/dependency guard.
- **Výstup:** produkce i Dart test používají stejný čistý protokol; bez shimů.
  Kanonický úplný příkaz už v tomto bodě provede obě lane a kontrolu inventory.

### 2. Celý sync modul: porty, store, orchestrace, adaptéry

- Rozdělit `client_sync_remote.dart` podle rozhodnutí 5. Zachovat validaci
  checksumů, rozsahů, head/pointer kontraktů i privátního RPC.
- Přesunout `ClientSyncStore`, jeho datové typy a `ClientSyncStorage` do core.
  Přesunout `StorageHelperClientSyncStorage` do aplikačního adaptéru, vyžadovat
  storage v konstruktoru a upravit skutečné vytvoření v `client_sync_runtime.dart`.
- Přesunout `ClientSyncService` se zachováním front, identity fencing,
  revision monotonicity, staging/activation, budgetů, backoff a dispose.
  Žádný paralelní orchestrátor nebo defaultní skrytý StorageHelper.
- Přesunout kontraktní testy store/remote/service do Dart runneru; skutečný
  StorageHelper, Supabase wrapper a připojení runtime dále ověřit ve Flutteru.
  Existující `_MemoryStore` a `_MemoryStorage` sjednotit podle produkčního portu,
  ne do fake, který obchází atomické operace. Test musí dokázat i neúspěšnou aktivaci.
- **Validace:** cílené core případy pro stale/scope, retry, atomické pointery a
  neúspěšné storage operace; Flutter runtime a platformní adapter kontrakty.
- **Výstup:** sync rozhodování neběží pod Flutter testem; offline a identity
  chování je stejné a root kompozice používá nové implementace.

### 3. Formuláře, produkty a program jako doménové moduly

- Tuto vlnu realizovat jako čtyři samostatně dokončitelné vertikální řezy:
  **3a** metadata formulářů, čisté výpočty/default hodnoty, program mutation
  coordinator a minimální mapové datové typy; **3b** produkt/type katalog,
  produktová pravidla a skutečný produktový grid; **3c** události, jejich codec,
  event grid a ostatní spotřebitelé programu; **3d** definice formuláře a pole,
  aplikační kontextový bundle a skutečné editory/runtime. 3b předchází 3d,
  protože formulář používá produkty. 3c předpokládá mapové kontrakty z 3a.
- Pro každý řez projít pouze odpovídající import closure a přiřadit rozhodování
  vlastníka. Čistý `DefaultValueHelper` nemůže dál přijímat celý UI-propojený
  `FormFieldModel`; hodnotové operace pracují s daty defaultu a vrací novou hodnotu
  či metadata. Widgetový editor přiřadí výsledek svému draftu. Po migraci volání
  odstranit starou helper implementaci, nikoli ponechat dvě sady pravidel.
- Metadata klíče a typy formuláře přestanou žít ve widget helperu. Vytvořit jeden
  čistý kontrakt používaný parserem, modelem i UI; nepřidávat druhé sady konstant.
  Rozlišit tyto doménové klíče od celého `database_tables/tb.dart`. Nepřesouvat
  kompletní schéma tabulek do společného core modulu. Endpoint codec vlastní
  potřebný wire kontrakt; databázové adaptéry dál vlastní tabulková jména.
- Oddělit JSON/data a klientská pravidla od `ITrinaRowModel`, `toTrinaRow`,
  `BuildContext`, UI stringů a DB metod. Migrovat UI spotřebitele na adaptéry
  a existující command rozhraní. Nezměnit RPC payloady či význam serializace.
  Relevantní spotřebitelé grid kontraktu jsou `single_data_grid_controller.dart`,
  `single_data_grid_header.dart`, `data_grid_action_confirmation.dart` a konkrétní
  feature callery. Zachovat generický grid kontrakt pomocí pojmenovaných
  aplikačních records; nemigrované grid modely mohou dál implementovat
  `ITrinaRowModel`. Tento kontrakt není položka k plošnému odstranění.
- U cen zachovat server time/offset, časové vlny, viditelnost a měny. U programu
  zachovat poslední záměr, superseding, scope změny a práci s occasion timezone.
  Lokalizované labely a widgetové form controllery zůstávají mimo core.
- Následně přepojit `ClientSyncProjection` na čisté modely, kde už je to možné;
  zbylé mapování do UI typů zůstává pouze v pojmenovaném adaptéru.
- **Validace:** přesunuté behavior testy v Dart; cílené formulářové widgety,
  price scheduling, program mutation a grid mapping. Porovnat konkrétní původní
  JSON fixtures včetně null/missing polí a datových typů.
- **Výstup:** doménové testy nevytvářejí widgetový strom ani Supabase; původní
  metody/helpery nemají souběžnou starou implementaci.
  Každý z řezů 3a-3d samostatně obsahuje nové jádro, skutečné produkční spotřebitele,
  příslušné testy a odstranění nahrazené cesty. Nelze odevzdat jen nové typy a
  odložit jejich použití až na konec všech čtyř řezů.

### 4. Zbývající čisté kandidáty a dosažení maximálního smysluplného rozsahu

- Klasifikovat zbývající `*_cases.dart` a `*_test.dart` jako core, widget,
  adapter nebo environment integration. Každý ponechaný netriviální čistý
  algoritmus musí mít konkrétní důvod, proč zatím nelze přesunout jeho closure.
- Kandidáti: mapové datové výpočty, path/layout geometrie bez `Color`, parsery
  a manifest schéma; čisté command payloady; form metadata a datové validace.
  Například `offline_map_bundle_manifest.dart` dnes importuje `dart:io`:
  oddělit přenositelné schéma od nativního ověřování souborů, neprotlačit IO na web.
- Nativní MbTiles/MapLibre, clipboard, image engine, fonty, routování a renderery
  zůstávají adapter/widget testy. Nepřesouvat SQL pravidla do klienta a nepřepisovat
  knihovny pro testovatelnost trivialit. Inventář této vlny má konečný seznam
  přesunů a odůvodněných zbytků, nikoli otevřený refaktor všeho.
- Samotné `dart:io` však není důvod ke Flutter enginu. Čistě Dart/VM adaptéry
  bez Flutter import closure testovat v root `test_dart/adapters/` pomocí
  `fvm dart test test_dart`, s explicitní root dev dependency na `test`.
  Ověří skutečný aplikační IO adaptér a core, bez zpětného importu aplikace
  do core package. Root může mít Flutter dependency; konkrétní VM test closure
  ji nesmí importovat. Tento test root není automaticky objeven Flutterem.
  Přidat ho do úplného runneru ve stejném řezu jako první takto přesunutý případ;
  nevytvářet další produkční package jen kvůli pár IO testům.
- **Validace:** core purity guard, Dart testy přesunutých modulů, cílené skutečné
  adaptéry a web kompatibilita; absence starých importů po každém celém řezu.
- **Výstup:** každý zbývající Flutter případ opravdu potřebuje UI/platformu nebo
  má explicitně doložený integrační kontrakt závislý na Flutteru. VM-only IO není
  výjimka, kterou lze bez odůvodnění nechat na Flutter lane.

### 5. Fixture s explicitním lifecycle a odstranění globálních testovacích zkratek

- Založit malé moduly v `test/support/fixtures/` pro widget environment,
  kontrolovanou Supabase komunikaci, lokální storage a platformní kanály.
  Fixture nebude náhradou produkční logiky. Zpracovat zdroje v `token_update_test.dart`,
  `rights_explicit_occasion_test.dart`, `sign_in_code_login_test.dart`,
  `external_login_context_test.dart` a `news_page_render_test.dart` jako první
  reprezentativní integrační řezy; dál jen konkrétní stejné vlastníky prostředků.
- Přesunout setup z `main()` do scope, získat fresh storage/request logy pro test,
  vypnout auto refresh tam, kde není předmětem testu, kontrolovat nečekané requesty.
  Doménové testy používají porty; skutečný Supabase adaptér testovat syntetickým
  klientem s mock transportem. Žádný produkční backend, reálné tokeny ani emaily.
- U zbývajících statických DB entrypointů přesunout implementaci do existujícího
  doménového adaptéru s explicitním klientem a přepojit produkční kompozici.
  Nezavádět `setClientForTests`, globální reset všeho ani dvě implementace RPC.
- Pro platformní stav použít veřejné seam a registrovat disposer hned při získání
  zdroje. Neobnovitelný pluginový globál ponechat izolovaný, dokud není odstraněna
  konkrétní závislost. Nový obecný service locator je zakázaný.
- **Validace:** lifecycle testy dokazující nový kontext, disposal po neúspěšném
  setupu, dokončení všech disposerů a případů A-B-A; cílené kombinované běhy ve
  dvou deterministických pořadích. Nestačí samostatně zelené soubory. Pokud řez
  změní auth/identity kompozici, ověřit přihlášení, změnu kontextu a odhlášení
  skutečnou aplikací proti disposable local tenant podle skillu
  `festapp-local-e2e` a existujících E2E pravidel; žádný produkční účet/backend.
- **Výstup:** dokumentovaný kontrakt každé sdílené fixture; žádné mutable zdroje
  v registrační fázi a žádné uniklé requesty, listenery nebo timery.

### 6. Sdružení zbývajících Flutter případů a jeden úplný vstup

- Znovu seskupit podle prostředí a produkční oblasti, např. eshop, bank účty,
  news, admin widgety; udržet cílené spuštění oblasti i jednotlivého cases souboru.
  Nezvětšovat jednu sadu tak, že vytvoří nový dlouhý sériový ocas.
- Kanonický `automation/test_client.sh` zavedený ve vlně 1 spustí všechny Dart
  a Flutter test roots právě jednou; výchozí je úplná sada. Dart práce zahrnuje
  core package a po vlně 4 také skutečné VM adaptéry v `test_dart`, pokud je
  inventář přiřadil. Režimy `core` a `flutter` jsou jen výslovně částečné.
  Závislosti vyřešit před paralelním během, nespouštět souběžně pub operace nad
  stejným lockfile. Samotné měřené běhy používají již připravené dependencies.
- `fvm flutter test` bude záměrně pouze Flutter lane; samo neobjeví testy balíčku
  v `packages/`. Aktualizovat `automation/test_all.sh`, `CONTRIBUTING.md`,
  `docs/setup/local_development.md`, relevantní release/test skripty a skutečné
  CI caller entrypointy nalezené cíleným `rg` při každém přesunu. Přímé `test_reception_rollout.sh`
  musí zahrnout přemístěné kontrakty; nepřidávat zbytečné nové GitHub workflow.
- Runner propaguje každé selhání, při paralelním běhu počká na obě větve a vždy
  sebere všechny dílčí výsledky, včetně VM adapter rootu. Selhání kteréhokoli
  podřízeného runneru znamená neúspěch celku; úspěch posledního ho nepřepíše.
  Souběžnost nastavit podle benchmarku a paměti; nepřepsat všude default na 10.
- Kontrakt CLI: bez argumentu nebo `all` běží obě lane; `core` a `flutter`
  jsou výslovně částečné režimy a souhrn to uvádí. `core` znamená pouze balíček,
  nikoli automaticky všechny Dart/VM adapter testy; ty lze spustit přímo.
  Neznámý argument, chybějící
  FVM, nevyřešené závislosti nebo chybějící balíček skončí srozumitelnou chybou,
  nikdy úspěšným skipem či systémovým Dart/Flutter fallbackem. Přímé cílené
  příkazy uvést samostatně; nevytvářet překladač libovolných argumentů obou runnerů.
- Runner určuje root ze své vlastní cesty, funguje i z jiného working directory,
  nenačítá produkční `.env.local` a nevyžaduje backend credentials. Při `INT/TERM`
  ukončí a sklidí vlastní podprocesy včetně jejich testovacích dětí, nesahá na
  cizí FVM proces ani globální lock. Timeout nesmí zanechat Flutter testery.
  JSON výstupy jednotlivých lane ukládá odděleně, aby se události nepromíchaly.
- Doplnit malý kontrolní mechanismus inventáře/discovery: migrované případy právě
  jednou, každý `*_cases.dart` registrován a žádné importované testy opomenuté.
  Neporovnávat pouze názvy souborů nebo součet `test()` regexů.
- **Validace:** shell kontrakt na propagaci selhání každé lane a discovery;
  cílené sdílené fixture ve dvou pořadích; celý kanonický klientský příkaz.
- **Výstup:** běžná úplná kontrola používá jeden zdokumentovaný příkaz a nemůže
  zeleně vynechat nový Dart balíček nebo zamaskovat Flutter failure.

### 7. Kontrakce a závěrečný výkonový doklad

- Dokončit ledger níže. Guard čistoty musí kontrolovat import/export/part closure,
  conditional imports a balíčkové závislosti; přímý grep na `flutter` nestačí.
  Směr závislosti je aplikace -> core, nikdy opačně. Guard má malou negativní
  fixture, aby bylo doložené zachycení tranzitivního UI importu.
  Pro vlastní Dart zdroje použít AST/resolver ze SDK-kompatibilního analyzeru,
  nikoli domácí regex parser. Balíčkový closure vyhodnotit nad produkčními
  dependencies core; test/analyzer dev dependencies nejsou produkční závislosti.
  Ověřit také zakázaný cyklus mezi moduly, import cizího interního `src/` a
  platformní import přidaný přes conditional větev.
- Odebrat staré agregátory nebo jejich přesunuté registrace, prázdné soubory,
  dočasné mosty a superseded fake implementace. Upravit odkazy v aktivních
  skriptech/dokumentaci; historické evidence se zpětně nepřepisují.
- Spustit cílený analyze nad změněnými Flutter soubory a core analyze/test.
  U změn sdílených modelů provést web compile podle existujícího lokálního
  build postupu, bez deploymentu a bez přepínání tenant konfigurace. Případné
  blokování buildu rozpracovanou cizí prací hlásit přesně, neobcházet fallbackem.
- Závěrečná celá sada a tři benchmark běhy na finálních vstupech. Reportovat
  zachované případy, skipy, výsledky, warm medián, cold údaj pokud změřen,
  souběžnost, peak paměť a zbývající kritický řetězec. Neopakovat passing check
  po každé drobné editaci; opakování zde slouží konkrétně měření výkonu.
- **Výstup:** odstraněné staré cesty, zelený kontrakt a doložený dosažený výkon.
  Nesplněný výkonový cíl musí zůstat viditelně označen jako nesplněný.

## Ledger odstranění

| Dnešní artefakt | Konečný stav | Důkaz |
|---|---|---|
| Přesunuté protokoly/algoritmy v `lib/` | Smazány; produkce importuje core. | Žádné staré importy, žádné forwarding exports. |
| Store s výchozím StorageHelperem | Pouze core store s explicitním portem; adaptér v aplikaci. | Runtime composition a skutečný adapter kontrakt. |
| Remote soubor s Flutter Supabase i protokoly | Čisté porty/HTTP a samostatný Supabase adaptér. | Dependency closure core. |
| UI/DB metody v migrovaných doménových modelech | Prezentační adaptéry a existující command kontrakty. | Migrovaná skutečná produkční volání, původní JSON fixtures. |
| `ITrinaRowModel` a generický grid | Záměrně ponechaný UI kontrakt; migrovaná doména jej neimplementuje, pojmenované grid records ano. | Žádný Flutter/grid import v core; skutečné save/cancel toky. |
| Cyklický produkt/type object graph | Vlastněný katalog a relace pomocí ID; vnořený wire kontrakt beze změny. | Žádné dvousměrně synchronizované mutable kopie; decode/encode fixtures. |
| `StorageHelper._databases` jako implicitní test fixture | Explicitně vlastněný handle/factory u testovaného adaptéru; runtime cache případně zůstává s pojmenovanou životností. | Close před delete, žádná data či otevřený handle z předchozího testu. |
| Flutter registrace přesunutých core případů | Odstraněny; Dart registrace právě jednou. | Semantický inventář před/po, bez duplicit. |
| Flutter registrace čistě VM adapter případů | `test_dart/adapters/` a skutečný VM runner; core nemá závislost zpět na aplikaci. | Úplný runner je zahrne a propaguje jejich selhání. |
| Setup efektů v `main()` a rozptýlené vlastněné fake storage | Scoped fixture a jeden fake na skutečný port. | A-B-A a cleanup při selhání; žádné privátní reset hacky. |
| Warning-only Flutter větev `test_all.sh` | Volání úplného klientského runneru, fail-closed exit code. | Vynucené selhání každého test rootu v kontraktním testu. |
| Staré instrukce „Flutter příkaz = všechny Dart testy“ | Výslovné rozlišení celku a lane. | Aktivní docs a caller inventář. |
| Izolované custom/native testy | Záměrně ponechány jen s konkrétním důvodem. | Konečná klasifikace, nikoli anonymní výjimky. |

## Předpoklady, rizika a dokončení

- Předpoklad: testy a plán se mezitím mohou změnit. Implementátor ve vlně 0
  aktualizuje baseline a omezený inventář, neprovádí nový průzkum celého projektu.
- Předpoklad: jeden core balíček stačí. Nový balíček přidat jen při doloženém
  odděleném deployment/dependency kontraktu, ne pro zrychlení jedné testovací funkce.
- Riziko: flattening `ProductModel`/`EventModel` může změnit null semantiku,
  měny, čas či identitu. Migrovat vertikálně s konkrétními round-trip/behavior
  kontrakty; neprovádět hromadný rename modelů před přepojením spotřebitelů.
- Riziko: fake může být rychlý a nesprávný. Zachovat testy skutečných adaptérů,
  včetně atomických storage operací a privátního auth/scope kontraktu.
- Riziko: nový core package se tiše vynechá při `fvm flutter test`. Kanonický
  runner, CI callery a kontrola inventáře jsou povinnou součástí migrace.
- Riziko: současný host neodpovídá CI; výkon a paměť reportovat odděleně.
  Horní počet workerů není univerzální architektonický kontrakt.
- Žádný známý blocker pro lokální implementaci. Produkční zásahy nejsou potřeba.

Hotovo znamená: čistý dependency closure core, stejné produkční rozhodování,
žádné staré paralelní implementace, úplná a zelená sada, ověřené lifecycle fixture,
fungující cílené testování, aktualizované callery a explicitní výkonový výsledek.
Výjimku nelze uzavřít jako „hotovo“ jen proto, že nový test běží rychle.

### Konečný předávací záznam

Součástí implementace bude jeden stručný záznam v `docs/development/`:
aktuální modulová mapa, konečná klasifikace zbylých Flutter testů a důvody jejich
izolace, staré -> nové umístění migrovaných případů, provedené gates a benchmark.
Nemá duplikovat celý tento plán nebo obsahovat surové logy. Výkonový souhrn
obsahuje wall time obou lane i celku; jejich prostý součet se při souběhu
nevydává za wall time. Uvést současně počet případů, počty engine startů a paměť,
aby nižší čas nebyl vykoupen ztrátou pokrytí nebo neúnosným počtem workerů.

Implementace probíhá lokálně po koherentních řezech. Revertovat lze celý řez
včetně produkčních spotřebitelů, nikoli obnovit skrytý fallback. Commit, push,
merge ani nasazení tento plán neautorizuje. Před případnou samostatně vyžádanou
publikací platí běžné repository gates.
