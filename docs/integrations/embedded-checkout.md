# Objednávkový formulář na vlastním webu

V nastavení formuláře jej nejprve uložte a zvolte **Vložit na vlastní web**.
Zkopírujte kód do HTML bloku svého CMS. Při neuložené změně adresy se používá
poslední uložený odkaz. Nový formulář je nutné nejdříve uložit.

Automatická výška používá iframe a externí `/embed.js` ze stejného tenantu.
Helper ihned nastaví startovní výšku 120 px a poté ji přizpůsobuje obsahu,
bez animace (také při reduced motion). Atribut `height="800"` zůstává jako
fallback bez JavaScriptu, včetně stávajících WordPress pluginů. Pevné výšky
se helper nedotýká. Nový helper posílá volitelné `minHeight: 120`; child bez
něj zachová minimum 240 px pro kompatibilitu se staršími helpery protokolu 1.
Rozsah `viewportHeight` se nemění. Na webclientových cestách `/form/:slug` a `/order` s přesným `?embed=1` je startovní plocha
průhledná s černobílým symbolem bez názvu webu v boxu 48 × 48 px. Startovní výška
120 px ponechává okolo symbolu prostor; veřejný SEO souhrn je skrytý,
aby neprosvítal při načítání. Při převzetí vzhledu se světlý/tmavý režim řídí
hostitelskou stránkou, včetně jejího přepnutí, nikoliv osobním nastavením aplikace
nebo režimem prohlížeče. Helper sjednotí barevné schéma iframe i jeho obsahu,
aby Chrome nevykreslil neprůhledný canvas. Aktualizační banner se nezobrazuje.
Nedotčený veřejný formulář se aktualizuje automaticky; po začátku vyplňování
aktualizace počká na příští otevření a rozpracované údaje neruší.
Samooprava startu včetně deep refresh,
přepnutí verze před připravením aplikace a obnova rozbitého runtime zůstávají aktivní.
Pevná výška ponechá iframe na 800 px s vlastním posouváním. Převzetí vzhledu
funguje v obou režimech výšky, pokud CMS povoluje externí skript. Pokud jej
zakazuje, zůstane pevná výška a vlastní vzhled formuláře. Výšku můžete v HTML upravit. Obě varianty obsahují odkaz pro otevření
běžného formuláře v nové záložce. Pokud CMS zakazuje iframe, použijte tento odkaz.

Generovaný kód obsahuje pouze hostitelský obal, responzivní iframe, záložní odkaz
a externí `/embed.js` s `defer`. Vzhled řídí pouze uložené `forms.data.design.embed_inherit_style`. HTML ani doplňky nenabízejí vlastní přepínač. Inline JavaScript ani verzovací parametr `?v=appearance-1` nejsou potřeba. Iframe má `display:block`, aby pod ním nezůstávala
mezera textového řádku; šířku řídí jeho hostitelský blok. Nepřidávejte další
pevnou výšku do CSS, pokud chcete automatické přizpůsobení.

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
fragmenty. Stávající Supabase session se neodhlašuje ani nenahrazuje. Aktivace
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
| init | parent -> child | instance, viewportHeight 240-4000 CSS px, autoHeight (false pro pevnou výšku), volitelné minHeight: 120, volitelné dataLayer: true a dataLayerUserData: true |
| viewport | parent -> child | Stejné ID a výška 240-4000 CSS px |
| theme | parent -> child | Stejné ID a volitelná prezentace theme |
| analytics | child -> parent | Whitelistovaný objekt payload, viz Datová vrstva hostitele |
| resize | child -> parent | Konečná výška 240-20000 CSS px; s init.minHeight = 120 již od 120 px |
| scroll-request | child -> parent | Konečné y 0-20000, volitelné block start/end/nearest a height 0-20000; host cíl omezuje na iframe |
| scroll-save/scroll-restore/scroll-discard | child -> parent | Neosobní ID snapshotu vázané na konkrétní iframe; discard jej zruší bez posunu |

Child opakuje ready nejvýše desetkrát; parent inicializuje při objevení iframe,
jeho load i ready. To pokrývá obě pořadí načtení a reload. ResizeObserver a RAF
měří přirozenou výšku body, včetně otevřeného dialogu a kalendáře. Změny DOM
vyvolají přeměření, odstranění stránky odpojí observery i listenery. Obsah nad
20000 px používá vnitřní scroll. Změny velikosti viewportu parent dávkuje přes RAF. Pozici při scrollování
předává ihned, bez dalšího čekání na snímek.
Scroll se vyžaduje při návštěvníkově akci, nikdy při běžném resize nebo prvním
načtení; host respektuje reduced motion.

U automatické výšky posouvá stránku výhradně host. Child neposílá současně
požadavek a `scrollIntoView`, které by posouvalo i nadřazené dokumenty.
Pevná výška při handshake posouvá vlastní okno iframe a host pouze odhalí
dosud neviditelný cíl. Bez handshake zůstává jediným vlastníkem nativní
scroll prohlížeče včetně odhalení iframe na stránce. `nearest` ponechá viditelný prvek na
místě a jinak provede nejmenší nutný posun s okrajem 16 px.
Validace i cenový přehled používají tento stejný kanál. Rekapitulace jedním
plynulým posunem odhalí tlačítko odeslání včetně spodního odsazení, stejně jako
samostatný klient. Nepředchází mu druhý posun k nadpisu ani opožděný timer.
Reduced motion zachovává okamžitý přesun. Zavření rekapitulace a plánku
obnovuje uloženou pozici a focus bez nového scroll požadavku.
Při odeslání se snapshot rekapitulace zahodí a její cleanup skončí před
zobrazením potvrzení. Opožděná animace zavírání nesmí obnovit starou pozici
ani přemístit focus nebo patičku přes novou obrazovku.
Bez helperu lze uložit a obnovit pouze vnitřní scroll iframe; přesnou pozici
nadřazeného dokumentu spravuje jen spolupracující host.

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

## Vlastníci implementace

`web_client/src/runtime/page_context.js` klasifikuje podporované veřejné cesty;
`runtime_state.js` drží startup stav a jediný navigační zámek. Inline bootstrap
obou HTML shellů generuje `automation/lib/startup_theme.cjs`. Pouze webclientový
shell má embed prezentaci a kompaktní lokalizovanou chybu s retry. Ready marker,
událost `festapp-app-ready` a existující recovery globály zůstávají kompatibilní.

`update_policy.js` rozhoduje o důvodu obnovy, `update_controller.js` provádí
worker handshake a efekty a `update_banner.js` vykresluje běžnou aktualizaci.
`web/festapp_update_prompt.js` je standalone generovaný výstup. Před každým
navigačním efektem po čekání se znovu kontroluje aktuální ready stav. Výjimkami
z odložení aktualizace jsou jednorázová obnova prokázaného poškození runtime
a omezená migrace skutečně starých Flutter cache. Ruční retry při chybě
startu opraví cache vstupního modulu a nepřenačte již připravenou stránku.

`embed/protocol.js` vlastní základní wire kontrakt, `channel.js` připíná peer,
origin a instanci. `EmbedBridge` skládá child layout, measurement a stávající
`EmbedTheme`; formulář, validátor, přehled ceny a plánek používají jeho zachované
rozhraní. Na hostiteli oddělují `host_layout`, `host_presentation`, `host_price`
a `host_measurement` geometrii, vzhled, projekci ceny a scoped consent.
Measurement pravidla dál patří `form_measurement_contract` a
`FormMeasurementSession`. Staré disposery nesmějí zasáhnout novou vazbu.

`host.js` se přes esbuild sestaví do jediného `/embed.js`; CMS nepotřebuje žádné
runtime importy. `build_embed.mjs --check` a `build_runtime.mjs --check` odmítají
generační drift. Externí protokol 1, `FestappEmbed`, atributy a HTML markup
zůstávají podporované, včetně helperu s minimem 240 px a fallbacku 800 px.

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
`embedded-closed` nebo `embedded-waitlist`; `style=inherit` přidá vlastní webový
font a barvy hostitele (lze kombinovat s `mode=fixed`); `reject=1` pošle chybný handshake bez helperu. Server je určen jen tomuto testu;
po dokončení jej i vlastní disposable projekt zastavte.

## Centrální vzhled vloženého formuláře

Jediný vlastník je `forms.data.design.embed_inherit_style` (boolean, výchozí true). Oprávněný editor ho mění ve Vzhledu formuláře a ukládá běžným příkazem formuláře. HTML, WordPress, Joomla a Wix nikdy nepřepisují tuto hodnotu. Staré externí atributy `data-festapp-style` a staré lokální CMS hodnoty jsou inertní; nevytvářejí druhou rozhodovací cestu.

Host poskytuje jen omezené prezentační tokeny a písma; EmbedBridge ověřuje parent/source/origin/instance a po načtení formuláře řídí EmbedTheme jedinou uloženou volbou. Režim pevné výšky řídí pouze velikost. Helper se načítá v obou režimech. Standalone formulář a plánek sálu nemění vzhled.

Změny platí pro další načtení stránky bez výměny HTML nebo nuceného restartu nákupu. Historická vložení bez helperu ho musí jednou doplnit. Staré pluginové přepínače se po aktualizaci helperu stanou neúčinné; nové balíčky je odstraní z editoru. Veřejný odkaz nedává oprávnění uložit nastavení formuláře.

Zprávy init/viewport/theme mohou nést `theme: null` (obnovit vzhled služby) nebo
objekt s `fontFamily`, `text`, `background`, `primary`, `buttonText` a `fonts`.
Každá CSS hodnota má nejvýše 512 znaků a validuje se pro konkrétní CSS vlastnost.
Nejde o přenos libovolného CSS. Nejvýše 32 definic fontů obsahuje rodinu písma,
nejvýše 4 absolutní HTTP(S) URL bez credentials a standardní fontové deskriptory.
Child používá FontFace API, nikoli HTML/style injection; žádné CSS importy ani
skripty nepřijímá. Nové pole je aditivní k protocol 1 a starší integrace fungují.

Host čte dostupná @font-face pravidla, rozvine relativní URL podle stylesheetu
a přenáší pouze rodiny skutečné font-family. Cizí stylesheet může přečíst jen
s jeho CORS souhlasem (bez credentials). Server fontu musí povolit načtení
z originu služby; totéž musí povolit její font-src CSP. Jinak zůstane přesná
předaná font-family s jejími fallbacky. Změna tříd/stylů hostitele, načtení fontů,
resize i reload iframe aktualizují prezentaci. Vypnuté uložené nastavení zabrání použití hostitelského vzhledu.

`EmbedTheme` je jediný příjemce prezentace ve web clientu, za ověřením bridge.
CSS tokeny se přepisují pouze na veřejných checkout plochách, včetně rekapitulace,
výsledku a kalendáře. Body/root nastavení služby se nepřepisují, takže pozdější
načtení servisního tématu i vypnutí volby zachovají správný výsledek. Ovládání výběru míst (pokračování, zoom a souhrn ceny) přebírá stejné tokeny.
Samotný plánek a význam barev sedadel se nemění. Souhrn ceny zůstává vpravo nahoře ve viditelné části formuláře pomocí
nativního sticky zobrazení v hostitelském wrapperu. Admin/Flutter nejsou součástí přizpůsobení.

### Dlouhá rekapitulace

Existující host fixture s `?long=1&style=inherit` načte skutečný OrderPreview
s 8 vstupenkami, 7 odpověďmi objednávky a 32 odpověďmi vstupenek. `large=1`
použije 64 vstupenek pro ověření hranice 20000 px a vnitřního scrollu iframe.
Jde jen o test zobrazení; formulář nic neodesílá. Rekapitulace uvnitř embedu
roste s obsahem, běžně se posouvá hostitelská stránka. Standalone nákup dál
používá scroll uvnitř rekapitulačního dialogu. Ověřovat poslední odpověď,
celkovou cenu, dostupnost odesílacího tlačítka a vodorovné přetečení i na mobilu.

Parent v init/viewport zprávách předává také volitelný `viewportOffset` v rozsahu
0-20000 CSS px: viditelný horní okraj iframe při scrollování hostitelského webu.
Child jej po stejném ověření source/origin/instance promítá do
`--embed-visible-top`. Toto je kompatibilní režim pro původní ruční kód bez hostitelského wrapperu.
Nově generované integrace používají nativní sticky projekci bez scroll zpráv. Zprávy při scrollu neobsahují theme ani
znovu nečtou fontové stylesheety. Starší host bez tohoto pole používá offset 0.

Rekapitulace v obou režimech automaticky přejde dolů ke konečné ceně a odeslání.
V embedu bridge před scroll-request publikuje aktuální resize, takže se cíl
vyhodnotí až vůči nové výšce iframe. Volitelné `block: "end"` zarovná konec
cílového prvku k dolnímu okraji hostitelského viewportu; výchozí je start.
Pevný iframe a obsah nad 20000 px navíc využívají nativní posun uvnitř iframe.
Návrat z pickeru vrací pouze fokus, nevyvolává nový posun hostitele.

### Nativně připnutá cena a návraty z overlayů

WordPress renderer i generátor běžného embedu vytvářejí
`data-festapp-embed-host` kolem iframe. Helper iframe nikdy nepřesouvá ani
znovu nenačítá. Host v init oznámí `hostPrice: true`. `PriceWidget` zůstává
jediným vlastníkem výpočtu a formátování ceny; bridge publikuje pouze jeho view:
`price` zpráva obsahuje počet, již formátovanou cenu, doplňkové řádky, viditelnost
a omezené prezentační CSS vlastnosti. Žádná objednávka, identita nebo odpověď
z formuláře se do hostitele nekopíruje.

Helper vykreslí textovou projekci s native `position: sticky` uvnitř stejného
wrapperu a potvrdí `price-ready`. Teprve pak child skryje svou kopii. Aktivace
projekce pošle `price-activate`, který vyvolá existující akci původního widgetu
(posun k pokračování, nikdy odeslání objednávky). Rekapitulace a výsledek cenu
skrývají podle viditelnosti původního widgetu. Bez podpory projekce zůstává
funkční původní iframe widget. Při nativní projekci není připnutí ceny závislé
na postMessage ani RAF při scrollování.

Picker i rekapitulace používají společný `preserveCheckoutScroll`: před
otevřením zachytí polohu a po skutečném zavření obnoví fokus, polohu a původní
history scrollRestoration. V embedu zprávy `scroll-save` / `scroll-restore`
nesou jen náhodné ID snapshotu. Host ukládá vlastní souřadnice pro konkrétní
ověřenou instanci, obnoví je jednou a až po resize obnoveného formuláře.
Tím se stejné návratové chování používá pro šipku Zpět, zavření i Escape.

## Aktualizace nainstalovaného pluginu

WordPress plugin ukládá adresu, přístupný název a výšku. Vzhled vlastní formulář. Veřejný iframe
načítá živou službu a její verzované klientské assety; jeho `/embed.js` nemá
verzi pluginu v URL a produkční worker vyžaduje revalidaci při každém načtení.
Servisní vydání se tak projeví při dalším načtení stránky bez reinstalace
pluginu. Již otevřený formulář se během vyplňování násilně neobnovuje.
Změny WordPress nastavení, editoru nebo PHP vyžadují vydání pluginu.
Protokol 1 musí zachovat kompatibilitu se staršími instalacemi.

## Měření a datová vrstva hostitele

Měření je ve výchozím stavu vypnuté. Vyžaduje všechna uložená povolení, platné
zásady, aktuální policy a schválený hostitelský origin. Na souhlas nečeká: skripty se
načtou hned a volba návštěvníka jde do Consent Mode, který vyhodnocuje kontejner
pořadatele. Události `purchase` a `generate_lead` nesou `user_data` s e-mailem a
telefonem. Za nastavení tagů a použití údajů odpovídá pořadatel. Porucha CMP ani
starší helper nebrání nákupu ani layoutu.

Nově generovaný kód předvolí `window.dataLayer` hostitele a výslovně přidá
`data-festapp-datalayer`. Tagy a souhlasy pak řídí GTM a CMP webu. Bez atributu
zůstává oddělený runtime jednotky, takže starší vložení po aktualizaci helperu
nezmění příjemce údajů. Generátory při volbě jednotky atribut vynechají, což funguje
i se staršími helpery. Změna atributu za běhu transport znovu inicializuje.
WordPress a Joomla nabízejí volbu `measurement="host"` nebo `"unit"`; chybějící
či neplatná volba zachová jednotku. Hostitelský režim zpřístupňuje skriptům stránky
kontakty při konverzi a identifikátory transakcí. Volba transportu sama neuděluje
souhlas ani nezapíná měření.
Obě cesty vyžadují schválený origin a nezobrazují vlastní lištu souhlasu. Přímé
návštěvy dál používají runtime a Klaro. Hostitelský kontext i každá událost nesou
`form_embedded: true`; místo `page_view` se v obou transportech posílá
`form_page_view` se stejnou deduplikací podle `page_type`. Přímé návštěvy zachovávají
`page_view`. Na komunikačním kanálu zůstává vždy `page_view`; společný kontrakt
přejmenovává událost až při zápisu do cílového dataLayer. Starší příjemci tak
událost nezahodí a do své aktualizace zachovají dosavadní výstup.
Napojení hostitelské lišty na runtime je volitelné a předává jen stav souhlasu:

```js
const formular = document.querySelector('iframe[data-festapp-embed]');
FestappEmbed.setMeasurementConsent(formular, {analytics: true, marketing: false});
```

Pro průběžné čtení uložené volby slouží `connectKlaro(formular, manager)` nebo
`connectMeasurementConsent(formular, zdroj)`. Explicitní adaptér má vždy přednost
před automatickým mostem a jeho odpojení automatický zdroj neobnoví.
Automatický most vyžaduje zapnutí „Převzít souhlas z lišty schválených webů“ v nastavení
měření pořadatele (`measurement_consent_bridge`). Výchozí stav je vypnuto i pro
existující pořadatele. Zapnutím pořadatel potvrzuje, že web a formulář provozuje
jako stejný správce a lišta výslovně pokrývá formulář na vstupenky.online, účely,
služby GTM pořadatele, runtime `*.pages.dev` a Festapp jako zpracovatele. Musí
vysvětlovat odvolání; důkaz souhlasu uchovává pořadatel v CMP webu. Cizí partnerský
web tuto podmínku automaticky nesplňuje. Přepínač je součástí manifestu a revize
zpracování. Explicitní adaptéry fungují nezávisle na přepínači.

Most čte ICS každých 250 ms, jinak pouze nové příkazy Arguments v dataLayer každou
sekundu; pole ignoruje. Při zkrácení či výměně dataLayer začne znovu. Analytika
vyžaduje `analytics_storage`, marketing explicitní udělení všech tří typů
`ad_storage`, `ad_user_data` a `ad_personalization`. Chybějící stav znamená denied.
Regionální default bez aktualizace znamená denied. Přítomnost `__tcfapi` vždy
zamítne marketing; TCF most nečte, analytiku určuje Consent Mode.
Odvolání těsně před nákupem může dorazit až za 250 ms nebo 1 s; uspání prohlížeče
může okno prodloužit. Již předaná data nelze odvolat. Režim web zdroj odpojí,
návrat do režimu jednotky jej znovu připojí. Změna jednotky či revize zůstane denied
do nového navázání zdroje, například načtením nového vložení. Měření běží i při denied.

Layout/scroll/theme zůstávají na protokolu 1. Měření používá protokol 2 a staré
měřicí zprávy odmítá. Události se nefrontují. Již přijatá data nelze odvolat. Povolené kampaně se filtrují,
celá URL hostitele ani soukromé odpovědi se nepředávají. Podrobný kontrakt,
SQL fakta a provozní meze popisuje [měření formulářů](form-datalayer.md).

Měřicí komunikace používá protocol 3, nezávisle na layout protocol 1. Starý helper
nebo runtime s novým klientem měření neaktivuje; samotný checkout funguje dál.
Setter, Klaro a revision-aware source nahrazují jednu účinnou volbu. Odpojení
zdroje neobnoví starší souhlas a nový scope vyžaduje novou nebo znovu ověřenou
volbu. Změna iframe originu uklidí původní subscription i heartbeat.

Veřejný web instaluje pouze webovou část offline shellu. Flutter HTML, loader,
hlavní JS a všechny jeho deferred části se připraví atomicky až při skutečném
vstupu do Flutter aplikace. Veřejný formulář ani jeho update/recovery požadavek
je nestahují. Worker a per-version cache zůstávají společné; handshake nese
`runtime: web | flutter`. Běžná Flutter aplikace je dostupná offline po svém
online otevření, veřejný formulář má nezávislou webovou offline obnovu.

## Převzetí živé volby cookies

Web s `embed.js` může předat uloženou volbu svého CMP do samostatného formuláře:

```html
<script defer src="https://vstupenky.online/embed.js"></script>
<a data-festapp-consent-link target="_blank"
   href="https://vstupenky.online/form/vas-formular">Koupit vstupenky</a>
```

Pořadatel zapne `measurement_consent_bridge` a platforma schválí origin webu.
Samotný atribut odkazu ani stav Google Consent Mode nestačí. Správce webu jednou
nastaví standardní adaptér Complianzu na skriptu `embed.js`:

```html
<script defer src="https://vstupenky.online/embed.js"
  data-festapp-consent='{"provider":"complianz","organization":1,"unit":2,"consentRevision":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","policyId":"42"}'></script>
```

Ukázkové hodnoty nahraďte skutečnými ID organizace a jednotky, hodnotou
`analytics.consent_revision` z metadat formuláře a ID přijatých zásad Complianzu.
Archivované znění těchto zásad musí pokrývat nákup ve formuláři, jeho účely,
příjemce a oddělenou doménu měření. Konfiguraci neodvozujte z příchozí žádosti.
Jeden skript obsluhuje jednu organizaci a jednotku; cizí rozsah odmítne.

Adaptér ověří režim opt-in, uložené kategorie, stav lišty a shodu nastavené,
uložené a aktuální verze zásad CMP. Uložené přijetí, částečná volba i odmítnutí
se přenesou bez dalšího dotazu. Neznámý či zastaralý stav, chybějící API,
vynucené statistiky nebo souhlas po jednotlivých službách ponechá místní lištu.
Při TCF se automaticky neudělí marketing. Pouhé zavření lišty bez uložené volby
nic nepovolí. Přímé čtení pevných názvů cookies se nepoužívá; prefix řeší CMP.

Podporované standardní lišty jsou Complianz a CookieConsent v3 od orestbida.
Pro CookieConsent v3 zpřístupněte veřejné API i při bundlování přes npm:

```js
import * as CookieConsent from 'vanilla-cookieconsent';
window.CookieConsent = CookieConsent;
```

```html
<script defer src="https://vstupenky.online/embed.js"
  data-festapp-consent='{"provider":"cookieconsent","organization":1,"unit":2,"consentRevision":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","revision":42,"categories":{"analytics":"analytics","marketing":"marketing"}}'></script>
```

Hodnota `revision` musí být kladné celé číslo shodné s nastavením CookieConsent
i uloženou volbou. Archivujte odpovídající zásady a mapování na revizi Festappu.
Použijte režim `opt-in`; nula, opt-out, předvolené nebo povinné mapované kategorie
a volby po službách vracejí neznámý stav a ponechají místní lištu. Volitelné
`categories` určuje oba různé názvy kategorií webu; výchozí jsou `analytics` a
`marketing`. Při TCF marketing zůstává odmítnutý. Kontroluje se i expirace a změna
úložiště v jiné kartě; při neshodě se stavem instance je potřeba web znovu načíst.
Podporována jsou cookies i `useLocalStorage`. Neplatná konfigurace nepřejde na GCM.
Podrobnosti a zdroje jsou v [rešerši adaptéru](../plans/consent-link-cmp-adapters-2026-11-11.md).

Dalším standardním zdrojem je Cookiebot (`provider:"cookiebot"`). Stačí běžný
loader z Cookiebot Manageru:

```html
<script id="Cookiebot" src="https://consent.cookiebot.com/uc.js"
  data-cbid="12345678-1234-1234-1234-123456789abc" data-blockingmode="auto"></script>
<script defer src="https://vstupenky.online/embed.js" data-cookieconsent="ignore"
  data-festapp-consent='{"provider":"cookiebot","organization":1,"unit":2,"consentRevision":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","cbid":"12345678-1234-1234-1234-123456789abc","origin":"https://poradatel.example","consentValidFrom":"2026-11-11T00:00:00.000Z","maxAgeSeconds":15552000}'></script>
```

Všechny ukázkové hodnoty nahraďte. `cbid` musí odpovídat data-cbid nebo parametru
cbid loaderu a `origin` přesně HTTPS originu webu. Loader `.com/uc.js` ponechte
v DOM. Opt-in se čte ze stavu lišty, ne z atributů loaderu: volba musí být
výslovná (`consent.method`), musí platit GDPR a nesmí CCPA; implied volba, jiný
než opt-in režim účtu a neznámý stav souhlas nepřevezmou. Uložený záznam
`CookieConsent` musí nést ID souhlasu této karty, takže volba v jiné kartě nebo
smazaný záznam převzetí ukončí při následující sekundové kontrole. Pro ruční blokování použijte `data-blockingmode="none"`;
blokování samo nedokládá souhlas. Atribut ignore ponechá helper dostupný i při
automatickém blokování.

Cookiebot SDK nenabízí srovnatelnou verzi zásad. Povinné `consentValidFrom` je
okamžik účinnosti archivovaného znění (UTC ISO s milisekundami a Z), vůči němuž se
kontroluje `consentUTC`. Povinné `maxAgeSeconds` nastavte nejvýše na skutečnou
platnost v Cookiebotu, maximálně 365 dní; ukázka používá 180 dní. Při změně
rozsahu obnovte souhlasy a aktualizujte časový předěl i revizi Festappu.
CBID, stamp, consentID ani cookie ver nejsou automatickým důkazem verze zásad;
obsah a správné mapování dokládá správce. Změna CBID nebo domény převzetí odmítne.

Převádějí se statistics → analytics a marketing → marketing, pouze u výslovné
uložené volby shodné s API a čerstvou cookie. Implied/opt-out, neznámé či rozbité
API, expirace, per-service a nesoulad úložiště ponechají lištu formuláře bez
fallbacku na GCM. Interval kontroluje i jinou kartu; při neshodě načtěte web znovu.
TCF marketing zůstává odmítnutý. Podrobné hranice a oficiální zdroje jsou v
[dokumentaci měření](form-datalayer.md#configured-cookiebot-source).

Technická změna runtime ukončí starou vazbu, ale nemění verzi podmínek souhlasu.
Při změně účelů, příjemců nebo vzdáleného obsahu GTM/zásad zvyšte
`measurement_consent_version`, zajistěte nové rozhodnutí v CMP a aktualizujte
společné mapování jeho zásad a revize Festappu. Starý souhlas se nesmí označit
novou revizí. Pro jiné CMP zůstává `FestappEmbed.connectMeasurementSource`;
přesný kontrakt je v dokumentaci měření. Bez adaptéru se odkaz řídí místní lištou.
Dosavadní GCM cesta vložených formulářů bez napojeného zdroje se nemění.

Skript načtěte přímo z originu formuláře. Helper zachytí běžné kliknutí do nové
karty a formulář hned zruší veřejný opener. Odkazy s noopener/noreferrer,
referrerpolicy, stahováním nebo modifikátory zachovají nativní chování. Bez
referreru, propojení oken nebo při omezení COOP se zobrazí běžná místní lišta.
Povoleny jsou HTTPS originy; HTTP loopback pouze při lokálním vývoji.

Převzetí čeká nejvýše 1500 ms. Pak platí pouze pro aktuální návštěvu, nejvýše
24 hodin, a průběžně se obnovuje krátkou vazbou na živý zdroj. Odvolání na webu
se přenese; zánik záznamu, odpojení zdroje, opuštění webu nebo vypršení vazby
ukončí převzetí a obnoví místní lištu. Žádné převzaté souhlasy se nezapisují do
cookies. Obnovená nebo další karta vyžaduje nové předání. Vlastní volba uložená
ve formuláři má přednost a zůstává v cookie na 180 dní.

Po převzetí je dostupné plovoucí tlačítko nastavení. Uložení odpojí vzdálený zdroj;
Escape zavře neuložené nastavení. Obnovení vazby nepřepíše rozpracovanou volbu.
Klaro místní volby mezi již otevřenými kartami nepřenáší průběžně. Kliknutí helperu
může potlačit GTM Just Links trigger s validací; nákup měřte událostmi formuláře.

Přesný kontrakt zdroje a protokolu je v
[dokumentaci měření](form-datalayer.md#live-consent-transfer-to-a-new-tab).
