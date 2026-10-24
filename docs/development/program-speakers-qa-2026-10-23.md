# Program, přednášející a nastavení - třetí průchod UI/UX, 23. 10. 2026

Souhrnná stránka: [QA zápisník](qa-overview.html).

Výsledek: **4 nové nálezy P2**. Průchod rozšířil testování mimo formuláře na program, správu přednášejících, přepínání kontextu a konfiguraci typů událostí. Produktový kód nebyl opravován.

## Stav oprav - 23. 10. 2026

Všechny čtyři nálezy třetího průchodu jsou opravené v lokálním pracovním stromu:

- QA-011: formatter přijímá prázdnou hodnotu; výběr místa má explicitní prázdnou volbu a dekódování ukládá nepřiřazené místo jako `null`.
- QA-012: přepínač rozpoznává aktivní rodičovskou routu administrace, rezervací a správy jednotky přes `root.currentSegments` a identity rout.
- QA-013: ukládání přednášejícího sestaví samostatný model s původním ID, verzí a metadaty. Odmítnuté uložení nemění sdílenou entitu a Storno ji zachová pro další otevření.
- QA-014: nové typy dostávají volný kód; stabilní identity řádků zachovávají správné hodnoty po mazání. Formulář odmítá prázdné a duplicitní kódy i při sbalené sekci. Chyba je přeložená do všech šesti jazyků.

Regresní sada [program_qa_regression_test.dart](../../test/components/qa/program_qa_regression_test.dart) prošla: **7 testů**. Ověřuje prázdné místo a jeho dekódování, smazání/přidání typu, validaci včetně sbalené sekce, skutečný editor přednášejícího s odmítnutým HTTP uložením a následným Storno/otevřením, a skutečný app bar se vnořenými routami ve čtyřech kombinacích administrace/rezervací a sekce.

Společný závěrečný běh nové sady a existujících `data_grid_helper_cases.dart` / `event_grid_record_cases.dart`: **12 testů prošlo**. Cílená analýza nehlásí chyby ani varování; v okolním kódu zůstávají stávající informační linty. Kontrola JSON překladů prošla pro šest jazyků.

Jde o lokální widgetové/kontraktní ověření se simulovaným HTTP backendem. Celý původní browserový průchod ani produkční nasazení se neopakovaly. Původní důkazy níže popisují stav před opravou; starší průchody jsou mimo tento zásah.

## Prostředí a metoda

Aktuální pracovní strom na `feat/occasion-setup-wizard-20261007`, HEAD `353394511`, včetně existujících lokálních změn. Starší nálezy z předchozích průchodů nebyly znovu ověřované proti tomuto novějšímu stavu.

Vlastní projekt `festapp-wizard-ux-20261023` obnovený z lokální zálohy. API/DB `56821/56822`, skutečná Flutter aplikace `test/browser/occasion_setup_e2e.dart`, server `56880`, podpora aplikace zapnutá. Příprava přes `automation/run_occasion_setup_local.py --prepare-only --app-supported`; následný `automation/baseline.py upgrade-local` vrátil `applied=[]`. Produkční data ani služby se nepoužily.

Izolovaný headless Chromium `festapp-program-qa-20261023`, 1440 x 1000, explicitně prázdná konfigurace. Produkční Festapp, Supabase Cloud a OneSignal požadavky blokované. Pokračuje lokální akce QA Formuláře a nastavení, ID 1. Syntetická položka programu QA Workshop - program, ID 1, byla vložena jako databázová fixture pro další scénáře; její vznik není vydáván za úspěšné vytvoření přes tabulku. Přednášející Eva QA i vazba na program vznikli přes skutečné UI.

Po úvodním načtení a reprodukci první chyby byl vlastní Flutter server ukončen kvůli sdílenému Flutter slotu pro souběžný release. Další kroky proběhly v již načtené SPA proti dále běžícímu lokálnímu backendu. Fyzický reload, načtení dalšího dokumentu a veřejný program se v této části neověřovaly. Použity přístupnostní kliky i běžné pointer kliky; nejde o certifikaci všech hitboxů ani nativního telefonu.

U nálezu 3 bylo záměrně přerušeno pouze lokální RPC `save_speaker_client_sync_v1` pomocí browserové route `--abort`. Nejde o tvrzení, že nastal skutečný výpadek produkce. Po reprodukci byla route odstraněna a původní jméno obnoveno úspěšným uložením. Duplicitní kód z nálezu 4 byl po zachycení důkazů ručně změněn na unikátní.

## Prošlé a omezené scénáře

| Scénář | Výsledek |
| --- | --- |
| Otevření prázdné správy programu | Prošlo |
| Přidání prvního řádku bez existujících míst | Chyba buňky Místo, nález 1 |
| Zahození rozpracovaného řádku | Potvrzení i zahození prošlo |
| Vytvoření Evy QA z výběru přednášejících v programu | Prošlo; jméno a role ověřeny v DB |
| Automatické přiřazení nového přednášejícího k programu | Prošlo; `event_speakers` obsahuje vazbu 1 / 1 |
| Otevření správy přednášejících a existujícího editoru | Prošlo |
| Selhání uložení, Storno a nové otevření | Neuložená změna zůstala v editoru, nález 3 |
| Otevření prázdné správy míst a jejích záložek | Prošlo; vytvoření konkrétního místa se neověřovalo |
| Vyhledání Program v nastavení funkcí | Prošlo |
| Přidání, odebrání a opětovné přidání typu programu | Uložily se duplicitní kódy, nález 4 |
| Oprava lokální testovací konfigurace na dva unikátní kódy | Prošlo |

[Finální stav](evidence/program-speakers-qa-2026-10-23/final-state.json) obsahuje 0 objednávek a 0 zpráv v e-mailové frontě. [Surový záznam průchodu](evidence/program-speakers-qa-2026-10-23/program-settings.webm) zachycuje testování i obsluhu automatizace.

## 1. P2 - První nový řádek programu vykreslí chybu v prázdném místě

Reprodukce: v akci, která nemá žádná místa, otevřít Správa události > Program > Program a stisknout Přidat.

Skutečnost: nový řádek vznikne, ale v buňce Místo se vykreslí chybový widget s `NoSuchMethodError: indexOf`, `Receiver: null`, `Arguments: [":"]`. Ostatní části tabulky zůstaly dostupné a rozpracovaný řádek šel zahodit. Nebylo potvrzené úspěšné vytvoření položky z tohoto řádku; není proto tvrzeno úplné zablokování aplikace.

V `ScheduleContent` je místo select nad prázdným seznamem a jeho formatter je `DataGridHelper.getValueFromFormatted`. Helper bez kontroly null volá `value.indexOf(":")`. Při vytvoření prvního řádku je hodnota null.

Směr opravy: prázdné nepovinné místo bezpečně vykreslit a zpracovat i při ukládání. Přidat odpovídající prázdný výběr; nezakládat povinnou vazbu jen kvůli chybě formatteru.

Důkazy: [nový řádek s chybou](evidence/program-speakers-qa-2026-10-23/program-new-row.png), [výpis výjimky](evidence/program-speakers-qa-2026-10-23/program-new-row-error.txt).

## 2. P2 - Přepínač kontextu zamění administraci za Zobrazit aplikaci

Reprodukce: otevřít `/qa-formulare/admin/events/schedule` a rozkliknout poslední část horního breadcrumbu. Stejný chybný popisek zůstal i po přechodu do Info.

Skutečnost: v administraci je v breadcrumbu napsáno **Zobrazit aplikaci**. Rozbalená nabídka obsahuje jen Rezervace a Správa události. Položka pro vstup do aplikace v této nabídce chybí, protože je chybně považovaná za aktuální kontext. Tento přepínač tak neposkytuje očekávanou cestu do účastnické aplikace. Nejde o tvrzení, že neexistuje žádná jiná cesta.

`AppPanelHelper` určuje kontext přes `originalContext.routeData.path` a `endsWith(admin/reservations)`. V kontextu vnořené záložky to nerozpozná rodičovskou administraci a zvolí `viewAppAction`; menu následně aktuální akci odfiltruje.

Směr opravy: kontext určit podle skutečné rodičovské routy, ne koncovky lokálního path. Ověřit administraci i rezervace v několika vnořených sekcích.

Důkazy: [chybný breadcrumb a nabídka](evidence/program-speakers-qa-2026-10-23/admin-action-picker.png), [snapshot](evidence/program-speakers-qa-2026-10-23/admin-action-picker.snapshot).

## 3. P2 - Neúspěšně uložená změna přednášejícího přežije Storno

Reprodukce:

1. Ve správě přednášejících otevřít Evu QA.
2. Změnit jméno na Eva QA - neuložená změna.
3. Při přerušeném lokálním `save_speaker_client_sync_v1` kliknout Uložit a nechat pokus selhat.
4. Odstranit přerušení, zavřít dialog přes Storno a znovu otevřít úpravu stejné osoby.

Skutečnost: znovu otevřený editor obsahuje **Eva QA - neuložená změna**, zatímco karta za dialogem a DB stále obsahují **Eva QA**. Neuložená změna tedy unikla do sdíleného modelu a neodpovídá uloženému stavu. Při selhání nevznikl nový databázový zápis.

`SpeakerEditorDialog._performHtmlSave` před odpovědí serveru mění přímo `widget.speaker` pomocí cascade. Po selhání vrátí Storno hodnotu false a `SpeakersTab._openSpeakerEditor` neobnoví seznam. Další editor tak převezme již změněný objekt.

Směr opravy: editovat samostatný koncept a sdílený model nahradit až potvrzeným výsledkem. Případně při odmítnutí obnovit původní model; Storno nesmí působit jako zachování neuložené změny do entity.

Důkazy: [editor po opětovném otevření](evidence/program-speakers-qa-2026-10-23/speaker-phantom-after-cancel.png), [snapshot](evidence/program-speakers-qa-2026-10-23/speaker-phantom-after-cancel.snapshot), [souběžný uložený stav DB](evidence/program-speakers-qa-2026-10-23/speaker-persisted-state.json), [zachycené požadavky](evidence/program-speakers-qa-2026-10-23/speaker-save-network.txt).

## 4. P2 - Opětovné přidání typu programu vytvoří a uloží duplicitní kód

Reprodukce:

1. Nastavení > Hledat funkce: Program > Typy událostí.
2. Z prázdného seznamu dvakrát Přidat typ události. Vzniknou `new_type_1` a `new_type_2`.
3. Odebrat první typ.
4. Znovu Přidat typ události.
5. Uložit nastavení.

Skutečnost: oba zbývající typy mají **new_type_2**. UI chybu nehlásí a DB uloží oba záznamy se shodným kódem. Uživatelský zásah do kódu nebyl pro vznik chyby potřeba. Downstream pád výběru typu ani vykreslení veřejného programu se v tomto průchodu neověřovaly.

`_ScheduleFeatureFormState._addEventType` generuje kód z `_eventTypes.length + 1`, nikoli z nezabraného identifikátoru. V tomto scénáři také nezasáhla validace unikátnosti před uložením. Kód je identitou typu používanou položkami programu; dva typy tak nelze spolehlivě rozlišit podle této identity.

Směr opravy: generovat nezabraný kód a při ukládání vyžadovat unikátnost v rámci akce. Po zachycení důkazů byl druhý testovací kód ručně změněn na `new_type_3` a ověřen úspěšný zápis unikátní dvojice.

Důkazy: [původní dva typy](evidence/program-speakers-qa-2026-10-23/event-types-two.png), [automaticky vzniklá duplicita](evidence/program-speakers-qa-2026-10-23/event-types-duplicate-code.png), [uložené duplicitní nastavení](evidence/program-speakers-qa-2026-10-23/schedule-feature-saved.json).

## Omezení a další postup

Neověřeno: dokončení tvorby položky programu přes tabulku, celý samostatný editor položky programu, účastnické přihlašování na workshopy, veřejné vykreslení duplicitních typů, reálné notifikace a média. Žádné produkční operace, publikace ani opravy aplikačního kódu se neprováděly.

Nálezy jsou samostatné vůči dřívější vadě přístupnostního stromu zachovaných záložek. Doporučené opravy: bezpečný prázdný řádek, správné určení navigačního kontextu, izolované koncepty přednášejících a unikátní identifikátory typů. [Otisky zdrojů](evidence/program-speakers-qa-2026-10-23/source-digests.json) zachycují testovanou podobu souborů.
