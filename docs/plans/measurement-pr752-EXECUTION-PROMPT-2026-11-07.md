# Dokončení PR #752 po architektonickém review

Přečti celý autoritativní plán:
`docs/plans/measurement-pr752-plan-2026-11-07.md`.

Nejprve načti AGENTS.md, CLAUDE.md, docs/architecture/ai_context.md a CONTRIBUTING.md. Režim standard. Pracuj v izolovaném worktree ze skutečného PR #752; zachovej cizí checkouty a vydání #749. Známý PR head je fa427b9835771b21ad73dc040c67bccb90d41b12, poslední zkoumaný main 99dc29ae7f664796f6d1a9916d360ca28535411e. Fetchni aktuální stav, prohlédni intervenující změny a integruj #749/#754 beze ztrát. Generované reference regeneruj.

Realizuj všech pět nálezů: jediný scope-bound choice owner pro setter/Klaro/modern source, úplný cleanup frame recordu, konzistentní nested consent update, protocol 3 + nový stabilní SQL fingerprint a prokázaná old/new kompatibilita, jednoznačný význam consent_required. Zachovej deklarovaný advanced/contact záměr PR i stávající SQL oprávnění, session ownership a checkout nezávislý na měření. Bez placeholderů, duplicitních autorit, trvalých protocol 2/3 větví, neplánovaných fallbacků a přepisování historických migrací.

Nejdříve dolož červené regrese; potom proveď koherentní změny, generování a cílené JS/SQL/browser ověření i dotčené canonical mirror lanes podle plánu. Browser deleguj Terra v izolované muted session, respektuj jeden Flutter task. Pnpm 11.24.0 a frozen lockfiles. Žádné skipy zastírající chybějící DB nebo browser. Neopakuj passing checks na nezměněných vstupech.

Pokud nová evidence vyvrátí předpoklad, oprav nejdříve autoritativní plán a dotčené vlny. Nezačínej další nezávislý audit/subagent review bez výslovného zadání.

Toto zadání pokrývá lokální implementaci. Bez samostatné autorizace neprováděj commit/push, GitHub komentáře/review/merge, produkční migrace, enablement ani deployment #752. Starší souhlas s vydáním #749 je jiný scope. Na konci stručně uveď worktree, změny, přesné checks, uzavření deletion ledgeru a skutečně nedokončené kroky. Za hotovou neoznačuj implementaci s chybějícím požadovaným důkazem.
