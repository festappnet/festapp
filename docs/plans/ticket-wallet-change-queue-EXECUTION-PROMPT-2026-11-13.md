# Exekuce fronty změn Wallet vstupenek

Pracuj v `/Users/miakh/source/festapp`. Přečti příslušné `AGENTS.md`, `CLAUDE.md`
a `docs/architecture/ai_context.md`. Použij verification: standard.
Respektuj cizí rozpracované změny a vytvoř čistý worktree z aktuálního main.

Přečti celý autoritativní plán a implementuj jej ve stanoveném pořadí:

`docs/plans/ticket-wallet-change-queue-plan-2026-11-13.md`

Cílem je trvalá verzovaná fronta, do níž kanonické změny vstupenky atomicky
zařazují aktualizaci existující Google Wallet karty. Změna během běžící práce
nesmí být ztracená, Google třída i objekt musí mít jediného zapisovatele a
existující identity, QR, capability a admission pravidla musí zůstat zachované.
Převezmi spolehlivost e-mailové fronty, nepoužívej její tabulky pro Wallet práci.

Nejprve doplň konkrétní producer -> enqueue -> test mapu a pořadí zámků.
Potom implementuj expanzi, producenty, consumer, backfill, opravnou kontrolu,
metriky a kontrakci starého plánování. Dokončení vyžaduje také odstranění položek
z deletion ledgeru, ne pouze funkční novou cestu vedle staré. Nepřidávej
aplikační triggery, neplánované fallbacky, V1/V2 aliasy ani obecný job framework.

Implementuj pouze Google. Apple zohledni v hranicích doménového požadavku a
odděleného provider stavu; nepřidávej nefunkční Apple adaptér, tlačítko či APNs.
Původní PR #838 je samostatná změna automatického pokračování z e-mailu. Obnov
jeho stav; pokud už je na main, použij jej, jinak ho neduplikuj ani neamenduj.
Souhlas s admin merge PR #836 neopravňuje admin merge PR #838 nebo nového PR.

Ověř chování testy skutečných příkazových funkcí, souběhů a externích timeoutů
a proveď kapacitní měření bez produkčních fixtures či hromadných Google zápisů.
Spusť postižené canonical mirror lanes podle aktuálního DAG a plánu. Dodrž
pnpm 11.24.0, frozen lockfiles a jediný Flutter task s testy `--concurrency=1`.
Passing kontroly opakuj pouze při změně jejich vstupů nebo novém problému.

Pokud současný kód vyvrátí předpoklad plánu, aktualizuj tento autoritativní plán
konkrétním důkazem a uprav příslušnou vlnu; neměň potichu cíl. Nevyžaduj uživatele
pro rutinní implementační volby, ale nepředstírej chybějící produkční oprávnění.

Tento prompt autorizuje lokální implementaci a ověření. Bez samostatného souhlasu
necommituj, nepushuj, nemerguj, neprováděj produkční migrace, restart ani deploy.
Produkční postup připrav konkrétně a označ jej jako neprovedený; pokud je později
výslovně autorizován, zachovej všechny release gates a rozsah vstupenky.online.

Při předání stručně uveď výsledný kontrakt, pokryté producenty, odstraněnou starou
cestu, výsledky testů a kapacity a přesné případné blokery/neprovedené kroky.
