# Web embed architecture - local execution evidence

Source: isolated worktree `/Users/miakh/source/festapp-web-embed-20261108`,
branch `refactor/web-embed-architecture-20261108`, base
`06671adfbf42b30a331eb73d7efe3ec6975615f0`. PR #769 remained open at
`987574b9dbe9a9617a4f070332fffa511b2b1004`; its diff was applied locally,
excluding the Flutter embed presentation. No commit, push, merge or deployment.

## Ownership and contraction

- `page_context` owns `/form/:slug` and `/order` with exact `embed=1`.
  `embed_context`, generated pre-paint HTML and the updater use that source.
- `runtime_state` owns starting/ready/failed, retry and the navigation lock.
  HTML/Dart ready globals project it; `update_policy` gates named reasons,
  `update_controller` owns recovery execution, and `update_banner` presents it.
- `protocol` and per-peer `channel` replace both basic wire definitions.
  The child bridge composes layout, measurement and the existing theme.
  `form_page`, validation, preview, price and blueprint callers keep their APIs.
  Host layout, presentation, price and measurement have separate modules.
- Deleted `scripts/embed.template.js`, text-spliced measurement exports,
  query-only production detectors and handwritten distribution updater.
  No Flutter embed CSS was imported. Regex checks of updater internals were
  replaced by behavioral checks; build wiring assertions remain.
- Preserved protocol 1, singleton `FestappEmbed`, CMS attributes/markup,
  `/embed.js`, 120/240/800 behavior, measurement contract/session policy,
  ready/recovery names, session keys, worker version handshake and limited
  legacy Flutter cache migration. Frozen old helpers are test fixtures only.

## Evidence

Logs: `/Users/miakh/source/artifacts/festapp-web-embed-20261108/`.
Checks apply to their recorded source inputs; failed diagnostic attempts are
retained separately and are not counted as passes.

| Check | Inputs / contract | Result | Log |
| --- | --- | --- | --- |
| Pre-refactor browser characterization | PR #769 behavior before owner swaps | Existing access/interaction + initial real embed cases passed | Terra baseline logs |
| Targeted contracts | Embed, update, startup, appearance, bootstrap | 115 passed at initial module extraction | `targeted.log` |
| New runtime behavior | Context matrix, policy, async races, navigation lock, channel lifecycle | Initial 38 passed; updater-only live-route delta + existing update tests: 62 passed; local-development behavior: 1 passed | `runtime-contract.log`, `runtime-final.log`, `local-development.log` |
| Final web suite | Generated assets, all web tests, fresh marked local SQL on port 62542 | 1127 + 24 passed, 10 + 1 skipped, 0 failed | `web-suite-final.log` |
| Update executor behavior | Actual standalone asset and public recovery globals | Passed | `update-behavior-final.log` |
| PWA and manifests | Shell wiring, worker, offline safety and immutable recovery paths | 12 passed | `pwa.log` |
| Canonical lanes | web-startup, wix-checkout-compatibility, seat-checkout | Passed: 82.57 / 9.93 / 92.96 s; affected web-startup rerun after compact error CSS/test also passed (90.4 s) | `ci-three-lane-receipt.json`, `ci-three-lane-*.log`, final startup receipt/log |
| CSP / final verifier diagnostics | Static CSP generation and final static verifier | Both passed independently; later approved-budget gate and verifier also passed | `csp-diagnostic.log`, `verifier-diagnostic.log` |
| Build completion after approved budget calibration | Reused unchanged compiled artifacts; source config now 35/80 MiB | PASS: core 28,991,850 / 36,700,160 B; known 64,303,550 / 83,886,080 B; final verifier passed | `pwa-budget-approved.log`, `verifier-approved-budget.log`; earlier build logs retained |

The full web suite preceded a controller-only correction to read the live route
for banner suppression. Its affected update tests passed again (62 tests), with
a separate passing local-development case; unrelated DB/child coverage was reused.

Web-suite skips: nine explicit live security tests without live credentials and
two optional separate-database concurrency scenarios. They are not claimed as
executed. Real SQL runs use only marked local disposable databases. Backend
transport in form-access characterization is simulated; seat-checkout's SQL
browser gate provides the real order/offline contract.

Owned port-62542 database was stopped with the canonical bootstrap `--stop`.
Owned browsers, fixture servers, mirror database (55442) and full-suite database (62542) are stopped; no owned Flutter task remains. Compiled build artifacts and logs are retained. No production orders, payments, e-mails or remote data changes.

Browser environment: the unmodified mirror used its supported Chromium discovery
with a task-owned launcher for installed Chrome for Testing 151.0.7922.47 and
agent-browser 0.39.4. System Chrome stalled under the runner's cross-domain
network controls. The passing cases retain different localhost/127.0.0.1
origins. Isolated font-sheet restrictions logged a Flatpickr CSSStyleSheet
SecurityError; actual calendar opening, date selection and validation passed.
This is not evidence for Safari, Firefox or physical mobile devices.

## Completion and build provenance

Etapy 1-6 jsou implementované a lokálně ověřené, deletion ledger je uzavřený.
Původní PWA size blocker je po uživatelem schválené kalibraci 35/80 MiB uzavřený.
Mění se pouze build policy v `automation/project.conf`; runtime ani seznamy
cache zdrojů se nemění. PWA gate a finální static verifier prošly nad hotovým
balíkem, bez opakované Flutter kompilace. Known součet po vygenerování CSP je
64,303,550 B; starší měření 64,270,378 B bylo před CSP výstupy.

Původní static wrapper po úspěšné Flutter kompilaci skončil na nestabilním
browser fixture assertion. Po testové opravě navázal přesným zbývajícím suffixem
stejného skriptu se stejnými vstupy a ověřenými hashy Flutter HTML/executables.
Startup/browser gate, Vite a rendering prošly, původní PWA budget selhal.
CSP/verifier byly ověřeny samostatně; nyní prošel i schválený PWA gate a finální
verifier. Původním neúspěšným procesům se nepřepisují exit kódy ani receipts.
Platné kontroly nezměněného runtime/browser/SQL kódu se neopakovaly.

Neprovedené provozní kroky: commit, push, merge, tenant overlay, GitHub release
gate pro publikovaný exact-main SHA, produkční deploy, migrace a live smoke.
Nejde o nasazený ani publikovaný release.

## Audit možností zmenšení

- Live `vstupenky.online` verze `0.20.530+1041` už používá gzip/Brotli:
  hlavní JS 13,112,051 B raw, 3,591,190 B gzip, 3,580,137 B Brotli.
  Lokální build `0.20.1+485` má jinou identitu; velikosti se nesměšují.
- Lokální další minifikace obou Flutter executables ušetřila pouze 0.45 %
  syntax-only / 1.60 % při experimentálním přejmenování. Šlo o měření v paměti,
  nikoli změnu distribuovaných souborů ani důkaz bezpečnosti transformace.
- Pozadí náhledů, katalog fontů a ukázky e-mailů mají skutečné runtime volající.
  Z offline kontraktu se nevyřazují. Odregistrované dependency fonty již nemají
  automatické engine načítání; dosavadní optimizer je ponechává dostupné.
- `CORE_URLS` (67 souborů) worker instaluje atomicky. Větší known/PRECACHE
  seznam (278 souborů) pouze dovoluje lazy caching. Nepoužívané fonty a ostatní
  CanvasKit varianty tedy nejsou důkazem zbytečného stahování při instalaci.
  Jejich vyřazení by snižovalo hlavně teoretický known budget.
- Live worker core obsahuje Flutter main i deferred part. Oddělení jeho instalace
  od veřejných webových formulářů je skutečný další kandidát na úsporu, ale mění
  současné offline/update vlastnictví a vyžaduje samostatný návrh a ověření.
  Direct HTTP probe deferred part vrátil 403; není to důkaz chyby UI.

Podklady: `compression-probe.json`, `size-options-experiment.json`.
Žádná produkční konfigurace, asset ani obsah cache nebyly změněny.

Final affected startup lane: Node batches 229/229, 168/168 and 29/29 with zero
skips; all browser cases passed. Wix: 47 pass/4 skips, 81/81, 5/5 and 24 CMS
renderer cases (CMS APIs stubbed). Seat: 120 Node passes, 104 SQL passes and real
SQL/browser checkout plus offline recovery; Deno output remains in the lane log.
The startup-error case uses `navigator.onLine=false` plus an actual local entry
404; it is not a physical network-disconnection test.

`source-inputs.json` records the final uncommitted source and individual SHA-256
inputs by group; `source-diff.patch` records tracked deltas. Final source digest
excludes documentation so this evidence can be updated without invalidating
code checks. The full web-suite receipt is retained for unchanged inputs;
controller-only and startup-CSS/browser-fixture deltas have the targeted and
canonical results listed above. Build-generated source drift: none.

Původní runtime/test input SHA-256: `ee0b504d2fae33100bae843b2f20ce15fe90ba854313548de4f891b278effeb4`.
Schválený config-only delta SHA-256: `369150d8ba4cd3ae755bc228898fb38700462a0bf90f3adbca47f054c415bd2b`; viz
`source-inputs-budget-approved.json` a `source-diff-budget-approved.patch`.

## Navazující požadavek: veřejná instalace bez Flutteru

Implementováno v témže izolovaném checkoutu. Původní report a receipts výše
platí pro své vstupy; tato změna má nové logy v
`/Users/miakh/source/artifacts/festapp-public-runtime-20261108/`.

Jediný manifest nyní rozděluje core na web a Flutter. Root worker instaluje
webový graf; Flutter připraví atomicky až jeho skutečná navigace/handoff nebo
Flutter HTML startup. Verze, per-client cache pinning a cache pruning zůstávají
společné. Nový `worker_shell.js` sdílí profilovaný handshake mezi startupem,
update controllerem a existujícím `prepareFlutterRuntime`. Veřejný repair se
omezuje na web. Chybné stažení Flutter části nepoškodí veřejný shell.

Průběžná evidence: 114 runtime/startup/handoff testů prošlo; PWA manifest +
nové runtime-shell testy 14 prošlo, samostatný PWA/offline kontrakt také prošel.
Celá webová Node sada: 1129 pass, 10 skip, 0 fail. Všechny tři kanonické CI lanes a canonical static build následně prošly.
Deset web skips jsou explicitně volitelné live/concurrency scénáře; nepočítají
se jako provedené. Původní nezměněné DB testy se zbytečně neopakovaly;
kanonický seat-checkout lane znovu ověří reálné SQL a offline formulář.

Finální release build: veřejný core 61 souborů / 2,797,713 B; odložený Flutter
core 6 souborů / 26,198,087 B. Veřejná instalace se zmenšila oproti společnému
core 28,995,800 B o 90.35 %. Jde o raw bytes cache, nikoli přenosová data.
Known součet po CSP je 64,308,321 B; budget před CSP měřil 64,275,149 B.
Dříve schválené souhrnné limity 35/80 MiB zůstávají v platnosti.

| Finální kontrola | Výsledek | Evidence v novém artifact adresáři |
| --- | --- | --- |
| Runtime/startup/handoff | 114 pass | `runtime-targeted.log` |
| PWA manifest + runtime-shell kontrakty | 14 pass; opraven cwd fixture, 3 shell případy také ověřeny z web_client | `pwa-targeted.log`, `shell-cwd-check.log`; konečný kanonický lane obsahuje všechny |
| PWA offline/recovery | 1 pass | `pwa-offline-final.log` |
| Web Node suite mimo DB | 1129 pass, 10 skip, 0 fail | `web-suite.log` |
| Canonical web-startup / Wix / seat | PASS, 106.68 / 9.85 / 91.86 s | finální CI receipt a zkopírované lane logy |
| Canonical static release build | exit 0; Flutter, browser/startup, Vite, PWA budget, CSP i finální verifier PASS | `static-build.log` |

Browserová nová fixture používá skutečný generovaný worker a Cache API;
webový a Flutter engine payload jsou simulované. Prokazuje 0 Flutter požadavků
při čisté veřejné instalaci, web repair i starém neoznačeném dotazu z formuláře
nebo kořenové stránky; offline veřejný shell; žádný částečný Flutter zápis po
selhání; kompletní instalaci po retry nebo skutečné app navigaci a následnou
offline app navigaci. Reálný formulář, SQL objednávku a offline obnovu nezávisle
potvrdil seat-checkout lane. Nejde o plný browser audit všech Flutter obrazovek.

Build nezměnil tracked source. Vlastní browser sessions, mirror DB a Flutter
procesy jsou ukončené. Commit, push, tenant release a produkční deploy zůstávají
neprovedené. Finální zdroj a souhrn jsou v `source-inputs.json`,
`source-diff.patch` a `result-summary.json` nového artifact adresáře.

Navazující split-runtime source SHA-256: `07b017004a8bc317b976413a315122eba9f255e280fdc992c3ef620c2f7f2845`.

## Příprava autorizovaného web releasu

Uživatel následně autorizoval publikaci a nasazení na vstupenky.online
(`prod/festapptickets`) a požaduje plnou testovací sadu. Širší běh odhalil
zastaralé fixtures mimo původní tři lokální lanes. Opravy zachovávají současný
kontrakt a nesahají do produkčního SQL ani historických migrací:

- Bankovní fixtures mají skutečného připojeného příjemce. Testy přesně ověřují
  časné odmítnutí nedostupné metody i nulové vedlejší účinky. Bezplatný checkout
  fixture používá stejný common bank/no-provider payload jako oba klienti.
- Blueprint test ověřuje zachování skutečného uloženého deadline snapshotu,
  ne staršího pevného defaultu. Widget cash dialogu nespouští platformní
  deep-link listener mimo svůj testovací scope.
- Staré build fixtures kopírují nové runtime závislosti. Dva email-preview
  JSONy byly přegenerovány; jejich obsah mimo sourceDigest je shodný.
- Kontroly historické payment integrace/hardeningu nyní uzamykají původní SQL
  digest a ověřují aktuální definice proti posledním forwardům přes kanonický
  parser. Staré SQL soubory se nepřepisují; negativní test odmítá jejich změnu
  i pokus o historický zápis. Původní kontrola jediného receipt ownera zůstává
  omezena na svůj kanonický manifest a nezměněná.

Cíleně prošlo 5 SQL scénářů, 6 widget testů, 11 canonical-operation testů,
10 parser testů, version/build wiring. Finální celý wrapper běží na vlastním
lokálním DB/Auth/REST prostředí. Přesné release receipts a následné CI/live
ověření se ukládají do
`/Users/miakh/source/artifacts/festapp-web-embed-release-20261108/`.
Žádná databázová migrace ani odeslání reálné objednávky/emailu není součástí
webového nasazení.
