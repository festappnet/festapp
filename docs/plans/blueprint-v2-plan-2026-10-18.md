# Blueprint v2: plnohodnotný editor a shodné vykreslování plánků

Datum: 2026-10-18  
Stav: Revidováno pro standalone-first postup; etapa A je samostatný balíček a demo, etapa B integrace do Festapp až po novém zadání; implementace začíná G0  
Verification: standard - etapa A veřejný balíčkový kontrakt a renderery; SQL, rezervace a integrace až v etapě B  
Výchozí bod: Festapp HEAD `eb2304724` a aktuální pracovní strom, který obsahuje rozpracované změny. Tento dokument je plán, nikoli důkaz provedené implementace nebo nasazení.

## Výsledek a hranice

Pořadatel vytvoří od prázdného plátna celý sál, autobus nebo vlak bez externího grafického editoru. Přidává jednotlivá sedadla, stoly, řady, oddíly, uličky, pódium, dveře a popisky. Stůl se sedadly se chová jako jeden celek, ale každé sedadlo zůstává samostatně upravitelné a prodejné. Výsledný plánek má ve Flutter editoru, Flutter výběru míst a JS výběru míst stejnou geometrii, tvary, typografii a stavy.

V rozsahu je tvorba, přesouvání, otáčení, kopírování, číslování, hromadné úpravy, text s volbou fontu a barvy, kreslicí tvary, vlastní složené objekty, knihovna předvoleb s drag-and-drop, změna rozměrů plátna a inteligentní práce s podklady, šablony, chytré přichytávání, kontrola kolizí, undo/redo, ukládání, zákaznický výběr, převod existujících plánků a odstranění nahrazených cest. Všechny níže popsané základní scénáře patří do konečného výsledku; pořadí vln není zúžení na pouhý generátor řad.

Mimo rozsah: 3D/CAD, zadávání skutečných rozměrů a fyzická kalibrace, výpočet evakuačních kapacit, automatická certifikace přístupnosti budov, import DWG, prodej celého stolu jako nový obchodní produkt, přidělování jízdenek podle úseků trasy, AI generování a souběžné živé editování více lidí. Více vozů/pater se modeluje jasně označenými oblastmi jednoho společně viditelného plánku bez přepínání; nevzniká nový dopravní rezervační systém. JS potřebuje plnohodnotný viewer/picker, nikoli druhou administrátorskou aplikaci.

## Etapa A: samostatné demo před integrací

**Poslední rozhodnutí uživatele má přednost před cílovými integračními popisy níže.** První implementační zadání řeší jen veřejný balíček v `/Users/miakh/source/venue_seat_picker` a jeho demo. Festapp slouží jako read-only reference; neměnit jeho runtime, dependency piny, Ticket Editor, font službu, SQL, setup, objednávky ani klienty. Současná úprava těchto dvou plánovacích dokumentů není integrace. Žádný Supabase, přihlášení, tenant ani produkční asset není nutný ke spuštění A.

- **A: vyzkoušit editor.** G0, vlny 1-6, 10A; plnohodnotný editor, Flutter picker, samostatný JS picker, šablony, lokální save/reopen, scénáře a distribuovatelný demo kit. Používají stejné veřejné API jako budoucí host.
- **B: integrovat až na nové zadání.** Vlny 7-9, 10B a odložené host/font/image části 2/5/6. Zachovat zde popsané obchodní invarianty, ale před zápisy znovu zkontrolovat tehdejší vlastníky SQL a callery. Přijetí dema není automatické oprávnění k B.
- **C: publikace a provozní převod.** Registry/deployment/tenant aktivace a contraction pouze ve výslovně zadaném scope. Veřejně vydatelný neznamená již publikovaný.

### Demo, které lze skutečně spustit a předat

Rozšířit existující `example/` (dnes má `file_selector` a místní assety), nevytvářet vedle něj druhý demo editor. Základní obrazovka má galerii, editor a přepnutí Náhled zákazníka. JS picker je samostatný consumer v `web/demo/`; převezme tentýž exportovaný dokument. Režim Diagnostika obsahuje porovnání obou rendererů a simulace. Technická tlačítka, metriky, seed nebo latence nejsou v běžném panelu pořadatele.

Demo host implementuje pouze syntetické `seatPresentation`, `capacityPresentation`, cenové bindingy, constraints a persistence adapter. Umožní vyzkoušet dědění ceny, gauč jako celek, stání po kusech a chybové stavy. Neimplementuje účetnictví, SQL ani druhý rezervační engine; vždy je označené „Demo - ukázková data“. Mock success/conflict/timeout/resource failure jsou deterministické odpovědi na hranici hosta. Simulace nedokazuje atomitu databáze, oprávnění nebo platby.

Lokální Uložit potvrdí demo baseline; Export/Import přenáší verzovaný balíček s layout JSON, povolenými obrázky/font fixtures a demo host metadaty oddělenými od přenositelné geometrie. Import obnoví i místní podklad bez původního file path/blob URL. Validace velikostí, cest a resource hashes proběhne před změnou dokumentu; poškozený import ponechá poslední platný draft. Vytvořit čistý geometry export pro jiného hosta bez demo cen/stavů. Autosave přes host storage s debouncingem, obnovou po reloadu a jasným stavem při nedostupném storage; export do souboru musí fungovat i tehdy. Reset obnoví seed bez smazání jiného dokumentu, náhrada rozpracovaného plánu chrání neuložené změny.

Veřejný balíček nemá produkční katalog fontů. Demo přibalí několik licencovaných fixtures se známými původními ID/hash metadaty a lokálními glyph resources, včetně české diakritiky a odlišných metrik. Offline outline build je obecný nástroj package pipeline. Není potřeba měnit Festapp resolver; společná produkční fontová pipeline zůstává výslovně B. Žádné runtime stahování z CDN pro základní demo.

**Spuštění a balení:** během G0 prověřit skutečné možnosti lokálního SDK a zaznamenat je. Dodat package-owned `tool/demo.sh` s příkazy `build`, `check`, `open`, `stop`, dokumentované v `example/README.md`. Jde o navržené vstupy, zatím neexistující příkazy. `build` připraví Flutter web example a JS kernel/demo v jednom `build/demo/` kitu se source/protocol/asset manifestem; SDK operace používají FVM. `check` spustí izolovaný headless browser přes stejný artefakt a uloží krátký report, screenshoty a failure logy. `open` vypíše odkaz a otevře novou kartu jen na výslovné přání. `stop` ukončí pouze vlastní task session.

Preferovat přímo otevřitelný `file://` demo kit s vloženými zdroji. Funkční Flutter web může vyžadovat HTTP kvůli loaderu/WASM/fetch; G0 to musí doložit. Pouze tehdy je pro běžící aplikaci přípustný explicitní package launcher na loopback s přiděleným portem, vlastním PID a úklidem, bez Festapp dev serveru a bez bindu do LAN. Agent při ověření vždy ukončí vlastní server/browser. Statický report výsledků je samostatné `file://` HTML a žádný server nepotřebuje. V README jasně oddělit build prerequisites (SDK/toolchain cache) od offline provozu již sestaveného kitu; netvrdit instalaci bez internetu na čistém stroji.

### Konkrétní výchozí šablony

**Závazné vlastnictví:** všech 9 níže uvedených šablon je dodávanou součástí veřejného balíčku a galerie samostatného editoru, nikoli pouze demo fixtures. Balíček vlastní verzovanou knihovnu šablon, jejich metadata, potřebné licencované assets a veřejné API pro vytvoření editovatelného dokumentu s novými IDs. Editor je nabídne bez Festappu i bez demo hosta. Demo používá přesně tuto knihovnu přes public API; nemá kopie ani vlastní generátory těchto šablon. Syntetické ceny, obsazenost a simulace se připojí zvlášť přes demo hosta. Release archive a čistý consumer smoke musí ověřit přítomnost a otevření všech šablon také přímo v editoru bez demo adapters.

Všechny jsou syntetické, bez kopírování soukromé grafiky; základní místa jsou dostupná. Obsazenost se zapíná jako samostatný demo scénář. Počty jsou seed defaults, upravitelné přes stejné generátory jako ruční práce. Thumbnail vzniká z dokumentu, nemá ručně kreslenou druhou podobu. Karta ukazuje počet adresných míst a kapacitu stání odděleně; fitting preview uvádí neumístěná místa s důvodem a Apply je jediný undo krok.

| ID / šablona | Výchozí obsah | Co na ní ověřit |
|---|---|---|
| `ball-classic` / Klasický ples (výchozí) | 12 obdélníkových stolů po 6 místech = 72; parket, pódium, vstup a 2 sloupy | Zřejmý plesový začátek, fitting u překážek, přidání židlí a cena stolu |
| `ball-round` / Kulaté stoly | 10 stolů po 8 = 80; parket a pódium | Rovnoměrný kruhový reflow, limit velikosti, rotace |
| `ball-mixed` / Smíšený ples | 6 obdélníkových po 6 + 4 kulaté po 8 = 68 | Oba typy, cenové výjimky, přesun židle s undo |
| `ball-balcony` / Členitý sál s balkónem | Přízemí 8 stolů po 6 + balkón 4 po 4 = 64; obrys do L, schody a sloupy | Vše v jediném plánku, názvy oblastí a žádné překryvy |
| `lounge` / Lounge a stání | 6 gaučů po 2 = 12 adresných míst, 4 odkládací stolky a plocha pro 20 stojících | Gauč `×2` celý, stání počet z 20; oddělit seats od standing capacity |
| `auditorium` / Řadový sál | 10 řad, 2 bloky po 6 = 120; středová ulička a jeviště | Číslování, hromadné změny, ruční výjimka |
| `bus` / Autobus | 10 řad 2+2 + zadní lavice 5 = 45; dveře, řidič jako dekorace | Schematic doprava, vlastní čísla, odebrání míst |
| `train` / Dva vozy s kupé | 2 vozy, každý 4 kupé po 6 = 48; chodby a 2 označené oblasti | Společný přehled, protilehlá místa, sekce a číslování |
| `blank` / Prázdný plánek | Prázdné plátno s rozumnou velikostí | Ruční tvorba bez šablony |

Testované objektové předvolby zahrnou i oválný stůl, lavici, jednotlivou židli, dveře, schody, pódium, parket, bar a sloup. Předvolba je geometrie s rolí a přístupným názvem; dekorace se nesmí započítat do prodejné kapacity. Diagnostické generované plány 500/5 000/20 000 míst jsou výkonnostní corpus mimo galerii pro pořadatele.

### Rozdělení mezi subagenty a efektivní pořadí

Použití subagentů je výslovně požadované uživatelem. Koordinátor drží plán, veřejné kontrakty, integraci změn a finální gates. Nejvýše 3 pracovní subagenti současně (4 sloty včetně koordinátora); další agent vzniká jen pro připravený nezávislý úkol. Žádné rekurzivní delegování ani soutěž několika agentů o stejný UI návrh.

| Pracovní balík | Model / vlastník | Vyhrazené soubory a výstup | Závislost |
|---|---|---|---|
| Core a runtime | Výchozí coding model, subagent core | `packages/venue_layout_core/`, kernel build/export, geometrické a parity unit fixtures | Koordinátor provede G0, zmrazí contract v1 |
| Samotné UI/UX | **`gpt-6-astra`, `reasoning_effort: medium`, `fork_turns: none`**, subagent ui | Package editor/viewer widgets, toolbar, inspector, galerie, touch/keyboard, animace, sémantika; čte UX skills | Nejdřív krátký tok a stavy nad kontraktem, funkční UI po G0/1; žádný vlastní core |
| Demo a šablony | Výchozí coding model, subagent demo | Package knihovna `lib/src/templates/` a její assets/public API přes koordinátora; `example/`, `web/demo/`, demo adapters, launcher a README | Stabilní veřejné API; první vertikální průchod před rozšiřováním šablon |
| QA a distribuční kontrola | Výchozí coding model, znovupoužitý volný slot | package integration/parity harness, smoke z archive, report DA; neimplementuje paralelní UI | Spustitelné demo; stejné testy doplňovat průběžně, finální běh na sloučeném stavu |

Koordinátor vlastní sdílené manifests, public barrels, schema/types a změny závislostí. Před delegací zapíše konkrétní soubory, vstupní revision, kontrakt, exit kritéria a jeden relevantní validační příkaz; při kolizi vlastnictví změnu převezme nebo přerozdělí. Agenti neupravují cizí dirty changes, nerestartují cizí server, neprovádějí git reset ani produkční operace. Oddělené worktrees jsou volitelné podle stavu repozitáře, nikoli povinná režie pro každou malou změnu. Handoff obsahuje diff paths, změny kontraktu, skutečné výsledky a zbylá rizika.

**UI balíky pro Astra Medium:** nejprve galerie a shell, potom inspector/paleta a dotykové ovládání, následně zákaznický náhled/chybové stavy a nakonec responsive/motion kontrola. UI agent vlastní package widgets, demo agent jejich zapojení v `example/`; controller/core vlastní výhradně core agent. Tato revize plánu prošla cílenou UI konzultací přes `gpt-6-astra` na medium; nejde o důkaz testování implementace.

**Kritická cesta:** G0 -> schema/public contracts -> jeden stůl + text + local save/reopen + oba renderery -> kompletní tools/fitting -> všechny šablony -> 10A. Po G0 mohou paralelně běžet UI nad stabilním controller interface, doplňování core algoritmů a demo adapters/templates. Přes tentýž slot UI agent dokončí responsive/motion polish; nenajímá se nový agent pro každou obrazovku. Současné tři full buildy se nespouštějí: koordinátor vlastní build lock a integrační batch. Nedělat SQL nebo připravovat Festapp font refaktor „pro úsporu času“ během A.

První kontrolovatelný milestone je minimální funkční vertikální tok, nikoli statická maketa; není to předčasný konec A. Po každém uceleném balíku spustit pouze jeho cílenou kontrolu, finální shared/parity/E2E/archive batch jednou po sloučení. Opakovat jen při změně pokrytého kódu nebo selhání. Astra Medium nesmí být potichu nahrazena jiným modelem; případnou nedostupnost sdělit a koordinátor pokračuje nezávislou prací. Budoucí B má vlastní bounded backend a host tasky; nespouštějí se nyní.

### Akceptace samostatného dema

| ID | Povinný důkaz před dokončením A |
|---|---|
| DA01 | Kit z čistého package archivu funguje bez Festapp checkoutu, `.env`, backendu a přihlášení; všech 9 šablon má správné counts, unikátní IDs a lokální assets; jsou dostupné přes public API i galerii samostatného editoru bez demo hosta. |
| DA02 | Nový uživatel vybere Klasický ples, vloží stůl/židle, změní text/font/barvu, otočí objekt, nastaví ukázkovou cenu, undo/redo, uloží/exportuje a znovu otevře bez ztráty podkladu či vazeb. |
| DA03 | Flutter a JS picker načtou stejný export; gauč vybere dvojici, stání 2 z 20, badge celkové kapacity se nezamění za vybraný počet. Stavový patch nemění geometrii/kameru. |
| DA04 | Lokální failure/timeout/conflict a font race nepoškodí draft; reload obnoví autosave, neplatný import či plný storage mají srozumitelnou obnovu a funkční export. |
| DA05 | Desktop mouse/keyboard a touch na 360/900/1440 px, vložení bez hover/drag, focus/sémantika, IME/české texty s otevřenou klávesnicí a reduced motion; návrat z náhledu zachová draft a výběr; browser flow používá skutečná gesta, ne jen volání controller metod. |
| DA06 | Exact scene parity a cílené raster/motion porovnání; corpus 500/5 000/20 000, dokumentovaný hardware/browser/SDK, init/frame/memory podle stávajících cílů. Nesplnění je explicitní, ne skryté snížení rozsahu. |
| DA07 | Opakovatelné `build/check/stop`, izolovaný headless smoke a přenosný report; žádný ponechaný server, žádné ovlivnění uživatelova prohlížeče. Licenční/asset manifest a offline runtime ověřené s vypnutou sítí. |
| DA08 | Public API/import/export a consumer smoke ověří právě zabalený obsah; package zdroje ani demo neimportují Festapp/Supabase. Předání obsahuje spuštění, reset, export, report a přesný seznam simulovaných obchodních funkcí. |

**Mapování AC na A:** skutečně ověřit package/UI části AC01-14, AC22-24, AC27-29. AC07 ověřuje obecný provider a font parity, nikoli dosud neintegrovaný Ticket picker; AC01/05 node identity a místní persistence, nikoli spot IDs v DB. AC03/21/25/26 a konflikty AC15-18 lze předvést přes mock hranici, ale ve výsledcích zůstávají jako „simulace, čeká B“, nikdy splněný SQL test. AC19-20 (legacy/setup/copy) celé čekají B. AC28 má v A syntetický cenový draft a roundtrip; produkční bindingy až B. Finální report uvádí pro každý AC stav package pass / simulace / odloženo B a odkaz na důkaz.

## Závazná rozhodnutí

**Hlavní produktový princip potvrzený uživatelem:** co nejjednodušší ovládání a co nejlepší automatické výchozí chování. Rutinní mechaniky řeší editor bez průvodců a opakovaných potvrzení: umístění, přichytávání, rozmístění židlí, dědění cen při změně stolu, číslování nových objektů a dostatek prostoru na plátně. Pokročilé hodnoty jsou dostupné až na vyžádání. Automatika má předvídatelný náhled, je vratná přes undo a nemění svévolně identitu, existující zákaznické označení nebo objednávku. Další produktové otázky mají řešit skutečně nejasný obchodní význam, nikoli přenášet návrh běžných detailů na uživatele.

1. Editor je od prvního commitu samostatně použitelný a vydatelný balíček. Festapp host adaptéry nepřebírají obecné nástroje ani geometrii.
2. Jeden existující fontový katalog a stejný picker, načítání, cache a error chování jako v ticket editoru. Žádný blueprint seznam fontů.
3. Jeden core pro Flutter i JS, s prokázanou shodou scén před stavbou velkého UI. Export technologie zatím není implementovaný ani změřený.
4. Úpravy jsou lokální a vratné; produkční save je jediný atomický command s revision a zachováním spot ID.
5. Dvanáct vln je rozděleno do samostatných etap A/B/C. Etapa A končí ověřeným demem a package release kitem bez integrace; integrační a migrační důkazy patří až do B. Akceptace má 29 doménových scénářů a demo brány DA01-DA08.

## Ověřený současný stav

| Fakt | Důkaz v aktuálním kódu | Důsledek |
|---|---|---|
| Flutter viewer, picker i editor pochází z veřejného balíčku | `pubspec.yaml`, `pubspec.lock`: `venue_seat_picker` 0.1.2, Git ref `c829a33d07de9a8fa376b407658875d22abd246e`; `lib/components/blueprint/README.md` | Obecná geometrie a interakce patří do tohoto balíčku, obchodní pravidla do Festapp. Neupravovat pub cache. Zdrojový checkout existuje v `/Users/miakh/source/venue_seat_picker`. |
| Controller je hustá celočíselná mřížka | Pinovaný balíček: `VenueSeatController.loadPlan`, `slots`, `replaceSeat`; `VenueSeatDocument` schema 1 | Pozice nelze pouze rozšířit o rotaci. Je třeba řídký objektový dokument a prostorový index bez alokace všech prázdných buněk. |
| Festapp mapuje místo přes řádek/sloupec | `blueprint_object_model.dart`, `blueprint_seat.dart`: `SeatPosition(y, x)`; `blueprint_configuration.dart` | Stávající `x/y` jsou indexy mřížky, nikoli volné souřadnice. Převod musí mít explicitní měřítko. |
| Editor kombinuje tvorbu a provoz rezervací | `views/blueprint_editor_tab.dart`: `BlueprintSelectionMode`, `saveChanges`, `loadData`, `BlueprintTab.prototype` | Oddělit návrh geometrie a správu objednávek, zachovat obě vstupní cesty včetně setup prototypu. |
| JS má nezávislou geometrii a vzhled | `blueprint_data_preparer.js`, `blueprint_renderer.js`, `blueprint_config.js`, `seat_styler.js`, `svg_utils.js` | JS umisťuje objekty jako `x/y * seatSize`; `seatSize` je 60, Flutter wrapper používá 15. Relativní škálování není společný kontrakt. |
| Existující model je rozdělený mezi JSON a databázová místa | `database/tables/tables.sql`: `eshop.blueprints.objects/configuration/groups/background_svg`, `eshop.spots` | Identita místa a jeho objednávka nesmí záviset na pořadí objektů ani souřadnicích. |
| Zápis už má receipty Client Sync | `supabase_form_commands.dart::saveBlueprint`, migrace `20260802234000_client_sync_v1_expansion.sql`: `update_blueprint_client_sync_v1` -> `update_blueprint_internal_v1` | Rozšířit existující command, replay a invalidaci. Nevytvořit druhou save API. Starší Dart transport volá facade `update_blueprint`. |
| Původní SQL průběžně mění místa před některými business chybami | `database/functions/eshop/update_blueprint.sql`: aktualizace/vkládání míst před kontrolou nemožného smazání, chyba se může vrátit jako JSON | Nový save musí garantovat rollback všech doménových zápisů i při zamítnutém výsledku. Samotný receipt nezaručuje atomitu. |
| Existují další čtenáři a zapisovači | `get_blueprint.sql`, `get_blueprint_for_edit.sql`, `occasion_setup/finalize.sql`, `others/duplicate_occasion.sql` | Převést také setup, duplikaci, veřejné projekce a jejich aktualizované migrační definice. Nestačí upravit editor. |
| Editor vstupenek má potřebné principy | `ticket_layout_controller.dart`, `ticket_snapping.dart`, `views/ticket_layout_canvas.dart`, `ticket_layout_saver.dart`, `ticket_layout/README.md` | Použít transakci gesta, jeden undo krok, původní nesnapovanou pozici, magnet v obrazových pixelech, vodítka, lokální repaint, ochranu draftu a konfliktu. |
| Aktuální resize ticket editoru zachovává geometrii obsahu | `ticket_layout/README.md`: Saved data and print resources; `TicketLayoutController.resizeCanvas` | Blueprint převezme živý náhled a ochranu blokujících objektů; sedadla se při zmenšení nesmějí tiše skrýt. Starší popis škálování ticket návrhu není pravidlem resize plátna. |
| Font katalog není runtime vektorový renderer | `font-catalog.json`: 1 896 entries, styly pouze `normal`; `ticketFonts.ts::fontMetrics`, `ticket_text.dart::ticketTextInsets` | Pro Blueprint je nutné generovat glyph obrysy. Ticket editor už používá syntetické tučné/kurzívu; prosté sdílení TTF názvu by nedokazovalo paritu. |
| Upload policy pro blueprint už existuje | `ImageUploadProfile.blueprintBackground`, `workers/image-worker/src/upload-policy.ts` | Zachovat serverem vlastněný profil 3000 px / 800 KiB / quality 90 a stávající upload flow. |
| Hold již zamyká řádek místa | `select_spot.sql`: buyer advisory lock, potom `spots ... FOR UPDATE` | Save nesmí získávat buyer/admission advisory lock po zamčení místa. Test musí prokázat save-vs-hold chování ve dvou session. |
| Setup má další lokální serializaci plánku | `lib/components/occasion/setup/occasion_setup_page.dart`: `_save` payload, prototype callback, `blueprintObjects` a `blueprintBackground` | Převést také pending setup drafty, čítač míst a edit-reopen. Přítomnost dekorací nesmí začít znamenat prodejní kapacitu. |

Reprezentativní tok dnes: `BlueprintTab` -> `VenueSeatController` -> `DbForms.updateBlueprint` -> command/facade -> interní SQL -> `eshop.blueprints` + `eshop.spots`. Čtení editoru přes `get_blueprint_for_edit`; veřejný výběr přes `get_blueprint` a samostatné Flutter/JS renderery. Rezervace nadále rozhoduje `select_spot`; objednávky a výměny jejich stávající receipted SQL/Edge hranice.

Dokumentace a zdroje byly čteny lokálně. Nebyl prováděn audit živých dat, browser audit existujícího UI ani produkční inventura. Později byl prohlédnut lokální snapshot skutečných plesových plánků a skautský PNG podklad; přesný rozsah důkazu je uveden v sekci referencí. Vnější inspirace není nutná pro tato rozhodnutí.

## Produkt a ovládání

### Pracovní plocha

- Samostatný široký editor: nahoře Zpět, název, stav změn, Undo/Redo, Náhled zákazníka, Uložit. Vlevo nástroje a vložení, uprostřed dominantní plátno, vpravo kontextové vlastnosti a strom vrstev. V etapě A použít vlastní neutrální package shell a injektovatelné lokalizované texty; existující shell a lokalizační konvence Festapp připojit až v B.
- Nástroje: výběr, posun plátna, sedadlo, stůl, řada/blok, dopravní sestava, tvar, text. U vybraného objektu jen relevantní vlastnosti. Nový plánek otevírá vizuální výběr šablon podle ticket editoru; výchozí nabídka ukazuje plesové sály. Prázdný plánek je také jedna z voleb. Existující uložený plánek se otevírá přímo do editoru.
- Pod 900 logických px jeden kompaktní toolbar, plátno a spodní panel Objekt/Vlastnosti/Vrstvy. Vkládání i přesné souřadnice fungují dotykem bez hoveru. Druhý prst posouvá/přibližuje; aktivní drag vlastní jen jeden objektový nástroj.
- Klik vybírá, Shift přidává, rámeček vybírá více, Escape ruší gesto/nástroj, Space dočasně posouvá, šipky posouvají, Shift zvětšuje krok, Delete maže povolené objekty, Cmd/Ctrl+D kopíruje, Cmd/Ctrl+Z a redo odpovídají platformě. Klávesové zkratky nekradou vstup textovým polím. Kontextová nabídka má dotykovou alternativu.
- Rodičovský objekt lze vybrat jedním klikem, konkrétní sedadlo dvojklikem nebo ve stromu. Uživatel může zarovnat, rovnoměrně rozložit, seskupit/rozpojit, zamknout a měnit pořadí vrstev. Skrytí v editoru je stav relace; skrytí veřejné vrstvy je explicitní součást dokumentu a nikdy neukryje prodávané sedadlo.

### Výběr šablony a jednoduchý plesový začátek

**Potvrzené rozhodnutí uživatele:** začátek tvorby má nabídnout šablony obdobně jako ticket editor, nikoli povinný parametrický průvodce nebo automaticky otevřené prázdné plátno.

Galerie ukazuje názorné lokálně vykreslené náhledy, název a krátký popis. Výchozí nabídka je zaměřená na ples; jiné typy prostorů jsou dostupné přes kategorie. Volba Prázdný plánek zůstává v galerii. Samotný výběr šablony otevře editovatelný návrh bez povinného mezikroku. Nastavení počtu stolů a míst je následná volba v editoru. Potvrzeno uživatelem: nabídnout více plesových variant, nevybírat jediné univerzální uspořádání. Galerie zahrne varianty s obdélníkovými, kulatými a kombinovanými stoly, lounge sezení a členitý sál s balkónem. Konkrétní počty jsou editovatelné příklady, nikoli omezení modelu.

Použít stejné principy gallery a thumbnail renderingu jako v ticket editoru. V etapě B může layout galerie znovupoužít existující vhodné UI části přes host shell; obecná gallery v balíčku nesmí importovat Festapp ticket modely. Výběr kopíruje dokumentovou geometrii a styly s novými IDs, nepřenáší skutečné produkty, rezervace ani zákazníky. Zvolená šablona se nestává druhým runtime zdrojem geometrie. Pozdější volba jiné šablony je explicitní náhrada s náhledem a jedním undo krokem; nikdy neobejde ochranu prodaných/držených míst.

Při akceptaci AC01 doplnit vstup přes galerii a volbu Prázdný plánek, u AC24 ověřit galerii ve standalone example. Implementovat jako součást vlny 4 a plesové šablony doplnit ve vlně 6. Existující dokument při opětovném otevření galerii nevyžaduje.

### Text, kreslení a knihovna objektů

- **Text je samostatný objekt:** vložení klikem nebo přetažením, editace dvojklikem i přes inspector, více řádků, výběr fontu s ukázkou, řezu (běžný/tučný/kurzíva podle společné politiky fontů níže), velikosti, barvy, zarovnání a řádkování. Barva má picker i HEX a podporuje průhlednost. Psaní podporuje českou diakritiku, schránku a IME; jeho klávesy neovládají plátno. Editační textové pole je pouze overlay, konečný náhled musí projít společným textovým layoutem.
- **Velikost textového boxu není změna fontu:** tažení šířky mění zalomení, velikost fontu se mění výslovným ovladačem. Volitelný příkaz Přizpůsobit text boxu má náhled a minimální velikost; žádné tiché zmenšení. Přetečení je viditelné a obsah se bez oznámení neodřízne. Text lze otočit stejně jako jiné objekty; čitelnost labelů sedadel je oddělené pravidlo od orientace jejich symbolu.
- **Jeden fontový katalog a stejné chování jako ticket editor:** použít přesně `TicketFontCatalog.load()` a `FontFamilyPicker`, včetně oblíbených rodin, rozšířeného výběru, dědění fontu dokumentu a přepsání na jednotlivém textu. Nezavádět blueprint katalog, kurátorovaný podvýběr, nové font ID ani samostatný seznam rodin v balíčku. `supabase/functions/_shared/ticket-assets/font-catalog.json` zůstává jediná autorita. Fonty se načítají až po výběru přes tentýž hashovaný resolver a cache, úspěch se teprve potom zapíše jako undoable změna. Rychlá volba A -> B nesmí po pozdním doběhnutí A přepsat B. Chyba zachová předchozí font. Balíček dostává seznam a zdroje přes obecný provider; nezná ticket endpoint ani umístění katalogu. Pro shodu renderů dodá provider také odvozené metriky a obrysy stejných bajtů; ty jsou cache renderovacích dat, nikoli druhý katalog. Tučné a kurzíva použijí stejnou syntetickou politiku jako ticket editor (obrys a shear), dokud katalog neobsahuje explicitní řez. Chybějící font nebo glyf je viditelný stav bez automatického přepsání uloženého dokumentu. Nahrávání vlastních fontových souborů není podmínkou této verze.
- **Kreslicí nástroje:** čtverec/obdélník se zaoblením, kruh/elipsa, čára, šipka, lomená čára a uzavřený mnohoúhelník. Tažením se určí rozměr, Shift drží poměr stran nebo úhlový krok. Lomenou čáru a polygon lze dokončit Enterem/dvojklikem, zrušit Escape a upravovat přes vrcholy. Inspektor nabídne výplň, barvu/tloušťku/styl obrysu, průhlednost a podle typu zakončení šipky. Prosté tvary zůstávají dekoracemi, dokud uživatel explicitně nezvolí fyzickou překážku nebo vyhrazenou plochu.
- **Knihovna vlevo:** vyhledávání, kategorie Sedadla / Stoly / Vybavení / Tvary / Text / Vlastní a názorné miniatury ze stejného rendereru. Předvolby obsahují také pódium, bar, schody, WC, dveře, východ, řidiče a dopravní sestavy. Objekt lze přetáhnout na plátno nebo vybrat a umístit klikem; dotyk a klávesnice musí mít stejně plnohodnotnou alternativu.
- **Drag-and-drop:** během přetažení ghost v měřítku plátna, kurzorová kotva, snapping a stav platného umístění. Drop převede screen souřadnice inverzní kamerou i parent transformací; funguje při zoomu, posunu a rotaci cílové skupiny. Okraj plátna podporuje omezený autopan. Escape/drop mimo plátno nic nezmění. Úspěšný drop celé předvolby je jeden undo krok a všechna její ID jsou nová.
- **Vlastní objekty:** vybrané tvary, text a případná sedadla lze seskupit a uložit jako znovupoužitelnou předvolbu v knihovně tohoto dokumentu, přejmenovat a exportovat/importovat jako validovaný dokumentový fragment. Součásti zůstávají editovatelné. Předvolba je snapshot, následná změna instance nemění jiné instance. Obchodní bindings, produkty, objednávky a secret se do předvolby neukládají; kopie sedadel vyžádá výběr produktu. Sdílení knihovny mezi organizacemi není podmínkou editoru.

### Rotace, měřítko a velikost plátna

**Potvrzené rozhodnutí uživatele:** editor pracuje schematicky jako dnešní plánky. Uživatel nemusí měřit sál ani zadávat metry, mm, měřítko podkladu či skutečné rozměry nábytku. Běžné UI nabízí velikost objektu, počet míst a přetažení; interní world jednotky nejsou zákaznická fyzikální veličina. Předvolby mají vzájemně konzistentní proporce stolů a židlí. Limity sezení jsou geometrická a proporční pravidla návrhu, nikoli výpočet skutečné stavební kapacity. Reálné rozměry a fyzická kalibrace nejsou součástí tohoto zadání a nesmějí komplikovat základní tok ani být podmínkou validace.

- Každý podporovaný objekt, text, stůl i sestava má rotační úchyt, přesný úhel v inspectoru, rychlé Otočit vlevo/vpravo o 90 stupňů a Vrátit natočení. Volná rotace drží pointer bez zpoždění; Shift přichytává po 15 stupních a Alt dočasně vypíná úhlové magnety. Proti sobě orientovaná sedadla u stolu mají správnou lokální orientaci.
- Výchozí pivot jednotlivého objektu je jeho střed, multi-select společný střed obálky; inspector dovolí zvolit střed nebo roh obálky jako pivot a jasně ho zobrazí. Jádro po operaci zapíše výsledné transformace, nikoli druhou skrytou soustavu souřadnic. Otočení skupiny skládá parent/child transformace, nikdy znovu negeneruje místa. Locked potomci blokují celou operaci místo částečného překvapivého otočení.
- Resize přes rohy/hrany i číselný vstup, přepínač poměru stran a minimum podle typu. Samostatné sedadlo může mít upravitelný půdorys, ale hromadné fitování nesmí potichu měnit rozměry sedadel. Zrcadlení dekorativních tvarů je možné materializací geometrie; zrcadlení prodejní sestavy není automatická náhrada rotace a nesmí obrátit text ani pořadí čísel.
- **Plátno:** nastavit šířku/výšku, barvu pozadí, poměr stran, orientaci a okraje; rozměry uvádět jako schematickou velikost, bez fyzických jednotek. Rozměry plátna nejsou zoom ani velikost podkladového obrázku. Výchozí změna rozměrů zachová rozměry i pozice objektů. Uživatel volí kotvu původního obsahu (roh/střed), může prohodit šířku/výšku nebo použít Přizpůsobit plátno obsahu s paddingem.
- Při zmenšení ukázat přesný náhled objektů mimo nový okraj a nabídnout zvětšení plátna nebo explicitní přesun vybrané sestavy. Uložení nesmí tiše oříznout sedadla, odpojit potomky ani skrýt objekty mimo viewBox. Samostatné Přizpůsobit rozmístění nové ploše mění rozestupy/pozice s kontrolou kolizí a zachovává skutečné rozměry sedadel; změna rozměrů plátna není tímto příkazem.
- Každý dialog má živý lokální náhled; Potvrdit = jeden undo krok, Zrušit = přesně původní stav. Nezměněné zobrazené zaokrouhlené rozměry nesmí měnit uloženou přesnost. Numerické limity stanovuje tabulka kontraktu níže; první technická brána je ověří na fixtures. Nepřebírat tiskové limity 60-842 pt z ticket editoru.

### Automatické rozšiřování plátna

Z odpovědi uživatele vyplývá automatický výchozí režim: při platném přetažení nebo vložení objektu za okraj se plátno rozšíří tak, aby objekt zůstal celý uvnitř s konzistentním okrajem. Stejně se posuzuje obálka celého stolu se sedadly, rotovaná skupina a její popisky, nikoli jen anchor bod. Žádné dialogové „chcete zvětšit plátno?“ u běžné manipulace. Volitelný pevný okraj lze nabídnout až v pokročilých vlastnostech, není druhou úvodní otázkou.

Rozšíření se ukazuje v ghost náhledu a při dokončení se uloží s operací objektu jako jeden command/undo krok. Escape, pointercancel, neplatný drop nebo nedostatečná kapacita vrátí objekt i původní plátno. V průběhu jednoho drag gesta se vychází z počátečního snapshotu; návrat pointeru dovnitř nesmí zanechat zbytečně nafouknuté plátno. Po dokončení běžného gesta se plátno samo nezmenšuje, aby ostatní obsah a kamera neposkakovaly. Přizpůsobit plátno obsahu zůstává explicitní příkaz.

Při rozšíření vlevo/nahoře změnit canvas `x/y` a rozměry; nepřepisovat world souřadnice ostatních nodes ani registraci podkladu. Kamera během drag zachovává world-to-screen mapování a pozici objektu pod pointerem, fit-to-all se nespouští automaticky. Opatrný autopan u okraje viewportu je samostatná camera operace; expanze plátna není přiblížení/oddálení. Podklad zůstává registrovaný, na nové ploše pokračuje canvas fill; neroztahuje se automaticky bitmapa.

Automatická expanze neobchází překážky, zakázané oblasti nebo horní limit velikosti dokumentu. Canvas je pracovní plocha, obrys místnosti je samostatný objekt: zvětšení pracovního prostoru neznamená posunutí stěny či povolení sedadel mimo deklarovaný sál. Nový nábytek lze rozpracovat na rozšířeném plátně; přiřazení do konkrétní místnosti znovu ověří její platné oblasti. Pokud musí uživatel upravit půdorys, označit důvod přímo u objektu a nabídnout vhodnou akci.

Ruční zmenšení plátna je výslovná akce a dál nesmí skrýt/odstranit sedadla. Při běžném vložení a zvětšování sestavy automaticky nabídnout potřebný prostor, zachovat stávající limity kolizí. Implementovat ve vlně 5 přes společný core command, nikoli oddělené `setState` ve Festapp. AC11-AC14 doplnit o rozšíření na všech čtyřech stranách, otočený objekt, ghost návrat dovnitř, cancel/undo, neměnnou polohu ostatního obsahu a podkladu a stabilní kameru.

### Inteligentní výměna a nastavení podkladu

Referencí je `ticket_layout/README.md`, části Saved data and print resources a Preview and save lifecycle: lokální preview, contain/fill/center, nezávislá transformace obrázku, nedestruktivní crop, výběr při změně poměru stran a jeden undo krok. Blueprint přebírá interakční principy, nikoli PDF jednotky nebo print upload budget vstupenky.

1. Podklad lze zvolit z předvoleb, nahrát nebo odstranit. Nové assety jdou přes stávající image infrastrukturu. Náhled ukazuje také velké plány, průhledné PNG a jejich skutečné rozlišení; použít existující profil `blueprint-background` (maxEdge 3000, budget 800 KiB, quality 90), vstup do 20 000 000 bajtů a 40 000 000 pixelů. Limity vlastní Worker, klient je nekopíruje jako konkurenční politiku. Pro větší rozlišení se případná změna řeší ve Worker profilu podle změřené čitelnosti. Nepoužívat ticket limit 1080 px.
2. Režim Upravit podklad mění pouze obrázek: posun, jednotné měřítko, rotace, průhlednost a nedestruktivní crop. Zdroj zůstává zachovaný, crop nevyvolává reupload. Výchozí contain zachovává poměr stran; příkazy Vejít celý / Vyplnit plátno / Vycentrovat jsou explicitní a fill ořez je náhledově viditelný. Ořezané okraje jsou v editačním režimu stále naznačené. Žádné protažení os.
3. Při výměně nabídnout Zachovat rozmístění a plátno (výchozí), Zachovat registraci podkladu, nebo Upravit plátno podle poměru nového podkladu. Každá volba má náhled. Zachování registrace zachová explicitní world transformaci, ne náhodně dopočítanou CSS velikost; u jiného nativního rozlišení používá normalizované rozměry zdroje. Starý crop se nepřenáší na jiný obrázek bez potvrzení.
4. Pro podklady s jinou geometrií nabídnout Zaregistrovat pomocí dvou bodů: uživatel přiřadí dva různé body nového podkladu dvěma existujícím bodům plánu; jádro vypočte posun, jednotné měřítko a rotaci. Zobrazit overlay před/po. Nejde o automatické rozpoznávání míst ani zkosení plánu; sedadla a jejich identity zůstávají na místě.
5. Při prvním vložení do prázdného dokumentu nabídnout založení rozměrů podle poměru podkladu; u hotového plánku se plátno samo nezmění. Odstranění podkladu nechá objekty a velikost plátna. Opaque/transparent canvas fill má na obou platformách stejný výsledek.
6. Chyba uploadu/dekódování nebo Cancel zachová předchozí podklad i geometrii. Výměna, transformace a crop patří do undo/redo jako reference a metadata; historie neukládá kopie bitmap. Neuklízet assety při Cancel/Undo, cleanup vlastní stávající asset lifecycle. Potřebné starší assety držet dostupné po dobu historie.

### Stůl a postupné přidávání sedadel

1. Vložit kulatý, oválný, obdélníkový nebo zaoblený stůl; nastavit rozměr a označení.
2. Vybrat Přidávat sedadla. Kolem obvodu se objeví platné náhledové kotvy. Klik přidá jedno sedadlo, nástroj zůstává aktivní. U obdélníku se volí strana; u kruhu výchozí orientace oblouku. Rozmístění připojených židlí se automaticky upraví podle typu stolu a respektuje jeho vypočtenou maximální kapacitu. Sedadla se natočí ke stolu a dodrží odstup; před klikem se ukáže výsledná celá sestava.
3. Alternativa Rozmístit N sedadel ukáže náhled počtu na stranách nebo po oblouku. Potvrzení je jeden undo krok. Zachovat ID existujících sedadel; změna počtu přidává/odebírá konkrétní objekty, neobnovuje všechny.
4. Přesun a otočení stolu přenese připojená sedadla. Změna rozměru přepočítá jen připojené kotvy. Ručně posunuté sedadlo drží vlastní offset; explicitní Odpojit odstraní vazbu, nikoli prodejní identitu.
5. Když se další sedadlo nevejde, zobrazit důvod a nabídnout větší stůl, menší rozestup nebo změnu počtu. Nikdy tiše nezmenšit sedadla nebo nepřečíslovat ostatní stoly.

### Automatické rozmístění a maximální kapacita stolu

**Potvrzené pravidlo uživatele:** při přidání židle má editor inteligentně přerovnat sezení podle typu stolu, zejména u kulatého. Pro zvolenou velikost stolu musí existovat rozumné maximum; nepřidávat neomezeně mnoho židlí nebo je automaticky zmenšovat. Základní použití nevyžaduje ruční nastavování constraintů.

| Typ stolu | Výchozí přepočet při přidání/odebrání židle |
|---|---|
| Kulatý | Rovnoměrně přerovnat všechna automaticky připojená místa po povoleném obvodu; zachovat IDs, pořadí čísel a zvolený počáteční směr. Zakázaný oblouk například u stěny nesmí dostat nové místo. |
| Oválný | Stejné pravidlo po délce obvodu, nikoli podle shodného úhlu; skutečné obrysy ověřit na koncích elipsy. |
| Obdélníkový / dlouhý | Klikem se zvolí strana a rovnoměrně se přerovná dotčená strana; ostatní strany drží svůj počet. Plesová předvolba nabídne sezení po dlouhých stranách, čela lze explicitně povolit. Rohové konflikty posuzovat mezi stranami. |
| Nepravidelný nebo ručně upravený | Přepočítávat pouze deklarované kotevní úseky a automatická místa. Ručně fixované pozice a odpojené židle jsou explicitní výjimky, ne body pro globální přeskupení. |

Každá předvolba definuje realistický poměr velikosti stolu a sedadel, povolené strany/oblouky a profil místa u hrany. Kapacita se počítá z použitelné délky hran/obvodu, minimálního prostoru na jedno místo u stolu, skutečné šířky a hloubky židle, odstupu od stolu, rohových rezerv a okolních překážek. Pouhý obvod vzdáleného kruhu středů židlí není kapacita stolu - dovolil by příliš mnoho lidí u malého stolku. Fyzické kolize a prostor u hrany musí vyhovět současně.

Pro každou povolenou stranu nejprve spočítat horní mez z délky a minimální rozteče, potom ověřit konkrétní kandidáty a kolize celé sestavy. U kruhu analogicky z použitelného obvodu hrany stolu; obrysový test může kapacitu dále snížit. Zobrazit stručně například „6 / max. 8 míst“ až při výběru stolu nebo v nástroji přidávání; nejde o veřejný badge ceny či dostupnosti. V běžném zákaznickém plánku zůstane vizuální klid.

Po dosažení maxima nástroj zobrazí zablokovaný ghost a důvod „Pro tento stůl už není místo“. Nabídne zvětšit stůl nebo změnit povolené strany/uspořádání, ne přidat překrývající se místo. Advanced rozestupy se pohybují jen v platném rozsahu; nelze jimi obejít fyzické kolize. Pokud zvětšení brání stěna nebo sousední stůl, zobrazí se konkrétní překážka. Neprovádět skrytou změnu velikosti jiných objektů.

Přidání a celý odpovídající reflow jsou jeden command a jeden undo krok. Solver minimalizuje změnu existujícího pořadí a zachovává node/spot ID, cenové výjimky a objednávkové vazby. Automaticky se mohou pohybovat i již obsazené připojené židle, pokud jde pouze o geometrii; nesmějí se přejmenovat, smazat nebo přecenit. Locked/manual kotvy zůstávají na místě a vstupují jako constraints. Pokud se nový počet s nimi nevejde, operace se neprovede částečně a uživatel dostane vysvětlení.

Při zmenšování stolu pod kapacitu aktuálního počtu ukázat neplatný preview a nejmenší přípustný rozměr. Apply nelze dokončit, dokud uživatel velikost neopraví nebo explicitně neodebere povolená volná místa; nic se nesmaže automaticky. Změna parametrů nezpůsobí nové číslování jako vedlejší efekt. Pro původní importované plánky platí jejich explicitní pozice: konverze nikdy nespouští reflow, teprve budoucí vědomá editace sestavy může nabídnout automatické uspořádání.

Vlna 6 zahrnuje tyto politiky jako package table-type strategies nad jedním solverem. AC01/AC02 doplnit o přidání nad maximum, undo reflow, zachování produktových výjimek/ID a změnu rozměru při plné kapacitě; AC04 o stůl u stěny a zablokované čelo. Fixture stejných vstupů musí dát stejnou kapacitu i geometrii ve Flutter/JS core.

### Konkrétní reference skutečných plesových plánků

Pro tento návrh byla prohlédnuta lokální konfigurace šesti zdrojových akcí v soukromém snapshotu `../festapp-wizard-local/vstupenky-source-configurations.json`, popsaném v `docs/development/occasion-setup-local.md`. Nejde o čerstvou produkční inventuru; snapshot neobsahuje objednávky ani obsazenost. Nebyla kontaktována produkční DB. Pro Skautský ples byl přes lokální Storage načten a vizuálně prohlédnut původní PNG podklad 3000 × 3000; sedadlové pozice a počty byly ověřeny z konfigurace, nikoli novým browser screenshotem běžícího pickeru.

| Lokální zdrojová konfigurace | Ověřená struktura | Důsledek pro návrh |
|---|---|---|
| Skautský ples 2026 | Mřížka 32 × 32, 31 stolových skupin, 182 sedadel; 29 skupin po 6 a 2 skupiny po 4. Rastrový podklad má velký centrální parket, pódium nahoře, vstup a sloupy, obdélníkové stoly po obvodu i různě otočené sestavy dole. | První reprezentativní plesová předvolba má umět právě tuto kompozici: stoly/čísla, velký volný parket a překážky. Základní vzhled je čitelný půdorys, nikoli nutně fotorealistické židle. |
| Sportovní ples Větřkovice 2026 | 280 míst, 26 skupin, počty 10/12/14; SVG podklad a mřížka 29 × 54. | Podporovat dlouhé obdélníkové stoly, nepravidelné počty a vysoký sál bez vnuceného kruhového sezení. |
| Ples obce Větřkovice | 290 míst, 27 skupin, počty 10/12/14; SVG podklad a mřížka 29 × 54. | Varianta stejného prostoru s odlišným rozmístěním/kapacitou není jiný model nebo renderer. |
| Farní ples | 164 míst, 26 skupin po 4/8; SVG s viewBox a fyzickými jednotkami. | Výslovná reference pro kombinaci velikostí stolů a přesnou registraci podkladu. |

Skautská reference má hash konfigurace `591521c069c1f615dca2b8035ed7c6885416eed58a9abcae81a67a1393ea9b03` a PNG `37a346f6c7063c3e10cef03d462f736cefe41d7610e713bdaaaf3e778b807d77`. Identifikátory lokálního snapshotu nejsou autoritou pro aktuální produkční IDs. Původní konfigurace ani bitmapy se tímto nekopírují do veřejného balíčku: pro standalone example vytvořit vlastní syntetický ekvivalent tvarů a sestav, reference ponechat lokálnímu migračnímu corpus. Licence původních podkladů není doložena pro další publikaci.

Zachování vzhledu znamená, že původní plán lze po převodu zobrazit se stejným podkladem, registrací a polohami/označeními míst; nový objektový editor zároveň dokáže obdobné rozmístění vytvořit bez bitmapy. Není to požadavek převést bitmapový obrázek automaticky na editovatelné objekty nebo nasadit pouze kulaté stoly. AC19 použije skutečnou lokální skautskou geometrii a srovnání před/po, AC23 vlastní anonymizovaný protějšek se stejným typem kompozice. Před tvrzením plné vizuální parity v implementaci doplnit skutečně renderovaný Flutter/JS screenshot včetně sedadel; samotné prohlédnutí podkladu tento důkaz nenahrazuje.

### Gauče, lavice a členité sály

**Potvrzené požadavky uživatele:** více variant plesových šablon; součástí sezení mohou být gauče; prostor může být členitý a obsahovat balkón. Model ani fitting nesmějí předpokládat obdélníkový sál nebo jeden typ židle.

Knihovna nábytku obsahuje židli, křeslo, rovný i rohový gauč a lavici. Nábytek má vlastní editovatelný rozměr, orientaci a fyzický obrys. Předvolby kombinují nábytek se stolem, přičemž fyzický gauč není automaticky několik židlí položených přes sebe. Počet a identita rezervovatelných míst se oddělují od tvaru nábytku. Potvrzené rozhodnutí uživatele: u dvoumístného gauče se vždy vybírají obě místa naráz. Klik na kterékoli místo vybere celý pár; odznačení uvolní celý pár. Zůstávají dvě samostatně identifikovaná místa spojená pravidlem společného výběru. Nejde o pouhé vizuální seskupení. Cenu určuje stávající produktové přiřazení míst, společný výběr nepřidává zvláštní cenu za nábytek. Výchozí návaznost na existující model je jedna vstupenka na každé místo; gauč tedy vytvoří dvě vstupenky v jedné objednávce. Jde o návrhové rozhodnutí odvozené ze zachování dosavadního ticket modelu, nikoli zavedení nového produktu nebo jedné sdílené vstupenky.

Prostor lze popsat nekonvexním půdorysem s výklenky, navazujícími částmi, sloupy a vyřazenými plochami. Hranice použitelné plochy je odlišná od obdélníkového canvas viewBox a od dekorativního obrázku sálu. Fitting musí kontrolovat celý obrys sestavy uvnitř vybrané oblasti a mimo její překážky; samotný AABB nestačí. Manuální umístění mimo použitelnou plochu má viditelnou validační chybu, ne automatický přesun jiných sestav.

Přízemí, balkón a další části mají samostatné stabilní identifikátory a názvy, které lze uvést v přístupném popisu místa a filtrování. Stejné lokální číslo sedadla ve dvou sekcích není duplicita prodejní identity; výsledné zákaznické označení musí sekci rozlišit. Fyzické kolize se neposuzují mezi různými výškovými úrovněmi. Potvrzené rozhodnutí uživatele: celý prostor je jeden plánek bez přepínání pater nebo sekcí, v editoru i zákaznickém výběru. Přízemí, balkón, výklenky a další části jsou společně viditelné, prostorově oddělené a jasně pojmenované. Sekce jsou organizační metadata a pomůcka pro editaci, nikoli povinná navigace mezi samostatnými pohledy. Balkón lze schematicky umístit vedle nebo nad přízemí s označením a naznačením schodiště; nejde o vzájemně překryté průhledné vrstvy. Všechny části sdílejí jeden world souřadný systém a kameru. Zobrazit vše zahrnuje všechny viditelné části, zoom na výběr/oblast je pouze pohyb stejné kamery. Žádné přepínání, které by skrylo nabídku míst v ostatních částech. Odlišení výškové úrovně zůstává metadatem pro označení a fyzické kolize.

Obecné typy nábytku, hranice oblastí a označení úrovní patří do veřejného balíčku. Festapp host vlastní jen produktová přiřazení a rezervace. Vlny 4-6 zahrnou jejich knihovnu, editaci a fitting; vlna 8 zákaznické označení a výběr. AC04 rozšířit o sál do L s překážkou a balkónem, AC10 o gaučovou sestavu a její kopii, AC23 o shodu nábytku a prostorových úrovní v obou rendererech. Společný výběr gauče je závazný, cenový model navazuje na existující produkty míst; následné změny objednávky dodržují pravidla jednotky a stávající storno/swap owner podle uzavřených pravidel níže. AC04 a AC23 musí ověřit společný přehled všech částí bez přepínání a bez překrytí míst.

### Ceny při práci s plánkem podle současné aplikace

**Potvrzené zadání uživatele:** zachovat existující logiku produktů/cen po stolech a jednotlivých místech. Nastavení ceny je dostupné během úprav plánku; nevynucovat nový samostatný krok „nejdřív rozmístění, potom ceny“.

Ověřený současný tok: `BlueprintGroupModel.product` je transientní skupinový default, nikoli uložená cena stolu. `GroupProductManagerDialog._pickProduct` umožňuje přiřadit produkt všem sedadlům skupiny nebo jednomu konkrétnímu sedadlu; `_recalculateState` zobrazuje jednotný versus smíšený stav. `_handleAddAvailable` přebírá produkt skupiny, případně prvního jejího místa a teprve potom první dostupný spot produkt. `SelectProductDialog` vybírá/vytváří/upravuje existující spot produkty přes `DbEshop.updateProduct`. Autorita ceny je produkt v `eshop.products` a vazba `eshop.spots.product`, ne geometrie ani skupinový JSON.

Nový inspector po výběru stolu nabídne kompaktní sekci Cena míst u stolu: při jednotném přiřazení název produktu a cenu za místo, při rozdílném stavu „Různé ceny“ a rozbalitelný seznam sedadel. Akce Nastavit pro celý stůl přiřadí vybraný produkt všem oprávněným místům, akce u konkrétního místa umožní výjimku. Nově přikliknutá místa dědí aktuální default stolu/skupiny podle stávajícího významu; pouhá geometrická změna nesmí znovu sjednotit již rozdílné produkty. Rozumný default neznamená neviditelné přepsání výjimek.

Výběr či vytvoření cenového produktu zůstává ve stejné produktové cestě a zachová současná price-wave, měnová, kapacitní a oprávňovací pravidla. Nepřidávat `table.price`, `seat.price` ani oddělený blueprint ceník. Stejný produkt může sdílet více stolů, každý stůl však může mít vlastní přiřazení. Změna ceny sdíleného produktu musí viditelně uvést dopad na další přiřazená místa/stoly; změna pouze vybraného stolu se řeší přiřazením jiného existujícího nebo explicitně vytvořeného produktu, nikoli nečekanou úpravou sdíleného produktu.

Zachovat oddělení životních cyklů: přiřazení produktu místům je součást draftu a `seatChanges`, úprava samotného produktového katalogu používá existující produktový command s vlastním explicitním Uložit. Cancel plánku nevrací již potvrzenou změnu sdíleného produktu. UI to musí sdělit před potvrzením katalogové změny; neslibovat její undo přes historii geometrie. Po úspěchu aktualizovat host product snapshot podle ID, aby všechny reference v inspectoru ukazovaly aktuální cenu, aniž se zahodí rozpracovaný layout. Přesný command route znovu trasovat při implementaci z `DbEshop.updateProduct`, nevolat interní SQL přímo.

U držených/prodaných míst zachovat ochranu přiřazení produktu a historické objednávkové ceny. Převzetí skupinového produktu pro celý stůl nesmí jen přeskočit zakázané řádky a nepravdivě hlásit jednotnou cenu: nejprve ukázat blokery, při explicitní akci pro celý stůl operaci zamítnout jako celek. Případná akce Pouze volná místa je zvlášť označená s náhledem počtu změn a ponechaných výjimek.

Gauč dál sestává ze dvou existujících cenově přiřazených míst vybíraných společně; dosavadní produktová autorita se kvůli badge `×2` nemění. Nenavrhovat bez dalšího požadavku samostatný cenový produkt za nábytek. Detail zobrazuje zákazníkovi výslednou částku společného výběru podle existujícího nacenění, nikoli novou cenu uloženou na gauči.

Vlny 7-8 zachovají pricing command hranice a dodají host inspector slot; balíček dál nezná Festapp produkty. AC01 rozšířit o dva stoly s různými produkty, výjimku jednoho sedadla a dědění nového místa. AC15/AC18 ověří blokovanou změnu přiřazení a cizí produkt; AC21 ověří správnou cenu obou míst gauče a více sedadel se stejným produktem. Samostatný test musí odlišit Cancel rozpracovaného přiřazení od již potvrzeného product commandu a ověřit dopad změny sdíleného produktu.

### Přesun k jinému stolu a zachování existujících výměn

**Potvrzené pravidlo uživatele:** neprodané sedadlo při přiřazení k jinému stolu přebírá produkt a cenu cílového stolu. Uživatel výslovně dovoluje zlepšit architektonické slabiny existujícího řešení; zachovat jeho obchodní význam, nikoli kopírovat chyby nebo vytvořit paralelní finanční engine.

Rozlišit tři operace:

| Operace | Geometrie / identita | Produkt a cena / objednávka |
|---|---|---|
| Posun židle nebo celého stolu po plátně | Stejná node/spot ID a stejné příslušnosti. | Beze změny. Pouhé překřížení obrysu jiného stolu nepřepisuje produkt. |
| Připojení volného sedadla k jinému stolu | Přepsat příslušnost/anchor, zachovat node/spot ID. | Převzít default produktu cílového stolu; geometrie i přiřazení jsou jeden undoable draft command a jeden atomický save. |
| Přesazení zákazníka nebo výměna objednaných míst | Fyzická místa a jejich produkty zůstávají; mění se obsazení míst. | Použít stávající receipted swap/replace owner a jeho přepočet objednávek, nikoli `seatChanges` editoru. |

Při přetažení volného sedadla na platnou kotvu jiného stolu ghost ukáže cíl a novou cenu před dropem. Drop do potvrzeného cíle provede jednotnou změnu; Escape a undo obnoví původní vazbu i produkt. Přesun bez připojení zůstává čistě geometrický. Aktivně držené nebo objednané místo nelze tímto draft commandem přecenit; nabídnout existující explicitní správu přesazení, ne obejít ochranu layout save.

U cílového stolu s individuálními cenovými výjimkami se dědí jeho explicitní skupinový default, nikoli cena náhodně prvního sedadla. Současný `BlueprintGroupModel.product` je pouze transientní, proto nový host model potřebuje perzistentní default. Přidat host tabulku `eshop.blueprint_group_products(blueprint BIGINT, group_node UUID, product BIGINT)`, PK `(blueprint,group_node)`, FK na blueprint a produkt. Scope a existenci group node ověřuje stejný save owner, direct klientský write zakázat. Tabulka neobsahuje cenu; odkazuje na původní produkty. Při legacy převodu odvodit default z původního platného group produktu, pokud je dohledatelný, jinak pouze z jednotné množiny přiřazení. Smíšená skupina bez známého defaultu se explicitně označí; prvním připojením uživatel jednou vybere default, systém si jej pak pamatuje. Nevymýšlet historickou hodnotu, která se neukládala.

**Ověřená současná výměna:** `BlueprintTab._handleSwapSeats` -> potvrzení -> `_performSwap` -> `DbTickets.swapSpotTickets` -> `SupabaseTicketCommands.swapSpots` -> `swap_spot_tickets_client_sync_v1` -> `swap_spot_tickets_internal_v1`. Poslední owner mění `spots.order_product_ticket`, ponechá `spots.product` a přes `_swap_spots_update_ticket` upravuje produktový snapshot, součet objednávky a `payment_info.amount`. `replace_blueprint_order_client_sync_v1` už drží přípravu storna a vytvoření nové objednávky v subtransakci s receipt/replay. Tuto existující transakční hranici znovupoužít; interní `confirm_blueprint_order_change_internal_v1` není mrtvý kód k odstranění.

**Konkrétní zpevnění, která patří do vln 7-8:**

- `_performSwap` dnes přehodí lokální obsazení před awaited requestem a na tomto místě nemá obnovu snapshotu při chybě. Nový host controller drží transakční pending snapshot, potvrdí až serverovou response a při chybě obnoví obě místa; nenačítá celý layout přes rozpracovaný draft. Generic balíček může mít pending animaci, nevlastní finanční změny.
- Prohlédnutý swap wrapper/interní owner čte místa před explicitním spot row lockem. Doplnit a dvousession testem doložit stabilní zámky míst a dotčených orders/payment info ve stejném pořadí jako ostatní order mutations. Existující receipt serializuje retry stejného příkazu, není důkazem ochrany proti dvěma odlišným příkazům.
- `_swap_spots_generate_product_json` čte `products.price`; při integraci sladit účinnou cílovou cenu, price waves, dostupnost, měnu a zákaz změny nemutovatelných tickets s již existující cenovou/order autoritou. Nevytvářet novou lokální kalkulaci doplatku. Neshodné měny odmítnout před zápisem, pokud je dosavadní owner výslovně nepodporuje.
- Unit výběru gauče musí zůstat nedělitelná i při přesazení. Před source změnou určit kompatibilní swap rozhraní pro množiny; dvoumístný gauč proti jedné židli nelze vyřešit přesunutím poloviny páru. Podporované párové změny provést jednou transakcí nad kompletními jednotkami, ostatní odmítnout s důvodem a odkázat na explicitní replace workflow. Nedělat z toho obecné automatické storno bez potvrzení.
- Zachovat existující audit/history, receipts a sync publication. Testovat dvě místa téže objednávky i různých objednávek, přesazení na volné místo, různé ceny, refund/doplatek stav, hold konflikt a failure po první dílčí změně. Následné odeslání zákaznické komunikace ponechat existujícímu povolenému workflow, bez nového automatického email produceru.

AC01 rozšířit o převzetí produktu po přesunu mezi dvěma stoly a přesné undo; AC15/AC17 o swap-versus-hold/save a souběžné swapy; AC18 o rollback celé finanční operace, cizí scope, nemutovatelný ticket a měnu; AC21 o aktuální cenu cílového místa. Ve vlně 9 přidat default mapu stolu do copy/migration product remapping. Opravený swap owner zůstane jedinou aktivní obchodní implementací, ne `swap_v2` vedle původního.

### Gauč jako nedělitelná jednotka výběru

Jednotka výběru (`selectionUnit`) je odlišná od prostorové skupiny a produktové skupiny. Pro dvoumístný gauč obsahuje dva node IDs. Obecný balíček umí rozšířit uživatelský výběr na celou jednotku a zobrazit společný hover/selected/pending/error stav; Festapp mapuje oba nodes na skutečné spots. Knihovní předvolba gauče obsahuje tuto obecnou vztahovou informaci, nikdy spot/product IDs. Rozpojení nábytku v editoru nesmí tiše zrušit pravidlo společného výběru již uloženého páru.

Pravidlo není realizované dvěma nezávislými `select_spot` voláními. Jeden interní rezervační owner odvodí ze vstupního spot ID kompletní jednotku ze serverem uložených bindings, zamkne všechny její spot řádky v pořadí ID, ověří dostupnost i produktová omezení obou a teprve potom provede společný hold/release. Nová explicitní veřejná hranice `select_blueprint_unit(form_key, secret_id, spot_id, selecting)` deleguje na tento owner a vrací dotčená IDs/stavy. Původní `select_spot` zachová svoji signaturu a odpověď pro jednotlivé místo a deleguje na stejný owner; pro multi-seat jednotku vrátí upgrade-required bez změny. Nejde o druhý engine ani změnu released response shape, která by starému klientovi tiše potvrdila polovinu gauče. Nový host picker používá jednotkové API i pro jednotku velikosti 1. Všechna místa mají stejný secret a společnou expiraci; opakovaný select neprodlužuje původní hold. Chyba libovolného místa vrátí celý pár beze změny. Klient nesmí rozdělit jednotku ani podvrženým seznamem IDs. Samostatná sedadla mají nadále jednotku velikosti 1; nezavádět druhý paralelní rezervační engine.

Existující save owner uloží členství jednotky se stabilním group ID do bindings jako odvozenou validovanou projekci dokumentového vztahu. Člen smí patřit nejvýše jedné jednotce a všichni členové patří témuž blueprintu. Změna členství aktivně držené nebo prodané jednotky je zamítnutá. Podoba storage sloupce a document `selectionUnits` se přidá do schématu vlny 1 a SQL vlny 7; žádná odlišná trvalá klientská mapa.

Response vrací dotčené IDs a společný výsledný stav; Flutter/JS picker provede jednu optimistic transakci pro celý pár a společný rollback při chybě. Kapacita košíku a limit vstupenek musí počítat dvě místa. Zbývá-li limit pouze na jedno, celý pár odmítnout s vysvětlením před i na serverové hranici. Checkout/order finalizer odmítne neúplnou jednotku a změny objednávky nesmějí omylem přidělit její polovinu jinému zákazníkovi. Následné storno/výměna zachovává celistvost jednotky podle uzavřených pravidel níže a znovupoužije současné doménové ownery; UI nesmí samo stornovat další vstupenku bez zobrazeného potvrzení.

Rozšířit vlnu 7 také o rezervační owner a checkout validaci, vlnu 8 o group result adaptér obou pickerů. AC10 ověří zachování jednotky při kopírování předvolby, AC17 souběžný výběr téhož páru dvěma kupujícími a selhání druhého místa bez částečného holdu, AC21 společný select/release/rollback a limit 1 versus pár 2 v obou klientech. Před aktivací párů ověřit, že starší klient nemůže zpracovat novou group response jako potvrzení pouze poloviny; upgrade guard nebo kompatibilní nasazení je součástí vlny 11.

### Počet míst na společném objektu a srozumitelnost výběru

**Požadavek uživatele:** objekt reprezentující více míst má přímo v plánku viditelný násobek počtu, například `×2` nebo `×5`. Platí pro gauč a společné oblasti, například stání. Význam počtu musí zůstat stejný v editoru, náhledu i zákaznickém pickeru.

Návrh byl konzultován přes skill `ui-ux-pro-max`, cílené hledání `badge count accessible label` v doméně UX. Relevantní pravidla: kompaktní count badge držet na jednom řádku, mít srozumitelný přístupný název, změny počtu oznamovat v kontextu bez přesunu focusu. Konkrétní podoba badge níže je produktový návrh nad těmito pravidly, nikoli hotový vzor nalezený ve skillu.

| Objekt/stav | V plánku | Detail po kliknutí/dotyku nebo focusu |
|---|---|---|
| Dvoumístný gauč, povinný společný výběr | Jeden rozeznatelný gauč s kompaktním badge `×2`. | „Gauč - 2 místa, vybírají se společně“; stav výběru a cena podle následně dohodnutého cenového kontraktu. |
| Společný objekt s pěti místy | Badge `×5` představuje celkový počet míst reprezentovaných objektem. | Název, kapacita a samostatně aktuální dostupnost, například „Volná 3 z 5 míst“. Návštěvník volí požadovaný počet od 1 do aktuálně dostupné kapacity, nemusí koupit celou oblast. |
| Vybraný gauč | Badge zůstává `×2`, celý objekt má společný selected/pending stav. | Souhrn explicitně uvádí „Vybrána 2 místa“. Barva není jediný signál. |

Badge označuje počet míst zastoupených objektem, ne cenu, počet zbývajících míst ani proměnlivý obsah košíku. Dostupnost a zvolený počet se zobrazují odděleně a slovně. U běžného stolu s jednotlivě vykreslenými sedadly nesmí automaticky vzniknout badge, který by naznačoval povinný společný nákup celého stolu. U gauče musí být i bez otevření detailu patrný společný rozsah výběru: hover/focus zvýrazní celý objekt a obě místa, klik není nabídka výběru poloviny.

Umístění badge volí společný scene/presentation kontrakt podle obrysu objektu, nesmí zakrýt číslo místa nebo překrýt sousední aktivní objekt. Při příliš malém zoomu použít společné LOD a informaci vždy zpřístupnit po focusu/tapu v detailu, nikoli v hover-only tooltipu. Stejná pravidla platí pro Flutter/JS, text badge používá společné glyph zdroje a číselné formátování. Badge není druhé tlačítko ani samostatný tab stop.

Dostupnost lze měnit serverovým patchem bez záměny celkové kapacity badge. Jedna změna výběru oznamuje jeden souhrnný stav, například „Vybrán gauč, 2 místa“, nikoli dvě izolovaná čísla nebo samostatný live region na každém objektu. Když server pár odmítne, oba selected stavy i souhrn se vrátí společně. V editoru mění počet míst vlastnost objektu, ale pravidlo pro změnu již držené/prodané jednotky zůstává chráněné.

Potvrzené pravidlo uživatele: nábytek typu gauč tvoří nedělitelnou sestavu a vybírají se všechna její místa; kapacitní oblast typu stání dovoluje libovolný požadovaný počet do aktuální dostupné kapacity. Stání `×5` tedy umožní vybrat například 2 místa a další 3 ponechat ostatním. Nejde o individuálně číslovaná místa v nákresu. Klik otevře kompaktní detail se stepperem počtu a potvrzením; cena a počet vybraných míst jsou zřetelné před potvrzením. Odebrání/snížení počtu nemění celkovou kapacitu badge. Typ objektu nastaví rozumné výchozí pravidlo automaticky: gauč společný výběr, stání volitelný počet. Pořadatel to nemusí při každém vložení nastavovat. Do modelu přidat explicitní rozdíl `selectionUnit` a `capacityArea`, nikoli používat velikost badge jako obchodní pravidlo. Vlny 7-8 použijí stávající inventory/order autoritu podle doložené hranice v následující sekci. Výběr počtu je pro stání návrh košíku; sám nezakládá dočasný hold. Kapacita se atomicky získá při finálním vytvoření objednávky, stejně jako u nynějších neadresných produktů. UI nesmí před tím hlásit „rezervováno“. Nezakládat nový plošný hold engine ani druhý inventory ledger. Server vynutí poslední dostupnou kapacitu i při souběžném potvrzení; při nedostatku vrátí konkrétní stav a klient zachová rozpracovaný košík pro úpravu počtu. AC17 doplnit o dva souběžné nákupy poslední kapacity stání bez přeprodeje; AC21 o výběr 2 z 5 a společný výběr gauče bez quantity volby. Vlny 2/4/10 zahrnou společný badge renderer, inspector a přístupnost; AC10/AC21/AC22/AC23 ověří význam počtu, dostupnost, atomický pár, dotyk/klávesnici a paritu badge při zoomu.

### Řady, autobusy a vlaky

| Scénář | Nastavení a výsledné editovatelné objekty |
|---|---|
| Sál s řadami | Počet řad a sedadel, rozestup, bloky s uličkou, natočení, přímé či obloukové řady, vynechané pozice, pódium. |
| Autobus | Opakovaná sestava 2+2 nebo 2+1, šířka uličky, počet řad, zadní lavice, dveře, řidič a neprodejné plochy. Směr jízdy je grafický prvek. |
| Vlak | Vůz jako sekce, otevřené uspořádání nebo opakované kupé, volitelný stůl mezi protilehlými místy, předsíň a dveře. Čísla mohou být vlastní, nikoli jen sekvenční. |
| Volný plánek | Samostatná sedadla, stoly, schody, bar, pódium, WC, východy, vozíčkářské místo a popisky; vše s přesnými rozměry a rotací. |

Generátor je deterministická lokální funkce s náhledem. Po potvrzení vznikají běžné objekty a vazby, ne neprůhledný obrázek. Sestavu lze znovu parametricky upravit, dokud uživatel explicitně nezvolí rozpojení; ruční výjimky mají stabilní ID a explicitní override. Vůz, kupé, řada a stůl jsou prostorové kontejnery, nikoli nové cenové skupiny.

Číslování má samostatný náhled: prefix, začátek, krok, směr, lichá/sudá, pokračování mezi bloky a explicitní seznam pro vlak. Číslo místa, označení řady a stolu se nesměšují s DB ID. Potvrdit jen změněné názvy; kolize ve stejné sekci jsou viditelná chyba. U již prodaných nebo držených míst jsou změny zákaznického označení blokované, aby se nerozešly dříve vystavené vstupenky.

### Co přesně znamená inteligentní fitting

- **Přichytávání:** hrany, středy, stejné mezery, osy řad a kotvy stolů; volitelná mřížka. Výchozí magnet 5 obrazových px, uvolnění 8 px; přepočet přes zoom, priorita explicitní kotva > zarovnání > rozestupy > mřížka. Stabilní tie-break podle ID, žádné přeskakování mezi shodnými kandidáty. Alt dočasně vypíná magnet.
- **Umístění:** ghost objekt, orientace a vodítka ještě před klikem. Přidané sedadlo používá aktuální rozměr, styl a vybraný produkt. Bez produktu může existovat v lokálním draftu, ale save musí nabídnout přiřazení a vyžadovat ho pro každé prodejné místo.
- **Fit sestavy:** výslovná akce Vejít do oblasti vypočítá kapacitu ze skutečného obrysu sedadel, rozestupů, okrajů a uliček. Nabídne varianty počtu/rozestupu; neřeší to škálováním lidí a židlí. Uzamčené objekty zůstávají na místě; neproveditelný návrh má vysvětlení.
- **Kolize:** rozlišit fyzické objekty, kontejnery a dekorace. Překryv dekorace s objektem může být legální; překryv fyzických sedadel, stolu a vyhrazené uličky je chyba. Použít broad phase index a přesný test transformovaných obrysů. Žádný tichý globální přesun dalších objektů.
- **Fit kamery:** samostatné Zobrazit vše / Výběr / Sekci. Ohraničení zahrnuje otočené objekty a popisky, používá jednotné contain měřítko a padding; nikdy deformaci os nebo `slice` ořez. Po běžném editu se kamera sama neresetuje.

### Animace a úplné stavy

| Událost | Chování |
|---|---|
| Pohyb při tažení | Objekt bez časového zpoždění pod pointerem; animace nesmí měnit hit test. Vodítko a ghost reagují v témže snímku. |
| Vložení/potvrzení kotvy | Jemné zvýraznění/scale 0.96 -> 1 během 160 ms; geometrie je okamžitě finální. |
| Přepočet připojených sedadel | Přechod 180-220 ms mezi starou a novou transformací podle stabilních ID; místa mimo upravovanou sestavu se nehýbou. |
| Fit kamery | 240 ms ease-out kolem zvoleného cíle; nové gesto přechod okamžitě přeruší. |
| Výběr místa zákazníkem | Okamžitý lokální indikátor, pending při RPC, při zamítnutí návrat za 160 ms a srozumitelná zpráva. Pending neznamená potvrzenou rezervaci. |

Motion tokeny a easing jsou společná data. Hromadná změna animuje jen viditelné objekty, bez mnohasekundového staggeru. Reduced motion vypíná prostorové přechody a ponechá stavovou odezvu. Obě platformy mají shodné začátky/konce i vzorky mezistavů; nezávislé výchozí Flutter/CSS pružiny se nepoužívají.

Povinné stavy: načítání, prázdný plán, nedostupný podklad, offline draft, ztráta oprávnění, neplatná data, nepodporovaná verze, nedostupný produkt, konflikt uložení a obsazené místo. Save failure nechá draft i kameru beze změny. Odchod s neuloženými změnami používá společnou ochranu draftu. Nabídnout export/obnovu lokálního dokumentu bez tajných rezervačních tokenů; žádný tichý autosave do produkčního plánku.

## Kanonická architektura

### Jeden geometrický zdroj pro Flutter i JS

**Rozhodnutí D1:** celý obecný editor je od začátku veřejně vydatelná knihovna v repozitáři `venue_seat_picker`, nikoli Festapp obrazovka později vytažená do balíčku. Obsahuje dokument, geometrii, interakční controller, nástroje, generátory, obecný inspector/knihovnu a Flutter viewer/picker/editor. V témže repozitáři vznikne čistý Dart subpackage `packages/venue_layout_core` bez Flutteru, Supabase, DOM a `dart:ui`. Flutter wrapper na něm závisí; browser JS distribuce se kompiluje z totožného core. Balíček nikdy neimportuje `fstapp`, `festapp_core`, ticket modely, RightsService, interní dialogy ani storage Festapp. Konkrétní veřejná rozhraní a release gates jsou specifikované níže.

Navrhované vlastnictví: `packages/venue_layout_core/lib/src/{document,geometry,commands,generators,scene,motion}/`, `lib/src/layout_editor/` pro Flutter UI a `web/` pro JS bridge, typings a distribuci. Festapp drží jen host adaptéry, obchodní inspector sekce a napojení produkčních služeb. Čisté core má samostatný public barrel; JS entry nesmí tranzitivně importovat Flutter.
**První technická brána:** ověřit `dart compile js` pro čisté jádro s explicitně exportovaným verzovaným API (`decode/validate/compileScene/hitTest/interpolate`). Web adaptér použije samostatný browser entry point s JS export wrapperem a registrací do jmenného prostoru `VenueLayoutKernel`; nepoužije Flutter barrel import. Podporu interop exportů z lokálního SDK je nutné ověřit; export a bootstrap prokázat malým lokálním buildem. Nemá vzniknout závislost web klienta na celé Flutter aplikaci. Nezavádět ručně přepsaný JS layout engine jako fallback. Pokud dostupný SDK export neumí nebo bootstrap nesplní limity, zastavit navazující implementaci a aktualizovat tento architektonický bod s důkazem.

Build balíčku publikuje kernel a scene assety se stejným source SHA, verzí kontraktu a hashem; publikuje zde znamená vytvoření distribučního artefaktu, nikoli automatický upload do registru. Festapp přebírá konkrétní immutable distribuci, kontroluje její hash vůči pinu Flutter balíčku a bundluje ji do Vite. Žádné runtime CDN nebo kompilace v prohlížeči. `pubspec` pin a web artifact se mění v jednom koherentním commitu. Build kontrola musí odhalit jejich rozchod; generované soubory se ručně needitují.

**Rozhodnutí D2:** jádro vrací display list s číselnými transformacemi, cestami, fill/stroke, pořadím vrstev, clippingem a hit obrysem. Flutter vykreslí seznam přes CustomPainter, JS přes SVG. JS DOM nesmí dopočítávat velikost sedadla nebo textu přes CSS box model. Symboly sedadel, stolů, stavové ikony a fontové obrysy jsou jedny verzované assety. Pro popisky plánku použít společné glyph advances a obrysy z vybraného fontu a řezu společného připnutého katalogu; žádný nativní text layout pro geometrii uvnitř plánku. Běžné panely používají normální přístupný text.

To dává identický obsah a umístění i textové zalomení. Rastrový antialiasing různých OS/GPU nemusí být bitově identický; toto je výslovný technický limit, nikoli povolení měnit vizuální návrh. Testovat přesnou normalizovanou scénu a téměř shodné screenshoty při stejném viewportu/DPR. Pokud by zadání vyžadovalo doslova stejné pixely mezi všemi zařízeními, musel by se změnit požadavek na renderovací backend; SVG/Flutter to nezaručí.

**Rozhodnutí D3:** z ticket editoru převzít ověřené principy a konkrétní algoritmické části až po oddělení ticket typů. Balíček neimportuje `TicketTemplate`, ticket controller ani PDF služby. Festapp fontový adaptér naopak záměrně znovupoužívá stejný katalog, picker a font resource pipeline jako ticket editor. Neutrální font resource/cache kód lze vyčlenit jednou do `lib/components/fonts/` a přesměrovat na něj oba editory bez změny ticket chování. Blueprint rotované objekty a topologie potřebují vlastní doménovou vrstvu. Neprovádět při tom celkový refaktor fungujícího ticket editoru; jeho UX zůstává referencí pro gesta, snapping a save.

### Dokument, identity a vlastnictví dat

Nová kolonka `eshop.blueprints.layout JSONB` bude jediný zdroj geometrie. Přidat `layout_revision BIGINT NOT NULL DEFAULT 0`. První nový objektový formát má `schemaVersion: 1`; název iniciativy „v2“ není pokračování nesouvisejícího `VenueSeatDocument` schema 1. Nový typ pojmenovat `VenueLayoutDocument`, aby nešlo oba dokumenty zaměnit.

| Část kontraktu | Obsah a invariant |
|---|---|
| Dokument | `schemaVersion`, `canvas` s viewBox, `sections`, `nodes`, `symbolSetVersion` pro symboly balíčku, `background` a dokumentová `presets` knihovna. Canvas obsahuje schematické rozměry a barvu. Pevný top-left souřadný systém, world jednotky nezávislé na viewportu; bez fyzické kalibrace v tomto zadání. Neprezentovat rozměry jako reálné metry. |
| Node | Stabilní UUID `nodeId`, `kind`, `parentId`, lokální `x/y/rotation`, rozměry, explicitní pořadí vrstvy, zamčení a přístupný název. Bez cyklů a duplicitních ID, jen konečná čísla a povolené typy. |
| Sedadlo | `kind: seat`, geometrie a volitelná typová značka. Obchodní identita přes vazbu `nodeId -> spotId`; produkt, prodejní označení a stav vlastní SQL, nikoli scene JSON. |
| Text a tvar | Text ukládá obsah, font ID/řez, box, velikost, barvu, zarovnání a řádkování; tvar svůj typ/vrcholy, výplň, obrys a opacity. Jen podporované hodnoty, žádné HTML/CSS či spustitelný obsah. |
| Podklad | Asset reference a hash, normalizovaný crop zdroje, explicitní world posun, rotace a jednotné měřítko, opacity a clipping plátnem. Bez obrazových bajtů a bez implikovaného přemístění sedadel. |
| Předvolby | Verzovaný dokumentový fragment se všemi referencemi na fonty/assety, bez spot ID a soukromých obchodních dat. Rozbalení generuje nové node IDs a přepisuje vnitřní parent vazby. |
| Vazby | Kotva strany/úhlu stolu, řada/blok/kupé, parametry generátoru a explicitní ruční override. Sedadla jsou explicitní stabilní nodes; generátor je pouze command, ne další runtime zdroj geometrie. |
| Sekce | ID, název, použitelný obrys a pořadí; odlišení prostorové části a výškové úrovně. Více vozů/oddílů, přízemí/balkón a fit/filtrování; bez současného rozšiřování obchodního modelu na více plánků jedné akce. |
| Session | Kamera, výběr, hover, pending, grid, guides a undo se neukládají do veřejného dokumentu. |

**Rozhodnutí D4:** oddělit `layout` od obchodních vazeb pomocí nové tabulky `eshop.blueprint_seat_bindings(blueprint, node_id UUID, spot BIGINT)`, PK `(blueprint,node_id)`, unikátní `spot`, FK na blueprint a spot. Tabulka nemá vlastní cenu ani stav. Vazbu a validaci příslušnosti spravuje výhradně save/copy hranice; přímé klientské zápisy zakázat. Jedno `eshop.spots.id` se při přesunu nikdy nevyměňuje. Pro neprodejné objekty vazba neexistuje. Cenová skupina zůstává ve stávajících produktech. Pouhá geometrie produkt nemění; explicitní připojení volného místa k jinému stolu přebírá jeho cenový default podle potvrzeného pravidla.

Save command nese `layout`, `expected_layout_revision` a explicitní `seatChanges` pro nové/změněné/smazané vazby a metadata. Nová sedadla mají `nodeId`, server vrací jejich `spotId`. Cena ani objednávka nejsou přepisovatelné přes document. Původní `blueprints.data/title` zachovat, pokud vlastní jiná metadata; neodkládat do nich druhou kopii layoutu.

Souřadnice kvantizovat na 1/1024 world jednotky, úhly na 1/1024 stupně a kanonizovat pořadí serializace. Matice mají pevně definované pořadí translate/rotate a pivot. Transformace potomků, obrysy a inverze hit testu vznikají ve stejném jádře. Materiální změna rodiče aktualizuje odvozené pozice potomků bez změny jejich ID. Neomezeně vnořené škálování a záporné transformační měřítko do první verze nezařazovat; dekorativní zrcadlení se materializuje do geometrie bez záporné scale matice; zjednoduší to obrysy a zachová velikosti sedadel.

### Save, rezervace a souběh

1. `update_blueprint_client_sync_v1` zůstává vstupním commandem s command ID a replay. Přidat kanonický SQL zdroj pod `database/functions/eshop/`; nespoléhat na ruční úpravu staré již aplikované migrace.
2. Odvodit organizaci z akce, ověřit oprávnění a příslušnost blueprintu, produktů, bindings a všech spot ID. Interní vlastník kontroluje scope také pro setup/copy caller; wrapper není jediná ochrana.
3. Zamknout blueprint a dotčené spot řádky ve stabilním pořadí, ověřit revision a aktuální hold/order stav. Sladit pořadí zámků s `select_spot` a finalizací objednávky při implementačním trasování, aby nevznikl deadlock. Kontrola ze snapshotu editoru nestačí.
4. Validovat celý dokument, reference, bounds, počet objektů, povolené assety a všechny seat changes před změnou dat. Klientská validace pomáhá UX, SQL je autorita obchodních pravidel a strukturálních invariantů. SQL znovu neimplementuje fitting.
5. Jedna transakce uloží layout/bindings/místa, zvýší revision a publikuje existující sync invalidaci. Doménové chyby musí rollbacknout všechny zápisy před vrácením rejected receipt. Přesný replay neprovádí operaci znovu a vrátí stejné mapování ID.
6. Na konflikt vrátit aktuální revision a strukturovaný důvod. UI drží lokální kopii, nabízí načtení uložené verze a export draftu. Žádný slepý force overwrite ani automatický merge topologie.

Geometrický přesun/rotace prodaného sedadla je povolen, protože nemění jeho identitu. Smazání, výměna produktu, odpojení obchodní vazby nebo přejmenování objednaného/používaného či aktivně drženého místa je zamítnuté. Pravidla se aplikují na potomky i při smazání celého stolu/vozu. Překopírování sestavy vždy vytváří nové node IDs a nová místa, nikdy nekopíruje objednávku, hold ani secret. Undo je pouze historie draftu; po úspěšném save se historie uzavře na nové baseline, nemůže obnovit starou databázovou identitu.

`get_blueprint` vrací veřejný layout a pouze bezpečné seat metadata/dostupnost podle formuláře. `get_blueprint_for_edit` přidává revision, editovací vazby a autorizovaná data. Žádný secret, skrytá poznámka ani zákaznické údaje ve veřejné scéně/exportu. Veřejná změna dostupnosti je patch podle `spotId`, nezpůsobuje nové generování geometrie. Stávající objednávkové RPC, limity výběru, optimistic rollback a price-wave omezení zůstávají autoritou.

### Podklady, výkon a přístupnost

- Nové vektorové prvky jsou omezený katalog primitives, nikoli libovolné SVG/HTML. Importovaný SVG projde allowlist sanitizací (bez scriptů, event handlerů, `foreignObject` a externích odkazů) a materializací podporovaných cest. Nepodporovaný starý podklad převést před cutoverem na jeden schválený statický asset se stejným viewBox; neodhadovat měřítko při renderu. Raster podklady pouze přes povolenou asset infrastrukturu.
- Řídký prostorový index a viewport culling; stavové patche mění jen dotčené nodes. Při malém zoomu lze skrýt popisky, ale podle stejných LOD pravidel na obou platformách. Žádná alokace `rows * columns`, žádný request během drag/snap/undo.
- Produktové akceptační cíle, které je nutné změřit: fixture 500, 5 000 a 20 000 sedadel; na zaznamenaném desktopu p95 frame <= 16.7 ms pro 5 000, na reprezentativním telefonu <= 33 ms. Pro 20 000 změřit limit a zvolit společné LOD. První použitelný náhled 5 000 míst <= 2 s na lokálně servírovaných assetech; komprimovaný kernel se základními symboly <= 500 KiB bez volitelných podkladů a fontových balíků. Celý společný katalog zůstává dostupný; fontové zdroje načítat podle použitých font ID, měřit zvlášť velikost/cold load a zabránit zobrazení finálního textu s náhradním fontem. Jsou to cíle, ne naměřená tvrzení.
- Barevný stav doplnit ikonou/textem. Keyboard navigace používá prostorové sousedství a roving focus, nikoli 20 000 tab stopů. SVG/popisky mají paralelní přístupný seznam míst a detail výběru; Flutter odpovídající Semantics. Dotykové ovladače mají doporučených 44-48 logických px, hustá místa nabídnou zoom/detail místo překrývajících se nejednoznačných hit zón.

## Předpoklady a rozhodovací brány

- **A1:** Samostatně vydatelný `venue_seat_picker` je výslovný požadavek uživatele a vlastní obecnou implementaci. Budoucí implementace zahrnuje i jeho zdrojový repozitář; před editací přečíst jeho instructions a stav checkoutu. Toto zadání zůstává plánovací, neautorizuje publikaci balíčku.
- **A2:** Existující plánky lze převést zachováním spot ID a registrovaného podkladu. Inventura při migraci musí vypsat rozměry, nestandardní objekty, background viewBox, duplikované ID a chybějící produkty. Výjimky se explicitně opraví nebo blokují aktivaci daného plánku, nesmí se tiše zahodit.
- **A3:** První verze nepovolí měnit zákaznické označení prodaných míst. Taková změna nesmí být automatický důsledek layout editu; explicitní přesazení řeší stávající swap/replace owner a jeho zákaznické označení podle cílového místa.
- **A4:** Existující obchodní skupiny a price-wave pravidla stačí i pro dopravní uspořádání. Ověřit fixtures vlak/autobus s více cenami; při požadavku na úsekové jízdné vyjmout tuto novou doménu do samostatného projektu.
- Žádný blocker pro tento plán. Brána exportu jádra, skutečný inventář plánků a měření výkonu jsou povinné výstupy implementace před aktivací.

## Veřejný balíček je výchozí produkt

### Hranice vlastnictví

| Vlastník | Veřejná odpovědnost | Co nepatří dovnitř |
|---|---|---|
| `venue_layout_core` | Verze dokumentu, přesná geometrie, command reducer, constraints, generátory, validace, prostorový index, display list, hit test a motion sampling. | Flutter widgety, font katalog Festapp, HTTP, přihlašování, obchodní produkty a SQL. |
| Flutter `venue_seat_picker` | Obecný editor, paleta, inspector, ovládání klávesnicí/dotykem, painter, Semantics, viewer a async picker. Přijímá theme, lokalizaci a host sloty. | `AppDialog` import Festapp, české produkční texty natvrdo, pevné URL, konkrétní tenant nebo povinný backend. |
| JS distribuce téhož repozitáře | Stejné core a vykreslení scény, TypeScript declarations, mount/update/dispose vieweru/pickeru, DOM přístupnost. | Přepis algoritmů v JS, kopie stavové logiky eshopu, závislost na běhu Flutter aplikace. |
| Festapp Flutter adaptér | Katalog/picker fontů, image upload, auth, produkty, metadata míst, save, konflikty, odchod s draftem a správa objednávek. | Vlastní výpočet umístění, fitting, rotace, druhý obecný editor. |
| Festapp web adaptér | `get_blueprint`, patch dostupnosti, výběr přes `select_spot`, limity košíku, tooltip a asset/font provider. | Vlastní rozměry symbolů, CSS font layout uvnitř scény, odvozování obsazenosti z produktu. |
| SQL | Scope, produkty, ID míst, verze, vazby, rezervace, atomita a existující sync publication. | Kopie geometrického fittingu nebo další stavová tabulka objednávek. |

Veřejná API používat například takto; jde o cílový kontrakt, nikoli tvrzení o existujících symbolech:

```text
VenueLayoutDocument.fromJson(json) -> document | UnsupportedSchema | InvalidDocument
VenueLayoutController(document, resources, constraints)
  .dispatch(LayoutCommand) -> CommandResult(document, changes, issues)
  .beginGesture / updateGesture / commitGesture / cancelGesture
  .undo / redo / select / setViewport
VenueLayoutEditor(controller, strings, theme, fontControlBuilder?, inspectorBuilder?)
VenueLayoutViewer(document, resources, seatPresentation, viewport)
VenueLayoutPicker(..., onSelectionRequested: Future<SelectionResult>)
LayoutFontProvider.catalog / resolve(fontId) -> FontResource
LayoutAssetProvider.resolve(assetRef) -> AssetResource
LayoutConstraintProvider.evaluate(changeSet) -> allowed | reasonByNode
```

`FontResource` má ID, hash, family, metriky a glyph obrysy, volitelně bytes pro editorový overlay. Katalog je předaný `FontEntry[]`, balíček ho nevytváří. Resource provider řeší I/O, core pracuje jen s již dodanými zdroji. Async resolve vrátí nový resource snapshot a zneplatní jen příslušný text/thumbnail, ne celý dokument.

`seatPresentation` je mapa `nodeId -> {label, status, selected, pending, accessibilityLabel}` a callbacky pro business detail. Spot/product ID nepotřebuje core znát. Generic picker má async úspěch/zamítnutí/cancel a ochranu opakovaného tapu. Festapp provádí mapování přes bindings; cenu a zákaznické údaje dodává host, nikoli uložená předvolba.

Host může dodat widget font pickeru i podoby dialogu. Výchozí standalone editor funguje s obecným pickerem a bez Festapp shellu; ve Festapp se přímo vloží existující `FontFamilyPicker`. Obě cesty čtou hostem dodaný katalog. Host inspector rozšiřuje vlastnosti o produkt, nevyměňuje základní inspector ani command reducer.

### Samostatné použití a release gate

Povinný balíčkový example otevře editor z JSON fixture a lokálních resource providerů, umí celý scénář stůl/text/tvar/podklad/save-to-file/reopen a nepotřebuje `.env`, Supabase ani Festapp checkout. Totéž platí pro JS viewer demo s importem dokumentu. Demo font je licenčně přenositelný fixture asset, nikoli druhý produkční font katalog.

Před označením balíčku za vydatelný musí existovat:

- Dokumentované public barrels bez dosažení do `src`, přehled podporovaných platforem, JSON schema, TypeScript declarations a příklady rozšíření host slots.
- LICENSE, licence všech přibalených ikon/font fixtures, CHANGELOG a migrační poznámky. Existující repozitář má MIT licenci (ověřeno v `LICENSE`); žádné proprietární fonty Festapp se nebalí do veřejné distribuce.
- Semver oddělený od verze dokumentu. Nový reader zachová unknown schema jako needitovatelná data; změna parseru nikdy automaticky nepřepíše cizí novější dokument. Staré grid public API zůstává omezenou externí boundary podle deletion ledgeru.
- Samostatný `fvm dart pub publish --dry-run` pro čisté core a `fvm flutter pub publish --dry-run` pro wrapper s budoucí verzí závislosti; JS `npm pack --dry-run` v `web/`. Při dry-run používá validační workspace dočasné path resolution, vydávaný manifest používá konkrétní publikovatelnou semver závislost, ne lokální cestu.
- Archive/package smoke test: rozbalit artefakt do čistého dočasného workspace, sestavit example a importovat JS přes deklarovaný entry point. Testovat právě distribuovaný obsah, ne pouze pracovní checkout.
- Package CI ověřuje public API contracts, JSON fixtures, build obou runtime a shodu source/version manifestu. Bez pevného build toolchainu nelze tvrdit reprodukovatelnou distribuci.

Publikace na pub.dev/npm a deployment dema jsou samostatné provozní akce. Příprava release artefaktů a dry-run patří do implementace. Pořadí skutečné publikace je core -> Flutter wrapper a JS artefakt -> aktualizace Festapp pinu, vždy z jednoho zaznamenaného source SHA.

## Implementovatelný kontrakt editoru

### Dokument, transformace a stav relace

Dokument má tři oddělené vrstvy: geometrické nodes, autorské vztahy (`attachments`/`generators`) a hostem vlastněná obchodní metadata mimo dokument. Příkaz materializuje výslednou geometrii do nodes. Renderer nespouští generátor; nevznikají dvě rozdílné pozice pro totéž místo. Autorská vazba slouží příštímu příkazu a podléhá validaci konzistence.

Konkrétní příklad minimálního objektového dokumentu:

```json
{
  "schemaVersion": 1,
  "symbolSetVersion": 1,
  "canvas": {"x": 0, "y": 0, "width": 2400, "height": 1600, "fill": "#FFFFFFFF"},
  "defaultTextStyle": {"fontId": "gf:7f3ec5073a282c666c9a0063573345841229caf50ed34d33017e20d441bf5caf", "size": 24, "color": "#222222FF"},
  "nodes": [
    {"id": "10000000-0000-4000-8000-000000000001", "kind": "table", "parentId": null,
     "transform": {"x": 600, "y": 500, "rotation": 0}, "width": 160, "height": 100,
     "shape": "roundedRect", "cornerRadius": 12, "z": 0, "locked": false},
    {"id": "10000000-0000-4000-8000-000000000002", "kind": "seat",
     "parentId": "10000000-0000-4000-8000-000000000001",
     "transform": {"x": 0, "y": -82, "rotation": 180}, "width": 40, "height": 40,
     "symbol": "chair", "z": 1, "locked": false}
  ],
  "attachments": [{"seatId": "10000000-0000-4000-8000-000000000002",
                   "targetId": "10000000-0000-4000-8000-000000000001",
                   "kind": "edge", "edge": "top", "t": 0.5, "gap": 12}],
  "generators": [], "sections": [], "selectionUnits": [], "background": null, "presets": []
}
```

Ukázka obsahuje pouze geometrii, není kompletní save request. Ukázka používá skutečné ID Roboto ze společného katalogu; nevytváří tím omezenou nabídku fontů. Prodejní označení sedadla dodá host. Textový node má vlastní `text`, společné `width/height`, stylové overrides a zalomení. Všude používat pole `id` z ukázky jako kanonický název; výraz `nodeId` v API/bindings označuje tutéž identitu, ne další JSON pole.

Každý node má pivot ve středu lokálního boxu. `x/y` je pozice tohoto středu v souřadnicích rodiče, kladný úhel je po směru hodin v systému y dolů. World matice je `parentWorld * translate(x,y) * rotate(angle)`. Body boxu jsou v rozsahu `[-w/2,w/2] × [-h/2,h/2]`. Zvolený editační pivot se při dokončení přepočítá do nové polohy středu; nevstupuje jako skrytý další transform dokumentu.

Při seskupení zachovat world matice, při rozpojení je materializovat do nových lokálních transformací. Žádný kontejner nesmí mít více rodičů nebo obsahovat sám sebe. Změna pořadí v array nesmí změnit geometrii; pořadí kreslení je explicitní `(renderBand,z,id)`. Public rendering má podklad -> dekorace/stoly -> sedadla -> popisky/stavy; host tooltip a editor handles jsou overlay. Opaque dekorace tak nemůže v zákaznickém výběru zakrýt sedadla. Uvnitř bandu lze pořadí měnit.

### Navržené pevné limity

Limity jsou cílový produktový kontrakt, nikoli dosud změřená kapacita. G0 změří největší fixture; změna limitu musí aktualizovat klient/core/SQL najednou a být uvedena v plánu. Různé nezávislé konstanty jsou zakázané; generovat je z jednoho package contract resource.

| Oblast | První cílový limit | Chování při překročení |
|---|---|---|
| Save payload | Existující strop 8 MiB včetně layout, bindings změn a presets. | Před save změřit UTF-8 payload, zobrazit velikost a problémové části; SQL odmítne bez zápisu. |
| Dokument | 25 000 nodes, z toho až 20 000 sedadel; depth 16. | Žádné vložení další sestavy přes limit, stávající dokument se nezkrátí. |
| Plátno | Každá strana 64-1 000 000 world units, default 2400 × 1600. | Neplatná změna má inline chybu; minima bounding geometry mohou být vyšší. |
| Text | 4 096 Unicode code points na node, font size 1-4096 world units, řádkování 0.8-3. | Zachovat editovaný text při chybě; nesekat obsah. |
| Polygon/polyline | 2-512 bodů; polygon alespoň 3, bez self-intersection. | Označit chybné hrany, nedokončit neplatný tvar. |
| Presets | 100 vlastních předvoleb, 2 000 nodes v jedné, stále platí 8 MiB celkem. | Odmítnout konkrétní import s důvodem. |
| Crop/opacity | Normalizovaný crop uvnitř [0,1], kladné rozměry; opacity [0,1]. | Neplatné hodnoty nezapsat, bez fallback transformace. |
| Historie | Nejvýše 100 příkazů nebo 32 MiB command dat; bitmapy nejsou v historii. | Odstranit nejstarší undo položky, nikdy aktuální draft. Stav omezené historie zobrazit v nápovědě. |

Přesnost je 1/1024 jednotky; ve fixture 20 000 sedadel musí reálná serializace včetně autorských metadat vejít do 8 MiB. Pokud ne, zredukovat redundantní defaulty/metadata nebo explicitně změnit gate pro payload, nikoli slibovat nefunkční kombinaci limitů. ID nesmějí být odvozené z indexu v listu. Barevný protokol je vždy `#RRGGBBAA`, převod do Flutter ARGB je host adaptér.

### Interakční automat a command transakce

Stav controlleru tvoří `document + resourceSnapshot + selection + viewport + tool + gesture`. Jeden aktivní pointer vlastní gesto; přepnutí nástroje nejprve commitne platný text nebo explicitně zruší neplatnou operaci. Žádný save v půlce gesta.

| Stav | Vstup | Výsledek |
|---|---|---|
| `idle/select` | Pointer down na objekt | Vybrat, připravit drag; do překročení 4 screen px jde o klik. |
| `dragging/resizing/rotating` | Pointer move | Počítat z počátečního snapshotu a celkového raw delta, nikdy z předchozí snap pozice. |
| `placing` | Pointer move/drop | Ghost s validací; drop commitne jediný Insert command, Escape nic nevloží. |
| `drawingPath` | Klik/Enter/Backspace/Escape | Přidat vrchol/dokončit/odebrat poslední/zrušit rozkreslení. |
| `editingText` | IME, blur, Escape | IME completion před commitem; Escape vrací text z počátku editace. Cmd+Z uvnitř pole nejprve patří textovému editoru. |
| `editingBackground/canvas` | Handle drag / číselný vstup | Explicitní edit mění zvolenou vlastnost; automatická expanze je součástí objektového commandu. Preview a potvrzení tvoří jednu transakci. |
| Libovolné gesto | `pointercancel`, ztráta focusu během drag | Vrátit snapshot, uvolnit pointer capture a odstranit guides. |
| `saving` | Další Save / pointer | Neduplicovat request; pro první verzi zablokovat dokumentové úpravy do výsledku, kamera a prohlížení zůstávají dostupné. |

Command families: `InsertNodes`, `DeleteNodes`, `TransformNodes`, `Group/Ungroup`, `SetText/Style`, `EditVertices`, `Attach/DetachSeat`, `Generate/UpdateAssembly`, `RenumberSeats`, `ResizeCanvas`, `Replace/Transform/CropBackground`, `Save/DeletePreset`. Každý vrací change set s dotčenými IDs, warnings, inverse pro historii a validation issues. Session příkazy select/pan/zoom/grid nemění dirty stav ani undo. Rozpracovaná textová editace nebo několik změn stejného slideru patří do jednoho explicitního begin/commit, nikoli debounce s nekonečně otevřenou historií.

Při multi-select jsou různorodé hodnoty „Různé“, prázdný input nesmí omylem resetovat ostatní. Lock předka zamyká potomky. Změna celé skupiny s locked potomkem je zamítnutá s konkrétním jménem. Mazání má náhled počtu objektů a obchodních míst; žádné částečné provedení příkazu přes zakázané potomky.

### Konkrétní geometrické algoritmy

1. **Rectangular table anchors:** obvod se rozpadá na čtyři strany. Parametr `t` je normalizovaná pozice středu sedadla na straně, `gap` vzdálenost obrysů. Dostupná délka odečítá rohové rezervy a poloviny sousedních seat šířek; nové sedadlo se přidá na vybranou stranu a automatická sedadla této strany se rovnoměrně přerovnají podle kapacitní strategie. Ostatní strany a manual/locked výjimky se bez explicitního příkazu nepřeskupují. Přidání i přerovnání jsou jeden batch command.
2. **Round/ellipse anchors:** ukládat normalizovaný parametr obvodu, orientovat k normále obrysu. U elipsy nelze rozdělit úhel rovnoměrně a tvrdit stejné rozestupy; použít délkovou parametrizaci obvodu z deterministické aproximace. Při změně počtu automaticky přerovnat automatická místa, zachovat pořadí/ID a kapacitu ověřit délkou použitelné hrany stolu i skutečnými transformovanými obrysy.
3. **Generator diff:** vytvořit kandidáty se stabilními slot keys `(assemblyId,row,block,index)`; existující slot drží node ID. Ruční výjimka je `manual` node připojený ke skupině, změna parametrů ji nesmaže. Odebrané sloty s objednaným/drženým sedadlem blokují celý diff. Náhled uvádí `+nová / změněná / -odebraná`.
4. **Snap:** sbírat cíle jen z prostorově blízkých objektů a viewport hran, vynechat moving subtree. Screen threshold přepočítat zoomem; zvolený magnet držet hysterézí. Přichytávání do lokální osy otočené řady pracuje v jejím souřadném systému; výsledné world guides ukazují skutečný match.
5. **Kolize:** spatial index nad world AABB, potom SAT pro orientované obdélníky/konvexní části; kruh/ellipse a zakřivené symboly převést na pinovanou obrysovou aproximaci. Zdrojový symbol má vlastní physical hull odlišný od hover hit targetu. Bezpečnostní rozestup je uživatelský geometrický parametr, ne prohlášení o splnění stavebních norem.
6. **Fit do oblasti:** prohledat počet řad/slotů a povolený interval rozestupů, vyřadit kolize a zablokované plochy; řadit kandidáty nejdřív podle splněného počtu, potom nejmenší změny rozestupu a stabilního ID. Nikdy měnit seat size. Pokud žádná varianta nevyhoví, ukázat maximální dosažený počet a blokující oblast. Hledání má limit 100 000 kandidátů, kontrolu cancel mezi dávkami nejvýše 8 ms a při vyčerpání vrací nejlepší dosud nalezené varianty označené jako neúplné hledání. Nesmí tvrdit, že lepší varianta neexistuje. Parametry rozestupů vzorkuje v uživatelem zadaném kroku, takže výsledek je reprodukovatelný; žádný neomezený synchronní loop.
7. **Dvoubodová registrace:** `scale=|B2-B1|/|A2-A1|`, rotace je rozdíl úhlů úseček, translace mapuje A1 na B1. Shodné/téměř shodné body odmítnout, označit body a chybu; vyžadovat vzdálenost alespoň 1 world unit a 8 screen px pro výběr. Výsledek je similarity transform bez shear, uložený podkladově, nikoli do sedadel.

### Jedna fontová pipeline ve Festapp

Současný tok je konkrétní: `TicketFontCatalog.load` -> `FontFamilyPicker` -> `TicketLayoutService.font(occasionId,id)` -> `preview-ticket-layout` mode `font`, protocol 2 -> `resolveTicketFont`/`TicketFontResolver` -> ověření SHA a Flutter `FontLoader`. `selectFont` používá generation token a commit až po úspěchu. Blueprint převezme tento tok, ne jen vzhled dropdownu.

Z `TicketLayoutService` vyčlenit pouze neutrální resource/cache/registration část do `lib/components/fonts/editor_font_service.dart`. `TicketLayoutService.font` zůstane jeho delegující caller, Blueprint font adaptér dalším callerem. `TicketFontCatalog` i `FontFamilyPicker` zůstávají sdílené existující komponenty bez blueprint kopie. Případné neutrální přejmenování katalog loaderu musí být skutečný přesun obou callerů, nikoli alias a druhý soubor JSON.

Pro vektorovou scénu doplnit k existujícímu hashovanému resolveru odvození glyph cest stejným `fontkit`, který už vytváří metriky. Cache key je `(fontSHA, outlineProtocol)`, nikoli rodina; metadata dál vlastní původní katalog. Host font resource request může získat toto rozšíření přes nový explicitní resource protocol na stejné servisní pipeline; původní ticket protocol 2 zůstane kompatibilní. Znovu nevytvářet fetch/cache/font authorization řešení v blueprint funkci.

Autorizovaný editor může on-demand připravit fontové zdroje. Save ověří připravenost zdrojů všech skutečně použitých font ID. Veřejný viewer dostane pouze existující immutable resource reference těchto fontů, nikoli přístup k autorizovanému preview endpointu. Při veřejném cache miss se nesmí spouštět neomezené generování celého katalogu; zobrazit retryable resource error. Bucket, public delivery a CORS ověřit proti existujícímu `ticketFontStorage.ts` a font asset infrastruktuře před přidáním URL; přímé zdroje Google v browseru nejsou fallback.

Core používá stejné advance metriky jako ticket text, řídí zalomení a syntetické emphasis deterministicky. První verze negarantuje komplexní script shaping nad rámec existujícího ticket kontraktu; nepodporovaný glyph nesmí tiše změnit uložený text. Před finálním save uživatel opraví text nebo výslovně zvolí podporovaný font. Standardní české/anglické texty a NFC/combining diakritika mají explicitní fixtures. Celý katalog zůstává ve výběru dostupný, neprůchodný konkrétní font vrací stejný viditelný resource failure jako ticket editor.

### Obnovení draftu, práva a změny zvenku

Host drží `baselineRevision`, immutable `baselineDocument`, aktuální draft a poslední potvrzené bindings odděleně. Obnova draftu obsahuje schema/resource protocol, blueprint/occasion ID a baseline revision, nikdy hold secret nebo zákaznická data. Soubor při importu zobrazí scope a rozdíl revision; z jiného blueprintu importuje geometrii jako nové identity, ne původní spot bindings. Offline režim dovolí geometrii a lokální export, server Save je neaktivní s vysvětlením.

Příchozí změna obsazenosti aktualizuje pouze `seatPresentation` a host constraints. Nesmí přepsat lokální dokument, smazat undo ani resetovat kameru. Pokud místo určené ke smazání mezitím získá hold, označí se jako nový blocker a save znovu prověří SQL. Ztráta editor práv přepne na read-only a nabídne export návrhu; nesmaže draft. Generic balíček pouze respektuje `readOnly` a constraints, host i server vlastní autentizaci.

V lokálním prototype setupu callback vrací dokument jen po explicitním Apply, Cancel ho nesmí uložit jako vedlejší efekt dispose. Parent setup draft musí odlišit přijmutí a zrušení editoru; původní chování prototypu prověřit a opravit při integraci. Tím se ochrání uživatelské očekávání i plnohodnotné balíčkové použití.

### Save request, výsledky a tabulka povolených změn

Transport zachová `p_command_id` v existující command vrstvě, `p_blueprint` nově obsahuje následující části. Nepřidávat command ID do uloženého layoutu:

```text
{ id, occasion, title, expected_layout_revision, layout,
  seatChanges: {
    create: [{nodeId, productId, title, groupLabel}],
    update: [{nodeId, spotId, expectedMetadata: {productId,title,groupLabel},
              nextMetadata: {productId,title,groupLabel}}],
    remove: [{nodeId, spotId}]
  },
  groupProductChanges: [{groupNodeId, expectedProductId, nextProductId}],
  areaBindingChanges: [{nodeId, expected, next, capacityChange}]
}
```

Čistě dekorativní dokumenty jsou validní; v setupu se kvůli nim nesmí zapnout blueprint prodej ani nulovat běžnou kapacitu formuláře. Prodejní plánek ale může být tvořen jen stáním: aktivní seat bindings nebo validní prodejní capacity-area binding znamenají skutečnou nabídku, nikoli počet všech nodes. Neúplný lokální seat bez produktu je draft; běžný Save vyžaduje produkt. Žádná produkční „draft spots“ tabulka.

| Operace | Volné místo | Aktivní hold | Objednané/použité místo |
|---|---|---|---|
| Posun, rotace, vizuální styl | Ano, se stejným spot ID. | Ano, držení i výběr se zachovají. | Ano, identita i ticket vazba se zachovají. |
| Přejmenování, změna produktu | Ano po validaci scope/produktů. | Ne. | Ne. |
| Smazání nebo odstranění seat binding | Ano v atomické transakci. | Ne. | Ne. |
| Připojit/odpojit od stolu | Ano. | Ano, pokud se nemění obchodní metadata ani ID. | Ano se stejnou podmínkou; změna zákaznického označení stolu je zvlášť chráněná metadata změna. |
| Kopírovat/preset | Nová node ID, nová spot ID až při save. | Kopie bez hold. | Kopie bez objednávky a stavu. |
| Zmenšit plátno/skrýt parent přes místo | Blokovat, pokud by místo nebylo vykreslitelné. | Stejně. | Stejně. |

Ochrana „odpojení obchodní vazby“ neznamená zákaz vizuálního detach od stolu; jsou to dvě různé operace. Tabulka je závazná pro controller preflight i SQL. Transformace s kolizí je blokovaná celkovým geometrickým validátorem, nevytváří částečný save.

Výsledky mají stabilní machine reason: `invalid_document`, `unsupported_schema`, `revision_conflict`, `seat_in_use`, `foreign_reference`, `product_unavailable`, `resource_unavailable`, `payload_limit`, `upgrade_required`. Ke každému patří `issues[{nodeId,path,reason}]`, případně aktuální revision, nikdy secret. Host přeloží důvod a vybere problémové objekty. `revision_conflict` nabídne Exportovat můj návrh / Načíst uložený; původní draft zůstává, dokud uživatel nerozhodne.

Save snapshot je neměnný. Při síťovém timeoutu znovu poslat přesně týž command ID a payload; nový command ID by nebyl bezpečný retry. Success musí vrátit revision a úplné mapování změněných bindings. Až po aplikaci response nastaví UI baseline ze serverem potvrzeného odeslaného immutable snapshotu a přidělených bindings, nikoli z mezitím proměnlivého aktuálního draftu. Zamítnutá změna obchodních řádků se rollbackne v SQL subtransakci a až potom se uloží rejected receipt; nepoužívat průběžné UPDATE následované prostým JSON returnem.

Zámky: nový owner nejprve ověří scope a command receipt, poté serializuje editor přes blueprint `FOR NO KEY UPDATE` (nemění blueprint klíč), podle potřeby čte/zamyká produktové reference před zamykáním spotů a spoty zamyká vzestupně podle ID. Save nikdy nebere buyer/admission advisory lock; `select_spot` ho dnes získává před spot row lockem. Před finálním SQL projít zbývající order/swap/copy spot writers a zaznamenat lock order do SQL komentáře a testu. Změnu tohoto pořadí neprovádět bez dvousession důkazu; současná evidence neprokazuje všechny order internals.

## Uzavření produktových rozhodnutí a integrační kontrakt

Rozhovor je pro přípravu implementace uzavřený. Potvrzené volby uživatele jsou uvedené v produktových sekcích. Následující provozní defaulty jsou návrhová rozhodnutí odvozená ze zachování současných ticket/order/inventory hranic; nejsou dalšími nevyřízenými otázkami ani souhlasem s produkčním zápisem. Nový důkaz z kódu může změnit technickou cestu, nikoli potichu změnit výsledné chování.

### Nejkratší běžná cesta plesového pořadatele

1. Vytvořit plánek -> galerie -> vybrat plesovou šablonu. Hned se otevře editovatelný návrh; žádný povinný průvodce, měření sálu nebo výběr layout enginu.
2. Přetáhnout stůl/předvolbu, případně upravit počet míst. Editor přichytí a přerovná, nabídne platné kotvy a podle potřeby rozšíří plátno.
3. Vybrat stůl -> v kompaktním inspectoru změnit označení, počet/rozměr a existující cenový produkt. Výjimky na jednotlivých místech jsou rozbalovací volba, nikoli další trvale otevřený panel.
4. Podle potřeby vložit parket, pódium, sloupy, gauč, text nebo společnou plochu stání. Přízemí i balkón zůstávají v jednom přehledu. Dekorace nevyžadují produkt.
5. Náhled zákazníka -> Uložit. Ukázat jen skutečné blokery, vybrat dotčené objekty a nabídnout přímou opravu; neměnit prodané místo nebo platbu automatickou „opravou“.

Výchozí UI používá Výběr/Posun, Vložit a kontextové vlastnosti. Nezobrazovat při prvním otevření technické souřadnice, UUID, algoritmické profily, všechny cenové výjimky a všechny pokročilé možnosti najednou. Plná funkčnost je dostupná přes progressive disclosure, nikoli ztracená v samostatném technickém režimu. Chování fontů, galerie, barev a podkladů má stejná očekávání jako ticket editor.

### Vstupenky, storno a výměna společné jednotky

- Gauč má samostatná spot/ticket ID pro každé fyzické místo, dvě místa tedy vytvoří dvě vstupenky ve stejné objednávce. Společné musí být přidělení i uvolnění, nikoli skenování vstupu: každý ticket se dál běžně skenuje zvlášť. Neměnit QR formát ani tiskový model kvůli tvaru nábytku.
- Požadavek storna člena společné jednotky nejprve zobrazí celý dotčený pár a dopad na objednávku, pak jedním potvrzením pošle kompletní množinu stávajícímu cancellation owneru. Samotná operace na jedné polovině je serverem zamítnutá, ne potichu rozšířená po odeslání. Refund/stav plateb se řídí stávajícími pravidly; žádná nová automatická bankovní výplata.
- Ochrana mutability platí pro všechny dotčené vstupenky. Pokud některou nelze změnit, operace neprovede polovinu a UI pojmenuje překážku. Po částečném využití či při historicky neúplném páru se nepovolí prodat zbytek cizímu kupujícímu; zobrazit konflikt ke správě, ne vytvořit druhý rezervační režim.
- Výměna kompletních jednotek stejné velikosti se provede atomicky stávajícím hardenovaným ownerem. Přechod na jiný počet míst patří do explicitního replace workflow s náhledem storna, nových vstupenek a výsledné částky. Původní jednoduché výměny jednotlivých sedadel dál fungují.
- Dodržení jednotky musí ověřit také přímé order/ticket commands a zásahy administrátora, nikoli jen blueprint widget. Scope rozšíření je ochrana nových společných jednotek; neměnit ostatní storno/refund pravidla aplikace.

### Stání: navázání na ověřenou kapacitní autoritu

**Fakta z aktuálního kódu:** `finalize_ticket_order_internal_v1` v `database/functions/eshop/finalize_ticket_order.sql` přijímá i ticket bez `spot`; ověří vybraný produkt vůči `form_fields` a kontroluje produktové maximum. Volá `lock_ticket_order_products_internal` a na konci `apply_allocations(order_id)`. `database/functions/inventory/apply_allocations.sql` alokuje existující `eshop.spots` přes `product_inventory_contexts`, zamyká řádky a respektuje `inventory_pools.sellable_capacity`. Kapacitní stav není důvod zakládat novou tabulku účastníků nebo počítadlo prodaných kusů v layout JSON.

**Rozhodnutí:** společná plocha stání je geometrický `capacityArea` node s host vazbou na prodejní produkt a jeden řídicí inventory context. Host tabulka `eshop.blueprint_area_bindings(blueprint,node_id,inventory_context,product)` má PK `(blueprint,node_id)` a reference do existujících entit; neobsahuje own `sold/remaining/capacity` counter. Capacity authority zůstává pool/context a jeho spot supply. Pro první verzi povolit jednu plochu na řídicí context v blueprintu, aby dvě kresby nezdvojily nabídku stejné kapacity. Případné další produktové inventory contexts stále omezuje existující finalizer.

Při změně počtu v editoru použije blueprint save transakčně interní inventory bundle/capacity owner, pokud host výslovně mění jeho konfiguraci. Pouhé přetažení/resize plochy mění geometrii, nikoli počet prodejních míst. Default předvolby například navrhne kapacitu 5; po uložení se badge odvozuje z autoritativního inventory stavu. Přímý klientský zápis do poolu/bindings není povolen. Příslušnost produktu/contextu a proveditelnost snížení pod obsazenost ověří server se zámky v pořadí stávající inventory cesty.

Na klik zákazník nastaví počet, host z něj vytvoří běžné ticket items se stávajícími product fields, bez konkrétního spot ID a bez falešného `secret`. Dvě místa na stání znamenají dvě vstupenky a dvě alokované kapacitní jednotky. Produkt musí být přípustný pro daný formulář; vazba na plánek jeho oprávnění neobchází. Pokud v nabídce formuláře chybí, editor nabídne opravu konfigurace před zpřístupněním prodeje.

Výběr počtu stání není hold. Při checkoutu existující transakce znovu ověří maximum a alokuje kapacitu; konflikt nezanechá novou objednávku s poloviční alokací. V košíku neslibovat rezervaci stání před jeho potvrzením. Ve smíšené objednávce se sedadly zachovat platné seat holdy, ale nepotvrdit neúplnou objednávku při nedostatku stání. Cena/obsah košíku se automaticky nezkrátí na to, co se právě vešlo.

Veřejná dostupnost se projektuje z existujících produktových a inventory dat: skutečná dostupnost je minimum produktového limitu, volné supply a všech požadovaných contextů podle jejich quantity. Pokud nynější reader vrací jen boolean (`is_product_dynamically_available`), doplnit jeden společný SQL read helper pro počet; nesčítat jinak v Dart a JS. Read snapshot může během rozhodování zestárnout, finální autorita je checkout. Obě platformy ukazují stejné `capacity/available/selectedQuantity`, stejné důvody zamítnutí a stejné cenu za položku i součet.

### Dokončený seznam nových polí a vazeb

Tento seznam doplňuje základní geometrický příklad; žádná část projektu nesmí opomenout vztahy přidané během rozhovoru:

| Kontrakt | Kanonický obsah / vlastník |
|---|---|
| `layout.selectionUnits` | `[{id, nodeIds}]` se stabilní UUID a nedělitelným výběrem. Místo patří nejvýše jedné jednotce. Bez cen nebo ticket IDs. |
| `layout.sections` | `[{id,title,levelId,rootId,outline}]`; vlastní část plánu, nikoli samostatný viewer. `rootId` ukazuje na kontejnerový node. `outline` je volitelný validovaný polygon v lokálních souřadnicích rootu. |
| `layout` node kinds | Minimálně `group`, `table`, `seat`, `furniture`, `capacityArea`, `shape`, `text`. Nábytek obsahuje editovatelný geometrický typ. `capacityArea` nese jen geometrii/roli, počet dodává host. |
| `blueprint_seat_bindings` | `(blueprint,node_id,spot,selection_unit UUID NULL)`; SQL je validovaná projekce vazeb, nikoli druhá definice jednotky. Nepřijímat rozporné členství. |
| `blueprint_group_products` | `(blueprint,group_node,product)`; persistovaný cenový default stolu, bez duplikace ceny. |
| `blueprint_area_bindings` | `(blueprint,node_id,inventory_context,product)`; mapuje stání na stávající kapacitní autoritu. |
| Save DTO navíc | `groupProductChanges` a `areaBindingChanges` vedle `seatChanges`; expected revision chrání všechny části jednoho blueprint aggregate. Případná požadovaná capacity změna je explicitní intent, ne nepřímý důsledek změny velikosti kresby. |
| Host presentation | `seatPresentation` pro adresná místa a `capacityPresentation` pro společné plochy; obsahují aktuální labels/stavy/kapacitu/cenu pro UI. Jsou oddělené od přenositelné geometrie a nejsou ceníkem balíčku. |

Parser nové geometrie validuje všechna ID a vztahy v jednom passu. Save SQL ověří přesnou shodu seat nodes/bindings a membership, příslušnost produktů/contextů a registry resource; odeslaný overlay stav není autorita. Nové bindings se vracejí v command resultu, žádné odhadování spot IDs v klientu.

### Jednotná historie a velikost response

Připojení sedadla ke stolu mění layout i host produktový draft. Balíček poskytne obecný history participant (`capture/restore`) a připojí immutable host checkpoint ke stejnému history entry jako geometrický command. Host nemusí zapisovat obchodní data do layoutu ani udržovat druhý nezávislý undo stack. Undo/Redo vždy obnoví obě části; potvrzené product catalog mutations do této historie nepatří. Host resources/presentation snapshoty se přes tento mechanismus nevracejí do staré obsazenosti.

Existující mutation architecture omezuje `data` command response na 4 MiB a receipt na 8 MiB (`docs/architecture/mutations.md`). Save response tedy nebude automaticky zrcadlit celý až 8MiB request/layout. Vrátí accepted revision, serverový document hash, nové/změněné bindings a potřebné host replacements; server geometrii tiše nepřepisuje. Klient před odesláním drží kanonický normalizovaný snapshot, po success přijme přesně tuto baseline a serverem přidělená ID. Hash je reference potvrzeného serverového obsahu, ne předpoklad o identickém serializéru PostgreSQL/Dart. Největší fixture musí prokázat oba response limity včetně sync metadat.

Po úspěchu Save se undo historie uzavře na potvrzené baseline, zůstává geometrie a kamera. Timeout používá stejné command ID a payload. Conflict/permission/resource/capacity rejection uchová draft, protože není validní success. Veřejná read RPC může vracet velký dokument podle vlastního limitu; nepřizpůsobovat kvůli tomu druhý mutation envelope.

### Technické brány a konec plánování

Nezbývá otevřená otázka základního UX, cenového modelu, výběru gauče, stání nebo přepínání pater. Zbývají implementační důkazy: G0 pro JS distribuci, přesnou kvantizaci geometrie v obou runtime a paritu fontů, reprodukovatelná package release sada, measured payload/performance a read-only inventura skutečných legacy výjimek před provozním převodem. Tyto práce jsou součást příslušných vln; nejsou předstíraně splněné tímto plánem a nevyžadují znovu návrhový rozhovor, pokud se nezmění požadovaný produkt.

Demo-ready (etapa A) znamená G0, vlny 1-6 a 10A včetně DA01-DA08; vlny 7-9 ani úpravy Festapp nejsou podmínkou. Integration-ready (po samostatném zadání etapy B) přidá vlny 7-9 a 10B, skutečné SQL/inventory důkazy a suchý migration kit. Production cutover-ready (etapa C) navíc vyžaduje konkrétní tenant/scope a provozní důkazy vln 11-12. Plánování je hotové uložením tohoto konzistentního dokumentu a execution promptu; implementace, publikace a produkce nebyly tímto rozhovorem provedené.

## Akceptační scénáře a důkazy

Každý scénář má být pokryt u skutečného vlastníka chování. Parametrizované core cases nahrazují stovky téměř stejných UI testů. Widget/E2E se soustředí na kompletní interakční cestu, SQL na doménovou autoritu a souběh.

| ID | Provedení | Pozorovatelný výsledek / důkaz |
|---|---|---|
| AC01 | Prázdný dokument, vložit stůl, postupně 7 sedadel, uložit a otevřít. | Sedadla mají unikátní stabilní node/spot ID a stejnou geometrii po roundtrip. |
| AC02 | Otočit stůl 37 stupňů, zvětšit, odpojit jedno místo, undo/redo. | Připojené nodes sledují stůl, odpojené drží world transform; obnoví se přesně celý předchozí stav. |
| AC03 | Zmenšit kapacitu stolu s jedním prodaným místem. | Odebrání tohoto ID blokuje celý diff; žádný jiný spot se mezitím nesmaže. |
| AC04 | Sál: 10 řad, 2 bloky, ulička, liché/sudé číslování a ruční výjimka. | Žádná místa v uličce, číslování má preview, výjimka přežije změnu parametru. |
| AC05 | Autobus 2+2 se zadní lavicí, poté ručně odstranit dvě volná místa. | Zůstane editovatelný dokument, počet prodejných míst odpovídá spotům. |
| AC06 | Dva vlakové vozy, kupé, protilehlá místa se stolem a vlastní čísla. | Sekce/označení se nesměšují s produktem, pořadí je správné ve Flutter i JS. |
| AC07 | Vybrat jiný font přes stejný picker jako ticket editor, změnit barvu a velikost víceřádkového textu. | Stejná font ID, stejné resource/cache chování; po save stejný text layout na obou runtime. |
| AC08 | Rychlá volba font A -> B, A doběhne poslední; potom simulovat font failure. | Zůstane B; při chybě zůstane poslední platný font, žádný tichý fallback. |
| AC09 | Kreslit obdélník, elipsu, šipku a polygon; upravit vrchol a alpha. | Přesné obrysy/barvy a validní serializace, self-intersection má konkrétní error. |
| AC10 | Uložit vlastní skupinu jako preset, přetáhnout ji dvakrát při zoomu 2 a otočeném parentovi. | Správné world pozice, nové IDs a nezávislé instance, žádná zkopírovaná objednávka. |
| AC11 | Volná rotace, snap 15 stupňů, číselný úhel a roh jako pivot. | Stejný transform/hit test po opakovaném save; přetažení nepřeskakuje. |
| AC12 | Zmenšit plátno přes sedadlo, zrušit, potom fit plátna obsahu. | Nesmí zmizet sedadlo; Cancel zachová přesné rozměry a fit zahrnuje rotované bounds. |
| AC13 | Vyměnit podklad 4:3 za 16:9, contain/fill/crop/registrace, undo. | Žádný automatický pohyb sedadel; rozdíl volby je viditelný před potvrzením. |
| AC14 | Při uploadu selhat, odstranit podklad, vrátit přes undo. | Zdrojové assety nejsou smazané, předchozí geometrie je obnovitelná. |
| AC15 | Dva editoři načtou revision N, oba ukládají odlišnou změnu. | První uspěje, druhý dostane conflict, žádný last-write-wins. |
| AC16 | SQL uloží změnu, síť ztratí odpověď, klient opakuje command. | Jedna revision změna, stejná nová spot ID, jeden receipt/publication. |
| AC17 | Save maže volné místo současně s novým holdem/order finalizací. | Pořadí zámků rozhodne; buď hold/order uspěje a delete je zamítnutý, nebo delete uspěje a hold selže bez přidělení cizího místa. |
| AC18 | Poslat cizí blueprint/spot/product, duplicate ID, cyklus nebo obří payload. | Zamítnout bez vedlejších doménových zápisů, veřejně nevrátit privátní data. |
| AC19 | Převést legacy plánek se SVG a objednávkami; poté konverzi zopakovat. | Stejné spot ID a stavy, stejný registr podkladu, druhý apply nic nepřepíše. |
| AC20 | Setup draft otevřít/zavřít z editoru a finalizovat, poté duplikovat akci. | Draft zachová dokument; copy vytvoří nové identity a korektní product map bez holdů. |
| AC21 | Public výběr stejného místa ve Flutter a JS, souběžný obsazený stav. | Obě cesty rezervují stejné spot ID; pending, odmítnutí i rollback jsou srozumitelné. |
| AC22 | Telefon 360 px, klávesnice, screen reader a reduced motion. | Primární cesta dokončitelná bez hoveru; plátno nezmizí za klávesnicí; sémantika a focus zůstávají. |
| AC23 | Corpus 500/5 000/20 000 míst, fixní camera/DPR a motion sample times. | Přesná scene parity, schválený raster diff a report init/frame/memory; cíle nejsou tvrzené bez měření. |
| AC24 | Rozbalit veřejný release archive bez Festapp checkoutu a backendu. | Example/editor i JS viewer fungují, dokument jde exportovat/načíst a public API je kompletní. |
| AC25 | Koupit gauč, samostatně načíst oba tickety, stornovat/vyměnit jednotku. | Dvě řádné vstupenky v jedné objednávce; scan zůstává individuální, storno/swap nevytvoří napůl prodejnou jednotku a zachová dosavadní finanční pravidla. |
| AC26 | Vybrat 2 ze stání s kapacitou 5, pak souběžně dokončit další objednávku na poslední místa. | Quantity výběr bez falešného holdu; checkout nejvýše do kapacity, nedostatek rollbackne celou neplatnou finalizaci a zachová klientský návrh. |
| AC27 | Přesun/vložení za každý okraj, návrat pointeru dovnitř, cancel a undo. | Automatická expanze je jeden command s objektem, nemění souřadnice ostatních nodes, podklad ani kameru; návrat v gestu nezanechá zbytečné zvětšení. |
| AC28 | Připojit volné sedadlo k jinému stolu s jinou cenou, undo/redo a reopen. | Layout i produktový draft se obnoví společně, přebírá se persistovaný target default, ponechají se ID a ostatní výjimky. |
| AC29 | Nový pořadatel zvolí plesovou šablonu, přidá stůl, židle, cenu a uloží. | Celý základní tok bez metrů, technických ID, povinného průvodce nebo pokročilého panelu; limit židlí je zřejmý a výsledek připomíná doložené plesové plánky. |

## Implementační vlny a jejich závislosti

Každá vlna má omezený výstup. Nepřesouvat šest různých editorových subsystémů do jednoho „hotovo UI“. Etapa A provede G0 -> 1-6 -> 10A. Etapa B po samostatném zadání provede 7-9 -> 10B včetně odložených host částí vln 2/5/6. Vlna 11 obsahuje samostatně autorizované produkční kroky; globální contraction ve vlně 12 čeká na skutečné převedení všech dotčených consumerů.

| Vlna | Potřebuje | Akceptace |
|---|---|---|
| 1: core/package contract | G0 | Schema a čisté závislosti |
| 2: scéna a font resource bridge | 1 | AC07-08, základ AC23 |
| 3: controller a výběr | 1-2 | Cancel, identity, command transakce |
| 4: text, tvary a paleta | 2-3 | AC07-10 |
| 5: transformace, plátno, podklad | 3-4 | AC11-14 |
| 6: sestavy a fitting | 3,5 | AC01-06 |
| 7: SQL owner a kontrakt save (B) | Přijatá etapa A a zadání B | AC15-18 |
| 8: Festapp editor a oba pickery | 2-7 | AC01, AC15-18, AC21 |
| 9: setup, copy a converter | 7-8 | AC19-20 |
| 10A: demo, UX a package kit (A) | 1-6 | DA01-DA08, package části AC corpus |
| 10B: integrační regression (B) | 7-9, 10A | AC01-AC29 včetně skutečné obchodní autority |
| 11: autorizovaná aktivace dat | 9-10, přesný scope a oprávnění | Provozní důkaz |
| 12: contraction | Prokázaná aktivace dotčených consumerů | Absence legacy cest |

### G0. Ověření proveditelnosti před stavbou UI

V čistém temporary workspace ověřit export minimálního čistého Dart core do browser JS a jeho použití bez Flutter runtime. Z lokálního SDK zjistit skutečný interop export, nepsat neověřený binding naslepo. Pokus musí obsahovat document parse, rotovanou scénu, textové glyph cesty a hit test. Přesný SDK pin uložit do build manifestu; stávající Festapp FVM pin je 3.47.2, nelze ho automaticky zaměnit za minimální podporovanou Flutter verzi veřejného balíčku.

**Důkaz:** stejné normalizované scene JSON v Dart VM a browseru, import public JS API z distribuce, měření cold init/velikosti a ověření font resource. Pokud neprojde export/bootstrapping nebo zvolená renderer architektura, aktualizovat autoritativní plán před následnými UI vlnami. Nepřepisovat core do JS. Tento plán nevydává dosud neprovedený spike za ověřenou technologii.

### 1. Samostatné core a pevný datový kontrakt

**Změny:** ve `venue_seat_picker/packages/venue_layout_core` vytvořit pure Dart package, immutable model, validátor, transformace, contract constants, JSON schema a fixtures. Schéma od počátku zahrnuje `selectionUnits`, `capacityArea`, pojmenované sekce jednoho společného plánku a rozšiřitelné presentation contracts. Flutter wrapper závisí na core přes public API. Založit `web/` distribuci, source/contract manifest a veřejné type declarations.

**Migrace/selhání:** existující public grid API zůstane dostupné pro externí uživatele. Nový dokument není reinterpretace `VenueSeatDocument` schema 1. Unknown schema vrací typed failure a původní bytes jsou zachované.

**Validace:** package targeted model tests pro roundtrip, cykly, IDs, nesting/limity a transform inverzi; dependency check na absenci Flutter/host imports v core; G0 reprodukovat přes package build entry.

**Exit:** samostatný spotřebitel vytvoří a serializuje dokument bez Festapp i Flutteru. Finální JSON jména a schema jsou zapsaná, ne další návrh „upřesnit později“.

### 2. Jedna scéna, fontové zdroje a parity základ

**Změny v A:** core `scene/` a resource contracts, Flutter scene painter a JS SVG adaptér v balíčku; lokální licencované font fixtures a offline provider. **Odloženo do B (součást vlny 8):** ve Festapp vyčlenit neutrální font resource cache ze `TicketLayoutService` do `lib/components/fonts/editor_font_service.dart`; původní ticket caller deleguje. Reuse `TicketFontCatalog`/`FontFamilyPicker`, rozšířit existující server resolver o hashované outline resources. Přidat blueprint host FontProvider a společnou resource fixture bez nového seznamu fontů.

**Migrace/selhání:** ticket protocol 2 a vykreslení PDF beze změny. Resource protocol je explicitně verzovaný. Chyba fontu/assetu zachová dokument, stale font request nezmění aktuální volbu. Font cache pro public viewer nevyžaduje editor auth endpoint.

**Validace:** v A package část AC07-08 na resource hranici a text emphasis fixtures; targeted ticket font/cache regression až v B; Dart/browser scene equality pro Unicode, více fontů, stroke, crop a alpha. Do manifestu zahrnout resource protocol a source SHA.

**Exit A:** stejný dokument dává stejnou scénu v obou runtime bez Festapp a s obecným FontProvider. **Exit B:** ticket i blueprint čtou jediný katalog a sdílejí resource service. Demo fixtures nejsou produkční katalog ani omezení nabídky.

### 3. Controller, selection a historie

**Změny:** core command reducer, sparse spatial index a change sets; wrapper `lib/src/layout_editor/` controller, selection, marquee, pan/zoom, keyboard, pointer ownership, undo/redo a host constraint hook. Hierarchie a lock semantics podle interakčního automatu; obecný history participant propojí host draft checkpoint s geometrickou historií bez ukládání produktů do dokumentu.

**Migrace/selhání:** pouze in-memory editor. Výběr/kamera nejsou dirty, pointercancel a Escape obnoví počáteční snapshot. Nová vložení používají nová IDs i po redo; redo téhož příkazu zachová jednou přidělená lokální IDs.

**Validace:** command tests a omezená widget cesta select -> multi-select -> drag -> cancel -> undo/redo; nested lock, duplicate identity a retained raw pointer delta při opuštění magnetu.

**Exit:** standalone example umožní přesouvat, vybírat a bezpečně vracet objekty bez host callbacků a requestů.

### 4. Text, kreslení a drag-and-drop knihovna

**Změny:** generic text inspector a host font-control slot, IME overlay, barvy, box wrapping, shape tools a editace vrcholů. Paleta s kategoriemi, search, ghost placement, autoscroll, click/touch alternativou; dokumentová knihovna vlastních presets a validovaný fragment import/export.

**Migrace/selhání:** vlastní preset nikdy neobsahuje obchodní reference. Import validační chyba se zobrazí před vložením. Celá instance předvolby se vloží atomicky; jednotlivé části zůstávají editovatelné.

**Validace:** AC07-10, transformovaný drop, cancel mimo plátno, self-intersect polygon, multi-select „Různé“, dlouhý text a font failure. Targeted analyzer pouze změněných Dart souborů.

**Exit:** z prázdného příkladu lze nakreslit a popsat vlastní objekt, uložit jako preset, vložit dvě nezávislé kopie a obnovit vše přes undo.

### 5. Rotace, rozměry a podklady

**Změny:** rotate/resize handles, pivoty a numerické properties, dedicated canvas resize tool, bounds/collision preview a automatická expanze při objektových operacích podle AC27. Generic background transforms/crop/two-point registration a resource lifecycle. V A provider čte lokální soubory/bytes a spravuje jejich životnost; Festapp image provider až v B/vlně 8 používá `ImageUploadProfile.blueprintBackground`, nikoli kopii Worker policy.

**Migrace/selhání:** nový podklad nezdědí starý crop bez potvrzení; file upload a document commit jsou oddělené. Neúspěch neodstraňuje předchozí asset. Canvas shrink nemůže schovat sedadlo. Přesná geometrie se nezmění pouhým otevřením/Apply zaokrouhleného dialogu.

**Validace:** AC11-14, nenulový viewBox origin, rotovaný parent, transparent PNG, contain/fill a dvoubodová registrace se shodnými body; při změně host uploadu relevantní Worker policy tests.

**Exit:** objekt, plátno a podklad mají zřetelně oddělené nástroje a uložené transformace, všechny operace jsou samostatně undoable.

### 6. Inteligentní sestavy a fitting

**Změny:** package table/row/arc/bus/compartment generators, attachments, typově řízený automatický reflow, výpočet maximální kapacity stolu, parametric diff, number preview a collision solver. V A demo inspector dodává syntetické cenové bindingy přes host slot; Festapp inspector přidá skutečné produkty až v B/vlně 8. Obecná geometrická galerie je balíčková. Stage/aisle dekorace dostanou explicitní role překážky podle uživatelské volby.

**Migrace/selhání:** změna N neobnoví všechna IDs; manual overrides přežívají změnu assembly. Neproveditelný fit vrátí vysvětlení a kandidáty, nikoli překryté židle nebo menší lidi. Constraint hook umí zamítnout odstranění prodaného slotu.

**Validace:** AC01-06 v core/widget fixtures, ellipse equal-spacing, locked obstacle, cancel dlouhého fitu a změna parametrů s manual výjimkou.

**Exit:** uživatel vytvoří všechny tři typy prostoru, upraví jedinou součást a následně smysluplně změní parametr celé sestavy bez ztráty identit.

### 7. SQL schema a atomický save owner

**Změny:** `database/tables/tables.sql`, nové kanonické SQL zdroje pod `database/functions/eshop/` a jedna scoped migration: layout, revision, seat/group-product/area bindings, validovaná projekce selection units, strukturální validátor a resource readiness validation. Rozšířit existující inventory/order alokaci pro vazbu kapacitních ploch; nevytvářet druhý ledger. Zavést jednotkovou veřejnou fasádu se stabilní legacy `select_spot` boundary a jediným interním hold ownerem. Společný interní guard jednotky použijí finalizer, cancellation, swap a replace před doménovými změnami. Rozšířit existující `update_blueprint_client_sync_v1`, zachovat receipts a sync publication. `FormCommands` přenese typovaný výsledek místo ztráty všech detailů ve `StateError` textu. Dodržet limit 4 MiB result data/8 MiB receipt; nevracet celý velký layout v save response.

**Migrace/selhání:** schema expansion před readery/writery. Domain owner používá rollback subtransaction pro rejected receipt, scoped authorization i interní setup/copy callery, žádné nové persistent application triggers. Neopravovat historické již aplikované migration files jako jediný zdroj nové funkce.

**Validace:** AC15-18 a AC25-26 přes nový `database/tests/eshop/blueprint_layout_test.sql`, skutečný dvousession Node/PG test a grant checks. Pro save-vs-finalize sepsat skutečný lock order všech dotčených ownerů. SQL test ověřuje i nulové částečné změny po selhání posledního seat change.

**Exit:** idempotentní autorizovaný command zachová reserved/order identity, conflict vrací strukturovaná data a žádný přímý klientský zápis nemůže obejít owner.

### 8. Host integrace editoru a obou pickerů

**Změny:** `BlueprintTab` bude host shell nad veřejným editorem, `blueprint_layout_adapter.dart` mapuje dokument a seatPresentation, `blueprint_layout_saver.dart` řeší snapshot/response/conflict. Geometrické tool widgety nevznikají ve Festapp. `SeatReservationWidget` a JS `BlueprintRenderer` používají package viewer/picker, stávající eshop callbacky a product-wave eligibility. Zpracovat jednotkovou response pro společné select/release a quantity UI stání napojené na běžné ticket/product items; nepředstírat rezervaci stání při změně stepperu. Všechny části prostoru zůstávají v jednom vieweru. `get_blueprint`/`get_blueprint_for_edit` vrátí nové bezpečné projekce, metadata/bindings a revision pouze tam, kde náleží.

**Migrace/selhání:** dočasný legacy reader je jen pro explicitně nepřevedený layout, izolovaný a evidovaný pro odstranění. Nový layout nemůže propadnout do grid fallbacku. Stavové patche podle spot ID nemění document geometry ani kameru. `get_blueprint` neposílá dokumentové presets, interní generation metadata nebo draft recovery; veřejná projekce a editor preview musí přesto dát shodnou scénu.

**Validace:** AC01, AC15-18, AC21 a AC25-29; existující blueprint loading/viewport, order-sequence, preview a product-wave regression. Současně ověřit více sedadel na stejném produktu, aby produktový index nezaměnil jejich objednávky.

**Exit:** editor save/reopen a obě zákaznické cesty pracují se stejnými spot ID a package scene. Nový blueprint nemá aktivní mřížkový renderer.

### 9. Setup, kopírování a offline převodník

**Změny:** `occasion/setup/occasion_setup_page.dart`, draft serializace a `occasion_setup/finalize.sql` přijmou nový dokument a explicitní mapu produktů. `others/duplicate_occasion.sql` přemapuje všechna node/parent/attachment/assembly/selection-unit ID, spot IDs, cenové defaulty a produkty. U kapacitních oblastí zkopíruje nebo explicitně přemapuje pool/context přes existující inventory copy owner; chybějící mapa znamená error, nikoli fallback na supply zdrojové akce. Pod `automation/blueprints/` připravit inventory/dry-run/apply/verify s hashi a audit reportem. Dosavadní `blueprintObjects.length` nahradit počtem skutečných prodejných sedadel.

**Ohraničená inventura:** scoped `rg` na `blueprintObjects|background_svg|update_blueprint|BlueprintModel|VenueSeat` v `lib`, `packages`, `database/functions`, `supabase/functions`, `web_client/src`; klasifikovat všechny dynamické/SQL projekce jako reader/writer/history. Případné staré saved setup drafty převést jednorázově při verzovaném draft decode, nikoli udělat trvalý druhý finalizer.

**Migrace/selhání:** zachovat spot ID při legacy konverzi; při kopii akce naopak vytvořit nové. Staré `black/table` objekty mají odlišný význam od rezervovatelného spotu, musí projít typovým inventářem; nelze všechny objekty přemapovat na sedadla. Nested relations a pozadí se nesmějí ztratit. Converter materializuje původní geometrii/viewBox, nedopočítává nové rozestupy.

**Validace:** AC19-20, setup bez jediného sedadla ale s dekoracemi, část product map chybí, clone s inline/raster pozadím a converter replay/hash mismatch. Old setup payload odmítnout jasnou verzí po ukončení přechodu.

**Exit:** setup i copy produkují jediný dokumentový kontrakt, suchý převod každého tvaru legacy fixture je reviewable a bez jakékoliv změny rezervací.

### 10. Dokončení UX, výkonu a release kitu: 10A demo, 10B integrace

**Rozdělení:** 10A navazuje pouze na vlny 1-6 a uzavírá etapu A. 10B po vlnách 7-9 ověří skutečnou integraci; nesmí blokovat dodání dema.

**Změny:** animace/LOD tokeny, phone bottom sheet, focus a Semantics, resource retries, reduced motion, bounded history a large-plan culling. Doplnit package README/schema/examples/typings/changelog/license a archivní dry-run. Festapp dokumentace až v 10B popíše jen host hranice.

**Migrace/selhání:** nezvyšovat podporovaný max počet jen proto, že statický screenshot jde vykreslit. Zaznamenat případně nesplněný cíl a změnit kontrakt v plánu před aktivací. Generic example nepotřebuje práva ani tajné prostředky Festapp.

**Validace 10A:** DA01-DA08, package části AC22-24 a mapovaný demo corpus níže; **10B:** celý AC corpus v jeho skutečných owning test seams; screenshoty na 360/900/1440 px a DPR 1/2, zoom 0.5/1/2 a motion časech 0/80/160/240 ms. Exact display-list compare, raster edge mask místo tolerance zakrývající posun. Package `pub`/`npm` dry-runs a čistý consumer smoke z archive.

**Exit:** doložené měření frame/init/memory, zkontrolované distribuované soubory a release-ready balíček. Žádná skutečná publikace/deploy ještě neproběhla bez zadání.

### 11. Samostatně autorizovaná aktivace

**Změny:** pouze podle provozního pořadí níže a výslovně pojmenovaného tenant/datového scope. Připravené SQL a assets/readers -> oba nové klienty -> edit fence -> hashovaný převod -> verificační report -> nový editor -> otevření editace. Routine build/deploy delegace dle AGENTS.md; bez engineering rozhodování v levném deploy tasku.

**Migrace/selhání:** rezervace a objednávky se během převodu nezakládají znovu; hash mismatch, chybějící resource nebo neověřený legacy objekt blokuje daný scope. Neaktivovat další prod branch bez požadavku. Po novém objektovém zápisu není grid-only klient validní rollback.

**Validace:** živá revision/asset/source SHA a coherent version probe pro vybraný tenant, DB report spot IDs/counts a prokázané read/write kompatibility; žádná testovací placená objednávka v produkci bez samostatného zadání.

**Exit:** evidence aktivace obsahuje přesný klient/package/core/SQL source, datový scope a výsledky. Pokud aktivace nebyla zadána, výstupem implementace je explicitně neprovedený provozní krok, nikoli blokování lokálního vývoje.

### 12. Contract/schema contraction

**Změny:** podle deletion ledgeru odstranit grid callery ve Festapp, starý JS renderer, dočasné flagy a legacy write acceptance. Fyzický DROP starých sloupců až po prokázané migraci všech dotčených datových scope a klientů; žádná automatická globální migrace při prvním tenant release. Opravit oba README a AI context.

**Migrace/selhání:** externí public grid API balíčku, historické SQL migrace a offline converter zůstávají výslovnými boundaries. Nechat dočasnou read podporu pro další tenant znamená pending contraction, ne hotový celý cutover.

**Validace:** deklarace/calleři přes scoped `rg` a targeted analyzer; SQL absence přímých legacy grantů a blueprintů bez layout v contraction scope; parcel public consumer smoke a dotčené regression tests.

**Exit:** deletion ledger má konkrétní důkaz odstranění nebo přesně pojmenované záměrné ponechání. Release evidence nevydává částečný tenant rollout za globální odstranění starého kontraktu.

## Deletion ledger

| Artefakt | Konečná akce | Důkaz |
|---|---|---|
| Grid editační stavy `emptyArea/addBlack/addAvailable` v `BlueprintTab` | Nahradit objektovými nástroji; swap/create order zachovat ve správě rezervací. | Žádný grid save caller; widget scénáře obou obrazovek. |
| Festapp `SeatPosition(y,x)` adaptér a `VenueSeatController` grid load | Přesunout aktivní Festapp callery na layout API. | Scoped rg + targeted analyzer. |
| Původní veřejné API `VenueSeatDocument`/grid controller v balíčku | Záměrně ponechat pouze jako existující veřejnou package boundary pro externí uživatele; Festapp ho nepoužívá. Nezavádět adapter převádějící nový layout na hustý grid. Případné odstranění až v samostatné major release. | Balíčkové contract testy a nuloví aktivní grid calleři ve Festapp. |
| JS grid positioning, `BlueprintConfig.seatSize/baseSize`, vlastní tvarování `SeatStyler`/seat helperů | Nahradit scene adaptér; zachovat jen host interakce/tooltips a obchodní metadata. | Žádný `x * seatSize` v aktivním rendereru, společná parity fixture. |
| `SvgUtils` fallback a rozdílné runtime interpretace podkladu | Nahradit normalizovaným asset/viewBox kontraktem. | Viewer nemountuje neupravené SVG přes `innerHTML`. |
| `objects/configuration/groups/background_svg` jako geometrická pravda | Po inventuře přesunout potřebná data do layoutu nebo obchodních metadat; odstranit aktivní reads/writes. Fyzický DROP až po migraci všech DB consumerů, nikoli při prvním tenant release. | Reader/writer seznam a scoped schema contraction test. |
| Původní interní grid save | Nahradit novým vlastníkem; veřejné starší transportní facade jen jako explicitně ohraničené upgrade rejection pro staré klienty. Žádné přijímání grid payloadů po aktivaci. | SQL negativní test a grant kontrola. |
| Legacy setup/duplicate payloady a read projekce | Převést na layout + bindings včetně zdrojů funkcí vlastněných migracemi. | Setup/copy/projection tests. |
| Dočasný enable přepínač nového editoru/read podpory | Odstranit po cutoveru. Deployment registry potřebná pro ostatní scope je dočasná s jmenovanou contraction podmínkou. | Inventář flagů a aktivovaných scope. |
| Offline converter a převodní evidence | Záměrně ponechat jako audit/obnovu; runtime jej neimportuje. | Žádný import z klienta/server request path. |

### Další výslovné boundary po uzavření rozhovoru

- Původní `select_spot` je released transportní boundary pro jednotlivé místo, deleguje na jediný interní hold owner. Na multi-seat jednotce jen odmítne starého klienta; neprovádí jinou rezervační logiku. Nový picker používá `select_blueprint_unit`.
- Stávající inventory/order pooly, `apply_allocations` a ticket finalizer se zachovávají jako autorita kapacity stání. Maže se pouze případná lokální duplikace counterů/availability výpočtů, ne inventory doména.
- Původní transientní group default přestává být zdrojem cílové ceny při reparentu: nový host model čte `blueprint_group_products`. Legacy hodnoty slouží jen converteru, nejsou druhým aktivním defaultem.
- Starý `_performSwap` s nevratnou lokální mutací nahradí host pending transakce nad stejným receipted swap ownerem. Přidělené ticket/order vazby se nikdy nedají obnovit prostým Undo geometrie.

## Provozní pořadí a návrat

Tento požadavek autorizuje pouze sestavení plánu a jeho uložení. Neautorizuje změnu produkce, publikaci balíčku, commit, push ani release.

Až samostatně zadaná integrační etapa B připraví aditivní SQL, kompatibilní read podporu a blokaci starých writes pro převedené blueprinty, oba klienty a inventář dat. Při samostatně schválené aktivaci: ověřit canonical backend/organizaci, zazálohovat a zafixovat scope, nasadit kompatibilní read kontrakt, zpřístupnit oba nové klienty pro dosud legacy i nové dokumenty, krátce uzavřít pouze editační zápisy, převést scope s hash guardy a ověřit rezervace, zapnout nový editor, znovu otevřít editaci. Dočasný legacy reader je izolovaný, odstraňuje se ve vlně 12. Nepřerušovat zákaznické objednávky bez konkrétního zdůvodnění; konverze používá row lock a zachovává spot ID.

Rollback před aktivací = vypnout nový vstup. Po nových objektových zápisech se nevrací klient, který umí jen grid, a neobnovuje stará kopie `spots` přes nové objednávky. Opravovat dopředu nebo dočasně uzavřít editaci a zachovat funkční kompatibilní picker. Obnova databáze má vlastní plán s ochranou mezitím vzniklých objednávek.

Produkční rollout je standardně pouze jeden výslovně vybraný tenant; tento plán žádný nevybírá. Sdílené DB contraction může vyžadovat další rollout a tím i další oprávnění. Web build lokálně, deploy přes `automation/deploy_direct.sh`, bez automatického spouštění GitHub Deploy. Rutinní autorizovaný build/deploy a ověření živé verze delegovat levnějšímu subagentovi podle AGENTS.md, se známým source SHA, tenantem a gates.

## Ověřování a definice dokončení

Pro psaní tohoto plánu nebyly spouštěny aplikační testy ani buildy. V A se používají pouze package/demo kontroly; následující Festapp/SQL příkazy jsou určeny až pro B. Implementace má používat cílené standard kontroly podle vln, nikoli testovat po každém jednotlivém editu:

- Flutter: změněné soubory přes `fvm dart analyze <paths>` a relevantní cases přes jejich skutečné `test/sessions` rooty a `--plain-name`; nové soubory zařadit do stávající session architektury, nevytvářet desítky nových Flutter procesů.
- JS: `node --test web_client/tests/components/blueprint_loading.test.js web_client/tests/components/blueprint_viewport.test.js` a nové kernel/parity tests. Dosavadní testy upravit na skutečnou novou hranici, ne udržovat grid jen kvůli starým assertionům.
- SQL: `node web_client/scripts/run_db_tests.js database/tests/eshop/blueprint_layout_test.sql` nad lokální test DB a cílené stávající testy preview/order sequence/product waves. Concurrency ověřit přes skutečné dvě DB session.
- Balíček: jeho vlastní targeted Dart/Flutter testy a reprodukovatelný browser kernel build ve zdrojovém checkoutu. Přesné příkazy navázat na přečtené package instructions ve vlně 1.
- Deterministické browser E2E držet v repository kontraktu; agent-browser pouze průzkumná izolovaná kontrola. Pro full Festapp UI použít disposable local tenant podle `festapp-local-e2e`; pro fixture harness není potřeba živý backend.

Hotovo pro etapu A znamená DA01-DA08 a výstupy 10A, nikoli splnění SQL a Festapp bodů. Následující seznam definuje celý cílový produkt po etapě B (produkce zůstává C):

1. Od nuly lze vytvořit a uložit sál se stoly, řadový sál, autobus i vlak a pak upravit jednotlivá místa.
2. Ruční přidávání ke stolu, fitting, text s fonty/barvami, kreslicí tvary, vlastní předvolby s drag-and-drop, rotace/pivoty, změna plátna a výměna/registrace/crop podkladu mají funkční scénáře, undo/redo a chybové stavy včetně mobilního ovládání a animací.
3. Flutter a JS používají tentýž geometrický zdroj, shodné scene fixtures a připnuté assety; vizuální rozdíly se omezují na doložený raster antialiasing.
4. Save je atomický, autorizovaný, verzovaný a idempotentní; cizí scope, souběžná změna a obsazené místo nemohou poškodit objednávku.
5. Převod a duplikace zachovávají správné identity podle svých rozdílných pravidel; všechny aktivní read/write entry points jsou zapsané a převedené.
6. Jsou splněny nebo výslovně znovu dohodnuty měřené výkonové cíle, přístupnost a hranice dat. Nesplněný cíl není tichá výjimka.
7. Deletion ledger je uzavřen v autorizovaném scope; package public compatibility, historické migrace a offline převodník jsou jediná zde jmenovaná dlouhodobá ponechání.
8. Oba editory používají jediný fontový katalog a stejný picker/resource service; veřejný balíček má zdokumentované API, bezbackendový example a úspěšný čistý consumer smoke z release archivu.
9. Produkční aktivace je buď doložena samostatným release zadáním a evidencí, nebo výslovně zbývá jako neprovedený provozní krok. Samotná dokončená implementace se nevydává za dokončený rollout.

Největší zbývající technická rizika: JS export/velikost kernelu a glyph zdrojů, historická registrace SVG, největší skutečné payloady, souběžné změny jednotek/inventory a veřejná kompatibilita balíčku. G0, cílené SQL concurrency scénáře a inventory/dry-run je ověří před aktivací. Nejsou to otevřené otázky základního produktu ani důkaz dosud provedené implementace.

### Implementační důkaz A: bezpečný rozsah geometrických čísel (2026-10-18)

Při datovém auditu standalone core se prokázalo, že samotné `isFinite`
nestačí: hodnota `1e308` je konečná, ale násobení 1024 při kvantizaci přeteče
(a hodnoty nad přesností JS integerů ztrácejí garantovanou přesnost). Kontrakt
A proto explicitně omezuje absolutní geometrické souřadnice, úhly a rozměry
na `1e9`, vrací `coordinate_range` před kvantizací a má negativní fixtures.
Limit stran plátna 64-1 000 000 zůstává zachován. Autoritou konstant je
`venue_layout_core.layoutLimits`; nejde o fyzické jednotky ani tichý clamp.
Tato úprava se týká pouze plánovacího kontraktu a standalone A; neprovádí
žádnou úpravu runtime Festappu, dat ani SQL etapy B.

## Povinná funkční parita V1 (doplnění 2026-10-19)

Uživatel požaduje zachovat ve V2 všechny funkce V1. Inventura konkrétních
UI/serverových toků a závazný kontrolní seznam pro integrační vlny je v
[paritě V1 → V2](blueprint-v2-v1-functional-parity-2026-10-19.md).
Samostatné demo neuzavírá žádný obchodní integrační požadavek.

## Spustitelná integrace B (2026-10-19)

Pro nové zadání úplného napojení na Festapp použij
[autoritativní integrační plán B](blueprint-v2-integration-plan-2026-10-19.md) a
[jeho execution prompt](blueprint-v2-integration-EXECUTION-PROMPT-2026-10-19.md).
Původní execution prompt z 2026-10-18 zůstává pouze zadáním samostatné etapy A.
Tento návrh je referencí pro platné datové a produktové invarianty; pořadí práce
a hranice aktuálního integračního provedení určuje nový plán.
