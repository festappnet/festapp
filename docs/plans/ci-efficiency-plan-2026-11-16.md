# Rychlejší CI s měřitelně nižší spotřebou

Datum: 2026-11-16  
Stav: Lokální implementace dokončena; [výsledek a limity](ci-efficiency-result-2026-11-16.md). Hosted publikace neprovedena.  
Ověřování implementace: standard (výběr povinných kontrol, původ evidence a souběh)

## Výsledek a rozsah

Zkrátit čekání na spolehlivý výsledek CI a snížit součet spotřebovaných runner minut na jednu dokončenou změnu. Zachovat testovací scénáře, povinné kontroly a přesnou vazbu releasu na ověřenou revizi. Rychlejší výsledek dosažený pouze přidáním runnerů není splnění cíle.

Rozsah: osm kanonických regression jobs, jejich společný lokální mirror, selector, DAG, evidence a dokumentace. Priorita je selector, výběr integračních testů a dlouhé Wix/SQL bloky. Android, produkční deploy, produkční databáze, změna branch protection a nákup kapacity jsou mimo rozsah.

Tento dokument je autoritativní pro zde popsanou optimalizaci CI. Navazuje na `ci-release-latency-plan-2026-11-13.md` a `test-runtime-speedup-plan-2026-11-09.md`; jejich body o produkčním deployi zůstávají mimo tento plán. Již existující DAG, telemetrii, SQL runtime a cache nevytvářet znovu. Při implementaci doplnit do starších plánů odkazy na tento dokument u překrývajících se bodů, bez přepisování historických výsledků.

## Výchozí důkazy a omezení měření

Audit CI definic vycházel z main `ff597ea596d072f87a9e391eae6bd9fadca10066`. Doplnění vlastníků scheduleru, SQL runtime a release gate bylo přečteno z main `2b9ca14268ce4d95e577a3ce2346bdd7684687fd`. Nejde o jednu neměnnou měřenou revizi. Implementátor musí začít z aktuálního main a zkontrolovat rozdíl těchto souborů proti němu.

Pracovní adresář auditu je starší větev `docs/festapp-tickets-readme-20261107` s rozsáhlými cizími změnami. Implementace patří do čistého samostatného worktree od main. Nekopírovat z tohoto checkoutu staré CI skripty ani jeho ostatní změny.

| Fakt | Důkaz | Dopad |
|---|---|---|
| Wix čekal 398 s do startu jobu, běžel 478 s; uvnitř `wix-contract` 423,7 s. | [Run 43716164726](https://github.com/festappnet/festapp/actions/runs/43716164726), job timestamps, log a artefakt `ci-wix-checkout-compatibility-1`. | Oddělit čekání a práci; hlavní blok rozdělit podle závislostí. |
| Seat čekal 288 s, běžel 487 s; `seat-contract` 276 s. | [Run 43716164658](https://github.com/festappnet/festapp/actions/runs/43716164658), log DAG. | Uvnitř SQL větve zůstává dlouhý blok i přes existující paralelismus. |
| Selector image kontroly trval 135 s a 126 s; regression DAG v obou případech 38 s. | [Run 43708009689](https://github.com/festappnet/festapp/actions/runs/43708009689), [run 43708835907](https://github.com/festappnet/festapp/actions/runs/43708835907). | Optimalizovat hledání evidence před dalším laděním krátkých testů. |
| Wix lane vlastní celé `integrations/**`, `web_client/**`, `database/**`, `supabase/**`. `wix-contract` spojuje unit testy, build, adaptéry a instalovanou CMS matici. | `automation/ci/checks.json`: `jobs.wix-checkout-compatibility`, `steps.wix-contract`. | Pouhé rozdělení příkazů nezlevní běh, pokud selector dál vybírá celý lane. |
| CMS fixture instaluje tři prohlížeče a startuje reálné WordPress/Joomla prostředí; obsahuje devět ověřovaných případů. | `automation/testing/cms_consent_fixture.py`, uložený log Wix artefaktu. | Zachovat instalované CMS a cross-browser pokrytí; zlevnit přípravu a výběr. |
| Scheduler, měření, čisté DB leases a ověřený reuse již existují. | `automation/ci/{scheduler,telemetry,selection,run}.py`, `automation/local_db/runtime.py`, `CONTRIBUTING.md`. | Rozšířit kanonické vlastníky, nevytvářet další orchestrátor či cache systém. |

Čas od vytvoření runu do startu jobu není důkaz čistého nedostatku runnerů. Obsahuje i workflow concurrency a plánování. Výše jsou vybrané pomalé příklady ze vzorku 100 posledních main běhů, nikoli mediány ani odhad běžné úspory. Anonymizované časy a odkazy uložit s výsledkem implementace; nespoléhat na dočasné `/tmp` soubory auditu.

## Kanonické vlastnictví a bezpečnostní podmínky

- `checks.json` vlastní inventář, závislosti, vstupy jednotek a jejich resource claims. Lokální i hosted výběr čtou tutéž definici. `selection.py` vlastní fingerprint a ověření evidence; `run.py` její provedení a receipt; `scheduler.py` rozpočet; `release_gate.py` agregovaný release gate.
- Zachovat osm existujících jmen povinných jobs. Jejich SUCCESS musí znamenat úplné pokrytí aktuálního inventáře: každá povinná jednotka buď skutečně prošla, nebo má samostatně ověřený shodný předchozí výsledek. Chybějící pokrytí nesmí být zelené.
- Zachovat přesný `baseMainSha`, původ artefaktů a jejich digest, úplné vstupy, toolchain, CI definici, PR merge tree a ancestry. Stáří reuse nejvýše sedm dní. Evidence o reuse nikdy nesmí být zdrojem dalšího reuse. Novější odpovídající selhání ani nedokončený běh nelze zakrýt starým PASS.
- Neznámá cesta, nový nezařazený test nebo neúplná mapa znamenají konzervativní plný výběr. Neověřitelná evidence spouští testy; neověřitelný povinný gate blokuje release. Žádný automatický zelený fallback.
- Zachovat dosavadní vynucené plné exekuce pro ruční dispatch, rerun a přechod PR z draftu. Lokální explicitně vybraný lane se provede celý bez hosted reuse; `affected` dává přesný výběr a důvod.
- Jeden Flutter task na workstation a testy `--concurrency=1`. Paralelismus ostatních jednotek pouze v mezích RAM, browser, source-generation a DB claims. Souběžné testy nesmí měnit stejnou DB či generované soubory.
- Zachovat skutečné cold replay a upgrade z naplněné DB, skutečnou CMS matici, síťovou izolaci a cleanup vlastněných prostředků. Snapshot není upgrade test, stub není instalovaný CMS test.
- Žádné plošné `cancel-in-progress: true` pro main, žádné rušení aktivního releasu. Neoslabovat gate kvůli zrušenému runu. Nezvyšovat počet runnerů ani používat placené služby bez samostatného zadání.

## Postup implementace

### 1. Zaznamenat reprezentativní cenu a čekání

**Změny:** Rozšířit existující telemetrii jen o chybějící pole. V reportu rozlišit workflow čekání, runner čekání pokud je prokazatelné, checkout, selector, instalace, přípravu DB/CMS, testy a cleanup. U selectoru počítat API volání, prohlédnuté kandidáty a stažené bajty. U CMS rozlišit instalace browserů, image pulls, readiness, jednotlivé cesty a cleanup; neměřit vše jako jeden příkaz. Příkazy, tokeny, SQL a soukromá data nevkládat do telemetrie.

**Měření:** Použít posledních sedm dní dostupných běhů, nejvýše 100 na workflow pro úvodní analýzu; reportovat velikost a omezení vzorku. Rozdělit reuse/full, změny klienta/backendu/CMS/CI a známé cold/warm běhy. Počítat p50/p95 času a součet runner minut, včetně neúspěšných a zrušených pokusů; nesčítat překrývající se testové fáze jako wall time. Pokud je dostupný billing údaj, uvést ho zvlášť; runner minuty nejsou automaticky účtované minuty.

**Validace a hotovo:** Rozšířit existující telemetry testy nalezené cíleně v aktuálním main. Report z existujících běhů ukáže kritickou cestu a spotřebu; nevytvářet nové CI běhy jen pro sběr baseline. Zapsat přehled do `docs/plans/ci-efficiency-result-2026-11-16.md`.

### 2. Zlevnit selector bez změny výsledku rozhodování

**Změny:** V `selection.py` odstranit opakované dotazy a výpočty v rámci jednoho rozhodnutí. Cache pouze neměnná metadata podle repository/run/attempt/commit a fingerprintů se zahrnutou definicí policy. Stav běhu načíst čerstvý. Před stahováním ZIP ověřit levné podmínky a shodu vstupů, pokud je lze pro daný event bezpečně určit. U PR nikdy nezaměnit `head_sha` za testovaný merge checkout. Zachovat pořadí kandidátů i zastavení na novější neúspěšné evidenci. Reuse-only běhy nesmějí vést k hromadnému stahování nepotřebných artefaktů.

Přidat celkový časový rozpočet selectoru 20 s. Síťové subprocessy musí mít timeout podle zbývajícího rozpočtu, včetně fetch a ukončení jejich potomků. Po vyčerpání rozpočtu spustit testy a zaznamenat důvod. Nesmí se z toho stát záměrný krátký timeout nahrazující správné hledání evidence. Pokud rollout ukáže vyšší spotřebu kvůli častému fallbacku, opravit lookup nebo vrátit tuto optimalizaci před pokračováním.

**Validace:** `test_selection.py` rozšířit o stejné výsledky pro původní kandidátní historii, síťový timeout, nové attempts, padlé/pending běhy, neplatný ZIP/digest, neúplný PR merge checkout a limit počtu volání. Nezakládat nový nezávislý verifikátor.

**Hotovo:** Rozhodnutí zůstávají ekvivalentní mimo explicitní timeout vedoucí k exekuci. Selector běžně nestahuje artefakty s prokazatelně odlišnými vstupy; síťová nedostupnost nevisí minuty. Sledovat hit rate i celkové runner minuty, ne pouze délku selectoru.

### 3. Rozdělit dlouhé bloky, zatím zachovat plný výběr

**Změny:** `wix-contract` rozdělit v `checks.json` na rychlé kontrakty/build, PHP/adapter smoke a instalovanou CMS matici. `seat-contract` rozdělit podle nynějších příkazů na souvislé domény: payment providers, order/seating, ticket delivery a zbývající kontrakty. Přesné členství odvodit z aktuálních příkazů a SQL inventáře; každý původní příkaz musí mít nového vlastníka. `run.py` a workflow dál používají kanonický DAG.

Nezávislé jednotky spouštět pomocí existujícího scheduleru. Každé DB jednotce přidělit vlastní lease z existujícího runtime; cluster-global zásahy serializovat. Přípravu drahého prostředí podmínit skutečným consumerem. Rozdělit resource claims podle práce, ne mechanicky kopírovat nárok na browser a DB všem částem.

**Odstranění:** Nahradit staré monolitické step definice a jejich registrace, nikoli udržovat staré i nové seznamy. Staré receipts s odlišnou CI definicí už nesmějí autorizovat reuse.

**Validace a hotovo:** Rozšířit contract/scheduler testy z aktuálního main. Porovnat inventář před/po podle identity příkazů a scénářů, nikoli jen počtu testů. Provést dotčené kanonické mirror lanes jednou jako ucelenou dávku. Všechny původní kontroly stále běží; receipt ukazuje časy samostatných bloků a správný cleanup po chybě.

### 4. Vybírat práci a reuse po jednotkách

**Změny:** Přidat do kanonické definice explicitní vstupy nových jednotek včetně transitivních helperů, fixture, generátorů, konfigurace a lockfiles. Výběr dělat podle úplného fingerprintu, nikoli pouze názvu změněného souboru. Široké lane patterns ponechat jako konzervativní agregát, dokud je testy neprokážou nahraditelné. CMS matice musí reagovat i na sdílené embed, consent, export, auth a backend smlouvy, které používá.

Rozšířit stávající receipt o jednoznačnou verzi schématu a jednotkové exekuce. Pro každou jednotku zaznamenat její identitu, vstupy, skutečný PASS, source/run/attempt/job a vazbu na původní artefakt. V aggregate receipt explicitně rozlišit `executed` a `reused`; žádný reused řádek nesmí být novou exekuční evidencí. Starší lane-only receipt není automaticky jednotkovým důkazem a v nové definici vede k provedení testů.

`selection.py` a `run.py` musí společně ověřit každou jednotku, dependency closure a úplnost aktuálního lane. Aktualizovat nynější lane-level ověření `verify_execution()`, kontrolu markeru `All lane tests executed` i souhrny: marker znamená pouze skutečně kompletní exekuci lane. Smíšené pokrytí má odlišný souhrn a ověřenou agregaci. `release_gate.py` dál kontroluje přesný main SHA a všech osm jmen; žádné SUCCESS založené jen na prázdném seznamu vybraných testů.

Změna definice CI zneplatní starou evidenci a vyvolá první plný běh. Tento jednorázový náklad vykázat; neobcházet ho změnou trusted-definition pravidla.

**Validace:** Jedna společná negativní matice v existujících selection/contract/release-gate testech: chybějící jednotka, nová jednotka, změněný helper/lock/config, smazání/přejmenování vstupu, změněná definice, starý toolchain, sedm dní, pending/failed novější jednotka, cizí repository/attempt, reuse řetězec a nekompletní aggregate. Ověřit i kombinaci nově provedených a přímo doložených jednotek, která gate oprávněně splní. Lokální mirror nesmí používat hosted reuse.

**Hotovo:** Změna izolovaného kontraktu provede jen dotčené jednotky a nutné závislosti; nezměněné části mají přímý platný důkaz. Neznámé vstupy spustí plný rozsah. Povinné joby zůstávají přítomné na každé kontrolované revizi; nepoužívat workflow `paths` k jejich zmizení.

### 5. Zlevnit přípravu CMS a omezit opakovanou práci při publikaci

**CMS:** Podle nových časů v `cms_consent_fixture.py` odstranit opakované instalace v jednom runu; využít digestem připnuté image layers a browser cache klíčovanou přesnou Playwright verzí, OS/arch a konfigurací. Instalované závislosti CMS držet podle skutečných frozen lockfiles. Nestahovat a neukládat tak velké cache, že přenos převýší ušetřenou přípravu. Neměnit verze image na plovoucí tagy. Data DB/CMS mezi běhy nesdílet; sdílet jen ověřené neměnné podklady. Zachovat všech devět současných CMS scénářů a jejich browser matrix.

**Publikace:** Z časů a concurrency určit, kolik čekání způsobují překrývající se publikace. V existujícím publikačním postupu slučovat související hotové změny před push, určit jednoho vlastníka monitorování a nedispatchovat další workflow kvůli pouhému čekání. Zachovat rušení zastaralých PR běhů. Main/merge-group/release běhy plošně nerušit: chybí prokázaná ochrana revize vlastněné aktivním releasem. Tento plán nezavádí nový publikační daemon ani globální frontu.

**Validace a hotovo:** Jeden cold a jeden warm průchod dotčenou CMS cestou, v pozadí, izolovaně a muted; zachovat systémové závislosti, timeouty, odmítnutí síťových úniků a cleanup po chybě. Pro srovnání cache vykázat transfer i obnovu. Publikační cesta nevytváří duplicitní dispatch a nezruší revizi určenou k releasu. Při potřebě browser operátora dodržet předepsané delegování na Terra; deterministické testy spouštět přes kanonický lane.

### 6. Ověřit úspory, odstranit zbytky a uzavřít

**Změny:** Aktualizovat `CONTRIBUTING.md`, `docs/architecture/ci_input_reuse.md` a výsledek měření. Odstranit staré step identifikátory z aktivních workflow, kontraktu a testů. Zachovat historické receipts pouze jako historii, ne jako skrytou alternativní cestu. Nedržet přechodný režim, který tiše považuje lane-only PASS za jednotkový PASS.

**Vyhodnocení:** Z běžných následných běhů získat alespoň pět srovnatelných pozorování pro dostupné hlavní třídy změn; uvést malý vzorek a neprezentovat jeho p95 jako stabilní statistiku. Nespouštět desítky umělých GitHub běhů pro naplnění tabulky. Oddělit přínos kratší fronty od nižší spotřeby. Srovnávat stejný rozsah testů a cold/warm režim; neporovnávat starý full s novým reuse bez označení.

**Cíle, nikoli předem naměřené sliby:** alespoň 30 % méně runner minut u reprezentativních malých změn; alespoň 30 % kratší medián času k povinným výsledkům ve srovnatelné třídě; selector běžně do 10 s a fallback po rozpočtu 20 s. U plné cold matice doložit nulovou ztrátu pokrytí a cenu, i když výrazná úspora nebude dosažena. Optimalizaci s vyšší spotřebou nebo horší spolehlivostí neprohlásit za úspěch jen kvůli kratšímu wall time. Při nedosažení cíle zapsat konkrétní limit a naměřený výsledek, nevymýšlet další plošné testování.

**Hotovo:** Výsledkový dokument obsahuje baseline/head SHA, validační příkazy, odkazy na běhy, scope, exekuce/reuse, časy a runner minuty včetně retry. Implementace a ověření úspor jsou dvě explicitní položky; při chybějící autorizaci publikace zůstává hosted vyhodnocení označené jako neprovedené.

## Ověřování, publikace a návrat

Plánování nevyžaduje spuštění testů. Při implementaci používat `standard`, koherentní změny ověřovat jednou společnou cílenou dávkou. Z aktuálního main zjistit skutečná jména scheduler/telemetry/runtime testů; pro známé moduly použít například `python3 -m unittest discover -s automation/ci -p 'test_*.py'`. Reálné dotčené testy spouštět přes `automation/test_ci.sh`, ne vymyšlenou náhradní sadu. Dodržet workstation Flutter slot a pnpm 11.24.0. Passing kontrolu neopakovat bez změny pokrytých vstupů.

Před případným publikováním jsou povinné affected canonical mirror lanes a aktuální upstream s vyřešenou kolizí; následně přesná GitHub evidence. Současné zadání autorizuje plán, nikoli implementaci, push, spuštění placené kapacity či produkční rollout. Implementace může být předána připravená lokálně; skutečné GitHub ověření vyžaduje následně autorizovanou publikaci. Produkční tenant není pro tuto práci potřeba.

Jednotlivé vlny držet jako přehledné reverzibilní změny. Při vadném jemném výběru vrátit celou příslušnou změnu ke konzervativnímu plnému výběru, nikoli obejít gate nebo doplnit trvalý kompatibilní fallback. Změna definice znovu vyžaduje skutečnou exekuci. Návrat nezachová reuse staré evidence na změněných vstupech.

## Definice dokončení a zbývající rizika

- Všech osm required jobs má pro přesnou revizi úplné prokazatelné pokrytí. Negativní scénáře gate zůstávají červené.
- Dlouhé Wix/SQL bloky mají samostatné vlastníky, měření, vstupy a bezpečné resources; původní testy nejsou odstraněny kvůli rychlosti.
- Selector má omezené čekání a nízkou režii; jeho fallback nezpůsobuje skrytou explozi exekucí.
- Úspora času a runner minut je doložená odděleně; výsledek obsahuje i nezdařené a zrušené pokusy.
- Žádné dvě aktivní mapy testů, starý monolitický příkaz ani neověřená evidence nejsou alternativní cestou. Dokumentace odpovídá výslednému kontraktu.

Hlavní riziko je neúplná mapa transitivních vstupů. Proto začít rozdělením při plném pokrytí a teprve potom zapnout jemný výběr. Další rizika: proměnlivá dostupnost runnerů, drahý cache transfer, nedostupné artefakty a práce jiných publisherů. Tyto faktory reportovat, nikoli skrýt do tvrzení o rychlosti testů. Širší dependency mapu nebo timeout upravit jen na základě měření a zachování stejných pravidel důvěry.
