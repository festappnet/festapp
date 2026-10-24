# Proveď plán zmenšení repozitáře Festapp

Pracuj v `/Users/miakh/source/festapp`. Přečti AGENTS.md, CLAUDE.md, docs/architecture/ai_context.md a celý autoritativní plán:

`docs/plans/repository-size-cleanup-plan-2026-10-21.md`

Verifikace: standard. Cílem je odstranit nepotřebné pracovní výstupy a konsolidovat SQL instalaci bez změny aplikačního schématu, datových kontraktů, podporovaných upgrade cest nebo chování map. MapLibre overrides nyní zachovej; publikované balíčky při průzkumu potřebné patche nepokrývaly. Fonty a aktivní JSON inventáře ponech.

Postupuj po vlnách plánu. Zachovej souběžné necommitované změny. Před smazáním historického SQL vytvoř obnovitelný manifest a kit včetně nesledovaných souborů, prokaž baseline/seed parity, bezpečný migration ledger a podporovaný upgrade. Nedoložený provozní stav neopravňuj předpokladem. Při neplatné premise aktualizuj plán s důkazy a vymez přesně nedokončenou část.

Nevytvářej další paralelní bootstrap, nezdokumentované fallbacky ani fork závislostí. Neprováděj plošný git clean, přepis Git historie, commit/push, produkční SQL nebo deployment bez samostatné autorizace. Nezahajuj nezávislý subagent audit. Flutter spouštěj pouze při skutečné změně klientského kódu a respektuj jedinou úlohu na workstation a concurrency=1.

Dokončení vyžaduje uzavřený mazací soupis, platné odkazy, zachování potřebné evidence, úspěšné cílené ověření a skutečné metriky před/po. Úsporu nepředstírej přesunem do jiné části stejného repozitáře ani minifikací JSON. Reportuj odstraněné skupiny, výsledek SQL parity, záměrně ponechané závislosti a přesnou zbývající podmínku, pokud některá kontrakce nemohla bezpečně proběhnout.
