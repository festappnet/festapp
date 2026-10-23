# Zásady návrhu a provozu MCP pro Festapp

Ověřeno 2026-10-23. Praktická pravidla pro další etapy
[kanonické administrace](../plans/admin-mcp-canonical-plan-2026-10-23.md).
Tento dokument je návrhová a ověřovací brána; samotný zápis pravidla neznamená,
že je již každý současný nástroj plní. Stav nasazení dokládá release receipt.

## Co je standard, zkušenost a naše rozhodnutí

- **Protokol:** stabilní revize `2026-07-28`. Server používá oficiální SDK
  `@modelcontextprotocol/server` 2.3.1 a Node adaptér 2.1.1. Moderní HTTP
  obsluhuje `createMcpHandler`, stdio `serveStdio`; samotné přejmenování
  importů by novou revizi nezapnulo. [Migrační dokumentace][sdk-modern]
- **Kompatibilita:** oficiální stateless legacy hranice SDK obsluhuje existující
  klienty nad stejným katalogem a doménovými operacemi. Není druhým vlastníkem
  doménové logiky. Legacy SDK 1.32.1 je pouze vývojová závislost skutečných
  integračních testů, není součástí produkčního obrazu. Hranici lze odstranit
  až po ukončení podpory klientů používajících handshake `initialize`.
- **Ověření:** skuteční moderní i legacy klienti musí projít HTTP/OAuth a stdio.
  Moderní test připíná `2026-07-28` a kontroluje skutečně vybranou protocol era.
  In-memory round-trip sám tuto revizi neprokazuje. Odpojení moderního HTTP
  ruší transportní exchange, nevrací již commitnutou SQL transakci. Obnova
  zápisu stále používá původní command ID a receipt. [Cancellation][cancel-new]
- **Veřejné zkušenosti:** Anthropic popisuje vývoj a evaluace nástrojů;
  GitHub dokumentuje řízení svého MCP serveru. Jde o zkušenosti a implementační
  vzory jejich týmů, ne univerzální garanci úspěšnosti či optimálního počtu tools.
- **Rozhodnutí Festapp:** společný SQL owner UI/MCP, atomické příkazy, scope
  tenant/unit/occasion a receipty. Tyto požadavky vycházejí z naší aplikace.
  MCP samo neurčuje počet SQL requestů ani negarantuje exactly-once doručení.

## 1. Nástroje podle úkonů, s jasným účinkem

**Zkušenost:** Anthropic doporučuje jednoznačné názvy, účelné schopnosti,
stručné relevantní výsledky a ověření popisů pomocí skutečných úloh. [Zdroj][effective]

**Pro Festapp:** 94 položek administrace není požadavek na 94 nástrojů.
Jeden doménový příkaz může pokrýt několik nastavení téhož agregátu. Vyhýbat se
současně nejasnému univerzálnímu `manage_everything` i jednomu nástroji pro každý
nízkoúrovňový SQL zápis. Agent nemá volat `execute_sql` ani libovolnou URL.

Blokovat místo, uvolnit dočasné držení a zrušit prodanou vstupenku mají odlišné
účinky a oprávnění: neskrýt je pod neurčité „uvolnit místo“. V popisu uvést,
jaké objekty příkaz změní, potřebné ID/verzi a význam jeho výsledku. Zachovat
existující namespace `festapp_*`; stejné úkony nepřejmenovávat bez důvodu.

**Důkaz:** pro každou přidanou schopnost existuje obyčejně formulovaná úloha,
jednoznačný výběr nástroje a pozorovatelný správný doménový výsledek.

## 2. Malý typovaný vstup a předvídatelný výstup

**Protokol:** tools mají vstupní schema; při deklarovaném output schema musí
strukturovaný výsledek odpovídat. Chyby samotné operace mohou být tool results
s `isError`. Anotace nejsou bezpečnostní hranice. [Zdroj][tools]

**Pro Festapp:** explicitní pole, omezené kolekce a povolené hodnoty. Rozlišit
vynechaný klíč, `null`, false a obnovení dědičnosti. Peníze a měny přenášet
bez ztráty přesnosti; časy s jasným pásmem. U blokace místo souřadnic přijmout
stabilní ID a původní revizi; SQL znovu ověří skutečný objekt a scope.

Vrátit uložené ID/verze, skutečně dotčené objekty, receipt a přesný stav účinku.
`queued` není doručený e-mail, `paid` není nově provedený card charge. Známý
výsledek nesmí vyžadovat několik dalších lookupů jen kvůli chybějícím ID.
Neposílat klientovi nové interní sloupce automaticky přes `SELECT *`.

**Důkaz:** skutečný SDK round-trip ověří schema, null/default chování a stabilní
ID pro další krok; příklad ve schématu souhlasí se skutečným handlerem.

## 3. Stručná data od databáze až k agentovi

**Zkušenost:** omezení výsledků a načítání potřebných definic může snižovat
zátěž kontextu. Článek o code execution popisuje také zpracování mezivýsledků
mimo model. [Zdroj][execution]

**Pro Festapp:** seznamy mají filtry, serverový keyset a bounded limit. Detail
objednávky se načítá cíleně; QR, secrety a formulářové klíče nejsou součástí
obecného seznamu. Souhrnný počet vypočítá kanonický report v SQL. Stránkování
catalogu nástrojů není totéž co stránkování produktových dat.

Naše [lokální baseline](../reports/admin-data-network-baseline-2026-10-23.json)
ukázala 1000 produktů z DB pro MCP stránku 50: omezený modelový výstup ještě
neřeší zbytečnou práci a přenos před modelem. Proto nejdřív opravit společný read
owner. Pro SQL join optimalizace ověřit počty a zabránit násobení vazeb.

S velkým exportem pracovat přes konkrétní autorizovaný resource/artifact
s expirací a kontrolou scope při čtení. Generický code execution server,
server-side JavaScript či SQL od modelu tímto zadáním nevzniká. Nejprve využít
běžné filtrování/agregaci a podporované schopnosti klienta.

**Důkaz:** srovnatelné before/after entity a bajty, případně SQL plán. Tokeny
měřit skutečným tokenizerem daného klienta/modelu, ne tvrzením podle znaků.

## 4. Jeden doménový owner a skutečná transakce

**Rozhodnutí Festapp:** UI, MCP, cron a worker musí používat stejné obchodní
validace a výpočty. Sdílení názvu wrapperu ani samotné snížení HTTP volání není
zárukou čisté architektury. Kompozice tří nezávisle potvrzených zápisů se
neprohlašuje za atomickou operaci.

Související DB záměr má jednu transakci a vlastněnou receipt hranici, vhodné
zámky a preconditions. Externí provider nebo asset Worker vyžaduje existující
outbox/recovery. Nevracet jejich potvrzení před skutečným přijetím účinku.
Nevytvářet kopie rules v Node ani klientská počítadla obchodní dostupnosti.

**Důkaz:** failure injection uprostřed příkazu, stejné výsledky UI/MCP,
dvouspojový souběh s checkoutem/cronem a jediný audit/sync/externí intent.

## 5. Retry, konflikt a cancellation jsou různé stavy

**Protokol:** cancellation a transportní odpojení se řídí vyjednanou verzí;
pro současný protokol odpojení samo neznamená žádost o zrušení. [Zdroj][transport]

**Rozhodnutí Festapp:** po timeoutu opakovat totožný command ID a payload.
Věcný konflikt revize znamená znovu načíst stav a získat rozhodnutí o změně.
Dočasná infrastruktura má bounded retry; trvale odmítnutý vstup se neopakuje.
Cancel/odpojení neznamená důkaz, že již potvrzená DB transakce byla vrácena.

Chyba má stabilní kód a krátký bezpečný postup nápravy: například reload kvůli
konfliktu nebo obnovení autorizace. Nevracet raw SQL traceback. Request ID slouží
k diagnostice, command ID k doménové idempotenci; neslučovat jejich účely.

**Důkaz:** ztracená odpověď po commitu, bounded opakování, konflikt, expirovaný
receipt a odpojení klienta mají samostatné očekávané výsledky.

## 6. Autorizace na serveru a oddělené identity

**Protokol:** HTTP autorizace používá discovery, určený resource/audience a
příslušné OAuth mechanismy. [Zdroj][auth] Přijetí tokenu určeného jinému
resource a jeho nepřezkoumané předání downstream je zakázaný vzor. [Zdroj][security]

**Pro Festapp:** zachovat oddělený delegovaný backend session, běžnou identitu,
MFA a aktuální typed predicates. OAuth grant i token musí povolovat operaci;
SQL současně ověří skutečnou tenant/unit/occasion vazbu, včetně replay.
Žádný nový scope automaticky nerozšíří starý grant. Filtrace `tools/list`
nenahrazuje kontrolu `tools/call` a doménového příkazu.

Hromadná správa rolí, banky a card-provider účinky si zachovají zvláštní pravidla
běžné aplikace. Nesmí vzniknout privilegovaná MCP zkratka přes service role.
Citlivé operace nevystavovat anonymně; správné transportní auth challenge ověřit
přes klienta. Chyby chybějící identity nezaměnit s věcným odmítnutím objektu.

**Důkaz:** matice identity/role/consent/token, cizí ID i tenant, změna role nebo
přesun akce a revokace během běžícího čtení. Každá vrstva fail closed.

## 7. Uživatelská kontrola podle skutečného účinku

**Protokol:** specifikace doporučuje možnost lidské kontroly. Hints z trusted
serveru mohou klientovi pomoci, ale nevynucují oprávnění. [Zdroj][tools]

**Rozhodnutí Festapp:** `readOnlyHint`, `destructiveHint`, `idempotentHint` a
`openWorldHint` odrážejí konkrétní účinek. Nastavení se nemá kopírovat bez
posouzení. Opakované potvrzování schváleného přesného příkazu není cílem.

Před kritickým zápisem ukázat konkrétní objekty, částky, rozšíření výběru na
celý nedělitelný celek a následné účinky. Běžné čtení nevyžaduje další dialog.
Náhled je skutečně bez zápisu a odesílání. Text šablony, jméno zákazníka či
popis produktu nikdy nemění instrukce agenta nebo schválený rozsah.

**Důkaz:** stejné schválené parametry dojdou do DB; žádné tiché zvětšení dávky,
příjemců nebo scope. Testovat prompt-injection texty jako obyčejná data.

## 8. Objevování nástrojů bez nepřehledného katalogu

**Veřejný vzor:** GitHub MCP používá toolsets a scope filtering, odděleně také
read-only nastavení. Dokládá to možnost organizovat větší katalog podle použití,
ne povinnost kopírovat jeho konfiguraci. [Zdroj][github]

**Pro Festapp:** ponechat jeden sdílený registr funkčních scopes a stálé názvy.
Seznam odpovídá oprávněním žádosti a podporovaným schopnostem. Udržovat
jednoznačné doménové skupiny a stabilní pořadí; při růstu měřit skutečný vliv
počtu/objemu definic na klienta. Nepřidávat vlastní search-tools framework ani
runtime enable/disable protokol bez potřeby a ověření kompatibility.

Současné textové a strukturované výsledky nelze slepě zkrátit odstraněním jedné
reprezentace: nejprve ověřit podporované hosty a jejich očekávání. Kompatibilita
je konkrétní spotřebitel a podmínka odstranění, nikoliv trvalý druhý engine.

**Důkaz:** skutečný SDK listTools/callTool pro různé scopes, prázdný katalog,
nový/odvolaný souhlas a odpovídající veřejná dokumentace schopností.

## 9. Vyhodnocovat celé uživatelské úlohy

**Zkušenost:** Anthropic doporučuje měřit, jak agent nástroje skutečně používá,
a podle neúspěšných scénářů zlepšovat návrh. [Zdroj][effective]

**Pro Festapp:** deterministické testy SQL/transportu doplnit malým scénářovým
balíkem. Úspěch je správný stav, nikoli jen zelená odpověď nebo použití přesné
předem předepsané sekvence tools. Začít těmito případy:

| Zadání | Pozorovatelná podmínka úspěchu |
| --- | --- |
| Kolik je přihlášených lidí? | Správné vymezení reportu, odlišené objednávky/vstupenky/lidé, žádný dump zákazníků. |
| Zablokujte tato tři místa. | Přesný scope a revize, známý případný celý výběrový celek; chráněné místo se tiše nevynechá. |
| Zrušte dočasnou rezervaci. | Uvolněn hold, žádná objednávka nebo blokace změněná omylem. |
| Změňte cenu od určeného času. | Jedna validní naplánovaná změna; zakoupené ceny zachované. |
| Upravte šablonu a ukažte náhled. | Uložen přesný override, shodné placeholders a dědičnost, žádný odeslaný e-mail. |
| Odpověď se ztratí po zápisu. | Stejný command vrátí původní účinek bez dalšího resource nebo zprávy. |
| Role je během úlohy odebrána. | Další zápis/replay je odmítnut, soukromý in-flight výsledek není vrácen neoprávněnému. |

Měřit výsledek, chybné výběry nástroje, requesty, payload a dobu úlohy.
Neoptimalizovat skóre pouze úpravou promptu pro známé příklady; ponechat několik
variant jako nezávislé kontrolní případy. Sbírat pozorovatelné tool calls a stav,
ne soukromé chain-of-thought. Reálné placené modelové evaluace ani externí služby
nespouštět automaticky bez příslušného zadání; nejprve využít existující testy.

## 10. Diagnostika a udržovatelná dokumentace

**Rozhodnutí Festapp:** log obsahuje operation ID, korelační ID, scope identifikátor,
latenci, velikost a výsledek, pokud je to potřebné pro konkrétní diagnostiku.
Nelogovat tokeny, refresh sessions, raw šablony ani zákaznické odpovědi.
Omezit paralelní běhy, velikost vstupu, request timeout a práci drahých exportů;
limity musí být doložené danou operací a testované, ne univerzálně odhadnuté.

Po změně schopností aktualizovat registry, katalog dokumentace, source evidence
a ověřit generátor. Zásady jsou závazným vodítkem pro plán, nejsou novou sadou
ručně duplikovaných runtime deklarací. Pokrytí celé administrace a stav
produkčního nasazení zůstávají vedené odděleně.

## Brána dokončení konkrétní schopnosti

- Úloha, správný nástroj a konkrétní účinek jsou jednoznačné.
- UI a MCP dosahují stejného doménového owneru; nahrazená cesta je odstraněná
  nebo má doloženého externího spotřebitele a exit condition.
- Skutečná SQL fixture prokáže práva, scope, revizi, replay a důležitý souběh.
- Výsledek odpovídá schématu, obsahuje potřebné IDs a nezveřejní nepotřebná data.
- Requesty a objem dat jsou přiměřené záměru; optimalizace má před/po důkaz.
- Schválení, annotations, chybový postup a dokumentace odpovídají skutečnosti.

## Zdroje a jejich role

Zdroje byly otevřeny 2026-10-23. Doporučení výše jsou stručná parafráze a vlastní
aplikace na Festapp, nikoliv přepis článků nebo tvrzení o osobní provozní zkušenosti.

- [MCP Tools 2026-07-28][tools] - aktuální kontrakt tools.
- [MCP Authorization 2026-07-28][auth] - HTTP OAuth a resource vazba.
- [MCP Security Best Practices][security] - konkrétní bezpečnostní antipatterny.
- [MCP SDK v2 migration][sdk-modern] - moderní entrypointy a legacy hranice.
- [MCP Cancellation 2026-07-28][cancel-new] - transportní rušení požadavku.
- [Writing effective tools for agents, Anthropic][effective] - zkušenosti týmu
  s návrhem nástrojů a evaluacemi, 2025-09-11.
- [Code execution with MCP, Anthropic][execution] - zkušenosti s velkými katalogy
  a mezivýsledky, 2025-11-04; nepřikazuje vlastní code execution server.
- [GitHub MCP server configuration][github] - konkrétní implementační vzor
  toolsets, read-only a scope filtering; nikoliv srovnávací benchmark.

[tools]: https://modelcontextprotocol.io/specification/2026-07-28/server/tools
[auth]: https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization
[security]: https://modelcontextprotocol.io/docs/2026-07-28/tutorials/security/security_best_practices
[transport]: https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2025-11-25/basic/transports.mdx
[cancel-new]: https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2026-07-28/basic/patterns/cancellation.mdx
[effective]: https://www.anthropic.com/research/writing-tools-for-agents
[execution]: https://www.anthropic.com/research/code-execution-with-mcp
[github]: https://github.com/github/github-mcp-server/blob/main/docs/server-configuration.md

[sdk-modern]: https://ts.sdk.modelcontextprotocol.io/v2/migration/support-2026-07-28
