# Anglický ticketing na tickets.festapp.net

Datum: 2026-10-23  
Stav: rozpracovaný prováděcí plán se závazným sdílením jádra a odděleným katalogem  
Ověřování při implementaci: standard (platby, autentizace, veřejné kontrakty)

## Upřesnění zadání po implementačním předání

Cílová Git nasazovací větev a profil se jmenují `prod/festappticketsglobal` / `festappticketsglobal`, bez pomlčky. Veřejný brand je **Festapp Tickets**; česká varianta je označována **Festapp Tickets Czech**. Doména je `tickets.festapp.net`.

Nejnovější pokyn nahrazuje mezitím zvažované sdílení organizace 3: anglická varianta používá samostatnou organizaci **25 - Festapp Tickets Global**, založenou na kanonickém backendu 2026-10-23. Má jazyk `en`, výchozí platbu `stripe` a žádné akce, jednotky, členy ani externí zdroje. Nové Stripe platby jsou vypnuté pro sandbox i live. Česká organizace 3 ani její produkční větev nebyla změněna. Založení organizace není nasazením webu; důkaz je v `tickets-festapp-en-evidence-2026-10-23/organization-provisioning.json`.

## Společné jádro a reprodukce videí - doplnění zadání

Global je pouze úzký konfigurační/brandový overlay. Společný kód, překlady,
renderer, videa i capture tooling patří na main; kontrola driftu zakazuje jejich
kopie nebo úpravy jen v tenantové větvi. Výjimka musí mít konkrétní důvod a úzkou
main-owned policy, nikoli obecné povolení pro zdrojové adresáře.

Origin videí byl dohledán podle aktuální české stránky: 32 souborů odpovídá produkční referenci `8a390d70c90f788b897f9ca621fe5e6d0c0a9663`. Sdílený scénář je `automation/landing_capture/scenarios/storyboard.json` a nástroje umějí ověřovat přesnou párovou reprodukci. Nejnovější pokyn ale odkládá shodu 1:1; anglické scénáře se mohou později lišit. Existující EN videa mají ověřené skutečné anglické UI, přehrání a dekódování, nikoli přesnou identitu českého scénáře. Párová reprodukce není podmínkou aktuálního vydání.

## Implementační stav 2026-10-23

Navazující EXECUTION-PROMPT autorizoval lokální implementaci tohoto plánu. Práce je v izolovaném worktree `/Users/miakh/source/festapp-worktrees/tickets-en-20261023`, větev `feat/festappticketsglobal`, základ aktuálního upstream main `d97835e798e48f17047de4b438a2db6b9e0f8a9c`. Původní rozsáhlý pracovní strom zůstal zachován; žádný commit ani push nebyl proveden. Pozdější autorizovaný produkční zásah se omezuje na založení organizace 25 a jejích vypnutých platebních politik.

Oprava faktického předpokladu: načtený upstream už obsahuje Stripe a původní landing stránku. Implementace je používá přímo. Existující `external_sync_maps` je také použitelný registr povolených zdrojů podle `target_org_id` a `source_name`; nový registr nevznikl. Nová organizace bez map nemá externí katalog. Před produkční migrací zbývá inventura a schválení existujících map - lokální fixture nedokládá produkční inventuru.

Společný profil a renderer nyní vybírají locale a explicitní `WEB_ORGANIZER_LANDING_ENABLED`. Anglická testovací identita je pouze syntetická organization/unit 900001 na loopbacku. Není produkčním profilem ani náhradou českého tenantu. Výchozí placený formulář má banku vypnutou; uzavřený draft může čekat na Connect, server blokuje otevření a placenou objednávku bez validní metody.

Lokální akceptace zahrnuje založení anglické akce průvodcem, webový nákup ve skutečném Stripe sandboxu, serverové potvrzení platby, původní e-mailovou frontu s lokálním souborovým transportem, anglické PDF a online vstup včetně kamerového dekódování QR z tohoto PDF. SES doručení ani live platba se tím neprokazují. Vstupní PDF i raw mediální mastery zůstávají mimo Git; jejich identifikátory a důkazy jsou v [adresáři evidence](tickets-festapp-en-evidence-2026-10-23/README.md).

Konkrétní dosud neprovedené provozní kroky a chybějící skutečné hodnoty uvádí [provozní manifest](../../automation/release/tenants/festappticketsglobal.manifest.json). Produkční organization je 25; unit, pilotní akce/formulář/měna, vlastnictví/routing hostname, právní a sender brány zůstávají otevřené. Původní fáze níže jsou zachovány jako kontrakt rozsahu, nikoli jako nový implementační plán.

## Výsledek a rozsah

Na `https://tickets.festapp.net` funguje anglická obdoba vstupenky.online: web pro pořadatele, katalog veřejných akcí, založení a správa akce, formuláře, produkty, plánek a výběr míst, objednávka, platba, e-maily, PDF vstupenky, odbavení a přehledy. Primární platbou je karta přes existující Stripe integraci. Bankovní převod včetně platebního QR lze pořadatelem výslovně zapnout jako vedlejší metodu. QR pro kontrolu vstupenky zůstává součástí vstupenky i při platbě kartou.

Závazné upřesnění uživatele: používat doslova stejné jádro a vycházet co nejvíce z původní stránky; české události se na anglickém webu ve výchozím stavu nezobrazují. Jde o další tenant nad společným produktem, nikoli kopii aplikace nebo přesměrování české služby. Sdílený kód zůstává na `main`. České formuláře, obsah, obchodní nastavení a aktivace Stripe na vstupenky.online se tímto úkolem nemění. Implementace společných oprav může vyžadovat české regresní testy, nikoli český deploy.

Součástí je i produkční příprava: DNS/TLS, hosting, originy a návratové URL, OAuth, odesílatel e-mailů, právní a podpůrné stránky, SEO, monitoring a bezpečné pořadí aktivace. Nové nativní aplikace do obchodů, převod českých historických dat, automatické překlady obsahu pořadatelů, automatická konverze měn a nový provizní model jsou mimo rozsah. Embed/native Stripe je samostatná akceptační brána, nikoli automatická součást první aktivace.

Toto zadání autorizuje plán a jeho uložení. Neautorizuje implementaci, commit/push, DNS změny, produkční data či migrace, deploy nebo živé platby. Navazující implementační zadání má vést k hotovému lokálnímu výsledku; provozní kroky musí mít vlastní autoritu.

## Fakta z aktuálního repozitáře

Průzkum proběhl v pracovním stromu `feat/occasion-setup-wizard-20261007`, HEAD `353394511`, s rozsáhlými souběžnými změnami. Nálezy popisují tento lokální stav, nikoli důkaz publikace na main nebo produkci. Při implementaci zaznamenej aktuální upstream a rozliš již začleněné závislosti od lokálních změn.

| Fakt | Podklad | Dopad |
| --- | --- | --- |
| Český tenant má vlastní produkční overlay. | Lokální `prod/festapptickets:automation/project.conf`: doména vstupenky.online, organization 3, canonical backend, jazyk cs, `IS_APP_SUPPORTED=false`. | Nepoužít jeho organization ID ani profil pro anglický tenant. Read-only nález není aktuální live inventura. |
| Generování konfigurace a overlay politika už existují. | `automation/apply_config.sh`, `docs/architecture/tenant_overlays.md`, `automation/tenant-overlays/festapptickets.paths`. | Rozšířit existující kontrakt a allowlist; neupravovat ručně generované listy. |
| Landing renderer i edge routing dnes zapínají marketing podle české domény. | `automation/release/render_organizer_page.mjs`: `DOMAIN === vstupenky.online`, pevný apex, cs texty/JSON-LD; `automation/cloudflare_build.sh`: host-based `ORGANIZERS_ENABLED`; `apply_config.sh`: host-based sitemap. | Samotná změna domény landing page vypne. Zobecnit stávající renderer a tutéž routovací pipeline pro oba profily. |
| Katalogové SQL dnes zahrnuje externí události napříč organizacemi. | `database/functions/others/get_available_occasions.sql`: `(o.organization = p_organization_id OR c.source_name IS NOT NULL)`; JS caller `components/occasion/db_occasions.js`. | Nové organization ID samo neizoluje katalog. Povinná serverová politika externích zdrojů a testy obou tenantů. |
| Obsah původní landing page obsahuje české reference a hardcoded UI texty. | `automation/release/organizers/content.json.publicProjection.references`, `render_content.mjs`, `page.html`, `page.css`, `clips.json`. | Sdílet layout a renderer, lokalizovat obsah; české event cards automaticky nepřebírat. |
| Anglický katalog překladů existuje, jeho úplnost není prokázána. | `assets/translations/en.json`; JS `LocalizationService`, Flutter `EasyLocalization` v `lib/main.dart`. | Prověřit obě UI a všechny výstupy, nestačí přepnout jazykový seznam. |
| V lokálním kódu zůstává český obsah a fallbacky. | `web_client/index.html`; `seo_service.js` obsahuje český popis a `cs-CZ`; `_shared/ticketDate.ts` má výchozí cs. | Lokalizovat i první HTML, SEO a generované dokumenty; překládací JSON sám nestačí. |
| Platební autoritou je SQL, Stripe má již implementovaný tok. | `database/functions/eshop_stripe/`, `supabase/functions/stripe-*`, `supabase/functions/_shared/stripe/`, `lib/components/stripe_payments/`. | Neimplementovat druhý checkout, ledger ani webhook. |
| Dostupný Stripe již dostává první místo před bankou. | `form_payment_availability_internal` v `eshop_stripe/form_availability.sql`; JS `payment_method_picker.js` vybírá první `available`. | Primárnost řešit správnou konfigurací a shodou obou klientů; nepřidávat další výpočet dostupnosti na frontend. |
| Chybějící platební konfigurace dnes implikuje banku. | Stejný SQL soubor: `bankEnabled` implicitně true; `form_settings_content.dart` má bankovní default. | Pro nové anglické formuláře je třeba explicitní tenantový default a stav nepřipojeného Stripe. |
| Stripe v tomto stavu podporuje CZK/EUR/PLN/USD/GBP, odmítá některé kombinace. | `stripe_form_compatibility_internal`: jedna měna, bez záloh, meta surcharge a Fakturoid; omezení konce prodeje. | Angličtina nesmí automaticky znamenat EUR nebo slib libovolných měn a účetních funkcí. |
| E-mailové šablony mají dědičnost occasion > unit > organization. | `lib/components/email_templates/README.md`, existující email renderer a `public.email_messages`. | Připravit anglické tenantové šablony a projít override/fallbacky; zachovat jednu frontu. |
| Stripe má lokální sandboxové důkazy, nikoli doloženou produkční aktivaci. | `stripe-client-owned/IMPLEMENTATION-STATUS.md`, `PILOT-RUNBOOK.md`, `stripe-integration-readiness-plan-2026-10-22.md`. | Integrace a replay migrací jsou předpoklad; neopakovat je bez kontroly stavu, nepovažovat je za hotový deploy. |

Reprezentativní cesta: doména a activation manifest vyberou tenant -> veřejný katalog/formulář -> SQL vrátí dostupnost metod a příjemce -> explicitní potvrzení objednávky vytvoří neměnný Stripe pokus -> Edge Function založí hosted Checkout -> podepsaný webhook/reconciliation uloží finanční fakta a přechod objednávky -> existující fronta vygeneruje a doručí e-mail/PDF -> server ověří platnost při vstupu. Návrat z Checkout sám platbu nepotvrzuje.

## Rozhodnutí, předpoklady a otevřené brány

### Rozhodnutí návrhu

1. Jeden společný produkt, samostatná konfigurace anglického webu. Pracovní tenant slug `festapptickets-en`, navržená větev `prod/festapptickets-en`; před vytvořením ověřit kolize v registraci a policy. Žádné větvení obchodní logiky podle hostname.
2. První verze používá `WEB_SUPPORTED_LANGUAGES=en`. Anglicky je veřejný web i administrační cesta. Budoucí další jazyk je rozšíření seznamu, nikoli důvod nyní udržovat druhou českou landing page.
3. Nové placené formuláře preferují Stripe; banka není implicitně zapnutá. Když účet není připojen nebo ověřen, pořadatel dostane úkol dokončit Connect a prodej kartou zůstane blokovaný. Bez výslovné volby se nevytvoří bankovní objednávka. Bezplatné registrace fungují samostatně.
4. Pokud pořadatel zapne obě metody, dostupný Stripe je předvolený. Při nedostupnosti Stripe může návštěvník výslovně zvolit povolenou banku; už potvrzenou volbu karty nelze při submitu potichu změnit na banku. Stripe-only formulář vysvětlí nedostupnost a zachová vyplněné údaje.
5. Použít stávající Connect a direct-charge kontrakt: platba vlastnímu účtu pořadatele, bez nové platformní provize nebo převodů. Identita příjemce je neměnná pro existující platební pokusy. Nové platební metody nad existující `card` se neslibují bez vlastního ověření.
6. Katalog anglického webu obsahuje pouze veřejné a způsobilé akce jeho organizace a případně později výslovně schválených zdrojů. Výchozí externí zdroje jsou prázdné. Při prázdném katalogu zobrazit anglický prázdný stav, bez české náhradní nabídky. Jazyk názvu ani země konání nejsou filtrem - rozhoduje příslušnost/publikace v katalogu.
7. Jazyk, měna a časové pásmo jsou oddělené údaje. Měna náleží akci/produktům a serverem podporované kombinaci. Čas akce má být návštěvníkovi jednoznačný; nefixovat všechny akce na britský čas ani na čas prohlížeče.

### Předpoklady vyžadující vyřešení před provisioningem

- **Doména:** přepis zadání chápu jako `tickets.festapp.net` podle opravy názvu. Před DNS, Stripe allowlisty a publikací potvrdit přesný hostname.
- **Datový model:** jako implementační rozhodnutí použít novou organization a vlastní katalog; nejde o jazykový alias organization 3. Uživatelem potvrzené nezobrazování českých událostí je pevné. Sdílení stejné akce mezi katalogy není požadováno a neimplementuje se. Pokud později vznikne tento požadavek, vyžaduje samostatný kontrakt publikace, `DEFAULT_URL`, identity a canonical URL; nekopírovat data jako náhradu.
- **Brand:** pracovní veřejný název `Festapp Tickets`, existující Festapp identita. Finální název, kontaktní adresa a právní subjekt se stanoví před dokončením obsahu. Nevytvářet fiktivní reference nebo ceník.
- **Pilot:** pořadatel, země jeho Stripe účtu, měna a konkrétní akce nejsou zadány. Výběr patří před živou akceptaci, neodvozovat jej z angličtiny. Neaktivovat EUR jen podle pracovní domény.
- **Obchodní podmínky:** zachovat aktuálně schválený model; zahraniční prodej, daňové doklady, refund policy a zveřejněné ceny vyžadují konkrétní podklady provozovatele. Technická integrace není daňové či právní posouzení.

Externí stav nebyl měněn ani kontrolován přihlášením: vlastnictví DNS, nové organization ID, živý Stripe účet, sender a produkční dostupnost domény zůstávají provozními branami.

## Cílové invarianty

- Tenant identita je shodná v configu, activation manifestu, organizaci, veřejných RPC, odkazu na obrázky a případném Client Sync. Chybné napojení končí chybou, ne českým fallbackem.
- Nový účet, jednotka, akce a formulář vznikají v anglickém tenantovi se správnými právy. Registrace, Google OAuth, reset hesla a návrat do rozpracované akce zachovají origin i jazyk.
- UI, první HTML, metadata, validace, systémové e-maily, ticket PDF a podpora nemají české systémové fallbacky. Vlastní obsah pořadatele se automaticky nepřekládá.
- Dostupnost, přesná částka/měna, příjemce a finální změna stavu platby zůstávají serverovou autoritou. Banka nevyžaduje svůj účet/VS pro Stripe-only objednávku.
- Duplicitní webhook, dva panely, reload, timeout a pozdní platba nevytvoří dvojí objednávku, dvojí ticket intent ani obnovu již uvolněné kapacity.
- Veškeré maily používají `public.email_messages`; odesílatelem je pouze `process-email-queue`. Platba, platnost vstupenky a doručení jsou samostatné stavy.
- Samostatný nový tenant nesmí přesměrovat české objednávky, změnit jejich metody ani zveřejnit jejich neveřejné údaje.
- Výchozí anglický katalog, výsledky hledání, počty, reference, doporučení, sitemap a SEO výstupy neobsahují české události z jiného katalogu, ani přes externí cache nebo výpadkový fallback.
- Oba weby sestavuje stejná šablona landing page, stejné CSS, stejné marketingové moduly a stejné app/SQL/Edge komponenty. Liší se jen validovanými daty profilu a obsahu. Oprava společného layoutu se provede jednou na main.

## Konkrétní kontrakt stejného jádra a původní stránky

Anglická verze je konfigurace existující stránky. Zachovává její informační strukturu, hierarchii, rozvržení, vizuální styl, animace, video přehrávač a cestu ze stejného CTA do stejného průvodce založením akce. Nevzniká nový design, framework, komponentová sada ani anglický fork šablony. Při úpravě je autoritou aktuální implementace původní stránky na zvolené kanonické revizi, ne starší screenshot nebo kopie v jiném worktree.

| Oblast | Jediný sdílený vlastník | Povolená odlišnost EN |
| --- | --- | --- |
| Marketingové HTML a layout | `automation/release/organizers/page.html`, `page.css`, `render_content.mjs`, `render_organizer_page.mjs` | Texty, locale, bezpečné odkazy, povolené reference, média s EN obsahem. |
| Chování a média | `web_client/src/marketing/landing.js`, `motion.js`, `reference_carousel.js`, `demo_player.js`; schéma `clips.json` | Obsahové manifesty a mediální assety; stejné ovládání, reduced motion a lazy loading. |
| Obsah a metadata | stávající `content.json.publicProjection` a validovaný locale/profile výběr | Anglická projekce pod stejným schématem; pravdivá tvrzení o Stripe místo bankovního QR. |
| Katalog a veřejné stránky | stejné JS/Flutter obrazovky, katalogová SQL projekce, edge SEO | Organization ID, explicitní zdroje, texty a locale; žádný český event feed. |
| Pořadatelský průvodce | `lib/components/occasion/setup/occasion_setup_*`, existující form/blueprint/ticket editory | Překlady, lokalizované výchozí vzory a serverový default plateb. |
| Checkout, platby, doručení a scan | stávající SQL/Stripe Edge Functions, queue, renderery a admission | Příjemce dle jednotky, povolené metody, locale; stejný ledger a stavové automaty. |
| Build, hosting a offline shell | `build_web_bundle.sh`, `apply_config.sh`, `cloudflare_build.sh`, stávající PWA pipeline | Tenant config, origin, locale a asset manifest. |

**Hranice dat:** `automation/project.conf` vlastní public brand/domain/language a aktivaci existujících schopností. Organization config vlastní katalogové zdroje a platební default. Locale manifest vlastní publikovatelný marketingový obsah. Secret store vlastní Stripe/sender credentials. Nevytvářet nový mega-config, ve kterém frontend rozhoduje o oprávnění nebo povolení plateb.

**Výběr landing page:** současné hardcoded `vstupenky.online` v rendereru, Worker generátoru a sitemap nahraď jedním explicitním tenantovým přepínačem existující pořadatelské stránky, pracovně `WEB_ORGANIZER_LANDING_ENABLED`, s výchozí false pro ostatní tenanty a explicitní true pro oba ticketing profily. Ověř existenci ekvivalentního klíče a pokud již existuje, použij jej místo nového. Locale pochází ze stejné jazykové konfigurace jako zbytek webu. Generovaný config, router, renderer a PWA musí číst tento kontrakt shodně. Žádný seznam domén zduplikovaný v několika souborech.

**Výběr obsahu:** zachovej schéma a pipeline `publicProjection`, rozšiř je o validovaný výběr jazykové varianty. Existující český obsah je výchozí pro český profil; chybějící povinný EN obsah znamená chybu sestavení EN profilu. Nepoužívat runtime fallback na celý český dokument. Stejný princip platí pro hardcoded popisky playeru, reference carouselu, hero a CTA v `render_content.mjs` a rendereru. Interní research a neveřejné podklady se dál neserializují.

**Zachování struktury:** hero a hlavní CTA -> důkazy produktu a ukázky -> existující funkční sekce formuláře/plánku/vstupenek/správy -> obchodní informace a FAQ -> finální CTA a kontakt. Konkrétní pořadí sekcí přebírá aktuální `page.html` a obsahové manifesty. Nezavádět alternativní EN pořadí ani přepis celé stránky pro Stripe. U platební sekce změnit konkrétní text a ukázku na kartu a jasnou identitu příjemce; zbytek předvádí tentýž produkt.

**Reference a ukázky:** na EN se automaticky nepřebírají české event cards z `content.json.publicProjection.references`. Prázdná reference sekce se stejným rendererem nevykreslí; není vyplněna českými akcemi ani fiktivními zahraničními referencemi. Obecné produktové ukázky lze převzít, pokud neprezentují českou událost jako aktuální EN nabídku. Produktová videa převzatá ze stejné stránky povinně znovu natočit se skutečně anglickým rozhraním a anglickými ukázkovými daty ve stejném editoru. Překryv českého záznamu anglickými titulky tento požadavek nesplňuje. Pro statické obrázky použít odpovídající anglické výstupy. Záznam se nesmí vydávat za uskutečněný nákup.

**Cesty:** pro oba ticketing profily `/` marketing, `/events` katalog, stávající login a aplikační deep linky, `/form/<slug>` veřejná objednávka a stávající `/stripe/*` návraty. Použij existující normalizaci legacy URL a zachovej query parametry; nezakládej `/en` duplikát pro jednojazyčnou subdoménu. Jiní tenanté si ponechají současné root/forced-occasion routování.

## Matice shody s původní stránkou

| Povrch | Požadovaný výsledek | Akceptační důkaz |
| --- | --- | --- |
| Hero, navigace, CTA | Stejná kompozice a chování, anglické texty; přechod do existujícího login/setup. | Dvojice lokálních CS/EN renderů ze stejné revize, desktop + mobil, funkční odkazy. |
| Funkční sekce a galerie | Stejné šablony a pořadí; anglické popisky/alt; žádný český referenční feed. | Výstup jednoho rendereru se dvěma locale daty a kontrola asset provenance. |
| Platby | Karta je hlavní sdělení i skutečný default; žádná falešná funkce typu nepodporovaná měna/záloha. | Obsahový průchod + skutečná odpovídající sandboxová objednávka. |
| FAQ, ceny a kontakt | Stejné obsahové sloty, platné EN podklady a skutečný kontakt. | Renderovaná stránka bez placeholderů a bez nepodložených cenových tvrzení. |
| Bez JS / reduced motion / offline | Čitelný statický dokument, přístupné CTA, stejné ovládání, správný tenantový PWA shell. | Existující renderer/PWA test seams pro oba profily, cílený browser check. |
| Prázdný katalog | Anglická informace a relevantní CTA, žádné české karty, počty ani fallback. | SQL + UI nad prázdným EN katalogem vedle naplněného CS katalogu. |

Shoda neznamená přesně stejnou výšku přeloženého odstavce. Znamená stejné zdroje a layout pravidla, použitelnost při jiných délkách textu a odstranění zbytečných rozdílů mezi klienty/profily. Nové testy nemají opisovat anglické věty; mají prokazovat výběr profilu, strukturu, odkazy a finanční/katalogové invarianty.

## Implementační vlny

### 1. Kanonický zdroj, závislosti a profil

**Cíl:** připravené sdílené základy a jednoznačný profil bez přepsání souběžné práce.

Zjisti upstream main a stav Stripe/landing změn podle výše uvedených plánů. Pracuj v čistém izolovaném worktree; současný dirty strom nestashovat, neresetovat a nepřenášet jako celek. Začlenění Stripe připrav podle existujícího readiness plánu, nevytvářej konkurenční migrační sadu. Zapiš zdrojové revize a přesné dosud nesplněné brány.

Připrav nový tenantový overlay podle `tenant_overlays.md`, config schema a allowlistu vlastněného main. Konfiguruj anglický název/popisy, HTTPS origin, ticketing-only režim obdobný českému tenantovi, jazyk en, loga/PWA, právní URL a canonical backend. Reálné ID organization a aktivační hodnoty patří až ověřenému provisioningu; lokální profil používá jen izolovanou testovací identitu. Rozšíření registru/drift politiky implementovat na main dříve než nový overlay. Privátní provisioning a secrets patří schválenému private-input kontraktu.

**Migrace/kompatibilita:** nová organization bez kopírování českých zákazníků, účtů, objednávek, šablon s tokeny nebo finanční historie. Nepředpokládat, že production branch je úplný aktuální zdroj shared kódu.

**Ověření:** relevantní `automation/tests/tenant_config_matrix.test.sh`, config/legal fixtures a main-owned drift checker nad připraveným overlay. Výstupem je deterministický profil a manifest závislostí; registrace není prohlášena za živou.

### 2. Anglická veřejná i pořadatelská cesta

**Cíl:** jazyk je konzistentní od vstupní stránky po správu akce.

Propoj `WEB_SUPPORTED_LANGUAGES` a výchozí en do JS, Flutter a generovaného HTML. Prověř `apply_config.sh`, `app_config.js`, `app_config.dart`, `LocalizationService` a `EasyLocalization`; pevnou češtinu odstranit ve sdílené autoritě konfigurace, nikoli ručním přepisem build výstupů.

Zobecni `automation/release/render_organizer_page.mjs`, `organizers/render_content.mjs` a `automation/cloudflare_build.sh` podle výše popsaného kontraktu. Zachovej `page.html`, `page.css` a stejný Vite marketingový entry; nepřidávej `page.en.html`, EN CSS ani jiný landing renderer. Z rendereru odstraň český apex guard a nahraď ho validací nakonfigurovaného HTTPS originu. Lokalizuj i `lang`, JSON-LD, OG locale a hardcoded přístupné popisky. Doplň anglický obsah pod společné schéma a fail-closed validaci jeho povinných polí.

Lokalizuj katalog `/events`, formuláře, plánky, objednávky, waitlist, chyby, přihlášení/registraci/reset, založení akce, produkty, editor a přehledy. Počítej s dlouhými anglickými texty a mobilem. Uživatelsky potvrzený požadavek: všechna produktová videa přebíraná z původní stránky znovu natočit v anglickém UI. Zachovat jejich scénáře, účel a umístění; česká videa nejsou přípustný EN fallback a vynechání videí není dokončením této vlny. Připrav také odpovídající anglické postery, titulky/popisky a případný hlas. Referenční obrázky se zapečenou češtinou opatři anglickou verzí skutečného UI. Marketing má vysvětlit kartu, nikoli vést primárně na české QR placení.

Veřejný shell a SEO musí mít en, vlastní canonical a anglické popisy/OG obrázky v prvním HTML i po hydrataci. Uprav `seo_service.js` a společnou projekci `public_page_seo.js` i odpovídající edge render tam, kde vytváří metadata. Zachovej noindex privátních objednávek a capability/Stripe návratů. Hreflang přidej pouze pro skutečně ekvivalentní stránky, nikoli mezi nesouvisejícími katalogy či akcemi.

**Migrace/kompatibilita:** sdílené překlady zůstávají na main, nevytvářet anglické kopie komponent v tenant větvi. Výchozí český profil zachovat.

**Ověření:** `automation/tests/organizer_page.test.mjs`, `automation/tests/public_seo.test.mjs` a relevantní `pwa_manifest.test.mjs`/`pwa_offline.test.mjs` rozšiř cíleně pro CS/EN profil a zachování chování třetího tenantu. Dále cílené JS SEO/config testy, dotčená Dart analýza a jeden izolovaný headless průchod hostem s en profilem. Při realizaci použij repository runnery a ověř aktuální názvy příkazů. Zkontrolovat také raw HTML bez JS, mobil a chybovou/obnovovací cestu. Výstup: návštěvník i nový pořadatel dokončí hlavní cestu v angličtině.

### 2a. Přetočení produktových videí v angličtině

**Cíl:** všechny produktové klipy používané na anglické stránce mají novou skutečnou anglickou nahrávku, při zachování původní prezentace produktu.

Po ustálení EN UI vytvoř inventář z `automation/release/organizers/clips.json`, návazností v `content.json.publicProjection` a skutečného `page.html`. Pro každý používaný klip zapiš původní scénář, cílovou sekci, desktop/mobile varianty, poster, stav EN záznamu a zdrojovou revizi. Počet odvoď z aktuálního manifestu, nikoli z historického počtu videí. Zahrň i další vložená videa objevená v publikovaném layoutu.

Při vlastním natáčení použij skill `product-demo-video` a existující postupy `automation/landing_capture/README.md`, scénáře a capture tooling. Nejdříve přečti jejich aktuální pravidla; nevytvářej nezávislou nahrávací pipeline. Natáčej ve vlastní izolované session se syntetickou anglickou akcí, názvy produktů, odpověďmi a náhledy vstupenek. Bez osobních údajů, skutečných zákazníků či capability/secrets v záběru. Ukázka platby má odpovídat Stripe-first cestě; sandboxový záznam nesmí být prezentován jako skutečný komerční prodej.

Zachovej původní sdělení, kompozici a srozumitelnost každého klipu. EN rozhraní musí být anglické i v dialozích, validačních stavech a výstupních dokumentech viditelných v záznamu. Pokud existují titulky, grafické texty nebo voiceover, připrav jejich anglickou verzi; nové namluvení nezaváděj, pokud původní klip hlas neměl. Z nových záznamů vytvoř příslušné desktop/mobile web exporty a postery, metadata a přístupné popisky. Capture masters zůstávají mimo Git podle stávajících pravidel, do repozitáře patří jen schválené web exporty a provenance.

Locale/profile manifest vybírá EN assety; přehrávač, CSS a způsob lazy load jsou stejné jako v české variantě. České assety zachovej pro českou stránku. Žádné přejmenování českého souboru na EN ani tiché doplnění českého klipu při chybějící variantě. Chybějící EN video blokuje označení mediální sady a veřejného EN releasu za dokončené; rozpracovaný lokální preview smí tento stav explicitně přiznat.

**Ověření:** existující mediální verifier podle `automation/landing_capture/verify_media.py` a podporovaného postupu, skutečné přehrání všech EN klipů v izolovaném browseru, správný poster a výběr desktop/mobile exportu. Zachovat reduced motion/Save-Data, ruční spuštění a fallback při chybě média. Videa se nadále nepřidávají do kritického PWA precache. Zkontrolovat čitelnost UI a absenci českého systémového textu v záběrech, ne jen názvy souborů.

**Výstup:** kompletní matice původní klip -> nově natočené EN varianty/poster/revize a funkční anglická stránka s hotovou mediální sadou. Natáčení je samostatná závislost po EN UI, před konečnou akceptací stránky a releasem.

### 2b. Izolovaný katalog bez českých událostí

**Cíl:** anglický web nemá žádný implicitní přísun českých akcí, ani při prázdném katalogu nebo chybě.

Kanonickým vlastníkem výběru je serverová projekce katalogu. Začni `database/functions/others/get_available_occasions.sql`, zejména globálním `OR c.source_name IS NOT NULL`, a porovnej `get_public_occasions.sql`, které používá Flutter přes `lib/components/unit/db_units.dart`. JS používá `web_client/src/components/occasion/db_occasions.js`; dohledat všechny přímé i dynamické callery obou RPC, Worker `publicOccasions` a feed writer `external_occasions_cache`.

Zaveď explicitní organizační politiku připuštěných externích zdrojů ve stávajícím konfiguračním modelu. Nový tenant má prázdný allowlist. Pokud už source registry existuje, rozšiř jej; nevytvářej druhý registr ani anglické katalogové RPC. Současné globální přibírání externích řádků nesmí být novým defaultem při absenci policy. Při migraci inventarizuj dosavadní použití a pro existující oprávněné katalogy explicitně zachovej dosud zamýšlené zdroje; neodstraňuj jim nabídku potichu. Nesmí vzniknout runtime bypass typu `tenant != english` ani neomezený `includeAllExternal` z prohlížeče.

Sjednoť organizační/source predicate pro JS, Flutter, sitemap a související katalogové projekce při zachování rozdílů jednotlivých use cases. Neměň plošně pravidla open/promoted/hidden, archivace nebo dostupnosti formuláře. Serverová politika výběru musí omezit i agregace/počty, stránkování a hledání; pouhé odfiltrování karet po fetchi nestačí. Přehled povolených zdrojů smí měnit pouze příslušná serverově ověřená role.

Sitemap z `automation/cloudflare_build.sh` dnes vychází ze stejného katalogového načítání; filtr stejného originu sám nestačí, pokud se cizímu slugu předtím přiřadí anglická doména. Ověř filtrování před sestavením URL. Cache musí mít tenant/org a relevantní jazyk či policy revizi v klíči; invalidace po změně zdrojů nesmí dočasně přehrát český feed. Selhání backendu vrátí anglický chybový stav nebo bezpečný poslední obsah stejného tenantu.

Přímý veřejný odkaz na českou akci není požadavkem zakázat přístup k této akci na jejím českém originu. Na anglickém originu však nesmí vzniknout její indexovatelná kopie. Dohledej existující slug binding/canonical kontrakt a použij jej: nepatří-li objekt do veřejné projekce tohoto hostu, vrať odpovídající not-found nebo existující ověřený canonical redirect, nikdy fallback katalogu. Nevytvářej nový systém aliasů a neslibuj hostname jako autorizační hranici veřejné akce. Privátní data nadále chrání vlastní oprávnění.

**Migrace/kompatibilita:** kanonický SQL predicate a forward migrace policy musí předcházet anglické publikaci. Žádné mazání nebo přejmenování českých událostí, změna jejich jazyků, kopie event tabulek ani migrace českých objednávek. Zdroje nového tenantu se mohou později přidat jen výslovnou správou, nikoli automaticky kvůli stejnému jazyku.

**Ověření:** jedna cílená SQL fixture s EN organizací, českou organizací, cizím promoted externím řádkem a hidden/unpromoted řádky. Prokázat EN prázdný katalog, EN pouze vlastní způsobilé akce, explicitní povolení jednoho zdroje bez ostatních a zachování schválené české nabídky. Ověřit obě RPC a edge sitemap na stejných datech. UI test pro search/empty/error a cache střídání dvou tenantů. Výstup: nikde není implicitní česká nabídka.

### 3. Výchozí Stripe a onboarding pořadatele

**Cíl:** nová placená akce začne správnou metodou a příjemcem bez bankovní závislosti.

Dohledej deklarace a callers tvorby formuláře a průvodce přes `create_form_internal_v1.sql` a `form_settings_content.dart`. Vytvoř jeden serverově vlastněný tenantový default ve stávajícím organization konfiguračním kontraktu; nezaváděj hostname podmínky ani souběžný platební DTO. Žádný nový klíč nepřidávej přímo do `forms.data.payments` bez úpravy validátoru, který dnes povoluje pouze `bankEnabled` a `stripeConnectionId`.

Neexistující Connect vazba znamená explicitní nepřipravenou platbu. Pokud současný validátor neumí uložit draft bez banky i bez připojeného Stripe, rozšiř pouze stav konfigurace draftu a serverovou bránu publikace/prodeje; nepoužívej falešné connection ID nebo dočasně zapnutou banku. Audituj i přímé veřejné RPC, aby bylo možné draft uložit, ale zaplacenou objednávku bez platné metody vytvořit nešlo. Hotový formulář má ověřenou unit-scoped connection a explicitní `bankEnabled=false`.

Proveď anglickým Connect onboardingem, vysvětli příjemce/platební poplatky podle skutečného modelu, zobraz stav účtu a blokující omezení. Ověř editaci, duplikaci formuláře/akce, re-open draftu a výslovnou volbu banky/obou metod. Kopírování nesmí přenést účet příjemce do jiné jednotky nebo organizace. Stávající formuláře ani již vytvořené platební pokusy se defaultem zpětně nemění.

Pro JS `payment_method_picker.js` a Flutter platební UI zachovej stejné SQL pořadí a zacházení s nedostupností. Checkout jazyk musí být en i v prohlížeči s cs preferencí: prověř `supabase/functions/_shared/stripe/provider.ts` a přidej důvěryhodný locale údaj do existujícího serverového snapshotu/kontraktu, pokud chybí. Jazyk z neověřeného requestu nesmí ovlivnit příjemce, cenu nebo return origin.

**Migrace/kompatibilita:** případné nové config/locale údaje a kontrakty mají kanonické SQL zdroje a forward migraci. Dříve publikované migrace neměnit. Bez paralelního platebního enginu nebo persistentních aplikačních triggerů.

**Ověření:** SQL create-order/form-availability/recipient a cross-tenant negativní testy, oba klientské method-picker kontrakty; nepřipojený účet, změna příjemce mezi review/submit, restriction, banka pouze explicitně, bezplatná registrace. Výstup: karta je primární na novém tenantovi, české defaulty zůstaly stejné.

### 4. Anglické e-maily, PDF, finance a podpora

**Cíl:** po dokončení UI nezůstane zákazník v české servisní komunikaci.

Použij existující organizační šablony/wrappery a resolver dědičnosti. Připrav anglické potvrzení, čekání na platbu/připomínku, zaplacení, aktualizaci/storno, waitlist confirmation/offer a používané Auth zprávy. Projdi `send-email/`, `_shared/emailRenderer.ts`, `_shared/stripe/email.ts`, `_shared/ticketGeneration.ts` a `_shared/ticketDate.ts`: locale předávej z důvěryhodného existujícího kontextu, pro nový tenant fallback en. Pokud kontext není uložen, doplň ho v kanonickém produceru; nevytvářej druhý sender.

Ověř anglický subject, systémové labely, datum/časové pásmo, přesné částky a všechny odkazy z obnovení pošty, ticket PDF i přehledu objednávky. Ticket layouty a obsah pořadatele musí mít anglické výchozí vzory. Nepoužívej bankovní VS, bankovní QR ani instrukce k doplatku jako výstup Stripe-only objednávky. Samostatně zachovej QR k odbavení. Zaplaceno neznamená doručeno a refundace/dispute mají odpovídající anglické stavy i admission ochrany.

Tenantové právní a support Markdown zdroje v `automation/release/legal/` přelož podle skutečných provozních údajů, vygeneruj kanonické public URL včetně delete-account. Odesílatel, reply-to a kontaktní kanál musí být skutečné a ověřené; DNS autentizaci odesílatele přidávej jen pokud ji zvolená stávající identita vyžaduje. Žádná nová fronta nebo obejití SES limitů.

**Migrace/kompatibilita:** seed jen nových tenantových šablon, idempotentně přes existující kontrakt. České šablony/overrides a staré frontové zprávy nepřepisovat.

**Ověření:** skutečné renderování běžné/paid/cancel/waitlist/Auth zprávy do lokálního mail capture a PDF z reálné testovací objednávky; ticket QR a částky, locale, link origin, send-time eligibility. Výstup: celá doručená servisní sada je anglická a finanční údaje souhlasí se SQL.

### 5. Provozní příprava a úplná sandboxová akceptace

**Cíl:** konkrétní release manifest a důkaz funkčnosti před povolením ostrých plateb.

Připrav přesné hostname/tenant/organization/unit/form/měna/revize/build a backend manifesty. Po autorizaci provisioningu nastav novou organizaci, důvěryhodné `DEFAULT_URL`, RBAC a příslušné katalogové/source registry bez náhodného sdílení českých dat. Zkontroluj backend activation, GoTrue site/redirect allowlist, Google OAuth, shared web CORS, image Worker, případný sync, CSP/embedding a cache/service-worker scope. `STRIPE_ALLOWED_ORIGINS` rozšiř aditivně o přesný origin; změna společného callbacku nesmí rozbít existující tenanty. Callback musí používat existující actor/tenant-bound state, nikoli otevřený return redirect.

V Stripe konfiguraci použij připnutou a otestovanou API verzi z runbooku; samotné čtení nové dokumentace není důvod k jejímu upgradu. Připrav správné test/live klíče, Connect callback a connected-account webhook s oddělením prostředí. Existující sdílený webhook neregeneruj pro každou doménu; ověř jeho account/mode/tenant vazby. Secrets pouze ve schváleném úložišti. Proveď finální baseline/upgrade replay podle readiness plánu, pokud ještě není doložen pro výslednou revizi.

Připrav DNS/TLS a hosting podle existující přímé deployment pipeline. Před aktivací měj zdravý reconciliation scheduler, receipt readback, doručování, alerty a operátora. Globální runtime Stripe policy se nejdřív instaluje s novými platbami vypnutými; existující recovery/history zůstávají funkční.

**Ověření:** skutečná testovací objednávka na správném účtu přes JS a Flutter web: úspěch, 3DS, decline, Back/cancel, reload, expirovaná rezervace, opakovaný webhook, dva panely, waitlist offer, refundace a online scan. UI + SQL receipt + account-scoped provider readback + e-mail/PDF musí souhlasit. Adresy s capability nepatří do veřejných logů. Bez Stripe secretes musí česká bankovní cesta nadále projít lokální regresí.

**Výstup:** sandboxová akceptace svázaná s revizí a konkrétním hostem/povrchy, připravené provozní kroky a výslovně zbývající produktové brány. Lokální sandbox nesmí být vydáván za live akceptaci.

### 6. Samostatně autorizované spuštění jednoho tenantu

**Cíl:** živá anglická služba a kontrolovaný start plateb.

Před publikací ověř čerstvý upstream main a integruj ovlivňující souběh. Shared kód publikuj podle repo pravidel; vytvoř jen schválený nový tenant overlay a ověř ancestry/drift. Produkční migrace/config proveď v kompatibilním pořadí z runbooku. Lokálně sestav Flutter a web klienta, nasaď `automation/deploy_direct.sh`; GitHub-hosted produkční build jen na výslovnou žádost. Rutinní deploy, monitoring a live-version ověření deleguj levnějšímu agentovi podle AGENTS.md s přesnými SHA, tenantem a gates. Jiné prod větve neměnit.

Nejprve ověř live build/activation, DNS/TLS, deep links, právní stránky, raw SEO/robots/sitemap a anglické chybové stavy s novými platbami stále vypnutými. Ostrý pilot vyžaduje samostatné přijetí konkrétního účtu/akce/měny a pravidel z runbooku: 31minutová rezervace, dispute hold, online-only Stripe admission, refundace a pozdní platba. Teprve poté povol nové platby pro schválený pilot a proveď autorizovanou skutečnou platbu, ticket delivery a scan. Reálná refundace vyžaduje zahrnutí do autority pilotu.

**Výstup:** zaznamenaná live revize, zdravé recovery a doručování a prokázaná end-to-end anglická transakce. Při nedokončeném pilotu označit službu jako nasazenou s platbami neaktivními, nikoli jako dokončený prodej.

## Zachování a odstranění dotčených cest

| Artefakt/chování | Výsledná akce | Důkaz |
| --- | --- | --- |
| Domain-only guards rendereru/Workeru/sitemap pro `vstupenky.online` | Nahradit jedním tenantovým capability kontraktem se zachováním stejné stránky. | Renderer/routing test CS + EN + neaktivovaný třetí profil; žádné zbylé nezávislé host guards. |
| Globální `OR c.source_name IS NOT NULL` v katalogu | Nahradit explicitní organizační politikou zdrojů; migrovat zamýšlené existující zdroje. | EN empty/own/external negativní SQL fixture + CS regrese + sitemap. |
| České reference v EN publicProjection | Nevkládat do EN projekce; zachovat český obsah pro CS. | Výsledné EN HTML neobsahuje české reference/katalogové odkazy. |
| České systémové fallbacky na anglické cestě, `cs-CZ`, české metadata a média | Nahradit locale/profile kontraktem nebo anglickou variantou v existující pipeline. | Raw HTML, vykreslené UI, skutečný e-mail/PDF; scoped hledání identifikovaných hardcoded hodnot. |
| Implicitně bankovní nové formuláře | Zachovat pro existující tenanty; nový tenant má explicitní serverový default a Connect draft gate. | SQL test nového vs. českého tenantu, clone a přímé create-order RPC. |
| Bankovní platební QR/instrukce u Stripe-only | Na tomto platebním toku nejsou produkovány. Bankovní metoda i admission QR zůstávají. | Skutečný Stripe order result, mail/PDF, bankovní regrese. |
| Český tenant, historie, účty a objednávky | Zachovat v původní hranici; žádný hromadný přesun či přejmenování URL. | Cross-tenant access testy a omezený provisioning manifest. |
| Návrh duplicitního checkoutu, senderu nebo tenantových kopií UI | Nevytvářet; případné pracovní prototypy odstranit před předáním. | Diff a callers vedou k existujícím kanonickým vlastníkům. |

## Ověřování a rollback

Při samotném psaní plánu se nespouštějí testy ani build. Implementace má standardní cílené kontroly podle dotčených hranic, nikoli plošnou testovací kampaň po každém editu. JS používá pnpm 11.24.0 a podporované repo runnery; konkrétní SQL soubory lze spouštět přes `node web_client/scripts/run_db_tests.js <soubor>`. Stripe generátory/replay a concurrency gates přebírá existující readiness plán. Flutter vždy přes fvm, na workstation pouze jeden úkol a testy `--concurrency=1`. Browser jen izolovaně headless podle agent-browser a E2E pravidel. Nepoužívat produkční zákazníky jako fixture.

Minimální matice: totožný renderer/layout pro CS i EN; neaktivovaný třetí profil se stejným chováním jako předtím; EN katalog bez českých/external výchozích řádků včetně prázdného stavu, hledání, reference sekce, sitemap a cache; český profil/banka beze změny; nový anglický profil bez Connect; aktivní Stripe-only; explicitní obě metody; disabled/restricted Stripe; free/waitlist; negativní tenant/recipient přístupy; en prohlížeč i cs prohlížeč na anglickém hostu; přesné částky a akční čas; všechny systémové e-maily a ticket PDF; refund/dispute/admission; restart/návrat z Auth a Checkout. Změní-li se kontrakt nebo migrační pořadí, zopakovat jen ovlivněné důkazy včetně konečného SQL upgrade.

Při potížích zastavit nové Stripe pokusy tenantovou runtime policy a případně publikaci nových prodejů. Zachovat webhook, reconciliation, finanční historii, návraty a refund/admission/email fences. Neodstraňovat nový tenant, objednávky nebo migrace jako rollback. Předchozí klientský build vracet pouze tehdy, umí-li bezpečně zobrazit již vzniklé Stripe objednávky; jinak forward fix nebo jasná servisní stránka. Automaticky nepřepínat zákazníky na banku.

## Definice dokončení a zbývající rizika

- Lokální příprava je hotová, když profil a všechny veřejné/pořadatelské cesty fungují anglicky, Stripe je správný default a cílené testy i skutečný sandboxový nákup/mail/PDF/scan prošly pro zapsanou revizi.
- Produkční spuštění je hotové až po samostatně schváleném provisioningu/deploy, live manifestu a skutečné pilotní transakci s potvrzeným doručením a online admission. Neprovedené kroky zůstávají explicitně otevřené.
- Všechna videa použitá na EN stránce jsou znovu natočená z anglického UI, včetně odpovídajících variant a posterů; provenance a matice dokončení jsou doložené. České klipy ani odstranění původních video sekcí nenahrazují tento požadavek.
- Kódová shoda je doložená: jeden landing renderer/HTML/CSS/marketing entry, jeden průvodce a stávající platební/queue/scan autority, rozdíly pouze v explicitních profilech a obsahu. EN katalog zůstává bez českých akcí i při prázdných datech a chybě.
- České systémové fallbacky a bankovní instrukce nesmí zůstat na anglické Stripe cestě; sdílený produkt nemá tenantové kopie checkoutu či senderu.
- Hlavní technická rizika jsou globální externí feed v katalogovém SQL, původní zapínání landing page jen pro český hostname, dosud neintegrované Stripe/landing změny, dostupnost účtu pořadatele, překlady override šablon a přijetí online-only kontroly vstupu. Mají vlastní implementační a akceptační brány. Výchozí anglický katalog bez českých událostí již není otevřená produktová otázka.

## Navazující autority a externí podklady

- Doménový kontrakt Stripe: `docs/plans/stripe-client-owned-plan-2026-10-21.md`.
- Integrace: `docs/plans/stripe-integration-readiness-plan-2026-10-22.md`.
- Aktivace a provoz: `docs/plans/stripe-client-owned/PILOT-RUNBOOK.md`.
- Aktuální lokální důkazy: `docs/plans/stripe-client-owned/IMPLEMENTATION-STATUS.md`.
- Stripe API umožňuje určit Checkout `locale`; bez něj či při `auto` používá jazyk prohlížeče. Parametr `expires_at` má minimum 30 minut. [Stripe Checkout Session API](https://docs.stripe.com/api/checkout/sessions/create) (ověřeno 2026-10-23). Existující 31minutový kontrakt tímto plánem neměníme.
