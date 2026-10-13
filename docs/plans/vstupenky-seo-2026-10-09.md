# SEO vstupenky.online

Rozsah: hlavní stránka a veřejné karty akcí na vstupenky.online. Zachovat logo „fa“, zvětšit jeho obsah a odstranit vnější bílý okraj. Značka služby je `vstupenky.online`. Bez publikace před náhledem uživatele, bez změn dat nebo rolloutů dalších tenantů.

1. Sjednotit tenantovou konfiguraci, titulky, popisy, jazyk statického shellu, manifest a odkazy na skutečně existující stabilní ikony.
2. Upravit karty na nativní odkazy. Zachovat běžný klik a dialogy; podporovat klávesnici, nový panel a použití bez JavaScriptu.
3. Doplnit do veřejného HTML hlavní stránky název, krátký popis a odkazy na veřejné akce z existujícího veřejného RPC. Zajistit bezpečné escapování a omezený timeout; při výpadku backendu zachovat načtení aplikace.
4. Sjednotit URL sitemapy s cíli karet, odstranit nedoložené `lastmod` a uvést sitemap v robots.txt. Opravit chybějící obrazové URL; zachovat platné hluboké odkazy Flutteru. Ověřit neexistující formuláře bez zaměňování výpadku backendu za 404.
5. Spustit cílené testy skutečného edge routeru, karet a konfigurace; sestavit web klient. Ověřit statický náhled desktop/mobil, fokus a ikonu v kruhovém výřezu. Výsledky zapsat do tohoto dokumentu.

Ověření: standard (veřejný kontrakt, generování konfigurace a sdílené routování). Reálné pořadí ve vyhledávání, indexace a Core Web Vitals zůstávají závislé na nasazení a datech Search Console. Změna faviconu se u Googlu projeví až po novém procházení.

## Provedeno a ověřeno

Všechny body plánu jsou implementované pro místní kontrolu. Název služby, WebSite JSON-LD, titulky a manifest používají tenantovou konfiguraci. Úvodní blok je na přání provozovatele skrytý. Volitelný `WEB_PAGE_TITLE` přidává popis služby do titulku bez změny názvu aplikace. Hlavička používá původní wordmark Festapp ve všech velikostech displeje.

Stávající „fa“ bylo zachováno. Nový nativní SVG výřez původní grafiky odstraňuje nadbytečné okraje; odvozené PNG a ICO jsou stejné v obou klientech. Hlavní favicon je 192 x 192 PNG na stabilní URL. Generátor kopíruje tenantové webové ikony do public adresáře Vite, takže favicon nezískává cestu závislou na bundlování. Zvětšené ikony mají v manifestu účel `any`, protože nejsou navržené pro povinnou bezpečnou oblast maskovatelných ikon.

Karty používají `a[href]`, primární klik zachovává existující dialog nebo registraci, modifikované kliky zůstávají nativní. Sdílené cíle respektují odlišný slug formuláře a platné externí formuláře. Při přímém načtení i návratu historií se slug dekóduje jednou. Úvodní serverové HTML obsahuje také bezpečně escapované odkazy z veřejného katalogu; výpadek backendu nezablokuje aplikaci.

Sitemap používá stejné interní cíle jako karty, neuvádí externí domény ani nedoložený čas aktualizace. Robots.txt uvádí její URL. Potvrzené neexistující formuláře a neznámé slugy vracejí 404; platné hluboké odkazy aplikace zůstávají funkční a výpadek backendu není považován za důkaz neexistence. Metadata při navigaci mezi formuláři aktualizují canonical, sdílecí URL a obrázky bez zbytků předchozí akce.

Výsledky kontrol:

- 19 cílených JS testů prošlo: edge SEO/routování, karty a původní registrační testy, metadata a dekódování URL.
- `apply_config.test.sh`, konfigurační matice tenantů a `deploy_workflow.test.sh` prošly. Matice provádí pouze místní generování syntetických profilů; žádný jiný tenant nebyl publikován.
- Vite build skutečného vybraného profilu `festapptickets` prošel. Generované vstupy odpovídají canonical backendu a organizaci 3; deklarované PNG, ICO a wordmark existují na stabilních veřejných cestách.
- PNG rozměry a všechny čtyři ICO snímky jsou validní; kontrola relevantních diffů nenašla chyby whitespace.
- Náhled byl zkontrolován na desktopu, při 390 px a 320 px, také v tmavém režimu. Původní překrytí wordmarku a tlačítek bylo opraveno; bez horizontálního přetékání. Enter otevřel kartu jako nativní odkaz. Kruh faviconu byl vizuálně porovnán před/po.

Náhled: `/tmp/festapp-seo-preview/index.html`, ikona a ilustrativní výsledek vyhledávání: `/tmp/festapp-seo-preview/icons.html`. Náhled má ukázkové akce a neodesílá data. Reprodukční skript: `/tmp/festapp-seo-preview.mjs`.

## Před publikací

Nic není commitnuté, pushnuté ani nasazené. Pro vybraný produkční overlay je připraven soubor `docs/plans/vstupenky-seo-tenant-profile.patch`. Při následném autorizovaném release je nutné převzít také SVG zdroj zvětšené ikony a PNG/ICO zdroje do tohoto jediného overlay, použít aktuální main-owned policy a obvyklé plné release gates. Současný workspace obsahuje další nesouvisející změny, které do tohoto vydání nepatří. Byl sestaven veřejný JS klient; nebyl vytvářen ani publikován kompletní Flutter release bundle.

## Úprava po vizuální kontrole

Provozovatel schválil odkazy Soukromí a Podmínky, požádal o původní logo Festapp vlevo nahoře a skrytí úvodního nadpisu a popisu. Logo bylo vráceno, úvod má atribut `hidden` a schválené odkazy jsou součástí skutečné domovské šablony. SEO název vstupenky.online a zvětšený favicon zůstávají. Aktualizované sestavení vybraného klienta a test generátoru prošly. Náhled při 1280 a 320 px nemá horizontální přetékání ani překrytí hlavičky; úvod má vypočtené `display: none`. Nic nebylo publikováno.
