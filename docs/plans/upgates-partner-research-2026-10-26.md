# Upgates: průzkum partnerství a prodeje vstupenek

26. 10. 2026 · Pouze průzkum a návrh dalšího postupu · Ověřování: standard

## Doporučení

**Má smysl pokračovat k úvodní konzultaci o ověřeném doplňku.** Základní obchodní podmínky odpovídají našemu rozpočtu i placené navazující službě. Doplněk však není hotový a nativní prodej míst přes Upgates zatím není prokázaný. Před implementací vybrat s jejich vývojářem konkrétní způsob rezervace a platby. Samotné čtení objednávek po zaplacení nezajistí, že poslední místo neprodáme dvakrát.

Dosavadní checkouty se nemění. Kapacitu, QR/PDF, frontu e-mailů a odbavení nadále vlastní současné moduly Festappu; nový nativní prodej využije checkout Upgates. Adaptér do e-shopu nebude obsahovat Flutter. Sdílení se Shoptetem znamená společné doménové kontrakty, ne přenesení hotového pluginu; ani Shoptet konektor zatím implementovaný nemáme.

## 1. Náklady podle aktuálních podmínek

Vyhledávače nabízejí i již neplatnou verzi podmínek. Z rozcestníku jsme otevřeli aktuální dokumenty účinné od 14. 8. 2026, s příponou `-1` v URL.

| Oblast | Zjištění | Zdroj |
| --- | --- | --- |
| Partnerský účet, profil, nabídka | Bezplatné. | [Obecné podmínky 5.7](https://www.upgates.cz/obchodni-podminky-pro-partnery-1) |
| Zveřejnění a distribuce doplňku | Standardně bez poplatku a provize. Možná je jiná písemná dohoda nebo pozdější změna podle obecných podmínek; nejde o trvalou garanci. | [Podmínky doplňků 6.4](https://www.upgates.cz/obchodni-podminky-pro-vyvoj-a-nabidku-doplnku-1) |
| Naše placená služba | Lze ji nabízet a účtovat přímo zákazníkovi při jasném uvedení ceny a poskytovatele. To samo nepotvrzuje externí ticketing checkout. | Stejný dokument 6.2-6.3 |
| API zákazníka | Obecný přístup a dodatečné limity mohou být placené. Dokumentace rozlišuje ověřené doplňky pro všechny klienty, pro které se běžné zpoplatnění a request limity neuplatňují. | [Rate limiting](https://docs.upgates.com/api/rate-limiting) |

Před potvrzením konkrétní nabídky ověřit zařazení našeho konektoru a rozpočet přístupů. Neprodávat zákazníkům placené obecné API, pokud máme být ověřený partnerský doplněk. Podmínky účtování naší služby, ceny vstupenky a platformních prostředků nejsou jedna a tatáž platba. Žádná platba ani registrace během průzkumu neproběhla.

## 2. Registrace a schválení

[Partnerský postup](https://www.upgates.cz/a/vytvoreni-partnerskeho-uctu) a [založení doplňku](https://www.upgates.cz/a/vytvareni-doplnku) vedou přes Marketplace účet a profil firmy, návrh názvu/popisu a vybraný testovací e-shop. Kategorie obecné nabídky agentury není sama technickým doplňkem.

Na skutečné registrační stránce `https://marketplace.upgates.com/admin/sign/up` jsme bez vyplnění ověřili pole: firma, e-mail, telefon, země, město, heslo a jeho opakování, souhlas s podmínkami. Veřejný průvodce následně požaduje doplnění profilu a IČO. Přesný právní subjekt a údaje nesmíme hádat. V připojené poště není nalezená komunikace s doménami Upgates; účet přes jiný e-mail nebo kanál tím vyloučený není.

[Úvodní konzultace](https://www.upgates.cz/a/uvodni-konzultace) je povinná před vývojem/editací doplňku. Připravit záměr, vstup a návrat zákazníka, data a oprávnění, více e-shopů na jeden e-mail a případné iframe rozhraní. S Upgates určit další postup a testovací projekt. Prodloužení demo projektu je možné řešit s jejich týmem, ne kupovat tarif bez potřeby.

Pro finální schválení potřebujeme skutečný instalační a odinstalační průchod, popis služby a ceny, návod, testovací přístupy a důkazy proti přesnému kandidátovi. Neověřený doplněk a ověřený partnerský doplněk mají jiný přístupový/obchodní kontext; cílem navrhovaného postupu je ověřená integrace.

## 3. Co jsme našli v katalogu

V izolovaném headless prohlížeči jsme hledali `vstupenky`, `ticket`, `rezervační` a `rezervace`. První tři dotazy v zobrazeném výsledku neměly položku. Poslední vrátil skladové/expediční integrace (např. DEPOTO WMS), nikoli srovnatelný doplněk s plánem sálu a QR odbavením.

To je omezený výsledek vyhledávání, nikoli důkaz absence konkurence nebo poptávky. Nepřenášíme existenci rezervačního doplňku ze Shoptetu na Upgates a nemáme zatím přímého Upgates pořadatele pro pilot.

## 4. Aktuální API: co lze doložit

Původní Apiary stránka v načteném prohlížeči výslovně odkazuje na novou dokumentaci `https://docs.upgates.com/`. Řídit se touto dokumentací; starší FAQ např. nepopisují dnešní dostupnost vytváření produktů.

| Potřeba | Doložená veřejná dokumentace | Omezení závěru |
| --- | --- | --- |
| Připojit konkrétní e-shop | REST API v2, HTTP Basic, individuální oprávnění; per-shop URL předaná instalací. | Není to Shoptet/Shopify OAuth. Ověřit instalační identitu před použitím předaných secrets/URL. [Základ](https://docs.upgates.com/api/intro) |
| Propojit produkt nebo variantu | `GET`, `POST`, `PUT` produktů; identita code. | Přístup k metodám musí odpovídat schválenému účelu. První pilot může mapovat existující produkt bez obecného zápisu celého katalogu. [Produkty](https://docs.upgates.com/api-reference/produkty) |
| Sledovat košík | Veřejně popsané `GET /api/v2/carts` a `GET /api/v2/carts/{id}`. | V tomto přehledu není serverový validační háček ani zápis do košíku. Nevyvozovat z existence čtení možnost závazně blokovat checkout. [Košíky](https://docs.upgates.com/api-reference/kosiky) |
| Převzít objednávku | Detail a seznam `/api/v2/orders`, filtry podle změny/úhrady, `order_number` jako identita. | Obsahuje směs zboží a vstupenek; položky a jejich identitu je nutné bezpečně mapovat. [Objednávky](https://docs.upgates.com/api-reference/objednavky) |
| Zjistit zaplacení | Objednávková data obsahují informace o úhradě včetně `paid_date`. | Konkrétní autoritu úplné úhrady, částečných plateb a refundací potvrdit. `/payments` popisuje platební metody s typem, popisem a cenou, nikoli bankovní/karetní účetní pohyby. [Platby](https://docs.upgates.com/api-reference/platby) |
| Průběžné změny | `Orders.create/update` a další webhooky. | Notifikace jsou podnět k API čtení, ne hotová účetní transakce. `Payments.create/update` není samo potvrzení nákupu. [Události objednávek](https://docs.upgates.com/webhooks/orders), [události plateb](https://docs.upgates.com/webhooks/payments) |

Ukázky API nejsou záznamy našeho ověřeného e-shopu. Na žádný autentizovaný endpoint ani zákaznická data jsme nesahali.

## 5. Instalace, podpisy a výpadky

[Instalace](https://www.upgates.cz/a/api-dokumentace-aktivace-doplnku) předává token, verzi, apiUser/apiKey/apiUrl, jazyk, čas a `signature_v2`. Má vlastní limit 5 sekund a strukturovanou odpověď HTTP 200 s `error`. Podepisují se předepsaná pole; ověření používá veřejný klíč a SHA-256 podle platformního návodu. Nebrat bez ověření jako kopii Shoptet HMAC. Přihlášení administrátora do našeho účtu a oprávnění dané akce jsou další kontroly, ne důsledek znalosti e-mailu obchodu.

Návrhová bezpečnostní pravidla: před použitím credentials ověřit podpis a čas, endpoint omezit na doložený HTTPS host/path e-shopu, neprovádět libovolné requesty podle `apiUrl`. Přesunutí serveru API může vracet 301; před změnou cíle validovat novou adresu a neodeslat Basic credentials neověřenému hostu. Jedna e-mailová adresa není identita e-shopu. Přeinstalace může změnit oprávnění/credentials, obchodní deduplikační klíče starých objednávek musejí zůstat.

[Deaktivace](https://www.upgates.cz/a/api-dokumentace-deaktivace-doplnku) se v Upgates provede bez ohledu na odpověď našeho endpointu a odstraňuje API přístupy. Po odpojení proto nelze slíbit další automatickou synchronizaci. Vydané vstupenky zachovat, dotčený prodej zastavit a rozpracované případy řešit posledním ověřeným stavem nebo doloženou ruční opravou; nové refundace bez API nelze automaticky zjistit.

[Iframe průvodce](https://www.upgates.cz/a/doplnky-iframe) pojednává o aktivaci a administraci doplňku. Není důkazem, že stejným způsobem smíme vložit veřejný nákupní formulář a externí checkout. Požadovanou podobu admin rozhraní dohodnout na konzultaci; opakované nastavování celé akce v obou aplikacích není cílem.

### Důležitá vlastnost webhooků

[Aktuální dokumentace](https://docs.upgates.com/webhooks/intro) rozlišuje 1 sekundu na navázání a 3 sekundy na celkové vyřízení. Chybná odpověď vyvolá opakování po 5 minutách, ale překročení celkového timeoutu může být považováno za doručení bez dalšího pokusu. Ani evidovaný úspěšný stav na straně Upgates tím nedokazuje commit u nás.

Návrh: rychle uložit přijatý podnět do trvalého inboxu, potvrdit 200/204 a zpracovat mimo request. Doplnit omezené stahování změn z API s kurzorem, časovým přesahem, deduplikací a opravnou frontou. Zvládnout dávku více entit. Autentizaci obyčejných datových webhooků potvrdit samostatně; nepředpokládat, že mají stejný podpis jako instalační callback. Do té doby je brát jen jako omezený podnět ke čtení ověřeného e-shopu přes uložený API přístup, nikdy jako přímý příkaz „zaplaceno“.

## 6. Který produktový model zvolit

| Varianta | Co dostane kupující | Rozsah práce a otevřená otázka |
| --- | --- | --- |
| Vložení formuláře | Existující veřejný prodej v naší službě, zobrazený na webu. | Nejvíc využije dnešní web client. Přijatelnost do katalogu a veřejné vložení/checkout musí potvrdit Upgates; admin iframe návod to sám nepotvrzuje. |
| Nativní košík | Vstupenka je produkt Upgates, platba a objednávka projdou e-shopem. | Nový adaptér pro rezervaci, finance a objednávkový lifecycle. Stejný navržený směr jako Shoptet, ale jiné platformní API a garance. |

Doporučení pro konzultaci: představit nativní prodej jako zamýšlený cíl a požádat o doporučený kontrakt. Zjistit i přípustnost jednoduššího vložení, bez předstírání hotového řešení. Po konzultaci vybrat jednu variantu první verze, nevyvíjet obě najednou.

Pro nativní cestu potřebujeme buď doloženou kontrolu rezervace před přijetím objednávky, nebo skutečně bezpečný, naším SQL evidovaný příděl kapacity pro kanál. [Běžný objednávkový proces](https://www.upgates.cz/a/objednavkovy-proces-1) umí omezování podle skladu, ale z textu neplyne atomická spolupráce s naší databází. Přímý nákup u nás, obnova košíku, admin/API objednávka i změna množství nesmějí obejít společný limit. První pilot jedna akce a CZK; prodej míst zapnout až po samostatném důkazu rezervace.

## 7. Co by se měnilo u nás

Navázat na [Shoptet technický návrh](shoptet-partner-technical-2026-10-26.md), ne na dosud neexistující implementaci. Konkrétní opěrné body: `database/functions/eshop/select_spot.sql`, `database/functions/eshop/finalize_ticket_order.sql`, `database/functions/eshop_orders/create_ticket_order_client_sync_v1.sql`, `database/functions/eshop_transactions/payment_totals.sql` a `supabase/functions/send-ticket-order/`.

Pro nativní prodej přidat privilegovanou vazbu na externí obchod/objednávku/položku, neměnný snapshot ceny a zdroj úhrady do stávající finanční projekce. Současný finalizer bank/Stripe není hotový univerzální import. Veřejný prohlížeč nesmí dodat důvěryhodné „zaplaceno“. Nebude druhá tabulka vstupenek, paralelní kapacita, samostatný renderer PDF ani jiný odesílač e-mailů. Dvojí potvrzení o nákupu nesmí vyvolat dvojí vstupenku nebo druhou platební výzvu.

Před odhadem ceny práce vyřešit: více akcí v košíku, neměnné identity položek, slevy/DPH/refundy, dlouhé neuhrazené objednávky a rozdělení odpovědnosti za doklady. Bez těchto rozhodnutí není poctivé tvrdit, že jde jen o převzetí WordPress iframe.

## 8. Přesný další postup a rozhodovací body

1. **Účet a záměr.** Ověřit existující partner účet, právní subjekt a kontakty. Schváleným kanálem jednou požádat o konzultaci. Výstup: skutečné potvrzení, žádné duplicitní podání. Návrh textu je v samostatném souboru; zatím není odeslaný.
2. **Domluvený kontrakt.** S vývojářem Upgates projít níže uvedené otázky a vybrat jednu variantu. Výstup: konkrétní potřebná oprávnění, rozdělení plateb, kapacita a testovací prostředí; nikoli marketingové „jde to“.
3. **Ověření v demu.** Teprve po přístupech vlastní izolovaný e-shop a lokální Festapp tenant, syntetické objednávky bez reálné úhrady a emailový sink. Dokázat poslední místo při souběhu, expiraci/pozdní platbu, změnu objednávky, opakovaný webhook, timeout, odpojení a reinstalaci. Pro nativní cestu rozhodovací brána i pro obyčejnou kapacitu, nejen mapu sálu.
4. **Implementace.** Až po rozhodnutí založit `integrations/upgates/`; adapter, návody a jeho důkazy mají jedno místo. SQL/Edge změny přes existující kanonické vrstvy a explicitní migrace. Není schválen zásah do produkce ani placený provoz.
5. **Pilot a zveřejnění.** Jeden dohodnutý pořadatel a akce; skutečný instalační test, návod a technické schválení Upgates. Hotovo znamená i anonymně dostupný záznam v katalogu a ověřený prodej, ne pouze vytvořený partner účet.

### Otázky pro jejich tým

- Je doporučená cesta nativní produkt/košík, případně je přijatelný i externí ticketing formulář? Kam smí doplněk zasahovat do storefrontu?
- Existuje serverová kontrola rezervace před přijetím objednávky, která platí i pro admin/API a změny množství? Pokud ne, jak bezpečně vyhradit kapacitu kanálu?
- Jaký údaj dokládá úplnou úhradu, částečnou platbu a refundaci položky, a jak se změny doručují? Nejde o číselník `/payments`.
- Jak předat a uchovat identitu vybraných míst/naší rezervace v položce při změně či sloučení košíku? Jak stabilní jsou item ID?
- Jak se ověřují běžné datové webhooky a jaké jsou aktuální callback/retry/limitní kontrakty pro ověřený doplněk?
- Potvrdíte partnerský API režim, případné náklady, rozsah endpointů a možnost dlouhodobého testování bez nákupu tarifu?

## Co je a není hotové

Ověřeny veřejné podmínky, dokumentace a registrační formulář; vyzkoušeno veřejné vyhledávání v katalogu. Prozkoumané zdroje a meze průzkumu zaznamenává [evidence](upgates-research-evidence-2026-10-26.json). Nebyla vyplněna registrace, přijata smlouva, odeslána zpráva, vytvořen doplněk ani proveden autentizovaný API/prodejní test. Neproběhla nezávislá kritika ani testy aplikace, protože se zatím pouze zkoumaly možnosti.

[Návrh úvodní zprávy](upgates-partner-proposal-2026-10-26.md) · [Zadání pro další session](upgates-partner-EXECUTION-PROMPT-2026-10-26.md).
