# Plánované změny cen v tabulce Produktů

Datum: 2026-10-04
Stav: Implementováno a lokálně ověřeno; produkční migrace, deploy a cron dosud neověřeny.
Verification: standard (ceny, oprávnění, migrace a souběh transakcí).

## Výsledek a rozsah

Správce vidí aktuální cenu a budoucí cenové změny přímo v řádku produktu. Jedním kliknutím naplánuje cenu od určitého data a času, upraví plán nebo jej zruší. Po skutečném provedení změna zmizí z plánů a nová cena se zobrazí jako aktuální. Historie se v této funkci nezobrazuje.

Rozsah: Flutter tabulka Produktů, editor plánů, autorizované SQL rozhraní, existující spouštěč, synchronizace a cílené testy včetně prodejního toku. Zachovat existující podporu `products.is_hidden` a `forms.is_open`, ale nevytvářet pro ně nové UI. Žádné hromadné změny, opakované cenové kalendáře, změny měny v plánu ani přepracování historie objednávek.

Implementace a izolované lokální ověření byly autorizovány uživatelem prostřednictvím execution promptu. Produkční migrace, commit, push a deploy vyžadují samostatnou autorizaci; produkční rollout má rozsah jednoho vybraného tenantu.

## Zjištěný stav a důkazy

Průzkum pracovního stromu na větvi `release/ticket-editor-ui-20261003`, HEAD `e380979aa`. Strom obsahuje rozpracované změny i v `products_tab.dart`, `product_model.dart`, `eshop_columns.dart`, `db_eshop.dart` a překladech. Implementace je musí respektovat; nepřepisovat je ani resetovat. Sdílený kód patří podle pravidel do main; před implementací vyřešit začlenění do aktuální práce bez ztráty těchto úprav.

| Fakt | Důkaz | Dopad |
|---|---|---|
| Tabulka má typ změny, subjekt, textovou hodnotu, čas s pásmem, příznak applied a nullable occasion. | `database/tables/tables.sql`, `eshop.planned_changes` | Znovu použít úložiště; bezpečně doplnit validaci a stav selhání. |
| Produktová tabulka má editovatelnou cenu, ale nemá sloupec plánů. V prohledaném Flutter kódu není napojení na planned_changes. | `lib/components/eshop/views/products_tab.dart`, `eshop_columns.dart: PRODUCT_PRICE` | Doplnit celé čtení i zápis, nikoliv jen renderer. |
| Admin čtení je chráněné podle organizace a práva prohlížet objednávky. | `database/functions/eshop/get_products_and_types_for_occasion.sql` definuje `get_products_and_types_for_edit` | Rozšířit právě admin bundle; neveřejný plán neposílat automaticky do veřejných formulářů. |
| Aktuální baseline používá wrapper a implementaci se synchronizačními událostmi. | `supabase/baseline/20260805230000_production_schema.sql`, `supabase/migrations/20260802234000_client_sync_v1_expansion.sql: apply_planned_changes_client_sync_v1` | Zachovat sync. Starší SQL zdroj v `database/functions/cron/apply_planned_changes.sql` není rovnocenná náhrada. |
| Spouštěč vybírá splatné řádky podle času/id s FOR UPDATE SKIP LOCKED; cena se aktualizuje přímo. | Stejná funkce | Zámek plánů sám nezaručuje pořadí změn jednoho produktu při dvou workerech. Chybný cast může zrušit celý běh. |
| Definice cronu předpokládá minutový interval. | `database/functions/seed/crons.sql`, `automation/hetzner-supabase/runtime/finalize-canonical-database-operations.sh` | Runtime job, cílová DB, role a poslední výsledky nejsou tímto průzkumem potvrzené. |
| Běžná aktualizace produktu kontroluje vztah zálohy a ceny. | `database/functions/eshop/update_product.sql` | Naplánovaná cena musí respektovat tentýž invariant, také při aplikaci. |
| Objednávka počítá cenu na serveru a ukládá historii. | `database/functions/eshop/create_ticket_order.sql` | Ověřit skutečnou cenu nových objednávek a neměnnost existujících. |
| Existují kompaktní souhrny cenových rozdílů. | `models/orders_history_model.dart: generateSingleLineSummaryWidget`, `views/product_changes_preview.dart` | Převzít vizuální slovník šipky, nikoliv historický model nebo přeškrtnutí stále platné ceny. |

V `database/tests` byl nalezen kontrakt existence sync funkce, nikoliv cílené behaviorální testy plánovaných cen. To není důkaz funkčnosti. Produkce nebyla dotazována a testy nebyly v plánovací fázi spouštěny.

## Konkrétní návrh UX

Samostatný specializovaný UI/UX skill není v dostupném katalogu. Použít existující Material komponenty aplikace a oficiální návrhové podklady: [Material dialogy](https://m3.material.io/components/dialogs/guidelines), [výběr času](https://m3.material.io/components/time-pickers/), [UX texty](https://codelabs.developers.google.com/codelabs/material-communication-guidance). Následující rozložení je návrh pro Festapp, nikoliv tvrzení o požadavcích těchto zdrojů.

### Řádek produktu

Zachovat číselný sloupec ceny se současným řazením a editací, v Produktové tabulce jej označit „Aktuální cena“. Vedle měny přidat „Změna ceny“. Nezměnit globálně názvy cen v jiných tabulkách.

| Produkt | Aktuální cena | Měna | Změna ceny |
|---|---:|---|---|
| Vstupenka | 450 | Kč | ◷ 450 Kč → **550 Kč** · od 15. 10. 2026 09:00 · +1 další |
| Doprovod | 200 | Kč | + Naplánovat |

- Celá buňka s plánem otevře správu; bez plánu jasná akce „Naplánovat“. Žádná povinná cesta přes kontextové menu.
- Kompaktní jednorádkový souhrn v rytmu současné tabulky, bez zvětšování všech řádků. Nejbližší cena a čas mají přednost před počtem dalších změn.
- Výchozí šířka asi 160 px bez plánů, asi 360-420 px při alespoň jednom plánu v celé načtené sadě. Neodvozovat od filtrovaných řádků; nereagovat skákáním při filtrování. Ruční změnu šířky uživatelem respektovat. Konkrétní API ověřit v používané verzi TrinaGrid.
- Omezený prostor: zkrácení a tooltip s úplným souhrnem; detail dostupný i kliknutím/klávesnicí, nejen hoverem. Na úzké obrazovce dostupná akce i při horizontálním posuvu tabulky.
- Aktuální cena se nepřeškrtává. Budoucí stav odlišuje ikona hodin, datum a text, nikoliv jen barva. Změny dolů nejsou chyby.
- Prohlížející bez práva zápisu vidí detail, nikoliv aktivní akce pro změnu.

### Dialog „Plánované změny ceny“

Na desktopu přibližně 560 px, na malém displeji responzivní celoplošný dialog. Nahoře název produktu, aktuální cena a časové pásmo akce. Pod tím chronologický seznam pouze neprovedených změn s cenou, termínem a akcemi Upravit/Zrušit změnu. Nejbližší změna první; všechny další řádky ukazují navazující ceny a vlastní datum i čas. Více termínů jednoho produktu je výslovný požadavek uživatele, nikoliv volitelné rozšíření. Problémové položky mají stav a možnost nápravy, neoznačovat je jako historii.

Prázdný stav rovnou ukáže formulář: „Nová cena“ s pevnou měnou produktu, „Datum“, „Čas“. Žádná automaticky potvrzená cena nebo čas. Datum/čas lze vybrat i napsat klávesnicí. Primární tlačítko „Naplánovat změnu“, při úpravě „Uložit změnu“; sekundární „Zavřít“. Přidání další změny otevře tentýž formulář uvnitř dialogu, ne řetězec modalů.

Průběžné shrnutí: „Od 15. 10. 2026 v 09:00 bude cena 550 Kč.“ Podpora pásma přes `lib/services/time_helper.dart` a timezone akce, ne automaticky pásmo počítače. U letního času odmítnout neexistující lokální čas; u dvojznačného času vyžádat výběr konkrétního offsetu. Čas při ukládání ověřuje server.

Krátká nápověda vysvětlí, že jde o cenu nových objednávek, stávající objednávky se nepřepočítají a automatické provedení běží přibližně po minutě. Během ukládání blokovat opakované odeslání; při chybě zachovat formulář. Úspěch zobrazit až po serverovém potvrzení a načíst aktuální bundle.

Zrušení naplánované změny má krátké potvrzení s částkou a termínem. Zavření rozepsaného formuláře řešit standardním vzorem aplikace pro neuložené změny. Fokus se po zavření vrátí do původní buňky; přístupné názvy akcí zahrnují produkt/termín.

### Více změn v různých termínech

Příklad jednoho produktu: nyní 450 Kč; od 15. 10. 2026 09:00 cena 550 Kč; od 1. 11. 2026 00:00 cena 650 Kč; od 10. 11. 2026 18:00 cena 500 Kč. V tabulce je nejbližší přechod a „+2 další“; kliknutí otevře úplnou chronologickou osu. Tooltip může ukázat všechny termíny, ale dialog je dostupný i bez hoveru. Po první aplikaci se aktuální cena změní na 550 Kč a souhrn ukáže 550 Kč → 650 Kč, další termín a „+1 další“.

- Každý termín má vlastní identitu a lze jej jednotlivě přidat, upravit nebo zrušit. Počet není omezen na jedinou či dvě změny; delší seznam v dialogu scrolluje a hlavní akce zůstávají dostupné.
- Vložit lze i termín mezi existující změny. Změna data přeuspořádá seznam. Náhled navazujících přechodů se přepočítá, uložené cílové částky ostatních plánů se nemění.
- Při zrušení prostřední změny se propojí zbývající termíny. Nejde o cenová období s koncem: každá cena platí do další skutečně provedené změny. Poslední zůstává platná bez automatického návratu.
- Při selhání dřívější změny není její částka platnou aktuální cenou. Další absolutní změna může proběhnout samostatně; UI odliší očekávanou návaznost od potvrzené aktuální ceny.
- Testovací scénář musí obsahovat alespoň tři termíny, vložení mezi ně, přesun přes jiný termín, odstranění prostředního, kolizi stejného okamžiku a postupné provedení. Zkontrolovat pořadí, částky, počet dalších změn a zachování poslední ceny.

### Obnova a mimořádné stavy

- Po uplynutí termínu se cena lokálně nepřepne odhadem. Zobrazit „Čeká na provedení“, dokud server nepotvrdí aplikaci; po delším prodlení výstrahu a možnost obnovy.
- Při otevřené tabulce obnovit data po nejbližším termínu, při návratu aplikace do popředí a během čekání nejvýše jednou za minutu. Timer zrušit při opuštění stránky. Obnova nesmí zahodit rozpracované editace gridu: při dirty stavu pouze označit dostupnou aktualizaci a načíst ji po uložení/zahození.
- Neprovedený plán se filtruje podle stavu, nikoliv pouze `change_time > now()`: jinak by opožděný cron z UI zmizel.
- Ruční změna aktuální ceny zachová budoucí absolutní ceny a přepočítá souhrn. U ceny s plány zobrazit vysvětlení „Budoucí naplánované ceny zůstávají platné“.
- Měnu nelze změnit, dokud existují neprovedené cenové plány; vynutit na serveru ve všech zapisujících cestách, UI vysvětlí nutnost je nejdřív zrušit. Neinterpretovat uloženou částku potichu v jiné měně.

## Datový kontrakt a invarianty

1. `eshop.products.price` zůstává jedinou aktuální cenou. `eshop.planned_changes` zůstává jediným úložištěm plánů. Flutter je pouze zobrazuje a předává příkazy.
2. Rozšířit admin RPC `get_products_and_types_for_edit` o seznam neprovedených cenových plánů u každého produktu, serverový čas a potřebný stav/verzi. Jedno načtení, žádné RPC pro každý řádek. Plány nepatří do obecného `ProductModel.toJson()` pro aktualizaci produktu.
3. Nové veřejné RPC `save_product_price_change` a `cancel_product_price_change` přijímají ID produktu/plánu, absolutní číselnou cenu, UTC instant a očekávanou verzi při editaci. Vlastníka i occasion odvozují z produktu; ověřují editora příslušné akce a tenant. SECURITY DEFINER má explicitní search_path, kvalifikované eshop tabulky a minimální granty. Žádné přímé klientské DML do planned_changes.
4. Přijmout nezápornou konečnou cenu v přesnosti měny (0 je legitimní, pokud projde pravidly záloh), budoucí čas, existující produkt a správný typ plánu. Dva aktivní cenové plány stejného produktu se stejným okamžikem odmítnout pomocí DB constraint/indexu. Více různých budoucích okamžiků povolit. Hodnota stejná jako očekávaná předchozí cena může zůstat platná; upozornit, ale neměnit implicitně další plány.
5. Zápis ceny i aplikace plánu sdílí validaci ceny/zálohy. Při implementaci dohledat také změny produktu uvnitř `update_form` a sync fasád, aby neobcházely zákaz změny měny nebo invariant ceny. Neprovádět obecný refaktor všech produktových operací.
6. Doplnit `revision` pro optimistickou kontrolu a `failed_at`/stabilní `failure_code` pro neproveditelné plány. applied zůstává kompatibilním příznakem úspěchu. Chybný plán zůstává viditelný, neběží automaticky stále dokola; oprava resetuje chybu a musí určit budoucí termín. Zrušení odstraní pouze neprovedený řádek, aplikované se nemažou kvůli UI.
7. Spouštěč kontroluje typ, subjekt, occasion a aktuální pravidla. Nesprávný subjekt nebo neznámý typ nesmí vykázat jako úspěšně aplikovaný. Selhání jedné položky zaznamenat uvnitř izolovaného bloku a pokračovat dalšími. Při chybě sync zápisu vrátit změnu ceny dané položky zpět, nevytvářet cenu bez sync události.
8. Serializovat běhy spouštěče transakčním advisory zámkem; změny zpracovat deterministicky podle `(change_time, id)`. CRUD a spouštěč sdílí pořadí zámků produkt -> plán, stav se znovu ověří po zamčení. Dva správci dostanou konflikt místo tichého přepsání. Cancel proti aplikaci má jediný transakční výsledek. Zopakování požadavku po nejisté síti řešit znovunačtením stavu, ne duplicitním plánem.
9. Po prodlevě zpracovat platné splatné změny chronologicky; nejnovější splatná vítězí. Úspěšné nastavení ceny, applied a sync událost jsou v jedné transakci; opakovaný běh je nezopakuje.
10. Úspěšná cena platí od skutečného provedení serverem, nikoliv přesně v sekundě termínu. Stávající minutový mechanismus zachovat; přesná aktivace přímo v checkoutu by byla jiný rozsah.

## Postup implementace

### 1. Charakterizace a databázový kontrakt

- Použít izolovanou lokální DB dle CONTRIBUTING. Potvrdit efektivní definice wrapperu, sync funkce a zapisujících cest z baseline + migrací. Neměnit historickou baseline.
- Připravit cílené testy `database/tests/eshop/product_price_scheduling_test.sql`: čtení, create/edit/cancel, oprávnění včetně cizího tenantu, neplatné částky/časy, zálohy, kolize a verze.
- Doplnit kanonické SQL zdroje pro nové RPC, admin bundle, schema a novou následnou migraci. Doplnit index načítání pending produktových cen a index splatných plánů.
- Před constraints provést diagnostiku existujících duplicit, orphanů, null occasion a nečíselných hodnot. Bezpečně odvozenou occasion doplnit z ověřeného vlastníka; nejednoznačné položky označit selháním a vyřadit z automatické aplikace. Nevolit libovolnou cenu a nezahazovat data. Constraint aplikovat jen na aktivní cenové plány, neomezit jiné typy.
- Výstup: autorizované round-trip RPC a migrace zachovávají platné dosavadní plány. Testovat migraci také na fixture starého schématu s existujícími plány.

### 2. Spolehlivé provedení a prodejní tok

- Sjednotit `database/functions/cron/apply_planned_changes.sql` s efektivním sync chováním. Zachovat veřejný entrypoint `public.apply_planned_changes()` i používanou sync implementaci; žádný druhý scheduler.
- Implementovat invarianty selhání, validace a zámků. Nepoužít aplikační triggery. Při smazání produktu odstranit jeho neprovedené cenové plány v explicitní transakční cestě; prověřit i mazání přes formulář.
- Behaviorální SQL testy: budoucí plán nic nemění, splatný ano, více splatných po výpadku, opakovaný běh, vadný plán neblokuje jiný produkt, audit/sync právě jednou, změna zálohy mezi naplánováním a aplikací, regrese is_hidden a forms.is_open.
- Souběh ověřit dvěma skutečnými DB spojeními (dva workery, edit/cancel proti workeru), ne jen sekvenčním SQL testem. Použít lokální harness a zaznamenat jeho příkaz.
- Objednávková integrační fixture vytvoří objednávku před změnou i po ní a ověří snapshot ceny; otestuje také otevřený veřejný formulář se starou cenou a konzistentní přepočet/potvrzení při odeslání. Pokud současný checkout selže, opravit konkrétní cestu bez přeceňování starých objednávek.
- Výstup: platný plán ovlivní nové nákupy a ponechá existující objednávky beze změny; nejistota není maskovaná applied=true.

### 3. Tabulka a dialog

- Přidat model `ProductPriceChange` a service metody v `lib/components/eshop/db_eshop.dart`; admin metadata připojit k produktu pouze pro čtení, bez zpětného zápisu přes generický product save.
- Upravit `views/products_tab.dart`, `eshop_columns.dart`, potřebné mapování buněk v `models/product_model.dart`; renderer izolovat do widgetu cenového plánu. Callback pracuje se stabilním ID, nikoliv indexem řádku.
- Přidat `views/product_price_changes_dialog.dart`, řazení plánů, formulář, chybové stavy a refresh. Použít existující RightsService, ExceptionHandler.guard, formátování částek, časové helpery a komponenty dialogu.
- Rozšířit `orders_strings.dart` a cs/en překlady; synchronizovat Flutter/web překlady repo skripty. Bez ručně vložených produkčních textů ve widgetech.
- Připojit obnovu do životního cyklu Produktů. `SingleDataGridController.reloadData()` existuje, ale nesmí vymazat rozpracovaný grid; ověřit jeho použití před zapojením. Zachovat filtr, řazení, scroll i ruční šířky.
- Výstup: v prázdném řádku lze plán vytvořit a po uložení jej okamžitě vidět; edit/cancel se projeví až podle skutečného výsledku serveru.

### 4. Cílené ověření a předání

- Widget/model testy v `test/components/eshop/product_price_scheduling_test.dart`: prázdný/jeden/více plánů, chyba a pending po termínu, aplikovaný skrytý, oprávnění, zachovaný formulář při chybě, refresh bez ztráty grid editace, pásmo/DST. Použít ovládané hodiny.
- Spustit cílené SQL testy a odpovídající stávající objednávkové/sync testy. Základní příkaz: `DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' node web_client/scripts/run_db_tests.js database/tests/eshop/product_price_scheduling_test.sql`.
- `fvm flutter test test/components/eshop/product_price_scheduling_test.dart` a cílené `fvm dart analyze` pouze změněných Dart souborů. Testy nepouštět po každé jednotlivé editaci, validovat soudržné části.
- Pro skutečný UI tok použít skill `festapp-local-e2e` a izolovaný headless `agent-browser`: přihlášení editora, naplánování, reload, úprava, zrušení, spuštění workeru na lokální fixture, nová aktuální cena. Lokální fixture z důvodu testu splatnosti smí změnit čas plánu; produkční data ne.
- Vizuálně ověřit desktop i úzký viewport, větší text a klávesnici; screenshot má prokázat čitelnost ceny, termínu a akcí. Při oprávněném live ověření zvlášť zkontrolovat jediný aktivní cron, správnou DB/roli a výsledky běhů, bez vytváření testovacích cen v produkci.
- Výstup: stručná evidence příkazů/výsledků a přesné oddělení lokálně ověřeného chování od stavu produkčního nasazení.

## Nasazení, zachování a odstranění

Neodstraňovat tabulku plánů, aplikované záznamy, historické migrace ani podporované jiné typy změn. Odstranit rovnoběžné nesynchronizující chování v kanonickém SQL zdroji jeho sjednocením s efektivním entrypointem. Nepřidávat V2 API nebo fallback, který by polykal chybu načtení plánů jako prázdný seznam.

Po samostatné autorizaci: ověřit aktivaci vybraného tenantu podle ai_context, read-only preflight existujících dat a cronu, nasadit aditivní DB změnu, ověřit ji, poté klienta a smoke. Nevolat široký finalizační skript infrastruktury jen kvůli cronu - mimo jiné unscheduleuje všechny joby. Chybějící job opravit jen cíleným schváleným postupem.

Starší klient bez nových polí musí dál fungovat, ale serverová ochrana cen platí i pro něj. Rollback UI ponechá validní DB kontrakt a plány; rollback workeru musí zachovat synchronizaci. Již provedené ceny automaticky nevracet. Počet čekajících a selhaných plánů i chyby běhu musí být dohledatelné.

## Předpoklady a zbylá rizika

- Více různých termínů na produkt uživatel výslovně potvrdil. Návrh používá absolutní ceny; neřeší procentní změny ani automatický návrat ceny.
- Minutová přesnost je vědomé navázání na stávající cron. Zpoždění je viditelné, žádná záruka přesné sekundy.
- Runtime cron, současná produkční data a jejich validita nejsou zatím ověřené. Před nasazením je musí doložit implementující agent schváleným backendovým přístupem.
- Časové pásmo akce a měnová přesnost mají existující helpery; implementující agent ověří jejich konkrétní kontrakt pro DST a dotčené měny, nevytvoří paralelní převod.
- Rozpracované soubory mohou mezitím změnit kontrakt. Při rozdílu upravit tento plán podle konkrétního důkazu, zachovat uživatelský výsledek.

## Podmínky dokončení

- Aktuální cena je jednoznačná; pouze neprovedené plány se zobrazují s cenou a termínem. Nejméně tři navazující změny v různých datech projdou celým tokem včetně vložení, přesunu a zrušení prostřední změny.
- Správce vytvoří/upraví/zruší plán přímo z řádku, prohlížející nemůže zapisovat ani přes RPC.
- Worker je ověřen proti chybným vstupům, opakování a souběhu; cena a sync se nemohou rozejít.
- Lokální test prokazuje dopad na novou objednávku bez změny staré a UI po aplikaci načte nový stav.
- Cílené testy a vizuální kontrola prošly; produkční ověření a případné nasazení jsou výslovně doložené nebo označené jako zbývající samostatný krok.

## Implementační doplnění a ověření 2026-10-04

- Zachován existující rozpracovaný checkout `release/ticket-editor-ui-20261003`; žádný commit, push ani tenantová propagace. Nová migrace je `20261004150000_product_price_scheduling.sql`.
- Skutečné `products.price` je `NUMERIC(10,2)` (`database/tables/tables.sql`). Cílová cena proto musí být reprezentovatelná: nejvýše 99999999.99 a přesnost nejvýše dvě desetinná místa, pro měny bez minor units celé číslo. Měny se třemi minor units nepřidávají tiché zaokrouhlení do stávajícího sloupce. Změna přesnosti sloupce je samostatný rozsah.
- Uživatel při implementaci výslovně doplnil automatický reload při přepínání tabů. `AdminTabActivity` nyní dává společným tabulkám, Produktům a Reportu explicitní signál návratu. Rozepsané tabulky zůstávají uchované; příchozí request znovu kontroluje dirty stav. Zachovává se filtr, řazení, scroll a šířky. Uložení/zahození standardně znovu načte data a odstraní upozornění.
- Baseline má na `eshop.planned_changes` `GRANT ALL` pro anon/authenticated. Migrace proto odebírá všechny přímé granty tabulky i sekvence, včetně TRUNCATE a SELECT; admin čtení jde přes autorizovaný bundle. Service scheduler si ponechává své granty.
- Ověřeno 7 SQL testů, samostatně legacy migrace a skutečný souběh DB spojení, 32 Flutter testů, cílený analyzer a izolovaný headless tok skutečné aplikace. Evidence a provozní krok: [validation.md](evidence/product-price-scheduling-2026-10-04/validation.md).
- Produkční backend ani cron nebyly dotazovány či měněny. Lokální úspěch není důkazem produkčního nasazení.
