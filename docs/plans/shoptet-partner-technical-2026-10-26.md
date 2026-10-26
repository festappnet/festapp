# Shoptet: technická příloha plánu

Součást [autoritativního plánu](shoptet-partner-onboarding-2026-10-26.md), 26. 10. 2026. Návrh kontraktů, nikoli popis již implementované integrace. Externí tvrzení vycházejí z níže uvedených primárních zdrojů; podporu na našem partnerském účtu dosud nemáme ověřenou.

## 1. Rozhodnutí o první verzi

Počáteční rozsah: CZ, CZK, jedna propojená akce/formulář v jednom Shoptet košíku; běžné zboží může být přimíchané. Jedna prodávaná jednotka znamená jednu vstupenku. Balíčky, předplatné, více akcí najednou a více měn zatím nepodporujeme. Není to globální omezení Festappu. Doprava a další zboží zůstávají v Shoptetu a nezvyšují cenu našich vstupenek.

Omezení jedné akce, prodejní doby a kapacity musí umět vynutit skutečná serverová hranice Shoptetu, včetně admin/API a obnoveného košíku. Pokud to neumí, zvolit po dohodě se Shoptetem proveditelné dělení externí objednávky na naše objednávky podle akce a alokaci částek, nebo zúžit produktový rozsah jiným prokazatelně vynutitelným způsobem. Do vyřešení se pilot nespustí. Pouhý JavaScript nepostačí.

Před vývojem potvrdit běžnou plnou online úhradu jako první podporovanou metodu. Bankovní převod a bezplatné vstupenky ověřit jako samostatné průchody před jejich zapnutím. Dobírka, zálohy, neurčené kombinované úhrady a poukazy nejsou automaticky podporované. Slevové kódy lze povolit jen po ověření přesného rozdělení částek a DPH v celém smíšeném košíku.

## 2. Brána proveditelnosti před implementací

V partner sandboxu vytvořit jedinou akci s posledním volným místem/kapacitou a dva zákaznické košíky; současně zkusit přímý nákup u nás. Uložit konkrétní API verzi, oprávnění, požadavky/odpovědi a anonymizovaný záznam SQL alokací. Prověřit také ruční objednávku v administraci, API import, obnovení košíku, změnu množství a nákup bez načtení našeho JS.

Výsledek musí zvolit jednu metodu pro konkrétní mapování:

- **Společná rezervace při checkoutu:** Shoptet před přijetím objednávky na serveru ověří a potvrdí naši rezervaci; nedostupné ověření prodej bezpečně odmítne. Nevíme, zda tuto hranici poskytne běžnému doplňku. Dokázat místo a čas předání tokenu i to, že jej nelze přesunout na jiné položky/e-shop.
- **Předem vyhrazený příděl:** pokud první možnost není dostupná, lze projednat kanálový příděl. Kapacita se nejprve atomicky odebere našemu přímému prodeji a až potom zveřejní v Shoptetu, který ji musí sám závazně omezovat. Při nejistém výsledku se příděl drží, nikoli vrací do prodeje. Zpětné uvolnění až po serverově ověřeném zastavení produktu, vypořádání objednávek a reconciliation. Vyžaduje nové výslovné rozšíření našich SQL alokací, ne nezávislý sklad. Pro konkrétní místa musí být doloženo i jednoznačné vyčlenění a výběr; úspěch u obecné kapacity neprokazuje prodej míst.

Ani jedna varianta není nyní vybraná nebo schválená. Kritéria výběru: žádný dvojí prodej v uvedených cestách, ověřené selhání při výpadku a cena/čas zákazníka přiměřené pilotu. Neuspěje-li žádná, vrátit se k technické domluvě. Neprogramovat import po zaplacení jako náhradu bezpečné kapacity.

## 3. Co se ukládá a proč

Návrh objektů pro `database/functions/eshop_shoptet/` a explicitní migrace, konkrétní názvy potvrdit po bráně proveditelnosti:

| Objekt | Účel a klíčová omezení |
| --- | --- |
| Instalace | Ověřená identita e-shopu, doplňku, tenant/unit a generace přístupu, stav a rozsah oprávnění. Tokeny šifrované, bez logování. |
| Mapování produktu | Produkt/varianta → akce/formulář/produkt u nás, podporovaná měna a metoda kapacity. Nová změna má revizi; již přijatý prodej drží původní snapshot. |
| Vazba prodeje | Stabilní identita `(addon, eshop, external_order_code, line_id)` přežije reinstall. Externí kódy jsou neprůhledné řetězce. Obsahuje naše order/ticket ID, snapshot ceny a mapování; nevytváří další tabulku vstupenek. |
| Rezervace/alokace | Platnost, revize, příslušné položky a kanonické SQL alokace. Neopírat se o libovolný session secret z prohlížeče. |
| Inbox a úkoly | Trvalé přijetí autentické události, zpracování, chyba a retry. Událost není sama finanční transakce. |
| Finanční fakta | Ověřený zdroj částky a měny, typ/původ/revize, vnější identita a vazba na naše payment_info; refundace oddělená. |

Generace tokenu nesmí být součást obchodního unikátního klíče prodeje. Nová generace nemá automatické právo zapisovat ke starým akcím: musí ověřit stejný e-shop a vlastníka a obnovit oprávněné vazby. Starý podepsaný webhook po odpojení nesmí změnit finance nové generace. Minimální deduplikační identita se uchovává podle dohodnuté retenční politiky; osobní data nepatří do deduplikačního klíče ani logů.

Před callbackem rozlišit instalaci doplňku a přihlášení administrátora. Oficiální dokumentace pro ně používá jiné OAuth tokeny. Při propojení vyžadovat jak doloženou kontrolu e-shopu, tak naše aktuální právo spravovat zvolenou jednotku/akci. Admin OAuth používá jednorázový náhodný state, přesné redirect URI a serverovou relaci; nepřevzít do backendu neověřený e-shop/tenant z URL. Instalace nejprve trvale uloží token, pak vrátí úspěch; nedokončená konfigurace neotevře prodej.

## 4. Život rezervace a objednávky

| Stav | Co se stalo | Kdo a kdy jej smí změnit |
| --- | --- | --- |
| Výběr / krátký hold | Uživatel vybírá místo, objednávka ještě nevznikla. | Naše SQL, omezená platnost a oprávněné obnovení. Opuštěný košík se uvolní. |
| Objednávková alokace | Shoptet přijal objednávku; položky, ceny a zákazník jsou svázané s naším order ID. | Serverový kontrakt z kroku 2 musí provést převzetí ještě před vypršením holdu. Krátký košíkový limit se již nepoužívá. |
| Čeká na úhradu | Existuje stabilní alokace a konkrétní platební termín. | Dle podporované platební metody; dlouhé převody vyžadují zvláštní termín a komunikaci. Žádný platný QR vstup před politikou úhrady. |
| Zaplaceno / vydáno | Ověřená úplná úhrada podporované položky. | Privilegovaná transakce finančního zdroje + kanonický přechod a e-mailový intent. Opakování nic nevydá podruhé. |
| Zrušeno / vypršelo | Objednávka nebo konkrétní položka ukončená. | Kanonické storno/uvolnění v transakci po ověření stavu protistrany. Nezpracovaná událost o platbě brání slepému uvolnění. |
| Konflikt | Například pozdní platba, změna ceny po zaplacení, nejasná položka nebo refundace. | Prodejce/podpora vidí důvod a podklady. Vstupenku na cizí místo nevydat; další kroky zaznamenat jako explicitní rozhodnutí. |

Událost o vytvoření může dorazit po úhradě. Consumer si vezme časově omezený aplikační lease pro externí objednávku, stáhne aktuální stav a poté jej aplikuje v krátké SQL transakci. Přes HTTP volání nedrží databázový zámek. Fencing token/revize zabrání commitu workeru, jehož lease převzal jiný worker. Řídí se ověřeným přechodem, ne pořadím příchozích webhooků. Samotný timestamp oznámení není monotónní revize entity. Pokud API verzi nedává, serializovat čtení/aplikaci pro objednávku, porovnávat ověřené snapshoty a při regresi finančních údajů otevřít konflikt. Opravná událost nesmí být omylem zahozena jako opakování původního create.

Změna množství nejprve vyžaduje novou alokaci pro přidávané kusy, potom potvrzenou změnu položky. Odebrané kusy se uvolní až po ověřené změně. Chyba mezi systémy vytvoří trvalý nedokončený úkol a blokaci dalšího prodeje dotčené kapacity. Přecenění nebo změna akce u již zaplacené položky je konflikt. Nepřepisovat původní finanční historii.

## 5. Finanční hranice v našem backendu

Dnes `eshop/finalize_ticket_order.sql` přijímá jen bank/stripe, cenu bere z materializovaných produktů a vytváří bankovní či Stripe payment_info. `eshop_transactions/payment_totals.sql` počítá bankovní a Stripe pohyby. `eshop_orders/recalculate_order_payment_status.sql` může u jiné než Stripe metody reaktivovat expired objednávku. Pouhé přidání řetězce `shoptet` tyto cesty neopraví.

Požadovaná změna v kroku 3:

- Privilegované přijetí Shoptet objednávky musí mít důvěryhodný snapshot jednotlivých vstupenkových položek, částky po slevách, měny, daně, jednotek a mapování. Sdílet kanonické kontroly/alokace; rozdělit finalizer jen v nezbytném místě zdroje ceny a platby. Veřejný create nikdy nepřijme externí snapshot ani údaj zaplaceno.
- Finanční zdroj Shoptetu má své ověřené identifikovatelné události/snapshoty a příspěvek do stávající projekce `payment_financial_totals_internal`. Přidat ochranu měny, zdroje a order scope. `refresh_payment_info_totals_internal` nesmí Shoptet platbu vynulovat. Reporty, cenové změny a ruční označení úhrady musí respektovat zdroj a existující autorizaci.
- Neplnit `paid_externally` jako anonymní zkratku a nevyrábět bankovní transakce. Shoptet objednávku vyřadit z automatického bankovního párování, našich platebních odkazů, připomínek dluhu a generické reaktivace expired. Při manuální úpravě zobrazit externí zdroj a přejít na dohodnutý postup.
- Finanční identitu neodvozovat z každé notifikace `order:update`: updaty obsahují i nefinanční změny. Má-li API identifikátory plateb/refundací, deduplikovat podle nich. Vrací-li jen agregáty, vést ověřované revizované snapshoty, nikdy jejich součty; podpora refundací je do vyjasnění blokovaná.
- U smíšeného košíku musí být jednoznačně určená část platby pro vstupenky. Plně zaplacenou celou objednávku lze rozdělit podle uložených konečných položek; nealokovaná částečná úhrada nestačí k vydání. Dopravu, poplatky, DPH, slevy a zaokrouhlení zachovat odděleně a s kontrolním součtem. Nevyvozovat zaplacení položky z libovolného procenta celkové úhrady.
- Zpřístupnit výsledek adminovi i reportům přes existující Client Sync/effect intent, nevytvořit tichou změnu pouze pro webhook. QR/PDF a zasílání používají stejný kanonický tiket a frontu jako ostatní kanály. Vrácení peněz samo nemá znovu vytvořit dluh nebo měnit již použitý vstup bez pravidla.

Předem uzavřít, kdo vystavuje fakturu za nákup a kdo účtuje naši službu. Shoptet je autorita checkoutu, ale nemusí sám vykonat pohyb peněz - ten provádí zvolená brána/banka. Nepřebírat endpointy určené vlastníkovi platební brány jako automatické oprávnění ticketingového doplňku. Účetnictví ani provizní sazbu nelze odhadnout z marketingového medailonku.

## 6. Webhook, obnova a odpojení

Zpracování: ověřený podpis nad raw tělem → přijetí do trvalého inboxu → HTTP potvrzení → worker načte oprávněný aktuální stav → SQL pod zámkem zapíše fakta, alokace a effect intent → potvrdí dokončení úkolu. Nevracet 200 před uložením. Konflikt obsahu pod stejnou identitou uchovat k řešení; podpis nepřiděluje automaticky přístup k libovolné akci.

Návrhový provozní kontrakt k ověření v sandboxu: nové přijetí potvrdit do dokumentovaných 4 sekund; async chybu opakovat po 1, 5, 15 a 60 minutách, nejvýše 8 pokusů, potom opravná fronta. HTTP429 respektuje Retry-After a společný per-shop limit. Stahování změn nejvýše po 5 minutách na aktivní pilotní instalaci, s kurzorem a přesahem pro zpožděné změny; skutečnou frekvenci přizpůsobit API limitům před pilotem. Úspěch cursoru potvrdit až po zpracování celé stránky, restart jej nesmí přeskočit. Opravné případy nesmějí vytlačit běžné úlohy.

Pozastavení a odinstalace nejsou totéž co výpadek našeho serveru:

| Situace | Chování |
| --- | --- |
| Náš incident, API přístup platí | Zastavit nové prodeje a pokračovat v bezpečném dopracování/reconciliation. |
| Shoptet suspend/invalid token | Zastavit volání, nezkoušet token v rychlé smyčce. Ponechat poslední známé alokace a neověřené finance ve frontě; upozornit pořadatele. |
| Uninstall/revokace | API již nemusí být dostupné. Odpojit zápisy nové instalace, smazat/revokovat používané secrets podle retenčního kontraktu; identita starých prodejů a historie zůstává. Neověřené platby řešit doloženě s pořadatelem, ne slibem dalšího API čtení. |
| Reinstall/resume | Ověřit stejný e-shop, nové oprávnění a mapování; nejdřív reconciliation starých vazeb, pak nové prodeje. Zachovat staré obchodní deduplikační klíče. |

Vydané vstupenky fungují i po odpojení. Nelze ale garantovat automatické zachycení nových refundací bez API: pořadatel musí mít jasný ruční způsob jejich doložení a zneplatnění QR s oprávněním a auditní stopou. Nezaměňovat ručně doložený fakt za údaj z API. Znovupřipojení jej porovná a nesmí jej načíst podruhé.

Sledovat per instalace: poslední úspěšné API sladění, stáří nejstaršího úkolu, počet retry/opravných případů, konflikty úhrad/kapacity a chybné podpisy. Při úhradě bez bezpečné alokace upozornit podporu a pořadatele hned po zjištění, do 5 minut zpracovatelem; při nejstarším úkolu nad 15 minut upozornit podporu. To je interní cíl, ne již slíbené SLA. Obsluha potřebuje tlačítka opakovat/srovnat/uzavřít s důvodem a rolí, ne možnost libovolně přepsat finance.

## 7. Pořadí změn a ověření

A. Krok 2: uložit podporovaný kontrakt a anonymizované skutečné request/response do `integrations/shoptet/evidence/`, včetně omezení. Dokud není jasný přenos rezervace/kapacity, žádné produkční schéma.

B. Krok 3: aditivní schéma a soukromé SQL procedury; explicitní grants a search_path; rozšíření kanonické finanční projekce, finalizeru a guardů; až potom Edge producer. Rollback nové produkční objednávky nemaže. Žádné persistentní aplikační triggery, druhá fronta e-mailů ani přepis historie. Frontend nové možnosti uvidí až po kompatibilním backendu.

C. Krok 4: výběr míst a životní cyklus až na ověřeném základě; veřejný klient nesmí sám označit úhradu. Test fixture vlastní izolovaný tenant, Shoptet sandbox a bezpečný sink pro emaily. Reálné placené nákupy jen po samostatné konkrétní domluvě.

D. Krok 5: vybraný pilot, limitované prodeje, podpora a cvičný incident včetně návratu. Zastavení konektoru musí umět zastavit prodej i v Shoptetu; pouhé skrytí našeho tlačítka nestačí. Nejde-li to při výpadku serveru zaručit, je nutná platformní pojistka z kroku 2. Nasazení podmiňuje samostatná kritika hotové implementace, běžné CI a příslušné backend/release brány.

| Test | Povinný důkaz |
| --- | --- |
| Poslední kapacita ze 3 souběžných cest, JS vynechaný, admin/API | Jedna alokace; další přijetí/platba znemožněná serverem nebo bezpečně omezená přídělem. |
| Hold, vytvořená nezaplacená objednávka, opuštěný košík, platba při expiraci | Žádný ztracený potvrzený prodej a žádné znovu přidělené místo. |
| Duplicate/out-of-order webhook, crash po SQL commit a před ack úkolu, reinstalace | Jedno order/ticket ID a právě jeden přijatý delivery intent. |
| Slevy a smíšený košík, změna ceny/množství/mapování, refundace použitého QR | Přesný snapshot a kontrolní součty; konflikt místo tichého přepisu nebo znovuvydání. |
| Cizí tenant/eshop, replay OAuth, starý podpisový klíč, falešné zaplaceno | Odmítnutí bez finančního či kapacitního efektu. |
| Výpadek, neplatný token, uninstall/resume, chybějící událost | Viditelná fronta, bezpečné zastavení, žádné API čtení po revokaci; dokázaná obnova/ruční řešení. |
| Změna SQL projekce | Regrese bank/Stripe, reportů, Client Sync a fronty; API import neotevře nový anonymní paid vstup. |

Existující opěrné testy: `database/tests/blueprint/capacity_resources_test.sql`, `database/tests/eshop/stripe/payment_totals_test.sql`, `database/tests/eshop/stripe/admission_test.sql`, `database/tests/client_sync/canonical_mutation_write_release_test.sql`. Nové kontrakty pokrýt scénáři v `database/tests/eshop/shoptet/` a cílenými Edge testy; SQL se spouští existujícím `web_client/scripts/run_db_tests.js` pouze proti izolovanému lokálnímu cíli. Žádné testy zatím spuštěné ani nová implementace.

## Primární podklady

- https://developers.shoptet.com/api/documentation/installing-the-addon/
- https://developers.shoptet.com/api/documentation/eshop-verification-using-oauth/
- https://developers.shoptet.com/api/documentation/webhooks/
- https://developers.shoptet.com/api/documentation/pausing-and-resuming-addon/
- https://developers.shoptet.com/api/documentation/uninstalling-the-addon/
- https://developers.shoptet.com/correct-api-usage/
- https://developers.shoptet.com/platebni-brany/ (práva platební brány nejsou automaticky práva našeho doplňku)
- https://developers.shoptet.com/api/documentation/inserting-html-codes/
- https://api.docs.shoptet.com/shoptet-api/openapi
