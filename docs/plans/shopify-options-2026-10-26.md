# Shopify: možnosti doplňku vstupenky.online

> Odloženo na výslovné přání vlastníka: jednorázový poplatek 19 USD je nyní příliš vysoký. Nezakládat registraci, neplatit poplatek a nezahajovat implementaci Shopify, dokud vlastník práci znovu neotevře. Podklady zůstávají pro pozdější návrat.

Průzkum k 26. 10. 2026. Žádná aplikace není založená, odeslaná ani schválená v rámci této práce; žádný poplatek nebyl přijat. Zkoumali jsme veřejnou dokumentaci a katalog, nikoli funkčnost vlastního prototypu.

## Závěr pro rozhodnutí

Shopify je vhodné pro stejný produktový model jako zamýšlený Shoptet konektor: obchod vede košík a platbu, Festapp akci, rezervace, QR/PDF a odbavení. Technickou možnost dokládají existující aplikace, podporu našeho konkrétního řešení je nutné ověřit. Hotový Shoptet doplněk nepůjde jen nahrát do Shopify; sdílet lze backend vstupenek a část webového výběru míst, každá platforma má vlastní instalaci a checkout rozhraní.

## Co už existuje

[Evey Events & Tickets](https://apps.shopify.com/event-tickets) nabízí prodej vstupenek, jejich doručení a QR odbavení. Dokládá, že tento typ služby má v katalogu místo. Jeho vnitřní řešení rezervací, sdílení kapacity ani testy jsme neověřovali; existenci konkurence nelze zaměnit za hotové napojení našeho systému.

## Cena pro nás a zákazníka

[Oficiální registrace a revenue share](https://shopify.dev/docs/apps/launch/distribution/revenue-share): pro vstup do App Storu jednorázově 19 USD za partnerský účet. Standardní režim má 0 % z prvního 1 milionu USD kumulativního hrubého příjmu z aplikací, potom 15 %; započítávají se příjmy od 1. 1. 2025, související účty a zvláštní pravidla velkých vývojářů. Není to každoroční obnovení limitu. Účtování aplikace podléhá 2,9% processing fee a případným daním/dalším regionálním poplatkům. Tyto sazby nejsou automaticky procenta z nominální ceny vstupenek ani sazby platební brány obchodníka.

[Shopify App Pricing](https://shopify.dev/docs/apps/launch/billing) je výchozí pro nové veřejné aplikace a podporuje i účtování podle využití. Konkrétní servisní poplatek za vstupenku musíme popsat, sladit s jejich billingem a ověřit při review; nepřevzít externí fakturaci našeho současného modelu jako automaticky povolenou. Výjimky a nepodporované modely vyřešit podle aktuálních podmínek, ne obcházením billingu.

Vývojové prostředí a [testování app billing plánů](https://shopify.dev/changelog/posts/app-pricing-more-plans-no-charge-plan-testing-and-negative-and-fractional-app-events) umožňují přípravu bez reálných app charges. Nemusíme začít placeným obchodním tarifem. Registraci k publikaci a jakýkoliv nákup řešit až podle konkrétního schváleného kroku.

## Navržené rozdělení práce

| Část | Společná pro oba kanály | Shopify adaptér |
| --- | --- | --- |
| Akce a nabídka | Existující Festapp konfigurace | Vazba na Shopify produkt/variantu |
| Kapacita a místa | Kanonické SQL alokace a stav rezervace | Dohodnutý přenos do košíku a kontrola checkoutu |
| Objednávka a úhrada | Privilegovaný import, deduplikace, finanční projekce | Shopify identity, webhooky, měny, slevy a refundace |
| Vstupenky a vstup | Stávající QR/PDF, e-mailová fronta a scanner | Předání potřebných kontaktů a údajů položky |
| Správa a instalace | Naše akce zůstává u nás | OAuth/session tokens, admin UI, theme app extension, billing |
| Vydání | Obvyklé interní kontroly | Samostatné Shopify review a App Store listing |

Společné rozhraní zatím není implementované ani pro Shoptet. Nejprve ověřit jeden skutečný kontrakt a ponechat platformní odlišnosti v adaptérech; nedělat předem obecný framework pro hypotetické kanály. Současné finanční omezení bank/Stripe popisuje [technická příloha Shoptetu](shoptet-partner-technical-2026-10-26.md); Shopify potřebuje stejnou důvěryhodnou hranici pro externí objednávky, ne přímý anonymní zápis zaplaceno.

## Podstatné požadavky Shopify

- [App Store requirements](https://shopify.dev/docs/apps/launch/shopify-app-store/app-store-requirements) vyžadují vlastní Shopify checkout. Obalení našeho současného placení do iframe nepředstavuje vhodný katalogový doplněk. Nevyvíjíme platební bránu.
- [Theme app extensions](https://shopify.dev/docs/apps/build/online-store/theme-app-extensions) umožní webový výběr a propojení s produktem na podporované šabloně. Kupující nepotřebuje Flutter aplikaci; existující webový výběr lze adaptovat bez našeho platebního kroku. Přesnou kompatibilitu šablon je nutné ověřit.
- [Cart and Checkout Validation](https://shopify.dev/docs/api/functions/latest/cart-and-checkout-validation) je serverová validační hranice včetně expresních checkoutů. Není tím slíbené volání na náš backend. [Network access pro Functions](https://shopify.dev/docs/apps/build/functions/network-access) má vlastní omezení: pro validační funkci aktuálně Shopify for enterprises s custom aplikacemi. Veřejnou appku pro běžné tarify proto nelze navrhnout s automatickým předpokladem externího API dotazu při každé platbě. Nezaměňovat dostupnost samotné funkce a dostupnost sítě.
- Pro posílání vstupenek na email kupujícího bude potřeba [protected customer data](https://shopify.dev/docs/apps/launch/protected-customer-data): oprávnění a posouzení příslušných polí pro veřejnou aplikaci. Oprávnění k orders samo o sobě neznamená automatický přístup k emailu. Doplnit povinné privacy webhooky a proces výmazu/odpojení podle skutečné integrace.

## Co ověřit jako první

1. Účet/registraci ověřit v Dev/Partner Dashboard; v prohledané poště jsme nenašli relevantní potvrzení, není to důkaz neexistence účtu. Nezakládat duplicitní placenou registraci.
2. Na běžném cílovém tarifu v izolovaném dev store prokázat vazbu posledního místa na nativní košík, objednávku a úhradu. Test musí zahrnout Shop Pay/express cestu, přímý odkaz na produkt, množství, opuštěný košík a souběh prodeje u nás. Výsledek neodvozovat pouze z toho, že konkurence appku má.
3. Pokud nepůjde synchronně ověřit naši rezervaci, posoudit serverově vynucený příděl kapacity pro kanál, jehož alokace zůstává v naší SQL autoritě. Ověřit nativní sklad, zakázaný overselling, expresní/admin/API cesty a bezpečné uvolnění přídělu. Generická synchronizace dvou skladových čísel není garance a úspěch obecné kapacity neprokazuje výběr konkrétních míst.
4. Potvrdit konkrétní model app billingu, potřebné customer-data scopes a lifecycle instalace/uninstall. Pak navrhnout malý pilot a implementaci; bez úspěšného kapacitního důkazu nepřijímat peníze za nealokované vstupenky.

Odhad sdílení je architektonický závěr, ne měřená úspora. Shopify ani Shoptet nemají v tuto chvíli náš hotový konektor. Jednorázových 19 USD bylo pouze zjištěno, nikoli zaplaceno. Nebyla odeslána žádost ani vyvíjen nový kód.
