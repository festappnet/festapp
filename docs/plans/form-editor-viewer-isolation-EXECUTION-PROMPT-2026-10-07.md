# Zadání pro později autorizovanou implementaci společného formulářového modulu

Tento dokument sám implementaci neautorizuje. Po zadání implementace pracuj v čistém worktree Festappu a přečti celé autoritativní posouzení:

`docs/plans/form-editor-viewer-isolation-plan-2026-10-07.md`

Dodrž repository instructions a verification: standard. Nejprve zafixuj autoritativní main SHA a rozhodni podle již přijatých commitů, které HTML/grid packages jsou skutečně dostupné; nepřebírej celé nepublikované dirty worktree.

Cílem je společná definice a izolované běžné field behavior pro Flutter editor i viewer. Host dál vlastní commerce, persistence, rights, routing a SQL/Edge kontrakty. Zachovej JS interoperabilitu, pasivní editor preview, dosavadní veřejné preview chování, failed-save draft, explicitní deletions a server-side seat lifecycle.

Proveď vlny 1-3, vyhodnoť rozhodovací gate a výsledek zapiš do plánu. `form_engine` vytvářej jen při splnění gate; zamítnutí package s ověřeným interním modulem je přípustné dokončení. Při přijetí proveď úplnou vlnu 4: jediný vlastník definitions/rendering, odstranění přesunutých starých files a aliasů, package tests i integrační tests a povinné zapojení runneru. Nenechávej placeholder commerce callbacks ani druhý schema model.

Pokud evidence zvoleného base vyvrátí fakta v plánu, oprav plán a příslušnou vlnu; neobcházej gate a neměň obchodní chování. Nespouštěj nezávislý agent audit. Neprováděj commit/push/deploy, SQL migrace ani veřejnou publikaci bez samostatného zadání. Při předání uveď gate verdict, výsledné rozhraní/vlastníky, odstraněné kopie, relevantní ověření a zbývající omezení; nezaměň cache rozdíly za performance přínos.
