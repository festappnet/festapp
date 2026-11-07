# Objednávkový formulář na vlastním webu

V nastavení formuláře jej nejprve uložte a zvolte **Vložit na vlastní web**.
Zkopírujte kód do HTML bloku svého CMS. Při neuložené změně adresy se používá
poslední uložený odkaz. Nový formulář je nutné nejdříve uložit.

Automatická výška používá iframe a externí `/embed.js` ze stejného tenantu.
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
| init | parent -> child | instance, viewportHeight 240-4000 CSS px, autoHeight (false pro pevnou výšku), volitelné dataLayer: true a dataLayerUserData: true |
| viewport | parent -> child | Stejné ID a výška 240-4000 CSS px |
| theme | parent -> child | Stejné ID a volitelná prezentace theme |
| analytics | child -> parent | Whitelistovaný objekt payload, viz Datová vrstva hostitele |
| resize | child -> parent | Konečná výška 240-20000 CSS px |
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

`data-festapp-datalayer` volí výhradně hostitelský transport. Bez atributu je cílem
oddělený runtime jednotky. Obě cesty fungují bez dalšího kódu na webu. Napojení lišty
je volitelné a předává jen stav souhlasu:

```js
const formular = document.querySelector('iframe[data-festapp-embed]');
FestappEmbed.setMeasurementConsent(formular, {analytics: true, marketing: false});
```

Pro průběžné čtení uložené volby slouží `connectKlaro(formular, manager)` nebo
`connectMeasurementConsent(formular, zdroj)`. Bez signálu je stav `denied` a měření
běží. Změna volby měření nezastaví ani nespustí znovu.

Layout/scroll/theme zůstávají na protokolu 1. Měření používá protokol 2 a staré
měřicí zprávy odmítá. Události se nefrontují. Již přijatá data nelze odvolat. Povolené kampaně se filtrují,
celá URL hostitele ani soukromé odpovědi se nepředávají. Podrobný kontrakt,
SQL fakta a provozní meze popisuje [měření formulářů](form-datalayer.md).

Měřicí komunikace používá protocol 3, nezávisle na layout protocol 1. Starý helper
nebo runtime s novým klientem měření neaktivuje; samotný checkout funguje dál.
Setter, Klaro a revision-aware source nahrazují jednu účinnou volbu. Odpojení
zdroje neobnoví starší souhlas a nový scope vyžaduje novou nebo znovu ověřenou
volbu. Změna iframe originu uklidí původní subscription i heartbeat.
