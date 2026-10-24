# Formuláře a zakládání akcí - druhý průchod UI/UX, 23. 10. 2026

Souhrnná stránka: [QA zápisník](qa-overview.html).

Výsledek: **6 nových nálezů** (1x P1, 4x P2, 1x P3). Hlavní problém: editor dovolí uložit povinné výběrové pole bez možností a celý veřejný formulář pak ukáže „Rezervace nedostupná“.

Navazuje na [první průchod](exploratory-ui-ux-qa-2026-10-23.md). Bez změn produktového kódu, produkčních zápisů a odesílání e-mailů. Nejde o ověření nasazené produkce.

## Prostředí a metoda

Aktuální necommitnutý pracovní strom na `feat/occasion-setup-wizard-20261007`, HEAD `eb2304724`. Skutečná aplikace přes `test/browser/occasion_setup_e2e.dart`, podpora aplikace zapnutá, nový průvodce vypnutý. Testováno běžné vytváření a kopírování.

Vlastní Supabase projekt `festapp-wizard-ux-20261023`, API/DB `56821/56822`, Flutter `56880`. Po předchozím zastavení bez zálohy byla databáze prázdná; před tímto průchodem znovu dostala kanonický baseline, dopředné migrace a syntetický seed. Data prvního průchodu proto nejsou součástí tohoto běhu.

Izolovaný headless Chromium `festapp-forms-qa-20261023`, prázdná konfigurace, desktopové viewporty 1440 x 1000 a po obnově prohlížeče 1280 x 720. Produkční Festapp, Supabase Cloud a OneSignal požadavky blokované, externí push callbacky nahrazené existující fixture. Použité přístupnostní kliky i skutečné pointer kliky na karty polí. Výsledky ukládání potvrzené čtením lokální DB. Nejde o kompletní certifikaci pointer hitboxů, mobilu ani čtečky obrazovky.

Při práci s fokusem se zasekla automatizace prohlížeče. Obnoven byl pouze vlastní headless proces. Tato událost není vykázaná jako chyba aplikace. [První záznam](evidence/forms-occasion-qa-2026-10-23/forms-events-recovered.webm) byl po ukončení prohlížeče remuxován; končí po 276 sekundách. [Pokračování](evidence/forms-occasion-qa-2026-10-23/forms-events-continued.webm) obsahuje zbývající průchod a kontrolní scénáře. Jde o surové záznamy, nikoli sestříhané demonstrace.

## Ověřené funkční průchody

| Scénář | Výsledek |
| --- | --- |
| Založení akce s vlastním odkazem `qa-formulare` | Prošlo |
| Založení formuláře `qa-workshop` | Prošlo |
| Přidání textového pole a vlastní název Jméno a příjmení | Uloženo, potvrzeno v DB |
| Kapacita 12 osob, náhradníci, nabídka 1.5 hodiny | Uloženo jako 12 / true / 5400 sekund |
| Kopie formuláře | Zachovala 4 pole, kapacitu 12, náhradníky i 5400 sekund |
| Kopie celé akce běžnou akcí Vytvořit kopii | Zachovala všechny 3 formuláře a jejich pole i uvedené limity |
| Prázdný název při zakládání formuláře | Vytvořit správně zakázáno |
| Kolize odkazu při založení akce, poté změna na volný | Konflikt bezpečně nevytvořil záznam; změna na `qa-formulare-recovery` vytvoření umožnila |
| Otevření formuláře pro účastníka | S prázdným výběrovým polem selhalo, po doplnění jediné možnosti prošlo |

[Stav formuláře před kopírováním](evidence/forms-occasion-qa-2026-10-23/form-baseline.json), [kopie formuláře](evidence/forms-occasion-qa-2026-10-23/copied-form-state.json), [kopie akce](evidence/forms-occasion-qa-2026-10-23/occasion-copy-state.json). Finální lokální stav obsahoval 0 objednávek a 0 zpráv v e-mailové frontě: [souhrn](evidence/forms-occasion-qa-2026-10-23/final-state.json).

## 1. P1 - Prázdné výběrové pole znepřístupní celý veřejný formulář

Reprodukce:

1. Otevřít editor existujícího formuláře.
2. Přidat pole > Jedna možnost. Nezadat žádnou možnost.
3. Otevřít kartu pole a zaškrtnout Povinné.
4. Uložit. Editor uložení přijme a po reloadu stále ukazuje Jedna možnost * / Žádné možnosti.
5. Zapnout dostupnost formuláře a uložit.
6. Otevřít lokální `/form/qa-workshop`.

Skutečnost: celý účastnický formulář se nenačte. Místo něj je **Rezervace nedostupná / Rezervace na vybranou událost není momentálně dostupná.** DB přitom má `is_open=true` a veřejné RPC vrací `code=200`.

Uložené nové pole mělo lokální ID 23, `type=select_one`, `is_required=true`, `title=NULL`, `data=NULL`. Kontrola přes skutečné UI: přidání jediné volby Ranní skupina, uložení a otevření stejné veřejné URL obnovilo celý formulář. Výsledná data pole: `{"options":[{"value":"Ranní skupina"}]}`. Ostatní konfigurace zůstala stejná.

Příčina odpovídá kódu: `FormHolder.createFieldHolder` čte `ffm.data[FormMetadata.metaOptions]` bez kontroly null. `FormPage.loadData` výjimku zachytí a zobrazí obecnou nedostupnost. Samostatně chybí zabránění uložení povinného pole bez odpověditelné volby.

Oprava má zahrnout validaci definice při ukládání i bezpečné načtení dříve uložených konfigurací. Nezaměňovat chybu definice s vypnutou registrací. Kompletní účastnické odeslání přes Edge službu se netestovalo.

Důkazy: [uložené povinné pole po reloadu](evidence/forms-occasion-qa-2026-10-23/empty-required-after-reload.png), [nedostupný veřejný formulář](evidence/forms-occasion-qa-2026-10-23/public-empty-choice-attempt.png), [kontrola po doplnění jediné volby](evidence/forms-occasion-qa-2026-10-23/public-choice-control.png).

## 2. P2 - Kolize odkazu při zakládání akce selže bez vysvětlení

Reprodukce: založit další akci, zadat název QA Kolize události a již použitý odkaz `qa-formulare`, kliknout Vytvořit.

Skutečnost: `create_occasion_client_sync_v1` vrátí HTTP 409, akce nevznikne, ale dialog zůstane beze změny, bez chybové zprávy a bez označení problematického pole. Tlačítko Vytvořit zůstane dostupné. Po změně odkazu na `qa-formulare-recovery` stejný dialog akci úspěšně vytvořil.

V `OccasionCreationHelper.createNewOccasion` chybí kolem asynchronního `DbOccasions.updateOccasion` zpracování této chyby. Doplnit českou chybu přímo k odkazu, zachovat návrh a umožnit opravu.

Důkazy: [dialog po odmítnutí](evidence/forms-occasion-qa-2026-10-23/occasion-duplicate-slug-silent.png), [snapshot](evidence/forms-occasion-qa-2026-10-23/occasion-duplicate-slug.snapshot), [HTTP výsledky](evidence/forms-occasion-qa-2026-10-23/creation-statuses.txt).

## 3. P2 - Kolize odkazu formuláře ukáže technickou databázovou výjimku

Reprodukce: Vytvořit/Zkopírovat formulář > nový prázdný formulář > název QA Kolize odkazu > již použitý odkaz `qa-workshop` > Vytvořit.

Skutečnost: dialog zobrazí `PostgrestException(message: Public link is already in use, code: 23505, details: Conflict, hint: null)`. Konflikt nic nepřepsal ani nevytvořil. Výsledek je technická anglická chyba místo srozumitelné informace k poli.

`FormCreationHelper.showCreateFormDialog` v catch přímo použije `e.toString()` jako `linkError`. Mapovat známý konflikt na českou zprávu typu Tento odkaz už je obsazený. Nezobrazovat databázové detaily. Zotavení úpravou odkazu v témže dialogu zde není certifikované kvůli nejistotě při automatizaci fokusu.

Důkazy: [snímek](evidence/forms-occasion-qa-2026-10-23/duplicate-form-slug.png), [snapshot](evidence/forms-occasion-qa-2026-10-23/duplicate-form-slug.snapshot).

## 4. P2 - Česká desetinná čárka je odmítnutá jako nekladné číslo

Reprodukce: Nastavení formuláře > kapacita 12 > povolit náhradníky > Platnost nabídky (hodiny) = `1,5` > Uložit.

Skutečnost: validace ukáže **Zadejte kladné číslo**. Hodnota je kladná a používá český desetinný oddělovač. Kontrola s `1.5` prošla a DB uložila 5400 sekund.

V `FormSettingsContent` používá validátor i serializace `double.tryParse` bez normalizace desetinné čárky. Použít stejný parser podle jazyka v obou místech, případně jasně uvést akceptovaný formát. Další desetinná pole nebyla nezávisle ověřovaná.

Důkaz: [zamítnutí 1,5](evidence/forms-occasion-qa-2026-10-23/waitlist-decimal-comma.png), kontrolní uložení s tečkou je v [DB stavu](evidence/forms-occasion-qa-2026-10-23/form-baseline.json).

## 5. P2 - Povinný název lze později smazat v nastavení formuláře

Reprodukce: otevřít Nastavení existujícího formuláře, nahradit Název formuláře jednou mezerou a Uložit.

Skutečnost: uloží se `title=NULL`, navigace místo názvu zobrazí `qa-workshop`. Stejný prázdný název při zakládání formuláře tlačítko Vytvořit správně zakáže. Validace vytvoření a úprav tedy není konzistentní. Název byl následně obnoven přes UI a ověřen v DB před kopírováním.

`FormSettingsContent` při ukládání prázdný ořezaný název převádí na null, ale vstup nemá odpovídající validátor. Sjednotit pravidla pro vytvoření a editaci; technický slug nemá tiše zastupovat smazaný název.

Důkazy: [uložený prázdný název](evidence/forms-occasion-qa-2026-10-23/empty-title-saved.png), [kontrola vytvoření se zakázaným tlačítkem](evidence/forms-occasion-qa-2026-10-23/create-empty-title.snapshot).

## 6. P3 - Kopie formuláře má anglické označení v českém rozhraní

Reprodukce: v českém UI zkopírovat QA Přihláška na workshop přes Vytvořit/Zkopírovat formulář.

Skutečnost: nová karta se jmenuje **QA Přihláška na workshop (copy)**. Kopie celé akce ve stejném běhu dostala správně české **(kopie)**. Navíc nový výchozí formulář a produkt mají názvy Registration / Spot / Variant 1; ty jsou zaznamenané jako kontext, nikoli samostatně prokázané lokalizační regresní nálezy.

`duplicate_form_to_occasion_internal_v1` natvrdo volá `copy_occasion_title_internal(title,'en')` a klient při kopii nepředává jazyk. Předat jazyk záměru stejně jako při kopii akce.

Důkazy: [kopie formuláře](evidence/forms-occasion-qa-2026-10-23/form-copy-english-title.png), [česká kopie akce](evidence/forms-occasion-qa-2026-10-23/occasion-copied.png).

## Omezení a další postup

Neověřeno: nový vícekrokový průvodce, seat mapy, bankovní/Stripe integrace, média přes R2, skutečné e-maily, objednávky a platby, nativní telefon. Žádné GitHub issues se nezakládaly a opravy nebyly provedené.

Priorita oprav: nejprve prázdná výběrová pole a pravdivá chyba při jejich načítání, potom obě kolize odkazů, konzistence názvu a číselné zadávání. Lokalizace kopie je drobný samostatný úkol. [Otisky relevantních zdrojů](evidence/forms-occasion-qa-2026-10-23/source-digests.json) identifikují testovanou podobu necommitnutého pracovního stromu.
