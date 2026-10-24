# WordPress: od lokálního prostředí po veřejný plugin

Datum: 2026-10-23  
Stav: český i globální plugin a oba lokální distribuční balíčky implementovány a ověřeny; veřejné podání a vydání neprovedeny, otevřené brány v integrations/wordpress/READINESS.md  
Ověřování implementace: standard - veřejný integrační kontrakt a práce s nedůvěryhodným vstupem

## Aktuální rozšíření podle výslovného pokynu uživatele

Uživatel po dokončení české etapy výslovně zadal také globální doplněk pro
**tickets.festapp.net** s maximem sdíleného kódu. Toto novější rozhodnutí
nahrazuje omezení první etapy na jediný produkt níže. Obě distribuce 1.0.0
jsou implementované z `integrations/wordpress/shared/` a `products.json`,
samostatně instalovatelné i současně aktivovatelné. Konkrétní ZIPy, hashe,
skutečné průchody a limity uvádí `integrations/wordpress/READINESS.md`.
Registrace od nuly je ověřena lokálně, nalezené opravy služby nejsou nasazené.
Veřejné podání a vydání obou produktů jsou připravené ke schválení, nic
nebylo odesláno, publikováno ani pushnuto. Následující omezení první etapy
zůstává historickým záznamem tehdejšího zadání, ne aktuálním zákazem.

## Historický závazný rozsah první etapy

Poslední rozhodnutí uživatele: nyní implementovat pouze **vstupenky.online**.
Tato část má přednost před níže zachovaným dlouhodobým návrhem dvou produktů.
Festapp Tickets je budoucí samostatný projekt, v této etapě bez implementace.

- Vlny 0-6 provést pouze pro `vstupenky-online`: jeden plugin, jeden blok,
  shortcode `[vstupenky_online url="…"]`, jeden ZIP a jedny katalogové podklady.
- Vytvořit pouze `integrations/wordpress/vstupenky-online/` a potřebné nástroje,
  testy a dokumentaci. Nevytvářet globální bootstrap, globální testovací tenant,
  manifest, ZIP, katalogovou stránku nebo druhý SVN release.
- Níže popsané dvě distribuce, společné buildové zdroje, produktové manifesty
  a současná aktivace obou pluginů platí až pro budoucí etapu Festapp Tickets.
  Nyní nevytvářet `shared/`, `products/`, generátor variant ani brand switch.
  Renderer a validaci organizovat jako běžné interní moduly českého pluginu;
  sdílenou knihovnu extrahovat teprve při skutečné implementaci druhého produktu.
- Seed a kompatibilitní matice pokrývají český plugin. Česky vytvořit onboarding
  a návody; připravit standardní překladatelnost a anglické katalogové readme
  pro review. Anglické texty nevytvářejí globální produkt.
- Produkční povolené hosty ověřit pouze pro vstupenky.online. Žádná závislost
  na rozhodnutí o globální doméně, zahraničních platbách nebo globálním účtu.
- Aktuální dokončení: lokální WP, funkční český plugin, doložené kontroly,
  distribuční ZIP s hashem a připravené podklady pro katalog. Veřejné podání,
  komunikace reviewerům a vydání jsou následné samostatně autorizované kroky.
- Závěrečnou definici dokončení a všechny formulace „oba produkty“ v tomto
  dokumentu vyhodnocovat v první etapě jen pro vstupenky.online. Nevydávat
  budoucí globální distribuci za rozpracovanou část právě autorizované úlohy.

## Doplnění první etapy: účty, skutečné ověření a rychlost

Tato část zpřesňuje první etapu podle posledního požadavku uživatele a má
přednost před obecnými formulacemi níže.

### Tři oddělené identity a oprávnění

1. **Správce lokálního WordPressu:** vytvořit a ověřit přihlášení do vlastní
   testovací instalace, instalaci ZIP, aktivaci a publikaci stránky přes editor.
   Je to jiný účet než WordPress.org; placený WordPress.com není potřeba.
2. **Pořadatel vstupenky.online:** projít registraci/přihlášení, vytvoření nebo
   otevření syntetické akce, uložení formuláře a získání jeho veřejného odkazu.
   Reálné objednávky testovat pouze v disposable prostředí se skutečnými RPC.
   Nedostupnost izolovaného prostředí není důvod k vytvoření produkčních objednávek.
3. **WordPress.org vydavatel:** ověřit existenci správného účtu, přihlášení,
   vlastnictví značky, kontaktní email, 2FA a dostupnost submission formuláře.
   Uživatelský souhlas nyní zahrnuje přihlášení a přípravu registrace účtu,
   případně dokončení registrace při dostupné potvrzené identitě a emailu.
   Nevytvářet duplicitní účet. Bez potvrzeného vlastníka, emailu, hesla nebo
   požadovaného 2FA předat přesně jeden nezbytný interaktivní krok uživateli;
   jinou nezávislou práci dokončit. Netvrdit, že přístupy již existují.

Pro oficiální plugin doložit vztah účtu ke vstupenky.online; osobní účet bez
prokazatelného vztahu může vyžadovat vyřešení identity před podáním. Doménový
email nedoplňovat odhadem. Před případným prvním vydáním připravit oddělený
SVN přístup dle WordPress.org pravidel, bez vyzrazení hesel nebo recovery kódů.
Účet, 2FA ani bezpečnostní nastavení neměnit bez výslovné potřeby; nastavení
nového autentikátoru a úschovu recovery kódů provádí vlastník.

Pracovat v izolovaném browseru, neovládat stávající uživatelovy taby. Pokud je
nutné ruční přihlášení, domluvit konkrétní krok; nevyžadovat heslo ve zprávě.
Do záznamů ukládat stav ověření a případnou referenci bezpečného uložení,
ne samotné přihlašovací údaje.

### Přijímací matice skutečného produktu

Ke každé položce evidovat PASS / FAIL / BLOCKED / NOT RUN, revizi, prostředí,
verzi a stručný důkaz. Simulace a reálný průchod musejí být rozlišené.

| Průchod | Co musí prokázat |
|---|---|
| Čistá instalace výsledného ZIP | Žádná závislost na zdrojovém checkoutu nebo vývojových nástrojích |
| Správce WP -> blok/shortcode -> publikace | Skutečný editor a uložený frontend, ne ručně vložený mock HTML |
| Registrace/přihlášení pořadatele -> uložený formulář | Pořadatel opravdu získá veřejnou URL a vloží ji do WP |
| Nepřihlášený návštěvník | Bez účtu WP koupí vstupenku; případné požadavky služby jsou popsány |
| Objednávka přes WP iframe | Skutečná uložená objednávka, správná cena a změna kapacity |
| Výběr sedadla | Správně rezervované sedadlo; opakovaný pokus nevydá duplicitní objednávku |
| Potvrzení a vstupenka | Kanonická email fronta a výstup do lokálního sinku nebo zachycení; platný PDF/QR podle skutečného stavu objednávky |
| Odbavení | Skutečná serverová kontrola QR a očekávané odmítnutí opakovaného vstupu, kde to typ vstupenky vyžaduje |
| Selhání a soukromí | Nedostupný backend/helper, blokované úložiště, izolace osobních URL a oprávnění |
| Kompatibilita | Deklarované WP/PHP, bloková/klasická šablona, mobil, klávesnice, více iframe |
| Životní cyklus | Deaktivace/aktivace, uninstall, zachování objednávek služby; update při existenci předchozí verze |
| WordPress.org účet | Ověřené přihlášení a stav předpokladů podání, nikoli jen URL přihlašovací stránky |

PDF, email a odbavení ověřovat přes existující Festapp mechanismy, nevytvářet
jejich WP kopie. Lokální sink nesmí obejít kanonickou `public.email_messages`
frontu; není důkazem doručitelnosti produkčního emailu. Test platební větve
provést bez skutečné transakce, s existujícím sandboxem nebo podporovaným
lokálním potvrzením bankovní platby. Konkrétní platební metodu neuvádět jako
podporovanou, dokud její odpovídající průchod neprojde. Safari/iOS vyžaduje
skutečně odpovídající browser; mobilní viewport Chromium tuto položku nesplňuje.

Před submission musí být zelené všechny kritické scénáře deklarovaného rozsahu.
Nepovinnou/nepodporovanou metodu výslovně vyřadit z nabídky. Pokud kritický
průchod blokuje chyba služby, opravit jen nezbytnou lokální příčinu a znovu
ověřit dotčené chování; neprovádět neautorizovanou produkční opravu. Nepublikovat
nefunkční wrapper, sandbox-only produkt ani balíček s kritickým NOT RUN/BLOCKED.

### Efektivní provedení

Jednou načíst relevantní podklady, pak implementovat ucelený plugin. Nezakládat
obecný framework, druhý produkt nebo rozsáhlé testovací zázemí. Přednostně využít
existující runtime, fixture a platné důkazy se shodnými vstupy. Účty a podklady
řešit včas, zatímco lze pokračovat v nezávislém vývoji. Nezávislé levné kontroly
seskupit do jedné dávky; těžké úlohy a Flutter slot držet sekvenčně. Přesné cílené
kontroly spouštět nad ucelenými změnami a opakovat jen při změně vstupů či chybě.
Žádný repo-wide build, opakované celé audity nebo zbytečné čekání na externí review.

Odevzdat `integrations/wordpress/READINESS.md` s přijímací maticí, stavem všech
účtů bez tajných údajů, hashem ZIP a konkrétními zbývajícími kroky. Veřejné
podání, zprávy reviewerům, staging a publikace zůstávají oddělené kroky:
nejdříve dodat ověřený reviewovatelný výsledek. Nežádat znovu o povolení
k běžnému přihlášení nebo lokálním testům, které uživatel právě autorizoval.

Aktualizované oficiální podklady:
- [Oficiální plugin, účet a připravenost balíčku](https://developer.wordpress.org/plugins/wordpress-org/plugin-developer-faq/).
- [2FA a SVN přístup](https://make.wordpress.org/meta/handbook/tutorials-guides/svn-access/).
- [Zabezpečení autorských účtů](https://make.wordpress.org/plugins/2024/09/04/upcoming-security-changes-for-plugin-and-theme-authors-on-wordpress-org/).

## Výsledek a pořadí investic

Pořadatel nainstaluje plugin své služby, vloží veřejný odkaz uloženého formuláře do bloku
nebo shortcode a zveřejní funkční prodej na svém webu. Plugin je dostupný přes
WordPress.org Plugin Directory, který je cílovým „storem“. Cílem jsou dva
samostatné produkty a dvě katalogové stránky. Schválení, publikace
a ověřená instalace z katalogu jsou tři různé milníky.

První investice: společný integrační základ a WordPress. Následně návody pro
vkládání do dalších CMS; Shoptet až po ověření konkrétní poptávky a podmínek
partnerství. WooCommerce košík, další marketplace aplikace a Make/Zapier jsou
samostatné navazující projekty. Tento plán je neimplementuje.

## Produkt a dvě značky

- **vstupenky.online:** český trh, česká prezentace, návody, reference a podpora.
- **Festapp Tickets:** evropský/mezinárodní trh; nejprve anglická prezentace
  a konkrétní země s ověřeným nákupem, platbami a podporou.
- **Rozhodnutí uživatele:** dva samostatné pluginy. Globální „Festapp Tickets“
  a český „vstupenky.online“ mají vlastní ZIP, identitu, katalogovou stránku,
  onboarding, kontakty, právní odkazy, screenshoty, changelog a vydávání.
  Nejde o přepínač značky nebo pouhý překlad jednoho katalogového produktu.
- Pracovní slugy `festapp-tickets` a `vstupenky-online` nejsou rezervované ani
  ověřené jako dostupné. Před podáním každého pluginu ověřit název, oprávnění
  značku používat a definitivní slug. Změnu promítnout konzistentně do příslušné
  hlavičky, adresáře, text domain, namespace, balíčku a dokumentace.
- Sdílet technické zdroje rendereru a validace, nikoli uživatelskou identitu.
  Každý ZIP obsahuje vlastní izolovaně namespacovanou kopii sestavenou z tohoto
  zdroje; žádný vyžadovaný třetí „core plugin“. Oba lze aktivovat současně.
- Konfigurace produktu určuje jeho službu, povolené hosty a obchodní nabídku.
  Jazyk WordPressu nemění produkt, účet, tenant ani platební konfiguraci.
- Dvě samostatné katalogové položky jsou cíl, nikoli předem garantované schválení.
  V review vysvětlit skutečné oddělení služeb a trhů; samotná změna loga není
  důkazem odlišného produktu. Pokud review požaduje úpravu, zaznamenat ji
  a vyřešit s vlastníkem, nesloučit produkty automaticky.
- Doménu Festapp Tickets neodvozovat z názvu. Přesné veřejné originy obou
  služeb musí být doloženy jejich aktuální konfigurací a dostupným formulářem.

## Rozsah první verze

Každý plugin má nativní Gutenberg blok a vlastní shortcode:
`[festapp_tickets url="…"]` nebo `[vstupenky_online url="…"]`. Součástí je
lokální informační stránka ve WordPress administraci, české a anglické texty,
automatická/pevná výška a odkaz na samostatný formulář. Blok i shortcode mají
společný zdroj PHP rendereru a validace, sestavený pro daný produkt.
Editor zobrazuje místní placeholder
a chyby konfigurace; cizí formulář se načítá na publikované stránce.

Nezahrnuje WooCommerce, vlastní platební bránu, správu akcí ve WordPressu,
kopírování objednávek/účastníků do WP databáze, katalog akcí, synchronizaci CMS,
OAuth ani API klíče. Správa událostí zůstává ve službě, odkazy vedou mimo WP
administraci. Plugin má fungovat bez WooCommerce a bez dalšího builder pluginu.

## Potvrzené podklady z repozitáře

Průzkum: pracovní větev `feat/occasion-setup-wizard-20261007`, HEAD `353394511`.
Strom obsahuje rozsáhlé souběžné změny. Tento údaj není release revizí ani
důkazem nasazení. Při implementaci zaznamenat aktuální zdroj a chránit cizí práci.

| Fakt | Podklad | Důsledek |
|---|---|---|
| Existuje veřejný embed kontrakt | `docs/integrations/embedded-checkout.md` | WordPress je adaptér, nikoli nový checkout |
| Generátor používá uložený slug, iframe, fallback a tenant `/embed.js` | `lib/components/forms/views/form_embed_code.dart`: `formEmbedCode` | Zachovat stejnou podobu veřejného vstupu |
| Host helper používá `data-festapp-embed` a protokol 1 | `web_client/public/embed.js` | Nepřejmenovat interní protokol podle obchodní značky |
| Child ověřuje parent a komunikuje resize/scroll | `web_client/src/services/embed_bridge.js`: `EmbedBridge` | Nevymýšlet druhý resize protokol |
| Embed je explicitní `embed=1` | `web_client/src/services/embed_context.js` | Neodvozovat režim z přítomnosti iframe |
| Existuje lokální fixture a protokolové testy | `web_client/tests/fixtures/embedded-checkout/`, `web_client/tests/core/embed.test.js` | Reálný nákup ověřovat přes existující službu |
| Karetní průchody nejsou garantované embed kontraktem | `docs/integrations/embedded-checkout.md` | Marketing nesmí tvrdit univerzální podporu plateb |

Tok: atribut bloku/shortcode -> společná validace veřejné URL -> serverový HTML
výstup -> stávající iframe -> `FormSession` / `DbOrders` / `send-ticket-order`.
Objednávky, kapacita, platby a emaily zůstávají ve stávajících vlastnících.

## Cílové invarianty

1. Ukládat pouze veřejný formulářový odkaz, prezentaci a volbu výšky. Nepřijímat
   osobní odkazy, capability fragmenty, tajné klíče nebo předvyplněné objednávky.
2. Produkční renderer přijímá pouze HTTPS, přesný povolený origin a veřejnou
   cestu `/form/<uložený-slug>`. Odmítnout userinfo, jiné porty, query,
   fragment, neplatné/nejednoznačné kódování a cesty mimo formulář. `embed=1`
   přidává renderer. Neplatné vstupy neopravovat na potenciálně jiný formulář.
3. Povolené originy pouze příslušné služby jsou součástí vydaného pluginu.
   Odkaz druhé služby odmítnout s vysvětlením, který plugin použít.
   Žádné wildcard subdomény,
   volná pole pro doménu ani serverové stahování uživatelem zadané URL.
   Lokální originy povolit pouze při `local`/`development` prostředí a explicitní
   konstantě v konfiguraci testovací instalace; nikdy přes veřejný atribut.
4. Escapovat HTML a URL správnými WP funkcemi. Cizí iframe a helper se nenačítá
   pouhou aktivací pluginu ani na jeho administrační stránce.
5. Použít dokumentovaný `/embed.js` příslušné služby, načíst jej nejvýše jednou
   pro každý použitý origin a jen na stránkách s automatickým embedem.
   Zachovat více instancí a žádný nový přenos osobních nebo platebních údajů.
6. Vyřešit renderer i pro sekundární smyčky/šablony: nespoléhat pouze na
   `has_shortcode` v hlavním příspěvku. Ověřit enqueue při skutečném renderu
   a dostupnost helperu ve výstupu před dokončením stránky.
7. Bez helperu zůstává funkční pevný iframe a samostatný odkaz. Nedostupnost
   služby nesmí způsobit PHP fatal error nebo automatické opakování nákupu.
8. Bez analytiky, sledovacích pixelů a externích fontů v první verzi.
   Informovat správce před prvním vložením o připojení služby a v readme uvést
   hosty, účel, předávaná data, podmínky a ochranu soukromí. Návštěvnické
   souhlasy posoudit podle skutečných cookies/úložišť služby; netvrdit automaticky
   „bez cookies“. Režim kliknutím načíst doplnit jen při doložené potřebě.
9. Nezavádět vzdálenou administraci v iframe, vlastní updater nebo skryté
   SEO odkazy. WordPress.org zásady pro frontend SaaS integraci výslovně doložit.

## Realizační vlny

### 0. Produktové a distribuční předpoklady

**Změny:** vytvořit `integrations/wordpress/README.md` s rozsahem, oběma značkami,
podporovanými hosty a tabulkou podporovaných způsobů nákupu/platby. Doložit
funkční službu, skutečné kontakty, podmínky a privacy stránky. Vybrat vlastníka
WordPress.org účtu a podpory, ověřit dostupnost obou názvů/slugů. Rozlišit skutečné
vlastnosti služeb od jejich marketingové prezentace. Zaznamenat aktuální
stabilní WP, podporované PHP a navržené minimum; neslibovat neotestované verze.

**Ověření a výstup:** konkrétní seznam URL a odpovědných osob, zvolený název
a minimální kompatibilita. Externí účet není potřeba pro zahájení lokálního vývoje.
Chybějící mezinárodní platby blokují příslušný obchodní příslib, nikoli český
vývoj. Sandbox-only službu neposílat jako hotový veřejný plugin.

### 1. Opakovatelné lokální WordPress prostředí

**Změny:** balíček nástrojů `integrations/wordpress/package.json`, autoritativní
`pnpm-lock.yaml` a `pnpm-workspace.yaml`, `.wp-env.json` a seed skript.
Pluginy patří do `integrations/wordpress/festapp-tickets/` a
`integrations/wordpress/vstupenky-online/`; společné zdroje do
`integrations/wordpress/shared/`, produktové manifesty do `products/`.
Použít lokálně připnuté `@wordpress/env`, Docker a WP-CLI; všechny JS příkazy
přes pnpm 11.24.0. Další instalace používají `pnpm install --frozen-lockfile`.
Při prvním vytvoření závislostí lockfile vygenerovat a uložit.

Před startem inventarizovat existující kontejnery/porty, přidělit vlastní
loopback port a ověřit skutečný bind na localhost. Nesdílet databázi se stávající
instalací. Seed vytvoří pro každý produkt blok, shortcode a stránku se dvěma
iframe, dále stránku s oběma produkty pro kontrolu jejich souběhu.
Použít syntetická data. Připravit aktuální stabilní WP/PHP a oddělenou konfiguraci
pro deklarované minimum; konkrétní verze připnout po zjištění ve vlně 0.

**Ověření:** z adresáře nástrojů `pnpm exec wp-env start`, poté
`pnpm exec wp-env run cli wp core version`. Čistý start, seed a instalace ZIP
musí být reprodukovatelné z README. Docker náklady nesmějí vést k zastavení
cizího prostředí. Reset/destroy jen pro vlastní identifikovaný projekt.

**Výstup:** samostatný lokální WP s přihlášením a testovacími stránkami,
zdokumentované start/stop. Veřejný staging není předpoklad vývoje. Žádný nový
Flutter task; při potřebě backendu použít samostatný lokální Festapp fixture.

### 2. Dva samostatné pluginy ze společného základu

**Změny:** samostatné bootstrapy `festapp-tickets.php` a `vstupenky-online.php`,
produktové manifesty a společné zdroje `includes/embed.php`, `includes/admin.php`,
bloku `blocks/ticket-form/` (`block.json`, editor JS), lokálního CSS a překladů.
Sestavení deterministicky vytvoří dva izolované distribuční adresáře. Prefixy
`festapp_tickets` a `vstupenky_online`, block names, script handles, option keys
a text domains se nesmějí střetnout. Výstupy ručně neupravovat.
PHP registruje vlastní blok a shortcode se společným zdrojovým rendererem.
WordPress poskytuje vlastní editor dependencies; nezabalovat druhý React.

Blok přijímá veřejnou URL, přístupný titulek, režim a omezenou pevnou výšku.
Editor vysvětlí neplatný odkaz. Frontend při neplatné konfiguraci nevygeneruje
cizí iframe; editor/správce dostane opravitelnou chybu. Úpravy nastavení chránit
capability a nonce, pokud se ukáže potřeba ukládat globální nastavení; ideálně
první verzi držet bez globálních zápisů. Žádné API požadavky z PHP.

**Ověření:** jednou po ucelené implementaci cílená PHP/WP sada pro validaci URL,
escaping, blok/shortcode a vícenásobné enqueue. Negativní případy zahrnují
podvržený hostname, nebezpečné schéma, lokální IP v produkci, osobní fragment,
uložený poškozený atribut a uživatele bez potřebných oprávnění. Ověřit lifecycle
aktivace/deaktivace a zacházení s případnými plugin options při uninstall.

**Výstup:** každý plugin samostatně i oba současně zobrazují svůj existující
checkout. Oprava společného zdroje se může vydat pro každý produkt zvlášť,
s doloženou verzí jádra a konfigurace. Žádné ručně udržované forky obchodních
pravidel. Blok i shortcode fungují bez změny obchodních
pravidel Festappu; instalace bez WooCommerce funguje. První verze nepřidává
tabulky ani migraci, takže nic z původního systému nemaže.

### 3. Reálný průchod a kompatibilita

**Změny:** `integrations/wordpress/tests/` a stručný záznam výsledků s přesnými
verzemi. Pro skutečné objednávky použít disposable tenant dle
`docs/integrations/embedded-checkout.md` a skillu `festapp-local-e2e`; žádné
produkční objednávky, poskytovatelské klíče nebo odesílání zákaznických emailů.
Placeholder backend slouží jen pro WP render testy a není důkazem nákupu.

**Ověření:** aktuální stabilní WP/PHP a deklarované minimum; standardní bloková
a klasická šablona; editor a frontend obou produktů, shortcode, dvě instance,
současná aktivace obou pluginů, odmítnutí URL opačné služby,
mobilní šířka, klávesnice, resize, pevná výška a fallback. Dokončit nákup
obyčejné vstupenky i rezervovaného sedadla, prokázat jedinou objednávku a obvyklé
chování při opakování po chybě. Ověřit nedostupnou službu a blokovaný helper.
Safari/iOS a blokované úložiště vést zvlášť s konkrétním výsledkem; emulace šířky
není důkaz Safari. Platební průchody přijímat odděleně podle matice z vlny 0.

Interaktivní kontrola přes agent-browser skill, izolovanou headless session,
primárně accessibility snapshoty; session po dokončení zavřít. Pro opakovatelné
CI testy využít existující podporovaný repository runner; pokud WP zatím runner
nemá, zavést dokumentovaný cílený příkaz, neobcházet stávající E2E brány.

**Výstup:** doložené scénáře a explicitní seznam neověřených prohlížečů/plateb.
Nevyřešenou kritickou chybu řešit před submission; nerozšiřovat scope na WooCommerce.

### 4. Balíček a připravenost pro WordPress.org

**Změny:** pro každý produkt vlastní `readme.txt`, GPL kompatibilní licence
(preferovat GPLv2-or-later),
changelog, instalace, požadavek na účet/službu, odkazy na sazby služby, podmínky,
privacy, kontakty, externí požadavky a známá omezení. Oddělit bezplatný plugin
od případně placené služby. Dostupné zdroje a reprodukovatelný build uvést
v readme. Vyplnit skutečné `Requires at least`, `Requires PHP`, `Tested up to`,
verzi a `Stable tag`. Nenavyšovat testovanou kompatibilitu bez ověření.

V `integrations/wordpress/scripts/` přidat balení a release přípravu s explicitní
volbou produktu. Výstupem jsou dva samostatné ZIP soubory. Každý ZIP
obsahuje jediný adresář pluginu, ne node_modules, Docker, testovací účty, fixture
nebo tajné údaje. `store-assets/` připraví ikonu, banner a snímky editoru,
mobilního formuláře a sedadel. Katalogové obrázky se při publikaci kopírují
do kořenového SVN `assets/`, nikoli do distribuovaného pluginu.

**Ověření:** PHP syntaxe, WordPress Coding Standards relevantní pro plugin,
oficiální Plugin Check včetně runtime kontrol a instalace výsledného ZIP do
čistého WP. Pro Plugin Check použít UI nebo aktuálně dokumentované CLI s runtime
bootstrapem; výchozí statický CLI běh nevydávat za runtime check. Chyby odstranit,
varování konkrétně vyhodnotit. Zkontrolovat balíček a shodu hlavičky/readme/tagu.

**Výstup:** pro každý produkt konkrétní ZIP, hash, vlastní katalogové podklady
a přehled výsledků připravené
ke kontrole. Úspěch Plugin Check není příslib schválení.

### 5. Odeslání a komunikace s review týmem

Oba produkty lze připravovat lokálně souběžně; podání do katalogu plánovat
postupně. Aktuální FAQ obecně dovoluje jednu otevřenou submission na autora;
neobcházet limit dalšími účty. Doporučené pořadí je český plugin pro ověřený
český pilot, poté globální po ověření jeho služby a plateb. Vlastník může pořadí
změnit podle skutečné připravenosti; neslučovat kvůli tomu produktové identity.

Po autorizaci externího podání konkrétního produktu vlastník použije svůj WordPress.org účet,
ověří jeho zabezpečení dle aktuálních požadavků a odešle finální ZIP přes
`https://wordpress.org/plugins/developers/add/`. Uchovat verzi, hash a datum.
Submission popíše skutečnou službu správy akcí, registrací a odbavení, ne pouhý
obchodní odkaz. Nepoužívat iframe pro vzdálenou administraci ve WP dashboardu.

Připravit návod pro reviewer: registrace/testovací přístup, veřejný ukázkový
formulář a popis externího helperu. Přístupy nedávat do veřejného readme ani
repozitáře. Potřebný veřejný demo tenant/staging zřídit jako samostatně schválený
provozní krok; místní vývojový WP s výchozím heslem nezpřístupňovat internetu.

Připomínky evidovat, opravit, cíleně přetestovat a odpovědět v existujícím vlákně.
Nezakládat duplicitní submission. Doba review je externí a proměnlivá; nelze ji
zahrnout do garantovaného data vydání. Zprávy reviewerům neodesílat bez výslovné
autorizace. Výstupem vlny je schválení nebo přesný otevřený požadavek review.

### 6. První veřejné vydání a údržba

Pro každý produkt po schválení získat jeho přidělený SVN repozitář.
Git zůstává zdroj společného vývoje, SVN slouží
distribuci. Připravit z ověřené revize `trunk/`, neměnný `tags/<verze>/`
a katalogové `assets/` pro explicitně vybraný produkt; nejprve prohlédnout SVN
diff a vazbu `Stable tag`. Vydání jednoho produktu nespouští vydání druhého.
Přístupové údaje řešit přes aktuálně podporovaný SVN mechanismus WordPress.org,
nikdy je nevypisovat nebo ukládat do skriptů. Samotný SVN commit je veřejné vydání
a vyžaduje autoritu k publikaci. Žádné automatické vydání při běžném pushi main.

**Ověření:** veřejná katalogová stránka, stažení a instalace katalogového balíčku
do čistého WP, shoda verze a funkční blok. Při dalším vydání ověřit aktualizaci
ze skutečné předchozí verze se zachováním uložených bloků a shortcode.
Změna helperu služby musí dál zachovat embed protokol 1.

**Výstup:** instalovatelný veřejný plugin a funkční podpora. Pro chybu publikovat
opravenou novou verzi, nepřepisovat starý tag a nespoléhat na automatický downgrade.
Deaktivace pluginu nemaže objednávky služby; stránka může ukázat nezpracovaný
shortcode, což vysvětlit v odinstalačním návodu.

## SEO a distribuce po funkčním pilotu

Připravit samostatnou českou a anglickou integrační stránku odpovídající značce,
ukázku, návod a případovou studii. Získat malou sadu pilotních pořadatelů
a tvůrců webů pro oba směry. Sledovat instalace dostupné z katalogu a obchodní
konverze na vlastních webech; nepřidávat kvůli tomu skrytou telemetrii do pluginu.
Nedělat plošné SEO odkazy ve widgetu. Event schema, import akcí do WP a seznam
akcí jsou další samostatná vlna, první formulář je neslibuje.

## Zbývající rozhodnutí a provozní hranice

| Bod | Kdo a kdy jej uzavře | Důsledek do uzavření |
|---|---|---|
| Definitivní název a slug | Vlastník produktu, vlna 0 před submission | Pracovní názvy lze lokálně změnit |
| Přesné Festapp hosty, kontakty a právní URL | Vlastník služby + implementátor, vlna 0 | Nevydávat vymyšlené odkazy |
| Stav nákupů/plateb pro jednotlivé země | Vlastník služby, před zahraničním pilotem | Neslibovat globální platební podporu |
| WP/PHP minimum | Implementátor, vlna 0-1 | Teprve potom vyplnit hlavičky a matici |
| WordPress.org účet a dlouhodobá podpora | Vlastník produktu, před submission | Neomezuje lokální vývoj |
| Veřejný demo tenant, externí podání a vydání | Vlastník produktu, vlna 5-6 | Připravit reviewovatelný balík, nepublikovat automaticky |

Následným execution promptem a požadavkem uživatele byla autorizována a provedena
lokální implementace českého pluginu, účty a testování. Produkční změny, commit/push,
veřejné podání, zprávy reviewerům a publikace nadále vyžadují následnou autoritu
nad konkrétním výsledkem. Přesný stav implementace a otevřené brány jsou v
[READINESS](../../integrations/wordpress/READINESS.md).

## Zdroje a omezení závěrů

Oficiální podklady ověřeny 2026-10-23; před submission a vydáním znovu ověřit
změněné požadavky. Schválení frontend SaaS pluginu zůstává rozhodnutím reviewerů.
Není zde odstranění staré implementace: stávající ruční embed zůstává podporovanou
veřejnou cestou a plugin je pouze nový adaptér.

- [Plugin guidelines](https://developer.wordpress.org/plugins/wordpress-org/detailed-plugin-guidelines/): licence, SaaS, externí spojení, zdroje a administrace.
- [wp-env](https://developer.wordpress.org/block-editor/reference-guides/packages/packages-env/): lokální prostředí a konfigurace.
- [Plugin Check](https://wordpress.org/plugins/plugin-check/): automatické kontroly a jejich limity.
- [Submission](https://wordpress.org/plugins/developers/add/): podání a ruční review.
- [Developer FAQ](https://developer.wordpress.org/plugins/wordpress-org/plugin-developer-faq/): slug, review a zveřejnění.
- [SVN](https://developer.wordpress.org/plugins/wordpress-org/how-to-use-subversion/): přístupy a struktura vydání.
- [Katalogové assets](https://developer.wordpress.org/plugins/wordpress-org/plugin-assets/): umístění a formáty grafiky.

## Definice dokončení

- Lokální WP lze opakovatelně vytvořit a bezpečně ukončit bez zásahu do cizích služeb.
- Dva samostatné pluginy mají oddělené identity, ZIP, katalogové podklady,
  podporu a vydávání; využívají jeden společný zdroj rendereru a existující checkout.
- Oba fungují samostatně i při současné aktivaci a nepřijímají URL opačné služby.
- Bezpečnostní, kompatibilitní a reálné nákupní kontroly mají doložené výsledky.
- ZIP, zdroje, dokumentace, licence, podpora a katalogová grafika jsou připravené.
- Externí milníky jsou pro každý produkt evidovány samostatně:
  odesláno / schváleno / publikováno /
  instalace z katalogu ověřena. Dokud některý chybí, celá distribuce není hotová.


## Realizace 2026-10-23

První etapa existuje v `integrations/wordpress/`: jediný český plugin,
Gutenberg/shortcode, český onboarding a anglické readme/překlad, připnutý wp-env,
reprodukovatelná disposable konfigurace, distribuční ZIP a offline SVN návrh.
Autoritativní přijímací matice a hash jsou v
[READINESS](../../integrations/wordpress/READINESS.md); restart, cleanup a přesné
příkazy v [README](../../integrations/wordpress/README.md).

Změněné faktické předpoklady: aktuální kanonická baseline je
`20260906140000`, nikoli dřívější snapshot z runbooku. Vlastní backend běžel
na 59821/59822, checkout na 59801, WordPress na 59811/59812; existující
projekty nebyly resetovány. WP 7.1.3/PHP 8.5.12 a minimum WP 6.6.4/PHP 7.4.33
byly skutečně spuštěny. Produkční origin je přesně `https://vstupenky.online`.
Původní embed fixture potřebovala doplnění lokálního bankovního popisu,
rezervace odkazu akce, rolí prefixovaného seed účtu a scope produktu. Tyto opravy
nejsou produkční migrací ani změnou autority nákupu. Bundled Chromium 151 měl
poruchu Gutenberg blob iframe; skutečný editor byl ověřen v Chrome 155.

Prošly skutečné anonymní objednávky běžné vstupenky i sedadla přes WP,
verzovaný save i skutečný UI Save formuláře, lokální potvrzení platby,
kanonická email fronta s capture, skutečné PDF/QR a první/druhý vstup.
Prošel také skutečný výpadek vlastního gateway se zakázaným úložištěm a
stejnou command identitou při opakování. Následně prošel i skutečný Mobile
Safari 26.5/iOS 26.5: běžná vstupenka, sedadlo A2, outage/retry [0,0,200] se
stejnou command/client identitou, blokované storage a právě dvě nové objednávky.
Obě prošly potvrzením, kanonickou email frontou, skutečným PDF/QR a odbavením.
Safari stáhlo kanonickou PDF přílohu z lokálního capture sinku a zobrazilo ji
v nativním PDF preview; Vision dekódoval její QR také ze Safari screenshotu.
Apple WebDriver session se musí vytvořit až po dokončení simctl bootstatus;
nefunkční agent-browser iOS wrapper byl nahrazen přímým nativním driverem,
bez mocku business logiky a bez otevírání uživatelových oken.

Uživatel potvrdil kontakt `info@festapp.net` a autorizoval dokončení účtu
`festappnet`, následně výslovně povolil i nastavení 2FA agentem. Ověřena byla
skutečná session, potvrzený account email, profil vstupenky.online a nové
izolované přihlášení heslem + TOTP. Heslo, autentikátor a nové recovery kódy jsou
uloženy v místní login Klíčence. Submission formulář je dostupný a nebylo zjištěno
čekající podání. Přidělený SVN repozitář a SVN credentials jsou následný krok
po schválení pluginu, ne hotová publikace. Žádný další účet nevznikl.

Výsledek je připraven ke schválení **podání konkrétního ZIP** s hashem v READINESS.
Nic nebylo podáno, schváleno katalogem nebo publikováno. Veřejné vydání po review
nadále vyžaduje příslušnou samostatnou autoritu.

Dodatečný testerský průchod na žádost vlastníka: 74 nových assertions na obou
WP/PHP sestavách a skutečná publikace/obnova v minimálním Gutenbergu prošly.
Opraven byl automatický update disposable WP core a zarovnání lokální DB při
seedu. Plugin ani ZIP se nezměnily. Podrobný důkaz je v
`integrations/wordpress/evidence/tester-review.json`; veřejné podání neproběhlo.
