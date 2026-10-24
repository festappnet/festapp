# Exekuční prompt: kompletní ukázkové akce

Implementuj v `/Users/miakh/source/festapp` celý autoritativní plán:
`docs/plans/demo-occasions-plan-2026-10-14.md`

Nejdřív přečti plán, `AGENTS.md`, `CLAUDE.md` a `docs/architecture/ai_context.md`. Použij relevantní skills `focused-development` a `ux-designer`; pro nutné čtení referencí z backendu `festapp-backend-access`. Zachovej ostatní rozpracované změny. Jde o zadání implementace, pokračuj až k funkčnímu a ověřenému výsledku, nezůstávej u dalšího návrhu.

## Výsledek

- Tři kompletní společné ukázky: ples, koncert a víkendovka. Jsou serverově pouze ke čtení, dostupné novým i stávajícím uživatelům. Každou lze idempotentně zkopírovat do oprávněné vlastní Unit jako běžnou editovatelnou akci. Kopíruje se konfigurace, obsah a grafika, nikoli demo účastníci, historie, účet, transakce a obsazenost. Výsledek je nejprve skrytý s uzavřenými formuláři.
- Ples vychází strukturou a plánkem ze skautského nebo větřkovického plesu, s 200-300 fiktivními účastníky. Všechny osobní a transakční údaje generuj synteticky. Popisky formulářů a vhodné grafické podklady mohou vycházet z reálných akcí, s přizpůsobením konkrétních údajů.
- Všechny ukázky mají věrohodné objednávky, fiktivní účty a provázané transakce. Ples ukazuje i nedoplatek, dělenou úhradu, přeplatek a nespárovanou platbu. Menšina objednávek má storno nebo změnu s historií; ceny, úhrady, vstupenky a obsazenost musí sedět. Bez skutečného bankovního napojení a platebních instrukcí.
- Víkendovka má náhradníky, navrženě 24 přijatých a 4 čekající, a historii přijetí po uvolnění místa. Použij současný waitlist kontrakt, stejné ticket ID při přijetí a kapacitní formulář bez seat-picker blueprintu. Čekající nemají finance, produkty ani platný vstupní QR. Nabídky a jejich historie jsou pouze k prohlížení.
- Každá ukázka má vlastní propracovaný styl plánku, formuláře a vstupenky. Použij existující blueprint editor, ticket layout schema 3 a společný PDF renderer. Ověř skutečné výsledné PDF, diakritiku, dlouhé údaje a QR. Grafika vlastní kopie zachová kvalitu a nebude obsahovat demo označení ani zapečené datum/název zdroje.

## UI/UX, které musí být součástí implementace

Bez vlastních akcí nebo návrhů zobraz výraznou sekci se třemi kartami a titulkem „Podívejte se, co můžete vytvořit“. Karty vedou na „Prohlédnout ukázku“, vlastní založení akce zůstává dostupné. S vlastními akcemi/návrhy mají prioritu ony; ukázky zpřístupni kompaktním odkazem „Inspirujte se ukázkovými akcemi“, který rozbalí stejnou sekci. Použij jeden sdílený blok. Žádný povinný onboarding nebo popup.

Stav určuj z nefiltrovaných oprávněně spravovaných nedemo akcí a návrhů aktuálního tenanta; nulový výsledek hledání není nový účet. Fungovat musí i účet bez Unit. Po první kopii přejdi do kompaktního stavu a otevři její existující nastavení. V ukázce je úsporný read-only banner, jedno hlavní CTA pro vlastní kopii a cesta zpět. Respektuj loading/error stavy, mobil a klávesnici podle plánu.

## Rychlý a efektivní postup

1. Proveď jednu cílenou kontrolu současných kontraktů a referenčních podkladů. Neopakuj již doložený průzkum celého repozitáře. Pokud fakt v plánu neplatí, oprav jej podle kódu a pokračuj; běžná implementační rozhodnutí vyřeš samostatně.
2. Nejprve dotáhni svislý průřez plesu: podklady a vizuál, ochrana zdroje, syntetická data, prohlížení a čistá kopie. Potom stejnou mechaniku použij pro koncert a víkendovku. Dokončeny musí být všechny tři.
3. Recykluj existující oprávnění ke čtení, seznamy, formuláře, kopírování, finanční přehledy a renderery. Rozdíly akcí ulož jako data. Nevytvářej marketplace, nový editor, druhý finanční model, obecný verzovací systém ani další průvodce kopírováním. Katalog načítá jen metadata, detail a PDF až při otevření.
4. Dělej souvislé změny a validaci dávkuj po funkčních celcích. Použij verification: standard kvůli oprávněním a finančním/datovým kontraktům. Cílené SQL a modelové testy, jeden hlavní lokální E2E průchod plesu a krátké kontroly specifik koncertu/víkendovky. Již úspěšný test neopakuj, pokud se jeho pokrytý kód nezměnil. Nevytvářej agentní audit bez výslovného požadavku.
5. Prohlédni skutečné vizuální výstupy všech tří akcí, jejich PDF a oba stavy nabídky ukázek na desktopu a mobilu. Použij izolované lokální E2E dle repo skills, bez narušení uživatelova prohlížeče. Průběžné aktualizace stručně, bez vyprávění každé operace.

Rychlost nesmí obejít serverové read-only kontroly, izolaci tenanta, ochranu bankovního účtu a nespárovaných pohybů, zákaz vedlejších efektů, idempotenci kopie ani kvalitu výstupů. Nespoléhej pouze na skrytá tlačítka. Bezpečnost ošetři ve společných hranicích a samostatně pouze tam, kde je volající obchází.

Toto zadání pokrývá lokální implementaci a ověření. Produkční migrace, seed/upload, release, commit a push nejsou jeho součástí bez dalšího výslovného zadání. Dokonči všechny nezávislé lokální práce i při chybějícím produkčním podkladu a uveď konkrétní zbývající závislost. Na konci stručně uveď výsledek, odkazy na vizuální důkazy/PDF, provedené kontroly a případné kroky zbývající k aktivaci. Neoznačuj nedokončenou část za hotovou.
