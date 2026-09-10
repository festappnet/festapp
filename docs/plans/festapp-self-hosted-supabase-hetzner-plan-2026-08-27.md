# Festapp: jeden self-hosted Supabase na Hetzneru a okamžitá konsolidace projektů

**Stav:** připraveno k realizaci po schválení rozhodovacích bran
**Datum:** 2026-08-27
**Režim ověření:** standard — jde o autentizaci, produkční data, migraci DB a produkční provoz
**Vzor:** provozní principy Mendelio.net, nikoli slepé převzetí jeho starší runtime revize

## 1. Výsledek

Festapp bude mít jeden vyhrazený Hetzner Cloud VPS a na něm jeden kanonický,
self-hosted Supabase projekt. Dva dnešní Supabase Cloud projekty:

- **Vstupenky.online backend** — `kjdpmixlnhntmxjedpxh`, v technické
  konfiguraci dále `default`; používají jej mimo jiné produkční větve
  `prod/festapp` a `prod/festapptickets`,
- **Festapp A backend** — `lwfpdjxsdmkfyrzqbrlk`, v technické konfiguraci dále
  `a`; používají jej tenantové označení `IMAGE_PROJECT_ID=a`, například
  CSM Ostrava a další produkční instalace,

se nesmí zachovat jako dvě trvalé databáze. `default` je výchozí kanonický základ.
Data, Auth identity, Storage metadata a tenanty projektu `a` se do něj řízeně
sloučí. Kolize se řeší verzovanými pravidly a mapami, nikoli přepisem podle
pořadí importu.

Předmětem sloučení tedy nejsou pouze dvě vybrané organization rows. Migrují se
**všechny organizace, unity, occasions, uživatelé a navázaná data ze všech
tenantů obou uvedených Supabase projektů**. Organization ID je lokální uvnitř
zdrojového projektu — například hodnota `3` existuje v obou — a proto se každá
organizace identifikuje dvojicí `(source_project, organization_id)` a dostane
jednoznačné cílové mapování.

Konečný veřejný kontrakt je jediný endpoint:

```text
https://api.festapp.net
```

Po omezenou dobu poběží hybridní fáze. Ta neznamená dva rovnocenné backendy:

- tenanty původního `default` zapisují pouze do kanonického self-hosted cíle;
- dosud nepřepnuté tenanty `a` zapisují pouze do cloudového `a`;
- každý zápis v `a` prochází journalovanou RPC cestou a je jednosměrně,
  idempotentně přehrán do cíle;
- cílový replay nespouští znovu e-maily, platby, push notifikace ani jiné
  externí efekty;
- při finálním cutoveru se `a` zmrazí, journal se vyprázdní, ověří se data a
  tenanty se přepnou na jediný endpoint;
- journal, forwarder, dočasný hostname a zdrojové cesty se potom odstraní.

Neexistuje klientský dual-write, obousměrná synchronizace ani řešení konfliktů
typu „last write wins“.

## 2. Rozsah

### V rozsahu

- autoritativní inventura obou cloudových projektů a všech zapisovatelů;
- sizing a vytvoření jednoho Hetzner VPS;
- hardening OS, síť, Caddy/origin, monitoring, alerting a zálohy;
- jeden pinned self-hosted Supabase runtime;
- přenos `default` do self-hosted cíle;
- deterministické sloučení `a` do téhož cíle;
- řešení kolizí číselných ID, UUID, Auth identit, unikátních klíčů a Storage objektů;
- dočasný jednosměrný hybridní most;
- změny klientských konfigurací, release automatizace, Edge Functions, cronů,
  webhooků a image workerů;
- rehearsals, cutover, rollback hranice, pozorování a odstranění legacy cest.

### Mimo rozsah

- druhý produkční Supabase server nebo trvalý warm standby;
- aktivní/aktivní databázový cluster;
- migrace R2 obrázků do Supabase Storage; existující R2 buckety mohou zůstat
  oddělené, ale jejich autorizační Supabase bude po cutoveru jediný;
- změna hlavní verze PostgreSQL současně s datovým cutoverem;
- redesign obchodní logiky, RLS nebo doménového modelu mimo nutné řešení kolizí;
- mazání cloudových projektů před uplynutím retenční a důkazní lhůty.

## 3. Zjištěný současný stav

| Zjištění | Důkaz v repozitáři | Dopad |
|---|---|---|
| Produkční větve ukazují na dva cloudové projekty. | `automation/project.conf` v hlavní a produkčních větvích | Migrace je konsolidace dvou zdrojů, ne prostý restore jednoho projektu. |
| `ORGANIZATION_ID=3` se vyskytuje u tenantů v obou projektech. | konfigurace produkčních větví | Číselná ID nejsou globální a musí se mapovat podle zdroje. |
| Autoritativní projekt se vybírá z `SUPABASE_URL` tenant konfigurace; `.env.local` ani `supabase/.temp/project-ref` nejsou autorita. | `docs/architecture/ai_context.md`, `automation/project.conf` | Každý export i release musí fail-closed ověřit source ref, organization a occasion. |
| Datový model je multi-tenantní Organization → Unit → Occasion. | architektonická dokumentace a SQL | Kontroly musejí být po původním zdroji i po novém organization mappingu. |
| Obchodní logika, RLS a významná část zápisů jsou v SQL/RPC. | `database/functions`, migrace | Hybrid se musí navázat na explicitní zapisovací hranice. |
| Existuje `external_sync_sources`, ale synchronizuje jen vybranou occasion/public vrstvu. | `database/functions/synchronization` | Nelze jej vydávat za obecné CDC nebo použít k úplnému sloučení. |
| ID jsou i v JSONB/textových payloads, např. organization defaults, form, ticket/order a transaction payloads. | SQL migrace a funkce | Nestačí přemapovat deklarované foreign keys; je nutný registr všech referencí. |
| Flutter/web build obsahuje URL a anon key; starý klient míří přímo na `*.supabase.co`. | build a release skripty | DNS nemůže přesměrovat starou Supabase doménu. Je nutná adopční brána pro klienty. |
| Některé skripty předpokládají Supabase Management API a project ref v URL/JWT/storage key. | `automation/lib/supabase_management.mjs`, `automation/verify_web_build.mjs` | Self-hosted cesta vyžaduje vlastní deployment API/SSH a nový stabilní project slug. |
| Repo obsahuje přibližně 20 Edge Function adresářů. | `supabase/functions` | Každá funkce musí být klasifikována jako read/write/side-effect a nasazena či nahrazena. |
| Supabase Storage používá minimálně `editor-files`, `public-files`, `images-temp`. | aplikace, SQL a Edge Functions | Migrují se metadata i objekty a řeší se kolize shodných object keys. |
| Image worker registry dnes rozlišuje `IMAGE_PROJECT_ID=default|a`. | image worker konfigurace | R2 buckety mohou zůstat oddělené, ale oba záznamy budou ověřovat proti jednomu Supabase endpointu. |
| DB cron/webhook kód skládá URL Edge Functions. | migrace a SQL | URL a secrets se musí změnit transakčně s cutoverem. |
| Lokální config uvádí PostgreSQL 15; skutečná produkční verze musí být ověřena na obou zdrojích. | `supabase/config.toml`, `.temp/postgres-version` | Cíl se volí podle skutečné kompatibility; upgrade major verze není součást cutoveru. |
| Mendelio má Terraform, Caddy, pinned Compose, root-only env, restore a monitoring skripty. | `<reference-infrastructure-repo>` a `platform-backup` | Převzít provozní strukturu a bezpečnostní principy, aktualizovat runtime a Festapp specifika. |

Oficiální Supabase dokumentace uvádí pro plný self-hosted stack doporučený
výchozí bod 4 CPU, 8 GB RAM a 80 GB SSD; self-hosted provozovatel si sám zajišťuje
zálohy, obnovu, monitoring a upgrady. Viz [Self-hosting](https://supabase.com/docs/guides/self-hosting),
[Docker setup](https://supabase.com/docs/guides/self-hosting/docker) a
[restore z platformy](https://supabase.com/docs/guides/self-hosting/restore-from-platform).

## 4. Cílová architektura

```text
podporované aplikace / web / Edge callers
                    |
             api.festapp.net
                    |
       Cloudflare DNS/WAF/proxy vrstva
                    |
      chráněný origin + Caddy na Hetzneru
                    |
       jeden pinned Supabase Compose stack
                    |
     PostgreSQL + Auth + Storage + Realtime
                    |
       jeden kanonický Festapp datový model
```

Během hybridu existuje navíc pouze dočasná větev:

```text
legacy klienti tenantů a
          |
  cloudový projekt a  --journalované RPC--> append-only journal
          |                                      |
  jediný write owner                   host-local forwarder
                                                 |
                               idempotentní ingest RPC cíle
                                                 |
                                   kanonický self-hosted cíl
```

`a.api.festapp.net` lze použít jen jako dočasnou kompatibilní hranici pro nově
vydané, ještě nepřepnuté kohorty `a`. Nesmí se stát druhým trvalým veřejným API.
Staré binárky s pevnou `lwfp...supabase.co` poběží přímo proti zdroji, dokud
nesplní adopční bránu; nelze je DNS trikem převést na Festapp doménu.

## 5. Závazná architektonická rozhodnutí

1. **Jeden fyzický server, jeden Supabase stack, jedna databáze, jeden Auth a jeden finální API hostname.**
2. **`default` je kanonický základ.** Jeho ID se zachovají, pokud kontrola neprokáže kolizi nebo poškození. `a` se nikdy neobnoví surovým dumpem přes kanonické tabulky.
3. **Cílové schéma vzniká z kanonických migrací repozitáře.** Zdrojová schémata se fingerprintují a rozdíly se vysvětlí před importem.
4. **Import `a` jde přes staging a mapovací registr.** Pro každou tabulku s číselným PK vznikne mapa `(source_project, source_table, source_id) → target_id`. Všechna target ID se přidělí před vložením závislých řádků.
5. **Žádný globální offset ani blanketní JSON replace.** Každé relační i nerelační místo je v reference registry s transformační a ověřovací funkcí.
6. **Nejasná kolize blokuje cutover.** Rozdílné payloady pod stejným unikátním přirozeným klíčem se neslučují automaticky.
7. **Hybrid má jediného vlastníka zápisu pro každého tenanta a každý entrypoint.** Klienti nikdy nezapisují zároveň do obou systémů.
8. **Journal je transakční součást explicitního RPC.** Projekt zakazuje trvalé aplikační triggery; před hybridem se všechny relevantní přímé DML cesty převedou na RPC a přímá write grants se odeberou.
9. **Replay je at-least-once transport s exactly-once výsledkem.** Každá změna má stabilní command ID, source transaction/order, aggregate key, payload version a checksum. Target uchovává receipt a duplicitní command neaplikuje podruhé.
10. **Replay je bez externích efektů.** Importuje durable state; neposílá e-mail, neúčtuje platbu a nevydává push. Tyto efekty provádí jen aktuální write owner.
11. **Auth signing keys, JWT secrets a všechny veřejné i privilegované klíče se rotují.** Všichni uživatelé se po přechodu znovu přihlásí.
12. **Žádné secrets ani PII mapy do Gitu.** Repo obsahuje jen schémata manifestů, transformační pravidla a test fixtures. Produkční mapy jsou v zabezpečené staging DB a šifrovaném důkazním artefaktu.
13. **PostgreSQL major se při cutoveru nemění.** Případný upgrade je následná, samostatná změna.
14. **Rollback je časově asymetrický.** Před prvním cílovým zápisem lze vrátit jednotlivou kohortu na původní owner. Po přepnutí `a` a prvním cílovém zápisu se neprovádí split-back; používá se forward repair nebo obnova celého cíle.
15. **Cloud projekty se nejdříve zmrazí, ne smažou.** Smazání je samostatně schvalovaný destruktivní krok po retenční lhůtě a důkazu nulové závislosti.

## 6. Pravidla konsolidace dat

### 6.1 Klasifikace tabulek

Před psaním importeru musí každá tabulka spadnout právě do jedné třídy:

| Třída | Zacházení |
|---|---|
| Kanonické schema/seed/config | Vzniká z repozitáře; zdrojová data se importují jen při přesné sémantické shodě nebo schváleném merge pravidle. |
| Tenant-owned business data | Import všech řádků s přemapováním ID a zachováním původního source provenance. |
| Auth identity/profile/membership | Speciální identity reconciliation níže. |
| Storage metadata/object | Hash, collision policy, copy a rewrite evidovaných references. |
| Audit/receipt/ledger | Zachovat neměnnost; duplicita se řeší podle source provenance, nikoli přepsáním. |
| Cache/generated/read model | Rebuild z kanonických dat, pokud lze prokázat úplnou reprodukovatelnost. |
| Queue/side effect | Drain/reconcile; neimportovat tak, aby efekt proběhl podruhé. |
| Legacy/obsolete | Neimportovat pouze na základě schváleného deletion ledgeru a důkazu nedosažitelnosti. |

### 6.2 Číselná ID a sekvence

- `default` ID se rezervují jako první.
- Pro `a` se pro každou tabulku předem vloží mapovací řádky a alokují cílová ID z cílové sekvence; mapování je stabilní napříč rehearsal a produkčním během.
- Import probíhá topologicky, ale všechny mapy existují před transformací FK.
- Po importu se sekvence nastaví nad skutečné maximum s definovanou rezervou.
- Validace vyžaduje úplnost map, nulové osiřelé FK a nulový odkaz na původní ID mimo pole výslovně označená jako historická provenance.

### 6.3 Auth identity

Normalizace e-mailu a provider identity musí odpovídat skutečnému Auth chování.

| Situace | Pravidlo |
|---|---|
| Stejné UUID a stejný normalizovaný e-mail | Jedna cílová identita; memberships/profil podle explicitního field policy. |
| Různé UUID a stejný ověřený e-mail | Preferovat existující UUID z `default`; všechny `a` reference přemapovat. Pokud identita není v `default`, použít předem schválenou deterministickou volbu. |
| Stejné UUID a rozdílný e-mail | Ruční blocker; nelze automaticky pokračovat. |
| Neověřený/ambiguous e-mail nebo konfliktní providers | Ruční blocker a identity decision manifest. |
| Unikátní UUID i e-mail | Zachovat, pokud neexistuje jiná kolize. |

Při sloučení dvou účtů nelze zachovat dvě odlišná hesla. Hash kanonické identity
zůstává; druhá identita dostane password-reset requirement. Nové signing keys
stejně zneplatní staré sessions. MFA, provider links, recovery tokens a email
confirmation se inventarizují odděleně; žádná položka se nesmí tiše zahodit.

### 6.4 Unikátní a přirozené klíče

- přesně shodná referenční data lze deduplikovat podle schváleného pravidla;
- shodný unikátní klíč a rozdílný payload je unresolved conflict;
- tenant-owned unikátnost se nejdřív vyhodnotí v novém tenant namespace;
- auditní UUID, receipt ID, QR/ticket symboly a idempotency keys mají samostatný collision report;
- nula unresolved conflicts je povinná cutover podmínka.

### 6.5 JSONB, text a jiné ne-FK reference

Vznikne `automation/hetzner-supabase/merge/reference-registry.json`. Každý záznam
obsahuje tabulku, sloupec/path, typ reference, cílovou mapu, transformaci,
nullability a invariant validátoru. Počáteční inventura musí zahrnout minimálně:

- organization `DEFAULT_UNIT`, `REPRESENTATIVE_OCCASION`, `DEFAULT_OCCASION`;
- occasion/form payloads;
- ticket, order, spot a product payloads;
- transaction payloads (`bank_account_id`, `movement_id`, `bank_command_id`);
- client-sync artifacts/heads a uložené URLs;
- DB cron/webhook URLs a external sync mappingy.

Importer odmítne sloupec s identifikátorovým obsahem, který není v registru ani
na explicitním allowlistu historických opaque dat.

### 6.6 Storage

- Exportovat bucket konfiguraci, metadata, ACL/RLS vazby, object key, velikost, content type, ETag a SHA-256 objektu.
- Stejný bucket/key + stejný hash se deduplikuje.
- Stejný bucket/key + jiný hash dostane nový deterministický key s tenant/source namespace; všechny evidované odkazy se přepíší přes registry rule.
- Po copy ověřit počet, součet velikostí, hash sampling a 100 % kritických ticket/editor objektů.
- Podepsané URL se nemigrují; generují se znovu.

### 6.7 Side effects a fronty

Počáteční shadow import nepřenáší executable queue položky tak, aby se znovu
provedly. Před finálním freeze se fronty drainují nebo se každá pending položka
reconciluje podle stabilního receipt/Message-ID/provider ID. Jen schválené,
dosud neprovedené položky se převedou a aktivují až po změně write ownera.

## 7. Repo artefakty, které mají vzniknout

```text
automation/hetzner-supabase/
  README.md
  terraform/
  runtime/
  deploy/
  backup/
  restore/
  monitoring/
  merge/
    README.md
    inventory.mjs
    schema-fingerprint.mjs
    export-source.mjs
    import-default.mjs
    stage-source-a.mjs
    allocate-mappings.mjs
    transform-source-a.mjs
    validate-merge.mjs
    reference-registry.json
    merge-policy.json
    manifest.schema.json
    forwarder/
    fixtures/
docs/operations/supabase-self-hosted/
  architecture.md
  provisioning.md
  backup-restore.md
  merge-runbook.md
  hybrid-runbook.md
  cutover-runbook.md
  rollback-runbook.md
  incident-runbook.md
  upgrade-runbook.md
```

Skutečné source exports, mappingy, identity decisions a secrets patří do
šifrovaného pracovního úložiště mimo Git. Každý běh vytvoří podepsaný manifest s
project ref, časem snapshotu, schema fingerprintem, počty, checksums, verzí
transformace a výsledkem validace.

## 8. Realizační vlny

Každá vlna má vlastní exit gate. Do další se nepokračuje pouze proto, že
automatizace doběhla; musí být splněny datové a provozní invarianty.

### Vlna 0 — Autoritativní inventura a rozhodovací brány

**Cíl:** odstranit neověřené předpoklady před návrhem serveru a importeru.

1. Z obou produkčních projektů získat read-only inventuru PostgreSQL verze,
   extensions, collations, DB/Storage velikosti, růstu, WAL, peak connections,
   rolí, grants, RLS, funkcí, cronů, vault, publications, Auth a Edge Functions.
2. Zmapovat každou produkční branch/config na source ref, původní organization,
   occasion, image project a odpovědnou release cestu.
3. Vytvořit write-authority matrix: mobil, web, admin, Edge Function, cron,
   webhook, bank/payment callback, email, image worker, import a ruční skript.
4. Vygenerovat FK graf, unique constraints, kandidátní embedded-ID sloupce a
   collision report pro PK/UUID/e-mail/natural-key/Storage key.
5. Klasifikovat tabulky podle §6.1 a potvrdit rebuild/vynechání.
6. Zvolit source-compatible pinned Supabase release a PostgreSQL major.
7. Zvolit VPS podle kombinované zátěže a růstu. Minimum je 4 vCPU/8 GB/80 GB,
   ale po DB, Storage, WAL, stagingu a restore workspace musí zbýt 50 % disk headroom.

**Blokátory:** neznámý zapisovatel, nevysvětlený schema drift, unresolved identity
collision, chybějící source credential nebo nemožnost spolehlivě zachytit zápisy `a`.

**Exit:** schválený inventory manifest, write matrix, collision report, sizing,
runtime pin, reference registry draft a vlastníci ručních rozhodnutí.

### Vlna 1 — Reprodukovatelná infrastruktura jednoho serveru

**Cíl:** připravit prázdný hardened host bez produkčních dat.

1. Terraform podle Mendelio principů: Hetzner server, volume, firewall, SSH keys, labels a outputs bez secrets.
2. Ubuntu LTS pin, security updates s maintenance window, NTP, SSH hardening, non-root deploy user, audit log a disk limits.
3. Firewall povolí 22 jen z admin allowlist/VPN; veřejně 80/443. Žádný Postgres, Studio, analytics ani Docker port není veřejný.
4. Root-only runtime env (`0600`), oddělený secret bootstrap a rotace; defaultní upstream hesla/keys zakáže validátor.
5. Pinned Docker/Compose a přesně jeden Compose project/network/volume namespace.
6. Caddy přijímá jen přesný chráněný origin hostname a constant-time shared origin credential; nouzový přístup jen VPN/SSH tunnel.
7. Monitoring disk/CPU/RAM/container health, cert expiry, DB connections, journal lag a backup freshness.
8. Infrastructure CI: Terraform validate, Compose render bez secrets a smoke test z čistého hostu.

**Exit:** host lze znovu vytvořit z kódu a health endpoint je dostupný pouze přes
schválenou cestu. Veřejný raw port nebo origin bez credential znamená selhání.

### Vlna 2 — Jeden pinned Supabase runtime a provozní základ

1. Vendor/pin oficiální release digesty; dokumentovat upstream commit/tag a upgrade postup.
2. Generovat JWT secret, anon/service keys, DB hesla, dashboard credentials, SMTP a encryption secrets z root-only prostředí.
3. Nastavit `https://api.festapp.net`, redirect allowlist, Site URL, SMTP a Auth providers.
4. Nastavit extensions, roles, default privileges, RLS, Realtime, Storage a Functions dle inventory.
5. Studio/analytics nezveřejňovat; provozní přístup pouze tunelem/VPN.
6. Přidat deploy s preflightem, DB advisory lockem, migrací a health checkem.
7. Nahradit Management API předpoklady explicitním self-hosted deploy/inspect kontraktem. Project slug se neodvozuje z cloud ref ani JWT.

**Exit:** prázdný cíl projde Auth, REST, RPC, Realtime, Storage a Edge Function
smoke testem; žádný default secret ani veřejný admin endpoint nezůstává.

### Vlna 3 — Zálohy, obnova a merge tooling

1. Odděleně zálohovat role, schema, data, Auth, Storage metadata/objects, Functions config a runtime manifest z konzistentního snapshotu.
2. Zálohy klientsky šifrovat, ukládat mimo VPS s versioning/retention; klíč není na serveru.
3. Definovat full + WAL/PITR podle schváleného RPO. Pokud PITR není dostupné, výslovně schválit horší RPO.
4. Implementovat resumable merge fáze, source assertions a schema fingerprint gate.
5. Přidat anonymizované fixtures pro org/PK/FK/JSON/Auth/unique/Storage kolize.
6. Obnovit do odděleného ephemeral prostředí a změřit RPO/RTO.

**Exit:** dva restore drills z různých snapshotů a merge fixtures dokazují
mapování, idempotenci, conflict blocking a nulové orphan FK.

### Vlna 4 — Expansion: kanonické schéma a journalované zápisy `a`

1. Dodat dopředně kompatibilní schema expansion do obou cloudů i cíle.
2. V `a` přidat dočasný append-only `merge_change_journal` a explicitní veřejné RPC pro každý mutating contract. Business write a journal insert jsou jedna transakce.
3. Journal nese source position, command UUID, aggregate key, operation version, checksum, actor/provenance a timestamp; citlivý payload je minimální.
4. Přesměrovat podporované `a` klienty, Functions, crony, webhooky a skripty na tato RPC; poté odebrat přímé DML grants aplikačním rolím.
5. Negativním testem dokázat, že anon/authenticated/workload identity journal neobejde; service role je minimální a auditovaná.
6. Na cíli přidat dočasný idempotentní ingest RPC a receipt table se zákazem external effects.
7. Host-local forwarder čte journal po pozici, aplikuje do cíle, potvrzuje receipt a reportuje lag/dead letter.

**Adopční brána:** telemetry za dohodnuté okno musí prokázat nulový přímý DML
bypass. Staré buildy musejí být read-only, vynuceně aktualizované nebo mimo
cutover; jinak se volí úplný freeze, nikoli nespolehlivý hybrid.

**Exit:** journal pokrývá 100 % write matrix, replay je idempotentní a cílový
replay nevytváří externí efekty.

### Vlna 5 — Rehearsal celého sloučení

1. Snapshot `default` obnovit do čistého cíle a aplikovat kanonické migrace.
2. `a` exportovat do odděleného staging namespace, ne přes canonical tabulky.
3. Vytvořit všechny ID mapy, identity decisions, organization map, conflict report a Storage map.
4. Importovat topologicky, přepsat FK i registry references, nastavit sequences a rebuildnout jen schválené caches.
5. Přenést Auth/Storage a nacvičit reset/login scénáře.
6. Spustit forwarder od snapshot position a dohnat změny vzniklé po snapshotu.
7. Otestovat každý organization mapping: login/rights, tenant scope, order/ticket/QR, finance, admin, sync, Storage, Realtime, deletion, Functions a images.
8. Porovnat counts, tenant partitions, sums, checksums, FK, uniques, business invariants a vzorky.
9. Otestovat backup a úplný restore již sloučeného cíle.
10. Druhý rehearsal provést z novějšího snapshotu; každé ruční SQL převést do automatizace.

**Exit:** nula unresolved konfliktů/orphan FK, úplné mapy, shodné invariants,
doložené trvání freeze/drain a schválený produkční manifest.

### Vlna 6 — Přesun `default` a zahájení hybridu

1. Schema/config freeze a čerstvé nezávislé zálohy obou cloudů.
2. Krátký write freeze `default` a final export se source assertion.
3. Obnovit `default` do čistého cíle, aplikovat rehearsed migrace, rotovat keys a ověřit data.
4. Přepnout gateway, Functions, crony, workery a `default` tenant configs na `api.festapp.net`; cloud `default` změnit na read-only.
5. Ověřit cílové zápisy/efekty. Odteď je návrat řešen restore/forward repair cíle, ne znovuotevřením cloudu.
6. Vytvořit snapshot `a` s journal position, provést staging, mapping a bulk import do téhož cíle.
7. Spustit forwarder od snapshot position. `a` zůstává jediným ownerem nepřepnutých tenantů; cíl je jejich shadow stav.
8. Sledovat source traffic, journal/applied head, dead letters, divergence a side-effect owner.

**Go/no-go:** pokud `default` selže před otevřením zápisů, vrátit routing na
zmrazený cloud. Pokud selže import `a`, `default` pokračuje na cíli a `a` zůstane
na svém cloudu; importer se opraví bez dual-write.

**Exit:** `default` je canonical self-hosted, `a` bulk data jsou v cíli, journal
se stabilně dohání a každá kohorta má jediného write ownera.

### Vlna 7 — Finální cutover `a`

**Předpoklady:** adopční brána splněna, journal lag pod limitem, dead-letter nula,
konflikty uzavřeny, kapacita potvrzena a on-call/rozhodovatel aktivní.

1. Vynutit maintenance/read-only pro `a`; zastavit mutující cron/webhook/worker entrypointy v runbook pořadí.
2. Zapsat final source marker a drainout journalu až po něj.
3. Ověřit `applied_position == final_source_position`, nula dead letters a nula aktivních transakcí starého ownera.
4. Finální delta validace counts/checksums po tenantovi, FK, identities, tickets/orders/finance, Storage a business invariants.
5. Přepnout tenant configs na canonical organization map a jediný `SUPABASE_URL`.
6. Přepnout Edge/cron/webhook/image registry. Oba image project IDs mohou dál vybírat své R2 buckety, ale ověřují proti jednomu Supabase.
7. Aktivovat target side effects, otevřít zápisy a provést synthetic i skutečný canary s audit/receipt kontrolou.
8. Cloud `a` ponechat read-only; reverse replication nezapínat.

**Stop:** nenulový final lag, divergence, klient mimo journal, duplicate side
effect, Auth outage nebo chybějící tenant map.

**Exit:** veškeré podporované čtení i zápisy jdou přes `api.festapp.net`; oba
cloudy jsou read-only a hybridní přenos je prázdný.

### Vlna 8 — Pozorování, contraction a odstranění legacy cest

1. Po stabilizační okno sledovat error/latency/Auth/locks/connections/WAL/disk/Storage/Realtime/Functions/journal/side effects.
2. Odstranit target ingest/receipts, source journal RPC/table, forwarder a secrets.
3. Odstranit `a.api.festapp.net`, cohort routing a dvěma projekty podmíněné větve.
4. Odstranit inter-project `external_sync_sources/maps/cache/cron`. Generický mechanismus ponechat jen pro prokázaný skutečný externí zdroj.
5. Odstranit cloud refs, Management API assumptions, staré deploy commands, JWT/storage-key názvy a secrets.
6. Produkční mapping manifest archivovat šifrovaně; runtime staging/map tables odstranit.
7. Po retention a explicitním destruktivním souhlasu odstranit cloud projekty, až po posledním šifrovaném exportu a nulovém trafficu.
8. Projít čistý backup/restore drill pouze z canonical cíle a aktualizovat runbooky.

**Exit:** jediná dosažitelná implementace je jeden self-hosted Supabase; config
scan, DNS/traffic logy a secret inventory neukazují aktivní legacy cestu.

## 9. Validace a důkazy

### Reachability

- build/release configy obsahují jen canonical endpoint;
- produkční tenant konfigurace používají novou organization map;
- Functions, crony, webhooky a workery mají jediný target;
- DNS/gateway logy dokazují nulový provoz na cloud ref a dočasný hostname;
- write grants dokazují, že jen schválené role/RPC mohou mutovat data.

### Datový stav

- `source(default) + source(a) - approved_deduplications = target` pro každou datovou třídu a tenant partition;
- 100 % ID map coverage, nula orphan FK a sequences nad maximy;
- nula unresolved identity, natural-key a Storage collision;
- reference registry nenajde starý živý identifikátor/URL;
- journal final head se rovná target applied head;
- audit/ledger/receipt invariants a součty sedí.

### Chování a provoz

- Auth login/reset/refresh, role/RLS a tenant isolation;
- Organization/Unit/Occasion CRUD a sync;
- orders, tickets, QR a finance;
- Storage, deletion, Realtime, Edge Functions a image delivery;
- side effects právě jednou, nikdy z replaye;
- backup freshness, off-host restore a schválené RPO/RTO;
- alert delivery, resource headroom a security scan veřejných portů;
- rotace klíčů a odstranění starých secretů.

## 10. Rollback a failure model

| Bod | Povolená reakce |
|---|---|
| Před cílovými zápisy `default` | Vrátit routing na zmrazený cloud a opakovat import. |
| `default` zapisuje do cíle, `a` stále cloud | `default` opravit/obnovit na cíli; `a` ponechat. Bez dual-write. |
| Import/replay `a` selže před cutoverem | Znovu spustit idempotentní import nebo obnovit čistý target backup; `a` zůstává owner. |
| Freeze/drain `a` selže před cílovými zápisy | Znovu otevřít `a` jako jediného ownera a naplánovat nový pokus. |
| Po prvním cílovém zápisu tenantů `a` | Žádný split-back; forward repair nebo obnova celého cíle. |
| Ztráta VPS | Obnovit canonical backup + WAL + Storage na novém hostu; cloudy nejsou failover. |

## 11. Deletion ledger

| Legacy prvek | Podmínka odstranění | Důkaz absence |
|---|---|---|
| oba `*.supabase.co` refs | adopce + retention | config scan, traffic nula |
| `a.api.festapp.net` | všichni tenanty canonical | DNS/gateway test |
| source journal/RPC/grants | final marker + stabilizace | schema diff, privilege test |
| target ingest/receipts | journal odstraněn + audit export | schema/reachability scan |
| forwarder + secrets | lag 0 + contraction | service/secret scan |
| staging/map runtime tables | audit manifest archivován | schema diff |
| identity conflict workspace | unresolved 0 + retention | encrypted archive manifest |
| inter-project sync rows/maps/cron/cache | canonical data ověřena | DB/cron inventory |
| staré organization IDs | tenant mapping nasazen | branch/config scan |
| Management API/project-ref logika | self-hosted deploy ověřen | `rg` + CI |
| staré JWT/API/service keys | adopce + rotace | inventory + revoke test |
| cloud Edge návody | nový runbook ověřen | docs scan |
| cloud projekty | retention + explicitní souhlas | final export + delete receipt |

## 12. Rizika a mitigace

| Riziko | Mitigace |
|---|---|
| Skrytá ID reference | registry, scanner, blocking validator, rehearsals |
| Stejný e-mail není stejná osoba | ruční identity gate pro ambiguous případy |
| Starý klient obchází journal | write grants, telemetry, minimum-version/read-only gate |
| Replay zopakuje efekt | durable-state-only ingest, receipt, single effect owner |
| Jeden server selže | off-host backup, WAL/PITR, IaC rebuild, restore drill |
| Runtime drift | pinned digest, upgrade rehearsal, explicitní ownership |
| Nedostatečná kapacita | combined sizing, 50 % disk headroom, resize runbook |
| Předčasné smazání cloudů | read-only retention, explicitní approval, final export |
| Záměna R2 project ID za Supabase source | oddělit image routing od jediné Supabase autority |

## 13. Definition of Done

- [ ] Jeden Hetzner VPS provozuje jeden pinned self-hosted Supabase stack.
- [ ] `default` i `a` jsou sloučeny do jedné DB/Auth/Storage autority.
- [ ] Všechny tenanty používají `https://api.festapp.net` a canonical organization map.
- [ ] Nula unresolved identity, ID, unique-key nebo Storage konfliktů.
- [ ] Nula orphan FK a úplný reference-registry report.
- [ ] Auth, RLS, Functions, Realtime, Storage, sync, tickets/orders a finance prošly.
- [ ] Journal, forwarder, dočasná RPC a hostname jsou odstraněny.
- [ ] Neexistuje dual-write, reverse sync ani druhý zapisovatelný backend.
- [ ] Staré refs, Management API předpoklady a keys nejsou dosažitelné.
- [ ] Backup/restore splňuje schválené RPO/RTO.
- [ ] Monitoring, incident, cutover, rollback a upgrade runbooky jsou ověřené.
- [ ] Cloudy jsou nejméně read-only; smazání má samostatný souhlas a důkaz.

## 14. Materiální předpoklady a otevřené brány

Plán předpokládá, že lze před hybridem aktualizovat nebo omezit všechny aktivní
zapisující klienty projektu `a`. Pokud nelze uzavřít přímé DML starých klientů,
bezpečný průběžný hybrid není možný bez jiné autoritativní CDC technologie;
alternativou je delší read-only maintenance/final freeze, nikoli dual-write.

Před objednáním serveru a implementací importeru je nutné potvrdit:

1. kombinované live velikosti, růst, peak connections a PostgreSQL verze;
2. aktivní klientské verze a možnost vynutit minimum version;
3. úplnou write-authority matrix;
4. rozsah Auth/MFA/provider a Storage kolizí;
5. požadované RPO, RTO a retenční dobu cloudů;
6. DNS/Cloudflare ownership a správce provozních secretů.

Tyto body nemění cílovou architekturu. Rozhodují o velikosti serveru, délce
hybridu a o tom, zda je bezpečnější journalovaný průběh, nebo krátký úplný freeze.
