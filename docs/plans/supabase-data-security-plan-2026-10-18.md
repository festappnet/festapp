# Supabase: uzavření datových mezer a dokončení dotčených klientských migrací

Datum: 2026-10-18  
Stav: Připraveno pro lokální implementaci; produkční kontrakce má níže uvedené vstupní podmínky  
Verification: standard  
Autoritativní plán pro databázové nálezy z auditu 2026-10-18 a jejich přímo související datové cesty.

## 1. Výsledek a hranice práce

Zachovat registraci, přihlašování a reset hesla, práci se skupinami a jejich místy, novinky a počty nepřečtených zpráv, veřejné formuláře, nastavení akcí a emailové šablony. Současně odstranit přístupy k cizím datům a historické zapisovací vstupy obcházející současnou autorizaci. Oprava zahrnuje klienty, RPC, efektivní ACL/RLS, synchronizované projekce i kontrolu skutečného nasazení.

**Rozsah:** DB01-DB06 z [auditu](../operations/security-audit-2026-10-18-database.md), dvě při plánování potvrzené související mezery DB07/DB08 níže, jejich klientské závislosti, nutné bezpečné kompatibilní hranice, výchozí granty a regresní ochrana. Žádná hromadná migrace všech přímých Supabase dotazů v celé aplikaci.

**Mimo rozsah:** nová synchronizační architektura, změna protocol 1, plošné přejmenování `*_v1`, přestavba Auth, změna modelu rolí či pozvánek, přesun zákaznických dat, mazání historických migračních souborů, XSS/CSP opravy ze samostatného webového plánu, infrastruktura/backup/PITR a jiná dřívější serverová doporučení. Již opravené serverové nálezy z 2026-10-16 se znovu neimplementují.

V tomto zadání je autorizován plán. Implementace, produkční migrace, nasazení, commit a push nejsou jeho vytvořením provedeny ani autorizovány. Budoucí release míří na nyní vybraný tenant `festapp`, organizaci 1 a nanejvýš `prod/festapp`; další tenantové buildy/pushe neprovádět. Sdílená databázová ACL/RLS mají dopad na všechny organizace téže DB, proto musí být tento dopad výslovně součástí schváleného produkčního kroku, i když se nasazuje jediný web.

## 2. Pevný bod a ověřená fakta

- Autoritativní main při průzkumu: `8b1420ea1da7349db68b4a293bb37da049fb9047`; `prod/festapp`: `0a8876868b8935d24231fafce599a22a8aadeb77`. Vzdálené reference ověřeny přes `git ls-remote`.
- Aktuální pracovní větev `feat/occasion-setup-wizard-20261007`, HEAD `eb23047248d59bf86345b9e0b79db4a988275231`, obsahuje rozsáhlé cizí rozpracované změny. **Nevycházet implementačně z tohoto diffu ani jej přepisovat.** První implementační krok je aktuální čistý main v izolovaném worktree a porovnání s tímto pevným bodem. Níže uvedené cesty mohou v dnešním starším checkoutu chybět, ale na main existují.
- Kanonický runtime: tenant `festapp`, generation 1, organizace 1, `https://api.festapp.net`; aktivace na `https://live.festapp.net/backend-activation.json`. Ověřena shoda SSH hostu, runtime DB, chráněných target assertions, `current_database()` a existence organizace 1. Pro další produkční práci znovu použít projektový `festapp-backend-access`, nikoli cloudové fallback projekty.
- Auditní důkazy: [definice, katalog, čtecí reprodukce a výsledky](../operations/security-audit-2026-10-18-db/). Nálezy nejsou založeny jen na migračním ledgeru.
- Živé katalogové počty jsou inventář, nikoli úplný bezpečnostní důkaz: 679 public SECURITY DEFINER; 218 s anon EXECUTE a 431 s authenticated EXECUTE.

| Oblast | Ověřený stav | Důsledek pro plán |
|---|---|---|
| DB01, hesla | Historická `set_user_password(uuid,bigint,text)` projde pro existujícího manažera a administrátora jako cíl, kde `get_can_reset_user_password(uuid)` vrátí false. Neplatný argument dosáhne veřejného RPC. | Nejprve uzavřít starý vstup; nepřepisovat správnou hierarchii podle staré funkce. |
| DB02, účty | `create_user_in_organization_with_data(bigint,text,text,jsonb)` je anon SECURITY DEFINER bez účinné registrační kontroly. | Uzavřít veřejnou cestu a prozkoumat konkrétní další Auth zapisovače ve stejné vlně. |
| DB03, skupiny | Živé tabulky povolují authenticated `USING(true)`. Main už v `DbGroups` používá příkazové RPC a editor bundle. | Dokončenou migraci nepřepisovat z lokální větve; odstranit průchod tabulkou, nikoli stavět další skupinovou implementaci. |
| DB04, novinky | `user_news` je anonymně čitelná, přestože `private_news` je privátní projekce. Main `DbNews` stále obsahuje přímé čtení a zápisy a pomocné metody mimo přepnutí synchronizace. | Vyřešit zbývající skutečné čtenáře před konečným odebráním potřebných oprávnění. |
| DB05, akce | REST vrací skryté akce. `DbOccasions.getOccasion` i `DbUsers.getOccasion` čtou tabulku; volají je nastavení, kopie/demo, inventář a rozvrh. | Nenahradit všechny čtenáře editor-only RPC; některé cesty potřebuje běžný účastník. |
| DB06, šablony | Přímý SELECT používá `get_is_manager_on_any_occasion()`, bez scope čtené šablony. Klient `DbEmailTemplates` už používá RPC. | Nezavádět nový klientský loader; odebrat bypass a zachovat existující dědičnost šablon. |
| Kompatibilita | `ClientSyncRuntime.isV1Selected` se řídí capability z modelu, nikoli předpokladem, že všechny akce už používají sync. | Neodstraňovat globálně legacy režim a nezapínat automaticky sync na všech akcích. |
| Nasazené bezpečnostní zdroje | Main má `database/functions/security/*`, manifest a samostatné drivere; část není ve starém lokálním checkoutu. | Rozšířit existující smlouvy a přidat nové dopředné migrace; nepřegenerovat již aplikované fáze z 2026-10-16. |

### Dodatečné potvrzení při plánování

**DB07 - Členské skupinové RPC vrací celý cizí profil.** `database/functions/groups/group_member_read.sql`, `get_user_group_info_with_users(bigint)`, vrací u účastníků `row_to_json(p_ui)`. V živé databázi byl vybrán skutečný řadový člen skupiny bez editor_view; čtecí volání s jeho claims v `BEGIN READ ONLY` vrátilo účastnické objekty obsahující klíče z množiny `phone`, `birth_date`, `email_delivery`, `data`. Zaznamenán pouze boolean `response_contains_private_fields=true`, nikoli hodnoty. Potvrzen je nadbytečný rozsah odpovědi; nenulový obsah všech těchto polí se netvrdí. Kanonická privátní projekce v `database/functions/groups/group_profile_read.sql` už u spolučlenů používá užší jméno/příjmení/UUID. Náprava patří do stejné skupinové vlny.

**DB08 - Anonymní čtení skrytých skupinových míst.** Živý anon SELECT na `places` spojený pouze s `occasions` našel v organizaci 1 řádky s `is_hidden=true AND type='group'`. Zdroj skupinových příkazů tento typ místa označuje za privátní skupinovou lokaci. Zaznamenán jen boolean `visible=true`. Původní varianta sondy s JOIN do `user_group_info` vrátila false, protože anon tuto tabulku nevidí; tento výsledek není důkazem ochrany `places`. Zúžení jen skupinových tabulek by tuto další cestu nechalo otevřenou.

Tyto dvě položky jsou nové vůči původnímu šestibodovému reportu. Podrobnosti dalších obsahových tabulek (`information`, `speakers`, `exclusive_groups/events` atd.) jsou kandidáti pro omezené prověření ve vlně 0/3, nikoli automaticky potvrzený únik nebo pokyn k plošnému zákazu veřejného obsahu.

## 3. Cílové kontrakty a invarianty

### Vlastníci operací

| Operace | Jediný zamýšlený vlastník | Výstup / omezení |
|---|---|---|
| Změna hesla | Existující `reset_user_password`, společná `get_can_reset_user_password`, příslušné token/scan vstupy s jejich vlastními důkazy | Zachovat současné odpovědi klientům, hierarchii, admission a žádné obnovení historického zapisovače. |
| Veřejná registrace | Edge `register` -> service-only `enqueue_account_email` -> registrační doména -> invoker `*_pure` | Doménový zápis a emailový intent atomicky; vypnutá/NULL registrace není veřejně povolená. |
| Správce vytváří účastníka | Existující `update_user_internal_v1` / profilové příkazy podle scope akce nebo jednotky | Odlišné oprávnění od veřejné registrace; absence veřejné registrace nesmí rozbít oprávněné přidání účastníka. |
| Skupinový editor / vedoucí | Existující `get_user_groups_editor_bundle_v1`, `get_user_group_editor_bundle_v1`, save/delete/assignment příkazy | Zachovat verze agregátů, idempotenci, zámky, soukromé místo a omezená práva vedoucího. |
| Člen čte svou skupinu | `get_user_group_info_with_users` a existující `private_profile.groups` | Stejné minimální peer DTO: UUID, jméno, příjmení a skupinová role. Vlastní úplný profil zůstává ve vlastní privátní projekci. |
| Novinky | Existující news příkazy, public katalog/agregáty, identity-scoped `private_news`; legacy veřejný seznam může být tenká fasáda | Cizí individuální markery nikdy nejsou veřejný výstup. Zachovat souhrnné views, pořadí, unread a offline stav. |
| Čtení kontextu akce | Stávající bootstrap/projekce a autorizovaný reader akce podle skutečného čtenáře | Veřejná allowlist projekce nebo oprávněný privátní/editor kontext. Nevracet celé `o.*` anonymovi. |
| Šablony | `get_all_email_templates`, `get_entity_email_templates` a existující resolver | Scope objektu odvozený v SQL, zachovaná globální/org/unit/occasion dědičnost. |

Nový veřejný reader přidat jen tam, kde současný kontrakt neumí existujícího legitimního čtenáře. Preferovaný konkrétní chybějící kontrakt je `public.get_occasion_for_context_v1(p_occasion bigint)` v `database/functions/others/get_occasion_for_context.sql`; nejprve ověřit, zda stejnou roli už nepokrývá aktuální main. Vrátit stabilní pole potřebná `OccasionModel`, bez interních vazeb a skrytých dat pro anonymní kontext. Autorizaci odvodit od objektu, členství a existujících práv; ne od klientem dodané organizace. Editor čte rozšířený editor bundle přes stávající reader, nikoli přes veřejnou projekci.

### Povinné invarianty

1. Manager jedné akce se nestává administrátorem organizace změnou hesla, ani nevytváří účty v cizím scope díky `get_is_manager_on_any_occasion()`.
2. Anon ani cizí authenticated nezískají přes tabulku, RPC, GraphQL nebo synchronizační výstup privátní členství, markery či skupinová místa.
3. Běžný člen vidí svou skupinu a minimální peer údaje; editor a vedoucí nadále vykonají přesně své dosavadní povolené činnosti.
4. JSON response allowlist nahrazuje `row_to_json(user_info)` u peerů. Nezměnit ukládání profilů a nevymazávat jejich pole z DB.
5. Výchozí ACL nového objektu neudělí klientům automaticky práva. Každý potřebný existující veřejný kontrakt dostane explicitní grant a politiku.
6. `is_hidden` a `is_open` se nezaměňují s univerzální autentizační politikou. Skryté akce nesmějí být globálně vylistovatelné, ale platný veřejný odkaz na otevřený formulář si zachová současný povolený nákup/registraci. Uzavřený formulář zachová `header_off`.
7. Žádný klientský zápis do dotčených agregátů neobejde existující pozorování změn, revize a mutation receipts. Nepřidávat aplikační triggery, druhou frontu či druhý limiter.
8. `client_sync_v1` je existující verzovaný veřejný protokol. Náprava nesmí přejmenovat jeho drátové názvy, resetovat revize nebo zapnout/vypnout capability mimo její runbook.
9. Bezpečná stará klientská kompatibilita může zachovat pouze jedno delegující rozhraní nebo úzce scoped RLS čtení. Nemůže zachovat prokázaný neoprávněný přístup.
10. Autorizace se znovu ověřuje i při replayi příkazu po odebrání role/členství; receipts nesmí znovu vydat cizí privátní payload.

## 4. Kompatibilita a rozhodnutí, která nesmějí být domyšlena

**Rozhodnutí:** přímý přístup přes RLS není sám o sobě chyba. U již převedených domén je cílem odebrat nepotřebné tabulkové granty. Podporovaný starší klient může dočasně potřebovat bezpečný scoped SELECT, dokud se čtenář nepřevede. Konečný stav musí mít explicitní allowlist těchto hranic, nikoli obecný fallback.

**Otevřený bod A1:** neznáme seznam skutečně podporovaných vydaných Android/iOS buildů a jejich přímých čtenářů. Vlastník řešení: implementující agent ve vlně 0. Ověřit release metadata a zdroje příslušných buildů; aktuální `VERSION` v main ani dnešní web nejsou důkaz instalované mobilní verze. Telemetrie může doplnit užití, ale samotná absence nedávného requestu není důkazem, že cesta nemá podporovaného klienta.

Každá potřebná hranice má zápis do manifestu: přesná signatura/tabulka+sloupce, autorizace, podporované buildy, vlastník a měřitelná podmínka odstranění. Pokud podporu nelze zjistit, nepouštět nevratnou produkční kontrakci potřebných bezpečných čtení; lokální implementaci ostatních vln to neblokuje. Prokazatelně nebezpečné Auth cesty zabezpečit ihned po autorizaci releasu, případně zachovat stejnou signaturu jen jako delegaci se současnou autorizací. Neuchovávat původní nebezpečné tělo kvůli starému klientovi.

**A2:** obchodní význam volných polí skupin, soukromých míst a událostí není úplně popsán. Rozhodování o veřejném výstupu opřít o existující podporované readery a UI konzumenty, ne o pouhé názvy. Pokud pole používá legitimní člen, zachovat ho ve scoped DTO; neodstraňovat ho z uložených dat. Nejasné volné JSON pole nesmí automaticky přejít do veřejné allowlist projekce.

**A3:** role mohou patřit k různým organizacím než domovská `user_info.organization` kvůli sloučení. Scope oprávnění určovat z cílového objektu a skutečného členství. Nepoužívat domovskou organizaci jako univerzální zákaz legitimní přeshraniční role.

**Produkční blokery:** A1 pro destruktivní kontrakci a samostatná autorizace sdílené DB změny/releasu. Žádný z nich nevyžaduje zastavit přípravu kódu, migrací, regresních testů a dry-run důkazů.

## 5. Implementační vlny

### Vlna 0 - Ověřený základ, konečný seznam vstupů a podporovaných klientů

**Změny/příprava:** začít čistým aktuálním main; zaznamenat nový SHA a relevantní rozdíly od pevného bodu. Zachovat již sloučené skupinové a bezpečnostní změny. Přečíst aktuální `CLAUDE.md`, `docs/architecture/ai_context.md`, relevantní READMEs a tento plán v plném rozsahu.

Vytvořit strojově čitelný doplněk `database/functions/security/data_security_contracts.json`, propojený s existujícím security manifestem, který bude vlastnit přesnou množinu objektů a kompatibilních hranic tohoto plánu. Nezakládat paralelní obecný ACL systém.

Omezený průchod:

- V `pg_proc`, `pg_depend` i tělech PL/pgSQL najít všechny overloady `set_user_password`, `create_user_in_organization_with_data`, `create_user`, `create_user_with_data`, registračních wrapperů a veřejně dosažitelných interních Auth zapisovačů. `pg_depend` nestačí pro textové/dynamické volání. Odlišit invoker helper od definer fasády a skutečné efektivní granty od explicitního ACL.
- Trasovat `register -> enqueue_account_email -> create_user_from_registration`, `update_user_internal_v1 -> create_user_in_organization_with_data_ws`, import/reception/Google a token/scan reset. Nenarušit service-only interní volání odebráním jejich funkce.
- Pro DB03-DB08 zahrnout přesné čtenáře v Dart/JS, SQL wrappery, GraphQL dosažitelnost, `private_profile/private_news`, veřejný publisher a obsah již publikovaných projekcí. Rozšířit o konkrétní přidružené public SELECT politiky na `places`, `information`, `events`, `exclusive_groups/events` pouze tehdy, když obcházejí tutéž privátní/hidden hranici. U každé rozhodnout: veřejný katalog, scoped privátní obsah, nebo dosud neprokázaný kandidát.
- Zaznamenat podporované buildy, staré tvary odpovědí a příznaky capability. Ověřit skutečný canonical-mutation release gate a jeho minimum build; neměnit ho ani neobcházet kvůli testu.

**Validace:** katalogová/zdrojová evidence bez produkčních zápisů; srovnání main a live; každé rozšíření musí mít konkrétní zdroj nebo čtecí důkaz. V této vlně se nespouštějí produkční fixtures.

**Exit:** každá cesta má vlastníka a rozhodnutí keep/migrate/delete/bounded compatibility; žádná produkční kontrakce nepočítá s neznámým mobilním klientem.

### Vlna 1 - Uzavření Auth bypassů nezávislé na klientském read cutoveru

**Cíl:** DB01/DB02 nelze využít ani během dalších vln.

- Přidat kanonický zdroj `database/functions/security/data_security_auth.sql` a novou dopřednou migraci s unikátním pozdějším timestampem. Odebírat efektivní EXECUTE od PUBLIC, anon a authenticated u přesných starých signatur. DROP pouze bez neočekávaných závislostí, bez CASCADE; jinak nejprve zabezpečení a explicitní následná kontrakce.
- Staré `set_user_password(uuid,bigint,text)` bez podporovaného volajícího odstranit. Nutná historická signatura smí pouze delegovat do současné kontrolované cesty a zachovat bezpečný výstup, nikoli kopírovat bcrypt/update. Otestovat actual target hierarchy, sebeobsluhu a ordinary participant reset. Token/scan důkaz nelze nahradit pouhou rolí manažera.
- Nepoužívaný `create_user_in_organization_with_data` odstranit. `create_user` a `create_user_with_data` vyřadit nebo zabezpečit podle skutečné dosažitelnosti a podporovaných klientů; existence registračního wrapperu není důvod ponechat alternativní přímý Auth zápis.
- `create_user_from_registration` ponechat interním service-owned registračním procesům; klientům zrušit přímé EXECUTE. NULL/false registrační politika se musí vyhodnotit jako zakázaná veřejná registrace. `get_is_manager_on_any_occasion()` nesmí být registrační oprávnění do jiného scope.
- Oddělit oprávněné vytvoření uživatele správcem od veřejné registrace. `create_user_in_organization_with_data_ws` dnes volá i `update_user_internal_v1`; nenahradit ho prostým service-role-only checkem, který by tento legitimní tok zablokoval. Zpřístupnit interní vytvoření pouze přes již scoped a autorizovaný rodičovský příkaz, nebo zachovat přesnou bezpečnou fasádu pro doloženého klienta. Mrtvou `DbUsers.unsafeCreateUser` odstranit až po potvrzení všech volajících.
- Převzít admission a `email_messages` kontrakt; nevytvářet uživatele či email mimo současnou atomickou doménovou operaci tam, kde ji stávající tok vyžaduje. Zkontrolovat efektivní možnost klienta spouštět invoker helper: samotný EXECUTE není Auth INSERT oprávnění.

**Kompatibilita/selhání:** žádné resetování skutečných hesel při ověření. Oprávněné správcovské vytvoření, CSV/import, reception, Google a registrační inicializace jednotky musí zůstat funkční. Registrace po timeoutu znovu nesmí vytvořit účet/jednotku/email, pokud už existuje receipt nebo nevyřešený intent. Nepřidávat nový password transport do veřejného readeru.

**Validace:** izolované role+identity testy Auth ACL a hierarchie; skutečná registrace se stubovaným senderem přes existující frontu; false/NULL/missing org, cizí manager, běžný správce cílového scope. Rozšířit `reset_user_password_permissions_test.sql`, registrační a emailové testy a nový `data_security_auth_test.sql`.

**Exit:** není veřejně dosažitelný legacy Auth zapisovač bez současné autorizace; legitimní entrypointy mají pozitivní test. Fázi lze samostatně připravit a později autorizovaně nasadit bez čekání na read migraci.

### Vlna 2 - Doplnění readerů a převedení zbývajících klientů

**Cíl:** současný klient už nepotřebuje nebezpečné tabulkové cesty; žádný pokus s novým RPC a fallbackem na původní široký SELECT.

- `lib/components/news/db_news.dart`: převést `getLastReadMessage`, `setLatestMessageAsRead`, `countNewMessages` a `getAllNewsMessages` na existující projekce v sync režimu; doplnit odpovídající bezpečný RPC read v non-sync režimu, pokud není dostupný. Převést zbylé delete/insert/mark-read větve na existující news command owner. Zachovat chování non-sync akcí; ověřit, že zvolené commands nevyžadují dosud neaktivovanou capability.
- `news_commands.dart`: používat stávající příkazy a jejich command ID/transport. Posun markeru řešit atomicky; nikdy klientské DELETE+INSERT. Stanovit podle dosavadního kontraktu, zda explicitní nižší marker smí snížit přečtení; běžný opožděný retry nesmí vrátit stav zpět.
- `lib/components/occasion/db_occasions.dart: getOccasion`, `lib/components/users/db_users.dart: getOccasion`: odstranit duplicitu dotazu a zavést společný reader kontextu. Call sites: `occasion_settings_tab.dart`, `demo_occasion_banner.dart`, duplicitační workflow, `inventory_pool_settings_view.dart`, `schedule_content.dart`. Editorové získávají editor bundle; legitimní účastník veřejnou/scoped projekci. Testovat čerstvě vytvořenou skrytou kopii ještě před publikací.
- `lib/components/groups/db_groups.dart` na main již má RPC owner: zachovat jej. Zmapovat mapové `getGroupsWithPlaces`, vedoucího skupiny a správu účastníků přes existující read/command kontrakty; nereintrodukovat přímé write větve ze starého checkoutu. Pokud se potřebná kompatibilní větev sloučila mezitím, řešit ji explicitně a ve stejné implementaci.
- `DbEmailTemplates` zůstane na existujících RPC. Žádný nový klientský table fallback.

**Kompatibilita/selhání:** nezměnit protokol ani přepínač `isV1Selected` mimo dotčené implementace. Respektovat `canonical_mutation_write_release_gate`; nízký build se nesmí obejít legacy DML. Odpovědi nových readerů musí projít existujícími parsery. Chyba sítě nesmí zahodit poslední úplnou cache nebo přepnout klienta na cizí tenant.

**Validace:** cílené adapter/unit testy pro obě capability, načtení kopie a příkazové mutation replacement; analyzer dotčených souborů. Bounded client journeys se testují až s připravenými kontrakty, nikoli po každém editování.

**Exit:** main nemá nepřiznaného přímého čtenáře/zapisovače dotčených privátních tabulek. Všechna bezpečná starší rozhraní jsou v manifestu s konkrétní podmínkou odstranění.

### Vlna 3 - Scoped RLS a minimální odpovědi, včetně vedlejších cest

**Cíl:** DB03-DB08 uzavřené přes všechny ověřené cesty.

- Kanonický zdroj `database/functions/security/data_security_reads.sql` a deklarace `database/policies/02_policies.sql` musí vyjadřovat stejný cílový stav. Odstranit skutečnou živou `user_news` politiku `select for all`, přestože není v dnešním kanonickém souboru. Přidat explicitní DROP v dopředné migraci; upravit test bootstrap i upgraded DB.
- `user_group_info/user_groups`: odstranit permissive authenticated true. Je-li podporovaný klient bez tabulkového přístupu, granty odebrat; jinak jen explicitní scoped SELECT pro editor_view nebo skutečného člena příslušné skupiny. Žádný veřejný zápis. Nepřidávat RLS cyklus vzájemnými subquery mezi oběma tabulkami: použít existující ověřený predicate nebo úzký definer boolean helper s `auth.uid()` uvnitř, explicitním search_path a bez volitelného cizího user ID. Testovat jeho klientskou dosažitelnost také jako RPC.
- `group_member_read.sql`: nahradit `row_to_json(p_ui)` allowlist objektem `{id,name,surname}`. Zachovat vnější klíče `user_groups[].user_info` a `is_admin`, aby parsování zůstalo funkční. Další peer pole přidat jen s doloženým legitimním konzumentem a vlastní autorizací. Totéž pravidlo u wrapperů a mutačních replay odpovědí. Kompletní vlastní profil neměnit.
- `places`: anonymní a veřejné čtení nesmí zahrnout skryté skupinové lokace; scoped člen/editor je získá přes skupinový DTO. Zkontrolovat `DbPlaces.getPlace/getPlacesIn/getAllPlaces` a veřejné mapové projekce. Nepřenést soukromou lokaci do veřejného public head nebo cache. Ostatní veřejná místa, úklid a mapa nadále fungují podle současného kontraktu.
- `user_news`: veřejně jen agregát; vlastní marker přes privátní projekci/RPC. Starší přesně filtrované vlastní čtení může mít dočasnou bezpečnou RLS hranici. Editorův souhrn nesmí potřebovat přímý výpis všech UUID.
- `occasions`: široký PUBLIC true nahradit allowlist veřejných řádků/sloupců nebo zrušit SELECT podle dokončené klientské migrace. Udržet autorizované admin/účastnické čtení a validní veřejný formulářový odkaz; veřejný reader a filtr seznamu nejsou editor API. Nevracet interní `occasion_hidden` vazbu a nekontrolované `data/services` veřejně jen kvůli starému `select(*)`.
- `email_templates`: zrušit globální manager větev. Ideálně zrušit klientský SELECT, pokud v inventáři nezůstává potřebný čtenář. Případné kompatibilní RLS používat podle scope konkrétního override; globální template čtení povolit jen v již oprávněném řešení šablon, ne všem manažerům automaticky.
- U přidružených obsahových tabulek opravit pouze ve vlně 0 potvrzené obcházení stejné hranice; vytvořit odpovídající scoped pozitivní test. Nezakazovat plošně veřejné novinky/katalog, který je záměrně veřejnou součástí aplikace.

**Migrace:** žádné mazání skupin, míst, markerů, šablon ani profilů. DML opravy dat pouze pokud se prokáže konkrétní nekonzistence a vznikne samostatně popsaný nutný forward repair. Měnit ACL a politiky v atomické fázi; dočasně nesmí vzniknout permissive true jako přechodový most.

**Validace:** role matrix anon / unrelated / ordinary member / group leader / editor_view / editor / manager / org admin / service role, dvě organizace a dvě akce, včetně legitimní cross-organization role. REST i GraphQL negativní testy na izolovaném backendu, RPC a private/public projekce. Test nesmí procházet jen jako postgres s RLS bypass.

**Exit:** negativní scénáře jsou odmítnuty a povolené scénáře vracejí stejná potřebná data; peer payload neobsahuje privátní profilové klíče. Kompatibilní hranice jsou bezpečné a explicitní.

### Vlna 4 - Výchozí ACL a kontrola efektivního stavu

**Cíl:** další migrace automaticky neotevře stejnou chybu.

- Rozšířit existující `server_security_acl_manifest.json`, `definer_contracts.json` a runtime `audit-security-state.sql` o přesné kontrakty nových vln. Propojit `data_security_contracts.json`; neduplikovat protichůdné seznamy.
- U skutečných vlastníků vytvářejících aplikační objekty odebrat výchozí klientské granty pro nové tabulky/sekvence/funkce v `public/eshop`, přidávat jen explicitní potřebná oprávnění. U funkcí zohlednit i globální implicitní PUBLIC EXECUTE: jeho výchozí grant nelze účinně odstranit jen per-schema REVOKE. Inventarizovat `pg_default_acl` podle role vlastníka a schématu, nikoli předpokládat jediného ownera.
- Neodebírat hromadně všechny existující granty bez inventáře jejich legitimních konzumentů. Není to migrace všeho Supabase API na RPC. Zachovat auth/storage servisní role i nutné sequence usage skutečných interních zapisovačů.
- Odstranit klientský TRUNCATE a další nevyužitá DDL oprávnění také na potvrzených třech Storage tabulkách po ověření vlastnictví a servisních závislostí. Storage objekty jsou vendor-managed; neměnit jejich business schéma nebo servisní privilegia. Nevydávat současný TRUNCATE grant za prokázaný veřejný HTTP exploit.
- Test vytvoří v izolované DB dočasný nový objekt pod reálným vlastníkem a ověří, že anon/authenticated nemají nechtěné oprávnění. Zvlášť ověří potřebný explicitně grantovaný veřejný kontrakt. `has_function_privilege` musí zachytit i dědění přes PUBLIC, ne jen proacl text.
- Nové migrační balíčky generovat deterministicky do nových verzí. Stávající `assemble-server-security-migrations.py` přepisuje již známé fáze z 2026-10-16; pro tuto práci jej v zapisovacím režimu nepoužívat. Přidat oddělený scoped assembler pro nové zdroje nebo bezpečně rozšířit generátor tak, aby staré výstupy zůstaly bajtově stejné.

**Validace:** grant/default-ACL kontrakty na fresh i upgrade DB, test driftu manifest/SQL, existující server security a group kontrakty. `--check` musí být skutečně bez vedlejšího přepisování starých artefaktů.

**Exit:** nový objekt je klientsky uzavřený bez explicitního kontraktu; runtime audit najde simulovaný návrat nebezpečného grantu/politiky, ale nehlásí záměrně veřejné funkce jako chybu jen podle počtu.

### Vlna 5 - Produkčně připravený balíček a autorizovaný rollout

Tato vlna se za nynějšího plánovacího zadání neprovádí. Implementující agent připraví k revizi konkrétní migrace, seznam fází/digestů, buildy, test evidence a kontrakční preflight. Nesmí nasadit celé nesouvisející pending migrations.

1. Obnovit target assertions, aktivaci, runtime katalog/ledger a source SHA. Zkontrolovat změny na authoritative main a překryv s webovým/security plánem. Zmrazit finální vstupy před buildem.
2. Autorizovaná Auth containment fáze může jít samostatně první. Nemá závislost na read cutoveru. Pokud je nutný podporovaný legacy Auth adapter, musí už od tohoto okamžiku vynucovat současnou autorizaci.
3. Nasadit aditivní bezpečné readery a potřebné backend opravy odpovědí, pak kompatibilní nové klienty. Pro peer JSON zúžení zachovat parserem požadované klíče; nečekat na klienta kvůli nepotřebnému citlivému poli.
4. Web vybraného tenantu: lokální Flutter + web client build a `automation/deploy_direct.sh`, nikoli GitHub build workflow bez výslovného požadavku. Zachovat main/tenant ancestry, drift a live version probes. Android/iOS vydání ani jiné tenanty nespouštět jen jako důsledek tohoto plánu; jejich potřebná vydání jsou zvláštní konkrétní krok.
5. Bezpečné scoped RLS může uzavřít neoprávněné čtení před konečným odebráním všech table grantů. Konečnou kontrakci pustit až po ověření podporovaných buildů/kontraktů, nikoli po libovolném čekání. Bez těchto důkazů vykázat pending přesnou bezpečnou hranici.
6. Každou SQL fázi aplikovat atomicky s ledgerem, kontrolou digestu, správnou vlastnickou rolí a PostgREST reload. Zachovat nezměněný mutation release gate, receipt tombstones a registry readiness nesouvisejících objektů. Použít kanonický SSH postup, ne cloud-only sync mutátory.
7. Po změně přečíst reálné definice, role politik a efektivní privilegia. Ověřit koherentní verzi webu a API výsledky; ledger sám nestačí. Produkční sondy zůstávají čtecí, bez ukládání payloadů a bez resetů/registrací. Pozitivní zapisovací journeys jsou důkaz z izolovaného prostředí.
8. Rutinní build/deploy monitoring a live-version ověření delegovat podle standing pravidel na levnějšího agenta; předat přesné frozen revize, tenant, oprávněné fáze a gates. Neposílat ho rozhodovat o nečekané migraci nebo rozšiřovat rollout.

**Exit:** efektivní runtime odpovídá manifestu; vybraný klient má pozitivní smoke evidence; nic nebylo prohlášeno za nasazené jen podle merge nebo úspěchu buildu.

## 6. Deletion ledger

| Objekt / větev | Konečná akce | Důkaz odstranění nebo záměrného ponechání |
|---|---|---|
| `set_user_password(uuid,bigint,text)` | DROP bez klienta; pouze doložený bezpečný delegující adapter může dočasně zůstat | Všechny overloady, závislosti a efektivní ACL; admin reset negativní test |
| `create_user_in_organization_with_data(bigint,text,text,jsonb)` | Odstranit po dependency gate | Žádný dnešní volající ani veřejně dosažitelný alternativní overload |
| `create_user/create_user_with_data` | Inventář a odstranění nepoužitých; případný podporovaný kontrakt přes současného vlastníka | Auth write graph a role testy, nikoli prostý výskyt jména |
| Přímý klientský `create_user_from_registration` | Zrušit EXECUTE; interní funkci ponechat registrační doméně | Registrace přes frontu funguje, anon RPC odmítnuto |
| Globální manažerská registrační výjimka a `unsafeCreateUser` | Scoped owner; mrtvý klientský helper odstranit | Pozitivní manager-create vs negativní foreign manager |
| Přímé privátní dotazy ve `DbNews` | Nahradit projekcí/command/RPC, odstranit duplicitní výpočty a DELETE+INSERT | Obě capability a offline/unread tests; žádný table fallback |
| Duplikované přímé `getOccasion` | Jeden reader/adaptér s oprávněním podle skutečné role | Nastavení, kopie/demo, inventář, rozvrh |
| Skupinové raw SELECT/DML ze starého checkoutu | Nevracet do main; pouze doložená bezpečná externí hranice smí zůstat v DB | Main call graph, canonical group tests, manifest |
| Globální SELECT politiky skupin, `user_news`, skrytých řádků a šablon | DROP/replace přesnými scoped kontrakty | Negativní REST/GraphQL/SQL/RPC tests |
| `row_to_json(user_info)` pro peers | Allowlist DTO | Test přesné sady polí, zachovaný parser |
| Přímá veřejná cesta ke skrytým skupinovým místům | Uzavřít, člen/editor přes skupinový reader | Anon direct GET/SQL i public projection negativní; scoped positive |
| Automatické default klientské granty | REVOKE pod skutečnými ownery; explicitní allowlist | Fresh-object a upgrade tests |
| Podporované starší read kontrakty | Jen bezpečné hranice s konkrétní podmínkou odstranění | Manifest včetně buildů; neoznačit za úplně odstraněné před splněním |
| Aplikované migrační historie a `client_sync_v1` protocol názvy | Ponechat | Bajtová neměnnost historie a kompatibilita protokolu |

## 7. Ověření a ochrana funkčnosti

Všechny zapisovací testy na izolované lokální Supabase DB. Před spuštěním runneru vynutit explicitní lokální `DATABASE_URL` a ověřit hostname/port/current_database; `.env.local` nesmí vybrat produkci. Použít existující bootstrap a SQL runner, nevytvářet druhý testovací systém. Runner hledá `**/*_test.sql`, přijímá více filtrů a při nule nalezených souborů končí úspěchem: záznam proto musí obsahovat skutečně nenulový počet a názvy provedených testů.

### Povinná behaviorální matice

| Riziko | Pozitivní funkčnost | Negativní důkaz |
|---|---|---|
| Hesla | Sebeobsluha, povolený reset běžného účastníka, platný reset token a scan podle současné politiky | Manager nesmí resetovat org admina/privilegovaný cizí účet; anon a NULL proof odmítnuty |
| Registrace | Zapnutá veřejná registrace, vytvoření účastníka správcem, unit init, Google/reception/import, idempotentní retry | Vypnutá/NULL registrace, cizí manager, přímé legacy/pure Auth zápisy bez potřebných grantů |
| Skupiny | Člen čte vlastní skupinu, vedoucí omezeně upraví, editor importuje a spravuje; soukromé místo i přidání/odebrání člena | Cizí skupina/akce/tenant, peer citlivé klíče, anonymní soukromé místo, replay po odebrání role |
| Novinky | Publikace, editace/smazání, read marker, unread badge, views, offline obnovení a non-sync akce | Cizí individuální marker, podvržený user ID, opožděný retry a chybné dvojí kumulování views |
| Akce/formuláře | Veřejný katalog, oprávněný účastník, nastavení, nová skrytá kopie, veřejný otevřený formulář na neveřejném seznamu, closed header | Enumerace skrytých akcí a vynesení interních polí přes veřejný reader |
| Šablony | Globální/org/unit/occasion dědičnost, lokalizace a waitlist/feature visibility, editace v oprávněném scope | Manager jiné akce bez potřebné role, smíšená hierarchie, přímý SELECT bypass |
| ACL | Funkční explicitně veřejný kontrakt a potřebný service role writer | Budoucí nový objekt, PUBLIC inheritance, TRUNCATE, neočekávaný overload |

Existující testy použít/rozšířit: `database/tests/users/reset_user_password_permissions_test.sql`, `database/tests/users/password_reset_token_expiry_test.sql`, `database/tests/eshop/reset_password_via_scan_authorization_test.sql`, `database/tests/auth/registration_db_test.sql`, `database/tests/groups/canonical_group_commands_test.sql`, `database/tests/get_email_templates_tenant_scope_test.sql`, `database/tests/emails/get_all_email_templates_test.sql`, `database/tests/emails/occasion_template_roundtrip_test.sql`, `database/tests/emails/waitlist_template_visibility_test.sql`, `database/tests/get_occasion_for_edit_tenant_scope_test.sql`, `database/tests/security/remediation_verification_test.sql` a příslušné `client_sync` kontrakty. Nové role/read/ACL scénáře v `database/tests/security/data_security_{auth,reads,defaults}_test.sql`; jejich názvy a skutečné provedení zaznamenat.

Příklady cílených příkazů po finálních změnách, s explicitně lokální DB:

```sh
node web_client/scripts/run_db_tests.js data_security_ reset_user_password_permissions password_reset_token_expiry reset_password_via_scan_authorization registration_db canonical_group_commands get_email_templates_tenant_scope get_all_email_templates occasion_template_roundtrip waitlist_template_visibility get_occasion_for_edit_tenant_scope
node automation/check_client_sync_registry.mjs
fvm dart analyze lib/components/news/db_news.dart lib/components/occasion/db_occasions.dart lib/components/users/db_users.dart
fvm flutter test --concurrency=2 test/sessions/shared_default_2_test.dart test/sessions/shared_default_3_test.dart
```

Uvedené Flutter roots podle `automation/client_test_classification.json` na pevném bodu skutečně zahrnují `groups_unit_cases.dart` a `news_unit_cases.dart`. Před použitím ověřit aktuální existenci a collector entrypointy na implementačním main; `_cases.dart` není samostatně automaticky objevený důkaz. Doplnit existující adapter testy unread/password flow a server-security manifest testy podle změněných kontraktů. Pro změny JS/Edge spustit jejich stávající cílené sady, nikoli automaticky veškerý frontend build po každém kroku.

UI smoke: izolovaný lokální tenant a účty s různými rolemi, existující projektový E2E workflow a `agent-browser` v headless izolované session. Ověřit členskou a editorovou skupinu, mapu soukromého místa, načtení/čtení novinek a badge, skrytou kopii/nastavení, veřejný formulář a šablony. Zavřít session. Neovládat uživatelův prohlížeč ani nevytvářet produkční fixtures. Pokud je později výslovně vyžadován release verification, přidat povinné plné release gates; nyní platí standard.

## 8. Rollback, migrace a cache

- Změny jsou nové dopředné migrace po refreshi aktuálního main a ledgeru. Needitovat dříve aplikované migrační verze. Zálohovat definice/ACL v chráněném release evidence úložišti; do veřejných artefaktů nevkládat osobní údaje nebo secrets.
- Každá nezávislá fáze má preconditions, digest, vlastní transakci a readback. Omezený lock/statement timeout; při nesplněném dependency/compatibility gate abort celé příslušné fáze, nikoli částečný grant repair.
- Rollback neobnoví permissive true ani nebezpečný Auth zapisovač. Při nefunkčním novém readeru dodat forward opravu nebo bezpečnou explicitní scoped hranici. Starý klientský build, který už potřebuje odebrané privilegium, není povolený rollback artefakt.
- Zúžení odpovědi nesmí vrátit privátní data přes starý cache fallback. Prověřit existující klíčování podle uživatele/akce a identity epoch v Sembast i web cache. U dotčených peer payloadů navrhnout cílenou lokální invalidaci/novou cache generation, pokud se skutečně cachují; nezmazat offline katalog ani čekající mutation receipts.
- Oprávnění nelze zpětně odebrat již staženým datům. Opravená aplikace je už nesmí znovu vydávat jinému kontextu. Pokud byl citlivý payload publikován do public R2/CDN, před kontrakcí je nutné konkrétní odstranění/obnova discovery podle sync runbooku a autorizovaný cache purge; neotáčet immutable pointer zpět ani nemazat bucket plošně. Samotný nový vyšší revision neprokazuje nedosažitelnost starého veřejného objektu.

## 9. Definice dokončení a zbývající rizika

- [ ] DB01-DB08 mají odpovídající změnu, pozitivní i negativní behaviorální důkaz; neověřené kandidáty nejsou vydávány za potvrzené nálezy.
- [ ] Současní klienti používají konkrétní vlastníky; zbytky přímých bezpečných přístupů jsou explicitně zdokumentované hranice, nikoli skryté fallbacky.
- [ ] Na fresh i upgrade DB jsou stejné efektivní ACL/RLS a stejné tvary odpovědí.
- [ ] Vydané podporované mobilní buildy mají doložený funkční kontrakt; žádná nebezpečná cesta se kvůli kompatibilitě nevrátila.
- [ ] Historické overloady a interní zapisovače nejsou veřejný bypass; definice, manifesty, bootstrap a forward migrace souhlasí.
- [ ] Skupinová místa, peery a markery neunikají tabulkou, RPC, replayem, GraphQL, sync projekcí nebo křížením cache identity.
- [ ] Cílené kontroly skutečně běžely na požadovaném počtu testů. Produkční readback je samostatně odlišen od lokální test evidence.
- [ ] Každý ponechaný adapter má konkrétního konzumenta a removal condition. Dokud existuje, nehlásit úplnou kontrakci.
- [ ] Při čistě implementačním předání jsou nepoužité produkční kroky výslovně pending. Za odstraněnou živou slabinu se nález označí až po autorizovaném nasazení a efektivním readbacku.

Zůstávají limity cíleného auditu: nejde o důkaz absence všech jiných zranitelností nebo historického zneužití. Podporu starých buildů nelze garantovat bez A1. Původní význam některých volných JSON polí může vyžadovat potvrzení konkrétního produktového chování; implementující agent má nejprve vyčerpat existující čtenáře a testy, nikoli změnit jeho význam odhadem. Samostatný XSS plán a dřívější provozní dluh mají jiné vlastníky a jejich stav nesmí být zaměňován za dokončení tohoto plánu.
