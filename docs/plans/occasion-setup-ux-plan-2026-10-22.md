# Zjednodušení průvodce vytvořením události

Datum: 2026-10-22
Stav: Plán k implementaci; první krok ověří shodu zdrojové větve se screenshoty.
Ověřování: standard pro oprávnění, platební nastavení, SQL a sdílené renderování; cílené kontroly pro UI.

Pořadí otázek, dostupnost kopírování, automatický název formuláře, vzhled, navigaci a dynamický progress nyní vlastní [typy akcí a společný vzhled](../archive/plans/occasion-setup-types-appearance-plan-2026-10-22.md). Následující starší průzkum je historický podklad; požadavky komunikace a návratu z editoru sálu zůstávají platné.

## Výsledek a rozsah

Organizátor projde srozumitelným průvodcem, může vytvořit nebo zkopírovat událost, formulář i plánek, vidí skutečný náhled komunikace a po uložení plánku se vrátí na správnou otázku. Výběr formulářů funguje i při tvorbě od nuly. Správa bankovních účtů se načte bez chyby 21000 a neztratí rozpracovaný koncept.

Tento dokument pokrývá všech 15 dodaných screenshotů. Nejde o redesign ostatní administrace. Nyní se připravuje pouze plán; implementace, živá diagnostika, migrace a nasazení se neprovádějí.

Rozhodnutí uživatele: živý náhled e-mailu patří do této změny; editor šablon bude samostatný navazující krok. Tento plán neobsahuje úpravu textu šablony přímo v průvodci.

## Ověřené skutečnosti a omezení podkladů

Průzkum proběhl ve větvi `feat/occasion-setup-wizard-20261007`, HEAD `eb2304724`. Pracovní strom obsahuje rozsáhlé existující změny. Zdrojové soubory v pracovním stromu jsou podkladem níže, samotný HEAD nereprezentuje jejich celý obsah. Při implementaci zachovat cizí změny a znovu určit příslušný rozdíl.

Screenshoty ukazují 14 otázek a novější či odlišnou podobu některých částí. Aktuální `OccasionSetupStory.questions()` obsahuje v obou variantách 10 otázek; samostatné otázky otevření prodeje, splatnosti a komunikace zde nejsou. Výběr šablon sálu ze screenshotu nebyl v této implementaci editoru nalezen. Nelze tvrdit, že tato větev je zdrojem právě běžící verze.

| Fakt | Zdroj | Důsledek |
|---|---|---|
| Dvě rádia pro zdroj už existují, používají názvy Od nuly / Z předlohy. | `lib/components/occasion/setup/occasion_setup_page.dart`, `_body`, case 0 | Upravit existující stav a pojmenování, nevytvářet druhý mechanismus. |
| Dialog kopírování dostává pouze `_sourceForms`, odvozené z `_selectedSource`. | stejný soubor, `_sourceForms`, `_chooseForm` | Při tvorbě od nuly je seznam prázdný bez ohledu na jiné dostupné formuláře. |
| `_chooseForm` vyžaduje potvrzení nahrazení ještě před otevřením výběru. | stejný soubor | Zrušení výběru musí být bez změny konceptu; druhý potvrzovací dialog odstranit. |
| Rozpracovaný formulář má veřejný odkaz, interní počty a vložený editor. | `_body`, case 3; `forms/views/form_public_link.dart` | Náhled odkazu lze zjednodušit bez změny jeho skutečné rezervace. |
| Splatnost, připomínky a tón jsou promíchané v `_paymentSettings`. | `occasion_setup_page.dart` | Oddělit platební nastavení od komunikace. |
| Koncept má debounce, revizi a řešení konfliktu; vytvoření má opakovatelný příkaz. | `_change`, `_flush`, `_drain`, `_finalize`; `occasion_setup_draft.dart`; `database/functions/occasion_setup/` | Zachovat ochranu proti přepsání konceptu a duplicitnímu vytvoření. |
| Uložení prototypu plánku pouze zapíše a flushne koncept; editor zůstane otevřený. | `_openBlueprint`; `blueprint/views/blueprint_editor_tab.dart`, `saveChanges` | Potřebuje explicitní dokončení a návrat až po úspěšném uložení. |
| Dialog správy bank načítá účty a potom organizaci ve společném try/catch. | `bank_accounts/views/unit_bank_accounts_screen.dart`, `_loadData` | Text chyby sám neurčuje, který RPC selhal. |
| `bank_sync_connections.bank_account_id` má UNIQUE; čtecí cesta prochází i oprávnění a aliasy. | `database/functions/eshop_bank_sync/schema.sql`, `bank_sync_manage.sql`; `get_bank_accounts_for_unit_management.sql` | Chybu nelze poctivě vysvětlit domnělými duplicitami připojení. |
| Šablony i wrappery dědí událost > jednotka > organizace. | `email_templates/README.md`, `db_email_templates.dart` | Náhled musí respektovat stejné rozlišení jako odeslání. |
| Potvrzení objednávky používá tón, ale také vytváří QR/faktury/přílohy. | `supabase/functions/send-email/getTicketOrderConfirmationTemplate.ts` | Produkční odesílací cestu nelze spustit jen pro náhled. |

UI konzultace proběhla se subagentem `gpt-6-astra`, reasoning `medium`, se skillem `ui-ux-pro-max`. Konkrétní vyhledání progressive disclosure v katalogu neposkytlo použitelný výsledek; doporučení k postupnému odhalování nastavení vychází z obecných pravidel skillu a z analýzy tohoto toku.

## Cílová podoba podle připomínek

| Screenshot | Změna | Pozorovatelná podmínka dokončení |
|---|---|---|
| 1 | Dvě viditelné volby: **Vytvořit novou událost** / **Zkopírovat událost**. Pod kopií výběr zdroje a konkrétních částí ke kopírování. | Volby odpovídají skutečnému stavu; při nové události nejsou vidět ovladače kopie. |
| 2 | Výchozí obsah: **Odkaz formuláře**, celý návrh URL, akce **Upravit odkaz**. Editor adresy a kontrola dostupnosti až po otevření. | Jeden náhled, jedna krátká poznámka: Odkaz začne fungovat po vytvoření události. |
| 3 | Odstranit počet polí a produktů i obecnou vysvětlující větu o vstupenkách z hlavního toku. | Organizátor vidí přímo editovatelný obsah formuláře. |
| 4 | Volby **Použít tento formulář** / **Zkopírovat formulář**. První zachová připravený nový formulář a vložený editor. | Žádné tlačítko Vytvořit/Zkopírovat; tvorba od nuly nepotřebuje dialog. |
| 5 | Samostatný funkční výběr formulářů nezávislý na výběru zdrojové události. | Formuláře se zobrazí i při nové události; loading, chyba, prázdný seznam a nulový výsledek hledání mají odlišný stav. |
| 6 | Odstranit dodatečný dialog Nahradit formulář v konceptu? | Výběr se aplikuje jediným rozhodnutím; zrušení nic nezmění, vlastní předchozí formulář lze obnovit. |
| 7 | Při první volbě **Naplánovat otevření** předvyplnit nyní + 24 hodin. Krátce ukázat konkrétní datum a čas. | Návrat na otázku ani přepnutí jinam nepřepíše vlastní termín; neplatný interval blokuje pokračování s lokální chybou. |
| 8-9 | Opravit příčinu SQL chyby a spolehlivý návrat ze správy bank. | Seznam účtů se načte, oprávnění zůstanou zachována; po návratu se účty obnoví a volba pro událost je jednoznačná. |
| 10 | Kompaktní splatnost a připomínka; odstranit dlouhou technickou prózu a ukládání výchozích hodnot organizace z průvodce. | Na první pohled počet dní a zapnutí připomínky; další časování jen při zapnutí. |
| 11 | Pole **E-mail pro odpovědi**, vysvětlení Reply-To, dvě volby **Vykat** / **Tykat** a skutečný náhled. | Přepnutí aktualizuje reálný render; náhled nic neodesílá ani nemění šablony organizace. |
| 12 | Tři viditelné volby **Bez plánku** / **Vytvořit nový plánek** / **Zkopírovat plánek**. | Nikde v tomto rozhodování není nejasné Převzít. |
| 13 | Nezobrazovat počet míst u prázdného nového plánku. | Před výběrem šablony žádné hlášení 0 míst; u hotového plánku je kladný počet užitečný souhrn. |
| 14 | Nový plánek otevře nejdřív výběr šablon včetně **Prázdný plánek**, bez předvýběru. | Před explicitním výběrem se nevloží žádné objekty; zrušení zachová původní koncept. |
| 15 | V editoru jedna hlavní akce **Uložit a vrátit se do průvodce**. | Po úspěšném uložení se otevře stejná otázka plánku se souhrnem a akcí Upravit plánek; při chybě zůstane editor otevřený. |

### Konkrétní návrh plateb a komunikace

Otázka splatnosti:

- **Splatnost objednávky**: `[7] dní od objednání`.
- **Připomenout nezaplacenou objednávku**: přepínač. Při zapnutí jeden řádek `Připomenout [1] den před splatností`.
- Jedna krátká věta u splatnosti: `Nezaplacené objednávky rušíte ručně.` Další vysvětlení v nápovědě, pokud je potřebné.
- Výchozí hodnoty skutečně vypočítat z existujícího dědění. Krátký doplňkový štítek `Podle organizace` pouze tam, kde hodnota opravdu dědí. Formulářový override nenazývat organizačním výchozím nastavením.
- Změna vytvoří override pouze pro koncept; pouhé zobrazení účinné hodnoty nevytvoří override. Případný reset `Obnovit výchozí` je vedlejší akce. Správa organizačních výchozích hodnot patří do nastavení organizace.
- Zachovat nulu jako okamžitou splatnost. Záporné nebo nečíselné hodnoty odmítnout. Chování připomínky u nulové/krátké splatnosti musí odpovídat existujícím pravidlům scheduleru, ne slibovat nemožný čas odeslání.

Otázka komunikace:

- **E-mail pro odpovědi** s účinnou adresou; pod ní `Na tuto adresu přijdou odpovědi účastníků na e-maily k události.` Jde o Reply-To, nikoli změnu odesílací identity.
- **Jak oslovovat účastníky?** - dvě přístupné volby `Vykat` / `Tykat`, předvolené podle účinného nastavení. Zachovat příznak dědění, dokud organizátor hodnotu nezmění.
- **Náhled potvrzení objednávky**: předmět a HTML s ukázkovým jménem, událostí a objednávkou. Na desktopu může být vedle voleb, na mobilu pod nimi.
- Náhled zahrne účinnou zdrojovou nebo zděděnou šablonu a wrapper. Přepínání mění stejné překládané fragmenty jako skutečné odesílání. Pevný text vlastní šablony nelze automaticky přepsat z vykání na tykání; v takovém případě krátce vysvětlit, že vlastní text zůstává.
- Úpravy šablon jsou samostatná budoucí práce podle potvrzené preference uživatele. V této změně nepřidávat nefunkční tlačítko ani přímý zápis přes `updateEmailTemplate` do organizace.

### Plánek a návrat

Tok: otázka plánku -> Vytvořit nový -> výběr šablony -> pracovní editor -> Uložit a vrátit se do průvodce -> souhrn stejné otázky.

Editor v konceptu stručně uvádí `Plánek pro novou událost`. Vedlejší akce je `Zpět do průvodce`; neuložené vlastní úpravy chrání existující PopScope/snapshot guard. Nezdvojovat horní a spodní stejně významná tlačítka Zahodit změny. Uložení nesmí vytvořit živý plánek před dokončením celé události. Běžný editor existující události si zachová svůj současný způsob ukládání.

## Autorita a invarianty

1. `OccasionSetupDrafts` a SQL v `database/functions/occasion_setup/` zůstávají vlastníkem uložení a finalizace konceptu. Žádná druhá lokální cesta vytváření události.
2. Kopie nikdy neaktualizuje zdroj a nepřenáší objednávky, osoby, rezervace, tajné klíče ani platební pohyby. Seznam i detail ověřují oprávnění serverem a hranici organizace.
3. Kopie jednotlivého formuláře nebo plánku nevolá `_selectSource` jako vedlejší efekt a nepřepíše nesouvisející údaje události. Vazby produktů a míst se přemapují podle existujícího kontraktu finalizace.
4. Technické identifikátory `none/new/copy`, `inherit/formal/informal` a stabilní klíče otázek nejsou lokalizované popisky. Staré uložené koncepty musí pokračovat na významově správné otázce.
5. Zobrazení zděděné hodnoty ji nezafixuje; explicitní změna ovlivní pouze koncept. Změna konfigurace zneplatní předchozí kontrolu před vytvořením.
6. Odkaz je návrh do okamžiku atomického přidělení serverem; dostupnost v náhledu není rezervace. Náhled konceptu se neotevírá jako funkční veřejný formulář.
7. Uložení plánku -> potvrzený flush konceptu -> návrat. Chyba nebo konflikt nevede k oznámení úspěchu ani ztrátě pracovní kopie.
8. Náhled e-mailu používá společné renderování, neodesílá zprávu, nevytváří faktury/objednávky ani nenavštěvuje produkční odkazy. HTML náhled izolovat od navigace a aktivního obsahu.
9. Všechny admin dialogy používají sdílený AppDialog shell; zachovat klávesnici, focus, Escape a současné ochrany konceptů. UI respektuje světlý/tmavý motiv, úzký viewport a cíle alespoň 44-48 px.

## Implementační vlny

### 0. Určení správného zdroje a rozsahu změn

**Změny:** Před editací porovnat pracovní větev, dostupné lokální větve/worktrees a historii souborů průvodce s verzí screenshotů. Stačí cílený průzkum `occasion_setup_story.dart`, hlavní stránky a editoru. Zjistit, zda pokročilejší průvodce/šablony existují jinde; nepřepisovat je jednodušší starší implementací. Bez resetu pracovního stromu a bez přepínání větví přes cizí změny.

**Rozhodnutí:** Pokud novější zdroj existuje, použít jej v izolovaném worktree a aktualizovat zde uvedené symboly. Pokud ne, cílové otázky a výběr šablon doplnit v současném vlastníkovi; tato chybějící funkcionalita je explicitní rozsah, ne důvod vytvořit paralelní průvodce.

**Výstup:** Zaznamenaná výchozí větev/revize, relevantní pracovní změny a mapování na cílové otázky. Žádné testy pouze pro tuto inventuru.

### 1. Oprava datových překážek: formuláře a bankovní účty

**Formuláře:** Oddělit výběr kopie od `_selectedSource`. Použít existující autorizované `get_occasion_setup_source_list` / `get_occasion_setup_source` jako vlastníka projekce a oprávnění: seznam oprávněných událostí, formuláře načítat při rozbalení/výběru, ne hromadný detail každé události. Je-li pro přehled nutný seznam formulářů napříč událostmi, přidat lehký SQL list ve stejném modulu s totožným omezením organizace a copy oprávnění; detail stále číst jedinou stávající projekcí. Přehled používá všechny oprávněné zdroje v tenantovi cílové jednotky; detail i finalizace znovu ověřují dosavadní právo kopie.

Existující globální `get_all_viewable_forms_for_copying()` vrací jiný datový kontrakt a kontroluje jiné view role. Nepřipojit jej do průvodce bez kontroly hranice organizace a copy oprávnění. Nekopírovat jeho těžkou agregaci statistik objednávek, kterou výběr nepotřebuje.

V `CreateOrCopyFormDialog` rozlišit načítání, chybu s opakováním, žádné dostupné formuláře a žádný výsledek hledání. V průvodci otevřít tento dialog v režimu kopírování; jeho běžné použití mimo průvodce zachovat, pokud potřebuje i tvorbu nového formuláře. Detail přijatý po změně výběru nesmí přepsat novější koncept.

**Banky:** Reprodukovat přes `_loadData` samostatně `get_bank_accounts_for_unit_management` a `get_current_organization_data`. Prověřit `check_is_manager_on_unit` -> `get_is_manager_on_unit`, demo guardy a bank-sync resolver. Scalar subquery v `get_is_manager_on_unit` je kandidát, nikoli potvrzená příčina. Zachytit SQL kontext a fixture, která opravdu vyvolá 21000; nespoléhat na screenshot.

Opravit konkrétní vlastník dotazu. Pokud má být odpověď existenční oprávnění, použít odpovídající EXISTS; pokud skutečně vyžaduje jedinečná data, určit a opravit porušený invariant. Nepoužít nahodilý LIMIT 1, nelikvidovat řádky a neobcházet oprávnění. Pokud závada v aktuálním zdroji už není, doložit rozdíl a chybějící stav nasazení místo nové obcházející opravy. Případná migrace musí vycházet z kanonického SQL.

UI načítání účtů oddělit od doplňkového kontextu organizace, pokud jeho selhání blokuje jinak platný seznam. Místo raw SQL dialogu zobrazit stručnou chybu a opakování; technickou příčinu zachovat v diagnostice. Po návratu obnovit účty a měnové směrování bez ztráty konceptu.

**Ověření:** SQL fixture pro skutečnou chybu, více účtů a rolí, přípustné aliasy, uživatele bez přístupu a cizí organizaci; UI test nová událost -> kopie formuláře a návrat ze správy bank. Relevantní vlastníci: `database/tests/occasion_setup/sources_test.sql`, `database/tests/units/get_bank_accounts_for_unit_management_test.sql`, bankovní testovací cases.

**Konec vlny:** Funkční kopie bez vybrané zdrojové události, chyba bank reprodukovaná a opravená nebo prokazatelně identifikovaný již existující fix a chybějící rollout.

### 2. Jednoznačné volby, odkaz a otevření prodeje

**Změny:** `_body`, `_chooseForm`, `_formTextField`, případně skutečné novější otázky z vlny 0. Zdroj volit dvěma rádii. Copy options ukázat pod kopií s dostupností jednotlivých částí podle schopností varianty. Přesunout existující volby `copyProgram/copyInformation/copyEmails` k rozhodnutí kopie, odstranit jejich duplicitní ovládání v dalších otázkách. Formulář a plánek mají vlastní volbu detailu, žádné druhé konkurenční přepínače pro stejný obsah.

Nový formulář zůstane okamžitě upravitelný. Odstranit `_chooseForm` potvrzení před otevřením dialogu. Nahrazení provést atomicky po úspěšném načtení/validaci; nabídnout `Vrátit změnu` s kompletním předchozím formulářem a souvisejícími vazbami, nebo ekvivalentně uchovat obnovitelný draft. Pozdní undo nesmí přepsat následné úpravy; omezit jej na bezprostřední přechod a invalidovat po dalším editování. Zrušení/selhání ponechá původní stav.

Odkaz vykreslit jednou přes stávající URL helpery. Editor otevřít akcí Upravit odkaz; kontrolu dostupnosti se stavem a návrhem náhradní adresy zobrazovat v editoru, zachovat serverovou validaci kolize při finálním vytvoření. Pokud uživatel adresu změnil, automatická změna názvu ji nesmí přepsat.

Plánované otevření: použít existující vlastníka dostupnosti formuláře; pokud v určeném zdroji chybí, dohledat přes `lib/components/forms/README.md`, form metadata a SQL finalizaci a doplnit tentýž kontrakt do konceptu. Default `now + Duration(hours: 24)` stanovit jednou při první volbě. Ukládat jednoznačný čas, vykreslit lokálně. Je-li nyní+24h po konci prodeje/události, neuložit tichý neplatný default: ukázat krátkou chybu a požadovat platnou volbu. Zachovat dříve uložený plán při obnově.

**Odstranění:** souhrn polí/produktů, zbytečná vysvětlující věta, slash tlačítko, druhé potvrzení, duplicitní adresy a nejasné názvy kopie. Měnit jen dotčené kontexty; nesmazat globální překlady používané jinými obrazovkami.

**Ověření:** cílené widget/kontrakt testy zdroj nová/kopie, cancel/error bez mutace, undo, editovaný slug, první plán +24h, zachování vlastního času a hraniční interval. Ověřit source i form kopii přes SQL finalizaci, včetně přemapování produktů.

**Konec vlny:** screenshoty 1-7 mají odpovídající cílové chování a neexistuje druhý způsob ovládání stejných copy voleb.

### 3. Splatnost a skutečný náhled komunikace

**Změny:** oddělit hlavní UI plateb od komunikace v `occasion_setup_page.dart`; formulářové metadata a organizační dědění držet u současných vlastníků. Použít `forms/views/form_settings_content.dart` jako referenci existujících override klíčů, nikoli zkopírovat celý rozsáhlý settings formulář do průvodce. Účinné hodnoty nesmí počítat každá obrazovka jinak. `OccasionSetupStory` zachová stabilní identitu otázek, nové otázky dostanou explicitní readiness namísto nevhodného společného `_stepReady` pro celý platební krok.

Přidat Reply-To a vykání/tykání do konceptu a kanonického persist/finalize kontraktu, pokud chybějí. Posoudit načtení kopírované šablony oproti zděděné podle copyEmails; pouze čtení kontextu nesmí změnit zdroj.

Ze `getTicketOrderConfirmationTemplate.ts` oddělit čisté skládání obsahu a substituci proměnných od získávání faktur, QR, příloh a zařazování e-mailů. Odesílání i náhled budou volat tentýž renderer. Pro náhled vytvořit malý autorizovaný draft-aware read/render vstup s ID konceptu, revision a povolenými přechodnými hodnotami; server ověří oprávnění a vyřeší účinnou šablonu/wrapper. Nevystavit libovolné čtení cizích šablon ani SQL interní resolver. Ukázková data budou bez osobních údajů a platných capability tokenů. Nevolat SES ani fakturační služby.

Rychlé přepínání tónu ošetřit request generation; stará odpověď nepřepíše novou. Selhání náhledu nabídne opakování, nesmaže nastavení a samo neblokuje vytvoření jinak platné události. Náhled bez vytvořené události nesmí falšovat cizí occasion kontext.

**Odstranění:** tón z platebního bloku, opakované odstavce o dědění, hlavní reset tlačítko a ukládání výchozích hodnot celé organizace z průvodce. Zachovat organizační správu na její vlastní obrazovce. Nepřidávat editor šablon do této vlny.

**Ověření:** automatizované testy dědění vs override, nula/záporné dny, připomínky, Reply-To a uložený tón. Renderer: formální/neformální varianta, vlastní statický text, wrapper dědění, shoda obsahu náhledu a skutečné zprávy při stejných datech; žádné volání senderu/fakturační služby. SQL odepření přístupu k cizímu konceptu. Ověřit také, že refaktor nezměnil skutečné odesílání a přílohy.

**Konec vlny:** obrázky 10-11 mají kompaktní UI, náhled prokazatelně odpovídá odesílání a nastavení se skutečně uloží.

### 4. Výběr šablony plánku a dokončení editoru

**Změny:** `occasion_setup_blueprint.dart`, `_blueprintSettings`, `_selectBlueprint`, `_openBlueprint` a callback rozhraní `BlueprintTab.prototype`. Výběr kopie zpřístupnit i bez globální zdrojové události přes autorizované source list/detail vlastnictví z vlny 1. Zachovat produkty a typy míst při kopii formuláře/plánku; neskrývat validační chybu nekompatibilní vazby.

Pokud vlna 0 najde existující katalog šablon ze screenshotu, použít jeho autoritativní data a picker. Jinak doplnit minimální výběr nad existujícími doloženými daty; screenshot sám není dostatečný serializovaný zdroj šablony. V takovém případě je katalog konkrétních sálů implementační rozhodnutí, které se zaznamená před jeho tvorbou. Vždy nabídnout Prázdný plánek a nepředaplikovat první položku.

Pracovní model editoru izolovat od přijatého draftu. Nový výběr či šablona se nezapíše do živé události. Uložit a vrátit nejdřív dokončí snapshot a `_flush`, potom přijme baseline a provede jediný návrat. Zachovat již existující PopScope; neprovádět pop uvnitř callbacku tak, aby zbytek `saveChanges` použil zrušený context nebo spustil reload po návratu. Rozšířit explicitní completion callback nebo návratový výsledek, nikoli testovat text tlačítka. Tuto změnu omezit na draft režim.

**Odstranění:** UI Převzít, souhrn 0 míst, automaticky vložená šablona, duplicitní discard akce v draft editoru. Existující parser starých uložených hodnot `Nový/Převzít` ponechat jen na vstupní hranici pro obnovu konceptu; nové zápisy mají kanonická ID.

**Ověření:** cancel picker bez mutace; výběr šablony právě jednou; nová pracovní kopie neobsahuje rezervace; uložení vrátí na původní otázku; chyba flush/conflict ponechá editor; back s úpravami zachová guard; běžný editor mimo průvodce funguje stejně. Zařadit cases do skutečně spouštěného test entrypointu.

**Konec vlny:** screenshoty 12-15 jsou splněné a další pokračování/finalizace používá právě uložený plánek a platné produkty.

### 5. Společná kontrola průchodu a dokončení

Jeden cílený průchod na izolovaném lokálním backendu: nová událost -> kopie formuláře bez zdroje -> vlastní odkaz -> plánované otevření -> správa účtů a návrat -> splatnost -> komunikace a náhled -> šablona plánku -> editor a návrat -> kontrola -> vytvoření. Druhý scénář pokryje kopii události a obnovu uloženého konceptu. Kontrolovat relevantní app-supported i ticketing variantu, nerozšiřovat tenant rollout.

Aktualizovat existující návody pouze u změněných kontraktů. Starý plán z 2026-09-25 je historický kontext, nikoli konkurující zadání tohoto UX balíku. Nevytvářet V2 průvodce, dočasné alternativní routy ani duplicitní renderery.

**Konec vlny:** jsou splněné všechny řádky tabulky screenshotů, nejsou rozbité existující koncepty a výsledky skutečně vybraných kontrol jsou zaznamenané.

## Ověření a provozní hranice

Během plánování se nespouštějí testy ani buildy. Při implementaci ověřovat až souvislý hotový blok; SQL/oprávnění/platební sémantika mají standardní cílené kontroly. Před Flutter úlohou zkontrolovat jediný workstation slot; `fvm flutter test --concurrency=1`. Cases soubory musí být skutečně importované do spouštěného entrypointu, ne pouze existovat.

Doporučené kontrakty:

- `test/components/occasion/occasion_setup_story_test.dart` a `occasion_setup_story_shell_test.dart`: navigace, obnova a stabilní otázky.
- `test/components/forms/occasion_setup_defaults_cases.dart` a relevantní blueprint/bank account cases: zapojit přes vlastnící entrypoint podle CONTRIBUTING.md, ne spouštět cases jako domnělý samostatný test.
- `database/tests/occasion_setup/sources_test.sql`, `drafts_test.sql`, `finalize_test.sql`, `usability_test.sql` a `database/tests/units/get_bank_accounts_for_unit_management_test.sql`: podle skutečně změněných kontraktů.
- SQL runner: `DATABASE_URL=<ověřená disposable lokální DB> node web_client/scripts/run_db_tests.js <konkrétní test.sql>`; ověřit nenulový počet vybraných testů. Nebootstrapovat cizí databázi.
- Existující renderer test lane podle vlastníka TypeScript změny; žádný skutečný e-mail ani externí fakturační požadavek.
- `fvm dart analyze <změněné Dart soubory>`; souhrn jen relevantních diagnostik.
- E2E přes podporovaný `automation/run_occasion_setup_local.py` / `test/browser/occasion_setup_e2e.dart` po přečtení `festapp-local-e2e` skillu. Interaktivní vizuální kontrolu dělat jen headless/izolovaně přes agent-browser; nepoužít uživatelův Chrome.
- Vizuálně desktop + úzký viewport, dark/light, focus a čitelnost: počet primárních akcí, jasný návrat z editoru, žádný prázdný dialog. Nedoplňovat snapshot testy každé české věty.

Nasazení ani produkční SQL nejsou součástí schváleného plánování. Pokud bude později požadováno, odděleně zvolit jediného tenanta, ověřit activation a kanonickou main/tenant ancestry, připravit kanonickou migraci a vydat přes místní build a `automation/deploy_direct.sh`. Rutinní provedení delegovat dle AGENTS.md. Případná nová read-only preview funkce/rozšíření schématu musí být dostupné před klientem, který je vyžaduje. Rollback nesmí smazat koncepty nebo vracet chybnou autorizační logiku.

## Zbývající nejistoty

- Původ novějšího UI ze screenshotů je třeba určit v první vlně; plán nezaměňuje aktuální zdroj s živým stavem.
- Příčina 21000 není potvrzená. Nelze předem slíbit konkrétní SQL opravu; exit condition je reprodukce a fix, nikoli potlačení výjimky.
- Konkrétní katalog šablon plánků a samostatný draft preview vstup v tomto checkoutu chybí. Oba mají explicitní implementační místo a hranici, nikoli předstíraný hotový komponent.
- Vlastní text šablony nereaguje automaticky na vykat/tykat. Náhled musí tuto skutečnost ukázat; editor textu má podle uživatele následovat odděleně.

## Hotovo znamená

- Všech 15 připomínek má uvedené chování, odpovídající kontroly a vlastníka implementace.
- Existuje jediný průvodce, jediná projekce zdrojových konfigurací a společné renderování e-mailového obsahu.
- Zrušené UI prvky z tabulky se v dotčených kontextech již nepoužívají; parser pro staré koncepty je vědomě omezená vstupní hranice.
- Kopie i náhled respektují serverová oprávnění a nedělají vedlejší produkční operace.
- Úspěch uložení plánku znamená trvalý koncept a návrat, nikoli jen lokální toast.
- Handoff rozlišuje implementováno, lokálně ověřeno a nasazeno; případný chybějící rollout je uveden výslovně.
