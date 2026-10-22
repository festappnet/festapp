# Exekuční prompt: Stripe na vlastním účtu pořadatele

Implementuj integraci Stripe do Festapp podle autoritativního plánu:

`docs/plans/stripe-client-owned-plan-2026-10-21.md`

Přečti plán celý včetně UI/UX kontraktu A-I, akceptační matice A01-A25, zachovaných/nahrazených hranic a podmínek pilotu. Před změnami přečti aktuální AGENTS.md, CLAUDE.md a docs/architecture/ai_context.md. Ověřování: `standard` (platby, oprávnění, veřejné kontrakty a databáze). Respektuj cizí změny v pracovním stromu.

## Výsledek a rozsah

Pořadatel připojí vlastní Stripe účet a v něm spravuje výplaty, refundace a spory. Festapp zajišťuje objednávku, kapacitu, platbu na účet pořadatele, převzetí platebních faktů a vstupenky. MVP: Stripe-hosted Checkout, direct charges, plný Dashboard klienta, bez provize Festapp a bez převzetí odpovědnosti za záporné zůstatky klienta podle ověřeného Connect modelu. Zachovej bankovní cestu.

Po zadání tohoto promptu realizuj vlny 0-5 a připrav podklady pro vlnu 6. Nekonči u dalšího plánu, backendového prototypu nebo jednoho klienta. Produkční pilot není součástí této implementační autority.

## Postup a externí ověření

Začni konkrétními návrhy obrazovek a jejich stavů podle vlny 0, pak ověř integrační předpoklady vlny 1 a pokračuj závislými vlnami.

Uživatel má Stripe účet používaný v Mendeliu; ověř jeho dostupné testovací prostředí a Connect nastavení z oprávněně dostupné konfigurace. Existující účet není důkaz sandbox přístupu ani hotového Connect profilu. Festapp testovací objekty a webhooky odděl od Mendelia; jeho endpointy ani živé platby nepřepisuj. Secrets nevypisuj, nekopíruj do repozitáře a nevkládej do snímků.

V testovacím prostředí ověř připojení existujícího účtu včetně Google loginu, finanční model, karetní platbu, 3D Secure, refundaci a návratové cesty. Platforma a připojený pořadatel jsou odlišné role. Google login řeší Stripe. Nepřepni potichu na jiný typ účtu, vytvoření nového klientského účtu nebo příjem peněz účtem Festapp.

Při chybějícím přístupu dokonči vše nezávislé na této překážce a připrav provider fixtures a testy. Neprováděj neověřenou integrační volbu, nepovažuj mock za sandbox důkaz a neoznač celou integraci za hotovou. Uveď přesný blokátor a potřebný další krok.

## Neporušitelné kontrakty

- Jedna SQL autorita pro objednávky, kapacitu, platby a doménové stavy; zachovat receipted příkazy a Client Sync. Provider pohyby nejsou falešné bankovní transakce. Společný přepočet zachová ruční/externí úhrady i celkové a denní reporty. Žádné persistentní aplikační triggery nebo druhý platební engine.
- `order_view` zůstává pouze čtecí. `order_pay`, handoff a návratový read handle mají oddělené scope. Cenu, měnu, příjemce a dovolené akce určuje server. Nová `payment_method` nemění význam `payment_type` (záloha/celá částka).
- Jeden aktivní pokus, stabilní idempotence pro timeout/replay/dvě záložky. Podpis webhooku ověř nad původními byty; ověř účet, tenant, prostředí a atomický SQL výsledek. Návratová URL není potvrzení zaplacení. Pozdní platba automaticky neobnoví uvolněnou kapacitu.
- Všechny emaily přes současnou frontu. Odděl stav platby, vstupenek a emailu. Refundace/spor po enqueue musí ovlivnit i send-time eligibility.
- Částečná refundace sama nezneplatní skupinu. Pořadatel auditovaně určí konkrétní vstupenky nebo vrácení části ceny bez zrušení vstupenek. Navrženou 30minutovou rezervaci a politiku sporů ověř a zachovej jako výslovné produktové předpoklady před pilotem.
- Pilot vyžaduje online validaci Stripe vstupenek na všech přijímacích cestách; zachovej bankovní offline režim. Nepředstírej okamžité odvolání odpojeného skeneru. Nepodporované kombinace MVP vynucuj serverově a vysvětli v UI.

## UI/UX a ověření

Použij existující design tokeny, komponenty, dialogy, drafty a Save/Discard. Implementuj oba klienty a všechny stavové matice, nejen úspěšný nákup. Zachovej vyplněná data, kontext pořadatele, stejnou objednávku po přerušení a přesné ceny. Rozliš připojení, přijímání plateb a výplaty. Iframe nesmí navigovat parent ani přenášet citlivá data/platební stav embed protokolem. Native používá systémový prohlížeč a bezpečný návrat/resume.

Ověř skutečné rozhraní na mobilu/desktopu, klávesnicí, s velkým textem, dlouhými překlady a tenant light/dark tématem. Použij relevantní UI/UX skills a izolovanou headless browser session podle pravidel repozitáře. Statický návrh není důkaz fungujícího UI. Neověřený native/iframe/CMS neoznač za podporovaný.

Testy vybírej podle vlastnící vrstvy A01-A25: SQL pro autoritu/souběh, Deno pro provider hranice, UI pro zobrazení/focus, sandbox pro skutečný handoff. Ověř počet vybraných SQL testů. Flutter nejvýše jeden proces na workstation; před spuštěním ověř volný slot, testy s `--concurrency=1`. JavaScript přes pnpm 11.24.0. Již prošlé kontroly neopakuj bez změny dotčeného kódu. Nezahajuj nezávislý agentní audit.

Vyvrátí-li nové důkazy předpoklad, aktualizuj autoritativní plán a dotčenou vlnu. Nepřidávej placeholdery, neplánované fallbacky nebo paralelní kompatibilní cesty. Neměň potichu vlastnictví peněz ani klientovu samoobsluhu. Běžné implementační a UI volby řeš autonomně; neptej se opakovaně na již zadaný rozsah.

## Dokončení a předání

Předej implementaci v rozsahu 0-5, cílené výsledky A01-A25 a aktualizované provozní/integrátorské dokumenty. Přiznej konkrétní neověřené scénáře. Připrav vypínač nových plateb, recovery a rollback zachovávající rozpracované platby i historii.

Bez dalšího zadání neprováděj produkční migrace, deploy, commit/push, živé platby/refundace ani zásahy do klientských produkčních Stripe účtů. Pro pilot připrav konkrétní rozsah, migrace, konfiguraci a kontrolní kroky. Později autorizované nasazení zachová místní build, přímý deploy na jediného vybraného tenanta a delegaci podle AGENTS.md.

V závěru odděl: implementováno, ověřeno lokálně, skutečně ověřeno v sandboxu a zbývající kroky před produkcí. Lokální implementace není hotové nasazení nebo pilot.
