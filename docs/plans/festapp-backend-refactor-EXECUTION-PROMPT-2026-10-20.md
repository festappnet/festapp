# Exekuční prompt: kanonický backendový refaktor Festapp

Pracuj v `/Users/miakh/source/festapp`. Implementuj backendový refaktor podle
níže uvedeného plánu a dokonči jeho lokálně ověřitelný rozsah. Nezůstávej
u dalšího návrhu nebo seznamu doporučení.

Nejdřív přečti `AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md`
a celý autoritativní plán:

- [Kanonické operace](festapp-canonical-operations-plan-2026-10-20.md), zejména 1A-1I, kontrakty, deletion ledger a ověřovací postupy.
- [Ledger CW01-CW24](../architecture/operations/remaining-write-cutover-ledger-2026-10-20.md).
- [Rozbor sekvencí](../architecture/operations/sequence-review-2026-10-20.md).
- [Vstupenkové operace](festapp-ticketing-mcp-plan-2026-10-20.md), zejména konkrétní backendové slabiny a podmínky zápisů.

Tento prompt vybírá backendový rozsah uvedených plánů. Neimplementuj nyní
CLI, MCP, hosted OAuth, nový editor ani vizuální preview. Z jejich plánu proveď
jen potřebné doménové kontrakty, oprávnění a minimální verzované čtecí projekce.
Úpravy současných Dart/JS/Edge volajících patří do rozsahu, pokud jsou nutné
pro přechod na jedinou kanonickou operaci nebo odstranění její staré cesty.
Pořadí E0-E6 z celkového plánu zde nepřikazuje začít MCP adaptérem.

## Výsledek

Každá vybraná operace má jednoho vlastníka obchodních pravidel a explicitní
transakční hranici, oprávnění, vedlejší účinky, souběh a opakování příkazu.
Aktuální klienti používají tohoto vlastníka. Nahrazené implementace a fallbacky
jsou odstraněné. Nutné rozhraní pro podporovaného staršího klienta smí zůstat
jen jako tenký adaptér s konkrétním spotřebitelem a podmínkou odstranění.
Historické migrace zůstávají zachované.

## Postup

1. Proveď cílené 1A: potvrď efektivní definice, volající, oprávnění a závislosti
   jen pro měněnou rodinu. Použij existující inventář, neopakuj celkový audit.
   Zachovej nesouvisející změny v pracovním stromu.
2. Dokonči 1B: jeden autor každé vybrané SQL signatury, sjednocení duplicit
   mazání objednávky a Auth definic, bezpečná deterministická forward assembly.
   Definice potřebné pro další rodinu vytahuj postupně; nepřepisuj aplikovanou
   historii a neopakuj historickou adopci dat nebo reset rozpočtů Auth.
3. Oprav společný životní cyklus příkazu z 1D/1I: dodané stabilní command ID
   transport nepřepíše; identita zahrnuje backend, aktéra, operaci, scope,
   normalizovaný obsah a původní očekávané verze. Pending intent ukládej před
   odesláním a maž atomicky jen při shodě přesného ID a principal binding.
   Zachovej nevyřešené platební intenty, receipt tombstones a autorizované
   obnovení výsledku i po smazání zdrojového řádku.
4. Dokonči backendové 1I po rodinách: nejdřív úzké ukládání vzhledu vstupenky
   přes existující occasion command, potom formuláře/plánky. Zachovej původní
   editor baseline, užší oprávnění layoutu a nesouvisející occasion features.
   U plánků oprav částečné změny před pozdním JSON odmítnutím, příslušnost ID
   sedadel, únik hold secrets a souběh s rezervací/prodejem. Doménové odmítnutí
   nesmí ponechat změny; rejected receipt lze dokončit mimo rollback blok.
   Formuláře zachovávají explicitní seznamy mazání, význam vynechaných hodnot,
   ochranu použitých polí/produktů a pravidla kapacity/waitlistu. Vytvoření
   formuláře pro authoring musí zajistit zavřený stav atomicky.
5. Dokonči 1E a související CW: atomické uložení produktu s inventory contexts,
   aditivní přidání členů skupiny a vytvoření cenové vlny s cílovým nastavením.
   Oprav sdílené inventory vlastníky a přesměruj aktuální volající.
6. Dokonči 1C/1D: kanonické storno se záměrem automatického oznámení v jedné
   transakci, bez následného automatického emailového volání klienta. Sjednoť
   single/bulk/legacy deduplikaci. Zachovej manuální resend a volitelné smazání
   externí faktury jako samostatné explicitní úmysly. Ověř replay mazání.
7. Uzavři zbývající 1F/CW01-CW24 a rozhodnutí 1G v ucelených doménových změnách.
   Pool a cleaning-report command nyní volají staré veřejné writery: nejdřív
   vyčleň interního vlastníka, teprve pak deleguj facade, jinak vznikne rekurze.
   Zachovej rozdíl unit/occasion scope, samostatné uživatelské akce a existující
   recovery externích workflow. Několik awaitů samo o sobě není chyba.
8. Uzavři 1H: aktualizuj inventář, katalog, removal ledger a stav každé rodiny.
   Prokaž chování i nedosažitelnost odstraněných cest. Neoznačuj celkový refaktor
   za dokončený, pokud zůstává nevysvětlený CW záznam nebo konkurenční writer.

Pořadí uvnitř kroků uprav podle skutečných sdílených závislostí. Dokončuj vždy
celou rodinu: kontrakt, kanonický writer, migrace, přesun volajících, odstranění
nahrazené cesty a ověření. Nesjednocuj odlišné doménové úmysly do obří transakce.

## Neporušitelné podmínky

- Použij existující mutation receipts, aggregate versions a email queue.
  Nevytvářej obecný dispatcher, další API server, druhý business engine,
  paralelní idempotency store ani aplikační triggery.
- SQL funkce patří do `public`; `SECURITY DEFINER` má explicitní kontroly
  oprávnění a `search_path = public, extensions`. Zachovej admission a lock order.
- Verze se porovnává s původním stavem editora pod zámkem. Čerstvé načtení před
  zápisem původní baseline nenahrazuje. Všichni konkurenční writeři musí verzi
  správně posouvat. Pro staré klienty bez baseline dolož upgrade/fence politiku;
  bez ní neprohlašuj rodinu za připravenou pro bezpečné MCP zápisy.
- Po timeoutu neopakuj nejasný výsledek s novým command ID. Neměň platební,
  refund ani fakturační politiku a neposílej skutečné emaily při testování.
- Při rozporu se zdrojovým kódem uprav plán s konkrétním důkazem. Nezakládej
  nový fallback, nezahazuj nutnou kompatibilitu a nezvětšuj scope na celý backend.

## Ověření a dokončení

Použij `verification: standard`, cílené repository lanes a izolovaný lokální
backend. Po ucelené změně spusť jednu relevantní dávku kontrol na finálních
vstupech. Zachovej platné výsledky; opakuj jen kontroly zasažené další změnou.
Existující fixtures rozšiřuj postupně. Neprováděj celý Flutter build kvůli SQL.
Dodrž jeden Flutter task na workstation a testy s `--concurrency=1`.

Prokaž zejména atomické odmítnutí, cizí scope/ID, oprávnění, stale-version
konflikty, souběh rezervace a změny plánku, replay po ztrátě odpovědi, opožděné
mazání intentu, souběžné storno s jediným emailovým záměrem a kontinuitu receiptů.
Zkontroluj skutečné zařazení testů do discovery. Ověř fresh baseline i forward
migraci podle dotčené assembly; produkce není testovací databáze.

Neaplikuj produkční SQL, nepracuj s živými tenant daty, nenasazuj, nekonfiguruj
externí konektory, necommituj ani nepushuj bez samostatného zadání. Nespouštěj
nezávislý subagent audit. Nevyřešená produkční kompatibilita má přesný rollout
gate; ostatní lokálně proveditelnou práci dokonči.

Na konci stručně uveď kanonické vlastníky, přesunuté volající, odstraněné cesty,
ponechané externí adaptéry s podmínkami odstranění, skutečně spuštěné kontroly
a zbývající rollout kroky. Rozliš lokální dokončení refaktoru, připravenost každé
rodiny pro MCP a dosud neprovedenou produkční aktivaci.
