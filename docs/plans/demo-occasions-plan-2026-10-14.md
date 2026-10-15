# Tři kompletní ukázkové akce s možností vytvoření vlastní kopie

Datum: 2026-10-14  
Stav: Návrh připravený pro implementaci; produkční aktivace není součástí zadání  
Ověřování implementace: standard (oprávnění, databázový kontrakt, objednávky)  
Ověřování tohoto plánu: čtení aktuálního pracovního stromu, bez testů a přístupu k produkci

## Výsledek a potvrzené zadání

Nový i stávající přihlášený uživatel najde tři hotové ukázky: ples, koncert a víkendovku. Ukázky jsou skutečně založené akce s provázanými daty, realistickými plánky, formuláři, programem, přihlášenými účastníky a zakoupenými vstupenkami podle typu akce. Uživatel může procházet také administrativní pohledy a pochopit, co lze vytvořit. Zdrojové ukázky jsou společné, pevně připravené a pouze ke čtení. Uživatel si může ukázku zkopírovat jako běžnou vlastní akci a tu upravovat.

Nejde o automatické vytvoření tří akcí při každé registraci ani o samostatný simulátor aplikace. Použijí se existující modely a obrazovky. Registrace nemusí zapisovat členství v ukázkách; dostupnost je odvozená ze serverového katalogu pro přihlášeného uživatele.

## Rozhodnutí a předpoklady

- **Potvrzeno uživatelem:** přesně tři typy; kompletní ukázková data a plánky; zdroj pouze ke čtení; možnost kopírování do běžné akce.
- **Upřesněno uživatelem:** ples má vycházet ze skautského plesu nebo plesu ve Větřkovicích, v reálném rozsahu 200-300 lidí a s realistickými časy a situacemi. Všechny osobní a transakční údaje musí být vymyšlené.
- **Další upřesnění uživatele:** plánek i vstupenka mají být vizuálně propracované; vstupenka musí být stylová a odpovídat konkrétní akci. Popisy akcí, formulářů a jejich polí mohou vycházet z reálných akcí. Kvalita má být dosažena efektivně opětovným použitím existujících nástrojů a vhodných podkladů.
- **Potvrzené rozšíření:** součástí kompletní ukázky je také fiktivní bankovní účet a viditelné syntetické transakce provázané s objednávkami. Pouhý stav „zaplaceno“ bez platební historie nestačí.
- **Potvrzené provozní scénáře:** ukázky obsahují i občasné storno a změny objednávek, včetně srozumitelné historie a odpovídajících dopadů na vstupenky, obsazenost a finance.
- **Potvrzeno pro víkendovku:** součástí ukázky jsou náhradníci na čekací listině.
- **Navržené rozhodnutí:** kopie obsahuje konfiguraci a obsah, ale žádné fiktivní účastníky, přihlášky, objednávky, finanční historii ani vystavené vstupenky. Vlastní akce začíná s nulovými prodeji a volnými místy. Tento význam kopie uživatel zatím výslovně nepotvrdil.
- **Potvrzený směr UI/UX:** bez vlastních akcí ukázky výrazně nabídnout; s vlastními akcemi ponechat pouze nenápadnou, snadno dostupnou nabídku inspirace. Konkrétní provedení určuje sekce níže. Registrace končí běžným vstupem do aplikace, kde je nabídka dostupná bez dalšího povinného kroku.
- **Navržené rozhodnutí:** ukázky jsou katalog spravovaný pro konkrétní Organization. Žádné implicitní čtení nebo kopírování mezi tenanty. Případná budoucí globální knihovna je jiné zadání.
- **Předpoklad:** uživatel bez vlastní Unit si ji může vytvořit existujícím oprávněným postupem. Implementace ověří `unit_creation_helper.dart`, `unit_commands.dart` a oprávnění příslušné RPC. Pokud tenant zakazuje samoobslužné založení, ukázky jsou stále dostupné a kopírování vysvětlí potřebu oprávněné cílové Unit; nevytvoří ji privilegovaně za uživatele.
- **Rozhodnutí podle upřesnění:** pro ples použít jako strukturální referenci skautský ples nebo ples ve Větřkovicích: uspořádání sálu, rozsah, typy vstupenek, formulář a provozní scénáře. Před přípravou fixture vybrat konkrétní referenční akci podle dostupného plánku a konfigurace. Její strukturu zatím tento plán neověřoval. Z referencí nepřebírat osobní údaje, texty objednávek, identifikátory vstupenek, bankovní údaje ani historii plateb. Všechny demo záznamy generovat nově, nikoli anonymizací skutečných zákazníků.
- **Předpoklad:** konkrétní vizuální podklady nebyly dodány. Použít dostupný oprávněně použitelný referenční plánek nebo jeho vlastní věrnou strukturální rekonstrukci a legálně použitelné obrázky. Pokud je reference dostupná jen na produkci, číst pouze nutnou konfiguraci a plánek přes schválený backend přístup a ověřený tenant kontext; žádné dotazy na skutečné účastníky nebo objednávky.
- **Omezení důkazů:** pracovní strom obsahuje rozsáhlé rozpracované změny. Plán vychází z jeho současného stavu; implementátor ověří dotčené kontrakty před úpravami, zachová ostatní práci.

## Obsah ukázek

Rozsah plesu 200-300 lidí je požadavek uživatele, nikoli jen maximální kapacita prázdného sálu. Konkrétní cíl 260 účastníků a počty ostatních ukázek jsou návrh fixture. Rozhodující je konzistence souvisejících entit, kapacit a statistik a realistická naplněnost.

| Ukázka | Co ukazuje | Plánek | Vzorová data |
|---|---|---|---|
| Ples | Prodej konkrétního místa, různé ceny, objednávky a QR vstupenky; struktura podle skautského nebo větřkovického plesu | Realistický sál podle reference, cílově 300 míst; číslované stoly a židle, pódium, parket, bar a vstupy; přehledná legenda | Cílově 260 účastníků / aktivních vstupenek v přibližně 95 objednávkách; další stornované záznamy mimo počet účastníků; jednotlivci, páry a skupiny u stolů, volná i prodaná místa, zaplacené a nezaplacené objednávky a část vstupenek již odbavená |
| Koncert | Vstupenky na stání a do sedících sektorů, více cenových kategorií, kontrola vstupu | Pódium, dva sektory sedadel celkem 80 míst, samostatná kapacita 150 míst na stání, vstupy | Přibližně 20 objednávek / 55 vstupenek; několik objednávek s více lístky; kapacita stání přes existující inventář |
| Víkendovka | Přihlašování účastníků, náhradníci, páteční až nedělní program, ubytování, strava, kapacitní workshopy | Areál s pokoji a společnými prostory; ubytování přes existující inventář; orientační plánek není seat-picker blueprint připojený ke kapacitnímu přihlašovacímu formuláři | Cílově 24 přijatých účastníků a 4 aktuální náhradníci; vyplněné přihlášky, ubytování, jídlo a workshopy; historie nabídky uvolněného místa a přijetí náhradníka |

Každá ukázka má popis, úvodní obrázek, správnou časovou zónu, srozumitelná data, informační obsah, povolené relevantní funkce, formulář a odpovídající vzhled vstupenky. QR je označen jako ukázkový a mimo ukázku není platným oprávněním ke vstupu. Kontaktní údaje jsou fiktivní a nedoručitelné; není nutné zakládat funkční Auth účty všem kupujícím. U víkendovky případné identity nutné pro programové přihlášení připraví fixture bez přihlašovacích údajů a bez odeslání pozvánek.

Realistické časy a situace nejsou náhodně rozdané stavy. Ples například otevírá vstup v 18:30, začíná v 19:30, obsahuje předtančení ve 20:00, půlnoční program a končí ve 02:00 následujícího dne. Koncert má otevření vstupu, předkapelu a hlavní vystoupení; víkendovka páteční příjezd, sobotní bloky a nedělní odjezd. Konkrétní časy přizpůsobit referenci, nikoli je prezentovat jako ověřený program skutečné akce. Objednávky vznikají v průběhu několika týdnů prodeje; zaplacení následuje objednávku a odbavení následuje zaplacení i otevření vstupu. Storno uvolní místo a skupinové objednávky mají věrohodné rozmístění. Připravit konzistentní pevný scénář, například stav plesu v den akce ve 20:30; aplikace jasně uvádí referenční okamžik ukázky, místo aby historii odvozovala od dnešního času.

Vymyšlené jsou také názvy demo pořadatelů, kontakty, poznámky, odpovědi formulářů, objednávkové a platební identifikátory i QR symboly. Reference slouží ke struktuře a provozní věrohodnosti; demo nemá vystupovat jako skutečná aktuální akce referenčního pořadatele.

Přesné datum fixture je součástí její verze. Při nasazení zvolit reprezentativní termíny; UI ukázek nesmí zmizet mezi minulými akcemi. Odbavené lístky jsou výslovně ukázkový stav, i když je termín akce v budoucnu. Žádný denní posun datumů cronem.

## Náhradníci na víkendovce

Přihlašovací formulář víkendovky má zapnutou čekací listinu a kapacitu navrženě 24 účastníků. Finální ukázka obsahuje 24 přijatých a další 4 čekající náhradníky s fiktivními údaji, odpověďmi a různými časy přihlášení. Jeden z aktuálně přijatých původně čekal: po stornu jiného účastníka dostal nabídku, přijal ji a následně zaplatil. Jeho historie a syntetická platba jsou provázané. Jeden aktuální náhradník může mít v historii již vypršenou nabídku a následné čekání podle stávajících pravidel. Čekající se zobrazují odděleně od přijatých a nezvyšují jejich počet ani tržbu.

Použít kanonický kontrakt v `docs/plans/form-capacity-waitlist-plan-2026-10-13.md` a aktuálním kódu: čekající položka je `eshop.tickets` ve stavu `waitlisted`, bez platného ticket symbolu, produktů, financí a vstupního PDF/QR. Nabídky odkazují přes `waitlist_offer_slots.ticket_id`; přijetí zachová stejné ticket ID a využívá existující finalizer. Nezavádět tabulku osob ani druhý lifecycle náhradníka. Kapacita formuláře a seat-picker blueprint se podle současného kontraktu nekombinují; areál zůstane orientační a ubytování používá samostatné podporované produktové/inventární vazby.

Pro stabilní read-only ukázku použít aktuální čekání a dokončenou historii přijaté nebo vypršené nabídky. Nepotřebuje neustále prodlužovanou aktivní nabídku ani vlastní demo hodiny. Uživatel může vidět pořadí čekání, odpovědi a historii nabídky, ale nemůže nabídku poslat, přijmout, odmítnout ani zrušit čekání. Také přímý osobní/offer odkaz musí změnu demo dat odmítnout. Žádné nabídkové emaily se neposílají a expiry úloha demo nemění.

Ve fixture ověřit 24 obsazených míst a 4 čekající, správné uvolnění/znovuobsazení místa po stornu a přijetí, stejné ID přijaté vstupenky a nulové finance/produkty/platné symboly čekajících. Krátký E2E průchod víkendovky otevře seznam náhradníků a historii přijatého účastníka. Kopie zachová konfiguraci kapacity a čekací listiny, ale začne bez účastníků, náhradníků a nabídek. Při implementaci ověřit dostupnost waitlist kontraktu v cílovém prostředí; pokud ještě není nasazený, uvést jeho nasazení jako explicitní závislost demo aktivace, nenahrazovat náhradníky statickým seznamem.

## Fiktivní účet, transakce a finanční přehled

Každá ukázka má vlastní fiktivní účet a sadu transakcí v existujících tabulkách `eshop.bank_accounts`, `eshop.unit_bank_accounts`, `eshop.payment_info` a `eshop.transactions`. Uživatel může otevřít údaje účtu, seznam pohybů a detail objednávky s navázanými platbami. Použít standardní finanční pohledy v režimu pouze ke čtení. Účet má fiktivní název, příjemce, zobrazované číslo a měnu CZK; pohyby mají věrohodné částky, datum, variabilní symbol, jméno plátce a zprávu. Všechny hodnoty vznikají synteticky.

Číslo účtu se zobrazuje jako výslovně ukázkové, nepoužít náhodně vygenerovaný platný IBAN nebo skutečný účet. V poli pro směrování plateb ponechat NULL, pokud to stávající kontrakt dovolí, jinak použít záměrně neplatný demo identifikátor a explicitní read-only prezentaci. Demo formulář ani PDF nesmí vytvořit použitelný platební QR nebo odkaz pro skutečný převod. To se netýká syntetického vstupenkového QR. UI vysvětlí „Ukázkový účet - neposílejte platbu“.

Ples obsahuje alespoň tyto pojmenované příklady; ostatní ukázky využijí stejný generátor a přirozenou podmnožinu podle svých cen:

| Příklad | Data a viditelný výsledek |
|---|---|
| Běžná úhrada | Objednávka 2 × 450 Kč, příchozí platba 900 Kč, správný VS, nulový nedoplatek a zaplacené vstupenky |
| Částečná úhrada | Objednávka 900 Kč, platba 450 Kč, zbývá uhradit 450 Kč; žádné předstírání plného zaplacení |
| Doplacení | Jiná objednávka 900 Kč, dvě platby 450 Kč v různých dnech, celkem uhrazeno 900 Kč |
| Přeplatek | Objednávka 900 Kč, platba 1 000 Kč, viditelný přeplatek 100 Kč podle stávajícího finančního modelu |
| Nespárovaná platba | Pohyb s chybným nebo chybějícím VS bez `payment_info`; viditelný u demo účtu, nezvyšuje úhradu žádné objednávky |
| Ruční spárování | Syntetický pohyb s nepřesnou referencí a připravenou historií ručního přiřazení, pokud ji současný detail zobrazuje |
| Nezaplacená objednávka | Žádné transakce, zbývá celá částka; ukazuje rozdíl mezi objednáním a zaplacením |

Cenu 450 Kč přizpůsobit skutečnému demo ceníku; součty se odvozují z produktů, nikoli z nezávisle napsaných statistik. Storno samo nevytváří bankovní vratku. Pokud se přidá příklad již vrácené platby, musí mít vlastní syntetický odchozí pohyb a odpovídat současnému podporovanému modelu; nový systém refundací není součástí zadání.

**Ochrana účtu je samostatná hranice:** účet a nespárovaná transakce nejsou přímo vázané na Occasion. Přidat explicitní serverově spravovanou vazbu demo účtu ke konkrétní verzi ukázky, navrženě unikátní `bank_account` v registru `demo_occasions`. Účet nesmí být sdílený s běžnou Unit/akcí. Ochranu účtu a všech jeho pohybů odvodit z této vazby i bez objednávky; samotná kontrola `order.occasion` nestačí. Neudělovat čtenářům bank-account admin ani správu zdrojové Unit. Povolit pouze potřebné čtení demo účtu a jeho pohybů, nikoli přístup k jiným účtům nebo provozním logům.

Žádný token, bankovní připojení, BankSync operace nebo synchronizace se pro demo účet nezaloží; `is_fetch_enabled` zůstává false a server odmítá pokus připojit účet, vložit token, zapnout import, přepárovat, změnit nebo smazat transakci a připojit účet k běžné Unit. Syntetické vazby a historie párování se připravují při seedu bez volání banky či živého ingestu. Slovo „spárované“ zde popisuje uložený výsledek, nikoli běžící automatizaci.

Při kopírování ukázky se účet, jeho Unit vazby, platební instrukce, transakce a historie párování nepřenášejí. Uživatel nastaví vlastní účet standardní cestou. Kontrola fixture porovná součet přiřazených pohybů, měnu, uhrazenou částku a stav každé objednávky a dokáže, že nespárovaný pohyb neovlivnil její tržbu. Žádná z těchto dat nesmějí ovlivnit souhrny skutečných akcí.

## Občasné storno a změny objednávek

Většina objednávek má běžný průběh. U plesu navrženě 4 z přibližně 95 objednávek obsahují úplné nebo částečné storno a dalších 6 nějakou změnu; přesné počty přizpůsobit fixture. Zachovat 200-300 aktuálních účastníků po změnách, stornované vstupenky do tohoto počtu nezahrnovat. Koncert a víkendovka obsahují po jednom až dvou přirozených příkladech zrušení a změny podle svého rozsahu. Tyto počty jsou výtvarně/provozně zvolený vzorek, nikoli statistika reálných zákazníků.

| Situace | Co uživatel uvidí |
|---|---|
| Úplné storno nezaplacené objednávky | Původní objednávka, pozdější zrušení, neplatné vstupenky a uvolněná místa; žádná vymyšlená úhrada nebo vratka |
| Částečné storno skupiny | Zrušená jedna vstupenka z několika; ostatní zůstávají aktivní, uvolní se pouze příslušné místo; cena a finanční zůstatek odpovídají aktuálnímu kontraktu storna |
| Storno po zaplacení | Platba zůstane v historii, vstupenka se zneplatní; případná nevrácená částka je viditelná podle stávajícího modelu. Označit jako vrácené pouze při existenci odpovídající syntetické vratky |
| Přesun ke společnému stolu | Dvě vstupenky se přesunuly na jiná volná místa stejné ceny, původní místa se uvolnila, cena a skutečně uhrazená částka zůstaly stejné |
| Doplnění vstupenky | Ke dvěma vstupenkám za celkem 900 Kč přibyla třetí za 450 Kč, objednávka má 1 350 Kč a po původní platbě zbývá doplatit 450 Kč; příklad doplatku může následně zůstatek vyrovnat |
| Oprava údajů | Opravené fiktivní jméno nebo odpověď formuláře, bez změny ceny a kapacity |
| Víkendovka | Změna varianty stravy nebo ubytování v existujícím produktovém modelu, případně zrušení účasti; kapacita a případný cenový rozdíl odpovídají výsledku |

Použít existující mechanismy změny/storna a historii `eshop.orders_history`, nikoli samostatnou demo časovou osu. Její aktuální kontrakt ukazují `database/functions/eshop_orders/update_order_responses.sql`, `update_ticket_products_ws.sql`, storno funkce a jejich čtenáři. Před seedem ověřit formát historických snapshotů a přesný význam ceny při částečném stornu; nevnucovat modelu domnělé účetní chování. Přidání vstupenky a přesun míst připravit podle aktuálního standardního objednávkového workflow, včetně případné výměny/revize dokladů, nikoli přepsáním cizích vazeb.

Historie musí ukázat co a kdy se změnilo, dostupného fiktivního autora a skutečně uložené původní i nové hodnoty. Fiktivní důvod doplnit jen do pole, které aplikace již podporuje. Události mají realistické odstupy a následují po založení objednávky. Finální detail, historie, plánek, vstupenky a pohyby musí popisovat tentýž průběh; žádné další záznamy vytvořené jen kvůli počtu scénářů. Příklady lze provázat s platebními scénáři výše.

Scénáře jsou předem připravená data k prohlížení. Návštěvník nemůže změnu nebo storno spustit. Seed neodesílá emaily a nepoužívá živé bankovní operace; uložená historie musí odpovídat tomu, co vytvářejí běžné doménové funkce. Kopie ukázky nepřenáší objednávky ani jejich historii.

Ověřit především nulovou kapacitní stopu stornovaných vstupenek, uvolnění původních a obsazení nových míst, zachování ostatních vstupenek po částečném stornu, rozdíl ceny a plateb po změně a čitelnost historie v existujícím detailu. Do jednoho E2E průchodu plesu zahrnout částečné storno a změněnou objednávku, bez samostatné testovací infrastruktury.

## Vizuální a obsahová kvalita jako součást dokončení

Každá ukázka má jeden vlastní výtvarný směr napříč úvodním obrázkem, formulářem, plánkem a vstupenkou. Sdílí paletu, motiv a typografickou hierarchii v mezích stávajících editorů. Administrace zůstává ve společném designu aplikace; nevytvářet tři odlišné skiny nebo komponentové systémy. Následující směry jsou návrhy pro první zpracování, nikoli povinné nové značky:

| Akce | Výtvarný směr | Vstupenka a plánek |
|---|---|---|
| Ples | Elegantní krémová, tmavá lesní zelená a střídmý zlatý akcent; jemný ornament, vzdušná sazba | Výrazný název večera, dobře čitelný stůl/místo a datum; sál působí jako profesionální plán prostoru, s pravidelným rozmístěním a jasně odděleným parketem |
| Koncert | Výrazná plakátová typografie, antracit a jeden živý akcent, vlastní grafický motiv | Dominantní interpret/název, kategorie a čas; plánek jasně rozliší sezení, stání, pódium a vstupy |
| Víkendovka | Přírodní odstíny, teplá světlá plocha a jemná ilustrace krajiny | Civilní pobytová vstupenka s termínem a místem; přehledný areál a ubytování, nikoli styl koncertního sálu |

**Plánky:** vyjít z ověřené referenční geometrie a upravit ji ve stávajícím blueprint editoru/vieweru. Použít konzistentní velikosti objektů, rozestupy a číslování; žádná překrytá sedadla, popisky ani nečitelná legenda. Pódium, stoly, uličky, parket, vstupy a zázemí musí vytvářet uvěřitelný celek. Přehled celého sálu se vejde do výchozího pohledu a detail po přiblížení dovolí přečíst čísla míst. Volno/prodáno se pozná i jinak než samotnou barvou, s použitím možností současného vieweru. Mobil umožní pohodlné přiblížení a posun bez ztráty orientace. Plánek nesmí být jen obrázek s neprovázanými tečkami; viditelné místo a jeho detail musí odpovídat produktu a objednávce.

**Vstupenky:** vytvořit jednu dotaženou výchozí šablonu pro každý typ akce, varianty kategorií řešit datovými vazbami existujícího layoutu. Použít aktuální `ticket.layout` schema 3 a společný PDF renderer popsaný v `lib/components/ticket_layout/README.md`. Začít dostupnými presety a vhodnými historickými podklady, jejichž metadata jsou v `test/fixtures/ticket_layout/historical/`; původ a možnost použití konkrétního obrázku ověřit před převzetím. Vizuální kvalita nesmí záviset na novém rendereru nebo novém editoru.

Název, datum, místo, kategorie, případně stůl/sedadlo, cena a identifikátor mají jasnou hierarchii. Proměnné texty zůstávají datovými prvky layoutu, nikoli součástí bitmapy, aby vlastní kopie neměla zapečený název a datum ukázky. Použít podporované fonty s českou diakritikou. Ověřit krátké i dlouhé jméno, dlouhou kategorii a chybějící nepovinný údaj bez překryvů nebo nevhodných prázdných bloků. Pozadí má dostatečné rozlišení pro cílovou velikost tisku; QR a text renderovat stávajícími prostředky, QR nepřidávat do dekorativního obrázku. Zachovat minimálně 60 pt a bílou ochrannou zónu QR podle současného rendereru. QR musí jít dekódovat na syntetický údaj a současně nesmí umožnit skutečné odbavení.

Označení „UKÁZKA - NEPLATÍ PRO VSTUP“ patří do serverem odvozené prezentace demo výstupu, ne trvale do kopírované grafiky. Umístit jej čitelně mimo QR a hlavní údaje. Při vzniku běžné kopie označení zmizí, grafická kvalita zůstane. Read-only uživatel může otevřít a stáhnout označený ukázkový PDF výstup přes autorizovaný read-only render; tento krok nic neodesílá a nemění objednávku, stav vstupenky ani uložený layout.

**Formuláře a texty:** lze převzít věcnou strukturu i vhodné formulace reálných popisů, nápověd, pokynů k výběru místa, cenových kategorií, stravy a ubytování. Zdroj zapsat do manifestu. Upravit název pořadatele, datum, kontakty, ceny a odkazy tak, aby celek odpovídal fiktivní akci. Nepřebírat vyplněné odpovědi, soukromé poznámky ani identifikátory zákazníků. Neponechat odkazy na skutečný prodej nebo platební instrukce referenční akce. Texty mají být přirozené a konkrétní, bez lorem ipsum a opakovaných generických odstavců. Pole i nápovědy musí odpovídat tomu, co lze opravdu vybrat v produktech a plánku.

**Vizuální důkaz:** pro každou ukázku uložit screenshot skutečného plánku, formuláře a vstupenky z aplikace a PDF z finálního uloženého layoutu. Jeden společný statický přehled těchto výstupů může sloužit k rychlé kontrole všech tří stylů. Kontrola je součástí implementace, ne nový schvalovací krok: ověřit desktop, mobilní šířku 390 px, detail míst, české znaky, dlouhé údaje a PDF v zamýšlené tiskové velikosti. Samotný hezký obrázek nebo náhled v editoru bez ověření výsledného PDF nestačí. Opravit zjištěné vady před dokončením.

## Efektivní postup a omezení rozsahu

- Jedna cílená inventura referencí: plánek, produkty, formulářové popisky, ticket layout a grafické podklady. Zapsat pouze vybraný zdroj a rozhodnutí o použití do manifestu; neprovádět export celých reálných akcí nebo opakované průzkumy stejného obsahu.
- Nejprve připravit ples jako svislý průřez: vizuál + plná syntetická data + prohlížení + čistá kopie. Stejné funkční části potom použít pro koncert a víkendovku. Všechny tři ukázky zůstávají podmínkou dokončení.
- Sdílet katalog, oprávnění, kopírování a deterministické generování fixture. Odlišnosti akcí uložit jako data. Nevytvářet obecný marketplace šablon, nový systém správy verzí ani editor ukázek; verzované seed soubory a jednoduchý registr stačí.
- Katalog vrací jen metadata karet a verzi. Detail, velké plánky, účastníky a PDF načítat až při otevření a používat existující stránkování a cache. Registrace ani domovská obrazovka negeneruje PDF a nenačítá stovky účastníků všech ukázek.
- Ochrany soustředit do existujících autorizačních a servisních hranic, kde skutečně pokryjí volající. Seznam cest z vlny 1 slouží jako důkaz pokrytí; není požadavkem přidat redundantní podmínku do každé funkce. Cesty obcházející společnou hranici potřebují vlastní ochranu.
- Validaci dávkovat po funkčních celcích. SQL a modelové testy pro společnou mechaniku, jeden E2E průchod plesu a krátká kontrola specifik koncertu a víkendovky. Vizuálně zkontrolovat všechny tři styly a jejich PDF; neprovádět celou testovací matici znovu pro každou změnu popisku.

## UI/UX nabídky podle vlastních akcí

Použít jeden sdílený blok ukázek se dvěma způsoby zobrazení. Vložit jej do relevantního domovského přehledu a správy akcí, nikoli do všech obrazovek nebo nad právě rozpracovaný editor.

| Stav | Zobrazení a akce |
|---|---|
| Uživatel zatím nemá vlastní akci ani rozpracovaný návrh | V hlavní obsahové oblasti nad prázdným seznamem nabídnout „Podívejte se, co můžete vytvořit“ a krátké vysvětlení „Prohlédněte si hotovou akci a vytvořte si vlastní kopii.“ Následují tři vizuální karty Ples, Koncert, Víkendovka s obrázkem, jednou větou o obsahu a štítkem „Ukázka“. Hlavní akce každé karty je „Prohlédnout ukázku“. Existující tlačítko „Vytvořit akci“ zůstává dostupné pro přímé založení. |
| Uživatel má vlastní akci nebo rozpracovaný návrh | Prioritu mají vlastní akce a pokračování návrhu. U záhlaví přehledu zobrazit pouze sekundární textový odkaz „Inspirujte se ukázkovými akcemi“; teprve jeho aktivace rozbalí stejnou trojici karet. Nabídka nevytlačuje vlastní seznam a sama se neotevírá při každém návratu. |
| Právě vytvořil první vlastní akci/kopii | Aktualizovat seznam bez reloadu celé aplikace, zobrazit vytvořenou akci a nabídku ukázek převést do kompaktního stavu. Otevřít nastavení kopie podle kopírovacího kontraktu. |
| Filtr nevrátil žádnou akci | Zobrazit běžný prázdný výsledek hledání. Nezaměnit jej za nový účet a nerozbalovat onboarding ukázek. |
| Data se načítají nebo selhalo načtení | Použít stávající loading/error vzory. Dokud není znám skutečný počet vlastních akcí, nepřeskakovat mezi výraznou a kompaktní variantou. Výpadek katalogu ukázek nesmí zablokovat vlastní akce ani založení nové. |

„Vlastní“ znamená nedemo akce, které uživatel může spravovat v aktuálním tenant kontextu, včetně minulých/skrytých akcí a dostupných rozpracovaných návrhů. Pouhá účast na cizí akci se nepočítá. Stav určit z autorizovaného nefiltrovaného přehledu nebo levného serverového existence příznaku, nikoli ze seznamu viditelného po hledání. Změna zobrazené Unit nesmí uživateli s vlastními akcemi jinde v témže tenantovi vnucovat onboarding znovu. Pro uživatele bez Unit musí katalog fungovat samostatně. Nepřidávat persistentní onboarding workflow nebo sledování kliknutí jen kvůli těmto dvěma variantám.

Na desktopu mohou být tři karty v jednom řádku, na mobilu v jednom sloupci, bez horizontálního karuselu a automatického posouvání. Karty mají jednotnou geometrii, čitelné popisky a viditelné ovládání klávesnicí. Obsah krátkých popisků například: Ples „Místa u stolů, objednávky a platby“, Koncert „Vstupenky, sektory a odbavení“, Víkendovka „Přihlášky, ubytování a náhradníci“. Žádné vyskakovací okno po registraci ani povinná prohlídka.

Uvnitř ukázky ponechat stabilní, úsporný banner „Ukázková akce - pouze k prohlížení“, jedno hlavní CTA „Vytvořit vlastní kopii“ a jasnou cestu zpět k vlastním akcím. Po návratu zachovat filtr a pozici vlastního seznamu. Copy akce není rozesetá jako několik stejně výrazných tlačítek na každé kartě a panelu. Použít existující komponenty, lokalizaci, barvy a typografii aplikace.

Ověřit oba stavy na desktopu a 390 px, nulové výsledky filtru, existující návrh, uživatele bez Unit a přechod po první kopii. Doložit jeden screenshot výrazné a jeden kompaktní varianty; pro změny textů nepřidávat křehké screenshotové snapshot testy.

## Důkazy ze současného kódu

| Fakt | Důkaz | Důsledek |
|---|---|---|
| Správa seznamu, otevření administrace a kopírovací dialog jsou společně | `lib/components/unit/views/occasions_screen.dart`: `_handleView`, `_handleCreateCopy`; `occasion_edit_card.dart` | Navázat katalog ukázek na existující seznam, upravit volbu cíle pro zdroj mimo uživatelovu Unit |
| Domovský přehled má vlastní seznam veřejných akcí | `lib/components/unit/views/unit_page_base.dart`: `_loadDataForUnit`; `db_units.dart` | Nestačí přidat ukázky pouze do administrace; nově registrovaný uživatel nemusí mít Unit |
| Existují oprávnění ke čtení administrace a objednávek oddělená od zápisu | `lib/data_services/rights_service.dart`: `canSeeAdministration`, `canSeeReservations`, `isEditorView`, `isEditorOrderView`; `database/tables/tables.sql`: `occasion_users` | Rozšířit čtení o serverem doložený demo přístup; nepřidělovat editor/manager role |
| Administrativní routy mají přístupovou hranici | `lib/components/navigation/occasion_administration_boundary.dart` | Demo čtení musí projít stejnou routovací kontrolou, včetně přímých odkazů |
| Kopírování kontroluje správu zdroje i cíle a shodu tenantů | `database/functions/others/duplicate_occasion.sql`: `duplicate_occasion_internal_v1`; `duplicate_occasion_client_sync_v1.sql`: stejnojmenná RPC a `get_occasion_copy_units` | Prosté použití současné RPC běžným čtenářem ukázky selže; změna patří do serverové autorizační politiky |
| SQL kopie již mapuje program, plánky, produkty, místa, formuláře a šablony; u míst nuluje rezervace | `database/functions/others/duplicate_occasion.sql` | Použít jeden kopírovací mechanismus; inventář a všechny nové konfigurace ověřit jako úplnost kontraktu |
| Kopie dostává práva pro autora, receipt a aktualizaci katalogu cílové Unit | `database/functions/others/duplicate_occasion_client_sync_v1.sql` | Zachovat idempotenci a synchronizační kontrakt |
| Médium se kopíruje po SQL commitu; selhání ponechá již vzniklou akci | `lib/components/occasion/db_occasions.dart`: `duplicateOccasion`; `occasion_media_copier.dart`: `copyOccasionMedia` | Vrátit ID výsledku i při částečném selhání, retry médií nesmí vytvořit druhou akci |
| Automatické úlohy a jediná emailová fronta mají doménové vedlejší efekty | `database/functions/seed/crons.sql`; `docs/architecture/ai_context.md` | Uzavřený formulář sám nezaručuje neměnnost fixture; je nutná ochrana automatických producentů a konzumentů |
| Účty se vážou k Unit, transakce k účtu a volitelně k payment_info; oprávnění účtu jsou samostatná | `lib/components/bank_accounts/README.md`; `database/tables/tables.sql`: `bank_accounts`, `transactions`, `transaction_pairing_events`; `database/functions/eshop_transactions/get_transactions_for_order.sql` | Demo účet potřebuje explicitní ochranu i pro nespárované pohyby a samostatné read oprávnění; využít stávající finanční model |
| Ticket layout má sdílené presety, fonty, lokální náhled a jediný PDF renderer; dostupná je historická galerie podkladů | `lib/components/ticket_layout/README.md`: `ticketGeneration.ts`, `drawLayoutTicket`, schema 3, Local historical-reference gallery | Tři stylové šablony připravit jako uložené konfigurace; ověřit finální PDF a kopii, nezavádět další renderovací cestu |

## Vlastnictví a serverový kontrakt

Přidat kanonický serverový registr, navrženě `public.demo_occasions`, s `occasion` jako unikátním klíčem, `organization`, `demo_key` (`ball`, `concert`, `weekend`), `fixture_version`, `is_listed`, pořadím a krátkým popisem. Unikátní je trojice Organization + demo_key + fixture_version; částečný unikátní index na Organization + demo_key WHERE is_listed dovoluje nejvýše jednu zveřejněnou verzi každého typu. Tím lze připravit novou verzi nezveřejněnou a zároveň ponechat ochranu staré. Přepnutí staré a nové verze provést atomicky; registrované staré zdroje se běžným čtenářům a novým kopiím již nenabízejí. Vazba na Occasion a Organization musí být konzistentní serverově. Identita chráněné ukázky plyne z registru, nikoli z klientem upravitelného `occasions.data` nebo URL.

Rozlišit **je chráněná ukázka** od **je zobrazena v katalogu**. Stažení ukázky z nabídky ji nezmění na běžnou zapisovatelnou akci. Registr se neupravuje běžnou aplikací. Údržba je explicitní verzovaný SQL/seed postup s provozní autoritou, nikoli skrytý přepínač v UI.

- Čtení: přihlášený uživatel v aktuálním oprávněném tenant kontextu dostane katalog a omezený přístup pouze k vybraným ukázkám. Stejná politika pokryje RPC, RLS, synchronizační projekce a média. Nepřidávat členství každému registrujícímu se uživateli.
- Cache a offline projekce musí rozlišovat tenant, zdrojovou akci a verzi; při změně kontextu nesmí přenést demo read oprávnění do běžné akce. Nesdílet přes demo přístup širší Unit katalog, uživatelské profily nebo soukromá média mimo schválenou fixture. Při stažení verze odmítnout nové čtení/kopírování serverově a invalidovat příslušný katalog.
- Prohlížení: použít stávající administrativní pohledy pro nastavení, plánky, program, formuláře, účastníky, objednávky a vstupenky. Nastavení lze vidět, ale nelze uložit. Neměnit běžné akce na read-only.
- Zápis: jeden serverový predikát pro ochranu zdrojové ukázky musí být použit na všech relevantních hranicích. SQL/RLS chrání přímé tabulkové zápisy i RPC; Edge a image worker odmítají upload, kopii do zdroje a mazání zdrojových médií. Ochrana platí i při zděděných tenant právech; údržba fixture je oddělená.
- Zakázané změny zahrnují také přihlášení uživatele, výběr/rezervaci místa (`select_spot`), objednávku, sken QR, platbu, storno, import, publikaci, zasílání a formulářové odeslání. Veřejné endpointy nesmí obejít demo omezení ani anonymně. Navigace, zoom, filtrování a otevření detailu jsou možné.
- Vedlejší efekty: demo entity nesmějí vstupovat do bankovního párování, fakturace, odesílání emailů, připomínek, expirace čekací listiny ani úloh měnících data. Jejich statistiky se zobrazí v ukázce; reálné provozní souhrny je vyloučí. Použít tentýž serverový predikát, ne emailový suffix jako ochranu. Tato změna je lokální k demo entitám, nepřestavuje platební ani emailový subsystém.
- Kopie: zachovat `duplicate_occasion_client_sync_v1` jako jediný veřejný receipted kopírovací příkaz. Pro běžný zdroj zůstává současná politika; pro registrovanou ukázku nahradit požadavek správce zdroje oprávněním jejího čtenáře. Cíl vyžaduje stávající právo správce Unit a stejnou Organization. `get_occasion_copy_units` musí použít přesně stejnou politiku a nikdy nenabídnout demo Unit jako cíl.
- Vnitřní implementace kopie nesmí ponechat starou kontrolu, která novou politiku zablokuje, ani obejít oprávnění pro ostatní volající. Pokud se extrahuje interní kopírovací část, nemá přímý grant pro authenticated/anon a každý její wrapper explicitně autorizuje zdroj i cíl. `SECURITY DEFINER` má `search_path = public, extensions`.
- Retry používá stejné `command_id` a stejný payload. Změna cíle se stejným ID je konflikt. Kopírování samotné zdroj nemění a nevyžaduje uvolnění ochrany.

## Co přesně vytvoří kopie

Zkopírovat popis, nastavení funkcí, program, místa, informační stránky, strukturu formulářů, produkty a ceny, plánky, služby, odpovídající kapacitní konfiguraci inventáře, emailové šablony a ticket layout. Přemapovat všechny ID v relacích i JSON, včetně pravidel kapacit a referencí v šablonách. Nové odkazy a klíče jsou unikátní, vlastník a ancestry patří cílové Unit. Zdrojové média musí být dostupné i pro povolenou operaci kopírování; ověřit také obrázky vložené v HTML, plánky a obrázky v jednotlivých ticket templates, které současný `copyOccasionMedia` výslovně nepokrývá.

Nekopírovat registraci do demo katalogu, přístupová práva zdroje, `occasion_hidden` s identitami/tajnými údaji, Auth identity, účastníky, programové přihlášení, objednávky, vystavené lístky, transakce, faktury, přijetí na recepci, nabídky čekací listiny, rezervace ani obsazenost inventáře. Potřebnou neveřejnou konfiguraci kopírovat explicitně do nových řádků, nikoli sdílením zdrojového FK. Autor získá existující běžná práva správce výsledné akce.

Kopie je běžná editovatelná akce, ale první stav je skrytý, nepropagovaný a s uzavřenými formuláři. Bankovní napojení a externí integrace se nepřenášejí. Použít existující kopírovací dialog s volbou cíle a po dokončení otevřít nastavení nové akce, kde uživatel upraví název a termín. Samostatný nový průvodce a automatický posun všech časových pravidel nejsou podmínkou této funkce. Uživatel vidí, že musí zkontrolovat datum akce i programu, ceny a platby před otevřením prodeje. Pokud současné nastavení již podporuje posun programu, znovu použít jeho pravidla. Zdrojové vzorové finanční hodnoty se nepropisují do výsledné historie. Demo označení PDF je odvozené ze zdroje a do běžné kopie se nepřenese.

## Implementační vlny

### 0. Jedna referenční a výtvarná příprava

**Změny:** vybrat referenci plesu a vhodné existující formulářové texty; zapsat zdroj a přizpůsobené údaje do manifestu budoucí fixture. Pomocí existujících editorů/presetů připravit první plánek a uložitelný ticket layout plesu. Z něj ověřit skutečný PDF výstup ještě před hromadným generováním objednávek. Pro koncert a víkendovku určit jednu paletu a motiv podle vizuálního zadání výše.

**Ověření a hotovo:** geometrie plesu pojme požadovaný počet účastníků, plánek je přehledný a skutečné PDF má čitelný text i dekódovatelný syntetický QR. Zaznamenané podklady neobsahují zákaznická data. Nečekat na novou uživatelskou autorizaci designu; pokračovat podle tohoto zadání a doložit výsledek v handoffu.

Vlny 1-4 nejprve propojit na plesu. Po ověření společné mechaniky doplnit ve vlně 2 obsah koncertu a víkendovky a ve vlně 4 jejich specifické průchody. Nedokončovat všechny obrazovky a všechna data třikrát odděleně.

### 1. Registr a ochrana zdrojů

**Změny:** přidat registr do `database/tables/tables.sql` a verzované migrace podle současného repo workflow. Funkce dát do `database/functions/others/`. Implementovat katalog, serverový demo predikát a autorizační pravidla. Cíleně projít producenty a čtenáře v `database/functions/{user_permissions,events,eshop,eshop_orders,eshop_forms,inventory,emails}`, aktuální RLS a odpovídající Edge/image-worker hranice. Sepsat jejich přesný seznam do implementačního evidence souboru; pro každou cestu určit zákaz zápisu nebo povolený read-only přístup. Zahrnout crony a synchronizační projekce.

**Migrace / kompatibilita:** přidání registru nesmí změnit oprávnění žádné běžné akce. Bez persistovaných aplikačních triggerů, bez podvržených editor rolí. Nenaplněný katalog je validní stav. Přímé přepnutí `is_listed` nikdy neruší ochranu.

**Ověření:** nové cílené SQL testy s běžným authenticated, privilegovaným uživatelem, anon a automatickým workerem. Přečtení jiného tenanta je zamítnuto; reprezentativní zápisy (včetně rezervace a objednávky bez loginu) jsou zamítnuty před vedlejším efektem. Testovat výslovně cron/email/fakturaci a běžnou akci jako kontrolu.

**Hotovo:** katalog umí vrátit pouze oprávněné ukázky; žádná aplikace ani automatická úloha nemění registrovaný zdroj.

### 2. Tři reprodukovatelné kompletní fixture

**Změny:** připravit verzované SQL fixture a manifest médií pod `database/fixtures/demo_occasions/` (nová cesta). Nejprve vybrat a zaznamenat strukturální referenci plesu (skautský nebo Větřkovice), původ plánku a způsob převzetí konfigurace bez osobních či transakčních dat. Použít skutečné vazby existujícího modelu, realistické plánky a 200-300 fiktivních účastníků plesu. Seed má explicitní tenant vstup, předběžné kontroly a stabilní verzi; opakování stejné verze nevytvoří další trojici. Novou verzi nejprve sestavit nezveřejněnou, ověřit a až potom přepnout katalog. Nikdy nemazat uživatelské kopie.

**Vedlejší efekty:** fixture vzniká kontrolovaným SQL postupem, který nevyvolává reálné objednávkové emaily, Auth pozvánky, platby ani faktury. Fiktivní zaplacení je podloženo syntetickými transakcemi na demo účtu a konzistentními vazbami na payment_info; žádný skutečný bankovní převod ani bankovní import se neprovádí. Připravit scénáře finančního přehledu výše včetně nespárovaného pohybu. Žádné čtení produkčních účastníků pro inspiraci.

**Ověření:** SQL integritní testy na odkazy, kapacity, počet vstupenek a obsazenost; ples má skutečně 200-300 fiktivních účastníků, nikoli jen tolik míst. Ověřit pořadí objednávka -> zaplacení -> odbavení, uvolnění stornovaných míst a čas programu přes půlnoc. Plánky mají odpovídající místa a produkty. Seed dvakrát zachová přesně tři zdroje. Prohlížení ani běh úloh nezmění jejich doménová data a nevytvoří emailové/outbound záznamy.

**Hotovo:** všechny tři scénáře mají úplná navazující data, média a konzistentní statistiky, včetně fiktivních účtů a transakcí; každý má vlastní dotažený styl, finální PDF vstupenky a formulář s věrohodnými popisky podle vizuálních kritérií výše. Výstupy a původ podkladů jsou doložené manifestem. Nejprve pouze lokální fixture, produkční seed zůstává samostatným krokem.

### 3. Kopírování ukázky do vlastní Unit

**Změny:** upravit autorizační politiku v `duplicate_occasion.sql`, `duplicate_occasion_client_sync_v1.sql` a `get_occasion_copy_units`; sdílet kopírovací jádro. Doplnit úplnost kopie inventáře, citlivých dat a referencí. V `occasion_commands.dart` a `db_occasions.dart` předávat/vracet stabilní ID příkazu a ID výsledné akce; navázat otevření existujícího nastavení výsledku. V `occasion_media_copier.dart` zahrnout všechna média definovaná manifestem a zachovat obnovitelnost po SQL commitu. Obrázky a další aktiva výsledku mají vlastní životní cyklus.

**Chyby / kompatibilita:** lokální práva autora nebo vyprázdněný cílový seznam neudělují právo zapisovat do cizí Unit. Síťový timeout se dohledá přes receipt; dvojklik/retry nevytvoří duplicitu. Při selhání médií zobrazit existující výsledek s možností dokončit média. Nepoužívat nové založení jako recovery. Běžná duplikace zachová dosavadní chování mimo výslovně sdílené opravy nutné pro kontrakt.

**Ověření:** rozšířit `database/tests/duplicate_occasion_target_unit_test.sql`, `duplicate_occasion_creator_editor_test.sql` a nové demo copy testy: čtenář ukázky -> oprávněný cíl, neplatný cíl, jiný tenant, běžný zdroj bez správy, retry a konflikt command ID. Ověřit nulové prodeje/obsazenost, úplné mapování FK/JSON a editovatelnost výsledku. Dart test na částečné selhání médií.

**Hotovo:** ukázku lze jednou zkopírovat bez správy zdroje; vznikne pouze běžná vlastní čistá akce a originál se nezmění.

### 4. Dostupnost a prohlížení v UI

**Změny:** katalog a sekci napojit v `unit_page_base.dart`, `occasions_screen.dart` a skutečné vstupní obrazovce uživatele bez Unit (dohledat z post-login navigace v `signup_page.dart` a `RouterService.handlePostLoginNavigation`). Karty označit „Ukázka“, uvnitř trvale „Ukázková akce - pouze k prohlížení“ a CTA „Vytvořit vlastní kopii“. Upravit read capabilities v `rights_service.dart`, routovací hranici a read-only stavy jednotlivých pohledů bez udělení write rolí. Použít `*_strings.dart` a existující lokalizační soubory.

**Interakce:** žádné Uložit, Smazat, Importovat, Odeslat, Skenovat ani výběr místa s rezervací. Formulář lze přečíst, ale neodeslat. Lze otevřít označenou ukázkovou vstupenku a stáhnout její PDF bez zápisu do objednávky. Kopírovací dialog ukáže cíl a co se nepřenáší; po vytvoření otevře nastavení kopie s upozorněním na kontrolu termínů. Chybějící cíl vede k oprávněnému založení Unit, pokud je dovoleno. Samotné zobrazení ukázek nesmí zapisovat účast nebo spotřebu kapacity. Přepnutí do vlastní akce obnoví její standardní práva.

**Ověření:** cílené Flutter testy na prázdný a naplněný účet, read-only pohledy, přímou routu, návrat do běžné akce a kopírovací dialog. Pro šíři interakcí jeden průchod izolovaným lokálním E2E dle `festapp-local-e2e` a `agent-browser`, bez uživatelova prohlížeče. Veřejný JS formulář musí odmítnout odeslání ukázky, i pokud se otevře jeho přímý odkaz.

**Hotovo:** uživatel s akcemi i bez nich najde všechny tři ukázky, prohlédne související data a vytvoří oprávněnou vlastní kopii.

## Ověřovací příkazy pro implementaci

Do SQL testů demo oprávnění a fixture zahrnout účet bez bankovního připojení, čtení nespárované transakce, zákaz změn účtu/párování/importu i pro uživatele se zděděnými právy a zákaz vazby na běžnou Unit. Do copy testu přidat nepřenesení účtu a finanční historie. V E2E plesu otevřít účet, seznam pohybů a objednávku s částečnou/dělenou platbou; doložit shodu částek a pouze čtecí ovládání. Použít existující pohledy v `lib/components/bank_accounts/views/` a transakční detail objednávek, ne druhou demo bankovní aplikaci.

Plán samotný nevyžaduje běh testů. Implementace použije lokální izolovanou DB a cílené testy, nikoli produkci jako testovací prostředí:

```sh
DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' node web_client/scripts/run_db_tests.js database/tests/demo_occasions_test.sql
DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' node web_client/scripts/run_db_tests.js database/tests/demo_occasion_copy_test.sql
DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' node web_client/scripts/run_db_tests.js database/tests/duplicate_occasion_target_unit_test.sql
DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' node web_client/scripts/run_db_tests.js database/tests/duplicate_occasion_creator_editor_test.sql
```

Nové testové soubory výše jsou plánované. Flutter analyzovat cíleně přes `fvm dart analyze <dotčený_soubor>` a spustit související `fvm flutter test <soubor_testu>`. Pro změněné Edge funkce, JS klienta a image worker použít jejich existující cílené testovací příkazy. Všechny nutné bezpečnostní hranice musí mít behaviorální důkaz; samotné skrytí tlačítek není ověření oprávnění.

## Nasazení, návrat a ponechané cesty

Jde o přidání funkce, žádná dosavadní akce se neruší. Ponechat běžnou duplikaci a její existující klientské fasády; není zde zadána jejich migrace. Nepřidávat druhý demo objednávkový systém, registrační seed pro každého uživatele nebo klientskou autorizační výjimku.

Produkční migrace, seed, upload a release vyžadují samostatné zadání a výběr jednoho tenanta. Pořadí: ochrana a registr -> lokálně ověřená fixture na vybraném tenantovi -> oprávněné read/copy kontrakty a média -> UI -> zveřejnění katalogu. Nešířit automaticky na další `prod/*` větve. Údržba fixture nezasahuje do již vytvořených kopií.

Při návratu skrýt katalog a vypnout kopírování demo zdrojů, ale ponechat ochranu a filtr vedlejších efektů tak dlouho, dokud existují demo data. Starší klient musí být bezpečně odmítnut serverem. Běžné vytvořené kopie se nemažou.

## Definice dokončení a zbývající rizika

- Přesně tři kompletní ukázky jsou dostupné novým i stávajícím uživatelům v povoleném tenant kontextu.
- Ples vychází z doložené struktury skautského nebo větřkovického plesu, má 200-300 fiktivních účastníků a realistický program i časovou historii. Žádné osobní či transakční údaje skutečných lidí nejsou převzaté.
- Uživatel vidí fiktivní účet, transakce a jejich vazby na objednávky včetně nedoplatku, přeplatku a nespárovaného pohybu. Finanční součty sedí; účet se nikdy nepřipojuje k bance a nevytváří použitelné instrukce pro platbu. Vlastní kopie tento účet ani historii neobsahuje.
- Menšina objednávek ukazuje storno a změny s existující historií. Jejich výsledné ceny, platby, vstupenky a obsazenost souhlasí; storno nepředstírá automatické vrácení peněz a ukázku nelze změnit návštěvníkem.
- Víkendovka obsahuje skutečnou čekací listinu se syntetickými náhradníky a historií nabídnutí a přijetí uvolněného místa. Počty přijatých, čekajících a kapacita souhlasí; čekající nemají platné vstupenky ani finance a návštěvník nemůže měnit nabídky.
- Každá akce má sladěný plánek, formulář a stylovou vstupenku odpovídající jejímu charakteru. Doložené screenshoty a finální PDF splňují vizuální kritéria; QR je čitelný, texty nepřetékají a vlastní kopie zachová grafiku bez demo označení a zapečených údajů zdroje.
- Zdroj není zapisovatelný přes UI, RPC, přímé tabulky, veřejné formuláře, média ani automatické úlohy; read-only režim nezvyšuje role.
- Kopie vzniká idempotentně ve spravované vlastní Unit, je běžně editovatelná a nemá fiktivní účastníky, prodeje ani obsazená místa.
- Program, formuláře, inventář, plánky a ticket layout kopie mají vlastní správně mapované reference a média; selhání po commitu lze dokončit bez druhé kopie.
- Cílené oprávnění a regresní testy pro běžné akce procházejí. Žádná paralelní demo doménová implementace nevznikla.

Největší riziko je neúplná ochrana automatických nebo veřejných zápisových cest a neúplnost současného kopírování novějších konfigurací. Proto se katalog nesmí zveřejnit před doložením těchto hranic. Konkrétní vizuální podklady a případný jiný požadovaný obsah kopie lze upřesnit před implementací; produkční aktivace zatím není autorizovaná.
