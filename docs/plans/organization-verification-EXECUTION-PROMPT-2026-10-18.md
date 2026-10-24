# Implementace ověření organizací

Přečti celý autoritativní plán `docs/plans/organization-verification-plan-2026-10-18.md` a aktuální `AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md`, `CONTRIBUTING.md`. Implementuj podle jeho vln s `verification: standard` pro oprávnění, migraci a veřejné kontrakty. Pracovní strom při plánování obsahoval mnoho jiných změn; zachovej je a ověř aktuální branch/base před zahájením.

Výsledek: každá veřejná forma ověřené Unit zobrazuje přímo název organizace s malou ověřovací UI ikonou; kliknutí otevře právní a kontaktní údaje. **Žádné „Prodejce:“ ani viditelný text „Ověřená organizace“ v patičce.** U neověřených se blok nezobrazuje. Vycházej z vizuálně zkontrolovaného principu Google Forms: tichý řádek pod formulářem na pozadí stránky, bez další karty.

Dotáhni nastavení právních údajů, žádost a ruční schvalování v administraci, serverovou autoritu a audit, bezpečnou veřejnou projekci, modely a shodné UI v JS/Flutteru včetně uzavřených a capability stavů. Právní identita patří Unit; tenant Organization určuje autoritu schvalovatele. Nové profile RPC nesmějí být závislé na výběru běžného Unit save transportu ani ukládat stav ověření do `units.data`.

Drž zúžení architektury z revize 2: dvě tabulky, pět externích RPC, jeden interní projekční helper. Každý skutečný stavový přechod zvýší revizi; žádné receipts, sync fan-out ani automatické opakování write po konfliktu. Timeout řeš načtením aktuálního profilu se zachováním draftu. Ve Flutteru read-only identita patří `FormBundle`, bez změny `FormDefinition`, editor draftu nebo `festapp_core`. Právní sekce má vlastní Form mimo běžné nastavení. JS detail použije nativní `<dialog>` bez refaktoru globálního modal systému.

Pro konkrétní UI/UX práci podle výslovného požadavku uživatele použij **Astra Medium (`gpt-6-astra`, reasoning effort `medium`)** a načti skilly `ui-ux-pro-max` a `ux-designer`. Předej přesný kontrakt a neprolínající se vlastnictví UI souborů; nepřidávej další agenty/audity. Dodrž konkrétní geometrii, stavy a přístupnost z plánu, nevymýšlej nový design systém.

Nezaváděj placeholdery, per-form override, automatické ověření z IČO ani paralelní kompatibilní implementaci. Změna schválených veřejných údajů ruší ověření; approve kontroluje přesnou revizi. Otestuj práva, veřejné úniky, souběh/retry, modely a zachování rozpracovaného formuláře. DB testy pouze proti výslovně zvolenému disposable lokálnímu backendu; browser izolovaný/headless dle repo pravidel.

Pokud se faktický předpoklad plánu ukáže nepravdivý, aktualizuj autoritativní plán podle konkrétního důkazu. Produktové předpoklady a chybějící autoritu nevydávej za ověřená fakta. Dokončení posuzuj podle checklistu plánu, včetně kompletního schvalovacího toku a obou klientů.

Tento prompt sám není pokyn k zahájení práce, commitu, pushi, produkční migraci nebo nasazení. Po výslovném zadání implementace proveď místní změny a cílené kontroly; produkční operace potřebují samostatné zadání. Nepřenášej změny ani buildy na jiné tenanty.
