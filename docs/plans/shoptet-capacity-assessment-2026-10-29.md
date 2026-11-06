# Shoptet - kapacita, více otevřených formulářů a stav implementace

Historický výzkum a návrh z 29. 10. 2026, začleněný 6. 11. 2026. Nejde o implementaci ani novou autorizaci realizace. Tehdejší záznamy o neodeslání jsou překonané [stavem potvrzeným vlastníkem 1. 11.](shoptet-partner-onboarding-2026-10-26.md): návrh byl odeslán, čeká se na odpověď a další podání se neposílá.

Aktuální architekturu vlastní [společný Commerce Connector](../architecture/commerce-connectors.md) a jeho [realizační plán](commerce-connectors-plan-2026-10-29.md). Shoptet je první adaptér; tento starší průzkum zůstává podkladem, nikoli druhou implementační autoritou.

Doplnění výzkumu: [aktuální porovnání variant](shoptet-direction-plan-2026-10-29.md) nahrazuje zdejší předběžnou preferenci pevného přídělu. Popis domácího kódu zůstává podkladem; nově se nejdříve ověřuje shipping-request kontrakt.

29. 10. 2026. Kontrola aktuálního zdrojového kódu a existujících testovacích scénářů. Nejde o nové ověření produkce; testy ani skutečný Shoptet experiment v této kontrole neproběhly. Uživatel zakázal jakékoli odesílání.

## Hlavní závěr

Festapp již má serverovou ochranu sedadel a společné kapacity. Vložení stejného formuláře na další web nezakládá druhý sklad. Naproti tomu Shoptet košík je jiný objednávkový systém: stávající ochranu nezíská tím, že budeme číst jeho objednávky. Konektor, převzetí rezervace do Shoptet objednávky ani kanálové příděly pro Shoptet nejsou implementované.

Je nutné rozlišovat ochranu proti dvojímu prodeji, aktuálnost zobrazení a pokračování stejného rozpracovaného nákupu. Jsou to tři různé vlastnosti. Zámky v databázi řeší první; samy nezaručí zbylé dvě.

## Co znamená otevřený formulář

| Stav zákazníka | Co se děje dnes ve Festappu |
| --- | --- |
| Jen otevře formulář | Samotné zobrazení neblokuje kapacitu. Otevřených oken může být více a původně zobrazená dostupnost může zestárnout. |
| Vybere konkrétní sedadlo | `select_spot` žádá SQL o časově omezené držení. Zámky serializují konkurenty; aktivně držené nebo objednané místo není volně přidělitelné jinému kupujícímu. |
| Změní počet běžných vstupenek bez sedadel | Výběr počtu se skládá v klientovi. V běžné cestě tím nevzniká stejný dočasný hold jako kliknutím na sedadlo. Společná kapacita se závazně přiděluje při vytvoření objednávky. |
| Odešle objednávku | SQL znovu ověří platnost rezervace a dostupnost a provede přidělení. Nespoléhá jen na to, co bylo v otevřeném formuláři. Při konfliktu se objednávka odmítne a transakční změny se vrátí. |
| Má přijatou nezaplacenou objednávku | Přidělená kapacita patří objednávce; nesmí se řídit dobou života otevřeného okna nebo krátkého výběru sedadla. Její uvolnění řídí objednávkový životní cyklus. |
| Reloaduje formulář | Klient obnovuje rezervační oprávnění ze sessionStorage a načte autoritativní stav SQL. Opakovaný hold stejného místa neprodlužuje původní expiraci. |

Prodej různých produktů/formulářů sdílí kapacitu tehdy, jsou-li skutečně napojené na stejný inventory pool/context nebo stejné sedadlo. Dvě nezávisle založené kapacity se automaticky nesloučí jen proto, že mají stejný název akce. Samostatný limit účastníků konkrétního formuláře je další pravidlo, nikoli univerzální společný limit všech kanálů.

## Více oken, zařízení a webů

| Situace | Co pokrývá kód a co nelze slibovat |
| --- | --- |
| Dva různí kupující kliknou na stejné místo | Rozhodne SQL. Jeden získá hold, druhý dostane odmítnutí. Zastaralá zelená židle v druhém okně není právo ji koupit. |
| Dva různé formuláře soutěží o poslední kus společného poolu | Přidělení zamyká společné kapacitní rodiče; existuje deterministický dvouspojový test právě pro dva formuláře a dva produkty nad posledním kusem. |
| Stejný člověk otevře další samostatnou záložku nebo telefon | Není to automaticky stejný rozpracovaný košík. Hold oprávnění je v sessionStorage, klíčované backendem a formulářem, nikoli jen e-mailem člověka. Nové zařízení ho samo nepřevezme. |
| Zduplikuje již otevřenou záložku | Prohlížeč může zkopírovat sessionStorage. Dvě záložky pak mohou používat stejné hold oprávnění a jedna může uvolnit místo držené tímto oprávněním v druhé. SQL nepovolí druhé prodání sedadla, ale neřeší tím koordinaci dvou obrazovek jednoho nákupu. |
| Stejný formulář je vložen na více webech | Pokud oba vstupy míří na stejnou kanonickou kapacitu, platí stejné SQL kontroly. Sdílení browser storage mezi weby/iframe není spolehlivý kontrakt, zvlášť při blokování či dělení úložišť. |
| Otevřené okno zůstane dlouho na pozadí | Jeho obrazovka může zestárnout. Existují autoritativní čtení při otevření plánku, obnově rezervace a zotavení po nejasné chybě; nebyla doložena úplná průběžná synchronizace všech oken. Konečné rozhodnutí zůstává na serveru. |
| Opakování stejného příkazu k objednávce | Serverová command identity umožňuje replay stejného výsledku. Dva nezávislé příkazy na dvě objednávky nejsou automaticky jeden nákup jen kvůli stejnému e-mailu. U běžných vstupenek tak člověk může oprávněně vytvořit dvě objednávky, má-li akce kapacitu. |

Browserové úložiště má fallback do paměti stránky. Je-li trvalejší úložiště nedostupné, nelze slibovat obnovu po reloadu. To nemění serverovou ochranu proti přidělení obsazené kapacity.

## Co už je implementované a co je teprve návrh

| Schopnost | Stav |
| --- | --- |
| Serverový hold sedadla s expirací a ověřením držitele | Implementováno ve zdroji. |
| Společné kapacitní alokace a transakční odmítnutí přečerpání | Implementováno ve zdroji; existují testy souběhu. |
| Obnova hold oprávnění při reloadu stejné relace | Implementováno, s omezeními browser storage. |
| Idempotentní opakování stejného objednávkového commandu | Implementováno; nejde o obecné sloučení všech nákupů jednoho člověka. |
| Jeden košík automaticky pokračující napříč telefonem, různými weby a záložkami | Není doložen jako hotová vlastnost; stávající sessionStorage ho nezajišťuje. |
| Shoptet instalace/OAuth, mapování produktů a webhook worker | Není implementováno jako Shoptet konektor. |
| Rezervace navázaná na Shoptet košík a její převzetí při objednání | Není implementováno; nejprve potvrdit podporovaný kontrakt se Shoptetem. |
| Vyhrazený kanálový příděl pro Shoptet se stopnutím a vrácením | Není implementováno. Stávající inventory model je základ, nikoli hotový kanálový lease. |
| Shoptet úhrady, storna, refundace a ochrana před druhou platební výzvou | Navrženo v technické příloze; integraci nelze označit za hotovou. |

## Doporučený postup pro Shoptet

Cíl pro všechny vstupy je jedna účetní evidence kapacity. Formulář ani košík sám o sobě není autorita. Nejdřív se Shoptetem potvrdit, kde lze před závazným přijetím objednávky bezpečně zastavit prodej bez platné alokace, a to i při obcházení našeho frontend kódu.

**Varianta A - sdílená okamžitá rezervace:** každá podporovaná cesta Shoptet objednávky musí získat/převzít serverově ověřenou rezervaci z Festappu. Rezervace je svázaná s instalací, položkou, množstvím a revizí, nikoli pouze e-mailem nebo libovolným browser tokenem. Krátký hold se při přijetí objednávky převede na objednávkovou alokaci ještě před svým vypršením. Až potom následuje platební cesta. Pokud Shoptet takovou hranici neposkytne, nelze ji nahradit webhookem po zaplacení.

**Varianta B - vyhrazený příděl:** realistická možnost k projednání pro první verzi běžných vstupenek. Například ze 100 kusů Festapp nejprve závazně vyhradí 20 pro Shoptet; přímý prodej má zbývajících 80. Shoptet musí vlastním serverovým skladem nepřekročit svůj příděl ve všech podporovaných cestách. Objednávka ze Shoptetu spotřebovává přidělených 20, nesmí znovu odečíst kus ze zbývajících 80. Nejde o kopírování hodnoty „zbývá 100“ mezi dva sklady. Vrácení nevyužitých kusů je možné až po potvrzeném zastavení prodeje a vypořádání rozpracovaných objednávek. Při nejistém výsledku se příděl drží. Tuto schopnost musíme teprve implementovat.

Pokud Shoptet potvrdí obě cesty, pro první pilot doporučuji začít menším pevným přídělem běžných vstupenek. Má jednodušší hranici při výpadku než synchronní propojení každého checkoutu. Je to ale podmíněné doporučení, ne potvrzená proveditelnost. Pokud neprokážeme serverové nepřekročení přídělu nebo bezpečné zastavení, pilot se nespouští. Konkrétní sedadla jsou další krok: vyhradit přesné židle, ne jen počet.

Příklad rizika, kterému se vyhnout: v naší databázi zbývá poslední kus. Zákazník A ho koupí přes přímý formulář a zákazník B současně zaplatí v Shoptetu. Přijmeme-li Shoptet teprve následným webhookem, naše SQL sice druhé přidělení odmítne, ale B už zaplatil za něco, co mu nemůžeme dodat. Databázová ochrana sama tedy neřeší obchodní selhání externího checkoutu.

## UX a ověření před pilotem

- Starou záložku při návratu obnovit; při konfliktu zobrazit aktuální dostupnost a ponechat nesouvisející vyplněné údaje. Po ztrátě či expiraci holdu nenabízet platbu za nepotvrzené místo.
- Pro Shoptet určit stabilní serverovou identitu košíku/rezervace; oddělit ji od konkrétní obrazovky. Více oken stejného košíku musí pracovat s revizí a změnu buď převzít, nebo viditelně odmítnout. Synchronizace obrazovek nesmí být bezpečnostní pojistka kapacity.
- Otestovat dvě nezávislá okna, duplikovanou záložku, dva telefony, vložený i přímý formulář a Shoptet na posledním kuse/místě. Prověřit změnu množství, reload, odpojení sítě, pozdní odpověď a platbu při expiraci.
- Samostatně ověřit obyčejné vstupenky, sedadla, nezaplacenou objednávku, opakovanou notifikaci, storno a pozdní úhradu. Souběh domácího SQL není důkaz funkčního Shoptet kontraktu.

## Opory v kódu

- `database/functions/eshop/select_spot.sql`: `select_spot`, zámky a neprodlužování aktivního holdu opakovaným požadavkem.
- `database/functions/eshop/create_ticket_order.sql` a `finalize_ticket_order.sql`: zamknutí a transakční finalizace.
- `database/functions/eshop/materialize_ticket_products_internal_v1.sql`: ověření držitele a platnosti při tvorbě vstupenky.
- `database/functions/inventory/apply_allocations.sql`: sdílené limity, respektování aktivních holdů a zamknutí fyzických jednotek.
- `web_client/src/components/forms/reservation_capability_store.js` a `form_session.js`: sessionStorage oprávnění a autoritativní obnova.
- `web_client/src/components/blueprint/blueprint_selector.js`: načtení plánku a rezervační reader.
- `web_client/src/components/eshop/ticket_order_identity.js` a `database/functions/eshop_orders/create_ticket_order_client_sync_v1.sql`: identita příkazu a serverový replay.
- `web_client/scripts/blueprint_concurrency.mjs`: mimo jiné poslední sdílený kus mezi dvěma formuláři a závody kolem expirace/držení.
- `database/tests/eshop/blueprint_reservation_integrity_test.sql`: cizí/chybějící/expirovaný hold, stejný command a pokus o další objednávku prodaného sedadla.

Stav „implementováno“ označuje zkontrolovaný checkout. Neprokazuje samostatně shodu právě běžící produkce; v této úloze nebyl produkční backend čten ani měněn.
