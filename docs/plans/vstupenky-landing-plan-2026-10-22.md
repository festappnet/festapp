# vstupenky.online: úvodní stránka pro pořadatele plesů

## Závazné doplnění uživatele - skutečný produkt a čeština

Tato pozdější instrukce nahrazuje konfliktní části původního plánu:
reference jsou menší ručně ovládaný carousel skutečných publikovaných plesů,
archiv má datum a označení Archiv. Všechny vytvářené záběry mají skutečné české
UI i česká ukázková data. Formulář ukazuje skládání otázek, možnosti a povinnost;
původní demonstraci fontů nahrazuje hotový formulář. Vstupenka ukazuje skutečné
tažení textů i QR kódu. Výběr míst používá skutečný veřejný Festapp klient nad
lokální syntetickou akcí; knihovní picker již není přípustný. Skenování je
zobrazené jako telefon, se skutečným mobilním UI v rozpoznatelném rámu.

Obchodní fakta dodaná uživatelem: QR platba bankovním převodem má transakční
poplatek 0 Kč; cena samotné služby se řeší samostatně. Platby kartou jsou možné
po kontaktování vstupenky.online. Ke všem klipům se ukládá reprodukovatelný
postup, fixture a capture/export nastavení pro pozdější jazykové verze nebo
YouTube sestřih; dlouhé video nyní není požadováno. Recipes vlastní
`automation/landing_capture/`, raw takes zůstávají mimo Git.

Datum: 2026-10-22  
Stav: lokální realizace R2/R3/R4 dokončena 2026-10-22; zdrojový marketing, osm klipů a routing implementovány. Žádné nasazení. Závěrečné důkazy viz [implementation-summary.md](vstupenky-landing-evidence-2026-10-22/implementation-summary.md)  
Ověření plánu: cílený průzkum aktuálního stromu, veřejné reference a existujících záznamů; bez buildů a testů  
Ověření realizace: standard, protože se mění veřejné směrování, vstup do aplikace a PWA  
Výchozí checkout: `feat/occasion-setup-wizard-20261007`, HEAD `eb2304724`, rozsáhlý rozpracovaný strom.

## Výsledek a potvrzená rozhodnutí

Po otevření `https://vstupenky.online/` se zobrazí plnohodnotná, pohybově propracovaná landing page. Primární návštěvník je pořadatel plesu. Uvidí skutečné skládání plánku, nákup konkrétních míst a výsledky skutečných klientů. Na první obrazovce pochopí produkt a může začít připravovat akci. Kupující najde katalog jedním kliknutím přes stále viditelné „Akce“.

- **Potvrzeno uživatelem:** landing page přímo na hlavní adrese, inspirace Tickenderem včetně plynulého odkrývání při scrollu a produktového videa; vlastní značka a obsah.
- **Potvrzeno uživatelem:** skládání plánku je povinné, nejde pouze o ukázku výběru hotových sedadel. Plesy jsou hlavní obchodní příběh.
- **Potvrzeno uživatelem:** máme skutečné klientské reference a prodeje; reference jsou součást zadání, jejich získání nepovažovat za obecný blocker ani se znovu neptat, zda je chceme.
- **Potvrzená URL:** katalog používá `/events`, nikoli českou URL. České menu „Akce“ může zůstat.
- **Poslední upřesnění uživatele - hlavní formát:** návštěvník scrolluje stránkou a přímo u jednotlivých funkcí vidí samostatná krátká videa. Povinné jsou plánek, formulář, vstupenka a možnosti jejich přizpůsobení. Jeden dlouhý film není hlavní formát ani podmínka dokončení; případný YouTube sestřih je samostatný volitelný výstup.
- **Rozhodnutí návrhu:** jedna marketingová stránka na `/`; stávající `/pro-poradatele` přesměruje na `/`. Samostatný katalog na `/events`. Bez rozdělení hlavní stránky podle přihlášení.
- **Rozsah nynějšího úkolu:** plán, provedená kritika, porovnání a přesné zadání dalších iterací. Tento dokument neautorizuje nasazení ani nevydává plánované funkce za hotové.

## Hranice

Pracujeme na prezentaci, vlastních médiích, tenantově omezeném směrování a návazných veřejných vstupech. Zachovat existující objednávky, ceny, rezervace, přihlášení, QR a administraci. Do hlavního marketingového bootstrapu nepřidávat Flutter, platební SDK ani dotazy na objednávky.

Platí pouze pro `vstupenky.online`, případně při pozdějším výslovném nasazení pro `prod/festapptickets`. Ostatní tenanty nemigrovat na `/events` ani jim nezobrazovat naši landing page. Kód zůstává vlastněný canonical main. Do rozpracovaného stromu jiných úkolů nezasahovat a neswitchovat jej naslepo.

Vlastní editor ani obchodní backend se v tomto projektu nevyvíjí. Existující editor se použije jako zdroj záběrů. Pokud host integrace některou ukázanou funkci ještě nemá, nepředstírat ji: doložit ji skutečným veřejným package example jako samostatně přiznanou ukázkou editoru, nebo nejprve dokončit konkrétní host seam samostatným úkolem. Nevytvářet kvůli landing page druhý editor.

## Ověřené výchozí důkazy

| Fakt | Konkrétní vlastník | Důsledek |
|---|---|---|
| `/` dnes servíruje JS katalog se serverovými odkazy na akce; `/pro-poradatele` má vlastní HTML. | `automation/cloudflare_build.sh`: `routeRequest`, `handleHome`, `handleSitemap`, `ORGANIZERS_ENABLED` | Nestačí překreslit hero v katalogu. Přesunout katalog včetně SEO a opravit explicitní směrování. |
| Marketingový generátor vytváří `web/organizers-page`, v bundlu `build/web/organizers-page`; canonical je dnes `/pro-poradatele`. | `automation/release/render_organizer_page.mjs`, `automation/release/organizers/page.html`, `page.css`, `automation/build_web_bundle.sh` | Použít stejného vlastníka a přepsat cílový kontrakt. Neupravovat ručně generovaný výstup. |
| Generátor dnes také přepisuje značkovanou navigaci v `web_client/index.html`. | `ORGANIZERS_NAV_START/END` | Změnit odkaz v katalogu na aktuální hlavní stránku, odstranit obsolete text i cílovou URL. |
| `/?create=1` otevírá existující registraci nebo administraci. Handler je omezený na pathname `/`. | `web_client/src/startup/organizer_intent.js`: `handleOrganizerIntent`; `main.js` | Nový kanonický vstup je `/events?create=1`; aktualizovat guard, ponechat starý vstup jako redirect. |
| Root JS řeší legacy hash odkazy před další navigací. Normalizace zpracuje `#/...`; skener má čistý resolver. | `web_client/src/services/router_service.js`: `normalizeUrl`, `handleInitialLoad`; `scanner_routes.js`: `resolveScannerRoute` | Nová statická root stránka musí zachovat staré hash odkazy včetně query. Worker fragment nevidí. |
| Katalog se montuje do `events-grid` až po bootstrapu; jeho komponenty a klasifikace už existují. | `web_client/index.html`, `src/main.js`, `components/unit/unit_page.js`, `components/occasion/catalog.js` | Na `/events` znovu použít katalog, nikoli vytvořit nový seznam. |
| Precache dnes sbírá téměř všechny soubory v bundlu. | `automation/lib/pwa_shell_manifest.mjs`: `shouldPrecache`, `collectPwaShellManifest`; `generate_pwa_service_worker.mjs` | Videa nesmějí automaticky zvětšit PWA install. Prověřit také offline navigaci na `/` a `/events`. |
| Host blueprint UI a nový samostatný editor nejsou totéž. | Festapp `lib/components/blueprint/views/blueprint_editor_tab.dart`: `BlueprintTab`, `VenueSeatController`; sibling `venue_seat_picker/example/README.md`: `VenueLayoutEditor` | Natáčení začne identifikací skutečného zdroje editoru. Nenavázat platební tvrzení na lokální geometrické demo. |
| Sibling example má skutečné editování, společný dokument a handoff do JS pickeru; jeho rezervace a ceny jsou syntetické. | `/Users/miakh/source/venue_seat_picker/example/README.md`, `doc/demo.webm`, `doc/demo.gif` | Znovupoužít zkušenosti a vhodné takes pro geometrii, ne důkaz fungování plateb nebo produkční rezervace. |
| Značka má Futura a tenantové barvy. | `automation/project.conf`: `FONT_FAMILY_BASE=Futura`, `THEME_SEED_1..4`; existující theme CSS | Neimportovat konkurenční typografii ani generický fialový SaaS design. |
| Aktuální analytics rozhodnutí jsou pouze serverové souhrny bez browser beaconu. | úvod `docs/plans/vstupenky-analytics-plan-2026-10-20.md` | Přesné video/click eventy nepřidávat kvůli experimentu. Iteraci hodnotit laboratorně a existujícími souhrny. |
| Živá stránka pořadatelů je propracovanější než zdejší starší HTML šablona. | prohlédnuté `https://vstupenky.online/pro-poradatele` vs. současný `page.html` | Před implementací zaznamenat zdrojovou/live odchylku, převzít hodnotný obsah a rezervaci ukázky. Nikdy nepovažovat checkout za automaticky totožný s live. |

Vizuální a video rozbor Tickenderu je v místním balíčku `/Users/miakh/Downloads/festapp-tickender-reference-2026-10-22/`: `index.html`, `manifest.json`, `tickender-reference.mp4`, `tickender-scroll.mp4` a veřejné animační zdroje. Obsahuje 25 scén a přesná časování. Referenční média držet mimo produkční assets a Git; do naší stránky patří vlastní záběry.

## Návrh obsahu a přesná hierarchie

### 1. Hlavička a první obrazovka

Sticky hlavička: naše logo odkazuje na `/`; navigace „Ukázka“, „Reference“, „Jak to funguje“, „Cena“, výrazně dostupné „Akce“ → `/events`; „Moje akce“ → existující `/admin`; hlavní CTA „Připravit ples“ → `/events?create=1`. Na mobilu nechat viditelné logo, „Akce“ a menu; CTA je v hero a může se po jeho odscrollování objevit v úsporném spodním panelu. Panel nesmí zakrýt video, consent ani footer.

Hero text R2:

> **Od plánku sálu po poslední vstupenku.**
>
> Sestavte sál, prodávejte konkrétní místa a mějte platby i příchod hostů pod kontrolou.

Primární tlačítko „Připravit ples“. Sekundární „Prohlédnout možnosti“ posune na `#ukazka`, první sekci s vlastním klipem plánku. Neotevírá centrální přehrávač ani dlouhé video. Pod CTA stručné vysvětlení účtu podle skutečného registration toku, bez neověřených časových slibů a slibů o nulových poplatcích.

Pravá strana desktopu: skutečný záběr hotového sálu s čitelným navazujícím výběrem dvou míst na mobilu. Poster je vidět ihned. Hero se účastní stejného řízení viditelnosti jako ostatní klipy; při příchodu do první produktové sekce se jeho teaser zastaví. Doporučené živé chování: krátký vlastní 6-8s teaser ukazující umístění jednoho stolu a doplnění židlí, pouze pokud je hero dostatečně viditelný; ovladatelná pauza. Při reduced motion a úspoře dat pouze poster. Teaser může být výřezem samostatného klipu `layout-build`; nepodmiňuje se dlouhým masterem.

Šířka obsahu 1200 px, desktop 12 sloupců (text 5, produkt 7), gutter 24 px, hero vnější mezery 72-96 px. Na 390 px jeden sloupec: nadpis, krátký text, CTA, produktový poster; bez zmenšování celé administrace do nečitelného thumbnailu. H1 cca 64-76 px na velkém desktopu, 38-44 px na mobilu, body 18 px / 1,5; skutečné zalomení ověřit na 320 px i s Futurou. Bez horizontálního přetečení.

### 2. Reference bezprostředně po hero

Nadpis „Už pomáháme skutečným pořadatelům“. První řada 3-5 existujících klientských názvů/log. Pod ní nejvýše tři doložené výsledky: například zaplacené vstupenky, realizované akce a počet pořadatelů. Konkrétní hodnoty se berou z existujících referencí, ne z demo fixture.

Implementátor najde oprávněně používané existující podklady v projektu a dosavadních marketingových materiálech a vytvoří jeden manifest `automation/release/organizers/content.json`. Záznam má klienta/akci, logo/fotografii, přesné znění citace a autora/roli, používaný veřejný odkaz, metriku a její význam/období a interní odkaz na zdroj. Soukromé podklady se do public manifestu nekopírují; generátor emituje pouze explicitní veřejnou projekci. Reference nejsou brána pro celý projekt: nejprve použít dostupné skutečné jméno/logo/citaci; nedoloženou číselnou metriku nezobrazit. V hotové stránce nejsou prázdné reference, generické avatary ani „doplnit číslo“.

### 3. Funkce odkrývané při scrollu - hlavní formát stránky

Kotva `#ukazka` je začátek série produktových sekcí. Žádný centrální 55s přehrávač ani nutnost sledovat souvislý film. Návštěvník scrolluje přirozeně a v každé sekci má krátký text a samostatný skutečný klip dokazující právě danou funkci. Na desktopu střídavě text vlevo/video vpravo a opačně; video zabírá přibližně 7 z 12 sloupců. Na mobilu nadpis a vysvětlení před videem, výřez přizpůsobený konkrétnímu ovládání.

Tři hlavní produktové sekce jsou **plánek → formulář → vstupenka**. Každá ukáže vytvoření/obsah a možnosti vzhledu. Další sekce ukazují zákaznický výběr, odbavení a přehled. Každá dává smysl i člověku, který předchozí klip přeskočil. Reference a CTA jsou normální obsah stránky, nikoli závěrečný slide povinného filmu.

| Sekce / kotva | Samostatný klip | Délka střihu | Co návštěvník uvidí |
|---|---|---:|---|
| „Sál poskládáte podle sebe.“ / `#planek` (také `#ukazka`) | `layout-build` | 12-18 s | Drag stolu z palety, přidání židlí, skutečná kopie sestavy, čitelný hotový sál. |
| Stejná sekce, volba „Vzhled plánku“ | `layout-style` | 8-12 s | Výběr více objektů, změna podporovaného stylu/barvy a označení, okamžitý výsledek na stejném sále. |
| „Formulář podle vaší akce.“ / `#formular` | `form-build` | 10-14 s | Přidání vlastního pole a jeho možností, změna pořadí/povinnosti podle skutečných ovládání, výsledek ve veřejném formuláři. |
| Stejná sekce, volba „Vzhled formuláře“ | `form-style` | 8-12 s | Skutečná změna barevného presetu/hlavní barvy a fontu; stejné údaje ve dvou rozdílných vzhledech. |
| „Vstupenka ve vašem stylu.“ / `#vstupenka` | `ticket-design` | 10-15 s | Úprava skutečné šablony vstupenky: obrazový motiv, rozmístění a typografie dostupnými ovládáními; výsledná PDF vstupenka s odpovídajícími údaji a QR. |
| „Hosté si vyberou konkrétní místo.“ / `#vyber-mist` | `seat-select` | 8-10 s | Reálný úzký zákaznický viewport, dvě sousední místa, jejich označení a celková cena. |
| „U vstupu máte jasno.“ / `#odbaveni` | `check-in` | 6-10 s | Skutečný demo QR, přijatý vstup, změna počtu, druhé načtení a varování. |
| „Objednávky a platby po ruce.“ / `#prehled` | `orders-overview` | 8-10 s | Skutečný přehled, rozlišení stavů a dostupný export; čitelné syntetické demo údaje. |

U plánku a formuláře mají dvě lokální tlačítka „Sestavení / Vzhled“ a „Pole / Vzhled“ přepínat **dva samostatné klipy téže funkce**. Nejde o globální kapitoly jednoho filmu. Výchozí je první klip a druhou možnost zviditelňuje jasný popisek; při ručním přepnutí se změní poster, popis a zdroj. Každá volba je dostupná klávesnicí, má vyznačený stav a zachovává rozměr panelu. Přepnutí nesmí skrýt jediný popis možností customizace; klíčové možnosti jsou i v běžném textu. Vstupenka má vlastní výraznou sekci a nesmí být jen dvě sekundy potvrzení nákupu.

### 4. Přizpůsobení jako viditelná schopnost produktu

Customizace je povinná ve všech třech hlavních sekcích, nikoli obecné tvrzení „vše podle vás“. Každý customizační klip má **výchozí vzhled → skutečnou změnu ovládáním → čitelný změněný výsledek**. Pro formulář jsou ve zdroji ověřené presety, hlavní barva a výběr fontu (`lib/components/forms/views/form_design_settings.dart`, `form_design_content.dart`). Obsah formuláře vlastní `form_editor_content.dart`. Šablonu vstupenky vlastní `lib/components/ticket_layout/views/ticket_layout_editor.dart`; konkrétní použité úpravy v něm ověřit při zkoušce, neslibovat neexistující nástroj. V plánku používat pouze skutečně přístupné style/label/group ovládání z vybraného editoru.

Vizuální varianta může být slavnostní ples a kontrastní moderní akce; je to designový cíl, nikoli požadavek přidat dvě nové systémové šablony. Pracovat s existujícími ovládáními a stejnými obsahovými údaji. Ukázat vlastní obrazový motiv pouze tam, kde ho produkt skutečně umožňuje.

Přehrávání se spouští **při vstupu sekce do viditelné části stránky**, nikoli odrolováním jednotlivých framů. Žádný scroll-scrubbing ani povinně pinovaná sekce. Uživatelský scroll nesmí čekat na dohrání klipu. Na stránce je najednou aktivní nejvýše jeden klip, včetně hero; viditelný klip má ovládání pauzy a znovupřehrání. Přesný stavový kontrakt je v pohybovém systému níže.

### 5. Případová studie a další typy akcí

Jedna výrazná skutečná reference: pořadatel, konkrétní ples, fotografie, krátká přesná citace a doložený výsledek. Klientský údaj vizuálně odlišit od demo obrazovek. Následuje klidná sekce „A když nepořádáte ples?“ se stručnými možnostmi koncertů, kurzů a víkendovek; využít existující demo katalog, pokud má veřejně použitelný vstup. Nevytvářet anonymní přístup do admin demo dat. Jinak nabídnout domluvení ukázky skutečným existujícím kanálem.

### 6. Cena, tři kroky a FAQ

Příprava akce → prodej → den plesu, bez dalšího dlouhého opakování všech produktových sekcí. Konkrétní cenu, platební metody, lhůty výplat a obchodní sliby uvádět jen podle současné skutečné nabídky. Není-li veřejný ceník, použít existující pravdivý kontakt a ukázku; nevymýšlet tarif.

FAQ prioritně řeší přípravu plánku, konkrétní místa, způsob nákupu, platby a vstupenky, skenování, podporu a cenu. Nativní `details/summary`. Závěrečná sekce: „Připravte svůj další ples.“ Hlavní CTA stejné jako nahoře; sekundární „Domluvit ukázku“ znovupoužije existující rezervaci, pokud je zdrojově doložená. Zachovat odkazy na soukromí, podmínky, podporu a provozovatele.

## Natáčecí list: samostatné funkční klipy

Použít `product-demo-video` včetně `references/capture.md`. Nejdříve prohlédnout současné záznamy `venue_seat_picker/doc/demo.webm` a další existující takes; využitelné záběry znovu použít, pokud sedí identita dokumentu a vzhled. Nepřetáčet automaticky vše. **Každý řádek je samostatný soubor s vlastním začátkem a koncem. Časy jsou lokální vůči klipu, nesčítají se do povinné stopáže filmu.**

| Cue / soubor | Lokální záběry | Čitelný výsledek a ověření |
|---|---|---|
| `layout-build` | 0-4 s drag stolu; 4-8 s přidat několik židlí jednotlivě; 8-13 s Ctrl/Cmd-drag kopie; 13-18 s konečný celek. | Skutečný drag a držený modifikátor, původní sestava zůstane. Židle a jejich animace jsou čitelné. Závěr podržet alespoň 2 s. |
| `layout-style` | 0-3 s viditelný výběr více objektů; 3-7 s společná podporovaná barva/styl a označení; 7-12 s výsledek. | Výběr před změnou. Stejná geometrie a stabilní identity; barevnost není vydávaná za změnu dostupnosti nebo ceny. |
| `form-build` | 0-4 s přidat skutečné vlastní pole; 4-9 s jeho volby, pořadí nebo povinnost; 9-14 s čitelný veřejný náhled. | Uživatel vidí ovládání i výsledné pole. Zvolit jedno srozumitelné plesové pole a reálné podporované chování. |
| `form-style` | 0-2 s výchozí formulář; 2-7 s preset/barva a font; 7-12 s tentýž obsah v novém vzhledu. | Skutečné design settings; barva i typografie se projeví ve výsledném formuláři. |
| `ticket-design` | 0-3 s výchozí šablona; 3-10 s skutečné ovládání motivu, rozmístění a textového stylu; 10-15 s výsledné PDF. | Samostatná customizace vstupenky, nikoli jen doručení. QR a proměnné údaje jsou skutečný výstup šablony. Nezrychlovat všechny úpravy do nečitelné montáže. |
| `seat-select` | 0-2 s stejný sál v zákaznickém pickeru; 2-6 s dvě konkrétní sousední židle; 6-10 s označení a součet. | Reálný 390px viewport. Skutečný export/host save/portable handoff stejného dokumentu, nikoli ručně podobná mapa. |
| `check-in` | 0-4 s první načtení a přijetí; 4-8 s stejné QR znovu a upozornění; do 10 s čitelný stav. | Odpovídající demo vstupenka, změna počtu pouze při prvním přijetí. Pro kameru skutečný telefon a druhý displej nebo existující opakovatelný fixture. |
| `orders-overview` | 0-3 s přehled; 3-6 s konkrétní filtr/stav a dostupný export; 6-10 s výsledek. | Čitelné syntetické údaje. Package example není důkazem existujícího platebního/rezervačního backendu. |

Samostatný klip nesmí vyžadovat intro, závěrečné CTA ani kontext předchozího videa. Nadpis a vysvětlení žijí v HTML vedle něj. Každý clip má desktop a potřebný mobilní výřez, vlastní poster, jeden klíčový výsledek a záběr skutečného ovládání. Pokud je gesto při stanovené délce nečitelné, rozdělit jej do druhého lokálně volitelného klipu; nezrychlovat násilně animace. Dlouhý sestřih pro YouTube může později vzniknout z těchto takes, nemá vlastní povinnou délku a není součástí dokončovací brány landing page.

Jeden fixture: ples s realistickým sálem, jasně pojmenované stoly, uličky, pódium a parket; zvolit a uložit konkrétní dokument před natáčením. Demo účastníci jsou syntetičtí. Platební tok nevyvolává placený nákup na produkci. Klientské výsledky se používají jako samostatné veřejné reference, nikoli jako přestrojená demo statistika.

Pokud nový editor zatím existuje jen v samostatném example, označit jeho sekci jako „Ukázka editoru“ a oddělit ji od skutečného prodejního pohledu. Handoff mezi klipy editoru a pickeru musí být doložený; samotné rozdělení do více sekcí neospravedlňuje falešné tvrzení integrace. Toto je hlavní riziko celého natáčení a řeší se před čistými takes.

Při zkoušce ověřit kotvení celé sestavy při dropu, prostor pro židle a kopie, skutečné rozměry canvasu a výsledný dokument. Native capture při krátkých animacích ukládá čas každého frame; samotných „30 fps“ neprokazuje správné tempo. U native Ctrl-drag nepoužít `press Control` jako náhradu držené klávesy. Capture browser má task-owned prázdný config od prvního příkazu; žádný Panerelay ani osobní Chrome. Flutter nejvýše jeden proces na workstation; před jeho spuštěním zkontrolovat existující úlohy a cizí nezastavovat.

Dodávka médií: manifest samostatných klipů, původní takes a kvalitní zdroj každého klipu (typicky 1920×1080, 30 fps), webový MP4, případně WebM, délka a desktop/mobil poster pro každou variantu. Jeden společný film se nevyrábí jako povinný mezikrok. Mobilní materiál přerámovat nebo natočit samostatně, nepoužít zmenšenou nečitelnou administraci. Všechna média mají explicitní rozměry; každý webový klip cílově do 2 MB a každý poster do 200 KB, úvodní landing JS+CSS přidané tímto úkolem do 60 KB gzip. Jsou to projektové rozpočty k ověření, ne naměřený stav. Při prvním načtení pouze hero poster a aktuálně potřebné malé assets. Ostatní video `src` připojit až poblíž viewportu, přednačítat nejvýše následující klip a nikdy všech osm videí a jejich variant. S data saverem žádný automatický video download před klikem.

## Pohybový systém

### Závazný charakter: produkt v pohybu jako u reference

Poslední uživatelská preference: Tickender je vybraný kvalitativní a režijní směr po předchozích konceptech. Nehledat další zásadně odlišný koncept. Zachytit jeho charakter ve vlastní značce a vlastních funkčních klipech, nezredukovat zadání na obecné „text vedle videa“ nebo seznam funkcí.

- **Čistá produktová scéna.** Skutečné UI je velké a hlavní. Jemný rám okna nebo telefonu pomáhá orientaci, nesmí vytlačit obsah. Žádná záplava dekorací, stock záběrů nebo drobných dashboardů.
- **Režírované gesto.** Kurzor vede oko k relevantnímu ovládání, následuje skutečný klik či tah, viditelná reakce a stabilní výsledek. Náhodný záznam proklikávání nebo časosběr celého editoru tento charakter nenahradí.
- **Jedna srozumitelná proměna.** Ze stolu vznikne sestava, z pole použitelný formulář, ze šablony vlastní vstupenka. Customizaci ukázat na stejném obsahu před změnou a po ní, aby změnu nebylo nutné vysvětlovat.
- **Klidné, ale svižné tempo.** Vystřihnout hledání ovládání a čekání, zachovat přirozenou rychlost gest a animací. Po důležité změně nechat 1-2 s čitelný výsledek; podle složitosti i déle. Klip nesmí působit jako zrychlený návod.
- **Cílené přiblížení a návaznost.** Z celku přiblížit konkrétní práci, po dokončení znovu ukázat kontext. Pohyb kamery je střídmý, nezvětšuje rozmazané detaily. Přechod editor → zákaznický pohled zachovává stejný objekt a vizuální orientaci.
- **Stránka a klip mají společný rytmus.** Nadpis, krátké vysvětlení a médium se odhalí jako komponovaný celek. Samotná produktová akce začne až po usazení panelu, aby divák nepropásl první gesto během scrollu. Po scroll pauze nepouštět současně několik nesouvisejících efektů.
- **Krátké popisky.** Nadpis říká přínos, doprovodná věta ukotví scénu. Titulek neopakuje každý klik a nezakrývá ovládání, jehož výsledek ukazujeme. Význam funguje bez zvuku.

**První režijní brána před natáčením celé sady:** připravit jeden skutečný pilot `layout-build` včetně jeho produktové sekce a porovnat jej přímo s vybraným záběrem Tickenderu. Hodnotit velikost UI, vedení kurzoru, čitelnost změny, držení výsledku, framing a souhru s reveal sekce. Pokud je výsledek jen běžný screencast zasazený do generické karty, brána není splněná. Nejdříve opravit pilot a teprve pak stejnou režii rozšířit na formulář a vstupenku. Jde o místní kvalitativní ověření v existující vlně, nikoli další obecné kolo hledání konceptu nebo povinné schvalování uživatelem.

Inspirací je skutečný chování Tickenderu, ne pouze screenshot. Naše stránka používá existující logo, Futura fonty a tenantové barvy (#253759 / #4465A6 / #80BDF2 podle konfigurace). Světlá hlavní plocha, tmavý kontrastní blok pro přehled nebo referenci, jemné linky a asymetrický produktový obraz. Žlutou konkurenční stěrku nahradit vlastním akcentem s ověřeným kontrastem. Existující uživatelské téma nesmí po startu blikat ani se přepínat kvůli marketingu.

| Prvek | Přesné cílové chování |
|---|---|
| Hero | Hlavní obsah dostupný ihned, jemný nástup 500-650 ms; rozdíl text/obraz 80-120 ms. CTA není podmíněné animací. |
| Sekce | Jednorázový opacity + translateY 12-16 px, 480-540 ms, cubic-bezier(.22,.61,.36,1), prah viditelnosti 0,05 a spodní root margin -8 %. Po odhalení observer odpojit. |
| Související prvky | Stagger 70 ms, nejvýše 4 prvky; po skoku na kotvu odhalit cílový obsah okamžitě. |
| Nadpis | Vlastní akcentová stěrka cca 420 ms se zpožděním 180-220 ms; výjimečně, ne na každé větě. |
| Linky | scaleX/scaleY od počátku čtení, 550-650 ms. Neměnit layoutové rozměry. |
| CTA a karty | 180-240 ms; lehký posun šipky, případně zvednutí nejvýše 4 px; ekvivalentní focus feedback. |
| Ukázky | Každá sekce má vlastní video. Při alespoň 50% viditelnosti video panelu po 250 ms spustit nejviditelnější oprávněný klip, muted + playsinline; ostatní pauza. U panelu vyššího než viewport počítat průnik vůči menší z výšek panelu a viewportu, aby autoplay nezůstal nedosažitelný. Při odchodu či skrytí tabu pauza. Vrácením pokračovat od stejného místa, pouze pokud pauzu vyvolala viditelnost. Ruční pauzu nikdy nepřebít. Po jednom přehrání držet výsledek a nabídnout Znovu přehrát; bez neovladatelné smyčky. |
| Lokální varianty | Přepnutí Vzhled/Sestavení mění samostatný soubor a poster jen v příslušné sekci. Zastavit předchozí video, nové spustit jen po uživatelské volbě nebo splnění visibility politiky a bez přebití ruční pauzy. Jeden manifest mapuje sekce, varianty, zdroje, postery, délky a popisy. |
| Hlavička | Sticky, stabilní výška, jemný scroll progress jen pokud nepůsobí jako loader. Kotvy mají scroll-margin. |
| Reduced motion / data saver | Obsah okamžitě viditelný, bez stěrky a nástupů, bez autoplay; statické postery a ruční Play. |
| Chyba JS/video | Výchozí HTML obsah viditelný. Odhalování aktivovat až po úspěšném navázání observeru; po chybě vždy odkrýt. Video error zobrazí poster, textový postup a opětovné spuštění/stáhnutí. |

Nativní scroll, bez scroll-jackingu, pinovaných mnohaobrazovkových prezentací a povinného čekání. Nepřidávat GSAP ani React jen pro několik reveal efektů; CSS + IntersectionObserver + malý modul stačí. K trvale pohybujícím se číslům/logům nepřidávat marquee jako dekoraci. Číselné výsledky se nemusí dopočítávat od nuly; přednost má čitelnost.

## Kanonické URL a vstup do aplikace

Tento kontrakt je tenantově omezený a musí být ověřen testy Workeru i klienta. Marketing nezávisí na tom, zda se návštěvník přihlásil.

| Vstup na vstupenky.online | Výsledek |
|---|---|
| `/`, běžné UTM a marketingové kotvy | 200 statické marketingové HTML, canonical `/`, hlavní obsah bez backendu a bez Flutteru. |
| `/events` | 200 stávající katalog s funkčním hledáním, roky/archivem a serverovými odkazy; canonical `/events`. |
| `/events/` | 308 na `/events`, zachovat query. |
| `/events?create=1` | Katalogový shell spustí existující `handleOrganizerIntent`: host registrace, přihlášený admin, zákaz registrace má existující vysvětlení. |
| `/?create=1`, staré root hledání s `q` | 308 na `/events` se zachovanou query. Neprovádět přesměrování pro obyčejné UTM. |
| `/pro-poradatele`, `/pro-poradatele/` | 308 na `/` se zachovanou query; fragment zachová browser. Žádná druhá marketingová kopie. |
| `/#/form/...`, `/#/scan/...`, další podporované root legacy hash deep linky | Malý raný landing modul převede přes existující společnou normalizaci na kanonický aplikační path se zachovanou jeho query. Fragmenty `#ukazka`, `#reference`, `#faq` zůstávají na landing page. |
| `/form/...`, `/scan/...`, `/login-qr`, `/google-auth`, `/app/google-auth`, `/login`, `/admin`, objednávkové a waitlist odkazy | Dosavadní vlastníci, response policy a chování. Marketing je nepřebírá. |
| Interní `/organizers-page`, `/webclient`, `/flutter` | Nadále interní assety; žádné veřejné stahování HTML nebo nový veřejný alias. |
| Ostatní tenanty a jejich forced occasion home | Dosavadní chování bez této landing page a bez tenantově cizí `/events` větve. |

Vlastník marketingu zůstane `automation/release/organizers/` a generátor; existující interní jméno `organizers-page` není samo o sobě paralelní veřejná stránka. Přepsat canonical/OG na `/`, katalogové meta na `/events`, sitemap zahrne oba cíle a skutečné veřejné event URL. `/pro-poradatele` v sitemapě nebude. Změna root nesmí odsunout veřejné události do neindexovatelného JS-only prostoru.

Katalogový root match v `RouterService` rozšířit o `/events` pouze v tomto tenantovi; `UserHeader` nemá přidat druhé H1 na novém katalogu. Odkazy „Akce“ a návraty do katalogu dohledat ve scoped `web_client/src` a v generátoru, změnit podle významu: logo značky → `/`, seznam akcí → `/events`, admin → existující admin route. Prostý globální replace `'/'` je zakázaný.

Legacy hash normalizaci neimplementovat druhým regexovým routerem v marketingu. Extrahovat potřebnou čistou část `normalizeUrl` do malého sdíleného modulu a používat ji z RouterService i raného landing modulu. Query z `#/...?...` se nesmí ztratit. Zachovat seznam přípustných interních cest a stejný origin; neotevírat přesměrování na libovolný externí URL obsah fragmentu. Citlivé scanner/auth odkazy se nesbírají do analytics ani nepřidávají do referreru.

Service worker musí rozlišovat marketingové `/` a katalogové `/events` také po aktualizaci ze starého app shellu. Prověřit manifest start URL a offline fallback podle skutečné konfigurace; žádný generický root fallback, který by na marketing vracel starý katalog. Přidat podporu interního marketingového HTML v precache, pokud má offline fungovat, explicitně vyloučit marketingové MP4/WebM z install manifestu. Stará cache se vyřadí stávajícím release mechanismem, bez přepsání cache kontraktu všech tenantů.

## Kritika R1, porovnání a přijatá iterace R2

Proběhla návrhová kritika původního briefu a následná korekce po explicitním upřesnění formátu: původně navržený 55s film byl chybnou prioritou. Autoritativní jsou nyní samostatné klipy u funkcí při scrollování. Následující tabulka je kritika návrhu, nikoli naměřený test dosud neexistující implementace. Všechny opravy jsou zapracované výše.

| Téma | Tickender: pozorovaný stav | Původní brief R1 | Kritika | Závazný návrh R2 |
|---|---|---|---|---|
| První adresa | Marketing na `/`. | Redesign především `/pro-poradatele`. | Nesplňuje poslední explicitní zadání. | Marketing na `/`, katalog `/events`, starý marketing 308. |
| Důvod pro pořadatele plesů | Obecný ticketing a návrat publika. | Obecný průchod aplikací, plánek hlavně hotový. | Chybí náš nejsilnější výrobní moment. | Samostatný `layout-build` a `layout-style` přímo v sekci plánku; jasně plesový slovník. |
| Formát videí | Hlavní animované demo a další názorné sekce. | Původní 45s a následný 55s společný film. | Uživatel chce poznávat jednotlivé funkce při scrollu, ne čekat na kapitolu ve filmu. | Každá funkce vlastní krátký klip; dlouhý YouTube sestřih pouze volitelně. |
| Formulář a vstupenka | Styling stránky je výrazný. | Nákup a doručení převažovaly nad vlastní tvorbou a designem. | Samostatné funkce a jejich customizace byly podhodnocené. | `form-build`, `form-style`, `ticket-design` mají své viditelné produktové sekce. |
| Plynulost | Jednotné reveal, stěrky, linky a interakce. | Popsaný vizuální styl a orientační motion. | Statická replika by nesplnila požadovaný pocit. | Konkrétní motion tabulka, životní cyklus, pauza a reduced-motion. |
| Reference | Na prohlédnuté landing page nenalezené pojmenované klientské reference. | Přidat skutečné klienty, ale čekat na výběr. | Uživateli jejich existence není nejistá. | Obsahový proud běží paralelně, skutečné reference brzy; čísla pouze doložená. |
| Pravdivost dema | Simulované prodeje a QR v kódu. | Reálné záběry, nevyřešená návaznost editoru. | Sibling editor nemusí být aktuální Festapp host. | Zdroj a handoff explicitně ověřit; žádná falešná kontinuita. |
| Kupující | Reference je koncipovaná pro pořadatele. | Katalog zůstal root. | Po přesunu root se kupující může ztratit. | „Akce“ viditelné i na mobilu, katalog jeden klik na `/events`. |
| Spolehlivost | Animace skrývají obsah před reveal. | Nedostatečně popsaný failure stav. | Při JS chybě může být „prázdná elegantní stránka“. | HTML viditelné ve výchozím stavu, poster a textový fallback. |
| Výkon | DOM animace bez originálního MP4. | Nahradit naším videem. | Více MP4 může zatížit první load a offline install. | Lazy média, jen poster úvodem, rozpočet a PWA výjimka. |
| Měření | Nebylo ověřeno. | Obecné budoucí porovnávání. | Nové event beacon měření by porušilo předchozí rozhodnutí. | Pevný srovnávací scénář, laboratorní evidence, existující serverové souhrny. |

### Další iterace podle důkazů

1. **R2 → R3: statická skutečná kompozice.** Implementovat produkčně použitelnou HTML/CSS kompozici s opravdovými referencemi a existujícími postery. Porovnat s referencí ve stejných 1440×1000 a 390×844. Ověřit hierarchii, viditelnost plánku, Akce a CTA, čitelnost, cenu a reference. Výsledek je konkrétní seznam nejvýše pěti prioritních změn, ne obecné „přidat wow“.
2. **R3 → R4: pohyb a čisté záběry.** Dodat klipy, stejné scroll gesto u obou stránek, stejný záznam a vedlejší náhled. Hodnotit kontinuitu a skutečné viditelné výsledky gest. Přetáčet jen nevyhovující samostatné klipy; neopakovat všechny takes. Zkontrolovat zvlášť obsah i vzhled plánku, formuláře a vstupenky.
3. **R4: funkční a přístupnostní brána.** Celý průchod host/přihlášený, legacy odkazy a PWA; reduced-motion, data saver, video/JS failure, mobilní čitelnost. Nová chyba mění příslušnou sekci autoritativního plánu a přesnou vlnu realizace.

### Srovnávací protokol

Stejný viewport, zoom 100 %, stejná síťová/cache situace a nativní scroll o přibližně 500 px každou sekundu. Samostatně projít normální a reduced-motion režim; konkurenta hodnotit jen na skutečně dostupném veřejném povrchu. U každého řádku evidence: screenshot/čas v záznamu, pozorování, závažnost, konkrétní oprava, stav před/po.

| Kritérium | Průchodová podmínka naší stránky | Důkaz |
|---|---|---|
| Srozumitelnost | První obraz ukazuje plesový plánek a vysvětluje vytvoření i prodej míst. | Desktop/mobil hero screenshot. |
| Skládání plánku | Drop stolu, židle, kopie, hromadná úprava a konečný sál skutečně vidět. | `layout-build`, `layout-style`, dokument před/po. |
| Formulář a vstupenka | Tvorba vlastního pole, barva/font formuláře a úprava vlastní šablony vstupenky jsou samostatně vidět. | `form-build`, `form-style`, `ticket-design`, skutečný výstup. |
| Formát stránky | Scrollující uživatel vidí u každé funkce příslušný samostatný klip a nemusí seekovat společný film. | Souvislý scroll záznam sekcí včetně lokálních variant. |
| Důvěra | Konkrétní klienti před dlouhou feature částí; čísla odpovídají zdroji. | Reference HTML + manifest. |
| Plynulost | Obsah se odhaluje jednou bez přeskoků, stěrka nezakrývá text nepřiměřeně dlouho. | Scroll záznam a kontrola layout shift. |
| Funkčnost | Všechna CTA vedou do správného toku; samostatné klipy přehrávají a jejich lokální varianty se přepínají; ruční pause drží. | Browser průchod + cílené testy. |
| Kupující | `/events` je z každého běžného marketingového viewportu dostupné přes hlavičku jedním klikem. | Desktop i mobil. |
| Mobil | Žádná horizontální lišta v 320/390/768 px, cena a označení dvou míst čitelné v klipu. | Screenshot + skutečný encode. |
| Výkon | Cíl CLS < 0,1 a LCP ≤ 2,5 s na zaznamenaném laboratorním profilu; neznačit je za produkční percentily. | Uvést device/network/cache profil a naměřené hodnoty. |
| Odolnost | JS/media error a reduced-motion ponechají použitelný obsah i CTA. | Jeden záznam reprezentativních stavů. |

Nedávat subjektivní skóre „9/10“ jako důkaz zlepšení konverze. Bez reálného měření lze potvrdit splnění kritérií a kvalitu průchodu, nikoli obchodní uplift. Další iteraci dělat pouze pro konkrétní nesplněné kritérium nebo nové uživatelské připomínky.

## Realizační vlny

### Efektivní koordinace

Realizaci vede Astra medium a používá subagenty podle připojeného execution
promptu: levnější inventura obsahu/médií, samostatný vlastník routing/PWA a
nezávislá kritika až nad konkrétním výsledkem. Nejvýše tři souběžní subagenti,
disjunktní vlastnictví souborů, stručné handoffy bez kopírování celé historie.
Koordinátor drží vizuální režii, pilot a integrační brány. Jeden Flutter slot
platí pro celý tým; kontroly se dávkují a nepouštějí po každém editování.

### Vlna 1: obsah, identita a zdroj záběrů

**Cíl:** konkrétní storyboard a skutečné podklady, nikoli placeholder landing.

- Zaznamenat source/live rozdíl stávajícího marketingu; zachovat užitečný kontakt, rezervaci schůzky a obchodní text.
- Připravit `automation/release/organizers/content.json` s explicitní veřejnou projekcí, reference assets a deterministické generování. Soukromé důkazy mimo produkční bundle.
- Prohlédnout existující záznamy editoru, vybrat konkrétní demo sál a ověřit editor → picker handoff. Založit ignored take adresář s cue manifestem; neurčovat další skutečné transakce pro záběr.
- **Ověření:** kontrola zdrojů referencí, jedno nanečisto provedené gesto `layout-build`, přechod do `seat-select` a krátká zkouška editoru formuláře/vstupenky. Při Flutter tasku respektovat společný limit.
- **Výstupní podmínka:** klientské bloky mají skutečný obsah; zdroj editoru je pojmenovaný a cesta stejného plánku doložená.

### Vlna 2: jeden root marketing a `/events`

**Cíl:** kanonické URL, zachovaný prodejní a registrační tok.

- `automation/cloudflare_build.sh`: tenantově specifické root HTML, `/events` katalog, staré marketingové a query redirecty, sitemap/canonical a zachované scanner/auth response policy.
- `render_organizer_page.mjs`, `organizers/page.html` a `page.css`: root canonical, skutečný obsah, změna původní katalogové navigace. Interní `organizers-page` zůstává interní.
- `web_client/src/startup/organizer_intent.js`, `main.js`, `services/router_service.js`, `components/users/user_header.js`, `web_client/index.html`: `/events` jako nový katalogový vstup, root intent redirect, semanticky správné odkazy a jediné H1.
- Přidat malý sdílený URL normalizer a raný landing entry modul; znovupoužít stávající logiku legacy hash tras, nestahovat celý app bootstrap do landing.
- `automation/build_web_bundle.sh` a `web_client/vite.config.js`: zahrnout malý fingerprintovaný marketingový modul a styly do normálního build graphu. Nevytvářet druhý bundler nebo ručně kopírovanou knihovnu.
- `automation/lib/pwa_shell_manifest.mjs`, `generate_pwa_service_worker.mjs`: explicitní marketing/katalog offline kontrakt, vyloučení video souborů z precache, zachovat stávající cache/version mechanismus.
- **Odstranění:** veřejná duplicitní `/pro-poradatele`, starý katalogový canonical `/`, obsolete textové navigace, dead tests očekávající staré canonical. Samotné historické release dokumenty nemažou aktuální kontrakt.
- **Ověření:** jeden cílený Node batch s routing, generator, organizer intent, home startup, scanner a PWA testy; viz níže. Během editace jej nepouštět po každém souboru.
- **Výstupní podmínka:** root funguje bez backendu, `/events` zůstává katalogem, query/legacy odkazy a ostatní tenanty zachované.

### Vlna 3: vizuální R3 a první srovnání

**Cíl:** naše přehledná kompozice se skutečným obsahem a postery.

- Realizovat obsahovou hierarchii výše, lokální fonty, theme tokeny, desktop/mobil layout, viditelné Akce a skutečné CTA.
- Bez videa už musí fungovat reference, vysvětlení plánku, cena, FAQ a vstup do aplikace. Žádné vývojové instrukce nebo technické diagnostiky ve veřejném UI.
- První srovnání podle protokolu, uložit HTML galerii z reálných screenshotů a stručné rozdíly oproti R2. Nepředstírat, že storyboard screenshot je produktová implementace.
- **Výstupní podmínka:** kritéria hierarchie, obsahu a mobilní čitelnosti splněná; konkrétní výtky zapracované před čistým natáčením.

### Vlna 4: skutečné záběry a pohybové R4

**Cíl:** každá funkční sekce má svůj skutečný klip včetně customizace a scroll chování odpovídá briefu.

- Natočit/recutovat všech osm samostatných klipů dle natáčecího listu. Zachovat dokument a identitu mezi editorem a prodejem; exportovat manifest a webové encody pro jednotlivé sekce. Velké masters a takes mimo Git, distribuční assets podle existující asset pipeline.
- Přidat `organizers/motion.js` a `organizers/demo_player.js` jako malé produkční moduly, nebo odpovídající stávající Vite entry vlastníky. Sekce a lokální varianty číst z jednoho clip manifestu. Žádný globální seznam časových kapitol a žádná závislost na dlouhém filmu.
- Reveal, stěrka, linky, pause/resume, reduced-motion, visibility a error stavy podle tabulky. Připojování observerů a listenerů musí mít vlastní cleanup; opakovaná inicializace nespouští více přehrávání.
- Druhé srovnání na stejném scroll scénáři. Nahradit pouze nevyhovující klipy a opravit konkrétní motion problémy.
- **Výstupní podmínka:** je vidět skutečné skládání plánku, všechny klipy odpovídají finálnímu UI, slib délky sedí a nízkopohybový režim funguje.

### Vlna 5: jedna závěrečná integrační brána

**Cíl:** zkontrolované a reviewovatelné lokální dílo připravené k samostatně autorizovanému release.

- Ověřit host → registrace, signed-in → admin, zakázaná registrace, přímý `/events`, filtry a návraty z forem, legacy scanner hash, OAuth routes, marketingové kotvy, refresh a browser back.
- Izolovaný browser na 320/390/768/1440 px, keyboard průchod, reduced-motion, media/JS failure, automatický axe a výkonové pozorování podle definovaného profilu. Neprovádět opakované plné audity bez nového důvodu.
- Cílený encode/decode/seek check, čitelnost posledního stavu každého samostatného klipu a kontrola PWA manifestu, že neobsahuje marketingová videa.
- Aktualizovat `automation/cloudflare/README.md` route tabulku a příslušný stručný produkční guide. Starší plán `vstupenky-organizers-ui-plan-2026-10-15.md` označit v dotčeném rozsahu jako překonaný tímto plánem, nerozbít jeho ostatní platné cíle.
- **Výstupní podmínka:** závěrečná srovnávací tabulka má odkazy na skutečné důkazy a žádný nevyřešený blocker; stav je „implementováno lokálně“, dokud není skutečně nasazeno.

## Testovací seamy a příkazy realizace

Při plánování se nic z následujícího nespouští. Stávající tests upravit pro nový kontrakt, nepřidávat křehké asserty na marketingové věty.

- `automation/tests/organizer_page.test.mjs`: root canonical, tenant gating, deterministic renderer, veřejná projekce referencí, správné CTA a neexistence placeholderů.
- `automation/tests/public_seo.test.mjs`: `/`/`/events`, redirecty včetně query, sitemap, forced tenant a staré scanner/auth hranice; root při výpadku backendu stále 200 marketing.
- `web_client/tests/core/organizer_intent.test.js`, `home_startup.test.js`: nová cesta, guest/signed-in/registration-disabled; nezahajovat katalog na marketingové stránce.
- Stávající scanner route a RouterService testy: extrahovaná normalizace zachová root hash, query a blokuje externí redirect. Najít přes scoped `rg --files web_client/tests` a vybrat skutečné současné soubory.
- `automation/tests/pwa_manifest.test.mjs`, `pwa_offline.test.mjs` a související relevantní generator test: marketing/katalog při upgrade a video exclusion. Nezměnit cache chování ostatních tenantů.
- Malý nový test `web_client/tests/components/landing_demo_player.test.js`, pro společný správce samostatných videí: výběr jednoho viditelného klipu, explicitní pause, observer resume, dokončení/replay, lokální změna varianty, lazy source, reduced-motion a error fallback. Má hodnotu pro stavovou logiku, nikoli pro CSS nebo doslovný text.

Příklad hlavního cíleného batch z rootu, upravit pouze podle skutečných změněných seamů:

```sh
node --test automation/tests/organizer_page.test.mjs automation/tests/public_seo.test.mjs automation/tests/pwa_manifest.test.mjs
pnpm --dir web_client exec node --test tests/core/organizer_intent.test.js tests/core/home_startup.test.js
pnpm --dir web_client run build
```

PWA offline/browser gate provést existujícím repository příkazem podle aktuálního `CONTRIBUTING.md` a vlastníka testu, ne obcházením přímým Playwrightem. `pnpm install --frozen-lockfile` jen pokud je potřeba, pnpm 11.24.0. Při změně Flutter kódu je to samostatně odůvodněný scope a jediná Flutter úloha s `--concurrency=1`; pro samotnou landing page se Flutter rebuild ve vývojové smyčce nevyžaduje.

## Odstranění a zachování

| Artefakt | Finální stav | Důkaz |
|---|---|---|
| Veřejný marketing `/pro-poradatele` | Pouze 308 na root. | Worker test a HTTP probe. |
| Root katalog pro tento tenant | Přesunut na `/events`; root existuje jako marketing. | Worker/SEO + browser. |
| `/?create=1` | Zachovaný externí starý vstup přes 308 na kanonický `/events?create=1`. | Query test a skutečný registrační tok. |
| Interní asset `organizers-page` | Úmyslně zachován jako build artefakt bez přímé veřejné prezentace. | Internal-path test. |
| Root odkazy | Přesměrovat pouze ty znamenající seznam akcí; brand logo zůstává root. | Scoped call-site kontrola. |
| Konkurenční média | Jen lokální výzkumné podklady, nikdy produkční obrázky/video. | Obsah distribučního asset manifestu. |
| Soukromé referenční důkazy a transakční data | Mimo public bundle; viditelná jen schválená projekce. | Kontrola public výstupu. |
| Video v precache | Vyloučeno z install-critical i všeobecného media precache. | PWA manifest test. |
| Paralelní marketing/feature flags | Nezavádět trvalý druhý landing režim. | Jediný veřejný root vlastník a route testy. |

## Nasazení a návrat

Současný úkol nepovoluje deploy, commit ani push. Po samostatném zadání release se připraví coherent main/tenant revision, drift a release gates. Pouze `prod/festapptickets`, lokální build a `automation/deploy_direct.sh`, žádný GitHub build bez výslovného požadavku. Rutinní build/deploy/monitoring podle osobních pravidel delegovat levnějšímu subagentovi s přesnými SHA a ověřením; inženýrské rozhodnutí zůstává primárnímu agentovi.

Root, `/events`, redirecty, příslušná média a PWA se publikují jako jedna coherent verze. Při návratu nasadit celý předchozí známý bundle včetně Workeru a cache kontraktu; nedělat ad hoc routing fallback na starý katalog při chybě videa. Backend se nemění, rollback nemá nic obnovovat v objednávkách. Po release ověřit také metadata, obsah rootu a katalogu, media range/seek a skutečnou verzi obou veřejných vstupů.

## Hotovo znamená

- `/` je naše funkční plesově orientovaná landing page; `/events` je původní plnohodnotný katalog a je dostupný jedním klikem.
- Reference jsou skutečné a viditelné; žádné vymyšlené metriky nebo falešný klientský obsah.
- Hero a sekce plánku ukazují skutečné skládání sálu, nikoli jen hotový plánek nebo animovanou kresbu imitující editor.
- Plánek, formulář a vstupenka mají vlastní názorné klipy včetně customizace; zákaznický výběr, odbavení a přehled mají navazující samostatné sekce. Scroll odhaluje a spouští odpovídající funkci bez společného filmu.
- Každý klip má pravdivý výsledek, čitelnou délku, poster a ovládání; související klipy drží identitu dokumentu a editor-only example není vydáván za živou integraci. Dlouhý YouTube sestřih není dokončovací podmínka.
- Pohyb stránky odpovídá stanovenému systému a funguje také s klávesnicí, reduced-motion, bez autoplay, při chybě videa a bez JS.
- Stará marketingová URL už není druhým vlastníkem, root legacy odkazy a ostatní tenanty fungují, PWA neinstaluje videa.
- Srovnání R3/R4 se opírá o skutečné screenshoty a záznamy, cílené kontroly jsou úspěšné a nasazený stav se nezaměňuje s lokálním.

## Zbývající nejistoty

1. Source/live odchylka marketingu a rozpracovaný editor: implementátor určí skutečnou autoritativní zdrojovou revizi a ověří konkrétní handoff před natáčením. Žádný automatický předpoklad, že nový editor už je v live Festapp.
2. Přesný výběr klientských podkladů: existence referencí je potvrzená, konkrétní hodnoty se doplní ze skutečných zdrojů při obsahové vlně. Nezávisí na nové ústní aprobaci obecného použití referencí.
3. Skutečná cena a dostupné platební metody: opsat aktuální vlastní nabídku, ne konkurenční text nebo nedokončený platební plán. To blokuje jen konkrétní neověřené tvrzení, ne celou stránku.
4. Výkonové rozpočty jsou návrh; první skutečný encode a build určí, zda je nutné zmenšit teaser, poster nebo počet souběžných médií. Neměnit kvůli tomu obsahový požadavek na skládání plánku.

## Doložené upřesnění během realizace 2026-10-22

- Objednávky nemají vlastní export ovládání (`orders_content.dart` nepředává `exportOptions`). Klip proto přesně ukazuje filtrování objednávek a následný dostupný CSV export vstupenek, který poskytuje `tickets_tab.dart`. Ověřen skutečný soubor 260 syntetických vstupenek. Rozsah přehledu a exportu zachován bez vymyšleného ovládání.
- Formulář ukazuje vlastní pole, možnosti a změnu povinnosti; veřejný vzhled před/po používá stejné údaje. Vstupenka ukazuje změnu motivu a rozložení šablony, font a zarovnání textu, následně reálné PDF.
- Hero používá skutečný úplný ukázkový plesový sál a samostatně popsaný mobilní výběr. Sekvence editor -> picker dále používá tentýž doložený čtyřstolový dokument; hero není tvrzením o rezervaci ani jiném handoffu.
- Původní pilot neprošel kvůli drobnému UI/cropu a nečistému konci. Opravené výřezy, synchronní detail ovládání a čistý výsledný stav prošly nezávislou kritikou před rozšířením sady.

## Dotažení po vizuální připomínce 2026-10-22

Uživatel odmítl původní modrou paletu a nejasné reference. Tato pozdější korekce nahrazuje výše uvedené tenantové barvy a jednoduchý uniformní reveal pro marketing: teplá slonová kost #f8f6f1, inkoust #222321, vínový akcent #803d49. Futura a skutečná produktová média zůstávají. Text, produkt a detail nastupují postupně (650-900 ms, odstup 80/190 ms); hero skládá sál a telefon v samostatných vrstvách, akcentová linka se rozvine jednou. Automatický start videa čeká 550 ms po ustálení scrollu. Reduced motion a focus vždy odhalí obsah.

Reference jsou jediná obrazová řada dvou ověřených nadcházejících plesů Country bál 2026 a Ples AKH 2026. Vlastní úvodní obrázky jsou stažené z veřejného katalogu; karty vedou na existující objednávkové formuláře. Archivní akce ani jejich plakát se nemíchají do aktuálních referencí. Datum ověření a originál obrázku vlastní content.json. Na mobilu zůstává jedna posuvná řada, s další kartou viditelnou přes okraj.

Důkazy tohoto dotažení: vstupenky-landing-evidence-2026-10-22/visual-refinement.md. Pouze lokální implementace.

## Nové upřesnění uživatele po odmítnutí vizuálního dotažení

Předchozí ivory/ink/wine korekce nebyla schválena a je nahrazena tímto zadáním.
Landing přebírá skutečný současný jazyk veřejné aplikace a administrace:
Futura, navy/blue tenantové tokeny, světlé veřejné pozadí, 10/15px rohy.
Autoritou je skutečný live public světlý režim a současný ThemeConfig, nikoli
nová marketingová paleta. Dekorativní šipky z odkazů a CTA se odstraňují.

Plesový editor má ukázat doplnění stolů a židlí a odstup na plný sál.
Navazuje obrazový příběh jiných dispozic (kino, divadlo, sezení a stání pro
různé akce včetně koncertů) ze skutečných editorových presetů. Označení
koncertního použití není tvrzením o existenci samostatného concert presetu.
Vstupenka ukáže více skutečných šablon, včetně výsledných renderů. QR odbavení
zůstává výraznou navazující funkcí. Osm základních klipů, reference a URL
kontrakt se zachovávají. Nový velký sál není vydáván za dokument původního
samostatného seat-select take. Pouze lokální implementace, bez nasazení.
