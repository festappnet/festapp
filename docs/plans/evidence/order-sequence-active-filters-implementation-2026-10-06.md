# Pořadí objednávek a aktivní filtry - implementační evidence

Datum: 2026-10-06. Vlny A-D dokončené; po následném schválení uživatele backend i web nasazené pro festapptickets. Níže je zachována historie lokálního ověření a následného rolloutu. Checkout `festapp-order-symbol-main-20261006`, branch `main`, základ `0a5274c5ab8105607ac4a05ce83efd940e188f00`; počáteční fetch origin/main odpovídal tomuto základu. Bez commitu, push, produkční migrace nebo deploye. Nesouvisející existující evidence globálního symbolu zůstala zachována.

## Hotové chování

- Persisted readonly `order_sequence`: per occasion MAX všech existujících objednávek včetně storno + 1, přidělení jednou před retry symbolu. Po úplném odstranění nejvyšší objednávky lze číslo znovu použít. Per-occasion transaction advisory lock před samostatným MAX, named UNIQUE, positive CHECK a NOT NULL. Bez triggeru/defaultu, klientského MAX nebo high-watermark counteru.
- Expand doplňuje historické NULL deterministicky podle created_at/id a aktivuje writer/readers atomicky. Residual append zachovává vydané hodnoty; contract ověřuje NULL a odstraňuje helper. Canonical source i nové migrace obsahují stejné definice. API nemůže alokovat ani nastavit pořadí.
- Objednávky, vstupenky a historie zobrazují stejné parent číslo, numericky řaditelné. Fresh canonical reads odmítají chybějící/invalidní metadata; write DTO nové číslo neposílá. Uložené history snapshots se nepřepisují.
- Samostatné výchozí vypnuté checkboxy objednávek/vstupenek kombinují native column filters, přesný cached count a raw ticket/parent state. Přepnutí zachovává drafts, řazení a refresh; skrytý výběr se odznačí, hromadné akce vybírají jen viditelné řádky. Export používá tutéž filtrovanou množinu.
- Sloupce pořadí mají 90 px; symbol se měří skutečným fontem a text scale (minimum 120 px, v lokálním app běhu 132 px). Compact header zachovává native menu/filters/sort bez původního 160 px interactive-help minima. Na žádost uživatele kliknutí na symbol otevře kompaktní nabídku plného symbolu a malou ikonku kopírování; po úspěšném kopírování se v otevřeném popoveru změní na zelenou fajfku s tooltipem Zkopírováno do schránky. Bez textového tlačítka a bez toastu; sdílené také historií.
- ID/FK, veřejné symboly, bank/payment reference, QR a email cesty nejsou nahrazované. Migration harness porovnává ostatní order fields i uložené history snapshots před/po.

## Skutečně provedené ověření

Vlastní disposable PostgreSQL 15/Supabase project `festapp-sequence-local-20261006`, pouze loopback API 56521/DB 56522. Baseline, všechny migrace a seed prošly. Změny fixture queue a fixtures byly pouze v tomto projektu.

| Kontrola | Výsledek |
| --- | --- |
| `automation/test_all.sh` před následnou ikonovou úpravou | Exit 0; JS 222 pass, DB 129 pass, Flutter 1141 pass + 1 skip, Deno 271 pass; automation Node sady 8/5/97 pass a shell checks pass. |
| Dodatečný skutečný Auth SDK test | Původně skipped google_session_sdk_test doplněn local Auth recovery/refresh fixture: 1 pass; původní skip v plném gate se tím zpětně nepřepisuje. |
| Order sequence real clients | 100 canonical creation commands / 16 souběžných clients: 325.9 commands/s, p50 33.1 ms, p95 118.2 ms. Kontrolní množina 105 orders = 105 unikátních sequences = 105 tickets/payments/intents. |
| Concurrency / migration harness | PASS: historic ties/storno, rerun, zachované fields/snapshots, residual čekající za writerem, contract odmítající NULL, replay, spoofing, commit/rollback barrier podle pg_stat_activity, nezávislé scopes, forced symbol collision/retry exhaustion a atomic rollback, reuse nejvyššího čísla; index-only MAX na 10000-row occasion. |
| Local HTTP/Auth | PASS: obě get_orders projections, history metadata, přihlášení k vlastnímu backendu; allocator a retired residual nejsou anonymous RPC. |
| Targeted widget batch | 5 focused tests pass: native filters, draft preservation, count/cache/zero, visible selection/actions/export/sort/reload/dispose, ticket/parent storno, exact Clipboard payload, font scaling 1/1.3. |
| Focused nové UI files analyze | No issues. Analyzer širších existujících souborů obsahuje baseline diagnostics; není deklarován jako clean. |
| Real isolated Flutter web UI | Orders 3 -> 2, tickets 6 -> 3; partial/parent storno, stejné pořadí, native search + checkbox count 0, odznačení hidden rows a disabled actions; tab return zachová samostatné flags, page reload výchozí off, druhá prázdná occasion count 0. Plný symbol a copy nabídka otevřena a akce aktivována. |
| Real UI CSV | Kliknutí na skutečný export button, zachycený CSV Blob na download boundary: header + 3 viditelné tickets; oba storno typy vyřazené. |

Skips a hranice: image-worker suite 27 skipped (guard nepouští tento local DB režim); PyYAML nebyl dostupný, deploy workflow kontroloval strukturální fallback. OneSignal v full_app_e2e je explicitně mocked. Clipboard readback v headless browseru blokovalo permission; přesná hodnota je ověřena platform-channel widget testem. Native download nebyl prohlášen za pass: skutečný export byl zachycen mockem Blob/anchor boundary. Žádné external OAuth, produkční push nebo živé odeslání emailu ověřováno nebylo.

První full gate měl 1 SQL failure: předchozí committed load fixtures naplnily email queue a změnily očekávání client_sync_v1_runtime_test. Pouze vlastní fixture queue byla stornována; targeted retest prošel a závěrečný celý gate měl všech 129 SQL pass. Tento failure neskrývá tolerovaný exit.

Lokální logy: `/tmp/order-sequence-complete-full-gate.log`, `/tmp/order-sequence-load-final.log`, `/tmp/order-sequence-http.log`, `/tmp/order-sequence-sdk-check.log`, `/tmp/order-sequence-copy-test.log`, `/tmp/order-sequence-ui-analyze-final.log`. CSV `/tmp/order-sequence-tickets.csv`, screenshot popover `/tmp/order-sequence-copy-popover.png`. Tyto temp artefakty nejsou release artefakty; trvalý přehled výsledků je tento dokument.

## Dočasný residual helper ledger

| Artefakt / krok | Lokální stav | Produkční stav |
| --- | --- | --- |
| Expand 20261006140000 + private backfill_order_sequences | Instalováno a otestováno v disposable DB; API execute revoked. | Aplikováno 2026-10-06, atomicky s ledger zápisem. |
| automation/order-sequence/residual-function.sql + residual.sql | Owner-only batch; NULL append při souběžném canonical writeru prokázán. Existující pořadí se nemění. | 0 pre-expand transactions a 0 NULL; residual batch nebyl potřeba. |
| Contract 20261006141000 | NULL guard/positive/NOT NULL ověřeno; helper DROP; absence + API denial prokázané. | Aplikováno po NULL=0; helper odstraněn, absence ověřena. |
| Operational scripts | Zachovány jako repeatable rollout artefakty, nejsou runtime RPC. | Neinstalovat residual helper znovu po contract. |

## Pending rollout

Samostatná navazující autorita je nutná pro commit/push/deploy a produkční migrace. Před publikací nový fetch a kontrola authoritative main/protection; výchozí tenant scope pouze prod/festapptickets. Před migrací podle plánu ověřit canonical backend/tenant, writers/grants, NULL occasion a objem, chráněnou zálohu a mapping, lock budget a migration ledger. Expand -> doběh starých transactions -> případný owner residual -> NULL=0 -> contract -> nové UI. Žádné production load fixtures. Lokální ověření tento provozní krok nenahrazuje.

SHA-256 manifest changed implementation sources/migrations/test fixtures: [order-sequence-active-filters-implementation-2026-10-06.sha256](order-sequence-active-filters-implementation-2026-10-06.sha256). Manifest nezahrnuje nesouvisející existující dokumentaci.

## Následné upřesnění mini copy ikony

Uživatel dodal screenshoty Supabase: textové tlačítko nahrazeno samotnou 18 px copy ikonou. Clipboard success ji přepne na zelenou fajfku, popover zůstane otevřený; tooltip potvrdí zkopírování. Při opětovném otevření opět copy ikona. Po této lokální UI úpravě proběhl jeden focused batch `fvm flutter test test/components/eshop/order_grid_filters_test.dart`: 5 pass, včetně přesného clipboard payloadu, zachování popoveru a resetu při reopen. Log `/tmp/order-sequence-icon-copy-test.log`. Předchozí full gate a browser evidence platí pro předchozí podobu copy nabídky; full gate nebyl po této malé UI změně opakován. `git diff --check` prošel. Bez publikace nebo nasazení.

## Autorizované nasazení - readiness 2026-10-06

Uživatel následně autorizoval nasazení. Scope pouze `prod/festapptickets` / `vstupenky.online`. Main posunul commit `2455327c96fb1b24cc61059ede63ca06eb3f532c` (oprava mazání email records); feature branch byla rebased na tento commit. Overlap v order_delete_email_cleanup_test zachovává nové upstream assertions a přidává pouze explicitní sequence fixture hodnoty. Source manifest byl aktualizován po rebase.

Na novém základu proběhl finální celý `automation/test_all.sh`, exit 0, ve znovu vytvořeném vlastním disposable Supabase projektu: JS 222 pass, SQL 129 pass, Flutter 1141 pass + 1 skip, Deno 271 pass, automation pass. Image-worker 27 skipped a PyYAML structural fallback zůstávají explicitními omezeními. Log `/tmp/order-sequence-release-full-gate.log`. Tentokrát gate zahrnuje i finální mini copy ikonu.

Read-only produkční preflight přes festapp-backend-access: hostname a current_database odpovídají target assertions; tenant activation je festapptickets/generation 1/canonical, config organization 3 a DB organization 3 existuje. Celkem 3287 orders, 0 NULL occasion, 78 occasions. Migration ledger již obsahuje email deletion 20261006170000; sequence expand/contract 20261006140000/20261006141000 zatím neobsahuje. Do produkce nebylo zapisováno a nebyly použity produkční test fixtures.

Publikace je přes PR: GitHub main protection vyžaduje 1 approving review a repository agent rules požadují PR při required reviews. Auto-merge není v repository povolené. Produkční migrace musí použít přesný ověřený merged main source, chráněnou vzdálenou zálohu a atomický ledger zápis; release overlay musí obsahovat nový merged main SHA a projít main-owned drift checkerem. Tyto kroky čekají na schválení PR. Uživatelovu autorizaci nasazení není nutné vyžadovat znovu po splnění tohoto gate.

## Produkční rollout po výslovném schválení uživatele

Uživatel výslovně schválil sloučení a nasazení navzdory předchozímu GitHub review gate. PR #323 byl admin merge sloučen 2026-10-06T16:10:11Z; authoritative main `1e3b46ed7319773356314f623d0a24b1abb4fc03`. Nejedná se o zaznamenané GitHub approving review.

Pouze tenant `festapptickets`: release commit `cad7340dff5630cb5108b78433ad426a14c6e22b`, verze `0.20.124+608`, prod/festapptickets forward od `cbd69bb725477da5403e0f87aecf72e407803b85`. Overlay je fresh canonical main + explicitní povolené tenant source paths a regenerované leaves; metadata baseMainSha je merged main. Main-owned drift checker prošel. Před push origin/main stále odpovídal ověřenému main a origin/prod/festapptickets původnímu tenant tipu. Jiná tenant větev nebyla měněná ani sestavovaná.

Backend: expand 20261006140000 a contract 20261006141000 aplikované na ověřený canonical runtime DB, každá s ledger insert a PostgREST notify ve stejné transakci. 5s lock_timeout. Chráněná serverová evidence `/var/lib/festapp-rehearsal-evidence/order-sequence-20261006T161331Z`, directory 0700: schema a orders/history/payment data backup, source transaction files/digests, id/occasion/sequence mapping a výsledky. Zákaznická data zůstávají pouze v této chráněné vzdálené evidenci.

Expand navíc porovnal ostatní order fields před/po pod stejným table lockem; případná změna by rollbackovala migration i ledger. Před contract: 0 zbývajících pre-expand transactions, 0 NULL sequences, residual batch nebyl potřeba. Po contract: 3287 orders = 3287 non-null = 3287 unique (occasion, sequence), 0 nekladných hodnot; UNIQUE/CHECK validated, NOT NULL true; residual helper absent; anon/authenticated/service_role nemají allocator EXECUTE. Source SHA-256 uložený v produkčním ledgeru odpovídá přesnému merged main source: expand `74dcbccad175cc518a744b1cf23ecc1d6b1e3aade45837bfb55e3e7ed7f54418`, contract `33c685ab444a1c3e539dd766b47f159ef86aedb002b74c44dc309d233ffb89b2`. Canonical writer/history/get_orders(text,text,jsonb) projekce obsahují order_sequence. Historický overload get_orders(text) není canonical runtime consumer a nebyl touto změnou upraven.

Web release je explicitně spuštěný schváleným Deploy workflow #37494156077 pro přesný tenant release SHA. Lokální direct build správně skončil na chybějícím private FESTAPP_RELEASE_MANIFEST; nebyla vytvořena náhradní evidence. GitHub workflow používá stávající tenant release manifest secret. Stav webového vydání bude doplněn po výsledku workflow a veřejném smoke.

### Finální stav webového vydání

[Deploy workflow 37494156077](https://github.com/festappnet/festapp/actions/runs/37494156077) dokončen s conclusion **success** pro commit `cad7340dff5630cb5108b78433ad426a14c6e22b`. Tenant-drift, legal-contract, detect a cloudflare jobs success; neaktivní podmíněný job `skipped` očekávaně skipped. Deployment URL `https://ba231dd4.vstupenkyonline.pages.dev`. Produkční probe 2026-10-06T16:21:50Z: `verify_web_deployment: ok (0.20.124+608, 3 consecutive probes)`.

Dodatečný veřejný Node HTTP smoke na `https://vstupenky.online`: version manifest `0.20.124+608`, festapptickets canonical generation 1 activation, admin shell HTTP 200 na canonical cloudflare-pages workeru a vazba na manifest-selected immutable main bundle. PASS; `/tmp/order-sequence-public-smoke.json`. První dodatečný Python urllib probe dostal HTTP 403; nebyl započten jako pass. Node fetch, používaný také canonical verifierem, prošel. Produkční přihlášení ani zákaznické mutace/fixtures nebyly prováděny.

Rollout je dokončen: produkční backend obě migrace a retired residual helper, main merged, pouze prod/festapptickets publikováno a web live. Neproběhl Android/iOS store release ani build jiné tenant varianty. Log workflow `/tmp/order-sequence-release-actual-workflow.log`. Chráněné backupy zůstávají na backendu; lokální testovací backend/browser/server jsou vypnuté.
