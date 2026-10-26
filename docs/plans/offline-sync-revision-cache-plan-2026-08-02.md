# Kanonický polling sync, offline revize a distribuční cache

> Historical design baseline. Current hardening and operational contracts are
> authoritative in `client-sync-production-hardening-plan-2026-08-05.md`.

Date: 2026-08-02; mutation architecture hardened 2026-08-03

Status: Ready for execution

Verification: release pro jednu koordinovanou produkční migraci

## Outcome

Festapp po startu okamžitě zobrazí poslední lokálně potvrzená data. Jediný
`ClientSyncService` řídí všechny refresh důvody a jeden foreground scheduler.
Každých přibližně 15 sekund ověří přes Cloudflare malý veřejný head; přihlášený
uživatel v témže scheduleru nejvýše jednou za 60 sekund ověří private revision
vector přes Supabase RPC. Změněné veřejné komponenty stáhne jako immutable
artifacts z CDN, změněný soukromý overlay autorizovaně ze Supabase.

Programový katalog neobsahuje počty přihlášených. Ty vznikají jako malý
materializovaný `live_public` read model pouze po relevantním zápisu a přes
Cloudflare se fan-outují všem klientům. `get_events` se tedy při každém čtení
nesmí znovu procházet `event_users`/`event_users_saved` ani sestavovat celý
program v PostgreSQL.

Nebude použit Supabase Realtime, Broadcast ani paralelní invalidační mechanismus.
Nebude existovat ani entity-level delta journal, tombstones nebo skládání
snapshotu s delta ocasem. Jedinou synchronizační jednotkou je úplná verzovaná
komponenta. Smazání entity se projeví její nepřítomností v nové komponentě.

Produkční přechod pro `csmostrava2026` proběhne jako jeden release: aditivní
backend, publisher, kompletní klient, audit a jeden capability cutover
`client_sync_v1`. Starší podporované aplikace dál používají nezměněná legacy
RPC na tenké compatibility hranici. Nový klient si při bootstrapu zvolí celý
legacy, nebo celý v1 režim; nikdy je nemíchá v jednom aktivním kontextu.

Každá logická změna vytvoří ve stejné DB transakci jeden immutable **sync
commit**. Commit obsahuje aktéra, důvod/zdroj, bezpečný diff a výsledné revize
dotčených komponent. Admin získá online-only tab **Změny**, který tento commit
ledger zobrazuje. Ledger není offline cache ani technická publisher fronta a
klienti z něj změny nepřehrávají.

„Aktuální offline data“ znamenají poslední atomicky potvrzenou serverovou verzi
se zobrazeným časem. Zařízení bez sítě nemůže znát pozdější změny a UI to nesmí
prezentovat jako živý stav.

## Rozhodnutí, která návrh zjednodušují

1. **Polling je jediný mechanismus freshness.** Žádný Realtime fallback ani
   druhý timer v jednotlivých stránkách.
2. **Komponenta se vždy nahrazuje celá.** Žádné delty, tombstones, cursory,
   journal retention nebo konfliktní merge pravidla.
3. **Jeden klientský vlastník.** `ClientSyncService` vlastní lifecycle, síť,
   single-flight, lokální commit a stav pro UI.
4. **Jedna orchestrace, dvě trust/cache hranice.** Veřejný edge head je společný
   a cachovatelný; private handshake je autorizovaný a necachovatelný. UI zná
   pouze jeden `ClientSyncService`, nikoli dva refresh mechanismy.
5. **Veřejné a soukromé doručení jsou oddělené.** Public data mohou do CDN;
   private data nikdy nedostanou veřejnou artifact URL.
6. **Idempotency receipt a audit commit jsou rozdílné věci.** Každý dokončený
   command má replayovatelnou receipt, ale pouze skutečná změna stavu vytvoří
   append-only audit commit a posune component revisions. Snapshot říká
   aktuální stav; ledger vysvětluje, proč se head revize změnila. Publisher ani
   klient z ledgeru nereplayují data.
7. **Compatibility je jen na hranici starých binárek.** Uvnitř nové aplikace po
   cutoveru nezůstane žádný alternativní loader ani skrytý fallback.
8. **Závislé položky nejsou vedlejší feedy.** Place types, paths a ikony jsou
   součást `map_catalog`; jejich společnou konzistenci připíná jeden nadřazený
   release manifest.
9. **Současný textový objem nevyžaduje lazy program.** První online bootstrap
   stáhne kompletní public component set pro skutečný offline režim. Další
   kontroly stahují pouze malý head a změněné digests; přepnutí tabu nikdy znovu
   nestahuje nezměněný program. Obrázky a mapové dlaždice zůstávají oddělené
   content-addressed/lazy assety.

### Průmyslové vzory použité v návrhu

- Google resource-oriented API guidance výslovně varuje před API, které jen
  zrcadlí databázové schéma, a custom methods pojmenovávají doménový záměr;
  Festapp proto používá explicitní commands místo remote CRUD tabulek:
  <https://google.aip.dev/121>, <https://google.aip.dev/136>.
- Google update guidance používá resource version/etag pro optimistic
  concurrency; Festapp používá monotónní aggregate version oddělenou od sync
  revision: <https://google.aip.dev/134>.
- Stripe a Shopify vážou idempotency key na původní request a replayují uložený
  výsledek; stejný princip má oddělená mutation receipt s request hashem:
  <https://docs.stripe.com/api/idempotent_requests>,
  <https://shopify.dev/docs/api/usage/idempotent-requests>.
- PostgreSQL row locks a isolation pravidla jsou autoritativní mechanismus pro
  contested capacity/stock rozhodnutí, nikoli následná klientská kompenzace:
  <https://www.postgresql.org/docs/17/explicit-locking.html>,
  <https://www.postgresql.org/docs/14/transaction-iso.html>.
- Supabase doporučuje invoker jako výchozí function security a u definer funkce
  explicitní `search_path`/grants; RPC volané z klienta je proto samostatná
  bezpečnostní hranice:
  <https://supabase.com/docs/guides/database/functions>.
- Android offline-first guidance požaduje, aby vyšší vrstvy četly z lokálního
  zdroje pravdy a repository synchronizovalo síť do něj; UI tedy nikdy nebude
  přímo dotahovat place types nebo icons:
  <https://developer.android.com/topic/architecture/data-layer/offline-first>.
- OCI manifest model používá descriptors s media type, digestem a velikostí pro
  content-addressed komponenty. Festapp nepřebírá container formát, ale stejný
  ověřitelný manifest→components princip:
  <https://github.com/opencontainers/image-spec/blob/main/manifest.md>.
- TUF snapshot metadata připínají verze, délky a hashe všech targetů a při
  nesouladu update zahodí. Festapp používá stejnou atomic/mix-and-match ochranu,
  bez zbytečné podpisové infrastruktury v první verzi:
  <https://theupdateframework.github.io/specification/v1.0.19/>.
- RFC 8246 standardizuje versioned immutable URL s dlouhou freshness; public
  artifacts proto mají revision/digest v cestě a
  `Cache-Control: public, max-age=31536000, immutable`:
  <https://www.rfc-editor.org/rfc/rfc8246.html>.
- Cloudflare u R2 custom-domain cache výslovně upozorňuje na cached 404 a starý
  obsah při přepisování klíče. Proto se publikovaný klíč nikdy nepřepisuje a
  manifest pointer se posune až po ověřeném uploadu:
  <https://developers.cloudflare.com/r2/reference/consistency/>.
- CQRS/materialized-view pattern odděluje transakční write model od
  denormalizovaného read modelu a dovoluje oba škálovat nezávisle; přesně to
  potřebují event counts proti programu:
  <https://learn.microsoft.com/azure/architecture/patterns/cqrs>.
- Transactional outbox řeší atomický DB write + pozdější publikaci bez
  distribuované transakce; publisher musí být idempotentní a počítat s retry:
  <https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/transactional-outbox.html>.
- Workers KV je eventual-consistent až desítky sekund a není vhodné pro často
  přepisovaný hot key; Durable Object by přidal nový koordinující source. Pro v1
  se proto nepoužije ani jedno: malý public head čte Worker přímo přes strongly
  consistent R2 binding a krátce jej cachuje na edge:
  <https://developers.cloudflare.com/kv/concepts/how-kv-works/>,
  <https://developers.cloudflare.com/r2/reference/consistency/>.

## Scope

### In scope

- Veřejná data akce: config, program, místa a jejich typy, trasy, informace,
  novinky, přednášející, veřejné skupiny a veřejný stav úklidu.
- Proměnlivý veřejný stav: počty účastníků/uložení, kapacity a malé odvozené
  hodnoty, které nemají nutit rebuild velkého programu.
- Soukromé komponenty: moje přihlášení a program, přečtené novinky, profil,
  skupina, ubytování/inventory, moje aktivity a stav feedbacku.
- Scoped Sembast cache s atomickým manifest pointerem a oddělenými public/private
  namespaces.
- Monotónní revize, immutable public artifacts, publisher a CDN.
- Centrální foreground polling, reconnect/resume sync, single-flight a backoff.
- Compatibility pro vydané klienty, kill switch a pozdější odstranění legacy.
- Append-only sync commit ledger jako audit sync-relevantních změn a
  `Admin → Změny`.
- Release monitoring, load test, rollback a absence proofs.

### Out of scope

- Realtime, Broadcast, websocket invalidace a background polling.
- Entity-level delta API, tombstones a dlouhodobé klientské cursory.
- Offline fronta mutací. Kapacitní/konfliktní zápisy zůstávají online-only.
- Offline admin, velké admin bundle a univerzální audit všech tabulek Festappu.
- Automatické stažení PMTiles/MBTiles; `OfflineMapBundleManager` zůstává
  samostatný instalační kontrakt.
- Nahrazení Supabase jako zdroje pravdy nebo cachování autorizace v CDN.

## Current-state evidence

| Zjištění | Evidence | Dopad |
|---|---|---|
| Offline JSON je v Sembastu, ale klíče nejsou scoped podle organizace/akce/uživatele. | `lib/services/storage_helper.dart`; `lib/data_services/offline_data_service.dart` | Nové úložiště musí používat scoped generace a identity epoch. |
| `refreshOfflineData()` sériově stahuje mnoho datasetů a nastaví jediný timestamp. | `lib/data_services/synchro_service.dart` | Nelze poznat částečné selhání; sync musí mít per-component revize a atomický commit. |
| Program ručně kombinuje local, `get_events(false)` a `get_events(true)`. | `lib/components/schedule/schedule_page.dart` | Nový klient musí mít jeden stavový tok bez page-level loaderů. |
| `EventModel` míchá public katalog, počty i user flags. | `lib/components/schedule/event_model.dart` | Public artifact potřebuje vlastní DTO bez soukromých polí. |
| `get_events` při každém čtení agreguje `event_users` a `event_users_saved` a současně připojuje private user flags. | `database/functions/events/get_events.sql` | Statický program, živé veřejné počty a privátní overlay se musí oddělit; běžné veřejné čtení nesmí znovu skenovat vztahové tabulky. |
| Produkční public payload CSM Ostrava má při 939 eventech: program s popisy 577 140 B raw / 156 533 B gzip; bez popisů 297 978 B / 42 254 B. Program + speakers + news + information + places + paths + icons + place types mají dohromady 849 070 B raw / 228 490 B po síti. | Read-only měření produkčních public RPC/PostgREST odpovědí 2026-08-02 | Na současném objemu je úplný programový replacement levnější a čistší než lazy description API; obrázky do tohoto payloadu nepatří. |
| Logout nemaže events s uživatelskými příznaky. | `lib/data_services/offline_data_service.dart` | Public a private store musí být fyzicky oddělené. |
| Login spouští sync programu a celý offline refresh souběžně. | `lib/data_services/auth_service.dart`; `lib/data_services/synchro_service.dart` | Jeden koordinátor musí deduplikovat lifecycle požadavky. |
| Program dnes reaguje na změnu tabu a má vlastní 10s rate limit; několik stránek samostatně refreshuje při `resumed`. | `lib/components/schedule/schedule_page.dart`; `schedule_basic_page.dart`; `schedule_light_page.dart`; `occasion/occasion_home_page.dart` | Uživatelsky správný navigation/resume trigger zachovat, ale převést jej do jednoho koordinátoru a odstranit page-level síťové loadery. |
| Search je derived index nad několika offline datasety. | `lib/components/search/db_search.dart` | Index se váže na aktivní component manifest a rebuildne po jeho commitu. |
| Mapa už používá immutable version, SHA-256, staging a atomický pointer. | `lib/components/map/offline_map_bundle_manager.dart` | Stejný ověřený vzor lze použít pro JSON komponenty. |
| App config už posílá platform/version, ale klient a SQL mají drift `v217`/`v218`. | `lib/data_services/synchro_service.dart`; `database/functions/others/get_app_config.sql`; `web_client/src/services/rights_service.js` | Capability handshake vyžaduje předem ověřenou compatibility matici. |
| Neexistuje jednotný audit programu/mapy/obsahu/skupin/ubytování. | `eshop.orders_history`; `public.activity_history`; `public.cleaning_reports`; technické logy | Nový sync commit ledger musí být vlastní modul; současné doménové historie se neruší. |
| Řada sync-relevantních adminských zápisů dnes obchází RPC a používá PostgREST DML. | `lib/components/schedule/db_events.dart`; `map/db_places.dart`; `information/db_information.dart`; `news/db_news.dart`; `groups/db_groups.dart`; `icons/db_place_types.dart`; `users/db_users.dart` | Pouhé doplnění commit helperu do několika RPC není úplné; každý direct writer se musí migrovat nebo být po dobu compatibility mechanicky hlídaný. |
| Sync-relevantní data mění také SQL importy a složené funkce. | `update_activities.sql`; `import_occasion_users_from_csv.sql`; `import_user_group_assignments.sql`; `delete_occasion_user.sql`; `delete_event.sql`; speaker/cleaning/inventory RPC | Writer inventory musí zahrnout vnořené změny a vazebné tabulky, ne pouze UI tlačítka. |
| Cron `sync_source_via_http` přímo upsertuje/maže `occasions`; další servisní a recovery skripty mohou psát pod privilegovanou rolí. | `database/functions/synchronization/sync_source_via_http.sql`; `database/recovery/` | Service-role/DBA cesta je samostatný writer a musí mít commit context nebo explicitní break-glass audit. |
| Cloudflare R2 `festapp-public` existuje, `assets.festapp.net` je aktivní s TLS 1.2+, `r2.dev` je vypnuté a immutable mapový manifest odpovídá 200 se správným cache headerem. `sync.festapp.net` zatím v DNS neexistuje. | Read-only Wrangler/DNS/HTTP preflight 2026-08-02; `docs/plans/offline-sync-preflight-baseline-2026-08-02.md` | Artifact hranice je připravená; nový head Worker a jeho DNS zůstávají explicitní součást Wave 2/6, nikoli skrytý předpoklad. |

### Facts, decisions, assumptions and blockers

- **Fact:** dnešní source of truth je Supabase PostgreSQL; Cloudflare nyní
  hostuje Pages/image R2 hranice, nikoli autoritativní aplikační data.
- **Fact:** současná offline cache obsahuje program, places, paths, icons,
  place types, information, news, speakers, cleaning status, occasion/settings
  a user-scoped profil/skupinu, saved program, activities, vlastní inventory a
  feedback stav. Některé se plní mimo `SynchroService` přímo ze stránek.
- **Fact:** současní writeři jsou směs direct PostgREST DML, RPC, importů, cronů
  a servisních/operational skriptů; bez migrace není commit coverage úplná.
- **Fact:** produkční `event_feedback` tabulka a všech šest RPC byly 2026-08-02
  read-only porovnány s recovery snapshotem a mají nyní canonical source v
  `database/tables/event_feedback.sql` a
  `database/functions/events/*event_feedback*.sql`.
- **Fact:** produkční PostgreSQL má `log_statement = ddl`, nemá `pgaudit` a
  `pgaudit.log = none`; samotná DB tedy nyní nedokládá privileged DML audit.
- **Decision:** Supabase vlastní zápisy/heads/private handshake; Cloudflare R2
  vlastní pouze public immutable artifacts; klient používá polling.
- **Decision:** component source registry je jediný coverage seznam a každý
  materiální serverový save musí mít právě jeden commit.
- **Assumption:** 15sekundový public edge poll, 60sekundový indexed private
  handshake a full-component velikosti projdou produkčně podobným load/size
  testem. Pokud ne, cutover se blokuje a mění se komponentizace nebo interval,
  nikoli se potají přidá druhá cesta.
- **Owner-approved exception (2026-08-03):** vlastník odmítl placený externí
  Supabase Log Drain. Produkce má pgaudit `write` aktivní pro `postgres` a
  `authenticator` a zůstává fingerprint reconciliation, ale auditní evidence
  není nezávisle dlouhodobě uchovávaná mimo Supabase. Toto zbytkové riziko je
  pro web-only CSM cutover výslovně přijato; `pg_stat_statements` se nadále
  nepovažuje za auditní ledger.
- **Blocker:** `sync.festapp.net` Worker/DNS ještě neexistuje a musí vzniknout v
  autorizované release wave. `festapp-public` a `assets.festapp.net` jsou již
  read-only ověřené.

## Cílová architektura

### Síťová a úložná hranice

```text
ZÁPISY + AUTORIZACE + HEAD REVIZE + PRIVATE DATA
Flutter/Web ──RPC──> Supabase PostgreSQL

VEŘEJNÉ VELKÉ ČTENÍ
publisher ──build/upload──> Cloudflare R2 `festapp-public`
Flutter/PWA ──GET immutable artifact──> `assets.festapp.net`

VEŘEJNÝ FRESHNESS HEAD
Flutter/PWA ──GET + ETag──> `sync.festapp.net`
                           Cloudflare Worker
                           └─ R2 binding: public head + immutable live descriptor

APP SHELL
prohlížeč ──HTML/JS/WASM──> Cloudflare Pages
```

Cloudflare nenahrazuje Supabase. Supabase zůstává zdrojem pravdy, vlastní
transakce, oprávnění, commit ledger, component heads a private payloady.
Cloudflare Pages servíruje aplikaci; R2/CDN veřejné immutable snapshoty; nový
stateless `sync-worker` pouze malý cacheable public head. Worker nikdy
neautorizuje mutaci, neukládá private data a při klientském requestu nevolá DB.
`img.festapp.net`/`festapp-images` zůstává image pipeline. Kanonický public sync
target je samostatný prefix v `festapp-public` na `assets.festapp.net` a head na
`sync.festapp.net`; Supabase Storage, KV, Durable Objects ani `r2.dev` nejsou v1
fallback. Pokud tyto hranice nejsou dostupné, cutover se zastaví.

### Kanonická write architektura

Autoritativní detail je v `docs/architecture/mutations.md`. Standardizuje se
lifecycle a bezpečnost mutace, nikoli doménové DML: **jeden uživatelský záměr =
jeden explicitně pojmenovaný doménový RPC = jedna PostgreSQL transakce**. Běžné
tvary jsou entity command, aggregate replacement, guarded transition a
draft/publish; import je bounded set-based varianta. Univerzální CRUD RPC,
cross-domain `CASE` dispatcher, table-name API a klientský
`execute(String rpc, Map payload)` jsou zakázané.

Veřejný RPC kontrakt používá typed context/concurrency parametry a pouze u
agregátu dokumentované JSON DTO, nikdy raw table row. Výsledek má status
`applied|unchanged|rejected|conflict`, autoritativní `data`, mutation receipt a
`sync.replacements`. Command UUID vzniká na hranici uživatelského záměru a
zůstává stejný při všech retry. `client_mutation_receipts` claimne ID + request
hash před DML a ukládá přesnou response; stejné ID s jiným hashem je conflict.
Pouze `applied` změna vytvoří auditní `client_commit`, items, revisions a dirty
keys. No-op, odmítnutí a conflict jsou replayovatelné, ale nevyrábějí falešný
audit změny.

Sdílený kernel tvoří pouze negrantované helpers
`begin_client_mutation_v1`/`finish_client_mutation_v1`. Smějí znát receipts,
commit/revision metadata a dirty keys, ne doménové tabulky, auth pravidla nebo
lock pořadí. Sdílí se envelope, idempotence, audit/sync finalizace, error mapping
a atomická aktivace response; doménové invarianty zůstávají v explicitních
RPC. Po stabilizaci 2–3 referenčních slices lze přidat build-time manifest či
generovat typed bindings/grant tests, ne runtime routing.

Protože RPC volá přímo nedůvěryhodný klient, každý grantovaný function je
internet-facing auth hranice: actor pochází z `auth.uid()`, scope/ownership z
autoritativních relací, payload je bounded a odmítá neznámé keys, všechny IDs se
ověří proti scope a sync/audit impacts hardcoduje server. Výchozí je
`SECURITY INVOKER`; nutný `SECURITY DEFINER` má prázdný `search_path`, plně
kvalifikované objekty, explicitní auth a minimální grants.

Čisté DB záměry jdou klient → explicitní RPC. Záměry se secrets, externím nebo
dlouhým side effectem jdou klient → authenticated Edge → úzký service-only DB
command, který atomicky zapíše stav + outbox; idempotentní worker dokončí efekt.
Edge nesmí dělat libovolné service-role DML. `client_projection_dirty_keys` je
specializovaný outbox, nikoli začátek event sourcingu nebo obecného message busu.

Editor aggregate replacement používá monotónní `bigint` aggregate version
oddělenou od sync component revision. Kapacita, stock, ticket a allocation
transition zamykají autoritativního vlastníka rozhodnutí v dokumentovaném pořadí
před čtením a rozhodnutím. `sign_user_to_event` se proto musí přepsat/extrahovat
s locky, ne pouze obalit; activities publish spojí history PUBLISH a live graph
replacement v jediném `publish_activities_v1`.

```text
doménový write
  └─ stejná DB transakce
       ├─ změní source data
       ├─ zvýší revision dotčených komponent
       └─ zapíše 1 immutable commit + items + component heads

publisher (interní periodický worker, jediný DB čtenář public projekcí)
  └─ pollne coalesced dirty scopes/keys
       ├─ sestaví úplnou public komponentu
       ├─ pro dirty event/place keys obnoví malý live_public read model
       ├─ ověří schema + hash
       ├─ uloží immutable artifact do CDN
       └─ monotónně posune R2 public head

ClientSyncService (jediný foreground poller)
  ├─ public tick: GET sync.festapp.net head (15 s, edge cached)
  │    ├─ unchanged/304 → nic
  │    ├─ nový release manifest → CDN component downloads
  │    └─ nový live descriptor → CDN live_public download
  └─ private tick: get_private_client_sync_v1 (60 s, auth)
       └─ changed private components → scoped replacements
```

Publisher poll není druhá klientská invalidace. Je to interní scheduler odvozené
cache a jediný způsob tvorby public artifacts. Na klientovi existuje jeden
scheduler a jedna metoda `refresh`; pouze respektuje dvě legitimní trust/cache
hranice. Žádný feature tab nemá vlastní timer nebo síťový fallback.

### Kanonický klientský modul

Novým vlastníkem bude `lib/data_services/client_sync/ClientSyncService`:

```dart
Stream<ClientSyncState> open(SyncContext context);
Future<void> refresh({SyncReason reason});
Future<void> closeContext();
```

Interní hranice:

- `PublicSyncHeadRemote`: cacheable `GET` na `sync.festapp.net`, bez auth/PII.
- `PrivateSyncRemote`: jediné auth RPC `get_private_client_sync_v1`.
- `PublicComponentRemote`: stáhne immutable artifact a ověří hash/schema.
- `ClientSyncStore`: staging komponent, component pointers, atomický manifest
  pointer, schema migrace a identity epoch.
- `SyncPollingPolicy`: jediný timer, jitter, single-flight a backoff.
- `SyncProjection`: skládá catalog + `live_public` + private overlay do
  read modelu pro UI; nikdy je nezapisuje zpět jako smíšený blob.
- Feature-specific typed command ports (`EventCommands`, `MapCommands`,
  `ActivityCommands`, …) volají staticky svázané RPC přes interní transport a
  předávají `sync.replacements` do stejného atomického activation mechanismu.

UI nezná URL, Sembast klíče, RPC verze ani polling timer. Tab Program, Mapa,
Informace, Profil a Search pouze sledují `ClientSyncState`/repositories.

### Polling kontrakt

- Po cold startu, změně kontextu, login/logout, návratu do foregroundu a
  obnovení connectivity se požádá o okamžitý public i relevantní private check.
- Přepnutí hlavního occasion tabu vyšle centrálně `SyncReason.navigation`.
  Koordinátor okamžitě zobrazí lokální data a provede pouze freshness check:
  public request jen pokud poslední úspěšná kontrola je starší než 15 sekund
  nebo chybí required catalog; private RPC jen pokud cílová projection private
  data potřebuje a její kontrola je starší než 60 sekund. Opakované překliknutí
  uvnitř okna nevytvoří request.
- Navigation trigger nesmí požádat o „data tohoto tabu“ zvláštním endpointem.
  Kontroluje stejné globální heads a stáhne pouze jejich neznámé digests; tím
  zachová současný pocit čerstvosti bez návratu feature side-loaderů.
- V popředí běží právě jeden scheduler s base tickem 15 sekund a jitterem 0–3
  sekundy. Každý tick kontroluje public head; každý čtvrtý úspěšný tick nebo
  lifecycle trigger kontroluje private vector. Interval není v žádné stránce.
- V backgroundu se timer zastaví. Neexistuje background wake-up ani websocket.
- Souběžné důvody se sloučí do jednoho in-flight requestu. Pozdní odpověď ze
  starého user/occasion epoch se zahodí před zápisem.
- Public a private request mají oddělený single-flight/error/backoff state, aby
  výpadek private RPC nezastavil veřejný program. UI však dostává jeden složený
  `ClientSyncState` s per-class freshness.
- Po neúspěchu se zachová poslední zdravá generace; retry je 15, 30, 60, 120 a
  maximálně 300 sekund. Úspěch dané třídy resetuje její backoff. Reconnect/resume smí vyvolat
  jeden okamžitý pokus, ale stále respektuje single-flight.
- Úspěšná vlastní mutace vrací autoritativní změněnou private/live hodnotu
  nebo její novou revizi a aplikuje se okamžitě. UI nečeká na další poll ani
  nespouští full refresh.
- Ruční Refresh volá stejnou metodu `refresh`; nevytváří druhou síťovou cestu.
- Čas a scheduler jsou injectované, aby testy nepoužívaly reálné čekání.

Výchozí freshness SLO:

- vlastní potvrzená mutace a autoritativní count po sign-in/out: okamžitě z RPC;
- cizí `live_public` změna aktivnímu online klientovi do 25 sekund p95
  (publisher/coalescing ≤5 s, edge TTL ≤5 s, poll+jitter ≤18 s; fáze se mohou
  překrývat);
- strukturální public změna do 45 sekund p95;
- cizí private změna do 75 sekund p95.

SLO se ověří load testem. Public interval lze zkrátit bez zvýšení DB read loadu,
protože klientské public requesty končí na Cloudflare; nesmí se ale změnit bez
ověření Worker/R2 request cost a battery/network budgetu.

Výchozí payload budgets pro současný scale:

- `program_catalog` nejvýše 1 MiB raw a 300 KiB compressed;
- celý povinný public component set nejvýše 5 MiB raw a 1 MiB compressed;
- `live_public` nejvýše 100 KiB compressed;
- public head nejvýše 16 KiB.

Publisher změří raw/compressed bytes a překročení budgetu zablokuje cutover nebo
publication s alarmem. Teprve naměřené překročení je důvod rozdělit strukturální
komponentu; klient nesmí předem zavádět lazy event-description endpoint. V
prohlížeči se stažené komponenty ukládají content-addressed do lokálního store a
do UI se materializuje pouze projection aktivní obrazovky, nikoli opakovaná
kopie celého JSON pro každý tab.

### Public edge head a private handshake

`GET /v1/public-sync/{organization}/{occasion}/head` na `sync.festapp.net`
vrací bez PII malý `PublicSyncHead`. Worker čte přes R2 binding jeden aktuální
head objekt, podporuje `ETag`/`If-None-Match` a odpověď edge cachuje nejvýše 5
sekund; browser TTL je 0 a musí revalidovat. Worker při requestu nikdy nevolá
Supabase. R2 binding obchází relaxed custom-domain cache, takže mutable head
nemůže uváznout jako cached 404; všechny odkazované payloady jsou immutable.

`get_private_client_sync_v1(p_context, p_known_private_vector)` je `STABLE`,
read-only a autorizovaný Supabase RPC. Čte jen indexované private revision rows
a změněné private projections. Nevkládá heartbeat, telemetry ani commit.

Public head obsahuje:

- protocol/schema verzi a server time;
- descriptor jediného immutable public release manifestu, pokud se jeho
  `releaseRevision` liší; manifest připíná přes revision, media type, URL,
  SHA-256 a velikost přesně jednu verzi každé required komponenty;
- descriptor immutable `live_public` snapshotu s vlastní revizí/hash/velikostí;
- `publicationPending`, pokud source revisions předběhly poslední kompletní
  release manifest nebo live projection; klient ponechá předchozí validní data;
- minimální podporovanou klientskou/schema verzi a explicitní error stav.

Private RPC obsahuje pouze změněné private component replacements a jejich
revision vector. Public head ani public artifacts nikdy neobsahují auth token,
user ID, `isSignedIn`, `isSaved`, group membership nebo vlastní ubytování.

Příklad tvaru, který Wave 1 uzavře golden testem:

```json
{
  "protocol": 1,
  "serverTime": "2026-08-02T14:31:00Z",
  "catalog": {
    "releaseRevision": 124,
    "manifestUrl": ".../manifests/124-<hash>.json",
    "manifestSha256": "...",
    "manifestBytes": 1240
  },
  "live": {
    "revision": 9812,
    "url": ".../live/9812-<hash>.json.br",
    "sha256": "...",
    "bytes": 28420
  }
}
```

Release manifest například připne `program_catalog@93`, `map_catalog@18`,
`content_catalog@22`, `occasion_config@17` a `unit_catalog@6`. Klient porovná
descriptors s lokálním manifestem a stáhne pouze ty komponenty, jejichž digest
nezná. Nezměněné blobs znovu použije. Breaking změna vyžaduje protocol v2 vedle
v1; v1 pole jsou během compatibility additive-only.

### Komponenty a vlastnictví

| Komponenta | Obsah | Doručení | Nahrazení |
|---|---|---|---|
| `occasion_config` | features, timezone, public settings, map manifest ref | CDN | úplné |
| `program_catalog` | event core+description, place refs, groups/roles, cancellation; bez counts/user flags | CDN | úplné |
| `map_catalog` | places, place types, paths a úplné záznamy právě těch SVG ikon, na které viditelné položky odkazují | CDN | úplné jako jeden aggregate |
| `content_catalog` | information, news, speakers, topics a vazby | CDN | úplné |
| `unit_catalog` | public/promoted occasions pro unit context | CDN | úplné |
| `live_public` | participant/saved counts, odvozená remaining capacity a public cleaning state | immutable R2 snapshot přes public edge head | úplné, malé, vlastní freshness třída |
| `private_program` | sign-ins a saved IDs | auth RPC | úplné |
| `private_profile` | profil, skupina a členové | auth RPC | úplné |
| `private_inventory` | vlastní ubytování/inventory | auth RPC | úplné |
| `private_activity` | moje activities a feedback state | auth RPC | úplné |
| `private_news` | read markers | auth RPC | úplné |
| `anonymous_program` | lokální saved IDs před loginem | device-only | explicitní jednorázový import |
| `search_index` | derived index nad aktivními public komponentami | local-only | rebuild |

Public eligibility je allowlist podle visibility a práv. Private/hidden occasion
nikdy nedostane public URL. Změna public → hidden zastaví publication, odstraní
pointer a spustí explicitní artifact delete + CDN purge runbook. Již staženou
kopii na trvale offline zařízení nelze fyzicky odvolat; proto public artifact
nesmí obsahovat nic, co není skutečně veřejné.

### Revize a publisher

- `client_sync_scopes` drží právě jednu `source_revision` pro component/scope.
- Sync-relevantní write zvýší každou dotčenou revision nejvýše jednou za
  logickou operaci a ve stejné transakci vytvoří právě jeden sync commit.
- Změna sdílené dependency používá registry reverse lookup: například změna SVG
  ikony bumpne `map_catalog` všech occasion/unit scopes, jejichž place, place
  type nebo path ji referencuje. Fan-out zůstane jedním commitem s více
  `client_commit_components`, nikoli sérií falešných auditních akcí.
- Před aktivací v1 jsou všechny podporované sync writery převedené na explicitní
  RPC/service boundary. Na sync source tabulkách nevzniká persistentní
  aplikační trigger ani commit-context guard.
- `client_sync_publications` drží ověřené immutable component artifacts a jejich
  monotónní `published_revision`; `client_sync_release_manifests` eviduje
  immutable sestavy descriptors a `client_sync_public_heads` právě jeden
  atomicky měněný manifest pointer na public scope.
- `client_projection_dirty_keys` je bounded upsert set, ne historický journal:
  `(component, scope, entity_id)` existuje nejvýše jednou bez ohledu na počet
  mezilehlých commitů. Vzniká ve stejné transakci jako source write/commit.
- `event_public_state` a `cleaning_public_state` jsou materializované read modely
  pro rychlé exporty; nejsou autoritativní pro sign-in, kapacitu nebo práva.
- Publisher každých nejvýše 5 sekund polluje pouze dirty scopes/keys, claimuje
  je přes `FOR UPDATE SKIP LOCKED` a koaleskuje burst změn. U event IDs přepočte
  counts z autoritativních relations přes indexy, aktualizuje read model a
  vytvoří jeden nový immutable `live_public` snapshot za occasion.
- Source RPC sestaví komponentu v jednom konzistentním PostgreSQL statement
  snapshotu. Artifact obsahuje scope, revision, schema, generatedAt a hash.
- Starší nebo souběžně dokončený worker nesmí přepsat novější pointer; pointer
  update je podmíněný a monotónní.
- Publisher nejprve připraví všechny dirty component artifacts, potom vytvoří
  immutable release manifest s descriptors celé konzistentní sady a teprve
  nakonec atomicky posune jediný public manifest pointer. Jeden commit měnící
  mapu i program se proto veřejným klientům neukáže jako mix staré/nové verze.
- Selhání uploadu/validace pointer neposune. Klient dál používá poslední
  publikovaný release manifest a handshake hlásí pending.
- Po ověřeném uploadu publisher přes R2 API atomicky přepíše pouze malý
  `public-head.json`; versioned catalog/live payloady se nikdy nepřepisují.
  `sync-worker` čte head přes R2 binding, vrací `ETag`, `Cache-Control:
  public, max-age=0, must-revalidate` pro browser a edge TTL nejvýše 5 sekund.
- Periodická reconciliation porovná source/published revize a opraví ztracený
  dirty claim; zvlášť porovná materializované event counts s reálnými relations
  a opraví drift. Neprovádí full rebuild zdravých statických komponent.
- Retention public artifacts je počet ověřených verzí + minimální časové okno,
  ne sync cursor. Poslední published a verze potřebná pro rollback se nemažou.

### Coverage registry a ochrana proti neauditovanému zápisu

Jediným autoritativním seznamem synchronizace bude verzovaný **component source
registry**. Pro každou source tabulku/vazbu uvádí component, public/private
scope resolver, sledované sloupce, canonical mutation RPC, legacy writery a
test factory. Snapshot query, revision capture, commit audit a test coverage se
musí odkazovat na stejný registry; čtyři nezávislé ruční seznamy jsou zakázané.

Minimální registry vycházející z dnešní cache a čtecích RPC:

| Component | Potvrzené source tabulky/vazby | Typické writery, které je nutné pokrýt |
|---|---|---|
| `occasion_config` / `unit_catalog` | `organizations`, `units`, `occasions`, relevantní `features/data` | occasion/unit RPC, duplication/deletion, `sync_source_via_http`, config editor |
| `program_catalog` | `events`, `event_groups`, `event_roles`; event↔speaker reference ovlivní projection | přímý `DbEvents` DML, `delete_event`, counseling slot RPC, activities/import helpers |
| `map_catalog` | `places`, `place_types`, `path_groups`, `icons` | `DbPlaces`, `DbPlaceTypes`, icon admin, `save_place_location`, occasion duplicate/delete |
| `content_catalog` | `information`, public `news`, `speakers`, `speaker_topics`, `speaker_topic_links`, `event_speakers` | přímý info/news DML a speaker RPC |
| `live_public` | `event_users`, `event_users_saved`, `cleaning_reports`, relevantní event capacity fields → materialized `event_public_state`/`cleaning_public_state` | sign-in/out, schedule sync, cleaning RPC, event delete, user delete/import |
| `private_program` | uživatelovy `event_users`, `event_users_saved` | sign-in/out, `synchronize_my_schedule`, event/user delete |
| `private_profile` | `user_info`, `occasion_users`, `user_group_info`, `user_groups`, `user_companions` | user save/import/delete, group editor/import, service/cleaning flags, companion create/delete a companion attendance |
| `private_inventory` | `occasion_users` spot assignment a `inventory_contexts`, `inventory_pools`, `resources`, `resource_slots`, související product contexts | inventory RPC, user stay save, imports a delete cascades |
| `private_activity` | `activities`, `activity_assignments`, `activity_assignment_events`, `activity_assignment_places` | `update_activities`, publish/autosave a assignment změny |
| `private_news` | `user_news` | mark-read, news delete/remap a user delete |
| `private_feedback` | `event_feedback` + šest canonical feedback RPC, production verified 2026-08-02 | submit/delete feedback RPC; canonical schema/functions jsou v repo source |
| `cleaning preferences` | relevantní sloupce `occasion_users` | mute/block RPC; oddělit private flags od public cleaning statusu |

Evidence update 2026-08-03: forms and tickets are not wholesale sync
components. Their online-only domain RPCs remain commerce boundaries, but
`eshop.spots`, `eshop.products`, `eshop.product_inventory_contexts` and
`eshop.order_product_ticket` do feed `private_inventory`; every writer of those
relations must therefore be registered and must advance affected private
revisions before capability enablement. `unit_catalog` is occasion-materialized
but unit-written. Repository closure 2026-08-03 adds a unit-scoped
receipt/commit identity and atomic fan-out to all visible occasions; an
arbitrary occasion is not used as a fake unit audit scope.

Repository closure update 2026-08-03: exclusive groups/events are guarded
attendance-decision state and now use one versioned aggregate RPC instead of
client-composed DML. Companion create/delete is a typed, receipted boundary;
the owner's `private_profile` contains companions and is advanced when a
companion's attendance changes. A news item requested together with a push is
persisted with its notification-log outbox row in one command. These paths are
therefore no longer unclassified v1 writers.

Further repository closure 2026-08-03 adds stable anonymous feedback receipts,
receipted occasion duplicate/delete, ticket-profile import and service deletion.
Spot-assignment batches and product-context replacement share one private
inventory completion helper so component identifiers and revision/replacement
rules are not duplicated across domain commands. Order/form/blueprint/cancel,
membership, account-deletion and external occasion sync roots now have explicit
canonical owners. The registry has no remaining activation boundary;
production enablement still requires the Wave 6 operational gates.

Tato tabulka je ověřený výchozí seznam, nikoli ještě důkaz úplnosti. Wave 0 ji
musí porovnat s produkčním `pg_catalog`, nasazenými funkcemi, Edge Functions,
crony, recovery/operational skripty a všemi Flutter/JS direct DML callery.

Ochrana má tři vrstvy bez persistentních aplikačních triggerů:

1. **Normální provoz:** odebrat app rolím direct DML na sync source tabulkách a
   migrovat všechny podporované zápisy do explicitních canonical mutation RPC.
2. **Compatibility gate:** staré read/RPC contracty zůstávají dostupné, ale
   vydaná adminská verze zapisující sync source přes direct PostgREST DML nemůže
   po revokaci zůstat podporovaná. Musí být před cutoverem migrovaná nebo
   force-upgraded; nenulový podporovaný direct-DML traffic cutover blokuje.
   Nevytváří se dlouhodobý triggerový most. Pokud by release orchestrace nutně
   potřebovala krátký technický capture trigger během deployment overlapu, smí
   existovat pouze uvnitř stejného releasu a musí být odstraněn a absence
   ověřena ještě před zapnutím capability.
3. **Privilegovaný zásah:** servisní job nebo DBA používá explicitní commit gateway
   s `source = service|break_glass`, databázovou rolí a povinným důvodem. Zásah
   databázového ownera, který obejde grants/gateway, nelze PostgreSQL uvnitř
   stejné instance absolutně zakázat. Musí být zachytitelný externími DB audit
   logy a následnou fingerprint reconciliation; dostupnost/retention těchto logů
   je release blocker, nikoli předpoklad.

Periodická nízkofrekvenční reconciliation porovná deterministický fingerprint
každé public source komponenty s posledním published fingerprintem. Nezajištěný
drift nevyrábí falešný detail auditu: zastaví publication, otevře incident a
vyžaduje explicitní `break_glass` commit s dohledaným aktérem/důvodem. Tato
reconciliation je bezpečnostní kontrola, nikoli druhý klientský sync mechanismus.

### Lokální atomický commit

1. Zachovat aktivní manifest a zobrazovat jej po celý refresh.
2. Stáhnout a ověřit nový release manifest; z jeho descriptors stáhnout pouze
   content digests, které nejsou v lokálním blob store.
3. Ověřit HTTP status, limity velikostí, kompresi, každý component hash/schema,
   scope/revizi a úplnost dependency closure (např. každé `place.icon` a
   `place_type.icon` existuje uvnitř téhož `map_catalog`).
4. Zapsat validní nový `live_public` a private replacements do odpovídajícího
   scoped staging; neúspěšnou class ponechat na jejím starém pointeru.
5. Ověřit referenční konzistenci každé měněné class a tolerovat pouze definované
   cross-class lag chování (unknown live/private event ID se nezobrazí).
6. Jednou Sembast transakcí přepnout pointers všech úspěšně ověřených classes.
7. Až potom publikovat nový `ClientSyncState`, rebuildnout search a později
   uklidit nedosažitelné staging generace.

Pád před bodem 6 ponechá staré pointers. Pád po bodu 6 načte nové validní
pointers.
Klient nikdy neukáže směs public/private generací z různých identity epoch.
Po logoutu se zvýší epoch, zruší in-flight work a odstraní private namespace;
pozdní odpověď předchozí identity se nesmí commitnout.

## Commit ledger a Admin audit

Commit ledger pokrývá všechny změny, které od cutoveru mění některou komponentu
`client_sync_v1`; není retroaktivní ani univerzální pro všechny tabulky. Jde o
auditovatelný commitový model, nikoli event sourcing: source tabulky zůstávají
zdrojem pravdy, stav se z commitů nerebuildí a klienti je nereplayují.

Datový model:

- `client_mutation_receipts`: command ID/name, actor, scope, canonical request
  SHA-256, přesná bounded response, optional `commit_id`, stav a timestamps.
  Unikátní command ID serializuje concurrent retry; replay znovu ověří auth.
  Po response retention zůstane déle hash tombstone, aby pruning neumožnil
  opětovné provedení starého commandu.
- `client_commits`: jedna logická operace s UUID `commit_id`, occasion, časem,
  actor ID a
  display snapshotem, actor kind, source, change class, app/client version a
  correlation/idempotency ID; záznam je immutable.
- `client_commit_items`: entity type/ID, operation, bezpečný label a pouze
  allowlisted `changed_fields`. Žádné raw row JSON, tokeny, emaily, telefony,
  private notes nebo neomezené HTML.
- `client_commit_components`: component/scope a výsledná source/private revize
  dosažená tímto commitem. Publication stav se nemutuje do historického commitu;
  UI jej odvodí porovnáním s aktuálním `client_sync_publications` pointerem.

Commit, jeho items, component revisions a doménový write jsou jedna transakční
jednotka. Selhání povinného commitu fail-closed rollbackne celou změnu. Bulk
operace má jeden commit a stránkované items. Human-readable text se skládá až
  při čtení, ne drahými joiny ve write cestě.

Canonical mutation RPC nejprve autorizuje a claimne mutation receipt, potom
provede všechny statementy a při skutečné změně založí `commit_id`. Unikátní
constraint `(commit_id, component, scope)` zabrání dvojímu revision bumpu a
receipt vrátí při retry tentýž výsledek. Neočekávané SQL chyby se nebalí do
úspěšné JSON response; propagují se a rollbacknou celou transakci. Legacy direct writer,
u kterého nelze znát širší business operaci, není podporovaná v1 write cesta a
musí být před capability cutoverem odstraněn nebo force-upgraded.

Hranicí commitu je jedno skutečné serverové potvrzení logické akce **Uložit**.
Jeden save měnící více řádků nebo komponent je stále jeden commit s více items a
component heads. Samotné psaní do formuláře, lokální draft/autosave bez změny
sync source a no-op save commit nevytvářejí. Pokud doména autosave skutečně
persistuje jako sdílený publikovaný stav, je to samostatný explicitně označený
commit; nesmí vzniknout skrytá výjimka mimo ledger.

### Pull jako jeden logický batch

Klient nikdy nestahuje jeden payload pro každý commit, který od posledního
spojení vznikl. Handshake porovná jeho známý manifest s aktuálními component
heads a všechny mezilehlé commity zkoaleskuje na **nejnovější dostupnou verzi
každé změněné komponenty**. Deset uložení programu proto znamená deset řádků v
auditu, ale při příštím pullu jen jeden download nejnovějšího
`program_catalog`.

Jeden `refresh()` vytvoří logický `SyncCycle`: public head zkoaleskuje katalog a
live změny, private RPC zkoaleskuje private změny. Public catalog je jedna
atomická consistency class, `live_public` druhá a private identity třetí. Uvnitř
každé třídy se všechny required části ověří a přepnou old-or-new; chyba private
RPC nesmí blokovat nový veřejný program a chyba live snapshotu nesmí blokovat
bezpečný catalog update. Složený stav vždy ukazuje samostatný čas/revizi každé
třídy. Public artifacts mohou proběhnout jako paralelní HTTP downloady, ale
nejde o request na každý commit. Autoritativní odpověď vlastní mutace se zobrazí
okamžitě a následující cycle ji potvrdí proti serverovému headu.

`get_client_commits_v1` a `get_client_commit_v1` jsou online-only, keyset
stránkované podle `(occurred_at, commit_id)`, s limitem nejvýše 200. Přístup má pouze admin,
occasion manager nebo odpovídající unit manager; klientské role nemají přímý
SELECT/UPDATE/DELETE. Tab podporuje filtry čas, actor, source, component, typ
entity a operation; detail zobrazuje redigovaný diff a publication stav.

Handshake čte current component heads, nikoli commit ledger. Publisher také
porovnává current source/published heads. Ledger tedy může mít dlouhou auditní
retention, aniž by jeho velikost ovlivňovala pravidelný polling nebo publication.

Existující orders/activity/cleaning histories zůstávají svými canonical moduly.

## Neměnné invarianty

1. DB je jediný autoritativní zdroj pro práva, kapacity a mutace.
2. Každá komponenta má právě jednoho vlastníka, scope a monotónní revizi.
3. Klient používá jediný sync coordinator a jediný polling timer.
4. Public poll nevstupuje do DB. Private handshake je read-only a unchanged
   polling vytvoří nula DB writes.
5. Public artifact je immutable a neobsahuje user flags ani private data.
6. Private komponenta je autorizovaná při každém handshake a scoped identity
   epoch; nikdy není v CDN.
7. Nový manifest se aktivuje pouze po ověření všech changed komponent.
8. Delete nepotřebuje tombstone: úplný replacement je jediná semantika.
9. Vlastní mutation response se aplikuje lokálně bez následného full refresh.
10. Publisher může zaostávat, ale nikdy nezneplatní poslední zdravý artifact.
11. Starý klient dostává po compatibility dobu nezměněný contract.
12. Nový klient nikdy nekombinuje legacy a v1 data v jednom session contextu.
13. Každá skutečná sync-relevantní změna vytvoří právě jeden commit, jeho items
    a výsledné component revisions v jedné transakci; unchanged/rejected/conflict
    má receipt bez commitu.
14. Commit ledger je append-only, online-only a redigovaný; handshake ani
    publisher jej nepoužívají jako pracovní frontu.
15. Page lifecycle, Realtime ani feature repository nesmějí vytvářet alternativní
    síťovou synchronizační cestu.
16. Retry se stejným idempotency key nevytvoří druhý commit ani druhý revision
    bump; vrátí původní autoritativní výsledek.
17. Jeden poll nevytváří request na každý commit: zkoaleskuje historii na
    nejnovější heads a každou consistency class aktivuje old-or-new.
18. `map_catalog` je uzavřený aggregate: žádné místo, typ ani trasa nesmí
    odkazovat na ikonu mimo stejnou verzi katalogu a žádný mapový widget nesmí
    síťově dotahovat chybějící referenci.
19. Jeden immutable public release manifest připíná přes digest kompletní sadu
    component versions; public pointer se neposouvá po jedné komponentě.
20. Zobrazený live count je eventual-consistent projection s revizí/časem;
    skutečné přijetí/odmítnutí sign-inu a kapacita se vždy rozhodují atomicky v
    Supabase a mutation response vrací autoritativní nový stav.
21. Každý podporovaný user intent vstupuje jedním explicitním RPC a dokončí se
    v jedné DB transakci; neexistuje cross-domain dispatcher ani raw RPC-string
    gateway dostupný feature/UI vrstvě.
22. Direct-client RPC při každém volání odvozuje actor/scope/ownership v DB,
    odmítá neznámý či oversized input a klient nikdy deklaruje vlastní
    audit/sync impact.
23. Aggregate edit concurrency používá `bigint` version; contested transitions
    používají autoritativní row/advisory locks v dokumentovaném pořadí.

## Compatibility a canonical cutover

Před cutoverem transition klient při bootstrapu přečte capability:

- `client_sync_v1 = false`: celý session context používá existující legacy
  adapter;
- `client_sync_v1 = true`: celý session context používá `ClientSyncService`.

Přepnutí za běhu vyžaduje uzavření kontextu a nový bootstrap. Fallback uprostřed
refresh není dovolen. Kill switch se projeví v nové session; incidentní rollback
vrátí celý nový klientský režim na legacy, nikoli jednotlivé komponenty.

Po doloženém konci podpory starých binárek následuje contraction release:

- odstranit transition legacy adapter, `SynchroService`, page loaders, staré
  offline keys/import, fixtures a mrtvou dokumentaci;
- odstranit serverová legacy RPC pouze pokud writer/caller inventory neprokáže
  jiného podporovaného consumera;
- doložit, že neexistuje persistentní compatibility capture/guard trigger a že
  každý podporovaný writer vstupuje přes explicitní RPC/service boundary;
- `rg`, call graph, DB function inventory a usage telemetry musí prokázat, že
  zůstala jedna canonical cesta nebo explicitně pojmenovaná externí hranice.

## Implementační vlny uvnitř jednoho releasu

### Wave 0 — Inventory, kontrakty a rozpočty

- Zmapovat všechny readers/writers pro každou komponentu v Flutteru, webu, SQL,
  Edge Functions a adminu; zahrnout relation-only delete a bulk importy.
- Porovnat registry s živým `pg_catalog`/`pg_proc`, RLS/grants, cron jobs a
  service-role/operational skripty. Funkce nebo tabulka existující pouze v
  produkci se musí propsat do canonical repo source před cutoverem; feedback
  contract je již předpřipravený a production-body verified.
- Pro každý source table evidovat všechny `INSERT/UPDATE/DELETE` entry points a
  klasifikovat je `migrate`, dočasný `boundary`, nebo `delete`; neklasifikovaný
  writer je blocker.
- Pro každý user intent evidovat aggregate owner, command shape, explicitní RPC,
  transaction boundary, auth source, lock/version strategii, response
  replacements a trust lane (`direct RPC` nebo `Edge + DB command/outbox`).
- Změřit velikost komponent, p95/p99 private payload, současný počet requestů,
  DB time/rows/57014 a očekávaný počet foreground klientů.
- EXPLAINnout private revision RPC, dirty-key claim a targeted count projection
  na reprezentativních datech. Load testovat 15s public edge polling pro 5 000
  klientů, 60s private polling přihlášených klientů a restart/reconnect burst;
  měřit zvlášť Worker/R2 a PostgreSQL load.
- Uzavřít protocol golden JSON, DTO/schema a privacy allowlist/denylist.
- Ověřit `get_app_config_v217/v218` matici a deployment targety.
- Read-only ověřit existenci/stav `festapp-public` a `assets.festapp.net`;
  chybějící provisioning zařadit do autorizované release wave, nepřesměrovat na
  Supabase Storage fallback.
- Ověřit, že produkční DB audit logy umějí identifikovat privileged DML/DDL a
  mají domluvenou retention; jinak nelze tvrdit detekci owner bypassu.
- Sepsat deletion ledger všech současných sync entry points včetně
  cross-domain dispatcheru, raw RPC-string gateway, direct PostgREST DML,
  dvoukrokového activities publish a legacy RPC facades.

Gate: nejhorší očekávaný polling load má rezervu; snapshoty jsou bounded;
každý source i writer je v registry a má capture/migration strategii; všechny
produkční kontrakty jsou v repu; Cloudflare a DB-audit hranice jsou ověřené;
žádný privacy blocker.

### Wave 1 — Aditivní heads, commit ledger a handshake

- Přidat `client_sync_scopes`, `client_sync_publications`,
  `client_sync_release_manifests`, `client_sync_public_heads`, `client_commits`,
  `client_commit_items`, `client_commit_components`, oddělené
  `client_mutation_receipts`, aggregate-version metadata, bounded
  `client_projection_dirty_keys`, `event_public_state` a
  `cleaning_public_state` s FK/indexy/RLS/grants. Nevytvářet
  `client_sync_changes` ani delta journal.
- Implementovat negrantované `begin_client_mutation_v1` a
  `finish_client_mutation_v1`: receipt se claimne před DML, exact replay
  rozlišuje request hash a commit/revision vznikne jen při skutečné změně.
  Žádný helper nesmí obsahovat cross-domain DML/auth; žádný persistentní
  aplikační trigger ani commit-context guard.
- Migrovat všechny app/service writery na canonical RPC a odebrat direct DML
  grants app rolím. Každý nalezený starý direct-DML consumer musí mít doložený
  upgrade/retirement před capability enablement; nelze jej schovat za dlouhodobý
  triggerový adapter.
- Implementovat read-only `get_private_client_sync_v1`, publisher source/claim
  RPC a commit list/detail RPC s explicitním `search_path` a oprávněními.
- Bez historického commit backfillu inicializovat source revize současným stavem.
- Otestovat insert/update/delete, relation změny, bulk, concurrency, rollback,
  multi-statement canonical RPC, concurrent/po-connection-loss idempotentní
  retry, ID reuse s jiným payloadem, response/tombstone retention,
  auth-before-replay, privacy, hidden occasion a nula side effects při
  unchanged handshake.
- Pro sign-in/out/saved/cleaning testovat, že transakce vytvoří právě jeden
  coalesced dirty key; publisher targeted projection odpovídá autoritativnímu
  `COUNT`, retry nedvojí count a reconciliation opraví záměrný drift.
- Contract test musí iterovat component source registry: pro každý source
  provést materiální testovací změnu, ověřit právě jeden commit, správné items,
  všechny očekávané component revisions a odmítnutí stejného direct DML přes
  grants/RLS.

Gate: každý sync writer bumpne správnou komponentu a vytvoří právě jeden commit;
legacy RPC vracejí stejný contract; DDL proběhne s bounded
lock/statement timeoutem.

### Wave 2 — Publisher a public CDN

- Implementovat source RPC pro každý public component jako jeden konzistentní
  JSON snapshot bez private fields.
- `map_catalog` source sestaví places + place types + paths + transitive closure
  referencovaných SVG icons v jednom statement snapshotu; orphan/dangling icon
  reference zablokuje publication a nevznikne vedlejší icon request.
- Implementovat idempotentní worker: dirty claim, build, compression, hash,
  immutable upload, ověření, monotónní pointer a reconciliation.
- Přidat samostatný stateless `workers/sync-worker/`: public GET head přes R2
  binding, ETag/304, maximálně 5s edge TTL, žádný Supabase subrequest, auth header
  nebo private payload. Nepřidávat KV ani Durable Object.
- Static dirty scopes publikovat jako release manifest. Live dirty keys nejvýše
  jednou za 5 sekund koaleskovat, targeted přepočítat a publikovat jako jediný
  malý immutable `live_public` descriptor v public headu.
- Nastavit bucket/CDN headers a retention; URL obsahuje revision+hash.
- Přidat visibility stop/delete/purge runbook a test public eligibility.
- Generovat initial artifacts pro všechny required scopes a kryptograficky je
  ověřit před client cutoverem.

Gate: starší worker nepřepíše novější pointer; selhání nikam neposune pointer;
všechny required komponenty mají ověřený artifact.

### Wave 3 — Lokální store, poller a protokol

- Implementovat `ClientSyncStore`, staging/pointer, recovery, quota handling,
  scoped namespaces a one-time legacy cache migration.
- Implementovat handshake/CDN adaptéry, hash/schema validation a full component
  replacement.
- Implementovat content-addressed local blob store a release-manifest resolver;
  stejný digest se nestahuje ani neukládá podruhé.
- Implementovat jediný injected `SyncPollingPolicy`: 15s public ticks, každý
  čtvrtý tick private, lifecycle triggers, per-class single-flight/backoff a
  identity/context cancellation. Stále jde o jediný scheduler.
- Napojit tab/router observer na `SyncReason.navigation` s freshness gatingem;
  odstranit `_onTabSwitch`/page-level network refresh listenery po cutoveru.
- Implementovat `SyncProjection` a per-component freshness/error state.
- Testovat fake clockem; žádné skutečné sleeps ani hardcoded produkční hodnoty.

Gate: crash-point testy dokazují old-or-new manifest; corrupt/404/quota zachová
starou generaci; login A → logout → login B nemůže commitnout odpověď A.

### Wave 4 — Consumers a mutations

- Nejprve dokončit referenční vertical slices: event aggregate save/delete,
  attendance guarded transition s locky, activities publish a inventory bundle.
  Každý musí mít explicitní RPC, typed feature command port, aggregate version
  nebo lock, receipt→optional commit semantics a authoritative replacement.
- Po prokázání referenčních slices migrovat stejným kontraktem map/content,
  group/private-place/membership, profile/accommodation, cleaning, forms,
  tickets a ostatní inventory flows. Sdílená infrastruktura nesmí pohltit
  jejich doménové invarianty.
- Odstranit in-progress cross-domain SQL dispatcher a Dart gateway přijímající
  libovolný RPC string/map. UI/feature vrstva smí vidět pouze typed command port.
- Legacy RPC buď zůstane dočasnou vydanou facade nad stejným interním doménovým
  handlerem, nebo se po usage gate smaže. Funkci, která polyká chyby či porušuje
  transakční invarianty, pouze neobalovat—nejprve extrahovat/opravit handler.
- Přesměrovat Program, Mapu, Informace, News, Profil, Skupiny, Ubytování,
  Activities a Search na canonical projections.
- Odstranit z `MapPage` vlastní online/offline orchestrace places, place types,
  paths a icons. `MapRepository` dostane jediný `MapCatalog` z aktivního local
  release manifestu; adminský editor po save aplikuje mutation response a běžný
  reader nikdy nevolá PostgREST pro chybějící typ/ikonu.
- Odstranit jejich local-then-fast-then-full loadery a page-level refresh sítě.
- Rozdělit public DTO od private overlays; po logoutu není možné zobrazit user
  flags z public cache.
- Canonical mutation RPC vrací revision + autoritativní replacement relevantní
  komponenty; klient jej aplikuje stejným commit mechanismem.
- Anonymous saved program se při prvním loginu importuje právě jednou pomocí
  idempotency key; potom je server autoritativní.

Gate: každý consumer má právě jeden read path; každý podporovaný intent má jeden
explicitní transactional RPC a typed client port; absence proof nenajde v nové
cestě dispatcher, raw string gateway ani direct DML; vlastní mutace se projeví
okamžitě bez dalšího requestu.

### Wave 5 — Admin → Změny

- Přidat oprávněný online-only tab, repository, keyset pagination, filtry,
  detail redigovaného diffu a component/publication stav.
- Použít repo lokalizaci a společné test factories; assertions nesmějí stát na
  hardcoded UI stringu nebo produkčním ID.
- Otestovat 403, deleted actor/entity, shodné timestamps, souběžný insert mezi
  stránkami, velký bulk detail a timeout/retry.

Gate: preflight změny programu, místa, place type, obsahu, skupiny a ubytování
jsou právě jednou vidět pod správným aktérem a bez zakázaných polí.

### Wave 6 — Jediný produkční cutover

1. Ověřit backup/restore point, production targets a legacy baseline.
2. S bounded locks aplikovat aditivní DB migraci; při lock timeoutu ukončit
   transakci před deployem klienta.
3. Nasadit publisher a `sync-worker`, vygenerovat/ověřit všechny initial
   artifacts, public head a live projection; ověřit, že Worker request nevolá DB.
4. Nasadit kompletní transition klient s capability defaultně off.
5. Spustit jeden release preflight včetně commit auditu, offline/reconnect a load
   gate.
6. Atomicky zapnout `client_sync_v1` pro `csmostrava2026`.
7. Na vlastních účtech/zařízeních ihned ověřit online, offline cold start,
   resume/reconnect, login/logout, mutation a odpovídající commit.
8. Sledovat public edge hit/304/R2-read rate, live projection lag/drift, private
   handshake latency/error/57014 a request rate, DB CPU/locks/rows, publication
   lag, CDN 404/bytes, local cache commit failures, commit capture latency a
   legacy usage podle platform/version.

Kill switch vypíná v1 pro nové session. Aditivní schema ani poslední artifacts
se při incidentu nemažou. Capability se nezapíná po komponentách.

### Wave 7 — Compatibility retirement

The repository deletion ledger is
`docs/plans/offline-sync-deletion-ledger-2026-08-03.md`.

Po uplynutí rollback okna a doložení nulového podporovaného legacy trafficu
provést contraction podle deletion ledgeru. Toto je samostatný pozdější release,
protože staré vydané aplikace jsou externí compatibility hranice, nikoli druhá
interní architektura.

## Failure matrix

- unchanged polling, 5 000 klientů s jitterem a reconnect burst;
- 5 000 anonymních klientů s 15s public pollingem musí vytvořit nula client-side
  DB requestů; edge hit/304 a R2 read rate musí zůstat v rozpočtu;
- burst přihlášení na stejný event musí zkoaleskovat na jeden dirty key,
  rozhodnout kapacitu přesně v DB a do 25 sekund publikovat správný live count
  bez rebuildu `program_catalog`;
- nový immutable live descriptor + přepsání public headu nesmí přes cache vrátit
  descriptor k dosud neviditelnému objektu; Worker outage zachová poslední
  lokální zdravý stav a označí jej jako zastaralý;
- timeout/57014, offline, flapping connectivity a opakovaný resume;
- rychlé přepínání tabů během 15/60s freshness oken nesmí přidat request;
  přepnutí po vypršení okna musí použít stejný single-flight jako timer;
- deset commitů stejné komponenty mezi dvěma polly musí stáhnout pouze její
  nejnovější verzi; jeden multi-component save musí být v auditu jednou;
- publisher delay/failure, CDN 404, corrupt JSON, hash/schema mismatch;
- map catalog s chybějící/zakázanou ikonou, neexistujícím place type a path
  referencí; žádný případ nesmí vyvolat side-load ani partial activation;
- změna jedné sdílené ikony musí jedním commitem bumpnout přesně všechny
  referencující map scopes a žádný nereferencující scope;
- dva workers dokončené opačně a source změna během buildu;
- pád po každém staging kroku a těsně před/po manifest pointer commitu;
- plný disk, web private mode a cache schema upgrade/downgrade;
- login A, logout během requestu, login B a pozdní odpověď A;
- změna occasion během requestu a offline cold start v jiném contextu;
- insert/update/delete parentu i relation-only změna;
- public → private/hidden occasion a artifact purge;
- duplicate mutation, timeout po DB commitu, retry a unique conflict;
- starý klient proti novému serveru, capability off/on a final client bez
  legacy adapteru;
- commit actor user/system/service/unknown, deleted actor/entity, denylisted
  values, bulk action, rollback a stable keyset pagination;
- direct DML jako authenticated writer je odmítnut grants/RLS;
  registrovaný break-glass zápis vytvoří commit s DB rolí a důvodem;
- úmyslně nasimulovaný source fingerprint drift zastaví publication a vyvolá
  incident, nikoli vymyšlený auditní diff;
- DDL lock timeout musí rollbacknout celou expansion migraci;
- 60 unchanged private handshakes musí vytvořit nula heartbeat/log/commit writes.

## Verification

| Oblast | Důkaz |
|---|---|
| Private handshake auth/privacy/read-only | targeted SQL contract test + side-effect assertion |
| Public edge isolation | Worker test: R2 binding + ETag/304, nulové DB/Supabase volání a bounded stale head |
| Revision/commit capture/concurrency | SQL tests včetně concurrent harness |
| Úplnost source/writer coverage | registry contract test + repo/`pg_catalog` inventory diff musí být prázdný |
| Direct/privileged bypass | grant/RLS denial, break-glass, external audit a fingerprint drift test |
| Snapshot consistency/eligibility | golden JSON, denylist, hash a visibility matrix |
| Polling load | production-like 5k model: 15s public + 60s private, oddělené edge/R2/DB metriky |
| Live counts | SQL projection/reconciliation test + burst/coalescing/publisher latency test |
| Atomic cache/identity isolation | targeted Flutter store/service tests s fake clockem |
| Mutation idempotency | SQL + Dart integration tests |
| Consumer cutover | call graph + `rg` absence proofs + targeted widget tests |
| Offline UX | repository E2E; web smoke přes agent-browser; native/PWA checklist |
| Commit audit UI | SQL permission tests + repository/widget tests |
| Release | `./automation/test_all.sh` a repozitářem předepsané build/deploy gates |

Test data vznikají přes factories/SQL helpers a assertions používají vrácené
IDs/revize/doménové konstanty. Žádné hardcoded produkční hodnoty nebo náhodné
UI stringy.

## Definition of complete

Repository verification completed 2026-08-03 against a disposable local
Supabase stack pinned to the production-linked backend image versions
(Postgres `15.1.1.25`, GoTrue `v2.194.0`, PostgREST `v12.0.2`, Storage
`v1.67.26`). Checked items below are complete in repository code. Items marked
**Operationally blocked** require production authority or production-like
external infrastructure and are deliberately not inferred from local tests.

- [x] Existuje jediný `ClientSyncService`, jediný foreground timer a jediný
      read path pro každý migrovaný consumer.
- [x] V kódu ani infrastruktuře v1 není Realtime/Broadcast invalidace, delta
      journal, tombstone merge ani page-level polling.
- [ ] **Operationally blocked:** public poll nevolá DB a private handshake je
      read-only/indexed v repository tests; cílové concurrency load gates čekají
      na autorizované production-like Cloudflare/Supabase prostředí.
- [x] Každá komponenta má scope, owner, source/published revision, freshness SLO
      a privacy klasifikaci.
- [x] Public artifacts jsou immutable/hashované a nikdy obsahují private pole.
- [x] `get_events` při běžném čtení neagreguje participant/saved relation;
      statický katalog, `live_public` a private overlay mají vlastní canonical
      projekce a jsou složeny pouze ve sync repository.
- [x] `map_catalog` obsahuje places, place types, paths a jejich přesnou icon
      dependency closure; v runtime neexistuje mapový side-loader.
- [x] Jeden public release manifest připíná kompletní component set a pointer se
      posune pouze po ověření všech required artifacts.
- [x] Private components jsou izolované podle user/occasion/identity epoch.
- [x] Klient atomicky aktivuje old-or-new manifest a po chybě zachová poslední
      zdravou generaci.
- [x] Vlastní mutace se projeví z jedné RPC odpovědi bez full refresh.
- [x] Jeden user intent používá jeden explicitní doménový RPC a jednu DB
      transakci; feature/UI kód nemá generic RPC-string gateway ani skládání
      několika persistence requestů.
- [x] `client_mutation_receipts` claimují command ID + hash před DML a jsou
      oddělené od auditu; exact retry nere-exekuuje DML a unchanged/rejected/
      conflict nevytváří commit ani revision bump.
- [x] Direct-client RPCs odvozují actor/scope/ownership server-side, mají bounded
      allowlisted input a nejmenší grants; Edge/service-role cesta je omezená na
      explicitní command + outbox pro externí side effects.
- [x] Event attendance/capacity a ostatní contested transitions mají
      concurrency test dokazující lock invariant; aggregate editor saves mají
      monotónní version conflict test.
- [x] Pull koaleskuje více commitů a nestahuje historii po jednom; catalog,
      `live_public` a private identity jsou tři explicitní old-or-new classes se
      samostatnou freshness, nikoli nahodilé feature loadery.
- [ ] **Operationally blocked:** vlastní mutation response je okamžitá v
      repository tests; p95 25/45/75 s čeká na end-to-end production-like load
      měření po provisioningu Workeru/R2.
- [x] Offline UI ukazuje čas/revizi a nepředstírá živost bez sítě.
- [x] Každá skutečná sync-relevantní změna atomicky vytvoří právě jeden
      redigovaný commit s items a výslednými component revisions; no-op a
      business rejection mají pouze replayovatelnou receipt.
- [x] Každá synchronizovaná source tabulka a každý app/RPC/cron/service writer je
      v jediném registry; inventory diff nemá neklasifikované položky.
- [x] Ordinary-role revocation má atomický registry-driven cutover, explicitní
      RPC/service boundaries a absence persistentních aplikačních triggerů jsou
      ověřené. Externí auditní retence je vědomě odmítnutá výjimka popsaná výše;
      hosted pgaudit a fingerprint reconciliation zůstávají aktivní.
- [x] `Admin → Změny` je permission-gated, keyset paginated a online-only.
- [x] Staré aplikace fungují na nezměněné explicitní compatibility hranici.
- [x] Každá položka deletion ledgeru je odstraněná nebo pojmenovaná externí
      hranice s ownerem a retirement podmínkou.
- [ ] **Operationally blocked:** repository release gate je zelený; migration
      apply, initial publication, capability enablement, immediate production
      smoke, monitoring a kill-switch drill vyžadují explicitní deployment
      autoritu.

Local verification evidence: client-sync preflight OK (14 required sources),
registry OK (39 sources, 0 unclassified boundaries), SQL `61/61`, Edge/Deno
`14/14`, web `28/28`, Flutter `299/299`, automation smoke OK, account-deletion
Auth/Storage E2E OK, receipt race and queue `SKIP LOCKED` concurrency proofs OK.
No production write, migration, deploy, capability enablement, commit or push
was performed.

## Residual risks a jejich limity

- **Polling není okamžitý.** Cizí live count může za normálního provozu zaostat
  do 25 sekund a private změna do 75 sekund. Vlastní mutace vrací přesný stav
  okamžitě; UI u projekce nese revizi/čas a při překročení SLO označí data jako
  zastaralá.
- **Veřejný polling přesouvá zátěž na edge, neodstraňuje ji.** Public request
  nevolá DB, ale spotřebovává Worker/cache/R2 kapacitu; private poll nadále čte
  indexed revision registry. Obě větve mají samostatný 5k load budget a interval
  se bez měření nezkracuje.
- **Odvozená live projekce může driftovat.** Periodická reconciliation porovnává
  materializované počty s autoritativními relation tabulkami, nesoulad alarmuje
  a opraví projekci; kapacitní rozhodnutí projekci nikdy nevěří.
- **Cloudflare je nová distribuční závislost.** Při výpadku Workeru/R2 klient
  zachová poslední ověřenou lokální generaci, ukáže její stáří a private mutace
  nadále rozhoduje Supabase; nevzniká skrytý Supabase public fallback.
- **Full replacement může být velký.** Komponentizace, komprese, velikostní
  budget a CDN přesouvají běžné čtení mimo DB. Překročení budgetu blokuje cutover
  a vede k rozdělení komponenty, ne k návratu delta protokolu bez nového ADR.
- **Compatibility dočasně drží starý backend.** Je izolovaný na bootstrap hranici
  starých/transition binárek; nový runtime nemá dual read. Retirement má měřené
  podmínky a deletion ledger.
- **Commit ledger přidává write metadata.** Explicitní RPC helper musí být
  operation-batched, allowlisted a bez drahých joinů; fail-closed riziko kryje
  write load test.
- **Commit audit začíná cutoverem.** Historii před migrací nelze spolehlivě
  dopočítat;
  existující doménové historie zůstávají autoritativní pro své oblasti.
- **DB owner je absolutní trust boundary.** Owner může technicky obejít grants i
  změnit audit. Riziko nelze odstranit schématem ve stejné DB; omezuje jej
  minimální přístup, externě uchovávané DB audit logy, povinný break-glass
  runbook a fingerprint reconciliation.
- **Offline revokaci nelze okamžitě doručit.** Private payload je minimalizovaný,
  logout jej smaže a UI ukazuje stáří; zařízení bez sítě z principu změnu neví.
