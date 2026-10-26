# Shoptet: partnerský doplněk pro prodej vstupenek

26. 10. 2026 · Stav: úvodní návrh odeslán API týmu, čekáme na odpověď; platformní kontrakt dosud nepotvrzený · Ověřování: standard

Stručný obchodní postup je níže, podrobný návrh kontraktů a testů v [technické příloze](shoptet-partner-technical-2026-10-26.md). Oba dokumenty tvoří jeden plán; příloha nerozšiřuje oprávnění k produkčním zásahům.

## Co chceme

Zákazník vybere vstupenku na e-shopu, dokončí běžnou Shoptet objednávku a zaplatí jeho platební metodou. Náš systém zajistí kapacitu, případně výběr místa, QR vstupenky a odbavení. Pořadatel bude akci nastavovat u nás a spojí ji s produktem v Shoptetu.

To je doporučený návrh k projednání, ne již potvrzená možnost integrace. Nahrazuje původní pracovní úvahu o vloženém formuláři s naším checkoutem. WordPress, Joomla, Wix ani běžný prodej přes naši aplikaci se tím neruší.

## Co už víme

- Shoptet má samostatné API partnerství. Postup je návrh → posouzení → smlouva a vývojové přístupy → vývoj → technická kontrola a medailonek → zveřejnění. U posouzení uvádí odpověď do čtyř týdnů, nikoli garantované přijetí. [Postup](https://doplnky.shoptet.cz/chcete-delat-vlastni-doplnky), [partnerství](https://partneri.shoptet.cz/api-partneri/).
- Doplněk [Rezervační systém](https://doplnky.shoptet.cz/rezervacni-system) veřejně popisuje výběr míst, Shoptet košík, QR a odbavení. Dokládá produktový model, ne jeho vnitřní architekturu nebo dostupnost konkrétních integračních háčků pro nás.
- Dokumentace nabízí [vložení produktu do košíku](https://developers.shoptet.com/home/shoptet-tools/editing-templates/how-to-properly-add-product-to-cart-with-javascript/), [webhooky](https://developers.shoptet.com/api/documentation/webhooks/) a [vkládání kódu](https://developers.shoptet.com/api/documentation/inserting-html-codes/). Neprokazuje tím atomickou rezervaci našeho místa během Shoptet checkoutu.
- U nás objednávku a kapacitu mění SQL, nikoli frontend: `lib/components/eshop/README.md`, `database/functions/eshop/create_ticket_order.sql`, `database/functions/eshop_orders/create_ticket_order_client_sync_v1.sql`, `database/functions/eshop/select_spot.sql`. Existující obálka také rovnou připravuje potvrzovací e-mail; nelze ji bez úpravy použít jako neutrální import.
- Přechod do zaplaceno a doručení vlastní `database/functions/eshop_orders/update_order_and_tickets_to_paid.sql`; e-maily procházejí `public.email_messages`. Shoptet nesmí zavést druhý generátor vstupenek nebo přímé odesílání.
- V prohledané poště není nalezená partnerská žádost pro vstupenky.online. Starší obchodní hovor ke Shoptetu existuje; před odesláním ještě ověřit případné jiné vlákno/kanál.

## Navržené rozdělení odpovědnosti

| Oblast | Kdo ji vede |
| --- | --- |
| Produkt na e-shopu, košík, cena skutečně zaplacené položky, sleva, platba a vrácení peněz | Shoptet |
| Akce, místa, společná kapacita všech prodejních kanálů, QR, PDF a vstup | Festapp |
| Vazba produktu na akci, rezervace na položku a potvrzených finančních faktů | Shoptet adaptér |

Nastavení události zůstane u nás. V Shoptetu bude nezbytné propojení produktů a stav napojení. Cena a dostupnost se musí smluvně i technicky sjednotit před prodejem: náš adaptér nesmí přepočítat již zaplacenou Shoptet objednávku podle dnešního ceníku. Jedna Shoptet objednávka může obsahovat běžné zboží i vstupenky; přenášíme pouze výslovně navázané položky a rozdělení slev/refundací pro ně.

### Pravidla, která musí platit

1. Jedna kapacita pro náš přímý prodej i Shoptet. Žádná druhá nezávislá zásoba míst.
2. Opakovaný webhook nevytvoří druhou objednávku, platbu ani vstupenku. Obchodní identita je doplněk + ověřený e-shop + objednávka + položka a musí přežít přeinstalaci. Generace instalace určuje oprávnění ke zpracování; změny mají vlastní trvalou evidenci a otisk obsahu.
3. Platbu potvrzuje ověřený stav Shoptetu, nikoli návrat zákazníka z brány nebo pouhý název stavu objednávky. U těchto položek náš BankSync a jiné brány nesmějí zaúčtovat stejnou úhradu podruhé.
4. Podpis webhooku se ověří nad původním tělem a s klíčem konkrétní instalace. Po trvalém přijetí do inboxu následuje rychlé potvrzení; další práce běží asynchronně. Po běžném výpadku stav doplní omezená reconciliace přes API. Při pozastavení/odinstalaci se API může stát nedostupným; neověřené platby čekají na obnovení nebo doložené ruční řešení.
5. Náhodné pořadí událostí nesmí vrátit zaplacenou objednávku do rezervace. Pozdní platba po uvolnění místa znamená viditelný konflikt, ne automatický prodej již obsazeného místa.
6. Storno, vrácení peněz a zneplatnění QR jsou různé skutečnosti. Částečná refundace se váže na konkrétní položky/vstupenky; peníze nevracíme automaticky z našeho systému bez dohodnutého procesu.
7. E-shop se váže na oprávněného pořadatele a konkrétní akce. OAuth tajemství jsou jen na serveru, odinstalace/nová instalace nesmějí obnovit stará oprávnění nebo přehrát staré prodeje.

## Plán v pěti krocích

| Krok | Výsledek a práce | Jak poznáme hotovo |
| --- | --- | --- |
| 1. Představit záměr | Použít přiložený návrh; doplnit skutečný právní subjekt, IČO, kontakty a cenový model. Ověřit, že žádost už není jinde. Běžnou provizi nezdržovat, zjistit pevné členské a podmínky služby. | Jedno přijaté podání s potvrzením a seznam otázek pro API tým. Odeslání evidovat až podle skutečné odpovědi formuláře. |
| 2. Ověřit kritické napojení | Po získání partnerských přístupů v samostatném testovacím e-shopu ověřit vazbu rezervace na košík/položku, změnu množství, obnovu stránky, přímé API/admin objednávky, zaplacení a storno. Zjistit dostupnost serverového ověření před přijetím objednávky a limity oprávnění. | Schválený datový kontrakt a průkazný experiment: dva kupující a náš přímý prodej nespotřebují stejné poslední místo. Bez tohoto výsledku neimplementovat ani neslibovat prodej míst. |
| 3. Základ konektoru | Založit `integrations/shoptet/` pro adaptér, manifest oprávnění, návody a důkazy; serverový OAuth/webhook vstup v `supabase/functions/`. SQL vlastní instalace, mapování, inbox a vazby na existující objednávky. Nejprve obyčejná vstupenka bez mapy sálu. | Reálný průchod testovacím Shoptet košíkem a potvrzenou testovací úhradou vytvoří právě jednu naši objednávku a jedno doručení. Změny neovlivní ostatní kanály. |
| 4. Místa a životní cyklus | Připojit existující výběr míst bez našeho platebního kroku. Provázat hold, expiraci a objednávku; doplnit změnu množství, zrušení, částečnou úhradu/refundaci, výpadek, pause/uninstall a obnovu z API. | Matice níže projde proti skutečnému Shoptet prostředí. Když platforma neumí potřebné garance, vrátit návrh k domluvě; nenahradit problém tichým externím checkoutem. |
| 5. Pilot a katalog | Jeden výslovně vybraný pořadatel a akce, návod, skutečné screenshoty, podpora a metriky. Technická a obchodní kontrola Shoptetem, poté domluvené spuštění. | Ověřený pilot bez dvojího prodeje/účtování a anonymně dostupný záznam v katalogu. Samotná instalace není publikace. |

### Technické zadání pro kroky 2-4

Konkrétní endpointy a oprávnění určit z aktuálního OpenAPI a testovacího účtu, ne hádáním. Pro začátek doložené `POST /api/webhooks`, `GET /api/webhooks`, `DELETE /api/webhooks/{id}`, `POST /api/webhooks/renew-signature-key` a čtení detailu objednávky z dokumentace. Další potřebné čtení produktů, plateb/stavů a případné zápisy přidat až podle potvrzeného kontraktu. Pokud stačí mapovat existující produkty, nepotřebujeme obecný zápis katalogu ani správu zákazníků.

Nové SQL umístit do `database/functions/eshop_shoptet/` a explicitních verzovaných migrací. Navržené objekty jsou evidence instalací, produktových vazeb, inboxu a externích order/payment vazeb; přesné názvy určit po kroku 2. Nezakládat druhé orders/tickets tabulky. Současný `database/functions/eshop/finalize_ticket_order.sql` přijímá jen bank/stripe a počítá katalogovou cenu; `database/functions/eshop_transactions/payment_totals.sql` sčítá bankovní a Stripe pohyby. Před Shoptet importem je nutný privilegovaný externí zdroj ceny a finančních faktů promítnutý do stávajícího součtu, reportů i guardů. Podrobný rozsah stanoví technická příloha; pouhé nastavení `paid_externally` není řešení. Privilegovaný interní vstup musí ověřit instalaci a rozsah, použít kanonické alokace a transakčně zapsat efekt/receipt. Veřejný klient nesmí sám předat důvěryhodné „zaplaceno“ nebo nový platební zdroj. Existující potvrzovací e-mail nesmí vyzývat k další platbě za Shoptet objednávku.

Dokumentace webhooků uvádí odpověď do 4 sekund a omezené opakování, proto nestačí spoléhat na další doručení. V implementaci ověřit aktuální podpisový kontrakt, rotaci klíče, API limity a ochranu webhooku před zahlcením. Nezaměňovat OAuth stav s identitou e-shopu převzatou z libovolného požadavku.

U prodeje bez míst platí stejná kontrola společné kapacity jako u mapy sálu. Pokud Shoptet nemá vhodnou synchronní hranici, je třeba se Shoptetem dohodnout skutečně bezpečnou alokaci kapacity pro kanál, která se promítne do naší SQL autority; prosté kopírování skladového počtu ani webhook po zaplacení nejsou záruka. Toto je otevřené rozhodnutí, ne připravená funkce.

## Ověření a bezpečné spuštění

- Lokální SQL integrační testy: poslední místo, souběh s přímým prodejem, opakování, změněný obsah pod stejnou identitou, expirace versus pozdní platba, částečné storno a oprávnění jiné organizace.
- Skutečný Shoptet test: smíšený košík, slevy, daně/měna a zaokrouhlení, množství, změna/storno objednávky, pořadí a ztráta webhooků, znovupřipojení. Ověřit konkrétní podporované platební metody; neoznačit všechny za otestované po jedné metodě.
- Doručení a vstup: právě jedna kanonická fronta, PDF a dekódované QR, platný vstup a odmítnutý opakovaný/zrušený vstup.
- Každou dávku ověřit cílenými SQL/Edge/JS testy v lokálním prostředí; přesné existující příkazy převzít z příslušného balíčku. Žádné plošné Flutter buildy kvůli plánování.

Nasazení: nejdřív aditivní SQL a neveřejný serverový adaptér, potom oprávnění a jeden pilot. Změny sdíleného backendu ověřit i pro stávající klienty. Migrace, produkční přístupy a spuštění budou konkrétní samostatné realizační kroky, tento plán je neprovádí. Při poruše zastavit nové prodeje konektorem a pokračovat jen v ověřitelném zpracování rozpracovaných případů a podpoře; nezrušit hromadně rezervace a nevypnout stávající QR. Kompenzace druhého systému vést jako trvalý úkol, ne tvrdit, že HTTP a SQL tvoří jednu transakci.

## Co vyřešit se Shoptetem

- Partnerská dostupnost testovacího prostředí a bezpečná vazba míst/kapacity na nativní checkout, včetně obcházejících cest.
- Které API skutečnosti dokládají zaplacení, refundaci a storno; jak navázat identitu položky a rezervace i při úpravě objednávky.
- Cena konektoru, servisní příjem, běžná provize a případné pevné poplatky. Nic z toho zatím není dohodnuté; žádná nová sazba ani placené členství není schváleno.
- Způsob distribuce frontend kódu: dokumentace zmiňuje Addon Repository a partnerský hosting. Existující widget nepřebírat bez jejich posouzení.

## Rozhodnutí před implementací

První podání není podmíněné hotovým prototypem ani partnerskými přístupy. Jeho cílem je domluvit technickou konzultaci. Formulářové povinné API use cases popíšeme jako návrh s označenými nejistotami; nebudeme potvrzovat nepravdivá prohlášení. Pokud formulář vyžaduje již rozhodnutý technický kontrakt, použijeme nejprve oficiální kontakt `api@shoptet.cz`, nikoli smyšlené odpovědi. Neodesílat oba kanály duplicitně.

Krok 2 je rozhodovací brána pro oba typy vstupenek. Bez bezpečné kapacity se nespouští ani obyčejná vstupenka. Zvolená metoda musí být jedna pro daný produkt/akci a má přesně vymezené obcházející cesty. Konkurenční rezervaci řešíme na serveru, ne vypnutím tlačítka v prohlížeči.

## Hotovo znamená

Přijatá a smluvně odsouhlasená spolupráce, bezpečný testovaný prodej Shoptet košíkem, jedna naše kapacita a evidence vstupenek, vyřešená storna a výpadky, skutečný pilot a veřejný katalogový záznam. Do té doby přesně rozlišovat připraveno / podáno / schváleno / zveřejněno.

Jde o nový prodejní kanál. Stávající checkouty ani historické objednávky se nemigrují a nemažou. Původní varianta externího Shoptet checkoutu není druhá větev k implementaci; tento dokument je jediný aktuální plán. Hlavní zbývající riziko je platformní garance rezervace před zaplacením, ne vykreslení widgetu.

Podklady: [návrh pro Shoptet](shoptet-partner-proposal-2026-10-26.md), [zadání pro realizaci](shoptet-partner-EXECUTION-PROMPT-2026-10-26.md), [přihlašovací formulář](https://salesforce-eu.123formbuilder.com/form-62353/cz-nabidka-noveho-doplnku), [OpenAPI](https://api.docs.shoptet.com/shoptet-api/openapi), [medailonek a ceny](https://developers.shoptet.com/api/documentation/shoptet-api-starters-guide/).

## Úvodní kontakt odeslán

Po schválení finálního textu vlastníkem byl návrh jednou odeslán na oficiální `api@shoptet.cz`, s odpovědní adresou `info@festapp.net`. Gmail potvrdil stav SENT; doručení ani odpověď zatím potvrzené nejsou. Jde o úvodní žádost o spolupráci a technickou domluvu, nikoli podání do marketplace nebo přijetí smlouvy. Neodesílat současně druhou žádost formulářem. [Záznam](shoptet-partner-contact-2026-10-26.json).
