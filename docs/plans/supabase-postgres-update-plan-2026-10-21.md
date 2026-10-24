# Bezpečná aktualizace PostgreSQL a Supabase s minimálním výpadkem

Datum: 2026-10-21  
Stav: Plán připraven; realizace ani produkční změny nejsou tímto zadáním autorizovány.  
Ověřování při implementaci: standard; dodržet případné povinné release gates.  
Rozsah dosavadní práce: pouze čtení repozitáře, upstream dokumentace a diagnostického stavu serveru.

## Výsledek a doporučená varianta

Aktualizovat existující kanonický backend, zachovat všechna data, session, konfiguraci bezpečnosti a obnovitelnost. Zůstat na PostgreSQL 17, cílit na opravy 17.11 a ověřenou sadu Supabase self-hosted/v0.8.3. Produkční změna smí začít až s hotovými image, ověřenou obnovou, nacvičenými příkazy a změřeným servisním oknem. Tento dokument nic z toho neoznačuje za již provedené.

Doporučení je in-place aktualizace s krátkým řízeným přerušením API. Jeden primární PostgreSQL nelze aktualizovat bez restartu. Nezavádět nyní druhou databázovou autoritu ani replikační přepnutí pouze kvůli této aktualizaci. Většina přípravy proběhne za běžného provozu; v okně se pouze přepnou předem připravené artefakty a ověří dostupnost.

Pracovní rozpočet, nikoli naměřený slib: databázová nedostupnost 30-120 sekund, jednotlivé dotčené API služby přibližně 10-60 sekund. Jejich součet a schema migrace mohou znamenat několik minut omezení. Vyhradit 15minutové okno; hranici pro rozhodnutí o návratu určit z nácviku tak, aby se do něj vešel i návrat. Pokud nácvik nevejde aktualizaci i návrat do rozpočtu, opravit postup nebo dohodnout delší okno před produkcí.

Nulový výpadek je samostatná varianta vyžadující další kapacitu, synchronizovanou repliku, jednoznačné odpojení starého writera, otestované přepnutí všech DB klientů a řešení dlouhých spojení i migrací služeb. Není součástí doporučeného postupu a nepořizuje se bez dalšího zadání.

## Tempo realizace

Uživatel 2026-10-21 výslovně požaduje svižný postup při zachování bezpečnosti. Vlny níže jsou závislosti jednoho souvislého úkolu, nikoli samostatná kola analýzy a schvalování. Tento požadavek sám neautorizuje zahájení implementace ani produkční změny.

- Po zadání přípravy udělat jednu cílenou kontrolu změn od tohoto průzkumu. Neopakovat celý audit, nevytvářet další plán a nerozšiřovat úkol o obecnou serverovou hygienu.
- Připravit image, konfiguraci a konkrétní příkazy jako jeden balík. Využít existující recovery, zámky a monitoring; nový updater držet jako tenkou vrstvu nad nimi, nikoli nový deployment framework.
- Jeden společný izolovaný nácvik pokryje obnovu, upgrade celé kandidátní sady, kompatibilitu a návrat. Existující důkazy opakovat jen pro změněné hranice; nevytvářet samostatný plný drill pro každou komponentu. Smysluplné cílené kontroly spustit v jedné dávce. Další běh jen po změně nebo neúspěchu.
- Krátké kontroly zdraví zůstanou mezi nevratnými kroky, bez dlouhých umělých prodlev. Test Realtime přes 20 minut překrýt s ostatním izolovaným ověřováním; nečekat na něj nečinně.
- Nasazení musí být připravené před otevřením okna. Žádné builds, hledání příkazů a běžné stahování během výpadku. Nesouvisející problémy evidovat mimo tento upgrade; kompatibilita dat, session a obnovitelnost zůstávají blokující.
- Po návratu zdravého provozu sledování dalších 24 hodin běží existujícím monitoringem. Neblokuje otevření API ani předání výsledku nasazení; pozdější backup/restore a provozní kontroly zůstávají výslovně evidované do uzavření upgradu.
- Autorizaci vyžádat až nad hotovým balíkem a konkrétním servisním oknem; pokud už ji následné zadání poskytlo, nežádat opakovaně. Při provedení dodržet rozhodovací stop body a nacvičený návrat.

## Rozsah a omezení

- Kanonické runtime image, jejich konfigurace, pgBackRest derivát, zálohy a upgrade runbook. Bez upgrade PostgreSQL 18/19, OS, Dockeru, klientských SDK nebo aplikačních funkcí.
- Bez rolloutů frontendů nebo dalších prod/* větví. Backend je sdílený: jeho restart ovlivní všechny klienty používající api.festapp.net. Servisní oznámení a souhlas s oknem musí tento dopad výslovně pokrýt; neznamená to oprávnění měnit data jiných tenantů.
- Bez obnovování bývalých cloud backendů jako fallbacku, bez reset.sh, down -v, prune a bez přepisování živého PGDATA kopií.
- Neprovádět placené provisioning kroky, odesílání zpráv uživatelům ani produkční testovací objednávky v rámci přípravy.
- Zachovat JWT/anon/service keys, refresh tokeny, Auth hooks, TLS/Access, stávající R2 vlastnictví a email/bankovní idempotenci. Neměnit současně resource limity a databázové ladění.

## Ověřená východiska

| Fakt | Důkaz při průzkumu | Dopad |
|---|---|---|
| Live activation vstupenky.online uvádí festapptickets, canonical, generation 1 | veřejný backend-activation.json | před realizací znovu svázat tenant, org a target podle backend-access skillu |
| Host a runtime DB odpovídají chráněným target assertions | SSH hostname, FESTAPP_RUNTIME_DATABASE a current_database() shodné | nespoléhat na historický název rehearsal; jde o produkci |
| PostgreSQL skutečně 17.6, linux/arm64 | SQL version(); image ID 58ab4c77b25c, tag festapp-postgres-pgbackrest:17.6-2.57.0-r0 | běží vlastní image; změna běžného db pinu sama nestačí |
| Auth 2.189.0, REST 14.12, Realtime 2.102.3, Edge 1.74.0, Meta 0.96.6, Supavisor 2.9.5 | docker ps, 2026-10-21 | starší runtime; upgradovat podle kompatibilní matice |
| Storage ani imgproxy neběží | docker ps i ps -a filtr storage | při upgradu je neaktivovat jen kvůli upstream Compose |
| pgBackRest 2.57.0; archive_mode=on; timeout 5 min; 349 archivovaných segmentů, 0 selhání | pg_stat_archiver a pgbackrest info | zachovat existující PITR, nezakládat nové klíče/stanza/repository |
| Poslední differential backup 20261018-031955F_20261021-031924D, status ok | pgbackrest info, 2026-10-21 | není sám o sobě důkazem čerstvé obnovy |
| RAM 3796 MiB, available 933 MiB, swap 0; disk volný cca 13 GiB | free/df, jednorázový snapshot | nedělat paralelní celý stack na produkčním serveru; nácvik jinde |
| Žádné logické replikační sloty při předchozí kontrole | pg_replication_slots | nevytvářet je kvůli updatu; před změnou opakovat inventuru celého clusteru |
| Pracovní kopie je rozsáhle rozpracovaná a není shodná s origin/main | HEAD eb2304724, lokální origin/main 43bcb89d7; některé recovery zdroje jen v origin/main | realizaci začít v čistém izolovaném checkoutu aktuálního main; nerevertovat tuto kopii |

Zdrojové body pro implementaci:

- `automation/hetzner-supabase/runtime/pins.json`, `docker-compose.festapp.yml`, `verify-pins.mjs` a `docs/operations/supabase-self-hosted/version-policy.md`.
- V kanonickém main: `automation/hetzner-supabase/backup/pgbackrest/{Dockerfile,README.md,install.py,test-pitr-local.py}`, `runtime/docker-compose.pgbackrest.yml`, `restore/{RECOVERY.md,drill-pgbackrest-local.py,drill-online-backup-local.py}`. Neobnovovat chybějící soubory násilně v rozpracované kopii.
- `upgrade-installed-production-runtime.sh` instaluje registry/tooling, není to image upgrade. `set-production-target-write-barrier.sh` je historický promotion postup, odpojuje spojení a vyžaduje promotion důkazy. Ani jeden nespouštět jako obecný updater.
- Historické `run-integration-canaries.mjs` má pevný přímý SSH target a starý DB/endpoint; nelze jej použít beze změny proti dnešní produkci. Starý encrypted rehearsal restore očekává jiný backup manifest a původní image. Použít současné recovery helpers z main, ověřit jejich argumenty a kontrakty.

## Cílová matice a upstream podklady

| Vrstva | Kandidát | Podmínka |
|---|---|---|
| Supabase bundle | self-hosted/v0.8.3, vydáno 2026-10-16 | vyřešit konkrétní commit tagu a ARM64 digesty |
| Auth / REST / Realtime | 2.197.0 / 14.18 / 2.143.3 | migrace, session a reconnect otestované na kopii |
| Edge / Meta / Supavisor | 1.77.4 / 0.100.0 / 2.9.13 | zachovat Festapp overrides; ověřit kompatibilitu konfigurace |
| Studio | 2026.10.12-sha-3699278 | zachovat Access, logout customizaci a neveřejné meta cesty |
| PostgreSQL | 17.11, přesný Supabase build určit při přípravě | dostupnost vhodného Docker ARM64 artefaktu, extensions/libc/PGDATA kompatibilita, pgBackRest derivát a recovery důkaz |
| Storage / imgproxy | zůstanou vypnuté | případné piny sjednotit s bundlem, bez startu nebo migrace Storage |

PostgreSQL 17.11 existuje a Supabase publikuje řadu 17.11.0.006; release tag není důkaz vhodného Docker image ani jeho kompatibility s dnešním Alpine derivátem. Výchozí upstream Compose stále používá 17.6.1.136. Aktualizace PG je proto výslovná testovaná odchylka od bundle a musí být takto evidována, nikoli vydávána za výchozí upstream kombinaci.

Primární zdroje ověřené 2026-10-21:

- [PostgreSQL version policy](https://www.postgresql.org/support/versioning/) a [17.11 release notes](https://www.postgresql.org/docs/release/17.11/): minor update nevyžaduje dump/restore, může ale vyžadovat doplňující opatření.
- [Supabase Docker changelog](https://github.com/supabase/supabase/blob/master/docker/CHANGELOG.md): bezpečnostní opravy, konfigurace a migrační omezení vydání 0.8.3.
- [Výchozí Compose](https://github.com/supabase/supabase/blob/master/docker/docker-compose.yml), [Supabase Postgres release](https://github.com/supabase/postgres/releases/tag/17.11.0.006), [updating guide](https://supabase.com/docs/guides/self-hosting/updating).

V přípravě porovnat neměnné tagy 0.8.0 -> 0.8.3, nikoli aplikovat pohyblivý master. Pokud novější bezpečnostní vydání změní cíl, aktualizovat tuto matici a znovu nacvičit dotčenou část.

## Invarianty a rozhodnutí

1. Existuje jediná aktivní zapisující databáze. Přípravná kopie není veřejně dosažitelná a nesmí poslat email, platbu, webhook, cron HTTP nebo Worker side effect.
2. Po návratu provozu nesmí zmizet žádný potvrzený zápis. Záloha před oknem neopravňuje zahodit pozdější objednávky.
3. pgBackRest archivace, šifrování, repo prefix, retention a nezávisle dostupný recovery klíč zůstávají funkční. PITR není časově atomická záloha externích R2 objektů.
4. Artefakty se stáhnou a sestaví před oknem. V okně žádný build, provisioning, neověřený download ani plošné compose down/up.
5. Zachovat přesný seznam aktivních Compose overrides z hosta včetně email a pgBackRest. Sealed `FESTAPP_PGBACKREST_DB_IMAGE` musí odkazovat na nový ověřený derivát; původní image ID ponechat pro návrat.
6. Kompletní kandidátní sada se otestuje dohromady; lze ji aplikovat po službách jen podle otestovaného pořadí a migrační kompatibility. Žádné náhodné posouvání jednotlivých tagů.
7. Automatický návrat smí vrátit binárku/config jen pokud je kompatibilita s již změněným schématem a daty prokázaná. Jinak zastavit další změny a použít otestovaný forward fix nebo řízenou obnovu.

## Vlny přípravy a provedení

### 1. Uzavřít přesný release kontrakt, bez změn produkce

**Změny:** v čistém checkoutu main načíst aktuální instrukce a projektový backend-access skill. Znovu ověřit activation/org/DB, image ID, Compose seznam, schémata/verze služeb, systemd writery a jejich vlastníky. Zapsat výchozí manifest a kandidátní manifest bez tajemství; citlivou konfiguraci a rollback kopii držet mimo Git v chráněném úložišti.

Prověřit upstream changelogy všech meziverzí, startovací migrace Auth/Realtime/Supavisor a jejich downgrade podporu. Zvlášť posoudit sdílené interní DB, nejen aplikační DB. Pro Realtime 2.143.3 zahrnout upstream workaround REGION=us-east-1 pro periodické výpadky Postgres Changes, pokud nebude nahrazen ověřenou opravou. Ověřit rozdíly route discovery, Edge main workeru, deno.jsonc, limitů a timeoutů, nepřepsat vlastní gateway/security konfiguraci upstream souborem.

**Výstup:** tabulka každého image/config/migrace, cílového digestu, očekávaného restartu a možné cesty návratu. Není-li vhodný PG17.11 image, označit PG větev za blokovanou; nevolit vanilla postgres nebo neznámý cloud/Nix artefakt. Nezávisle připravený Supabase bezpečnostní balík může být předložen zvlášť, nesmí se tím PG označit za hotové.

### 2. Připravit reprodukovatelné artefakty a úzký updater

**Změny:** aktualizovat piny/Compose z jednoho zvoleného bundle, Dockerfile pgBackRest derivátu a dokumentaci. Pro PG zkontrolovat dostupnost všech instalovaných extensions, preload knihoven, cesty, UID/GID, libc/ICU a collation verze. Nevynucovat nový extension update současně s binárkou, není-li nezbytný a nacvičený. Zachovat pgBackRest 2.57.0, pokud je kompatibilní; změnu package manageru/libc řešit explicitně.

`verify-pins.mjs` dnes vyžaduje přesnou shodu všech image s upstream Compose a zároveň kontroluje nejnovější nesouvisející host nástroje. Doplnit úzkou validaci vybraného bundle a explicitního PG override s původem/digestem/test evidence; neoslabit kontrolu na libovolný tag a nevynutit OS/Docker upgrade. Původní online kontrolu rozlišit od deploy gate.

Připravit `automation/hetzner-supabase/runtime/apply-runtime-update.sh` jako jediný nový upgrade vstup: explicitní ack, target a source SHA; stejný runtime zámek; kontrola očekávaného výchozího stavu; root-only snapshot konfigurace; explicitní seznam služeb; preflight, apply a resume podle zaznamenaného stavu. Žádný shell dump .env nebo interpolovaného Compose config. Renderovat config do chráněného souboru a validovat bez výpisu hodnot. Dry-run nesmí restartovat ani zapisovat SQL.

Updater nevolá historickou promotion, installer PITR ani reset. Pokud nový Auth/Realtime po startu může migrovat DB, před jeho spuštěním zaznamená nevratný bod a nepředstírá automatický binární rollback. Zachovat exit cleanup, přesný původní stav pause a recovery cestu i při ztrátě SSH.

**Validace/výstup:** lokální pin kontrola, ARM64 digest kontrola a cílené shell/Node testy upgraderu: mismatch cíle, obsazený lock, částečné selhání, idempotentní resume, ochrana volume a zachování klíčů. Prebuild/import obou DB image; původní image zůstává dostupný. Žádné změny hosta v této vlně bez další autority.

### 3. Obnova a plný nácvik mimo produkční server

Použít aktuální recovery zdroje z main a nezávisle dostupnou recovery identitu. Stáhnout vybraný off-host backup a potřebný WAL, ověřit obsahové hashe, dešifrování a obnovit do nového izolovaného PGDATA. Nespouštět legacy manifest-v3 rehearsal drill nad dnešními asset-v2 sadami. Nácvik nemusí obnovovat Storage, která je vypnutá; zachovat dnešní DB/R2 kontrakt.

Izolace před prvním startem obnovené DB: žádná veřejná síť/produkční JWT, odchozí integrace zakázané, cron/pg_net/background writery pozastavené včetně těch v postgres DB. Nezkoušet plný stack vedle produkce na 4GB hostu. Použít lokální izolaci s kapacitní kontrolou nebo zvlášť autorizovaný testovací host; nekupovat jej automaticky.

Nacvičit skutečný in-place přechod PG17.6 derivát -> PG17.11 derivát na kopii fyzických dat. Přečíst i kumulativní instrukce 17.7-17.11; ověřit potřebné reindexace, logical decoding output_plugin_libraries, autentizaci a změny pgcrypto. Rozhodnout podle skutečných extension/index inventur, nikoli instalovat všechny příklady z poznámek. Zvlášť změřit délku migrací služeb a lock waits s limity a bezpečným stop bodem.

Provést upgradovaný stack na kopii, test Auth password/OAuth/session refresh a rotace, REST/RPC rights, rezervace posledního místa při souběhu, timeout po možném commitu a deduplikace opakování, Client Sync catch-up, scanner, generování PDF, queue/provider outcome recovery bez odeslání. Realtime testovat přes 20 minut a reconnect, nejen websocket handshake. Ověřit Studio Access/logout a nezveřejnění meta.

Obnovit z pgBackRest do zvoleného času, prokázat zachování požadovaného a vyloučení pozdějšího fixture commitu. Otestovat archivaci/nový backup a obnovu po upgradu. Nacvičit zvlášť návrat PG binárky při zastavených writerech; pokud jej formát/library/schema změna nepřipouští, nesmí být v produkčním rollbacku. Změřit také nouzovou obnovu, včetně startu služeb, nikoli jen pg_restore.

**Výstup:** všechny gates prošly; přesné image/zdrojové SHA, pořadí služeb, restart/health/rollback časy, změněné schema migrace a povolené návraty jsou zaznamenané. Chybějící kompatibilita nebo nezměřená obnova je stop podmínka, nikoli úkol do servisního okna.

### 4. Předložit hotový balík a finální provozní runbook

Příprava končí přehledem zdrojového commitu, digestů, recovery důkazů a změřeného okna. Teprve samostatný pokyn autorizuje publikaci/instalaci a pozdější produkční aplikaci. Respektovat canonical main, nepublikovat z rozpracované kopie. Produkční balík musí být před aplikací na autoritativním main podle pravidel repozitáře.

Finální runbook obsahuje konkrétní bezplaceholderové příkazy a očekávané výstupy pro skutečný Compose seznam a zvolené image, monotónní časovou osu, timeout každého kroku a nejzazší bod návratu. Společné dependency změny pořadí se rozhodnou nácvikem; předpoklad je nejprve PG při starém runtime, pak bundle, pouze pokud jsou obě přechodné kombinace prokázaně kompatibilní. Jinak jeden koordinovaný krátký výpadek a pořadí podle závislostí.

**Výstup:** balík je reviewovatelný a k samotnému provedení nevyžaduje nový architektonický průzkum. Pokud nové zadání vyžádá pouze implementaci přípravy, zde skončit.

### 5. Produkční okno - až po samostatném pověření

Rutinní provedení a monitoring delegovat dle AGENTS.md levnějšímu subagentovi s přesným SHA, scope, příkazy a gates. Neočekávané schema/backup chyby vracet hlavnímu agentovi, neimprovizovat.

1. Za provozu připravit již ověřené image a chráněnou rollback konfiguraci; preflight identity, zámku, disk/RAM, backupů a archive lag. Předem vybrat dobu bez vstupního skenování/špičky a ověřit recovery klíče. Během okna nespouštět backup full scan; po okně obnovit plánování, WAL archivaci ponechat aktivní.
2. Pozastavit email dispatch podle existující `email_capacity.paused` a vyčkat na nulu `sending/preparing`; původní hodnotu uchovat. Zmapovat běžící payment/bank/webhook/cron/Worker writery. Neprohlásit běžný DB read-only default za úplný write fence. Krátce zavřít nové mutace přes ověřenou maintenance hranici, nechat doběhnout transakce a externí pokusy. Nejasný provider outcome zapsat k reconciliation, neodesílat znovu.
3. Maintenance odpověď 503 + Retry-After, bez cache; zachovat potřebné read/static cesty, pokud to otestovaná hranice umožní. Ověřit retry kontrakt webhook providerů a dostatečnou dobu jejich opakování. Příchozí request neacknowledgovat 2xx bez trvalého přijetí. Pokud některá kritická cesta retry nemá, předem vyřešit durable příjem nebo zvolit okno bez ní. Cloudflare sama frontu ani nulový výpadek nezajistí.
4. Po drainu zaznamenat čas/LSN a zajistit odpovídající dostupný WAL; nepředstírat fyzickou kopii živého volume. Provést otestovaný stop/start pouze db na tentýž PGDATA a sealed kandidátní image. Nikdy dva postmastery nad stejnými daty. Ověřit SQL verzi, identity, extensions, archivaci a zotavení klientských poolů.
5. Upgradovat pouze předem určené aktivní služby a konfiguraci v nacvičeném pořadí. Použít service-scoped compose up s řízením dependencies, nikoli plošné down/up. Zachovat custom Edge bundle, bezpečnostní routes a aktuální overrides. Gateway/Caddy reloadovat validovanou konfigurací; počítat s odpojením Realtime websocketů.
6. V uzavřené admission hranici provést čtecí/identity/security health gates. Zápisové testy dělat jen v předem autorizovaném testovacím scope, ne nad zákaznickými objednávkami; jejich absence nenahrazuje izolované testy z vlny 3. Ověřit očekávané service migration heady a přístup existujících session podle schválené metody bez logování tokenů.
7. Otevřít admission a obnovit právě původní stav jobů/email pause. Ověřit backlog, Client Sync catch-up, žádné ztracené/duplicitní provider pokusy a metriky DB/API. Měřit reálný uživatelský výpadek od prvního selhání po souvislou úspěšnost, nikoli jen dobu docker restartu.

**Stop/návrat:** při identity mismatch, selhání startu, neznámé migraci, nefunkční archivaci nebo překročení nacvičeného budgetu nepokračovat dalšími službami. Použít matici návratu níže. Při ztrátě SSH musí runbook umožnit zjistit poslední dokončený krok a obnovit admission/jobs bez opakování migrací.

### 6. Doložit provoz a uzavřít upgrade

Minimálně 30 minut aktivně sledovat dostupnost, 5xx/latence, DB spojení/locky/RAM/disk, Auth refresh, Realtime reconnect a WAL archive lag; následně zkontrolovat dalších 24 hodin v existujícím monitoringu. Ověřit další úspěšný pgBackRest i logický backup a izolovanou obnovu nové fyzické sady.

Uložit sanitized manifest skutečných image ID/digestů, source SHA, schema migration headů, downtime, backup identity a kontrol. Aktualizovat version-policy, recovery návod a potřebné testy. Odstranit dočasnou maintenance konfiguraci a izolované fixture prostředky až po zachování evidence. Původní image/config ponechat v chráněném rollback balíku po ověřenou dobu, navrženě 7 dnů; staré recovery body nikdy nemažou deploy skripty. Žádná trvalá druhá release cesta nebo Storage kontejner navíc.

## Matice návratu a ochrana dat

| Okamžik | Přípustný postup |
|---|---|
| Před změnou image/schématu | zrušit maintenance, obnovit původní pause/jobs, beze změny dat |
| PG restart selhal, migrace služeb neběžely, žádné nové zápisy | pouze nacvičený návrat starého image/config na stejný PGDATA; při nekompatibilitě izolovaná obnova na fencing bod |
| Služba provedla migraci | návrat pouze s prokázanou downgrade kompatibilitou; jinak forward fix nebo koordinovaná obnova se zastavenými všemi writery |
| Provoz už přijal nové zápisy | nevracet snapshot před oknem; zachovat nejnovější WAL/data, forward fix nebo obnova se zachováním potvrzených zápisů a explicitní reconciliation |
| Potřeba obnovy DB před migrací | samostatné recovery rozhodnutí, zastavit všechny writery, nová izolovaná cílová data, ověřit úplnost clusteru a externích side effects před přepnutím |

Obnova do času před migrací může ztratit potvrzené zápisy a rozpojit DB od již odeslaných emailů/plateb/R2 změn. Bez jejich vypořádání není bezpečný rollback. Běžný restart a záloha nejsou slibem RPO=0 při ztrátě hosta; archive_timeout 300s ponechává nenulové recovery okno. Pro tento upgrade je cílem neztratit žádný potvrzený zápis, nikoli tím deklarovat synchronní HA.

## Kontroly, nejistoty a hotovo

- Příprava: pin/bundle/registry a cílené upgrader testy; `node --test automation/tests/hetzner_supabase_infrastructure.test.mjs automation/tests/hetzner_supabase_backup.test.mjs` podle aktuálního main a změněných seams. Přidat pouze testy skutečných failure hranic, ne prose snapshoty. Žádný Flutter build není pro runtime upgrade nutný.
- Recovery: současné `test-pitr-local.py`, `drill-pgbackrest-local.py --rest-smoke` a `drill-online-backup-local.py` dle jejich aktuálních CLI; nacvičené DB/Auth/REST/Edge/gateway testy proti izolované kopii. Historické skripty nespouštět naslepo.
- Neověřené před realizací: vhodný PG17.11 Docker ARM64 image a libc/extension kompatibilita, downgrade jednotlivých service migrací, změřený restart/restore čas, všechny nezávislé writery a provider retry kontrakty. Každý bod uzavře vlna 1-3; při neúspěchu se produkční část nespouští.
- Hotovo znamená: skutečně běžící schválená matice, zachované session/objednávky a konfigurace, obnovené joby, zdravá archivace, prokázaná obnova nové zálohy, změřený výpadek a odstraněná dočasná maintenance hranice. Samotná změna pinů ani zelený docker ps nestačí.

Tento plán neprovádí implementaci, commit, push, zálohu, obnovu, instalaci ani restart produkce. Další krok je samostatně zadaná příprava a nácvik vln 1-4, poté výslovně pověřené servisní okno.
