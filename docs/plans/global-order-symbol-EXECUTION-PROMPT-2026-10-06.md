# Realizace: veřejný symbol objednávky

Po předání tohoto promptu jako úkolu implementuj níže uvedený plán a dokonči lokální ověření. Nezastavuj se u dalšího návrhu nebo žádosti o potvrzení již rozhodnutého formátu. Produkční operace se řídí samostatnou autoritou uvedenou níže.

Výchozí checkout s plánem je `/Users/miakh/source/festapp-order-ticket-change-overview-20261006`. Pracuj v repozitáři Festapp, nikoliv v Mendelio. Před úpravami ověř branch a pracovní změny; nepředpokládej, že checkout zůstal od vytvoření plánu nezměněný. Přečti jeho aktuální `CLAUDE.md`, `docs/architecture/ai_context.md`, `CONTRIBUTING.md` a pravidla tenant overlay/release. Zachovej cizí změny. Verification: standard; splň povinné repo gates. Nespouštěj subagenty bez výslovného zadání.

Autoritativní plán, který musíš přečíst celý:

`docs/plans/global-order-symbol-plan-2026-10-06.md`

Zaveď samostatný neměnný `eshop.orders.order_symbol`, globálně unikátní napříč organizacemi kanonické DB. Uživatelem schválený desetiznakový tvar `7G4K9M2R6A` používá stávající ticket abecedu. Podle výslovného požadavku uživatele musí být uložený i zobrazovaný symbol souvislý, bez pomlček a mezer, aby se dal celý označit dvojklikem a zkopírovat. Interní `orders.id`, všechny FK, příkazy, fronty, idempotence a platební reference zůstávají beze změny. Po dohledání podle symbolu používej dál interní ID.

Postupuj podle tabulky „Pracovní checklist pro realizátora“ (kroky 1-8), která konkretizuje vlny A-E. Pevné názvy, regex, SQL recept přidělení, generátor a testovací soubory jsou již rozhodnuté; nenavrhuj je znovu. Kontroly dávkuj podle pravidel rychlé realizace v plánu. Nejprve ověř aktuální runtime writer a facade `create_ticket_order_internal_v1` / `create_ticket_order_client_sync_v1`, grants a projekce. Generování patří do SQL, unikátnost do globálního constraintu a retry jen kolem konfliktu symbolu. Zahrň backfill, API/modely, všechny prezentační plochy, e-maily/custom šablony, staré pending a replay payloady, testy na více úrovních a ledger odstranění/ponechání.

Pracuj úsporně:

- Plán přečti jednou celý. Následně čti jen soubory potřebné pro aktuální krok; neprováděj nový celorepozitářový audit ani průzkum historie konverzace.
- První průzkum omez na runtime otázky vlny A a relevantní rozdíly od výchozí revize plánu. Skutečný rozpor oprav v plánu, potvrzená rozhodnutí znovu neřeš.
- Používej cílené `rg` a krátké výřezy; nezávislé čtecí příkazy dávkuj. Výstupy úspěšných kontrol shrň jedním řádkem, plné logy čti jen při selhání.
- Dokonči související implementační blok před ověřováním. Cílené testy seskup podle DB kontraktu a konzumentů; povinný plný repo gate spusť na finální změně. Úspěšné kontroly neopakuj bez relevantní změny.
- Používej existující modely, renderery a test runnery. Nevytvářej pomocnou infrastrukturu nebo nové abstrakce jen kvůli tomuto úkolu. Nevynechávej kvůli úspoře testy souběhu, idempotence, migrace a oprávnění.
- Nedostupnou produkční kontrolu přesně zaznamenej, nevydávej ji za provedenou a pokračuj v nezávislé lokální práci. Ptej se jen na chybějící zásadní rozhodnutí či autoritu, ne na rutinní implementační volby.

Nevytvářej paralelní business logiku, persistentní aplikační trigger, fallback symbolu na ID ani nový neautorizovaný lookup endpoint. Neměň původní barvy/design e-mailů. Již vydané symboly, PDF a ticket QR neregeneruj. Pokud se faktické předpoklady liší od aktuálního kódu či runtime, oprav nejprve autoritativní plán a související vlnu.

Dokončení znamená prokázané invarianty a testovací matici, nejen nový sloupec. Tento prompt autorizuje implementaci a lokální ověření; sám nepovoluje produkční migraci, odesílání e-mailů ani commit/push/deploy. Ty proveď pouze tehdy, pokud je autorizuje navazující zadání a dovolují aktuální repo pravidla. Dřívější souhlas s nasazením jiné e-mailové opravy není automatickou autoritou pro tuto změnu. Na konci stručně uveď hotový kontrakt, převod dat/consumerů, výsledky testů a přesný stav nasazení či zbývající blokaci.
