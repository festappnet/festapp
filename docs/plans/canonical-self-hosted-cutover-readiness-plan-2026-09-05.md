# Dokončení canonical self-hosted Supabase cutoveru

Datum: 2026-09-05
Stav: připraveno k realizaci, produkční cutover je zatím NO-GO
Ověření: release

## Výsledek

`https://api.festapp.net` se stane jedinou relační, Auth a Supabase Storage
write autoritou. Cloudové projekty `default`, `a` a `slunovrat` po přepnutí
zůstanou po schválenou retenční dobu pouze ke čtení. Žádný klient, Function,
cron, callback, worker ani operátor nesmí po otevření cílových zápisů zapisovat
do cloudu.

Tento plán aktualizuje zbývající provedení původního plánu
`docs/plans/festapp-self-hosted-supabase-hetzner-plan-2026-08-27.md`. Jeho
historické hybridní vlny se již nepoužijí: závazná produkční strategie je jeden
koordinovaný `full-freeze` podle
`docs/operations/supabase-self-hosted/cutover-runbook.md`.

## Rozsah

### V rozsahu

- uzavření klientských, provider, databázových a provozních bran;
- čerstvý třízdrojový export/import do přesně označeného cíle;
- produkční promotion, aktivace pinned one-way manifestů a otevření zápisů;
- důkaz jediné write autority a následná kontrakce legacy cest.

### Mimo rozsah

- journal-hybrid, dual-write, reverse sync nebo opětovné otevření cloudových
  zápisů po prvním kanonickém zápisu;
- smazání cloudových projektů, dat, Storage, DNS, credentials nebo důkazů bez
  samostatného destruktivního souhlasu;
- paralelní multi-tenant buildy; Android release lanes proběhnou sekvenčně;
- změna dostupnostní topologie bez samostatného rozhodnutí.

## Současný stav

**Verdikt aktualizovaný 2026-09-08: NO-GO pro samotné přepnutí.** Většina
pre-window základů je hotová,
ale produkční readiness receipt nelze poctivě vytvořit. Přepnutí dnes by obešlo
explicitní fail-closed brány.

| Oblast | Potvrzený stav | Dopad |
|---|---|---|
| Canonical kontrakt | `docs/operations/supabase-self-hosted/architecture.md`: jeden endpoint, full freeze, cloudy read-only | Cílová architektura je uzavřená. |
| Merge a recovery rehearsal | `second-canonical-rehearsal-2026-08-28.md`: dvě kompletní sloučení, Auth/Storage, RPO 0, restore a runtime switch | Importer a základní recovery cesta jsou prokázané; nejde ale o čerstvý produkční snapshot. |
| Repo gate | Na čistém `origin/main` `ea7f13d2e` prošel `repository-cutover-preflight.mjs`: `repository_ready=true`, 148 writer kandidátů, 0 unknown, 14 prod refs, 0 unknown tenantů, 0 pending retirementů | Commitnutý stav repozitáře je připravený. Gate z principu nechává `production_cutover_authorized=false`. |
| Lokální strom | Aktuální pracovní strom má nesouvisející iOS/Fastlane změny a necommitnutý `workers/supabase-legacy-keepalive/`; lokální scan proto vidí 154 kandidátů | Před finálním gate musí být zamýšlené změny integrovány nebo odstraněny z release worktree. Uživatelské změny se nesmí přepsat. `.mjs` discovery navíc odhalila dříve neklasifikovaný monitor i keepalive. |
| Tenant overlaye | Všech 11 aktivních overlayů obsahuje dnešní `main`; tři staré refs jsou úmyslně uzavřené retirement hranice | Synchronizace aktivních větví je hotová. |
| Web | Všech 11 aktivních web deploymentů z 2026-09-04 uspělo v GitHub Actions. Veřejné `backend-activation.json` vrací `200`, `no-store`, `backend=legacy`, `generation=0` | Transition weby jsou staged a stále bezpečně zapisují do legacy zdrojů. Aktivace dosud neproběhla. |
| iOS | Veřejný App Store readback potvrzuje sedm aktivních aplikací na `0.19.95` | Publikace je hotová, ale adopce není uzavřená. App Store analytics byla 2026-09-02 blokována rolí 403 a OneSignal stále viděl starší nekompatibilní verze u některých tenantů. |
| Android | Šest autorizovaných identit je v Play production na `0.20.1 (485)`, full rollout, s nezávislým readbackem; jejich source organizace zobrazují soft update prompt `0.20.1`. `fstapp.fstapp` nebyla publikována. | Release gate je uzavřený pro šest lane; zbývá adoption/technically-read-only evidence a retire/read-only dispozice `fstapp.fstapp`. |
| Databázová parita | `default` a `a` mají všechny tři migrace `20260906120000`–`20260906140000` a shodný finální function/ACL/search-path kontrakt. | Self-hosted katalogový readback je stále nutný; veřejný runtime je zdravý, ale SSH z aktuálního operátorského připojení timeoutuje. |
| Runtime | `api.festapp.net` dnes vrací očekávané Auth/REST `401` a Storage `200`; DNS je přes Cloudflare a TLS platí do 2026-11-13 | Veřejný origin je živý, ale health není promotion ani write-activation důkaz. |
| Recovery | Off-host encrypted backup a starší isolated restore byly prokázány; readiness validator přijímá restore důkaz nejvýše 7 dní starý | Rehearsal z 28. srpna je pro finální gate již za hranicí čerstvosti. Je nutný nový úplný isolated restore, ne jen `pg_restore --list`. |
| Dostupnost | Jeden CAX11 node, measured restore RTO 790 s, bez repliky/failoveru | Před window musí vlastník výslovně přijmout `single-node-recovery`, nebo se musí zvlášť navrhnout replikovaná topologie. |
| Externí writery | Repo policy má 0 unknown a 18 mutujících runtime surfaces | Live AWS SNS, Vault/notify, OneSignal, payment callbacks, SMTP, sync worker a ostatní canaries stále nemají společný čerstvý passing receipt. |
| Farnost Opava | Starý `rezervace.farnostopava.cz` dnes zachovává path/query přes 301 na `farnostopava.festapp.net`; canonical origin vrací 200 | Starý WEDOS CNAME handoff už není technickým DB-cutover blockerem, pokud je redirect finální produktové rozhodnutí. Starší work item/matice se musí opravit. |

## Cílový kontrakt a invarianty

### Canonical owner

Canonical owner je jeden pinned self-hosted Supabase runtime za
`api.festapp.net`. PostgreSQL vlastní autorizaci, durable business DML,
idempotenci a audit v explicitních RPC transakcích. Cloudflare je front door a
R2/image boundary, nikoli druhá relační write vrstva.

### Invarianty

1. Před snapshotem jsou aktivní všechny lane `application`, `auth-refresh`,
   `cron`, `edge-functions`, `manual`, `storage` a `webhooks`; na zdrojích není
   žádná mutující session.
2. Každý klientský lane je `adopted`, `technically-read-only` nebo `retired` s
   důkazem mladším než 24 hodin a bez neznámé/nekompatibilní aktivní verze.
3. Target side effects i write barrier zůstanou zavřené během importu a validace.
4. Final marker, import inventory, encrypted promotion backup, isolated restore
   a promotion receipt patří témuž timestampovanému targetu.
5. Po prvním cílovém zápisu se cloudy nikdy znovu neotevřou; recovery je pouze
   restore nebo forward repair self-hosted cíle.
6. Legacy cloudy se nemažou bez zvláštního souhlasu.

### Povolené vstupy a zakázané bypassy

- Klienti přepínají pouze přes předem připravený, digestem připnutý a monotónní
  `backend-activation.json`; běžící native proces musí projít úplným cold startem.
- Edge Functions, crony, callbacks, workery a manuální nástroje používají pouze
  registry/policy popsané v runbooku.
- Zakázané jsou dynamický nekompilovaný endpoint, klientský dual-write,
  `journal-hybrid`, přímé cloudové DML po aktivaci a persistentní aplikační
  merge trigger.

## Rozhodnutí, předpoklady a blokátory

### Rozhodnutí

- **D1:** Produkční režim je `full-freeze`; hybridní návrh z původního plánu je
  superseded.
- **D2:** Dnes se nepřepíná. Nejprve se uzavřou Android/adoption a pre-window
  důkazy, teprve poté se rezervuje maintenance window.
- **D3:** `workers/supabase-legacy-keepalive/` je při zachování návrhu pouze
  read-only retention boundary. Musí být commitnutý a klasifikovaný v runtime
  inventory/deletion ledgeru, nebo nesmí být nasazen. Jeho cron se po retention
  odstraní; nesmí získat service-role credential ani write oprávnění.
- **D4:** Farnost WEDOS změna CNAME se vyřadí z cutover blockerů, pokud vlastník
  potvrdí už nasazený redirect na `farnostopava.festapp.net` jako finální stav.

### Předpoklady

- **A1:** Sedm iOS `0.19.95` buildů obsahuje přesně schválený pinned transition
  profil; ověřit privátními manifesty a artifact digesty, ne jen App Store verzí.
- **A2:** Staged Function bundle na hostu odpovídá funkčnímu obsahu dnešního
  `main`; znovu svázat digest s finálním repository headem před promotion.
- **A3:** Denní backup a pětiminutový monitor od 2. září stále běží; ověřit
  poslední off-host receipts a alert freshness, nikoli stav odvodit z timeru.

### Aktuální blokátory

- **B1:** Šest Android release lane je vydaných; chybí adoption nebo
  technically-read-only evidence a retire/read-only dispozice `fstapp.fstapp`.
- **B2:** Chybí úplná iOS active-version/minimum-version adoption evidence.
- **B3:** Cloud `default` a `a` mají shodný aktuální migrační kontrakt; chybí
  self-hosted katalogový readback migrací z 6. září kvůli SSH timeoutu.
- **B4:** Chybí čerstvý úplný isolated restore a explicitní přijetí
  single-node recovery rizika, nebo replikační design.
- **B5:** Chybí čerstvé passing canaries všech 11 integrací požadovaných
  `validate-operational-readiness.mjs`.
- **B6:** Chybí named maintenance window, freeze owners, pre-snapshot/final
  marker, finální import, promotion backup/restore a go/no-go receipts.
- **B7:** Legacy keepalive a Function guard jsou nasazené, `.mjs` discovery a
  šest-Worker policy jsou lokálně canonicalizované; změny musí projít release
  gate a být commitnuté. Všech 11 aktivních overlayů se potom musí sekvenčně
  srovnat s finálním `main`.
- **B8 (closed operationally):** Veřejný pre-activation guard je nasazený na
  přesné Function route a ověřeně vrací `503/no-store`; odstranit jej lze pouze
  po promotion a interním ověření canonical Function bundle.

## Deletion ledger

| Artefakt | Současná role | Finální akce | Důkaz |
|---|---|---|---|
| Cloud `default`, `a`, `slunovrat` | aktivní legacy authority | po cutoveru read-only retention; nemaže se bez souhlasu | grants/session/traffic evidence |
| Legacy URL/key větev pinned resolveru | předaktivační fallback | odstranit až po adopci a retention; resolver rozhraní zůstává | completed-bundle a config scan |
| `workers/supabase-legacy-keepalive` | zamýšlený read-only anti-pause cron | retain boundary během retention, poté odstranit | policy + request method/credential test + Worker inventory |
| `workers/self-hosted-preactivation-guard` | fail-closed hranice před promotion | odstranit přesně po interním Function ověření a před externími canaries | route inventory + hardened Function probes |
| Cloud Management API/deploy cesty | dočasná správa zdrojů | odstranit po self-hosted deploy proof | `rg`, config a credential inventory |
| Target ingest/receipts, staging a mapy | import/audit hranice | odstranit až po stabilization a audit exportu | schema/reachability scan |
| Staré cloud credentials | rollback/retention | revokovat po adopci a retention | revoke test |
| Cloud projekty a data | rollback archiv | pouze explicitně schválené smazání | final export, zero traffic, delete receipt |

## Realizační vlny

### Vlna 0 — Opravit zdroj pravdy a znovu zavřít repo gate

**Cíl**

Aktuální dokumentace, policy a release worktree popisují stejný skutečný stav.

**Změny**

- Aktualizovat otevřený work item a client matrix: 11 web lanes z 4. září,
  sedm live iOS `0.19.95`, uzavřené legacy retirementy, nový Farnost redirect a
  stále chybějící Android/adoption evidence.
- Rozhodnout a canonicalizovat `workers/supabase-legacy-keepalive`: přidat jej
  jako read-only retention boundary do writer/runtime policy, testů a deletion
  ledgeru, nebo ho nenasedit a odstranit z kandidáta.
- Na všech třech zdrojích/targetu read-only ověřit migration ledger a katalog
  pro `20260831220000_reconcile_invitation_delivery_status.sql`; chybějící cíl
  doplnit pouze schválenou release DB cestou.
- Dokončit nebo oddělit lokální Fastlane změny bez přepsání uživatelské práce.

**Validace**

- `node automation/hetzner-supabase/merge/repository-cutover-preflight.mjs`
  na čistém synchronizovaném `main`.
- Třícílový parity report se shodným migration SHA, ledger row a katalogovým
  kontraktem.
- `./automation/test_all.sh` jako release gate po integraci změn.

**Exit**

Čistý aktuální `main` vrací `repository_ready=true`, žádný runtime vstup není
untracked/unclassified a třícílová SQL parita je doložená po poslední migraci.

### Vlna 1 — Zavřít klientské release a adoption lanes

**Cíl**

Každá aktivní web/iOS/Android identita má transition artifact a starý writer už
nemůže být přijat jako podporovaný aktivní klient.

**Změny**

- Na Windows obnovit polling a zpracovat sedm Android produktů sekvenčně.
  Před každým buildem provést read-only Play inspection, zvolit version code nad
  aktuálním maximem, svázat package/source/manifest/AAB/signature hash a teprve
  po přesné autorizaci publikovat.
- Pro každý Android i iOS lane získat store state, active-version nebo enforced
  minimum-version evidence a legacy/canonical physical-device canary.
- Ověřit všech 11 web activation dokumentů, cache headers, cold start, refresh
  nebo reauth, rights a jeden idempotentní write proti rehearsal/final targetu.

**Selhání a kompatibilita**

- Upload, schválení nebo jedna platforma neuzavírá lane.
- Starý native proces se nepřepíná foregroundem; vyžaduje úplný restart.
- Neznámá či nekompatibilní aktivní verze je no-go, ne důvod pro fallback.

**Validace**

- Privátní release manifests a podepsané artifact receipts.
- Public/store readback plus telemetry mladší než 24 hodin.
- `release_lane_preflight.mjs` a `client_cutover_preflight.mjs` pro každý lane.

**Exit**

Operational evidence hlásí `unknown_active_versions=0`,
`incompatible_active_versions=0` a každý lane má uzavřenou dispozici.

### Vlna 2 — Obnovit čerstvou provozní připravenost

**Cíl**

Host, recovery, monitoring a všechny externí integrace mají čerstvý passing
důkaz použitelný pro konkrétní maintenance window.

**Změny**

- Výslovně přijmout `single-node-recovery` s RTO 790 s, nebo připravit a
  nacvičit repliku před pokračováním.
- Ověřit poslední encrypted off-host DB/Storage/runtime backup a provést nový
  úplný isolated restore s RPO 0; výsledek musí být mladší než 7 dní.
- Projít přesně: Auth password/OAuth/refresh, AWS SNS, Edge Functions,
  OneSignal, payment callbacks, Realtime, SMTP, Storage a sync worker.
- Zapsat připravený notify token do finálního target Vaultu, ověřit shodu s
  Function secret a instalovat pouze canonical HTTPS callback.
- Z čerstvé finální mapy vytvořit `sync-publisher` scope IDs; nikdy nepoužít
  historické cloudové ID 643.
- Refreshnout host tooling, Function bundle a runtime digests proti finálnímu
  `main`; ověřit disk headroom, TLS, Cloudflare-only ingress, monitoring a alert.

**Validace**

- Všechny položky `validate-operational-readiness.mjs` mají pravdivý receipt a
  požadovanou čerstvost.
- Externí Auth/REST/Storage/Realtime probes a induced alert/recovery pass.

**Exit**

Nezbývá pre-window blocker; jedinými chybějícími důkazy jsou ty, které lze
pravdivě vyrobit až během schváleného freeze window.

### Vlna 3 — Schválit window a provést full freeze

**Cíl**

Všechny tři cloudové zdroje jsou konzistentně zmrazené před snapshotem.

**Změny**

- Schválit nejméně 60min window, jmenovat maintenance ownera/on-call a připravit
  status/customer komunikaci.
- Do 30 minut před freeze vytvořit private operational-readiness decision pro
  přesný timestampovaný target.
- Aktivovat a doložit sedm freeze lanes, zablokovat target writes/side effects a
  ověřit nula mutujících sessions.
- Teprve potom pořídit čerstvé encrypted snapshots `default`, `a`, `slunovrat`
  včetně Auth a Storage a vytvořit `pre-snapshot` decision.

**Exit**

Fresh full-freeze receipt předchází všem finálním snapshotům a cloudy zůstávají
zmrazené až do aktivace nebo pre-write rollbacku.

### Vlna 4 — Finální import, restore a promotion

**Cíl**

Přesný target obsahuje poslední zdrojový stav a je připravený, ale stále
read-only vůči produkčním writerům.

**Změny**

- Importovat třikrát označené snapshoty stejnou dvakrát rehearsed transformací.
- Ověřit markers, konflikty, FK, Auth hash/session/refresh continuity, Storage
  payloady, tenant mappingy a business invarianty.
- Vytvořit encrypted promotion backup a obnovit jej izolovaně; inventura se musí
  přesně shodovat s targetem.
- Zavřít target DB write barrier a spustit jediný
  `promote-production-runtime.sh`; ověřit runtime DB binding a všechny interní
  canaries. Promotion sama nesmí aktivovat klienty ani zápisy.

**Exit**

Unexpired final-marker, backup/restore a promotion receipts ukazují na stejný
target; zdroje i target writes zůstávají zavřené.

### Vlna 5 — Jednorázová aktivace a důkaz jediné autority

**Cíl**

Veřejné vstupy atomicky přejdou na canonical runtime bez paralelního writeru.

**Změny**

- Po samostatném final go/no-go přepnout server writery/callbacks/workery,
  otevřít target barrier a aktivovat přesně připnuté klientské manifesty.
- Provést cold-start, refresh/reauth, rights, write, external-effect a receipt
  canaries pro každou aktivní identitu.
- Ověřit cloudy read-only, nula cloudových mutací a jediný canonical writer.

**Rollback**

- Před prvním target write lze routing vrátit ke stále zmrazeným cloudům.
- Po prvním target write se cloudy neotevírají; pouze target restore nebo
  forward repair.

**Exit**

`api.festapp.net` je jediná write authority a každý produkční lane má passing
canonical canary.

### Vlna 6 — Stabilizace a contraction

**Cíl**

Legacy cesta zůstane pouze jako přesně omezený read-only retention boundary a
po schválené lhůtě zmizí.

**Změny**

- Sledovat Auth, error/latency, DB, Storage, Realtime, Functions, callbacks a
  side-effect receipts po schválené stabilizační okno.
- Odstranit legacy URL/key větve, dočasné ingest/map/staging kontrakty a staré
  credentials podle deletion ledgeru.
- Retention keepalive zachovat jen po dobu, kdy má udržovat read-only cloudy;
  poté jej odstranit spolu s cloud refs.
- Cloudy smazat pouze po samostatném explicitním destruktivním souhlasu.

**Exit**

Reachability a absence scan nenachází žádný zapisovatelný cloudový nebo druhý
business path; open work item je přesunut do completed.

## Verification strategie

| Riziko | Důkaz | Příkaz/pozorování |
|---|---|---|
| Repo úplnost | clean main, overlaye, writery, Functions | `repository-cutover-preflight.mjs` |
| SQL parity | všechny tři migration ledgers a katalog | schválený read-only třícílový parity report |
| Klientská kompatibilita | artifact + store + adoption + canary | lane preflights a privátní receipts |
| Freeze úplnost | sedm controls, nula sessions | `cutover-mode-gate.mjs --phase=pre-snapshot` |
| Import přesnost | markers, FK, konflikty, Auth/Storage | `cutover-mode-gate.mjs --phase=final-marker` a merge validátory |
| Recovery | exact inventory, RPO 0, RTO pod window | encrypted backup + isolated restore receipt |
| Promotion | exact target a closed barrier | `validate-production-promotion.mjs` a promotion receipt |
| Jediná autorita | cloud deny + canonical canaries | grants/session/traffic/provider receipts |
| Legacy absence | config/runtime/DNS/credential/schema scan | deletion-ledger proof |

## Definition of complete

- [ ] Poslední migrace je prokazatelně identická na všech třech DB cílech.
- [ ] Každý web/iOS/Android lane je adopted, technically read-only nebo retired.
- [ ] Každý runtime/externí writer je klasifikovaný a má čerstvý freeze/canary.
- [ ] Single-node risk je přijat, nebo je nacvičená replika.
- [ ] Fresh snapshots, final marker, import, backup/restore a promotion patří
      témuž cíli.
- [ ] `api.festapp.net` je jediná write autorita; cloudy jsou read-only.
- [ ] Legacy artefakty jsou odstraněné nebo mají explicitní retenční hranici a
      exit condition.
- [ ] Žádný cloud nebyl smazán bez samostatného souhlasu.

## Reziduální rizika

- Největší riziko není merge algoritmus, ale klient, callback nebo operátor,
  který by obešel freeze. Proto se nesmí zkrátit live evidence jen proto, že dvě
  rehearsals prošly.
- Single-node provoz má doloženou obnovu, ne high availability. Přijetí RTO je
  produktové/provozní rozhodnutí.
- App Store/OneSignal adoption data nejsou z aktuální role kompletní. Bez jiné
  autoritativní telemetry musí být staré verze technicky vyloučené.
- Dokumentace z 2. září obsahuje stale stavy; vlna 0 ji musí opravit, aby se při
  window nepoužil starý blocker nebo naopak nevynechal nový.
