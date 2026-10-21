# Implementace embedded objednávkového formuláře

Pracuj v `/Users/miakh/source/festapp`. Přečti AGENTS.md, CLAUDE.md,
docs/architecture/ai_context.md a celý autoritativní plán:

`docs/archive/plans/embedded-checkout-plan-2026-10-20.md`

Cílem je kopírovatelný iframe pro uložený veřejný formulář, samostatně
i s pomocným skriptem pro automatickou výšku. Zachovej jeden objednávkový
backend a stávající commandId/clientId, kapacity, rezervace a platební QR.
Verification: standard, protože se mění veřejný protokol a objednávkový tok.

Implementuj vlny v pořadí plánu. Zachovej existující rozpracované změny.
Nezaváděj druhý checkout, objednávkové RPC, OAuth v embedu, nové DB nastavení
ani automatický retry/reload nákupu. Hostitelskému webu nesděluj osobní data
nebo capability. Dokončení zahrnuje oba integrační způsoby, bezpečný handshake,
mobilní dialogy a plánek, kopírování pouze savedLink, cílené testy a cross-site
syntetický průchod. Přesně vykazuj omezení browser coverage a storage recovery.

Pokud aktuální zdroj vyvrací premisu plánu, aktualizuj plán s konkrétním důkazem
a uprav související vlnu. Nenechávej placeholdery, duplicitní adaptéry ani
neplánované kompatibilní cesty. Neprováděj nezávislý subagent audit.
Dodrž globální limit jedné Flutter úlohy a --concurrency=1 pro Flutter testy.

Tento prompt je zadání pro následně autorizovanou implementaci, nikoliv
samostatné povolení ji zahájit. Produkční operace, commit a push vyžadují
samostatné zadání. Nasazení případně jen na vybraný tenant, lokálně přes
automation/deploy_direct.sh, s delegací dle AGENTS.md.

Při předání stručně uveď výsledek, provedené kontroly, zbytková omezení
a odděleně stav lokální implementace a produkčního nasazení.
