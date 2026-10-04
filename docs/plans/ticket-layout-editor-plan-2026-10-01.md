# Vizuální editor rozložení vstupenky

Datum: 2026-10-01\
Stav: Implementace - upraveno podle následného zadání\
Výchozí bod: `main`, `e7d798cdc`, včetně existujících necommitnutých změn\
Ověřování implementace: `standard` - změna sdíleného PDF výstupu, datového kontraktu a autorizovaného náhledu. Při plánování nebyly spuštěny testy ani dotčena produkce.

## Upřesnění při realizaci

Uživatel výslovně požaduje lokální živou editaci nad bitmapou a zachování
existujících funkcí generování vstupenek. Samostatný nový PDF renderer se
nezavádí: `generateTicketImage` a `generateNamedTicketImage` dostanou volitelný
layout; `ticketGeneration.ts` pouze připraví vstupy a sjednotí dispatch. PDF se
volá výhradně explicitním tlačítkem. Barvy textu i QR patří do inspectoru
vybraného prvku v editoru; samostatná barevná pole occasion settings se ruší.
Pro QR zůstává bílý ochranný podklad a ověřená tmavá paleta. Nové návrhy používají
stejné existující Futura PT Book bytes lokálně i na serveru; historické větve
zachovávají své původní fonty. SQL, Dart a TS používají minimum QR 60 pt,
minimum písma 6 pt a nejvýše 12 řádků. Na stejné fixtures navazují testy.

## 1. Výsledek a rozsah

V Nastavení události > Vstupenka bude náhled a tlačítko **Upravit rozložení**. Otevře editor, ve kterém správce posune QR a jednotlivé údaje, změní jejich velikost a zapne nebo skryje volitelné informace. Celou pracovní plochu může přirozeně posouvat a přibližovat. Změny se promítnou do PDF při stažení i odeslání e-mailem.

První dokončená verze zahrnuje oba současné typy `wide` a `named`, vlastní pozadí u `wide`, živý grafický náhled celé vstupenky, přímou manipulaci včetně velikosti písma, undo/redo, volitelný kontrolní PDF náhled a bezpečné uložení. Dodávat postupně: nejdříve jeden průchozí scénář `wide` s QR a kódem, potom ostatní pole a `named`, nakonec dokončení interakcí. Samotné dokončení prvního scénáře není dokončením zadání.

Rozsah nezahrnuje obecný grafický editor, libovolné HTML, vlastní skripty, nahrávání fontů, otáčení prvků, více stran, více vstupenek na A4, změny skenování, šablony podle produktu ani hromadné přegenerování již odeslaných dokumentů. Pozdější šablony pro produkty mají použít stejný kontrakt, nejsou důvodem přidávat nyní další úroveň dědičnosti.

### Zásada jednoduchosti po upřesnění zadání

Kvalitu posuzovat podle přesnosti výsledného PDF, čitelnosti QR a plynulého ovládání. Nejkratší uživatelská cesta je otevřít vstupenku, vybrat prvek, přesunout ho nebo změnit velikost přímo na plátně a uložit; PDF lze zvlášť otevřít pro kontrolu. Pokročilé vlastnosti zobrazovat až podle výběru; základní obrazovku nezahltit.

První verze má plochý seznam předem známých polí, jeden controller editoru a jednu serverovou cestu vykreslení vlastního layoutu. Bez systému skupin, pluginů, obecného constraint solveru, další databázové tabulky nebo samostatného ukládacího endpointu. Použít stávající knihovnu `pdf-lib` a stávající occasion save. PDF se generuje pouze explicitním tlačítkem Náhled PDF. Otevření editoru, pohyb prvku ani potvrzení návrhu PDF negenerují. Zpětná kompatibilita, oprávnění a ochrana před ztrátou změn zůstávají součástí kvality.

## 2. Co je ověřeno v repozitáři

| Fakt a evidence | Dopad na návrh |
|---|---|
| `lib/components/features/ticket_feature.dart`: `TicketFeature` ukládá typ, barvy, obrázek a přepínače. `buildFormField` dnes dovoluje obrázek a barvy pouze u `wide`. | Rozšířit tuto feature o layout; nepřidávat druhé konkurenční nastavení vstupenky. Vyčlenit složitější UI ze současného `StatefulBuilder`. |
| `occasion_settings/occasion_settings_tab.dart`: `_performHtmlSave` uloží formulář a volá `DbOccasions.updateOccasion`. Editace nastavení je řízena `RightsService.isUnitEditor()`. | Editor vrací pracovní kopii do nadřazeného formuláře. Finální uložení zůstává v nastavení události. |
| `occasion/db_occasions.dart`: `updateOccasion` používá buď `_commands.save`, nebo `update_occasion_203`. `occasion_commands.dart` již posílá `p_expected_version` a používá command transport. | Neobcházet command receipt, synchronizaci a existující ochranu souběhu novým přímým UPDATE. |
| `database/functions/others/update_occasion.sql`: `update_occasion_internal_v1` nahrazuje celé `features`; kontroluje editora jednotky. | Starý klient neumí nové pole serializovat. Backend musí layout zachovat při běžném uložení bez explicitní změny layoutu. |
| `supabase/migrations/20260813160000_allow_unit_editor_occasion_save.sql` a `20260813163000_allow_unit_editor_occasion_domain_save.sql` definují navazující command hranice. | Při úpravě SQL sledovat i command cestu, nejen historický wrapper. |
| `_shared/generateTicket.ts`: `generateTicketImage` vytváří PDF A4, pozadí škáluje na 90 % šířky; QR má `240 * scale`, odstup zprava `150 * scale`, zdola `140 * scale`. | Souřadnice jsou dnes navázané na pixely pozadí, nikoli na editovatelný model. Zoom obrazovky nesmí změnit PDF geometrii. |
| Stejný generátor tiskne kód pod QR a blok Stůl, Večeře, Poznámka, Cena. Chybějící položky se vynechají a další řádky se posunou. Načtené taxi se nekreslí. | Zachovat historické skládání řádků ve starém rendereru. Vlastní layout má samostatná pole s pevnými pozicemi. Taxi nezařazovat automaticky. |
| `_shared/generateNamedTicket.ts`: samostatný PDF generátor s logem, názvem, datem/místem, jménem, QR, kódem a patičkou. | Druhý počáteční preset; nevynutit převod všech existujících vstupenek při nasazení editoru. |
| `download-ticket/index.ts` a `send-tickets/index.ts` samostatně vybírají renderer. Download předává pro named `{}`, e-mail `order.data`. | Sjednotit výběr rendereru a vstupní data. Náhled nesmí zakrýt rozdíl v údajích mezi downloadem a e-mailem. |
| `database/functions/eshop/get_ticket_details_for_generating.sql` vrací ticket a occasion, nikoli plný kontext jména objednávky. | Doplnit minimální potřebný datový kontext a explicitně stanovit význam pole se jménem. |
| `blueprint/README.md`, `views/blueprint_editor_tab.dart`: plátno obsluhuje `venue_seat_picker`, controller a viewer. | Převzít srozumitelné ovládání, panel vlastností a práci s plochou. Nereprezentovat texty vstupenky jako sedadla a nepřebírat rezervace ani SQL blueprintu. |
| `occasion/occasion_media_copier.dart` kopíruje `TicketFeature.ticketBackground`; SQL `duplicate_occasion` kopíruje features. | Zachovat jednu referenci na pozadí, otestovat kopii geometrie i vazbu na nový obrázek. |
| `docs/backend/edge_functions.md`, runtime writer policy a `supabase/functions/test-coverage.json` vyžadují evidenci a testy nových entrypointů. | Náhledový endpoint zahrnout do runtime, coverage a balení, ne pouze založit soubor. |

Současná cesta: nastavení -> `TicketFeature.toJson` -> occasion features -> command/RPC -> při generování ticket feature + zdroje -> jeden ze dvou generátorů -> PDF ke stažení nebo příloha. Cílem je do této cesty vložit explicitní layout a společné rozhodnutí o rendereru.

Pracovní strom při průzkumu obsahoval uživatelské změny blueprintu, formulářů, prototypů a dalších plánů. Implementace je musí zachovat; nesmí je resetovat nebo zahrnout do vlastního commitu bez určení jejich vlastnictví.

## 3. Chování editoru

### Vstup a rozložení obrazovky

- V kartě Vstupenka ponechat typ a funkční přepínače, přidat malý náhled a **Upravit rozložení**. Zobrazit, zda jde o výchozí nebo vlastní rozložení.
- Editor jako plnohodnotná obrazovka/fullscreen dialog, aby gesta nekolidovala se scrollem nastavení. Desktop: seznam prvků vlevo, plátno uprostřed, vlastnosti vpravo; užší displej: plátno a rozbalovací spodní panel.
- Horní lišta: Zpět/Znovu, nástroj Výběr/Posun, zoom -, procento, zoom +, Přizpůsobit, Náhled PDF, Použít, Zrušit.
- Uprostřed zobrazit obrys skutečné PDF stránky a rozlišit oblast vstupenky od okolní A4. Výchozí fit míří na vstupenku; přepínač zobrazí celou stránku. Výstupní velikosti zůstávají stejné jako dnes.
- Hlavní ovládání je přímo na plátně: přesun tažením a změna velikosti úchyty. Kontextová lišta nabízí velikost písma posuvníkem / tlačítky - a +, zarovnání, barvu a viditelnost. Souřadnice se odvozují z polohy prvku; formulář X/Y není nutný ani součást základního workflow. U QR zachovat čtverec; obsah kódu se neupravuje.

### Živý náhled je vlastní editor

Plátno průběžně zobrazuje pozadí, skutečně vykreslený ukázkový QR a všechna zapnutá textová pole najednou. Výchozí přizpůsobení ukáže celou vstupenku; detaily lze přiblížit. Texty nejsou prázdné obdélníky ani drátěný model. Při přesunu nebo změně velikosti je výsledek vidět ihned během gesta, bez čekání na server nebo uvolnění myši.

Vizuálně jde o bitmapový/obrazový náhled na obrazovce. Implementovat jej přímo Flutter canvasem a vykreslenými vrstvami nad obrázkem pozadí, nikoli opakovaným generováním PDF či serverových PNG. Není potřeba při každém pohybu vyrábět nový soubor bitmapy. QR a texty lokálně překreslovat ostře pro aktuální zoom. Model polohy a velikosti je společný s PDF výstupem.

Rozlišit zoom pohledu a změnu velikosti obsahu: zoom zvětší celou pracovní plochu pouze na obrazovce, úchyt QR změní rozměr QR na výsledné vstupence a úchyt textu změní i jeho písmo. Uživatel všechny tři operace pozná podle výběru a ovládacích prvků.

### Gesta a přesnost

| Akce | Chování |
|---|---|
| Klik/tap na prvek | Výběr, obrys a úchyty. I nepřítomný údaj lze vybrat v seznamu prvků. |
| Tažení vybraného prvku | Posun v souřadnicích dokumentu, nezávislý na zoomu. Klikání do vlastností neposouvá plátno. |
| Rohový úchyt QR / loga | Plynulé zvětšení/zmenšení se zachováním poměru stran, výsledek je vidět během tažení. |
| Rohový úchyt textu | Proporcionálně mění box i velikost písma. Živé přepočítání textu během tažení; kotva protějšího rohu zůstává na místě. |
| Boční úchyt textu | Mění šířku boxu a zalomení, ponechá zvolenou velikost písma. Lišta - / + nebo posuvník mění samotné písmo. |
| Tažení prázdné plochy / nástroj Posun | Posun pohledu. Mezerník + tažení a prostřední tlačítko fungují jako dočasný posun. |
| Kolečko myši nad plátnem | Zoom kolem kurzoru. Trackpad: dvouprstý posun a pinch zoom; nepřepínat každé scroll gesto na zoom. |
| Dotyk | Tap vybírá, tažení vybraného prvku ho přesouvá, dva prsty posouvají/zoomují. Při druhém prstu zrušit rozpracovaný drag a přejít na navigaci bez skoku prvku. |
| Šipky / Shift + šipky | Jemný/větší posun vybraného prvku jako doplněk přetahování. Klávesové zkratky neodchytávat při psaní v inputu. |
| Fit / 100 % | Fit přepočítat po změně velikosti viewportu, zachovat rozpracovanou editaci. 100 % je logické měřítko editoru, ne slib fyzické velikosti monitoru. |
| Undo / redo | Jeden drag je jeden krok historie. Zoom, výběr a posun pohledu nejsou změny dokumentu. |

Rozumný rozsah zoomu například 25-800 %, s fit i pro menší viewport. Viditelné úchyty mají stabilní obrazovkovou velikost. Jemné přichycení k okrajům/středu vstupenky a k hranám ostatních prvků má toleranci v obrazovkových pixelech; modifikátor jej dočasně vypne. Mřížka je volitelná a netiskne se.

Vybrané prvky nesmějí být při uložení mimo tisknutelnou oblast. Drag i resize vizuálně omezit na plochu; omezení a přetečení zobrazit přímo u prvku. Uzamčení prvku brání nechtěnému posunu, neznamená oprávnění k datům.

### Obsah a text

- `wide`: QR, text kódu, Stůl, Večeře, Poznámka a Cena jako samostatné prvky. Výchozí preset umístí kód pod QR; oba lze upravovat samostatně.
- `named`: QR, text kódu, logo, název události, datum a místo, jméno z objednávky a patička.
- Rozlišit **jméno z objednávky** od jména držitele vstupenky. Dnes named renderer používá `order.data.name/surname`; bez dalšího datového návrhu nepřejmenovat význam na ověřeného držitele.
- Volitelné údaje se tisknou pouze při dostupné hodnotě. Vlastní layout má pevné pozice: chybějící údaj neposune ostatní prvky. Editor používá zřetelné zástupné hodnoty pro výběr skrytých/prázdných prvků. Při prvním použití vlastního rozložení toto chování stručně vysvětlit; staré vstupenky bez layoutu zachovají dosavadní skládání řádků.
- Text má omezený box, `maxLines`, velikost písma a politiku overflow. Výchozí: zalomení, zmenšení do určeného minima, pak výpustka s varováním už v živém náhledu i při kontrole PDF. Kód vstupenky se nikdy nezkracuje; nemožnost vypsat celý kód blokuje uložení. Dlouhé slovo bez mezery se musí měřit a zalomit také.
- Náhled nabízí běžná data, dlouhé údaje a chybějící údaje. Nevkládat reálné osobní údaje automaticky. Interní `note_hidden` do tiskového katalogu nepřidávat; přepínač `showHiddenNote` nepovažovat za svolení zveřejnit poznámku.
- QR je povinný, jediný, bez rotace a deformace, kreslený nad ostatním obsahem s neprůhledným světlým podkladem. Kód vstupenky zůstává povinný pro ruční identifikaci. Text nepovolovat přes ochranný okraj QR.

Nová vlastní rozložení mají kolem QR ochranný okraj alespoň 4 moduly podle [DENSO WAVE](https://www.qrcode.com/en/howto/code.html/index.html). Generovat QR vektorem z matice modulů, aby velikost tiskového kódu nebyla odvozena z rozlišení náhledové bitmapy. Minimum fyzické velikosti ověřit na skutečném nejdelším podporovaném symbolu a skenování; nepovažovat jeden počet pixelů za záruku čitelnosti. Výchozí nové QR použije tmavé moduly na bílém podkladu; u barev povolit jen ověřené kontrastní kombinace. Historické PDF neměnit bez explicitního použití nového rozložení.

### Uložení, zrušení a obrázky

1. Otevření vytvoří hlubokou kopii aktuálního návrhu. Pokud vlastní layout neexistuje, načte počáteční preset odpovídající současnému typu a zdrojům.
2. **Použít** provede lokální validaci bez generování PDF a vrátí návrh do rozpracovaného nastavení události. UI jasně uvede, že trvalé uložení nastane tlačítkem Uložit v nastavení.
3. **Zrušit** zahodí pouze změny tohoto otevření. Odchod s lokálními změnami vyžádá volbu zahodit/pokračovat. Selhání backendu zachová návrh pro opravu nebo opakování.
4. Finální save atomicky uloží feature a layout existující cestou occasion save. Při konfliktu nabídnout načtení nové verze při zachování lokální kopie; nikdy automaticky nepřepsat cizí layout.
5. Přepnutí typu uchová návrh obou typů. **Obnovit výchozí** resetuje pouze aktivní typ a patří do undo historie. Neodstraňuje nová data nepřímo vynecháním JSON klíče.
6. Výměna pozadí proběhne nejprve lokálně; změnu poměru stran zobrazit s volbou zachovat geometrii/obnovit preset, nikdy neroztáhnout QR. Nový editor zachovává velikost oblasti a obrázek v ní vykreslí `contain` bez deformace.
7. Upload dokončit před uložením reference, používat explicitní occasion ID. Starý obrázek nesmazat při stisku Zrušit ani před úspěšným save. Úklid nového nevyužitého uploadu smí odstranit jen soubor vlastněný tímto draftem a bez dalších referencí; pokud existující služba neumí tuto jistotu doložit, ponechat jej k zavedenému úklidu. Nedělat nebezpečný rollback sdíleného obrázku.

## 4. Architektura a kontrakt

### Jeden layout, oddělený pohled

Nová bounded komponenta `lib/components/ticket_layout/`:

- `models/ticket_layout.dart`: neměnný model, parsování, serializace, validace a kopie.
- `ticket_layout_controller.dart`: dokument, výběr, příkazy změn, undo/redo, dirty state. Síťové volání nepatří do pointer handlerů.
- `views/ticket_layout_editor.dart`, `ticket_layout_canvas.dart`, `ticket_layout_properties.dart`: prostředí, manipulace a inspector.
- `ticket_layout_service.dart`: načtení presetu a PDF náhledu přes Edge boundary, oddělené od uložení occasion.
- `ticket_layout_strings.dart`: lokalizované texty přes běžný projektový mechanismus.

Viewport použije Flutter `InteractiveViewer`/`TransformationController`, ne controller sedadel. Převod pointeru do dokumentu použije inverzní transformaci ([Flutter `toScene`](https://api.flutter.dev/flutter/widgets/TransformationController/toScene.html)). Při dragu vypnout konkurenční pan handler a explicitně vyřešit přechod na pinch. Počet prvků je malý; není důvod přidávat vlastní rendering engine ani měnit veřejný balíček blueprintu.

Dokument používá body PDF (`72 pt = 1 inch`), počátek vlevo nahoře. Prvky jsou relativní k oblasti vstupenky. Viewport transformace, vybraný prvek a zoom se nepersistují. Renderer převádí box do PDF souřadnic: `pdfX = area.x + x`, `pdfY = page.height - area.y - y - height`; baseline textu odvodí z metrik fontu, ne z dolního okraje boxu.

U `wide` zachovat A4 a výchozí placement pozadí. U `named` zachovat současný rozměr stránky 212.5 x 387.5 pt. Pro příliš vysoké pozadí nový preset použije contain v dostupné stránce a zobrazí vysvětlení; netiskne prvky mimo stránku. Nezavádět v první verzi libovolný editor tiskových formátů.

### Persistovaný tvar

Uložit jeden volitelný objekt `layout` uvnitř feature `code: ticket` v `occasions.features`. Objekt má:

| Pole | Význam |
|---|---|
| `schemaVersion: 1` | Verze datového kontraktu, nikoli název druhé aplikace. Neznámou verzi nelze přepsat či ignorovat. |
| `templates.wide`, `templates.named` | Volitelné explicitní návrhy pro oba současné typy. Chybějící typ používá dosavadní renderer do první úpravy. |
| `page`, `ticketArea` uvnitř template | Fyzický rozměr stránky a obdélník vstupenky v bodech. |
| `elements` | Omezený seznam typovaných prvků se stabilním ID, bindingem, boxem, stylem a viditelností. |

Bindingy jsou uzavřený výčet: `qr`, `ticketSymbol`, `spotGroup`, `food`, `note`, `price`, `occasionTitle`, `occasionDatePlace`, `orderName`, `logo`, `footer`. Žádné JSONPath, SQL nebo eval výrazy. Chybějící údaje normalizuje server na `null`, cena 0 je platná hodnota. Pořadí produktů musí být deterministické; při více hodnotách použít jasně popsanou agregaci nebo zachovat první dle stabilního pořadí, nikdy náhodný výsledek `.find` nad neuspořádanou sadou.

Reference na obrázek zůstává `TicketFeature.ticketBackground`; layout ji neduplikuje, aby kopírování occasion nezanechalo starou URL. Pro named logo použít současný occasion zdroj. Layout obsahuje pouze jeho geometrii. Barvy textu jsou ve stylech layoutu; staré `lightColor/darkColor` slouží výchozím presetům a historickému rendereru. Jednotný parser musí odmítnout neplatná čísla, rozměry, duplicitní ID/binding QR, nepovolené typy a příliš velký dokument.

### Canonical render hranice

Založit `_shared/ticketLayout.ts` (schema, validace, presety a geometrie), `_shared/ticketRenderData.ts` (normalizace údajů) a `_shared/ticketGeneration.ts` (načtení zdrojů a dispatch do existujících generátorů). Interní kontrakt `generateTicketPdf(data, resources, template)` vrací PDF bytes a strukturovaná varování. `resources` jsou předem načtené zdroje, nikoli služba sahající při každém prvku do DB.

`download-ticket`, `send-tickets` a nový preview endpoint volají tuto hranici. Existující `generateTicket.ts` a `generateNamedTicket.ts` zůstanou jako výslovně omezené historické renderery pouze pro chybějící vlastní template. Jejich pevné souřadnice nejsou další cestou pro vlastní layout. Neplatný nebo nepodporovaný vlastní layout nesmí potichu spadnout do historického vykreslení.

Na jednu e-mailovou dávku načíst jednu verzi layoutu a zdrojů a použít ji pro všechny přílohy. Rozpracovaná úprava v editoru nemá vliv na dávku. Chybu layoutu zjistit před generováním příloh; neodeslat z této příčiny pouze podmnožinu vstupenek, protože dnešní per-ticket catch pokračuje po selhání.

Oba produkční vstupy mají dostat stejný minimální datový kontext. Upravit `get_ticket_details_for_generating` tak, aby download získal potřebné údaje objednávky, a adaptovat e-mailový vstup na stejné DTO. Nekopírovat bezdůvodně celou objednávku do nového API. Pro stejné vstupy vyžadovat shodný viditelný obsah a geometrii, ne binární shodu PDF s odlišnými metadaty.

### Preview bez vedlejších efektů

Nová Edge Function `preview-ticket-layout` přijme `occasionId`, aktuální neuložený návrh, zvolený typ a identifikátor syntetického scénáře. Režim `resolve` načte layout nebo sestaví výchozí preset a vrátí metadata zdrojů i ukázkové údaje bez generování PDF. Režim `pdf` použije aktuální draft a vrátí kontrolní PDF s varováními. Jde o dva explicitní režimy jednoho endpointu. Server je jediný vlastník výchozích presetů, Flutter je znovu nepočítá podle odhadovaných konstant.

- Autentizace JWT a kontrola editora příslušné jednotky, tedy skutečného oprávnění nastavení. Výchozí `authorizeRequest` dnes znamená editor objednávek a nestačí. Použít ověření stejné role přes existující user-scoped oprávnění nebo přidat úzce vymezený permission režim bez změny defaultu ostatních endpointů.
- Autorizovat před privilegovaným čtením zdrojů nebo generováním. Preview nepřijímá system secret ani reálný ticket ID, nevytváří ticket, nepřepíná jeho stav, neposílá e-mail a neukládá layout.
- Syntetický symbol používat v odděleném zjevně testovacím formátu; ověřit, že nespadá do platného produkčního formátu a test scanneru jej odmítne. PDF označit jako VZOR mimo vlastní návrh vstupenky.
- Bounded vstup: velikost requestu, počet prvků, délky textů, rozměry a rozsah zoom-independent hodnot. Zdrojové URL omezit na serverem odvozené nebo schválené image zdroje; žádný libovolný fetch z klientské URL. Limity času/velikosti, ochrana redirectů a privátních adres podle existujícího `fetch-http-data` vzoru; nepovolit útočníkovi použít náhled jako proxy.
- Celá vstupenka se průběžně vykresluje lokálně bez síťových requestů při editaci. PDF vyžádá výhradně tlačítko Náhled PDF. Nejvýše jeden aktivní PDF request; pozdní odpověď pro jiný draft nesmí přepsat editor. Výpadek náhledu ponechá lokální návrh a umožní opakovat kontrolu.
- PDF náhled je volitelný a není podmínkou uložení. Lokální validace kontroluje geometrii a zobrazení; save RPC autoritativně validuje ukládaný kontrakt. Kontrolní PDF označit jako neaktuální, pokud se od jeho vytvoření změnil návrh nebo zdroj obrázku.
- Živý náhled musí věrně zobrazovat celé rozložení včetně textů, zalomení, barev a QR. Použít stejné fontové bytes, pravidla měření/overflow a geometrický kontrakt v lokálním plátně i PDF rendereru. Rozdíly Flutter/PDF metrik ověřit společnými fixtures a vizuálním porovnáním; PDF tlačítko nesmí sloužit jako omluva pro přibližné nebo neúplné plátno. Přesný PDF náhled může v první verzi otevřít/stáhnout soubor existujícím file helperem; přidání viewer závislosti je podmíněné ověřením Flutter web + mobile podpory a nákladů.

### Persistenční ochrana a souběh

Změna je aditivní v JSON, nepotřebuje tabulku layoutů ani backfill všech occasions. Vyžaduje ale SQL migraci save kontraktu.

- Přidat do vstupního configu existujícího occasion save explicitní nepersistovaný příkaz `ticket_layout_change: {expected: <původní layout nebo null>, next: <nový layout>}`. Model occasion tento envelope neukládá do DB; `DbOccasions` a command adaptér jej přidají jen při úpravě layoutu.
- V `update_occasion_internal_v1` uzamknout existující occasion řádek před čtením původního layoutu a sloučením features. Bez příkazu vždy zachovat dosavadní `ticket.layout`, i když jej starý klient vynechal nebo serializoval zastaralou kopii. Explicitní příkaz vyžaduje shodu `expected` s aktuální JSONB hodnotou a validní `next`; jinak konflikt bez dílčího zápisu. Při neexistující ticket feature ji pro uchování layoutu rekonstruovat s incoming stavem vypnutí, nikoli layout zahodit.
- Zachovat stávající `p_expected_version`, command idempotenci a replacements; nový expected layout chrání též legacy save cestu. Nevymýšlet další nezávislý čítač revizí. Při úspěchu obnovit lokální saved baseline; retry se stejným command ID nesmí provést změnu podruhé.
- Při create validovat případný layout. Při duplicate zkopírovat layout spolu s feature a potom obrázek současným mechanismem. Reset vytváří nový explicitní preset, ne null/delete.
- Strukturní SQL validace chrání uložení (typy, rozsahy, pole, povinné QR). Render-time validace v TS navíc kontroluje fonty, overflow a skutečnou QR geometrii. Obě používat proti stejné sadě validních/nevalidních JSON fixtures, aby se pravidla nerozcházela.
- Před implementací této změny dohledat všechny skutečné writes do `occasions.features`, RLS a granty; potvrdit, že layout nelze přepsat přímým client UPDATE mimo explicitní hranici. Pokud cesta existuje, zahrnout její úpravu a cílený test do této vlny; nespoléhat na UI. Neměnit globální politiku všech features a nepřidávat aplikační trigger.
- U neznámé `schemaVersion` ponechat data beze změny, editor označit jako nepodporovaný a zabránit přepisu. Běžná editace jiného nastavení nesmí layout smazat.

## 5. Implementační vlny

### Efektivní realizace bez snížení kvality

- Využít průzkum a konkrétní soubory z tohoto plánu. Na začátku zkontrolovat stav větve a změny proti výchozímu bodu; došetřit pouze dotčené rozdíly a výslovně uvedené otevřené hranice. Neopakovat plošný architektonický průzkum.
- Vlny určují závislosti, nikoli povinné přestávky na schválení. Co nejdříve propojit malý skutečný průchod: wide pozadí + QR + kód, živé přetažení/resize, uložení a kontrolní PDF. Pro tento průchod lze dodat tenký plátek UI z vlny 4 po nezbytných částech vln 1-3. Potom ve stejném modelu dokončit další pole, named a ovládání; nevytvářet zahazovací prototyp nebo druhou implementaci.
- Implementovat po ucelených blocích. Sdílet příkazy pro drag/resize/undo a fixtures pro Dart/TS/SQL. Extrahovat helper až pro konkrétní potřebu; nezavádět framework pro budoucí varianty.
- Po každém dokončeném bloku spustit jen relevantní cílené kontroly. Úspěšnou kontrolu opakovat pouze po změně kódu, který pokrývá, nebo při novém důkazu problému. Závěrem jednou projít integrační scénář, věrnost PDF a čitelnost QR; zachovat povinné repository gates pro případnou publikaci. Verification zůstává `standard` kvůli ukládání, oprávněním a sdílenému PDF výstupu.
- Rychlost editoru zajistit jednoduchou cestou: obrázek/font načíst a dekódovat jednou na zdroj, QR matici přepočítat jen při změně obsahu, při gestu překreslovat potřebné vrstvy. Bez sítě, PDF, nové image decode nebo přestavby celého formuláře při každém pointer eventu. Undo zaznamenat až za celé gesto. Nezavádět vlastní cache infrastrukturu ani optimalizace bez doloženého problému.
- V jedné finální interaktivní kontrole ověřit plynulý drag/resize/zoom na reprezentativní vstupence. Případné záseky diagnostikovat cíleně; neskrývat je debounce, který by zrušil živý náhled. Krátce hlásit výsledky a skutečné překážky, pokračovat samostatně až do úplných akceptačních podmínek.

### Vlna 1: Model, vstupy a výchozí výstupy

**Cíl:** dohodnutý kontrakt a důkaz, co se musí zachovat.

Založit Dart/TS model a společné JSON fixtures, definovat bindingy, převody souřadnic a validaci. Připravit syntetické vstupy pro wide/named, dlouhý text, chybějící data, diakritiku, nulovou cenu a různé obrázky. Zachytit referenční PDF obou stávajících generátorů s lokálními fonty/obrázky, ne s živými síťovými zdroji. Doplnit deterministickou normalizaci údajů a kontrakt jména objednávky.

**Migrace/mazání:** žádná data ani produkce; žádné přepsání starých rendererů.

**Riziko:** historický wide na extrémním poměru pozadí nemusí být validní nový návrh; nová template má výslovnou contain normalizaci a hlášení.

**Ověření a exit:** jednotkové round-trip/invalid fixtures a převody boxů pro oba jazyky projdou; existují referenční výstupy a explicitní typovaný kontrakt. Nepsat testy překladu tlačítek nebo zrcadlení každého getteru.

### Vlna 2: Společné vykreslení a skutečný PDF náhled

**Cíl:** vlastní geometrie se spolehlivě projeví v PDF ještě před komplexním UI.

Implementovat `ticketLayout.ts`, `ticketRenderData.ts`, `ticketGeneration.ts` a `preview-ticket-layout/index.ts`. Nejprve wide QR/kód, potom bindingy a named. Přepojit `download-ticket/index.ts` a `send-tickets/index.ts` na společný výběr; doplnit minimální order context v SQL a jeho test. Načítat layout/zdroje jednou na dávku. Přidat auth, bounds a runtime/coverage záznamy preview včetně `_shared/edgeEntrypoints_test.ts`.

**Migrace/mazání:** odstranit duplikované rozhodování `ticket_type` z entrypointů a nahradit je voláním canonical render hranice. Původní renderery ponechat pouze v explicitní větvi bez template. SQL změny authorovat v `database/functions/` a nové jednoznačně datované migraci.

**Selhání:** neplatný vlastní layout končí řízenou chybou; žádné tiché jiné rozložení nebo částečné odeslání z důvodu layoutu. Preview je bez zápisů i při opakování.

**Ověření a exit:** TS testy geometrie, obsahu, obou dispatch větví a unauth/foreign-unit preview; porovnání normalizovaných PDF draw operací/boxů a kontrola vyrenderovaných fixture PDF. Stejné vstupy přes preview/download/mail mají stejný obsah kromě označení VZOR. Ověřit QR dekódováním rasterizovaného PDF v několika velikostech.

### Vlna 3: Uložení a nastavení jako jeden celek

**Cíl:** data lze bezpečně uložit, znovu načíst a kopírovat.

Rozšířit `TicketFeature`, `FeatureConstants`, `DbOccasions.updateOccasion`, `OccasionCommands` o model/envelope. Přidat SQL validaci a zachování layoutu v běžném save včetně row locku a expected porovnání. Ověřit command wrappery z citovaných migrací a vytvořit/aktualizovat jejich kanonický SQL zdroj, pokud žijí pouze v migraci. Zapojit dirty baseline a konflikt do `occasion_settings_tab.dart` bez nahrazení stávajícího HTML save koordinátoru. Upravit lifecycle pozadí tak, aby zrušení návrhu nemazalo uložený soubor.

**Migrace/mazání:** aditivní změna JSON/RPC chování, žádný hromadný přepis. Odstranit okamžité mazání pozadí z nového editor flow. Starý image panel pro wide přesunout do editoru, nenechat dvě aktivní UI spravující stejný obrázek odlišně.

**Selhání:** SQL fail vrátí celou transakci; chybný upload neuloží URL; stale klient uchová layout a explicitní konflikt nesmaže draft. Vypnutí feature layout zachová.

**Ověření a exit:** SQL test pro unit editor vs nepovolaný uživatel, malformed layout, old-client save, souběžnou změnu layoutu, create/duplicate a vypnutí. Dart test úspěšného/conflict save a serializace. Znovuotevření i kopie occasion mají stejné boxy a správný obrázek.

### Vlna 4: Editor a přirozené ovládání

**Cíl:** člověk nastaví vstupenku bez ruční úpravy JSON.

Vyčlenit ticket settings widget z `TicketFeature.buildFormField`, dodat controller/plátno/inspector, explicitní occasion kontext přes již existující `FeatureForm.occasion` bez plošné změny všech feature widgetů. Implementovat tabulku gest, undo, jednoduchý snap, živou změnu velikosti písma a boxů, scénáře a explicitně vyvolaný PDF náhled. Snap řešit přímým porovnáním hran/středů malého počtu prvků; bez obecného systému vazeb. Všechny změny zapisovat přes stejné controller příkazy, ať drag, resize a kontextová lišta nemají odlišná pravidla. Lokalizovat přes strings a sdílené překlady.

**Migrace/mazání:** jeden nový editor nahradí původní jednotlivá vizuální nastavení wide. Funkční přepínače skenování zůstanou mimo canvas. Žádná editace ani kopie rezervačního controlleru blueprintu.

**Selhání:** pozdní síťová odpověď nesmí vrátit staré rozložení; dispose zruší listenery/controller; chybějící pozadí hlásit, nepoužít potichu jiné. Po načtení zdrojů lze bez sítě dál upravovat a lokálně potvrdit draft; trvalé uložení vyžaduje úspěšný save RPC. Výpadek PDF náhledu sám o sobě uložení neblokuje.

**Ověření a exit:** widget/controller testy pro posun při různých zoomech, resize QR i písma, zalamování textu, undo/redo, cancel/apply, stale preview, klávesnici a konflikt drag/pan. Jedna izolovaná browser QA relace podle agent-browser pravidel po dokončení souvislé implementace; desktop myš/trackpad a dotykový režim. Neotevírat uživatelův existující tab. Oba typy jsou upravitelné a PDF odpovídá návrhu. Test zachytí, že otevření editoru, drag, resize, zoom i Použít vyvolají nula PDF render requestů; jeden vznikne až stiskem Náhled PDF. Ověřit živé překreslování během gesta, nikoli až po jeho dokončení.

### Vlna 5: Dokončení a příprava nasazení

**Cíl:** žádná opomenutá cesta a jasné provozní předání.

Prověřit odkazy na staré entrypoint dispatch větve, test coverage/runtime registraci, kopírování obrázků a dokumentaci včetně nového `ticket_layout/README.md`. Zapsat limity a příklady kontraktu, aktualizovat backend inventář. Připravit seznam SQL/Edge/client artefaktů pro canonical backend a jedinou zvolenou tenant větev. Produkční tenant nebyl zadán, jeho výběr je potřebný až pro rollout.

**Migrace/mazání:** dokončit ledger níže; odstranit mrtvé helpery, importy a duplicitní controls po přepojení. Zachování dvou historických rendererů je záměrná hranice kompatibility, nikoli nedodělaná migrace.

**Ověření a exit:** cílené sady projdou, žádné vlastní layouty neobcházejí existující generátory se společným layout kontraktem a žádný aktivní klientský save nesmaže layout při absenci explicitního příkazu. Produkční nasazení je samostatný krok, ne součást plánovacího zadání.

## 6. Ledger nahrazovaných cest

| Artefakt | Finální stav a důkaz |
|---|---|
| Vizuální controls v `TicketFeature.buildFormField` | Delegují do ticket settings/editor widgetu; žádné druhé image delete flow. |
| Volba named/wide v `download-ticket` a `send-tickets` | Jedno místo `prepareTicketRenderer`; scoped `rg` prokáže absenci starých přímých dispatch větví. |
| Pevná geometrie `generateTicket.ts` a `generateNamedTicket.ts` | Úmyslně ponechána pouze pro chybějící custom template; test prokáže, že custom layout touto větví nikdy nejde. |
| `lightColor`, `darkColor`, `background`, `ticket_type` | Zachovány pro data existujících událostí, presety a typ; bez plošné migrace či rename. |
| Nahrazení `features` z klienta | Pro layout chráněno explicitním příkazem; regression test starého klienta. Ostatní feature kontrakty zůstávají ve své působnosti. |
| Blueprint komponenty/balíček | Beze změn v této feature; nepřidávat sdílenou abstrakci jen kvůli vizuální podobnosti. |

## 7. Ověřování, nasazení a rollback

Při implementaci testovat po souvislých vlnách, ne po každém editovaném souboru. Minimální cílená sada:

- `fvm flutter test test/components/ticket_layout/` a relevantní existující occasion command/media testy; `fvm dart analyze lib/components/ticket_layout` plus změněné integrační soubory.
- `deno test --allow-env --allow-net --allow-read` s explicitním seznamem nových layout/render/preview testů a dotčených entrypoint testů, podle způsobu spuštění v `automation/test_all.sh`. Testované zdroje mockovat, nepoužívat produkci.
- Lokální SQL test přes `node web_client/scripts/run_db_tests.js database/tests/ticket_layout_settings_test.sql` s `DATABASE_URL` izolované testovací DB podle `CONTRIBUTING.md`. Obnovu dedikovaného DB prostředí použít jen pokud je potřebná, nikdy nenahradit test živou DB.
- Po změně překladů projektové unify/reorder skripty. Před případným commitem plné požadované gates z `CONTRIBUTING.md`, nikoli při samotném plánování.
- Reálná vizuální kontrola PDF a čitelnosti QR, včetně světlého/tmavého pozadí, malého výsledného tisku, dlouhých českých názvů a obou typů. Deterministické geometrické testy nenahrazují tuto kontrolu.

Pořadí případného nasazení: (1) SQL zachovávající layout a validující explicitní editaci, (2) všechny serverové čtečky, společný renderer a preview, (3) klient s editorem. Dokud server není připraven, editor nezapínat. Starší klient dál může měnit jiné nastavení, ale nemůže smazat layout pouhým vynecháním pole. Nenavrhovat dočasný feature flag bez konkrétního důvodu.

Rollback klienta je možný, backend musí dál umět uložené layouty. Po prvním vlastním layoutu nelze vrátit starý renderer a potichu jeho data ignorovat. Při serverové vadě raději pozastavit dotčené generování/opravy; návrat konkrétního návrhu na preset je explicitní editace se souhlasem správce, ne destruktivní globální rollback. Již odeslaná PDF zůstávají beze změny; další download/odeslání používá aktuálně uložené rozložení, stejně jako dnes čte aktuální occasion settings.

Nasazovat jen na canonical backend podle activation pravidel `ai_context.md`; starší instrukce v `CONTRIBUTING.md` o zápisech do cloud zdrojů nejsou platnou autoritou pro obnovení cloud writes. Žádné deploy, migrace na produkci, push ani rollout více tenantů nebyly tímto zadáním povoleny.

## 8. Rozhodnutí, předpoklady a otevřené hranice

**Rozhodnutí:** vlastní layout je volitelná aditivní feature, oba stávající typy mají editor, historický vzhled bez layoutu se nemění. Neprovádíme zbytečný cutover všech již vydaných vstupenek. Serverový PDF renderer je autorita výstupu; Flutter zajišťuje interakci. Ukládání zůstává součástí occasion save.

**Předpoklad:** zadání míří na jednu šablonu pro událost a aktuální typ, nikoli na jednotlivé produkty. Pokud později vznikne požadavek na Bronze/Silver apod., jde o další vrstvu výběru šablony nad stejným layoutem, s vlastní prioritou a UI.

**Předpoklad:** cílem je posouvat prvky i procházet celou vstupenku, nikoli měnit umístění vstupenky na A4. Proto je tiskový formát v první verzi pevný a manipulace neovlivní velikost stránky.

**Implementační ověření ve vlně 1-3:** přesný formát ticket symbolu pro neplatný sample QR; všechny DB writer cesty a oprávnění; skutečné fontové formáty pro Flutter a Deno; dostupný file/PDF helper; původní draft save lifecycle. Každé má uvedeného vlastníka ve vlně a cílené rozhodovací kritérium; nevyžaduje nový plošný průzkum.

**Zbytková rizika:** odlišné fontové metriky lokálního plátna, historická obrázková rozlišení a reference, chybějící údaje některých objednávek, trackpad rozdíly mezi prohlížeči. Pokrývá je skutečný náhled, explicitní nullable bindingy a cílená QA. Vývoj není blokován neznámým produkčním tenantem; pouze jeho nasazení.

## 9. Akceptační scénář

Správce otevře běžnou wide vstupenku, přiblíží ji kolem kurzoru, přesune QR do jiného rohu, změní jeho velikost a samostatně umístí cenu. Posune celý pohled bez změny souřadnic prvků, vrátí poslední drag přes undo a tažením rohového úchytu zvětší písmo. Celou dobu vidí hotově vypadající vstupenku se všemi údaji; nic nenastavuje zadáváním X/Y. Zobrazí PDF s dlouhou poznámkou a chybějící večeří, upraví přetečení, použije návrh a uloží nastavení. Po opětovném otevření jsou všechny hodnoty stejné, download i e-mail zobrazí stejnou geometrii a QR jde načíst. Zrušení jiné rozpracované úpravy nic nezmění. Druhý správce se zastaralým layoutem dostane konflikt. Starší klient při změně názvu události layout nesmaže. Stejná cesta funguje pro named včetně shodného jména při downloadu a odeslání. Kopie události převezme rozložení a svůj obrázek. Existující událost bez vlastního návrhu dál generuje dosavadní podobu.

Hotovo znamená všechny výše uvedené scénáře, dokončený ledger a ověřené kontrakty; samotné plátno s přetahovatelným QR nestačí.


## 10. Dokončená realizace 2026-10-01

Všech pět implementačních vln je dokončeno. Živé plátno používá bitmapu,
QR moduly a text ve Flutteru. Samostatný nový PDF renderer nevznikl:
`ticketGeneration.ts` předává návrh existujícím `generateTicketImage` a
`generateNamedTicketImage`. Barvy textu a QR se upravují v inspectoru editoru.

Ledger z části 6 je uzavřen: ticket feature má jediný editor, download a e-mail
volají `prepareTicketRenderer`, historické větve zůstávají pouze bez vlastní
šablony, všechny explicitní změny layoutu procházejí stejnou SQL validací.
Souběžné blueprint/form změny v pracovním stromu nejsou součástí této realizace.

Ověření:

- Flutter: 10 testů editoru/controlleru včetně živého dragu před pointer-up,
  resize, zoom, klávesového undo, zrušení gesta při druhém dotyku, barev,
  konfliktu a zastaralého PDF; 8 cílených occasion command/media/save testů.
- Deno: 41 cílených testů celkem; referenční test porovnává všechny drawing
  a resource streamy obou historických PDF, nikoli nestabilní metadata souboru.
- Izolovaná PostgreSQL na 127.0.0.1:55432: layout a occasion permission sady
  prošly; migrace obsahuje přesné canonical SQL definice v jedné transakci.
- Dart analyzer: editor a occasion model bez nálezů; integrační soubory mají
  pouze šest dříve existujících info hlášení, žádné chyby či varování.
- Flutter web fixture používající skutečný editor se sestavila; izolovaný
  headless browser ukázal okamžitý přesun QR ještě během dragu. QR byl načten
  přímo z bitmapy plátna. Browser a dočasný HTTP server byly ukončeny.
- 19 PDF přes existující generátory: oba typy, běžné/dlouhé/chybějící údaje,
  světlé/tmavé pozadí, historické větve a všech pět QR barev při 60 pt.
  Všechna QR byla dekódována při 96, 150 a 300 DPI; výstupy byly vizuálně
  prohlédnuty. Tmavé pozadí vyžaduje vhodnou editovanou barvu textu.
- Coverage registrace zahrnuje 20 produkčních Edge Functions; oba cílené
  Node testy registrace prošly. Překlady byly sjednoceny a seřazeny.

Provozní předání: nejprve nasadit SQL migraci, potom canonical Function bundle
s download-ticket, send-tickets, preview-ticket-layout a sdíleným fontem,
potom klienta pro jediného vybraného tenanta. Canonical bundle builder kopíruje
celý `_shared`, tedy i fontový asset. Produkční nasazení, commit ani push
nebyly provedeny. Podrobnosti kontraktu a lifecycle jsou v
`lib/components/ticket_layout/README.md`.


### Úpravy po uživatelském náhledu

Doplněna galerie tří geometrických předvoleb pro každý formát, oddělené
přepínače mřížky a magnetů s vodicími čarami, omezený pan a dvojklik pro reset
font-size/max-lines sliderů. Při resolve se používá skutečný název, datum a místo
oprávněné události. Magnet pracuje s nezachyceným pointer originem, takže se při
pomalém tažení nezasekává. Zoom počítá pouze dvě osy plátna. Původní barva textu
bitmapové vstupenky se převezme do předvoleb, vlastní uložené barvy se zachovají.

Uživatel upřesnil, že původní tři obrazové varianty nejsou v repozitáři a mají
se dohledat mezi minulými plesy a událostmi s blueprinty. Canonical aktivace
vstupenky.online byla ověřena (festapptickets, generation 1; konfigurace org 3).
Named-user Access session je neplatná a anonymní čtení organizace bylo odmítnuto
403. Read-only dotaz je připraven; obrazové reference zatím nejsou ověřeny ani
nahrazeny domnělými obrázky. Tento bod zůstává otevřený do obnovení přihlášení.

Ostatní úpravy: 14 Flutter testů editoru včetně galerie, pan limitů, přepínačů
magnetů/mřížky a resetu dvojklikem; cílené Deno testy předvoleb a skutečných
údajů; analyzer editoru i preview bez nálezů. Lokální preview umí oba typy,
opětovné otevření použitého draftu a zadání názvu ukázkové události.
