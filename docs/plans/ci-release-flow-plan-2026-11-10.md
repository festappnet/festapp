# Jedno ověření změny, rychlé předání do releasu Festapp

Datum: 2026-11-10
Stav: Lokálně implementováno v izolovaném worktree; nepublikováno. Provozní exit kritéria čekají na samostatné pověření.

Politika vlny 1 byla výslovně přijata uživatelem v navazující implementační session. Výsledek a hranice ověření: `ci-release-flow-RESULT-2026-11-10.md`.
Verification: standard - důvěryhodnost CI, souběh a produkční release kontrakt
Zdrojový bod: `32adbae3f29c6c628fa13cc78543dcca1d4a5255` na `origin/main`

## Výsledek a priorita

Zkrátit čas od dokončené změny do možnosti nasadit ji. Prioritou je odstranit opakované úplné ověřování a rozpor mezi postupy, nikoliv dál optimalizovat těla Flutter testů. Jedna změna má jedno úplné autoritativní ověření svých vstupů. Další fáze převezmou jeho důkaz a vykonají jen práci závislou na novém kontextu.

Cílový tok:

```text
vývoj + cílené lokální testy
    -> GitHub ověří změněné vstupy jednou
    -> PR/main převezme důkaz totožných vstupů
    -> main má všech 8 požadovaných zelených kontrol
    -> overlay vybraného tenantu + jeden produkční build
    -> ověření hotového artefaktu + deploy + živý smoke
```

Řeší se lokální vývoj, PR, main, výběr sad, build a jejich propojení s releasem. Výchozí produkční příklad je vstupenky.online, při realizaci se musí jeho branch/tenant ID zjistit z aktuální konfigurace, nikoliv odhadnout podle domény. Žádný rollout jiných tenantů není součástí plánu. Mimo rozsah: změna aplikace a obchodních pravidel, produkční DB migrace, nákup runnerů, přepis Flutter testů, nový CI server nebo obecný orchestrátor.

## Doložený výchozí stav

| Fakt | Zdroj | Dopad |
|---|---|---|
| Poslední lokální úplné ověření trvalo 502,68 s; následný GitHub běh 230 s | Lokální receipt `/Users/miakh/Library/Caches/festapp-ci/runs/20261110T190246-a5071f681abb/receipt.json`; [GitHub seat/ticket run](https://github.com/festappnet/festapp/actions/runs/42872724353) a dalších pěti workflows na stejném SHA | Přes 12 minut serializovaného čekání před případným tenant buildem. Lokální receipt je dirty vývojový důkaz, nikoliv přenositelná release atestace. |
| Předešlý GitHub běh trval 232 s, po poslední optimalizaci 230 s | [Předchozí run](https://github.com/festappnet/festapp/actions/runs/42868337020), nový run výše | Není prokázané zásadní zrychlení celé sady; neslibovat úsporu podle součtu dílčích kroků. SHA a zátěž se liší, nejde o kontrolovaný benchmark. |
| Repo vyžaduje lokální canonical mirror před publikací a GitHub kontrolu přesného main SHA před releasem | `AGENTS.md`, `CONTRIBUTING.md`, `docs/architecture/tenant_overlays.md` | Dvojí úplný běh byl vynucen politikou. Nejprve se musí vědomě změnit pravidla, ne obejít skript. |
| Osm jmen jobů představuje vstup do release gate | `automation/ci/checks.json`; `release_gate.py: problems/release_source` | Zachovat všech osm aktuálních zelených stavů i vazbu na přesný `baseMainSha`. |
| Výběr znovu používá jen úspěšné skutečně provedené main běhy do 7 dnů | `selection.py: reusable/decide`; `inputs.json` | PR výsledek nelze převzít do main. Změna, která se stále liší od main, může běžet znovu při každé aktualizaci PR. |
| Jsou dvě mapy závislostí a několik seznamů vstupů | `checks.json` jobs/steps/affectedInputs; `inputs.json` components; `run.py: affected`; `selection.py: fingerprint` | Lokální a hosted výběr mohou konzervativně vybírat jiné množiny. |
| Image worker typecheck a unit testy jsou totožné ve dvou jednotkách | `checks.json: image-policy/image-server-policy` | Jedna skutečná sada má mít jednoho vlastníka. |
| Produkční builder spouští celou zdrojovou startup sadu znovu | `build_web_bundle.sh` volá `test_web_startup.sh`; stejný příkaz vlastní CI `web-startup` | Součástí buildu je opakované zdrojové ověření včetně browserových scénářů. |
| Deploy gate se volá před buildem i před uploadem | `deploy_direct.sh` | Jde o levné ověření stavu, nikoliv nový běh osmi sad. Zachovat obě bezpečnostní hranice. |
| GitHub Deploy je pouze manuální alternativou, push tenantu ho nespouští | `.github/workflows/deploy.yml`; `automation/deploy_direct.sh` | Samotná existence workflow není důkaz dalšího automatického buildu. |
| Release skill nadále doporučuje GitHub dispatch | `/Users/miakh/source/development-tools/vendor/codex-skills/festapp-web-release/SKILL.md` | Pokyny se rozcházejí s repozitářem. Opravit i kanonický zdroj skillu a jeho instalaci. |

Čísla nejsou baseline výkonu všech produkčních releasů. Dosavadní evidence neodděluje jejich Flutter kompilaci, upload a health čekání; tento rozpad doplní první vlna z existujících logů nebo nejbližšího již autorizovaného releasu.

## Cílový kontrakt a rozhodnutí

1. `automation/ci/checks.json` zůstává vlastníkem jednotek, sad a zdrojových závislostí. `run.py` je vykonavatel, `selection.py` rozhoduje, zda vykonat nebo převzít důkaz. Nerozšiřovat tuto změnu na nový plánovací framework.
2. Běžný vývoj a publikace používají cílené lokální testy. Úplné autoritativní ověření proběhne na GitHubu. Ruční úplný lokální mirror zůstává dostupný pro diagnózu, offline práci a výslovný požadavek, ale nepřidává se automaticky před stejný úplný hosted běh.
3. PR před mergem musí mít požadované kontroly podle branch protection. Main převezme pouze prokazatelně totožné testovací vstupy, nikoliv prostě „zelený PR“. Konflikt, jiný merge výsledek nebo změna toolchainu znamenají nový běh dotčených sad. Přímý push do main vykoná dotčené sady, pokud stejný důkaz neexistuje.
4. Zachovat osm požadovaných check names na přesném releasovém main SHA. Zelený stav znamená buď úspěšné skutečné vykonání, nebo ověřenou referenci na původní úspěšné vykonání. Skipped/missing/pending/failed není úspěch. Nezavádět propagaci pouhých statusů ani řetězení převzatých důkazů.
5. Build vytváří tenant artefakt. CI vlastní zdrojové regresní testy. Produkční ověření vlastní kontroly hotového bundlu, tenant identity, CSP, právních dokumentů, aktivace backendu, verzí a reálného nasazeného webu. Odstranění zdrojového testu z builderu nesmí odstranit jeho scénáře z CI.
6. Jeden běžný release vstup je `automation/deploy_direct.sh`. GitHub Deploy zůstává pouze výslovně zvolený alternativní executor stejného builderu a gate, nikoliv další automatická fáze. Žádný automatický deploy všech tenantů po main pushi.
7. Při čekání jeden vlastník sleduje jeden run. Nesčítat redundantní vlastní smoke se smoke kanonického releasu. Neprovádět nový build při pouhém opakování uploadu stejného ověřeného artefaktu.

### Důkaz o vykonání a jeho životní cyklus

Rozšířit stávající immutable CI receipt a GitHub artifacts, nevytvářet databázi důkazů. Pro vykonanou sadu zaznamenat: repository ID, workflow path a použitou definici, run/job ID a attempt, event, skutečně checkoutnuté SHA/tree, jméno sady, digest jejích úplných vstupů, toolchain/platformu, inventář scénářů a stav `executed`. Ověřovatel samostatně načte finální conclusion příslušného GitHub jobu. Receipt sám sebe neopravňuje.

- U PR nespoléhat na `run.head_sha`: workflow může skutečně testovat syntetický merge checkout. Digest počítat nad ověřeným checkoutem. Ověřit způsob checkoutu pro běžný merge, squash i rebase.
- PR reuse pouze z téhož důvěryhodného repozitáře a schválené definice CI. Fork PR, změna samotného selektoru/emitování/politiky/workflow nebo neprokazatelný původ znamenají skutečný nový běh. Nepoužívat `pull_request_target` ke spouštění nedůvěryhodného kódu se zvýšenými právy.
- Ověřit API vazbu repository -> run -> konkrétní attempt -> job -> artifact, skutečný vstupní digest a konečný úspěch. Název souboru, branch, cache key nebo uživatelský marker nejsou důkaz. Cizí artifact, změněný payload a rerun neúspěšného novějšího attemptu se odmítají.
- Stáří maximálně současných 7 dnů; převzetí stáří neobnovuje. Novější odpovídající failed/pending attempt nelze skrýt starším úspěchem. Při nedostupném API, expirovaném/smazaném artefaktu nebo neznámém vstupu vykonat sadu.
- Ruční workflow dispatch dál vynucuje skutečné vykonání. Uchovat stávající podporu `merge_group`; úprava nezapíná merge queue ani nemění branch protection.
- Pro main, který důkaz převzal, zůstává aktuální zelený job s viditelnou referencí na původní vykonání. Release gate nadále posuzuje aktuální přesný main SHA.

## Realizační vlny

### 1. Odstranit dvojí povinné úplné ověření a sjednotit postup

**Změna:** upravit společně `AGENTS.md`, `CONTRIBUTING.md`, `docs/architecture/tenant_overlays.md`, relevantní automatické publish wrappery a kanonický release skill. Lokálně požadovat testy dotčeného chování, ne předem všech osm lanes při každé změně CI souboru. Po publikaci běží GitHub gate; před tenant overlay/deployem na něj stále čekat. Příkaz explicitního úplného mirroru zachovat beze změny významu. Aktualizovat skill v `development-tools/vendor/codex-skills/festapp-web-release/SKILL.md` a spustit jeho `scripts/install-skills.sh`; nepsat jen do instalovaného symlinku.

**První přínos:** odstranění jednoho sériového úplného lokálního běhu z běžného online toku. Ve sledovaném příkladu tvořil 8:23; nejde o příslib stejné úspory pro každou změnu. Cílené lokální ověření dál stojí čas.

**Ověření:** projít read-only všechny publish/release vstupy přes scoped `rg`; nová pravidla musí jednoznačně určit, co provést lokálně, na GitHubu a při deployi. Zachovat branch protection i exact-main release gate. U nejbližší autorizované publikace doložit cílené lokální kontroly a jeden hosted běh.

**Exit:** žádný aktivní návod ani automatický publish wrapper nevyžaduje duplicitní lokální úplný mirror před identickým GitHub ověřením. Nedostupný GitHub není důvod obejít produkční gate; lokální vývoj může pokračovat.

**Autorita:** toto je navržená změna současného závazného pravidla. Plán ji sám nezapíná. Implementační zadání musí výslovně zahrnout přijetí této změny politiky; do té doby se před publikací plní dosavadní pravidla, včetně této přechodové změny.

### 2. Jedna mapa závislostí a jeden vlastník každé sady

**Změna:** v `checks.json` sjednotit současné job/step vstupy a komponentové závislosti tak, aby `run.py: affected` a `selection.py: fingerprint` používaly jednu odvozenou mapu. Odstranit ručně udržovanou duplicitu v `inputs.json` a `affectedInputs`; politiku stáří oddělit od mapy, nikoliv kopírovat seznamy. U každé známé komponenty určit čtené cross-layer kontrakty. Neznámá cesta/test stále znamená plné ověření. Přidání, odstranění, rename, executable mode, lockfile, generátor, fixture a SDK config musí invalidovat odpovídající vlastníky.

**Změna:** `image-policy` bude jediný vlastník worker typechecku a unit testů; odstranit kopii `image-server-policy` a nepotřebnou instalaci pouze tehdy, pokud ji zbytek `server-policy` skutečně nečte. Auth/MCP sady zůstanou v `server-policy`. Nezavádět cross-workflow závislost, kterou by `selected_units()` tiše zahodilo při filtrování. Zachovat osm veřejných check names.

**Ověření:** kontraktní testy reálné invalidace mapy v `automation/ci/test_contract.py` a `test_selection.py`; změna izolovaného Flutter UI nesmí bez doloženého konzumenta spouštět SQL checkout nebo Wix. Přitom např. změna společného platebního kontraktu musí vybrat všechny jeho skutečné klienty. Inventář před/po prokáže stejnou sjednocenou množinu scénářů; odstraní se druhé vykonání týchž worker testů, ne testy samotné.

**Exit:** jedna mapa, shodný lokální a hosted výběr, jeden vlastník každé odstraněné duplicity. Explicitní částečný lokální příkaz dál pravdivě hlásí svůj rozsah.

### 3. Předat důkaz PR -> main a mezi totožnými aktualizacemi

**Změna:** rozšířit `telemetry.py`, `run.py`, `selection.py`, příslušné workflows a jejich contract/release-gate testy podle výše definovaného důkazu. První nasazení nové politiky provede úplné sady a vytvoří důvěryhodný baseline; staré neúplné receipts se neuznávají. Použít stávající archivaci, do které se finální receipts zapíší i po selhání; selhané artefakty slouží jen diagnostice.

**Ověření:** přes skutečné ověřovací funkce s fixovanými API odpověďmi pokrýt merge/squash/rebase, změněný base, konflikt, PR merge-tree vs head-tree, fork, cizí repository, změněný workflow/selector, chybějící/smazaný receipt, odlišný input/toolchain, novější selhání/pending, stáří a zakázané řetězení. Potom jeden skutečný interní PR se zdrojovou změnou a jeho povolený merge: main má všech osm aktuálních zelených jobů, totožné sady se odkážou přímo na původní execution. Nepublikovat prázdné zkušební releasy ani neměnit ochranu větve pro test.

**Exit:** stejný ověřený vstup se na PR a main neprovádí dvakrát; změněný merge výsledek se skutečně testuje. Release gate dál odmítá přesný SHA s missing/skipped/failed/pending checkem.

### 4. Oddělit zdrojové regresní testy od tenant buildu

**Změna:** `test_web_startup.sh` zůstane vlastníkem současné zdrojové startup sady v CI. Z `build_web_bundle.sh` odstranit jeho plošné opakované volání až po ověření přeneseného CI důkazu pro release source. Generované runtime manifesty a tenant konfiguraci nesmí krýt důkaz pouze netenantového zdroje: v builderu ponechat kontroly jejich shody a doplnit úzký smoke výsledného bundlu tam, kde dnešní `verify_web_build.mjs` nestačí.

**Zachovat:** přehrání relevantních SQL upgradů v plném CI; image-service preflight; `apply_config.sh`; kontrolu povoleného overlaye; backend identity; CSP; právní a support konfiguraci; version/asset manifest a živou aktivaci. Nahradit pouze zjištěnou duplicitní zdrojovou práci. Gate před buildem i před uploadem zachovat: opakované načtení stavu stojí málo a hlídá jiný okamžik.

**Ověření:** upravit `automation/tests/deploy_workflow.test.sh`, `deploy_direct.test.sh`, `test_release_gate.py` a relevantní testy bundlu. Všechny produkční vstupy (direct deploy, výslovný hosted fallback a další hosting adaptéry volající builder) musí zachovat zdrojový gate; nelze vytvořit nový přímý vstup, který ho přeskočí. Reálný lokální build jen jednoho vybraného tenantu, teprve při samostatně autorizované release validaci; izolovaný muted/light browser smoke delegovat Terra podle AGENTS.

**Exit:** release build nespouští podruhé celou zdrojovou startup sadu. Počet buildů na jeden pokus je jeden a výsledný tenant artefakt má ověřenou identitu a chování.

### 5. Bezpečné pokračování a konečný důkaz zrychlení

**Změna:** rozšířit stávající build/version manifest o receipt sestavení a kontrolu před opětovným použitím existujícího `--skip-build`. Obsahuje main SHA, tenant overlay SHA a konfigurační digest, toolchain, build flags, zdrojové/generated/build vstupy a digest výstupů. Pouhý adresář `build/web` není důkaz. Nezavádět nový obecný cache systém ani další skip příznaky. Chybějící/odlišný receipt znamená odmítnutí reuse a běžný nový build; po uploadu nelze artefakt přeznačit jinou verzí.

**Ověření:** selhání uploadu a následné pokračování stejného ověřeného artefaktu; odmítnout změnu configu, zdroje, flags, verze, jiného tenantu i upraveného bundlu. Pokud se build nepoužívá znovu, tento receipt nesmí přidávat další build. Současně zachovat ancestry main/tenant, čistý release checkout, Flutter slot a `--concurrency=1`; nikdy nestopovat cizí task nebo rušit probíhající live operaci.

**Měření:** existující immutable receipts doplnit o lehký společný release timeline: lokální testy, PR execution, main reuse/execution, fronta/provisioning, build, artifact checks, upload a live probe. Časy publikování nerozmělňovat do mnoha nových frameworků. Samostatně ukázat úplný cold run, běžnou malou změnu a opakovaný upload.

**Exit:** závěrečná tabulka před/po doloží počet skutečných sad, buildů, čekání a celkovou kritickou cestu; nejméně jeden případ odstraněného lokálního plného běhu a PR/main reuse. Celkový přínos se nesmí tvrdit jen ze zkrácení dílčího kroku.

## Akceptační cíle

Cíle nejsou již naměřený výsledek ani garance rychlosti GitHub runnerů.

| Scénář | Požadovaný výsledek |
|---|---|
| Běžná online změna | Žádný povinný úplný lokální mirror následovaný identickou úplnou GitHub sadou. |
| Stejné vstupy PR -> main | Nula opakovaných těžkých sad; cílový medián potvrzení main do 60 s při dostupném GitHub API. Při nedosažení změřit provisioning/API overhead a uvést deficit. |
| Malá změna izolované komponenty | Vykonají se jen doložené sady konzumentů; ostatní aktuální checky převezmou přímý důkaz. |
| Plná neznámá/shared změna | Všech osm kontrol zůstane; nepožadovat pod 2 minuty, pokud musí reálně běžet současné Flutter sady. |
| Běžný tenant release ze zeleného main | Žádná opakovaná plná zdrojová sada; jeden build, ověření hotového artefaktu a živý smoke. Čas kompilace vykázat zvlášť. |
| Opakovaný upload stejného releasu | Nula nových buildů; platný artefakt receipt a všechny upload/activation guardy. |

Pro hlavní srovnání zachovat stejný typ změny, test inventory, platformu a tenant. Minimálně tři dostupné srovnatelné běhy pro medián; pokud nejsou, uvést jednotlivé hodnoty, nevyrábět zbytečné releasy jen pro benchmark. Cílem je odstranit opakování, nikoliv prohlásit, že 3:50 cold ověření samo o sobě kleslo na polovinu.

## Ledger odstranění a zachování

| Současná cesta | Cílový stav | Důkaz |
|---|---|---|
| Automatický povinný plný lokální mirror před stejným hosted ověřením | Odstranit z běžné online publikace po schválení politiky | Pravidla a jeden publication timeline |
| Ruční úplný lokální mirror | Zachovat jako explicitní diagnostický příkaz | `test_ci.sh` dál znamená všechny deklarované sady |
| Ruční komponentová mapa v `inputs.json` + odlišná mapa v runneru | Jedna kanonická mapa a odvozené pohledy | Stejné invalidace v testech a odstraněné duplicitní seznamy |
| `image-server-policy` jako druhý vlastník stejných testů | Odstranit duplikovanou jednotku a zbytečné instalační kroky | Stejný sjednocený test inventory a osm check names |
| PR důkaz ignorovaný při shodných vstupech na main | Nahradit ověřeným execution receipt | Skutečný PR/main scénář a odmítací testy |
| Plošný startup regression v produkčním builderu | Odstranit, CI sadu zachovat; testovat hotový tenant výstup | Build log + artifact checks + CI inventory |
| Default GitHub dispatch v release skillu | Odstranit z defaultního postupu v kanonickém zdroji a reinstalovat | Skill i repo ukazují na direct deploy |
| Manuální GitHub Deploy | Zachovat jen jako výslovně zvolený executor | Bez push triggeru a bez automatického dispatchování |
| Opakované levné gate/provenance/activation kontroly | Zachovat na existujících hranicích | Negativní release kontrakty |
| Osm jobů a skutečný upgrade gate | Zachovat | Přesný main SHA je přijat až po všech požadovaných úspěších |

## Autorita, pořadí a návrat

Toto zadání vytváří plán a execution prompt. Samo neautorizuje jeho implementaci, změnu release politiky, commit/push tohoto plánu, změnu branch protection ani produkční deploy. Předchozí povolení pushnout commit `32adbae3f` se nevztahuje na další publikace. Následující implementační zadání má výslovně přijmout cílovou politiku z vlny 1; jednotlivé kroky pak nevyžadují opakované schvalování již přijatého rozsahu.

Implementovat v čistém worktree z aktuálního main; původní checkout obsahuje rozsáhlou nesouvisející práci. Před publikací fetch a integrace případného posunu main; required PR pravidla zjistit před pokusem o push a neobcházet je admin oprávněním. Změny sdílené CI nepublikují žádný tenant. Produkční build/deploy a skutečný PR merge test patří pouze do samostatně autorizovaného scope.

Pořadí 1 -> 2 -> 3 -> 4 -> 5 umožňuje dodat první největší úsporu bez čekání na nový receipt mechanismus. Pro každou vlnu jedna relevantní dávka ověření; při změně vstupů přepočítat affected lanes. Přechodové publikace respektují dosud platná pravidla. Úplné release gates jen při produkčním releasu, ne při psaní tohoto plánu.

Selže-li důkaz, vykonat příslušnou sadu; nejde o kompatibilní paralelní cestu ani o green fallback. Selže-li oddělení builderu, vrátit jeho konkrétní změnu a zveřejnit, že duplicita dočasně trvá. Nevracet skryté defaulty v dokumentaci. Staré receipts lze expirovat, nelze jim dodatečně připsat nové vstupy. Žádná změna nebo úklid produkčních dat není součástí rollbacku.

## Zjištění při realizaci

- Aktuální výchozí main je `bdea2039cfa2332e5e746b2ca4c462bc12a6c612`, nikoliv původní plánovací SHA. Implementace je v čistém samostatném worktree.
- Existující interní PR run `42874037095` má prázdné `pull_requests`, ale API poskytuje repository ID, head SHA, konkrétní job/attempt a digest artefaktu. Vazba PR checkoutu proto používá důvěryhodný emitter, skutečný uložený checkout, rodiče merge commitu, kanonického main předka a vypočtený merge tree. Samotné run head SHA ani prázdné pole PR nejsou důkaz checkoutu.
- Stávající `wix-install` má lokální závislosti na jiných lanes kvůli serializaci sdílené instalace; hosted worktrees jsou izolované. Tato existující závislost zůstává, nová cross-workflow závislost nebyla přidána.
- Zapečetěný předchozí build se před novou kompilací přesune pod vlastní receipt digest v `build/web-artifacts/`; nový build jej nepřepisuje. Nejde o další cache selector nebo bypass zdrojových gates.

## Předpoklady a zbytková rizika

- API a artifact retention dovolí spolehlivě přiřadit skutečný PR checkout a execution. Ověřit ve vlně 3 na jednom existujícím běhu před návrhem formátu; pokud ne, použít nový ověřený receipt, nikoliv odhad podle branch SHA.
- Zdrojová startup sada může číst tenant-generated hodnoty. Vlny 2 a 4 musí jejich konzumenty explicitně přidělit tenant artifact checks; bez tohoto inventáře se volání z builderu neodstraní.
- Návrh zrychluje tok, ne samotnou Flutter kompilaci. Jestli po odstranění duplicit dominuje jeden build, je další práce samostatný profilovaný úkol, nikoliv důvod vypnout ověření.
- Důvěryhodnost reuse je bezpečnostní hranice. Žádné spoléhání na pouhý cache hit, uploaded JSON nebo lokální dirty receipt.
- Více souběžných agentů a publikací může znovu vyrábět zastaralé buildy. Jeden release owner musí před buildem zkontrolovat aktuální schválenou revizi a nesmí bez omezení honit každé nové main SHA.

## Hotovo znamená

- [ ] Běžná změna nečeká na dvě úplná ověření týchž vstupů.
- [ ] Lokální a hosted výběr používají jednu mapu, neznámé vstupy zůstávají konzervativní.
- [ ] PR/main reuse ověřuje skutečný checkout, zdroj důkazu, stáří a finální úspěch; neúspěchy se nezakrývají.
- [ ] Osm aktuálních zelených jobů zůstává podmínkou releasu přesného main SHA.
- [ ] Produkční build neopakuje plnou zdrojovou sadu a tenant artifact checks zůstávají reálné.
- [ ] Direct deploy, alternativní hosted executor, návody i globální skill mají shodný postup.
- [ ] Opakovaný upload lze provést bez nového buildu jen při platné identitě artefaktu.
- [ ] Výsledek obsahuje počet skutečných executions/buildů a naměřenou celkovou dobu, ne jen dílčí odhad.
