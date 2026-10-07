# Blueprint a úpravy pořadí objednávek - oprava 2026-10-06

Scope: pokračování autorizovaného nasazení order-sequence pro prod/festapptickets / vstupenky.online. Výchozí main 1e3b46ed7319773356314f623d0a24b1abb4fc03, tenant cad7340dff5630cb5108b78433ad426a14c6e22b (0.20.124+608). Ostatní tenant builds/releases nejsou ve scope.

## Příčina a oprava

Blueprint editor načítá vlastní get_blueprint_for_edit(text), ale jeho explicitní orders projekce nezahrnovala nové order_sequence. Společný GetOrdersHelper.parseOrders nově používá strict OrderModel.fromCanonicalJson; pro rezervované sedadlo proto BlueprintModel.fromJson vyhodí StateError a editor se nenačte. Test v disposable DB získal skutečný RPC code 200 a jeden order bez metadata: `ASSERTION FAILED: Blueprint order has canonical sequence for shared Dart parser. Expected 1, but got <NULL>`. Toto je red-capable příkaz `DATABASE_URL=<vlastní loopback DB> node web_client/scripts/run_db_tests.js database/tests/eshop/get_blueprint_order_sequence_test.sql`.

Canonical SQL a migrace 20261006183000 doplňují order_sequence a order_symbol do stejné readonly projekce. Permission check a scoped joins zůstávají stejné; žádná zákaznická data se nemění, strict parser se neoslabuje. Po aplikaci lokální migrace původní reprodukční příkaz: 1 Passed, 0 Failed. Dart regression přes skutečný BlueprintModel.fromJson ověřuje canonical metadata a přesný StateError starého payloadu. Chybě zabrání kontrakt test pokrývající také samostatnou blueprint projekci.

Read-only canonical production diagnostika pro uživatelem uvedený PlesAKH2025-copy-ad8a55ba: occasion existuje v organization 3; běžící get_blueprint_for_edit neobsahoval order_sequence. Do diagnostiky nebyly přidávány test fixtures ani změny oprávnění.

## UI podle upřesnění uživatele

- Platné objednávky / Platné vstupenky, české a anglické shared katalogy i web copies. Význam predicate stále odpovídá dohodnutým nestornovaným řádkům.
- Uživatel zvolil kompaktní filtrační tlačítko: native Material FilterChip s ikonou, přesným count a barvami aktivního tématu. Stejný controller/native filters/draft/selection seam.
- Copy ikonka je přímo v buňce, popup odstraněn. Celý uložený symbol jde do clipboardu, button ukáže fajfku; barvy onSurface/surfaceContainerHighest a onPrimary/primary dávají čitelné potvrzení pro light/dark theme. Při změně symbolu se feedback resetuje.
- Šířka sloupce započítává inline button; historie používá stejný měřený width. Compact headers mají zpět native vertical divider podle grid style, bez rozšíření na původní 160 px help minimum.

## Ověření a rollout

SQL reprodukce red -> green; targeted widget copy/light/dark/filter/selection/draft/refresh/font scaling testy. První full gate zachytil chybný typ výjimky v novém regresním testu (FormatException místo skutečného StateError); focused width retest zachytil test-only chybějící EasyLocalization context při konstrukci všech nesouvisejících column builders. Testy byly opravené, nikoliv produkční parser nebo business chování. Žádný z těchto failures není deklarován jako pass. Finální automation/test_all.sh na konečné změně: exit 0, avšak původní integration slice měl environment failure vitest/config (chybějící npm dependencies ve fresh worktree). Po npm ci byl stejný integration slice přes automation/test_all.sh integration ověřen znovu: Deno 271 pass, image-worker 27 skipped, bez dalšího failure. Tolerovaný exit 0 původního integration failure nebyl započten jako pass. Ostatní finální slices: JS 222 pass, SQL 130 pass, Flutter 1142 pass + 1 skip, Deno 271 pass, automation pass. Image-worker 27 skipped a PyYAML structural fallback nejsou deklarované jako pass. Logy /tmp/order-sequence-fix-final-full-gate.log a /tmp/order-sequence-fix-integration-recheck.log. Nasazení bude doplněné po dokončení.


## Nasazení opravy

PR #324 sloučen jako pokračování uživatelem schváleného stejného rolloutu; merged main d4302f156b1388749c9fe5fa0a074a3c45e9f622. Migration 20261006183000 aplikovaná z přesného main source, se schema backup v chráněné vzdálené evidenci /var/lib/festapp-rehearsal-evidence/blueprint-order-sequence-fix-20261006T164058Z (0700) a atomickým ledger zápisem. Source SHA256 a1db5b2c7b1748abe11a747f459d3d86e034e14e0f3a5e8effabe6337031efa1, ledger hash potvrzen. Žádné zákaznické mutace ani produkční fixtures.

Skutečný readonly get_blueprint_for_edit pro PlesAKH2025-copy-ad8a55ba s existujícím oprávněným occasion editorem: code 200, 1 order reference, validní sequence i symbol. Claims pouze transaction-local, diagnostic transaction rollback. Do logu šly jen code/count, žádné osobní údaje. Log /tmp/order-sequence-blueprint-production-verify.log. Nejde o test uživatelova browser session.

Tenant overlay nad přesným merged main, pouze prod/festapptickets: 0.20.125+609, commit 41d6b022a181d401a80e7266fc001077db321578, předchozí tenant tip cad7340dff5630cb5108b78433ad426a14c6e22b. Main-owned drift checker pass. Před push znovu fetch origin/main a origin/prod/festapptickets, oba heads souhlasily s plánovaným základem. Deploy workflow 37497790754 spuštěný výslovně pro tento commit; finální web výsledek bude doplněn. Source manifest /tmp/order-sequence-blueprint-ui-fix-source.sha256.


### Finální web stav

Deploy workflow [37497790754](https://github.com/festappnet/festapp/actions/runs/37497790754) conclusion success. Build/upload i canonical live verifier prošly; `verify_web_deployment: ok (0.20.125+609, 3 consecutive probes)` v 2026-10-06T16:47:59Z. Deployment https://040f952d.vstupenkyonline.pages.dev. Dodatečný Node public smoke: version 0.20.125+609, tenant festapptickets canonical generation 1, /admin HTTP 200 přes cloudflare-pages a správná immutable main bundle vazba - PASS. Log /tmp/order-sequence-fix-release-actual-workflow.log, veřejná metadata /tmp/order-sequence-fix-public-smoke.json.

Oprava i UI nasazené na vstupenky.online. Lokální testovací Supabase vypnutý, žádný vlastní browser/dev server nezůstává spuštěný. Vzhled copy/check je ověřený widget testem v light/dark; produkční browser session uživatele nebyla ovládána. Source manifest [order-sequence-blueprint-ui-fix-2026-10-06.sha256](order-sequence-blueprint-ui-fix-2026-10-06.sha256).
