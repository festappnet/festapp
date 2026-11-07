# PR #750 - lokální implementace souhlasem řízeného měření

Pracovní větev: `fix/form-measurement-consent`.
Worktree: `/Users/miakh/source/festapp-measurement-consent`.
Výchozí PR head: `65705b455ace4818d063aa122352cf48b6fe86f8`.
Fetched autoritativní main a konečný HEAD větve:
`44a46d6a8a67a51f9bd44c8f5f91fe02b16e74cf`.

PR změny byly sloučeny s aktuálním mainem, konflikt v MCP referenci vyřešen
kanonickým generátorem. Větev byla následně lokálně přepnuta na main pomocí
`git reset --mixed origin/main` se zachováním všech pracovních souborů. Výsledkem
je přezkoumatelný necommitnutý diff proti mainu, bez rozpracovaného merge.
Původní checkout a ostatní worktrees nebyly změněny. Oba lokální plánovací
podklady jsou zkopírovány sem. Nebyl vytvořen commit.

## Dosažený kontrakt a odstranění

- `FormMeasurementSession` jako jediný lifecycle owner: inertní konstrukce,
  synchronní start subscriptions, sdílená policy Promise, kontrola identity a
  generace, obnovitelné chyby policy/CMP, terminální dispose. Ekvivalentní policy
  zachová grant, onActive oznámí použitelnou aktivaci jednou.
- Basic režim obou transportů vyžaduje analytiku i marketing. Kontaktní extrakce,
  `user_data` payloady, always-on/catch-start/timeout-start, policy/Auth rozhodování
  ve FormDataLayer a samoaktivace bridge jsou odstraněny. Inactive capture a staré
  sendery zůstávají trvalý no-op přes revoke/regrant. Submit zachytí doménový
  outcome callback před rezervacemi/requestem; měření neovlivňuje business výsledek.
- Runtime protocol 2 porovnává skutečný SQL/Worker manifest před vložením Unit
  kódu. Scope, revize, instance a generace vážou ready/init/ACK a události.
  Layout/scroll/theme protocol 1 zůstává; starý measurement grant se nepřevádí.
- Host `connectMeasurementConsent` čte živý revision-bound zdroj a spravuje
  lokální lease. Heartbeat zdroj znovu čte, viewport oprávnění neprodlužuje,
  receiver ověřuje zdroj i lease před každým push. Starý boolean/Klaro vstup
  nemůže vytvořit nový měřicí grant. Bez helperu měření zůstane vypnuté.
- SQL processing revision a kladná nesnižovatelná `measurement_consent_version`
  používají existující autorizovanou Unit aggregate mutaci. Default projekce je 1;
  null, pokles, neinteger a konflikt verze jsou odmítnuty. Enhanced conversions
  jsou explicitně nedostupné. Obchodní facts/replay zachovávají původní podmínky,
  stabilní event ID, význam přijaté objednávky a nezávislost na runtime výpadku.
- UI texty všech šesti jazyků, MCP a integrační dokumentace popisují stejnou matici.
  Embed/runtime/MCP a source parity jsou vytvořeny kanonickými generátory.

## Migrace a lokální prostředí

Nový kontrakt je forward migrace
`20261107110000_form_measurement_consent.sql`, sestavovaná skriptem
`automation/assemble-form-measurement-consent-migration.py`.
Historické SQL obsahy nebyly změněny. Kvůli timestamp kolizi s main cash migrací
byla pouze PR privacy migrace přejmenována z `20261106220000` na `20261106221000`.
SHA-256 obsahu před i po přejmenování:
`afaf10ee7d4baa46771eab2f0685e505812b1992db9e22eb1b2b0411f24af7ce`.
Budoucí nasazení musí nejprve ověřit ledger případně aplikovaného PR timestampu.
Produkční ledger nebyl čten ani měněn.

Disposable bootstrap nyní sjednocuje také vlastníka schématu analytics s postgres,
stejně jako již sjednocoval tabulky a funkce. To umožní skutečně znovu aplikovat
historickou migraci v migračních/chaos testech; API role nadále nemají přístup.
Nově spuštěná conversion matrix odhalila kolizi názvu PL/pgSQL proměnné payload
s SQL sloupcem; dvě čtení jsou nyní jednoznačně kvalifikována. Assertions nebyly
oslabeny a žádná skutečná DB integrace nebyla nahrazena mockem či skipem.

## Ověření

- Finální výběr Node z `web-measurement`: 137 passed, 0 failed, 0 skipped.
  Obsahuje skutečné FormPage.submitOrder wiring přes čekající backend/rezervace,
  zpožděnou policy, role/identity, obě transportní hranice, CMP, deduplikaci,
  heartbeat/revizi a seeded soukromé kontakty. Po poslední úpravě textu readiness
  byl zopakován dotčený kontraktní test.
- Cílené Flutter Unit/form případy: 20 passed, `--concurrency=1`, FVM.
- Kanonický `web-startup` prošel. Po navazujících opravách obnovy CMP a doplnění
  regresí prošel finální Node výběr a dotčený `web-measurement` browser krok;
  ostatní nezměněné startup scénáře se zbytečně neopakovaly.
- Browser suite: host, skutečný Klaro (`--cmp`), runtime, nested a adversarial.
  Deterministické tagy dokazují načtení/spuštění i network hranici souhlasu,
  nesoulad parent A/Worker B, revoke/regrant a pagehide/BFCache. Browser práci
  provedl Terra v izolovaných background sessions s mute a light mode.
- Kanonický `seat-measurement`: 7 skutečně vybraných SQL souborů = 6 measurement
  testů + canonical mutation source parity. Všech 7 prošlo nad disposable DB.
  Následovalo 26 skutečných MCP/PostgreSQL testů, 26 passed, 0 failed, 0 skipped.
- Generátory: embed, runtime, configuration/form-measurement forward assemblery,
  historická migration immutable check, canonical source parity a MCP docs:check
  prošly. `git diff --check` prošel.

Průběžné lokální logy jsou `/tmp/measurement-node-final.log`,
`/tmp/measurement-flutter.log`, `/tmp/measurement-contract-final.log` a
`~/Library/Caches/festapp-ci/{web-startup,seat-checkout}.log`.
Kanonický `seat-checkout` dokončen úspěšně za 87,9 s včetně real map click ->
SQL reservation -> preview -> order a offline release/reconnect/recovery.
Kanonický `web-startup` prošel za 45,7 s. Po opravě CMP recovery prošlo všech pět
measurement browser invocations; po konečné opravě teardown se znovu úspěšně
spustil dotčený skutečný Klaro `--cmp` browser scénář. Finální Node výběr má
137 passed, 0 failed, 0 skipped. Poslední readiness text prošel 5 kontraktními testy.

Následná oprava 2026-11-07 odstranila i původní jediný skip authorization catalog
testu v `tools/festapp/test/postgres-guard.test.mjs`. Kanonický seat-contract
předává `FESTAPP_AUTHORIZATION_DATABASE_URL` a explicitní port/project stejné
marker-ověřené, cron-disabled a email-fenced disposable DB. Test skutečně proběhl
pro správný marker i odmítnutí chybných markerů; skupina prošla 23/23 bez skipu.
Finální kompletní seat-checkout rerun prošel za 87,9 s: všech 10 TAP skupin
vykonalo 119/119 testů a všechny hlásí 0 skipped, bez explicitních SKIP markerů.
SQL migrační NOTICE obsahující „skipping“ nejsou skipy testů. Real seat i offline
recovery browser checks rovněž prošly. Podmínky ani assertions nebyly oslabené. GitHub workflows nyní také výslovně
volají web-measurement a seat-measurement podle checks.json; shoda GitHub/local
prošla všech 6 CI contract testů. Measurement SQL ani MCP testy nemají skip.
Nebyly vynechány žádné požadované measurement DB/browser závislosti.
Seat browser fixture nyní volá skutečné policy SQL a serializuje RPC nad jednou
sdílenou fixture transakcí, aby souběžné policy/checkout requesty nekolidovaly
na savepointech. Fixtures nenahrazují databázové assertions stuby.

## Neprovedené provozní kroky a meze

Žádný commit, push, PR komentář, merge, deployment, produkční SQL, změna GTM,
collectorů nebo runtime konfigurace, ani zapnutí měření. Žádná prod větev nebyla
změněna. Celá klientská/Flutter sada ani osm GitHub required jobs se nespouštěly;
pro budoucí release platí běžné gates na přesném baseMainSha.

Test tag není živý důkaz Google/Meta atribuce či doručení do Ads. Změna obsahu
vzdáleného kontejneru nebo zásad na stejné adrese vyžaduje zvýšení consent verze
pořadatelem; Festapp takovou změnu automaticky nerozpozná. Cizí schválený host může
lhát o CMP a již přijatá data nelze odvolat. Nový deploy ani DB disable neukončí
již otevřené legacy always-on klienty; úplný provozní cutover se netvrdí.


## Autorizovaná publikace a release 2026-11-07

Následné zadání autorizovalo commit, začlenění PR #750 a nasazení jednoho tenanta
`prod/festapptickets` (vstupenky.online). Předchozí oddíl zaznamenává stav při
lokálním předání a není popisem pozdějšího provozního výsledku.
PR byl mezitím rebased na main: head `98dea55d6406591eb17fef989f9a6d0763853551`.
Range-diff potvrzuje stejné tři změny s přegenerovanými kontrakty a privacy migrací
na timestampu `20261106225000`; konečná větev navazuje na tento autoritativní head
a zachovává tento novější název, se stejným původním SQL obsahem.
Read-only produkční preflight ověřil canonical tenant festapptickets, organizaci 3,
ledger s cash_reservations na `20261106220000` a žádnou ze tří PR migrací ani novou
consent migraci. V daném tenantu je 0 povolených platform policies, 0 provisioned
Unit runtimes a 0 measurement-enabled Units. Zapnutí měření není součástí release.
Release stav a skutečně provedené provozní kroky budou zaznamenány samostatně.
