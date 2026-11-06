# Redukce kódu a dokončení canonical cutoveru

Datum: 2026-11-06
Stav: Implementováno lokálně včetně uživatelem upřesněné contraction administračního centra; viz execution result. Produkce ani publikace neprovedeny.
Verification: standard pro kontakty, SQL, veřejné kontrakty a migrace; low-risk pro izolovaný úklid pomocných skriptů.
Referenční main: `92ee5c61165cb214b2164ab424b46ef82d5047b1` (`origin/main`).

## Výsledek a rozsah

Zmenšit počet udržovaných implementací, vlastníků stavu a dosažitelných starých cest. Zachovat chování objednávek, odesílání e-mailů, oprávnění, fontové identity a osobní historii notifikací. Pět oblastí: měřicí skripty, kontakt objednávky, katalog fontů, notifikace a archivní/generované podklady.

Tento dokument autorizuje plán práce, nikoli tvrzení o provedené implementaci. Při následné implementaci provést lokální změny a potřebné testy až po konkrétní mazání. Produkční migrace, rollout, změna podpory starých klientů a publikace jsou samostatné kroky s vlastní autoritou. Nevyžadovat novou autorizaci pro běžné lokální úpravy zahrnuté do následně zadané implementace.

Mimo rozsah: další přepis Git historie, plošné mazání testů, změna produktových pravidel, změna plateb, nové fronty nebo aplikační triggery, změny TrinaGrid, přepis Blueprintu a rollout dalších tenantů.

## Pracovní základ a pravidla provedení

- Přečíst `AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md` a `CONTRIBUTING.md` z aktuálního canonical mainu.
- `/Users/miakh/source/festapp` je původní checkout před kompakcí historie, lokálně na `a31277e3c`, s rozsáhlou cizí rozpracovanou prací. **Neslučovat jeho historii do nového mainu, nepoužít reset ani plošný stash.** Podrobnosti: `docs/plans/git-history-compaction-RESULT-2026-11-03.md`, část Workstation transition.
- Průzkum proběhl v čistém odděleném checkoutu uvedeného main SHA. Implementovat v čistém checkoutu aktuálního `origin/main`; tento plán přenést jako soubory, nikoli sloučením staré větve. Existující `/Users/miakh/source/festapp-compacted-20261103` je v záznamu uveden jako nový checkout, jeho současnou čistotu ověřit před použitím.
- Před implementací jednou aktualizovat main a prohlédnout změny v dotčených modulech od referenčního SHA. Pokud se změnil kontrakt, opravit tento plán a pokračovat podle nových důkazů.
- Pracovat na main a nejvýše jednom později výslovně zvoleném tenantu. Nyní žádný tenant není vybrán.
- JavaScript: pnpm 11.24.0, frozen lockfiles. Flutter: FVM, nejvýše jeden task na workstation, testy `--concurrency=1`; jiný běžící task nezastavovat.
- Nezavádět obecný framework pro několik podobných funkcí. Redukci počítat po odečtení nových helperů, testů a runtime závislostí.

## Rozšíření základu při realizaci

Na výslovné upřesnění uživatele je lokální základ rozšířen o otevřená PR #733 (`0185c3a68`), #734 (`4334fc5d7`) a #736 (`d9ec85229`). Změny jsou přeneseny jako diffy proti merge-base do odděleného checkoutu `92ee5c611`; nejde o GitHub merge ani publikaci. Překryv `web_client/package.json` a `pnpm-lock.yaml` byl spojen třícestně bez konfliktu. #733 mění setup a konfiguraci formulářů; jeho pravidla souhlasu a měření musí zůstat zachována. #734 mění Blueprint a SQL test runner; redukce nesmí vrátit jeho opravy. #736 mění startup a statické náhledy. Jejich přenesený diff se vykazuje odděleně od vlastní redukce. Aktuální origin/main je shodný s referenčním SHA plánu.

## Ověřené výchozí skutečnosti

| Skutečnost | Zdroj | Důsledek |
|---|---|---|
| Od večera 1. 11. (`cf20f9b6e`) do referenčního mainu je textový diff +254 240 / -51 232 řádků. `automation/historical-inputs` tvoří +152 888 textových řádků. | `git diff --numstat cf20f9b6e 92ee5c611` | Přibližně 75 % čistého textového přírůstku jsou historické vstupy. Nejde o měření executable LOC ani přenosové velikosti. |
| Pět měřicích skriptů má 88 / 119 / 119 / 54 / 63 řádků. Starý benchmark měří `get_notification_center_daily_overview`; nový měří připravené pohledy. | `automation/notification-center/{benchmark,prepared_benchmark,prepared_maintenance,sustained,prepared_sustained}.mjs` | Dvě generace scénářů; část odstranit, společnou mechaniku sjednotit. |
| Obě UI cesty kontaktu volají stejný `OrderCommands.repairEmail`, přes durable `ClientCommandTransport`. | `lib/components/eshop/order_commands.dart`, `OrderDetailController.saveDrafts`, `OrderEmailContactEditor._save/_recoverContact` | Backendový příkaz už je canonical. Duplicita je řízení UI stavu a výsledků, nikoli dva backendy. |
| Controller má 257 řádků; kontaktový editor 751. Editor má vlastní `_order/_summary`, generation, loading/stale/busy a současně externí controller/callbacky. | `lib/components/eshop/order_detail_controller.dart`, `views/order_email_repair_dialog.dart` | Sdílet kontaktovou relaci, zachovat oba hosty. Velikost widgetu sama není důvod k přepisu. |
| Setup nabízí 1 892 rodin; 10 explicitních voleb doplňuje defaultní Google faces z jediného immutable katalogu. | `automation/generate_setup_appearance_fonts.mjs`, `automation/tickets/setup-appearance-fonts.json`, `supabase/functions/_shared/ticket-assets/font-catalog.json` | Volby jsou politika, fontové bytes/ID vlastní katalog. Nesmí se odhadovat ID z názvu. |
| Dart mapa má 3 787 řádků, SQL lookup 1 899. Oba soubory generuje jeden skript. | `occasion_setup_font_ids.dart`, `occasion_setup/appearance_fonts.sql` | Nejsou to dvě ručně udržované implementace. SQL projekce má vlastní účel. |
| `TicketFontCatalog` již načítá stejný bundled katalog, cacheuje in-flight read a po chybě dovoluje retry. `FormFontCatalog` vlastní deferred Google Fonts pro náhled. | `lib/components/fonts/{ticket_font_catalog,form_font_catalog}.dart` | Rozšířit existující vlastníka; neslévat PDF identitu s runtime načítáním webových fontů. |
| Notifikační SQL má 31 souborů, celkem 3 178 řádků včetně README. Flutter používá `get_notification_center_view`, prepared badge, settings a muting. | `database/functions/notification_center/`, `notification_center_controller.dart` | Starší prezentační rozhraní jsou kandidáti, nikoli automaticky mrtvý celý modul. |
| Moderní otevření objednávek stále volá `notification_center_order_selection`, který používá starší visible selector a normalizaci ID. | `eshop_orders/get_orders_tab_data.sql`, `notification_center/order_selection.sql` | Nejdřív přesměrovat moderního konzumenta; nelze smazat starý selektor podle Flutter RPC inventáře. |
| `notification_center_dto` používá i `prepared_views`; `notification_center_batch_internal` používá `prepared_worker`; read receipts a frozen baseline jsou platná data. | `core.sql`, `read_state.sql`, `prepared_worker.sql`, `prepared_views.sql` | Tyto části zachovat jako shared owners. Označení legacy ve stored ID není důkaz mrtvého kódu. |
| Historický manifest registruje 1 102 cest z 10 revizí, 986 unikátních objektů, 17 318 036 bytes; žádný objekt neleží mimo manifest. | `automation/historical-inputs/manifest.json` a `objects/` | Manifestová dosažitelnost je ověřena; sémantickou potřebnost každého vstupu tím netvrdíme. |
| Python a Node čtou původní bytes se SHA256 kontrolou; baseline, migration assemblery a bezpečnostní testy jsou skuteční konzumenti. | `automation/historical_inputs.py`, `automation/lib/historical_inputs.mjs`, `baseline.py`, `database/tests/security/server_rpc_security.test.mjs` | Zachovat offline reprodukovatelnost, žádný návrat k `git show` původních odstraněných commitů. |

Čísla z předchozího rychlého průzkumu zahrnovala i starší pracovní strom. Výše uvedené počty jsou z čistého referenčního mainu. Testy ani produkční diagnostika během plánování neběžely.

## Cíloví vlastníci a invarianty

### 1. Měřicí nástroje

Jedna současná sada scénářů pod `automation/notification-center/`: benchmark připravených pohledů, sustained workload a údržba. Sdílený malý helper vlastní lokální/disposable kontrolu, připojení, fixture lifecycle a společné měření. Scénáře nadále explicitně vlastní své SQL, arrival model a kritéria připravenosti. Bez `legacy` přepínače a bez druhé implementace projector/delivery logiky; ta zůstává v SQL a `drain.mjs`.

### 2. Kontakt objednávky

`OrderCommands` a durable transport zůstávají jediným vstupem mutace. Jedna kontaktová relace v Dart vlastní potvrzený snapshot, editovaný e-mail, busy/stale, generation, pending intent a výsledek command/readback. Nový malý `OrderContactController` bude tuto relaci sdílet mezi detailem a samostatným dialogem; nevytvoří nový transport ani obecný formulářový framework.

- Detail vlastní jeden kontaktový controller a jeho lifetime; dialog si vytvoří vlastní instanci stejného typu a zlikviduje ji při zavření.
- Detailní snapshot dodává do kontaktové relace `get_order_admin_detail`; samostatný dialog zachová své současné autorizované readers. Jde o dva skutečné hosty stejného kontraktu, nikoli duplicitní business logiku.
- `save`, `save + resend` a recovery původního intentu mají odlišný záměr. Potvrzený commit a neúspěšný refresh jsou odlišné výsledky; refresh nesmí automaticky zopakovat příkaz ani odeslání.
- Globální save detailu nadále ukládá kontakt bez odeslání a pak inline změny postupně s obnoveným full-array fence. Po částečném úspěchu zůstávají dirty pouze nepotvrzené změny.
- Durable pending intent přežije zavření, discard i změnu UI. Recovery používá původní UUID a bytes. Server dál rozhoduje stav, payment fingerprint, suppression, práva a send guard.

### 3. Fonty

Immutable `font-catalog.json` vlastní face identity. Malý `setup-appearance-fonts.json` vlastní explicitní volby a jejich prioritu. `TicketFontCatalog` nabídne `loadSetupFonts()` nad těmito vstupy; současné načítání ticket editoru zůstane zachováno. `FormFontCatalog` dál řeší dostupnost a preview runtime fontu.

- Odstranit obrovskou odvozenou Dart mapu; neduplikovat ji jako obrovský nový JSON asset.
- Existující malou selection JSON přidat mezi bundled assets v `pubspec.yaml`; žádný síťový lookup ID.
- `loadSetupFonts()` zachová přesné pořadí a prioritu: explicitních 10 voleb, potom katalogové Google default faces pouze pro dosud nepřítomné rodiny. Výsledkem je immutable mapa. Chyba se necachuje natrvalo.
- Katalogově závislé `OccasionSetupAppearance.valid/apply` a výběr font ID dostanou explicitní mapu/instanci s mapou; stateless `read/selectPreset/ticketBackground` mohou zůstat statické. Žádný globální měnitelný registr ani implicitní prázdná mapa/fallback.
- Mapa se načte jednou pro setup relaci před první operací aplikující sdílený vzhled, spolu se stávající přípravou dat. Samotný build widgetu nepouští nové čtení. Zachovat loading/retry a ochranu před pozdní odpovědí po změně relace.
- Kopie s `preserveSource` zachová vlastní layout/ID bez přepsání na default. Nenačtený katalog nesmí tiše nahradit font; izolovat chybu výběru od uložení již platné nezměněné kopie.
- SQL lookup zůstává deterministickou generated projekcí pro synchronní `IMMUTABLE` normalizátor. Nevytvářet kvůli redukci řádků novou mutable DB tabulku, síťovou závislost nebo změnu volatility. Z generátoru odstranit pouze Dart output. Změna SQL bytes není cílem této vlny.

### 4. Notifikace

Canonical serving kontrakt: `get_notification_center_view` a `mark_notification_center_view_item_read`, prepared badge, settings, `set_notification_center_muted` a tokenem vázaný výběr objednávek. Publication, delivery, worker leases, live rights a source invalidation zůstávají stávající vlastníci.

- View token váže uživatele, organization, occasion, snapshot, frozen slots a sequence envelope. Cizí, expirovaný nebo kontextově chybný token nic neodhalí ani neoznačí za přečtené.
- Open jako jediný posouvá seen watermark; preview, page, refresh a preparing jej neposouvají. Read receipts zachovávají obě meze, mezery i opačné pořadí čtení z více tabů.
- Related orders se vyberou podle uloženého scope a captured membership, po aktuální autorizaci a privacy kontrole; žádné klientské ID pole jako náhrada.
- Shared DTO, subject visibility, order activity classification, receipts, source events a historický baseline zůstávají platnými součástmi. Přesun shared helpers do vlastního souboru slouží odpojení starého serving kódu, nikoli přidání wrapperu.
- Legacy veřejné RPC odstranit až po důkazu, že je nepoužívá žádný podporovaný klient. Do té doby nejde prohlásit celý cutover za dokončený.

### 5. Archiv, evidence a generované výstupy

Historické bytes mají jediného vlastníka: stávající SHA256 manifest a offline readers. Aplikované migrace se nepřepisují ani nesquashují. Veřejný generated MCP reference a publikované help výstupy jsou produkty generátorů, ne kandidáti na automatické smazání.

Výsledek této oblasti může být **ověřená retence bez změny formátu**, pokud soubory stále potřebují konzumenti. Prosté skrytí souborů nebo přesun do jiného adresáře se nepočítá jako redukce kódu. Diagnostické zkomprimování spojených raw objektů dalo přibližně 8,8 MB oproti 17,3 MB raw; není to validní odhad úspory Git packu a neodůvodňuje nový archivní loader.

## Upřesnění kompatibility při realizaci

Uživatel výslovně zrušil potřebu podpory starých klientů pro administrační
notifikace rezervací a změn objednávek. Následně upřesnil, že výjimka pro Slunovrat
znamená mobilní push zprávy posílané do Androidu/iPhonu, nikoli editor/admin
notification center. Starší zdroj `origin/prod/festivalslunovrat` sice obsahuje
legacy center RPC, ale tato rozhraní uživatel výslovně vyňal z požadavku podpory.
Vlna 5 je tím autorizovaná lokálně. Mobilní news/push cesta se nesmí měnit;
žádný tenant se nemění ani nenasazuje. Produkční rollout stále není zadán.

Při reálném běhu byly nalezeny dva zastaralé měřicí předpoklady: skrytí členství
nesnižuje oprávněné order totals a 29 prefix receipts se compactuje do jedné read
history plus unread řady. Současný maintenance scénář ověřuje tento canonical
kontrakt. Barevné vectors v preview manifestu obsahují oba palette colors; test
je proto porovnává s explicitním gradient režimem, nikoli implicitním solid.

## Rozhodnutí, předpoklady a blokující podmínky

- **D1:** Priorita: odstranit nepoužívané měřicí varianty, sjednotit kontaktový stav, odstranit runtime kopii katalogu; potom contraction notifikací. Rozdělení souborů bez úbytku odpovědností se nevykazuje jako úspora.
- **D2:** Místo plošného mazání použít seznam keep/migrate/delete/boundary a doklad chování i nedosažitelnosti pro každý odstraněný vstup.
- **D3:** Fontový SQL CASE a immutable migrační historie zůstávají. Jejich počet řádků se nesnižuje změnou formátování.
- **A1:** Aktuální zdrojový Flutter používá nový kontrakt. To je ověřeno pro main, nikoli pro všechny nainstalované klienty; provozní ověření řeší vlna 4.
- **A2:** Staré CLI benchmarky nemají registry/CI konzumenty v prohlédnutém mainu; při realizaci zopakovat cílené hledání aktuálních callers a aktivních runbooků. Staré datované receipts nejsou aktuální volání.
- **B1:** Není ověřena minimální podporovaná verze instalovaných klientů ani aktuální nasazení prepared API. Starší datovaný execution result výslovně popisuje lokální stav. Pro rozhodnutí o contraction získat aktuální release/usage důkazy, nikoli tvrdit stav podle tohoto README.
- **B2:** Není určen tenant ani objednán produkční rollout. Lokální implementace a migrační soubory mohou být hotové, produkční cutover zůstává samostatně neprovedený.

## Deletion ledger

| Artefakt | Akce a podmínka | Důkaz dokončení |
|---|---|---|
| Staré tělo `benchmark.mjs` (daily overview) a `sustained.mjs` (delivery-only) | Delete; současné připravené scénáře převést na tyto canonical názvy. | Žádný současný benchmark nevolá retired API; CLI scénáře a receipt fields mají očekávanou semantiku. |
| `prepared_benchmark.mjs`, `prepared_sustained.mjs`, `prepared_maintenance.mjs` | Migrate do `benchmark.mjs`, `sustained.mjs`, `maintenance_benchmark.mjs`; původní soubory odstranit. | Existuje jedna sada scénářů; současné docs/commands ukazují na ni. Historické receipts mohou jmenovat starý soubor. |
| Duplicitní connect/fixture/cleanup/timing bloky | Nahradit malým sdíleným helperem. | Scénáře neduplikují guard ani lifecycle; každý setup teardownuje jen vlastní ID i při chybě. |
| Kontaktové `_load/_save/_recoverContact`, snapshot, pending a generation řízení ve widgetu | Přestěhovat do jednoho kontaktového controlleru; odstranit souběžné vlastníky a externí busy/loadContext/revision callback protokol. | Detail i dialog používají jednu implementaci; widget vlastní jen prezentaci, focus a lokální validation display. |
| Přímá kontaktová orchestrace v `OrderDetailController.saveDrafts` | Volat sdílenou kontaktovou relaci. | Jedna implementace fences/result/recovery; globální save stále neposílá e-mail. |
| `occasion_setup_font_ids.dart` a jeho import/generovaný output | Delete po migraci všech callers na katalog. | Soubor/import ani fallback mapa neexistují; všechny 1 892 family-ID dvojice a pořadí souhlasí. |
| `appearance_fonts.sql` + 10 explicitních voleb | Keep jako SQL projekci a policy. | Generátor `--check` prokazuje SQL; test prokazuje shodu runtime projekce s policy/katalogem. |
| `get_notification_center_feed/page/group/updates`, `open_notification_center`, starý `get_notification_center_badge` | Delete ve forward contraction po vlně 4 a odpojení moderních závislostí. | Přesné overload signatures nejsou v `pg_proc`; žádný runtime caller, grant, registration ani current source je neobnovuje. |
| `get_notification_center_timeline`, `_timeline_group`, `_timeline_group_updates`, `_overview`, `_daily_overview`, `mark_notification_center_item_read` | Stejné contraction; zrušit staré serialize/cursor/open/read implementace. | Aktualizované běžící testy netestují jejich existenci; cílená negative schema assertions a upgrade gate projdou. |
| `temporal_feed.sql`, `overview.sql`, `daily_overview.sql` | Delete, jakmile shared classification helper přestane bydlet v retired souboru a zmizí poslední interní závislost. | Shared helpers mají jediného vlastníka, source manifests a bootstrap retired soubory nenačítají. |
| `notification_center_visible_internal`, `notification_center_rollup_id_internal`, time cursor/period helpers | Delete pouze po přepsání moderního výběru objednávek a odstranění starých RPC. | PostgreSQL dependency inventory + current-source call map; žádné `DROP ... CASCADE`. |
| `notification_center_order_selection` | Keep názvu/kontraktu pro moderní výběr; odstranit branch pro scope bez tokenu po compatibility gate. | `get_orders_tab_data` používá tokenovou cestu a nový read owner, stejné results + fail-closed tests. |
| `notification_center_dto`, `notification_center_batch_internal`, `set_notification_center_muted`, read receipts/baseline | Keep; případně přesunout shared definice. | Prepared rendering/repair, muting a inherited receipts dál fungují. |
| Group-only sloupce/indexy | Candidate, nikoli předem schválené DROP. Dokázat nepoužití writerem, prepared backfillem, receipts i orders. | Bounded inventory pro každou položku; pokud zůstane doménová potřeba, keep s uvedeným konzumentem. |
| Staré notifikační tests/fixtures a baseline scénáře | Přenést relevantní invarianty na canonical API; odstranit výhradně obsolete presentation assertions. | Stejné producer/privacy/recovery/concurrency chyby jsou detekovatelné na novém seam. |
| Historické objects, aplikované migrace a datované receipts | Keep, pokud nejsou jednotlivě prokázány všechny zaniklé závislosti. | Exact bytes/hash a recovery/upgrade z čistého checkoutu bez původních Git commitů. |
| Aktuální README/manifests/CI/config | Migrate na surviving owners; datované důkazy neměnit zpětně. | Current docs nepopisují coexistence jako hotový cutover; historical exceptions jsou výslovné. |

## Prováděcí vlny

### Vlna 0 - Jednou změřit základ a zafixovat rozsah

**Změny:** V čistém aktuálním checkoutu zaznamenat SHA, čistotu a hodnoty z výchozí tabulky. Pro každou oblast oddělit hand-written runtime, generated data, tests, migrace a evidenci. Do stručného výsledku přidávat skutečné netto diffy, počet vlastníků a počet dosažitelných entry points.

**Ověření:** Zdrojový inventář a `git diff --numstat`, bez testování nezměněného baseline. Všechny chyby prostředí evidovat odděleně od změn.

**Exit:** Je jasné, co bude skutečně smazáno, co zůstává a na jakém SHA. Žádná cizí rozpracovaná práce nebyla přenesena.

### Vlna 1 - Jedna sada měřicích scénářů

**Změny:** Provést první tři řádky deletion ledgeru. Použít společný helper např. `automation/notification-center/benchmark_support.mjs`; připojení otevírat až při spuštění scénáře, nikoli při importu helperu. Zachovat nezávislá publisher/worker spojení sustained scénáře, timeouts, resume provenance a částečné receipts při timeoutu.

**Selhání:** Zadaný output ověřit před tvorbou fixtures. Cleanup musí fungovat i po částečném setup; spojení zavírat ve `finally`, obnovit původní claims pro úklid. Nejprve local URL i disposable marker, teprve potom zápisy. Nikdy nepřevést guard na obecný `allow remote` přepínač.

**Ověření:** Jedna dávka testů helperu pro remote/nesprávný marker, partial setup a exception cleanup. Současný scénář lokálně v nejmenší neprázdné velikosti, zachovat obsah/typy receipt fields a ověřit nulové vlastní zbytky. Pro parametrizaci velikosti použít již existující vstup, nebo přidat jen jednoduchý explicitní smoke preset se stejným chováním. Neopakovat 100k workload kvůli extrakci mechaniky.

**Exit:** Staré implementace zmizely a moderní benchmark, sustained a maintenance scénář fungují přes jednu mechaniku. Netto helper + scénáře má méně udržovaného kódu. Pokud extrakce přidává více orchestrace, zmenšit helper.

### Vlna 2 - Jeden vlastník kontaktové relace

**Změny:** Přidat `lib/components/eshop/order_contact_controller.dart`, přesunout do něj skutečně společný state a command-result/readback/recovery lifecycle. Zapojit `OrderDetailController` a `OrderEmailContactEditor`, upravit `order_detail_view.dart` a samostatný `OrderEmailRepairDialog`. Stávající `OrderCommands` zůstává beze změny wire protokolu. Obsah dialogu a detailu již sdílený je, ten nepřepisovat znovu.

**Odstranění:** Vymazat původní orchestrace a propojovací parametry po přepojení všech callers. `order_state_cell.dart` stále otevírá samostatný dialog; jej nelze smazat jako starou cestu. Čtení historie/plateb mimo kontakt ponechat.

**Selhání:** Controller musí zahazovat pozdní readback po změně order/occasion/dispose; celý detail nesmí držet dva editované e-maily. Nedokončené odeslání smí být vykázáno jako queued/unknown, nikdy jako jistý delivery success. Poll zůstává omezený na přesné message ID a současný budget. Globální save nesmí obejít pending uncertain intent.

**Ověření:** Cílená dávka `order_detail_save_changes_test.dart`, `order_email_repair_design_test.dart`, `order_detail_answers_test.dart` a existující command/recovery testy nalezené pod `test` podle `RecoverableOrderContactCommands`/`repair_order_email_client_sync_v1`. Rozšířit na sdíleném controlleru jen chybějící scénáře: commit + failed readback bez druhé mutace, stejný pending UUID po znovuotevření, 409, přepnutí occasion během requestu a save bez resend. Zkontrolovat dotčené Dart soubory cíleným analyzérem.

**Exit:** Jediný vlastník kontaktového state funguje v obou hostech. Žádný druhý transport ani retry/send engine. Stávající backend kontrakty a suppression nejsou oslabeny.

### Vlna 3 - Runtime setup fonty z existujícího katalogu

**Změny:** Rozšířit `TicketFontCatalog` o setup projekci; přidat pouze malou selection policy mezi assets. Nahradit statické map-dependent volání `OccasionSetupAppearance` explicitním kontextem. V `occasion_setup_page.dart` projít také volání mimo appearance panel: ticket preview, vytvoření výchozího layoutu a ukládání vzhledu. Změnit všechny test callers ve stejné vlně, žádný compatibility default parametr.

**Odstranění:** Smazat `occasion_setup_font_ids.dart`, jeho import a Dart větev `generate_setup_appearance_fonts.mjs`. SQL output zachovat byte-for-byte, pokud se nezměnila policy. `TicketFontCatalog.load()` pro ticket editor a deferred `FormFontCatalog` dál existují pro své odlišné účely.

**Ověření:** Před smazáním vytvořit v paměti oracle ze stávající mapy a porovnat všechny dvojice i pořadí s projekcí; oracle neponechat jako druhou produkční mapu. Upravit `occasion_setup_appearance_test.dart`, `occasion_setup_preview_performance_test.dart`, `occasion_setup_appearance_panel_test.dart` a doplnit retry/missing asset/nezměněnou copied custom layout cestu. `node automation/generate_setup_appearance_fonts.mjs --check` pro SQL. Ověřit asset deklaraci a offline načtení v testu. Neprovádět rebuild kompletního font katalogu a download fontů pro změnu readeru.

**Exit:** 1 892 voleb se stejnými ID, původní pořadí, žádná velká Dart mapa, žádný nový velký datový duplikát nebo síťový požadavek. SQL normalizace vzhledu zůstává canonical a nemění funkční kontrakt.

### Vlna 4 - Doklad kompatibility a odpojení moderních notifikací

**Změny:** Vytvořit konkrétní release inventory starých RPC: podporované Flutter/mobile/web verze a tenantové buildy, současný backend migration ledger a worker registrace, datum vydání moderního klienta. Pokud bude autorizováno provozní čtení, přistupovat přes `festapp-backend-access`, ověřit activation/tenant identity a použít existující verzi/logy. Neukládat kontakty ani token secrets do evidence.

**Compatibility gate:** Samotná nula v `pg_stat_statements`, krátké období bez trafficu nebo aktuální zdroj mainu nestačí. Vyžaduje se doložená minimální podporovaná verze a vyřešený přístup podporovaných starších klientů. Pokud zůstávají podporovaní konzumenti, zaznamenat přesné verze/RPC, vlastníka a konkrétní release podmínku odstranění. Nevymýšlet termín ani tichý force upgrade. Chybějící provozní autorita neblokuje ostatní lokální vlny, blokuje tvrzení o provozním dokončení contraction.

**Lokální příprava nezávislá na gate:** Oddělit shared helpers z `core/read_state/temporal_feed/daily_overview` podle skutečných callers. Přepsat tokenovou větev `notification_center_order_selection` tak, aby používala frozen prepared scope/membership a současnou live policy; musí vybrat celý captured group, nikoli pouze tři contact previews nebo první stránku. Přepojit tokenový mark-read v `get_orders_tab_data` přímo na canonical view read owner. Legacy branch zůstane jen do ověřeného odstranění jejích veřejných konzumentů, bez nové paralelní definice doménové policy.

**Ověření:** `prepared_orders`, `prepared_history`, `prepared_scope_authority`, `prepared_wide_scope`, `hidden_identity_surfaces` a read-cursor concurrency scénáře. Porovnat related-order IDs před/po pro stejný token, read/batch/self/inherited rozsah a pozdější nové přírůstky. Neplatný/cizí/expirující token, ztráta práv a hide/unhide nesmí vracet širší množinu. Ověřit lease release až po úspěšném orders response a žádný mark-read při chybě výběru.

**Exit:** Moderní cesta už nepotřebuje retired selector/serializer. Existuje konkrétní doklad dovolující contraction, nebo přesný otevřený compatibility blocker. Žádný blocker se nepřekryje popisem „cutover hotov“.

### Vlna 5 - Forward contraction a skutečné smazání

**Změny:** Po splnění gate připravit jednu novou forward migration za aktuálním nejvyšším timestampem. Přesné overload signatures vypsat z čerstvé lokální DB a katalogu; explicitní DROP v opačném pořadí závislostí. Žádný `CASCADE`, žádný přepis dříve aplikované migrace. Source canonical definice, grants a runtime calls odstranit ve stejné koherentní změně. Aktualizovat `automation/notification-center-feed-manifest.json`, assembler, `database/tables/tables.sql`, canonical operation/source contracts a generované parity kontrakty podle skutečných změn.

**Důležitý bootstrap detail:** Staré migrace při fresh install dočasně vytvoří staré RPC, nová migration je na konci odstraní. Jejich výskyt v immutable historii je záměrný. Současné generátory ani kanonické source manifests je ale nesmějí znovu vytvořit při dalším vydání. `assemble-notification-center-migration.py` má dosud prerequisite kontrolu na `get_notification_center_updates`; přepsat současnou prerequisite kontrolu na skutečný surviving schema contract a otestovat odmítnutí chybějícího prerequisites. Neměnit historické digesty jen proto, aby test prošel.

**Datová contraction:** `read_through_sequence`, `notification_center_read_batches`, `:legacy`/`:self` identity a group keys nemazat jen podle názvu. Pokud je jejich odstranění skutečně potřeba, nejdříve explicitní převod každého baseline na stejné range receipts, idempotentní backfill a důkaz stejného read/seen. Tento plán takový datový převod nevyžaduje; cílem je odstranit starou implementaci, ne platnou historii. Group-only indexy/sloupce odstraňovat pouze s doloženým nulovým moderním využitím.

**Testy a docs:** Staré prezentační testy přepsat na canonical API tam, kde ověřují stále platnou vlastnost, jinak odstranit. Zachovat historické upgrade fixtures, pokud jimi prochází predecessor migration. Aktualizovat README, aktuální test registrace a generovaný source contract: `python3 automation/generate_canonical_source_contract.py` a následně `--check` po stabilizaci zdrojů. Staré DTO/helpers, které moderní serving používá, zůstávají pouze jednou.

**Ověření:** Disposable fresh reset i upgrade z bezprostředního predecessor state na stejný výsledný schema/function/grant stav. `node web_client/scripts/run_db_tests.js notification_center` a repository concurrency entry points; source parity, privileges a negative `to_regprocedure` assertions pro všechny retired signatures. Dále assemblery `--check`. Žádný test nesmí vyžadovat znovuvytvoření odstraněného current kontraktu. Před source publication použít affected canonical CI mirror lanes uvedené níže.

**Exit:** V lokální výsledné DB nejsou stará RPC ani jejich grants, current source je neobnovuje a moderní chování včetně historie/privacy/concurrency prochází. Produkční stav se vykazuje zvlášť. Pokud compatibility gate není splněn, contraction lze připravit izolovaně, ale nesmí být automaticky zahrnuta do běžně aplikovaného migračního řetězce a publikována jako hotová.

### Vlna 6 - Archivní podklady a závěrečný doklad redukce

**Změny:** Doplnit stručnou mapu kategorií a skutečných konzumentů do `automation/historical-inputs/README.md`, bez katalogu všech 986 souborů. Oddělit current installable sources od fixtures. Prověřit každého kandidáta na odstranění vůči Python/Node readers, `source_paths/materialize`, baseline/historical manifests, assemblers, security/predecessor tests a capture tooling. Registrace v manifestu není sama runtime použití; absence přímého string match není sama důkaz nepoužití.

**Rozhodnutí pro současný inventář:** Žádné hromadné stěhování, komprimování, squash migrací ani mazání raw objektů. Pokud se pro konkrétní snapshot prokáže nulový konzument včetně podporovaného recovery scénáře, odstranit jeho mapping a teprve potom objekty bez dalších referencí, s doloženými hashy původních bytes. Recovery bundle mimo repo nenahrazuje podporovaný offline install/upgrade kontrakt. Pokud takový kandidát nevznikne, výsledek této vlny je explicitní keep s důvodem, nikoli nový loader.

**Ověření při změně historických vstupů:** `python3 automation/baseline.py check`, `python3 -m unittest discover -s automation/tests -p 'test_historical_inputs.py'`, existující Python i Node konzumenti nad čistou kopií bez původních historických commitů a ověření všech manifestových SHA256. Zachovat přesné line endings, corruption rejection, neznámý revision/path rejection a zákaz fallbacku na current sources. Pokud se mění pouze vysvětlení v README, tyto runtime testy znovu nespouštět.

**Exit:** Každé smazání je skutečná retirement, žádný podporovaný recovery vstup není ztracen. V krátkém execution result uvést netto změnu ručního runtime kódu zvlášť od generated, fixtures a dokumentace, počet sjednocených vlastníků, odstraněné entry points, test evidence a provozní kroky, které ještě neproběhly.

## Úsporné pořadí a validace

| Oblast | Priorita / relativní náročnost | Realistický přínos a limit |
|---|---|---|
| Měřicí skripty | 1 / malá | Odstranit 142 řádků starých scénářů a část duplicity; netto zisk sníží nový helper/testy. Nejde o produktovou změnu. |
| Kontakt objednávky | 2 / střední | Zanikne jeden vlastník state a callback protokol; velikost netto úspory určit z hotového diffu, předem ji neslibovat. |
| Setup fonty | 3 / střední | Odstranit 3 787 řádků generated Dart projekce, po odečtení malého runtime readeru a callers. Přínos je sjednocení katalogového načítání; nezapočítávat to jako odstranění 3 787 řádků ruční business logiky. |
| Notifikace | 4 / velká, compatibility gate | Retire 12 veřejných názvů RPC z ledgeru a jejich výhradní prezentační implementace. Počet řádků neodvozovat z celých 3 178 řádků modulu, velká část zůstává potřebná. |
| Archiv/generované podklady | 5 / malá pro mapu, větší pouze při konkrétním retirement | Výchozí záměr je zachovat podporované recovery. Žádný slíbený úbytek 153 tisíc řádků; přesun ani komprese nejsou runtime redukce. |

Vlny 1-3 lze implementovat nezávisle; dělat je postupně, batchovat související edits a jejich cílené testy. Vlna 4 odemyká 5; změny kontaktů a fontů na ni nečekají. Při každé vlně přidat jen testy skutečných invariantů, nikoli testy názvů privátních helperů či lokalizovaného textu. Žádný browser/deploy během plánování.

| Změna | Nejlevnější průkazná kontrola během implementace | Před publikací |
|---|---|---|
| Měřicí mechanika | Testy guard/cleanup a neprázdný lokální smoke skutečného scénáře | Příslušnou mirror lane vybrat podle aktuálního `automation/ci/checks.json`; nepřidávat benchmark do běžného CI jen kvůli refaktoru. |
| Kontaktový controller | Jedna cílená Flutter test dávka výše, `--concurrency=1`; úzký analyzer | Affected `client-contract`/`navigation-interactions`; ověřit, že dotčené testy lane opravdu obsahuje, případně doplnit canonical seznam. |
| Font projection | SQL generator check + katalog/asset/setup testy v jedné dávce | `ticket-preview-and-delivery` a další skutečně affected lane podle assets/config dopadu. |
| Notification SQL | Local reset + predecessor upgrade, notification SQL/concurrency, source/grant parity | `seat-checkout`, `ticket-preview-and-delivery` a další skutečně affected lanes ze současné CI definice. |
| Historické vstupy | Hash/read/recovery tests pouze při změně vstupů/readers | Affected security/baseline lanes podle konzumentů; nezaměnit dokumentační úklid za změnu DB kontraktu. |

Affected lanes spouštět přes `./automation/test_ci.sh <lane...>`, s jediným společným soupisem v `automation/ci/checks.json`. Vlny mohou sdílet jeden závěrečný běh lane, pokud pokrývá finální nezměněný kód. Passing check neopakovat bez změny pokrytého kódu. Testy nebyly v rámci tohoto plánu spuštěny a jejich budoucí příkazy nejsou tvrzením, že dnes procházejí.

Při případném browser ověření delegovat izolovanou muted session Terra agentovi podle osobních pravidel a použít lokální disposable tenant. Nevyužít přihlášený uživatelský tab. Produkční build/deploy a monitoring později delegovat dle repository pravidel; není to součást implementace plánu.

## Produkční pořadí a rollback

1. Samostatně autorizovat tenant a rollout. Ověřit backend activation, skutečný migration ledger, worker stav a podporované verze. Neaplikovat všechny čekající migrace z tohoto starého pracovního stromu.
2. Publikace shared source musí splnit affected mirror lanes a pravidla branch protection. Před deployem všechny canonical GitHub CI jobs na přesném `baseMainSha` přes `automation/ci/release_gate.py`; cílené testy tento gate nenahrazují.
3. Nový klient a backend musí mít moderní kontrakt před contraction. Pokud to již aktuální produkce splňuje, doložit to a nevydávat zbytečně znovu. Samotný update webu nedokazuje aktualizaci mobile/cache klientů.
4. Pouze po compatibility gate aplikovat konkrétní schválenou forward contraction na canonical self-hosted backend a ověřit absence retired signatures i funkční moderní průchod. Nasazovat web lokálně přes `automation/deploy_direct.sh`, ne GitHub-hosted production build bez výslovného zadání.
5. Rollback UI-only refaktorů může vrátit zdroj před vydáním. Po DB contraction se nesmí vrátit klient vyžadující odstraněná RPC. Použít opravu současného kontraktu nebo předem prověřený kompatibilní artefakt. Obnovení retired rozhraní by byl samostatný incidentní zásah, nikoli skrytý standardní fallback.
6. Změna font readeru nemění katalogové bytes, veřejná font ID ani SQL normalizátor. Kontaktový refaktor nemění e-mailovou frontu nebo provider. Nepřidávat kvůli němu restart Edge runtime ani rozesílání z testu do produkce.

## Doklad dokončení

- [x] Všechny podporované vstupy míří na jednoho vlastníka dané odpovědnosti.
- [x] Měřicí scénáře nemají delivery-only/daily-overview alternativu ani legacy switch.
- [x] Kontakt má jednu implementaci lifecycle pro oba hosty, durable nejistota a resend pravidla jsou zachována.
- [x] Setup používá existující katalog, stará Dart mapa je smazána a SQL projekce i všechny family-ID volby jsou zachovány.
- [x] Moderní notifikační orders/read cesta nezávisí na retired RPC/selectorech.
- [x] Každé veřejné odstranění má doloženou compatibility gate; žádná neznámá populace klientů není označena za nepoužívanou.
- [x] Retired signatures nejsou v koncovém fresh/upgrade schema; current zdroje je neobnovují.
- [x] Platné receipts, baseline, vlastní aktivita, muting, privacy a live authorization zůstaly zachovány.
- [x] Historické vstupy/recovery fungují offline; immutable migrace a datované důkazy nejsou zpětně pozměněné.
- [x] Execution result rozlišuje lokální dokončení, publikaci, compatibility blocker a produkční stav.

Plný provozní cutover není hotový, pokud zůstává podporovaný legacy konzument nebo neaplikovaná produkční contraction. Lokálně dokončené nezávislé redukce tím nejsou znehodnoceny a mohou být vydány samostatně.
