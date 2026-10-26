# Co je nového / What's new - společné aktualizace platformy

Datum: 2026-10-26
Stav: implementováno; připravuje se začlenění a autorizované vydání pro vstupenky.online
Ověřování implementace: standard (veřejné URL, sdílené sestavení a routování)

## Výsledek a rozsah

Pořadatel najde přehled změn platformy pod názvem „Co je nového“ / „What's new“.
Krátké záznamy vysvětlují nové funkce, vylepšení a důležité opravy: co se změnilo,
proč se to hodí a kde funkci najít. Nemusí jít o dlouhé články ani technické release notes.
Každý záznam má trvalý odkaz a český i anglický text nad jednou společnou identitou.
Stejná data budou použitelná pro upozornění; tato implementace nic nerozesílá.

Součástí první verze je veřejný přehled, detail, odkazy z webu a administrace a veřejný JSON přehled. Obsah se spravuje
v repozitáři a publikuje s webem. Editor v administraci, databázové tabulky,
automatické překlady, push/e-mail rozesílání, nepřečtené badge, RSS a vyhledávání
nejsou součástí. Nevzniká nový obecný CMS.

Tento dokument autorizuje pouze plán. Neautorizuje implementaci, commit/push,
produkční nasazení, změnu DNS ani zprávy uživatelům.

## Výchozí fakta

Průzkum popisuje lokální pracovní strom `feat/occasion-setup-wizard-20261007`,
HEAD `353394511`, s rozsáhlými souběžnými změnami. Není důkazem produkčního stavu.
Při implementaci zachovat cizí změny a znovu ověřit pouze dotčené kontrakty.

| Fakt | Podklad | Důsledek |
| --- | --- | --- |
| Veřejné stránky už mají renderer, explicitní profil a manifest URL. | `automation/release/render_organizer_page.mjs`, `organizers/context.mjs`, `organizers/profiles.json` | Rozšířit existující pipeline, nekopírovat web pro druhý jazyk. |
| Registr témat dnes přijímá jen kořen a jednosegmentové cesty; témata vyžadují kroky a FAQ. | `organizers/page_definitions.mjs: resolvePages` | Aktualizace potřebují vlastní typ stránky a omezenou validaci cest, nikoli předstírání marketingového tématu. |
| Edge routing, sitemap, ověření a offline chování už sdílejí seznam veřejných stránek. | `automation/cloudflare_build.sh`, `automation/lib/pwa_shell_manifest.mjs`, `automation/verify_web_build.mjs`, `automation/verify_web_deployment.mjs` | Nové URL musí být registrované ve všech těchto výstupech z jednoho rozlišeného kontextu. |
| Aktivní konfigurace má český marketingový profil a jazyky cs,en. | `automation/project.conf`, `organizers/profiles.json` | Oba překlady lze nabídnout na současném hostu bez zřízení nového tenantu. |
| Skutečný anglický profil v aktuálním registru není; testuje se syntetická anglická fixture. | `organizers/README.md`, `organizer_context.test.mjs`; navazující `tickets-festapp-en-plan-2026-10-23.md` | Nepovažovat tickets.festapp.net za připravený produkční cíl. |
| Stávající news jsou vázané na occasion; push sestavuje cestu do akce. | `lib/components/news/db_news.dart`, `database/functions/news/publish_news_client_sync_v1.sql`, `supabase/functions/notify/notificationPayload.ts` | Nepoužít eventové novinky jako úložiště globálních změn ani předpokládat podporu libovolného odkazu v push. |
| Centrum upozornění je soukromá provozní projekce s vlastními právy a retencí. | `database/functions/notification_center/README.md` | Veřejný archiv musí existovat nezávisle na osobních upozorněních. |

Současný tok: tenant config -> marketingový kontext -> renderer/manifest ->
web bundle -> Worker a service worker. Cílový tok přidá jeden zdroj aktualizací
do stejného sestavení; HTML a JSON jsou odvozené výstupy, nikoli další zdroje obsahu.

## Cílový kontrakt

### Zdroj a publikování

Navržené umístění: `content/platform-updates/<id>/meta.json`, `cs.md`, `en.md`.
Společný modul `automation/release/platform_updates/context.mjs` vlastní validaci,
řazení, výběr publikovaných položek a generování URL. Markup renderer nesmí
znovu rozhodovat o dostupnosti nebo publikaci.

Metadata obsahují neměnné `id` (malá ASCII písmena, číslice, pomlčky),
`status` (`draft`/`published`), explicitní `publishedAt` (UTC ISO instant),
volitelné `updatedAt`, `kind` (`feature`/`improvement`/`fix`) a pro každý jazyk
`title` a `summary`. Tělo je v odpovídajícím Markdown souboru. Identifikátor je
současně stabilní segment URL, nezávislý na titulku; další jazykové slugy se nezavádějí.

Publikovaná položka vyžaduje oba kompletní překlady. Draft může být neúplný,
ale nesmí proniknout do HTML, JSON, sitemap ani seznamu offline prostředků.
Publikace s budoucím datem selže s vysvětlením; plánované publikování se nezavádí.
Řazení je `publishedAt` sestupně a při shodě `id` vzestupně. Oprava textu nemění
identitu ani původní datum a sama nevytváří událost k rozeslání.

### URL a jazyky

- Český přehled: `/co-je-nove`; detail: `/co-je-nove/<id>`.
- Anglický přehled na současném hostu: `/en/whats-new`; detail: `/en/whats-new/<id>`.
- Explicitní jazyk v URL má přednost před prohlížečem a přihlášeným účtem.
- Samostatný přepínač English/Česky se nezobrazuje. Vstup z marketingu používá
  jazyk profilu jako homepage; vstup z administrace společný jazyk aplikace.
  Obě jazykové URL a SEO hreflang zůstávají dostupné nad stejným ID.
- Každá jazyková stránka má vlastní absolutní canonical, vzájemné `hreflang`
  cs/en a odpovídající HTML lang, title, description a OG metadata.
- Neznámé ID nebo nepodporovaná jazyková cesta vrací skutečné 404.
  Koncové lomítko přesměrovat 308 na jediný registrovaný tvar; zachovat query.
- Nepřesměrovávat automaticky podle IP, cookies ani Accept-Language.

Jazykový registr cest patří společnému modulu, origin do tenant konfigurace.
Anglický tenant později použije stejný obsah a renderer; tato práce ho nezřizuje
ani nenasažuje. Cross-domain přepínače a hreflang lze zapnout až po ověření
obou živých cílů. Nyní oba jazyky odkazují na skutečně generované stránky
stejného hostu. Nevymýšlet anglické marketingové reference ani překlad celého webu.

### Veřejná projekce a budoucí upozornění

`/platform-updates.json` má `schemaVersion: 1` a seznam položek s `id`, `kind`,
`publishedAt`, případným `updatedAt` a `translations.cs/en` obsahujícími
`title`, `summary`, `url`. Neobsahuje drafty, interní poznámky ani celé HTML.
Prázdný seznam je platný. Neznámá metadata v soukromém zdroji se nekopírují
automaticky - veřejná projekce je explicitní. URL generuje stejný modul jako HTML.

Budoucí upozornění bude referovat `platform_update_id`; titulek, shrnutí a URL
se vyberou podle jazyka příjemce (nepodporovaný jazyk -> en). Samotné načtení
JSON není pokyn k rozeslání. Budoucí odesílací služba musí odděleně evidovat
výběr příjemců, explicitní odeslání a deduplikaci podle aktualizace, příjemce
a kanálu, nezávisle na jazyce. Nyní se nemění news RPC, push payload, osobní
read state ani centrum upozornění. E-mailové rozšíření musí použít stávající
`public.email_messages`; žádný druhý odesílací systém.

### Zobrazení

Přehled ukáže datum, lokalizovaný typ, titulek a stručný přínos, nejnovější nahoře.
Detail doplní tělo, případné datum úpravy a odkaz zpět. Text je čitelný bez JS,
na mobilu i klávesnicí. Prázdný přehled má přeložené sdělení bez falešných změn.
Převzít typografii a základní prvky současného webu. Žádný autoplay ani nové trackery.
První verze podporuje odstavce, nadpisy, seznamy, bezpečné odkazy a volitelné
repozitářové obrázky s alternativním textem; video/embed se odkládá.
Raw HTML a nebezpečné URL schéma jsou zakázané. Chybějící odkazovaný asset je chyba buildu.

Odkaz v marketingové patičce a v trvalé nabídce administrace vede na
přehled podle jazyka UI. Umístění administrace dohledat od `admin_page.dart`
a `occasion_navigation_bar.dart`; přidat jednu společnou položku pro pořadatele,
nikoli do každé akce ani do soukromého provozního feedu. Nativní otevření použije
existující bezpečný externí URL launcher; nesmí přepisovat rozpracovaný editor.

## Implementační vlny

### 1. Zdroj a společný model

Vytvořit obsahový adresář, modul `platform_updates/context.mjs`, stručné autorské
README a cílené Node testy `automation/tests/platform_updates.test.mjs`.
Pro Markdown zvolit udržovaný parser s vypnutým raw HTML a validací odkazů;
před přidáním závislosti prověřit existující balíčky, nepřebírat omezený parser
právních dokumentů bez ověření potřeb. Nové JS závislosti pouze pnpm 11.24.0
v odpovídajícím balíčku s autoritativním lockfilem.

Ověřit: kolize ID/URL, neúplný překlad publikované položky, draft exclusion,
stabilní pořadí, bezpečný markup a shodu HTML/JSON URL. Chyby ukazují soubor a pole.
Výstupní podmínka: jeden resolver poskytuje všechny veřejné položky obou jazyků.
Bez databázové migrace a bez změn stávajících eventových novinek.

### 2. Stránky a integrace sestavení

Přidat renderer aktualizací a sdílený jazykový shell. V
`organizers/context.mjs` a `page_definitions.mjs` rozšířit registr o explicitní
typy přehled/detail aktualizace a omezené víceúrovňové cesty; zachovat přísnou
validaci původních témat. Pokud je potřeba společný registr přesunout do leaf
modulu, odstranit původní duplicitní vlastnictví ve stejné vlně.

Zapojit do `render_organizer_page.mjs`, `build_web_bundle.sh` a
`cloudflare_build.sh`: jediný výsledný manifest obsahuje marketing i aktualizace
a jejich assety; nesmí vzniknout dvě nezávislé tabulky veřejných URL. JSON patří
do stejného atomického bundle. Renderer nejprve validuje a připraví všechny
výstupy; vyčistí i staré generované aktualizace, aby draft nezůstal v incremental buildu.
Tenant bez explicitně zapnutého obsahu nepublikuje nové stránky ani feed.

Upravit statickou/dynamickou sitemap a `verify_web_build.mjs` /
`verify_web_deployment.mjs`. V `pwa_shell_manifest.mjs` a service workeru
registrovat stránky jako lazy resources; root zůstává install-critical.
JSON načítat aktuálně ze sítě, při offline lze vrátit poslední úspěšnou verzi;
uživateli neslibovat offline čerstvost. Neznámá offline stránka má běžnou offline chybu.

Ověřit renderer, metadata, přímé načtení vnořených cest, 404, 308, sitemap,
vyloučení draftů a tenant-off stav. Výstupní podmínka: bez JS fungují oba
přehledy i detaily a všechny veřejné výstupy vznikají ze společného zdroje.

### 3. Vstupy, autorský postup a dokončení

Přidat lokalizované odkazy do existujícího marketingového shellu a společné
administrace. Dokumentovat přidání záznamu, oba překlady, preview, publikaci přes
web release a opravu textu bez rozeslání. Lokální dokumentový preview musí
fungovat přímo z disku; nepouštět pro něj server. Při volbě obrázků používat
existující assety nebo dodané materiály, nikoli automaticky vyrábět nové vizuály.

Nevydávat plánované funkce za nasazené. Před prvním obsahem ověřit dostupnost
konkrétní funkce na cílovém tenantu a datum; bez důkazu ponechat draft. Prázdný
archiv s poctivým stavem je přijatelný lokální výsledek, falešné ukázkové příspěvky ne.

Výstupní podmínka: pořadatel najde přehled z webu i administrace podle jejich
kanonického jazyka, bez samostatného přepínače; veřejný JSON je použitelný pro další integraci bez scrapování HTML.

## Ověření a dokončení

Při implementaci spustit cílený batch Node testů pro nové kontrakty a dotčené
stávající hranice:

```sh
node --test automation/tests/platform_updates.test.mjs automation/tests/organizer_context.test.mjs automation/tests/organizer_page.test.mjs automation/tests/public_seo.test.mjs automation/tests/pwa_manifest.test.mjs automation/tests/pwa_offline.test.mjs
```

Přidat scénáře do existujících sad místo testování pouze nového pomocného modulu.
Pro změněné Dart soubory použít cílený `fvm dart analyze <soubory>`; předem
ověřit volný Flutter slot, nejvýše jeden Flutter úkol na workstation.
Pro odkazy v JS administraci využít existující test příslušné navigační komponenty.
Vizualitu a skutečné otevření odkazu ověřit jednou v izolovaném headless
agent-browser session nad existujícím app serverem, pokud běží; statické
vygenerované dokumenty lze kontrolovat přes file:// bez serveru. Test produkčního
routování zůstává povinností nasazení, lokální file:// ho nedokazuje.
Nepouštět plný Flutter build jen kvůli sepsání plánu nebo veřejnému HTML.

Hotovo znamená: jednotný obsah a identita, obě lokalizace, stabilní URL,
fungující odkazy, manifest/Worker/sitemap/PWA v souladu, žádné drafty ve výstupech,
bez vedlejšího rozeslání a cílené kontroly prošly. Rozlišit lokální implementaci,
začlenění a skutečné nasazení.

## Zachování a odstranění

| Oblast | Výsledná akce a důkaz |
| --- | --- |
| Occasion news, push a provozní notification center | Zachovat stávající vlastníky; žádný nový zápis nebo automatické napojení. |
| Seznam veřejných URL | Jediný společný resolved manifest; test shody rout, sitemap a rendereru. |
| Staré generované stránky aktualizací | Odstranit při regeneraci; test published -> draft ve stejném output adresáři. |
| Duplicitní texty pro web/feed | Nevytvářet; oba výstupy čerpají týž resolver a překlady. |
| Jiní tenanti | Zachovat chování; deaktivovaný profil negeneruje nové assety nebo routy. |

## Předpoklady, nasazení a zbylá rizika

- Rozhodnutí: repozitářové publikování je první verze. Pokud uživatel později
  požaduje samostatný editor bez release, změnit autorskou hranici v samostatném
  úkolu při zachování ID a veřejných URL; nezavádět nyní paralelní databázi.
- Předpoklad: oba překlady lze nejprve nabídnout na vstupenky.online. Vlastní
  anglická doména není závislost tohoto výsledku; před jejím zapojením ověřit
  aktuální tenant konfiguraci a živý stav, nikoli starší plán.
- První obsah závisí na pravdivých informacích o dostupnosti funkcí. To neblokuje
  lokální infrastrukturu a prázdný přehled; blokuje publikaci neověřeného tvrzení.
- Tato práce nic nemigruje ani nemaže v databázi. Obsah bude veřejný a může být
  archivován třetími stranami; návrat do draftu není odvolání již zveřejněného textu.
- Nasazení až samostatně autorizovat pro přesný tenant/branch. Použít existující
  main/tenant ancestry a drift gates, lokální build a `automation/deploy_direct.sh`;
  rutinní provedení delegovat podle AGENTS.md. Žádný automatický rollout na EN
  tenant nebo ostatní prod větve. HTML, JSON, Worker a service worker publikovat
  společně; ověřit verzi i oba jazyky, HTTP statusy a JSON na stejném bundle.
- Rollback vrací celý předchozí bundle. Trvalé odkazy dříve publikovaných položek
  zachovat při následné opravě; rollback obsahu nesmí vyvolat opětovné rozeslání.
- Při budoucím oddělení hostů synchronizovat vydání obsahu před zapnutím
  vzájemných jazykových odkazů. Kanonická identita sama nezaručuje shodnou živou verzi.

## Výsledek lokální implementace

Všechny tři vlny používají společný `organizers/context.mjs` a výsledný
`organizer-pages.json`. Striktní pravidla marketingových témat zůstávají v
`page_definitions.mjs`; přehledy a detaily vlastní leaf modul
`platform_updates/context.mjs`. Tento postup rozšiřuje registr v kontextu,
aniž by se víceúrovňové URL začaly přijímat jako původní marketingová témata.
Worker načítá hotový manifest z bundle a odmítne nesoulad s aktuálním zdrojem.

Explicitní capability `platformUpdates: true` je v `profiles.json` pouze u
`vstupenky-cs`. Stejný resolver odvozuje Flutter `platformUpdatesEnabled` přes
`apply_config.sh`. Nové dokumenty a JSON jsou ignorované generované výstupy;
nevzniká druhý obsahový zdroj ani ručně rozšiřovaný tenant seznam detailů.
Parser má vlastní pnpm balíček a frozen lockfile; společný build jej instaluje
před `apply_config.sh`. Autorský postup a statický file preview jsou v
`content/platform-updates/README.md`.

Archiv je záměrně prázdný: nebyla doložena dostupnost konkrétní změny na živém
tenantu. Integrační testy používají pouze dočasné příspěvky mimo repozitářový
obsah. Bez autorizace nebyl proveden commit/push, nasazení ani rozesílání.

Lokální ověření: cílený batch šesti Node sad prošel (33 testů), stejně jako
`automation/tests/apply_config.test.sh`. Cílený Dart analyzer nemá chyby ani
warningy; hlásí 16 existujících informačních diagnostik v `app_panel_helper.dart`.
Izolovaný headless prohlížeč ověřil přehledy obou jazyků a přepnutí dočasného
detailu při zachování ID, včetně mobilní šířky 390 px bez horizontálního
přetékání. Neběžel aplikační server tohoto projektu; browser kontrola se proto
týká statických file preview. Worker testy lokálně ověřují 200/404/308 a sitemap,
ale skutečné HTTP routování a otevření odkazu v běžící administraci musí
potvrdit následné samostatně autorizované nasazení.

Uživatelské upřesnění po preview: odstranit samostatný přepínač English/Česky
z přehledů i detailů. Jazyk vstupu zůstává ve správě existujícího marketingového
profilu a nastavení aplikace; nepřidává se vlastní detekce ani další jazykový UI.

Následné sjednocení po uživatelském preview: homepage, témata i aktualizace
používají jedinou `organizers/header.html` přes `organizers/shell.mjs`. Hlavička
a její texty/navigace se řídí kanonickým tenant profilem jako homepage; samostatná
hlavička aktualizací byla odstraněna. Integrační test porovnává shodu hlaviček.

Umístění podle následného upřesnění uživatele: odkaz „Co je nového“ patří
do patičky marketingového webu, nikoli do sdílené hlavičky. Stávající vstup
z administrace zůstává zachován; nová sekce nápovědy se nezavádí.

## Příprava vydání nad aktuálním main

Při autorizaci vydání byl autoritativní main `972e15bed`, mezitím rozšířený
na `03aa99975`. Původní pracovní strom má přes 2 700 nesouvisejících změn.
Implementace se proto přenáší samostatně do čistého worktree; stará feature
větev ani její ostatní změny nejsou součástí tohoto vydání.

Aktuální main už vlastní skutečný společný `site-header.html`,
`site-footer.html` a `site_shell.mjs`, včetně účtové hlavičky a nápovědy.
Aktualizace používají přímo tyto komponenty a produkční marketingový entrypoint;
původní lokální `header.html`/`shell.mjs` se nepřenášejí. Odkaz je pouze
v patičce a administraci. Anglický marketingový profil nyní existuje, ale
capability aktualizací zůstává zapnutá jen u českého profilu pro zvolený tenant.

Současná PWA politika výslovně nechává homepage a marketing online a zachovává
offline katalog. Tuto novější politiku vydání nemění: jen aktualizace mají lazy
prostředky a síťové načítání s poslední úspěšnou offline kopií ve stejné cache
generaci. Staré požadavky na install-critical marketingový root jsou tímto
nahrazené, aby nedošlo k regresi aktuální aplikace.

Vydání je autorizované pouze pro `prod/festapptickets` / `vstupenky.online`,
lokálním buildem a `deploy_direct.sh`. Main vyžaduje schválený PR; ochrana se
neobchází. Neprovádí se databázová změna, EN rollout ani rozesílání.

Release hranice parseru: CI web-startup i archivovaný tenant replay explicitně
instalují frozen pnpm závislosti rendereru před resolvováním publikovaného obsahu.
Tím první skutečný příspěvek nezávisí na node_modules z původního worktree.
