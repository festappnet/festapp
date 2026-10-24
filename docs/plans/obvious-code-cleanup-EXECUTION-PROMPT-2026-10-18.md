# Exekuce úklidu doloženého mrtvého kódu

Pracuj v `/Users/miakh/source/festapp`. Přečti platné `AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md` a celý autoritativní plán:

`docs/plans/obvious-code-cleanup-plan-2026-10-18.md`

Implementuj všechny tři vlny plánu: dva odpojené soubory, přesně vyjmenované nevolané Dart/JS členy, čtyři přímé závislosti a nadbytečné obaly dialogu doprovodů ve třech pohledech. Zpracování obrázků už bylo sjednoceno; starý kompresní helper neobnovuj. Pátý bod původního shrnutí, tedy velké backend/sync/storage/hosting přechody, i SQL cleanup jsou mimo rozsah.

Použij `verification: standard` kvůli auth/rights a sdílené docházce. Aktuální strom obsahuje rozsáhlé cizí změny. Ověř deklarace a skutečné volající těsně před mazáním, zachovej všechny ostatní změny a neobnovuj celé soubory z HEAD. Při změně faktů oprav plán s důkazem, nikoli rozsah potichu. Živého volajícího neodstraňuj jen kvůli dosažení počtu kandidátů. Žádné placeholdery, kompatibilní aliasy ani nový dialogový framework.

Dokonči souvislou změnu a pak proveď jednu závěrečnou dávku podle plánu: absence/diff kontrola, cílový `fvm dart analyze` vlastních změněných souborů, `./automation/test_client.sh` a `(cd web_client && npm test)`. Dependency resolution proveď podle vlny 2. Nepřidávej nové testy pro triviální mazání; rozšiř stávající behaviorální testy dialogu. Ověř skutečný discovery a nezaměňuj `_cases.dart` za celý validační vstup. Passing kontroly neopakuj bez změny jejich vstupů.

Neprováděj DB změny, produkční přístup, tenant rollout, build/release, commit ani push. Nepouštěj nezávislý review nebo subagenty. Hotovo znamená vyřešený celý mazací soupis, zachované aktivní kontrakty a úspěšnou vyžadovanou validaci. Na konci stručně shrň odstraněné položky, důvod případného ponechání, výsledky kontrol a přesný případný blocker.
