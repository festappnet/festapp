# Kanonická oprávnění pro aplikaci a MCP

Datum: 2026-10-20  
Stav: Lokální implementace vln 0-4 dokončená; produkční aplikace neprovedená. Evidence je v implementačním výsledku.
Verification: standard

## Implementační evidence a oprava premis

Práce probíhá v izolovaném checkoutu `festapp-canonical-authorization-20261020`
z fetched authoritative main `ce77a1e40057841bff9abe9f28ba0a4f0c4510dd`.
Closure vlastník potvrdil, že jeho změny jsou na tomto main a checkout je čistý;
backend/MCP vlastník neměl pending překryv. Aktivní Blueprint release byl
upozorněn, že tato nepublikovaná authorization změna není připravená k zahrnutí.

Skutečný předchozí create průchod vyžadoval současně unit managera (receipt)
a unit editora (vlastní zápis a výchozí formulář), přestože vnější guard používal
OR. Uživatel tento souběh 2026-10-20 výslovně opravil: editor sám stačí; správce
pořadatele je další dostačující role. To je explicitně autorizovaná výjimka z D1,
nikoli neoznačené rozšíření pod názvem refaktor. `unit_users.is_manager` podle
existující správy rolí přiděluje unit role i sobě; `organization_users.is_admin`
je odlišný tenantový rozsah. Další role se touto změnou globálně nerozšiřují.

Uživatel 2026-10-21 výslovně upřesnil výjimku pro banku: správa účtu
vyžaduje současně správce pořadatele a správce bankovního účtu. Dosavadní
account-only SQL guard a přímý connection route tuto podmínku nezajišťovaly.
`can_manage_bank_account` proto vyžaduje živé bank admin členství a živého
managera alespoň jednoho skutečně připojeného pořadatele. Nové připojení
vyžaduje managera cílového pořadatele a admina účtu; nesmí předpokládat již
existující link. Toto explicitní zpřísnění parity je zdokumentované samostatně
v [bankovní matici](canonical-authorization-BANK-2026-10-21.md).

Nové zdroje a forward migrace, skutečné testy, uzavřený lokální inventář a
výkonové podmínky jsou v [implementačním výsledku](canonical-authorization-RESULT-2026-10-20.md).
Lokální dokončení vln 0-4 se nevydává za produkční aplikaci.

## Výsledek a rozsah

Jedna definice oprávnění ke konkrétní doménové operaci v SQL, používaná běžnými requesty, MCP, RLS a projekcí možností pro Flutter/JS. MCP navíc omezuje operaci uděleným souhlasem. Refaktor zachová současnou matici práv a výkon; sjednocení nesmí znamenat automatické rozšíření rolí.

Jde o úplný cutover rozhodovací logiky, nikoli přidání další permission vrstvy. Rozsah zahrnuje všechny aktivní doménové operace, jejich SQL/RLS vstupy, Edge/Worker adaptéry, MCP a klientské výpočty funkčních oprávnění. Vlny postupují po doménách; pilot sám není dokončením celého plánu. Nezahrnuje změnu rolí produktu, nový obecný ACL engine, migraci poskytovatele identity ani přestavbu transakčních command/receipt ownerů.

Navazuje na [Blueprint/MCP closure](blueprint-mcp-closure-plan-2026-10-20.md). Její lokální opravy ani dosažené testy se zde nevydávají za hotový authorization cutover. Closure má vlastní neuzavřené gates a pokračuje samostatně.

## Pevný bod a evidence

Průzkum: izolovaný checkout `/Users/miakh/source/festapp-blueprint-mcp-closure-20261020`, HEAD `48d8b6db0479818b556e3852c7ea50ead4035d11` plus jeho necommitnutá closure delta. Při implementaci porovnat s aktuálním authoritative main a změnami paralelních vlastníků. Produkční stav ani výkon produkce nebyl pro tento plán měřen.

| Potvrzený fakt | Konkrétní vlastník | Důsledek |
|---|---|---|
| Existují malé SQL predikáty nad živými členstvími a demo pravidly. | `database/functions/user_permissions/`: `get_is_editor_order_on_occasion`, `get_is_editor_order_view_on_occasion`, `get_is_manager_on_unit`, `get_is_admin_on_organization` | Členské tabulky a jejich indexy zachovat jako zdroj faktů. Role číst přes společné primitivy. |
| Operace již někdy má vlastní predikát. | `database/functions/others/ticket_layout.sql`: `can_edit_ticket_layout` | Reuse či sémanticky přesunout existující pravidlo; nepřidávat paralelní implementaci. |
| Operator discovery kombinuje více rolí do seznamu dostupných akcí. | `database/functions/others/get_operator_access_v1.sql` | Dostupnost v seznamu není oprávnění ke všem operacím s danou akcí. |
| MCP odděluje souhlas a živá práva; konkrétní kontrola závisí také na doménovém requestu. | `tools/festapp/src/remote/delegation.mjs`: `authorizeOperation`, `authorizeContext`, `listAccess`; `operations/catalog.mjs`; `operations/access.mjs` | Zachovat souhlas jako další omezení. Sdílet pravidla doménových operací, ne OAuth protokol. |
| Klienti sami skládají funkční možnosti z rolí. | `lib/data_services/rights_service.dart`: `canUpdateOrders`, `canSeeAdmin`, `canEditOccasion`; `web_client/src/services/rights_service.js`: `canSeeAdmin`, `canSeeReservations` | UI potřebuje projekci SQL pravidel místo druhé interpretace rolí. Rozdíly nemusí být všechny bug. |
| Editor bundly mají odlišné podmínky a formy odmítnutí. | `database/functions/map/get_map_editor_bundle_v1.sql`, `information/get_information_editor_bundle_v1.sql` | Zmapovat per-operation kontrakt; nesjednotit automaticky práva ani veřejné response obálky. |
| Demo ochrana používá také RLS. | `database/functions/demo_occasions/rls.sql`, `read_policy.sql` | SQL funkce samy nestačí k důkazu úplnosti. Zahrnout policies a přímé table grants. |
| Existuje reálný PostgreSQL test delegace a revokace. | `tools/festapp/test/organizer-postgres.test.mjs` | Rozšířit skutečný SQL test, nezůstat u mocků. Jeho dnešní guard míří na jiný lokální projekt/port. |
| Public form bootstrap spouštěl nepotřebný offline editor refresh. | Closure plán, implementační aktualizace; `FormPage` a `RightsService.updateAppData` | Konkrétní veřejná projekce a doménové capability musí řídit požadavky; přihlášený kupující není editor. |

## Cílový kontrakt

### Vlastnictví

Kanonické zdroje v `database/functions/user_permissions/` vlastní:

1. Malé primitivy členství/rolí nad existujícími tabulkami. Zahrnují dnešní tenantové a demo výjimky.
2. Pojmenované, typované doménové predikáty podle konkrétní operace a resource ID, například oddělené čtení objednávek, změna objednávek, čtení ticket layoutu a jeho editace. Přesná jména a existující funkce se uzavřou ve vlně 1. Read/check varianty sdílejí jednu podmínku; assert jen převede false na chybu.
3. SQL projekci capability pro konkrétní kontext a seznamy. Používá stejné predikáty; JSON není samostatný rozhodovací engine. Identifikátory capability jsou stabilní veřejný kontrakt a mají jedno místo deklarace, ze kterého lze generovat klientské identifikátory.

Actor se odvozuje z ověřené identity, u SQL obvykle `auth.uid()`. Veřejný caller si nemůže zvolit libovolné user ID. Trusted background/service operace mají explicitní, omezenou interní hranici; service_role samo o sobě nenahrazuje doménový záměr. Funkce zůstávají v `public`, SECURITY DEFINER má bezpečný search_path, explicitní tenant/resource vazby a úzké EXECUTE grants.

Doménová mutace kontroluje aktuální práva ve stejné databázové transakci jako zápis, včetně receipt replay. UI projekce, tokenové role ani předchozí HTTP preflight nejsou důkaz oprávnění. Zachovat stávající replay semantics, ale replay nesmí po revokaci vracet soukromý výsledek neoprávněnému callerovi.

MCP dovoluje operaci pouze při průniku ověřené identity, aktuální SQL capability pro resource, resource rozsahu souhlasu a OAuth scope. Jednotlivé akce a celý pořadatel zůstávají různé explicitní souhlasy. Budoucí akce pokrývá pouze souhlas pro pořadatele; create vyžaduje vlastní opt-in i živé právo. Nové právo automaticky nezvětšuje starý souhlas. Expiry/revoke kontrola zůstává u vlastníka delegace.

### Výkon a konzistence

- Nevytvářet obecný stringový dispatcher volaný pro každý řádek ani velký JSON kontext při každé SQL mutaci. Ponechat úzké SQL predikáty a indexované vazby.
- Pro seznamy použít setové dotazy, filtrovat tenant a scope před agregací. Nevkládat drahé SECURITY DEFINER volání do row policy bez změření jeho plánu a počtu volání.
- UI capability vracet spolu s existujícím context/bundle requestem, bez samostatného síťového preflight před každou akcí. MCP nemá přidávat nové permission roundtripy; dnešní počet je baseline, bezpečné odstranění duplicit je přípustné.
- Žádná trvalá cache rozhodnutí napříč requesty, permission snapshot v tokenu ani nová materializovaná ACL tabulka. UI může držet informativní projekci, po odmítnutí ji obnoví a při změně uživatele/tenantu zahodí.
- Revokace se projeví v dalším requestu podle živého databázového snapshotu. Neslibovat zrušení již commitnuté operace ani retroaktivní změnu běžícího snapshotu. U souběžných změn scope/rolí definovat a testovat pořadí; citlivé mutace případně sdílejí cílený zámek, nikoli globální authorization lock.
- Pokud se akce přesune mimo delegovaného pořadatele mezi kontrolou a mutací, request nesmí uniknout souhlasu. Resource binding ověřit na transakční hranici přes důvěryhodně předaný omezený kontext nebo existující atomický command. Konkrétní adaptér uzavřít ve vlně 1 podle současného transportu; klientem podvržený kontext nikdy neuděluje právo.

## Rozhodnutí, předpoklady, otevřené hranice

- **D1:** Zachovat matici existujících oprávnění. Rozdíl mezi UI, MCP a backendem zaznamenat jako konkrétní neshodu; bezpečnostní rozšíření nemaskovat jako refaktor. Sporné produktové rozšíření vyžaduje samostatné rozhodnutí, ostatní domény mohou pokračovat.
- **D2:** Sdílet doménové SQL pravidlo, ne všechny transportní a UI funkce. Členství v úklidové četě pro notifikace není stejná capability jako editorův dohled nad reporty. Feature flag a UI preference nejsou role.
- **D3:** Nevytvářet druhou policy implementaci v JS, Dart, Edge nebo konfiguraci. Generované konstanty pouze pojmenovávají SQL kontrakt.
- **A1:** Existující členství a indexy jsou vhodný základ. Vlnou 0 ověřit schema/plány; případný index dodat forward migrací a změřit také write overhead.
- **A2:** Úplnost seznamu domén dosud není prokázána. Uzavře ji inventář aktivních vstupů ve vlně 0, nikoli pouze grep názvů role helperů.
- **Provozní hranice:** Implementace follow-upu a jeho produkční aplikace jsou samostatné kroky. Tento dokument neopravňuje migraci produkce, deploy, commit/push, publikaci ani skutečné e-maily.

## Implementační vlny

### 0. Úplná mapa a měřitelný výchozí stav

**Změny:** Na aktuálním main vytvořit evidence lokální evidence v ignorovaném `$FESTAPP_AUTHORIZATION_EVIDENCE_DIR` (viz [historický záznam a obnova](../archive/canonical-authorization-evidence-2026-10-20.md)). Vypsat RPC dostupné anon/authenticated/service_role včetně overloadů a SECURITY DEFINER funkcí; RLS/table grants; Edge/Worker entry points a skutečné Dart/JS/MCP callery. Přes source katalog a lokální `pg_proc`, `pg_policy`, grants dohledat také dynamické registrace a interní routy. Zdokumentovat každý endpoint: actor, tenant/resource vazba, operace, současné allow/deny pravidlo, caller a owning test. Rozdělit domény na pilot a konečný seznam zbývajících domén. Přímé tabulkové přístupy přes PostgREST/Realtime/Storage zahrnout, kde ovlivňují stejná data.

**Migrace/selhání:** Zatím beze změny schématu a chování. Nedostupná produkční evidence není důvod spouštět produkční dotazy nebo tvrdit změřený výkon.

**Validace:** Lokální syntetické prostředí s markerem, pozastaveným emailem a bez aktivního odesílacího cronu. Truth table: anon, běžný přihlášený, jednotlivé role, kombinace, cizí tenant, demo a chybějící resource. Baseline `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` a opakovaná měření pro context, operator seznam, editor bundle, přímý RLS list a representative write; malé i velké množství akcí/členství. Uložit fixture velikosti, indexy, verze, zdrojový hash, počet RPC, p50/p95 a buffers.

**Exit:** Každý aktivní vstup má vlastníka a pravidlo; inventář je kontrolovatelný proti katalogu, baseline lze znovu spustit.

### 1. Kanonické pravidlo a pilot bez změny práv

**Změny:** Pilot: ticket-layout read/write, čtení/změna objednávek, create occasion a oddělené public form/editor bundle. Vytvořit doménové predikáty nebo přesunout existující `can_edit_ticket_layout` bez druhé definice; assertion i projection používají stejný owner. Doplnit důvěryhodnou resource vazbu pro MCP v atomickém doménovém requestu, pokud ji dnešní request neumí zajistit. Rozlišit obecné discovery a konkrétní operaci.

**Migrace/selhání:** Forward migrace vytvoří nové funkce před přepojením callerů. Historické migrace neměnit. Stávající response/error obálky zachovat v adaptérech; neznámá capability a neplatný scope fail closed. Ve stejné změně nepřepisovat role data ani objednávky.

**Validace:** SQL truth table pilotu před/po, tenant a demo případy, EXECUTE grants, service-role hranice, přímé RPC mimo UI. Test replay po odebrání práv a souběžného přesunu resource mimo delegovaný unit. Porovnat skutečné query plány s baseline.

**Exit:** Pilotní doménová pravidla mají právě jednu definici a všechny pilotní serverové vstupy ji používají.

### 2. UI projekce a MCP adaptéry

**Změny:** Rozšířit existující context/bundle SQL vlastníky (`get_app_config*` dohledané ve vlně 0) o capability projection. Flutter/JS RightsService čte funkční možnosti z projekce místo OR výrazů rolí. `get_operator_access_v1` používá stejné doménové predikáty pro konkrétní dostupné operace; jeho klientský schema kontrakt aktualizovat atomicky s adaptéry. `tools/festapp/src/operations/access.mjs`, `remote/delegation.mjs`, `operations/catalog.mjs` ponechají pouze transport, validaci souhlasu a jeho průnik s živým výsledkem. Edge/Worker adaptér se stejným pravidlem nepočítá role znovu.

**Migrace/selhání:** Explicitně vyřešit starší podporované mobilní binárky a consent storage. UI role pole lze zachovat jako dokumentovanou externí projekci, nikdy jako druhý serverový owner. Starší platný souhlas se nesmí rozšířit; neinterpretovat nové operace jako automaticky povolené. Při změně actor/context zahodit stale async výsledek.

**Validace:** Stejný actor/resource/operation přes běžný RPC a MCP má stejnou SQL odpověď; MCP může navíc odmítnout kvůli scope/souhlasu. Revokace/expiry, přidání práv bez rozšíření souhlasu, unit budoucí akce, create opt-in, stale UI, admin/buyer/anon public form bez editor requestů. Počet síťových volání nesmí vzrůst.

**Exit:** Pilotní funkční práva už Dart/JS/MCP samostatně neodvozují; běží skutečný grant a doménový request proti lokální DB.

### 3. Dokončení všech domén a RLS

**Změny:** Pro každou zbývající položku inventáře přesunout kombinace rolí do jejího pojmenovaného doménového pravidla a přepojit čtení, zápisy, bundly, command/replay, Edge/Worker a RLS. Zahrnout uživatele, reception/scanning, informace/mapy/program, inventory, finance/email a interní jobs podle skutečné mapy. Seznam není povolení přeskočit doménu, která při inventáři přibude. Resource vztahy získávat z databáze, ne z callerem tvrzeného tenantu.

**Migrace/selhání:** Postup po koherentních doménách, bez dlouhodobé dvojí implementace. Technické tokenové/capability přístupy kupujícího a ověřené webhooky zachovat jako samostatně pojmenované autentizační hranice s doménovými invarianty; nenahrazovat je editor rolí. Omezit veřejnou spustitelnost interních helperů a zabránit přímým table-write bypassům. Nezavádět application triggers.

**Validace:** Každá doména prochází její původní testy a sdílenou truth table; RLS čtení/zápisy zkusit skutečně jako anon/authenticated, ne pouze superuser. Nejlevnější relevantní SQL/Node/Deno/Dart/Flutter testy podle inventáře. Flutter jediný task na stanici, test concurrency 1.

**Exit:** Inventář nemá nepřepojený aktivní vstup ani nezdokumentovanou role kombinaci mimo kanonického ownera.

### 4. Kontrakce, výkon a předávací důkaz

**Změny:** Uzavřít deletion ledger, doplnit source/parity kontrakt do existujících canonical SQL generatorů a společný architecture popis. Vygenerovat nový forward SQL bez úprav immutable historie. Zopakovat baseline na stejných datech a prostředí, včetně souběžných requestů, studeného a zahřátého běhu.

**Migrace/selhání:** Drop nepoužívaných helperů/overloadů až po přepojení DB závislostí a všech podporovaných callerů. Pokud starý veřejný RPC vyžaduje podporu instalovaných mobilních klientů, jediný explicitní adaptér volá kanonické pravidlo, má seznam podporovaných klientů a podmínku odstranění; nesmí obsahovat vlastní policy. Interní compatibility aliasy neudržovat.

**Validace:** Opakované A/B se stejným workloadem a střídáním pořadí; uložit raw výsledky i plán. Výkonový gate: žádné nové N+1/RPC, žádný nově lineární permission scan a žádné opakované čtení všech capabilities na řádek. Na stabilním měření nepřipustit opakovatelnou regresi p95/throughput nad 5 %; u krátkých operací nejprve prokázat, že rozdíl přesahuje rozptyl měření. Neprůkazný benchmark není zelený gate. Neřešit regresi cache práva nebo oslabením kontroly.

**Exit:** Zelené doménové/contract testy, katalogový důkaz absence bypassů a obsolete owners, source/migration hashe a porovnání výkonu. Produkční aplikace zůstává samostatně neprovedená, dokud není autorizována.

## Deletion ledger

| Artefakt | Konečná akce a důkaz |
|---|---|
| Funkční OR kombinace rolí v Dart/JS RightsService a feature UI | Odstranit po přepojení na projekci; role indikátory pro identitu/UX smějí zůstat s vysvětlením. Scoped search + behavior test. |
| Duplicitní role kombinace v SQL RPC, bundlu a RLS pro tutéž operaci | Nahradit jedním doménovým predikátem; inventář každé operace ukazuje jediný owner. |
| MCP-specifické kopie doménových práv / případné statické allowlisty | Odstranit, pokud je inventář najde; zachovat pouze souhlas, scope, identity a jejich validaci. |
| Staré read/check implementace a SQL overloady bez callerů | Drop v contraction migraci po kontrole závislostí a grants; ověřit `pg_proc`, `pg_depend`, `pg_policy`. |
| Cache/token claims používané jako autoritativní snapshot rolí | Odstranit z authorization rozhodnutí; živý SQL test revokace v další žádosti. |
| Historické migrace a externí podporované protokoly | Historii zachovat; externí adaptéry vyjmenovat individuálně, bez druhé policy, s vlastníkem a removal podmínkou. |
| Staré testy a dokumentace druhého permission ownera | Přepsat na kanonický kontrakt, zachovat behavior assertions. Aktualizovat architecture/SERVICES a odkazy. |

## Provozní pořadí a rollback

Lokální implementace: rozšíření schema/kontraktu, přepojení serverových callerů, klienti a MCP, poté kontrakce. Každá vlna musí být bezpečná bez spoléhání na UI. Produkční rollout vyžaduje zvláštní autorizaci, přesný backend/tenant rozsah a aktuální release pravidla; tento plán neautorizuje rollout na všechny tenanty.

Před kontrakcí je možný návrat aplikace pouze proti schématu, které stále má společný owner. Po odstranění starých kontraktů použít forward opravu nebo kompatibilní předchozí klientský build. Neobnovovat původní duplicitní policy ani práva rozšiřující fallback. Při chybě capability odmítnout chráněnou operaci a zachovat veřejné bezpečné čtení podle jeho kontraktu.

## Definice dokončení a zbytková rizika

- Každý aktivní vstup má explicitní identitu, resource/tenant vazbu a jednu kanonickou doménovou policy; RLS a interní service vstupy jsou v důkazu zahrnuty.
- Běžný request a MCP sdílejí stejná živá práva, MCP navíc zachovává původní souhlas a scope. Revokace, replay a race testy procházejí.
- UI používá projekci, veřejný kupující nespouští editor requesty a funkční rozhodování se nekopíruje do klientů.
- Deletion ledger je uzavřen; úmyslně ponechané externí adaptéry jsou jednotlivě doložené. Zdrojová a skutečná DB definice souhlasí.
- Změřený výkon splnil gate na stejném workloadu. Neprokázané produkční latence se neoznačují za ověřené.
- Předávací report jasně rozlišuje lokální implementaci, publikaci a skutečně aplikovaný produkční stav.

Zbytková rizika: dosud neúplný inventář a případná rozdílná dnešní pravidla, kompatibilita instalovaných mobilních klientů, rozdíl lokální a produkční distribuce členství. Mají konkrétní resolution ve vlnách 0, 2 a 4; nelze je uzavřít pouhým přejmenováním helperů.
