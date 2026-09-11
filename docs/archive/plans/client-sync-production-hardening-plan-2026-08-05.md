# Production hardening klientského sync enginu

Date: 2026-08-05
Status: Ready for execution
Verification: standard

## Outcome

`client_sync_v1` pro CSM Ostrava zůstane jediným kanonickým klientským sync
enginem, ale jeho produkční cesta bude splňovat původní provozní kontrakt:

- public head se bude po dobu nejvýše pěti sekund skutečně obsluhovat z
  Cloudflare Cache API, takže běžný klientský poll nebude znamenat jeden R2 read;
- dirty queue se bude zpracovávat každých pět sekund a live změna se bude běžně
  publikovat v původním p95 SLO 25 sekund end-to-end;
- každý viditelný event bude mít úplný `event_public_state`, včetně nově
  vytvořených běžných eventů a counseling slotů;
- neúspěšný publisher uvolní claim pro další tick, zatímco hard-crash lease
  zůstane poslední pojistkou;
- lokální `ClientSyncStore` bude atomicky nahrazovat superseded generations a
  držet pouze bounded blob cache, takže dlouho běžící klient nebude hromadit
  každou staženou revizi dvakrát;
- aktivace a deaktivace `client_sync_v1` bude jediná, explicitní operace přes
  cutover nástroj; create/duplicate/save ani hide/delete ji nebudou obcházet;
- immutable public artefakty a plné mutation responses budou mít explicitní,
  bezpečnou retention bez porušení current release nebo idempotence;
- read-only health/preflight výstup bude dokazovat cache efekt, publication lag,
  projection drift, dirty claims, receipt compaction a retention backlog;
- provozní dokumentace bude popisovat skutečný nasazený stav, nikoli původní
  pre-activation stav z 3. srpna.

Jde o hardening existujícího kanonického enginu, ne o V2 a ne o paralelní sync
implementaci.

## Scope

### In scope

- `sync-worker` public-head GET/HEAD/OPTIONS cesta, ETag/304 a pětisekundová edge
  cache;
- `sync-publisher` wake-up, claim/retry chování, R2 publication a maintenance;
- explicitní pětisekundový production scheduler přes Supabase `pg_cron` +
  `pg_net` a Vault;
- úplnost `live_public` projekce pro event create/update/counseling writers a
  jednorázová oprava existujícího driftu;
- read-only detekce projection/revision driftu a explicitní guarded repair;
- bounded lokální generations/blob cache uvnitř `ClientSyncStore`, včetně
  odstranění dat jiných private identit;
- kanonický occasion lifecycle pro enable/disable a ochrana create, duplicate,
  save, hide a delete cest;
- R2/metadata retention pod prefixem `client-sync/v1/`;
- 30denní exact-response retention mutation receipts a trvalý lehký tombstone;
- read-only monitoring, release preflight, dokumentace a absence proofs.

### Out of scope

- změna klientského protokolu `protocol: 1`, názvů komponent nebo lokálního
  Sembast formátu;
- entity-level delta journal, tombstones pro doménové entity, Realtime,
  Broadcast, KV nebo Durable Objects;
- změny mapových artefaktů mimo `client-sync/v1/` v bucketu `festapp-public`;
- prořezání immutable commit auditu (`client_commits`, items a components);
- změna business pravidel registrací, kapacit, programu nebo counseling;
- produkční migrace, backfill, DNS/secret provisioning, deploy, load test a
  aktivace scheduleru bez samostatného oprávnění.

## Constraints

- `docs/architecture/ai_context.md` určuje live projekt výhradně z
  `automation/project.conf`; pro tento plán je ověřen projekt
  `lwfpdjxsdmkfyrzqbrlk`, occasion link `csmostrava2026`, organization `9`,
  occasion `643`.
- Nové aplikační PostgreSQL triggery jsou zakázané. Dirty queue zůstává
  explicitně plněná kanonickými mutation RPC; scheduler smí pouze volat viditelný
  publisher/service boundary.
- Aplikovaná migrace `20260802234000_client_sync_v1_expansion.sql` ani její
  overlay migrace se neupravují. Změna databáze musí být nový forward migration
  s unikátním timestampem vyšším než baseline cutoff `20260805230000`.
- Všechny nové `SECURITY DEFINER` funkce musí být v `public`, mít explicitní
  `SET search_path = ''` nebo povolený projektový ekvivalent, explicitně
  kvalifikované objekty a minimální grants.
- Public GET boundary nesmí obdržet Supabase credential ani číst DB. Interní
  publisher wake-up poběží na odděleném hostname a bude fail-closed chráněn
  bearer secretem.
- Publisher smí zpracovat pouze scope z `SYNC_SCOPE_IDS`; request body nesmí
  rozšířit povolené scope.
- Public head smí být edge-stale nejvýše pět sekund. Immutable payloady zůstávají
  content-addressed a roční cache je správná.
- Retention nikdy nesmí odstranit current head, current a předchozí kompletní
  manifest ani žádný artefakt referencovaný current manifestem/live headem;
  nic mladšího sedmi dní není candidate.
- Pointer rollback na starší revision je zakázaný. Rollback dat je vždy nová
  forward publication s vyšší revision, nikoli znovuaktivování starého headu.
- `client_sync_v1` flag je provozní stav. Běžné occasion RPC jej nesmějí měnit;
  enabled occasion nelze skrýt ani smazat bez předchozího guarded disable.
- Exact mutation replay je garantován 30 dní. Po compaction se stejný command ID
  nesmí znovu vykonat; vrátí deterministickou expired replay response.
- Verification je `standard`, protože změna zasahuje public contract,
  idempotenci, billing boundary, migraci a produkční operace.

## Current-state evidence

### Runtime snapshot z 2026-08-05

| Claim | Evidence | Consequence |
|---|---|---|
| Target je správný a v1 aktivní. | Read-only management SQL: occasion `643`, link `csmostrava2026`, organization `9`, `client_sync_v1=true`; `automation/project.conf`. | Plán se vztahuje k aktivnímu produkčnímu kontraktu, ne k nenapojenému prototype. |
| Registry je připravený a queue aktuálně zdravá. | 40/40 `client_sync_component_sources.cutover_ready`; 0 dirty rows; source/published lag všech šesti public komponent 0. | Není potřeba nový engine ani nouzový rebuild; opravují se konkrétní seam gaps. |
| Head není cacheován přes Workers Cache API. | `workers/sync-worker/src/index.ts: handleRequest` volá `PUBLIC_SYNC.get` před každou 200/304 odpovědí; v repu není `caches.default.match/put`. | Každý poll je Worker invocation plus R2 Class B read. `s-maxage` v response není implementací Cache API. |
| Malý smoke měl stejnou latenci pro 200 a 304. | 20 klientů / 40 requestů: 0 chyb, initial p95 177,5 ms, conditional p95 204 ms, všech 20 conditional odpovědí 304. | ETag funguje, ale conditional request neodstraňuje R2 read. |
| Jediný nasazený publisher tick je minutový. | `workers/sync-publisher/wrangler.toml: [triggers] crons = ["* * * * *"]`; `src/worker.ts: scheduled`. | Nelze garantovat publisher/coalescing do 5 s. |
| Publication SLO je měřitelně překročené. | Join `client_commit_components` -> `client_sync_publications`: `live_public` p50 21,4 s, p95 56,4 s, max 62,9 s; `program_catalog` p95 56,6 s. | Původní live p95 25 s a structural p95 45 s nelze splnit bez subminutového wake-upu. |
| Repo už obsahuje 5s kanonickou polling smyčku, ale není produkčně vlastněná. | `workers/sync-publisher/src/loop.ts` volá stejné `ClientSyncPublisher.runOnce()` každých 5 s; production Worker používá jen scheduled handler. | Frekvence a owner jsou známé; není nutné navrhovat druhý publisher. |
| Supabase umí zvolený scheduler seam. | Read-only SQL: PostgreSQL 15.1; `pg_cron 1.6`, `pg_net 0.8.0`, `supabase_vault 0.2.8` jsou instalované; existují tři jiné aktivní cron jobs. | Pětisekundový `pg_cron` může přes `pg_net` budit chráněný publisher endpoint bez triggeru. |
| Sedm viditelných eventů nemá live row. | 936 visible `events`, 929 visible `event_public_state` rows v snapshotu; chybí IDs `2957`, `2959`-`2963`, `2970`; dirty queue 0. | Jde o tichý projection drift, nikoli čekající publikaci. |
| Event create writers neinvalidují live. | Current `save_event_client_sync_v1` completion obsahuje jen `program_catalog`; `create_counseling_slots_client_sync_v1` jen `program_catalog`,`content_catalog`. | Nový event se do live snapshotu dostane až po jiné live mutaci nebo vůbec. |
| Full-scope dirty key neumí obnovit všechny event states. | `publisher.ts` zahodí `entity_id <= 0` a zavolá `refreshEvents(..., [])`; SQL refresh chápe `NULL` jako full refresh, prázdné pole jako žádný event. | Reconciliation/initial dirty key `entity_id=0` dnes může být potvrzen bez materiální opravy. |
| Klient drift maskuje nulami. | `lib/data_services/client_sync/client_sync_projection.dart: projectEvents` používá `liveEvent?... ?? 0`. | UI prázdných eventů typicky vypadá správně, ale úplnost kontraktu a derived capacity nejsou prokazatelné. |
| Failed claims se neuvolňují. | `publisher.ts: runOnce/publishScope` shromáždí chyby, ale nemá release RPC; SQL claim lze znovu převzít až po 2 minutách. | Běžná transient chyba může zbytečně vytvořit dvouminutový publication lag. |
| Lokální sync úložiště je neomezené. | `ClientSyncStore.stageBlob` zapisuje každý `blob/$sha` bez eviction; `_activate` přidává nové `generation/$scope/$class/$pointer` bez odstranění předchozí generace. Stažený payload je tak uložen jako blob i jako parsed generation. | Při častých live revisions může zařízení růst neomezeně, i když serverová retention funguje. Limit musí vlastnit `ClientSyncStore`, ne UI nebo scheduler. |
| Stará private data mohou přežít restart. | `ClientSyncRuntime.identityChanged` čistí pouze právě známý old private scope; store nemá startup retention všech cizích scope/identity generations. | Odhlášení nebo změna účtu nemusí odstranit dříve uložené private generations, pokud změna identity proběhla v minulém procesu. |
| Occasion activation má bypassy. | `duplicate_occasion_client_sync_v1` kopíruje `occasions.data`; create/save přijímají arbitrary `data`, zatímco `client_sync_cutover.mjs` předpokládá, že flag řídí jen on. | Nová nebo editovaná occasion může získat `client_sync_v1=true` bez allowlistu, initial headu a preflightu. |
| Hide/delete nezneplatní public R2 head. | Save při visible->hidden jen invaliduje DB config; delete odstraní DB sync rows, ale serving Worker DB nekontroluje a R2 public head zůstává. | Enabled v1 occasion musí nejprve projít disable pořadím: odstranit a ověřit public head, teprve potom změnit flag. |
| Pointery jsou již monotónní. | `R2NativeObjectStore` i `R2S3ObjectStore` odmítají stale head regression; Flutter `ClientSyncService` odmítá component/live revision regression. | Starý non-current artefakt se forward publikací nestane znovu current. Retention nepotřebuje prune claims a rollback musí být corrective publication s vyšší revision. |
| Public historie roste bez pruning ownera. | 1 329 publication rows / 117 932 497 raw bytes a 34 manifestů od 3. srpna; posledních 24 h přibližně 46,4 MB raw. R2 bucket: 1 812 objektů / 265 MB. Search nenašel sync prune/delete implementaci. | Růst je lineární; bucket navíc obsahuje mapová data, takže deletion musí být prefixově omezená. |
| Plné receipt responses rostou bez compaction. | 5 136 receipts, 0 processing, relation 25 968 640 bytes, response payload 21 399 156 bytes; posledních 24 h 7 151 135 bytes. | Exact replay data potřebují časově omezenou retention, command ID ochrana musí zůstat. |
| Payload headroom je nyní zdravý. | Latest public set 891 889 B raw / cca 152 KB gzip; program 598 116 B = 57 % raw budget; live 76 223 B = 14,5 % raw budget. Max receipt response 8 517 B proti 8 MiB limitu. | Není důvod dělit komponenty nebo měnit protokol; plán nesmí zavést lazy/delta fallback. |
| Dokumentace je zastaralá. | `docs/runbooks/client-sync-v1-implementation-status-2026-08-03.md` stále říká, že nic nebylo aplikováno ani zapnuto. | Operátor může provést špatný rollout/diagnózu; dokument musí být přepsán na aktuální stav. |

### Reprezentativní end-to-end flow

1. Typed mutation RPC zapíše doménová data a přes
   `record_client_sync_commit_v1` atomicky vytvoří commit, zvýší component
   revision a upsertne `client_projection_dirty_keys`.
2. `ClientSyncPublisher.runOnce()` přes service-role RPC claimne bounded dirty
   keys, materializuje targeted live projections, vyrobí immutable JSON, ověří
   byte budget a SHA-256, zapíše R2 head a teprve potom potvrdí publication v DB.
3. Flutter foreground scheduler polluje `sync.festapp.net` po 15-18 sekundách,
   stáhne jen změněné immutable payloady, ověří hash/schema a atomicky přepne
   local generation.
4. Private handshake běží odděleně po 60 sekundách přímo proti autorizovanému
   Supabase RPC. Tento plán jeho protokol nemění.

## Target architecture and invariants

### Canonical owner and contract

Publikačním modulem zůstává `ClientSyncPublisher` nad databázovou dirty queue.
Jeho úzké rozhraní `runOnce()` má pouze tři adaptéry:

1. autentizovaný pětisekundový publication tick z Supabase Cron pro freshness;
2. minutový Cloudflare scheduled tick jako recovery safety net;
3. explicitní manuální `npm run once` pro autorizovaný provozní zásah.

Žádný vstup nepřijímá component nebo scope od veřejného calleru. Scope pochází
výhradně z `SYNC_SCOPE_IDS`; DB queue je jediný seznam práce. `loop.ts` se po
cutoveru odstraní, aby nezůstal neřízený čtvrtý production runtime.

Public serving owner je `sync-worker`. GET/HEAD čte pouze R2/Cache API a nikdy
DB. Interní publisher endpoint je na odděleném custom domain
`sync-publisher.festapp.net`, přijímá pouze `POST`, vyžaduje bearer secret a po
dokončení vrací bounded health metadata bez dat nebo credentialů.

Lokální persistence zůstává hluboký modul `ClientSyncStore`: caller žádá stage,
activate a změnu contextu, ale eviction, atomické nahrazení generace a odstranění
cizích identit jsou skryté uvnitř. `StorageHelper` smí získat jediný interní
atomický primitive „writes + remove matching prefixes“; nevznikne obecný veřejný
cache manager.

Lifecycle owner je existující `automation/release/client_sync_cutover.mjs`.
Jeho status/enable/disable je jediný povolený seam pro změnu operational flagu a
R2 public headu. Retention je oddělený interní modul
`ClientSyncRetention.runOnce({apply})`, volaný nejvýše denně; není součástí public
publisher rozhraní a `apply` je defaultně false.

### Invariants

1. Jeden client poll způsobí nejvýše jeden R2 head read na edge PoP za pět
   sekund; cache hit a matching ETag způsobí nula R2 reads.
2. Cache key je canonical GET URL bez conditional headeru. 200 i bounded 404
   cache expirují nejpozději za pět sekund; browser stále revaliduje.
3. Public GET/HEAD/OPTIONS cesta nemá Supabase binding, secret ani subrequest.
4. Publication endpoint fail-closed odmítá chybějící/špatný token, jinou metodu,
   nadměrné body a neznámou cestu bez DB/R2 publication callu.
5. Každý aplikovaný public commit vytvoří nejvýše jeden revision bump pro
   component/scope a retry stejného command ID nevytvoří druhý bump.
6. Každý visible event má přesně jeden `event_public_state` row. Jeho participant,
   saved a remaining-capacity hodnoty odpovídají autoritativním relations.
7. `live_public entity_id=0` znamená full event projection refresh; targeted ID
   znamená právě dané eventy. Tyto významy se nesmějí zaměnit s prázdným listem.
8. Failed class uvolní pouze své claim tokeny; úspěšně publikovaná catalog/live
   class zůstane potvrzená. Hard process death se zotaví přes existující lease.
9. Head je monotónní, immutable object existuje a souhlasí hash/length před
   pointer update; cache nikdy neukáže descriptor před uploadem objektu.
10. Artifact retention pracuje pouze pod `client-sync/v1/` a candidate je pouze
    přesná metadata URL starší sedmi dní, která není current head/manifest ani
    descriptor referencovaný current manifestem/live headem.
11. Concurrent forward publication nemůže starý non-current candidate znovu
    aktivovat; publisher i klient odmítají revision regression. Mazání proto
    nepotřebuje prune-claim state machine.
12. Exact completed receipt response zůstane 30 dní. Potom se stejný PK row
    atomicky změní na response-less `expired` tombstone; command ID se nikdy
    znovu nevykoná.
13. Immutable commit ledger se neprunuje a není v handshake/publisher hot path.
14. Health drift pouze detekuje a failne. Známý drift opraví jednorázová forward
    migration; budoucí repair je explicitní guarded operace, aby writer bypass
    nebyl automaticky maskován.
15. Aktivní public/private generation je po activation jediná pro daný
    scope/class. Blob cache je pouze optimalizace, nejvýše 16 položek a 8 MiB
    encoded dat; eviction nikdy neovlivní current generation correctness.
16. Store po bootstrap/context změně zachová jen current public scope a current
    private identity scope; ostatní private generations/pointers odstraní.
17. Create/duplicate vždy nastaví `client_sync_v1=false`, save zachová serverový
    flag a enabled occasion nelze skrýt ani smazat. Disable nejprve odstraní R2
    mutable public head a ověří 404, potom nastaví flag false.

### Entry points and forbidden bypasses

- Povolené: typed mutation RPC -> commit/dirty finalizer; authenticated
  publication tick; Cloudflare scheduled recovery; manual `once`; public
  GET/HEAD/OPTIONS; guarded cutover lifecycle; service-role maintenance RPC.
- Zakázané: persistent DB trigger/webhook, client-provided scope/component,
  public unauthenticated publication POST, přímý R2 head writer mimo
  `ObjectStore.putHead`, blanket R2 lifecycle na celý bucket, pruning podle
  samotného stáří bez current-reference checku, editace activation flagu přes
  occasion create/save/duplicate, pointer regression, druhý delta/Realtime sync,
  editace aplikovaných migrations.

## Decisions, assumptions, and blockers

### Decisions

- **D1:** Zachovat `client_sync_v1` a protocol 1; problémy jsou provozní seams,
  ne důvod pro nový engine.
- **D2:** Freshness bude vlastnit 5s Supabase Cron -> `pg_net` -> chráněný
  publisher HTTP endpoint. Potvrzené instalované extensions a existující cron
  provoz z něj dělají nejmenší explicitní cestu bez triggeru nebo nového hostingu.
- **D3:** Minutový Cloudflare scheduled handler zůstane recovery
  safety net, ale nebude jediným freshness mechanismem. Všechny vstupy volají
  stejný `runOnce()`.
- **D4:** Head cache použije Workers Cache API, nikoli KV/DO. TTL je pět sekund
  a cache miss čte strong-consistent R2 binding.
- **D5:** Event create/update a counseling create invalidují `program_catalog`
  i `live_public`; counseling speaker vazby dál invalidují `content_catalog`.
- **D6:** Full projection refresh je explicitní `eventIds: null`, nikdy `[]`.
- **D7:** R2 artefakty používají sedmidenní minimální okno a current-reference
  protection. Starý pointer rollback není podporovaný; náprava je forward
  publication. Bucket-level lifecycle rule ani prune-claim schema se nepoužije.
- **D8:** Exact response retention je 30 dní; stejný receipt row pak zůstane
  trvale jako lehký `expired` tombstone. Commit audit zůstává immutable.
- **D9:** Read-only health drift neopravuje. Retention je malý oddělený interní
  modul se scheduled adaptérem, nikoli další publisher; mazání je
  dry-run-first, exact-key a fail-closed.
- **D10:** Production rollout oddělí code deploy, secret/DNS, DB migration,
  scheduler activation, data repair a první destructive prune.
- **D11:** Pětisekundový cron provede levný indexed `EXISTS` nad unclaimed dirty
  keys pro configured scopes a `net.http_post` zavolá jen při práci. Minutový
  fallback řeší hard-crash lease, běžný failure claim explicitně uvolní.
- **D12:** Local retention se implementuje uvnitř `ClientSyncStore`: atomické
  replacement generations a bounded 16-item/8-MiB blob cache. Nevznikne nový
  cache subsystem ani změna persistent formátu.
- **D13:** `client_sync_cutover.mjs` se prohloubí na jediný operational lifecycle
  interface; create/duplicate/save/hide/delete zůstanou jednoduché doménové
  writery bez authority nad sync aktivací.

### Assumptions

- **A1:** `sync-publisher.festapp.net` lze přidat jako Cloudflare custom domain;
  impact if false: použije se explicitně schválený path route na jiném interním
  hostname, nikoli public GET Worker; resolve by: read-only DNS/route preflight
  před editací Wrangler configu.
- **A2:** Sedm dní je dostatečné offline/in-flight retention okno pro public JSON;
  impact if false: zvětší se konstanta bez změny architektury; resolve by:
  release owner potvrdí okno před prvním destructive prune.
- **A3:** Třicet dní exact replay pokrývá legitimní offline/retry chování klienta;
  impact if false: zvýší se response retention, tombstone model zůstane; resolve
  by: product owner potvrdí před aktivací receipt compaction jobu.
- **A4:** Pětisekundový indexed `EXISTS` má přijatelný DB cost; HTTP/claim call se
  při prázdné queue neprovede. Impact if false: interval se upraví až po měření a
  novém SLO gate; resolve by: production-like 24h measurement.
- **A5:** Cloudflare account dovoluje potřebný custom-domain Worker a Cache API;
  impact if false: deployment blocker, nikoli důvod obejít auth/cache; resolve
  by: `wrangler whoami`, route preflight a dry-run deploy.

### Blockers

- **B1:** Produkční DNS/custom domain, Cloudflare secret, Supabase Vault secret,
  Worker deploy a scheduler activation vyžadují samostatnou provozní autoritu.
- **B2:** Forward migration a jednorázový production projection repair mění
  produkční DB a vyžadují samostatnou autoritu a ověřený backup/restore point.
- **B3:** První R2 deletion a receipt compaction jsou destructive. Musí mít
  samostatné potvrzení po dry-run reportu; implementace je nesmí spustit sama.
- **B4:** 5k public/private release load gate může generovat náklady a produkční
  zátěž; nespouštět bez explicitního schválení.

## Deletion ledger

| Artifact | Current role | Final action | Removal proof |
|---|---|---|---|
| Přímý `PUBLIC_SYNC.get` na každý head request | Obslouží 200/304, ale účtuje R2 read pokaždé. | Nahradit cache-first `caches.default.match`, R2 pouze na miss, `cache.put` s 5s TTL. | Worker test pro dva sequential requesty dokáže jeden R2 get; runtime response/cache metrics. |
| Minutový cron jako jediný freshness owner | Publikuje p95 přibližně 56 s. | Ponechat pouze jako recovery; primary wake-up je conditional 5s Supabase cron. | `cron.job`, publisher logs a p95 query dokazují aktivní 5s tick a p95 target. |
| `workers/sync-publisher/src/loop.ts` | Neřízená lokální 5s smyčka, dnes nenasazená. | Po zavedení canonical HTTP scheduleru odstranit script a `package.json start`; ponechat jen one-shot. | `rg 'loop.ts|npm run start' workers docs automation` bez production odkazu. |
| Event save bez live dirty key | Publikuje strukturu, nevytvoří live row. | Forward migration změní current RPC definition a registry contract test. | SQL test vytvoří event a najde live dirty key i state po materializaci. |
| Counseling create bez live dirty keys | Vytvoří více eventů jen v program/content. | Přidat jeden live revision bump a targeted dirty key pro každý created ID. | SQL test porovná returned IDs s dirty keys a projected rows. |
| `entity_id=0 -> []` publisher převod | Full repair tiše neudělá nic. | Zavést nullable/full-refresh contract a odstranit filtrující empty semantics. | Publisher unit test očekává `refreshEvents(scope, null)`. |
| Sedm chybějících production projections | Drift maskovaný klientskými nulami. | Jednorázový auditovaný repair všech enabled/public v1 occasions, ne hardcoded IDs. | Zero-row anti-join a nový live revision/head po rollout smoke. |
| Failed claim ponechaný do lease expiry | Transient chyba způsobí až 2min delay. | Přidat token-scoped release RPC a volat jej pro failed class; lease ponechat pro process death. | Unit/SQL test partial failure + next tick reclaim. |
| Superseded local generations a blobs | Každá revize zůstává v Sembastu a payload je uložen dvakrát. | `ClientSyncStore` atomicky nahradí starou generaci, čistí cizí identity a drží blob LRU max 16/8 MiB. | Store tests dokazují crash safety, jedinou generation, bounded blobs a identity cleanup. |
| Occasion flag editovatelný běžnými writery | Create/duplicate/save může obejít allowlist a initial publication. | Force/preserve false/current flag v RPC; jediný owner změny je guarded cutover. | SQL/cutover tests pro create, duplicate, save, hide/delete a enable/disable ordering. |
| Public head po hide/delete | R2 mutable head může dál obsluhovat odstraněnou occasion. | Enabled hide/delete odmítnout; disable smaže exact head, ověří 404, pak flag false. | Failure-injection test nikdy nenechá `flag=false` s existujícím headem. |
| Neomezené immutable sync artefakty/metadata | Růst cca 46 MB raw/den. | Current-reference retention, 7d age floor, exact R2 delete a následný metadata delete; pouze prefix `client-sync/v1/`. | Dry-run candidates neobsahují current URLs; post-run R2/DB parity. |
| Neomezené full receipt responses | TOAST/index růst, exact replay navždy. | Po 30d změnit row na `expired`, response NULL, command metadata/PK ponechat. | SQL replay test před/po compaction a table-size metric. |
| Stará implementation-status tvrzení | Tvrdí, že v1 není nasazená. | Přepsat na current deployed state a odkázat health/runbook. | Search neobsahuje nepravdivé pre-activation tvrzení. |
| Legacy claim „publisher enforceuje compressed budget“ | Runtime enforceuje raw bytes; skutečný gzip/network výsledek vzniká až v delivery vrstvě. | Dokumentovat raw enforcement a měřit reálné compressed/network bytes v release/health gate; nepřidávat druhou kompresní implementaci. | Publisher raw-budget tests a endpoint measurement souhlasí s dokumentací. |

## Implementation waves

### Wave 1 — Cache-first public head bez změny protokolu

**Goal**

Každý edge PoP čte mutable R2 head nejvýše jednou za pět sekund a zachová
stávající URL, JSON, ETag, CORS, browser revalidation a bounded 404 semantics.

**Changes**

- `workers/sync-worker/src/index.ts`
  - rozšířit `handleRequest`/default handler o `ExecutionContext` a injektovatelný
    cache seam pro testy;
  - normalizovat GET cache key bez `If-None-Match` a bez HEAD method;
  - před R2 volat `caches.default.match`; na hit vyhodnotit callerův ETag proti
    cached ETag a vrátit 304 nebo cached 200/HEAD;
  - na miss načíst pouze přes scoped R2 key, vytvořit canonical response a přes
    `ctx.waitUntil(cache.put(...response.clone()))` uložit nejvýše na 5 s;
  - cacheovat `not_published` 404 nejvýše 5 s, necacheovat 405/OPTIONS;
  - nepřidávat DB, KV, DO ani libovolný bucket-key route.
- `workers/sync-worker/tests/index.test.ts`
  - test cache miss -> hit se stejným tělem a jediným R2 get;
  - test conditional cache hit -> 304 a nula dalších R2 get;
  - test TTL/miss pomocí fake cache, bounded 404, HEAD, CORS a arbitrary-path
    absence.
- `workers/sync-worker/wrangler.toml`
  - zachovat custom domain; nepřidávat nové bindingy pro public GET.

**Migration/deletion**

- Odstranit implicitní předpoklad, že samotný response `s-maxage` cache naplní.
  Protokol ani R2 key se nemění.

**Failure and compatibility**

- Cache API je regionální/PoP-scoped; první request po TTL smí číst R2.
- Cache put failure nesmí shodit validní R2 response; musí být logovaná a další
  request znovu přečte R2.
- Max stale je 5 s. Starý cache head odkazuje pouze na immutable již existující
  objekty, takže je bezpečný.

**Validation**

- `cd workers/sync-worker && npm test && npm run typecheck` — cache, HTTP a typový
  kontrakt.
- Lokální/miniflare nebo autorizovaný staging smoke: dva requesty a conditional
  request; logovaný R2 read count se nezvýší na hitu.

**Exit condition**

- Testy dokazují jeden R2 get pro cache population a žádný pro následující
  200/304 hit; public response shape/headers zůstávají kompatibilní.

### Wave 2 — Bounded lokální sync persistence

**Goal**

`ClientSyncStore` zachová atomickou offline correctness, ale úložiště nebude
růst s každou live revision ani držet private data předchozích identit.

**Changes**

- `lib/data_services/client_sync/client_sync_store.dart`
  - při activation v jediné transakci zapsat novou generation/pointer a odstranit
    superseded generation keys stejného scope/class;
  - blob považovat pouze za download cache: serializovat její mutace a uvnitř
    store držet atomický LRU/order/encoded-size index s limitem 16 blobs a 8 MiB;
    po překročení evictovat nejstarší položky, current generation na blobu
    nezávisí;
  - při bootstrap/context save zachovat jen current public scope a current
    private identity scope a odstranit generations/pointers jiných scopes;
  - částečně staged nebo invalidní blobs jsou bezpečně evictovatelné a nesmějí
    blokovat start.
- `lib/services/storage_helper.dart`
  - přidat pouze interní atomickou operaci pro kombinaci writes a odstranění
    přesně zadaných key prefixes; nepřidávat obecné cache policy API.
- `client_sync_service.dart` a `client_sync_runtime.dart` používat stávající
  store rozhraní/context lifecycle; eviction nesmí prosakovat do scheduleru/UI.
- Rozšířit `test/data_services/client_sync/client_sync_store_test.dart` přes
  skutečný store seam (production Sembast adapter a in-memory test adapter):
  atomic activation/failure, jediná generation po replacement, čitelný current
  stav, blob item/byte cap, restart a odstranění cizí identity.

**Migration/deletion**

- Není DB ani protocol migration. První otevření store po upgradu provede
  idempotentní cleanup starých generations/blobs v téže bounded policy.
- Neměnit názvy current records ani wire payload; odstraní se pouze redundantní
  lokální data.

**Failure and compatibility**

- Pád před commit ponechá starý pointer/generation; pád po commit zpřístupní
  kompletní nový stav a odstraněný starý. Nikdy nesmí vzniknout pointer na
  neúplnou generation.
- 8 MiB je encoded cache budget s headroomem nad dnešním public setem a
  existujícími raw component limity; změna konstanty nevyžaduje nový modul.
- Eviction může způsobit opětovný download, nikoli ztrátu aktivních offline dat.

**Validation**

- Targeted Flutter/Dart test command pro `client_sync_store_test.dart` podle
  repository test runneru.
- Jedna fixture s více než 16 blobs a více než 8 MiB; assertion nad uloženými
  keys i čitelností current generation.

**Exit condition**

- Store tests dokazují atomické replacement, oba blob limity a odstranění cizí
  identity; veřejné `ClientSyncStore` rozhraní nezískalo policy plumbing.

### Wave 3 — Jeden publisher s 5s wake-upem a rychlým retry

**Goal**

Stejný `ClientSyncPublisher.runOnce()` je bezpečně buditelný každých pět sekund,
má bounded auth boundary a po transient class failure je práce znovu claimnutelná
v dalším ticku.

**Changes**

- `workers/sync-publisher/src/worker.ts`
  - přidat pouze `POST /v1/internal/publication-tick` fetch handler;
  - ověřit `Authorization: Bearer` proti `PUBLISHER_WAKE_TOKEN` konstantně časově,
    odmítnout body nad malý pevný limit a všechny jiné paths/metody;
  - request nesmí přijmout scope/component; zavolat publisher sestavený z
    `SYNC_SCOPE_IDS`, awaitnout výsledek a vrátit pouze status, elapsed time,
    published scope count a correlation ID;
  - scheduled handler dál volá pouze tentýž publication owner.
- `workers/sync-publisher/wrangler.toml`
  - přidat oddělený custom domain `sync-publisher.festapp.net`;
  - token zůstane Wrangler secret, nikdy `[vars]` nebo repo soubor;
  - zachovat minutový cron jako safety net.
- `workers/sync-publisher/src/supabase_database.ts` a `publisher.ts`
  - přidat `releaseClaims(tokens)` nad novým service-role RPC;
  - po partial success potvrdit successful class a uvolnit pouze failed class
    tokens; pokud selže vše, uvolnit všechny získané tokens;
  - release failure logovat a neoznačit publication jako úspěšnou; hard-crash
    recovery zůstává přes dvouminutový claim lease;
  - `entity_id=0` předat jako `eventIds=null`; targeted IDs deduplikovat;
  - zachovat existující raw byte budgets; skutečné gzip/network bytes měřit v
    release/health endpoint gate, ne druhou runtime kompresní implementací.
- Nový forward migration, například
  `supabase/migrations/20260806100000_client_sync_production_hardening.sql`
  - přidat service-role-only
    `release_client_projection_claims_v1(uuid[])` s token-scoped update;
  - žádné trigger/webhook objekty;
  - zachovat claim lease pro process death.
- `automation/release/configure_client_sync_publisher_schedule.mjs`
  - režimy `--status`, default dry-run, `--apply`, `--disable`;
  - target odvodit z `automation/project.conf`, ověřit occasion link před změnou;
  - vytvořit/ověřit Vault secrets pro endpoint a token bez jejich vypsání;
  - idempotentně instalovat named `pg_cron` job s intervalem `5 seconds`, jehož
    command provede indexed `EXISTS` nad unclaimed dirty keys omezenými na
    configured scopes a pouze při výsledku true volá `net.http_post` na internal
    endpoint; Vault secret se načte podle názvu a hodnota není v cron commandu;
  - vyžadovat `--confirm=csmostrava2026`; disable smí odstranit jen exact named
    job tohoto skriptu.
- Worker/automation tests doplnit o auth, no-body/no-scope, overlapping tick,
  partial failure release, wrong token a idempotent schedule SQL generation.

**Migration/deletion**

- Po production cutoveru odstranit `workers/sync-publisher/src/loop.ts` a
  `package.json` script `start`; `once.ts` zůstane autorizovaný manual tool.
- Neodstraňovat minutový cron: jeho final role je recovery, ne
  primary freshness.

**Failure and compatibility**

- Překrývající tick je bezpečný díky DB claims; druhý run typicky najde nula
  práce.
- Wrong/missing secret nesmí prozradit, zda queue obsahuje práci.
- Při pg_net/cron výpadku pokračuje minutový fallback; při Cloudflare cron
  výpadku pokračuje 5s primary.
- Secret rotation: nejprve nový Cloudflare secret, potom Vault, ověřit tick,
  teprve potom odstranit starou hodnotu. Pokud platforma neumí dual-secret,
  přijmout krátké publication zpoždění, ne public fallback.

**Validation**

- `cd workers/sync-publisher && npm test && npm run typecheck`.
- `node --test automation/tests/client_sync_publisher_schedule.test.mjs`.
- Targeted SQL test pro claim/release/reclaim a grants v isolated DB.

**Exit condition**

- Jediný publisher owner lze bezpečně volat HTTP/scheduled/manual cestou;
  failed claim je na dalším ticku znovu dostupný; schedule script je dry-run-first
  a neobsahuje secret v outputu.

### Wave 4 — Úplná live projekce a bezpečný occasion lifecycle

**Goal**

Každý visible event má úplný live state od okamžiku vytvoření, existující drift
je jednorázově opraven bez hardcoded IDs a sync activation nelze obejít běžným
occasion writerem.

**Changes**

- Ve stejném novém forward migration předefinovat aktuální overlay verze:
  - `save_event_client_sync_v1`: při publishable occasion přidat jeden
    `live_public` revision bump a dirty key pro `v_event_id`; platí pro insert i
    update, protože změna capacity/visibility ovlivňuje live projection;
  - `create_counseling_slots_client_sync_v1`: přidat `live_public` do public
    components a targeted dirty key pro každý `v_ids` event, ale pouze jeden
    component revision bump pro celý command;
  - zkontrolovat `delete_event_client_sync_v1` a
    `delete_empty_counseling_slots_client_sync_v1`; zachovat jejich existující
    live invalidaci a nepřidat dvojitý bump.
- `refresh_event_public_state_v1`
  - definovat `p_event_ids IS NULL` jako full scope refresh;
  - pro full refresh upsertnout všechny visible events a odstranit stale
    projection rows, které už nemají event ve scope; targeted refresh nesmí
    mazat jiné rows;
  - counts a remaining capacity počítat v jednom statement snapshotu.
- Publisher nullable contract z Wave 3 použít pro entity 0.
- V migration data step pro každou nehidden occasion s `client_sync_v1=true` a
  drift anti-join/count mismatch:
  - zamknout její live scope;
  - vytvořit jeden redigovaný `system` commit se source
    `client_sync.live_projection_repair`;
  - zvýšit `live_public` revision právě jednou;
  - full-refreshnout projection rows s novou revision;
  - enqueue `entity_id=0` dirty key nové revision;
  - nic nedělat pro zdravý scope.
- `database/tests/client_sync_v1_runtime_test.sql` a nový targeted test:
  běžný event create/update, counseling multi-create, delete, full refresh,
  targeted refresh, no-op/replay, audit a zero-drift assertions.
- `database/tests/client_sync_v1_contract_test.sql`: registry writer a grants
  zůstávají přesné; žádný trigger a žádný ordinary direct DML bypass.
- Ve stejném forward migration předefinovat occasion writery:
  - create a duplicate vždy odstraní/force `data.client_sync_v1=false`;
  - save zachová serverovou current hodnotu flagu bez ohledu na input (nebo
    fail-closed odmítne pokus o jeho změnu; zvolit jediný konzistentní kontrakt);
  - save odmítne visible->hidden a delete odmítne enabled v1 occasion s jasnou
    chybou „nejprve disable“.
- Prohloubit `automation/release/client_sync_cutover.mjs` a jeho tests:
  - status/enable/disable je jediný lifecycle interface a explicitně ověřuje
    invariant jediného enabled occasion proti `SYNC_SCOPE_IDS`;
  - enable pořadí: allowlist/preflight -> initial build/upload/hash/head verify ->
    teprve potom flag true;
  - disable pořadí: exact delete mutable R2 public head -> endpoint 404 verify ->
    teprve potom flag false; failure před posledním krokem ponechá flag true;
  - old immutable URLs zůstávají nejvýše do retention okna a smějí obsahovat jen
    public data.

**Migration/deletion**

- Opravit všechny aktuálně chybějící rows genericky; žádný seznam produkčních IDs
  nesmí být v migration.
- Needitovat applied definitions; nový migration je jediný forward overlay.
- Nepřidávat druhý activation/deactivation script; rozšířit existující cutover.

**Failure and compatibility**

- Migration je transakční a bounded na enabled v1 occasions. Lock timeout a
  statement timeout musí ukončit celý repair bez partial revision/data stavu.
- Publisher code s `null` full-refresh semantics musí být nasazen před migration,
  aby entity 0 nemohla být falešně potvrzena.
- Starý klient chybějící live položky stejně defaultuje na nulu; přidané položky
  jsou zpětně kompatibilní protocol 1 data.
- Disable není pointer rollback. Pokud je třeba obnovit obsah, publisher vytvoří
  novou vyšší revision; starý head se nikdy znovu nezapisuje.

**Validation**

- `./automation/bootstrap_local_db.sh`.
- `DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' node web_client/scripts/run_db_tests.js database/tests/client_sync_v1_contract_test.sql`.
- Stejný targeted command pro runtime/projection test.
- `node --test automation/tests/client_sync_cutover.test.mjs` včetně
  failure-injection pořadí enable/disable a flag-bypass fixtures.
- SQL absence query: visible events anti-join event_public_state = 0 a
  authoritative count drift = 0.

**Exit condition**

- Testy dokazují jeden live bump na event command, úplné rows po create/full
  refresh a žádný bump na replay/no-op; lifecycle testy vylučují flag bypass a
  stale head po úspěšném disable; production repair zůstává neaplikovaný bez
  samostatné autority.

### Wave 5 — Jednoduchá artifact retention a receipt compaction

**Goal**

Těžká serverová data zůstávají v explicitních mezích bez ztráty current
artefaktů nebo idempotency ochrany a bez dalšího stavového automatu.

**Changes**

- Forward migration přidá jen potřebné service-role maintenance RPCs:
  - read-only bounded query/RPC pro artifact candidates: přesné publication URLs
    starší než 7 dní mimo current manifest/live references; bez claim columns,
    queue tabulky nebo opravného side effectu;
  - metadata delete RPC přijme pouze exact URLs, znovu ověří age/current
    protection v téže transakci a smaže jen skutečně odstraněné R2 objekty;
  - `compact_client_mutation_receipts_v1(cutoff, limit)`: `FOR UPDATE SKIP
    LOCKED` změní pouze `completed` receipts starší 30 dní na `expired`, nastaví
    `response=NULL`, zachová PK, command metadata, request hash, actor/scope,
    commit a completed timestamp; vrátí counts/freed bytes estimate.
- `client_mutation_receipts`
  - rozšířit status/check constraint o `expired` a optional `expired_at`;
  - upravit retention partial index pro `completed` rows;
  - všechny tři `begin_*_client_mutation_v1` funkce při validním expired row
    vrátí `disposition='replay'` s deterministickou bounded 410 response a nikdy
    znovu nespustí domain DML;
  - actor/request mismatch zůstává fail-closed i po expiry.
- `workers/sync-publisher` doplnit o interní hluboký modul
  `ClientSyncRetention.runOnce({apply})`, oddělený od
  `ClientSyncPublisher.runOnce()`:
  - načíst bounded candidate metadata a object delete povolit pouze pro key
    odvozený z exact `assets.festapp.net/client-sync/v1/` URL;
  - `ObjectStore` dostane exact-key `delete`/existence API, nikdy bucket-wide
    prefix delete;
  - po úspěšném R2 delete (404/not-found je idempotentní success) zavolat
    metadata delete, který znovu ověří ochranu;
  - samostatný daily scheduled adapter spouští bounded artifact/receipt batches;
    publication tick retention ani compaction nespouští;
  - první deployment má destructive maintenance vypnutou env flagou
    `SYNC_RETENTION_APPLY=false`; dry-run metrics jsou aktivní.
- Tests:
  - current/young objects nikdy nejsou candidates;
  - unrelated `csmostrava2026/vN/` map key není nikdy listován/mazán;
  - partial delete/DB failure je idempotentně retryable;
  - concurrent forward publication nemůže udělat starý candidate current a
    metadata recheck fail-closed odmítne current URL;
  - receipt replay před 30d je exact; po compaction je deterministic expired;
    mismatch a concurrent compaction/replay neprovedou domain DML.

**Migration/deletion**

- Po sedmidenním okně a explicitním approval první apply run odstraní staré
  unprotected R2 objects a odpovídající history metadata.
- Full receipt response payloady starší 30 dní se uvolní; tombstone rows a commit
  audit zůstanou.

**Failure and compatibility**

- Mazání pořadí je R2 exact object -> DB ack. Pád mezi kroky zanechá starý
  metadata row, ale nikdy dangling current head; retry akceptuje R2 not-found.
- Ruční pointer regression je zakázaná a existující R2/Flutter monotonic checks
  ji odmítají. Obsahový rollback je corrective forward publication s novou
  revision, proto retention nepotřebuje claim state.
- Compaction nesmí zpracovat `processing` receipt. Stuck processing je health
  incident, ne retention candidate.
- Batch limity a SKIP LOCKED brání dlouhým locks. Maintenance chyba nesmí
  blokovat publication tick.

**Validation**

- Targeted SQL retention/idempotency tests v isolated DB.
- `cd workers/sync-publisher && npm test && npm run typecheck`.
- Dry-run fixture s map a sync prefixy; assertion, že delete mock viděl jen exact
  approved client-sync keys.

**Exit condition**

- Retention dry-run je bezpečný a deterministický bez nové state machine;
  receipt compaction zachovává command-ID ochranu; destructive flags jsou
  defaultně vypnuté.

### Wave 6 — Health gates, runbook a absence proof

**Goal**

Operátor umí jedním read-only commandem poznat cache/SLO/drift/retention problém
a dokumentace odpovídá skutečnému nasazení.

**Changes**

- `automation/release/client_sync_health.mjs`
  - target resolution podle `automation/project.conf` a occasion-link presence;
  - read-only report: registry readiness, dirty/claimed age, source/published lag,
    matched publication p50/p95/p99/max, visible/projection drift, receipt status
    a response bytes, retention candidate/current-protected counts, R2 bucket info a
    endpoint 200/304/cache observations;
  - fail thresholds: dirty unclaimed > 2 ticks, claimed > lease, revision lag,
    live publication p95 > 25 s v definovaném rolling window, structural p95 >
    45 s, any projection drift, stuck processing receipt, current missing
    object, hash mismatch nebo `publicationPending=true`;
  - compact JSON a human output, žádné tokeny/PII.
- `workers/sync-worker/scripts/public_load_test.mjs`
  - reportovat cache/R2 evidence dostupnou z bezpečných headers/log correlation;
    5k default zůstává pouze release gate, ne běžný test.
- Aktualizovat:
  - `docs/runbooks/client-sync-v1.md` o scheduler, secret rotation, cache,
    monitoring, explicitní repair, retention dry-run/apply, occasion lifecycle a
    forward-only rollback;
  - `docs/runbooks/client-sync-v1-implementation-status-2026-08-03.md` přejmenovat
    nebo nahradit current status dokumentem; odstranit tvrzení „not deployed“;
  - `docs/architecture/database.md` o maintenance RPCs/status;
  - původní sync plan pouze označit jako historical design baseline a odkázat na
    tento hardening plan; nepřepisovat jeho historická měření.
- `automation/client_sync_preflight.mjs` a cutover tests rozšířit o absence
  triggeru, scheduler status, current-reference retention invariants a registry.

**Migration/deletion**

- Odstranit zastaralý production status a všechny instrukce, které by spouštěly
  `loop.ts` jako druhý daemon nebo doporučovaly blanket bucket cleanup.

**Failure and compatibility**

- Health command je read-only default. Jakýkoli repair/prune vyžaduje explicitní
  jiný command/flag a potvrzení targetu.
- Cloudflare request/operation billing se hodnotí z reálných dashboard metrics;
  syntetický test nesmí být vydáván za účetní skutečnost.

**Validation**

- `node automation/check_client_sync_registry.mjs`.
- `node automation/client_sync_preflight.mjs`.
- `node --test automation/tests/client_sync_cutover.test.mjs automation/tests/client_sync_publisher_schedule.test.mjs automation/tests/client_sync_health.test.mjs`.
- `rg` absence proof pro `loop.ts`, nepravdivý status, trigger/webhook a
  nechráněný prefix delete.

**Exit condition**

- Read-only health command reprodukuje známé metriky a správně failne fixture s
  cache/SLO/drift/retention porušením; runbook obsahuje přesný rollout i rollback.

### Wave 7 — Autorizovaný production rollout

**Goal**

Nasadit hardening bez přerušení protocol 1, ověřit SLO a teprve po retenčních
oknech povolit destruktivní maintenance.

**Changes**

1. Read-only preflight: správný Supabase target/occasion, backup/restore point,
   registry, current lag/drift, Cloudflare routes/account, R2 current hashes,
   cron/pg_net/Vault availability a baseline request/cost metrics.
2. Nasadit `sync-worker` cache změnu. Ověřit 200/HEAD/304/CORS, max 5s staleness,
   R2-read reduction a žádný DB binding.
3. Vydat klienta s bounded `ClientSyncStore`; ověřit upgrade existujícího store,
   offline current generation a cleanup cizí identity na disposable účtu.
4. Nasadit publisher s interním endpointem, retention apply vypnutou a minutovým
   fallbackem. Provision custom domain a Cloudflare secret; wrong-token smoke.
5. Zapsat stejný token/URL do Supabase Vault bez logování hodnoty. Ještě
   neaktivovat 5s job.
6. Aplikovat forward migration včetně writer/lifecycle guards a generic event
   projection repair. Ověřit zero drift, nový audit commit/revision, flag-bypass
   absence, dirty key a následný healthy head.
7. Cutover status preflightem dokázat jediný enabled scope a shodu se
   `SYNC_SCOPE_IDS`; enable/disable smoke pouze na disposable scope, ne na živé
   occasion 643 bez zvláštního schválení.
8. Aktivovat named conditional 5s scheduler přes guarded automation command.
   Sledovat nejméně
   24 hodin DB request rate, pg_net failures, Worker errors, dirty/claim age,
   publication p95/p99, R2 reads a cost trend.
9. Provést autorizovaný 5k public test a legitimate-account private handshake
   test. Potvrdit live p95 <=25 s a structural p95 <=45 s včetně klientského
   pollu, ne pouze DB->publication.
10. Po 7 dnech reviewnout artifact retention dry-run. Se samostatným potvrzením
   zapnout R2 apply a ověřit current objects + DB/R2 parity.
11. Po 30 dnech reviewnout receipt compaction dry-run. Se samostatným potvrzením
   povolit compaction a ověřit exact/expired replay kontrakt na disposable data.
12. Aktualizovat recorded status s konkrétními deployment IDs, časy a metrikami.

**Migration/deletion**

- Produkční data repair je součást kroku 5 a nesmí být spuštěn ad hoc před
  compatible publisherem.
- První skutečné deletions jsou oddělené kroky 10/11 a nejsou implicitní součástí
  deploye.

**Failure and compatibility**

- Kill switch pro nové sessions zůstává stávající guarded disable. Vypnutí 5s
  jobu vrátí publication na minutový recovery tick, nikoli na legacy sync.
- Rollback cache Workeru je code rollback. Rollback publisheru před DB migration
  je bezpečný; po migration musí podporovat nullable full refresh a claim release
  contract.
- DB migration se nevrací editací historie. Incident se řeší forward fixem,
  vypnutím 5s scheduleru/retention apply a zachováním posledních healthy heads.

**Validation**

- `node automation/release/client_sync_health.mjs --remote` před a po každém
  produkčním kroku.
- Endpoint smoke a přesné DB/R2 observations popsané v runbooku.
- 5k testy pouze s explicitní autoritou.

**Exit condition**

- 24h rolling production evidence ukazuje zero drift/lag/error, publication SLO
  v limitu a podstatné snížení R2 reads; destructive retention zůstává pending,
  dokud neuplyne její okno a není samostatně schválena.

## Rollout and rollback

Lokální implementace a testy nesmějí měnit produkci. Produkční pořadí je pevné:
cache serving -> publisher endpoint se disabled retention -> secrets -> DB
migration/repair -> 5s scheduler -> observation/load gate -> delayed retention.

Rollback nesmí obnovit přímé client DB loadery, legacy cache ani delta cestu:

- serving incident: rollbacknout pouze `sync-worker` version nebo dočasně obejít
  Cache API, stále přes R2 head;
- publisher incident: deaktivovat exact named 5s cron job, minutový stejný
  publisher zůstane fallback;
- projection incident: použít guarded cutover disable (head delete/404 před
  flagem), potom opravit forward migration; neměnit již aplikovanou migration;
- retention incident: `SYNC_RETENTION_APPLY=false`, nepokračovat v delete batchi,
  opravit forward a publikovat novou vyšší revision; nikdy nevracet pointer na
  starou revision;
- secret incident: rotovat Cloudflare/Vault token podle dual-value pořadí a
  zkontrolovat logs bez vypsání secretu.

## Verification strategy

| Risk or invariant | Verification seam | Command/observation |
|---|---|---|
| Cache hit nečte R2 | Worker fake cache + R2 spy | `cd workers/sync-worker && npm test` |
| HTTP/protocol kompatibilita | Worker request tests | 200/HEAD/304/OPTIONS/404/405 assertions |
| Publisher endpoint auth/scope | Worker tests | wrong token/no scope/body bounds; DB spy untouched |
| Claim retry | Publisher + SQL tests | partial class failure, release exact tokens, next claim succeeds |
| 5s schedule safety | Automation unit test + status SQL | named/idempotent cron, secrets redacted, guarded disable |
| Lokální storage bound | `ClientSyncStore` + in-memory adapter | atomic replacement, max 16/8 MiB, restart/identity cleanup |
| Event projection completeness | pgTAP/runtime SQL | create/update/counseling/delete/full refresh/anti-join |
| One revision per command | Commit component assertions | apply vs replay/no-op counts |
| Backfill auditability | Migration fixture | one system commit per unhealthy scope, zero for healthy |
| Occasion lifecycle authority | SQL + cutover failure injection | flag bypass rejected; head delete/404 precedes disable flag |
| Receipt idempotence po compaction | SQL concurrency tests | exact replay <30d, 410 replay >30d, no second DML |
| Artifact deletion safety | Retention fake R2 + DB candidates | only exact approved sync keys; current/map keys untouched |
| Concurrent retention/publication | SQL + retention race fixtures | current recheck fail-closed; no revision regression path |
| Payload budgets | Publisher tests + endpoint gate | raw accept/reject; actual compressed/network measurement |
| Full repository integration | Project gates | `./automation/test_all.sh` once after targeted checks pass |
| Production SLO | Read-only health + authorized load | rolling p95/p99 and 5k test, no dirty/drift |

Standard verification during implementation runs targeted Worker, automation and
isolated DB checks after coherent waves, then one `./automation/test_all.sh` at
handoff. Release-only load/deploy/destructive checks remain separately gated.

## Definition of complete

- [ ] Public head uses Cache API and cache hits/304 do not read R2.
- [ ] Primary production publisher tick is 5 s and calls the single canonical
      publisher pouze při dirty práci; minute tick je documented recovery.
- [ ] `loop.ts` production alternative is removed; one-shot remains bounded.
- [ ] Failed class claims are explicitly released and hard-crash lease remains.
- [ ] `ClientSyncStore` atomicky nahrazuje generations, blob cache je max
      16 položek/8 MiB a private data jiné identity po bootstrapu nezůstávají.
- [ ] Every visible event has correct live projection; all event writers
      invalidate it exactly once.
- [ ] Full refresh `null` and targeted refresh semantics jsou testované.
- [ ] Existing production drift repair is generic, auditovaný a buď autorizovaně
      aplikovaný, nebo explicitně označený jako pending operational step.
- [ ] Occasion create/duplicate/save nemění activation flag, enabled hide/delete
      failnou a jediný cutover interface dodržuje bezpečné enable/disable pořadí.
- [ ] Raw public budgets jsou enforceované a actual compressed/network headroom
      je součást release/health měření.
- [ ] Artifact retention chrání current/young set a nikdy nesáhne mimo
      `client-sync/v1/`.
- [ ] Exact receipts se po 30 dnech compactují na permanent tombstones bez
      možnosti opakovaného DML.
- [ ] Commit audit zůstává immutable a mimo hot path.
- [ ] Health command a runbook pokrývají cache, SLO, drift, claims, retention,
      billing metrics, secret rotation, rollout a rollback.
- [ ] Stará nepravdivá production-status tvrzení a alternativní runtime odkazy
      jsou odstraněné.
- [ ] Targeted standard checks a jeden full repository validation batch projdou.
- [ ] Produkční deploy, migrace, scheduler, load a destructive retention jsou
      provedené pouze se samostatnou autoritou a mají recorded evidence.

## Residual risks

- Cache API je PoP-scoped, takže velmi rozptýlený provoz stále vytvoří přibližně
  jeden R2 read na PoP/TTL. Reálné R2/Worker billing metrics musí zůstat součástí
  monitoringu.
- Pětisekundový cron provede přibližně 17 280 levných indexed `EXISTS` denně, ale
  prázdná queue nevyvolá HTTP ani claim RPC. Skutečný DB/pg_net cost se ověří po
  24 hodinách; případná změna intervalu musí znovu projít SLO gate.
- Hard process death může držet claim do lease expiry; explicitní release řeší
  běžné chyby, nikoli náhlé ukončení runtime.
- Offline klient s pouze starým, lokálně neúplným manifestem nemůže po sedmi
  dnech spoléhat na starý remote artefakt. Po návratu online musí nejprve získat
  current head; klientský bootstrap test to musí dokazovat.
- Direct URL starého immutable public artefaktu může fungovat do sedmidenního
  prune. To je přijatelné jen proto, že artefakty neobsahují private data;
  disable okamžitě odstraňuje pouze discovery head, nikoli již stažené kopie.
- Bez externího Supabase Log Drain zůstává dříve přijaté audit-retention riziko
  beze změny; tento plán je nezvětšuje ani neřeší.
