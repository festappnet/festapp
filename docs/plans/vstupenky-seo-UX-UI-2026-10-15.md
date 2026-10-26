> Historický plán. Veřejnou prezentaci služby dnes vlastní homepage `/`; pro aktuální směrování platí `automation/release/organizers/README.md`. Tento dokument není zadání k obnově původní samostatné stránky.

# UX/UI brief pro SEO vstupenky.online

Datum: 2026-10-15. Stav: plán, bez změn aplikace a bez vizuálního ověření. Podřízený dokument k [autoritativnímu SEO plánu](vstupenky-seo-plan-2026-10-15.md). Použit skill `ux-designer`. Implementace ani publikace tímto dokumentem nejsou autorizovány.

## Rozsah a pevná rozhodnutí

Cílem je vysvětlit službu pořadateli na `/pro-poradatele` a zachovat rychlou cestu účastníka z katalogu na akci. Grafická práce zahrnuje novou informační stránku, její odkaz z katalogu, kompaktní archiv a stavy dotčeného katalogu. Žádný obecný redesign, nové logo ani nová sada ilustrací.

Zachovat původní wordmark Festapp `/brand-logo.svg`, současný favicon, odkazy Soukromí a Podmínky a skrytý `#site-introduction`. Výslovnou preferenci provozovatele dokládá závěr [předchozího plánu](vstupenky-seo-2026-10-09.md). Na homepage nepřidávat náhradní marketingový hero blok. Rozsah je jediný tenant vstupenky.online; případné sdílené komponenty nesmějí automaticky zobrazit jeho obsah jiným tenantům.

## Důkazy a hranice průzkumu

| Ověřeno v místním zdroji | Důsledek pro návrh |
|---|---|
| `web_client/index.html:179` má úvod `hidden`; hlavička v `user_header.js:115` vytváří vizuálně skryté H1. | H1 v hlavičce není viditelným vysvětlením produktu. Nová stránka má vlastní viditelné H1; nepřidat k němu druhé H1 značky. |
| `user_header.js:180` podmiňuje nabídku založení tenantem a registrací; hostovi otevírá registrační pohled přihlašovacího dialogu. | CTA musí používat stejnou autorizovanou cestu a respektovat stav registrace; nepředstírat přímé založení bez přihlášení. |
| `UnitPage.render` již řadí probíhající, budoucí a minulé akce v tomto pořadí; archiv je plně rozepsaný. | Zachovat pořadí, změnit pouze výchozí prezentaci archivu. Neplánovat jako chybějící funkci již existující řazení. |
| `UnitPage.loadOccasions` při chybě vkládá anglický text a `e.message` do HTML, prázdná data a nulový výsledek hledání mají stejnou hlášku. | Navrhnout srozumitelný lokální text a opakování; hlavní implementátor zajistí bezpečné vykreslení a správnou klasifikaci stavů. |
| Shell má fullscreen startup overlay a `#app` s `display:none`. | Zachování použitelného serverového katalogu během čekání vyžaduje změnu startupu, ne pouze barvu loaderu. |
| Karty mají 16:9, tokenové radiusy, fotografii s textovým překryvem a `:focus-visible`; grid používá minimum 280 px. | Navázat na stávající karty; ověřit dlouhé názvy, kontrast nad fotografií a malé šířky při implementaci. |
| `theme_config.css` definuje světlý/tmavý režim, 1200px kontejner, spacing 8/16/24 px a radius 10/15 px; font může měnit tenantová konfigurace. | Použít existující tokeny a skutečný vybraný tenantový profil. Nezavádět vlastní paralelní paletu nebo font. |

Nebyl otevřen prohlížeč ani pořízen screenshot. Skutečné přetékání, kontrast, pořadí fokusu, čitelnost fotografií a chování živého releasu jsou neověřené; uvedené body jsou zdrojová zjištění nebo návrhy, nikoli vizuální audit. Historické výsledky náhledů nejsou ověřením budoucích změn.

## Nutné změny

1. **Stránka pro pořadatele.** Zachovat hlavičku se značkou a odkazy, obsah zarovnat v existujícím kontejneru; čtecí sloupec přibližně 65 znaků. Pořadí: H1 „Prodej vstupenek a registrace na akce“, krátké vysvětlení komu služba pomůže, primární CTA „Založit akci“, tři kroky založení - objednávky - odbavení, ověřené funkce, cena nebo doložený způsob jejího zjištění, 4-6 věcných FAQ, kontakt/provozovatel a právní odkazy. Jednotlivé sekce neobalovat automaticky do karet. FAQ může být běžný text nebo nativní `details/summary`, obsah přítomný v HTML.
2. **Vstup z katalogu.** Přidat nenápadný, trvale dostupný textový odkaz „Pro pořadatele“ v obsahové navigaci u hledání. Umístit jej mimo řadu akcí v úzké hlavičce; nedávat mu vzhled druhého primárního tlačítka. Musí být dostupný i v serverovém HTML, před načtením účtu. Na nové stránce nabídnout „Zpět na akce“.
3. **Archiv.** Pod aktuálními sekcemi použít kompaktní `details` se `summary` „Minulé akce (N)“, standardně zavřené. Uvnitř ponechat skutečné odkazy na veřejné akce. Při hledání, které vrátí archivní shodu, archiv rozbalit; pokud nejsou aktuální akce, sdělit to a ponechat jasně dostupný archiv. Hlavní implementátor potvrdí shodná data a klasifikaci se serverem. Neodstraňovat položky podle textu `(Copy)`.
4. **Stavy a přístupnost dotčené cesty.** Oddělit „Zatím zde nejsou žádné akce“, „Pro tento výraz jsme nenašli žádnou akci“ s akcí vymazání hledání a „Akce se nepodařilo načíst“ s opakováním. Zachovat již dostupné serverové odkazy při chybě aktualizace a označit neúspěšnou aktualizaci, ne katalog jako prázdný. Hledání dostane trvalé přístupné jméno, vymazání nativní tlačítko, stav stručné oznámení bez čtení celého katalogu. Technické chyby nepatří do uživatelského textu.
5. **CTA kontrakt.** Na stránce zvýraznit jednu hlavní cestu založení. Host vstoupí do existující registrace, přihlášený do existujícího oprávněného toku; stav zavřené registrace dostane pravdivé vysvětlení a ověřený kontakt, nikoli nefunkční tlačítko. Veřejná statická varianta musí mít skutečný navigační fallback na existující vstup, který určí hlavní implementátor. Nevymýšlet novou auth routu ani druhou registrační logiku.

## Doporučené a odložené

Doporučené: zopakovat hlavní CTA jednou za FAQ, pokud je stránka dlouhá; použít kompaktní textové oddělovače a již existující ikony pouze tam, kde pomáhají orientaci. Po implementaci zkontrolovat čitelnost skutečných dlouhých názvů a fotografií. Optimalizaci fontů přijmout jen při doloženém přínosu, zachované diakritice, rozměrech textu a ikonách.

Odložené: změna značky, nový hero, ilustrace, animace, reference bez souhlasu, ceník bez podkladů, nové filtry a stránkování, plošný redesign přihlášení/administrace, obecný audit všech komponent. Nalezené problémy mimo dotčenou cestu zaznamenat samostatně; neskrývat je kosmetickou změnou. Pošta, DNS, strukturovaná data a provozní SEO patří hlavnímu implementátorovi.

## Předání a rozdělení práce

Balík **U1** je návrh a statický náhled, balík **U2** je následná UI realizace a grafické ověření. Veškerou navazující grafickou UX/UI práci při autorizované realizaci přidělit subagentovi **`model: gpt-6-astra`, `reasoning_effort: medium`**. Vlastní informační hierarchii, layout, responzivitu, microcopy, stavové návrhy a grafické ověření; používá skill `ux-designer`. Nejprve připraví samostatný statický HTML náhled použitelný přes `file://` s jasně označenými ukázkovými daty. Konkrétní vzhled musí být před publikací ukázán uživateli podle autoritativního plánu.

Hlavní implementátor vlastní zdroj tenantové konfigurace, generování a doručení veřejného HTML a routing (**T2**), datový kontrakt a časovou klasifikaci katalogu (**T3**), metadata, startup a auth integraci. U2 navazuje na schválený U1 a dohodnutá rozhraní T2/T3; návrh U1 může postupovat souběžně s technickou přípravou. Před kódováním předá Astře: platný tenantový profil/tokeny, potvrzený cíl CTA pro hosta i přihlášeného, chování vypnuté registrace, význam časových stavů, způsob předání serverového katalogu klientovi a existující lokalizační rozhraní. Provozovatel dodá ověřený kontakt, cenu a produktová tvrzení; neověřené údaje se do veřejného obsahu nedoplní odhadem.

Před souběžnými úpravami rozdělit soubory: Astra vlastní samostatnou šablonu a její styly a dohodnuté prezentační změny katalogu; hlavní implementátor integrační soubory. `index.html`, `user_header.js`, `unit_page.js` a společné tokeny mají vždy jednoho aktuálního editora, druhý předává konkrétní patch/požadavek. Astra nesmí kvůli vzhledu měnit oprávnění, veřejnost akcí, canonical URL ani časovou klasifikaci. Hlavní implementátor zajistí stejné významové pořadí serverového a klientského obsahu a následnou cílenou validaci.

## Akceptační kritéria pro budoucí realizaci

| Oblast | Podmínka přijetí |
|---|---|
| Desktop a mobil | Náhled a integrovaná stránka při 1280, 390 a 320 CSS px bez horizontálního přetékání, překrytí loga nebo CTA; dlouhý název se zalomí. Při 200% zoomu lze číst a ovládat všechny nové prvky. Úvod homepage zůstává skrytý. |
| Styl | Původní logo a favicon, existující spacing/tokeny; světlý i tmavý režim bez nových pevných barev odporujících tématu. Fontová změna nevytvoří prázdné ikony ani nečitelnou češtinu. |
| Klávesnice | Odkaz pro pořadatele, CTA, hledání, vymazání, archiv a karty mají logické pořadí Tab a viditelný nezakrytý fokus. Odkazy fungují s Enter i otevřením v novém panelu; summary a tlačítka nativně. Návrat z dialogu vrátí fokus na spouštěč. |
| Přístupnost | Jedno obsahové H1 nové stránky, navazující H2, pojmenované ovládací prvky, správné role a smysluplné alt texty. Nový běžný text dosáhne kontrastu 4,5:1, velký text a potřebné hranice/fokus 3:1; kontrast ověřit i nad fotografiemi. Dotykové cíle nových prvků alespoň 24 x 24 CSS px, návrhově 44 x 44 px. Respektovat omezený pohyb. |
| Načítání a chyba | Bez JS je vysvětlení služby i navigace dostupná. Pomalý JS/backend nezakryje použitelný serverový katalog fullscreen overlayem. Selhání nabídne srozumitelný stav a opakování bez ztráty použitelného obsahu; nesmí se tvářit jako nula akcí nebo 404. |
| Archiv a hledání | Aktuální a budoucí akce před archivem; archiv rozbalitelný klávesnicí, odkazy přítomné v HTML. Archivní shoda hledání je viditelná. Ověřit 0/1/více akcí, pouze archiv a nulové výsledky hledání. |
| CTA a návrat | Odkaz z katalogu vede na skutečnou `/pro-poradatele`; CTA vede do potvrzené existující cesty pro hosta i přihlášeného. Zavřená registrace má vysvětlení. Návrat do katalogu funguje. Smoke neodesílá registraci, objednávku ani produkční změnu. |
| Jazyk a obsah | Čerstvý český i anglický profil má konzistentní nadpisy, stavy a přístupná jména podle dohodnuté lokalizace. Neověřená cena, reference ani přísliby nejsou publikované. |

Tyto podmínky jsou budoucí akceptace, nikoli provedené testy. Kontroly spojit do jednoho cíleného balíku po koherentní implementaci; vizuální kontrola izolovaně na pozadí, bez zásahu do uživatelova prohlížeče. Tento plánovací příspěvek neprovádí testy, build, deploy, commit ani push.
