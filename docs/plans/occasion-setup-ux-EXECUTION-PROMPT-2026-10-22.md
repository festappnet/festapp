# Realizační prompt: celý UX balík průvodce, rychle a efektivně

Pracuj v `/Users/miakh/source/festapp`.

Toto je zadání k implementaci. Nezůstávej u dalšího plánu nebo doporučení.
Dokonči všech 15 připomínek a cílené ověření. Optimalizuj čas do hotového výsledku:
krátký průzkum, souběžná implementace nezávislých částí, společná integrace a jeden
závěrečný cílený ověřovací průchod. Rychlost nesmí znamenat vynechání funkcionality.

## Autoritativní zadání

Přečti AGENTS.md, CLAUDE.md, `docs/architecture/ai_context.md` a celý plán:

`docs/plans/occasion-setup-ux-plan-2026-10-22.md`

Plán vlastní požadované chování a bezpečnostní invarianty. Tento prompt upřesňuje
rychlé provedení: jeho nezávislé vlny se mohou překrývat podle skutečných závislostí.
Nepřepisuj plán kvůli kosmetice. Aktualizuj jen předpoklad vyvrácený důkazy.

## Způsob práce: krátká kritická cesta

1. Udělej jeden společný cílený průzkum. Použij `rg`, potřebné úseky souborů a
   existující důkazy. Ověř rozdíl aktuálního checkoutu a screenshotů pouze nad
   průvodcem, jeho historií a relevantními worktrees. Neaudituj celý repozitář.
   Pro nezávislou práci nezačínej čekat na úplné vyřešení původu screenshotů.
   Chybějící novější zdroj nesmí vést k nekonečnému hledání: zaznamenej výsledek
   a doplň cílové chování do jediného existujícího vlastníka podle plánu.
2. Hned potom rozděl nezávislou práci mezi nejvýše tři subagenty a sebe.
   Každému dej konkrétní výsledek, přesné soubory a relevantní výňatek zadání.
   Předávej jen potřebný kontext. Agentům zakaž editovat sdílené soubory,
   které vlastní jiný pracovník. Nespouštěj paralelní agentní audity.
3. Doporučené rozdělení:
   - Subagent A: UI/UX návrh a implementace samostatných komponent splatnosti,
     komunikace a dokončení draft editoru. Použij `gpt-6-astra`, reasoning
     `medium`, `fork_turns="none"`, UI/UX skill. Musí dodat kód, ne jen návrh.
   - Subagent B: reprodukce a oprava bankovní chyby, SQL/oprávnění a příslušné
     cílené regresní pokrytí. Žádné produkční dotazy nebo migrace.
   - Subagent C: autorizovaný výběr formulářů/plánků nebo čistý renderer náhledu
     podle toho, která nezávislá část má větší rozsah. Konkrétní vlastnictví
     stanov po krátkém průzkumu, bez překryvu s A/B.
   - Ty: vlastníš integraci `occasion_setup_page.dart`, stav konceptu,
     navigaci, základní volby a odkaz. Převezmi také zbývající neobsazenou část.
   Sdílenou hlavní stránku, story model a překladové JSON soubory upravuje jediný
   určený vlastník. Ostatní dodají komponenty nebo přesný integrační požadavek.
4. Dohodni pouze nezbytná rozhraní: hodnoty vs dědění, callback změny konceptu,
   návratový výsledek editoru a vstup/výstup náhledu. Komponenty se mají dát
   integrovat přímo, bez čekání na vzájemné přepisování souborů.
5. Implementuj celé souvislé bloky. Reuse existujících modelů, rendererů,
   oprávnění a katalogů má přednost před novými abstrakcemi. Nevytvářej nový
   design systém, framework, paralelní průvodce, obecný orchestration systém
   nebo další plánovací artefakty.
6. Při čekání na agenta dokončuj vlastní integrační práci. Využívej oznámení
   dokončení, neopakuj polling ani stejný průzkum. Hotové výsledky začleň průběžně.
7. Závěrečné kontroly koordinuje jeden vlastník nad finálními vstupy. Subagenti
   nespouštějí každý vlastní buildy a celé test suites. Neopakuj již úspěšný check
   bez změny jeho vstupů nebo nové konkrétní pochybnosti.

## Povinný výsledný rozsah

- Zdroj události: dvě jasné volby Vytvořit novou událost / Zkopírovat událost;
  u kopie výběr zdroje a částí ke kopírování. Bez duplicitních ovladačů.
- Odkaz: výchozí celý návrh URL a Upravit odkaz; editor a dostupnost až při úpravě.
  Zachovat serverovou validaci i finální atomické přidělení, odstranit duplicity.
- Formulář: připravený nový formulář přímo upravitelný, alternativa Zkopírovat
  formulář. Odstranit Vytvořit/Zkopírovat, počty polí/produktů a nadbytečnou prózu.
- Kopie formuláře funguje i bez zdrojové události. Respektuje oprávnění a hranici
  organizace, má loading/error/empty/search-empty stavy a retry. Žádný prázdný dialog.
- Odstranit dodatečné potvrzení nahrazení formuláře. Cancel/error beze změny;
  předchozí vlastní úpravy obnovitelné podle plánu, včetně souvisejících vazeb.
- Naplánované otevření: při první volbě nyní + 24 hodin, konkrétní datum/čas,
  zachování vlastního termínu a validace intervalů.
- Banky: skutečně reprodukovat a opravit chybu 21000, zachovat oprávnění,
  načíst účty a bezpečně se vrátit do konceptu s obnoveným měnovým směrováním.
  Žádný náhodný LIMIT 1 ani nahrazení opravy pouhým skrytím výjimky.
- Splatnost: stručně počet dní a zapnutí připomínky; její čas jen při zapnutí.
  Zachovat dědění/override a nulu jako okamžitou splatnost. Z hlavního průvodce
  odstranit dlouhou technickou prózu a ukládání organizačních výchozích hodnot.
- Komunikace: srozumitelné vysvětlení E-mailu pro odpovědi, Vykat / Tykat,
  skutečný živý náhled potvrzení objednávky se stejným rendererem, šablonou
  a wrapperem jako odesílání. Náhled bez odeslání, faktur a dalších vedlejších
  účinků; respektovat vlastní statický text a opožděné odpovědi.
- Editor textů e-mailových šablon nyní neimplementovat. Uživatel výslovně zvolil
  náhled nyní a editor jako samostatný navazující krok. To není nedokončený bod.
- Plánek: Bez plánku / Vytvořit nový plánek / Zkopírovat plánek. Skrýt 0 míst
  u prázdného nového plánku. Výběr kopie nezávislý na globálním zdroji události.
- Nový plánek nejdřív otevře výběr šablon včetně Prázdného plánku. Nic předem
  nevkládat. Použít existující doložený katalog; pokud chybí, vyřešit jeho
  minimální skutečnou implementaci podle plánu, ne předstírat hotová data.
- Draft editor: Uložit a vrátit se do průvodce. Návrat na stejnou otázku až po
  potvrzeném flushi konceptu; chyba/conflict ponechá editor. Zachovat guardy
  neuložených změn, odstranit duplicity zahození, nepoškodit běžný živý editor.
- Propojit perzistenci, obnovu starších konceptů, finalizaci, lokalizaci a readiness
  otázek. Kopie nikdy nemění zdroj ani nepřenáší objednávky či rezervace.

## Rychlé ověření bez redundantní práce

Výchozí režim low-risk pro izolované vizuální změny; standard pro SQL, autorizaci,
platby, veřejný preview kontrakt a sdílený renderer. Neprováděj plný release build.

- Před kontrolami sjednoť finální změny; používej existující testovací infrastrukturu.
- Jednou spusť potřebný cílený analyzer, skutečně sbírané widget testy a dotčené
  SQL/renderer testy. Nepsat testy jen pro přesné české texty nebo zjevnou implementaci.
- SQL chybu a bezpečnostní hranice ověř skutečnou regresní fixture na disposable DB.
  Ověř nenulový počet vybraných SQL testů i skutečný import cases do entrypointů.
- Nejvýše jeden Flutter task na workstation; testy `--concurrency=1`.
  Zkontroluj obsazení slotu. Nezastavuj cizí úlohu. Dart analyze nespouštěj souběžně
  s jinou Flutter/FVM úlohou, kterou by porušil limit.
- Nezávislé lehké SQL a renderer kontroly lze provést souběžně s jedinou povolenou
  Flutter úlohou. Těžké buildy a přípravu backendu neduplikuj mezi agenty.
- Jeden společný lokální E2E průchod nové události a cílený doplňkový scénář kopie
  a obnovy pokryjí všechny změněné přechody. Použij existující podporovaný E2E
  runner, přečti festapp-local-e2e skill, znovu využij vhodné izolované prostředí.
- Vizuálně ověř úzký/desktop layout, světlý/tmavý motiv, focus a návrat z editoru.
  Browser pouze headless/izolovaně na pozadí; uživatelův Chrome nech nedotčený.
- Passing check znovu nespouštěj, pokud jeho vstupy zůstaly stejné. Selhání řeš
  cíleně podle konkrétní příčiny; nerozšiřuj testování bez důvodu na celý repozitář.

## Rozhodování, hranice a dokončení

Rutinní implementační rozhodnutí řeš samostatně. Neptej se opakovaně na potvrzení
již zadané práce. Skutečnou chybějící produktovou volbu polož stručně a pokračuj
na nezávislých částech; nevymýšlej odpověď, která mění rozsah nebo oprávnění.

Zachovej cizí rozpracované změny. Bez samostatného zadání neprováděj commit, push,
produkční migraci ani deployment. Tvorba tohoto promptu sama implementaci nespouští;
jeho zadání vykonávajícímu agentovi je pokynem provést popsanou implementaci.

Dokončeno znamená funkční celý balík podle plánu, žádná slepá tlačítka,
placeholders ani duplicitní cesty. Na konci dej nejvýše pět stručných bodů:
provedené změny, skutečné ověření a přesný případný blocker. Jasně rozliš
lokální implementaci od nasazení. Neopakuj dlouhý popis pracovního postupu.
