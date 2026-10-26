> Historický plán. Veřejnou prezentaci služby dnes vlastní homepage `/`; pro aktuální směrování platí `automation/release/organizers/README.md`. Tento dokument není zadání k obnově původní samostatné stránky.

# SEO vstupenky.online: technická konsolidace a obsah pro pořadatele

Datum: 2026-10-15. Stav: lokální realizace T1-T3/T5 a U1-U2 dokončena na základě následného pokynu uživatele; nic nenasazeno. Podrobnosti a omezení: [realizační záznam](vstupenky-seo-implementation-2026-10-15.md).
Ověřování při implementaci: standard pro veřejné routování a bezpečnostní hlavičky; cílené ověření obsahu. Plán vznikl jedním průzkumem bez buildů a testů.

## Cíl a rozsah

Zlepšit dohledatelnost služby a cestu pořadatele k založení akce. Zachovat rychlý katalog a funkční registrace. Úspěchem jsou správně indexované URL, relevantní návštěvnost a dokončené založení akcí, nikoliv konkrétní skóre SEO Site Checkup nebo jeho AI Visibility.

Rozsah: pouze vstupenky.online, veřejný web klient, příslušný edge router a tenantová konfigurace. Sdílené změny patří na main; žádný rollout dalších tenantů. Tento úkol neopravňuje k implementaci, změně DNS, produkčních dat, publikaci, commitu ani pushi. Backendové změny a obecný redesign nejsou součástí první etapy.

Respektovat předchozí výslovné přání skrýt úvodní blok na homepage a zachovat původní logo. Nevracet skrytý úvod automaticky. Navržený obsah má vlastní stránku `/pro-poradatele` s viditelným odkazem z katalogu; její konkrétní vzhled před publikací ukázat. Původní plán `vstupenky-seo-2026-10-09.md` zůstává historickým záznamem, tento dokument řídí navazující práci.

## Ověřená zjištění

| Fakt | Důkaz z 2026-10-15 | Dopad |
|---|---|---|
| Apex i www na HTTPS vracejí 200, včetně www formuláře | `curl -I https://vstupenky.online/`, `https://www.vstupenky.online/`, `https://www.vstupenky.online/form/country_bal_vetrkovice?utm_source=seo-check` | Potvrzená duplicita hostů, canonical tag sám nepřesměrovává |
| HTTP přesměrovává na HTTPS stejného hostu | HEAD obou HTTP variant: 301; www zůstává www | Sjednotit rovnou na cílový HTTPS apex |
| HTTPS nemá HSTS | HEAD + GET v izolovaném Chromium: chybí `strict-transport-security` | Bezpečnostní úprava, nikoli hlavní obsahová SEO páka |
| Title, description, canonical, OG, WebSite JSON-LD, robots a sitemap existují | `web_client/index.html`; živé načtení `/robots.txt`, `/sitemap.xml` v Chromium: 200 | Nerozepisovat plán jako nové zavádění již existujícího SEO |
| Úvod služby je v HTML skrytý | Živý GET i `web_client/index.html`: `section#site-introduction[hidden]`; H1 značky je v accessibility tree, místní `user_header.js` jej vizuálně skrývá | Přítomnost H1 ve stromu ani geometrický `checkVisibility()` nejsou důkazem čitelného vysvětlení služby |
| Katalog obsahuje i archiv a položky `(Copy)` | Živý snapshot; `UnitPage.render` dělí současné, budoucí a minulé akce | Upřednostnit současné akce a vyjasnit publikaci kopií bez mazání historie |
| Serverový seznam a JS karty mají odlišnou prezentaci | `handleHome` vypisuje plochý seznam; `UnitPage.render` třídí podle data | Sladit smysl a prioritizaci obsahu, bez speciální verze pro roboty |
| Dva externí fontové stylesheety blokují render | `web_client/index.html`; v jednom živém běhu CSS Roboto 352 ms, Material Icons 408 ms | Kandidát na optimalizaci; čísla nejsou celková úspora ani reprezentativní benchmark |
| Chyby konzole se nyní nereprodukovaly | `agent-browser errors` a `console` po ustálení homepage: prázdné | Report neuvádí konkrétní chybu, proto neplánovat opravu naslepo |
| Doména nemá SPF, DMARC ani MX v provedeném DNS dotazu | `dig +short TXT vstupenky.online`, TXT `_dmarc.vstupenky.online`, MX | Nevíme, zda root doména odesílá poštu; SPF hodnotu nelze hádat |

Metodická omezení: urllib dostal Cloudflare 403/1010, zatímco curl a izolovaný Chromium fungovaly. To není důkaz blokování Googlebotu; případné problémy procházení ověřit v Search Console a Cloudflare logu. Prohlížeč měl anglický jazyk a aplikace správně přepnula `lang` na `en`; nejde samo o sobě o českou lokalizační chybu. Čerstvý český profil patří do následné kontroly. Aktuální pracovní branch je `feat/occasion-setup-wizard-20261007` a workspace obsahuje mnoho jiných změn. Není prokázána shoda lokálního stromu s živým releasem; nesmí se použít celý jeho diff jako SEO release.

## Vlastnictví a neměnné podmínky

- `automation/project.conf` a `automation/apply_config.sh` vlastní tenantové údaje a generované metadata. Nedělat ruční opravu pouze v generovaném HTML. Při implementaci vybrat skutečný produkční overlay z main-owned policy; lokální konfigurace sama nedokazuje live organizaci.
- `automation/cloudflare_build.sh` generuje jediný produkční `_worker.js`. Vlastní `handleHome`, `handleForm`, `handleSitemap`, `htmlResponse` a routování. Build odstraňuje `_headers` a `_redirects`; samotná změna těchto souborů se v produkci neprojeví.
- `get_available_occasions` je existující zdroj veřejného katalogu. `web_client/src/components/occasion/db_occasions.js` a worker jej používají. Nezavádět druhou databázi akcí ani obcházení pravidel veřejnosti.
- `web_client/src/components/occasion/occasion_link.js` a workerové `occasionHref` musí dál shodně vybírat cílové URL; `SeoService.updateMetaTags` nesmí po navigaci vracet www nebo metadata předchozí akce.
- Přesměrování zachovává cestu i query, včetně registračních a OAuth parametrů. Canonical metadata mohou odstranit tracking, samotná navigace nikoliv. Fragment se na server neposílá a vyžaduje klientský smoke check tam, kde ho používá přihlášení.
- Stránka pro pořadatele má vlastní veřejné HTML, 200, canonical a metadata i bez JS; nesmí propadnout do Flutter fallbacku. Při klientské navigaci nesmí zůstat metadata předchozí stránky.
- Soukromé, neveřejné a demo akce nesmějí nově proniknout do HTML ani sitemapy. Minulé veřejné akce se automaticky nemažou, nepřesměrovávají na homepage a nedostávají hromadně noindex.

## Pracovní balíky, odpovědnost a závislosti

Uživatel 2026-10-15 výslovně požaduje přidělit grafickou a UX/UI práci subagentovi **Astra, Medium**. Tato volba je závazná i pro následnou realizaci. Hlavní agent zodpovídá za technickou integraci a konečné ověření; nepřebírá samovolně návrh rozložení, vizuální hierarchie nebo interakcí.

| ID | Výstup | Vlastník | Závislost | Zařazení |
|---|---|---|---|---|
| T0 | Izolovaný rozsah změn, vybraný tenant, baseline existujících URL a měření | Hlavní agent | Oprávnění k implementaci | Nutné před kódem |
| U1 | Specifikace navigace, stránky pro pořadatele, archivu a stavů načítání plus statický náhled v existujícím designu | Astra Medium | Tento plán a UX/UI zadání | Nutné před změnou UI |
| T1 | Canonical redirect a HSTS návrh v jediné skutečné runtime hranici | Hlavní agent | T0; dostupná konfigurace hrany před provozní změnou | Nutná technická oprava |
| U2 | HTML/CSS, přístupné ovládání, texty veřejného UI a jejich vizuální ověření | Astra Medium | U1; skutečné podklady kontaktu a nabídky před publikací | Nutné pro obsahovou etapu |
| T2 | Generování `/pro-poradatele`, routing, metadata a sitemap | Hlavní agent | U1 stanoví kontrakt, U2 dodá šablonu | Nutné pro obsahovou etapu |
| T3 | Shodná veřejná data, destinace a časové třídění SSR a klienta | Hlavní agent | U1; U2 dodá prezentaci archivu a stavů | Nutné při změně katalogu |
| T4 | Omezení externích fontů bez regrese vzhledu a ikon | Hlavní agent; vizuální posouzení Astra Medium | Baseline T0, stabilní U2 | Doporučené pouze s prokázaným přínosem |
| T5 | Cílená integrace a společný akceptační záznam | Hlavní agent; UI část Astra Medium | T1-T3, případně T4 | Nutné před předáním |
| O1 | Nasazení jediného tenantu a živé sondy | Hlavní agent | T5 pro vydávané dokončené celky a oprávnění k publikaci | Samostatný provozní krok |
| O2 | Search Console baseline a následné vyhodnocení | Hlavní agent | Přístup k účtu; následné měření po O1 | Nutné pro posouzení přínosu |
| M1 | Inventura pošty a teprve potom návrh SPF/DMARC | Hlavní agent | Doložená odesílací infrastruktura | Samostatná větev, neblokuje obsah |

U1 může probíhat souběžně s T0/T1. T2 a T3 integrují odsouhlasené rozhraní U1; předání HTML/CSS musí proběhnout před integrační kontrolou, aby dva agenti současně neměnili stejný soubor. T4 neblokuje opravu URL ani obsah, pokud se úspora nepotvrdí. Chybějící reference neblokuje první obsahovou verzi; chybějící pravdivý kontakt nelze zakrýt výplňovým textem.

Podrobné [UX/UI zadání](vstupenky-seo-UX-UI-2026-10-15.md) vypracoval při plánování subagent `gpt-6-astra` s `reasoning_effort: medium` pomocí skillu `ux-designer`. Je součástí tohoto realizačního plánu; určuje nutné, doporučené a odložené úpravy i akceptační matici. Nejde o provedený vizuální audit a žádné UI zatím není implementované.

### Zadání subagenta pro následnou realizaci

Použít `collaboration.spawn_agent` s `model: "gpt-6-astra"`, `reasoning_effort: "medium"` a `fork_turns: "none"`. Předat cestu k tomuto plánu, `docs/plans/vstupenky-seo-UX-UI-2026-10-15.md`, uživatelské preference a přesný aktuální seznam vlastněných souborů. Explicitně uvést, zda jde o návrh, nebo již autorizovanou implementaci. Aktuální úkol autorizuje pouze plánování.

Subagent vlastní rozložení nové stránky, umístění odkazu „Pro pořadatele“, typografii v mezích existujícího designu, prezentaci archivu, viditelnost a ovladatelnost stavů načítání/chyby a vizuální kontrolu případné změny fontů. Hlavní agent vlastní veřejnost dat, bezpečnost, SEO kontrakty, edge router, konfiguraci a release. Když UI návrh vyžaduje změnu datového kontraktu, subagent předá konkrétní požadavek hlavnímu agentovi, neobejde ho vlastním fetch nebo duplicitní logikou.

První souborové rozhraní: subagent může v dohodnuté implementační etapě vlastnit novou šablonu stránky, její styly, CSS karet a konkrétně přidělené prezentační části hlavičky/katalogu. Hlavní agent vlastní `automation/cloudflare_build.sh`, `automation/apply_config.sh`, konfigurační profil a datovou klasifikaci katalogu. `web_client/index.html` a `unit_page.js` jsou kolizní hranice: vždy jen jeden vlastník v daný čas; druhý předává požadovaný diff nebo kontrakt. Každé předání uvádí dokončené soubory a zbývající integraci.

## Pořadí realizace

### 1. Sjednotit URL a transportní hlavičky - vysoká priorita

Změny: v Cloudflare nastavit přesný permanentní redirect `www.vstupenky.online` na `https://vstupenky.online`, nejlépe spolu s HTTP variantami v jednom skoku. Použít verzovanou konfiguraci nasazení nebo zaznamenaný export pravidla; před změnou zkontrolovat stávající pravidla, TLS pro www a ostatní hostname. Redirect nesmí být odvozený z libovolného Host headeru. Pokud se řeší ve workeru, cílový host musí pocházet z tenantové konfigurace a preview hostname se nesmějí přesměrovávat.

HSTS přidat na skutečné odpovědi z produkčního workeru, včetně chyb a XML, nebo na přesně ohraničené Cloudflare hranici. Začít krátkou dobou platnosti, po ověření přejít na `max-age=31536000`. Nezapínat automaticky `includeSubDomains` ani preload bez inventury subdomén. Hlavičku nelze okamžitě odvolat klientům, kteří ji již uložili.

Odstranění: dvojí indexovatelný host; nevytvářet souběžná, odporující si pravidla v dashboardu a workeru. HTML canonical, sitemap a OG používají apex. Zachovat interní routy, OAuth a preview.

Ověření: automatická matice čtyř host/protokol variant pro `/` a platný formulář s query; cílový stav 200, varianty 301/308 se zachováním path/query, bez smyček. HSTS na 200, 404 a XML. Stávající testy routování rozšířit pouze podle změněné hranice. Výstup: jediný veřejný host a skutečně doručované hlavičky, lokálně doložené; produkční důkaz až po autorizovaném release.

### 2. Vysvětlit produkt a posílit důvěru - největší obsahový přínos

Změny: samostatná `/pro-poradatele`, navázaná viditelným odkazem z homepage, nikoliv automatické zobrazení dříve skrytého úvodu. Použít existující statickou šablonovací konvenci, např. vzor `automation/release/render_legal_pages.mjs`, s tenantovým vstupem a explicitní routou v edge routeru. Nevkládat tenantový marketing bezpodmínečně do všech tenantů.

Obsah: H1 „Prodej vstupenek a registrace na akce“, pro koho služba je, tři kroky od založení po odbavení, ověřené možnosti objednávek/plateb/vstupenek, odkaz na stávající založení akce, 4-6 věcných FAQ a skutečný kontakt/provozovatel. Přidat doložené podmínky ceny nebo vysvětlení, jak cenu zjistit. Reference jen autentická a se souhlasem; chybějící reference není důvod vymýšlet citaci ani blokovat základní informační stránku. Zachovat logo a současnou cestu účastníka k registraci.

Titulek a description sladit s obsahem; současný titulek je použitelný. Description rozšířit pouze kvůli lepšímu sdělení. WebSite JSON-LD zachovat; Organization a případné Event přidávat jen z pravdivých veřejných údajů, ne jako automatický slib rich results. Složitější Event data jsou až navazující etapa po kontrole detailů akcí.

Odstranění: žádný skrytý marketing navíc pro boty, žádné falešné reference či tvrzení o cenách. Existující skrytý blok na homepage lze ponechat podle přání provozovatele, nepovažovat jej za hotový obsahový cíl.

Ověření: HTML bez JS, metadata, explicitní 200 routa a sitemap; izolovaný český a anglický profil, mobilní šířka a funkční CTA. Statický vizuální návrh otevřít přes `file://`, bez serveru. Výstup: dohledatelná stránka, která vysvětlí službu a dovede pořadatele k založení akce.

### 3. Uspořádat katalog a indexaci - navazuje na obsah

Změny: v `UnitPage.render` dát současné a budoucí akce před archiv; archiv zobrazit kompaktně a rozbalit na vyžádání, zachovat skutečné procházetelné odkazy. `handleHome` poskytne věcně stejný katalog s daty/sekcemi; serverový obsah nesmí během čekání zmizet pod neprůhledným loadingem. Sladit časovou klasifikaci a rozhodnutí o zveřejnění mezi serverem a klientem. Žádné filtrování podle User-Agent.

Konkrétní UI kontrakt U1/U2: minulé akce ve výchozím stavu v nativním `details/summary` s počtem položek; archiv při nalezené historické shodě automaticky rozbalit. Zachovat již existující pořadí současné/budoucí/minulé, nejde o nové třídění. Rozlišit prázdný katalog, nulový výsledek hledání a neúspěšnou aktualizaci. Při chybě zachovat dostupné serverové odkazy, nabídnout opakování a nevypisovat technické `e.message` přes `innerHTML`; bezpečné vykreslení a lifecycle opakování integruje hlavní agent. Stejnou definici chyby a dostupných dat používají SSR a klient.

Položky `(Copy)` projít s provozovatelem jako seznam konkrétních kandidátů. Název není spolehlivý příznak soukromosti: neodstraňovat pomocí regexu a neměnit produkční data bez oprávnění. Pokud jde o testovací akce, použít existující publikaci/demo pravidlo. Případné změny RPC znamenají nový veřejný kontrakt a vyžadují cílenou SQL verifikaci; nejsou nutné pro první úpravu prezentace.

Sitemap deduplikovat podle finální interní canonical URL, přidat `/pro-poradatele`, držet mimo externí destinace a prokázané neveřejné/demo položky. Historické užitečné akce ponechat; neuvádět vymyšlené lastmod. Na vzorku aktuální, minulé a externí akce prověřit cílovou URL, response code, canonical a metadata při přímém otevření i navigaci. Backendový výpadek dál nesmí být vydáván za potvrzenou 404.

Ověření: `automation/tests/public_seo.test.mjs`, `web_client/tests/components/occasion_card_links.test.js`, cílený test katalogové klasifikace pokud se mění její logika; cena testu má odpovídat riziku. Výstup: shodné veřejné destinace, přehledný katalog, žádné nové indexované kopie zavedené touto změnou.

### 4. Omezit blokování fonty a ověřit skutečné načtení

Změny: nejprve zaznamenat srovnatelný mobilní cold-load baseline, včetně času do zobrazení použitelných karet a CTA. Report označil za LCP „Loading…“; hodnoty 1,23 s proto nedokazují rychlé načtení skutečného obsahu. Změřit také selhání backendu a zobrazení serverového katalogu.

Pro veřejný web zvážit systémový font místo Robota nebo lokální WOFF2 s `font-display: swap`. Material Icons načítat lokálně nebo nahradit existujícími SVG pouze v rámci potřebných ikon; zachovat ikony v dialozích i později otevřených formulářích. Upravit zdroj šablony i generátor `automation/configure_fonts.js`, pokud ovládá dané odkazy. Běžný malý hlavní CSS soubor nepřevádět automaticky na asynchronní načítání kvůli skóre - hrozí blikání a posuny layoutu.

Odstranění: jen skutečně nahrazené Google Fonts requesty a příslušný mrtvý fontový config; zachovat PWA/offline kompatibilitu a specializované fonty vstupenek. Neměnit kvůli homepage celý Flutter startup.

Ověření: jeden Vite build celého koherentního balíku změn a před/po měření při stejných podmínkách; ověřit diakritiku a ikony na homepage, formuláři a přihlášení, včetně offline scénáře pokud se dotkl fontové cache. Pokud zlepšení není doložené nebo jsou regrese, tuto optimalizaci nepublikovat. Konzoli opravovat až podle konkrétního reprodukovatelného záznamu.

### 5. Měřit přínos a samostatně dořešit poštu

Nejprve využít existující Cloudflare Web Analytics a Google Search Console. DNS ověřovací TXT sám nedokazuje přístup ani aktivní sledování. Zkontrolovat sitemap submission, indexaci homepage, nové stránky a vzorku akcí, procházení a důvody vyloučení; chyby auditovat podle konkrétních URL.

KPI: nebrandové dotazy, relevantní impressions/clicks a CTR po stránkách; z návštěvnosti cesta klik na založení -> dokončená první akce, pokud lze rozumně a bez osobních údajů měřit. Rozdělit akviziční stránku a návštěvnost účastníků konkrétních akcí. Porovnat 28 dní před a po, s ohledem na sezonnost a nízký objem. GA nepřidávat automaticky jen kvůli zelenému testu; případný nový tracker vyžaduje vlastní produktové rozhodnutí a odpovídající ochranu údajů.

SPF/DMARC: nejprve zjistit, zda a přes koho skutečně odchází pošta s From/MAIL FROM na této doméně, včetně subdomén, běžných schránek a konfigurace SES. Pokud root neodesílá, lze navrhnout zákaz odesílání; pokud odesílá, navrhnout jediný SPF z doložených providerů a DMARC podle skutečného alignmentu. Hodnoty a DNS změna až po této inventuře a oprávnění. SPF je doručitelnost a ochrana domény, není hlavní SEO páka. Nepřidávat ads.txt bez reklamního systému.

Výstup: dostupný baseline a konkrétní kontrola po 4-8 týdnech; SPF buď odůvodněně vyřešený samostatnou změnou, nebo výslovně evidovaný jako závislost na poštovní inventuře.

## Ověřování, nasazení a dokončení

### Převzetí práce

- Technická část: redirect matici prokáže hlavní agent; 200/404/XML mají očekávané hlavičky, preview a OAuth zůstávají funkční, tracking query se při přesměrování neztratí.
- Obsahová část: `/pro-poradatele` vrací vlastní HTML bez JS, má jediný věcný H1, metadata a odkaz z katalogu; CTA vede do existujícího toku vytvoření akce. Ceny, provozovatel a případné reference mají doložený zdroj.
- UX/UI část: Astra Medium doloží mobilní a desktopový výsledek, klávesnici, fokus, kontrast a čitelnost v podporovaných tématech, českou diakritiku a dlouhé texty. Konkrétní matice a priority jsou v doprovodném UX/UI zadání. Plán tyto vlastnosti nepovažuje za již otestované.
- Katalog: stávající rozdělení na současné/budoucí/minulé se zachová; změnou je kompaktní archiv a shodná prioritizace serverového obsahu. Rozbalování neodebere historické odkazy z HTML a nemění pravidla zveřejnění.
- Načítání: ověřit funkční obsah za běžného načtení, při pomalé síti i chybě backendu, nikoliv pouze čas vykreslení loaderu. Neoznačit prázdný výsledek jako chybu a chybu jako potvrzenou neexistenci akce.

První vydání nemusí obsahovat fontovou optimalizaci, reference ani změny pošty. Musí mít dokončené vybrané funkční celky; nepouštět do veřejného UI nefunkční odkaz na rozpracovanou stránku. Technickou opravu URL lze vydat samostatně po jejím ověření a autorizaci.

Po koherentních změnách provést jeden cílený balík kontrol: veřejný edge router/SEO, změněné klientské kontrakty, případně generátor konfigurace a jeden Vite build. Nepřepisovat testy pouze kvůli znění marketingu. Příkaz pro existující základní JS kontroly:

```sh
node --test automation/tests/public_seo.test.mjs web_client/tests/services/seo_service.test.js web_client/tests/components/occasion_card_links.test.js
```

Rozšířit o konkrétní testy změněného generátoru/routování, nikoliv celorepozitářový běh kvůli textu. Browser smoke izolovaný a headless, žádné registrace, objednávky ani jiné produkční zápisy.

Publikace je další autorizovaný krok. Vybrat pouze tenant vstupenky.online, předem oddělit nesouvisející workspace změny a zachovat canonical main/tenant ancestry a drift policy. Lokálně sestavit Flutter i web klient a nasadit přes `automation/deploy_direct.sh`; nevyvolávat GitHub build. Před vydáním porovnat aktuální upstream a provést gates vyžadované release pravidly. Po vydání ověřit jednu coherent live verzi, redirect matici, sitemap, novou stránku a registraci bez odeslání objednávky.

Rollback: vrátit aplikační bundle a konkrétní edge pravidlo nezávisle, bez obnovení dalších tenantů. HSTS má klientskou paměť, proto se zavádí s krátkým max-age. Nevracet DNS pošty bez důkazu dopadu; změna pošty má vlastní plán.

Hotovo znamená: jediný canonical host, ověřené skutečné hlavičky, veřejná stránka pro pořadatele dostupná bez JS a z katalogu, zachované hluboké odkazy a přihlášení, relevantní sitemap a věcně shodný katalog. Fontová změna jen při doloženém přínosu. Měření a zbývající externí závislosti jsou zaznamenané. Lepší pořadí v Googlu ani konkrétní AI skóre nelze předem garantovat.

## Rozhodnutí a zbývající závislosti

- Výchozí předpoklad: cílem je získat více pořadatelů při zachování katalogu pro účastníky. Pokud je prioritou pouze katalog, obsahovou etapu zmenšit; technické opravy zůstávají stejné.
- Konkrétní kontakt, ceny, reference a schválení designu dodá provozovatel; pracovní draft může pokračovat bez těchto údajů, veřejné tvrzení je nesmí nahrazovat.
- Účty Cloudflare/Search Console a poštovní inventura nebyly v tomto plánovacím úkolu otevřeny. Chybějící přístup blokuje až odpovídající provozní krok.
- Reálné dopady na pořadí jsou opožděné a sezónní; jednorázový laboratorní report není náhradou dat o návštěvnících.

## Zdroje a výklad reportu

- [Aktuální web](https://vstupenky.online/) a read-only sondy popsané výše.
- [Google: snippets a meta descriptions](https://developers.google.com/search/docs/appearance/snippet): Google nestanovuje povinné rozmezí 150-220 znaků; relevantní popis je důležitější než splnění limitu auditora.
- [Google: page experience](https://developers.google.com/search/docs/appearance/page-experience): perfektní technické skóre samo nezaručuje lepší pozice.
- [Google: Core Web Vitals](https://developers.google.com/search/docs/appearance/core-web-vitals): hodnotit skutečnou zkušenost, včetně INP; převzatý audit měří převážně laboratorní načtení a zobrazuje loader jako LCP.

AI Visibility 62/100 bez zveřejněných promptů, vzorku, trhu a metody bereme jako neověřený údaj poskytovatele. Prioritou je užitečný veřejný obsah, jasná identita a skutečné reference, nikoliv příslib ovlivnění konkrétních chatbotů.


## Aktualizace při realizaci 2026-10-15

Následný uživatelský pokyn autorizoval implementaci, nikoliv publikaci. Rozsah a výsledky ověření jsou v [realizačním záznamu](vstupenky-seo-implementation-2026-10-15.md), vzhled v [statickém náhledu](vstupenky-seo-preview-2026-10-15.html).

Upřesněné předpoklady s důkazem: produkční `origin/prod/festapptickets:automation/project.conf` má organizaci 3 a canonical aktivaci; živý aktivační dokument potvrdil tenant festapptickets/generaci 1/canonical. Místní konfigurace má organizaci 1 a nesmí se vydávat jako produkční profil. Kontakt a identita provozovatele již existují v `automation/release/legal/support.cs.md` a `terms.cs.md`; není nutné je vymýšlet ani považovat za chybějící podklad. Veřejný ceník/reference doloženy nejsou, stránka nabízí dotaz na cenu bez čísel a bez referencí.

Katalog zachovává i položky bez platného termínu v samostatné sekci; původní datumové filtry je mohly ztrácet a karta mohla při neplatném datu spadnout. Opravu pokrývá cílený test reálné karty. Nevalidní katalogový payload je chyba dostupnosti, nikoliv potvrzená nula akcí. SQL/RPC pravidla zveřejnění ani položky `(Copy)` nebyly změněny.

Fontová optimalizace T4 se neprovádí bez srovnatelného měření. Lokální technické a UI ověření nenahrazuje O1: www stále před vydáním vrací 200; živé jednohopové přesměrování a HSTS vyžadují autorizované nasazení a ověření vnějších Cloudflare pravidel. O2 a M1 zůstávají samostatnými provozními závislostmi.
