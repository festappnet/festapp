# Blueprint: kanonický model, shodný render a kvalitní typografie

Datum: 2026-10-20. Stav: lokální canonical cutover dokončený; aktuální ověření a omezení eviduje canonical-cutover-ledger.md.
Verification: standard. Produkční rollout vyžaduje samostatný rozsah.

## Upřesnění podle uživatelské QA

Uživatel výslovně požaduje skutečný font při editaci. Editor proto používá
přechodné nativní odstavce nad stejným autoritativním dokumentem a registrovaným
fontovým řezem. Tažení ani změna rozměrů nespouští přípravu vektorů. Zachycené
uložení a přechod do prohlížení připraví kanonické textové vektory; uložené
prohlížení a veřejný web používají pouze tyto připravené zdroje. Požadavky na
shodu výsledku níže se vztahují k uloženému/prohlíženému plánku, nikoli k
průběžnému nativnímu náhledu editoru. Nejde o druhý uložený model.

Ovládání editoru sdílí fontové, barevné a číselné komponenty s editorem vstupenek.
Aktuální výsledky: [canonical-cutover-ledger.md](evidence/blueprint-typography-20261020/canonical-cutover-ledger.md).
Níže uvedené průběžné stavové poznámky jsou historická evidence původní realizace.

## Průběžná implementační evidence

[Engine rozhodnutí, opravené admission regrese a přesný stav](evidence/blueprint-typography-20261020/decision-and-status.md).
HarfBuzz 14.6.0 je ověřený jediný kandidát backendu; Fontkit selhal na marks/Indic.
Dvě konkrétní schema-1 SQL mezery jsou opravené a jejich bounded SQL/Dart/extracted
JS corpus prochází. Celý text layout, dokument 2, runtime cutover a SVG import
zatím nejsou dokončené. Tato evidence nenahrazuje žádnou výstupní bránu.

## Výsledek a autorita tohoto plánu

Jeden uložený plánek se po save/read/copy zobrazí ve Flutteru a web klientu
se stejnými objekty, textem, fontovými řezy, umístěním glyphů a selection units.
Font musí být typograficky správný a čitelný, nestačí shodně chybný výsledek.

Tento dokument je nový autoritativní realizační plán. Nahrazuje pořadí realizace
v `blueprint-data-model-audit-plan-2026-10-20.md` a doplňuje jeho požadavky.
Původní ST/CT/PH/TX/PR/IO/MG/UI/PF acceptance a doménové invarianty zůstávají
závaznou přílohou; níže je jejich mapování na nové vlny. Jeho tvrzení, že skutečné
font faces/shaping mohou počkat, se tímto **ruší**. Ostatní změny kontraktu jsou
výslovně uvedeny zde. Starý plán ani starý execution prompt nejsou druhou autoritou.

Původní plánovací session neopravňovala implementaci. Následné uživatelské
zadání execution promptu autorizovalo lokální realizaci a disposable ověření.
Produkční změny, commit, push a registry publication zůstávají mimo tento rozsah.

## Přesný požadavek na zpracování celého textu

**Text se nejprve typograficky zpracuje v souvislém kontextu. Nesmí se skládat
podle samostatných šířek Unicode znaků.** Odstavec se rozdělí podle směru, scriptu,
jazyka a řezu na potřebné shaping runs; hranice nejsou libovolná jednotlivá
písmena. Shaper může několik znaků spojit do ligatury, jeden znak rozložit na
více glyphů, přeuspořádat je a upravit jejich polohy. Výstup obsahuje glyph IDs,
clusters, advances a offsets. Při zalomení se konečné řádky podle potřeby znovu
shapují s odpovídajícím kontextem; dlouhý shaped odstavec se nesmí slepě rozstříhat.

Potom lze obrysy výsledných glyphů kreslit jednotlivě, nebo je spojit do jedné
vektorové cesty labelu. **Obě varianty jsou přípustné, pokud zachovají tentýž
shaped výsledek.** Glyph cache není znakový layout: sdílený obrys podle face ID
+ glyph ID šetří data, zatímco umístění nadále určuje celý shaped run.
Není požadován bitmapový obrázek celého nápisu. Zachovat editovatelný originální
text, vektorovou ostrost, přístupný text a skutečné fontové identity.

Flutter painter a web SVG adaptér dostanou tentýž kanonický výsledek. Nesmějí
samostatně odhadovat kerning, wrap, velikost, baseline nebo syntetizovat B/I.
To je závazné uživatelské rozhodnutí pro tento plán.

## Pracovní kopie a evidence

- Host: `/Users/miakh/source/festapp-blueprint-cutover-release-20261019`,
  HEAD `a3a0637d8eeec1b0d5d3a5292e6db62fdcb4f5d1` plus současný necommitnutý
  scoped-font diff. Zachovat ho a navázat na něj; HEAD není úplný stav vstupů.
- Package: `/Users/miakh/source/venue-seat-picker-blueprint-b-20261019`,
  HEAD `0b881853bd9071784fd66102a03a1606a81afa79`, nyní změněná npm verze 0.2.3.
  Host má skutečný nový vendor archiv a lock. Před prací uložit bounded inventory
  HEAD/diff a hashů relevantních vstupů; nedělat reset ani pracovat v dirty původním main.
- Potvrzené reprodukce a dosavadní kontroly:
  [implementační evidence](evidence/blueprint-data-model-implementation-20261020.md)
  a [původní audit](evidence/blueprint-data-model-audit-20261020.md).
- Poslední kontrola první vlnu znovu otevřela. Passing scoped B/own C corpus
  dokazuje úzký průchod, nikoliv úplnou paritu nebo dokončení architektury.

| Potvrzený stav | Konkrétní owner / důsledek |
| --- | --- |
| SQL přijme duplicitní masku, kernel ji odmítne | `validation.sql`, `model.dart:validateDocument`; chybí rovnost admission pravidel |
| SQL validní atomic furniture nemá glyph × pro badge | `resources.sql:blueprint_layout_font_dependencies_internal` sbírá authored text; `scene.dart:_SceneGeometry/_compileScene` vytváří další text |
| Host, SQL a scéna rozhodují o textových závislostech samostatně | `blueprintLayoutFontCharacters`, SQL helper, `_glyphs`; chybí kanonický textový kontrakt |
| Současné obrysy vznikají bez shaping kontextu | `_shared/layoutFontOutline.ts` volá `glyphForCodePoint`, `scene.dart:_glyphs` sčítá advances po runách |
| B/I jsou simulované | `_glyphs` používá shear, scéna přidává stroke; nejde o skutečné řezy |
| Katalog nenabízí obecně všechny řezy | generátor `extractVariants` vybírá jeden normal face na rodinu; poslední inventura: 1893 normal/400, 2 normal/300, 1 normal/700, žádná italic položka |
| Font resolver odmítá některé formáty | `ticketFonts.ts:TicketFontResolver.validate` odmítá nebundled variable/color fonts; nelze automaticky slíbit podporu všech písem |
| Core už sdílí scénu mezi klienty | package `scene.dart`, `web/kernel/main.dart`, `layout_scene_surface.dart`, `web/src/index.js`; toto zachovat a prohloubit |
| Historie a produktový záměr jsou otevřené | host `restore/applyGroupsProduct`, package `undo/redo`; fontová oprava neřeší TX2/PR |

Tok nyní: immutable font bytes -> jednotlivé znakové obrysy -> globální registr
-> document + bindings save -> SQL resources -> core scene -> Flutter/SVG.
Cílový tok je popsán níže; Ticket Editor/PDF sdílí fontový katalog, ale celý jeho
layout/refaktor není tímto plánem automaticky zahrnut.

## Inspirace z vyspělých systémů

Přebíráme principy, nikoliv jejich celé SDK nebo nový editorový framework:

- [HarfBuzz](https://harfbuzz.github.io/shaping-and-shape-plans.html): shaping
  produkuje glyph IDs, clusters, advances a offsets v kontextu směru/scriptu/jazyka.
  Použít tento model dat a referenční oracle pro shaping testy.
- [Skia](https://skia.org/docs/user/tips/): oddělení shaping a kreslení.
  Naše rozhodnutí: renderer je konzument výsledku typografie, nikoliv další shaper.
- [Fontkit](https://github.com/foliojs/fontkit): existující dependency umí
  `font.layout` s positioned glyph runs a OpenType substitucemi/pozicováním;
  dosavadní `glyphForCodePoint` tyto možnosti nevyužívá.
- [Unicode UAX #9](https://www.unicode.org/reports/tr9/) a
  [UAX #14](https://www.unicode.org/reports/tr14/): bidi a line breaking mají
  vlastní pravidla. Kerning ani dělení řetězce po znacích je nenahrazují.
- [FreeType](https://freetype.org/freetype2/docs/glyphs/glyphs-2.html): malé velikosti
  mají zvláštní problémy rasterizace/hintingu. Shodné vektorové obrysy samy
  nedokazují stejnou čitelnost na displeji. Proto samostatná raster quality brána.

Shodné obrysy/pozice jsou přesná kontraktová podmínka. Bitově stejné pixely
mezi platformními rasterizéry nejsou realistický slib; vizuální kvalita se ověří
samostatně a nesmí se schovat za tuto odlišnost.

## Kanonické vlastnictví

| Význam | Jediný cílový owner | Co nesmí být druhou autoritou |
| --- | --- | --- |
| Dokument, styly, fyzika, placement, povrchy, import | `venue_layout_core` a jeho deklarativní contract metadata | Host properties normalizer nebo klientský alternativní formát |
| Kaskáda, leaf reset, provenance a text roles | core `resolveNodeAppearance` + `collectTextRequests` | Vlastní fallbacky inline editoru, SQL ruční kopie seznamů |
| Font bytes, family/face manifest a oprávněné načtení | existující Ticket font registry/resolver rozšířený o skutečné řezy | Blueprint vlastní katalog nebo náhodný CDN/system fallback |
| Kontextové shaping + řádky + fit + baseline | jediný verzovaný `prepareLayoutText` v existující Edge resource cestě | Fontkit na serveru a jiný nezávislý shaper v každém klientu |
| Vektorová scéna a world transformace | core `compileScene`, stejné zdroje pro Dart a sestavený JS kernel | SVG `<text>` či Flutter `TextPainter` určující finální geometrii labelů |
| Vykreslení scény | tenké Flutter/SVG adaptéry | Dopočítávání typografie, produktů nebo pozic židlí |
| Produkty, spot/ticket identity, revize, receipts | stávající host aggregate a transakční SQL | Renderer, fontová cache nebo historie live rezervací |

Nezavádět CRDT, obecný plugin/command framework, druhý renderer nebo druhý
finanční systém. Nové helpery musí vlastnit skutečný význam, ne jen přeposílat mapy.

### Dokument 2 a záměr stylu

Platí sparse kaskáda původního plánu: `styles.label`, `styles.kinds`,
`node.style`, `table.childStyles.seat`, samostatné `seatingDefaults/seating`,
`surface`, `assembly` a placement union. Missing dědí; Set shodné hodnoty
zůstává explicitní; Unset odstraní jediný leaf; null není reset. Lock nebrání
dědění společného stylu. Žádný runtime čtenář `appearanceOverrides` mimo importer 1.

**Zpřesnění fontové identity proti původnímu návrhu:** cílový label deklaruje
`fontFamilyId`, `weight:400|700`, `italic:boolean`. `fontFamilyId` odkazuje na
immutable versioned family manifest se skutečnými face IDs pro dostupné kombinace.
Manifest nese digest a přesné bytes-hash identity. Výsledný `fontFaceId` je
odvozená dependency, nikoliv druhá editovatelná kopie ve stylu. Display family name
není identita. Přidání/změna manifestu nesmí přepsat význam dříve uloženého ID.

Dosavadní `fontId` označuje bytes konkrétního řezu, proto nesmí tiše nově znamenat
rodinu. Importer jej mapuje na manifest zachovávající původní face. Chybějící
bold/italic se nesimuluje: ovládání ukáže nedostupný řez a nabídne vědomou změnu
rodiny. Nepoužívat nejbližší váhu pod názvem 400/700 bez explicitní produktové volby.
Staré syntetické B/I importer automaticky nahradí dostupným skutečným řezem
stejné rodiny; chybí-li požadovaná kombinace, explicitně uloží nejbližší dostupnou
kombinaci. Chybějící rodinu nahradí Roboto, jinak první rodinou podle jména a ID.
Rozhodnutí i změnu vzhledu zaznamená do receipt bez ručního schvalování.
To není automaticky bezchybná vizuální migrace ani důvod ponechat faux runtime.

Nový Blueprint bez explicitní rodiny používá immutable manifest Roboto ze společného registru, nikoliv fixture font. Výchozí nastavení Ticket editoru se tím nemění.

Dokument 2 navíc obsahuje closed `textPolicy` s uloženým language (výchozí `und`)
a direction (`auto|ltr|rtl`). Potřebné lokální language/direction výjimky jsou
validované listy `style.label` a řídí je stejný resolver. Script se odvozuje
verzovaným Unicode algoritmem. Jazyk ani textové formátování se nesmí odvozovat
z jazyka aktuálního browseru/telefonu, jinak by tentýž dokument měnil geometrii
mezi klienty. Feature policy a Unicode/engine verze jsou připnuté v resource
protocol manifestu; změna vyžaduje nové resource identity a vědomý reprepare.
To je další explicitní rozšíření původního návrhu dokumentu 2.

Nové metadata generují JSON Schema, SQL structural validators/admission tabulky,
text-role projection a digest. Reference/SQL business omezení zůstávají explicitně
SQL. Každý aktivní dnešní klíč má mapování podle původní property matice. Nový
fontFamilyId přepis je výslovná změna této matice; starý fontId zůstává jen importerem.

### Text request a text resources

Core `collectTextRequests` produkuje closed `TextRequest` pro každý skutečně
zobrazený textový role: authored text/label, odvozené počty a symboly. Hidden seat,
couch/bar labels nejsou glyph požadavky. Presety mají vlastní namespace a defaults;
admin preview dependencies jsou oddělené od public projection.

Request obsahuje originální text, role, immutable family manifest a resolved
face ID, velikost, jazyk/směr/feature policy, lineHeight/alignment, lokální label box
a fit/clip policy. Kamera, world poloha, pan/scroll a live zákaznická data tam nepatří.
Stejný lokální request musí mít stejný výsledek nezávisle na klientu a transformaci.

`prepareLayoutText` je jediná resource preparation implementace v existující
`preview-ticket-layout` authorized cestě. Přidat uzavřený layout-text mode s vlastním
`layoutResourceProtocol:2`; současný Ticket `fontProtocol:2` tím automaticky neměnit.
Použije stejné auth/unit/setup admission a byte/quota limity. Přesná verze enginu,
Unicode dat a feature policy je součástí výstupního identity/digestu.

Primární implementační kandidát je již používaný **Fontkit.layout**. Před zmrazením
resources musí vlna 0 prokázat kerning/marks/ligatures/RTL s oracle. Pokud potřebný
corpus nesplní, nahradit tento jediný shaper připnutým HarfBuzz backendem v téže
hranici a doložit jeho běh v Edge runtime. Výběr se uzavře v ADR před vlnou 3;
žádné přepínání mezi dvěma shapery za běhu ani optimistic fallback.

Shaping celého textu neřeší sám bidi a wrap: jediná preparation implementace
použije připnuté Unicode bidi/grapheme/line-break algoritmy a shape konečných
řádků. Nepsat vlastní neověřený Unicode engine. Doložit licence a runtime podporu
zvolených knihoven; nelze-li je spustit, blokuje to tuto vlnu místo tichého zúžení
přijatého jazykového corpus. Emoji/color a variable axes zůstávají explicitně
nepodporované, dokud nemají vlastní kontrakt; nikdy se nenahradí otazníkem.

Výsledné immutable resources obsahují:

- Face manifest, metriky a obrysy indexované **glyph ID**, nikoliv Unicode znakem.
- Shaped text runs s glyph IDs, advances, offsets, cluster map a direction.
- Konečné line positions, baselines, ink/advance bounds, fit scale a clip box.
- Odpovídající request descriptor, request identity, shaper/resource verze a digest.

Clusters mají jednotně definovanou indexaci, doporučeně offsety původního UTF-8
textu. Core poskytne mapování pro UTF-16 nativního inputu. Originální string se
nepřepisuje NFC/NFD nebo CRLF normalizací při Save; případná layout normalizace
musí zachovat mapping a být verzovaná. Bounds musí respektovat combining marks,
ascent/descent, záporné bearings a italic overhang, ne jen součet advances.

Registry přijímá resources jen z autorizované service-role preparation. SQL při
Save porovná uložený canonical request descriptor s požadavkem odvozeným z dokumentu
podle generované projection a vyžaduje ready resources. Nepřijme klientův hash
jako důkaz správného textu. Hash codec má společné fixtures; JSONB rovnost
strukturovaného descriptoru brání závislosti na rozdílném JSON whitespace/pořadí.
SQL neimplementuje shaper. Přidaný resource ref pro cizí text/font/box/revizi odmítne.

Autorský text a prepared text layout jsou oddělené vrstvy. Derived resources
nepatří do geometrické historie ani do portable document JSON. Save envelope
má typed refs na přesné resources konkrétního semantic proposal. Globální glyph
cache může deduplikovat obrysy; reader vrací jen potřebné glyphs/runs. Cache
obsahující celý text je scopeovaná podle occasion/unit/draft, nikoliv veřejný
cross-tenant plaintext registr. Oprávnění k font bytes neznamená přístup k cizím textům.

### Odvozené a dynamické počty bez nové sítě při hold/scroll

Static labels se shapují jako celé texty. Pro badge `×N` a latinské číselné
selection counts definuje core samostatný **numeric role**, nikoliv libovolný text
v rendererech. Preparation vytvoří pro tentýž face ověřené number-symbol resources
pro × a 0-9, s explicitně vypnutými kontextovými substitucemi/kerningem pro tento
omezený role. Core z nich skládá číslo s definovanými advances, alignment a bounds;
Flutter/JS nedopočítávají nic. Jde o záměrně definovanou symbolovou notaci, ne
náhradu shaping authored textů. Pokud má být role locale-shaped, musí přejít na
celé předpřipravené runs pro skutečně potřebné hodnoty; bez tokenové heuristiky.

Ověřit `×0`, `×1`, `×2`, `×10`, `×5000` i maximální smluvně povolený count.
Public hold refresh nesmí vyžadovat font binárky nebo jednu RPC pro každé číslo.
Nepředgenerovat kartézský součin všech čísel a fontů. SQL vyžaduje numeric resources
jen pro skutečně použité role a ověří jejich úplnost včetně ×. Explicitní declared
face existence je samostatná kontrola od konkrétních glyph dependencies.

### Editace a kvalita vykreslení

Inline input, inspector a scene používají tentýž resolved styl, skutečný face
a label box. Nativní input slouží IME, caret a přístupnosti, ne definici uloženého
renderu. Při IME composition nepřepisovat text ani nespouštět history pro každou
mezifázi. Po semantic změně se připraví nový whole-text layout s generation tokenem;
poslední platný preview zůstane zřetelně pending, stale odpověď se nezobrazí jako nový
text. Otestovat caret/selection, diakritiku a přepnutí focusu. Pokud nativní input
vizuálně neodpovídá kanonické scéně, upravit overlay/preview vazbu, nikoliv vytvořit
druhý layout engine nebo vydávat nativní wrap za kanonický. Nedělat nový text editor framework.

Příprava smí být debounce/batch/cacheovaná, Save však potřebuje ready výsledek
přesného captured snapshotu. Offline zobrazení používá již uložené resources.
Nový text při nedostupné preparation může zůstat lokálním pending draftem, nemůže
být označen za uložený/ready. Zavedení této explicitní závislosti pro nové texty
musí ověřit vlna 0 z hlediska odezvy; absence sítě nezničí rozepsaný text.

Kreslit skutečné křivky bez polygonální aproximace a bez B/I shear/stroke náhrad.
Oba adaptéry respektují fill rule, clipping, opacity, paint order a transformace.
Scene quantization zůstává 1/1024 layout unit; pro font-unit data ponechat dostatečnou
přesnost až do konečné transformace, žádné předčasné zaokrouhlení jednotlivých písmen.
Změna fontu nemění fyzickou velikost stolu. Table label má jednotný shrink-to-fit;
text node má definovaný wrap+clip a ponechá celý text v modelu/tooltippu.

Měřit raster kvalitu na DPR 1/2/3 při skutečné výšce textu 10/12/16/24 CSS px,
zoom 0.5/1/2/4 a rotaci 0/30/90 stupňů v platných viewportech. Zvětšení kamery
není důkaz čitelnosti normálního náhledu. Kontrolovat akcenty, kontrast, tenké tahy,
clipping a rozestupy. Chybějící accent/ligatura/glyph je vždy chyba. Při slabé
čitelnosti nejdřív řešit camera/min-size/label policy; pokud outlines požadovanou
kvalitu nesplní, vlna nesmí projít bez aktualizovaného rozhodnutí o společné
raster strategii. Nezavádět potají dva rozdílné textové renderery.

## Doplnění zadání: import vektorové grafiky

Uživatel 2026-10-20 výslovně doplnil import SVG jako běžného objektu plánku.
Normální textový input zůstává editačním rozhraním; jeho celý text se převádí
na hotovou vektorovou geometrii. SVG import používá tentýž cílový path/paint
kontrakt, nikoliv vložené DOM SVG nebo další renderer.

- Kanonický dokument 2 rozšíří closed vektorový objekt. Uloží authoring
  geometrii a barvy, stabilní ID, lokální box a běžnou transformaci uzlu.
  Původní SVG se zachová v privátním `originalSource` záznamu uzlu
  (`format`, přesný text a SHA-256) pro opakovaný import a další editaci.
  Veřejná projekce tento záznam odstraní; render čte pouze převedené cesty.
  Jde o původní importní podklad, nikoliv druhou runtime autoritu.
- Import zachová křivky, pořadí vrstev, barvy, opacity, fill rule a transformace.
  Podporované SVG prvky se převádějí do společných cest, nikoliv bitmapy nebo
  polygonální aproximace textových obrysů. Nepodporovaný prvek se nesmí tiše ztratit.
- Objekt lze vybrat, přesunout, otočit, změnit jeho rozměry, kopírovat, smazat
  a obnovit přes Undo/Redo. Import je jeden historický krok a nezasahuje místa,
  produkty, kapacity, rezervace ani finance.
- Parser/admission odmítne spustitelný obsah, externí závislosti a překročení
  budgetů. Text uvnitř SVG vyžaduje tentýž registrovaný face a whole-text
  preparation jako text plánku; systémový font nesmí být skrytý fallback.
- Vlny 2/3 rozšíří shared metadata, importer, resolver a scénu; vlna 5 uloží
  tentýž semantic proposal; vlny 6/7 ověří skutečný SVG import, save/read/copy,
  Flutter/extracted JS path paritu a distribuční artefakty.
- Uživatel následně výslovně potvrdil bitmapy JPEG/PNG na plátně. Zachovat
  existující upload/decode/verified-manifest cestu a pozadí; přidat i samostatný
  image objekt se stabilním ID, rozměry, crop a běžnou transformací. Bitmapu
  nepřevádět na vektory. SVG naopak nesmí potichu projít rasterizací.
- V4: JPEG i PNG -> vložení -> přesun/resize/rotace/crop -> save/reopen/copy,
  plus zachování stávajícího registrovaného pozadí. Byte hash a manifest musí
  zůstat ověřené; externí URL není nová autorita obsahu.
- Nová acceptance V1: vícebarevné SVG s kubickými/kvadratickými křivkami,
  viewBox, skupinovými transformacemi a průhledností zachová scene paths/paint.
  V2: import -> transformace -> save -> reopen -> copy -> undo/redo.
  V3: malformed/unsupported SVG a překročení limitu odmítnout atomicky bez
  částečného objektu nebo změny historie.

Upřesnění uživatele 2026-10-20: vytvoření akce a následná editace plánku
používají tutéž editorovou komponentu, včetně fontů, přípravy textu a vkládání
SVG/bitmap. Odlišný host řeší pouze persistence, scope a obchodní operace.

## Business a transakční invarianty z původního plánu

- Jedna aggregate revize zahrnuje geometrii i host bindings; spots.product a SQL
  zůstávají finanční pravdou. Zachovat node/spot/ticket identity a existující holds.
- `productAssignmentMode:inherit|override` je uložený záměr. Ruční A zůstane
  override při defaultu A a cyklu A -> B -> A. FreeOnly nemění přeskočený mode.
- Explicit attach má deklarovaný cílový business efekt; detach/reparent/import
  samy nezmění členství nebo produkt. Chybějící default žádá explicitní volbu.
- Core edit a host checkpoint mají jediný prepare/validate/commit. Undo/redo
  projdou dnešními live guardy včetně produktu/mode/členství. Reject ponechá doc,
  host, selection i oba history stacky beze změny. Capture/restore samo nestačí.
- Jeden drag/brush/slider/rename gesture je jeden undo krok. Resources, kamera,
  hover, live status a síťový pending nejsou historický business checkpoint.
- Save zachytí immutable proposal ještě před resource preparation. Výsledek je
  ready/superseded/failure. Pozdější editace zůstanou dirty po odpovědi na starší save.
  Ambiguous retry používá přesné stejné bytes + command ID, bez nové přípravy do
  zmrazeného požadavku. Receipt replay předchází admission nového kontraktu.
- Skutečné UTF-8 limity zahrnují doc+bindings+refs a result resources, nikoliv
  jen samostatný document. Cachované textové obrysy nejsou důvod zvýšit limity naslepo.

## Implementační vlny

### 0. Uzavřít rozhodnutí o typografii a zmrazit vstupy

**Změna:** inventář aktuálních diffů, artefaktů a owning suites; lokální proof
`font.layout` nad přesnými registered bytes, porovnání s HarfBuzz oracle na
corpus T1-T5 níže. Ověřit dostupnost skutečných B/I souborů z generátoru katalogu,
Unicode knihoven, Edge runtime a batch odezvu přípravy. Výsledkem je krátký ADR
přímo v tomto dokumentu nebo odkazované ADR s přesnými verzemi a digesty.

**Odstranění/migrace:** nic produkčního; zahodit neúspěšný engine kandidát,
nezaložit runtime přepínač. Nezavádět FFI/WASM dependency do obou klientů, když
cílová server preparation a sdílené resources splní požadavek.

**Selhání:** nevyhovující engine nebo chybějící font variant je konkrétní
implementační blocker této vlny, ne souhlas s faux B/I nebo rune layoutem.
**Ověření/exit:** spuštěný shaping/face/latency proof na disposable prostředí,
jediný vybraný engine, žádný nevyřešený zásadní runtime předpoklad před resource freeze.

### 1. Dovřít současné SQL admission mezery

**Změna:** `database/functions/blueprint/{resources,validation}.sql`, owning
`layout_integration_test.sql`. Přidat mask type/key/uniqueness testy a derived
badge ×N readiness; nejprve regrese na full save i validační hranici. Malformed
style/font/glyph musí atomicky odmítnout revizi/bindings. Zahrnout setup/copy.

**Odstranění/migrace:** dokončit rozpracovanou forward migraci z canonical SQL;
nejprve ověřit, že nebyla aplikována mimo disposable DB. Pokud již byla publikována,
nepřepisovat ji, přidat další forward. Dočasná schema-1 oprava se v cílovém stavu
přesune do generovaného kontraktu a importer hranice, ne do trvalého druhého ownera.

**Selhání:** stejný invalid corpus má fail v SQL i core/kernel; žádný zápis resource
není důkaz úspěšného aggregate save. **Exit:** obě nově nalezené reprodukce mají
opačné regression očekávání, včetně actual save/read/scene, ne pouze source review.

### 2. Kontrakt 2, resolver, family identity a importer

**Změna:** package `model.dart`, contract metadata, `tool/export_contract.dart`,
scene a inspector callery; nové uzavřené records podle cíle. Metadata generují
schema, SQL strukturální pravidla a text roles. Jeden resolver s provenance
obslouží scene/inline/presets/collector. Host DTO a capability envelope rozliší
read/write schema, schema digest a text resource protocol.

**Odstranění/migrace:** pure deterministický importer 1 -> 2 zachová IDs, wrappery,
transformace a source payload. Legacy appearance mask, fontStyle, fontId s původním
významem a faux typography přečte pouze importer. Ambiguous product/surface/style
má report; žádný autosnap offgrid polygonu ani odhad mode podle rovnosti.

**Selhání:** unknown future schema, null/unknown key, cycles, neplatné grid/face
reference fail closed; žádný writer downgrade. **Ověření:** ST1-ST3, CT1-CT2,
MG1-MG2; corpus valid/invalid přes pure core, schema, SQL a skutečný kernel.
**Exit:** cílový document 2 round-trip, mechanické pokrytí všech původních klíčů,
jediná stylová kaskáda a přesně vyjmenované importer-only legacy reads.

### 3. Skutečné font faces, whole-text preparation a resource protocol 2

**Změna:** `automation/generate_ticket_font_catalog.mjs`, existing registry/seeds,
`ticketFonts.ts`, nový focused text preparation helper u `layoutFontOutline.ts`,
`preview-ticket-layout/{handler,index}.ts`, SQL resources registration/read/save,
core scene a obě rendering adaptéry. Zachovat původní immutable face IDs; přidat
append-only family manifests s reálnými regular/bold/italic/bold-italic odkazy.
Žádné automatické přecenění, změna stolu nebo resource v portable doc.

**Odstranění/migrace:** blueprint rune-by-rune `_glyphs`, jeho vlastní wrap,
shear a faux-bold stroke nahrazeny konsumací připraveného text layoutu. Stará
`layoutFontOutline` znaková cesta nesmí být dosažitelná Blueprint writery/readery;
Ticket-only caller, pokud existuje, se výslovně oddělí a doloží scoped rg, nikoliv
zachová jako Blueprint fallback. Registry nevrací celé globální outlines.

**Selhání:** missing face, glyph/.notdef, invalid cluster, metric/hash conflict,
resource budget a unsupported format -> typovaná chyba; žádné '?'/system fallback.
Authorized registration oddělená od aggregate commit; neúspěšná cache příprava
nemění doc/bindings. Cache cleanup je explicitní maintenance, ne doménový trigger.

**Ověření:** T1-T8, IO1/IO4; oba klienti vykreslí totožné positioned glyph paths
z SQL readbacku. Numeric badge nepotřebuje RPC při availability refresh.
**Exit:** whole-text shaping a skutečné B/I jsou jedinou Blueprint runtime cestou;
nové font family ani size nedělají fyzické změny, source text zůstává editovatelný.

### 4. Fyzika, transakce, historie a produktový záměr

**Změna:** původní vlny 3/4: `operations.dart`, grid/seating/surface helpers,
`venue_layout_controller.dart`, host controller/DTO/save/setup/copy a SQL binding
schema. Placement automatic/sidePinned/free, uložený integer grid + module,
child seat style, rigid move bez reflow. Jediný prepare celého aggregate pro nové
příkazy i historii. Přidat productAssignmentMode a konzervativní backfill override.

**Odstranění/migrace:** majority/median seating inference, dvojí manual,
typography freeze, post-commit `_geometryChanged` jako business owner,
rovnost ID pro inheritance a nehlídaný host checkpoint restore. Column expand
před novými writery; historická nejasnost má receipt, ne automatický inherit.

**Selhání:** live změna během drag/undo/redo chrání celý aggregate; bezpečný návrat
k aktuálnímu server produktu zůstane možný. Reject neodebere history položku.
**Ověření:** PH1-PH4, TX1-TX2, PR1-PR2, existing hold/finance/atomic tests.
**Exit:** explicitní fyzikální/obchodní efekty a žádná raw apply cesta obcházející guardy.

### 5. Async semantic save a projekce

**Změna:** `_save/_prepareFonts`, controller/saver a text resource provider
přijmou captured snapshot. Finální příprava je ready/superseded/failure, token
chrání všechny await hranice. Editace při preparation/response nepřepíše nové
změny; receipt replay vyžádá současnou head revizi bez ztráty draftu. Public/admin
projekce používají tutéž scénu s jen potřebnými zdroji; preset knihovna je admin-only.

**Odstranění/migrace:** skryté normalizace při Save, mutable provider.characters
jako vstup dvou souběžných požadavků, globální celé registry v response, zdvojený
host collector a ručně udržovaná SQL font priorita. Zůstane generovaná projection
společných text request pravidel a explicitní SQL auth/reference omezení.

**Selhání:** font A/B dokončené obráceně, IME+rename při čekání, ambiguous retry,
revision conflict a size limit zachovají draft a jediný frozen intent. No-network
pending nelze označit za Saved. **Ověření:** IO1-IO4 + T6/T8.
**Exit:** stejný uložený semantic proposal vždy odkazuje na stejné text resources;
žádný stale commit ani závislost public renderu na stahování font binárek.

### 6. Migrační corpus, přesná parita, raster kvalita a výkon

**Změna:** jeden opakovatelný testový tok ve stávajících owning suites získá nové
SQL admin/public/setup/copy readbacky na disposable DB a pošle tytéž vstupy do
Dart core i **extrahovaného npm artefaktu**. Uložený JSON je fixture, ne náhrada
pravidelného integračního regenerování. Drifty emitují diff text request, face,
glyph ID, transformace, path, selection unit; ne pouze screenshot a label B/C.

**Odstranění/migrace:** porovnání neprázdných paths jako údajný parity gate.
Pure importer corpus obsahuje offgrid, ambiguous mode, faux B/I a missing faces;
receipt má source hash+revision a target digest. Produkční zdroj se čte teprve
v samostatně autorizovaném inventáři, nikdy není testovacím prostředím.

**Selhání:** změny typography mají explicitní automatické rozhodnutí v receipt.
Běžné nejasnosti nečekají na ruční kontrolu: zachovat identity, aktuální produkty
a materializované polohy; nejistý produktový záměr uložit jako vlastní přiřazení.
Offgrid geometrii převést přesným modulem, mimo limity zachovat obálku a rozhodnutí
zaznamenat. Stale revision/hash, neplatný zdroj nebo prázdný fontový registr
zastaví převod; nesmí vzniknout fallback writer.

**Ověření:** MG/UI/PF + T1-T8. Headless skutečný Flutter web i JS SVG viewer:
save -> close -> reopen -> copy, bez navigace uživatelova okna. Desktop/native
Flutter text paint ověřit owning widget/raster testy. Drag/scroll a IME scénáře,
317-node/5000-seat/max-valid fixtures, cold/warm preparation, payload bytes,
p50/p95 na stejném stroji. Nulové full scene compile při panel scrollu,
nulové seating reflow při rigid move; p95 zhoršení >10 % vyšetřit a doložit.
Přípravu textu měřit zvlášť od paint; síťové čekání neskrývat do cache-hit čísel.
**Exit:** přesná strukturální parita, doložená raster kvalita a celé UI journeys;
žádný úzký passing corpus vydávaný za kompletní výsledek.

### 7. Distribuce a úplné odstranění starých runtime cest

**Změna:** package exporter/kernel/manifest, host piny, vendor integrity, Dart
consumer a docs popisují tentýž final source digest a protokoly. Vytvořit nové
immutable artefakty, nic nepřepsat pod již použitým hashem/verzí. Spustit skutečný
archive gate. Nepřidávat clean package commit jako skrytou podmínku této session;
commit/push/publish vyžadují samostatnou autoritu.

**Odstranění/migrace:** deletion ledger níže a staré testy/config/runtime verze;
starý soubor může zůstat pouze pojmenovaným import/audit vstupem. README nesmí
slibovat legacy fallback, který runtime už nesmí poskytovat.

**Selhání:** reader/resource podpora musí předcházet writeru. Starý writer odmítnut
nad schématem 2 i s platnou aggregate revision. Receipt historického příkazu se
vrátí před admission. Po prvním uloženém dokumentu 2 rollback nesmí obnovit
schema-1-only writer. **Exit:** extrahované archivy fungují a absence starých
aktivních cest je prokázaná, provozní kroky přesně oddělené od lokálního dokončení.

## Deletion ledger

| Dosavadní cesta | Cílová akce | Důkaz nepřítomnosti/hranice |
| --- | --- | --- |
| appearance + appearanceOverrides + defaultTextStyle jako více stylových autorit | Jen importer 1, runtime sparse styles/resolver | Scoped rg deklarací a callerů + ST/CT corpus |
| Host blueprintLayoutFontCharacters a vlastní SQL font precedence | Přesměrovat na core request contract/generovanou SQL projection, pak smazat duplicity | Owning save/read/derived badge testy a žádný nezávislý collector |
| Ruční SQL appearance key/type/range whitelist | Generované metadata z core | Export --check + stejný invalid corpus |
| Blueprint glyphForCodePoint + per-rune wrap | Whole-text preparation/runs a numeric role | Kerning/marks/ligatures tests + žádný blueprint caller starého rendereru |
| Faux-bold stroke, italic shear, fontStyle alias | Skutečné face IDs; alias jen importer | All 4 face fixtures + scoped source/runtime check |
| Jeden normal font na rodinu v generátoru | Family manifest se všemi dostupnými skutečnými 400/700 normal/italic variantami | Generátor a seed diff, exact bytes hashes, missing-variant cases |
| Globální layout_outline dump / Unicode-key glyph identity | Subset glyph-ID/text-layout resources; historická cache pouze bounded retention | Jiný dokument nezvětší read payload testovaného dokumentu |
| Klientské nezávislé text defaults/measurement | Core resolver + canonical prepared layout | Inline/preview/scene/request equality |
| Dvojí manual, odvozovaný grid module, majority/median seating | Typed placement/surface/seating | PH corpus, stable IDs, load bez reflow |
| productId equality inheritance | productAssignmentMode | A -> B -> A a freeOnly/protected |
| Raw history host restore a post-commit business reconciliation | Prepare/validate/commit celého aggregate | TX2 + odmítnutá historie bez mutací |
| Save normalization/stale void success/mutable resource input | Captured proposal a explicit preparation result | IO race/retry tests |
| Neprázdná cesta jako parity důkaz | Kvantizovaná exact scene/text-layout parity + zvlášť raster testy | Skutečně regenerovaný SQL corpus v extracted archive lane |
| Zastaralé vendor verze a README claims | Jediný aktivní pin; immutable starý artefakt jen označený audit evidence, jinak odstranit | Dependency graph/manifest + archive gate |

## Acceptance a owning kontroly

Původní acceptance beze ztráty rozsahu:

| Původní skupina | Nová vlna |
| --- | --- |
| ST1-ST3, CT1-CT2 | 1-3 |
| PH1-PH4 | 4 |
| TX1-TX2, PR1-PR2 | 4-5 |
| IO1-IO4 | 1, 3, 5 |
| MG1-MG2 | 2, 6 |
| UI a PF | 3-7 |

Nová typografická matice:

| ID | Povinný důkaz |
| --- | --- |
| T1 | AV/To/Wa kerning, office/ffi/fi ligatury a features on/off na fontu s danými tabulkami; glyph IDs/advances proti připnutému oracle, ne jen počet glyphů |
| T2 | České/slovenské/polské/německé věty, € a ×; NFC/NFD combining accents, mark offsets, záporný bearing a žádný clipping diakritiky |
| T3 | Skutečné regular/bold/italic/bold-italic stejné rodiny, combined B+I, missing face a přepnutí rodiny; žádný faux tvar nebo tichý fallback |
| T4 | RTL a mixed Arabic/Latin/čísla s validními registered fonty, clusters, bidi, nové řádky a reshaping u zalomení; kontrolní Indic fixture před obecným tvrzením o shaping podpoře |
| T5 | Table shrink-to-fit, text wrap/clip, baseline/lineHeight, mezery/NBSP, prázdný text, dlouhý token, CRLF; styling nemění fyzický objekt |
| T6 | Stejný resolved face/style/request v inspectoru, inline edit, IME, preview, scene, font collector; out-of-order výsledky nikdy nepřepíší novější text |
| T7 | Duplicate/unknown/non-string masks ve vstupním formátu, malformed style, unsupported face, cizí/stale text resource descriptor a chybějící ×/digit odmítne SQL/core/kernel atomicky podle vlastní verze |
| T8 | Čerstvý SQL save/read/admin/public/setup/copy corpus: exact quantized paths/positions/bounds/clip/paint order/selection units na Dart a extracted JS, plus samostatná raster matrix DPR/zoom/rotace a bounded payload/performance |

Kontroly rozšířit v existujících vlastnících suites. Nový test root jen pokud
doménově nový seam nemá vlastníka; nepřidávat paralelní test framework.

- Package pure core: `fvm dart test` z `packages/venue_layout_core`, cíleně
  appearance/scene/transport a nové text contract cases v owning lane.
- Package Flutter: příslušné history/table/grid/inline/cache widget suites,
  vždy `fvm flutter test --concurrency=1 ...`; názvy zjistit scoped `rg --files`.
- Host: `fvm flutter test --concurrency=1 test/sessions/shared_czech_test.dart`
  s owning group filtry. `_cases.dart` samy nejsou test roots. Výpis musí
  obsahovat skutečně spuštěné testy, ne nula testů.
- SQL: `DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:59522/postgres' node web_client/scripts/run_db_tests.js database/tests/blueprint/layout_integration_test.sql database/tests/blueprint/copy_setup_test.sql`.
  Psql-parametrické `canonical_layout_cutover_test.sql` a
  `setup_draft_integration_test.sql` pouštět přes `psql -v fixture_form=...`,
  ne Node runnerem. Ověřit marker a existující syntetickou fixture před použitím.
- Deno: owning `_shared/layoutFontOutline_test.ts`, nové text helper cases,
  `preview-ticket-layout/preview_test.ts` a font registry tests s minimálními
  potřebnými allow permissions podle aktuální CONTRIBUTING/importů. Připnout
  dependency/engine verze; plánování je samo nespouští.
- Web: `node --test tests/components/blueprint_*.test.js` z `web_client`;
  package extracted consumer přes existující `tool/archive_check.sh`, rozšířený
  o skutečný font corpus a parity proof. Neobcházet CI gate přímým Playwright skriptem.
- Performance: existující `tool/benchmark_layout_scene_cache.dart`,
  `tool/drag_overlap_benchmark.dart` a izolovaný browser trace. Není to náhrada
  raster quality ani browser FPS tvrzení.

Před jakýmkoliv Flutter taskem ověřit workstation slot; maximálně jeden task
včetně testů/buildů/analyzátorů/serverů, testy `--concurrency=1`. Nezastavovat cizí
proces. Browser kontroly izolovaně/headless bez zásahu do uživatelova okna.
V plánovací session se nové testy ani buildy nespouštějí jen pro napsání plánu.

## Rollout, převod a rollback

Lokální implementace zahrnuje canonical SQL a forward migrace, import copies,
fixtures, archive consumers a dokumentaci. Nezahrnuje produkční zápis nebo rollout.
Konkrétní tenant není zadán. Před samostatnou produkční etapou vyřešit aktivaci,
read-only inventory a existující schema/resource verze podle backend skillu.

Pořadí: expand registry/schema -> readers a resource protocol support -> dry-run
konverze s receipts a automatickými rozhodnutími -> koordinované
read-only/write-window a writer cutover -> contraction. Převod porovnává expected
revision **i source hash**, dokument a binding modes atomicky; historie receipts
se nemaže. Neměnit spot/ticket identitu, finance ani holds kvůli fontům.

Po prvním zápisu nového kontraktu se rollback aplikace opírá o kompatibilní reader
nebo read-only editor. Nevracet schema-1-only writer, starý shaper ani faux B/I
jako skrytý fallback. Obnova starých dat je samostatná operace, ne běžný rollback.

## Předpoklady, rozhodovací brány a zbytková rizika

- **Potvrzeno:** současné konkrétní chyby a souborové ownery uvedené výše;
  nejde o dnešní inventuru produkčních dat.
- **Rozhodnutí:** kontextové whole-text shaping, jeden text layout owner,
  skutečné face IDs, sdílené prepared vector resources a tenké rendering adaptéry.
  Přesná pixelová identita různých rasterizérů není acceptance cíl.
- **Rozhodnutí:** nový plán superseduje staré pořadí a odklad shaping/faces;
  žádná původní doménová acceptance nezmizela.
- **Ověřit ve vlně 0:** Fontkit versus oracle, Unicode algoritmy, Edge kompatibilita,
  dostupnost variant a odezva služby. Konkrétní verze/latency čísla nejsou nyní
  naměřená a plán je nevydává za fakta.
- **Ověřit při importu:** vzhled původního faux B/I, offgrid plochy, neznámý
  product intent a chybějící skutečný řez vyžadují report a přezkum. Ztracený
  historický záměr nejde obnovit. Neprovádět automatickou změnu vzhledu pod PASS.
- **Provozní blocker:** tenant, write-window, produkční inventory/převod a rollout
  zatím nemají samostatné zadání. Neblokují kód a disposable důkazy.
- **Zbytkové riziko:** malé texty se mohou rasterizovat odlišně. Neprošlá quality
  brána je skutečný blocker vlny 6; vyžaduje doloženou úpravu návrhu, ne přejmenování
  testu nebo povolení rozmazaného výsledku. Nezaručovat všechna písma z katalogu.

## Definice dokončení

- Jeden interní model 2, appearance resolver, text request contract a text layout owner.
- Authored text se shapuje v kontextu; numerická symbolová role je explicitně omezená.
- Skutečné reálné řezy a žádný Blueprint faux/rune layout runtime fallback.
- Core/schema/SQL/distribuovaný kernel mají shodnou admission a scénu na čerstvém corpus.
- Text quality T1-T8 a původní ST/CT/PH/TX/PR/IO/MG/UI/PF mají konkrétní výsledky.
- Save/read/copy zachová styling, text, font identity, obchodní i geometrické identity.
- Undo/redo, explicit attach a async Save nemají nehlídanou vedlejší cestu.
- Deletion ledger je uzavřený; importer zůstává jen pojmenovanou vstupní hranicí.
- Artefakty, piny a manifesty jsou prokazatelně z týchž finálních zdrojů.
- Neprovedené provozní kroky jsou výslovně oddělené od lokálního dokončení.

Upřesnění uživatele 2026-10-20: migrační nejasnosti řešit automaticky podle výše uvedených deterministických pravidel; nevyžadovat ruční schvalování běžných rozhodnutí.

Upřesnění uživatele: následný architektonický audit posoudí také čitelnost
příkazů pro budoucí MCP. MCP má použít stejný validovaný command owner jako editor.
Uložení kompletní scény je případná odvozená cache dokumentu/revize, nikoliv
náhrada upravitelného dokumentu nebo další zdroj pravdy. Audit následuje až po
ověřeném dokončení současné implementace.
