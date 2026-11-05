# Datová vrstva veřejného formuláře

Kontrakt vychází z celého dokumentu
[Doporučená datová vrstva](https://frantisekbujnovsky.com/docs/gtm/datalayer/),
čteného ze zdrojového `src/content/docs/docs/gtm/datalayer.md`.
Níže uvedená schválená rozhodnutí upřesňují ceny, sadu událostí a kontaktní údaje.
Používá se pouze dataLayer s `ecommerce`, nikdy současně `gtag('event', …)`.

Schválený funnel je `view_item` → `add_to_cart` → `begin_checkout` →
`add_payment_info` → `purchase`. Dále existují `page_view`, `remove_from_cart`,
`generate_lead` a `form_submit_error`. Každý ecommerce event má `currency`,
`value` a `items`; každá položka má `item_id`, `item_name`, `price`, `quantity`.
`item_name` je veřejný název nabídky produktu nebo vstupenky, nikdy popisek sedadla
ani hodnota odpovědi návštěvníka. `product_123` je ID katalogového produktu.
Seznam má nejvýše 200 položek. Prázdné údaje se vynechávají.

**Ceny jsou konečné částky účtované kupujícímu, včetně případné DPH.**
`eshop.products.price` se v checkoutu sčítá do `orders.price` a
`payment_info.amount`. Backend nemá rozpis DPH, proto se `tax` neposílá.
Na rozdíl od obecného doporučení nejde o tržby bez DPH. `price` a `value` jsou
čísla na dvě desetinná místa, `value = Σ(price × quantity)`. Měny se nemíchají.
Nulová cena je platná. Není zaveden odhad výnosu leadu, doprava ani další slevy.

Košík je klientský výběr. Běžná volba produktu se měří po změně tohoto výběru;
kapacitní rezervace až po dokončení serverové operace. Pozorování analytikou
nespouští obnovu ani další rezervaci. U změny množství se posílá jen přírůstek
nebo úbytek. U sedadel se měří jejich katalogový produkt, žádné údaje o sedadle.

## Inicializace a základní vrstva

Kdy: po načtení veřejného formuláře před GTM; znovu při rekapitulaci a potvrzení
backendem. `user_type` označuje maloobchodní kanál, nikoli daňový status osoby.

```js
window.dataLayer = window.dataLayer || [];
window.dataLayer.push({
  page_type: 'product', // dále 'checkout' a 'confirmation'
  language: 'cs',      // pokud je jazyk rozhraní známý
  user_type: 'b2c'     // veřejný maloobchodní kanál
});
```

## page_view

Kdy: bezprostředně po každé základní vrstvě, také při změně kroku bez nové URL.
V GTM/GA4 nepřidávejte další automatický page view pro tentýž krok.

```js
window.dataLayer.push({
  event: 'page_view' // žádná URL, fragment, odpověď ani osobní údaj
});
```

## view_item

Kdy: při zobrazení formuláře s jeho nabídkou, jednou pro aktuální měnu nabídky.

```js
window.dataLayer.push({ ecommerce: null, user_data: null }); // vyčistit předchozí stav
window.dataLayer.push({
  event: 'view_item',
  ecommerce: {
    currency: 'CZK',
    value: 450, // konečná cena × jedna nabízená jednotka
    items: [{ item_id: 'product_11', item_name: 'Vstupenka na letní koncert', price: 450, quantity: 1 }]
  }
});
```

## add_to_cart

Kdy: po přidání do košíku; kapacitní rezervace až po potvrzení serverem.
Opakované oznámení stejného stavu další event nevytvoří.

```js
window.dataLayer.push({ ecommerce: null, user_data: null }); // neslučovat košíky
window.dataLayer.push({
  event: 'add_to_cart',
  ecommerce: {
    currency: 'CZK',
    value: 900, // 450 × 2, včetně případné DPH
    items: [{ item_id: 'product_11', item_name: 'Vstupenka na letní koncert', price: 450, quantity: 2 }] // přírůstek
  }
});
```

## remove_from_cart

Kdy: po odebrání z košíku a dokončení případného uvolnění rezervace. Také při
změně měny, která odstraňuje původní výběr.

```js
window.dataLayer.push({ ecommerce: null, user_data: null }); // vlastní odebrané položky
window.dataLayer.push({
  event: 'remove_from_cart',
  ecommerce: {
    currency: 'CZK',
    value: 450,
    items: [{ item_id: 'product_11', item_name: 'Vstupenka na letní koncert', price: 450, quantity: 1 }] // úbytek
  }
});
```

## begin_checkout

Kdy: otevření rekapitulace, po základní vrstvě `checkout` a jejím `page_view`.
Zavření a nové otevření znamená nový vstup do tohoto kroku.

```js
window.dataLayer.push({ ecommerce: null, user_data: null }); // celý aktuální výběr
window.dataLayer.push({
  event: 'begin_checkout',
  ecommerce: {
    currency: 'CZK',
    value: 900,
    items: [{ item_id: 'product_11', item_name: 'Vstupenka na letní koncert', price: 450, quantity: 2 }]
  }
});
```

## add_payment_info

Kdy: návštěvník potvrdí rekapitulaci a způsob platby, před odesláním objednávky.
Nejde o přijetí objednávky ani o potvrzení úhrady.

```js
window.dataLayer.push({ ecommerce: null, user_data: null }); // nepřebírat starý způsob platby
window.dataLayer.push({
  event: 'add_payment_info',
  ecommerce: {
    currency: 'CZK',
    value: 900,
    payment_type: 'bank_transfer', // 'card' pro Stripe, 'free' pro nulový košík
    items: [{ item_id: 'product_11', item_name: 'Vstupenka na letní koncert', price: 450, quantity: 2 }]
  }
});
```

## purchase

Kdy: backend potvrdil přijetí nové placené objednávky. **Bankovní převod znamená
přijatou objednávku, nikoli úhradu.** I u karty tento event označuje přijetí
objednávky, vlastní úhrada probíhá v odděleném platebním toku.

```js
window.dataLayer.push({ ecommerce: null, user_data: null }); // včetně minulého zákazníka
window.dataLayer.push({
  event: 'purchase',
  ecommerce: {
    transaction_id: '1A2C3E4F5G', // veřejné order_symbol, nikdy interní ID či capability
    currency: 'CZK',
    value: 900, // konečná cena včetně případné DPH; tax se neposílá
    payment_type: 'bank_transfer',
    items: [{ item_id: 'product_11', item_name: 'Vstupenka na letní koncert', price: 450, quantity: 2 }]
  },
  // Celý user_data objekt se přidá pouze při povolených rozšířených konverzích.
  user_data: {
    email: 'jana.novakova@example.com', // normalizováno, nehashováno
    phone_number: '+421905123456',     // skutečná předvolba z vyplněného telefonu
    address: {
      first_name: 'jana', last_name: 'nováková', // bez známých titulů, malá písmena
      postal_code: '602 00', country: 'CZ'      // pouze pokud je formulář sbírá strukturovaně
    }
  }
});
window.dataLayer.push({ user_data: null }); // další event kontakty nezdědí
```

Při vypnutých rozšířených konverzích `user_data` v eventu chybí. Nulovací pushe
neobsahují osobní údaje. Bez bezpečného veřejného `order_symbol` se purchase
vynechá. Formát veřejného čísla ověřuje backend, formulář i host; osobní přístup
vyžaduje samostatný token a samotné číslo jej neuděluje.

Backend vrací projekci produktů pouze v první úspěšné odpovědi anonymního
vytvoření objednávky, po uložení trvalého mutation receiptu **bez analytiky**.
Cena a název pocházejí z katalogu pod checkoutovými zámky ve stejné transakci.
Projekce neobsahuje kontaktní údaje; ty klient případně převezme z odeslaného
formuláře. Replay analytiku znovu nevrátí. Příznak podle veřejného čísla v
localStorage navíc brání opakování callbacku po reloadu. Při nedostupném
úložišti se purchase vynechá. Jde o **nejvýše jednou**, nikoli záruku doručení:
ztracená první odpověď či zavřená stránka mohou konverzi ztratit. Osobní odkazy,
platební návraty, administrátorské objednávky a přijetí nabídky čekací listiny
purchase nevysílají. Úhrady, storna a refundace tento kontrakt neměří.

## generate_lead: bezplatná registrace

Kdy: backend potvrdil registraci s `payment_info.amount === 0`, nikdy při kliknutí.

```js
window.dataLayer.push({ ecommerce: null, user_data: null }); // odstranit předchozí kontext
window.dataLayer.push({
  event: 'generate_lead',
  currency: 'CZK',
  value: 0, // skutečně bezplatná registrace, nikoli odhad výnosu
  lead_source: 'free_registration',
  user_data: { email: 'jana.novakova@example.com' } // pouze při povolených rozšířených konverzích
});
window.dataLayer.push({ user_data: null }); // nezanechat kontakty dalším tagům
```

Parametry leadu jsou stejně jako v referenčním dokumentu na nejvyšší úrovni.

## generate_lead: čekací listina

Kdy: backend potvrdil novou registraci na čekací listinu, před osobním přehledem.
Ne při zobrazení, úpravě osob ani přijetí nabídky.

```js
window.dataLayer.push({ ecommerce: null, user_data: null }); // čekací položky nemají finance
window.dataLayer.push({
  event: 'generate_lead',
  currency: 'CZK', // měna výběru, při její absenci CZK
  value: 0,
  lead_source: 'waitlist',
  user_data: { email: 'jana.novakova@example.com' } // pouze při povolených rozšířených konverzích
});
window.dataLayer.push({ user_data: null });
```

## form_submit_error

Kdy: odmítnutí backendem nebo transportní chyba odeslání. Chyba vykreslení již
přijaté objednávky nevytvoří další analytickou chybu. Klientská validace před
rekapitulací tento event nevytváří.

```js
window.dataLayer.push({
  event: 'form_submit_error' // bez textu chyby, stacku, kontaktů a odpovědí
});
```

## Rozšířené konverze a budoucí consent

Přepínač `analytics.enhanced_conversions` v sekci Měření je **výchozně vypnutý**.
Stejně jako GTM a skripty ho smí měnit pouze příslušný administrátor organizace,
vynucený serverem. Chybějící hodnota neznamená souhlas ani zapnutí. Kontakty se
přidávají jen k `purchase` a `generate_lead`, vedle `ecommerce`.

**Bez vyřešeného consentu přepínač nezapínejte.** Zapnutí předává osobní údaje do
GTM pořadatele nebo hostiteli vloženého formuláře. Dnešní
[`web/privacy/index.html`](../../web/privacy/index.html) uvádí, že se obsah
formulářů do měření neposílá. Před aktivací je nutné upravit text zásad a vyřešit
souhlas. Tento PR text zásad nemění a consent neimplementuje.

Jediné pojmenované místo pro budoucí souhlas je `shouldLoadFormIntegrations`.
Rozhoduje o skriptech i `user_data` (`purpose: 'user_data'`), se společnou
kontrolou veřejného kontextu a session. Budoucí consent se musí doplnit sem.
Samotný přepínač formuláře ani atribut iframe nejsou souhlas návštěvníka.

Klient čte pouze vyplněná hlavní kontaktní pole formuláře, nikoli účastníky
v jednotlivých vstupenkách, obecné odpovědi či poznámky. Whitelist zahrnuje
`email`, `phone_number` a `address.first_name`, `last_name`, `postal_code`,
`country`. E-mail a telefon jsou základní údaje vždy, když je formulář sbírá
a hodnoty projdou validací; zbývající pole jsou volitelná.

E-mail používá existující formulářový `isValidEmail`, bez seznamu domén nebo
koncovek. Oříznou se mezery i neviditelné znaky na okrajích a převede se na malá
písmena. Musí obsahovat právě jedno `@`, platnou doménu s tečkou a žádné vnitřní
mezery či neviditelné znaky. Náhodný text se vynechá. Tečky v Gmailu se nemění.
Telefon normalizuje společný helper `normalizeE164Phone` v existujícím
`phone_formatter.js`; host používá stejnou formátovou validaci. Povoleny jsou
všechny země, žádný seznam zemí se pro analytiku nezavádí. `+`, `00`, mezery,
pomlčky a závorky se převedou do E.164 s 8 až 15 číslicemi, první nesmí být nula.
Přednost má předvolba přímo ve vyplněné hodnotě. Národní číslo může použít jen
skutečně vybranou/výchozí předvolbu uloženou u pole nebo jedinou jednoznačnou
předvolbu konfigurace, nikoli odhad z první položky více možností.
Jména se převedou na malá písmena a odstraní se známé akademické/zdvořilostní
tituly. Prázdné a neplatné údaje se vynechávají, nic se nehashuje.

| Vstup | Kontext | Výstup |
| --- | --- | --- |
| ` Jan.Novak@Seznam.CZ ` | libovolná platná doména | `jan.novak@seznam.cz` |
| `U+200B Jan.Novak@Seznam.CZ U+2060` | neviditelné znaky jen na okrajích | `jan.novak@seznam.cz` |
| `jan@firma.co.uk` | libovolná koncovka | `jan@firma.co.uk` |
| `jan.novak@gmail.com` | tečky se nemažou | `jan.novak@gmail.com` |
| `neni-email` | neplatný e-mail | vynecháno |
| `+420 777 123 456` | předvolba přímo v hodnotě | `+420777123456` |
| `777123456` | skutečná předvolba pole `+420` | `+420777123456` |
| `777123456` | nejednoznačná nebo chybějící předvolba | vynecháno |
| `00420777123456` | mezinárodní zápis s `00` | `+420777123456` |
| `420777123456` | celé číslo včetně předvolby | `+420777123456` |
| `+421 900 123 456` | předvolba přímo v hodnotě | `+421900123456` |
| `+1 (415) 555-2671` | bez omezení země | `+14155552671` |
| `+44 20 7946 0958` | bez omezení země | `+442079460958` |
| `0044 20 7946 0958` | mezinárodní zápis s `00` | `+442079460958` |
| `123` | nedostatečná délka | vynecháno |
| prázdné pole | e-mail i telefon | vynecháno |

PSČ a země se přebírají pouze ze samostatných typovaných polí nebo strukturované
adresy s `postal_code` a dvoupísmenným `country`. Současné běžné adresní pole je
volný text; PSČ ani zemi z něj neodhadujeme a národnost nezaměňujeme za zemi
bydliště. U takového formuláře budou tato dvě pole vynechána.

Před ecommerce/lead pushem se vyčistí `ecommerce` i `user_data`; po konverzi se
`user_data` znovu nuluje. Tím se vymaže aktuální model GTM, nikoli historická
položka v paměťovém poli dataLayer nebo data již odeslaná tagem. Kontakty se
neukládají do URL, analytického localStorage příznaku ani serverového receiptu.
Další osobní údaje, odpovědi, sedadla a capability tokeny se neposílají nikdy.

## Administrace, načítání a bezpečnost

Existující `settings.analytics` ukládá `gtm_container`, `scripts` a přepínač
`enhanced_conversions`. GTM má formát `GTM-` a 4 až 32 velkých písmen nebo číslic.
Používá se standardní `https://www.googletagmanager.com/gtm.js?id=<ID>`.
GTM kontejner může spouštět libovolný JavaScript, proto pro všechny tři volby
platí stejné serverové oprávnění.

Lidská role platformy v repu neexistuje. Schválený fallback je
`organization_users.is_admin` organizace uložené akce. Helper
`get_is_admin_on_occasion` ověřuje právě tuto organizační roli.
`can_manage_form_measurement` je její typed predicate a
`forms.measurement.write` projekce pro UI. Existující oprávnění k editaci
formuláře platí dál. Editor/prodejce může zachovat měření při jiném uložení,
ale nesmí ho změnit či smazat. Explicitní nulový reset funguje i na starších
formulářích bez `design.presale_header`; vynechání nových klíčů starším klientem
zůstává zachováním. Kopie formuláře, celé akce i průvodce měření vždy odstraní,
včetně starších uložených draftů. Definer má deklarovaný ACL a bezpečnostní manifest.

`scripts` je jediné víceřádkové pole pro celé bloky `<script>`, inline i HTTPS
`src`. Limit 5000 Unicode kódových bodů má jediný zdroj
`automation/form_measurement_limits.json`, ze kterého vznikají konstanty JS,
Dart a SQL. Server ho vynucuje a UI ukazuje počítadlo. Kód se parsuje v inertním
`template`, které se nikdy nevloží do živého DOM. Vytvářejí se pouze nové
`script` elementy s povolenými atributy `src`, `type`, `async`, `defer`,
`integrity`, `crossorigin`; ostatní HTML a event atributy se ignorují.
`src` musí být absolutní HTTPS URL bez uživatelských údajů. Loader nastavuje
`referrerPolicy: 'no-referrer'`. Vlastní skripty zachovají pořadí: další tag čeká
na `load` nebo `error` předchozího externího či modulového skriptu. Před každým
vložením se znovu ověří session a veřejný kontext. GTM zůstává standardně async.

Tagy se načítají pouze v hlavním okně na veřejném `/form/<slug>`, bez session,
preview a osobního/platebního kontextu. Selhání kontroly úložiště znamená zákaz.
Vyžaduje se dostupné sledování Auth SDK. Původní kontext se zachytí před
routerem, včetně sale-opening markeru HTML shellu, takže odstranění tokenů
nemůže povolit původně neveřejný vstup. Na veřejném formuláři router ponechá
`lang`, `utm_source`, `utm_medium`, `utm_campaign`, `utm_term`, `utm_content`,
`gclid` a `fbclid`, aby je GTM viděl při spuštění. Ostatní query a fragmenty
odstraňuje jako dosud; tokenový vstup však zůstane analyticky zablokovaný.
Jiné stránky tímto zachováním atribuce neprocházejí. `embed=1` dovoluje jen
zprávy hostiteli a nikdy načtení tagů.

Po spuštění cizího kódu běží guard až do opuštění dokumentu. Uvnitř formuláře
povoluje pouze `#seat-selection`, `#order-preview`, `#order-result`. Jiná cesta,
formulář či neveřejný parametr vyvolají plnou navigaci. Nepovolená fragmentová
navigace vynutí i reload, protože samotný `location.assign` s hashem dokument
neopustí. Příznak opuštění se nastaví až na `pagehide`, takže pokus, který dokument
neopustil, nevypne další kontroly. `pageshow` jej obnoví pro kontrolu BFCache.
Přihlášení, mezikartové storage změny a návrat do popředí při neveřejném kontextu
vynutí reload. Při ověřeném odchodu do Stripe se nejprve zachová existující
soukromý návratový history state a provede jediná externí navigace. Návrat
obnoví `/stripe/pay` se stejnou capability a nezaloží další objednávku.

**Guard není izolace před škodlivým skriptem.** GTM i kód organizace běží na
sdíleném originu `vstupenky.online`, vidí zadávané údaje a může ovlivnit stránku.
Při přihlášení v jiné kartě může vlastní `pagehide` handler ještě před reloadem
přečíst auth token z localStorage a odeslat jej přes sendBeacon. Hook fetch
může zpřístupnit i platební capability. Dopad přesahuje hranice organizací;
GTM Custom HTML má stejnou moc a kontejner se může změnit mimo Festapp.
Ruční schvalování malého počtu organizací vlastníkem riziko zmírňuje, neizoluje.

Kód může trvale zapisovat do localStorage, IndexedDB, cookies a Cache Storage;
reload je nemaže. Vlastní service worker vyžaduje spustitelný skript stejného
originu a povolený scope, pouhý inline či externí snippet nestačí. Repo však
již má root `/festapp_service_worker.js` a OneSignal `/push/`; tento PR jejich
registrace ani browserová úložiště neizoluje a nezaručuje nepřetrvávání.
Jedinou plnou opravou přístupu ke session je oddělený origin formulářů.

**Před aktivací v produkci musí rozhodnout autor repa.** Doporučení je
organizační přepínač vypnutý ve výchozím stavu a povolovaný pouze vlastníkem,
pro GTM i vlastní skripty. Tento organizační přepínač se zde **neimplementuje**.
Další variantou je schvalování skriptů, které ale nepokryje změny uvnitř GTM,
nebo úplné oddělení originu. Současné `is_admin` je oprávnění ke změně nastavení,
nikoli konečná bezpečnostní ochrana. Podrobný návrh rozhodnutí je v PR-BODY.md.

CSP se neoslabuje. Enforced politika je jen `base-uri 'self'; object-src 'none'`,
`script-src` je report-only. Pozdější vynucení dnešní politiky zablokuje nové
inline skripty bez nonce/hash i nepovolené externí zdroje včetně GTM.
Nepřidává se `unsafe-inline`, nonce, nový zdroj ani bypass CSP.

## Embed

Stejné události se posílají hostiteli jen při `data-festapp-datalayer`.
Kontakty vyžadují navíc zapnuté rozšířené konverze formuláře **a** samostatný
atribut `data-festapp-datalayer-user-data`. Před tímto potvrzením se kontakty
ani neukládají do čekající fronty bridge. Host údaje znovu normalizuje z whitelistu,
řídí se aktuálními atributy a nuluje stav před i po konverzi. Iframe nevytváří
svůj dataLayer a nikdy nenačítá GTM či vlastní skripty. Detaily a příklady jsou v
[embedded-checkout.md](embedded-checkout.md#datová-vrstva-hostitele).
