# Implementace sjednocení platebního životního cyklu

Pracuj v `/Users/miakh/source/festapp`. Přečti `AGENTS.md`, `CLAUDE.md`,
`docs/architecture/ai_context.md` a celý autoritativní plán:

`docs/plans/payment-lifecycle-unification-plan-2026-10-29.md`

Použij `verification: standard`. Sjednoť rozhodování o platební způsobilosti
objednávek/vstupenek při bankovních změnách a editaci produktů. Zachovej
historické řádky, formáty snapshotů, počty událostí, oprávnění, receipt replay,
email fencing, ruční mark-paid bez odeslání a Stripe provider hranici.

V repozitáři jsou již tři zelené charakterizační SQL testy a jeden červený
regresní soubor se třemi známými chybami. Neodstraňuj ani nezměkčuj jeho
očekávání; doplň matici a souběh podle plánu, potom implementuj společného
ownera a scoped forward migraci. Existující migrace nepřepisuj. Dokončení
vyžaduje zelené fresh/upgrade testy i odstranění samostatného product-edit
výpočtu, nikoli další kompatibilní větev. Nezaváděj triggery ani nový ledger.

Implementaci organizuj podle části „Efektivní provedení a více agentů“.
Uživatel tuto delegaci výslovně povolil. Koordinátor vlastní aplikační SQL;
paralelně pověř agenta T SQL kontrakty a agenta C concurrency testy, s přesnými
nepřekrývajícími se cestami podle tabulky. Po zmrazení SQL předej dokončenému
agentovi T migrační balíček, nebo jej připrav sám. Nezakládej další auditní tým
a neopakuj původní průzkum. Agentům předej odkazy na plán a repo pravidla,
konkrétní výstupy a zákaz zásahu do cizích cest nebo dalšího delegování.

Jeden vlastník řídí lokální DB a ověřování. Přípravná DB z předchozí session
byla odstraněna. SQL runner, fault injection, concurrency harness a instalace
schématu nesmějí souběžně používat stejnou DB. Nezávislou přípravu paralelizuj,
závislé instalační/testovací kroky ponech v pořadí plánu. Bootstrapuj jednou
pro vývoj; fresh a upgrade migrační brány zachovej. Po zmrazení vstupů migraci
generuj z finálního SQL a neopakuj passing testy, dokud se jejich vstupy
nezmění. Pro tento SQL zásah nespouštěj klientské buildy bez konkrétního důvodu.

Postupuj podle závislostí vln plánu. Pokud skutečný kód vyvrátí jeho faktický
předpoklad, oprav plán s důkazem a přizpůsob dotčenou vlnu. Nezaměňuj očekávané
regresní selhání za chybu fixture. Nezasahuj do cizích rozpracovaných změn.

Nynější pověření neobsahuje produkční migraci/deploy, backfill, commit ani push.
Testy používej pouze na vlastní loopback disposable DB; neobnovuj cizí běžící
instance. Při předání uveď skutečné počty testů, zbývající selhání a přesný
stav neprovedené produkční části. Nezaměňuj dokončení delegovaných úloh za
úspěšnou integraci: všechny požadované brány musí projít nad finálními vstupy.
