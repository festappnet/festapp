# Detail objednávky - specifikace vybrané varianty A

Datum: 1. 11. 2026. Uživatel vybral variantu A: kontextový panel vedle objednávek, na úzké obrazovce celoplošný detail. Tento dokument zpřesňuje rozhraní před implementací. Nemění aplikaci, databázi ani HTML prototyp.

Implementace a skutečná lokální kontrola: [záznam](evidence/order-detail-local-review.md). Produkční nasazení nebylo provedeno.

## Cíl a závazné rozhodnutí

Správce má z jednoho detailu zjistit, kdo objednal, co skutečně patří do objednávky, kde jsou místa, jaká je platební situace a co se stalo se zprávami. Každá další akce má mít jedno srozumitelné místo. Běžná kontrola objednávky nesmí vyžadovat sérii dialogů ani procházení široké tabulky.

**Zvolená struktura: Přehled / Vstupenky a místa / Platby / E-maily / Historie.** Otázky formuláře jsou u příslušné objednávky nebo účastníka, nikoli automaticky v šesté záložce. Rozšíření panelu je volitelný režim téže otevřené objednávky; není to návrat k výběru varianty C.

[Dosavadní prototyp](../prototypes/order-detail-prototype-2026-11-01.html) je datovaný průzkumný podklad pro volbu A. Neprokazuje hotový návrh sálu, složitých plateb, kompletních formulářových odpovědí ani nového rozložení popsaného zde. Přepínače B/C v něm jsou historie rozhodování, nikoli otevřená otázka tohoto plánu.

## Rozvržení a práce s kontextem

Panel se na desktopu otevře vedle gridu bez překrytí jeho zbývající plochy. Doporučená výchozí šířka je 600 px, nastavitelná v rozmezí přibližně 520-760 px pouze tehdy, zbude-li alespoň 480 px pro tabulku. Rozhoduje dostupná pracovní šířka po odečtení navigace, nikoli samotný rozměr okna. Pokud oba prostory nelze zachovat, detail zabere pracovní plochu. Na telefonu se zobrazuje přes celou obrazovku včetně bezpečných okrajů.

V detailu jsou tři stabilní části: kompaktní hlavička, pás záložek a jeden svisle posuvný obsah aktivní záložky. Žádný samostatně posuvný formulář uvnitř dalšího posuvného seznamu. Výjimkou je prostor pro zoom/pan plánu sálu, který se ovládá záměrně a má vlastní návrat do výchozího pohledu. Akce rozpracovaného editoru se na úzkém displeji drží u spodního okraje editoru tak, aby nepřekrývaly poslední pole ani klávesnici.

Hlavička obsahuje:

- „Objednávka 260184“, akci kopírování čísla, zákazníka a název formuláře, pokud existuje více formulářů.
- Obchodní stav objednávky jako textový štítek. Doručení e-mailu se do tohoto štítku nemíchá. „Zaplaceno“ samo neznamená uhrazený celý doplatek.
- Předchozí/další objednávku v aktuálním filtrovaném a seřazeném seznamu, rozšíření/zúžení a zavření. Na mobilu lze přesun mezi objednávkami zkrátit na pojmenované šipky.
- Nabídku „Další akce“ pouze pro skutečně dostupné operace nad celou objednávkou, například úpravu jejího obsahu nebo zrušení. Odeslání, platby a vstupenky zde nemají duplicitní hlavní tlačítka.

První otevření těla řádku míří na Přehled. Kontextový vstup míří přesně: problém doručení do E-mailů na zprávu, finanční upozornění do Plateb, místo do Vstupenek a míst. Předchozí/další zachovává aktuální záložku, pokud je pro cílovou objednávku relevantní; jinak přejde na Přehled s krátkým vysvětlením. Konkrétní vybraný ticket nebo zpráva se na další objednávku nepřenáší.

Filtry, řazení, checkboxy, šířky sloupců a scroll gridu přežijí otevření, rozšíření i zavření. Otevřená objednávka je vizuálně odlišná od hromadně vybrané. Klik na checkbox, kopírování nebo jiný vložený ovladač neotevírá řádek. Textový výběr v buňce nesmí nechtěně otevřít detail.

Pokud změna filtru vyřadí otevřenou objednávku, panel zůstane s textem „Tato objednávka neodpovídá aktuálním filtrům“ a bez předchozí/další; uživatel nepřijde o práci. Nelze si potichu vybrat jiný řádek. Otevření přes notifikaci se řídí oprávněním k dané objednávce i tehdy, když objednávka není ve viditelné stránce gridu.

## 1. Přehled: kdo objednal a co nyní potřebuje pozornost?

Obsah v pořadí shora dolů:

1. **Důležitý další krok**, jen pokud existuje: doplatek po splatnosti, neověřený výsledek odeslání, nedoručená zpráva, čekající nabídka kapacity. Stručná věta a jeden odkaz do správné záložky. V případě více problémů ukázat nejvýše dva samostatné řádky a odkaz na zbývající; nezaměnit problém platby s problémem doručení. Bez problému se nevyrábí zelený úspěšný panel.
2. **Kontakt zákazníka:** jméno, aktuální e-mail, telefon pokud existuje. Vedle e-mailu „Upravit e-mail“, nezávisle na výsledku doručení. Chybějící kontakt je „E-mail nebyl uveden“, nikoli prázdná klikatelná plocha. Dlouhá adresa se zalomí; kopírování kopíruje celý uložený text. Telefon může být odkaz k volání, ne smyšlený údaj.
3. **Stručná objednávka:** součet a měna, uhrazeno, zbývá k úhradě nebo přeplatek podle kanonické platební prezentace. Pod tím jedna věta o obsahu: „4 vstupenky · 2 stoly · 2600 Kč“ nebo „3 přihlášky · 2 potvrzené, 1 čekající“. Odkazy „Vstupenky a místa“ a „Podrobnosti platby“ otevírají konkrétní části, nikoli další dialog.
4. **Poslední relevantní zpráva:** druh zprávy, poslední výsledek, datum a skutečná adresa příjemce. Pokud se liší od nynějšího kontaktu, výslovně „Poslední zpráva byla odeslána na původní adresu“. Odkaz „Zobrazit e-maily“. Nezobrazovat celý technický řetězec ani seznam všech zpráv.
5. **Poznámky a odpovědi:** interní poznámka oddělená od poznámky zákazníka; obě jen pokud existují, s možností přidat interní poznámku při oprávnění. Další objednávkové otázky jsou v rozbalení „Údaje z formuláře (N)“. Kontaktní pole se podruhé neopakují. Není důvod přidávat prázdné formulářové bloky.

Přehled neobsahuje seznam jednotlivých vstupenek, plný sál, tabulku transakcí ani časovou osu. Tím zůstane použitelný i pro objednávku 40 vstupenek a formulář s 25 otázkami.

### Odpovědi objednávky versus jednotlivých osob

Objednávková odpověď patří zadavateli nebo celé rezervaci, například „Kontaktní telefon“, „Fakturační údaje“, „Poznámka organizátorovi“. Odpověď účastníka patří konkrétnímu ticketu/přihlášce, například jméno, strava, velikost trička. Tyto dvě vrstvy se nesmějí zploštit do jediného slovníku ani odvozovat ze shodného jména.

V Přehledu jsou pouze objednávkové odpovědi. Vstupenka/přihláška ukazuje své odpovědi pod vlastním stabilním identifikátorem. Chybějící jméno se nahrazuje označením „Přihláška 2“, nikoli jménem objednavatele. Typové formátování data, seznamu voleb a dalších odpovědí musí využít současné formové prezentéry. Citlivé odpovědi se nenačítají nebo nezobrazují bez příslušné autorizované projekce.

Úpravu rozsáhlých odpovědí lze zpřístupnit akcí „Upravit údaje“ jako cílený editor obsahu, s jednoznačným názvem objednávky/ticketu. Není to druhý kontaktový writer: prostá oprava e-mailu používá kanonický příkaz opravy kontaktu. Nejasnost stávajícího klientského oprávnění u formulářových odpovědí musí technický plán vyřešit před zpřístupněním akce.

## 2. Vstupenky a místa: co je objednáno a kde?

Horní souhrn uvádí počet aktivních, zrušených a případně čekajících položek. Výchozí seznam ukazuje všechny položky objednávky, zrušené zřetelně odděluje; u dlouhého seznamu je filtr a hledání podle symbolu, jména, stolu a místa. Checkboxy pro akce nad vstupenkami jsou samostatné, nezávislé na hromadném výběru objednávek.

Každá položka má tuto hierarchii:

- Symbol vstupenky nebo stabilní označení přihlášky, držitele pokud existuje, stav vstupu nebo kapacitního procesu.
- Nejvýraznější místní údaj: „Hlavní sál · stůl 4 · místa 1-2“ ve skupinovém souhrnu, u konkrétní vstupenky právě její místo. Nezaměňovat počet produktů s počtem vstupenek.
- Produkty příslušné právě této vstupence: název, počet pokud jej zdroj definuje, cena a měna. Opakované instance stejných produktů neslučovat tak, že se ztratí vazba k osobě/ticketu.
- Stav vstupu „Dosud nepoužita“ / „Použita“, případně datum kontroly, jen když jej autorizovaný zdroj skutečně dodá. Čekající přihláška nemá platný vstupní symbol.
- Lokální akce „Ukázat místo“, „Stáhnout PDF“, případně další již podporovaná operace podle capability konkrétní vstupenky. PDF není dostupné pro neplatný nebo čekající vstup jen proto, že jiná vstupenka v objednávce je zaplacená.
- Rozbalení „Údaje účastníka“ a interní poznámka ticketu. Poznámka celé objednávky zůstává v Přehledu.

### Náhled sálu je součástí této záložky

Detail zobrazuje uložený plánek, nikdy souběžně rozpracovaný draft Blueprint editoru. Jeho otevření editor neuloží, nezahodí ani nepřevezme jeho undo či rezervační výběr. Kapacitní oblast sdílená více vstupy téže objednávky ukáže souhrn a příslušné osoby v seznamu; kliknutí nesmí svévolně zvolit první osobu.


Nad seznamem je kompaktní „Místa v sále“ s názvem plánu a počtem lokalizovaných míst. V běžném panelu je plán nad seznamem, zpočátku přibližně 260-320 px vysoký, s akcí „Zvětšit plán“. V rozšířeném detailu při dostatečné šířce stojí seznam a plán vedle sebe. Na telefonu je jako první čitelný seznam; „Zobrazit plán“ rozbalí náhled nebo otevře jeho celoplošné zobrazení uvnitř stejného detailu. Návrat zachová ticket, tab i scroll.

**Vizualizace je pouze pro čtení:** žádný rezervační secret, nová session, hold, výměna míst, drag geometrie, změna produktu nebo tlačítko uložit plán. Název „výběr“ v tomto pohledu znamená lokální zvýraznění, nikoli rezervaci.

- Všechna současná přiřazená místa objednávky jsou zvýrazněna souvisle stejným způsobem; aktivně prohlížená vstupenka má navíc výrazný obrys a textový popisek. Identita vychází ze vztahů order-product-ticket a všech odlišných `spotId` dané objednávky, rozdělených podle blueprintu, s mapováním přes `BlueprintLayoutSnapshot.seatBindings` na nodeId. Nepředpokládat jedno místo z pouhého `TicketModel.relatedSpot`, nepárovat podle názvu nebo indexu pole. Snapshoty `spot_title` / `spot_group_title` zachovávají historické popisky i bez současné geometrie.
- První pohled ukáže všechna místa objednávky s okolím pro orientaci. „Všechna místa objednávky“ vrací tento výřez, „Celý sál“ přizpůsobí celý dokument; zoom +/-, pan a návrat jsou dostupné i klávesnicí/tlačítky, ne jen gestem.
- Kliknutí na „Ukázat místo“ zvýrazní konkrétní místo a posune výřez. Kliknutí na místo této objednávky může aktivovat jeho položku v seznamu a oznámit její název. Cizí místa neotevírají cizí objednávky ani osobní údaje. Pokud renderer zatím nemá hit-test callback, první dodávka zachová plnohodnotný směr seznam -> plán; obousměrnost vyžaduje explicitně doplněnou podporu, nikoli skryté ovládání editoru.
- Trvalá jednoduchá legenda: „Místa této objednávky“, „Právě zobrazené místo“, „Ostatní místa“. Zrušené historické přiřazení má oddělený styl a popisek „Původní místo, již není rezervováno“, pouze pokud existuje spolehlivý historický podklad. Legenda není paleta pro změnu stavu sálu.
- Plán je uložená aktuální geometrie. Pokud se sál změnil a místo nelze lokalizovat, seznam dál ukazuje uloženou identitu a text „Místo se v aktuálním plánu nepodařilo najít“. Nezvýraznit stejnojmenné nové místo a nevydávat aktuální plán za historický.
- Více plánů: přepínač pojmenovaných sálů s počtem míst dané objednávky; „Ukázat místo“ přepne správný plán. Žádné přepočítávání souřadnic mezi sály. Umístění bez plánu zůstane textovým údajem.
- Stání: „Stání · Balkon · 2 vstupy“, případně zvýraznění skutečně svázané plochy. Bezčíselné vstupné: „Bez přiděleného místa“, bez chyby. Čekací listina: „Místo zatím nebylo přiděleno“, žádná vizuální rezervace.

Podrobný textový seznam zůstává plnohodnotnou alternativou canvasu. Uživatel nesmí potřebovat rozpoznávat barvy nebo manipulovat mapou, aby zjistil svá místa.

## 3. Platby: co bylo předepsáno, přijato a vráceno?

První blok obsahuje kanonický finanční souhrn: celková cena, aktuálně požadovaná částka, přijato, vráceno, zbývající požadavek nebo přeplatek. Nevyvozovat účetní pravdu jen z obchodního stavu a nevytvářet v panelu alternativní výpočet dluhu. Vráceno zůstává samostatným údajem; zrušení objednávky samo o sobě neznamená provedenou refundaci.

Zálohová objednávka ukáže dvě pojmenované etapy: výši a splatnost zálohy, stav její úhrady; výši a splatnost doplatku, pokud jej skutečný zdroj definuje. Příklad k ověření: celkem 2600 Kč, záloha 1000 Kč uhrazena, doplatek 1600 Kč do 10. 1. 2027. Nahoře nesmí být jen „Zaplaceno“ bez rozlišení.

Souhrn má využít existující `customer_order_payment_internal` (pro kartu deleguje na `stripe_order_payment_projection_internal`): stavy i `received`, `returned`, `outstanding`, `dueNow`, `dueAt` mají jednoho vlastníka. `unknown` zůstává neznámým stavem; chybějící nebo nulové číslo není důkaz nezaplacení, například u platby evidované externě.

Následuje blok konkrétní platební metody:

- Převod: přijímací účet, VS a další skutečně použité reference; datum splatnosti a informace o aktuální upomínce. Kopírování je po jednotlivých údajích. Upozornění BankSync odkazuje na skutečný problém, ne na každou historickou nerovnost částek.
- Karta: existující prezentace karetního stavu, dostupné potvrzené údaje a obnovení. Nezobrazovat prázdný VS, bankovní QR nebo návod k převodu jako náhradní platební cestu.
- Hotovost či jiná podporovaná metoda: pouze údaje dodané současným kontraktem. Akce „Přidat hotovostní platbu“ je podle oprávnění a stavu; neznamená automaticky právo měnit bankovní účet.

Potom kompaktní chronologický seznam transakcí: datum, podepsaná částka s měnou, druh/zdroj, reference a identita zapisujícího, pokud existuje. Rozbalení zpřístupní protistranu, zprávu, poznámku a další reference. Záporná částka se prezentuje jako skutečný bankovní/ledgerový údaj; popisek refundace vychází z typu operace, nikoli pouze znaménka.

Čtení vlastních objednávkových transakcí náleží autorizovanému čtenáři objednávky; absence práv pro správu bankovních transakcí nesmí skrýt celou záložku. `canManageBankTransactions` a další capability omezují jednotlivé zápisové/správní akce.

Relevantní akce jsou u tohoto bloku: existující připojení transakce, hotovostní zápis, odpojení či další operace jen při odpovídající capability a s původními potvrzeními. Samostatný dialog je přiměřený pro konkrétní transakční formulář/nezvratnou operaci, ne jako obal celé záložky. „Označit zaplaceno“ se nesmí slít s „Zapsat přijatou platbu“.

Měna je u každé částky a ve všech souhrnech. Částky různých měn se nesčítají do jednoho čísla ani potichu nepřepočítávají. Desetinná přesnost a seskupování respektují sdílené formátování projektu (například 49,90 EUR; čísla pod 10000 bez seskupování). Pokud data nesou rozpor měn, zobrazit oddělené skutečnosti a nedostupný souhrn s vysvětlením, nikoli zavádějící nulu.

## 4. E-maily: kam zprávy šly a co lze bezpečně udělat?

Nahoře je aktuální kontakt a stejný obsahový editor jako v Přehledu. Nemá vlastní nezávislý draft nebo odlišnou logiku. Pod ním kontext aktuální obchodní zprávy: potvrzení objednávky versus vstupenky, poslední relevantní pokus, skutečný příjemce a další dostupný krok.

Primární **Uložit e-mail** neodesílá zprávu. Vedlejší **Uložit a odeslat aktuální potvrzení/vstupenky** je výslovná kombinovaná akce podle současného stavu. Bez změny adresy zní samostatná akce „Odeslat aktuální vstupenky“ nebo „Odeslat aktuální potvrzení“. Tlačítko pojmenuje obsah, nikoli neurčité „Zkusit znovu“.

Před uložením je stručné vysvětlení dopadu: změna kontaktu zachová historické adresy, zruší dosud neodeslané staré příjemce podle kanonického kontraktu a sama nevytvoří nový e-mail. Již probíhající pokus se nedá vydávat za odvolaný. Po uložení zpráva „Kontakt byl uložen. Nová zpráva nebyla odeslána.“ Při kombinované akci se odlišuje přijetí požadavku do fronty od skutečného odeslání/doručení.

Historie má zprávy jako hlavní jednotku: druh, čas vytvoření, adresu a shrnutí. Rozbalení konkrétní zprávy ukáže pokusy, události poskytovatele, opravy a technickou diagnostiku. Staré potvrzení není automaticky zdrojem pro nové vstupenky. U více současných opravných větví musí být jednoznačné, kterou správce řeší; nelze tiše vybrat první.

Omezení a jejich umístění:

- `sending` nebo `unknown` u relevantních aktivních pokusů: kontakt lze uložit, ale nový pokus je blokovaný do ověření; vysvětlení přímo u tlačítka.
- `pending`, `preparing`, odložené nebo blokované zpracování: vysvětlit existující čekající zprávu, nevytvářet duplicitní požadavek. Pokud správce mění kontakt, může být nutné nejprve samostatné uložení a obnova, která potvrdí zrušení starého čekajícího intentu; teprve potom nabídnout výslovné odeslání na novou adresu. Tyto dvě mutace se nesmějí automaticky řetězit za skryté potvrzení.
- `bounce`, `suppressed`, `complaint`: blokace cílové adresy je normalizovaná, původní adresa zůstává blokovaná i po změně velikosti písmen. Nová skutečně ověřená neblokovaná adresa může být přípustná; rozhoduje server. Rozhraní nenabízí odblokování nebo obejití pravidel.
- Zrušená objednávka: žádné nové odeslání ani oprava kontaktu mimo povolený kontrakt. Režim pouze pro čtení: historie zůstává, zápisové akce nejsou dostupné.
- Úspěšné doručení: kontakt je stále editovatelný při oprávnění. „Doručeno poštovnímu serveru příjemce“ není přečtení ani potvrzení totožnosti. Otevření/kliknutí mohou vzniknout automatizovaným zpracováním pošty.

### Všechny stavy, bez nového stavového modelu

Zobrazované popisky vycházejí z `.EmailDelivery.state` v české lokalizaci. Implementace nesmí 27 klíčů přepsat do jediné vzájemně výlučné časové řady. Rozlišuje frontu/zpracování, pokus, události poskytovatele, blokaci adresy a diagnostiku.

| Prezentační vrstva | Klíče, jejichž přesné popisky musí zůstat dostupné |
| --- | --- |
| Fronta a zpracování / souhrn | `pending`, `preparing`, `sending`, `blocked`, `accepted`, `retry_wait`, `unknown`, `dead`, `cancelled`, `expired` |
| Poskytovatel a příjemce | `delivery`, `open`, `click`, `bounce`, `complaint`, `suppressed`, `reject`, `rendering_failure`, `delay`, `send`, `not_accepted` |
| Sledování a provozní diagnostika | `unavailable`, `done`, `tracking_disabled`, `not_observed`, `post_action_failed`, `feedback_overdue` |

Tato tabulka je členění prezentace, nikoli enum databázové tabulky. `email_attempts.state` obsahuje pouze `preparing`, `sending`, `accepted`, `not_accepted`, `unknown`, `cancelled`. `done` je dokončení navazující akce (`email_messages.post_action_state`), nikoli přečtení zprávy. `post_action_failed` je čekající oprava navazující aktualizace po převzetí e-mailu. Běžný operátor vidí srozumitelný důsledek a akci; kompletní diagnostika je po rozbalení, ne v každém řádku gridu.

## 5. Historie: co se v objednávce změnilo?

Výchozí pořadí je od nejnovější změny. Událost má datum/čas, lidský název, původce pokud je dostupný, a konkrétní změnu před -> po. Změna e-mailu ukazuje obě adresy. Změna produktů respektuje identitu ticketu a opakované produktové instance. Odstraněný produkt není novou anonymní zápornou položkou bez vazby.

Historie shrnuje vytvoření, obchodní změny, změnu kontaktu, důležité platební a ticketové události dostupné z autoritativního zdroje. Případné odkazy „Zobrazit platbu“, „Zobrazit vstupenku“ a „Zobrazit zprávu“ přepnou tab a zvýrazní konkrétní položku. Celá poskytovatelská telemetrie se sem nekopíruje; zůstává v E-mailech.

Prázdná historie je „Další změny nejsou zaznamenány“, pokud existuje alespoň známá objednávka. Nedostupná historie je chyba s obnovením, ne tvrzení, že změny neexistují. Historický výsledek nikdy nepřebírá aktuální jméno nebo adresu místo uloženého snapshotu.

## Klidnější grid a přesun akcí

| Údaj/akce | Výchozí grid | Vlastník v detailu |
| --- | --- | --- |
| Hromadný výběr, symbol/pořadí, zákazník | Ano; číslo otevírá, kopírování je oddělené | Hlavička a Přehled |
| Obchodní stav, cena a měna | Ano; mírné akcenty, žádná celoplošná duha řádků | Přehled, Platby |
| Vytvořeno | Ano na široké ploše; nižší priorita při zúžení | Hlavička/metadata Přehledu |
| Formulář | Jen je-li jich více | Hlavička |
| Kontakt e-mail | Kompaktní druhý řádek zákazníka nebo volitelný sloupec | Editor v Přehledu/E-mailech |
| Doručení | Jen stručná výjimka a kontextový vstup; přesný stav zůstává dostupný | E-maily |
| Transakce, kompletní platební reference, vrácené částky, splatnosti | Pokročilé volitelné sloupce, bez série dialogových ikon | Platby |
| Zákaznický přehled, historie, náhled míst, PDF | Kontextové vstupy podle potřeby, ne všechny v každém řádku | Příslušné záložky |
| Interní poznámka | Volitelná ikona/text; obsah nezahlcuje řádek | Přehled |

Při přechodu přesunout známé vstupy `HISTORY`, `TRANSACTIONS`, `OVERVIEW`, `CONTRACT` a platební plus do odpovídajících částí detailu. Globální uložit/zahodit se nesmí automaticky odstranit: současný grid může držet rozpracovanou `note_hidden` i připravená smazání. Nový detail nepřidává další neviditelný gridový draft; stávající drafty musí být buď dokončeny původní cestou, nebo výslovně migrovány bez ztráty. Hromadné a jednotlivé mazání zachová původní capability, náhled a potvrzení; není novou jednorázovou akcí v panelu.

Stávající export, filtry, hromadné akce a možnost pokročilých sloupců se neodstraňují. Uživatelovy uložené preference nepřepsat při vydání nového výchozího pohledu. Akce přesunuté do detailu musí zůstat dohledatelné; souběžná stará ikona a nová cesta smějí dočasně vést ke stejnému obsahu, nikoli ke dvěma rozdílným implementacím.

## Podmíněné varianty obsahu

| Situace | Požadované chování |
| --- | --- |
| Čtyři sedadla u dvou stolů | Přehled „4 vstupenky · 2 stoly“; seznam přiřazení po ticketu, plán zvýrazní všechna 4 místa a umí jednotlivé |
| Více produktů na jednom ticketu | Jedna vstupenka, více produktových řádků; nedělat z každého produktu nové místo |
| Prodáno bez místa / stání | Platný vstup s „Bez přiděleného místa“ / názvem stojící zóny; plán není podmínkou úspěchu |
| Prodáno z předtištěné série | Zachovat `TicketModel.batch` a identitu ticketu, případně „Série …“; rozlišit prodej od použití vstupu. Neoznačit skladový kus za zaplacený zákaznický ticket |
| Registrace bez funkce vstupenek | Druhá záložka se jmenuje „Přihlášky“, stejné osoby/odpovědi; žádná PDF ani ticketové QR jen kvůli sdílenému datovému modelu |
| Čekací listina nebo smíšená kapacita | Každá přihláška nese svůj lifecycle, nabídku a termín; čekající položka nemá přidělené místo, produkt ani finance. Souhrn kapacity neodvozovat z finančního stavu sourozence |
| Objednávka bez finanční části | Platby se nezobrazí jen pokud je jejich nepoužitelnost autoritativně známá; chybějící/načítaná data nejsou důvod tab skrýt |
| Bez plánku | Textové umístění je plnohodnotné; náhled není prázdný technický obdélník |
| Zrušená objednávka / ticket | Historie a finance zachovány; současná versus původní místa odlišena; žádné automatické vrácení peněz ani aktivní PDF bez platného kontraktu |
| Částečné vrácení | Samostatně přijato/vráceno/zůstatek a příslušná transakce; nezamlčet částečnost jediným „Vráceno“ |
| Pouze pro čtení | Klidný text režimu; kopírování, čtení a povolené stažení fungují. Zápisové akce skryté, relevantní stavové blokace vysvětlené |
| Neznámé oprávnění při načítání | Akce nejsou prozatím povoleny. Serverové capability mají přednost před odhadem z role |

Názvy tabů se odvozují z funkce a kontextu, ne z toho, zda zrovna přišla prázdná odpověď. E-maily mají smysluplný prázdný stav „K této objednávce zatím není žádná zpráva“. Historické e-maily se neztrácejí po vypnutí automatického odesílání.

## Opětovné použití konkrétních částí

Znovupoužití znamená společného vlastníka prezentace a operací. Neznamená vložit celý existující dialog, správu sálu nebo veřejný webclient do panelu.

| Existující symbol/zdroj | Použít | Nepřebírat bez úpravy |
| --- | --- | --- |
| `OrderModel`, `TicketModel`, `PaymentInfoModel`, `TransactionModel`, `OrderDataTicketModel`; `get_order_allowed_actions_internal_v1` | Identitu, vztahy, stavové/capability informace, platební a produktová fakta | Domýšlení dostupných akcí z jediné barvy/stavu nebo chybějících vztahů |
| `CustomerOrderOverviewView`, `CustomerOrderOverview`; JS `renderOverviewCustomer`, `renderOverviewAnswers`, `renderOverviewProducts`, `overviewItemChanges` | Datové významy a hierarchii kontaktu, účastníků, produktů a historických rozdílů; vhodné Dart obsahové části vyčlenit se stávajícím uživatelem | Celý veřejný flow, veřejnou identitu/footer, pokračování checkoutu, ani přepis JS DOM komponent do Dart jako kopie |
| `customer_order_payment_internal`, `stripe_order_payment_projection_internal` | Kanonický souhrn a platební status, načtení transakcí oddělit podle záložky | Vlastní výpočty sum, dluhu a zálohové logiky |
| `order_tickets_with_seating_internal` | Produktový snapshot a současné přiřazení míst, identitu ticketu a vztahů | Nahrazení historického místa aktuálním stejnojmenným objektem |
| `TransactionsDialog`, `DbEshop.getTransactionsForOrder`, `AddCashPaymentDialog`, `SearchTransactionsDialog` | Vyčlenit z dialogu sdílený transakční obsah/presenter; zachovat kanonické dotazy, autorizaci a jednotlivé potvrzovací formuláře | Vnořený plný `TransactionsDialog` jako tab nebo nový paralelní účetní výpočet |
| `OrderHistoryDialog`, `OrderHistoryModel` | Sdílené renderování položek a existující historii | Dialogovou hlavičku a další uzavírací vrstvu uvnitř záložky |
| `EmailDeliveryHistory(embedded, orderId, messageId)`, `OrderEmailIssue`, `OrderEmailRepairDialog`, `OrderCommands.repairEmail` | Existující order-scoped historii, cílení zprávy, interpretaci problému a kanonický příkaz; editor kontaktu vyčlenit pro oba hostitele | Druhý e-mailový agregátor nebo vložený opravný dialog v panelu; organizační historii místo scoped čtení |
| `FormResponseModel.updateMethod`, `DbOrders.updateOrderResponses`, existující formulářové prezentéry | Typové odpovědi a existující oprávněný workflow rozsáhlejších změn | Použít writer formuláře jako zkratku opravy e-mailu nebo automaticky převzít odlišný UI rights guard |
| `VenueLayoutViewer(document, resources, seatPresentation)`, `BlueprintLayoutSnapshot`, `BlueprintSeatBinding`, `BlueprintLayoutAssetResolver` | Uložený kanonický dokument, zdroje, mapování spot/node a prezentační zvýraznění | `BlueprintLayoutHost` se správou a mutacemi ani `SeatReservationWidget` s rezervacemi/hold session |
| `BlueprintLayoutAdapter` | Stávající mapování míst/produktů jako zdroj pro hostitelskou projekci | Jeho provozní výběr `selectedByMe` vydávat za pouhé lokální zvýraznění |
| `AppDialog`, `AppDialogHeader` / `AppDialogAppBar`, `CopyButton`, projektové formátování | Jednotný shell mobilního/celoplošného režimu, zavírání, Escape, kopírování, lokalizaci peněz a času | Samostatnou nepodobnou modal infrastrukturu nebo další formátovač |

**Známá mezera rendereru:** dnešní `VenueLayoutViewer` přijímá dokument, resources a seatPresentation, ale veřejně nevystavuje vlastní controller pro cílený fit/recenter ani callback konkrétního kliknutého místa. Požadavky výše tedy nejsou již hotovou funkcí. Technický plán má navrhnout nejmenší obecné read-only rozšíření rendereru/scene surface bez hostitelských order ID a bez editorových závislostí. Neobcházet jeho API přístupem do soukromého stavu, importem package `src` nebo připojením editorového controlleru. Stávající checkout reader `DbForms.getBlueprint(mySecret, formKey, blueprintId)` není autoritou pro administrátorský detail; nepoužít falešný secret. Nová úzká autentizovaná read-only projekce musí odvodit scope z uložené objednávky a dodat její vazby i dokumenty jednotlivých plánů.

## Stavové chování, přístupnost a návrat

První načtení otevře shell s identitou z bezpečně známého řádku a indikátorem načítání; nevykreslí data předchozí objednávky. Přepnutí tabů neresetuje celý panel. Dražší historie a geometrie se načtou při první potřebě; souhrn Přehledu není blokován načítáním plánu.

| Stav | Viditelná reakce a ochrana |
| --- | --- |
| Načítání tabů/plánu | Místní indikátor, stabilní rozložení, žádné dočasné nulové součty nebo „bez míst“ |
| Prázdná data | Věcný popisek konkrétního bloku; žádná falešná chyba nebo pobídka k neexistující akci |
| Chyba jedné části | Chyba a „Načíst znovu“ u dané části; ostatní autorizované části fungují |
| Objednávka nenalezena nebo již nepřístupná | Bez citlivého předchozího obsahu, zavření/návrat do seznamu; neloví se jiný tenant |
| Zastaralá data / souběžná změna | Ukázat konflikt a aktuální potvrzené hodnoty; nepřepsat server ani nezaměnit draft za uložený údaj. Odesílání zůstane blokované do znovuověření |
| Ztráta kontextu/oprávnění | Okamžitě znepřístupnit citlivý obsah a mutace. Pozdní response z předchozí objednávky se nesmí vykreslit |
| Zápis probíhá | Lokálně blokované opakování a odchod, který by ztratil výsledek. Úspěch až podle kanonické odpovědi, chybný draft zůstává opravitelný |
| Návrat z operace | Obnovit dotčené části a řádek při zachování výběru/filtru/scrollu. Neudělat plošný reset gridu |

Neuložený editor chrání zavření, přechod na jinou objednávku a opuštění obrazovky. Přepnutí záložky může draft zachovat, protože patří objednávce, nikoli DOM/widgetu záložky; editor kontaktu v E-mailech a Přehledu ukazuje tentýž draft. Doporučení je draft zachovat a u relevantního tabu zobrazit „Neuloženo“, nikoli nutit potvrzení při každém prohlédnutí plateb. Přechod na jinou objednávku nabídne „Pokračovat v úpravě“ nebo „Zahodit změnu“; žádné automatické uložení či odeslání. Rozšíření stejného panelu draft zachová bez dialogu.

Klávesnice: Enter na čísle objednávky otevírá detail; fokus jde na nadpis nebo kontextový cíl. Tab prochází nativní ovladače. Záložky podporují směrové klávesy a Home/End. Escape nejprve ukončí nejvyšší lokální vrstvu/editor podle jeho pravidel, pak zavře panel se stejnou ochranou draftu. Desktopový panel není modal a neuvězní fokus; mobilní celoplošný režim má inertní pozadí a správně vymezený fokus. Zavření vrací fokus na původní řádek; pokud již není viditelný, na toolbar gridu s oznámením.

Na 320-390 px se popisky, částky a kontakty zalamují, taby mohou vodorovně rolovat s viditelným aktivním tabem. Ovládací cíle jsou dotykově použitelné; tooltip není jediný zdroj informace. Na 768 px se nezobrazuje namačkaná dvojice grid/panel. Na 1440 px má mít správce reálně použitelný seznam i detail. Zoom 200 % musí vyvolat užší rozložení, ne překrývání tlačítek. Rozšířený plán nesmí zachytit scroll/klávesy mimo aktivní prostor plánu.

## Konkrétní akceptační průchody

1. **Běžná zaplacená objednávka.** Jana Novotná, 4 × 650 Kč = 2600 Kč, dva stoly, příchozí převod 2600 Kč, vstupenky doručené na `jana.novotna@example.com`. Z řádku je do dvou akcí vidět každé místo i odpovídající ticket. Návrat zachová filtr a hromadný výběr.
2. **Doručený e-mail patří jiné osobě.** Syntakticky platný kontakt se opraví i při úspěšném doručení. Pouhé uložení nezaloží zprávu; souhrn a historie dál uvádějí starého příjemce. Výslovné odeslání použije aktuální obsah a novou adresu.
3. **Nedoručeno a blokace adresy.** Původní blokovaná adresa ani její varianta velikosti písmen nejde znovu obeslat. Jiná ověřená adresa je posouzena serverem. Historie původního selhání nezmizí. `unknown`/`sending` stále blokuje duplicitní pokus i po změně kontaktu.
4. **Záloha.** Celkem 2600 Kč, přijato 1000 Kč, doplatek 1600 Kč se skutečným termínem. Přehled nevydává uhrazenou zálohu za dokončené finance; Platby ukážou etapy i skutečnou transakci.
5. **Refundace po zrušení.** Původně přijato 2600 Kč, vráceno 1300 Kč. Je vidět částečné vrácení; zbývající operace se nenazve automaticky provedenou. Zrušené vstupenky nemají aktivní místa ani nové odeslání.
6. **Smíšený obsah.** Dvě vstupenky s místem, jedna na stání a několik doplňkových produktů. Počet vstupenek není součtem produktových řádků; mapa zobrazuje jen skutečně přiřazené objekty. Každá osoba má vlastní odpovědi.
7. **Bez plánku a změněný plán.** Bezčíselné vstupné je normální stav; nenalezené dříve přiřazené místo je výslovný problém mapování, nikoli záminka rezervovat stejnojmenné nové místo. Textová informace zůstane dostupná i při chybě assetů.
8. **Registrace a čekací listina.** Přihláška bez ticket feature nemá PDF. Čekající osoba nemá vymyšlenou cenu, produkt nebo platný vstupní symbol. Nabídnutý termín je u správné osoby, nikoli na celé objednávce bez rozlišení.
9. **Velká objednávka.** 40 vstupenek přes více stolů/sálů, dlouhé kontakty a 25 formulářových odpovědí. Přehled zůstává krátký, hledání lokalizuje ticket a „Ukázat místo“ zvolí správný plán. Klávesnicí lze získat stejné informace jako klikáním do canvasu.
10. **Oprávnění a souběh.** Read-only uživatel prohlíží, kopíruje a podle capability stahuje. Změna práv během otevřeného detailu odebere mutace. Konflikt kontaktu nebo platební verze neodešle zprávu a nepřepíše novější data.
11. **Navigace a draft.** Oprava kontaktu přežije zobrazení Plateb i rozšíření panelu; při další objednávce jde pokračovat v úpravě. Přímý vstup z notifikace otevře konkrétní zprávu, ne nesouvisející poslední chybu.
12. **Měny a metoda.** Karetní objednávka v EUR ukazuje správnou přesnost i karetní stav; neobjeví se nesmyslné převodní pokyny. Různé měny se nesčítají. Chybějící data nevytvoří nulovou zaplacenou objednávku.

## Předání do technického plánu

Varianta A, pět záložek a oddělení odpovědí objednávky od ticketu jsou rozhodnutím tohoto návrhu. K implementačnímu dopracování patří autorizovaná projekce detailu, bezpečné vyčlenění existujících obsahových widgetů, minimální rozšíření read-only vieweru, zachování gridových preferencí a cílení stávajících notifikací. Žádná z těchto položek nevyžaduje znovu otevírat volbu A/B/C.

Číselné šířky jsou návrhové startovní hodnoty, ověřitelné při implementaci na skutečném gridu, nikoli slib existujícího responsive chování. Chybějící historická data a API vieweru jsou přiznané mezery, ne úkol pro klientské domýšlení. Tento plán je zpracován cíleným čtením zdrojů; v tomto kroku nebyly spuštěny testy, browser ani změny aplikace.

## Dopracování míst a plánku: přesná pravidla pro hraniční situace

Tato část zpřesňuje záložku Vstupenky a místa. Nepřidává nový editor míst ani provozní postup nasazení. Při rozporu s dřívějším zjednodušeným příkladem má přednost zdejší rozlišení identity, oprávnění a aktuálního přiřazení.

### Co je doloženo současným zdrojem

- `lib/components/blueprint/README.md` vymezuje jedinou autoritu fyzického umístění: `eshop.spots.order_product_ticket`. Geometrie, obchodní skupina a momentální autorizační možnosti jsou různé vrstvy. `spot.id` přežívá změnu geometrie; kopie objektu naopak dostává novou identitu bez přiřazení.
- `SeatingMapping` váže `ticketId`, `admissionItemId`, `expectedSpotId` a `targetSpotId`. Vazba tedy není prosté ticket ID -> jeden bod. `SeatingSeat.unitSpotIds` popisuje celé atomické jednotky; jejich úplný přesun může zasáhnout více vstupních položek a formulářů.
- `SeatingAdmission.mutable` vyžaduje konkrétní položku i produkt, absenci blokujícího důvodu a kategorii assigned/unassigned. `SeatingTransitionController.canAssign` vyžaduje současně `assign` i `readHolders`; `configure` je oddělené oprávnění. Použité, vytištěné a nejednoznačné vstupy nelze automaticky vynechat ani prohlásit za měnitelné.
- `BlueprintSeatSwapPreview` obsahuje revizi plánu, úplné zdrojové i cílové jednotky, potvrzovací hash a finanční dopady. `BlueprintTicketCancellationPreview` odděluje požadovaná místa od odvozených ticketů. Existující zrušení expanduje na skutečně dotčené tickety a používá jejich kanonickou operaci, ne jen vizuálně kliknutý bod.
- Stání používá vazby ploch a PIC/inventory alokace; změna množství nevytváří hold konkrétní sedačky. Zakreslená plocha není počet sedadel.
- `order_spot_metadata_internal` čte současný název obchodní skupiny z `binding.group_node` a příslušného `node.label`. Neurčuje stůl podle fyzické blízkosti, barev ani nakresleného textu.
- **Omezení existujícího helperu:** `order_tickets_with_seating_internal` dohledává vztah podle objednávky, ticketu a produktu a vybírá `LIMIT 1`. Je použitelný jako stávající textové obohacení, ale nedokazuje úplné přiřazení opakovaných stejných produktových instancí. Kompletní mapa musí mít samostatně přesné vztahy `order_product_ticket`/`admissionItemId` a distinct spot IDs, nikoli zpětné odvozování z těchto obohacených popisků.
- Uložené zobrazení používá kanonický schema-2 dokument, připravené textové vektory a ověřené zdroje. Chyba nespouští starý renderer, veřejný fallback font ani importní opravu dokumentu.

Při tomto dopracování byl přečten i aktuální necommitnutý diff jiného pracovního proudu: po uložení plánu obnovuje seating context, při `PRODUCT_MISMATCH` nabízí configure-only návrat k opravě produktů a upravuje české „Zrušit“. Tento dokument jeho změny nepřebírá ani nemění; zohledňuje, že návrat z hostitele musí vždy znovu načíst platný kontext a kompatibilitu.

### Identita a počty bez ztráty vztahů

**Návrhové rozhodnutí:** seznam má dvě úrovně, vstupenku/přihlášku a její konkrétní vstupní/produktové položky. V běžném jednoznačném případě se druhá úroveň vizuálně slije do jednoho čitelného řádku. Opakované doplňkové produktové instance se rozbalí bez vymýšlení dalšího ticketu. Více míst běžné atomické jednotky náleží více vstupům/ticketům; jeden ticket s více primárními admission položkami je datová nejednoznačnost, nikoli běžná varianta prodeje.

| Situace | Co správce uvidí | Co se nesmí stát |
| --- | --- | --- |
| Jeden ticket se dvěma primárními vstupními položkami | Nekonzistentní data: `ADMISSION_DATA_AMBIGUOUS`; upozornění a zachování dostupných faktů bez automatické volby nebo editace | Vydávat tento případ za podporovaný vícemístný ticket nebo vybrat první `relatedSpot` |
| Dvě stejné doplňkové produktové instance | Obě instance zachované pod správným ticketem podle item ID; bez vymyšleného nároku na další místo | Vydávat doplněk za další admission nebo sloučit instance jen podle product ID |
| Totéž místo vrácené v několika prezentačních řádcích | Jediný bod na mapě a distinct počet míst; seznam může ukázat související položky | Nafouknout „4 místa“ na „8“ podle joinových duplicit |
| Jedna sedačka má rozporné aktivní vlastníky v dostupných datech | „Přiřazení nelze jednoznačně ověřit“, neutrální problém v seznamu a obnovení | Potichu vybrat poslední řádek nebo zobrazit cizího držitele |
| Názvy „1“ a „Stůl 4“ se opakují | Vždy připojit sál/plán a ověřenou obchodní skupinu | Spojovat místa podle názvu napříč sály |
| Prodaný předtištěný ticket | Původní ticket ID/symbol, údaj série, aktuální oprávněná vazba na prodej a místo | Zaměnit skladovou objednávku původu za zákaznický prodej nebo generovat nový symbol |

Souhrn explicitně rozlišuje „vstupenky“, „přiřazená místa“ a „vstupy na stání“. Ani v atomické jednotce nemusí být jejich počty z definice stejné. U sold printed batch se nepředpokládá kompatibilita s přesazením: detail ukazuje skutečnost a případný serverový důvod omezení, nikoli slib, že vytištěná vstupenka již obsahuje nové místo.

### Atomické pohovky, skupiny a popisky stolů

Pohovka se dvěma místy může být jedna atomická obchodní jednotka a přitom mít dvě samostatné vazby účastníků. Detail zvýrazní pouze ověřená místa vlastní objednávky, obrys jednotky může ukázat jako orientační „Pohovka · společná jednotka“. Aktivace jedné osoby zvýrazní její bod; obrys související jednotky není tvrzení, že správci patří všechna místa jednotky.

Pokud část jednotky patří jiné objednávce/formuláři, detail nevypíše cizí osoby ani nepřidá jejich místa do počtu této objednávky. Případná změna je až v existujícím oprávněném workflow, jehož náhled vysvětlí úplné dotčené jednotky. Do detailu se nepřenáší automatická expanze mutačního výběru na cizí tickety.

Autoritativní obchodní skupina z bindingu má přednost před heuristikou nejbližšího nábytku. `blueprintCommercialGroupFor` existuje pro hostitelské reconciliation; detail nemá znovu heuristicky „opravovat“ skupinu. Nakreslený nápis „VIP“ vedle stolu není jeho datovým jménem. Při chybějícím ověřeném skupinovém popisku se ukáže pouze místo a sál; při rozdílu historického a současného názvu „Při nákupu: stůl 4 / Nyní: stůl VIP“. Nevynucovat slovo „stůl“ pro řadu kina nebo pohovku, pokud zdroj určuje jiný typ.

### Stání a množství

Řádek „Balkon · 3 vstupy na stání“ musí vycházet ze skutečných přidělených vstupních položek a alokací dané objednávky, nikoli z celkové kapacity plochy nebo její velikosti. Pokud tyto tři vstupy patří třem ticketům, seznam zachová všechny tři osoby/symboly; mapa zvýrazní jednu plochu s popiskem „3 vstupy této objednávky“. Pokud vazbu ke konkrétní ploše nelze prokázat, zůstává „Stání, plocha není určena“ a obecný text bez falešného polygonu.

Vyprodaná plocha není chybou již zakoupeného vstupu. Aktuální zbývající kapacita není hlavním údajem detailu a nesmí přepisovat zakoupené množství. Částečně zrušené vstupy oddělit: „2 aktivní, 1 zrušený“. Smíšené sezení a stání zobrazit v oddělených skupinách; nevymýšlet pro stání čísla sedadel. Není tu plus/minus množství, cena nové nabídky ani kapacitní editor.

### Aktuální umístění, historie a přeobsazení

Výchozí záložka ukazuje **současné autoritativní přiřazení**, načtené ve společném scope s objednávkou. Historický snapshot je vysvětlení, ne důkaz dnešního vlastnictví bodu. Rozšířené údaje „Původní místo“ jsou textové; historický náhled mapy se nenabízí bez skutečně dostupné historické revize dokumentu.

- Přesunutí geometrie se stejným spot ID mění polohu v aktuálním plánu, nikoli identitu ticketu. Změna přiřazení na jiný spot ID mění vazbu a musí být takto vidět v historii.
- Přesun do jiného plánu přepne aktivní plán až po potvrzeném obnovení. Přesun mezi formulářovými kohortami se nesmí prezentovat jako změna původního formuláře objednávky; původ objednávky a současný cílový sál jsou samostatné údaje.
- Po zrušení může původní místo obsadit jiný zákazník. Původní objednávka pak nesmí dál barevně vlastnit tento bod. Lze ukázat text „Původně stůl 4, místo 1; přiřazení již není aktivní“, bez jména nového držitele a bez zelené rezervace na mapě.
- Pokud je jeden ticket použitý a druhý zrušený, první zůstává viditelným skutečným vstupem, druhý historickým. Stav celé objednávky nenahradí stavy jednotlivých ticketů. Přesazení či zrušení použitého vstupu je otázkou serverové capability a náhledu, ne automatický zákaz/povolení podle lokálního popisku.
- Změna místa nezmění již stažené/tisknuté PDF. U doložené relevantní změny se nabídne informativní „Dříve stažené vstupenky se neaktualizují“ a standardní povolená cesta pro aktuální PDF/e-mail. Detail netiskne ani neodesílá automaticky.

### Práva k objednávce nejsou práva upravovat nebo procházet celý sál

`can_read_seating_status` dovoluje form authoring NEBO order read; samo tedy není dostatečné pro soukromý detail objednávky. `can_assign_existing_admissions` vyžaduje přihlášeného aktéra, order read i order write. Nová projekce vyžaduje konkrétní order read a vazbu objednávky na plán; běžnému oprávněnému čtenáři pro zobrazení uložené geometrie nepřidává požadavek configure. Širší `get_blueprint_for_edit` není automaticky vhodný datový zdroj.

Read-only mapový endpoint musí vydat dokument/resources a vlastní vazby jen v rozsahu ověřeného přístupu k objednávce a plánku. To, že je geometrie technicky veřejně dostupná, není oprávnění načíst soukromý organizační seznam držitelů. To, že uživatel smí upravovat plán, zase samo nedává právo číst zákaznický kontakt.

Když je objednávka čitelná, ale mapa není dostupná nebo autorizovaná, textová místa, ticketové údaje a ostatní záložky zůstávají použitelná. Místní sdělení zní „Náhled plánku není k dispozici“, případně konkrétní oprávněné vysvětlení; nedoporučuje přihlásit se jako jiný správce nebo použít veřejný secret. Ztráta práv k celé objednávce naopak odebere celý soukromý obsah.

Cizí, prázdná a nedostupná místa v plánu slouží pouze k orientaci. Jejich původní autorská výplň se nevydává za ověřenou dostupnost nebo obsazenost; bez příslušné projekce jsou všechna jen neutrálním pozadím. Kliknutí nevybere bližší volné místo, neotevře cizí objednávku a neposkytne tooltip s cizím ticketem. Tap na pozadí ruší jen lokální aktivní zvýraznění, pokud tím není přerušen drag/pinch; nic se neukládá. Pořadatel nemá z tohoto detailu zjišťovat jména ostatních hostů.

### Vizuální vrstva a zdroje

Zvýraznění objednávky je dočasný prezentační overlay nad původním dokumentem. Použít odlišný obrys/šrafování a textový popisek, ne rezervovací stav `selectedByMe` nebo přebarvení celého sálu na „volné“. Legenda používá „Tato objednávka“ a „Zobrazené místo“, nikoli „Vybráno k rezervaci“. Barva sama nestačí, obrys musí být čitelný na světlém i tmavém autorském pozadí. Pro aktivní bod je vhodný dvojitý kontrastní obrys bez změny uložených stylů.

Kanonické vektory zachovávají původní české diakritické i RTL/Bidi popisky sálu; runtime detail nezačne přepočítávat geometrii textu jiným fontem. UI kontakty/identifikátory a kombinované RTL popisky mají bidi izolaci, ale poloha židlí ani orientace plánu se zrcadlením UI nemění. Přeložit dostupné ovládání a přístupný název vieweru; jeho dnešní anglický semantics text není důvod přidávat alternativní renderer.

Ověřený resource resolver musí zůstat jedinou cestou k bitmapám a připraveným cestám. Při nedostupném podkladovém obrázku nebo textových zdrojích neslibovat úplnou orientaci: ukázat lokální chybu/„Plánek není úplný“ a obnovu, textový seznam dál funguje. Bez ověření geometrie a bindingů není bezpečné zobrazit nesouvisející body se starým cache overlayem. Obnovení nekonvertuje ani neopravuje dokument.

### Chování mapy při pohybu, návratu a změně dat

| Událost | Navržené chování |
| --- | --- |
| První otevření plánu | Přizpůsobit všechna aktivní přiřazená místa objednávky s okolím, při rozptýlených místech respektovat minimální čitelnost a nabídnout seznam; bez vazeb celý plán pouze na výslovné otevření |
| „Ukázat místo“ v seznamu | Přepnout správný plán, přiblížit přiměřeně a zvýraznit; fokus zůstane na vyvolávajícím tlačítku, oznámení popíše cíl. Samostatné „Přejít na plánek“ umožní klávesnici přejít k ovládání |
| Klik na vlastní bod, je-li callback doplněn | Aktivovat odpovídající konkrétní vazbu v seznamu; při více souvisejících položkách zobrazit lokální výběr, ne náhodný ticket. Nedělat náhlý přesun fokusu mimo mapu |
| Tab pryč a zpět / zvětšení / resize | Zachovat aktivní místo a kameru pro tutéž revizi plánu; při změně rozměru upravit pouze nutné meze, ne pokaždé resetovat fit |
| Jiná objednávka | Zrušit její staré zvýraznění, aktivní vazbu a kamera-default; neukázat předchozí soukromé popisky ani během loadingu |
| Potvrzená nová revize přiřazení | Obnovit mapu i seznam z koherentní kombinace revizí ticketů, přiřazení a layoutu; neoznačit smíchané revize za aktuální stav. Zachovat aktivní položku podle item/ticket ID, pokud stále existuje; její nové místo označit oznámením a akcí „Ukázat nové místo“, nikoli nečekaným zoomovým skokem |
| Zaniklá aktivní vazba | Zachovat ticketový řádek, je-li platný, oznámit „Přiřazení se změnilo“; zrušit neplatný highlight. Při odstranění řádku přesunout fokus na nejbližší stabilní nadpis, ne do prázdna |
| Obnovení selhalo | Označit staré údaje jako neověřené a blokovat tvrzení aktuálního vlastnictví. Pokud autorizace stále platí, zachovat čitelný poslední text; při odebrání autorizace jej odstranit |
| Pan/pinch/přerušení gesta | Žádné rezervace a žádná dodatečná aktivace při pointer cancel. Prázdný drag posouvá kameru. Escape neopakuje klik ani nevytváří žádný commit |

Kamera patří pouze vizuálnímu prohlížení. Zoom +/-, „Všechna místa objednávky“ a „Celý sál“ mají textový/semantický název a fungují bez myši. Šipky uvnitř explicitně aktivního ovládání mapy mohou posouvat plán, mimo něj zůstávají tabové a textové klávesy původnímu cíli. Mobilní pinch neblokuje scroll celého panelu, když gesto začalo mimo plánek. Lokální overlay se po opuštění nebo změně kontextu vždy vyčistí.

Velký sál se nevykresluje jako tisíce focusovatelných tlačítek a tooltipů současně. Klávesnicový přístup zajišťuje především seznam této objednávky. Záložka může zobrazit omezené/stránkované řádky, ale souhrn a mapa musí rozlišit úplnou objednávku od právě načtené části. Pokud nejsou všechny vazby načtené, pojmenovat „Zobrazená místa“ a počet načtených, nikdy „Všechna místa objednávky“. Načítat pouze dokument aktivního plánu, další až při přepnutí; nesměšovat opožděné resources/revize dvou sálů. Nezavádět nový renderovací engine ani skryté snižování přesnosti mapování kvůli výkonu.

### Předání do existující správy míst

Samotné otevření plánu nikdy nevolá swap/cancellation/publication preview: současný `preview_blueprint_swap` provádí skutečného mutačního vlastníka uvnitř záměrného rollbacku. Název „preview“ není důkaz čistého čtení.

Pokud je potřeba změnit místo, dostupná akce zní „Otevřít správu míst“, nikoli „Přesadit“ přímo nad canvasem detailu. Je podmíněná skutečným oprávněním a existujícím podporovaným cílem. Předává ověřené identifikátory objednávky, ticketu/položky a plánku jako navigační záměr; nepředává předem schválenou mutaci, cenu, novou rezervaci nebo oprávnění.

Cílový hostitel znovu načte svůj kontext, explicitní kompatibilitu a povolené operace. Atomický přesun, zrušení, produktový nesoulad nebo úpravu plánu řeší jeho stávající náhled/potvrzení/receipt. Pokud dnes neumí konkrétní deep-link cíl, technický plán smí přidat úzké cílení; detail nesmí předstírat dokončené předání klikem na obecnou obrazovku bez vybraného kontextu.

Opuštění detailu chrání jeho rozepsaná pole. Rozpracovaná nebo nejistá mutace ve správě míst patří tamnímu controlleru; detail neotevírá souběžný pokus, nevyčistí frozen request ani automaticky nereplayuje akci. Po potvrzeném výsledku se při návratu obnoví vazby, obchodní stav, platby a relevantní historie; úspěch neoznamuje pouhé zavření editoru. Po zrušení dialogu se stav nevymýšlí ani lokálně „nevrací“, pouze se načte autoritativní výsledek. Nové PDF nebo změnový e-mail zůstává oddělenou výslovnou akcí existujícího workflow.

### Jeden adversariální průchod návrhem

Proveden jediný cílený průchod proti nejrizikovějším předpokladům; šlo o čtení zdrojů a návrhovou kontrolu, nikoli test běžící aplikace.

| Pokus návrh rozbít | Zjištěná slabina původního zjednodušení | Zapracované rozhodnutí |
| --- | --- | --- |
| Jeden ticket má dvě primární admission položky; vedle toho platná objednávka obsahuje opakované doplňky | První případ je `ADMISSION_DATA_AMBIGUOUS`, zatímco doplňky se nesmějí ztratit sloučením | U nejednoznačného vstupu varování a žádná automatická volba/editace; doplňky zachovat po instancích |
| Polovina pohovky je v jiné objednávce/formuláři | Automatická expanze jako při rezervaci by ukázala cizí vlastnictví | Lokální zvýraznění jen oprávněných vazeb; obrys jednotky bez osobních dat; mutaci řeší původní náhled |
| Zrušené místo mezitím někdo jiný koupil | Starý snapshot by vypadal jako stále rezervované místo | Současné vazby jediný zdroj aktivního overlaye; historie textově |
| Plan editor změnil produkt a uložil, detail má starý kontext | Návrat může používat starou kompatibilitu a částky | Obnovení podle výsledku i při návratu, žádný odhad z vybraného widgetu |
| Sál se stejným názvem/seat label existuje ve dvou formulářích | Textové porovnání by zvýraznilo jiné místo | Per-blueprint identita a zdroj objednávky oddělený od cílového plánu |
| Uživatel čte objednávku, ale ne držitele ostatních míst | Obecný seating context by mohl prozradit jiné osoby | Úzká order-scoped projekce, žádné cizí popupy; oprávnění odvozena na serveru |
| Historický/importovaný údaj u vytištěného ticketu nesouhlasí s PDF | Nesoulad svádí k nabídce nepodporovaného přesazení nebo tvrzení, že se PDF opravilo | Zachovat `BATCH_TICKET_PRINT_IMMUTABLE`, přiznat nesoulad; stažený dokument se sám nezmění |

Zbývající nejistoty jsou konkrétní: dostupnost přesné projekce všech opakovaných položek a sold-batch vztahů, autorizace geometrie pro čtenáře objednávky a minimální veřejné API pro kameru/hit-test. To jsou ověřitelné body technického plánu, nikoli důvod přidat klientskou heuristiku.

### Další konkrétní akceptační příběhy pro mapu

13. **Pohovka a rozlišení doplňků od chybného vstupu.** Dva tickety mají po jedné primární vstupní položce a po jednom místě atomické pohovky. Seznam ukáže dvě osoby/vazby, mapa dva body; aktivace jednoho nic nerezervuje. Opakované stejné doplňky zůstanou jednotlivými instancemi. Oddělený negativní případ: ticket se dvěma primárními admission položkami musí zobrazit `ADMISSION_DATA_AMBIGUOUS`, bez automatického výběru prvního místa či nabídky editace.
14. **Částečné zrušení a nové obsazení.** Ze čtyř vstupenek je jedna použitá, druhá zrušená a její původní místo už prodané jinam. Detail staré objednávky neukáže nového držitele ani aktivní highlight zrušeného místa; použitý ticket zůstane viditelný, zbylé dva se neztratí. Finance se neodvodí jen z počtu bodů.
15. **Stejná jména ve dvou sálech.** Objednávka má místo 1 u stolu 4 ve dvou plánech. „Ukázat místo“ pokaždé otevře správný plán podle ID. Opožděná odpověď prvního plánu nepřepíše druhý; návrat zachová jeho kameru.
16. **Neměnná tištěná vstupenka a historický nesoulad.** Prodaný vytištěný ticket má omezení `BATCH_TICKET_PRINT_IMMUTABLE`; detail nenabídne přesazení jako podporovaný postup. Pokud historická/importovaná data ukazují jiné místo než již vytištěné PDF, přizná rozdíl a předá jej k existujícímu oprávněnému řešení bez automatické mutace. Symbol ani dokument se nevymýšlejí znovu, PDF se samo neaktualizuje a e-mail neodejde.
17. **Stání v plné ploše.** Tři zakoupené vstupy na Balkon, plocha má nyní nulovou volnou kapacitu. Detail zobrazí tři platné vstupy a jednu příslušnou plochu; žádné „vyprodáno, objednávka neplatná“. Po zrušení jednoho je souhrn dva aktivní plus jeden historický.
18. **Ztráta mapy bez ztráty objednávky.** Čtenář objednávky nemá přístup ke geometrii nebo selže ověřený obrázek. Text místa, osoba a PDF dle oprávnění zůstanou; náhled přizná omezení. Žádný checkout secret ani alternativní renderer.
19. **Změna při současném prohlížení.** Správce A sleduje ticket, správce B jej přesadí a změní plán. Po obnově se změní seznam i overlay společně, fokus zůstane u ticketu a objeví se „Umístění se změnilo“. „Ukázat nové místo“ pracuje s novou revizí; starý bod se neoznačí jako vlastněný.
20. **Hustý tmavý sál a ovládání bez myši.** Stovky sousedních židlí, české i RTL názvy a tmavé autorské pozadí. Vlastní místo je čitelné obrysem, seznam je kompletní alternativou, kamera má klávesnicové ovládání. Pinch/drag/cancel nevytváří výběr rezervace; resize nevrací správce stále na počáteční zoom.

Upřesnění koherence čtení: samotná `layoutRevision` neodhalí výměnu nebo přeobsazení místa při nezměněné geometrii. Core detail a mapa musí souhlasit i v očekávaném fingerprintu aktuálních placement tuples (readstamp). Při nesouladu/409 se neukáže vlastnictví ze smíchaných dat; proběhne nejvýše jedno řízené společné obnovení. Další konflikt se zobrazí jako neověřený stav s ručním obnovením, bez nekonečného přenačítání nebo ztráty rozepsaných polí.
