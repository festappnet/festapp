# Pořadí objednávek a aktivní filtry - implementační evidence

Datum: 2026-10-06. Vlny A-D dokončené lokálně. Checkout `festapp-order-symbol-main-20261006`, branch `main`, základ `0a5274c5ab8105607ac4a05ce83efd940e188f00`; počáteční fetch origin/main odpovídal tomuto základu. Bez commitu, push, produkční migrace nebo deploye. Nesouvisející existující evidence globálního symbolu zůstala zachována.

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
| Expand 20261006140000 + private backfill_order_sequences | Instalováno a otestováno v disposable DB; API execute revoked. | Pending, neaplikováno. |
| automation/order-sequence/residual-function.sql + residual.sql | Owner-only batch; NULL append při souběžném canonical writeru prokázán. Existující pořadí se nemění. | Pouze po doběhu před-expand writer transactions, pokud zůstane NULL; owner access. |
| Contract 20261006141000 | NULL guard/positive/NOT NULL ověřeno; helper DROP; absence + API denial prokázané. | Pending po kontrole NULL=0. |
| Operational scripts | Zachovány jako repeatable rollout artefakty, nejsou runtime RPC. | Neinstalovat residual helper znovu po contract. |

## Pending rollout

Samostatná navazující autorita je nutná pro commit/push/deploy a produkční migrace. Před publikací nový fetch a kontrola authoritative main/protection; výchozí tenant scope pouze prod/festapptickets. Před migrací podle plánu ověřit canonical backend/tenant, writers/grants, NULL occasion a objem, chráněnou zálohu a mapping, lock budget a migration ledger. Expand -> doběh starých transactions -> případný owner residual -> NULL=0 -> contract -> nové UI. Žádné production load fixtures. Lokální ověření tento provozní krok nenahrazuje.

SHA-256 manifest changed implementation sources/migrations/test fixtures: [order-sequence-active-filters-implementation-2026-10-06.sha256](order-sequence-active-filters-implementation-2026-10-06.sha256). Manifest nezahrnuje nesouvisející existující dokumentaci.

## Následné upřesnění mini copy ikony

Uživatel dodal screenshoty Supabase: textové tlačítko nahrazeno samotnou 18 px copy ikonou. Clipboard success ji přepne na zelenou fajfku, popover zůstane otevřený; tooltip potvrdí zkopírování. Při opětovném otevření opět copy ikona. Po této lokální UI úpravě proběhl jeden focused batch `fvm flutter test test/components/eshop/order_grid_filters_test.dart`: 5 pass, včetně přesného clipboard payloadu, zachování popoveru a resetu při reopen. Log `/tmp/order-sequence-icon-copy-test.log`. Předchozí full gate a browser evidence platí pro předchozí podobu copy nabídky; full gate nebyl po této malé UI změně opakován. `git diff --check` prošel. Bez publikace nebo nasazení.
