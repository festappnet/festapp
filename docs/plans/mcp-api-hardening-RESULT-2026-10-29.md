# MCP/API hardening - lokální výsledek 2026-10-29

Implementace všech čtyř vln je připravena v pracovním stromu nad `2b69bc6be`.
Úplná lokální akceptace je uzavřena: všechny povinné gate prošly bez skipped testů.
Původní dva blokery byly odstraněny na následné výslovné zadání uživatele.
Tento implementační receipt vznikl před následným pokynem uživatele k začlenění
a publikaci do main. Produkční SQL, deploy, proxy reload ani marketplace zápis neproběhl.

## Změněný kontrakt

- Jediný in-memory limiter drží pevná 60s okna, maximálně 20 000 identit,
  nevyhazuje aktivní buckety a vrací celočíselné Retry-After. Zachovává limity
  IP 240, grant 60 a flow/session 5, souběh i token queue. Make zachovává JSON chybu.
- Canonical Host/loopback/proto hranice předchází jediné validované a normalizované
  IP přepsané Caddy. Health má jen vymezenou výjimku. Broker nemá secret bypass;
  Edge zachovává 429 a bounded Retry-After bez automatického opakování/mintování.
- Samostatný SQLite kernel lock chrání hosted root i lokální profile. Soubory
  se nikdy nemažou. Hosted SessionOwner instance sdílejí bounded frontu bindingu;
  timeout čekající akce neodemyká držitele. Legacy adresáře vyvolají konflikt.
- `get_operator_order_summaries_v1` vrací přímo bezpečný SQL DTO a filtruje exact
  symbol před LIMIT. Sdílený private fact owner zásobuje full i summary snapshot;
  full admin signatury, peníze, mutace, scope checks a receipty zůstaly zachovány.
  Nová forward migrace je `20261029180000_operator_order_summaries.sql`.
- Make i libovolný `order-summary` MCP klient používají výhradně nový RPC a strict
  summary validaci. Chybějící RPC, chybný DTO, auth chyba ani timeout nevedou na full RPC.

## Odstraněné cesty

Odstraněny inline persistentní Rate reads/writes, canonical socket-IP fallback,
runtime mkdir/rmdir locking, full-to-summary mapper a čtyřstránkové kontaktní
hledání. Scoped rg nenalezl zbývající producenty těchto cest. Staré Rate záznamy
přirozeně expirují. Administrátorský full RPC je záměrně aktivní.
Historické migrace ani foundation bytes se neměnily. Existující shutdown již
čeká na listener a zavírá storage po drainu; potřebná změna je v idempotentním
storage.close, proto main.mjs nebyl zbytečně přepsán.

## Provedené ověření

| Gate | Výsledek |
| --- | --- |
| Připnutý Node 24.20.0 image, cílené Node soubory plánu | PASS 69/69, skipped 0; 25 ostatních + 44 remote testů |
| Skutečná disposable PostgreSQL, oba order soubory, také v image | PASS 2/2, skipped 0 |
| Deno handler/management | PASS 12/12 |
| Generátor source contract --check | PASS |
| Úplný server_security_migrations | PASS 7/7, skipped 0 |
| Úplný canonical_mutation_source_parity_test.sql | PASS v čisté canonical fixture, také v připnutém Node 24 image |
| Catalog parity čtyř nových/změněných SQL ownerů | PASS 4/4; následně prošel i úplný parity gate |
| Doplněné definer ACL proti čisté DB | PASS 112/112 signatur, všechny 3 role |
| Produkční Dockerfile build a izolovaný image/proxy smoke | PASS |
| git diff --check | PASS |

První DB ověření běželo přes `openDisposableDatabase` nad marker-ověřeným
`festapp-authz-20261020`, loopback 61022. Konečná akceptace použila novou samostatnou
`festapp-mcp-hardening-20261029`, loopback 61032, vybudovanou od nuly celým
kanonickým baseline/forward migračním řetězcem až po novou summary migraci.
V obou případech cron off a paused email workers bez worker URL. Testovací změny
DDL i fixtures byly v rollback transakcích; samostatný bootstrap nainstaloval
celý schema cut trvale pouze do nové disposable DB. Ta byla po ověření zastavena
s uchováním lokálních dat pro opakování. Původní DB nebyla resetována ani přepisována. Raw RPC assertions
před Node validací kontrolují absenci PII/revision, ACL, přesná decimal string
částky, distinct ticket count s vícenásobnými products a storno ticketem,
keyset, detail, neznámé ID, cizí kontext, přesunutí akce a odvolané role.
Exact symbol je nalezen za 210 kontaktními shodami; unikátní constraint je ověřen.

Runtime smoke skutečně spustil běžný image jako uid 1000, ověřil druhého vlastníka,
SIGKILL/restart na stejném volume, kompletní Caddy konfiguraci včetně globálního
trusted proxy bloku, přepis falešných hlaviček, 241. request = 429 a Compose
health probe před i po vyčerpání kvóty. Bez zveřejněných portů či externích
providerů; disposable kontejnery a volume byly odstraněny.

### Příkazy a runtime

Z kořene repozitáře:

```sh
bash automation/authorization/prepare-local.sh
python3 automation/generate_canonical_source_contract.py --check
deno test supabase/functions/mcp-session-exchange/handler_test.ts supabase/functions/mcp-session-exchange/management_test.ts
docker build -f tools/festapp/Dockerfile.remote -t festapp-mcp-hardening-local .
python3 tools/festapp/test/runtime-smoke.py
```

Node testy používají `pnpm exec node --test --test-concurrency=1` nad přesnými
osmi soubory z plánu. Přímo na workstation použita `/opt/homebrew/opt/node@24/bin`
v PATH. Poté stejná sada v image odvozeném od nezměněného produkčního image:

```dockerfile
FROM denoland/deno:2.9.0 AS deno
FROM festapp-mcp-hardening-local
USER root
RUN NODE_ENV=development pnpm --dir tools/festapp install --frozen-lockfile --prod=false --ignore-scripts
COPY --from=deno /usr/bin/deno /usr/local/bin/deno
COPY supabase/functions ./supabase/functions
COPY tools/festapp/test/canonical_preview.ts ./tools/festapp/test/canonical_preview.ts
RUN deno cache --no-lock --node-modules-dir=none tools/festapp/test/canonical_preview.ts
```

Ověřený lokální produkční image: `sha256:4cfe0c512c73ef9678339d439b61ab948810b0b9c047c7a5dfa5054ff370cab7`.
Test-only image: `sha256:8a91d18632867a8624114fb8c54b2998b79eb70a4c9597be02f796f2670bca11`.

Test-only image `festapp-mcp-hardening-tests` běžel s `--network none`,
`NODE_OPTIONS=--max-old-space-size=192`, `DENO_V8_FLAGS=--max-old-space-size=128`.
Read-only mounty dodaly `tools/festapp/test`, `tools/festapp/Dockerfile.remote`,
`automation`, `packages`, `supabase` pod stejné `/app` cesty. Monolitická sada byla
opravdu spuštěna, ale Colima se sdílenými 3.814 GiB zabíjela remote proces
(SIGKILL v TAP). Proto konečná acceptance spustila 25 testů ostatních souborů
společně a všech 44 remote názvů přes přesné `--test-name-pattern` ve skupinách
po nejvýše šesti. Součet je 69 skutečně provedených testů, žádný skip.

DB testy v image přidaly mounty `database`, `web_client`, `--network host`
(pouze pro Docker loopback port disposable DB) a obě proměnné
`FESTAPP_AUTHORIZATION_DATABASE_URL` a `FESTAPP_MCP_TEST_DATABASE_URL` na
`postgresql://supabase_admin:postgres@127.0.0.1:61032/postgres` pro konečnou čistou DB:

```sh
pnpm exec node --test --test-concurrency=1 test/make-orders-postgres.test.mjs test/orders-postgres.test.mjs
pnpm exec node --test --test-concurrency=1 ../../automation/tests/server_security_migrations.test.mjs
```

Druhý příkaz výše byl spuštěn z tools/festapp na workstation s Node 24.
Úplný parity gate má nyní verzovaný harness `tools/festapp/test/run-source-parity.mjs`.
Nic do schématu před kontrolou nepřihrává; porovnává skutečně nainstalovaný celý
schema cut a rollbackuje jen testovací assertions. Z tools/festapp, se stejnými
dvěma DB proměnnými jako výše:

```sh
pnpm exec node test/run-source-parity.mjs
```

### Odstranění původních blockerů

- Doplněno 112 explicitních současných header deklarací a 104 chybějících ACL
  entries, nikoli grandfather výjimky. Doplněny také dvě skutečné source cesty
  ke shodným hlavičkám (`center_policy.sql`, `blueprint_authoring.sql`).
- Deklarace zachovávají současné REVOKE/GRANT a zděděné historické default grants.
  U `get_waitlist_offer_proposal(bigint)` se zachovává existující anon EXECUTE;
  u čtyřparametrového game settings wrapperu a swap_spot_tickets se zachovává
  existující service_role EXECUTE. SQL oprávnění ani OAuth scopes se neměnily.
  Audit proti čerstvé DB porovnal všech 112 signatur pro anon/authenticated/service_role
  a nenalezl žádnou chybějící funkci ani rozdíl v ACL.
- Stará fixture měla navzdory ledgeru končícímu `20261023234000` již některé
  novější tabulky. Pokus o podporovaný upgrade proto selhal na existující
  `notification_center_activation`. Místo jejího přepisování vznikl samostatný
  projekt a úzce marker/port/URL/fence ověřovaná větev disposable guardu.

Čistý bootstrap a fence z kořene repozitáře:

```sh
FESTAPP_LOCAL_DB_WORKDIR="$PWD/.codex-artifacts/mcp-hardening/db" \
FESTAPP_LOCAL_DB_PROJECT_ID=festapp-mcp-hardening-20261029 \
FESTAPP_LOCAL_DB_PORT=61032 bash automation/bootstrap_local_db.sh
```

Workdir obsahuje Supabase config s project_id `festapp-mcp-hardening-20261029`,
major_version 15, db.port 61032 a shadow_port 61030. Před testy marker-ověřená
transakce nastavila `email_capacity.paused=true, worker_url=NULL`; cron byl
vypnutý od samotného bootstrapu. Konečný úplný parity gate i oba DB testy běžely
v připnutém Node 24 image. Následně:

```sh
supabase stop --project-id festapp-mcp-hardening-20261029
```

Zbývající lokální acceptance blokery: žádné. Runtime důkazy 69 Node testů,
12 Edge testů a Caddy/image/restart smoke jsou zachovány z předchozího běhu,
protože runtime zdroje a image zůstaly beze změny. Znovu byly provedeny všechny
kontroly ovlivněné doplněním kontraktů a novou fixture.

## Přesné neprovedené provozní kroky

Neproběhlo schválení/volba rollout tenantu, publish immutable image,
aplikace forward SQL na produkci, produkční Caddy staging/reload, stop starého
sidecaru a prokázané odstranění pouze starých prázdných legacy adresářů,
produkční spuštění nového sidecaru, deploy změněné Edge funkce, živé OAuth/Make/MCP
readback, přepnutí instalovaného lokálního CLI ani marketplace či další tenanty.
Jde o kroky mimo autorizovaný lokální implementační rozsah, nikoli o zbývající
implementační dluh. Případný samostatný rollout musí dodržet pořadí plánu.

## Začlenění do main

Následný příkaz uživatele autorizoval commit a publikaci do `main`. Před publikací
byl fetchnut `origin/main`; lokální i vzdálený základ byl `74a44e7a2`.
Tři mezilehlé commity od implementačního základu měnily Flutter UI a jeho testy;
žádná změna se nepřekrývala s MCP/SQL/Edge zdroji. Passing důkazy pro nezměněné
vstupy zůstaly zachovány. Rozpracované soubory nápovědy nejsou součástí změny.

Před commitem proběhl také povinný `automation/apply_config.sh` v odděleném
checkoutu stejného main základu, aby nepřepsal rozpracovanou nápovědu. Konfigurační
hodnoty zůstaly shodné; vznikly jen konce řádků ve FVM/VS Code souborech a již
existující regenerace privacy stránky. Tyto nesouvisející výstupy nejsou součástí
MCP commitu. `git diff --cached --check` kontroluje i nově přidané dokumenty.
