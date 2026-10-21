# Objednávkový formulář na vlastním webu

V nastavení formuláře jej nejprve uložte a zvolte **Vložit na vlastní web**.
Zkopírujte kód do HTML bloku svého CMS. Při neuložené změně adresy se používá
poslední uložený odkaz. Nový formulář je nutné nejdříve uložit.

Automatická výška používá iframe a externí `/embed.js` ze stejného tenantu.
Pokud CMS zakazuje skripty, zvolte pevnou výšku: iframe má 800 px a vlastní
posouvání. Výšku můžete v HTML upravit. Obě varianty obsahují odkaz pro otevření
běžného formuláře v nové záložce. Pokud CMS zakazuje iframe, použijte tento odkaz.

Hostitelská CSP musí povolit tenant host v `frame-src` a u automatické varianty
také v `script-src`. Host nemusí povolovat inline JavaScript. Nepřidávejte
neověřený `sandbox`, který může blokovat formulář nebo stažení QR.
Objednávka, rekapitulace, potvrzení i platba převodem zůstávají uvnitř iframe.
Přihlášení a administrace nejsou součástí vloženého formuláře.

Při chybě odeslání zavřete chybové hlášení a opakujte stejný požadavek v témže
formuláři. Skript nikdy neopakuje nákup automaticky. Při blokovaném trvalém
úložišti přežije identita nejasného požadavku pouze do zavření nebo obnovení
stránky. Reload a nový nákup nejsou zaručenou obnovou; při nejistotě ověřte
objednávku s pořadatelem. Chování Safari/iOS a konkrétního CMS je nutné ověřit
samostatně. Karetní brány a přechody do bankovních aplikací nejsou tímto
kontraktem garantované.

## Technický kontrakt

Vstup je `/form/<encoded-saved-slug>?embed=1`. Režim je explicitní, neodvozuje
se z `window.top`. Kanonizace slugu a historie zachovávají query a osobní
query parametry na kanonické cestě `/order`. Stávající Supabase session se neodhlašuje ani nenahrazuje. Aktivace
backendu a veřejné služby běží, organizer intent, Google pokračování, preview,
editor a Flutter navigace jsou vypnuté. `FormSession`, `DbOrders` a
`send-ticket-order` zůstávají jedinými vlastníky nákupu a identity příkazu.

`public/embed.js` je samostatný asset bez závislosti na aplikaci. Vícenásobné
vložení nevytváří další listenery. Každý `iframe[data-festapp-embed]` má vlastní
instanci; změna deklarovaného originu zneplatní jeho původní spojení. Odebrané
iframe skript přestane sledovat. Cache assetu má 300 s a revalidaci.

Zprávy používají `namespace: "festapp-embed"`, `protocol: 1`, `type` a po
inicializaci `instance`. Child oznamuje pouze neosobní `ready` bez instance na
`*`. Parent porovnává `source` s `contentWindow` a origin s deklarovaným src.
Potom pošle `init` s ID a `viewportHeight`. Child přijme jen `window.parent`,
připne jeho skutečný HTTP(S) origin a ID; další komunikace používá přesný
`targetOrigin`. Opaque/null originy jsou odmítnuty. HTTP slouží také lokálnímu
vývoji; veřejnou integraci publikujte na HTTPS.

Povolené typy a hodnoty:

| Typ | Směr | Data |
| --- | --- | --- |
| ready | child -> parent | Žádná osobní ani obchodní data |
| init | parent -> child | instance, viewportHeight 240-4000 CSS px |
| viewport | parent -> child | Stejné ID a výška 240-4000 CSS px |
| resize | child -> parent | Konečná výška 240-20000 CSS px |
| scroll-request | child -> parent | Konečné y v rozsahu 0 až výška iframe, nejvýše 20000 |

Child opakuje ready nejvýše desetkrát; parent inicializuje při objevení iframe,
jeho load i ready. To pokrývá obě pořadí načtení a reload. ResizeObserver a RAF
měří přirozenou výšku body, včetně otevřeného dialogu a kalendáře. Změny DOM
vyvolají přeměření, odstranění stránky odpojí observery i listenery. Obsah nad
20000 px používá vnitřní scroll. Viewport aktualizace parent dávkuje přes RAF.
Scroll se vyžaduje při návštěvníkově akci, nikdy při běžném resize nebo prvním
načtení; host respektuje reduced motion.

Rekapitulace, loader a výsledek jsou v toku dokumentu i v pevné variantě.
Plánek má vlastní panel omezený hostitelským viewportem, bez handshake vlastním
viewportem iframe. Jeho pan/zoom a rezervace zůstávají stejné. Kalendáře a
organizátorský dialog zůstávají stávající komponenty; otevřený dialog je umístěn
u spouštěcího prvku a zahrnut do měření. Escape a historie zavírají jednotlivé
kroky, rodičovský dokument se nezamyká.

Protokol neobsahuje JWT, secret, capability, osobní údaje, payload objednávky
ani stav platby. Parent nemůže vybrat produkt/sedadlo, předvyplnit nebo odeslat
formulář. Handshake není autentizací organizátora a nechrání před samotným
škodlivým hostitelským webem. Budoucí změny veřejného assetu musí zachovat
protocol 1 nebo výslovně řešit migraci kontraktu.

## Lokální ověření

Fixture je v `web_client/tests/fixtures/embedded-checkout/`. Použijte vlastní
nový Supabase projekt podle festapp-local-e2e runbooku, porty 59821/59822,
kanonickou baseline, novější migrace a seed. Teprve pak aplikujte `tenant.sql`.
Fixture odmítá neprázdný tenant, vypíná jeho cron úlohy a nepouští email worker.
Nedodávejte externí provider credentials. Pro waitlist vytvořte vlastní náhodný 32bytový `EMAIL_PAYLOAD_KEY` v Base64
v privátním env souboru pro lokální Edge runtime; jde o šifrování lokální fronty,
ne o přístup k poskytovateli emailu. Lokálně obsluhujte skutečnou funkci
`send-ticket-order` z úplné kopie `supabase/functions`.

Uložte `supabase status -o json` do privátního souboru s právy 0600. Spusťte
Vite s `FESTAPP_EMBED_LOCAL_STATUS=<soubor>` a konfigurací
`web_client/tests/fixtures/embedded-checkout/vite.config.mjs`. Config povolí
jen backend `http://127.0.0.1:59821`. Host otevřete na
`http://localhost:59801/tests/fixtures/embedded-checkout/host.html`.
Iframe používá `127.0.0.1`, tedy skutečně jiné site, nikoli pouze jiný port.
Parametry fixture jsou `mode=fixed`, `two=1` a `form=embedded-seats`,
`embedded-closed` nebo `embedded-waitlist`; `reject=1` pošle chybný handshake bez helperu. Server je určen jen tomuto testu;
po dokončení jej i vlastní disposable projekt zastavte.
