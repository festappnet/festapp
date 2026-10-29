# MCP a HTTP API: ochrana provozu, zotavení a minimalizace dat

Datum: 2026-10-29
Stav: Lokální implementace i úplná akceptace dokončeny. Všechny povinné gate prošly, žádný test není skipped. Produkční změny neprovedeny. Viz `mcp-api-hardening-RESULT-2026-10-29.md`.
Verification: standard - autentizace, souběh, veřejný kontrakt a SQL migrace.
Výchozí bod: `main`, `579f79f25`; před implementací ověřit případný posun HEAD.

## Výsledek a rozsah

MCP a Make HTTP API budou skutečně omezovat provoz podle důvěryhodné identity,
po tvrdém pádu se obnoví bez ručního odemykání a profil `order-summary` nedostane
osobní údaje ani přes interní odpověď databáze. Přesné hledání symbolu nebude
procházet stránky obecných kontaktních výsledků.

Rozsah: Node operator v `tools/festapp`, jeho Caddy/Compose hranice, SQL čtení
objednávek, související kontrakty a cílené testy. Oprava zahrnuje také zámek
lokálního CLI, aby tentýž druh pádu nezůstal ve druhém MCP transportu.

Mimo rozsah: nové obecné vývojářské API, rozšiřování oprávnění, změny OAuth scopes,
sedmidenního souhlasu či klientských redirectů, nové platební nebo objednávkové
enginy, Flutter UI, veřejný checkout a marketplace publikace.

Toto je plánování. Implementace, commit/push, migrace a nasazení nejsou tímto
úkolem autorizovány. Případné nasazení se vybírá samostatně pro konkrétní tenant;
regionální i globální MCP host se tímto automaticky nestávají rozsahem rollout.

Implementační reconnaissance: HEAD `2b69bc6be` (posun proti výchozímu SHA); scoped čtení server/storage/orders a SQL potvrdilo všechny níže uvedené závady. Návrhová rozhodnutí se nemění.

## Potvrzený stav

| Fakt | Důkaz | Důsledek |
| --- | --- | --- |
| Limiter při inkrementaci ztrácí `expires`; další volání začne nové okno. | `src/remote/server.mjs: limit`; lokální reprodukce 241 požadavků, všech 241 HTTP 200. | Nestačí změnit číslo kvóty; opravit jejího vlastníka a testovat hranice. |
| IP klíč je socket loopback proxy. | `server.mjs: http:${req.socket.remoteAddress}`, `Caddyfile.remote: reverse_proxy`. | Po opravě čítače by všichni sdíleli jednu kvótu. |
| Canonical Caddy již má trusted proxy resolution a přepisuje `X-Festapp-Client-IP`. | `automation/hetzner-supabase/runtime/Caddyfile`, globální `servers` a snippet `festapp_supabase_proxy`. MCP snippet přepis zatím nemá. | Použít stejný kontrakt; nepsat vlastní parser XFF. |
| Process i session zámky jsou adresáře s ručním odstraněním. | `remote/storage.mjs: openRemoteStorage`; `auth/session.mjs: locked`; README. Reprodukce nečistého ukončení: další open vrátí `EEXIST`. | Řešit oba životní cykly zámků, nikoli pouze startup. |
| Restart policy je automatická, datový volume trvalý. | `remote-compose.yml`: `restart: unless-stopped`, `/var/lib/festapp-mcp`. | Starý zámek přežije restart kontejneru. |
| Summary používá plný read RPC a pak JS allowlist. | `operations/orders.mjs: invokeOrderOperation`, `catalog.mjs: invoke`, `public-orders.mjs`. | Zúžit projekci už v SQL a změnit i mezivrstvové validátory. |
| Symbol se hledá přes kontaktové hledání a maximálně čtyři stránky. | `orders.mjs: orderSummaryOnly` smyčka; `operator_orders.sql: get_operator_orders_v1`. | Exact predikát musí být v SQL před LIMIT. |
| Neprázdný order symbol je globálně unikátní a indexovaný. | `database/tables/tables.sql: orders_order_symbol_key`, `20261006130000_order_symbol_expand.sql`. | Exact search vrací nanejvýš jeden řádek; nevymýšlet duplicity ani nový index. |
| Současné SQL testy hlídají PII až v konečném výsledku. | `test/make-orders-postgres.test.mjs`. | Přidat kontrolu syrové RPC odpovědi. |
| Historická foundation migrace je neměnná. | `automation/assemble-operations-foundation-migration.py`. | Nová forward migrace; nepřegenerovat instalovanou historii. |

Cesty `src/...` a `test/...` výše jsou relativní k `tools/festapp/`.
Pět cílených testů OAuth/API prošlo při předchozím review, ale nekrylo nalezené
poruchy. Reprodukce i testy byly lokální, nikoli důkaz aktuální produkční konfigurace.

## Cílová architektura a rozhodnutí

### D1. Jeden vlastník limiteru, žádný nový distribuovaný systém

Vyjmout limiter z routeru do `src/remote/rate-limit.mjs`. Protože hosted runtime
zůstává výhradně jeden proces, použít omezenou in-memory mapu, injektovatelný
monotónní čas a synchronní atomické rozhodnutí bez `await`. Persistovat abuse
čítače do šifrované grantové SQLite databáze není potřeba. Restart smí resetovat
abuse okna; nesmí změnit granty, souhlas, revokace ani receipty.

Každý bucket vlastní `{count, expiresAt}` po celé pevné okno 60 sekund. Přesně N
požadavků projde, N+1 vrátí 429 a celočíselné `Retry-After` do konce okna. Uchovávat
nejvýše 20 000 bucketů, promazávat expirované; při plné kapacitě odmítnout novou
identitu, nevyhazovat aktivní bucket a tím obnovovat její kvótu. IP ani credential
hodnoty nepatří do auditu; klíče lze hashovat existujícím digest helperem.

Zachovat dnešní základní limity jako výchozí politiku: 240/min/IP, 60/min/grant,
5/min/login flow nebo management session. IP limit je abuse guard pro NAT/Make
egress, nikoli uživatelská kvóta. Stávající limity souběhu 2/grant a 16 celkem a
fronta token exchange 8 zůstávají oddělené. Kvóty logovat jen typem bucketu a
výsledkem, bez identifikátorů a osobních údajů.

Canonical Caddy MUSÍ přepsat `X-Festapp-Client-IP {client_ip}` za stávajícím
trusted-proxy a origin filtrem. Node přijímá přesně jednu syntakticky validní IP
a normalizuje IPv4-mapped adresy až po stávající kontrole loopback peer/Host/proto.
Chybějící či vícehodnotová IP u canonical veřejné cesty skončí odmítnutím, nikdy
fallbackem na uživatelský XFF, `CF-Connecting-IP` či loopback. Nepoužít
`app.set('trust proxy', true)`. Disposable-local profil použije socket adresu;
lokální test nesmí zapnout canonical header trust pouhým posláním hlavičky.

`GET /healthz` má úzkou výjimku z abuse limiteru a požadavku na client-IP až PO
ověření Host/peer/proto, aby sonda Compose fungovala i při vyčerpané kvótě.
Discovery, token, MCP a Make zůstávají omezené. Broker cesty dál ověřují svůj
secret a uživatelský důkaz; tajná hlavička nesmí sloužit jako obecný rate bypass.
Edge broker volá veřejný issuer, takže jeho `/tenant-connection` a
`/tenant-connections` správně sdílejí IP kvótu 240/min podle egress adresy, včetně
status pollingu. Toto je vědomý strop broker kapacity; grantová kvóta tyto
pre-grant cesty nechrání. Nepředávat novou neověřenou koncovou user-IP. Měřit
souhrnné odmítnutí podle třídy route; případné zvýšení broker kapacity je
samostatná změna politiky podložená měřením, ne secret bypass.
Všechny vrstvy, které vracejí 429, sjednotí `Retry-After`; Make odpověď zachová
svůj JSON error kontrakt. Grantový limit lze použít až po ověření tokenu.

### D2. Zámky musí vlastnit živý proces, ne existující adresář

Přidat technický helper `src/auth/process-lock.mjs` nad již používaným
`node:sqlite`. Držet `BEGIN EXCLUSIVE` na SAMOSTATNÉ privátní lock databázi,
nikdy dlouhou transakci nad `remote.sqlite`. Kernel při ukončení procesu zámek
uvolní; soubor je stabilní kotva a NESMÍ se unlinkovat/nahrazovat ani po release.
Nejde o nový grantový ani doménový store, lock DB neobsahuje secrety nebo doménová data.

Helper musí před otevřením ověřit soukromý root, vlastníka a běžný nesymlinkový
soubor; nové soubory mají 0600. Před acquire neprovádět DDL ani změnu journal mode,
které by závodily s držitelem. SQLite busy timeout je nulový; bounded čekání se
dělá asynchronně, aby neblokovalo event loop. Při každém neúspěšném acquire
uzavřít vlastní connection, klasifikovat busy versus I/O/corruption a nepovažovat
jinou chybu za důkaz volného zámku. Release je idempotentní; zavírat vše v `finally`.

- Hosted root: `remote-owner.sqlite`, acquire bez čekání v `openRemoteStorage`.
  Uvolnit až po dokončení obsluhy a zavření hlavního storage. Druhý proces musí
  selhat před čtením, změnou deployment metadata nebo převzetím refresh session.
- Hosted session: `storage.runSessionExclusive(binding, action)` vlastní jednu
  bounded async frontu na binding sdílenou VŠEMI `boundOwner` instancemi. Po
  nejvýše 10 sekundách čekání `SESSION_BUSY`; čekající timeout nesmí uvolnit
  aktivního držitele ani později spustit zrušenou akci. Po idle smazat položku.
  Fronta chrání celý dosavadní úsek `locked`, včetně refresh persist a pending
  intent claim/submission/clear. In-memory stačí právě díky root process locku.
- Local CLI/stdio: výchozí `SessionOwner` používá stejný kernel helper s lock DB
  podle stabilního profile bindingu; zachová 10sekundové asynchronní čekání a
  cross-process serializaci. Nevytvářet lock soubor pro každé hosted OAuth flow.

`SessionOwner` získá explicitní lock strategy dependency. Hosted ji předává
`boundOwner`; nesmí vzniknout nový mutex pro každou instanci. Žádný lease podle
času, PID-only stale detection ani slepé mazání adresářů. Přítomnost starého
lock adresáře je migrační konflikt, který vyžaduje prokázané zastavení starých
procesů; nová verze jej automaticky nepřivlastňuje.

### D3. SQL vlastní dvě projekce týchž objednávkových faktů

V `database/functions/eshop_orders/operator_orders.sql` zachovat stávající plný
`get_operator_orders_v1` včetně signatury a kontaktního hledání pro administraci
a existující volající. Přidat jednoznačně pojmenovaný
`public.get_operator_order_summaries_v1`, nikoli overload staré signatury.

Nový RPC má explicitní occasion/organization/unit, bounded limit 1-50, keyset
`before`, stav, volitelný EXACT symbol a volitelné order ID. Kombinace detail ID
s nesouvisejícími list filtry odmítnout. Hranice vrací existující
`publicOrderPage`: `occasionId`, `orders`, `nextCursor`. Objednávka obsahuje jen
`id`, `occasionId`, `symbol`, `state`, `ticketCount`, `price`, `currency`,
`allowedActions` omezené na `view`, a nullable `payment {amount, paid, returned}`.
Peníze zůstávají decimal string; žádné nové výpočty v JS.

Společný private owner bezpečných objednávkových faktů zásobuje full i summary
snapshot. Sdílet současnou sémantiku distinct valid ticket count, uložených
částek a existující action eligibility; nepřidávat druhý stavový/finanční engine.
Plný snapshot rozšíří bezpečný základ o jeho dosavadní administrátorská pole.
Summary NESMÍ volat full snapshot ani `operator_order_revision_internal_v1`
a potom ořezávat JSON; nesmí skládat zákazníka, odpovědi, poznámky, QR, ticket
content, VS či jiné plné payment údaje. Interní helpery nemají přímý EXECUTE
pro authenticated/anon/service_role.

Oba veřejné read RPC používají `check_operator_order_scope_internal_v1` a
`can_read_orders` před daty, včetně vázání aktuálního organizátora ve stejné
transakci. Nový SECURITY DEFINER je jen v public, má
`search_path=public,extensions`, explicitní `eshop.*`, revokované PUBLIC/anon/
service_role a EXECUTE pouze authenticated. Neudělovat nová klientská oprávnění.

Symbol validovat podle dnešního `publicOrderSearch` a hledat `order_symbol =
p_symbol` uvnitř vybrané occasion PŘED LIMIT, bez LIKE a kontaktních polí.
Použít existující globální unikátní constraint/index `orders_order_symbol_key`;
exact search vrátí nanejvýš jeden řádek a `nextCursor: null`. Ověřit přítomnost
constraintu v disposable schématu a při rollout inventory. Pokud by cílová DB
constraint neměla, jde o schema drift a stop rollout, nikoli důvod přidat
duplicate-symbol chování nebo potichu zavádět nové omezení nad produkčními daty.
Žádný nový index není pro tento exact lookup plánován.

V Node `invokeOrderOperation` vybírá nový RPC podle `owner.orderSummaryOnly`.
`catalog.invoke` validuje summary větev přímo přes `publicOrderPage`, nikoli
nejprve přes full schema. Z `publicOrders` odstranit full-to-summary mapper a
zvláštní symbolové ořezávání; schema zůstává druhou fail-closed allowlist hranicí.
Odstranit čtyřstránkovou smyčku. Při chybějící migraci žádný fallback na full RPC.
Make i ChatGPT profily používají stejnou cestu bez závislosti na názvu klienta.
`orders.report`, finance, mutace, receipty a granty se nemění.

## Implementační vlny

### 1. Funkční kvóty a důvěryhodná identita

Změnit `server.mjs`, přidat `rate-limit.mjs`, upravit `Caddyfile.remote` a příslušné
probes/test fixtures. Odstranit současný inline `limit` a zápisy `Rate` do
grantového storage. Staré Rate záznamy pouze expirují, žádná hromadná úprava
šifrovaného store. Rozdělit identity podle D1, zachovat účel route guardů.
V `supabase/functions/mcp-session-exchange/handler.ts` zachovat broker 429 jako
429 místo současného catch-all 403; v `management.ts` doplnit přenos bounded
`Retry-After`, který už status 429 zachovává. Pro browser CORS vystavit jen tuto
potřebnou hlavičku. Žádné slepé automatické opakování approve/prepare/complete
nebo mint session; po nejasném účinku zachovat dnešní fail-closed cleanup a
completion-unknown chování. Čtecí status lze po okně zopakovat bez nového souhlasu.

Testy v novém `test/rate-limit.test.mjs` a `remote.test.mjs`: přesná hranice,
časová expirace, nezávislé identity/buckets, mapa plná, neobcházení kvóty při
chybějící IP, spoofed a duplicitní proxy header, canonical proti disposable,
429/Retry-After a zdravý healthcheck po vyčerpání kvóty. Přes skutečnou lokální
HTTP obsluhu ověřit společný broker egress: 429 při vyčerpání a obnovení status
čtení po expiraci, bez ztráty či rozšíření flow/souhlasu a bez nového approve.
Handler/management testy ověří 429/Retry-After a nemintování navíc; nejde o
nový automatický retry mechanismus v UI. Přes izolovanou
Caddy hranici ověřit, že vstupní falešná hlavička nepřežije přepis a globální
trusted-proxy blok je skutečně součástí výsledné konfigurace.

Exit: N+1 vrací 429, jiný grant/IP má své okno, healthcheck funguje a Node nemá
veřejnou canonical cestu s fallbackem na loopback identitu.

### 2. Zotavení po pádu bez ztráty výlučnosti

Změnit `storage.mjs`, `session.mjs`, `delegation.mjs`, shutdown v `main.mjs` a
přidat process lock helper a hosted keyed queue podle D2. Odstranit runtime
`mkdir/rmdir` process/profile locking; zachovat všechny refresh a intent critical
sections. Upravit README a test skutečného restartu, nikoli jen close/open.

Subprocess testy: druhý živý owner odmítnut, SIGKILL před i po data write, nový
owner okamžitě získá lock, data/šifrování zůstala čitelná, chybný klíč/acquire
nezanechá otevřený lock, graceful close je idempotentní. Stejný scénář pro
lokální profile lock. Hosted: různé SessionOwner instance stejného bindingu
neprovedou refresh souběžně; různé bindingy se neblokují; timeout čekajícího
neporuší držitele; po pádu nezůstane závislost na adresáři session locku.

Exit: SIGKILL/restart funguje bez mazání, dva procesy nemohou obsluhovat stejný
root a dvě operace nemohou souběžně rotovat stejný refresh token.

### 3. Bezpečná summary projekce v SQL a forward migrace

Implementovat D3 v kanonickém SQL, přidat novou forward migraci pro společné
fact helpery a summary RPC. Neměnit historickou `20261022233000_operator_order_management.sql`
ani foundation bytes. Nová migrace používá CREATE OR REPLACE stávajícího full
snapshotu se zachovanou signaturou, nikoli DROP CASCADE.

Zapojit nové/změněné signatury do existujících source/security kontraktů podle
`automation/canonical-source-contract.json`, `canonical-operation-sources.json`
a `database/functions/security/definer_contracts.json` spolu s explicitní ACL
deklarací v `database/functions/security/server_security_acl_manifest.json`. Generovat jen současné
odvozené kontrakty existujícím toolingem, nikdy přepisovat publikovanou migraci.

Rozšířit `make-orders-postgres.test.mjs` o raw RPC assertions před Node mapováním:
žádná PII pole/hodnoty ani revision, přesné peníze a ticket count shodné s full
ownerem, contact-only match nevrací řádek, symbol najde řádek i za více než 200
rušivými kontaktními shodami, detail a keyset, neznámé ID, foreign occasion/org/
unit, přesun akce a odvolaná role. Ověřit granty EXECUTE a private helpery.
Současné `orders-postgres.test.mjs` musí dál prokazovat full editor a mutace.

Exit: raw summary RPC nevrací citlivý JSON a full read/mutation kontrakty mají
zachované výsledky a oprávnění. Migrace je pouze lokálně aplikovaná v disposable DB.

### 4. Přepnutí všech summary konzumentů a odstranění staré cesty

Přepnout `orders.mjs`, `catalog.mjs`, `public-orders.mjs` a fixture dispatchery
v `make-transport.test.mjs`, `remote.test.mjs`, `operations.test.mjs` a SQL testech.
Aktualizovat jen skutečné volající nalezené scoped rg. Allowlist musí fungovat
také pro `dataProfile: order-summary` s libovolným registered client ID.

Odstranit full DTO mapping a kontaktní pagination workaround. Summary nesmí
odeslat full RPC ani při nedostupném novém RPC, špatném DTO, timeoutu nebo auth
chybě. Výstupní schémata MCP a OpenAPI zůstávají kompatibilní. Exact search
cursor zůstává null, protože symbol je unikátní; běžný seznam zachová keyset.
Obojí ověřit přes Make i MCP, včetně předaného `before`. Neodstraňovat unikátní
constraint kvůli testu fikce s duplicitními symboly.

Exit: Make HTTP a MCP summary list/detail používají pouze nový RPC; důkaz je
kontrola skutečného RPC dispatch i výsledku, nejen test mapperu.

## Deletion ledger

| Artefakt | Akce a důkaz |
| --- | --- |
| Inline limiter a persistentní `Rate` writes | Odstranit; všechny route guardy volají jediný limiter, stará data doexpirují. |
| Socket loopback jako veřejná client-IP | Odstranit pro canonical veřejné cesty; disposable a explicitní health probe jsou pojmenované výjimky. |
| `remote-process.lock` a `locks/<binding>` adresář jako autorita | Odstranit runtime producenty; jednorázové odstranění starých prázdných adresářů až po zastavení vlastníků. |
| `rmdir` při release locku | Odstranit; stabilní SQLite lock soubor se nikdy nemaže. |
| Full RPC ve summary větvi a čtyřstránkový workaround | Odstranit a ověřit dispatch testy; žádný fallback. |
| `publicOrders` full DTO mapper | Odstranit; ponechat explicitní summary schema/validaci. |
| Starý full SQL RPC a plný snapshot | Záměrně ponechat jako aktivní administrátorský kontrakt nad společnými fakty, nikoli jako summary kompatibilitu. |
| Historické migrace a datované evidence | Ponechat neměnné; aktuální README/architektura popisují nový stav. |

## Dokončení akceptace na následné výslovné zadání

Uživatel výslovně požaduje odstranit i oba zbývající acceptance blokery.
Úplný source inventory našel 112 chybějících aktuálních definer header deklarací
(104 bez explicitního manifest entry). Deklarace se doplní z přesných stávajících
source REVOKE/GRANT, se zachováním původních rolí, bez grandfather výjimky.
Pokus o kanonický upgrade staré autorizované fixture selhal na již existující
`notification_center_activation` při ledgeru končícím `20261023234000`.
Proto se stará fixture nepřepisuje: nový samostatný projekt
`festapp-mcp-hardening-20261029` na loopback portu 61032 vznikne kanonickým
`bootstrap_local_db.sh`. Guard povolí jen tuto přesnou marker/port identitu,
shodnou explicitní test URL a cron/email fence. Nová DB prošla celým parity
SQL i oběma order testy; staré passing runtime důkazy zůstávají platné pro
nezměněné runtime zdroje.

## Implementační upřesnění ověření

- `src/remote/main.mjs` již zavírá listener, po 30 s ukončí spojení a storage zavře až v close callbacku. Zdroj se proto nemění; nová idempotentní `storage.close()` drží kernel lock až do zavření hlavní DB.
- Kompletní Node sada v připnutém image byla skutečně spuštěna. Colima má 3.814 GiB pro již běžící ostatní projekty; při měření zbývalo 475816 KiB MemAvailable. TAP doložil `SIGKILL` remote test procesu při souběhu jeho nahromaděné paměti a Deno PDF fixture; samostatný artwork/boundary blok prošel. Acceptance proto rozdělí stejných 69 testů do sekvenčních procesů: 25 testů ostatních souborů a všech 44 remote testů v osmi skupinách nejvýše po šesti názvech (původní tříprocesové dělení ještě nestačilo). Stejné vstupy, žádný skip nebo změna produkčního image; jde jen o omezení paměťového maxima testovacího procesu.
- Původní úplný security gate selhal již nad výchozím HEAD: hlavička `manage_unit_agenda` má digest `1b3a1009003c7abc42b180831160765d629ec23db1ad433d14387311ad6aca78`, který není v HEAD declared ani grandfathered seznamu. Původní úplný DB source parity gate selhal na existujícím `abuse_effective_rules_v1(text,bigint,bigint)` v disposable fixture. Oba původní výsledky jsou vyřešeny následným dokončením: explicitní source/ACL deklarace a úplný kanonický bootstrap samostatné fixture. Security 7/7, ACL 112/112 a úplná parity nyní PASS. Staré sdílené fixture se nepřepisovaly.

## Ověření při implementaci

Plánování žádné další testy nespouští. Při implementaci validovat ucelené vlny,
ne každou editaci. Použít produkční Node 24 z připnutého image; předchozí review
běželo na lokálním Node 26, což není runtime acceptance gate.

- Z `tools/festapp`: `pnpm exec node --test --test-concurrency=1 test/rate-limit.test.mjs test/process-lock.test.mjs test/session-lock.test.mjs test/remote.test.mjs test/make-transport.test.mjs test/context.test.mjs test/operations.test.mjs test/remote-image.test.mjs`. Nové testovací soubory vytvořit v odpovídajících vlnách. Přidat stdio test jen pokud se mění jeho obsluha; profile locking už kryje subprocess test.
- Skutečná DB: cíleně `test/make-orders-postgres.test.mjs` a `test/orders-postgres.test.mjs` přes `pnpm exec node --test --test-concurrency=1` s `FESTAPP_MCP_TEST_DATABASE_URL` pro povolený disposable tenant. Test musí opravdu běžet, nikoli být skipped. Připravit nový forward schema cut; starý order test načítá historickou migraci a nesmí omylem přepsat nové funkce před ověřením.
- DB pouze přes guard `openDisposableDatabase`; ověřit paused email workers, fixture rollback a žádné produkční URL. Chybějící fixture je konkrétní blocker, ne důvod přepnout na produkci.
- `python3 automation/generate_canonical_source_contract.py --check` a z `tools/festapp` příkaz `pnpm exec node --test --test-concurrency=1 ../../automation/tests/server_security_migrations.test.mjs`. V povolené disposable DB spustit také `database/tests/canonical_mutation_source_parity_test.sql` existujícím guarded DB harness, nikoli proti produkci.
- Pro změněnou Edge 429 hranici: `deno test supabase/functions/mcp-session-exchange/handler_test.ts supabase/functions/mcp-session-exchange/management_test.ts` s repository import/cache konfigurací. Žádné skutečné vydávání session nebo produkční Edge volání v těchto testech.
- Caddy: validace výsledného kompletního configu, izolovaný proxy probe a Compose health probe; žádný reload produkce během implementace. Import/COPY test sám skutečný image/runtime startup neprokazuje.
- Lokální image: skutečný build/start připnutého Node 24 image s disposable volume, druhý owner a kill/restart smoke; žádné placené integrace nebo provider dispatch.

Úspěch reportovat stručně včetně přesných provedených příkazů a skipped/blockerů;
neoznačovat neprovedené DB/image/proxy gate jako splněné. Flutter task není potřeba.

## Rollout a návrat

Tato část je návrh samostatně autorizované operace, nikoli pokyn ji nyní provést.

1. Vybrat jeden tenant/issuer a ověřit aktivaci, ancestry, image/config revize,
   dostupný backup šifrovaného store i oddělených klíčů a účinný Caddy config.
2. Aplikovat pouze novou aditivní SQL forward migraci a ověřit scope, raw summary
   a shodu plného kontraktu. Starý sidecar může zatím dál číst starý full RPC.
3. Připravit a validovat Caddy přepis client-IP před novým sidecarem; starý jej
   ignoruje. Globální trusted proxy pravidla musí být skutečně účinná.
4. Zastavit starý sidecar, ověřit ukončení a nepřítomnost druhého vlastníka volume.
   Teprve pak odstranit přesně identifikované staré prázdné lock adresáře. Nikdy
   nemažte grantové DB, pending intents, lock SQLite soubory ani klíče.
5. Spustit nový immutable image na stejném volume, ověřit health, OAuth refresh,
   scope/odvolání, Make/MCP summary a skutečný process restart. Žádné re-consent
   ani změna grant expiry se migrací nevyžaduje.
6. Zapsat konkrétní release receipt se scope a revizemi. Local CLI přepnout až
   po ukončení starých CLI procesů; nepodporovat současný provoz starého mkdir
   a nového kernel lock protokolu nad stejným root/profile.

Rollback nesmí provozovat starý a nový image současně. SQL rozšíření nevracet
destruktivně. Preferovat opravný image zachovávající nový lock a summary kontrakt;
při nedostupném novém RPC summary selže uzavřeně. Nouzový návrat ke starému image
vrací známý rate/PII/crash problém a musí být explicitní incidentní rozhodnutí,
nikoli automatický fallback nebo běžná acceptance strategie.

## Předpoklady a zbývající rizika

- Jeden proces a lokální filesystem zůstávají provozním kontraktem. NFS/network
  filesystem nebo více replik vyžadují jiný návrh; nezapínat je jako součást opravy.
- SQLite exclusive lock nad samostatným souborem musí být prokázán subprocess
  testem a skutečným pinned image před přijetím vlny 2. Pokud prostředí tuto
  vlastnost neprokáže, aktualizovat D2 před pokračováním; nevracet stale mkdir.
- Globální Caddy trusted-proxy nastavení je doloženo zdrojem, ne live inspekcí.
  Owner rollout je odpovědný za výše uvedený gate; automatický trust arbitrary
  forward headers není přijatelné řešení.
- In-memory kvóty se restartem resetují, NAT sdílí IP limit. Zachovaná grantová
  kvóta, souběhové limity a downstream Auth ochrany tím nejsou nahrazeny.
- SIGKILL může přerušit odpověď po SQL commitu nebo rotaci downstream tokenu.
  Crash recovery lock není exactly-once garance. Zachovat stávající UUID/receipt
  a refresh recovery, testovat jejich kontinuitu a neslibovat bezpodmínečné
  zachování session, pokud downstream refresh skutečně nelze obnovit.

## Definice dokončení

- [x] Jediný limiter funguje na skutečné hranici, věří pouze normalizované proxy identitě a nevyřadí healthcheck.
- [x] Root i session locking přežijí nečisté ukončení a zachovají výlučnost; odstraněny staré runtime adresářové locky.
- [x] Summary SQL odpověď sama neobsahuje PII, exact search je SQL predikát a oba DTO sdílejí doménová fakta.
- [x] Všechny summary konzumenty přepnuty bez full RPC fallbacku, staré administrátorské kontrakty zůstaly funkční.
- [x] Všechny cílené gate včetně úplného security/source parity prokazatelně prošly; žádný povinný test není skipped.
- [x] Zdrojové/security kontrakty, README a deletion ledger odpovídají výsledku.
- [x] Lokální implementace a případné produkční nasazení mají oddělený, pravdivě uvedený stav.
