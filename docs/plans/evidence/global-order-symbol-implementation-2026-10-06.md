# Veřejný symbol objednávky - lokální implementace

Datum: 2026-10-06. Checkout: `festapp-order-ticket-change-overview-20261006`, branch `fix/order-ticket-change-overview-20261006`, výchozí commit `45c512db1cfe916d2e3459155c12df76e033d743`. Implementace není commitnutá ani nasazená. Hlavní workspace s nesouvisejícími pracovními změnami nebyl upravován.

## Kontrakt a převod

- `eshop.orders.order_symbol` je uložený text, NOT NULL, globální `orders_order_symbol_key` a přesný CHECK `^([1-9][ACEFGHIJKLMNPQRUVWXY]){5}$`. Privátní SQL generátor používá pgcrypto a rejection sampling. Writer opakuje pouze insert při konfliktu tohoto constraintu, nejvýše 10krát; jiné chyby propaguje stávajícím transakčním kontraktem. Kolize/vyčerpání se logují bez zákaznických dat.
- Interní ID, FK, row identity, RPC argumenty, idempotency/hash, email intent keys, VS/RF a Fakturoid identita jsou beze změny. Žádný order-symbol fallback na ID, klientský generátor ani aplikační trigger nebyl přidán.
- Table i column INSERT/UPDATE granty API rolí jsou odebrány. Service_role má pouze UPDATE(note_hidden), nutné pro row lock v existujícím SECURITY INVOKER email produceru. Zapisovat order_symbol nemůže. Generator i backfill jsou privátní, backfill setter contract migrace odstraňuje.
- Orders, history, email history, form response, related ticket, dialogy, grid export a veřejné potvrzení používají skutečný symbol. Nová orders response bez symbolu vyvolá chybu kontraktu; starší samostatné modely snesou prázdnou hodnotu. Write serializace symbol neobsahuje. `get_orders` zachovává tenant ochranu obou link resolution větví z novější migrace.
- `orderSymbol` je dostupný ve všech order email substitucích, včetně ticket rendereru. `fullOrder` přijímá explicitní uložený symbol odděleně od zákaznických data. Metadata-only adapter v existujícím orderOverview a privátní invoker SQL read hranice doplňují staré pending/replay payloady v jejich scope; nemění obchodní snapshot ani uložený response/hash. Aktuální payload nepotřebuje další query. Adapter zůstává kvůli neprokázané konečné retention.
- Podle upřesnění uživatele se mění pouze globální defaultní šablony. Jejich původní obsah, layout a barvy zůstávají, subject dostává `{{orderSymbol}}` a body explicitní symbol nebo existující fullOrder. Tenant/unit/occasion overrides se nepřepisují ani automaticky nerozšiřují. Již připravené/odeslané zprávy, PDF a QR se neregenerují. Nové agreement PDF má order symbol v patičce a názvu souboru; dosavadní číslo smlouvy/VS a orderId request zůstávají.

## Prokázané kontroly

| Kontrola | Výsledek |
| --- | --- |
| Canonical catalog, read-only po ověření aktivace a cíle | Jediný insert writer `create_ticket_order_internal_v1`, owner postgres; facade/replay zachován. 3 287 orders, 6 979 584 bytů; žádný orders trigger. Live tabulka/sloupcové write granty doloženy, nic nebylo změněno. |
| Disposable DB baseline + forward migrace | Obnovena samostatná DB na existujícím loopback backendu. Oprávnění/owners aplikace a Auth/Storage byla obnovena; žádné produkční fixtures, žádný nový lokální Docker nebo zásah do běžícího backendu jiné práce. Cron extension je v tomto serveru vázaná na postgres DB, v kopii není scheduler. |
| `node web_client/scripts/run_db_tests.js` v plném gate | **128 passed, 0 failed**, včetně generator/ACL/tenant/default-template testů a existujících storno/payment/product regresí. |
| `test_order_symbol_database.js` | **PASS**: backfill historických stavů/neúplných dat, checkpoint/rerun, nezměněná obchodní data a timestampy; expand/contract rerun; vynucená kolize skutečného writeru a úspěch druhého pokusu; 10 pokusů a rollback bez nové objednávky/ticket/payment/email; jiný unique konflikt selže na prvním pokusu; spoof odmítnut; replay stejné ID/symbol/jeden intent; starý uložený response se pouze čte, nepřepisuje. Dvě skutečné transakce prokazatelně čekaly na stejném globálním unique indexu a druhá po konfliktu přidělila jiný symbol. |
| Flutter v plném gate | **1 136 passed**, jeden stávající skip. Cílené model/widget/command testy pokrývají order/history/ticket/form/email grid identity, read-only serializaci a potvrzení. |
| Deno v plném gate | **271 passed, 0 failed**, včetně CS/EN order identity/default/custom placeholderů, starého payloadu, původního stylu a VS/RF, deposit a Fakturoid regresí. |
| `deno check` | PASS pro send-ticket-order, emailRenderer a generate-order-agreement. |
| Cílený Dart analyzer | Žádné chyby; existující warning v orders_history_model a legacy deprecation/info zůstávají. Nově vzniklá interpolation info byla odstraněna. |
| JS v plném gate | **213 passed**; dalších **9 HTTP security testů selhalo**, protože nebyl připojen samostatný REST endpoint této disposable DB. Spuštění použilo loopback placeholder místo produkce. Cílené symbol/command retry DOM testy prošly. |
| Browser smoke | Lokální statická fixture bundluje skutečný OrderResult a CS katalog. agent-browser v izolovaném headless session; native CDP doubleclick na rozsahu symbolu vybral `7G4K9M2R6A`, jeden textový uzel, žádné viditelné interní ID. Prohlížeč byl zavřen. Toto není full-app Auth/REST E2E. |
| Automation | Povinné automation části `test_all.sh` prošly; finální canonical sada **97 passed**. |
| Worker integrace | První gate neměl lokálně instalovaný Vitest. Po npm ci existující integration runner správně **přeskočil 27 testů** pro loopback DB; skutečný externí worker/upload/auth flow nebyl proveden. |
| `git diff --check` | PASS. Bez commitu/push/deploy/email send. |

`bash automation/test_all.sh` byl skutečně spuštěn s aktivní disposable DB. Jeho exit 0 neznamená zelený plný gate: runner toleruje některá selhání a přeskočení. HTTP testy, externí worker integrace a full-app E2E zůstávají neprokázané. Není to release-ready důkaz.

## Reprodukce cíleného DB kontraktu

Použít pouze čerstvou loopback disposable DB po canonical baseline a forward migracích, nikdy živou nebo sdílenou DB:

```sh
DATABASE_URL='<disposable loopback connection>' node web_client/scripts/run_db_tests.js
DATABASE_URL='<disposable owner connection>' FESTAPP_DISPOSABLE_ORDER_DB=yes \
  node web_client/scripts/test_order_symbol_database.js
```

Script používá existující pg harness a odmítá neloopback target i chybějící explicitní disposable flag. Všechny přechodné DDL/writer fixture změny se rollbackují, souběhové vložené rows se odstraní.

## Ledger

| Cesta | Stav |
| --- | --- |
| ORDER_SYMBOL <- id, HISTORY_ORDER_SYMBOL <- orderId, Order #id, numerické order nadpisy | Odstraněno z měněných consumerů, model/widget/DOM regresní testy. |
| Public symbol v generickém write payloadu nebo fallback na ID | Nepřidáno; toJson/fromPlutoJson a command args stále používají ID. |
| Orders/history/form/ticket/email/export | Převedeno přes autoritativní projekce a modely, žádné přepsání history data. |
| SQL private read adapter pro starý replay/pending | Záměrně ponechán, owner/service-only scope; retention release owner dosud neprokázal jako konečnou. |
| Backfill setter | Jen expand období, revoke všech API rolí; contract DROP FUNCTION. |
| FK/RPC/row IDs, idempotence, queue, interní URL/log correlation | Ponecháno. |
| VS, RF, Fakturoid custom ID, ticket symbols/QR a existující číslo smlouvy | Ponecháno. Nová PDF filename/patička používá order symbol. |
| Již připravené/odeslané emails/PDF a vlastní šablony bez placeholderu | Ponecháno podle výslovného zadání. |
| Historické migrace a baseline | Nepřepsány. Přidány vlastní scoped migrace, canonical SQL a seed. |

## Release pořadí a zbývající autorita

1. Samostatně autorizovat publikaci/migraci; ověřit aktuální authoritative main a tenant target. Nikde nebyl proveden commit/push/deploy.
2. Atomicky aplikovat expand `20261006130000`. Owner generátoru je postgres, stejný jako internal writer. Jednoduchý unique index odpovídá ověřené velikosti; 5s lock timeout je fail-closed, produkční lock budget se před release musí potvrdit.
3. Pouštět owner-only `automation/order-symbol/backfill.sql` v jednotlivých committed dávkách do chráněného CSV výstupu s umask 077. Checkpoint je vrácené id -> order_symbol. SKIP LOCKED batch 0 není důkaz konce, když jiný writer drží row locks; dokončení potvrdit samostatným NULL count. Nepublikovat mapping do gitu.
4. Po nulových NULL a invariant check aplikovat contract `20261006131000`, který odmítá neúplný backfill, validuje CHECK, nastaví NOT NULL a odstraní setter. Defaulty připravuje `20261006132000`; vlastní šablony zůstávají.
5. Potom nasadit kompatibilní backend renderery a čtenáře/UI pouze do samostatně schváleného tenant scope. Dokončit samostatný REST/Auth E2E, HTTP security gate a případně povinné externí worker gates. Nové testovací emaily neposílat bez explicitní autority.
6. Prokázat staré/nové orders z více occasions, konstantní symbol při změně/stornu/platbě, správné veřejné potvrzení/default email a nezměněné VS/RF/QR. Rollback nikdy neodstraní vydané symboly ani nový NOT NULL writer.

## Navazující autorizovaný release

Uživatel následně výslovně povolil pokračování a dotažení nasazení. Scope webu je jediný tenant `prod/festapptickets`; SQL je společný globální kontrakt objednávek.

- Authoritative `origin/main` před publikací: `45c512db1cfe916d2e3459155c12df76e033d743`; tenant tip `2a04735eafd44a5e9589559487b7c7a8bfdfc256`, stejný recorded base. Bez nových upstream změn.
- Nový vlastní Supabase projekt `festapp-order-symbol-e2e-20261006`, Auth/REST/Storage, API loopback 56521, DB 56522. Plná canonical baseline a všechny forward migrace prošly včetně skutečného cron schématu; synthetic tenant fixture. Existující lokální projekty zůstaly beze změny.
- Dříve chybějících **9 HTTP security testů nyní PASS** na tomto vlastním REST endpointu.
- Skutečné lokální password Auth přihlášení a REST: objednávka i history projection/dialog RPC vrací `7G4K9M2R6A`; anonymní historie je odmítnuta, generátor/read adapter/backfill RPC nejsou dostupné anon/authenticated. PASS.
- Full Flutter aplikace v headless isolated browseru: skutečné login UI, occasion, current orders, history tab přes jeho skutečný handler; na obou odpovídajících URL se zobrazil stejný symbol. Current orders zobrazují původní VS `123456`. Physical reload current prošel. Fixture se doplnila o payment_info, protože existující current grid vyžaduje jeho model. Žádná produktová změna kvůli fixture.
- Externí OneSignal hranice je stub/abort dle E2E runbooku; Google OAuth, externí worker uploady a odeslání e-mailu nejsou součástí této ověřené změny. Původních 27 worker integračních skipů tím nevydáváme za pass.
- Live read-only preflight: hostname/runtime DB/current_database/org3 souhlasí, 3287 orders / 6979584 bytes, bez aplikačních triggerů a kolizí migračních verzí. Vybraný fail-closed lock budget je 5s; skutečné časy aplikace budou zaznamenány při release.

### Produkční backend - provedeno

- Shared implementation commit `0a5274c5ab8105607ac4a05ce83efd940e188f00` je na authoritative main. Push využil existující administrátorskou výjimku main protection; remote oznámil běžný požadavek PR. Tenant production branch není chráněna. Další změny main mají projít běžným PR postupem.
- Pouze `prod/festapptickets`: tenant release commit `cbd69bb725477da5403e0f87aecf72e407803b85`, verze `0.20.123+607`, recorded base main výše. Deterministic overlay drift PASS. Ostatní production větve se neměnily.
- Chráněná vzdálená evidence: `/var/lib/festapp-rehearsal-evidence/order-symbol-20261006T144200Z`, mode 0700, schema backup a objednávky/historie/šablony backup, SHA256, canonical migration source/transaction digests, dávkové ID-symbol mapy, fingerprints před/po. Žádná zákaznická data nejsou v git.
- Expand 150 ms, contract 110 ms, global defaults 127 ms (wall time psql/docker, nikoliv přesná doba zámku). Vše s 5s lock_timeout a atomickým migration ledger zápisem.
- **3287 orders = 3287 non-null symbols = 3287 unique symbols; 0 invalid formats.** Oba constraints validated, NOT NULL nastavený, backfill setter odstraněný. Všechny tři verze potvrzené v migration ledgeru.
- Fingerprints celé objednávky kromě nového symbolu před/po jsou byte-identické; timestamps, states, prices, payment references a data zůstaly stejné. Fingerprints scoped/custom templates jsou také identické.
- Symbol UPDATE práva anon/authenticated/service_role: false/false/false.
- Reviewed clean synchronized main Function bundle nasazený canonical installerem, previous tree zachovaný, runtime restartovaný. Evidence `/var/lib/festapp-rehearsal-evidence/production-function-bundle-20261006T144350Z/result.json`. File digests `_shared/orderOverview.ts` a `send-ticket-order/index.ts` uvnitř běžícího containeru souhlasí s authoritative main.
- Live CORS OPTIONS 200. Invalid-payload smoke send-ticket-order 400, send-email 400, unauthorized process-email-queue 401; bez tvorby objednávky nebo enqueue/send. Agreement endpoint odmítl prázdný payload existující chybou `Order ID is missing from the request` (500 dle předchozího error kontraktu); jeho imports/handler běží. Tento smoke není generování PDF.
- Lokální direct build odmítl chybějící private `FESTAPP_RELEASE_MANIFEST`; žádný manifest nebyl vyroben ani gate obejit. Dispatch zavedeného Deploy workflow pro jediný tenant používá schválený private secret. [Release workflow](https://github.com/festappnet/festapp/actions/runs/37481411159).
- Vlastní headless browser, Flutter process a Supabase projekt jsou ukončené; dočasné lokální soubory s klíči smazané.

Uživatel následně převzal ruční závěrečný live smoke po nasazení. Agent proto nespouští další kontrolu živého webu či produkční browser E2E; čeká pouze na výsledek již běžícího release workflow. Automatické kroky existujícího workflow tím nejsou změněné.

### Release dokončen

Deploy workflow `37481411159` dokončen s conclusion **success**, včetně canonical build/upload a vestavěných release kroků. `prod/festapptickets` / `vstupenky.online`, verze `0.20.123+607`, commit `cbd69bb725477da5403e0f87aecf72e407803b85`. Ruční závěrečnou kontrolu převzal uživatel, žádné další live UI testy agent neprovedl. Backend, tři ledgerované migrace a globální backfill jsou dokončené. Tento navazující provozní záznam zůstává lokálním doplněním evidence k již publikovanému implementation commitu; produktový kód nemá nepublikované změny.
