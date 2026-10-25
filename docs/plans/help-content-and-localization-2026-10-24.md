# Nápověda: obsah, screenshoty a společný základ CZ/EN

Datum: 2026-10-24
Stav: osnova odsouhlasena v konverzaci 2026-10-24, pokračování implementace
potvrzeno 2026-10-25. Publikace kompletního obsahu čeká na dokončení a ověření.
Nahrazuje představu, že současných šest stránek je konečná struktura nápovědy.

## Potvrzené požadavky uživatele

- Nápověda musí jít použít také pro anglickou variantu služby.
- Nejprve určit podstatná témata a strukturu, potom dopracovat návody.
- Integrace mají vlastní první oblast: obecné vložení, WordPress, Webnode a
  následně skutečně ověřený Wix. WordPress obsahuje cestu s doplňkem i bez něj.
- Dále základní práce s akcí a konkrétní provozní postupy.
- Screenshoty musí ukazovat, jak se skutečné úkony dělají. Video je pozdější etapa.
- Hlavička, patička, tlačítka, typografie a grafický styl musí odpovídat hlavní
  stránce služby. Podobná barevnost samostatně nestačí.

## Pro koho a k jakému výsledku

Primární čtenář je pořadatel, který potřebuje dokončit konkrétní úkol bez podpory.
Další jasně vymezený čtenář je pracovník odbavení. Návody pro kupující směrovat
odděleně; nezamíchat hledání ztracené vstupenky mezi administrátorské postupy.

Názvy článků formulovat podle úkolu: „Jak vložit formulář do WordPressu“,
„Jak vytvořit plánek sálu“, „Jak odbavit návštěvníka“. Nepřebírat interní
názvy modulů jako hlavní navigaci a nevytvářet katalog všech tlačítek aplikace.

## Navržená informační struktura

Pořadí oblastí na rozcestníku i v navigaci:

1. **Integrace a vložení na web / Integrations and embedding**
   - Vložení na libovolný web pomocí HTML, včetně generátoru.
   - WordPress: jeden přehled se dvěma jasnými cestami, s doplňkem a přes
     Vlastní HTML. Vlastní kroky a screenshoty pro každou cestu.
   - Webnode: samostatný dohledatelný článek s vlastními předpoklady a postupem.
   - Wix: článek zveřejnit až po reálné instalaci, schválení modelu a ověření
     podporovaných editorů. Bez prázdné veřejné stránky slibující dostupnost.
   - Běžný odkaz nebo tlačítko na samostatný formulář jako alternativa v HTML
     článku, nikoli duplicitní dlouhý návod pro každý redakční systém.
2. **Začínáme s akcí / Getting started**
   - Založení akce a údaje pořadatele: název, datum a čas, místo a vzhled.
   - Příprava a zveřejnění prodejního formuláře: pole, povinné údaje, uložený
     veřejný odkaz, dostupnost prodeje a kontrola jako návštěvník.
   - Součástí první cesty je přihlášení; samostatný dlouhý článek o registraci
     není potřeba, pokud skutečné dotazy podpory neukážou opak.
3. **Vstupenky a plánek / Tickets and seating**
   - Typy vstupenek, ceny a kapacity.
   - Vytvoření plánku, propojení míst s nabídkou a ověření nákupu konkrétního místa.
   - Vzhled vstupenky a kontrola výsledného PDF.
   - Později: cenové vlny, zásoby a předtištěné série, složitější layouty,
     přesuny míst a další doložené časté scénáře.
4. **Objednávky a platby / Orders and payments**
   - Způsoby platby a co musí pořadatel připravit před zahájením prodeje.
   - Práce s objednávkou: kde ji najít, jak poznat její stav, opravit údaje
     a doručovací e-mail nebo znovu zpřístupnit vstupenky.
   - Později odděleně: storno objednávky a vrácení platby, ruční prodej,
     čekací listina a změny větších objednávek.
   - Storno není automaticky refundace. Popisovat jen ověřené chování aplikace
     a konkrétní platební metody; neslibovat neověřené tlačítko nebo automatizaci.
5. **Odbavení návštěvníků / Check-in**
   - Příprava přístupu pracovníka, otevření skeneru, kontrola QR a reakce na
     platnou, použitou nebo neznámou vstupenku; ruční dohledání.
   - Později samostatně offline provoz a jeho skutečná omezení, oprávnění týmu,
     souběžná zařízení a řešení konfliktních výsledků.
6. **Řešení potíží / Troubleshooting**
   - Problémy vložení: chybné URL, odstraněný skript, výška, vzhled, cache.
   - Z praktických dotazů postupně oddělit nedoručený e-mail, nerozpoznanou
     platbu a problém skeneru. Z konkrétního článku vést přímo na odpovídající pomoc.
   - Kontakt na podporu: co poslat a které údaje neposílat.

Integrace jsou první oblast, ale člověk bez uloženého formuláře z ní musí mít
krátký přímý odkaz na založení akce. Pořadatel se nemá proklikávat povinnou
učebnicí, než se dostane ke konkrétnímu problému.

## Doporučený první obsahový rozsah k odsouhlasení

Navrhuji dvanáct skutečně hotových článků, místo mnoha prázdných kategorií:

| Oblast | Články první verze |
| --- | --- |
| Integrace | Obecné HTML, WordPress oběma cestami, Webnode |
| Začínáme | Založení akce, příprava a zveřejnění formuláře |
| Vstupenky a plánek | Ceny a kapacity, plánek, vzhled/PDF vstupenky |
| Objednávky a platby | Nastavení plateb, práce s objednávkou a doručením |
| Odbavení | Základní postup odbavení |
| Řešení potíží | Problémy vložení a kontakt na podporu |

Wix se přidává až jako hotová podporovaná integrace. Pokročilé scénáře se
rozšiřují podle konkrétní potřeby, aby nevznikl neověřený kompletní manuál.
První implementační krok ověří společný vzhled a lokalizaci na integračních
návodech, poté se rozšíří základní a provozní postupy podle této osnovy.

## Jednotná podoba článku

Každý návod obsahuje:

1. Co po dokončení bude fungovat.
2. Co je potřeba předem: oprávnění, připravená data, tarif nebo aktivní funkce.
3. Stručné konkrétní kroky s přesnými názvy ovládacích prvků.
4. Screenshot u každého významného přechodu a rozhodujícího nastavení.
5. Výsledek a ověření jako skutečný uživatel nebo návštěvník.
6. Nejčastější potíž pro tento úkol a přímý navazující návod.

Rizikové kroky jako zveřejnění, vytvoření objednávky, rezervace místa, odeslání
e-mailu nebo storno označit v místě, kde nastanou. Nepřekrývat celý návod
opakovanými obecnými upozorněními. Videa nesmí být podmínkou pochopení postupu.

## Plán screenshotů

| Návod | Rozhodující skutečné obrazovky |
| --- | --- |
| Obecné HTML | Veřejný odkaz uloženého formuláře, volba vložení/generátor, vložený kód a publikovaný výsledek na počítači i mobilu |
| WordPress s doplňkem | Instalace/aktivace, přidání bloku, nastavení odkazu a výšky, veřejná stránka |
| WordPress bez doplňku | Přidání Vlastního HTML, vložený kód, veřejný výsledek; odlišit od pouhého náhledu editoru |
| Webnode | Přidání HTML bloku, dialog vložení kódu, publikace a skutečný veřejný výsledek |
| Založení akce | Vstup do založení, podstatné otázky průvodce a uložená akce; nepřidávat již zrušený výběr typu akce |
| Formulář | Nastavení polí, uložený veřejný odkaz, návštěvnický formulář a rekapitulace |
| Ceny a kapacity | Nabídka vstupenek a kapacity, správná cena a dostupnost ve veřejném formuláři |
| Plánek | Editor, přiřazení míst/cen a výběr místa z pohledu kupujícího |
| Vzhled vstupenky | Nastavení a skutečný náhled vygenerované ukázkové PDF vstupenky |
| Platby | Konkrétní dostupné nastavení a zákaznické platební instrukce; odděleně podle podporované metody |
| Objednávka | Přehled, detail a stav, oprava kontaktu/doručení a ověřený výsledek |
| Odbavení | Přístup pracovníka, skener, platný a opakovaný QR, ruční dohledání; skutečné mobilní rozhraní |

Pravidla pořizování a údržby:

- Skutečná aplikace a skutečné UI systému, žádné vygenerované náhražky.
- Izolované syntetické akce, objednávky a kontakty; žádné údaje skutečných
  kupujících, přístupové tokeny nebo platné produkční QR.
- Český článek má české UI, anglický článek anglické UI. Český screenshot
  s anglickým popiskem nenahrazuje anglický postup.
- Obrázek zabírá relevantní okolí a ovládací prvek, bez lišt ladicího prohlížeče.
- Jednotné jednoduché zvýraznění kroku; instrukce zůstávají také v textu.
- Mobilní záběr tam, kde mění skutečný postup nebo pomáhá ověřit vložení.
- Uložit neanotovaný originál a publikovanou variantu. Evidovat téma, krok,
  jazyk, značku, datum, ověřenou verzi aplikace a stav schválení.
- Obrázky mají smysluplný alternativní text, rozměry a možnost čitelného zvětšení.
- Změna důležitého UI zneplatní příslušný záběr k revizi; nezachovávat tiše
  staré obrázky jen proto, že soubor stále existuje.

## Společný základ pro českou a anglickou službu

Sdílet strukturu a vykreslování, nikoli udržovat dva nezávislé weby nápovědy.

- **Identita tématu:** stabilní ID nezávislé na jazyku a URL, například
  `integrations.wordpress` nebo `tickets.seating`. Přepnutí jazyka směřuje
  na stejné téma, ne vždy na rozcestník.
- **Lokalizovaný obsah:** titulky, text, kroky, metadata pro vyhledávače,
  popisky, alt texty a hlášky generátoru mimo vykreslovací kód.
- **Profil služby:** značka, origin služby, kontakty, odkazy do administrace,
  právní stránky, identita doplňku a dostupné funkce z jedné konfigurace.
- **Generátor:** stejná logika pro obě značky, validace podle originu aktivního
  profilu. Žádné překládání pevně zapsané české domény v jednotlivých souborech.
- **Média:** prostředky podle tématu, kroku, jazyka a značky; jednotný záznam
  dovolí později přidat video s posterem a titulky bez přestavby článků.
- **Rozdíly produktů:** platby, měny, tarify externích platforem a stav vydání
  každého doplňku ověřovat samostatně. České podání WordPress pluginu není
  důkazem dostupnosti anglické distribuce v katalogu.
- **Publikační stav:** koncept, k ověření, hotovo. Nezveřejňovat český text na
  anglické URL jako tichou náhradu za nehotový překlad. Přepínač nabízí
  skutečně dostupnou jazykovou variantu a zachovává téma.
- **URL a SEO:** české a anglické cesty mapovat podle témat. Při přesunu
  současných českých URL zachovat přesměrování a aktualizovat interní odkazy,
  canonical, sitemap a jazykové vazby podle skutečně zveřejněných variant.

Současný renderer je záměrně první český prototyp: má pevnou doménu, české
řetězce a jednu identitu ZIPu. Před zavedením anglické nápovědy tyto údaje
přesunout do profilu a jazykových zdrojů; nekopírovat renderer do druhé větve.
Tento plán nezapíná ani nenasazuje další produkční tenant.

## Jednotná grafika a společné části webu

Potvrzený požadavek je přesná návaznost na hlavní stránku:

- Sdílená hlavička, wordmark/logo, účtové akce a jejich stavy.
- Stejná patička, kontaktní údaje a právní/podpůrné odkazy pro danou značku.
- Společné varianty tlačítek, rozměry, typografie, zaoblení, focus/hover stavy
  a chování na mobilu. Generátor nevytváří vlastní konkurenční sadu ovládání.
- Značkové tokeny a fonty ze stejného zdroje jako hlavní stránka.
- Nápověda si ponechává čtecí uspořádání: tematickou navigaci, obsah článku,
  čitelnou šířku textu a obrázky. Marketingové animace ani prodejní sekce
  nejsou součástí každého článku.

Současná hlavička a patička prototypu nápovědy jsou zjednodušené a tento nově
upřesněný požadavek ještě nesplňují. Při navazující implementaci použít jeden
společný zdroj veřejné hlavičky/patičky a ovládacích stylů; nekopírovat další
verzi HTML a později ji udržovat ručně. Vycházet z
`automation/release/organizers/page.html`, `page.css` a existující účtové hlavičky.
Změna se týká společného veřejného shellu, nikoli redesignu hlavní stránky.

## Jak pokračovat po rozhodnutí o obsahu

1. Potvrdit oblasti a rozsah první verze z tohoto návrhu.
2. Sjednotit veřejný shell a zavést profil/jazykové zdroje nápovědy.
3. Dokončit jeden obecný integrační článek a jeden základní postup včetně
   skutečných screenshotů; na nich potvrdit podobu ostatních návodů.
4. Doplnit dohodnuté články a jejich ověření, potom skutečné anglické varianty.
5. Později vybírat témata pro video, zejména plánek a delší postup odbavení.

Do rozhodnutí o osnově zůstává dosavadní preview návrhem, nikoli finální
nápovědou připravenou k produkčnímu vydání podle nových požadavků.
