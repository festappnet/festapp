# Implementace přetažení obrázků do editorů

Pracuj v `/Users/miakh/source/festapp`. Přečti celé `docs/plans/editor-image-drop-plan-2026-10-20.md`, které je autoritativním plánem, a platná `AGENTS.md`, `CLAUDE.md`, `docs/architecture/ai_context.md`.

Implementuj sdílený interní obal pro externí file drop přes celé tělo editoru vstupenek a Blueprint editoru. Importuj do existujícího podkladu přes stejné hostitelské operace jako picker. SVG podporuj podle plánu pouze v Blueprintu. Zachovej jediného příjemce dropu, oprávnění, blokování importu/modálů/neaktivních tabů, prototype omezení a draft/save/discard. Chyba nesmí odstranit stávající podklad.

Ověř cílenými standardními kontrolami uvedenými v plánu, s nejvýše jedním Flutter taskem na workstation a testy `--concurrency=1`. Neprováděj nesouvisející úpravy v silně rozpracovaném workspace. Nevytvářej placeholdery, alternativní upload cesty ani závislost na novém lokálním API `../venue_seat_picker`. Pokud aktuální evidence zneplatní předpoklad, nejprve uprav autoritativní plán.

Hotovo je implementované a cíleně ověřené chování obou editorů včetně chyb a vnořených drop oblastí. Závěr má uvést změny, důkaz ověření a případné neověřené platformní chování. Commit/push, produkční operace a rozšíření SVG podpory vstupenek vyžadují samostatné zadání.
