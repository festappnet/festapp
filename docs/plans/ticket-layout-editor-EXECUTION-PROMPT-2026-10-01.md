# Implementuj vizuální editor rozložení vstupenky

Pracuj v `/Users/miakh/source/festapp`. Přečti `AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md` a celý autoritativní plán:

`docs/plans/ticket-layout-editor-plan-2026-10-01.md`

Implementuj plán se zachováním závislostí vln a verification `standard`. Výsledkem je editor v nastavení události pro wide i named: zoom/pan, přesouvání a změna velikosti QR i údajů, živé vykreslení všech prvků najednou, resize QR i písma úchyty, undo/redo, volitelný kontrolní PDF náhled a bezpečné uložení přes existující occasion save. Download a e-mail musí používat společný render kontrakt. Stávající vstupenky bez vlastního layoutu zachovají současnou podobu.

Dbej na kvalitu i jednoduchost: plochý seznam polí, přímé ovládání a stávající pdf-lib/occasion save. Bez systému skupin, obecného grafického frameworku či automatického PDF requestu po každém gestu. PDF spouští pouze tlačítko Náhled PDF, nikdy pohyb, otevření editoru ani potvrzení změn. Hlavním rozhraním je lokálně vykreslované živé plátno s pozadím, QR a texty; souřadnice vznikají přetažením, nikoli povinným zadáváním čísel. Použít validuje draft bez PDF; trvalé uložení validuje save RPC.

Postupuj rychle podle části „Efektivní realizace bez snížení kvality“: ověř změny od průzkumu, neopakuj jej celý. Co nejdříve dokonči skutečný průchod wide QR/kód od živého editoru přes uložení po PDF, potom rozšiř stejnou implementaci na celý rozsah. Pracuj v souvislých blocích, cílené kontroly spouštěj po nich a úspěšné neopakuj bez důvodu. Za gesta nedělej síťové requesty, decode obrázků ani přestavbu celého formuláře; zachovej okamžitý živý náhled. Nepřidávej frameworky či optimalizace pro hypotetické použití. Pokračuj bez zastavování na schválení jednotlivých vln až do splnění akceptačních scénářů.

Zachovej rozpracované cizí změny. Nezaváděj nový rezervační controller, obecný grafický editor ani druhou save cestu. Dodrž oddělení lokálního draftu a uloženého nastavení, ochranu před starými klienty, konflikty, autorizaci preview a bezpečný lifecycle obrázků. Dokonči ledger nahrazovaných cest; historické renderery jsou ponechány pouze na explicitně popsané hranici bez custom template.

Pokud implementační důkaz vyvrátí předpoklad plánu, nejdříve oprav příslušnou část plánu a poté pokračuj při zachování výsledku. Nenechávej placeholdery, spekulativní fallbacky ani dvojí výpočty geometrie presetů. Nespouštěj nezávislý agentní audit bez zadání. Ověřování prováděj cíleně po souvislých změnách podle plánu a repository gates.

Bez dalšího zadání neprováděj commit, push, produkční migrace, deployment ani tenant rollout. Při předání stručně uveď dokončené chování, změny kontraktu/volajících, výsledky testů a konkrétní zbývající provozní kroky. První průchozí wide QR scénář je mezikrok, nikoli dokončení celé práce.
