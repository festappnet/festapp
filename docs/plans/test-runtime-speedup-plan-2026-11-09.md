# Zásadní zrychlení testovacího prostředí a běhu sad Festapp

Datum: 2026-11-09
Stav: Implementováno, ověřeno a nasazeno jako0.20.542+1053. Opravený seat benchmark102,51 ->45,72 s (2,24x); Flutter90,77 ->58,07 s. Všech8 exact-SHA hosted kontrol prošlo. Zbývající absolutní seat/browser cíle jsou uvedené v RESULT.
Oprava při release ověření: starší seat speedup2,07x je nahrazen níže uvedeným opraveným měřením.
Image Worker měl vlastní fallback55432 místo přidělené DB; nyní používá společný
DATABASE_URL a ověřuje identitu lease. Opravené srovnání patří do evidence1053.
Flutter i110 SQL provedení tím nejsou dotčeny.

Verification: standard - mění se izolace, souběžnost a důvěryhodnost CI
Autoritativní reference po aktualizaci mainu: `e3de2261a0717893b41b8cbfc955f9b47ed46da4`
Původní měřicí reference: `570aa2a29c081393720b98cbc2c79355e6818fd0`

## Výsledek a rozsah

Zrychlit přípravu prostředí, skutečné provádění SQL, Flutter a browser testů i celkovou kritickou cestu. První přínos musí být doložen pro STEJNÝ inventář testů. Zmenšení vybrané sady je samostatná, pozdější optimalizace a nesmí se vydávat za rychlejší provedení stejné práce.

Rozsah: kanonické testovací příkazy v `automation/ci/checks.json`, `automation/ci/run.py`, bootstrap a SQL runner, klientské testovací vstupy, browser testovací harness a související workflows. Všechny změny mají jednoho kanonického vlastníka a platí v lokálním zrcadle i GitHub CI.

Mimo rozsah: produkční DB a její baseline/ledger, produkční konfigurace, nasazení, změna obchodních pravidel, nákup runnerů nebo služeb. Plán nezavádí druhý aplikační backend. Výkonnostní optimalizace produkční funkce je přípustná až jako samostatný zdůvodněný úkol, pokud profilování prokáže skutečnou chybu.

## Podklady a oprava předchozí diagnózy

Podrobná čísla jsou v `test-runtime-speedup-evidence-2026-11-09.json`. Jsou z existujících běhů; kvůli tomuto plánu nebyly spuštěny další testy. Lokální a GitHub příklady mají různá SHA a hardware, nejde o párový benchmark.

| Fakt | Důkaz | Důsledek |
|---|---|---|
| Lokální seat-checkout 107,96 s: DB 38,4 s, kontrakty 34,8 s, notifikace 13,6 s, browser 4,7 s | Lokální CI receipt a log, odvozená evidence vedle plánu | Nestačí zrychlit bootstrap. Přes polovinu času představují další kroky. |
| GitHub seat-checkout 279 s, DB krok 125 s | Run [42624387792](https://github.com/festappnet/festapp/actions/runs/42624387792), job timestamps | Bootstrap je nejsilnější samostatný kandidát na cold CI. |
| DB krok stahuje postgres 15.8.1.085, realtime v2.120.3, storage-api v1.67.20 a gotrue v2.194.0 | Stažený log stejného runu | Příkaz `supabase db start` v tomto běhu přináší více závislostí než jeden databázový obraz. Neznamená to, že běží všechny služby. |
| První forward migrace 13:21:06.698, poslední 13:21:36.584, připraveno 13:21:38.637 | Stejný log: 371 `Applying migration` | Zhruba 30 s je interval přehrávání migrací. Předchozích asi 94 s zahrnuje download/start/bootstrap; nelze všechno označit za seedování nebo SQL. |
| Baseline je ze 6. 9., schema má 2,12 MB; zkoumaný checkout má 372 forward migrací a 17,84 MB SQL | `supabase/baseline/manifest.json`, `automation/baseline.py`, adresář migrací; počet zahrnuje připravenou opravu ikonky | Opakovaná historická cesta je už významná. Malý `supabase/seed.sql` má 864 B a není automaticky hlavní problém. Demo seed a owner alignment dosud nemají samostatné časy. |
| SQL runner se v jedné sadě spustí 13krát, dokončí 107 SQL souborů | Lokální log a `web_client/scripts/run_db_tests.js` | Opakuje discovery, připojení a globální údržbu sekvencí. |
| SQL runner používá pevné dávky pěti; notification SQL soubory drží shodný session advisory lock | `runAll()`, `runTest()` v SQL runneru | Některé workery čekají na dávkovou bariéru, jiné na zámek. Pouhé zvýšení concurrency to nevyřeší. |
| Nejvyšší notification elapsed: lifecycle 3611 ms, prepared_lifecycle 3035 ms, prepared_orders 2706 ms, open_latency 2415 ms | Lokální log | Jsou to časy včetně čekání, ne důkaz pomalé konkrétní SQL funkce. Profilovat fixture, čekání i assertion zvlášť. |
| GitHub ticket-client trval 157 s; příkaz má dvě Flutter invokace a mnoho samostatných testovacích vstupů | `checks.json: ticket-client`, stejný GitHub run | Je nutné odstranit opakovaný load/compile a zrychlit těla testů. Samotný Flutter SDK cache neřeší totožný problém. |
| Repozitář už má `registerClientSuites`, inventář a starší dokončenou optimalizaci testovacích session | `test/support/register_client_suites.dart`, `automation/client_test_inventory.py`, plány z 15. 10. | Navázat na existující mechanismus, neopakovat již dokončenou migraci ani budovat nový paralelní registr. Starší časy s concurrency 2/3 nejsou současný baseline. |
| Web job 174 s, startup/security krok 98 s, measurement 49 s; measurement má pět browser příkazů | Run [42624387875](https://github.com/festappnet/festapp/actions/runs/42624387875), `checks.json: web-measurement` | Další významná větev; řešit počet startů, kompilací, CLI roundtripů a pevné čekání. |
| Požadované CI je přesně osm jmen jobů na konkrétním SHA | `automation/ci/release_gate.py: problems`, `CONTRIBUTING.md` | Zrychlení nesmí používat skipped/missing job jako úspěch ani starý receipt jako důkaz nového SHA. |
| Cílený nový email regression prošel, ale jeho název není v kanonickém výběru kroků | `checks.json`, `database/tests/emails/delivered_tickets_resolve_confirmation_test.sql` | Současně je nutné opravit inventář pokrytí; rychlost nesmí zakrýt vynechané testy. |


## Zjištění při realizaci a gate vlny 1

Lokální izolovaný experiment z `570aa2a29` doložil shodu normalizovaného
schématu, ACL, vlastníků, extension verzí, sekvencí a migračního ledgeru mezi
původním CLI bootstrapem a prototypem samotné PostgreSQL image. Neprošla však
shoda referenčních řádků `public.client_sync_component_sources`.

Obě čisté replay cesty zachovávají jeden neplatný `regclass`: historická registrace
`private_inventory`, `test_factory=waitlist_slot_factory`,
`scope_resolver=form -> forms.occasion`, `tracked_columns` obsahující
`participant_id`. Odkazuje na odstraněnou původní `eshop.waitlist_offer_slots`.
`database/functions/eshop_waitlist/retire_participants.sql` odstraňuje tabulku,
ale z registru maže pouze `eshop.order_participants`. Numerická OID neexistující
relation nejsou mezi replayi shodná a nelze je bezpečně přesunout logical dumpem
do jiného clusteru. Nejde o rozdíl pořadí rolí v policy: ten se normalizuje jako
množina; živé regclass se porovnávají přes názvy. Neplatný odkaz zůstává viditelným
selháním, není normalizován na úspěch.

Vlna 1 zahrnuje nezbytnou kanonickou forward opravu
registru a její populated upgrade regresi. Neupravovat zpětně historické migrace,
produkční baseline ani ledger a nepřidávat opravu pouze do testovacího bootstrapu.
Veřejný bootstrap nyní deleguje pouze kanonickému runtime. Forward oprava
`20261109180000_retired_waitlist_registry.sql` prošla populated regresí a obě
nezávislé cesty mají shodné referenční řádky a nula neplatných odkazů. Skutečný
replay, dvě současné leases, marker/connection fencing, crash recovery, GC a
checkpoint + skutečný append tail prošly integračními kontrakty.

Naměřené upřesnění vlny 4: 24 původních ticket vstupů obsahuje osm odlišných
SDK/font/client prostředí. Výsledkem jsou čtyři kompatibilní skupiny a osm
izolovaných vstupů v jedné invokaci; preference 3-5 vstupů proto ustupuje
odůvodněným 12, bez sloučení singletonů se staticky cachovanými klienty.
Stávající inventář dokládá všech 203 stejných semantic cases včetně skip stavů.

Aktualizace mainu přinesla agent-browser 0.41.2. Jeho nativní discovery prošlo
jedním úplným candidate gate a 12 opakovanými trusted click scénáři. První
matched control startup však následně selhal na 1440px iframe timeoutu;
samotný upgrade proto není prokázaná oprava spolehlivosti. Selhání zůstává
selháním a control startup neposkytuje platný rychlostní baseline. Dřívější geometrický
workaround pro 0.39.4 byl odstraněn; nepřipínat executable path, který na tomto
stroji způsoboval iframe stall. Zachovány jsou split ESM fixture, negativní
pozorovací okna a izolované browser procesy. Aktuální correctness inventář:
306 Node testů, 31 browser reportů, measurement 194 scénářů.

Na novém mainu je navíc původní email Flutter root: 13 vstupů v jedné invokaci,
295 shodných semantic cases. Cold control/candidate 118,05/89,60 s; warm
control 93,06/90,77/86,73 s a candidate 52,69/60,87/58,07 s. Medián klesl
z 90,77 na 58,07 s (36 %); všech osm běhů prošlo bez změny inventáře nebo
zdrojových vstupů. Reverse order prošel 295 případy za 43,08 s. Velká cizí
swap zátěž je zaznamenána, nejde o vyhrazený benchmark host.

Nové main gates jsou zachovány v DAG, včetně email variable/tone a user-creation
authorization SQL: seat inventář je nyní 110 provedení. Nová PG15 provider parity
a všech devět skutečných runtime kontraktů prošly. Cache klíče pokrývají i
tranzitivní seed includes a validační generátory/policy. Joomla/WordPress
packagery ověřují skutečné výstupy v privátním dočasném stromu, aby gate neměnil
vlastní vstupy. Čísla následujícího odstavce jsou historická před integrací mainu.

SQL tuning stejného inventáře (108 provedení, 107 unikátních ID): 2/4/5 workerů
prošlo bez retry za 19,08/19,45/28,84 s. Default je 2 (85,7 MiB host RSS proti
172,1 MiB pro 4). Sdílené helper DDL se instaluje jednou; skutečné TRUNCATE
fixtures vyžadují výhradní soubor, ostatní sdílené mutace mají resource claims.
Původní Docker memory samples nebyly čitelné kvůli ANSI streamu; nejsou důkazem
nulové spotřeby. Opravený sampler má regresi. Druhá celá matice prošla za
15,72/14,14/13,75 s s PG container peak347,0/375,8/432,9 MiB (27-31 samples).
Default2 omezuje tlak současných izolovaných units za cenu přibližně2 s.
Flutter cold72,05 s, warm63,88/56,12/48,13 s a reverse44,42 s zachovaly203
případů; control cold110,77 s a warm median80,41 s. Profil load i těla je uložen.

Finální current-main matched seat110SQL: control cold116,03 s a warm
108,07/108,09/105,52 s; candidate DAG cold73,93 s a warm52,12/51,09/52,80 s.
Medián108,07 ->52,12 s (2,07x), fallback2x splněn, deficit proti40 s je12,12 s.
Jde o stejných devět behavior units bez nově přidaných safety/upgrade gates.
Ty zůstávají v kanonickém CI a prošly ve finálním full8. Jeho celkový čas byl
340,12 s; kanonická seat větev včetně nových gates a scheduling wait ve společném
běhu zabírá span187,02 s. Nelze ji zaměnit za izolovaný matched benchmark.
Browser measurement median33,18 ->31,65 s, startup candidate107,15 s;
combined138,80 s překračuje75 s o63,80 s. Startup control poprvé selhal,
není proto platné tvrdit jeho zrychlení. Warm clone median0,69 s a tři targeted
SQL median2,23 s splňují samostatné limity. Detailní zdroje, memory, scope a
zachované první failure jsou v RESULT dokumentu a JSON. hosted cold výkon nebyl kontrolovaně porovnán. Tato část popisuje historický
lokální stav; následný release0da72ea9f prošel8 exact-SHA hosted kontrolami
a byl publikován i nasazen.

## Cíle a pravidla měření

Čísla níže jsou akceptační cíle, ne slib již prokázané úspory. Nejsou aditivní; finální součet určuje kritická cesta.

| Metrika | Dnešní důkaz | Cílový stav |
|---|---|---|
| Lokální bootstrap při stejném fingerprintu | 38,4 s v celém DB kroku | <= 5 s pro acquisition + čistý clone při teplém clusteru; zvlášť vykázat start zastaveného clusteru |
| Lokální celá seat-checkout, stejný inventář | 107,96 s | medián <= 40 s, jinak prokazatelně alespoň 2x rychleji a přesný zbývající bottleneck |
| GitHub cold seat-checkout, stejný inventář | 279 s referenční job | <= 120 s bez času ve frontě; vykázat cold cache miss i cache hit |
| GitHub ticket-client, stejný inventář | 157 s referenční krok | <= 75 s; zachovat concurrency=1 na Macu |
| Web startup + measurement, stejný inventář | 147 s referenční kroky | <= 75 s dohromady |
| Běžná cílená SQL oprava při hotovém základu | 3 cílené soubory dříve prošly za zlomek sekundy po přípravě DB | <= 10 s end-to-end včetně acquisition a cleanup; rozsah musí být výslovný |

Výchozí body změřit na jedné zmrazené revizi. Finální srovnání: stejné test ID a parametry, nástroje, resource limity, fixture velikosti a hardware. Pro rozhodnutí použít tři teplé běhy každé porovnávané varianty a alespoň jeden skutečně cold běh; nepočítat p95 ze tří vzorků. Cold znamená explicitně popsaný stav image/artifact/dependency cache, ne jen nový shell. Historické runy slouží k prioritám, nenahrazují tento experiment.

## Cílová architektura

### Jeden orchestrátor a strojově čitelný kontrakt

Rozšířit existující `automation/ci/run.py` a `checks.json`, nikoli přidat další nezávislý test launcher. Joby budou složené z pojmenovaných jednotek s příkazy jako argv/script, vstupním manifestem, test inventory, závislostmi a resource claims: flutter, browser, db cluster, db workspace, cluster-global mutation. Stejnou DAG spotřebuje lokální mirror i workflow. Zachovat osm veřejných check names a stávající release gate.

Příkazy `automation/test_ci.sh`, `automation/test_all.sh`, `automation/test_client.sh`, explicitní SQL runner a DB bootstrap mají delegovat prostředí stejnému vlastníkovi. Explicitní filtr má vždy ukázat, co se skutečně spustilo. Neznámý dopad spouští širší sadu; žádné heuristické skrytí testů.

### Dvě rozdílné odpovědnosti databázových testů

1. **Upgrade verification:** na čistém provider-compatible základu skutečně přehrát podporovanou historii/backfill/forward migrace a populated upgrade fixture. Tento důkaz nelze nahradit restore snapshotu. Platí pro změny migrací, baseline a runtime a pro úplnou release sadu.
2. **Behavior verification:** pracuje na čistém aktuálním schématu a referenčních datech odvozených z úspěšné upgrade cesty. Nemá při každém spuštění znovu ověřovat stovky historických přechodů. Každý run dostane vlastní databázi z neměnného základu.

Upgrade a behavior jsou oddělené jednotky, ne přepínač pro obejití gate. Při změně SQL migrace musí běžet relevantní skutečný upgrade i behavior testy, například nynější oprava emailového souhrnu. I tento případ zrychlí menší runtime, méně startů a rychlejší samotné testy.

Použít dvoustupňovou cache: ověřený checkpoint přesného neměnného prefixu migrací a výsledný aktuální behavior template. Nová append-only migrace smí využít clone nejbližšího kompatibilního checkpointu a skutečně aplikovat jen tail; checkpoint klíč obsahuje seřazené digests celého prefixu. Změna starší migrace, backfill/seed/prerequisite nebo owner alignment invaliduje checkpoint od místa změny. Fixture pro upgrade konkrétní změny musí být vložena PŘED jejím skutečným provedením; hotový behavior template ji nemůže nahradit. Úplná release/integration sada nadále obsahuje cold full replay podporované historie, přičemž lze připravit behavior workspace souběžně podle resource budgetu. Rozlišit v receipt full replay, checkpoint + tail i behavior restore. Tím se nový SQL commit nestane automaticky důvodem přehrát všech 371 starších přechodů v každém cíleném běhu.

### Databázový runtime a životní cyklus

Nový vlastník `automation/local_db/runtime.py` a manifest `automation/local_db/test-base.json` budou používat stejnou přesně připnutou Supabase PostgreSQL image/rozšíření jako podporovaný testovací provider. Nezaměnit ji za obyčejný Postgres bez Auth helperů, rolí a extensions. Docker publikuje pouze loopback, vypne skutečné cron/pg_net externí operace a nenačítá produkční environment.

Nejdřív prokázat minimální provider initialization pro SQL sady: auth/storage helper schema, role, grants, extensions, owners a required settings. Z běžné SQL cesty odstranit závislost na CLI startu, který dotahuje realtime/storage/gotrue images. Jejich schéma zachovat v přesném verzovaném prerequisite artefaktu, pokud ho testy potřebují; skutečné integrační sady pro tyto služby mají vlastní explicitní runtime. Žádné výchozí prázdné stubs za Auth, RLS, platby nebo provider schema.

Fingerprint obsahuje image digest/platformu a PG/extension verze, provider init, baseline manifest i jeho ověřené blob vstupy, všechny forward migrace podle obsahu, backfill stages, owner/grant alignment, seed/reference/demo data, bootstrap/runtime nástroje a jejich formát/verze. Dále zahrnout canonical-source parity vstupy nebo odmítnout drift zdrojových SQL od migrací; hash jen názvů migrací nestačí. Testovací kód samotný fingerprint schématu nezneplatňuje, pokud nemění společný základ. Test execution receipt ho ale zahrnuje.

Lokálně lze uchovat pouze neměnný čistý template v dedikovaném clusteru/volume, nikoli poslední databázi po testech. Run acquire ověří identity/marker + digest a pod lease vytvoří unikátní clone; release zavře vlastní connection pooly a odstraní jen vlastní run DB. Template není připojitelný testovacím klientům. Po poslední lease lze cluster zastavit se zachováním template volume; žádný bootstrap nesmí zastavit cizí session. Explicitní `status`, `prune` a `--stop` zachovají ownership/lease pravidla. GC řeší opuštěné runy podle vlastního PID/run ID a stáří, nikdy podle shody prefixu samotného.

GitHub používá verzovaný logical/custom dump nebo čistý initialization artifact vzniklý z ověřené cesty. Artifact musí být svázán s digestem zdrojů, platformou a toolchainem; cache miss bezpečně regeneruje. Neobnovovat živý PGDATA mezi hosty a verzemi. Template clone je uvnitř téhož clusteru. Fork PR a jiné nedůvěryhodné artefakty nesmějí publikovat cache, kterou později důvěryhodný workflow nekriticky obnoví. Preferovat důvěryhodný default-branch producer s úplnou provenance a read-only konzumenty; jinak cold rebuild.

Žádné plošné `fsync=off`, `BYPASSRLS`, zmenšení fixture nebo vypnutí asercí. Optimalizace není změna produkční baseline ani její ledger. Periodické přebalení testovacího základu je generovaný artefakt, nikoli smazání historie.

## Implementační vlny

### 0. Jemné měření a inventář před změnou chování

Změny: `run.py`, SQL runner, `bootstrap_local_db.sh`, klientský JSON reporter a browser harness. Zavést monotonic JSON časy pro download/start/readiness, baseline restore, history materialization, jednotlivé migrate stages, backfill, owner alignment, demo seed, clone, cleanup. SQL: acquire connection, advisory lock wait, fixture, body, cleanup; kde SQL monolit nemá seam, nejprve měřit server waits a oddělit jen tři nejdražší scénáře. Flutter: process startup, suite load a test body podle JSON events. Browser: build, start serveru, start browseru, jednotlivý scénář a CLI command count. Nepřidávat plné query logování.

Výsledek musí obsahovat přesné SHA + dirty-input content digest, platformu, verze, test IDs, skip/retry stav a peak memory. `latest.json` dnes přepisuje globální výsledek; přejít na immutable `runs/<id>/receipt.json`, latest pouze jako ukazatel. Oddělit čekání ve frontě, spuštění a cleanup, který je nyní mimo lane seconds. Archivy bez tajných hodnot.

Validace: kontraktní testy reporteru/manifestu, jeden výchozí běh. Exit: lze říct, kolik času konkrétně tvoří restore, migration replay, waiting a test body; nejde pouze o přejmenování starých souhrnných kroků.

### 1. Minimální databázový runtime a rychlý čistý základ

Implementovat runtime/fingerprint/template lifecycle a ověřený prefix checkpoint + tail výše, přesměrovat shell bootstrap na tohoto vlastníka. Nejprve zachovat skutečný cold upgrade, odstranit nepotřebné image pulls a opakované provider init; potom zavést opakované využití pouze čistého template. Dát seed fáze do samostatných měřených profilů: minimální referenční základ a explicitní demo dataset. Demo profil měnit pouze při prokázané nezávislosti všech ostatních testů.

Validace: bootstrap a skutečný upgrade porovnat se starou cestou podle normalizovaných schema/ACL/owners/functions/extension settings, ledger, referenčních řádků a kanonické parity. Ověřit invalidaci po změně obsahu migrace se stejným názvem, seed, toolchainu a provider init. Ověřit dvě současné leases, crash při tvorbě template, opuštěný clone, chybný marker, odmítnutí remote URL i loopback tunelu mimo vlastněný kontejner a nevypnutou cizí session. Template publikovat atomicky až po všech kontrolách.

Rizika: DB-local versus cluster-global extensions, cron metadata a hardcoded názvy `postgres` v existujících SQL/Node skriptech. Před přesměrováním consumerů udělat scoped inventář těchto odkazů a opravit command argumenty/adaptéry; nespoléhat jen na `DATABASE_URL`. Exit: SQL cold cesta nepřitahuje tři další service images, teplý run obnoví skutečně čistý vlastní DB a upgrade testy zůstávají reálné.

### 2. SQL runner bez bariér a opakované globální přípravy

`web_client/scripts/run_db_tests.js`: nahradit chunk+Promise.all bariéry průběžným bounded worker poolem. Využít už existující connection klienty přes hygienický pool, ale zkontrolovat ukončení transakce a reset session ROLE/GUC/advisory locks po každém souboru. Nelze obalit vše jedním rollbackem: existují testy se skutečným COMMIT a více connection. Selhaná nebo nečistá session se zahodí.

13 spuštění sloučit do deklarovaných SQL groups s jedním discovery a jedním sequence-maintenance krokem na čistý workspace. Zachovat závislosti mezi skupinami a samostatné script boundaries tam, kde mezikrok mění schéma. `run_db_tests.js <filters>` zachovat jako tenký podporovaný CLI, nevytvořit další runner.

Notification advisory lock dnes chrání skutečný singleton projector. Neodstraňovat jej naslepo. Unit workspace získá vlastní clone DB; singleton-sensitive soubory buď dostanou odlišné workspace, nebo zůstanou v explicitně sériové skupině. Cluster-global mutations, migration/upgrade tests a extension změny nemohou být automaticky paralelní ani v různých DB. Resource claims v kontraktu určují konflikty. Výchozí concurrency měřit na 2/4/5, nepřevzít vyšší číslo bez wall-time a memory důkazu.

Sekvenční retry dnes umí překrýt race. Zachovat first-attempt result jako součást verdiktu; retry je diagnostický a nenahradí úspěch deterministické gate. Před utažením této podmínky opravit odhalené sdílené fixture kolize v této vlně. Exit: shodný inventář, žádné nově skryté retries, žádný překryv globální údržby sekvencí s běžícími testy a měřitelně kratší SQL wall time.

### 3. Zrychlit fixture a těla nejdražších SQL testů

Začít `notification_center/{lifecycle,prepared_lifecycle,prepared_orders,open_latency}_test.sql`, potom top 5 z nového profilu kontraktů. U každého oddělit setup od skutečně testované operace. `open_latency` připravuje 2000 aktivit a projekci; tento objem a ready/nonempty aserce zůstávají. Změřit init a projector iteration count. Sdílet lze jen neměnný společný seed/template, každý scénář musí stále provést vlastní mutace a testovaný workflow.

Povolené změny: set-based mechanické fixture vložení místo opakovaných klientských roundtripů, prepared statements/přímý `pg` klient místo spawn psql na každý dotaz, jedna společná setup fáze pro skutečně identické izolované scénáře, reuse inertních binary/assets. Pokud setup právě ověřuje produkční mutation/RPC nebo reálný transport, tuto cestu ponechat a optimalizovat pouze okolí. Nepřepsat ji na přímý INSERT a nepovažovat výsledek za stejný test.

Pevné sleeps v concurrency testech nahradit pozorováním skutečného blocking/receipt/state s bounded deadline; kde čas sám tvoří kontrakt, čekání zůstává. Query plan a wait profiling jen pro prokázaný bottleneck v disposable DB. Exit: top 5 mají breakdown a zachovaný scénář; dosažené úspory nejsou tvořené redukcí dat nebo ztrátou konkurence.

### 4. Flutter: méně load/compile a rychlejší jednotlivé scénáře

`checks.json: ticket-client` a testovací entrypointy převést na několik kompatibilních seskupených vstupů přes existující `registerClientSuites`. Začít notification/form/occasion/eshop skupinami podle skutečného potřebného prostředí: locale, Supabase singleton, services, plugin/font bindings. Nesloučit neslučitelné globální stavy do jednoho souboru. Preferovat 3-5 kompatibilních vstupů místo dvou invokací s desítkami vstupů; přesný počet rozhodne izolace, ne libovolný limit.

Zachovat deklarace a test IDs v `*_cases.dart`, aktualizovat stávající client inventory a zabránit dvojité registraci v default discovery. Reverse-order mechanismus už existuje: použít jej pro nové skupiny, případně doplnit reproducible seeded ordering při vývoji fixture. Běžný finální běh neopakovat bez důvodu.

Profilovat `pumpAndSettle`, font/asset init, restartování plného MaterialApp a lokalizace, vytváření mock klientů a uzavření controllerů/timerů. Nahradit pouze nadbytečné čekání konkrétním pump/state očekáváním. Procesně čistou logiku přesunout do EXISTUJÍCÍHO `festapp_core` vlastníka jen pokud profil prokáže podstatný přínos a skutečnou logiku lze oddělit od widgetu; neprojektovat plošnou architektonickou migraci před první úsporou. UI adaptér musí zůstat ověřen widget testem.

Zkontrolovat, proč ve sledovaném CI zůstávají tisíce Easy Localization debug řádků navzdory `LocalizationLogFixture`; použít stávající scoped printer bez potlačení warning/error. Nesmí se tím maskovat reálné assertion chyby. Persistent compile caches použít jen pro shodný SDK/OS/arch/dependency/source fingerprint, nikdy neobnovovat cizí `.dart_tool` jako neověřený celek.

Validace: stejné semantic test IDs přes `client_test_inventory.py`, běžné i opačné pořadí nově seskupených fixtures a jedna konečná profilovaná dávka. Mac vždy pouze jeden Flutter task a `--concurrency=1`; nic v plánu tento limit nemění. Exit: ticket-client dosáhne cíle nebo má doložený zbývající profil; zrychlení kompilace a těl se vykáže zvlášť.

### 5. Browser a web: amortizovat starty i komunikaci

Začít `web-startup` 98 s a `web-measurement` 49 s, nikoli rychlým seat browserem 4,7 s. Přesné consumery: `web_client/scripts/test_form_access_browser.mjs`, `test_web_security_browser.mjs`, `test_form_measurement_{browser,runtime_browser,nested_browser,runtime_adversarial}.mjs`, `build_measurement_runtime.mjs`, `isolated_browser_startup.mjs` a jejich příkazy v kontraktu. Podle profilu z vlny 0 určit všechny scénáře ze startup kroku, které opravdu dominují.

Jeden immutable fixture/runtime build na obsahový fingerprint pro danou dávku. Jeden vlastněný server proces, kde to testovaný contract dovolí, a jedna browser lifecycle pro kompatibilní scénáře s čerstvým context/session a vyčištěným storage. Origin/site isolation, nested frames, CSP, sandbox a disconnect/reconnect scénáře mají své explicitní hranice; žádné nahrazení skutečného browseru JSDOM ani přímým voláním implementace.

Snížit počet spawn agent-browser CLI roundtripů seskupením čistých čtení/asercí a využitím podporovaných operací ve společném harness. Reálné click/navigation/form chování ponechat reálné. Nahradit pozitivní pevná čekání readiness/event kontraktem. Negativní aserce typu 'nic se nespustilo' musí dál mít pozorovací interval nebo doložený scheduler/network completion barrier; čekání nelze jen smazat. Zachovat timeouts jako horní hranice, nikoli sleep.

Browser operace při implementaci delegovat podle AGENTS na Terra; běhy headless/background, muted, izolované a bez zásahu do uživatelova prohlížeče. Žádný placený modelový backend. Zachovat kanonické E2E příkazy. Exit: stejná scénářová matice včetně negativních safety případů, nižší build/start/CLI count a splněný nebo přesně vysvětlený časový cíl.

### 6. Zkrátit kritickou cestu napříč osmi joby

Teprve po odstranění redundantní práce zavést dependency/resource scheduler v existujícím orchestrátoru. DB behavior, čisté Node/Deno kontrakty a Flutter mohou být nezávislé větve; DB mutace, generátory a globální prostředky mají deklarované hrany. Nezapínat vše paralelně na stejném Macu: respektovat Flutter slot, celkovou RAM, DB connection budget a browser workload. Měřit peak RSS a wall-time, ne jen součet procesů.

Sjednotit frozen dependency installation jednou na package + lockfile + Node/tool verzi v rámci runu. Při workspace s různým Node neprohlásit instalaci automaticky za kompatibilní. Lokálně reuse store a matching node_modules, hosted pnpm cache. Reuse browser/runtime build artifacts podle obsahu. CI ze superseded PR heads může rušit jen starší běh téhož PR; nikdy cizí worktree, release job nebo již probíhající live operaci.

Osm požadovaných check names ponechat. Workflows přesměrovat na stejný kontrakt/DAG, odstranit duplikované ručně sestavené seznamy kroků. Úplné CI na release SHA stále skutečně spustí všechny požadované jednotky. Lokální optimalizační receipt nenahrazuje GitHub exact-SHA gate.

Teprve potom přidat manifest affected inputs: explicitní test IDs, zdrojové/generated/tool/config/lock vstupy a reverse dependencies. Neznámý soubor = plná sada. Aktualizovat test selection kontrakty tak, aby nově přidaný soubor nemohl tiše vypadnout. Cílené běhy deklarovat jako cílené. Pokud později bude žádoucí přeskočit jednotku i uvnitř požadovaného release jobu, jde o samostatnou změnu politiky; tento plán to nepovoluje.

Exit: plný run má kratší kritickou cestu při stejném coverage, osm skutečně zelených checků na testovaném SHA, cílené lokální běhy mají strojově vypsaný rozsah a žádné falešné SUCCESS za skipped jednotku.

### 7. Jedno finální srovnání, odstranění starých cest a dokumentace

Pro finální kombinaci provést definované cold/warm srovnání, zachovat raw structured evidence a původní kontrolní SHA. Doložit počet i identitu scénářů, retries, wall time, peak RSS, startup/replay/body/waits/cleanup. Nejprve porovnat plné stejné sady, až potom odděleně přínos targeted selection.

Migrate všechny konzumenty bootstrapu, custom DB transportů, test_all/test_client a CI. Přidat coverage/inventory kontrakt pro email recovery a další nově nalezené mezery. Aktualizovat `CONTRIBUTING.md` o prostředí, profilované kroky, workspace lifecycle, regeneraci cache a přesné release gates. Artefakt validace bez finálních vstupů není přenositelný release receipt.

Exit: tabulka před/po na shodném workloadu, dosažené cíle nebo explicitní deficit se skutečnou příčinou, všechny odstraněné cesty podle ledgeru níže a žádný testovací DB/cache bypass v běžných příkazech.

## Ledger odstranění a zachování

| Současná cesta | Konečný stav | Důkaz |
|---|---|---|
| Bezpodmínečné stop/start a replay celé historie při běžném behavior runu | Odstraněno; vlastník runtime acquire/template clone | Běžný warm log nemá replay, skutečný upgrade unit ho má |
| Dotahování realtime/storage/gotrue pro SQL-only prostředí | Odstraněno z behavior/upgrade SQL runtime; explicitní service integration může zůstat | Cold image manifest a schema/provider parity |
| Pevné SQL dávky a 13 samostatných setupů | Nahrazeno jedním schedulerem s explicitními barriers | Trace a stejný test inventory |
| Oprava chyby paralelismu skrytá automatickým zeleným retry | Diagnostický retry ponechává původní selhání viditelné | First-attempt verdict v receipt |
| Přímé kompilování kompatibilních cases jako jednotlivých vstupů | Přesměrováno na existing registration mechanism | Semantic inventory a root list |
| Opakovaný build/start v kompatibilních browser scénářích | Společný immutable build/harness, izolace scénářů zachována | Lifecycle trace + scenario inventory |
| Globální přepisovaný jediný CI receipt | Immutable run receipts; latest je pouze ukazatel | Dva souběžné runy neztratí evidence |
| Historické migrace, reálné upgrade/backfill fixture, osm release jobů | Zachovat jako konkrétní kompatibilitní a release hranice | Upgrade parity a exact-SHA GitHub gate |
| `bootstrap_local_db.sh`, `run_db_tests.js` veřejné CLI | Zachovat jako tenké vstupy do kanonického vlastníka | Žádný druhý business/test bootstrap uvnitř wrapperů |

## Rizika, neověřené předpoklady a jejich řešení

- **Předpoklad:** minimal PostgreSQL image lze inicializovat bez service-image bootstrapu při úplné shodě provider schema. Ověřit ve vlně 1 před migrací callerů. Při neúspěchu ponechat provider initialization jako explicitní cold builder a obnovovat ověřený čistý artifact; nepřijmout nekompatibilní náhradu.
- **Předpoklad:** clone podporuje potřebné extensions a metadata. Ověřit dřív než zavést parallel workspaces. Cluster-global tests zůstanou sériové nebo dostanou vlastní cluster; nenutit je do nesprávné izolace kvůli času.
- **Předpoklad:** velká část Flutter času je load/compile. Evidence ukazuje počet vstupů, nikoli přesný podíl kompilace. Vlny 0/4 jej musí změřit; pokud dominují těla, prioritizovat fixture/pump a stávající core seams.
- **Riziko:** zrychlení startu odkryje pomalý testovací kód. Proto má plán samostatné vlny pro SQL a Flutter těla, ne pouze caching a targeting.
- **Riziko:** cached snapshot může maskovat rozbitou migraci nebo ACL. Oddělený skutečný upgrade gate, obsahové hashování a parity kontrola jsou povinné.
- **Riziko:** global pool/dependency cache zamaskuje cleanup chyby. Cold runs a per-test session hygiene jsou součást akceptace.
- **Riziko:** stávající checkout je silně rozpracovaný jinými úlohami. Implementovat v čistém worktree z aktuálního main, převzít jen ověřené změny. Při aktualizaci main přepočítat relevantní fingerprints a affected checks.

## Pořadí dodání a rozhodovací body

První samostatná změna: vlna 0 a minimální runtime z vlny 1; příprava template/cache je navazující samostatně posouditelná část vlny 1, aby se první přínos nezdržel návrhem celé cache. Obě odstraňují největší prokázanou režii. Druhá: SQL scheduler a top fixture (2-3). Třetí: Flutter skupiny a bodies (4). Čtvrtá: web harness (5). Pátá: společná DAG, manifest pokrytí a kontrakce (6-7). Každou změnu lze posoudit samostatně, finální úspora se ale musí prokázat kombinovaně.

Neměřit po každém kosmetickém editu. Na vlnu jedna smysluplná funkční dávka, navíc výkonnostní experiment nutný pro její rozhodnutí. Nové měření opakovat pouze po změně krytých vstupů. Při nedosažení cíle popsat skutečný profil a upravit příslušnou vlnu; nesnižovat coverage ani nepřesouvat nutnou práci mimo měřený interval.

Původní plán sám autorizoval pouze plánování. Následné zadání uživatele autorizovalo implementaci a později publikaci a release1053. Tato historická autorizační hranice neopravňuje nové produkční operace. Zrychlení CI nemění pravidla schválení PR nebo release gate. Návrat při implementaci má vrátit celý příslušný runtime/scheduler consumer slice na předchozí ověřenou cestu, ne ponechat potichu dvě soupeřící cesty nebo automatický fallback po nejasném selhání. Čisté cache lze bezpečně zahodit a znovu vygenerovat; produkce se netýkají.

## Akceptace a konečný audit úplnosti

- [x] Nejprve doložen přínos pro stejná test ID, velikosti fixture a reálné hranice; výsledek není dosažen přesunutím přípravy mimo stopky.
- [x] Warm/cold, start/restore/replay/tail/fixture/assertion/wait/cleanup mají vlastní časy; srovnání zachová stejné revize kontrolních vstupů a toolchain.
- [x] Cache hit nikdy nevydává stav po testech za čistý základ; invalidace funguje i při přepsání migrace pod stejným názvem. Crash a nedůvěryhodný artifact nevytvoří použitelný template.
- [x] Multi-connection, COMMIT, singleton projector a cluster-global testy mají prokázanou izolaci; default pool netají first-attempt failure pomocí retry.
- [x] Flutter grouping zachovává cleanup, locale/Auth singleton boundaries a semantic inventory; browser grouping zachovává origins a negativní intervaly.
- [x] Každý veřejný bootstrap/test/CI vstup dosáhne stejného vlastníka; osm veřejných check names a exact-SHA release gate zůstávají platné. Nové email regression testy jsou skutečně vybrány.
- [x] Staré SQL bariéry, nepodmíněný replay, duplicitní workflow seznamy a přepisovaný jediný receipt jsou odstraněny nebo explicitně ponechány na hranici v ledgeru.
- [x] Za žádnou úsporu se nevydává dosud neměřený cíl; nesplněný časový cíl má konkrétní profil a navazující úkol místo oslabení testů.

## Opravené závěrečné měření pro release1053

Stejných9 behavior units,110 SQL provedení109unique a oba skutečné image
lifecycle scénáře nyní prokazatelně používají vlastní správnou DB. Osm prvních
pokusů prošlo bez změny vstupů. Control first106,59 s a warm103,78/101,95/102,51 s;
canonical DAG first67,43 s a warm45,72/44,90/46,95 s. Opravený medián102,51 ->45,72 s
znamená2,24x zrychlení; fallback2x splněn, deficit proti40 s je5,72 s. Předchozí
seat čísla slouží pouze auditu chybné vazby starého transportu. Flutter zůstává
platný nezávislý benchmark. Detailní corrected release1053 JSON obsahuje přesné
scope, SHA, URL kontrakty, memory a oddělené cold/warm podmínky. Source0da72ea9f
prošel všemi8 hosted GitHub kontrolami; failure artefakty jsou nyní archivované.

Schválený release je dokončen: main0da72ea9f, tenant9fac6c3e9,
vstupenky.online0.20.542+1053. Všech8 exact-SHA hosted kontrol, lokální build,
306 Node/31 browser testů a3 koherentní živé probes prošly. Publikované runtime
změny a oprava vedlejší session jsou společně na produkci. Numerické poznámky
jsou po deployi publikované na mainu a nemění nasazený immutable source.

## Zbývající výkonnostní práce

- Seat: odstranit zbývající5,72 s proti absolutnímu40s cíli podle profilů
  contract/notifications/browser. Stejný inventář, upgrade a izolační hranice zachovat.
- Browser: snížit znovu změřenou režii startů a CLI při zachování čerstvých kontextů,
  původních originů a negativních pozorovacích oken. Aktuální combined median138,80 s
  nesplňuje75s cíl. Nevykazovat neúspěšný control startup jako platné srovnání rychlosti.
- Hosted výkon a full8 total: kontrolované párové srovnání nebylo provedeno;
  úspěšných8 hosted kontrol je důkaz správnosti release, nikoli měření zrychlení.

## Navazující optimalizace celé kanonické větve

Celý příkazseat-checkout se všemi11 units včetně upgrade/runtime a přidaných
safety testů: kontrolovaný medián79,40 ->70,98 s, tedy dalších10,6% dolů.
Stejných110 SQL provedení109unique a oba image lifecycle scénáře prošly ve všech
osmi prvních pokusech. Odstraněny jsou pouze falešné závislosti mezi izolovanými
units; výhradní cluster operace chrání původní resourceclaimdbCluster2 a nový
synchronizační regresní test. Paměťové/worker limity zůstávají stejné. Frameworkové
CI testy nyní skutečně sbírá kanonický image-storage owner (25cases).
Browserové batchování se po kontrolovaném měření neosvědčilo a bylo vyřazeno.
Release1053 zůstává beze změny; nová změna se týká pouze spouštění testů.
Podrobné výsledky a rozdílné benchmarkové rozsahy jsou v RESULT dokumentu a JSON.
