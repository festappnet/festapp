# Jak dostat vstupenky.online do Make

Datum: 2026-10-28. Stav: schválený směr, rozpracovaná příprava; účet, živé propojení a katalogové vydání dosud nejsou ověřené. Ověřování při implementaci: standard (OAuth a veřejné datové rozhraní).

## Aktuální zadání a úsporné provedení

Poslední instrukce vlastníka výslovně zahrnuje celý postup až k registraci a odeslání konektoru, ne pouze lokální přípravu. V rozsahu jsou: existující účet nebo bezplatná registrace `info@festapp.net`, běžné ověření vlastnictví e-mailu, založení app a testovacího prostředí, vývoj, nezbytné izolované OAuth registrace, cílené nasazení Make části do stávající regionální MCP služby, testování, Publish, jedna žádost o review a řešení jejích připomínek. Podmínkou jsou nulové pevné poplatky a splněné brány tohoto plánu. Nežádat znovu souhlas s již schválenými kroky. Případnou partnerskou přihlášku vyřídit, pokud je pro vydání potřebná; dobrovolný program není důvod odkládat konektor. Nový placený závazek, nepravdivé prohlášení ani změny jiných produktů autorizované nejsou.

Práce má šetřit tokeny i čas bez vypouštění auth a publikačních kontrol:

- Plán přečíst celý jednou; pokračovat z aktuálního důkazu a změn od poslední revize. Neopakovat rešerši, čtení nezměněných zdrojů, již provedenou kontrolu mailů ani selhaný browser pokus bez nové informace. Externí podmínky znovu ověřit cíleně před jejich přijetím.
- Nejprve vyřešit přístup, OAuth a jeden report. Po jednom rozhodujícím transportním prototypu zvolit cestu, potom dokončit souvislou sadu modulů před finálními kontrolami. Nepřipravovat několik alternativních konektorů.
- Nezávislé čtení a lehké kontroly dávkovat. Úspěšné výstupy držet na jednu řádku; plné logy číst až při chybě. Nepřidávat další plán, audit, report ani test jen k zopakování stejného důkazu.
- Cílené auth/kontraktní testy mají standardní hloubku. Pro nezměněné vstupy používat již platné výsledky; po změně zopakovat jen dotčené kontroly a povinné publikační gates. Žádný Flutter build, pokud Make změna Flutter nezasahuje.
- Do stavu průběžně uložit pouze aktuální fázi, revizi/digest, provedený krok, výsledek a přesný další krok. Historické receipty neměnit. Rutinní nasazení delegovat dle AGENTS.md, další agenty nespouštět bez oprávnění.
- Lidskou bezpečnostní výzvu nebo chybějící účet řešit jediným konkrétním požadavkem na nezbytný zásah. Nepřebírat uživatelův browser a nevyvolávat opakované ověřovací e-maily. Mezitím dokončit nezávislou lokální práci; neoznačit blokaci za hotové vydání.

Uživatel schválil pokračování a zvolil účet `info@festapp.net`. Vlastníkem implementace a důkazů je realizující agent, vlastníkem účtu a případných smluv provozovatel. Uložený přístup pro Make nebyl nalezen; cílené vyhledání komunikace z Make v připojeném Gmailu nevrátilo výsledky. To nedokazuje neexistenci účtu. Izolovaný prohlížeč na přihlašovací stránce zůstal na Cloudflare security verification i po běžném kliknutí na ověření. Žádný účet ani žádost tím nevznikly. Aktuální příprava je v [integrations/make](../../integrations/make/README.md).

## Doporučený postup

Hlavní výsledek je vlastní aplikace **vstupenky.online** dohledatelná v katalogu Make, připojitelná běžným pořadatelem a použitelná pro pravidelný přehled prodeje. MCP Client je krátký ověřovací krok a druhá možnost připojení, nikoli povinný distribuční mezikrok. Připojení přes obecný MCP Client samo o sobě vlastní katalogovou položku nevytvoří.

Plán je připravený k ověřovacím etapám A-C. Implementace všech modulů a veřejné vydání mají níže uvedené rozhodovací brány. Nevyřešenou kompatibilitu nebo smluvní podmínku nelze označit jako hotovou jen dokončením dokumentace.

| Cesta | Co získáme | Co ještě potřebujeme |
| --- | --- | --- |
| MCP Client | Používání našich nástrojů ve scénáři Make | Ověřit OAuth a výstupy v reálném Make |
| Verified remote MCP server | Výběr našeho serveru v nabídce MCP Client | Zjistit proces zařazení; veřejný návod jej nepopisuje |
| Vlastní verified app | Samostatně dohledatelný konektor s pojmenovanými moduly | Implementaci, testovací scénáře a review Make |
| Community app | Partnerskou distribuci aplikace | Partnerství a jeho podmínky; není to zvolená první cesta |

Rozdíly mezi custom, community a verified aplikacemi popisuje [Make](https://help.make.com/introduction-to-make-apps). Custom app označená jako public se stále instaluje přes pozvánku. Community katalog není obyčejná pozvánka: jeho [podmínky](https://developers.make.com/custom-apps-documentation/community-apps/terms-and-conditions) vyžadují partnerskou smlouvu.

## Co už máme

- Regionální MCP: `https://mcp.vstupenky.online/mcp`. Homepage služby: `https://vstupenky.online/`.
- `tools/festapp/src/remote/server.mjs`: OAuth issuer, předregistrovaní klienti, token endpoint auth `none`, dynamická registrace vypnutá.
- `tools/festapp/src/remote/config.mjs`: přesné redirect URI, stropy scopes a profil dat pro každého klienta.
- `packages/festapp_contracts/mcp-permissions.mjs`: společný seznam oprávnění a operací. Pro první verzi postačí `context.inspect`, `access.inspect`, `orders.report`, `orders.list`, `orders.inspect`.
- `integrations/chatgpt/README.md`: již ověřené připojení jiného klienta, ne důkaz kompatibility Make. Profil `order-summary` skrývá osobní údaje kupujících a volné texty.

Repozitář byl prozkoumán na `d2ed02f81`. Před implementací porovnat aktuální zdroj i skutečně nasazenou konfiguraci. Místní zdroj není doklad produkčního nasazení.

### Fakta, rozhodnutí a otevřené body

| Typ | Bod | Způsob uzavření |
| --- | --- | --- |
| Fakt | OAuth klienti mají `none`, PKCE S256 a pevné callbacky; otevřené DCR neexistuje | `remote/server.mjs`, `remote/config.mjs`; ověřit i aktivní server |
| Fakt | Samotný order-summary profil není zákaz zápisu; operace omezuje také scope a platný souhlas | `remote/delegation.mjs`: `permitsOperation`, `current`, `authorizeOperation` |
| Fakt | Dva povolené scopes zpřístupňují i `ticket_layouts.inspect`, tedy celkem šest MCP read tools | `mcp-permissions.mjs`: `READ_OPERATIONS` a orders read; neslibovat přesně pět dostupných tools |
| Rozhodnutí | Native MVP nabízí jen čtení čtyř oblastí plus povinný univerzální modul | Žádný zápisový scope, profil order-summary a omezené cílové rozhraní |
| Rozhodnutí | API ani doménová logika se nekopírují do Make | Reálné volání projde stejným `Operations.invoke` a `DelegatedOwner` |
| Otevřené | Make umí náš přesný OAuth a wire protokol bez slabší autentizace | Protokol `oauth-compatibility.json` podle brány G1 |
| Otevřené | Native konektor použije MCP, nebo tenký HTTP transport | Jediný dokumentovaný výsledek brány G2; dokud chybí, nepsat všechny moduly |
| Otevřené | Všechny pevné náklady vydavatele jsou nulové | Konkrétní tarif, aktuální podmínky a datum v `publisher-costs.json` |
| Blokace živého ověření | Přístup do účtu Make není navázaný | Dokončené přihlášení v izolované relaci nebo oficiální přístup s minimálními právy; nepřebírat uživatelovu relaci |

Název poskytovatele v účtu či veřejné značce není automaticky právní název smluvní strany. Ten při žádosti ověřit z aktuálních údajů provozovatele.

## 1. Připojení přes MCP

Make má aplikaci **MCP Client** v otevřené betě. Pro test použít modul **Call a tool**, který přímo volá vybraný nástroj. AI není pro tento postup potřeba. Funkce Make MCP server slouží opačnému směru, tedy ovládání Make z externího klienta.

### Nejdřív vyřešit OAuth

1. V izolované testovací organizaci Make založit scénář a přidat MCP Client > Call a tool > Create a connection.
2. Zvolit **+ New MCP Server**, zadat náš endpoint a název vstupenky.online.
3. Zjistit, zda vlastní server umožňuje zadat předregistrované OAuth client ID a PKCE bez secretu. Zaznamenat skutečně použitý callback, resource, scopes a způsob obnovy tokenu bez jejich tajných hodnot. Make dokumentuje MCP callback `https://www.make.com/oauth/cb/mcp`.
4. Teprve po ověření vytvořit samostatnou chráněnou registraci, navržené ID `festapp-make-mcp`, přesný callback, explicitní `dataProfile: order-summary` a strop `festapp:ticket-layouts:read`, `festapp:orders:read`. `offline_access` požadovat podle ověřeného refresh toku. Registrace nemá být součástí veřejného balíčku.
5. Pokud Make pro vlastní server vyžaduje DCR nebo nenabízí potřebnou konfiguraci klienta, zaznamenat konkrétní chybu. Pak ověřit u Make možnost zařazení do seznamu serverů s OAuth konfigurací. Podpora OAuth obecně neprokazuje kompatibilitu s naším klientským modelem.

Nepoužívat registraci `festapp-chatgpt`, nekopírovat jeho tokeny a nezapínat plošnou dynamickou registraci. Pole API Key / Access token není náhradou za bezpečné přihlášení a obnovu uživatelského souhlasu.

Tyto kroky vycházejí z [návodu MCP Client](https://apps.make.com/mcp-client); úspěšné připojení našeho serveru v Make dosud není ověřeno. Beta může změnit funkce i cenu. Manuální URL není automatické zařazení mezi ověřené servery.

### První scénář a důkaz funkčnosti

Po ověření konfigurace a cíleném nasazení v rozsahu aktuálního schválení:

1. Přihlásit syntetického pořadatele, povolit pouze jeho testovací akci.
2. Přes Call a tool načíst dostupný kontext a nástroje. Použít skutečné názvy z `tools/list`, nepřepisovat tečky či názvy odhadem.
3. Vybrat konkrétní akci jejím ID a zavolat prodejní report. Namapovat součty do testovací tabulky; srovnat se stejným reportem v aplikaci, včetně měny a významu částek.
4. Ověřit stránkování seznamu a detail objednávky. Odepřená či neúplná odpověď musí zastavit export, ne vyrobit nulový prodej.
5. Ověřit obnovu po expiraci access tokenu, okamžité odvolání souhlasu, zákaz cizí akce a absenci osobních údajů v logu.

Uložit sanitizovaný blueprint, očekávané výsledky a datum do budoucího `integrations/make/evidence/`. Tokeny, session a přihlašovací údaje pouze do chráněného úložiště. Test má být ruční a malý; neběží trvalý polling ani placený AI modul.

**Výstup etapy:** skutečně funkční scénář, nebo doložená OAuth překážka a konkrétní cesta jejího odstranění. Dostupný HTTP endpoint nestačí.

## 2. Vlastní konektor v katalogu

Pro vlastní produkt zvolit standardní app review jako autor služby. Community partnerství nepovažovat za povinný mezikrok. [Technology Partner program](https://www.make.com/technology-partners) je určený autorům vlastního produktu; zveřejněný postup začíná ověřenou aplikací a teprve potom partnerskou přihláškou. Program výslovně uvádí vstup bez poplatku a partnerský sandbox. Není tím potvrzena každá případná podmínka vývoje či trvalého zveřejnění.

### Účet, poplatky a připravené podklady

Nejdřív ověřit, zda už existuje náš účet nebo žádost, a nevytvářet duplicity. Použít existující firemní organizaci, pokud má správného vlastníka. Pro podklady použít značku vstupenky.online, provozovatele Festapp, homepage služby, vlastní regionální logo a kontaktní e-mail `info@festapp.net`; právní identitu převzít z aktuálních údajů provozovatele.

Vstup do Technology Partner programu je podle jeho FAQ bez poplatku. Veřejné stránky review ale nepotvrzují všechny náklady vydavatele ani potřebný tarif před vznikem partnerství. V účtu a aktuálních smluvních podmínkách ověřit registraci, vývoj, testování, review i dlouhodobé ponechání v katalogu. Pokud to nepůjde zjistit, připravit jeden stručný dotaz Make; před jeho případným odesláním ověřit autorizaci k této konkrétní komunikaci a absenci stejného otevřeného dotazu. Žádné předplatné ani pevný poplatek není schválený. Kredity zákazníka za běh scénářů jsou jiný náklad; viz [ceník a účtování kreditů](https://www.make.com/pricing). Nezapínat automatický nákup kreditů.

### Moduly první verze

| Modul | Kanonická operace | Výstup |
| --- | --- | --- |
| Dostupné akce | `access.inspect` a existující kontext | Jen akce dostupné aktuálnímu souhlasu a oprávněním |
| Přehled prodeje | `orders.report` | Částky, měna, počty a původní upozornění reportu |
| Seznam objednávek | `orders.list` | Omezené stránky bez osobních údajů |
| Detail objednávky | `orders.inspect` | Identifikátory, stav a částky v profilu order-summary |
| Vlastní API volání | Schválené veřejné čtecí rozhraní | Stejná oprávnění a datový profil |

To je návrh, ne existující sada Make modulů. První verze neobsahuje „nová objednávka“, webhook, tvorbu objednávek, párování plateb ani rozesílání. Pravidelný report nevyžaduje nový backendový trigger. Export kontaktů do newsletteru v tomto profilu není podporován.

### Rozhraní a architektura

Implementace patří do `integrations/make/`, společná logika zůstává v `tools/festapp/src/operations/` a kanonickém backendu. Viz [pravidla integrací](../../integrations/README.md) a [sdílené operace aplikace a MCP](../architecture/admin-mcp-parity.md). Make nepočítá vlastní zaplacení, kapacitu ani účetní součty.

Před psaním všech modulů udělat jediný transportní prototyp: OAuth + jeden report. Ověřit, zda custom app umí spolehlivě obsloužit MCP inicializaci, hlavičky, session a JSON/SSE odpovědi. Prostý POST `tools/call` není kompletní klient MCP.

Pokud prototyp neprojde nebo Make takové rozhraní nepřijme do review, zvoleným řešením je tenký verzovaný HTTP adaptér ve stávající službě nad stejným vlastníkem operací. Před implementací doplnit přesný kontrakt, autentizaci a testy do tohoto plánu. Nevymýšlet neexistující REST URL ani přímé přístupy k tabulkám. Nedělat paralelně MCP wrapper i HTTP adaptér.

Pro native app použít samostatného OAuth klienta. Make pro custom apps dokumentuje callback `https://www.make.com/oauth/cb/app` a PKCE; to je jiný callback než u MCP Client. Ověřit token exchange a refresh v obou směrech. [OAuth konfigurace](https://developers.make.com/custom-apps-documentation/app-components/connections/oauth2)

Make vyžaduje také univerzální modul. Povolit jen relativní cesty na pevně zvoleném vlastním originu, bez předávání bearer tokenu při přesměrování. Server znovu kontroluje profil dat a scopes, i když uživatel ručně sestaví požadavek. Zápisové doménové operace zůstávají zakázané, i když čtecí transport používá HTTP POST. Nelze odvozovat oprávnění jen z HTTP metody. [Pravidla univerzálního modulu](https://developers.make.com/custom-apps-documentation/app-components/modules/universal-module)

**Výstup etapy:** jeden zvolený transport, funkční moduly a obnovitelné OAuth připojení, žádná druhá implementace objednávek. Prototypy a testovací moduly před publikací odstranit. ChatGPT registrace a historické důkazy zůstávají samostatné.

### Přesný kontrakt modulů

Kanonické deskriptory v `tools/festapp/src/operations/catalog.mjs` vlastní schémata, `Operations.invoke` provádí operace a `public-orders.mjs` vlastní veřejnou projekci. Make vrstva překládá obálku a mapování polí. Nepřebírat běžné operator DTO obsahující kontakty a neodstraňovat citlivá pole až v Make: do Make logů se nesmějí vůbec dostat.

| Modul | Vstup | Mapování a okrajové případy |
| --- | --- | --- |
| Dostupné akce | Bez ID od uživatele | Volat `festapp_access_inspect`, vrátit položky `occasions`; `id` je hodnota výběru, `title` pouze popisek. Shodné názvy se neslučují. Prázdný seznam není chyba přihlášení. |
| Přehled prodeje | `occasionId` | `festapp_orders_report`; jeden výsledek pro jednu akci, zachovat report, měny, čekající vstupenky a varování. Seznam objednávek není zdrojem součtu reportu. |
| Seznam objednávek | `occasionId`, Make celkový `limit` (výchozí 10), volitelně `state`, `search` | `festapp_orders_list`; backendový limit stránky je samostatný, nejvýše 50. Vyhledávání jen přesný desetiznakový symbol `[A-Z0-9]{10}`. Interně pokračovat přes `nextCursor` jako `before`. Nepřidávat kurzor založený na offsetu. |
| Detail objednávky | `occasionId`, `orderId` | `festapp_orders_inspect`; kanonická odpověď je stránková obálka. Ověřit právě jeden odpovídající řádek; prázdno vrátit jako nenalezené/nedostupné. Nikdy nevzít první cizí řádek. |

Před implementací znovu odvodit vstupní i výstupní JSON Schema z `Operations.catalog` s profilem order-summary a skutečným stropem scopes. Nevést ručně nezávislou kopii schémat. Návrhový soubor `integrations/make/catalog-draft.json` je seznam modulů, nikoli hotový import Make.

Make List/Search vrací více bundles, Get/Report jeden objekt. Použít správný typ modulu, ne action vracející pole. V Make response nastavit `iterate`, `limit` a kurzorovou pagination podle [Search pravidel](https://developers.make.com/custom-apps-documentation/best-practices/modules/search-modules). Vstupní Make limit je volitelný s výchozí hodnotou 10; explicitně prázdná hodnota podle doporučení Make požaduje všechny výsledky do technických mezí, nikoli tiché omezení na 50. Konečné chování prázdného pole doložit scénářem.

Backendová stránka má nejvýše 50 položek; Make limit omezuje celkový počet vydaných bundles napříč stránkami. `before` patří do vnitřního stránkování, první verze jej nevystavuje jako náhradu exportního checkpointu. Odpověď s `nextCursor:null` stránkování ukončí; opakovaný nebo rostoucí kurzor je chyba kontraktu. Backend řadí podle ID sestupně (`get_operator_orders_v1`); validovat tento směr, nejen odlišnost kurzoru. `access.inspect` nemá stránkování ani backendový limit: omezit výstup přes Make, nevymýšlet síťové stránky.

Make dokumentuje stropy [pagination](https://developers.make.com/custom-apps-documentation/component-blocks/api/pagination): 100 requestů celkem, 50 stránkovacích requestů, 3200 záznamů a 40 sekund. Do prototypu zaznamenat, jak se počítají inicializační/refresh requesty a jak se limit projeví ve skutečném Make. Není dovoleno automaticky dohánět zbytek jiným jobem ani označit omezený výstup za úplný export. Před vyčerpáním vlastního známého rozpočtu skončit s jasnou chybou; pokud Make ukončí běh samo, doložit jeho chování a popsat omezení v návodu.

Vícestránkový seznam není konzistentní databázový snapshot. Ověření bez duplicit a ztrát platí pro stabilní fixture; během běhu se stavy objednávek nebo příslušnost k filtru mohou měnit. Report a seznam mají vlastní okamžik čtení a nemusí spolu při souběžných změnách číselně souhlasit. MVP neslibuje účetní export ani exactly-once synchronizaci.

Peníze zachovat v původní reprezentaci a měně, bez JS float přepočtů nebo slučování měn. Stav objednávky, její hodnota, přijaté peníze a počet platných vstupenek jsou různá pole. Přesné mapování polí finančního reportu a jejich datové typy zafixovat na syntetickém reportu až v prototypu; žádné součty odhadnuté z názvů polí. Referenční scénář ukládá jediný report do předem určeného řádku tabulky. Opakování jej přepíše, nepřičítá peníze ani nepřidává další řádek. Pro tutéž akci neběží souběžné aktualizace. Pokud cílová služba neumí idempotentní zápis nebo potřebnou serializaci, zůstane první důkaz u výstupu Make modulu a omezení se uvede; nepřidávat vlastní databázový ledger kvůli ukázce.

`toolResult` v `tools/festapp/src/mcp/protocol.mjs` vrací MCP výsledek se `structuredContent` a chybovým příznakem. Transportní HTTP 200 ani úspěšné JSON parsování neznamenají úspěch operace. Native adaptér musí rozpoznat JSON-RPC error, `isError` i vnitřní `ok:false`; žádná z nich nesmí vydat úspěšný bundle. Nepoužívat AI ke čtení JSON odpovědi.

| Chyba | Chování konektoru |
| --- | --- |
| Expirace access tokenu | Obnova standardním OAuth tokem, nejvýše jedno opakování původního čtení |
| Odvolaný/expirující grant, neplatný refresh | Vyžádat nové připojení; žádná nekonečná obnova |
| Forbidden / nedostatečný scope | Zastavit, nezvyšovat souhlas automaticky |
| Neplatný vstup / chybné schéma | Srozumitelná chyba modulu, žádná náhradní prázdná data |
| 429 / retryable timeout / 5xx | Omezené opakování čtení podle Make a Retry-After; ne dvojité nezávislé retry smyčky |
| Chyba po první stránce | Selhání běhu a žádné potvrzení úplnosti; zápisy již provedené jinou aplikací nemusejí jít vrátit |

Doba access tokenu v současném issueru je 300 sekund, refresh/grant sedm dnů. Dlouhodobý bezobslužný scénář tedy není prokázaný a může vyžadovat nový souhlas; ověřit skutečný deployed profil a chování rotace. Kvůli Make neprodlužovat plošně životnost grantů ani nesdílet refresh token mezi klienty. Dva souběžné běhy musí projít rotací bez revokace druhého legitimního běhu; případný konflikt řešit serializací refresh v připojení, ne vypnutím replay ochrany issueru.

Pro MVP zachovat současnou konečnou délku grantu. Refresh access tokenu nemá prodloužit `Delegation.expiresAt`. Před vydáním musí uživatel dostat pravdivý návod na nové připojení po vypršení; „nastavte jednou a běží navždy“ není platný příslib. Pokud je takto časté připojování pro produkt nepřijatelné, je to samostatné rozhodnutí o klientské politice s testy revokace, nikoli drobná změna konstant v Make adaptéru.

Ani chybová větev scénáře neumí obecně vrátit zápisy provedené ve třetí aplikaci. První ukázka proto používá Report s jedním výsledkem, ne vícestránkový export. Budoucí kompletní synchronizace by potřebovala vlastní protokol dokončení a obnovy; v tomto MVP se neimplementuje.

### Rozhodovací brány před implementací celého konektoru

**G0 - účet a náklady.** Výstup `publisher-costs.json`: vlastník/ID organizace, zone, název tarifu a aktuální oprávnění k custom apps; samostatné položky cena vývoje, review, katalogu a ponechání. Každá položka má zdroj, datum a hodnotu confirmed-zero / nonzero / unknown. Zdarma vstup do programu nesmí vyplnit ostatní položky. Bez placeného závazku lze dál připravovat lokální kontrakty, nikoli nakoupit tarif.

**G1 - autentizace.** Výstup `oauth-compatibility.json` pro oba typy připojení zvlášť. Zaznamenat client ID, přesný callback, issuer, použitý token endpoint, auth method, PKCE S256, scopes, audience/resource a chování refresh rotace. Bez tokenů, autorizačních kódů či cookies. Ověřit state a vazbu odpovědi na původní připojení. Veřejný klient bez secretu s PKCE je současný kontrakt. Pokud Make vyžaduje confidential client, tajný token nebo jiné resource, nejde o pouhé doplnění metadat: zastavit tuto větev a navrhnout konkrétní změnu auth kontraktu. Jiné funkční připojení není důkaz kompatibility.

**G2 - transport.** Jeden prototyp OAuth + Report, záznam `transport-decision.md`:

Rozhodnutí realizace 2026-10-28: vlastní aplikace úspěšně dokončila OAuth, MCP
prototyp v reálném Make selhal na streamované odpovědi a vlastní parserové funkce
nejsou účtu povolené. Zvolen je jediný tenký JSON HTTP adaptér. Přesné cesty,
metody, chybové stavy, odvození schémat a strategie jediné OAuth audience jsou
zafixované v [transportním kontraktu](../../integrations/make/evidence/transport-decision.md).
Brána zůstává otevřená do úspěšného reportu v tomto transportu.

- MCP varianta projde pouze s doloženou inicializací, verzí protokolu, Accept hlavičkami, rozpoznáním JSON/SSE a chyb, session chováním a rozpočtem requestů. Současný server používá per-request handler bez trvalé MCP session; nedoplňovat zbytečný session store. Doložit mapovatelné strukturované odpovědi v reálné Make custom app. Generic MCP Client není tento důkaz.
- Pokud to nepůjde, zvolit jediný tenký HTTP adaptér ve stávající službě. Nejdřív doplnit do plánu konkrétní metody, cesty, error/status mapu, JSON Schema a právě jednu strategii OAuth audience. Token vydaný pro `/mcp` nelze bez výslovného kontraktu prohlásit za token pro libovolnou novou API resource. Zachovat stejnou delegaci, revokaci a `Operations.invoke`; žádný service role token ani druhé přihlášení přes heslo.
- Univerzální modul musí fungovat s vybraným rozhraním a nesmí umožnit obejít profil a scopes. Pokud review vyžaduje něco neslučitelného s bezpečným kontraktem, zaznamenat přesný požadavek a upravit návrh před implementací.

Brána je uzavřená až volbou jedné varianty a odstraněním druhého pokusného transportu. V dokumentaci zůstane důvod volby, nikoli udržovaný fallback. Existující MCP pro jiné klienty se nemaže.

**G3 - kvalifikace a vydání.** Všechny moduly mají syntetické scénáře, sanitizaci, chybové větve a přesný export zdrojů. Čerstvost logů před odesláním se ověřuje novým během, ne tvrzením „testováno dříve“. Není přípustné Publish se skrytými pokusnými komponentami. Aktuální nulové pevné náklady a skutečnou dostupnost konektoru lze doložit jinak než marketingovým formulářem.

## Realizační etapy a přejímka

Každá etapa aktualizuje jeden sanitizovaný stavový záznam v `integrations/make/evidence/`. Označení prepared, tested, submitted a released se nesmějí zaměňovat.

| Etapa | Konkrétní práce | Podmínka dokončení |
| --- | --- | --- |
| A - účet a podmínky | Účet info@festapp.net; potvrdit vlastníka, Make zone a tarify. Sepsat důkaz nákladů. | Přístup bez narušení uživatelova okna; žádný pevný poplatek ani automatický nákup kreditů |
| B - MCP pilot | Samostatná registrace a prototyp dle etapy 1; zachytit callback, PKCE, resource a refresh | Syntetický report úspěšný, cizí akce a revokace odmítnuté; nebo doložená překážka OAuth |
| C - native transport | `integrations/make/` s jedním report modulem a connection; ověřit kompletní MCP komunikaci, případně konkretizovat jediný HTTP adaptér | Úspěšné přihlášení, typované výstupy a chyby bez tajných údajů v Make logu |
| D - celé MVP | Rozšířit zvolený transport o zbývající moduly a univerzální modul, exportovat zdroje z Make do repozitáře | Všechny moduly fungují; žádné pokusné komponenty; schémata odpovídají kanonické projekci |
| E - kvalifikace | Cílené lokální testy a aktuální reálné Make scénáře; připravit dokumentaci a metadata | Všechny níže uvedené případy doložené včetně mezí ověření |
| F - vydání | Zkontrolovat konkrétní finální podmínky a rozsah autorizace, Publish a jediné review | Oddělená potvrzení přijetí a vydání; nový uživatel konektor najde a připojí |

Etapy C-E mohou pokračovat i při nekompatibilitě obecného MCP Client, pokud je prokázaná kompatibilita OAuth vlastní aplikace. Celý projekt nesmí zablokovat pouze chybějící položka v nabídce ověřených MCP serverů. Naopak bez vyřešeného přístupu a OAuth se netvoří zdánlivě hotový import s vymyšlenými endpointy.

### Přejímací scénáře

1. **Přihlášení:** neplatný callback, verifier nebo resource se odmítne; scope nelze rozšířit a Make nedostane grant jiného klienta. Refresh po více než 300 sekundách funguje; revokace zablokuje i opakování již použitého čtení.
2. **Výběr akce:** dvě stejnojmenné syntetické akce, dostupná jen jedna; rozhoduje ID a aktuální oprávnění. Práva odebraná během připojení zastaví další čtení.
3. **Report:** shoda s kanonickým reportem pro syntetické zaplacené, nezaplacené, zrušené a čekající položky. Nulové, neznámé a chybové hodnoty se nerozpustí do jedné nuly.
4. **Stránkování:** aspoň 51 syntetických objednávek ve stabilní fixture, výstup bez ztrát a duplicit přes více stránek; celkový Make limit 10/51/52, prázdná hodnota, poslední stránka i nepostupující kurzor. Samostatně přesný symbol na pozdější stránce a záměrně neúplné hledání. Při změně stavu objednávky za běhu neslibovat snapshot.
5. **Detail a data:** nenalezené ID, ID z jiné akce a z jiného tenantu nic neprozradí. Striktní projekce objednávky nepřipustí customer, note, responses, QR ani neznámá pole; report posuzovat podle vlastního kanonického schématu, nikoli schématu objednávky. Finanční typy a měny zůstávají zachované.
6. **Chyby a retry:** včetně HTTP 200 s doménovou chybou, 429, timeoutu a chyby druhé stránky. Ověřit, zda už Make vydal předchozí bundles a co skutečně zůstalo v cílové službě; žádný slib automatického rollbacku cizích zápisů. Referenční jednorázový report po opakování nevytvoří další řádek.
7. **Univerzální modul:** zápisová operace i absolutní/cizí URL jsou odmítnuté; žádný token v hlavičkách při redirectu, blueprintu, výstupu či logu.
8. **Dlouhý běh:** rotace při dvou souběžných scénářích a dosažení expirace grantu mají doložené chování. Uživatelský návod jasně říká, kdy je potřeba nové připojení. Expiraci sedmidenní delegace testovat řízeným časem v disposable prostředí; živý pěti minutový refresh provést v reálném Make bez zkracování produkční TTL.
9. **Zátěž a cizí klienti:** souběh tří operací jednoho grantu vyvolá řízené omezení, nikoli únik nebo pád. Změna Make nesmí změnit katalog, scopes, callbacky ani granty stávajícího ChatGPT klienta. Současný server má strop 2 aktivních requestů na grant, 16 celkem a 60/min na grant; ověřit aktivní nastavení a pracovat v jeho mezích.

Scénáře používají izolovaná syntetická data. Stávající reviewer demo s osmi objednávkami pro test 51 řádků nestačí; nerozšiřovat bez domluvy účet používaný pro probíhající ChatGPT review. Testy Make autentizace musí použít Make klienta, ne pouze přejmenovanou ChatGPT fixture. Živý Make průchod a lokální simulace backendu mají oddělený důkaz.

## 3. Testy a žádost

Před review připravit stručnou veřejnou dokumentaci API, konfiguraci připojení, popis dostupných polí a podpory. Make reviewer potřebuje čerstvé scénáře pokrývající každý modul. Doložit stránkování, limity, práci s daty a očekávanou chybovou odpověď. Logy pouze syntetické; auth hlavičky a tokeny sanitizovat. [Požadavky review](https://developers.make.com/custom-apps-documentation/app-review/prerequisites)

Lokální ověřování při implementaci: v `tools/festapp/` spustit přes `pnpm exec node --test --test-concurrency=1` relevantní `test/remote.test.mjs` a nové cílené testy Make adaptéru. Doplnit testy izolace klientů, chybného callbacku/resource, revokace a pokusu obejít read-only profil univerzálním modulem. Potom jeden skutečný průchod v Make, včetně refresh. Nevydávat pouze průchod unit testy za připravenost katalogu.

### Soubory, testovací vrstvy a důkazy

| Vlastník | Co do něj patří |
| --- | --- |
| `integrations/make/` | Exportované zdroje app, connections, modules, RPC výběru akcí, samples a interface; přesné podadresáře podle editoru zvoleného v prototypu |
| `integrations/make/scripts/` | Deterministický export/build a kontrola souladnosti schémat, až existuje skutečný transport; žádný druhý ručně vedený seznam oprávnění |
| `tools/festapp/src/operations/` | Kanonické deskriptory a projekce; měnit pouze chybějící společný kontrakt, ne vytvářet `make-orders` s kopiemi doménových výpočtů |
| `tools/festapp/src/remote/` | Případný tenký HTTP vstup a sdílené ověření tokenu/delegace; chráněná produkční registrace se neukládá do tohoto adresáře |
| `tools/festapp/test/remote.test.mjs` | Stávající OAuth a wire regresní kontrakt; chrání i ostatní klienty |
| `tools/festapp/test/make-transport.test.mjs` (navržený) | Skutečný zvolený executor, přesná odpověď/chyba a klientská izolace; nenahrazovat autentizaci mockem, který vždy vrací autorizovaného uživatele |
| `tools/festapp/test/orders-postgres.test.mjs` a nový čtecí případ | Reálný SQL scope a projekce pro cizí akci, tenanta a cursor; jen disposable databáze |
| `integrations/make/evidence/` | Sanitizovaný výsledek bran, exportní digest, zdrojová revize a odkazy na aktuální testovací běhy/review; ne osobní nebo přístupové údaje |

Reálné DB testy vyžadují `FESTAPP_MCP_TEST_DATABASE_URL` a `openDisposableDatabase` z `tools/festapp/test/postgres.mjs`. Stav skipped není úspěšný test SQL. Připravit fixture s pozastaveným e-mailovým workerem bez URL, vytvořit syntetické členství a objednávky a vše odstranit rollbackem. Nikdy nesměřovat proměnnou na produkci. Pokud se mění backendový kontrakt, použít kanonické SQL/migraci a příslušné databázové kontroly; plán nepředpokládá novou tabulku ani migraci jen kvůli transportu.

Příkazy po implementaci ze složky `tools/festapp/` (pokud závislosti chybí, nejdřív `pnpm install --frozen-lockfile`; verze pnpm 11.24.0):

```sh
pnpm exec node --test --test-concurrency=1 test/remote.test.mjs test/make-transport.test.mjs
pnpm exec node --test --test-concurrency=1 test/orders-postgres.test.mjs
```

Nový testovací soubor je součástí budoucí implementace, dnes neexistuje. SQL příkaz má význam pouze s ověřenou disposable fixture. Při změně generátoru nebo Make mapování přidat cílený kontraktní check tam, kde bude skutečný build; nevytvářet falešný test hotového konektoru nad samotným návrhovým JSON.

Každý důkaz uvádí zdrojový commit a digest použitého exportu, Make zone, app ID/verzi, ID testovacích scénářů, čas, prostředí a co bylo skutečně provedeno. Podporu chybového případu nelze doložit jen tím, že je uvedený v testovacím seznamu. Soubor `preparation-20261028.json` zůstává historickým záznamem přípravy; pozdější fáze dostanou vlastní datum a nepřepíšou původní neprovedené kroky na provedené.

Postup odeslání podle [Make review](https://developers.make.com/custom-apps-documentation/app-review/request-app-review):

1. Odstranit pokusné komponenty. Akce **Publish** je podle dokumentace nevratná; zveřejněné komponenty nelze jednoduše smazat.
2. Po připravenosti a autorizaci publikace použít Publish, nastavit viditelné moduly a otevřít Review.
3. Vyplnit dokumentaci API a odkazy na čerstvé testovací scénáře. Request review zahájí posouzení.
4. Doplnit navazující formulář: vztah k dodavateli, kontakty, kategorii, logo a web.
5. Automatické i ruční připomínky řešit ve stejném vlákně; po úpravách obnovit testovací logy.
6. Zaznamenat přijetí, schválení a skutečné vydání odděleně. Hotovo je až dohledání konektoru z jiné organizace a úspěšné připojení.

### Řízení vydání a návratu

Před publikací zmrazit export app včetně connection, module/RPC definic, samples a interfaces a zaznamenat SHA256. Změna po tomto bodě zneplatní příslušné testy, nikoli automaticky všechny ostatní důkazy. Žádost musí odkazovat na stejnou app/verzi jako poslední úspěšné scénáře. Před retry odeslání zkontrolovat portál i potvrzovací e-mail; timeout není důkaz, že žádost nevznikla.

Pokud vznikne nový serverový transport, vydat nejprve zpětně kompatibilní server s platným issuerem a izolovanou registrací. Potom otestovat privátní app v Make. Teprve hotový export použít pro nevratný Publish a review. Žádný Flutter build, změna dalšího tenantu nebo přepnutí ChatGPT registrace není součástí vydání Make. Rutinní autorizované nasazení delegovat podle AGENTS.md se zafixovanou revizí a cílem.

Před Publish lze odstranit pilotní scénáře a nepoužité privátní komponenty. Po Publish už odstranění app a jejích součástí není běžný rollback; použít podporovaný postup Make a nezakládat druhou veřejnou app se stejnou značkou. Při incidentu nejdřív zastavit vlastní pilotní scénáře a odvolat konkrétní Make delegace. Odstranění klientské registrace je širší odstavení všech jejích uživatelů a vyžaduje popsaný dopad. Obnovení serverové verze nesmí načíst konfiguraci, které nerozumí, ani otevřít širší scopes. Případné odstranění nového endpointu až po vypnutí jeho klientů; existující MCP a ostatní granty zůstávají funkční.

Podpora musí umět rozlišit vypršelý souhlas, odebraná oprávnění, vyčerpané Make kredity, dosaženou pagination mez a nedostupný backend. Uchovávat jen kód výsledku, request ID, verzi a dobu běhu; žádné bearer tokeny nebo celé odpovědi s objednávkami. Doba držení důkazů a přístup reviewer vycházejí z aktuálních podmínek Make a používají pouze syntetická data. Při změně API/schema aktualizovat nejdřív cílené testy a vývojovou verzi; aktualizace veřejné app opět podléhá pravidlům Make.

## Co je otevřené a kdy je hotovo

- [ ] Potvrzené nulové pevné náklady vydavatele, včetně potřebného vývojového tarifu.
- [ ] Prokázaná kompatibilita Make OAuth; žádné vypnutí klientských omezení.
- [ ] MCP scénář funguje, nebo je jeho konkrétní překážka doložená.
- [ ] Native app má jeden zvolený transport a všechny moduly používají kanonické operace.
- [ ] G0-G3 jsou doložené, ve vzájemně konzistentních verzích; žádné unknown u podmínek potřebných pro vydání.
- [ ] Výchozí/prázdný celkový limit, technické meze, neatomické cizí zápisy a konečná životnost souhlasu jsou pravdivě popsané.
- [ ] Připravené testy, dokumentace a skutečně čerstvé reviewer scénáře.
- [ ] Review odesláno jen jednou; konektor následně dohledatelný a použitelný z jiného účtu.

Aktuální souhlas zahrnuje registraci, implementaci, nezbytnou Make konfiguraci/nasazení a Publish/odeslání po splnění bran; neomezovat jej zpět na pouhou přípravu. Publikační kontroly zůstávají povinné, další stejné schválení se nevyžaduje. Konkrétní placený závazek schválený není. Pokud se kompatibilita nepotvrdí, nezvyšovat scopes ani nepřidávat servisní klíč jako zkratku. Při návratu z pilotu odvolat jen připojení Make; zachovat ostatní klienty i jejich granty. Plán dokládá zadání, nikoli provedené externí kroky.
