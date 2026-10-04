# Implementuj opakovaně použitelnou nápovědu sloupců DataGridu

Pracuj v `/Users/miakh/source/festapp`. Přečti příslušné `AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md` a celý autoritativní plán:

`docs/plans/data-grid-column-help-plan-2026-10-02.md`

Implementuj plán v plném rozsahu. Cílem je volitelná mapa `columnHelp` na `SingleDataGridController` a společná hlavička s informační ikonou: hover, kliknutí/tap i klávesnice, použitelná v úzkých sloupcích. Bez neprázdného vysvětlení zůstane původní hlavička. Zachovej řazení, filtrování, menu, resize, přesun sloupců, checkboxy i CSV. Napojení musí přežít rebuild a `forceReload`, který může vytvořit nové sloupce.

Dodrž rozhodnutý kontrakt, implementační kroky, testovací matici a definici dokončení. Přidej stručný README s použitím a skutečné widgetové integrační testy. Produkční texty konkrétních sloupců nejsou zadány; nevymýšlej plošné nápovědy. Nevytvářej paralelní implementace, spekulativní fallbacky ani placeholdery. Neměň závislosti nebo `.pub-cache`.

Verification: standard pro tuto změnu sdíleného chování. Proveď cílenou analýzu a testy uvedené v plánu po koherentní dávce změn. Nezahajuj nezávislý audit ani subagenty. Pokud aktuální kód vyvrátí faktický předpoklad plánu, oprav jej s konkrétní evidencí a přizpůsob implementaci při zachování požadovaného výsledku.

Zachovej všechny nesouvisející rozpracované změny. Bez samostatného pokynu necommituj, nepushuj, nenasazuj ani neslučuj tenant větve. Na konci stručně uveď nové API, dotčené soubory, výsledek ověření a případný přesný zbývající problém.
