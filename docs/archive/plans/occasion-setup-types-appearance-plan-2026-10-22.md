# Průvodce podle typu akce a společný vzhled

Datum: 2026-10-22
Stav: implementováno lokálně; cílené ověření a provozní hranice jsou v `occasion-setup-types-appearance-VERIFICATION-2026-10-22.md`.
Ověřování: standard pro oprávnění, SQL a sdílený renderovací kontrakt.

## Výsledek a vztah k předchozím plánům

Uživatel zadá název a termín, vybere typ akce a její vzhled. Dále vyplňuje pouze relevantní nastavení. Formulář a případná vstupenka používají společné barvy nebo gradient a písmo. Začátečník bez předloh neřeší kopírování.

Tento plán je autoritativní pro nové připomínky z pěti screenshotů a navazujícího popisu. V těchto bodech nahrazuje pořadí a pravidla v `occasion-setup-ux-plan-2026-10-22.md` a starším wizard plánu. Jejich ostatní požadavky, například komunikace a návrat z editoru sálu, zůstávají samostatně platné. Starší popis aktuálního počtu otázek již neodpovídá pracovnímu stromu.

Implementace proběhla v existujícím pracovním stromu se zachováním ostatních změn. Nová migrace byla aplikována pouze na vlastní disposable lokální databázi. Commit, push, živá migrace ani nasazení nejsou součástí tohoto zadání.

## Ověřený základ

Průzkum: větev `feat/occasion-setup-wizard-20261007`, HEAD `eb2304724`, včetně necommitnutého pracovního stromu.

| Fakt | Konkrétní místo | Dopad |
|---|---|---|
| Otázky jsou definované podle `appSupported`, nikoli typu akce a dostupnosti zdrojů. | `lib/components/occasion/setup/occasion_setup_story.dart`, `questions`, `index` | Rozšířit jeden resolver aktivního toku. |
| Otázka zdroje a tlačítko kopie formuláře se vykreslují bez podmínky skutečné dostupnosti. | `occasion_setup_page.dart`, `_body`, case 0 a 3 | Skrýt až po úspěšném ověření prázdného seznamu. |
| Seznam předloh načítá vybranou jednotku; SQL povoluje zdrojovou jednotku stejné organizace a kontroluje `can_copy_occasion_source`. | `database/functions/occasion_setup/sources.sql`, `get_occasion_setup_source_list`, `get_occasion_setup_source` | Jediná vybraná jednotka neprokazuje neexistenci předloh u uživatele. Rozšíření přehledu nesmí rozšířit právo kopie. |
| Odkaz je nyní sloupec čtyř prvků. Název formuláře je samostatné editovatelné pole. | `occasion_setup_form_link.dart`, `build`; `occasion_setup_page.dart`, case 3 | Upravit kompozici a odstranit pole názvu z průvodce. |
| Vazba názvu formuláře na událost již částečně existuje. | `occasion_setup_page.dart`, `_change`, `formDefaultsFollowEvent` | Doplnit jednoznačné pravidlo i pro kopie a obnovené koncepty. |
| Vzhled formuláře již nabízí barevné presety a písmo; vstupenka má vlastní model a editor. | `forms/views/form_design_settings.dart`; `features/ticket_feature.dart`; `ticket_layout/models/ticket_layout.dart` | Znovu použít editory a katalogy, sjednotit vstupní rozhodnutí o stylu. |
| Preview vstupenky nyní potřebuje ID dostupné zdrojové události. | `occasion_setup_page.dart`, `_ticketSettings` | Nový uživatel musí dostat náhled nad vlastním draftem bez předlohy. |
| Progress konceptu používá pevná ID kroků; UI, validace a finální SQL nejsou jeden seznam. | `occasion_setup_draft.dart`, `supportedSteps`, `progress`; `occasion_setup_page.dart`, `_valid`, `_reviewBody`; `database/functions/occasion_setup/finalize.sql` | Změna toku musí zahrnout dokončování, obnovení i serverové podmínky. |
| Finalizace už ukládá formulář, vstupenkový feature a přemapovává odkazy layoutu. | `database/functions/occasion_setup/finalize.sql` | Nevytvářet druhou cestu založení ani kopírování. |
| Veřejný formulář má vlastní aplikaci fontu a tématu. | `web_client/src/services/theme_service.js` | Náhled v průvodci nestačí; ověřit skutečný veřejný render a PDF. |
| Horní segmenty v tomto pracovním stromu nemají callback pro kliknutí a jejich stav se odvozuje jen z pozice. | `occasion_setup_story_shell.dart`, `build`; `occasion_setup_page.dart`, `_wizard`; `occasion_setup_story_shell_test.dart` | Uživatelský požadavek na přepínání klikem je závazný; nelze předpokládat, že ho tento shell již implementuje. Pozice neprokazuje dokončení otázky. |

## Navržený uživatelský tok

Volitelný úvod **Jak má událost vzniknout?** zobrazit jen tehdy, má-li uživatel alespoň jednu oprávněně kopírovatelnou událost. V něm zůstanou volby Vytvořit novou událost / Zkopírovat událost a výběr částí kopie. Navrhuji tento úvod nečíslovat, aby vlastní vzhled byl opravdu čtvrtou otázkou. Bez předloh se rovnou založí cesta nové události.

| Pořadí | Otázka | Obsah |
|---|---|---|
| 1 | Jak se akce jmenuje? | Název události. |
| 2 | Kdy se koná? | Začátek a konec společně, existující časová zóna a validace intervalu. |
| 3 | Jaký typ akce připravuješ? | Tři volby s krátkým popisem, viz níže. |
| 4 | Jak má akce vypadat? | Presety, vlastní barvy/písmo, náhled formuláře a podle typu i vstupenky. |
| dále | Jen relevantní nastavení | Formulář, vstupenky/produkty, sál, otevření registrace/prodeje, případné platby, komunikace, kontrola. |

Záhlaví vedle názvu může stručně ukazovat například „Ples · vstupenky a rezervace míst“. Uživatel tak průběžně vidí, co vytváří. Počet číslovaných otázek odpovídá aktuálně aktivní cestě; volitelná kontrolní pomůcka nezvyšuje povinný počet.

### Typy akcí

| Volba | Popis pro uživatele | Formulář | Vstupenka | Sál a místa |
|---|---|---|---|---|
| Běžná akce | Přihlášení účastníků přes formulář. | Ano | Ne | Ne |
| Koncert | Vstupenky bez výběru konkrétního místa. | Ano | Ano | Ne |
| Ples | Vstupenky s rezervací konkrétních míst v sále. | Ano | Ano | Ano |

Typ není platební metoda. Koncert či ples mohou mít bezplatné vstupenky; běžná akce může mít registrační poplatek. Otázky účtu a splatnosti se zobrazují podle skutečné ceny a zvolených platebních možností, nikoli jen podle typu.

Při změně typu zůstane podřízené rozpracované nastavení v draftu jako neaktivní. Neaktivní plánek, vstupenka ani platební nastavení se nefinalizují. Návrat k původnímu typu obnoví práci. Každá relevantní změna zruší potvrzení závěrečné kontroly. Při explicitním kopírování nabídnout typ odvozený od zdroje; uživatel ho může změnit.

### Horní navigace: kde jsem a co připravuji

UI/UX návrh zpracoval subagent `gpt-6-astra`, reasoning `medium`, se skillem `ux-designer`, na základě tohoto plánu, shellu a jeho testu. Návrh je součástí cílového zadání, nikoli samostatný audit nebo další alternativa.

- **Kontext:** záhlaví „Nastavení akce · Podzimní slavnost“, pod ním typ a jeho význam, například „Ples · vstupenky a rezervace míst“, a skutečný stav uložení. Aktuální činnost stručně pojmenovat například „Základy · Vzhled · otázka 4 z 11“. Celá otázka zůstává nadpisem obsahu; nenásobit stejné dlouhé texty.
- **Desktop:** nynější nepopsané segmenty nahradit skutečnými tlačítky s krátkými názvy „1 Název“, „2 Termín“, „3 Typ“, „4 Vzhled“, „5 Formulář“… Každá aktivní otázka je přímo klikací včetně budoucích. Otázky přiřadit do sekcí Základy / Registrace či Prodej / Dokončení; sekce pomáhají orientaci, nenahrazují přímé cíle otázek. Při nedostatku šířky použít stejné řešení přetečení jako na mobilu.
- **Mobil:** jeden vodorovně posuvný řádek pojmenovaných tlačítek s cílem alespoň 48 dp, aktuální otázka se při přechodu přisune do viditelné oblasti. Nabídka „Všechny otázky“ otevře seskupený seznam všech aktivních cílů. Při velkém textu použít kompaktní záhlaví a tento seznam, aby navigace nevytlačila formulář. Zachovat spodní Zpět / Pokračovat a viditelnost při klávesnici.
- **Stavy:** aktuální otázku označit obrysem/podtržením a „Právě zde“, dokončenou fajfkou, nesplněnou číslem, navštívenou neúplnou jako Rozpracováno. Aktuální pozice, navštívenost a platnost jsou oddělené údaje. Nepoužívat `index < currentIndex` jako důkaz dokončení. Samotný skok ani platné výchozí hodnoty nenahrazují výslovnou závěrečnou kontrolu.
- **Přepínání:** klik převede aktuální editované hodnoty do stejného draftu a použije stávající revizované ukládání. Prázdné povinné hodnoty dovolí navštívit další otázku, ale krok zůstává neúplný. Pokud nelze vstup bezpečně převést nebo uchovat, zůstat u pole s konkrétní chybou. Selhání uložení ponechá lokální práci, označí Neuloženo a nabídne opakování; nesmí zobrazit falešné Uloženo. Zpět, Pokračovat i přímý skok sdílejí jednu navigační obsluhu; Pokračovat navíc validuje aktuální otázku a finální vytvoření vždy celý aktivní návrh.
- **Dynamická cesta:** změna typu ponechá uživatele na Typu a přepočítá cíle i počet ze stejného resolveru. Krátké oznámení vysvětlí vynechanou část, například „Nastavení sálu se nepoužije. Rozpracované údaje zůstávají uložené.“ Při obnovení konceptu s již neaktivním cílem přejít na Typ a vysvětlit změnu. Dostupné kopírování má samostatný nečíslovaný odkaz mimo číslovaný tok.
- **Přístupnost:** Tab/Enter/Space, viditelný fokus a `Semantics` s názvem, pořadím, stavem a `selected`. Po přechodu přesunout čtecí fokus na nadpis nové otázky. Informace nezávisí pouze na barvě. Automatické přisunutí nesmí neustále přetahovat uživatelské ruční posouvání.

Shell je prezentační komponenta: dostává stabilní klíče, krátké názvy, sekce a skutečné stavy od vlastníka toku a vrací callback výběru klíče. Neodvozuje oprávnění, validitu ani aktivní cestu sám. `readiness` zůstává údaj o dokončení, nikoli procento podle nejvzdálenější navštívené otázky.

### Dostupnost kopírování

- Události a formuláře posuzovat zvlášť. Uživatel může mít dostupnou událost bez jediného formuláře.
- Vyhodnotit všechny oprávněné zdroje pro tento cílový kontext v osobní správě a organizacích, nikoli jen vybranou zdrojovou událost nebo právě otevřenou jednotku. „Osobní“ není nový typ databázového vlastnictví; použít existující oprávnění.
- Respektovat tenantovou hranici. Pokud „v mých organizacích“ znamená kopii mezi různými platformními tenanty, jde o další rozhodnutí a samostatnou serverovou specifikaci. Tento plán takovou kopii automaticky nepovoluje.
- Po úspěšném načtení prázdného seznamu událostí úvod vůbec nezobrazit. Při prázdném seznamu formulářů nezobrazit tlačítko Zkopírovat formulář; automatický nový formulář zůstává dostupný.
- Během načítání nepřepínat samovolně z kopie na novou událost. Chyba má opakování načtení a možnost pokračovat novou událostí. Zamítnuté oprávnění ke konkrétní uložené předloze vyžaduje vysvětlení a zachování vlastní práce, nikoli tiché nahrazení.
- Data formulářů odvodit ze stejného autorizovaného přehledu; nespouštět znovu kompletní průzkum při každém otevření dialogu. Server znovu ověří oprávnění při čtení detailu a finalizaci.

### Odkaz a automatický název formuláře

Na desktopu jeden řádek: **Odkaz formuláře** `https://…/form/…` **Upravit odkaz**. Poznámka „Odkaz začne fungovat po vytvoření události.“ může být drobný druhý řádek. Na mobilu dovolit zalomení bez vodorovného přetékání. Editor slugu a jeho kontrola zůstanou až po kliknutí.

V průvodci nebude pole Název formuláře ani jeho duplikát v embedded editoru. Navrhuji automaticky použít aktuální název události, včetně převzatého formuláře. Při přejmenování události aktualizovat název i draftový model formuláře. Ručně upravený slug se nepřepisuje; automatický nadále používá existující serverový návrh a rezervaci. Mimo průvodce se obecná možnost pojmenování formuláře neruší.

## Společný vzhled

Jedna nabídka předvybraných stylů kombinuje paletu a písmo. Karta má název, barevný vzorek a krátký typografický náhled. Začít přibližně šesti styly; výchozí ponechat vizuálně blízko nynějšímu formuláři.

| Pracovní název | Paleta | Charakter písma |
|---|---|---|
| Čistý | Modrá, jednobarevná | Neutrální bezpatkové |
| Slavnostní | Tmavá modrá a zlatá | Výraznější titulky, čitelný text |
| Energický | Oranžová a červená, gradient | Výrazné bezpatkové |
| Přírodní | Zelená a tyrkysová, gradient | Měkčí bezpatkové |
| Jemný | Tlumená růžová a světlý neutrální tón | Lehčí titulky, běžný text |
| Kontrastní | Černá a bílá | Pevné bezpatkové |

Konkrétní fonty vybrat z průniku existujících katalogů formuláře a vstupenky s českou diakritikou a podporou PDF. Pokud se použije dvojice fontů, explicitně určit nadpisové a textové role; v první iteraci stačí jedno písmo na styl. Nenabízet font, který se při exportu tiše nahradí jiným.

Pod presety nabídnout **Vlastní vzhled**: písmo, hlavní barva, jednobarevný / dvoubarevný režim a druhá barva pro gradient. Směr gradientu může mít jeden společný výchozí směr. Náhled reaguje na změny a používá zadaný název a termín.

U běžné akce ukázat formulář. U koncertu a plesu ukázat současně formulář a vstupenku; na mobilu přepínač náhledu. Na stejném kroku nabídnout podobu vstupenky z existujících layoutů a akci pro detailní editor. Nezavádět samostatnou pozdější otázku designu vstupenky. Změna stylu nevymaže obsah ani rozmístění vlastního layoutu.

Barva/gradient se promítne do relevantních ploch formuláře i vstupenky, včetně skutečného exportu. Text, vstupní pole a QR zůstanou na čitelných plochách. QR má vlastní klidné pozadí a ochranný okraj; gradient nesmí procházet pod kódem. Selhání načtení fontu zobrazit s opakováním, nerozbít rozepsaný koncept.

## Technická smlouva a invarianty

1. `OccasionSetupStory` vlastní aktivní seznam otázek podle typu, dostupných schopností a obchodních voleb. Z tohoto seznamu vycházejí navigace, číslování a návrat na otázku. Stabilní klíče otázek nesmějí záviset na pořadí.
2. Stejná doménová pravidla aktivních sekcí se promítnou do progressu, revize kontroly a serverové validace. Server nevěří klientskému počtu hotových kroků. Staré `current_step` ID lze zachovat jako skupiny, ne jako uživatelská čísla otázek.
3. Typ uložit do existujícího draftového JSON jako explicitní volbu, například `eventKind`. Staré drafty odvodit z existující konfigurace bez změny výsledného chování; nejednoznačnou kombinaci označit k potvrzení.
4. Jeden draftový model vzhledu, pracovně `appearance`, vlastní preset a konkrétní barvy, režim pozadí a fontové role. Preset je zkratka pro hodnoty, nikoli druhý zdroj pravdy. Ukládat konkrétní hodnoty, aby změna katalogu nezměnila dokončenou akci.
5. Jedno mapování převádí společný vzhled do existujícího designu formuláře a ticket layoutu. Detailní úpravy mají explicitní precedence: změna palety mění stylové hodnoty, nikoli geometrii nebo obsah layoutu. Kopírovaný vlastní design nepřepsat automatickým výchozím presetem; zobrazit Vlastní.
6. Před rozšířením kontraktu ověřit podporu gradientu ve formuláři, Flutter preview a skutečném PDF rendereru. Chybějící podporu doplnit v těchto vlastnících společně se serverovou validací; simulace gradientu pouze v průvodci není dokončení.
7. Nový náhled vstupenky funguje nad draftem i bez zdrojové události. Výstupní konfiguraci finalizuje existující `finalize_occasion_setup_draft`, se zachováním idempotence, revizí, mapování ID a autorizačních kontrol.
8. Existující akce, odkazy a samostatné editory nesmějí být hromadně přestylovány. Změna je pro tento průvodce a jeho výstup; žádný druhý mechanismus kopie ani editor sálu.

## Realizované implementační vlny

### 1. Dostupné zdroje a zjednodušení formuláře

Změny: `sources.sql`, `_loadSources` a picker v `occasion_setup_page.dart`; sloučit přehled oprávněných zdrojů v povoleném cílovém kontextu, oddělit stav načítání/chyby/prázdno. Podmínit kopírovací úvod a tlačítko. V `occasion_setup_form_link.dart` změnit kompozici. Odebrat titulové pole v průvodci a nastavit automatický název ve společném draftovém modelu včetně embedded editoru.

Bez migrace názvů stávajících formulářů. Při obnovení draftu neprázdný vlastní slug zachovat. Oprávnění kontroluje server; cache není důkaz přístupu.

Ověření: cílené testy dostupnosti zdrojů v `database/tests/occasion_setup/sources_test.sql`; widget scénáře nulové předlohy, chyba/retry, formuláře mimo vybranou jednotku a dlouhá URL. Hotovo: nový uživatel nevidí kopii, oprávněný uživatel ji najde i mimo aktuálně vybraný zdroj.

### 2. Typ akce a odvozený tok

Změny: `occasion_setup_story.dart`, `occasion_setup_draft.dart`, `occasion_setup_page.dart`, lokalizace a `drafts.sql`/`finalize.sql` pro validaci aktivních sekcí. Sloučit začátek a konec do Termínu, přidat Typ, přesunout Vzhled před obsah formuláře. Propojit typ s ticket/form/blueprint konfigurací a placenost se skutečnými produkty.

V `occasion_setup_story_shell.dart` nahradit segmenty pojmenovanou navigací podle výše uvedeného kontraktu, přidat callback stabilního klíče a přístupný přehled všech otázek. V `_wizard` napojit skutečné stavy a jednu obsluhu přechodu místo pozic odvozených z indexu. Zrušit nepravdivé označení předchozích otázek za dokončené.

Normalizace starších konceptů proběhne při načtení a uloží se běžným revizovaným uložením; neprovádět plošný přepis živých akcí. Skryté konfigurace zůstanou obnovitelné v draftu, ale nesmějí unikat do finalizace.

Ověření: rozšířit `occasion_setup_story_test.dart`, `occasion_setup_settings_test.dart` a SQL `drafts_test.sql`/`finalize_test.sql`. Hotovo: všechny tři typy mají odpovídající cestu a funguje změna typu, návrat i resume starého konceptu bez falešných 100 %.

V `occasion_setup_story_shell_test.dart` ověřit skutečné kliknutí i klávesnicový skok, přeskočenou neúplnou otázku, mobilní přehled, velký text a zachování spodních akcí. Na integračním rozhraní ověřit skok s neuloženými poli, chybou uložení a návrat na odstraněný cíl. Stávající test samotných `Semantics` není důkaz klikatelnosti.

### 3. Společný vzhled a vstupenka

Změny: jeden model/převod vzhledu v setup modulu, existující `form_design_settings.dart`, `TicketFeature`, ticket layout, oba fontové katalogy a `web_client/src/services/theme_service.js`. Před změnou najít skutečný PDF renderer přes konzumenty ticket layoutu a jeho owning testy; určit podporovaný formát gradientu a doplnit jej na všech výstupech. Doplnit náhled nad draftem bez cizího occasion ID.

Rozšíření persistovaného renderovacího kontraktu dodat nejdřív čtenářům, následně zapnout nový zápis. Žádná destruktivní migrace starých layoutů. Odebrat samostatnou pozdější otázku `ticket`; podoba vstupenky je součást Vzhledu.

Ověření: převod preset/vlastní styl/roundtrip, font s českou diakritikou, veřejný formulář a skutečný PDF výstup ze stejných hodnot. Hotovo: změna barvy či fontu se projeví v obou náhledech i reálných výstupech bez změny geometrie a bez zdrojové události.

### 4. Dokončení a odstranění starých pravidel

Odstranit pevný tok jen podle `appSupported`, uživatelský název formuláře v průvodci, bezpodmínečné kopírovací prvky, pozdní samostatnou otázku vstupenky a závislost základního preview na předloze. Zachovat obecné editory a funkční tenantové capability kontroly. Aktualizovat aktivní dokumentaci a odkazy na předchozí plány v překrytém rozsahu.

Odstranit také nepopsaný neinteraktivní horní pruh a odvozování dokončenosti z pozice. Nenechat vedle nové navigace druhou sadu segmentů s odlišným významem stavu.

Ověření: jedna cílená sada relevantních Flutter testů s `--concurrency=1` po kontrole, že na stanici neběží jiný Flutter proces; owning SQL testy lokálně přes `node web_client/scripts/run_db_tests.js database/tests/occasion_setup/<soubor>.sql`; dotčené JS testy přes pnpm 11.24.0. Pro standard provést závěrečný izolovaný headless průchod mobil/desktop: nová přihláška bez zdrojů, koncert s vlastním gradientem, ples s plánkem a obnovení konceptu. Před implementačním browser během načíst příslušný skill a lokální E2E pravidla. Neprovádět produkční změny.

Hotovo: navigace, počet otázek, validace, souhrn i finalizace odpovídají téže aktivní konfiguraci. Testy prokážou, že skryté sekce nic nevytvářejí.

## Efektivní provedení a role

- UI/UX návrh i implementaci vizuální části zadat subagentovi `gpt-6-astra`, reasoning `medium`, se skillem `/Users/miakh/.codex/skills/ux-designer/SKILL.md`. Samostatné stručné zadání přes `fork_turns="none"`; předat tento plán, přesné soubory a rozsah. Nepověřovat ho samostatným architektonickým auditem.
- Hlavní agent vlastní resolver toku, draft/persistenci, oprávnění, finalizaci a ověření výstupů. Astra vlastní shell/navigaci, vizuální kompozici kroku Vzhled a jejich widget testy. Před souběžnými editacemi dohodnout rozhraní; `occasion_setup_page.dart` upravuje pouze hlavní agent. Astra dodá komponenty a konkrétní integrační pokyny. Bez překryvu úprav a bez druhé implementace logiky.
- Jedna cílená aktualizace průzkumu proti plánu, potom souvislé změny po závislostech. Neskenovat znovu celý repozitář a nevytvářet další plán místo implementace. Nevytvářet alternativní návrhy, pokud současné řešení neblokuje konkrétní důkaz.
- Ověření popsaná ve vlnách jsou důkazy dokončení; pokud nejsou potřeba dříve k rozlišení chyby, seskupit je do jedné závěrečné cílené sady po integraci. Standard zachovat pro oprávnění, SQL a renderovací kontrakt, bez nesouvisejících celorepozitářových kontrol. Již prošlé kontroly neopakovat bez změny dotčeného kódu.
- Žádné paralelní Flutter procesy ani souběžný Flutter test subagenta. Testovací slot řídí hlavní agent. Pro finální browser scénáře použít existující lokální E2E infrastrukturu a izolovanou headless session, nikoli produkci nebo uživatelův prohlížeč.
- Produktové detaily níže řešit uvedenými výchozími návrhy, pokud uživatel nedodá jiné rozhodnutí. Nezastavovat běžnou realizaci kvůli kosmetické volbě; výjimkou je rozšíření autorizační hranice nebo prokázaná ztráta dat.

## Výchozí rozhodnutí a zbylá rizika

- **Návrh:** kopírování jako nečíslovaný úvod; umožňuje vzhled vždy jako čtvrtou otázku.
- **Návrh:** názvy Koncert a Ples jsou jednoduché výchozí balíčky funkcí; možnost „Vlastní typ“ zatím nepřidávat.
- **Návrh:** ples vyžaduje dokončení sálu. Pokud má být plánek u plesu volitelný, upravit matici i serverovou validaci před implementací.
- **Předpoklad:** automatický název formuláře je shodný s názvem akce. Více formulářů v jednom průvodci není součástí tohoto rozšíření; stávající samostatná správa zůstává.
- **Předpoklad:** shodné barvy a písmo jsou společná identita, nikoli identická geometrie formuláře a vstupenky. Přesné presety a ticket layouty vybrat v další designové iteraci.
- **Riziko:** dostupnost mezi organizacemi musí odpovídat skutečné hierarchii Unit/Organization; současné SQL nedovoluje volně kopírovat napříč tenanty. Rozsah ujasnit před případným rozšířením autorizační smlouvy.
- **Ověřeno lokálně:** Roboto, Roboto Slab a Russo One mají explicitní vestavěné PDF identity; zvolený Roboto Slab se načetl ve skutečném veřejném formuláři a exportu. PDF používá axiální shading, Flutter shader a web CSS gradient se směrem zleva doprava. Zkopírovaný vlastní design se zachovává, dokud uživatel výslovně nezvolí společný styl.

Produkční aktivace vyžaduje samostatné zadání. Nové čtenáře layoutu je nutné nasadit před zapnutím zápisu `canvasGradient`; žádné existující akce se hromadně nepřestylovávají.
