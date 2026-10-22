# SEO nové úvodní stránky vstupenky.online

Stav22.10.2026: implementované lokálně, bez deploy/commit/push, bez požadavku
na indexaci. Uživatel výslovně zvolil variantu1 titulku i popisu: Prodej vstupenek na akce |
vstupenky.online. Ostatní dvě varianty zůstávají pouze pro srovnání. Headline/obsah landing
page se kvůli metadatům nepřepisuje a nepřidává se SEO výplň.

## Rozdělení záměrů

- `/`: pro pořadatele, prodej vstupenek na vlastní akci. Podpůrná témata vlastní
  plánek sálu, výběr míst, vlastní návrh vstupenky, přímé QR platby bez
  transakčních poplatků a odbavení telefonem.
- `/events`: pro návštěvníky, výběr akcí/plesů a nákup. Dostává vlastní titulek
  a description, aby nekopíroval sdělení služby pro pořadatele.
- Dřívější `/pro-poradatele` přesměrovává v připraveném Workeru308 na `/`;
  nepublikujeme dvě marketingové kopie. Kampaně mají canonical bez query.
- `plesy.vstupenky.online` zůstává samostatným existujícím katalogem, bez změn
  canonical napříč doménami. Varianta titulku zaměřená na plesy není důkaz
  objemu hledání a nezakládá automaticky další SEO stránku.

## Změny

Centrální metadata v publicProjection.seo. Nový head uvádí canonical, jednotné
OG/title/description, site name, jazykcs_CZ a index/follow/max-image-preview.
Vlastní PNG1200×630 používá skutečnou grafiku a Futura, místo ikony512×512.
Twitter karta používá name atributy a skutečné rozměry sdílecího obrázku.
Offline preview přepisuje jen relativní cesty médií; veřejné absolutní OGURL
zůstává nedotčené.

JSON-LD: WebSite, WebPage, Service, skutečný Person provozovatele s IČO a
kontaktem shodným s patičkou, propojené přes stabilní apexIDs. Bez fiktivní ceny,
hodnocení, počtů klientů nebo příslibů rich snippets. Cena služby se domlouvá
samostatně; „bez poplatků“ je v metadatech výslovně transakční QR převod.

Stávající dynamická sitemap v edge routeru už zahrnuje root, /events a veřejné
akce se správnými nativními cíli. Staticfallback je nyní konzistentní a zůstává
tenantově omezený. Nevymýšlíme lastmod při každém buildu. SearchAction pro
již nezobrazovaný search box se z této WebSite identity odstranil. Applyconfig
respektuje validní WebSite bez optionalaction a zachová rewrite tam, kde existuje.

## Read-only produkční audit

Veřejné GET bez přihlášení a zápisu:

- `/`200, titulek „Vstupenky online a registrace na akce | vstupenky.online“,
  description míří na nákup, jedna canonical na root, jeden JSON-LD script.
- `/pro-poradatele` stále200 se starým marketingovým titulkem a canonical na
  starou cestu, bez JSON-LD. `/events` zatím vede na root. Produkce tedy ještě
  nemá současné lokální rozdělení home/katalog; nejde o důkaz hotového releasu.
- `/sitemap.xml`200 application/xml, zatím obsahuje starou /pro-poradatele.
- Cloudflaremanaged robots při inspekci dovoluje běžné vyhledávání a Allow:/;
  pozorovaný text neobsahoval Sitemapdirective. Současný lokální robots ji má.
  Ověřit po nasazení, že ji edge nepřekryje. Managed AI pravidla neměněná.

## Ověření a zbývající release kroky

Cílené Node testy15PASS: generator (metadata,JSON-LD,escapeinjection,
site/catalogseparation,buildstamping), routing/canonical/sitemap/SSR/404 a další
existující veřejné kontrakty. Staticfallback tested pro vstupenky i jinou doménu;
PNG skutečně1200×630. Applyconfig fixturecheckPASS po opravě povinného
SearchAction a nahrazení spacing-dependent JSON assertions skutečným parsováním.
Žádný test ani config se nespouštěl proti produkčnímu backendu.

BrowserPASS:jedna canonical,H1,jednotná metadata a validní4nodeJSON-LD,
žádné rozbité obrázky. Veřejné OGURL zůstává správné i v offlinepreview.
Všechny3snippetvarianty ověřené na desktopu a mobilu,370pxmobilemode a bez
horizontálního overflow na390px. Původní okamžitá kontrola šířky před CSS
transition byla dokončená cíleným čekáním na konečný stav, bez product fix.
Receipt:Downloads/festapp-landing-review-2026-10-22/seo-review/final-review.json. Předchozí zamítnuté
configlogy jsou zachované v /tmp/festapp-seo-config*.log;15prošlých Node testů
se kvůli samotné opravě applyconfig/testu znovu nespouštělo.

Po autorizovaném releasu: ověřit apex/redirecty/robots/sitemap a doručení
nového socialPNG, zkontrolovat skutečné URL v SearchConsole a odeslat sitemap,
požádat o nové procházení. Přístup/SearchConsole nebyl v této revizi použitý.
Až pak měřit impres/CTR/dotazy a CoreWebVitals z reálných dat. Žádný slib
pořadí, CTR, doby indexace nebo přesného snippetu. Field performance ani
SearchConsolecoverage nebyly tímto lokálním checkem změřené.

## Primární podklady

- [Title links](https://developers.google.com/search/docs/appearance/title-link)
- [Snippets](https://developers.google.com/search/docs/appearance/snippet)
- [Site names](https://developers.google.com/search/docs/appearance/site-names)
- [Structured data policies](https://developers.google.com/search/docs/appearance/structured-data/sd-policies)
- [Sitemaps](https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap)
- [Retired search box](https://developers.google.com/search/blog/2024/10/sitelinks-search-box)
- [Video SEO](https://developers.google.com/search/docs/appearance/video): zde videa
  doplňují službu, proto nedeklarujeme samostatné watchpages nebo video richresults.

## Druhá revize: technické SEO celé veřejné cesty

Revize nekončí u meta description. Načtené metodiky `seo-audit`, `schema` a
`site-architecture` pocházejí z
[MarketingSkills](https://github.com/coreyhaines31/marketingskills/tree/e85f3cbc2e4a79bf33b2a12e9bdd9087d414735b),
připnuté na commit `e85f3cbc2e4a79bf33b2a12e9bdd9087d414735b`.
Použité jako auditní vodítko, bez instalace cizího kódu nebo přejímání slibů
pořadí ve vyhledávání. Nezávislý kritik zkontroloval návrh i implementaci.

### Prioritizované nálezy a řešení

| Priorita | Nález a dopad | Připravené řešení | Důkaz |
| --- | --- | --- | --- |
| P1 | Starý odkaz formuláře vracel jinou canonical v prvním HTML a po spuštění aplikace. | SEO RPC vrací uložený odkaz; edge přesměruje skutečný alias pomocí 308, zachová query a sjednotí canonical. | PostgreSQL alias fixture + Worker redirect test. |
| P1 | Při výpadku RPC formulář vracel HTTP 200 s metadaty katalogu. | HTTP 503, `Retry-After: 60`, `no-store`, vlastní canonical a zachovaný aplikační shell. Potvrzené neexistující stránky zůstávají 404. | Síťová chyba, HTTP chyba, vadný JSON payload, chybějící konfigurace a 404 testy. |
| P1 | Formulář a akce mají oddělené jmenné prostory; stejný slug mohl ukázat metadata jiného objektu. | Dvouargumentový RPC kontrakt vybírá `form` nebo `event`; původní jednoargumentový kontrakt zůstává podporovaný. | Skutečná databázová fixture s kolizí obou jmenných prostorů. |
| P2 | Nativní stránka akce ze sitemap měla pouze obecný Flutter shell. | První HTML obsahuje konkrétní nadpis, popis a existující datum. Bez JavaScriptu lze obsah přečíst; po `festapp-app-ready` přebírá obrazovku aplikace. | Raw HTML test + oddělený browser check včetně vypnutého JS a mobilního viewportu. |
| P2 | Server a klient vybíraly jiný název, popis a obrázek. | Jedna normalizace `public_page_seo.js`, stejné SEO údaje v otevřeném i zavřeném form bundle, bez dalšího síťového požadavku. | Test skutečného FormModel + PostgreSQL open/closed bundle. |
| P2 | Twitter metadata mohla existovat současně v `name` i `property` variantě. | Klient přijme oba staré zápisy a udržuje jediný `name` tag. | Klientský test přechodů mezi formuláři. |

Při revizi byly opraveny i nalezené implementační chyby: SEO pole bylo nejprve
přidáno do modelu pole místo do FormModel; nynější test konstruuje skutečný
FormModel. Úvodní HTML se odstraňuje při převzetí formulářové obrazovky i pro
přehled objednávky, čekací listinu a chybové stavy. Flutter čeká na skutečnou
připravenost aplikace, nikoli jen první rámec enginu. Bez JS se pevný loader
schová přes `noscript`, aby nepřekrýval veřejný text.

Nezavádí se nová politika viditelnosti akcí. RPC nadále poskytuje pouze veřejná
metadata známého odkazu; není to seznam všech akcí. Žádná zákaznická jména,
objednávky, platební údaje nebo přístupové tokeny se do SEO projekce nepřidávají.
Dřívější pravidla katalogu určují, které akce se dostanou do seznamu a sitemap.

### Obsahový záměr a další rozvoj

| Stránka / oblast | Záměr návštěvníka | Co má odpověď doložit |
| --- | --- | --- |
| `/` | Pořadatel hledá řešení pro prodej vstupenek na svou akci. | Jak založí akci, připraví plánek, nabídne vstupenky, přijme platbu a odbaví hosty. Stávající reálné ukázky tyto kroky dokládají. |
| `/events` | Návštěvník hledá akci a chce koupit vstupenku. | Konkrétní akce, srozumitelné názvy a správný přechod na formulář či program. |
| `/form/<uložený-odkaz>` | Zájemce o konkrétní akci chce výběr míst a nákup. | Název formuláře, údaje od pořadatele, aktuální možnosti nákupu; stabilní canonical. |
| `/<uložený-odkaz>/event` | Návštěvník hledá konkrétní událost nebo její program. | Skutečný název, popis a datum, přístupné ještě před spuštěním aplikace. |

„Prodej vstupenek“, „vstupenkový systém“, „vstupenky na ples“ a „plánek sálu“
jsou pracovní tematické hypotézy podle produktu, nikoli naměřené objemy hledání.
Bez Search Console a výzkumu dotazů není podložené vytvářet desítky městských
nebo téměř totožných landing pages. Další stránku má smysl přidat až pro
samostatný záměr a s konkrétní užitečnou odpovědí, například podrobný průvodce
přípravou prodeje na ples. Existující hlavička i odkazy na reálné reference
zůstávají zachované.

### Strukturovaná data a náhledy

Nerozšiřujeme schéma jen kvůli počtu typů. Pro události nepřidáváme `Event`
rich-result markup bez všech potřebných skutečných údajů, zejména místa konání.
Při přepnutí z katalogu na konkrétní akci edge odstraní starý katalogový JSON-LD,
aby nepopisoval jiný obsah. Žádné vymyšlené vstupné, dostupnost, recenze nebo
výchozí datum. Obsahové tvrzení musí být viditelné i návštěvníkovi.

Vybraná varianta 1 zůstává:

- Titulek: **Prodej vstupenek na akce | vstupenky.online**
- Popis: **Prodávejte vstupenky pro Vaši akci. Vlastní plánek sálu, výběr míst, QR platby bez transakčních poplatků a odbavení telefonem.**

Další varianty jsou pouze v offline srovnání, nikoli souběžně publikované nebo
náhodně rotované. Šířkové náhledy pomáhají posoudit čitelnost; Google může text
přepsat podle dotazu a zařízení. Pevný počet znaků není zárukou zobrazení celého
textu. Sociální karta má vlastní skutečný obrázek 1200 x 630 a popis obrázku.

### Ověření a pořadí vydání

Druhá revize: 18 cílených Worker/generator testů a 3 klientské SEO testy prošly.
Databázový test běžel na skutečném PostgreSQL v nově vytvořené databázi se
zkopírovaným schématem lokálního testovacího serveru. Ověřil instalaci připravené
migrace, rozlišení jmenných prostorů, oba aliasy, anonymní volání, neexistující
odkaz a SEO v otevřeném i zavřeném form bundle. Databáze byla odstraněna;
existující testovací ani produkční data nebyla upravována. Příprava izolované
kopie vyžadovala vynechat pg_cron z klonovaného schématu a použít lokální
administrátorskou roli; nejde o změnu produkčního nastavení.

Připravená definicová migrace:
`supabase/migrations/20261022225500_public_page_seo.sql`.
Pořadí je důležité: nejprve aktuální kanonické backendové závislosti a tato
migrace včetně obnovy PostgREST schema cache, teprve potom Worker a web client.
Původní klient může dál používat jednoargumentový RPC. Nový edge při chybějícím
backendovém kontraktu bezpečně vrátí dočasnou 503, nevydá chybnou úspěšnou stránku.
Migrace obsahuje úplné současné kanonické definice form bundle; při vydání musí
patřit ke stejnému backendovému reviznímu základu jako ostatní změny této větve.

Logy lokálních kontrol:
`/tmp/festapp-seo-deep-tests.log`, `/tmp/festapp-seo-client-tests.log`,
`/tmp/festapp-seo-db-check.log`, `/tmp/festapp-seo-browser-check.log`.
Raw SSR HTML a browser receipt jsou v lokálním `seo-review` vedle náhledu
výsledků vyhledávání. Jde o řízené fixture odpovědi skutečného Worker handleru,
nikoli tvrzení, že produkce už tuto verzi doručuje.

### Co ověřit po skutečném nasazení

1. Kořen, `/events`, starý marketingový odkaz, konkrétní formulář, jeho alias,
   konkrétní nativní akci, skutečnou 404 a hlavičky HTTP. Canonical musí souhlasit
   v prvním HTML i po spuštění aplikace. Nepřepisovat funkční privátní deep links.
2. Živé robots a sitemap, doručení sdílecího obrázku a vykreslená strukturovaná
   data. Soubory v repozitáři nejsou důkazem skutečné edge odpovědi.
3. Search Console: ověřená property, odeslání sitemap, URL inspection reprezentativních
   URL, zvolená canonical, index coverage a případné blokace. Následně sledovat
   dotazy, imprese a CTR odděleně pro pořadatele a kupující.
4. Core Web Vitals z reálných dat; lokální screenshot ani přítomnost malého JPEG
   nepotvrzuje dobré LCP, INP nebo CLS. Na základě důkazů řešit případné problémy
   s fonty, videi a rozvržením, ne provádět neověřený plošný přepis výkonu.

Tato práce neodeslala žádost o indexaci a nezměnila produkční infrastrukturu.
Výsledek je připravený lokální kód, obsah a ověřené kontrakty, nikoli záruka
pořadí ve vyhledávání.

Další primární podklady:
[JavaScript SEO](https://developers.google.com/search/docs/crawling-indexing/javascript/javascript-seo-basics),
[Event structured data](https://developers.google.com/search/docs/appearance/structured-data/event).

Závěrečná nezávislá kontrola: bez zbývajících blokujících nálezů v této revizi.
Browser receipt `seo-review/deep-review.json` potvrzuje čitelný mobilní obsah
s vypnutým JavaScriptem, skrytý loader a odstranění souhrnu teprve po skutečné
připravenosti aplikace. Bez nasazení a bez zápisů do produkce.


## Příprava autorizovaného produkčního vydání

Uživatel následně schválil implementaci a nasazení pouze vstupenky.online.
Release se skládá v odděleném worktree nad aktuálním kanonickým main; z původní
rozpracované větve se nepřenášejí staré verze CSP, oprávnění, demo ochrany,
soukromých odkazů ani katalogu pořadatelů. Landing page je zapnutá pouze pro
přesnou doménu vstupenky.online, ostatní tenanty zachovávají svůj katalog a jejich
build neobsahuje marketingová média. Žádný jiný tenant se nenasazuje.

Na výslovné upřesnění uživatele všechna tlačítka založení akce vedou přímo na
`/login`. Starší `create=1` odkazy se přesměrují tamtéž a zachovají ostatní
query parametry. Registrace se automaticky neotevírá.

Google přihlášení používá stávající vlastní OIDC broker. Read-only ověření
kanonického backendu potvrdilo povolení pro organizaci 3, registraci přesných
webových i Flutter callback adres a živou capability odpověď `enabled: true`.
Samostatný Google provider Supabase se nezapíná. Kontrola neprovedla přihlášení
konkrétního uživatele.

Původně zvolený timestamp 20261022210000 je v živém ledgeru již použitý jinou
migrací `setup_email_preview_payment_context`. SEO má proto vlastní ověřeně
volnou verzi 20261022225500. Historicky pojmenovaný hostname/databáze obsahující
„rehearsal“ není důvod měnit cíl: potvrzený runtime veřejný origin je
api.festapp.net a odpovídá aktivaci tenant festapptickets, generation 1, org 3.
