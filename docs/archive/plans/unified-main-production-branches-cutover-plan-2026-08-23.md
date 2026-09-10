# Jedna kanonická aplikace Festapp a tenké produkční branche

Date: 2026-08-23
Status: Ready for execution
Verification: standard

## Outcome

`main` bude jediným vlastníkem veškeré sdílené aplikační logiky Festappu:
Flutter klienta, veřejného webového klienta, SQL a Edge Functions, workerů,
testů, generátorů konfigurace a obecné release infrastruktury. Změny, které
dnes existují pouze v `prod/csmostrava2026`, budou buď zobecněny a přesunuty do
`main`, nebo výslovně označeny jako tenant overlay.

`prod/csmostrava2026` a `prod/hvezdamorska` se po cutoveru budou skládat z
aktuálního `main` plus malé, kontrolované množiny tenant-specific konfigurace,
brandingu a provozních/release artefaktů. Nebudou obsahovat vlastní kopie
business logiky ani starší varianty sdílených modulů. Budoucí společné opravy
vzniknou nejprve v `main` a do produkčních branchí se dostanou standardním
forward merge bez ručního přepisování celých společných souborů.

Tato práce je jeden ucelený cutover, ale provádí se v níže uvedených vlnách a
logických commitech. Nejde o slepý merge 260 commitů ani o jeden nečitelný
squash. Produkční deploy, DB migrace, push, přepsání vzdálené historie a release
do obchodů nejsou součástí automaticky uděleného oprávnění.

Tento plán a jeho execution prompt jsou nyní necommitnuté soubory v aktivním
CSM worktree. Další session je musí přečíst z této absolutní cesty ještě před
vytvořením čistého worktree. Prvním plánovaným source krokem je zkopírovat oba
dokumenty beze změny do integračního main candidate; jinak by se po přepnutí
worktree ztratily z branchového pohledu. Necommitnuté umístění není důkaz, že je
plán součástí `main`.

## Scope

### In scope

- Rekonstrukce úplného rozdílu `prod/csmostrava2026` vůči `main`, včetně
  změn schovaných za release agregáty, reverty a pozdějšími reapply commity.
- Přenesení všech tenant-neutral změn z CSM do `main`.
- Zobecnění CSM funkcí, které dávají smysl i pro jiné tenanty, pomocí existující
  occasion feature/config vrstvy; ne pomocí branch-specific forků kódu.
- Sjednocení Flutter, web client, SQL, Supabase Edge Functions, workerů,
  mapových balíčků, PWA/offline logiky, testů a obecné release automatizace.
- Vymezení a zmenšení tenant overlay pro CSM a Hvězdu mořskou.
- Forward-only obsahový cutover obou produkčních branchí na nový `main` bez
  přepisování jejich veřejné historie.
- Přesun aktuálních rozpracovaných tenant-neutral změn z pracovního stromu CSM
  do kanonické main historie, včetně opravy popisu produktového typu HM.
- Automatická kontrola, že produkční branche nedivergují mimo schválený overlay
  a že generované tenant soubory odpovídají `automation/project.conf`.
- Definice veřejného, verzovaného rozhraní mezi tímto repem a soukromým
  `private configuration repository`: Festapp deklaruje potřebné input names/schema, private configuration repository
  dodává neveřejné hodnoty a provozní seed/security materiál.
- Aktualizace dokumentace a pracovního postupu tak, aby se drift znovu
  nevytvořil.

### Out of scope

- Produkční nasazení klientů, Edge Functions, workerů nebo SQL migrací.
- App Store / Google Play submission a změna živých listingů.
- Změna produkčních dat, spuštění recovery SQL nebo backfillů.
- Force-push, reset nebo přepsání historie `main` či produkčních branchí.
- Smazání backup/recovery branchí. Ty zůstanou bezpečnostní hranicí minimálně do
  ověření obou produkčních release po cutoveru.
- Nové produktové funkce, které nejsou potřeba pro převzetí existujícího chování.
- Unifikace dalších historických `prod/*` branchí. Nový mechanismus však musí
  být použitelný i pro ně v navazující práci.
- Přesun nebo redesign obsahu samotného `private configuration repository`, dokud není repo
  jednoznačně nalezeno, přečteny jeho instrukce a udělen scope pro zápis.

## Constraints

- Před každým zásahem se čte `docs/architecture/ai_context.md`; business logika
  objednávek, plateb, oprávnění, sign-upů a inventáře může být v SQL.
- `automation/project.conf` je aktuální zdroj tenant identity a live Supabase
  cíle. `.env.local` nesmí určit cílový projekt.
- Všechny nové DB funkce jsou v `public`; `SECURITY DEFINER` funkce mají
  explicitní `search_path`, oprávnění a kvalifikované `eshop.*` tabulky.
- Nevznikne persistentní aplikační trigger ani dočasná dual-write/fallback cesta.
- Aplikované Supabase migrace se nepřepisují ani nepřečíslují. Přenášejí se jako
  stejná forward historie a nasazení zůstává odděleně autorizovaný krok.
- FVM je povinné pro lokální Flutter/Dart příkazy.
- Existující necommitnuté a untracked soubory patří uživateli. Cutover začne v
  novém čistém worktree a nesmí používat `reset --hard`, `checkout --` ani
  plošný stash nad současným pracovním stromem.
- Podle `CONTRIBUTING.md` agent nesmí automaticky commitnout ani pushnout.
  Připravené logické commity se před commitem ukážou uživateli a vyžádají si
  výslovné potvrzení.
- Standard verification je povinné, protože změna zasahuje produkční branche,
  databázové migrace, autentizaci/oprávnění, PWA a veřejné kontrakty.
- Release verification se spustí pouze na explicitní žádost o release.
- Overlay allowlist je bezpečnostní politika a vlastní jej `main`. Produkční
  branch nesmí měnit svou povolenou množinu ani drift checker, kterým je sama
  kontrolována.
- Service-role/database passwords, signing keys/certificates, provisioning
  credentials, Apple/Google/Cloudflare/OneSignal private API credentials,
  bootstrap/pairing/reception security codes a neveřejné provozní seed payloads
  nepatří do Festapp Git historie ani tenant overlaye. Jejich vlastníkem je
  `private configuration repository` nebo schválený secret manager napojený přes něj.
- Autorizační a validační logika sama o sobě je aplikační source code a patří do
  `main`; nesmí se schovat do private seed repa. Hranice odděluje neveřejné
  hodnoty/data od sdílené bezpečnostní implementace.
- `SUPABASE_ANON_KEY`, public app/bundle IDs, domains a AASA identifiers jsou
  veřejné client build identity, nikoli secrets. Mohou zůstat v public tenant
  configu, pokud politika private configuration repository neurčí jiný source; nikdy se za ně nesmí
  zaměnit service-role nebo deployment credential.

## Fixed points and current-state evidence

Následující SHAs a počty jsou lokálně pozorovaný stav z 2026-08-23. Před
implementací je nutné udělat `git fetch --all --prune`, znovu je zapsat do
cutover ledgeru a při změně aktualizovat tento plán; nelze tiše pokračovat proti
jinému fixed pointu.

| Claim | Evidence | Consequence |
|---|---|---|
| Aktivní worktree je `prod/csmostrava2026` na `84c1d5de5`; pracovní strom je špinavý. | `git branch --show-current`, `git status --short` | Implementace musí vzniknout v novém čistém worktree. Současné změny se nejprve inventarizují, neodkládají naslepo. |
| Lokální `main` je `d071cdd16`, lokálně 5 commitů před `origin/main`; `origin/main` je `d640434ed`. | `git rev-list --left-right --count origin/main...main` → `0 5` | Remote fixed point se musí před cutoverem ověřit; push main vyžaduje zvláštní souhlas. |
| CSM je lokálně 3 commity před remote. | `origin/prod/csmostrava2026=dbd06e0ff`, lokální tip `84c1d5de5`; count `0 3` | Tři lokální release/docs/map commity nesmí zmizet při konstrukci integrace. |
| HM je lokálně `942c45401`, 8 commitů před `origin/prod/hvezdamorska=591c66650`. | `git rev-list --left-right --count origin/prod/hvezdamorska...prod/hvezdamorska` → `0 8` | Lokální merge hlavní větve do HM je nutné zachovat jako historii, ale jeho strom nelze považovat za sjednocený. |
| `main...prod/csmostrava2026` má společný základ `c03c045c4`, main-only 1 commit a CSM-only 260 commitů. | `git rev-list --left-right --count main...prod/csmostrava2026` → `1 260` | Obyčejný merge je nevhodný; předchozí synchronizace byla agregovaná a histories nejsou patch-equivalentní. |
| Aktuální strom CSM se od main liší v 598 souborech, +183594/−3409 řádků. | `git diff --shortstat main prod/csmostrava2026` | Rozdíl směšuje zdrojový kód, vendored map packages, CSM assets, screenshots, recovery a release metadata; musí se klasifikovat. |
| `main` commit `d071cdd16` a CSM commit `90e7819da` popisují podobný reception/offline cutover, ale `git cherry` je nepovažuje za stejný patch. | `git cherry prod/csmostrava2026 main` a opačný směr | Nelze odhadnout „už přeneseno“ podle názvu commitu. Rozhoduje obsah a behaviorální testy. |
| Po `90e7819da` přibylo v CSM dalších 40 commitů a strom se změnil v 371 souborech. | `git log 90e7819da..prod/csmostrava2026`, `git diff --shortstat 90e7819da prod/csmostrava2026` | Ledger musí pokrýt minimálně map/PWA, feedback, activity, cleaning, schedule, place mutation, release automatizaci a iOS navigation. |
| HM má main ve své historii přes merge commity, ale aktuální strom proti main maže reception funkce/migrace a mění 223 souborů. | `git log --graph prod/hvezdamorska`, `git diff --name-status main prod/hvezdamorska` | „Main je ancestor“ není důkaz unifikace. HM potřebuje explicitní obsahový cutover, ne další no-op merge. |
| CSM a HM konfigurace ukazují na stejný Supabase ref `lwfpdjxsdmkfyrzqbrlk`, ale na různé organizace; main ukazuje na `kjdpmixlnhntmxjedpxh`. | tři verze `automation/project.conf` | Budoucí shared DB deploy na CSM/HM projekt se provede jednou a musí zachovat tenant scoping. Main/dev projekt je samostatný cíl. |
| `apply_config.sh` dnes mutuje společné source soubory pomocí sed/Python. | `automation/apply_config.sh`: web indexy/manifests, `app_config`, theme, Gradle, pbxproj, plisty, entitlements, AASA | Branchové rozdíly dnes mohou skrývat ruční změnu logiky ve stejných souborech. Generované listy se musí oddělit nebo deterministicky ověřovat. |
| Repository už říká, že public tenant identities a brand paths vlastní `project.conf`, nikoli generované soubory. | komentáře v `automation/project.conf` a `apply_config.sh` | Cutover tuto deklaraci musí technicky vynutit, ne jen dokumentovat. |
| `automation/tests/pwa_offline.test.mjs` obsahuje CSM-specific očekávání. | text `tenant-specific ... CSM sizing` a forced-occasion fixtures | Testy společné logiky musí být tenant-neutral; CSM data patří do overlay fixture/matrix. |
| CSM obsahuje generické vendored `packages/maplibre_android` a `packages/maplibre_platform_interface`, které main nemá. | `git diff --name-status main prod/csmostrava2026 -- packages` | Sdílené map packages musí být v main, pokud jsou aktivní dependencies; nesmějí zůstat CSM-only. |
| CSM-specific data jsou identifikovatelná: offline-map manifests, legal sources a recovery SQL; store metadata/screenshots vlastní the private configuration repository. | `automation/offline-map/manifests/csmostrava2026`, `automation/release/legal`, `database/recovery/2026-*csmostrava*`, private configuration repository `release/store-listings/csm-ostrava-2026` | Runtime tenant artefakty zůstávají na explicitní overlay boundary; publishing data mají jediného private ownera a do Festapp HEAD nepatří. |
| Předchozí EUR plán používal tenant-neutral implementaci v main a následné cherry-picky do produkčních branchí. | `docs/archive/plans/2026-08-05_eur_payment_reference_plan.md` | Jednorázový cherry-pick nestačí jako dlouhodobá architektura; nový cutover zavede opakovatelný main-first merge a drift gate. |
| HM popis produktu byl opraven v aktivním CSM worktree, nikoli v HM/main. | modifikace `web_client/src/components/forms/form_models.js` a nový `product_type_description.test.js` v CSM worktree | Oprava je tenant-neutral a musí být přenesena do main před cutoverem; z CSM nesmí zůstat jako branch-only logika. |
| Privátní konfigurační repozitář v `<private-config-repo-root>` obsahuje verzovaný provisioning contract a kanonická CSM publishing data. | read-only repo/remote audit a fail-closed provisioning testy 2026-08-24 | Cross-repo handoff používá jediný `FESTAPP_RELEASE_MANIFEST`; credential soubory zůstávají pouze v ignorovaném `release/private/` nebo schváleném secret manageru. |
| Po Wave 0 fetchi bylo zjištěno, že main a CSM nesou dvě různé migrace se stejným prefixem `20260806142000`: main `manage_occasion_users_permission`, CSM `reception_manual_login_code`. | `git log --all -- ...20260806142000*` a obsah obou souborů | Obě nelze vložit do jedné kanonické Supabase historie. Main historický soubor zůstává beze změny; CSM reception contract se přenese novou idempotentní forward reconciliation migrací `20260823120000`, takže se žádná již aplikovaná historie nepřepisuje. |

## Canonical contract

### Canonical owner

Kanonickým vlastníkem je `main` a jeho aktuální strom. Všechny produkční branche
jsou deployment overlays nad konkrétním main SHA.

`main` vlastní:

- `lib/**` a `test/**` kromě explicitně generovaných tenant leaf souborů;
- `web_client/src/**`, `web_client/tests/**` a společné web assets/templates;
- `database/functions/**`, `database/tables/**`, společné `database/tests/**`;
- `supabase/functions/**`, `supabase/migrations/**`, shared worker source/tests;
- `packages/**`, obecné `automation/**` skripty/testy, CI workflow a docs;
- feature metadata, permission contracts a runtime registrace;
- šablony a generátor tenant konfigurace.

`private configuration repository` vlastní neveřejné hodnoty, seed/security payloads a provisioning
materiál. Festapp `main` vlastní pouze veřejný input contract: názvy proměnných,
schema/typy, required/optional pravidla, bezpečné chyby pro chybějící input a
test fixtures s neplatnými/fiktivními hodnotami. Žádný Festapp test ani plan
artifact nesmí kopírovat skutečnou hodnotu z private configuration repository.

Produkční branch smí vlastnit pouze položky uvedené ve svém strojově čitelném
overlay manifestu:

1. `automation/project.conf` a branch release/version state;
2. brand assets (loga, fonty, Android/iOS/PWA ikony) uvedené konfigurací;
3. tenant legal texty nutné pro nasazený web/runtime; store listing metadata a
   screenshots vlastní private configuration repository a v produkční větvi Festappu nejsou;
4. tenant offline-map manifests/bundles;
5. tenant recovery/runbook artefakty, které se nikdy nespouští jako shared
   migration;
6. deterministické generované leaf soubory, pouze pokud zatím nelze generovat
   rovnou do build outputu.

Overlay manifesty a drift checker se vždy čtou z ověřeného `BASE_MAIN_SHA`
pomocí `git show`, nikoli z kontrolované produkční branche. Produkční branch
smí obsahovat pouze malý metadata soubor se svým tenant ID a očekávaným
`BASE_MAIN_SHA`; CI ověří, že SHA existuje, je schváleným main commitem a je
ancestor nebo explicitní parent cutover commitu. Tím si branch nemůže rozšířit
vlastní allowlist ani oslabit kontrolní skript.

Každá tenant odchylka mimo tento seznam je chyba cutoveru. Funkce dostupná jen
jednomu tenantovi se implementuje jednou v main a zapíná se přes existující
occasion feature/config contract. Branch name se nesmí používat v runtime
business rozhodování.

### Configuration inputs, outputs and errors

- Input: explicitní cesta ke konfiguraci nebo tenant ID; bez implicitního
  odvození z aktuálního Git branch názvu.
- Source of truth: `automation/project.conf` v produkční branchi, případně
  namespaced fixture/profile v main pro matrix testy.
- Output: přesně vyjmenované generated leaf files nebo build output.
- Error: chybějící required key, nevalidní URL/bundle ID/language/color/feature
  hodnota, neexistující asset nebo nevynulovaný stale tenant token ukončí
  generátor non-zero; nikdy se tiše nepoužije hodnota předchozího tenanta.
- Side effects: generátor nesmí měnit shared business logic, testy ani nevyjmenované
  soubory. Opakované spuštění se stejným inputem je byte-for-byte idempotentní.
- Persistence: branch-specific input/assets zůstávají v Git; build artefakty a
  secrets ne. Anon keys jsou veřejná build identity, service-role/Apple/Google
  credentials se do Git nepřidávají.
- Private-input resolution: build/deploy dostane tajné hodnoty explicitním
  environment/file handoffem z private configuration repository/secret manageru. Festapp nesmí mít
  fallback na committed tajemství ani automaticky číst libovolný sibling path.
  Interface version/fingerprint může být veřejný; secret content/hash ne.

### Invariants

1. `git diff "$BASE_MAIN_SHA".."$PROD_TIP"` obsahuje pouze cesty povolené overlay
   manifestem daného tenanta.
2. V žádné produkční branchi neexistuje modifikace shared Dart/JS/SQL/Deno
   business logiky proti uvedenému main SHA.
3. Všechny povolené generated soubory jsou reprodukovatelné z čistého tree
   `BASE_MAIN_SHA`, tenant source overlay a jednoho běhu konfigurátoru; následný
   druhý běh nevytvoří diff.
4. Shared feature je přítomná ve všech branchech; dostupnost určuje permission,
   occasion feature nebo config, ne odstraněný soubor či branch check.
5. Všechny SQL migrace a Edge contracts mají jednu společnou historii v main.
6. Tenant recovery SQL není součástí automatic migration discovery.
7. Produkční branch zaznamenává main SHA, nad kterým byl overlay ověřen.
8. Merge nového main do čisté produkční branche nevytvoří konflikt ve shared
   souborech; konflikt v overlay souboru je explicitní tenant rozhodnutí.
9. CSM i HM se sestaví ze stejného shared source SHA a z vlastního configu.
10. Oprava HM formuláře vykresluje `product_type_data.description` ve všech
    tenant builds; není HM-specific fork.
11. PWA cache, auth storage key, OneSignal identity, app ID, AASA, bundle ID a
    organization nikdy nepřetečou mezi tenanty v config matrix testu.
12. Žádná současná necommitnutá práce ani lokální ahead commit se při cutoveru
    neztratí.
13. Secret scan nenajde novou private hodnotu v plánu, ledgeru, patches,
    generated outputs, logs ani tenant overlays.
14. Festapp lze testovat s fiktivními security inputs; skutečné hodnoty jsou
    potřeba až pro samostatně autorizovaný build/deploy/release krok.

### Entry points and forbidden bypasses

Intended entry points:

- běžná feature práce: branch/PR z `main`;
- tenant release: aktualizace overlay vstupu/assets nad aktuálním main SHA;
- config generation: jediný `automation/apply_config.sh` (interně může delegovat
  na nové generátory);
- branch alignment: standardní forward merge main a overlay validation;
- DB schema: společné forward migrace z main, nasazené na přesně ověřený projekt.

Forbidden bypasses:

- feature commit přímo pouze do `prod/*`;
- ruční editace generated config output bez změny source/generatoru;
- kopie SQL/Dart/JS modulu v tenant adresáři;
- `if (branch == ...)`, hardcoded CSM/HM runtime rozhodování nebo hostname jako
  náhrada permission/feature kontraktu;
- merge conflict resolution typu „ponech naši verzi celého `lib/`/`database/`“;
- squash označený jako sync bez ledgeru, absence proof a testů;
- force-push produkční historie;
- deployment migrací na projekt vybraný podle `.env.local`.
- kopírování secret/security hodnot z private configuration repository do `project.conf`, fixture,
  dokumentace, patch snapshotu nebo CI logu;
- přesun authorization/business rules do private configuration repository jen proto, že souvisejí se
  security; private repo dodává hodnoty/data, ne druhou implementaci pravidel.

## Decisions, assumptions, and blockers

### Decisions

- **D1 — Forward-only content cutover:** produkční branche se nepřepisují.
  Vznikne nový commit, který nastaví všechny shared cesty přesně na nový main a
  znovu aplikuje pouze schválený overlay.
- **D2 — Main-first:** každá tenant-neutral změna včetně HM product description
  opravy a CSM map/PWA oprav skončí nejprve v main.
- **D3 — Behavior over commit names:** každý CSM commit dostane ledger status
  `already-equivalent`, `promote`, `generalize`, `tenant-overlay`, `obsolete-by-revert`
  nebo `operational-only`. Žádný commit nezůstane nezařazený.
- **D4 — Feature flags místo source absence:** reception, counseling, offline map,
  dark mode a podobné schopnosti zůstanou ve společném kódu a jejich dostupnost
  určí metadata/rights/config.
- **D5 — Reproducible overlays:** path allowlist nestačí. Generated paths musí
  mít také content proof z generatoru spuštěného nad čistým main template, ne
  nad už tenant-mutated stromem.
- **D6 — Shared CI/workflows own main:** produkční branch nesmí mazat nebo mít
  vlastní kopii obecného CI workflow. Tenant deployment se parametrizuje.
  Drift politika se načítá z recorded main SHA, takže kontrolovaná branch ji
  nemůže sama oslabit.
- **D7 — One task, multiple commits:** realizace je jeden cutover/PR, ale používá
  malé auditovatelné commity po vlnách. To umožní bisection a bezpečné schválení.
- **D8 — No production action:** lokální source/branch cutover končí před deployem,
  pushnutím a store release; ty jsou samostatná autorizovaná rollout fáze.
- **D9 — Minimal generator refactor:** cílem není preventivně přepsat celý
  config systém. Nejprve se instrumentací zjistí přesná write-set dnešního
  `apply_config.sh` a zavede fresh-main replay/content proof. Shared soubor se
  rozdělí na stable logic + generated leaf pouze tehdy, pokud současný mutátor
  nedokáže bezpečně a jednoznačně měnit jen konfigurační pole.
- **D10 — Main policy cannot be branch-owned:** `.paths`, checker, config schema
  a canonical templates jsou načítané z main. Tenant branch vlastní pouze
  input/data a recorded base SHA.
- **D11 — private configuration repository boundary:** neveřejné security/provisioning hodnoty a
  provozní seed payloads zůstávají mimo Festapp; public schemas a aplikační
  security logic zůstávají v main. Cross-repo handoff musí být explicitní,
  verzovaný a fail-closed, ale konkrétní private configuration repository path se neurčí bez jeho
  skutečného locatoru a instrukcí.
- **D12 — Migration collision reconciliation:** konflikt dvou různých
  `20260806142000` migrací se neřeší přepsáním ani výběrem jednoho obsahu. Main
  historická migration zůstává a reception schema/function contract dostane
  nový forward-only, idempotentní reconciliation timestamp; původní CSM
  migration zůstává dosažitelná pouze v produkční historii.

### Assumptions

- **A1:** `90e7819da` je přibližný obsahový okamžik, ze kterého vznikl main
  agregát `d071cdd16`; impact if false: ledger musí porovnat širší historii;
  resolve by: `git range-diff`, tree/path diff a behavior tests ve Wave 1.
- **A2:** vendored MapLibre packages v CSM jsou stále aktivně používané;
  impact if false: jejich přenesení by přidalo dead code; resolve by: `pubspec.yaml`,
  imports a platform registrace před klasifikací `promote` versus `delete`.
- **A3:** CSM-specific recovery a store data nemají být dostupná HM buildu;
  impact if false: přesunou se do namespaced shared tooling, ne do runtime;
  resolve by: callers/workflows/README reachability map.
- **A4:** HM-specific historické změny jako Fakturoïd/smlouva už mají nebo mohou
  dostat obecný config/feature contract; impact if false: musí být popsán jediný
  tenký externí boundary adapter s konkrétním consumerem a removal condition.
- **A5:** produkční branche mají i nadále zůstat release branches; impact if
  false: jednodušší model je jediná branch + tenant build matrix; resolve by:
  uživatelův explicitní požadavek na rozdíly v branches je pro tento plán
  autoritativní.
- **A6:** `private configuration repository` je dostupné pod jiným ownerem/URL nebo mimo aktuální
  `<workspace-root>`; impact if false: private-input část cutoveru zůstane
  pouze veřejným Festapp contractem; resolve by: uživatelem dodaný locator nebo
  autorizovaný repository discovery v první Wave 0 session.

### Blockers / separate authority

- Commit a push každého připraveného balíku podle `CONTRIBUTING.md` vyžaduje
  výslovné potvrzení.
- Produkční DB/Edge/worker/web/native deploy a store submission vyžadují nový
  souhlas.
- Pokud po fetchi remote obsahuje nové commity v některé ze tří branchí, musí se
  nejprve zařadit do ledgeru; nelze je přepsat.
- Pokud nelze určit, zda konkrétní HM/CSM chování je produktové nebo tenant-only,
  implementace se zastaví pouze na této položce, uvede caller/data a vyžádá
  rozhodnutí. Ostatní nezávislé vlny mohou pokračovat.
- Zápis do `private configuration repository` je blokovaný, dokud není znám přesný repo locator,
  přečteny jeho `AGENTS.md`/README/runbooky a uživatel nepotvrdí, že tento velký
  task smí měnit i druhé repo. Festapp-side schema/secret-free validation může
  pokračovat samostatně.

## Required cutover artifacts

Realizace vytvoří a průběžně udržuje:

- `docs/archive/audits/unified-app-cutover-ledger-2026-08-23.md` — každý divergentní
  commit/skupina a jeho klasifikace, cílový main commit a důkaz;
- `automation/tenant-overlays/csmostrava2026.paths` — povolené CSM cesty;
- `automation/tenant-overlays/hvezdamorska.paths` — povolené HM cesty;
- `automation/tenant-overlays/generated.paths` — společný seznam pouze
  generovaných leaf outputs;
- `automation/check_tenant_branch_drift.sh` — absence/drift gate;
- veřejné schema required build/deploy inputů bez skutečných secret values;
- config matrix fixtures bez live secrets pro Festapp/CSM/HM;
- cutover report se třemi výslednými SHAs a výstupy validace.

Všechny `.paths`, `generated.paths`, config schema a checker jsou main-owned.
Branch nesmí mít jejich odlišnou verzi. Branch-owned metadata má samostatnou
úzkou cestu, například `automation/tenant-overlay.json`, která obsahuje pouze
tenant ID, `BASE_MAIN_SHA` a release metadata povolená schématem.

Ledger nesmí být jen seznam commit subjects. U každé položky zaznamená source
SHA/range, dotčenou capability, status, cílové soubory/symboly, zda obsahuje
migraci/provozní krok, a příkaz/test dokazující výsledek.

## Initial classification map

Tato tabulka je startovní mapa, nikoli povolení přeskočit per-commit ledger.

| Area | Likely classification | Required treatment |
|---|---|---|
| Flutter UI/services in `lib/**`, tests in `test/**` | promote/generalize | Přenést do main; tenant availability přes feature/rights/config. |
| Web client source/tests | promote/generalize | Přenést do main, včetně HM product type description testu. |
| SQL functions/tables/tests | promote | Jedna čistá schema reprezentace v main; ověřit permissions a callers. |
| Supabase migrations/Edge Functions | promote, deploy pending | Zachovat timestamp/order; žádné nasazení v tomto tasku. |
| MapLibre vendored packages and generic map runtime | promote if reachable | Ověřit dependency/registraci; jinak smazat jako dead artifact. |
| CSM map manifests/bundles/style data | tenant-overlay | Zachovat v CSM namespaced boundary; shared loader patří main. |
| PWA/offline shell algorithms | promote/generalize | Odstranit hardcoded CSM assumptions; testovat tenant matrix. |
| CSM logos/fonts/icons/AASA values | tenant-overlay/generated | Assets/config zůstávají CSM; generované identities nejsou ručně editovatelné. |
| HM Cerebri fonts/logos/icons | tenant-overlay/generated | Totéž pro HM. |
| Store screenshots/listing/legal content | tenant-overlay | Nástroje/šablony shared, obsah namespaced/branch-owned. |
| `database/recovery/*csmostrava*` | retained tenant boundary | Není migration; označit a vyloučit z automatic runners. |
| General Android/iOS release automation | promote/generalize | Parametrizovat profile/project/listing paths. |
| CSM release numbers/submission evidence | tenant-overlay/operational-only | Nepřenášet jako main runtime verzi. |
| CSM deletion of generic GitHub workflows | obsolete divergence | Obnovit main-owned workflow nebo nahradit parametrickým main workflow. |
| Revert/reapply PWA sequence | obsolete-by-revert + promote survivor | Main dostane jen konečný behavior a regression tests, ne dosažitelnou starou cestu. |
| HM old duplicated fixes and test-only commits | already-equivalent/obsolete | Zachovat jen chování, které není v main; odstranit branch implementation. |
| Current dirty speaker/occasion/order work | promote after topic verification | Rozdělit dle capability, testovat a přenést do main; nic nezahodit. |

## Deletion ledger

| Artifact | Current role | Final action | Removal proof |
|---|---|---|---|
| Branch-only edits v `lib/**`, `web_client/src/**`, `database/functions/**`, `supabase/functions/**` | Paralelní implementace | Přenést/generalizovat do main, potom obnovit produkční shared stromy přesně z main | drift gate nad výslednými tips vrátí nulu mimo overlay |
| HM tree-level odstranění reception/logout/migrations proti main | Source-absence feature gating | Obnovit společné moduly; UI/runtime gate ponechat v canonical feature/permission vrstvě | soubory i testy existují v obou branchech; feature-off test skrývá/zakazuje entry point |
| Ruční tenant hodnoty uvnitř společné logiky/template souborů | Skrytá konfigurace | Přesunout do `project.conf`, template/generovaného leafu nebo build outputu | focused `rg` + config matrix bez stale identity |
| CSM-specific assertions v obecných PWA testech | Tenant coupling | Parametrizovat; tenant-specific fixture přesunout do overlay matrix | `rg -i 'csmostrava|CSM'` ve shared test paths má jen explicitní fixture references |
| Branch-specific `.github/workflows` deletion/copy | Divergentní release infrastruktura | Jeden parametrický workflow v main; branch config určuje target | diff gate a workflow fixture test |
| Duplicate/reverted PWA implementations z commitů `6426ae1ec` až `a726d63fc` | Historická alternativní cesta | Zachovat pouze konečný survivor; odstranit fallback/obsolete tests/docs | symbol/route/cache-name absence search + offline tests |
| Branch-only product description mapping | Omylem umístěná HM oprava na CSM | Přesunout test+fix do main; produkční branche zdědí | main test red-before/green-after; žádný branch-only diff v souboru |
| Ručně editované generated `app_config`, theme, native identity, manifests | Reprodukovaný tenant stav | Izolovat generated leafs nebo generovat do buildu; zakázat hand edits | dva config runs jsou idempotentní a `git diff` odpovídá manifestu |
| Private security/provisioning values ve Festapp history, fixtures nebo logs | Nesprávné repo vlastnictví a leak risk | Přesunout source-of-truth do private configuration repository/secret manageru; historii nepřepisovat v tomto plánu a existující leak řešit incident/rotation postupem | secret scan + owner/rotation report bez uvedení hodnot |
| Staré branch planning docs `HVEZDAMORSKA-PLAN.md`, `HANDOFF-hvezdamorska.md` | Historický návod, potenciálně zavádějící | Archivovat s označením superseded nebo odstranit, pokud neobsahují unikátní provozní fakta | focused doc search neodkazuje na starý workflow jako aktuální |
| Nezařazené CSM/HM commits | Neznámá reachability | Žádné nesmí zůstat; doplnit ledger status a důkaz | ledger checker: všechny SHAs ve fixed ranges jsou právě jednou klasifikované |
| Backup/recovery branches | Bezpečnostní návratový bod | Dočasně zachovat jako explicitní boundary | uvedené refs existují do post-release sign-off; nejsou build/deploy targets |

## Implementation waves

### Wave 0 — Freeze, safe workspace and immutable inventory

**Goal and invariant gained**

Žádná lokální/remote práce se neztratí a všechny další změny vzniknou proti
ověřenému fixed pointu.

**Changes**

1. Spustit read-only `git fetch --all --prune` a zaznamenat lokální/remote SHAs
   pro `main`, `prod/csmostrava2026`, `prod/hvezdamorska` a relevantní backup
   refs do ledgeru.
2. Zaznamenat `git worktree list --porcelain`, stav každého worktree a ahead/
   behind počty. Nezasahovat do současného dirty CSM worktree.
3. Vytvořit bezpečný snapshot manifest současné práce bez změny worktree:
   `git diff --binary` pro tracked změny, `git ls-files --others --exclude-standard`
   pro untracked cesty a SHA-256 každého untracked souboru. Snapshot nesmí
   vypisovat obsah credential/config souborů a uloží se mimo repozitář do nového
   task-specific adresáře z `mktemp -d`; jeho cestu zapsat do ledgeru. Současný
   worktree zůstává primární kopií až do potvrzeného přenesení všech topiců.
4. Každou položku snapshotu zařadit do topic bucketu `occasion permissions`,
   `speakers counseling`, `order command identity`, `HM product description`,
   `plan artifacts`, `other user work`. Pro každý bucket zaznamenat cílovou main
   větev/commit nebo explicitní `retained-unmigrated`; nic nesmí zůstat pouze v
   nepojmenovaném patchi.
5. Vytvořit nový clean integration worktree/branch z aktualizovaného lokálního
   `main`, například `cutover/unified-main-prod-branches-20260823`. Nevytvářet
   commit ani remote branch bez souhlasu.
6. Ještě před další editací zkopírovat tento plán a execution prompt z
   `<repo-root>/docs/plans/` do stejné relativní cesty v novém
   integration worktree a ověřit jejich SHA-256. Tato dvojice je první součást
   main candidate, nikoli ručně znovu vytvořený dokument.
7. Ověřit, že backup refs pokrývají pre-sync tips. Pokud remote backup chybí,
   pouze navrhnout jeho push a vyžádat autorizaci.
8. Získat přesný locator `private configuration repository`. Pokud je dostupný, pouze read-only
   načíst jeho repository instructions a současný public handoff contract;
   nevypsat secret soubory ani jejich obsah. Pokud dostupný není, zapsat blocker
   a pokračovat jen Festapp-side prací, která žádné private values nepotřebuje.

**Failure and compatibility**

- Pokud fetch ukáže divergence na obou stranách, žádný rebase/reset. Nové
  commity se přidají do ledgeru.
- Untracked soubory nelze obnovit z Git; pouhý seznam nestačí. Do přenesení je
  chrání nedotčený původní worktree + hashovaný snapshot manifest.

**Validation**

- `git status --short` v integračním worktree je prázdný.
- Ledger obsahuje všechny tři local/remote tips, hashovaný dirty inventory a
  přiřazený cíl každého topic bucketu.
- SHA-256 plánu a promptu je stejný v původním a integračním worktree.
- Ledger obsahuje stav `private configuration repository`: exact locator/instructions read, nebo
  explicitní unresolved blocker bez vymyšlené struktury.

**Exit condition**

Existuje čistý integrační worktree a jednoznačný, neztrátový fixed-point záznam.

### Wave 1 — Complete divergence and reachability ledger

**Goal and invariant gained**

Každý CSM/HM rozdíl má rozhodnutý osud; implementace se neopírá o názvy commitů
nebo pouhé ancestry.

**Changes**

1. Vygenerovat machine-readable seznam všech SHA v:
   - `main..prod/csmostrava2026`;
   - `main..prod/hvezdamorska`;
   - lokální-ahead ranges proti příslušným origin refs.
2. Použít `git range-diff`, `git cherry`, tree diffs a path history k párování
   main `d071cdd16` s CSM `90e7819da`; každou zdánlivě ekvivalentní capability
   potvrdit source diffem nebo testem.
3. Projít runtime entry points, registry a string dispatch pro:
   routes, feature metadata, RPC calls, Edge endpoints, workers, PWA cache,
   platform plugins, scheduled/deploy scripts a release workflows.
4. Pro každou CSM změnu po `90e7819da` explicitně zařadit konečný efekt, včetně
   revert/reapply sekvence. Reverted intermediate behavior není candidate k
   promoci.
5. Pro HM historické vlastní commity ověřit zejména Fakturoïd, smlouvy,
   currencies, R2 multi-instance a form-specific změny. Každý behavior buď
   existuje v main, přesune se do main, zobecní se, nebo se popíše jako externí
   boundary.
6. Vytvořit počáteční overlay manifests pouze z prokázaně tenant-specific
   souborů; neudělovat povolení celým adresářům jako `lib/`, `database/`,
   `supabase/` nebo `web_client/src/`.

**Migration/deletion**

- Žádná source migrace zatím. Nezařazené SHA jsou blokující položkou pro další
  wave dané capability.

**Validation**

- Ledger coverage script porovná `git rev-list` s ledgerem a selže pro missing
  nebo duplicate SHA.
- Path inventory nemá žádný shared source path bez vlastníka a cílové akce.

**Exit condition**

100 % divergentních commitů je právě jednou klasifikováno a každá runtime
capability má známý canonical/overlay cíl.

### Wave 2 — Prove and harden the tenant configuration boundary in main

**Goal and invariant gained**

Main umí vyrobit Festapp, CSM i HM identitu bez změny shared business logiky a
bez stale hodnot předchozího tenanta.

**Changes**

1. Z čistého exportu `BASE_MAIN_SHA` třikrát spustit současný
   `automation/apply_config.sh` s Festapp/CSM/HM fixtures a instrumentovat jeho
   skutečnou write-set přes pre/post `git diff --name-only` a hashes. Do
   `generated.paths` patří sjednocení skutečně měněných cest; neočekávaná cesta
   je nejprve chyba k vysvětlení, ne automaticky nový allowlist záznam.
2. Zavést canonical replay checker. Ten:
   - vytvoří dočasný čistý tree přes `git worktree add --detach` nebo
     `git archive` z recorded `BASE_MAIN_SHA`;
   - načte main-owned overlay manifest/checker pomocí `git show BASE_MAIN_SHA:...`;
   - aplikuje pouze povolené tenant source inputs/assets z produkční branche;
   - spustí `apply_config.sh` s explicitní config cestou;
   - porovná všechny generated outputs byte-for-byte s produkční branchí;
   - ověří, že všechny ostatní shared paths jsou byte-identické s main;
   - dočasný tree bezpečně odstraní přes přesnou task-specific cestu.
3. Zachovat veřejné CLI `./automation/apply_config.sh`. Rozdělit jej na menší
   generátory jen podle skutečných write boundaries z kroku 1; nepřepisovat
   bez důkazu fungující části pouze kvůli estetice.
4. U každého outputu, který míchá config a sdílenou logiku, rozhodnout podle
   konkrétního rizika:
   - pokud mutátor mění jednoznačně validované pole a replay test dokáže zbytek
     souboru shodný s main, ponechat strukturu;
   - pokud regex může spolknout/zakrýt logiku nebo tenant branch potřebuje ruční
     změny ve stejném souboru, oddělit stable logic a config-only leaf;
   - Android/iOS `.xcconfig`, properties, manifest placeholders nebo build-output
     generation zavést jen pro soubory, které druhou podmínku skutečně splní.
5. Přidat schema/validator pro všechny required a optional config keys,
   validaci odkazovaných assets, URL, IDs, languages, colors a numeric budgets.
6. Přidat sanitized matrix fixtures pro `festapp`, `csmostrava2026` a
   `hvezdamorska`. Live anon keys se neassertují verbatim; ověřuje se project ref
   a absence cross-tenant tokenů.
7. Učinit generování idempotentní: fresh template → tenant A → fresh template →
   tenant B. Nikdy B nad už vygenerovaným A jako source template.
8. `configure_fonts.js`, version sync, PWA budget a release scripts napojit na
   stejný explicitní config input.
9. `generated.paths` a oba tenant `.paths` číst pouze z main SHA. Přidat negativní
   test, ve kterém produkční branch upraví vlastní kopii `.paths` nebo checkeru;
   kontrola musí změnu odmítnout, ne použít podvrženou politiku.
10. Inventarizovat pouze názvy a zdroje required private inputs používaných build,
    deploy a release skripty. V main vytvořit veřejné schema a fiktivní fixtures;
    skutečné hodnoty ani jejich hashes nekopírovat. Integraci s private configuration repository měnit
    jen po odblokování druhého repa a podle jeho vlastních instrukcí.

**Migration/deletion**

- Odstranit pouze regex/sed větve, u kterých write-set/replay prokáže, že mohou
  mutovat shared logiku nebo ponechat stale tenant hodnotu.
- Odstranit implicitní branch-name detection, pokud existuje.
- Veřejný wrapper `./automation/apply_config.sh` zůstává canonical entry point;
  nejde o dočasný adapter, dokud na něj odkazují Quick Reference, CI a runbooky.

**Failure and compatibility**

- Build s chybějícím tenant leafem musí dát srozumitelnou chybu nebo použít
  explicitně zvolený neutral development profile; nesmí náhodně použít poslední
  vygenerovaný tenant.
- Bundle IDs, app groups a PWA `id=/` jsou veřejné update contracts; zachovat
  dnešní hodnoty každého tenanta.

**Validation**

- Rozšířený `bash automation/tests/apply_config.test.sh` přes tři fixtures.
- Nový idempotence/cross-tenant test porovná hashes outputs a zakáže stale CSM
  token v HM outputu a naopak.
- Canonical replay test dokáže exact content, nejen path allowlist.
- Negativní tamper test pro `.paths`, checker a ručně změněný generated output.
- Secret scan nad plánovaným diffem a test, že chybějící private input končí
  fail-closed bez vypsání hodnoty.

**Exit condition**

Tři tenant profily lze deterministicky reprodukovat z přesného main SHA; každý
branch diff je buď main-owned-policy-approved source overlay, přesně vygenerovaný
output, nebo explicitní namespaced operational data. Žádný spekulativní native/
web config refactor nezůstává bez testem prokázané potřeby.

### Wave 3 — Promote shared platform and application behavior from CSM

**Goal and invariant gained**

Main obsahuje úplný konečný CSM-derived shared behavior, nikoli pouze release
agregát z 2026-08-06.

**Changes by coherent slice**

Pro každý slice se vychází z main candidate a CSM slouží jako donor, nikoli jako
nový branch základ. Postup je vždy: vypsat exact path diff main↔CSM, načíst
ledger statuses, přenést pouze `promote/generalize` paths nebo jednotlivé hunks,
znovu aplikovat případný main-only survivor a zkontrolovat resulting diff proti
oběma zdrojům. Release aggregate commit se nikdy cherry-pickne celý. Pokud jeden
soubor míchá shared a tenant změnu, přenáší se po symbolu/hunku a doplní se test;
nesmí se obejít klasifikace restorem celého adresáře.

1. **Map platform:** aktivní vendored MapLibre packages, platform registrace,
   offline downloader, bundle manager/configuration, public map host/session,
   viewport/scene controllers, icon rasterization, path/place UI a external
   navigation. Nejdřív potvrdit aktivní dependency; nepřenášet dead package.
2. **Offline/PWA:** konečný survivor z offline shell/revert/reapply série,
   atomic update prompt, cache reconciliation, storage bridge, cold-start
   recovery a cache budget. Hardcoded CSM sizing/occasion přesunout do fixture
   nebo config.
3. **Sync/runtime:** authoritative client projections, stores, reconnect,
   publisher/worker contracts, activity metrics a cache hydration.
4. **Admin/shared UI:** feedback deletion/export, activity range, cleaning
   updates, grid mutation/version behavior, event/place mutations, news,
   information and search behavior.
5. **Schedule:** current weekday selection, after-midnight ordering, saved
   program state, timetable/light timeline a map session preservation.
6. **Authentication/reception/users:** reception QR flow, companion management,
   logout/login feedback, email identity and notification contracts. Vše zůstane
   feature/permission-gated, nikoli odstraněné z HM.
7. **Generic release infrastructure:** guarded Android release workflow, Apple
   helpers, reproducible builds, deploy safety a generic store tooling;
   tenant listing/submission evidence zůstane overlay.
8. **Current dirty topics:** po jednom přenést occasion permissions, speaker
   counseling deletion, order command identity a HM product description do
   main se svými testy. Před přenosem porovnat s případnými stejnojmennými
   feature branches a nesloučit dvě varianty.

Každý slice se přenáší behaviorálně: nejprve owning test seam, potom survivor
implementation, potom absence staré větve. Nevytvářet adapters jen kvůli
historickým tenant branchím, protože ty budou v následujících waves cut over.

**Migration/deletion**

- Zachovat jen konečné PWA/cache/map implementace; odstranit reachability na
  revertované fallbacky.
- Všechny relevantní main tests aktualizovat na konečný contract, ne na CSM copy.

**Failure and compatibility**

- Offline cache/PWA změny musí zachovat update stávajících instalací.
- Mapy musí mít explicitní fallback pouze tam, kde představuje reálnou
  platform capability, ne starou paralelní business implementaci.
- Auth/reception chyby musí zůstat tenant-safe a permission checks server-side.

**Validation**

- Po každém coherent slice jeho targeted tests; nerunovat celý suite po každém
  souboru.
- Focused absence searches z deletion ledgeru.
- Na konci wave společný web/Flutter/Deno/SQL targeted batch pro dotčené oblasti.

**Exit condition**

Každý ledger item `promote`/`generalize` má cílový main commit, passing owning
test a nulovou starou reachability.

### Wave 4 — Canonical database, Edge and worker history

**Goal and invariant gained**

Main má jedinou schema/permission/write contract historii pro oba produkční
tenanty a všechny nové runtime callers.

**Changes**

1. Porovnat `database/tables`, `database/functions`, `database/tests`,
   `supabase/migrations`, `supabase/functions` a workers proti ledgeru.
2. Přenést committed i schválené current dirty forward migrations v původním
   pořadí. Nezaměňovat clean-install files za production migration contract.
3. Pro každou RPC/Edge změnu najít všechny Dart/JS/Deno callers přes
   `supabase.rpc`, `functions.invoke`, route names a tests.
4. Ověřit `SECURITY DEFINER`, grants, RLS, cross-tenant scoping, retry a
   idempotence podle architektonických pravidel.
5. U CSM/HM společného projektu připravit jeden budoucí deployment manifest s
   expected target ref a migration list; nespouštět jej.
6. Recovery SQL z CSM nepromovat do `supabase/migrations`; zachovat ho pod
   explicitně neautomatickým path a dokumentovat target/incident.
7. Pro budoucí live preflight použít `SUPABASE_URL` z konkrétního tenant configu.
   CSM musí navíc potvrdit `FORCE_OCCASION_LINK=csmostrava2026`. HM má aktuálně
   prázdný `FORCE_OCCASION_LINK`, proto se před jakýmkoli live čtením/zápisem
   musí explicitně zadat schválený occasion nebo ověřit organization `4`; zákaz
   hledání „správných dat“ v jiném projektu platí stejně.

**Migration/deletion**

- Odstranit duplicate/older SQL writers nebo Edge branches, jakmile všichni
  callers používají canonical contract.
- Neodstraňovat aplikovanou migration history.

**Failure and compatibility**

- Rollback source nesmí obnovit starého writera. Produkční rollback po budoucím
  deployi musí být samostatná forward oprava.
- Pokud live schema drift není možné ověřit read-only, reportovat přesný pending
  preflight; nehádat.

**Validation**

- Disposable local baseline DB + všechny dotčené SQL testy.
- Deno tests pro Edge functions.
- Focused ACL/call graph/absence searches.
- Žádný production connect/write v rámci této wave.

**Exit condition**

Main clean install, forward migrations, callers a test contracts se shodují;
budoucí deployment manifest je připraven, ale neaplikován.

### Wave 5 — Isolate CSM overlay and eliminate CSM hardcoding

**Goal and invariant gained**

Veškerý CSM-only obsah je explicitní data/config boundary; žádná CSM-specific
business implementation nezůstává v shared code.

**Changes**

1. Zachovat CSM hodnoty `project.conf`, domain, organization, Supabase ref,
   OneSignal, bundle/app IDs, forced occasion, theme/font a PWA budgets.
2. Zachovat/namespacovat CSM logos/icons/fonts, offline-map manifests/style,
   legal texty, store metadata/screenshots, release evidence a recovery docs/SQL.
3. Generic části release/offline-map/store tooling přesunout do main; data paths
   předávat argumentem/configem.
4. Odstranit CSM hostname/logo/occasion literal ze shared source a tests mimo
   explicitní matrix fixtures.
5. Obnovit main-owned CI/deploy workflow; CSM target selection jde přes config,
   nikoli smazaný workflow.
6. Finalizovat `csmostrava2026.paths` na nejmenší praktickou množinu.

**Migration/deletion**

- Smazat duplicate generic scripts/docs z overlay; CSM runbook může odkazovat
  na main tool.
- Nechat historical store/recovery data mimo runtime/build, pokud build je
  nepotřebuje.

**Validation**

- `rg -i 'csmostrava|csm ostrava|jm2025'` v shared runtime paths; každý match je
  fixture, namespaced data nebo chyba.
- Drift checker na syntetickém main+CSM overlay stromu.
- Config/build preflight bez deploye.

**Exit condition**

CSM overlay manifest vysvětluje každý zbývající tree diff a shared paths jsou
byte-identické s main.

### Wave 6 — Normalize HM-specific behavior and overlay

**Goal and invariant gained**

HM získá nový shared code bez ztráty brandingu, veřejné identity, platebních a
externích integrací.

**Changes**

1. Zachovat HM config: organization 4, shared Supabase ref, languages `cs,en`,
   all-unit behavior, domain, OneSignal, bundle IDs, theme a Cerebri assets.
2. Auditovat historické HM-specific paths/commits: Fakturoïd, smlouva, currency,
   R2 multi-instance, web form behavior a release identity.
3. Přenést obecné chování do main; skutečný externí adapter ponechat jako
   jedinou tenkou boundary implementaci v main, aktivovanou config/feature.
4. Obnovit všechny shared reception/auth/schedule/sync/DB soubory z main.
   Tenant-disabled feature se ověřuje negativním testem, ne smazáním kódu.
5. Přesunout product type description fix/test do main a ověřit přes raw tvar
   `get_form_by_link`; odstranit branch-only modifikaci.
6. Finalizovat `hvezdamorska.paths`.

**Migration/deletion**

- Odstranit staré duplicated HM implementations a test-only/debug artefakty,
  pokud ledger nepotvrdí aktivního consumera.
- Supersede staré HM plan/handoff docs.

**Failure and compatibility**

- Zachovat existující app IDs, auth storage scope, domain a store update
  continuity.
- Platební/Fakturoïd behavior musí mít targeted regression tests před odstraněním
  staré větve.

**Validation**

- HM config matrix a targeted forms/orders/Fakturoïd tests.
- Focused runtime search pro HM literals mimo config/fixtures/assets.
- Drift checker na syntetickém main+HM overlay stromu.

**Exit condition**

HM overlay obsahuje jen schválené config/assets/operational data a jeho shared
runtime strom je identický s main.

### Wave 7 — Main integration and complete verification

**Goal and invariant gained**

Kanonický main candidate je interně konzistentní a připravený k branch cutoveru.

**Changes**

1. Aktualizovat architecture/readme/runbooks: main-first workflow, overlay
   contract, generator usage, migration targeting a drift remediation.
2. Aktualizovat generated AutoRoute/JSON outputs pouze canonical commands;
   generated files neupravovat ručně.
3. Zkontrolovat dependency locks a vendored packages.
4. Spustit adversarial pass: routes, registries, RPC strings, feature metadata,
   workers, scheduled jobs, retries, fallbacks, aliases, old cache names a docs.
5. Spustit repository-approved secret scanner, pokud existuje; jinak focused
   names/pattern scan a staged-diff review bez vypisování nalezených hodnot.
   Nález skutečného tajemství je incident/blocker: zastavit publikaci, nechat
   hodnotu zrotovat přes private configuration repository proces a nepřidávat ji do reportu.
6. Připravit logické commits a před každým commitem podle `CONTRIBUTING.md`
   ukázat staged status a vyžádat souhlas.

**Validation**

Protože současný `automation/test_all.sh` některé web/Flutter failures pouze
vypisuje jako warning, nesmí být jediným zeleným důkazem. Spustit komponentní
gates přímo a propagovat non-zero:

```bash
cd web_client && npm test
cd .. && fvm flutter test
find supabase/functions -type f \( -name '*_test.ts' -o -name 'test_*.ts' \) -print0 \
  | xargs -0 deno test --allow-env --allow-net --allow-read
bash automation/tests/apply_config.test.sh
./automation/test_all.sh db automation
```

DB command se spouští pouze proti disposable local baseline. Po focused opravě
spustit celý relevantní gate jednou; nepovažovat skipped DB/integration za pass.

**Exit condition**

Main candidate prochází všemi dostupnými standard gates, každý skip je uveden s
důvodem, deletion ledger má absence proof a pracovní strom obsahuje pouze
očekávané plánované změny.

### Wave 8 — Forward-only cutover `prod/csmostrava2026`

**Goal and invariant gained**

Aktuální CSM branch má historii zachovanou, ale strom je nový main plus přesně
CSM overlay.

**Changes**

1. Po autorizovaném main commitu/merge vytvořit clean CSM cutover worktree z
   aktuálního CSM tipu; ověřit remote se od Wave 0 nezměnil.
2. Zaznamenat pre-cutover backup ref; remote push pouze po souhlasu.
3. Připojit nový main forward merge commitem, pokud není ancestor. Konflikty
   neřešit plošným `ours`; shared path má vždy main obsah, overlay path CSM obsah.
4. Main-owned manifest načíst příkazem ekvivalentním
   `git show "$BASE_MAIN_SHA":automation/tenant-overlays/csmostrava2026.paths`;
   nikdy nepoužít kopii pravidel z CSM tipu.
5. Sestavit expected CSM tree v dočasném čistém worktree: main tree + povolené
   source/data overlay cesty z pre-cutover CSM tipu + fresh config generation.
   Teprve tento expected tree aplikovat do CSM worktree. Není dovoleno nejprve
   ponechat starý CSM strom a pouze z něj mazat známé rozdíly.
6. Pro všechny shared paths explicitně obnovit tree z přesného main SHA. Generated
   output převzít pouze z expected replay tree, nikdy ze staré branch jako source.
7. Přidat `automation/tenant-overlay.json` s tenant ID a recorded
   `BASE_MAIN_SHA`; schema/policy tohoto souboru vlastní main.
8. Spustit drift/config/targeted build checks. Připravit cutover commit a čekat
   na autorizaci commit/push.

**Migration/deletion**

- Tímto forward commitem se z current CSM tree odstraní všechny branch-only
  shared implementations. Historie zůstává dosažitelná přes parent/backup,
  runtime nikoli.

**Failure and compatibility**

- Žádný force push.
- Neaktualizovat version/store evidence automaticky, pokud cutover není release.
- Neaplikovat DB migrations ani deploy.

**Validation**

- `automation/check_tenant_branch_drift.sh "$BASE_MAIN_SHA" csmostrava2026`.
- CSM config generation twice/idempotence.
- Targeted Flutter web + web client build preflight, pokud standard gate dovolí;
  žádný upload.

**Exit condition**

CSM cutover commit má nový main jako parent/ancestor, drift gate načtený z main je
zelený a actual CSM tree je byte-for-byte stejný jako fresh expected replay tree.

### Wave 9 — Forward-only cutover `prod/hvezdamorska`

**Goal and invariant gained**

HM branch má stejný shared main SHA jako CSM a zachovaný pouze HM overlay.

**Changes**

Stejný expected-tree postup jako Wave 8 s HM tipem a main-owned
`hvezdamorska.paths`. Zvlášť ověřit:

- product type description test a vykreslení pod `Platby, zálohy:`;
- HM domain/app IDs/OneSignal/AASA/auth storage key;
- organization 4 a all-unit/multilingual behavior;
- Fakturoïd/order integration;
- absence CSM forced occasion, logos, fontu, PWA cache identity a store metadata.

**Migration/deletion**

- Odstranit z HM current tree všechny starší shared copies, včetně souborových
  odstranění používaných jako feature gating.

**Validation**

- `automation/check_tenant_branch_drift.sh "$BASE_MAIN_SHA" hvezdamorska`.
- HM config generation twice/idempotence.
- `node --test web_client/tests/forms/product_type_description.test.js` plus
  targeted payment/Fakturoïd tests.
- Build preflight bez uploadu.

**Exit condition**

CSM a HM deklarují stejný main SHA, oba drift gates jsou zelené a HM-specific
observable behavior je zachováno testy/configem.

### Wave 10 — CI enforcement, handoff and operational readiness

**Goal and invariant gained**

Drift se nemůže tiše vrátit a budoucí práce má jednoznačnou cestu.

**Changes**

1. Přidat CI job pro production branches:
   - načíst a schema-validovat branch `automation/tenant-overlay.json`;
   - fetch recorded canonical main SHA a ověřit jeho ancestry/approval;
   - načíst allowlist, checker a config schema přes `git show` z tohoto main SHA;
   - sestavit fresh expected tree a porovnat jej byte-for-byte s branch tree;
   - overlay path diff a generated content proof jsou odvozené z tohoto replay,
     ne z branch-owned skriptu;
   - forbidden branch-only shared code check;
   - config identity matrix.
2. Přidat PR/release checklist: shared změna musí odkazovat na main commit;
   overlay změna musí uvést manifest entry a důvod.
3. Dokumentovat běžný upgrade produkční branche: merge main, apply config,
   drift gate, targeted tests, release verification dle potřeby.
4. Vytvořit cutover report s final SHAs, commit ledger coverage, retained
   boundaries, test results, skips a unapplied deploy/migrations.
5. Backup branches označit removal condition: smazat až po samostatně schváleném
   úspěšném release a observačním okně obou tenantů.
6. Zdokumentovat Festapp↔private configuration repository handoff: public schema version, odpovědnost
   za hodnoty, fail-closed behavior a samostatně autorizovaný update postup.
   Pokud druhé repo zůstane nedostupné, reportovat tuto část jako exact blocker,
   ne jako hotovou integraci.

**Validation**

- Negativní fixture úmyslně změní shared file v prod branch modelu a CI gate
  musí selhat.
- Negativní fixture ručně změní generated identity a content proof musí selhat.
- Negativní fixture změní branch kopii allowlistu/checkeru nebo podvrhne
  `BASE_MAIN_SHA`; CI musí selhat před použitím branch politiky.
- Dokumentovaný fresh-worktree rehearsal obou tenantů projde bez ruční editace.

**Exit condition**

Cutover report je úplný, CI blokuje nelegální drift a jedinými neprovedenými
kroky jsou explicitně autorizované production deploy/push/release actions.

## Rollout and rollback

### Source rollout order

1. Dokončit a ověřit main candidate.
2. Po souhlasu commitnout/merge main.
3. Zmrazit jeden přesný `BASE_MAIN_SHA` pro oba tenant cutovers. Pokud se main
   před dokončením HM změní, nepoužívat různá base SHAs: nový commit zařadit do
   ledgeru a zopakovat expected-tree/drift ověření pro oba tenanty.
4. Cut over CSM branch, ověřit bez deploye.
5. Cut over HM branch, ověřit bez deploye.
6. Před každým prod cutover commitem znovu ověřit, že remote tip je totožný s
   Wave 0/aktualizovaným ledgerem. Při změně abortnout commit, nepřepisovat tip.
7. Zapnout CI drift gates. Nastavení required status checks/branch protection je
   externí operace a vyžaduje samostatné oprávnění; bez ní report nesmí tvrdit,
   že gate nelze obejít.
8. Teprve v samostatném release tasku naplánovat shared DB/Edge deploy a tenant
   client releases.

CSM jde před HM pouze proto, že je zdrojem většiny nového behavior a jeho
overlay klasifikace je již součástí promování. HM release nesmí začít, dokud
jeho branch nemá stejný verified main SHA.

### Rollback limits

- Před commitem: zahodit lze pouze čistý integrační worktree/branch; nikdy
  současný uživatelský dirty worktree.
- Po main commitu, před prod cutoverem: main lze opravit novým forward commitem;
  historie se nepřepisuje.
- Po prod cutover commit, před deployem: produkční branch lze vrátit novým revert
  commitem na pre-cutover tree, backup refs zůstávají.
- Po budoucím deployi: rollback je tenant/release-specific forward operation.
  DB schema se neodstraňuje a stará paralelní business implementation se
  neobnovuje.
- Backup refs nejsou dlouhodobý alternativní release source. Jejich jediný účel
  je časově omezené zotavení.

## Verification strategy

| Risk or invariant | Verification seam | Command/observation |
|---|---|---|
| Všechny divergentní commits rozhodnuty | ledger coverage | `git rev-list` proti machine-readable ledger exportu |
| Shared source stejný | branch drift gate | `automation/check_tenant_branch_drift.sh "$BASE_MAIN_SHA" "$TENANT_ID"` |
| Branch nemůže oslabit policy | main-owned policy replay | tamper fixture pro `.paths`, checker a base SHA |
| Generated config deterministický | config matrix/idempotence | rozšířený `automation/tests/apply_config.test.sh` |
| Žádný cross-tenant identity leak | fresh-template A/B matrix | forbidden project ref/domain/app ID/token assertions |
| HM product description | raw RPC model → renderer | `node --test web_client/tests/forms/product_type_description.test.js` |
| Flutter behavior | owning unit/widget tests | `fvm flutter test` |
| Web behavior | Node/JSDOM tests | `cd web_client && npm test` |
| SQL contracts/permissions | disposable baseline DB | direct DB runner / `./automation/test_all.sh db` s explicitním local `DATABASE_URL` |
| Edge behavior | Deno tests | direct `deno test` se všemi `_test.ts`/`test_*.ts` |
| PWA offline/update survivor | automation tests | focused PWA offline/reconcile/update tests |
| Map platform reachability | dependency/import/platform tests | pubspec/import search + relevant Flutter/platform tests |
| Tenant build viability | build preflight | config + Flutter web/web client build bez uploadu |
| Public identity preserved | manifest/plist/AASA inspection | generated content assertions pro každý tenant |
| No old paths/fallbacks | deletion-ledger searches | focused `rg` pro old symbols/cache names/routes/branch literals |
| No user work lost | pre/post inventory | dirty topic ledger a presence všech patches/tests v main nebo retained worktree |
| No secret/security material leak | staged/tree scan + public input schema tests | scanner/focused scan bez logování hodnot; missing-input fail-closed test |
| private configuration repository boundary | cross-repo contract/readback | exact locator/instructions + public schema version, nebo explicitní blocker |
| Production state | separately authorized readback | pending; není podmínkou source cutoveru, musí být v reportu jako unapplied |

## Definition of complete

- [ ] Ledger klasifikuje všechny divergentní a local-ahead commits bez mezer.
- [ ] `main` obsahuje všechny aktivní tenant-neutral CSM a HM capabilities.
- [ ] Oprava popisu HM formuláře je v main a prochází regresním testem.
- [ ] CSM/HM features používají shared implementation + feature/config/rights,
      nikoli source absence nebo branch condition.
- [ ] DB/Edge/worker contracts a migrace mají jediného vlastníka v main.
- [ ] Tenant generator je deterministický, idempotentní a nezasahuje shared logic.
- [ ] CSM a HM overlays mají minimální explicitní manifests.
- [ ] Obě produkční branche jsou forward-only cut over na stejný verified main SHA.
- [ ] Drift gate pro obě branche načítá policy z main, sestaví fresh expected
      tree a prokáže byte-for-byte shodu actual branch tree.
- [ ] Všechny deletion-ledger položky jsou odstraněné nebo mají pojmenovanou
      boundary, consumera a removal condition.
- [ ] Standard test gates prošly; skipped externí/live checks jsou přesně uvedené.
- [ ] Nebyl proveden force push, production deploy, DB write ani store release bez
      samostatného souhlasu.
- [ ] Dokumentace popisuje main-first workflow a CI ho vynucuje.
- [ ] Festapp neobsahuje nová private security data; public input schema a
      fail-closed validation jsou v main a private configuration repository ownership je doložené
      nebo přesně blokované.
- [ ] Cutover report obsahuje výsledná SHAs a unapplied operational steps.
- [ ] Stav external required checks/branch protection je buď read-backem ověřen,
      nebo přesně uveden jako neprovedený autorizovaný provozní krok; není
      implicitně považován za hotový.

## Residual risks

- Historie CSM obsahuje velké map/store artefakty. Forward-only cutover zmenší
  current diff, ale nezmenší existující Git historii; případné history filtering
  je samostatná destruktivní iniciativa mimo tento plán.
- CSM/HM sdílejí Supabase projekt. Zdrojová unifikace nezaručuje, že live schema
  odpovídá repozitáři; před budoucím deployem je nutný read-only drift/preflight.
- Native bundle/signing a PWA identity jsou veřejné update contracts. Source
  testy snižují riziko, ale před release je stále nutná explicitní release-level
  kontrola podepsaných artefaktů a hosted AASA/PWA odpovědí.
- Některé historické HM commits mají neurčité názvy. Ledger je musí posoudit podle
  diffu a reachability; samotný subject není důkaz pro smazání.
