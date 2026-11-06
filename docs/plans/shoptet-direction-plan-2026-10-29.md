# Shoptet - podklady pro rozhodnutí o kapacitě a checkoutu

Historický výzkum a návrh z 29. 10. 2026, začleněný 6. 11. 2026. Nejde o implementaci ani novou autorizaci realizace. Tehdejší záznamy o neodeslání jsou překonané [stavem potvrzeným vlastníkem 1. 11.](shoptet-partner-onboarding-2026-10-26.md): návrh byl odeslán, čeká se na odpověď a další podání se neposílá.

Aktuální architekturu vlastní [společný Commerce Connector](../architecture/commerce-connectors.md) a jeho [realizační plán](commerce-connectors-plan-2026-10-29.md). Shoptet je první adaptér; tento starší průzkum zůstává podkladem, nikoli druhou implementační autoritou.

Datum: 29. 10. 2026. Stav: vlastník zvolil variantu A; veřejný průzkum doplněn, backendové garance čekají na samostatné ověření. Ověřování: standard kvůli souběhu a veřejným kontraktům. Výchozí zdroj Festappu: `00f05276de8c07c186c9d884e59291666d7707d6`. Práce probíhá v izolovaném worktree `festapp-shoptet-research-20261029`.

**Vybraný směr: varianta A, společná kapacita přes zvláštní napojení digitálního doručení (`shipping-request`).** Rozhodnutí o vývoji závisí na potvrzení použitelnosti a několika serverových garancí. Žádná varianta Shoptet konektoru není hotová.

Uživatel zakázal odesílání. Neodešel e-mail, návrh ani jiný formulář; nebyla vytvořena rezervace nebo testovací objednávka. Změny jsou pouze v dokumentaci a lokálním náhledu.

## Ověření bez opakovaného kontaktování Shoptetu

Vlastník zvolil A a chce maximum ověřit samostatně. [Nový rozbor veřejného kódu a sandboxové scénáře](shoptet-self-verification-2026-10-29.md) rozlišuje již doložené vlastnosti od neprovedených zkoušek. Q1-Q7 níže jsou ověřovací body; neznamenají povinnost poslat sedm dotazů podpoře. Schválení zvláštního typu doplňku je standardní onboarding. Dokud není podání povoleno, nic se neodesílá.

## Co má rozhodnutí přinést

Cílový produkt: zákazník koupí vstupenku v nativním Shoptet košíku, zaplatí přes e-shop pořadatele a dostane kanonickou vstupenku Festappu. Tatáž místa mají být podle původního záměru prodejná i naším formulářem na jiných webech. Otevřená stránka není rezervace a stará záložka nesmí umožnit zaplatit za už prodané místo.

Nejde o výběr platební brány nebo změnu ostatních integrací. Přesměrování všech plateb do našeho checkoutu by měnilo dosavadní produktové zadání a vyžaduje nové rozhodnutí vlastníka. Nesmí vzniknout jako tichý fallback.

## Nejdůležitější nově ověřená fakta

**F1 - existuje konkrétní serverový mechanismus, ne jen obecný webhook.** Speciální Shipping Addons se schvalují s API týmem; dokumentace zmiňuje i digitální doručení a upozorňuje na neustálenost implementace. Popisuje identitu košíku `shippingRequestCode`, nabídku uloženou serverovým PUT, kontrolu `verificationCode` a odmítnutí objednávky po `expires`. Po objednání lze zjistit stav požadavku a orderCode. To dokládá nadějný mechanismus; neprokazuje oprávnění našeho doplňku, vazbu na nezměněné položky ani vynucení dopravní metody u vstupenek. [Oficiální kontrakt](https://developers.shoptet.com/shipping-addons/).

**F2 - aktuální strojové schéma potvrzuje cestu API.** Živý export má verzi `e879ebd`, 218 cest. Používá `GET/PUT /api/shipping-request/{shippingRequestCode}/{shippingGuid}` a GET stejné cesty s `/status`. GET vrací mimo jiné SKU a množství; PUT má `expires` a vrací `verificationCode`. Ve čtené struktuře položek nebyl rezervační token ani revize košíku. To není důkaz, že nejsou dostupné jinak. [Čtení košíku](https://api.docs.shoptet.com/shoptet-api/openapi/shipping-requests), [zápis nabídky](https://api.docs.shoptet.com/shoptet-api/openapi/shipping-requests/updateshippingdata).

**F3 - skladové API je oddělená cesta.** `PATCH /api/stocks/{stockId}/movements` umí relativní i absolutní změny. Hodnota pro objednání se liší od fyzického stavu o nároky objednávek. Dávka může částečně selhat i při HTTP 200. Dokumentace neprokazuje atomické porovnání očekávané revize ani obchodní idempotency key skladového pohybu. [Endpoint](https://api.docs.shoptet.com/shoptet-api/openapi/stocks/updatequantityinstock).

**F4 - nastavení obchodu rozhoduje o ochraně skladu.** Shoptet popisuje prodej do minusu i vypnutí kontroly skladu; pouhá dostupnost „vyprodáno“ pak nemusí bránit objednání. Změny objednávek v administraci ovlivňují zásoby. Případný kvótový pilot proto vyžaduje doložené nastavení a ověření konkrétních vstupních cest. [Skladové hospodářství](https://podpora.shoptet.cz/skladove-hospodarstvi/). Skladový nárok se týká již rozpracovaných objednávek, nelze jej zaměnit za hold otevřeného košíku. [Nároky](https://podpora.shoptet.cz/skladove-naroky/).

**F5 - existuje skutečný srovnatelný produkt.** Doplněk Rezervační systém nabízí místa, Shoptet košík a QR; jeho veřejné demo bylo otevřeno bez výběru místa a bez vložení do košíku. Potvrzuje produktovou proveditelnost na platformě, nikoli sdílený sklad s dalším prodejcem nebo bezpečnost implementace. [Katalog](https://doplnky.shoptet.cz/rezervacni-system), [demo](https://531825.myshoptet.com/vstupenky-ples-2026/).

**F6 - některé finanční podklady už veřejné schéma obsahuje.** Detail objednávky má `paid` s hodnotami true/false/null a `paymentTransactions` včetně transactionId, ceny, stavu a časů. Přístupnost a úplnost pro konkrétní metody se musí ověřit; `paid=true` může být důsledek obsluhy/stavové automatizace a není univerzální bankovní výpis. [Detail objednávky](https://api.docs.shoptet.com/shoptet-api/openapi/orders/getorderdetail), [stavy](https://podpora.shoptet.cz/stavy-objednavky/).

Doklad verze, hash celého staženého veřejného schématu a výběr skutečných polí: [public-contract.json](shoptet-direction-evidence-2026-10-29/public-contract.json). Specifikace byla přečtena, žádný chráněný API endpoint nebyl volán. Veřejný výpis cest neobsahoval obecnou reservation cestu; z toho nelze dovodit neexistenci zvláštního partnerského kontraktu.

## Srovnání variant

| Varianta | Nativní Shoptet platba | Tatáž kapacita současně u nás | Důkaz dnes | Doporučení |
| --- | --- | --- | --- | --- |
| A. Společná rezervace přes schválené digitální doručení | Ano, zamýšlený model | Ano, po implementaci a ověření | Konkrétní dokumentovaný mechanismus; ne všechny potřebné garance | První cesta k ověření. Nejlépe odpovídá původnímu cíli. |
| B. Pevný kanálový příděl pro Shoptet | Ano | Jen rozdělené množství nebo přesně vyčleněná sedadla | Skladové operace doložené; kanálový příděl ve Festappu neexistuje | Záložní cesta, pokud A neprojde a omezení přídělu dává pořadateli smysl. |
| C. Shoptet jako jediný prodejce dané nabídky | Ano | Ne; naše formuláře ji přímo neprodávají | Jednodušší model jedné prodejní autority, pořád nutno otestovat sklad a import | Možný samostatný menší produkt. Jen po výslovném přijetí tohoto omezení vlastníkem. |
| D. Každé sedadlo jako nativní varianta s jedním kusem | Ano | Ne automaticky; kombinuje se s B nebo C | Varianty a sklad existují; souběh ověřen nebyl | Nástroj pro vyhrazené sedačky, ne řešení sdílené kapacity. |
| E. Vložený Festapp checkout na stránce Shoptetu | Ne | Ano, přes naši existující autoritu | Existující vlastní checkout, přijetí tohoto typu doplňku neověřeno | Jen při změně zadání. Nezaměňovat za nativní integraci. |
| F. Dva sklady synchronizované webhookem po prodeji | Ano | Pouze zdánlivě | Časové okno pro dvojí prodej zůstává | Pro nedostatkové vstupenky zamítnout. |

U D uvádí Shoptet nejvýše 512 variant na produkt. Rozdělení většího sálu do produktů je další katalogová a UX práce, ne prosté zapnutí mapy. [Limit variant](https://podpora.shoptet.cz/sablony-variant/). Zákaznické kliknutí do mapy by samo nebylo časovou rezervací; konečné přidělení by dělal nativní sklad, pokud to konkrétní kontrakt prokáže.

Komerční překryv s existujícím doplňkem znamená, že návrh má zdůraznit naše konkrétní výhody pro pořadatele. Není doložená automatická poptávka po druhém obecném rezervačním systému. Samotný funkční konkurent také nedokazuje, že schvalovatel přijme nový doplněk.

## Jak by fungovala preferovaná varianta A

Následující je návrh našeho chování, nikoli dodatečná záruka Shoptetu.

1. Otevření stránky nic neblokuje. Zákazník zvolí počet nebo místa. Browser je pouze ovládání.
2. Server ověří připojený e-shop a přes autorizované API načte košík. Pro konkrétní košík zamkne naši revizi rezervace a atomicky přidělí společnou kapacitu. Rozsah obsahuje instalaci, SKU, množství, případně konkrétní sedadla a neměnný otisk relevantního obsahu.
3. Až po uložení rezervace server odešle nabídku s expirací. Neúspěšný nebo nejasný PUT nesmí ponechat prodejnou kapacitu, ke které by mohl existovat stále platný checkout; případ drží zámek evidence do srovnání. Browser nevidí Shoptet token ani tajemství naší rezervace.
4. Shoptet musí před závazným přijetím objednávky vynutit platnost správné nabídky pro správné položky. To je podmínka, kterou veřejné podklady zatím v celém rozsahu nepotvrdily. Jestli lze zvolit jinou dopravu a tím rezervaci obejít, samotná varianta A neprošla.
5. Přijatá objednávka převezme rezervaci do objednávkové alokace. Vydání a doručení vstupenek nastane až podle ověřeného finančního stavu. Nemíchá se s běžným interním bankovním párováním ani s další platební výzvou Festappu.
6. Pokud potvrzení nepřišlo včas, původní kapacita zůstane chráněná, dokud není autoritativně rozhodnut stav externího požadavku. Čas v browseru ani samotné vypršení běžného holdu nedokládá, že Shoptet objednávku nepřijal.

### Kritický závod na konci rezervace

Příklad: nabídka platí do 12:00:00; Shoptet přijme objednávku v 11:59:59; webhook dorazí ve 12:00:03. Pokud Festapp ve 12:00:00 uvolní židli do přímého prodeje, ochrana selhala. Řešením není odhadnout „dost dlouhé“ zpoždění webhooku. Potřebujeme potvrzenou finalitu/revizi a po dobu nejistoty zablokované místo. Neznámý stav může zhoršit dostupnost prodeje, ale nesmí zvyšovat prodejní kapacitu.

Běžný `select_spot` má expirovatelný hold. Takový hold se nemůže bez úpravy použít pro externí rozhodnutí, jehož výsledek zatím neznáme. Nesmíme spoléhat jen na prodloužení hodnoty `secret_expiration_time`: všechny naše alokátory musí rozumět chráněné externí rezervaci, jinak jiná prodejní cesta místo přidělí.

## Více záložek a více webů

Pro A je identitou serverově ověřený košík a naše revize rezervace. Dvě záložky stejného košíku musí buď pracovat s aktuální revizí, nebo změnu viditelně odmítnout. Starší výběr nesmí znovu přepsat novější nabídku po opožděném HTTP výsledku. Je třeba potvrdit, zda backend Shoptetu umožňuje starší nabídku odmítnout i při souběžných PUT; pořadí odpovědí browseru nestačí.

Jiný telefon obvykle znamená jiný košík. Nevazat rezervaci automaticky podle e-mailu: tentýž zákazník může záměrně dělat dva nákupy. Přímý formulář i embed na dalším webu spotřebovávají stejnou kanonickou kapacitu Festappu; jejich browserová úložiště se nemusejí sdílet.

Při návratu do staré záložky znovu načíst stav. Pokud mezitím změna v jiném okně zrušila rezervaci, ukázat aktuální výběr/konflikt a ponechat ostatní vyplněné údaje. Živé překreslování je zlepšení UX; bezpečnost musí platit i bez něj a při přerušené síti.

Pro C nejsou dvě okna konkurenty našeho a Shoptet skladu, protože nabídka se prodává výhradně přes Shoptet. To zjednodušuje hranici, ale mění možnost pořadatele prodávat stejnou nabídku přímo přes Festapp. Nelze to označit za stejný produkt s menší technickou složitostí.

## Vlastnosti k ověření - dokumentace a vlastní sandbox před dotazem

| ID | Otázka | Dopad odpovědi |
| --- | --- | --- |
| Q1 | Lze naši ticketingovou službu schválit jako digitální Shipping Addon se serverovým `shipping-request` kontraktem? Jaká je jeho aktuální produkční podpora? | Bez této dostupnosti není A konkrétní implementační cesta. |
| Q2 | Lze pro každou vstupenkovou položku serverově vynutit naši validní nabídku; co jiná doprava, uložený košík, přímé přidání produktu a administrativní/API vytvoření objednávky? | Žádný veřejný checkout nesmí získat vstupenku obcházející rezervaci. Zvláštní oprávněné admin cesty musí mít explicitně dohodnutý režim. |
| Q3 | Co přesně `verificationCode` váže? Zneplatní se při změně SKU, množství, měny, varianty a opětovném PUT? Existuje atomická revize/CAS nebo jiné zabránění přepisu starou nabídkou? | Rozhoduje o bezpečnosti více záložek a pozdních odpovědí. |
| Q4 | Jaká je finalita `/status` při expiraci a zpožděném webhooku? Může se `open` nebo `cancelled` později změnit na přijatou objednávku téže nabídky? Existuje konečná revokace nabídky? | Bez důkazu nepřijetí nesmíme uvolnit rezervovanou kapacitu. |
| Q5 | Co se stane se smíšeným košíkem fyzického zboží a vstupenek, když košík vybírá jednu dopravu? Existuje podporovaný způsob kombinace? | První verze nesmí bez ověření slibovat libovolné smíšené košíky. Ani omezení „jen vstupenky“ nesmí být jen JS hláška. |
| Q6 | Jaký přesný finanční údaj a změnovou událost máme použít pro plnou úhradu, odloženou platbu, refundaci a ruční označení zaplaceno? Jaké údaje získá běžný doplněk? | Definuje vznik a zneplatnění QR bez vymýšlení účetních faktů. |
| Q7 | U B/C: ve kterých cestách je zákaz prodeje do minusu atomický? Jak se pozná a provede bezpečný idempotentní skladový pohyb po ztrátě odpovědi? | Bez průkazu ochrany nelze kvótu vydávat za bezpečnou. |

Tyto body se nejprve prověří samostatně podle S1-S10 v navazujícím rozboru. Případnou komunikaci omezit na nutný onboarding nebo konkrétní zjištěný rozpor; nyní není odesílání povoleno.

## Rozhodovací pravidla

- Pokud A prokáže vynucení nabídky, vazbu na položky a bezpečnou finalitu, doporučuji A jako cílovou architekturu pro společná místa. Pořadatel nemusí ručně přesouvat příděly mezi kanály.
- Pokud A není dostupná, ale vlastník chce nativní Shoptet prodej a přijme rozdělení kapacity, posoudit B. Například příděl 20 z celkových 100 nejprve závazně vyhradit u nás, potom jej nabídnout v Shoptetu. Přijaté Shoptet objednávky spotřebovávají těch 20, nikoli další kus z našich zbývajících 80. Vrácení přídělu až po prokázaném zastavení a vypořádání.
- Pokud hlavním cílem je levnější první konektor pro obchodníky, kteří prodávají pouze přes Shoptet, může být C lepší první produkt než B. To je obchodní volba, ne technická nutnost. U takového modelu se nepovolí souběžný přímý prodej vyčleněné nabídky u nás.
- Jestliže A neprojde a uživatel nechce omezení B ani C, vývoj nativního konektoru zatím nezahajovat. E je návrh jiného produktu a F není přijatelná náhrada.

Předchozí doporučení „začít menším pevným přídělem“ bylo předčasné. Zůstává možností, ne výsledkem průzkumu. Připravený formulářový návrh má představit cíl a požadavek na ověření A; nemá tvrdit, že kvóta už byla vybraná, nebo že dosavadní endpointy postačují k implementaci.

## Co existuje v našem kódu

| Hranice | Dnes | Co je třeba doplnit po rozhodnutí |
| --- | --- | --- |
| Sedadla a sdílené inventory | SQL zámky, hold, finální přidělení; viz `select_spot.sql`, `finalize_ticket_order.sql`, `inventory/apply_allocations.sql` | Externí rezervaci se stavem nejistého výsledku počítanou ve stejné autoritě. |
| Obnova rozpracovaného výběru | `reservation_capability_store.js`, `form_session.js`; sessionStorage a autoritativní read | Serverovou vazbu na externí košík, revizi a obnovení více oken. |
| Opakované příkazy | Command identity a SQL receipts | Stabilní externí obchodní klíč přežívající reinstalaci, inbox a reconciliation. |
| Objednávka a úhrada | Vlastní finalizer, bank/Stripe projekce a jedna e-mailová fronta | Ověřený externí cenový/platební zdroj a potlačení druhé platební výzvy. |
| Shoptet adaptér | V relevantních runtime adresářích nebyl nalezen | Instalace, oprávnění, mapování, rezervace, transport a obsluha incidentů. |

Podrobnosti původního domácího souběhu jsou v [kapacitním posouzení](shoptet-capacity-assessment-2026-10-29.md). Existující testy nepředstavují nový běh ani ověření živé produkce. Veřejné demo konkurenta také není test našich garancí.

## Další postup po etapách

### Etapa 1 - uzavřít platformní kontrakt

Nyní připravit pouze tento podklad, otázky a endpointy podle vybrané kandidátní cesty. Po samostatném svolení lze pokračovat v existujícím partnerském vlákně/podání; nevytvářet paralelní žádosti. Výstupem má být odpověď Q1-Q7, případně vývojové přístupy. Zatím žádné schéma produkce nebo falešný živý callback.

Hotovo: vybraná A/B/C s doloženými garancemi a přijatým produktovým omezením, nebo výslovné rozhodnutí neimplementovat. Neuzavřené Q2-Q4 blokují A. Nejde o povinnost vzdát se záměru jen kvůli chybějícímu sandboxu při přípravě žádosti.

### Etapa 2 - minimální experiment v povoleném sandboxu

Po získání přístupů samostatně autorizovat potřebné sandboxové mutace. A: vytvořit nabídku s krátkou expirací pro poslední místo, prověřit čerstvý/stará/změněný košík, dvě záložky, jinou dopravu a pozdní potvrzení proti přímému SQL kupujícímu. B/C: dvě Shoptet objednávky na poslední skladový kus, prodej do minusu, změna v administraci a nejasný PATCH výsledek. Platba jen podporovanou testovací metodou bez reálných peněz.

Hotovo: anonymizované skutečné request/response a readback jediné alokace, odmítnutý obcházející checkout, bezpečný stav po ztrátě odpovědi a doklad konečné revokace/nepřijetí před uvolněním. Selhání vede k novému rozhodnutí, nikoli přidání tichého fallbacku.

### Etapa 3 - teprve potom realizační návrh a implementace

Doplnit jedinou vybranou cestu do `integrations/shoptet/`, serverové SQL hranice do `database/functions/eshop_shoptet/` a odpovídající Edge vstupy podle potvrzeného kontraktu. Kapacitu stále mění kanonické SQL; nepřidávat druhé tickets/orders ani alternativní e-mailovou frontu. Přesnou persistenci externí rezervace zvolit až podle garancí Shoptetu a pokrýt ji ve všech domácích admission/read cestách. Žádné dlouhé SQL transakce čekající na externí HTTP.

Nejdříve průchod s běžnými vstupenkami, poté sedadla nad stejnou prokázanou hranicí. Smíšený košík nebo více akcí nejsou automaticky podporované jen proto, že backend přijímá pole položek. Vybraná finanční data musí zachovat slevy, daně, měnu i pořadí oprav; refundace a storno nejsou totožné.

Hotovo: cílené SQL/Edge/JS scénáře, skutečný sandboxový průchod, žádný dvojí prodej, účtování ani doručení. Nasazení a pilot jsou další samostatně autorizované kroky.

## Ověření a podmínky rozhodnutí

| Riziko | Důkaz, který potřebujeme |
| --- | --- |
| Dva prodejní kanály prodají poslední kus | Paralelní transakce a platný druhý checkout odmítnutý ještě před závazným nákupem. |
| Starší okno přepíše novější místa | Opačné pořadí odpovědí/PUT a odmítnutí staré revize na rozhodující hranici. |
| Vypršel čas, objednávka už byla přijata | Zpožděný webhook, zjištění skutečného přijetí a zachovaná původní alokace. |
| Webhook se ztratil nebo přišel dvakrát | Stavový dotaz, stabilní obchodní identita a jeden efekt. |
| Změna dopravy/množství nebo admin/API obchvat | Konkrétní podporované cesty mají prokázané vynucení; ostatní jsou smluvně i provozně ohraničené. |
| Kvóta vrácená, přitom ještě prodávaná | Prokázané stopnutí, vypořádání všech pending stavů a jediný návrat kapacity. |
| Placeno neznamená ověřený příjem | Předem určený finanční kontrakt pro konkrétní metodu a zvláštní řešení ručních změn/refundací. |

V této průzkumné etapě nebyly spuštěny aplikační testy. Kontrola dokumentů ověří lokální odkazy a konzistenci exportovaného kontraktu. Experimenty až v oprávněném izolovaném prostředí; veřejný konkurenční e-shop není náš sandbox.

## Co tento dokument nahrazuje a co ponechává

Aktuální doporučení a pořadí rozhodování vlastní tento dokument. Dřívější [onboarding](shoptet-partner-onboarding-2026-10-26.md) a [technická příloha](shoptet-partner-technical-2026-10-26.md) zůstávají podklady pro původní doménové invarianty, ne autoritou nad nově ověřenou kandidátní cestou. Předchozí kapacitní posouzení zachovává popis domácího kódu; jeho preference kvóty je nahrazena tímto podmíněným rozhodovacím stromem.

Nevznikají dvě běžící implementace a nic z runtime se nemaže. Při pozdějším vývoji se implementuje jedna přijatá cesta, nikoli A a B současně pro tutéž kapacitu. Historický odeslaný úvodní e-mail se nepřepisuje. Zákaz nových podání a zpráv trvá.
