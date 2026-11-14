# Zkrácení CI a webových releasů při zachování ověření

Datum: 2026-11-13  
Stav: Plán k implementaci; bez změn pipeline a bez publikace  
Ověřování implementace: standard, protože jde o release gate a souběh úloh

## Výsledek a rozsah

Zkrátit cestu od připravené změny k ověřené živé verzi odstraněním duplicitní
přípravy, zbytečného přenosu Git historie a opakovaných startů testovacího
prostředí. Zachovat testovací případy, povinné kontroly, původ artefaktů a
ověření živého nasazení. Není cílem snížit počet kontrol ani zvýšit paralelismus
Flutteru. Plán neautorizuje release, push, změnu branch protection ani placené runnery.

## Výchozí bod a důkazy

Autoritativní zkoumaný main: `279281560848ba0a0dad35349f2f52a7e785c07c`.
Pracovní checkout byl na starší větvi `docs/festapp-tickets-readme-20261107`
a obsahoval přes tisíc změněných sledovaných souborů. Jeho verze CI skriptů
se liší od main. Implementovat v samostatném čistém worktree z aktuálního main;
nepřenášet do něj staré workflow ani cizí rozpracované změny.

| Potvrzené pozorování | Důkaz | Důsledek |
|---|---|---|
| Reuse funguje: u cddc5160a se image, Wix a seat testy přeskočily. | GitHub jobs a kroky posledních tří main revizí. | Nezavádět další systém reuse. |
| Poslední ticket job: 260 s, z toho regression DAG 200 s; ticket-client přibližně 178 s. | [43323685457](https://github.com/festappnet/festapp/actions/runs/43323685457), časové značky logu. | Zaměřit se na Flutter část a její opakované starty. |
| Main u scanneru začal 29 s po PR bězích. Selector hlásil `Newer matching or unresolved workflow did not pass`. | Main 22:51:08 UTC, PR 22:50:39 UTC dne 2026-11-12; selector logy navigation, seat a ticket. | Existuje překryv. Není tím prokázáno, že PR po dokončení poskytne shodný fingerprint a toolchain. |
| Web startup u cddc5160a: 332 s do startu jobu, 159 s běh. | [43321921692](https://github.com/festappnet/festapp/actions/runs/43321921692). | Oddělit frontu workflow a čekání na runner; součet není čas testů. |
| U dfd42126b trval checkout 437 s a následné testy byly přeskočené. | [43321616230](https://github.com/festappnet/festapp/actions/runs/43321616230); uložený audit log `/tmp/festapp-ci-slowcheckout.log`. Checkout fetchoval všechny branches a tagy. | Zúžit refspec; jeden výkyv není důkaz pravidelné úspory 7 minut. |
| Flutter build cache měla hit u Cookiebot i finálního seat releasu. Upload souborů 14,61 s a 15,47 s. | `/private/tmp/festapp-cookiebot-production-deploy.log`, `/private/tmp/festapp-seat-web-release-final.log`. | Neoptimalizovat upload jako první; časy nezahrnují celý deploy. |
| První seat pokus zastavil chybějící `FESTAPP_RELEASE_MANIFEST`; další selhal při Vite buildu. | `/private/tmp/festapp-seat-web-release.log`, `-retry.log`, `-final.log`. | Levně odhalitelné chyby řešit před drahou přípravou; příčinu Vite selhání nejprve určit. |

Dočasné logy mohou zmizet. Uchovat pouze potřebné anonymizované časy a důvody
v repozitářovém výsledku, žádné tokeny, prostředí nebo soukromý manifest.

## Kanonické vlastnictví a nepřekročitelné podmínky

- `automation/ci/checks.json` vlastní kroky, vstupy a testovací inventář.
  `selection.py` vlastní výběr a ověření evidence, `run.py` spouštění DAG,
  `resources.py`/`scheduler.py` omezení zdrojů a `telemetry.py` měření.
- `automation/ci/release_gate.py` dál vyžaduje všech osm úspěšných checks na
  přesném `baseMainSha`, včetně dosavadních pravidel pro další neúspěšné checks.
  Lokální PASS ani hotový build tento gate nenahrazují.
- Reuse vyžaduje skutečně dokončenou úspěšnou exekuci, shodné úplné vstupy,
  toolchain a definici CI, platný původ a digest artefaktu. Zachovat sedmidenní
  stáří, ochranu proti řetězení reuse a proti zakrytí novější chyby starým PASS.
- Chybějící historie, API nebo neověřitelná evidence znamená spuštění testů,
  případně explicitní chybu povinného gate. Nikdy automatický zelený výsledek.
- Zachovat skutečný PR merge checkout, ověření merge tree a ancestry.
  Ruční dispatch, rerun a ostatní dosavadní vynucené exekuce zůstanou plné.
- Jeden Flutter task na workstation, testy `--concurrency=1`; zachovat browser,
  DB a RAM limity a izolaci databází. Neslučovat testy s odlišnými dart-define.
- Lokální build a `automation/deploy_direct.sh` zůstávají cestou web releasu.
  Zachovat build receipt, gate před uploadem a ověření živé verze. Jeden tenant.

## Kroky implementace

### 1. Krátké měření a levný release preflight

**Změna:** V existující telemetrii oddělit čekání na workflow/runner, checkout,
selector, instalace, testovací jednotky, build, upload a live probe. Doplnit jen
chybějící údaje, nezakládat nový měřicí framework. V `deploy_direct.sh`,
`build_web_bundle.sh` a `automation/release/client_cutover_preflight.mjs`
prověřit pořadí levných kontrol nutného manifestu, konfigurace a toolchainu.
Kontroly závislé na buildu ponechat za buildem. Síťové gate před uploadem ponechat.

**Validace:** Rozšířit existující release/receipt kontraktové testy o chybějící
manifest a chybnou konfiguraci: kompilátor ani instalace se nesmí spustit.
Ověřit zachování obou source/upload gate a live probe. Použít existující
`test_build_receipt.py`, `test_telemetry.py` a příslušné deploy testy.

**Hotovo:** Jeden přehled ukáže časy fází a počet opakovaných pokusů; chybný
povinný vstup selže před drahou přípravou. Žádná kontrola nebyla odstraněna.

### 2. Checkout pouze potřebné historie

**Změna:** V šesti kanonických regression workflows nahradit fetch všech větví
a tagů cíleným checkoutem skutečně testovaného SHA a načtením main historie bez
tagů. Potřebné kandidátní evidence a rodiče PR merge commitu načítat explicitně
přes stávající `ensure_commit()`; zkontrolovat `validate_checkout()` a merge-base.
Nastavit konkrétní refspec. Pouhé `fetch-tags: false` při `fetch-depth: 0`
nepovažovat bez ověření skutečného příkazu za vyřešení.

**Validace:** V dočasném lokálním Git originu ověřit main, PR merge ref, squash,
rebase, změnu base, starší kandidát, chybějící SHA a neúplnou historii. Použít
a rozšířit `test_selection.py`, doplnit `test_contract.py`. Při nedostupném
objektu nesmí vzniknout reuse PASS. Zachovat tree fingerprint včetně režimů,
přejmenování a smazání. Jedním reálným CI během ověřit emitovaný fetch příkaz.

**Hotovo:** Checkout netahá všechny vzdálené větve a tagy; všechny případy
provenance stále procházejí. Hlásit naměřený rozdíl, ne slib úspory 437 s.

### 3. Omezit duplicitní publikace bez oslabení selectoru

**Změna:** Podle job timestamps a workflow concurrency rozlišit frontu
jednotlivého workflow od nedostatku runnerů. Zjistit vlastníka publikace a
existující publikační entrypoint; upravit tento entrypoint a release návod,
nevytvářet druhý frontovací systém. Slučovat související připravené změny před
publikací, rušit jen již povolené zastaralé PR běhy, ne main ani živé releasy.
U PR vyžadovaných pravidly dokončit potřebné kontroly před mergem. U přímé
publikace na main nevytvářet navíc PR jen jako mezikrok.

Změnu pravidel `reusable()` zatím nedělat. Nejprve na zaznamenaném překryvu
ověřit, zda dokončený PR artefakt skutečně splňuje všechny podmínky pro main.
Pokud ne, zaznamenat důvod a ponechat opakování. Nepřidávat plošný sleep ani
čekání na všechny PR. Případný budoucí wait/reuse návrh je samostatná změna
s limitem čekání, vazbou na konkrétní exekuci a vlastními negativními testy.

**Validace:** Porovnat jednu reprezentativní cestu od prvního publikovaného
commitu po všechny required checks; zahrnout čekání před mergem. Samotný
rychlejší main po delším čekání na PR není celková úspora. Ověřit, že nevznikl
druhý dispatch a nezrušil se main run. Nevyvolávat placené ani duplicitní běhy.

**Hotovo:** Každý opakovaný běh má vysvětlený důvod a jednoho publikačního
vlastníka. Změna nevyužívá pending/failed evidence a neobchází gate.

### 4. Snížit opakované starty Flutter testů

**Změna:** Začít `ticket-core` a `ticket-client` v `checks.json`, potom
`navigation-contract`. Seskupit kompatibilní soubory do menšího počtu existujících
test sessions a příkazů. Zachovat definice, pořadí vyžadované setupem, teardown,
časová pásma, lokalizace a obnovu globálního stavu. Oddělené konfigurace a testy,
jejichž izolaci nelze prokázat, ponechat samostatně. Neslučovat různé joby.

**Validace:** Před a po zaznamenat sadu semantic case ID, výsledky a existující
skip důvody přes `automation/client_test_inventory.py check-ci` a CI receipts.
Samotný stejný počet testů nestačí. Zkontrolovat běh sloučených skupin v opačném
pořadí kvůli únikům stavu. Porovnat alespoň tři sekvenční warm běhy stejné
revize a stroje s baseline, provisioning měřit zvlášť. Nespouštět Flutter souběžně.

**Hotovo:** Shodný inventář a výsledky, žádné nové skips/retries, prokázaná
úspora mediánu celé lane bez růstu paměti nad dosavadní rozpočet. Pokud
sloučení nepomůže nebo naruší izolaci, tuto část nepublikovat.

### 5. Uzavření a ověření výsledku

**Změna:** Aktualizovat `docs/architecture/ci_input_reuse.md`, `CONTRIBUTING.md`
a relevantní release návod podle skutečné implementace. Současný main už
umí ověřenou PR evidenci; starší místní popis „jen main evidence“ nekopírovat.
Odstranit nahrazené checkout nastavení a pouze prokazatelně duplicitní test
entrypointy. Zachovat jejich případy v kanonickém inventáři. Žádné trvalé skip
flagy, paralelní policy ani druhý cache systém.

**Validace:** V čistém worktree spustit cílené Python testy změněných CI modulů
pomocí `python3 -m unittest discover -s automation/ci -p 'test_*.py'` a
repozitářem požadované affected mirror lanes přes `automation/test_ci.sh`.
Před publikací fetch aktuálního main, integrovat posun a ověřit zasažené změny.
Po samostatně autorizované publikaci ověřit osm checks na přesném novém SHA.
Změna definice CI vynutí první plnou exekuci; to není regrese reuse.

**Hotovo:** Výsledkový dokument obsahuje base/head SHA, inventář případů,
provedené kontroly a časy před/po pro checkout, lane a celou publikační cestu.
Nevydávat výsledek jedné rychlé lane za zrychlení celého releasu.

## Pořadí, rollback a zbývající rizika

Kroky 1 a 2 mají první prioritu. Krok 3 je částečně provozní pravidlo; krok 4
provést po baseline a jen s doloženou izolací. Nevytvářet rozsáhlý přepis CI.
Každý krok držet jako samostatnou vrátitelnou změnu. Při regresi vrátit změnu
daného kroku, nikoli oslabit kontrolu nebo přijmout neověřenou evidenci.

Nedostatek runnerů zatím není potvrzený účetním limitem. Placené runnery,
změna ochrany větví a větší paralelismus nejsou součástí řešení. Z uživatelského
limitu jednoho Flutter tasku plyne, že lokální Flutter části zůstanou sekvenční.
První plný CI běh po úpravě policy a změny image runneru mohou omezit reuse.
Celková délka posledních deployů není z logů bez úplných časových značek přesně
rekonstruovatelná; nevymýšlet procentní úsporu ani SLA.

Dokončení implementace neznamená produkční rollout. Ten vyžaduje samostatné
zadání konkrétního tenanta a všechny běžné release/live gates. Při takovém
zadání delegovat rutinní release podle AGENTS.md.
