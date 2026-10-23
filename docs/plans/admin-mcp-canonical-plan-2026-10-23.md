# Kanonické operace administrace pro UI a MCP

Datum: 2026-10-23. Stav: etapy 0, 0B, 1 a řez 2A lokálně dokončeny; pokračují další řezy etapy 2.
Ověřování implementace: `standard` (oprávnění, souběh, veřejné kontrakty a migrace).
Dokončení jednotlivých řezů dokládá checkpoint níže. Transportní
upgrade byl samostatně dokončen a nasazen z main
`4cfc9b7bc66f48c2d6e42155f08e905dde112d0d`: MCP `2026-07-28`, server SDK
2.3.1, Node adaptér 2.1.1, oficiální legacy hranice; všech 74 MCP testů prošlo
včetně disposable PostgreSQL bez skipů. Exekuční práce začíná etapou 0 níže.

## Výsledek a hranice

Správce může přes MCP vykonat stejné doménové operace jako přes běžnou
administraci, v mezích svých aktuálních práv a uděleného přístupu. UI a MCP
používají stejné doménové příkazy, výpočty, validace a vedlejší účinky.
Jeden uživatelský krok obsahující související databázové zápisy má jednu
transakční hranici. Samostatné uživatelské kroky se neslučují jen kvůli počtu RPC.

Základ tvoří sdílená revize `0fd16f4374b065c578ecee3f647fda40cb17b37b`,
nasazená pro `festapptickets` ve verzi `0.20.365+859`. Produkty, objednávky,
manuální platby a fronta odeslání vstupenek se znovu neimplementují. Jejich
existující kontrakty slouží jako vzor. [Mapa pokrytí](../architecture/admin-mcp-parity.md)
zůstává přehledem schopností; tento plán určuje pořadí a podmínky další práce.

Rozsah zahrnuje i opravy současných cest UI, pokud jsou nutné ke sjednocení
příslušné operace. Nezahrnuje nový obecný CRUD framework, přepis aplikace,
produkční testovací objednávky, skutečné platby/e-maily ani vydání jiných tenantů.
Externí assetové a platební operace se nevydávají za atomickou SQL transakci.

## Ověřený výchozí stav

| Fakt a konkrétní důkaz | Důsledek pro návrh |
| --- | --- |
| `database/functions/eshop/product_catalog.sql`: `get_product_catalog`, `manage_product`; `lib/components/eshop/supabase_eshop_commands.dart`; `tools/festapp/src/operations/products.mjs` | Již existuje společná hranice UI/MCP, původní verze produktu a opakovatelný příkaz. Nevytvářet druhý produktový engine. |
| `lib/components/eshop/db_eshop.dart`: `saveNewProductWaveTarget` volá receipted `save_product_wave_target_client_sync_v1`, `saveProductWaveTarget` volá přímo `save_product_wave_target` | Nové a existující cenové cíle mají různé transportní cesty. Nejdřív sjednotit, potom exponovat. |
| `database/functions/eshop/save_product_wave_target_client_sync_v1.sql` přijímá i `wave_id` a `expected_wave_revision` | Existující příkaz už umí část požadované konsolidace; nepřidávat bezdůvodně nový paralelní příkaz. |
| `lib/components/blueprint/blueprint_standing_inventory.dart`: `prepare` postupně volá `_savePool`, `_saveResource`, `_linkProduct` a pamatuje si částečný úspěch | Konkrétní kandidát pro jednu atomickou přípravu kapacity; současné obnovení není databázová atomicita. |
| `lib/components/inventory/inventory_commands.dart` používá příkazy pro pool/resource, produkt má vlastní příkaz pro kontexty | Reuse doménových vlastníků; wrapper nesmí jen vytvořit tři nezávislé receipt/commit hranice. |
| `lib/components/email_templates/db_email_templates.dart` používá `update_email_template`, `update_entity_email_banner`, `delete_entity_email_template` | Je třeba posoudit společný version/retry kontrakt, dědičnost a rozsah unit/occasion. |
| SQL vlastníci v `database/functions/others/` ověřují skutečnou hierarchii a `can_write_*_email_templates` | Neodvozovat oprávnění šablon od práva zapisovat objednávky. Zachovat existující serverové spotřebitele. |
| `supabase/functions/_shared/emailRenderer.ts` a `packages/festapp_core/lib/src/email_templates/` mají serverové a klientské části | Shodu náhledu a doručeného obsahu ověřit společnými scénáři; netvrdit, že jde již o jedinou implementaci rendereru. |
| `lib/components/forms/supabase_form_commands.dart`: create/save/duplicate/delete používají vlastní client-sync příkazy | Připojit existující agregát; nevytvářet MCP ukládání jednotlivých řádků formuláře. |
| `occasion_commands.dart` a `unit_commands.dart` již ukládají agregáty s původní verzí | Rozšiřovat tuto cestu; neobcházet ji přímým DML. |
| `packages/festapp_contracts/mcp-permissions.mjs` je sdílený registr issueru a webového souhlasu | Nové operace registrovat jednou; staré granty se nesmějí automaticky rozšířit. |

První průchod pokrývá skutečné unit taby v `unit_admin_page.dart` a seznamy
`AdministrationTabs` v `admin_page_helper.dart`. Pozdější oblasti níže mají
záměrně ohraničené dohledání konkrétních operací, nikoliv předstíraný úplný audit
každého formuláře. Při zahájení etapy ověřit pouze její call graph a změny proti
základu, neprovádět znovu průzkum celé aplikace.

## Konkrétní operace a pokročilá nastavení

Lidsky čitelný [statický katalog](../reports/admin-capabilities-2026-10-23.html)
a jeho [zdrojový soupis](../reports/admin-capabilities-2026-10-23.json) rozepisují
94 položek. Patnáct současných vzdálených MCP nástrojů je při generování ověřeno
proti skutečnému runtime katalogu. Některý nástroj pokrývá více úkonů, takže počet
položek není počet RPC nebo nástrojů. Jde o doložený snapshot, nikoliv o živé
oprávnění konkrétního připojení nebo tvrzení o úplnosti všech tenant variant.

Nové konkrétní důkazy pro provozní správu míst:

- `BlueprintLayoutHost._toggleSelectedBlocked` mění draft; jeho uložení vede
  přes blueprint aggregate save. `BlueprintLayoutController.setBlockedForSeats`
  rozšiřuje výběr o nedělitelné selection units a odmítá chráněná místa.
- `database/functions/blueprint/save.sql` porovnává `expected_layout_revision`,
  ověřuje skutečné spot/occasion vazby a odmítá změnu blokace již objednaného
  místa nebo místa s aktivním dočasným držením (`BLUEPRINT_SEAT_PROTECTED`).
- `BlueprintLayoutHost._releaseTemporaryHolds` vede přes
  `TicketCommands.releaseHolds` do `release_blueprint_holds_client_sync_v1`.
  Příkaz rozšiřuje nedělitelné výběrové celky a odmítá prodaná místa.
- `TicketCommands.swapSpots` používá `swap_spot_tickets_client_sync_v1`.
  Zrušení vstupenek má jiného vlastníka (`storno_tickets_client_sync_v1`).

| Konkrétní operace / nastavení | Vlastník nebo doložená UI cesta | Zařazení |
| --- | --- | --- |
| Blokovat a odblokovat volná místa | Blueprint draft/controller + aggregate save, `blocked` binding | Provozní řez 2B |
| Uvolnit dočasnou rezervaci | `release_blueprint_holds_client_sync_v1` | Provozní řez 2B |
| Prohodit místa vstupenek | `swap_spot_tickets_client_sync_v1` | Provozní řez 2B |
| Vytvořit objednávku z míst; zrušit vybrané vstupenky | `blueprint_create_order_dialog.dart`, `TicketCommands.cancel` | Provozní řez 2B, objednávkové vlastníky |
| Geometrie, názvy, stoly, skupiny a nedělitelné výběry | Blueprint layout/controller/save | Etapa 7, samostatné řezy |
| Produkt místa/skupiny a jeho dědičnost | Blueprint bindings + kanonické product rules | 2B/7 podle konkrétní změny |
| Kapacita, zobrazování volných míst, čekací listina a délka nabídky | `form_capacity_settings.dart`, waitlist owner | Etapa 4 |
| Splatnost, upomínky a interval, platební účet/metoda/příjemce | `form_settings_content.dart` | Etapa 4, zachovat finanční oprávnění |
| Typ a počáteční číslo variabilního symbolu | `form_variable_symbol_settings.dart` | Etapa 4 |
| Barvy, typografie a vzhled formuláře | `form_design_settings.dart` | Etapa 4 |
| Veřejný odkaz, Reply-To, časové pásmo akce | `occasion_advanced_settings.dart` | Etapa 5 |
| Výchozí Reply-To, komunikační tón a časové pásmo pořadatele | `unit_settings_screen.dart` | Etapa 5 |
| Ruční skenování a zobrazení skryté poznámky při kontrole | `ticket_scanning_settings.dart` | Etapa 5, oddělit nastavení od check-in příkazu |
| Feature přepínače a nastavení každé aktivní funkce | `occasion_features_section.dart` + příslušný Feature editor | Etapy 5/8; konkrétní řádky při převodu každé feature |

Blokace, dočasná rezervace a zakoupená vstupenka jsou tři odlišné životní cykly.
Jediný neupřesněný nástroj „uvolnit místo“ je nepřípustný. Nastavení dědičnosti
musí rozlišovat „vlastní hodnota“, „obnovit dědičnost“ a skutečné vypnutí.
Všechny potvrzené další UI ovládací prvky se před implementací přidají do katalogu;
nepotvrzené provider refundy a souhrnné zbývající exporty nejsou deklarovány jako
podporované funkce jen proto, že existuje sousední doména.

## Cílová architektura a nepřekročitelné podmínky

Používat také [zásady návrhu a provozu MCP](../architecture/mcp-design-practices.md).
Oddělují protokol, veřejné zkušenosti a rozhodnutí Festapp a stanovují scénářovou
bránu dokončení. Transport je převeden na stabilní protokol 2026-07-28
s oficiální legacy hranicí pro existující klienty; placené modelové evaluace
nejsou podmínkou těchto etap. Při každé etapě ověřit konkrétní uživatelskou úlohu vedle SQL
a transportních testů, se skutečnými chybami a přiměřeným objemem výsledků.

1. Vlastníkem pravidel je existující doménový SQL/modul. UI i MCP jsou adaptéry.
   Nový wrapper patří k doméně, nikoliv do samostatné implementace MCP.
2. Každý příkaz sváže skutečně uložený objekt s tenantem a vybranou unit/occasion
   v téže transakci jako změnu a replay. Samotné ověření ID v Node nestačí.
3. Rozsah souhlasu zužuje běžná práva, nerozšiřuje je. Odebrání role, přesun
   akce nebo revokace musí být účinné i pro opakovaný příkaz.
4. Zápis obsahuje neměnný command ID, očekávanou původní verzi nebo explicitní
   precondition neexistence, kanonický payload a potvrzený výsledek. Konflikt
   se neřeší tichým načtením nové verze a přepsáním cizích změn.
5. Timeout znamená opakování stejného příkazu, nikoli novou identitu. Složený
   příkaz má jednu vlastněnou receipt/transakční hranici; nevytváří dvojí
   publikaci, audit, alokaci ani e-mail.
6. Dodržet stávající pořadí zámků přes objednávky, produkty a kapacity. Nové
   scope/precondition zámky nesmějí zavést opačné pořadí. Ověřit relevantní
   souběh dvěma spojeními, nikoli jen postupným voláním.
7. Příkaz vrací normalizovaný uložený stav, verze a již existující sync
   replacements, aby UI nemuselo po každém zápisu skládat další čtecí requesty.
   Samostatná autentizace se nepočítá jako druhý doménový zápis.
8. Kritické operace mají správné MCP annotations a vyžadují schválení konkrétního
   účinku. Běžné čtení či již schválený přesný krok nevytváří další potvrzovací
   dialogy. HTML, názvy produktů a zákaznické texty nejsou instrukce pro agenta.
9. Registr nástrojů, schémata, souhlas a správa připojení používají jeden registr
   schopností. Pravidla závislostí scope se nezavádějí znovu v jednotlivých UI.
10. Žádné persistentní aplikační triggery, service-role zkratky pro MCP ani nový
    univerzální model propojení účtů. Google identity a delegace zůstávají oddělené.

Názvy nových veřejných doménových operací budou bez zbytečného V2/V3. Existující
verzovaný veřejný kontrakt se nepřejmenovává bez migračního důvodu. Vydané klienty
nelze odpojit tichým odstraněním RPC. Zachovaný kompatibilní vstup má pouze
adaptaci na jednoho vlastníka a doloženou podmínku odstranění.

## Význam administračního pohledu

Před každým řezem vycházet z konkrétní administrační tabulky nebo formuláře:
co správce potřebuje zjistit či rozhodnout, které sloupce a vazby k tomu používá
 a jakou entitu skutečně počítají agregáty. MCP nesmí být pouhá kopie řádků tabulky
ani nutit agenta dopočítávat obchodní význam ze surových dat. Kanonický čtecí model
zahrnuje relevantní počty, stav, názvy souvisejících objektů a verze pro další krok.
Optimalizuje se výběr a nepotřebný přenos, nikoli odstranění důležitých souvislostí.

Produktový pohled má [konkrétní sémantický kontrakt](../architecture/product-admin-read-contract.md).
Například UI zaplaceno zahrnuje paid i sent; počet objednaných položek není počet
lidí ani počet unikátních objednávek. Každý další řez zaznamená obdobnou stručnou
mapu otázka/sloupec -> společný owner/vazba -> DTO. Neodvozovat neověřenou
prodejní dostupnost nebo revenue z pouhé přítomnosti odkazu či počtu vazeb.

## Datová, SQL a síťová kvalita každého řezu

Tato kontrola je součástí implementace všech oblastí, včetně již napojených
operací. Nový MCP nástroj se nesmí spokojit s obalením nevyhovující cesty UI.
Oprava patří ke společnému doménovému owneru; míra změny musí odpovídat
konkrétnímu problému a evidenci, ne plošnému přepisu databáze.

### První doložené nálezy

| Nález a evidence | Závěr / požadovaný krok |
| --- | --- |
| `invokeProductOperation` načte `get_product_catalog`, teprve v Node provede sort/filter/slice. Kurzor a limit nejsou v SQL parametrech. | Přenos pro jednu stránku roste s celým katalogem. Opravit jako etapu 0 před dalšími nástroji. |
| Lokální disposable fixture přes skutečný executor: 100 produktů -> DB vrací 100; 1000 produktů -> DB vrací 1000; MCP v obou případech vrací 50. Totéž pro druhou stránku. | Potvrzené zbytečné načítání, ne jen odhad ze zdrojů. [Baseline](../reports/admin-data-network-baseline-2026-10-23.json), reproduktor `automation/reports/audit_admin_data_path.mjs`. |
| Při 1000 syntetických produktech představoval kompletní DB výsledek 575165 B serializovaného nekomprimovaného JSON na každou stránku. | Jde o velikost DB výsledku v adaptéru, nikoliv změřený HTTP provoz. Gzip a lokální jednorázové časy v evidenci nejsou produkční benchmark. |
| `get_products_and_types_for_edit` má několik korelovaných poddotazů na každý produkt: plány, počty, form vazby a aggregate version. | Kandidát pro sdílenou projekci a předagregaci. Zatím není doložen problém indexů nebo konkrétní pomalý execution plan; rozhodnout měřením. |
| Produktové inventory links se při skládání každé stránky opakovaně filtrují pro každý produkt. | Při přesunu projekce do SQL odstranit opakované klientské procházení; pokud zůstane potřebné, vytvořit jeden index podle product ID. |
| Nový cenový cíl používá receipt, existující cíl raw RPC; některé změny revize se v SQL hlásí jako `serialization_failure`. | Jeden kontrakt pro obě cesty; odlišit věcný revision conflict od skutečné retriable chyby souběhu. |
| Cenový scheduler zpracovává změny podle času/ID a drží product/plan zámky v transakci; wave move zamyká produkty podle ID. | Konkrétní kandidát pro dvouspojový deadlock test. Rozdíl pořadí sám o sobě není důkaz již reprodukovaného deadlocku. |
| Standing příprava má tři postupné zápisy a klientskou paměť částečného výsledku. | Etapa 2 získá jednu skutečnou transakční a receipt hranici, ne pouze jeden HTTP endpoint nad třemi účinky. |

Při tomto průchodu byla spuštěna pouze lokální, e-mailově odstavená fixture
s explicitní kontrolou identity. DDL i syntetická data se vrátila rollbackem.
Nebyl proveden produkční query ani změna runtime kódu. Celá administrativa
zatím není po SQL/performance stránce kvalifikovaná; každý další řez musí
projít níže uvedenými podmínkami.

### Povinné rozhodnutí před úpravou konkrétní operace

1. **Význam a data:** určit agregát, identitu, skutečné FK vazby, původní verzi,
   měny/přesnost, `null` versus chybějící klíč, smazání versus obnovení dědičnosti.
   JSON nastavení nevystavit jako neomezený patch. Neslučovat odlišné životní cykly.
2. **Jeden owner pravidel:** najít výpočty a autorizaci v SQL, Dart, JS i jobech.
   Duplicitní obchodní pravidlo přesunout k existujícímu vlastníkovi. Rozdílný
   transportní DTO a čistá prezentace samy o sobě nejsou business duplicita.
   Nesjednocovat odlišné operace jen kvůli podobným názvům či stejné tabulce.
3. **Dotazy:** vymezit filtry, pořadí a limit před drahou agregací. Při podezření
   na problém pořídit `EXPLAIN (ANALYZE, BUFFERS)` relevantního vnitřního SELECT
   na disposable reprezentativních datech, nikoli jen opaque function-call plan.
   Kontrolovat loops, odhady versus skutečné řádky, sort/spill a použité indexy.
   Index přidat až pro doložený access pattern; zahrnout cenu jeho zápisů.
4. **Transakce a souběh:** určit pořadí zámků napříč UI, MCP, checkoutem, cronem
   a queue workerem. Ověřit dvě spojení pro rizikové kolize a retry stejným UUID.
   Věcný konflikt verze vyžaduje nové načtení a rozhodnutí; deadlock/serialization
   může mít omezený retry se stejným záměrem. Žádné nekonečné opakování.
5. **Síť a objem:** zaznamenat doménové requesty odděleně od Auth/scope lookupů,
   předané entity a serializované bajty. Pro seznamy stránkovat na serveru;
   nepřenášet celý editorový bundle kvůli krátké MCP stránce nebo jediné hodnotě.
   Neprovádět write -> několik reloadů, pokud command již vrací potřebný snapshot.
6. **Vedlejší účinky:** receipt, audit, sync, e-mail a externí intent přesně jednou
   na doménovou operaci. Batch má jasné all-or-nothing nebo explicitní item outcomes;
   změna transportu nesmí toto chování nepozorovaně změnit.
7. **Zjednodušení:** odstranit opakovaná mapování, dvojí skládání stejného agregátu,
   nadbytečné round trips a nahrazené interní funkce. Nový helper musí ukrývat
   skutečné pravidlo nebo opakovanou složitost; nepřidávat vrstvy pouze přeposílající
   tentýž JSON. Nepřidávat cache bez jasné invalidace scope, verze a práv.

Důkaz úspory porovnává stejný scénář před/po: počty requestů, entit a bajtů,
případně reprezentativní SQL plán a rozdělení časů při více bězích. Snížení počtu
HTTP volání nesmí skrýt větší payload nebo neúměrnou práci SQL. Nepřidávat
libovolný produkční latency limit bez znalosti dat a prostředí.

## Pořadí a závislosti

| Etapa | Oblast | Proč v tomto pořadí | Předchůdce |
| --- | --- | --- | --- |
| 0 | Serverové stránkování katalogu a datový kontrakt čtení | Již doložené zbytečné načítání celého katalogu | Nasazené produkty |
| 1 | Plánované ceny, viditelnost a cenové vlny | Dokončení produktového katalogu, existující příkaz k opětovnému využití | Nasazené produkty |
| 2 | Sklady, zdroje, příprava kapacity a provozní správa míst (2B) | Odstranění tří zápisů; konkrétní blokace/rezervace bez čekání na celý editor | Nasazené produkty; 2B podle vlastního kontraktu |
| 3 | E-mailové šablony, bannery, dědičnost a náhled | Výslovně požadovaná administrace, vlastní oprávnění a renderer | Samostatná po produktech |
| 4 | Formuláře a jejich prodejní nastavení | Agregáty již existují; navazuje na ceny a kapacity | 1, 2 pro související scénáře |
| 5 | Nastavení akce a pořadatele | Sdílené agregáty a jasná hranice unit/occasion | Před rolovým a lifecycle rozšířením |
| 6 | Účastníci, role, skupiny a dobrovolníci | Změny přístupu vyžadují přesnou invalidaci a kontrolu delegace | 5 a existující auth kontrakt |
| 7 | Pokročilá editace plánků a vzhled vstupenek | Geometrie, drafty, obchodní celky a renderer mají vlastní řezy | 2, 4; PDF readiness pouze pro zápis vzhledu vstupenky |
| 8 | Program, místa konání, řečníci, služby a hra | Postupně využít stávající doménové příkazy | Příslušné feature/capability |
| 9 | Reporty, historie a exporty | Doplnění přehledů o nově zpřístupněné oblasti | Datové kontrakty příslušných etap |
| 10 | Banky, platební provider, lifecycle a zbývající unit agenda | Nejcitlivější a externí účinky, samostatné scénáře | Příslušné předchozí etapy |

Jde o výchozí pořadí. Čtení reportů lze dodat dříve jako malý samostatný řez,
pokud nezavádí novou architekturu. Nezávislost etap není pokynem k automatickému
spuštění více vývojových agentů. Každá etapa se řeže na malé hotové průchody
UI + doména + MCP, nikoliv zvlášť na „nejprve všechna SQL“ a „pak všechny nástroje“.

## Prováděcí etapy

### 0. Opravit stránkování a zbytečný přenos katalogu

**Cíl:** limitovaná MCP stránka se vybírá na SQL straně před skládáním souvisejících
položek. Počet přenesených produktů roste s limitem stránky, nikoliv s celou akcí.

**Změny:** rozšířit společný produktový read owner o explicitní keyset režim
`after` + bounded `limit` a stabilní pořadí ID. Vyžádat `limit + 1` pouze pro
určení existence další stránky. Současné UI může potřebovat celý edit bundle;
zachovat tento záměr jako explicitní režim, ne jako podklad každé MCP stránky.
Sdílené řádkové projekce a výpočty používají oba read režimy, nevytvářet druhý
nezávislý SELECT engine v Node či další kopii produktové autorizace.

Související typy/kontexty buď vracet v doloženě malém bounded rozsahu, nebo
oddělit jejich načtení podle skutečné potřeby; neskrýt neomezený přenos jiných
kolekcí za stránkováním produktů. Existující externí klientský kontrakt zachovat
přes explicitní compat hranici. Stanovit chování stránky při souběžném insert/delete;
keyset sám nezaručuje snapshot celé procházené kolekce.

**SQL a odstranění:** zmapovat nested agregace v
`get_products_and_types_for_edit`; společná data předagregovat pouze pokud
execution plan ukáže přínos. Při join refaktoru nevynásobit counts součinem
objednávkových, form a inventory vazeb. Z `operations/products.mjs` odstranit
původní full-catalog sort/filter/slice a opakovaný filter links pro každou položku.

**Ověření:** rozšířit `products-postgres.test.mjs` o více než jednu stránku,
stovky až tisíc produktů, chybějící metadata, relevantní související vazby,
autorizační scope a souběžný insert/delete. Obě čtecí cesty mají stejná data
pro tutéž položku. Zopakovat lokální baseline reproduktor po přizpůsobení novým
RPC parametrům; nezachovat v něm starou podmínku, že DB musí vracet celý katalog.
Před/po evidenci uložit odděleně, původní baseline nepřepsat novým výsledkem.

**Hotovo:** z databáze se pro MCP stránku nevrací 1000 produktů při limitu 50;
po sobě jdoucí stránky nevytvářejí mezery/duplicity v nezměněné fixture,
scope nelze obejít a UI má zachovaná data i save kontrakt. Zdokumentovat skutečné
objemy a případné ponechané důvody pro nezmenšené části editorového bundle.

### 1. Dokončit plánované ceny a viditelnost

**Změny:** v `db_eshop.dart` převést nový i existující cíl vlny na existující
`save_product_wave_target_client_sync_v1`; podle skutečných potřeb rozšířit
jeho společného vlastníka. Move/cancel a samostatnou plánovanou změnu převést
na stejný retry/version standard při zachování vlastníků v
`database/functions/eshop/product_price_waves.sql` a `product_price_changes.sql`.
`product_price_waves_dialog.dart` a případné injektované actions musí volat týž
kontrakt. Založení vlny a prvního cíle v rámci jednoho potvrzení provést atomicky;
existující příkaz už tento scénář částečně pokrývá. Nezavádět hromadné uložení
celé vlny, pokud UI potvrzuje jednotlivé cíle samostatně.

**Odstranění:** přímá současná klientská mutační RPC vedoucí mimo receipted
příkaz pro stejnou akci; žádný paralelní „MCP price engine“.

**Ověření:** existující `product_price_scheduling_cases.dart`, relevantní SQL
scénáře `database/tests/eshop/product_price_waves_test.sql` a nový reálný test
MCP executor -> sdílený příkaz. Pokrýt změněnou revizi, přesun/zrušení,
replay po timeoutu, cizí scope a souběh při aplikaci plánované změny.

**Hotovo:** každý zahrnutý cenový krok má shodné potvrzení a účinek z UI/MCP,
nepřepisuje historii nákupů, nezaloží při opakování druhou vlnu/cíl.

### 2. Atomická příprava skladu a správa zdrojů

**První řez:** připravit standing kapacitu jedním příkazem zahrnujícím pool,
kontext, resource a vazbu existujícího produktu. Využít interní vlastníky pod
`save_inventory_pool_client_sync_v1`, `save_resource_client_sync_v1` a produktovou
vazbou. Pokud jsou pravidla dosud uvnitř veřejného receipted příkazu, nejprve
je přesunout do jednoho privátního doménového vlastníka používaného oběma vstupy.
Neskládat tři vnořené nezávislé receipt/commit workflow. Vracet celý potřebný
snapshot a verze, včetně occasion u produktu, které UI potřebuje pro další editaci.

**Další řezy:** read/save/delete poolů, kontextů a zdrojů přes existující
`InventoryCommands`, vždy se zachováním alokací již prodaných vstupenek.

**Odstranění:** klientská orchestrace `_pool/_resource/_linked` jako mechanismus
nové přípravy v `BlueprintStandingInventory.prepare`; obnovu po výpadku vlastní
trvalá receipt. Aktualizovat setup dialog a všechny další volající. Existující
historicky částečně vytvořené objekty se automaticky nemažou: případná náprava
konkrétních dat vyžaduje samostatný doložený zásah.

**Ověření:** fixture selže mezi jednotlivými interními kroky a nezanechá nic;
stejný příkaz po ztracené odpovědi vrátí stejné IDs; konflikt verze a paralelní
příprava nesmí vytvořit dvojí sklad. Použít `standing_existing_product_inventory_test.sql`
a příslušné inventory command tests; přidat chybějící dvouspojový scénář.

**Hotovo:** jedna příprava = jedna doménová requesta, buď úplný výsledek, nebo
žádný zápis; běžná editace zdroje neobchází pravidla kapacity a alokace.

### Provozní řez 2B: konkrétní akce nad místy

Zařadit po zajištění příslušných scope/retry kontraktů; nemusí čekat na celou
geometrickou editaci etapy 7 ani na PDF ticket-layout readiness. Jeho první
samostatně dokončitelný řez je inspekce + blokace/odblokace vybraných míst.

**Změny:** explicitně rozlišit (a) block/unblock, (b) release temporary holds,
(c) swap ticket spots, (d) vytvoření objednávky z míst, (e) zrušení vstupenek.
Použít výše doložené vlastníky a přidat atomické tenant/unit/occasion narrowing.
Blokaci provést přes kanonického blueprint save vlastníka; žádný přímý UPDATE
`blueprint_seat_bindings` z MCP. Potřebuje-li MCP úzký příkaz nad seznamem míst,
sestavení a aplikace změny patří do stejné doménové vrstvy a používá stávající
aggregate owner, ne kopii jeho pravidel v Node.

Zachovat UI draft/Save/Cancel: kliknutí na blokaci nesmí nově automaticky uložit
jiné rozpracované geometrické změny. MCP potvrdí přesný výběr a původní revizi;
jedna potvrzená dávka je jeden atomický zápis. Výběrové jednotky mohou záměr
rozšířit: preview a výsledek musí ukázat skutečně dotčený celý celek před potvrzením.

**Odstranění:** žádné přímé MCP přepisování block flagů, vynulování reservation
secret nebo mazání order vazeb; duplicitní obchodní pravidla výběru přesunout
k existujícímu owneru, pokud ještě nejsou serverově vynucena.

**Ověření:** volné, blokované, prodané a aktivně držené místo; celý společný
výběr; cizí plánek; konflikt revize; souběh s checkoutem; replay po ztrátě odpovědi.
Odmítnutí jednoho chráněného místa nesmí tiše aplikovat jiný výběr. Pokud UI dnes
filtruje výběr, pro MCP zobrazit toto zúžení před potvrzením, nikdy až po zápisu.

**Hotovo:** operace mají oddělené typované kontrakty a stejné účinky z UI/MCP;
blokace nemění cizí objednávku ani rezervaci a release hold nezasáhne prodané místo.

### 3. E-mailové šablony a jejich dědičnost

**Řezy:** (a) čtení effective šablony s označením zdroje unit/occasion,
(b) uložení override s původní verzí, (c) odstranění override a návrat k dědičnosti,
(d) banner, (e) náhled. Veřejné názvy nástrojů stanovit až podle těchto operací.

**Změny:** společný typed command adapter pro `DbEmailTemplates` a MCP nad
vlastníky `others/update_email_template.sql`, `delete_entity_email_template.sql`
a `update_entity_email_banner.sql`. Doplnit receipt a konfliktový kontrakt tam,
kde chybí, včetně vytvoření dosud neexistujícího override. Vracejte efektivní
výsledek a jeho zdroj, nikoliv odhad klienta. Unit grant nepovoluje tenant-wide
šablonu; occasion grant nepovoluje úpravu unit šablony. Použít existující
`can_write_occasion_email_templates` / `can_write_unit_email_templates`.

Před náhledem dohledat konkrétní vstup serverového rendereru a jeho volající.
MCP náhled použije existující renderovací cestu bez odeslání a bez skutečných
recipientů. Rozdíly vůči Dart náhledu uzavřít sdílenými scénáři pro placeholdery,
wrapper, měny a dědičnost; nepřepisovat oba renderery jen pro přidání MCP.
Změna šablony není pokynem k e-mailové rozesílce.

**Odstranění:** přímé mutační volání z aktuálního editoru mimo nový společný
command adapter; duplicitní řešení effective šablony v MCP.

**Ověření:** `database/tests/get_email_templates_tenant_scope_test.sql`,
`database/tests/emails/get_all_email_templates_test.sql`, Flutter
`email_template_save_cases.dart` a `email_preview_context_cases.dart`; přidat
SQL/executor test pro replay, souběžné vytvoření a obnovení dědičnosti. Náhled
nesmí vytvořit delivery intent ani načíst skutečnou objednávku.

**Hotovo:** UI i MCP uloží/obnoví tutéž šablonu, zachovají dědičnost i přesné
scope a použijí shodnou interpretaci placeholders; fronta e-mailů je nedotčená.

### 4. Formuláře, pole a prodejní nastavení

**Řezy a změny:** read/create/save/duplicate/delete formuláře přes
`SupabaseFormCommands` a vlastníky v `database/functions/eshop_forms/`. Potom
v samostatných řezech nastavení prodeje, kapacity a čekací listiny včetně
podporovaných nabídek/uvolňování míst přes `waitlist_commands.dart`. Doplnit
také dosud nepokryté administrátorské vytvoření objednávky, pokud je v příslušném
UI dostupné: použít existující objednávkový/form owner, nikoliv simulaci nákupu
nezávislým zápisem ticketů a plateb. Dohledat
volající `FormCommands` a příslušné UI save handlery; existující aggregate save
má být společným vlastníkem polí, produktových vazeb a nastavení, které uživatel
potvrzuje jedním Save. Případný další zápis připojit v této transakci.

**Odstranění:** MCP skládání formuláře přímým DML nebo řadou samostatných
field RPC. Veřejné odkazy a klíče nepatří do obecného read DTO; přístup k nim
musí být konkrétní záměr s vlastní autorizací.

**Ověření:** `form_commands_cases.dart`, příslušné SQL testy create/save/duplicate;
fixture cizí produkt/context, konflikt při editaci polí, replay kopie a rollback
chybného child záznamu. Souběh prodeje s kapacitní změnou přes skutečný owner.

**Hotovo:** jedno potvrzení formuláře zapisuje kompletní validní agregát,
public checkout a uložené objednávky zůstávají kompatibilní.

### 5. Nastavení akce a unit

**Změny:** read/edit základních údajů, časů, feature nastavení, publikace a prodeje
připojit přes `OccasionCommands.save` a `SupabaseUnitCommands.save`. Nejdřív
vypsat konkrétní pole, která mohou tyto vlastníky měnit; neposkytnout agentovi
neomezený JSON patch. Cizí vazby a změnu vlastníka svázat se skutečnými řádky.
Draft/setup finalizaci dohledat zvlášť, neslučovat ji s nezávislou pozdější editací.

**Odstranění:** paralelní MCP ukládání `occasions.data` / `units.data`, obcházení
aggregate versions a capability invalidace.

**Ověření:** `occasion_commands_cases.dart`, `unit_commands_cases.dart`,
existující authorization fixtures; původní verze, změna scope během příkazu,
vrácený snapshot a zákaz zápisu unit pouze přes occasion grant.

**Hotovo:** nastavení dostupná v běžném UI mají stejný kanonický save pro MCP;
změna feature neobchází její doménové předpoklady.

### 6. Lidé, role, skupiny a dobrovolníci

**Řezy:** nejprve scoped seznam/inspekce; potom běžné údaje a členství;
změny rolí až jako samostatný explicitní příkaz. Začít `unit_commands.dart`,
`components/groups/group_commands.dart`, `components/users/profile_commands.dart`
a příslušnými unit/occasion user UI save handlery. Pro každý řez doplnit přesnou
matici typed predicate -> SQL owner -> UI -> nástroj, až potom kódovat.

**Odstranění:** kopie kombinací rolí v Node, klientské skládání více členství
pro jednu potvrzenou změnu; žádná nová ACL tabulka nahrazující běžná práva.

**Ověření:** skutečné běžné identity v authorization fixture, odebrání vlastní
role i role jiného člověka, zákaz eskalace a cizího profilu, účinná revokace
před replay i návratem rozpracovaného čtení. Použít existující group/profile
command tests, přidat executor test pro konkrétní nový příkaz.

**Hotovo:** žádný MCP grant neposkytne víc než živá běžná práva; role a členství
se projeví současně v UI, kontextu a dalších MCP voláních.

### 7. Pokročilá editace plánků a vzhled vstupenek

**Podmínka pouze pro zápis PDF vzhledu vstupenky:** vyřešit známý starší nesoulad
`generate_ticket_layout_write_contract.py --check`. Neměnit readiness hash jen
pro zelený test a nezapínat layout writes před skutečnou shodou živého kontraktu. Tento probe není společnou bránou pro
blokaci míst, release holds ani celou blueprint geometrii. Každá z těchto domén
má vlastní verzi, autorizaci a kvalifikaci.

**Řezy:** čtení plánu; jeden potvrzený save draftu; vazby produktu/kapacity;
vydání a změny vstupenek, přesuny a uvolnění spotů; kontrola/check-in tam,
kde ji běžný klient skutečně poskytuje; náhled a uložení vzhledu. Využít
`SupabaseFormCommands.saveBlueprint`, existující blueprint/spot doménu a
kanonický PDF renderer. Před změnou přečíst platné Blueprint integrity plány,
neznovuzavádět jejich staré implementace ani historické příkazy.

**Odstranění:** MCP reimplementace geometrie, počítadel kapacity či PDF;
automatické ukládání draftu při pouhém přejmenování či náhledu.

**Ověření:** konkrétní blueprint a spot command tests, reálný SQL souběh
rezervace se změnou plánu, nejednoznačný write/replay, draft Cancel a kontrola
renderer contractu. Browser pouze pokud se mění skutečný editorový tok.

**Hotovo:** uloží se přesně schválený draft, layout a rezervace zůstávají
konzistentní; náhled neukládá ani neodesílá vstupenky.

### 8. Program a doplňkové oblasti akce

Postupně samostatné řezy: program/aktivity, místa, řečníci, služby, hra.
Začít `components/activities/activity_commands.dart`, `schedule/db_events.dart`,
`map/db_places.dart`, `speakers/speaker_commands.dart` a `occasion/db_occasions.dart`.
Pro každou podoblast dohledat konkrétní read/save/delete a jeho typed predicate;
výsledkem je krátký operation ledger, ne nový průzkum celé aplikace.

**Změny a odstranění:** napojit existující doménové příkazy, převést skutečný
vícezápisový UI Save na jeden owner; odstranit nahrazené přímé klientské zápisy.
Zachovat draft/publication a feature pravidla. Nezpřístupnit nepodporovanou
feature jen proto, že nástroj existuje v jiné variantě aplikace.

**Ověření a exit:** cílené domain/adapter testy v dané komponentě plus executor
pro přesný scoped příkaz, konflikt a replay. Každá podoblast je hotová teprve
po převodu svých aktuálních UI volajících a registraci správného MCP scope.

### 9. Reporty, historie a exporty

**Změny:** používat existující SQL reporty/audit projections; zachovat odlišnost
objednávek, unikátních vstupenek a lidí. Přidávat bounded čtení, filtrování a
stránkování. U každého exportu předem určit zdroj, osobní údaje a oprávnění;
nezavádět druhé účetní či kapacitní součty v Node.

**Odstranění:** alternativní MCP výpočty téhož reportu a neomezené dumpy tabulek.

**Ověření a exit:** stejná fixture vrátí pro UI i MCP stejné hodnoty a měny;
pagination nevynechává záznamy, DTO nevynáší QR/klíče ani cizí zákaznické údaje.

### 10. Finance, lifecycle a zbylá agenda pořadatele

**Řezy:** bankovní účty a vazby; card-provider stav a podporované operace;
kopírování/finalizace/mazání akce; quotes a zbývající unit taby podle skutečné
feature dostupnosti. Začít `components/bank_accounts/db_bank_accounts.dart`,
`unit/db_units.dart`, `occasion/db_occasions.dart` a existující bankovní maticí
`canonical-authorization-BANK-2026-10-21.md`. Každý řez nejprve doplní konkrétní
owner, účinek a recovery kontrakt; jejich současná podoba zde není plně auditována.

**Podmínky:** banka zachová account-admin AND manager skutečně propojené unit.
MCP nesmí vyrobit provider stav, refund ani obejít onboarding. Kopie/mazání akce
má SQL i kanonické asset Worker účinky: jeden orchestration intent s obnovou,
ne nepravdivý slib jedné distribuované SQL transakce.

**Odstranění:** přímé externí mutace z nového MCP adaptéru mimo existující owner,
service-role náhrady běžné autorizace a nová asset/storage autorita.

**Ověření a exit:** bankovní auth matrix, opakování nejednoznačné odpovědi bez
dvojího externího účinku, provider fixture a asset failure recovery. Všechny
podporované účinky mají přesný readback. Destruktivní/finanční scénář není
hotový jen po úspěšné odpovědi HTTP.

## Ledger odstranění a zachovaných hranic

| Cesta | Akce | Důkaz dokončení |
| --- | --- | --- |
| Dvě současné cesty uložení cíle cenové vlny | Převést současné UI a MCP na jeden receipted owner | Call graph, relevantní testy a scoped `rg` nad aktuálními volajícími |
| Klientská orchestrace standing pool/resource/link | Nahradit jediným trvalým příkazem, odstranit novou závislost na in-memory partial state | Failure injection a dvouspojový replay test; žádný volající původní orchestrace |
| Přímé template mutace ze současného editoru | Převést na sdílený typed command adapter | UI/executor testy používají týž owner a verze |
| Nové paralelní výpočty/ACL v MCP | Nevytvářet; nalezené duplikace odstranit v příslušné etapě | Doménový výsledek stejný pro obě cesty |
| Registr nástrojů, capability labely a scope závislosti | Rozšiřovat existující sdílený registr, ne kopírovat mapy | OAuth/consent tests a skutečné SDK listTools |
| Veřejné RPC pro vydané klienty a SQL/serverové volající | Zachovat pouze nutnou hranici na jednoho vlastníka; zaznamenat konkrétní spotřebitele | Odstranit až po doloženém client upgrade gate a převodu posledního serverového volajícího |
| Historické migrace | Ponechat beze změny | Nové unikátní forward migrace a source parity |
| Nahrazené testy, dokumentace, exporty a feature flags | Upravit/smazat současně s odpovídající etapou | Žádný live odkaz na nahrazenou interní cestu; historické záznamy jasně označené |

Každý řez před editací doplní ledger přesnými objevenými symboly a spotřebiteli.
Zachovaná kompatibilní hranice se nesmí vykazovat jako úplné odstranění.

## Rychlé a kvalitní provádění

- Pracovat po jednom uceleném řezu. Před editací jednou zapsat jeho owner,
  kontrakt, volající a nejmenší smysluplný testovací batch. Nezakládat obecný
  framework ani samostatný typ pro každý transportní detail.
- Používat `rg` a úzká čtení; při pokračování číst checkpoint a změněné vstupy.
  Nenavazovat další kolo architektonického průzkumu na každé běžné rozhodnutí.
- Před novou schopností provést také datový/síťový průchod definovaný výše.
  Nejdřív doplnit schopnost owneru, pak převést všechny aktuální UI volající
  a MCP, nakonec odstranit nahrazenou cestu. Testovat hotovou koherentní změnu,
  ne po každém řádku; významnou chybu odhalit jedním konkrétním reproduktorem.
- Adapter tests mohou simulovat transport; transakce, oprávnění, replay a souběh
  potřebují skutečnou disposable PostgreSQL. Nevyrábět rozsáhlý nový harness,
  když postačí rozšířit `tools/festapp/test/products-postgres.test.mjs` vzor.
- Výsledky vázat na přesné vstupy/revizi. Zelené testy neopakovat při pouhém
  nasazování; po změně vstupu zopakovat jen zasažené ověření. Nezávislé lehké
  kontroly lze spustit v jednom batchi, nejvýše jeden Flutter task v celém stroji.
- UI/browser kontroly přidat pro skutečně změněné interakce, headless v izolaci.
  Neověřovat každou MCP operaci opakovaným proklikáváním stejného UI.
- Vývojové subagenty nepřidávat bez příslušné autorizace. Rutinní schválený
  deployment delegovat podle AGENTS levnějšímu agentovi s přesným frozen SHA,
  tenantem, příkazy, gate a readbackem. Agent nesmí měnit připravené zdroje.
- Vydávat koherentní kompatibilní balík hotových řezů; nedělat úplný Flutter
  produkční build kvůli každému RPC. Finální release build a tenant drift gate
  zůstávají povinné. Nenahrazovat je lacinným smoke testem.

## Ověřovací kontrakt a release

Příklady cílených příkazů; používat skutečně změněné a existující test files:

```sh
fvm flutter test --concurrency=1 test/components/eshop/product_price_scheduling_cases.dart
pnpm --dir tools/festapp exec node --test --test-concurrency=1 test/remote.test.mjs
pnpm --dir web_client exec node --test tests/components/mcp_connection_page.test.js tests/components/account_connections_page.test.js
python3 automation/generate_canonical_source_contract.py --check
```

Nové SQL/executor testy musí mít skutečně nastavenou podporovanou disposable DB,
žádný tichý skip vykazovaný jako test. Použít `openDisposableDatabase` a jeho
kontrolu identity projektu i vypnutého mail workeru; nepoužívat produkční fixtures.
Pro nové canonical SQL aktualizovat odpovídající source manifest/parity fixture
pomocí existujícího generátoru a nové migrace. Neopravovat unrelated readiness
kontrakt pouhým přegenerováním očekávaného hashe.

Před zveřejněním načíst aktuální main, začlenit jeho nové změny a ověřit pouze
dotčené vstupy. Nesmí se měnit cizí dirty checkout ani přesouvat sdílený lokální
main ref. Aktuální pracovní checkout pro tento plán je
`/private/tmp/festapp-mcp-recovery-20261022`; nejde o nový zdroj pravdy mimo main.

Produkční změny jsou samostatný, výslovně autorizovaný krok. Dokument oprávnění
neuděluje; při vykonávání se respektuje již udělené oprávnění a nežádá se znovu
jen kvůli změně etapy. Vybraný tenant je `festapptickets`; jiné varianty nejsou
součástí rollout scope. Backend se řeší přes schválený canonical workflow,
web lokálně a `automation/deploy_direct.sh`, nikoliv GitHub-hosted build bez
výslovného zadání.

Pořadí kompatibilního releasu:

1. Doplnit serverový doménový kontrakt a forward migraci; ověřit definice a ACL.
2. Připravit klienty a registr souhlasu, aby rozuměly novým schopnostem. UI/MCP
   aktivaci zkoordinovat: starý consent klient nesmí obdržet nové neznámé scopes.
   Je-li potřeba staging, použít existující deklaraci podporovaných nástrojů,
   nikoliv dlouhodobý paralelní business engine nebo další obecný feature systém.
3. Zveřejnit ověřené klienty/issuer v kompatibilním pořadí; nové nástroje vyžadují
   odpovídající výslovný souhlas, staré granty zůstávají stejně omezené.
4. Ověřit konkrétní source SHA, SQL ledger/definice, zdraví issueru, tenant drift,
   sestavené shared chunks a tři souhlasné live version/build/legal probes.
5. Teprve po doloženém upgrade gate kontrahovat podporované veřejné hranice.

Rollback může vrátit známý kompatibilní klient/image a ponechat bezpečné additive
SQL. Nesmaže platná data, receipt ani provider intent, neobnoví odstraněný druhý
business engine a nezahájí znovu nejasný externí účinek.

## Stav, předpoklady a podmínka dokončení

**Rozhodnutí:** výše uvedené pořadí, doménoví vlastníci, společné příkazy,
jedna transakce na jeden DB záměr a omezené kompatibilní hranice jsou závazné.

**Předpoklady k vyřešení na začátku příslušného řezu:**

- Aktuální main může být novější než uvedený základ. Executor zkontroluje delta
  pouze v souvisejících vlastnících a upraví neplatný fakt přímo v tomto plánu.
- Další UI může mít vlastní save handler. Executor etapy dohledá volající známého
  příkazu a registrace/callbacky; exit je úplný seznam pro tuto konkrétní operaci.
- Nové scopes nejsou předem definitivně pojmenované. Executor je odvodí od
  konkrétních doménových schopností, zachová existující souhlasy a nevytvoří
  každému nízkoúrovňovému RPC vlastní checkbox.
- Kompletní audit provider/quotes/lifecycle patří do etapy 10. Do jeho dokončení
  nevystavovat jejich nové mutační nástroje.

**Známá brána:** starší ticket-layout readiness nesoulad omezuje zpřístupnění
zápisu PDF vzhledu vstupenky v etapě 7. Neblokuje blokaci míst, release holds,
plánované ceny ani e-mailové šablony. Jiné runtime blokery tento plán netvrdí;
produkční dostupnost a oprávnění se znovu ověřují až při schváleném releasu.

Etapa je hotová pouze tehdy, když má:

- všechny aktuální UI/MCP vstupy na jednom kanonickém owneru;
- žádnou nahrazenou živou vnitřní cestu; zachované veřejné hranice mají spotřebitele
  a konkrétní podmínku odstranění;
- důkaz správných práv, scope, verze, retry a relevantní atomicity/souběhu;
- passing cílené testy na finálních vstupech, nikoliv jen kompilaci či mock receipt;
- uzavřený datový/síťový průchod s nálezy a rozhodnutími; u optimalizace
  srovnatelný před/po důkaz a ověřená shoda dat, nikoliv pouze menší počet RPC;
- stav `lokálně hotovo`, `publikováno` a `nasazeno` rozlišený skutečnou evidencí.

Po každém hotovém řezu aktualizovat níže checkpoint, mapu pokrytí a zdrojový
JSON statického katalogu; přegenerovat a ověřit HTML existujícím generátorem. Zapsat pouze
změněnou oblast, revizi, výsledek ověření, zbývající kroky a případný blokující fakt.
Celý plán je dokončen až po uzavření všech podporovaných oblastí skutečných
admin tabů, nikoliv po přidání jejich názvů do MCP katalogu.

### Checkpoint

- Etapa 0 lokálně hotová na autoritativním základu `4cfc9b7bc` v izolovaném
  `/private/tmp/festapp-admin-mcp-canonical-20261023`. Publikace a produkční migrace dosud neproběhly.
- Owner: `get_product_catalog_data_internal`; UI `get_product_catalog` (celý editor)
  a MCP `get_product_catalog_page` (ID keyset 1-100) sdílejí stejnou projekci.
  `get_products_and_types_for_edit(text)` zachován jako adaptér vydaných klientů.
  Exit gate: upgrade posledního podporovaného klienta a odstranění jeho volání.
- Odstraněno MCP full-catalog sort/filter/slice a opakované filtrování inventory links.
  Stránka přenáší jen relevantní typy a kontexty; prázdná stránka má prázdná metadata.
  Editor záměrně zachovává úplné pools/forms/waves. Page DTO podporuje nejvýše
  1000 inventory vazeb na produkt; větší historický záznam selže explicitně, bez truncation.
- Ověřeno: 3 skutečné PostgreSQL testy, 0 skipů: 1000 produktů, úplný průchod,
  UI/compat shoda, null/defaults, counts bez násobení form/inventory vazbami,
  scope a ACL, invalid limit/cursor, dvě spojení pro insert/delete a čekající scope move.
  Stránky jsou READ COMMITTED keysets, nikoli zmrazený snapshot celé kolekce.
- [Nová evidence](../reports/admin-data-network-keyset-2026-10-23.json): při 1000
  produktech DB vrací 50 místo 1000; 28884-28894 B místo 575165 B na stránku.
  Jeden doménový request, auth lookupy oddělené. Jde o skutečný serializovaný DB
  výsledek, nikoli HTTP wire měření. Původní baseline zachována beze změny.
  EXPLAIN ANALYZE vnitřního SELECT: korelované subplány 50 místo 1000 loops,
  lokální jednotlivé vzorky 3.087 ms proti 49.058 ms; žádný nový index ani plošná předagregace.
- Upřesnění uživatele: navazující etapa 0B doplnila sémantiku skutečné tabulky:
  SQL `purchased_count` zahrnuje paid/sent, UI jej používá přímo; MCP zná formuláře
  a skladové názvy/data. Counts se při UI editaci zachovají. 3 SQL testy bez skipů
  a 4 grid testy prošly. Nová evidence admin-view: 29895-29905 B při 1000 produktech,
  stále 50 produktů a jeden request. Starší evidence nebyla přepsána.
- Etapa 1 lokálně hotová: společný `manage_product_schedule`, zachovaný receipt
  owner cíle, bounded wave read ze stejné projekce jako matice, aktuální UI bez raw
  mutačních RPC. Scheduler má pořadí zámků podle ID produktů. Nové scopes jsou
  výslovné, staré granty se nerozšiřují. 87 MCP testů bez skipů, 10 cílených SQL
  testů, 18 + 13 cílených Flutter testů a 29 consent testů prošlo; přesné detaily
  a omezení disposable source parity jsou v execution checkpointu a stage 1 evidenci.
- Řez 2A lokálně hotový: jedna transakce/receipt, společné pool/resource/assignment
  vlastníky, odstraněná klientská saga i reload katalogu, uložené IDs/verze.
  7 reálných SQL testů bez skipů, 34 Flutter, 15 remote a 30 consent testů prošlo.
- Publikované 0/0B/1 čekají v PR #564 na vyžadovaný review/merge. Nasazení dosud
  neproběhlo; kanonický produkční target byl ověřen delegovaným read-only preflightem.
- Další krok: bounded skladové read modely podle skutečných UI karet a jejich RPC,
  pool/resource adaptéry, editorové volby produktů a provozní řez 2B.
- Přesné zdroje a výsledky průběžně v
  [execution checkpointu](admin-mcp-canonical-checkpoint-2026-10-23.md).
