V repozitáři `/Users/miakh/source/festapp` realizuj celý autoritativní plán
`docs/plans/blueprint-style-applicability-plan-2026-11-05.md`. Přečti ho celý
spolu s platnými AGENTS.md, CLAUDE.md a docs/architecture/ai_context.md.

Cíl: sjednotit dostupnost nastavení vzhledu podle typu/tvaru objektu a scope.
Zachovej existující resolver dědění, řídká přepsání, uložené plánky a hotovou
opravu značek sedadel. Použij malou interní politiku editoru; nepřidávej hierarchii
tříd, generický framework ani nová veřejná API. Smaž nahrazené duplicitní podmínky.

Pracuj v kanonickém balíčku, neupravuj vendored kopie. Začni soubory a testy
jmenovanými v plánu. Proveď ucelenou změnu, poté jednu cílenou validační dávku;
dodrž verification: low-risk a automatické zvýšení režimu podle AGENTS.md.
Distribuční gate spusť jednou na finálních vstupech a importuj ověřené archivy.
Neopakuj již dokončenou opravu ani úvodní průzkum celého repozitáře.

Pokud aktuální kód vyvrátí předpoklad plánu, uprav plán podle konkrétního důkazu.
Nezanechávej placeholdery ani paralelní rozhodovací cesty. Nepublikuj do registrů
a nenasazuj produkci bez samostatného zadání. Na konci stručně uveď změny,
provedené kontroly a případný zbývající blocker.
