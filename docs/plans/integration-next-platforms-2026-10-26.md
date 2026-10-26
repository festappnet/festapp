# Další platformy po odložení Shopify

26. 10. 2026. Shopify je na přání vlastníka odložené kvůli jednorázovému poplatku. Toto je doporučení z veřejných zdrojů, nikoli schválený vývoj, registrace nebo odeslaná žádost.

## Doporučené pořadí

1. **Upgates jako další nová platforma.** Má české partnerské prostředí a marketplace; obchodní rámec podle aktuálních podmínek dobře odpovídá externí službě vstupenky.online.
2. **WooCommerce jako rozšíření WordPressu.** Má smysl pro pořadatele, kteří chtějí vstupenky prodávat přes existující Woo košík a platební metody. Je to jiný rozsah než naše současné vložení formuláře do stránky.

Nejde o závěr z měřené poptávky pořadatelů. Před vývojem vybrat skutečného zájemce/pilot a ověřit kapacitu; nevydávat existenci marketplace za potvrzený prodejní kanál pro naši aplikaci.

## Upgates

Důležité: výsledky hledání vracejí i původní podmínky platné jen do 13. 8. 2026. Pro toto rozhodnutí byly ověřeny aktuální stránky účinné od 14. 8. 2026:

- [Obecné podmínky, čl. 5.7](https://www.upgates.cz/obchodni-podminky-pro-partnery-1): založení partnerského účtu, profil a zveřejnění nabídky jsou bezplatné.
- [Podmínky doplňků, čl. 6.2-6.4](https://www.upgates.cz/obchodni-podminky-pro-vyvoj-a-nabidku-doplnku-1): standardně se neplatí za zveřejnění/distribuci doplňku ani provize; odlišná písemná dohoda a změny podle obecných podmínek jsou možné. Navazující placená služba a přímý smluvní/platební vztah s jejím zákazníkem jsou popsané výslovně.
- Zákazník může platit Upgates za API nebo systémové limity; nelze to prezentovat jako cenu pro vydavatele doplňku ani slibovat zákazníkovi vše zdarma.
- [Postup vytvoření doplňku](https://www.upgates.cz/a/vytvareni-doplnku) vede přes partner účet, registraci záměru, testovací projekt a technickou konzultaci.

Další krok: zjistit existující účet/komunikaci, připravit stručný návrh a projednat, zda je vhodnější vložení našeho prodeje, nebo nativní košík. Z podmínek účtování služby neplyne automatické schválení externího checkoutu. Případný nativní prodej vyžaduje vlastní ověření rezervace, úhrad, změn objednávky a společné kapacity jako u Shoptetu. Nic zatím nebylo registrováno ani odesláno.

## WooCommerce

[WooCommerce core je bezplatný plugin](https://woocommerce.com/document/frequently-asked-questions/). Konektor lze vyvíjet a distribuovat přímo jako WordPress ZIP bez registrace do WooCommerce.com Marketplace; případné vydání na WordPress.org nadále podléhá jeho samostatné kontrole. Současné podání našeho WordPress pluginu se tím nemění.

[Oficiální Woo Marketplace](https://developer.woocommerce.com/docs/woo-marketplace/getting-started/) je další distribuční cesta se schvalováním a rozdělením prodejního příjmu 70 % vydavatel / 30 % Woo. Nelze tento podíl automaticky vztáhnout na nominální cenu každé prodané vstupenky nebo předem slíbit přijetí SaaS modelu. Je třeba rozlišovat přímé šíření pluginu a smlouvu pro Woo Marketplace.

Technicky lze doplnit Woo lifecycle pro košík, objednávku, úhradu, storno a refundaci; přesné podporované verze/classic a blocks checkout se musí prozkoumat. Existence podobných [ticketingových pluginů](https://wordpress.org/plugins/abp-event-ticket/) dokládá produktový model, nikoli interní bezpečnost jejich rezervací. Náš původní plugin pouze vkládá veřejný formulář, tudíž nativní Woo prodej není hotový a nepůjde jen zapnout přepínačem.

Další krok: ověřit zájem pořadatele s WooCommerce a navrhnout malý pilot. Ponechat naše kanonické SQL, vstupenky, e-mailovou frontu a scanner; přidat platformní adaptér. Nezakládat druhou nezávislou kapacitu ve Woo a netvrdit, že PHP hook sám tvoří transakci se vzdálenou databází.
